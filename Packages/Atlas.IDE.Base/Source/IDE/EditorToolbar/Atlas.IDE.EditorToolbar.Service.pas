unit Atlas.IDE.EditorToolbar.Service;

// Atlas-Editorleiste (#1101) in der IDE:
// - Über dem Editor jedes Editorfensters steht eine Leiste
//   (TAtlasEditorToolbar) mit den Befehlen aus editor.toolbar.items; Fenster,
//   die später aufgehen, bekommen sie beim nächsten Takt. Position nach
//   editor.toolbar.position: unter bzw. über der Brotkrumenleiste (alTop im
//   Eltern-Steuerelement des Editors) oder rechts in der Brotkrumenzeile
//   (alRight in TAtlasBreadcrumbBar); ohne Brotkrumen steht sie oben.
// - Ein Zeitgeber (150 ms) setzt für die aktive Ansicht den hervorgehobenen
//   Abschnitt, gesperrte Abschnittsknöpfe (Datei ohne interface/
//   implementation), den Punkt an „Probleme“ (Befunde der Datei), „Vor“ nur
//   mit Vorwärts-Verlauf und den Rücksprung-Knopf „↩ 214“. Abschnitte liest
//   TAtlasSectionScanner direkt aus dem Editortext (ohne Server).
// - Abschnittssprünge (GotoInterface, GotoImplementation, GotoUses,
//   GotoInitialization) setzen die Zielzeile ins obere Drittel und merken die
//   Ausgangszeile (TAtlasReturnPoints, erster Ausgangspunkt bleibt); Zeilen
//   darüber verschieben sie, Rückkehr auf die Zeile (Knopf, Alt+← oder
//   von Hand) erledigt sie. Die Befehle arbeiten auch ohne Leiste (Palette,
//   Menü, Tasten).
// - FindMethod: Atlas-Popup mit den Routinen der Datei aus der Gliederung
//   (TAtlasIdeOutlineCache), Enter zur Implementierung, Umschalt+Enter zur
//   Deklaration.
// - Customize: Dialog „Leiste anpassen“; übernimmt Belegung, Text neben den
//   Symbolen und Position in die Einstellungen.
// - Alles, was anderen Features gehört (Palette, Befunde, Verlauf,
//   Meldungsansicht), kommt über THooks von der Composition; so entsteht kein
//   Feature-Zyklus (A-09).
// - Eigene Sicherung TAtlasFeature.EditorToolbar: Löst sie aus, verschwinden
//   die Leisten, bis „Abgeschaltete Funktionen einschalten“.
// - Anlegen je Editorfenster, Wächter, Freigabe nach der Sperre durch die
//   IDE, Protokoll des Sperrenden und Abbau übernimmt TAtlasEditorBarHost
//   (#1248); hier stehen nur Einordnen (Place) und Inhalt.
// - editor.toolbar aus: Leisten weg, der Editor bekommt seine Höhe zurück;
//   Position, Text neben den Symbolen und Belegung gelten ohne Neustart.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Commands.Palette,
  Atlas.Core.EditorToolbar.Sections,
  Atlas.UI.EditorToolbar.Customize;

type
  TAtlasIdeEditorToolbar = class
  public type
    THooks = record
      /// <summary>Sichtbare Atlas-Befehle der Palette (mit Taste).</summary>
      Commands: TFunc<TArray<TAtlasCommand>>;
      /// <summary>Atlas-Befehl ausführen wie aus der Palette (Verlauf, Tipps).</summary>
      Execute: TProc<string>;
      /// <summary>Befehlspalette öffnen.</summary>
      ShowPalette: TProc;
      /// <summary>Taste eines Befehls als Text ('' ohne).</summary>
      ShortCutOf: TFunc<string, string>;
      /// <summary>Zahl der Befunde in der Datei.</summary>
      FindingsOf: TFunc<string, Integer>;
      CanGoBack: TFunc<Boolean>;
      CanGoForward: TFunc<Boolean>;
      /// <summary>Zeile in der Meldungsansicht.</summary>
      Message: TProc<string>;
    end;
  private class var
    FState: TObject;
    FHooks: THooks;
    class procedure Say(const AText: string); static;
  public
    class procedure Install(const AHooks: THooks); static;
    class procedure Uninstall; static;
    class procedure ApplySettings; static;
    class procedure ThemeChanged; static;
    /// <summary>Ist die Leiste eingeschaltet?</summary>
    class function Enabled: Boolean; static;
    class procedure GoToSection(ATarget: TAtlasSectionTarget); static;
    class procedure GotoInterface; static;
    class procedure GotoImplementation; static;
    class procedure GotoUses; static;
    class procedure GotoInitialization; static;
    /// <summary>Zurück zum Ausgangspunkt des letzten Abschnittssprungs in der aktiven Datei.</summary>
    class procedure ReturnFromSection; static;
    class procedure FindMethod; static;
    class procedure Customize; static;
    /// <summary>Befehle, die in die Leiste können: Atlas-Befehle der Palette und die Palette selbst.</summary>
    class function CommandInfos: TArray<TAtlasToolbarCommandInfo>; static;
  end;

implementation

uses
  Vcl.Forms,
  Atlas.Core.Outline.Breadcrumbs,
  Winapi.Windows,
  System.Classes,
  System.Math,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Style.Palette,
  Atlas.Core.Outline.Model,
  Atlas.Core.Settings.ToolbarItems,
  Atlas.Core.EditorToolbar.Icons,
  Atlas.Core.EditorToolbar.ReturnPoint,
  Atlas.UI.Strings,
  Atlas.UI.Outline.Breadcrumbs,
  Atlas.UI.EditorToolbar.Bar,
  Atlas.IDE.Foundation.EditorBarHost,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Outline.Cache,
  Atlas.IDE.EditorToolbar.FindMethod;

const
  TickMs = 150;
  /// <summary>Befehlsliste und offene Dateien nur alle so viele Takte neu lesen (etwa 2 s).</summary>
  SlowTicks = 13;
  PositionAbove = 'aboveBreadcrumbs';
  PositionInline = 'inBreadcrumbs';
  AtlasPrefix = 'Atlas: ';
  ProblemsId = 'Atlas.ProblemsWindow';
  BackId = 'Atlas.NavBack';
  ForwardId = 'Atlas.NavForward';

type
  TToolbarState = class
  private
    FTimer: TTimer;
    FHost: TAtlasEditorBarHost;
    FPoints: TAtlasReturnPoints;
    FCommands: TArray<TAtlasCommand>;
    FSlow: Integer;
    /// <summary>Takte seit dem letzten Lauf ohne aktiven Editor.</summary>
    FIdle: Integer;
    // Abschnitte der zuletzt gelesenen Datei.
    FSectionsFile: string;
    FSectionsVersion: Cardinal;
    FSections: TAtlasUnitSections;
    // Zeilenzahl je Datei für das Verschieben der Rücksprungpunkte.
    FLineCounts: TDictionary<string, Integer>;
    FLastFile: string;
    FLastLine: Integer;
    procedure Tick(Sender: TObject);
    function ToolbarOn: Boolean;
    function CrumbsOf(AHost: TWinControl): TAtlasBreadcrumbBar;
    function CreateBar: TAtlasEditorToolbar;
    procedure Place(ABar: TAtlasEditorToolbar; AHost: TWinControl);
    procedure Track(const AView: IOTAEditView; const AFileName: string; ALine: Integer);
    procedure UpdateBar(ABar: TAtlasEditorToolbar; const AFileName: string;
      ALine, ACharacter: Integer);
    function ButtonsFor(const AFileName: string; ALine, ACharacter: Integer): TArray<TAtlasToolbarButton>;
    function CaptionOf(const AId: string; out ACaption: string): Boolean;
    procedure MarkSection(var AButton: TAtlasToolbarButton; ATarget: TAtlasSectionTarget;
      ALine, ACharacter: Integer; ASection: TAtlasCodeSection);
    procedure Step(AOn: Boolean);
    procedure SlowRefresh;
    function CommandOf(const AId: string; out ACommand: TAtlasCommand): Boolean;
    procedure ForgetClosedFiles;
    procedure Later(const AAction: TProc);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Nach geänderten Einstellungen: Leisten neu anlegen (Position, Belegung), Befehle neu lesen.</summary>
    procedure Reset;
    procedure ApplyTheme;
    /// <summary>Abschnitte der Datei aus dem aktuellen Editortext.</summary>
    function SectionsOf(const AView: IOTAEditView; out AFileName: string): TAtlasUnitSections;
    property Points: TAtlasReturnPoints read FPoints;
  end;

function State: TToolbarState;
begin
  Result := TToolbarState(TAtlasIdeEditorToolbar.FState);
end;

function PlainCaption(const ACaption: string): string;
begin
  Result := ACaption;
  if Result.StartsWith(AtlasPrefix) then
  begin
    Result := Copy(Result, Length(AtlasPrefix) + 1, MaxInt);
  end;
end;

function BarColors: TAtlasColors;
begin
  if TAtlasIdeSettings.Current.BreadcrumbsIdeColors then
  begin
    Result := TAtlasIdeStyle.ChromeColors;
  end
  else
  begin
    Result := TAtlasIdeStyle.Colors;
  end;
end;

function SectionCaption(ATarget: TAtlasSectionTarget): string;
begin
  case ATarget of
    TAtlasSectionTarget.InterfacePart:
      Result := TAtlasStrings.Text(TAtlasTextId.GotoInterfaceCommand);
    TAtlasSectionTarget.ImplementationPart:
      Result := TAtlasStrings.Text(TAtlasTextId.GotoImplementationCommand);
    TAtlasSectionTarget.UsesClause:
      Result := TAtlasStrings.Text(TAtlasTextId.GotoUsesCommand);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.GotoInitializationCommand);
  end;
end;

/// <summary>Sprungziel eines Abschnittsbefehls; False für andere Kennungen.</summary>
function SectionTargetOf(const AId: string; out ATarget: TAtlasSectionTarget): Boolean;
begin
  Result := True;
  if SameText(AId, TAtlasToolbarItems.GotoInterface) then
  begin
    ATarget := TAtlasSectionTarget.InterfacePart;
  end
  else if SameText(AId, TAtlasToolbarItems.GotoImplementation) then
  begin
    ATarget := TAtlasSectionTarget.ImplementationPart;
  end
  else if SameText(AId, TAtlasToolbarItems.GotoUses) then
  begin
    ATarget := TAtlasSectionTarget.UsesClause;
  end
  else if SameText(AId, TAtlasToolbarItems.GotoInitialization) then
  begin
    ATarget := TAtlasSectionTarget.Initialization_;
  end
  else
  begin
    Result := False;
  end;
end;

/// <summary>Hervorgehoben, wenn der Caret in diesem Abschnitt steht (finalization zählt zu initialization).</summary>
function SectionPressed(ATarget: TAtlasSectionTarget; ASection: TAtlasCodeSection): Boolean;
begin
  case ATarget of
    TAtlasSectionTarget.InterfacePart:
      Result := ASection = TAtlasCodeSection.InterfacePart;
    TAtlasSectionTarget.ImplementationPart:
      Result := ASection = TAtlasCodeSection.ImplementationPart;
    TAtlasSectionTarget.UsesClause:
      Result := ASection = TAtlasCodeSection.UsesClause;
  else
    Result := (ASection = TAtlasCodeSection.Initialization_) or (ASection = TAtlasCodeSection.Finalization_);
  end;
end;

/// <summary>Tooltip: Name und, falls belegt, die Taste.</summary>
function KeyHint(const AId, ACaption: string): string;
var
  mKey: string;
begin
  Result := ACaption;
  mKey := '';
  if Assigned(TAtlasIdeEditorToolbar.FHooks.ShortCutOf) then
  begin
    mKey := TAtlasIdeEditorToolbar.FHooks.ShortCutOf(AId);
  end;
  if mKey <> '' then
  begin
    Result := Result + ' (' + mKey + ')';
  end;
end;

/// <summary>Zustand aus den Hooks: Befundpunkt an „Probleme“, gesperrtes Zurück bzw. Vor.</summary>
procedure MarkHooks(var AButton: TAtlasToolbarButton; const AFileName: string);
var
  mHooks: TAtlasIdeEditorToolbar.THooks;
  mFindings: Integer;
begin
  mHooks := TAtlasIdeEditorToolbar.FHooks;
  if SameText(AButton.Id, ProblemsId) and Assigned(mHooks.FindingsOf) and (AFileName <> '') then
  begin
    mFindings := mHooks.FindingsOf(AFileName);
    AButton.Dot := mFindings > 0;
    if mFindings > 0 then
    begin
      AButton.Hint := Format(TAtlasStrings.Text(TAtlasTextId.EditorToolbarFindings), [AButton.Hint, mFindings]);
    end;
  end
  else if SameText(AButton.Id, BackId) and Assigned(mHooks.CanGoBack) then
  begin
    AButton.Enabled := mHooks.CanGoBack();
  end
  else if SameText(AButton.Id, ForwardId) and Assigned(mHooks.CanGoForward) then
  begin
    AButton.Enabled := mHooks.CanGoForward();
  end;
end;

/// <summary>Befehl eines Klicks: die Palette selbst oder ein Palettenbefehl.</summary>
procedure RunToolbarCommand(const AId: string);
begin
  if SameText(AId, TAtlasToolbarItems.CommandPalette) then
  begin
    if Assigned(TAtlasIdeEditorToolbar.FHooks.ShowPalette) then
    begin
      TAtlasIdeEditorToolbar.FHooks.ShowPalette();
    end;
  end
  else if Assigned(TAtlasIdeEditorToolbar.FHooks.Execute) then
  begin
    TAtlasIdeEditorToolbar.FHooks.Execute(AId);
  end;
end;

{ TToolbarState }

constructor TToolbarState.Create;
begin
  inherited Create;
  FHost := TAtlasEditorBarHost.Create('Editorleiste', TAtlasFeature.EditorToolbar,
    function(AEditorParent: TWinControl): TControl
    begin
      Result := CreateBar;
    end,
    procedure(ABar: TControl; AEditorParent: TWinControl)
    begin
      Place(TAtlasEditorToolbar(ABar), AEditorParent);
    end);
  // Nur im Code-Editor; im Formular-Designer steht die Designer-Leiste (#1442).
  FHost.ShowIn := TAtlasEditorBarView.Code;
  FPoints := TAtlasReturnPoints.Create;
  FLineCounts := TDictionary<string, Integer>.Create;
  FLastLine := -1;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := TickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
  Reset;
end;

destructor TToolbarState.Destroy;
begin
  FTimer.Free;
  FHost.Free;
  FLineCounts.Free;
  FPoints.Free;
  inherited Destroy;
end;

function TToolbarState.ToolbarOn: Boolean;
begin
  Result := TAtlasIdeSettings.Current.EditorToolbar;
end;

procedure TToolbarState.Reset;
begin
  FSlow := 0;
  FSectionsFile := '';
  // Die Position stellt Place beim nächsten Takt um, die Knöpfe UpdateBar; hier nur, was alle Leisten betrifft.
  FHost.ForEach(
    procedure(ABar: TControl)
    begin
      TAtlasEditorToolbar(ABar).Labels := TAtlasIdeSettings.Current.EditorToolbarLabels;
    end);
  ApplyTheme;
  if Assigned(TAtlasIdeEditorToolbar.FHooks.Commands) then
  begin
    FCommands := TAtlasIdeEditorToolbar.FHooks.Commands();
  end
  else
  begin
    FCommands := nil;
  end;
end;

procedure TToolbarState.ApplyTheme;
var
  Colors: TAtlasColors;
begin
  Colors := BarColors;
  FHost.ForEach(
    procedure(ABar: TControl)
    begin
      TAtlasEditorToolbar(ABar).SetColors(Colors);
    end);
end;

function TToolbarState.CrumbsOf(AHost: TWinControl): TAtlasBreadcrumbBar;
var
  Index: Integer;
begin
  for Index := 0 to AHost.ControlCount - 1 do
  begin
    if AHost.Controls[Index] is TAtlasBreadcrumbBar then
    begin
      Exit(TAtlasBreadcrumbBar(AHost.Controls[Index]));
    end;
  end;
  Result := nil;
end;

/// <summary>Eigene Methode: Jede Leiste braucht ihre eigene gefangene Variable. Einordnen und Wächter: Host.</summary>
function TToolbarState.CreateBar: TAtlasEditorToolbar;
var
  Bar: TAtlasEditorToolbar;
  Host: TAtlasEditorBarHost;
begin
  Bar := TAtlasEditorToolbar.Create(nil);
  Host := FHost;
  Bar.SetColors(BarColors);
  Bar.Labels := TAtlasIdeSettings.Current.EditorToolbarLabels;
  Bar.MoreHint := TAtlasStrings.Text(TAtlasTextId.EditorToolbarMore);
  Bar.GearHint := TAtlasStrings.Text(TAtlasTextId.EditorToolbarCustomizeCommand);
  Bar.CustomizeCaption := TAtlasStrings.Text(TAtlasTextId.EditorToolbarCustomizeCommand);
  Bar.OnDisabled :=
    procedure(ASender: TObject)
    begin
      Host.Disabled(ASender);
    end;
  Bar.OnCommand :=
    procedure(const AId: string)
    var
      Id: string;
    begin
      Id := AId;
      // Im Protokoll: Der Klick kam an (Handtest zu „Klick ohne Wirkung“).
      TAtlasGuard.Log('Editorleiste: Klick auf ' + Id);
      // Nach dem Klick: Die IDE holt den Fokus in den Editor; Popups und Dialoge erst danach.
      Later(
        procedure
        begin
          RunToolbarCommand(Id);
        end);
    end;
  Bar.OnReturn :=
    procedure
    begin
      TAtlasGuard.Log('Editorleiste: Klick auf Rücksprung');
      Later(
        procedure
        begin
          TAtlasIdeEditorToolbar.ReturnFromSection;
        end);
    end;
  Bar.OnCustomize :=
    procedure
    begin
      TAtlasGuard.Log('Editorleiste: Klick auf Leiste anpassen');
      Later(
        procedure
        begin
          TAtlasIdeEditorToolbar.Customize;
        end);
    end;
  Result := Bar;
end;

/// <summary>Leiste an ihre Stelle: rechts in der Brotkrumenzeile oder oben, unter bzw. über den Brotkrumen. Die
/// Brotkrumenleiste kann später kommen oder gehen; jeder Takt prüft die Reihenfolge.</summary>
procedure TToolbarState.Place(ABar: TAtlasEditorToolbar; AHost: TWinControl);
var
  Crumbs: TAtlasBreadcrumbBar;
  Position: string;
  Width_: Integer;
begin
  Crumbs := CrumbsOf(AHost);
  Position := TAtlasIdeSettings.Current.EditorToolbarPosition;
  if SameText(Position, PositionInline) and (Crumbs <> nil) then
  begin
    if ABar.Parent <> Crumbs then
    begin
      ABar.Parent := nil;
      ABar.InlineMode := True;
      ABar.Align := alRight;
      ABar.Parent := Crumbs;
    end;
    // So breit wie nötig, höchstens die halbe Zeile; der Rest geht ins ».
    Width_ := Min(ABar.PreferredWidth, Max(MulDiv(120, Crumbs.CurrentPPI, 96), Crumbs.ClientWidth div 2));
    if ABar.Width <> Width_ then
    begin
      ABar.Width := Width_;
    end;
    Exit;
  end;
  if ABar.Parent <> AHost then
  begin
    ABar.Parent := nil;
    ABar.InlineMode := False;
    ABar.Align := alNone;
    ABar.Top := 0;
    if (Crumbs <> nil) and not SameText(Position, PositionAbove) then
    begin
      ABar.Top := Crumbs.Top + Crumbs.Height;
    end;
    ABar.Align := alTop;
    ABar.Parent := AHost;
  end;
  if Crumbs = nil then
  begin
    Exit;
  end;
  // alTop ordnet nach Top: kleiner steht weiter oben.
  if SameText(Position, PositionAbove) then
  begin
    if ABar.Top > Crumbs.Top then
    begin
      ABar.Top := Crumbs.Top - 1;
    end;
  end
  else if ABar.Top < Crumbs.Top then
  begin
    ABar.Top := Crumbs.Top + Crumbs.Height;
  end;
end;

function TToolbarState.SectionsOf(const AView: IOTAEditView; out AFileName: string): TAtlasUnitSections;
var
  Snapshot: TAtlasEditorSnapshot;
begin
  Snapshot := TAtlasEditorSnapshots.Get(AView);
  AFileName := Snapshot.FileName;
  if (Snapshot.Version <> FSectionsVersion) or not SameText(Snapshot.FileName, FSectionsFile) then
  begin
    FSections := TAtlasSectionScanner.Scan(Snapshot.Text);
    FSectionsVersion := Snapshot.Version;
    FSectionsFile := Snapshot.FileName;
  end;
  Result := FSections;
end;

function TToolbarState.CommandOf(const AId: string; out ACommand: TAtlasCommand): Boolean;
var
  Command: TAtlasCommand;
begin
  for Command in FCommands do
  begin
    if SameText(Command.Id, AId) then
    begin
      ACommand := Command;
      Exit(True);
    end;
  end;
  ACommand := Default(TAtlasCommand);
  Result := False;
end;

/// <summary>Text der Schaltfläche; False, wenn der Befehl fehlt.</summary>
function TToolbarState.CaptionOf(const AId: string; out ACaption: string): Boolean;
var
  mCommand: TAtlasCommand;
begin
  Result := True;
  // Die Palette selbst ist kein Palettenbefehl; abgeschaltete Funktionen fehlen in der Palette und in der Leiste.
  if SameText(AId, TAtlasToolbarItems.CommandPalette) then
  begin
    ACaption := TAtlasStrings.Text(TAtlasTextId.CommandPaletteCommand);
  end
  else if CommandOf(AId, mCommand) then
  begin
    ACaption := PlainCaption(mCommand.Caption);
  end
  else
  begin
    ACaption := '';
    Result := False;
  end;
end;

/// <summary>Abschnittsbefehl: gesperrt ohne Ziel (mit Grund im Tooltip), hervorgehoben im eigenen Abschnitt.</summary>
procedure TToolbarState.MarkSection(var AButton: TAtlasToolbarButton; ATarget: TAtlasSectionTarget;
  ALine, ACharacter: Integer; ASection: TAtlasCodeSection);
var
  mMark: TAtlasSectionMark;
begin
  AButton.Enabled := (FSectionsFile <> '') and FSections.Target(ATarget, ALine, ACharacter, mMark);
  AButton.Pressed := AButton.Enabled and SectionPressed(ATarget, ASection);
  if AButton.Enabled then
  begin
    Exit;
  end;
  if ATarget in [TAtlasSectionTarget.InterfacePart, TAtlasSectionTarget.ImplementationPart] then
  begin
    AButton.Hint := TAtlasStrings.Text(TAtlasTextId.EditorToolbarNoParts);
  end
  else
  begin
    AButton.Hint := Format(TAtlasStrings.Text(TAtlasTextId.EditorToolbarNoSection), [AButton.Caption]);
  end;
end;

function TToolbarState.ButtonsFor(const AFileName: string; ALine, ACharacter: Integer): TArray<TAtlasToolbarButton>;
var
  mItems: TArray<string>;
  mId, mCaption: string;
  mButton: TAtlasToolbarButton;
  mTarget: TAtlasSectionTarget;
  mSection: TAtlasCodeSection;
  mPinned, mIndex: Integer;
begin
  Result := nil;
  mItems := TAtlasToolbarItems.Parse(TAtlasIdeSettings.Current.EditorToolbarItems);
  mPinned := TAtlasToolbarItems.PinnedCount(mItems);
  mSection := FSections.SectionAt(ALine, ACharacter);
  for mIndex := 0 to High(mItems) do
  begin
    mId := mItems[mIndex];
    if TAtlasToolbarItems.IsSeparator(mId) then
    begin
      Result := Result + [TAtlasToolbarButton.Separator];
    end
    else if CaptionOf(mId, mCaption) then
    begin
      mButton := TAtlasToolbarButton.Create(mId, mCaption, KeyHint(mId, mCaption), TAtlasToolbarIcons.IconOf(mId));
      mButton.Pinned := mIndex < mPinned;
      if SectionTargetOf(mId, mTarget) then
      begin
        MarkSection(mButton, mTarget, ALine, ACharacter, mSection);
      end
      else
      begin
        MarkHooks(mButton, AFileName);
      end;
      Result := Result + [mButton];
    end;
  end;
end;

procedure TToolbarState.UpdateBar(ABar: TAtlasEditorToolbar; const AFileName: string;
  ALine, ACharacter: Integer);
var
  Point: TAtlasReturnPoint;
  Hint: string;
begin
  ABar.Labels := TAtlasIdeSettings.Current.EditorToolbarLabels;
  ABar.SetButtons(ButtonsFor(AFileName, ALine, ACharacter));
  if TAtlasIdeSettings.Current.EditorToolbarReturnButton and FPoints.Find(AFileName, Point) then
  begin
    if Point.Context <> '' then
    begin
      Hint := Format(TAtlasStrings.Text(TAtlasTextId.EditorToolbarReturnLineIn), [Point.Line + 1, Point.Context]);
    end
    else
    begin
      Hint := Format(TAtlasStrings.Text(TAtlasTextId.EditorToolbarReturnLine), [Point.Line + 1]);
    end;
    ABar.SetReturn(True, IntToStr(Point.Line + 1), Hint);
  end
  else
  begin
    ABar.SetReturn(False, '', '');
  end;
end;

/// <summary>Rücksprungpunkte mit eingefügten bzw. gelöschten Zeilen verschieben (wie der Navigationsverlauf) und
/// erledigen, wenn der Caret auf die Zeile zurückkommt.</summary>
procedure TToolbarState.Track(const AView: IOTAEditView; const AFileName: string; ALine: Integer);
var
  Key: string;
  Count, Known, Anchor: Integer;
begin
  if FPoints.Count = 0 then
  begin
    FLineCounts.Clear;
    Exit;
  end;
  Key := AnsiUpperCase(AFileName);
  Count := AView.Buffer.GetLinesInBuffer;
  if FLineCounts.TryGetValue(Key, Known) and (Known <> Count) then
  begin
    // Eingefügt bzw. gelöscht wurde an der Cursorstelle vor oder nach der Änderung.
    Anchor := ALine;
    if SameText(FLastFile, AFileName) and (FLastLine >= 0) then
    begin
      Anchor := Min(Anchor, FLastLine);
    end;
    FPoints.LinesChanged(AFileName, Anchor, Count - Known);
  end;
  FLineCounts.AddOrSetValue(Key, Count);
  FPoints.Caret(AFileName, ALine);
  FLastFile := AFileName;
  FLastLine := ALine;
end;

procedure TToolbarState.ForgetClosedFiles;
var
  Services: IOTAModuleServices;
  Files: TArray<string>;
  Index: Integer;
begin
  if (FPoints.Count = 0) or not Supports(BorlandIDEServices, IOTAModuleServices, Services) then
  begin
    Exit;
  end;
  Files := nil;
  for Index := 0 to Services.ModuleCount - 1 do
  begin
    Files := Files + [Services.Modules[Index].FileName];
  end;
  FPoints.KeepOnly(Files);
end;

procedure TToolbarState.Tick(Sender: TObject);
var
  mOn: Boolean;
begin
  mOn := ToolbarOn;
  // Sicherung ausgelöst: Leisten weg, bis die Funktion wieder eingeschaltet ist.
  if not FHost.Guard then
  begin
    Exit;
  end;
  // Ohne Leiste und ohne Rücksprungpunkte gibt es nichts zu tun.
  if not mOn and (FPoints.Count = 0) then
  begin
    if FHost.Count > 0 then
    begin
      FHost.Clear;
    end;
    Exit;
  end;
  // Kein Editor aktiv oder die IDE im Hintergrund: Nur jeder SlowTicks-te Takt räumt auf.
  if not Application.Active or (TAtlasEditorBuffer.ActiveView = nil) then
  begin
    Inc(FIdle);
    if FIdle < SlowTicks then
    begin
      Exit;
    end;
  end;
  FIdle := 0;
  TAtlasGuard.Run(TAtlasFeature.EditorToolbar,
    procedure
    begin
      Step(mOn);
    end);
end;

/// <summary>Befehlsliste und offene Dateien nur alle SlowTicks Takte neu lesen.</summary>
procedure TToolbarState.SlowRefresh;
begin
  Inc(FSlow);
  if FSlow < SlowTicks then
  begin
    Exit;
  end;
  FSlow := 0;
  if Assigned(TAtlasIdeEditorToolbar.FHooks.Commands) then
  begin
    FCommands := TAtlasIdeEditorToolbar.FHooks.Commands();
  end;
  ForgetClosedFiles;
end;

/// <summary>Ein Takt unter dem Wächter: Leisten zeigen bzw. entfernen, Rücksprungpunkte nachführen, Leiste füllen.</summary>
procedure TToolbarState.Step(AOn: Boolean);
var
  mView: IOTAEditView;
  mFileName: string;
  mLine, mCharacter: Integer;
  mBar: TAtlasEditorToolbar;
begin
  SlowRefresh;
  // Ensure gibt auch die von der IDE gesperrten Leisten frei, sobald ein Editor aktiv ist.
  if AOn then
  begin
    FHost.Ensure;
  end
  else if FHost.Count > 0 then
  begin
    FHost.Clear;
  end;
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView = nil) or not TAtlasIdeFindMethod.CaretOf(mView, mLine, mCharacter) then
  begin
    Exit;
  end;
  mFileName := mView.Buffer.FileName;
  Track(mView, mFileName, mLine);
  mBar := nil;
  if AOn then
  begin
    mBar := TAtlasEditorToolbar(FHost.ActiveBar);
  end;
  if mBar = nil then
  begin
    Exit;
  end;
  SectionsOf(mView, mFileName);
  if mFileName = '' then
  begin
    mFileName := mView.Buffer.FileName;
  end;
  UpdateBar(mBar, mFileName, mLine, mCharacter);
end;

/// <summary>Erst nach dem Klick ausführen (siehe CreateBar); nur, wenn der Zustand dann noch lebt.</summary>
procedure TToolbarState.Later(const AAction: TProc);
var
  Owner: TToolbarState;
  Action: TProc;
begin
  Owner := Self;
  Action := AAction;
  TAtlasMainThread.ForceQueue(TAtlasFeature.EditorToolbar,
    procedure
    begin
      if TAtlasIdeEditorToolbar.FState <> Owner then
      begin
        Exit;
      end;
      TAtlasGuard.Run(TAtlasFeature.EditorToolbar, Action);
    end);
end;

{ TAtlasIdeEditorToolbar }

class procedure TAtlasIdeEditorToolbar.Say(const AText: string);
begin
  if Assigned(FHooks.Message) then
  begin
    FHooks.Message(AText);
  end;
end;

class function TAtlasIdeEditorToolbar.Enabled: Boolean;
begin
  Result := TAtlasIdeSettings.Current.EditorToolbar;
end;

class procedure TAtlasIdeEditorToolbar.Install(const AHooks: THooks);
begin
  FreeAndNil(FState);
  FHooks := AHooks;
  // Immer: Die Abschnittsbefehle samt Rücksprung arbeiten auch ohne Leiste.
  FState := TToolbarState.Create;
end;

class procedure TAtlasIdeEditorToolbar.Uninstall;
begin
  FreeAndNil(FState);
  FHooks := Default(THooks);
end;

class procedure TAtlasIdeEditorToolbar.ApplySettings;
begin
  if FState <> nil then
  begin
    State.Reset;
  end;
end;

class procedure TAtlasIdeEditorToolbar.ThemeChanged;
begin
  if FState <> nil then
  begin
    State.ApplyTheme;
  end;
end;

class procedure TAtlasIdeEditorToolbar.GoToSection(ATarget: TAtlasSectionTarget);
var
  View: IOTAEditView;
  FileName: string;
  Sections: TAtlasUnitSections;
  Mark: TAtlasSectionMark;
  Line, Character, Rows: Integer;
  Context: string;
  Outline: TAtlasOutlineSnapshot;
begin
  if FState = nil then
  begin
    Exit;
  end;
  View := TAtlasEditorBuffer.ActiveView;
  if (View = nil) or not TAtlasIdeFindMethod.CaretOf(View, Line, Character) then
  begin
    Exit;
  end;
  Sections := State.SectionsOf(View, FileName);
  if FileName = '' then
  begin
    FileName := View.Buffer.FileName;
  end;
  if not Sections.Target(ATarget, Line, Character, Mark) then
  begin
    Say(Format(TAtlasStrings.Text(TAtlasTextId.EditorToolbarNoSection), [SectionCaption(ATarget)]));
    Exit;
  end;
  // Methode der Ausgangszeile für den Tooltip „Zurück zu Zeile 214 · TfrmKunde.btnSpeichernClick“.
  Context := '';
  Outline := TAtlasIdeOutlineCache.Refresh(View);
  if (Outline.Status = TAtlasOutlineStatus.Ready) and SameText(Outline.FileName, FileName) then
  begin
    Context := TAtlasReturnPoints.ContextAt(Outline.Nodes, Line);
  end;
  TAtlasGuard.Log(Format('Editorleiste: Abschnittssprung %d', [Ord(ATarget)]));
  TAtlasIdeNavigation.GoToLocation(FileName, Mark.Line, Mark.Character);
  // Ziel ins obere Drittel: Darunter steht, was zum Abschnitt gehört.
  View := TAtlasEditorBuffer.ActiveView;
  if View <> nil then
  begin
    Rows := Max(1, View.ViewSize.cy);
    View.SetTopLeft(Max(1, Mark.Line + 1 - Rows div 3), View.LeftColumn);
    View.Paint;
  end;
  State.Points.Jumped(FileName, Line, Mark.Line, Context);
end;

class procedure TAtlasIdeEditorToolbar.GotoInterface;
begin
  GoToSection(TAtlasSectionTarget.InterfacePart);
end;

class procedure TAtlasIdeEditorToolbar.GotoImplementation;
begin
  GoToSection(TAtlasSectionTarget.ImplementationPart);
end;

class procedure TAtlasIdeEditorToolbar.GotoUses;
begin
  GoToSection(TAtlasSectionTarget.UsesClause);
end;

class procedure TAtlasIdeEditorToolbar.GotoInitialization;
begin
  GoToSection(TAtlasSectionTarget.Initialization_);
end;

class procedure TAtlasIdeEditorToolbar.ReturnFromSection;
var
  View: IOTAEditView;
  FileName, Text: string;
  Point: TAtlasReturnPoint;
  Character: Integer;
begin
  if FState = nil then
  begin
    Exit;
  end;
  View := TAtlasEditorBuffer.ActiveView;
  if View = nil then
  begin
    Exit;
  end;
  FileName := View.Buffer.FileName;
  if not State.Points.Find(FileName, Point) then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.EditorToolbarNoReturn));
    Exit;
  end;
  // Auf das erste Zeichen der Zeile; die Spalte merkt sich der Sprung nicht.
  Text := TAtlasEditorBuffer.LineText(View, Point.Line + 1);
  Character := Length(Text) - Length(TrimLeft(Text));
  TAtlasIdeNavigation.GoToLocation(FileName, Point.Line, Character);
  State.Points.Caret(FileName, Point.Line);
end;

class procedure TAtlasIdeEditorToolbar.FindMethod;
begin
  TAtlasIdeFindMethod.Show(
    procedure(AText: string)
    begin
      Say(AText);
    end);
end;

class function TAtlasIdeEditorToolbar.CommandInfos: TArray<TAtlasToolbarCommandInfo>;
var
  Command: TAtlasCommand;
begin
  Result := nil;
  if Assigned(FHooks.Commands) then
  begin
    for Command in FHooks.Commands() do
    begin
      Result := Result + [TAtlasToolbarCommandInfo.Create(Command.Id, PlainCaption(Command.Caption))];
    end;
  end;
  Result := Result + [TAtlasToolbarCommandInfo.Create(TAtlasToolbarItems.CommandPalette,
    TAtlasStrings.Text(TAtlasTextId.CommandPaletteCommand))];
end;

class procedure TAtlasIdeEditorToolbar.Customize;
var
  Config: TAtlasToolbarConfig;
  Next: TAtlasPluginSettings;
begin
  Next := TAtlasIdeSettings.Stored;
  Config.Items := TAtlasToolbarItems.Parse(Next.EditorToolbarItems);
  Config.Labels := Next.EditorToolbarLabels;
  Config.Position := Next.EditorToolbarPosition;
  if not TAtlasToolbarCustomizeDialog.Execute(CommandInfos, Config) then
  begin
    Exit;
  end;
  Next.EditorToolbarItems := TAtlasToolbarItems.Format(Config.Items);
  Next.EditorToolbarLabels := Config.Labels;
  Next.EditorToolbarPosition := Config.Position;
  TAtlasIdeSettings.Update(Next);
end;

end.
