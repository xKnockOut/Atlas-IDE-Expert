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
  cTickMs = 150;
  /// <summary>Befehlsliste und offene Dateien nur alle so viele Takte neu lesen (etwa 2 s).</summary>
  cSlowTicks = 13;
  cPositionAbove = 'aboveBreadcrumbs';
  cPositionInline = 'inBreadcrumbs';
  cAtlasPrefix = 'Atlas: ';
  cProblemsId = 'Atlas.ProblemsWindow';
  cBackId = 'Atlas.NavBack';
  cForwardId = 'Atlas.NavForward';

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
  if Result.StartsWith(cAtlasPrefix) then
  begin
    Result := Copy(Result, Length(cAtlasPrefix) + 1, MaxInt);
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
  if SameText(AId, TAtlasToolbarItems.cGotoInterface) then
  begin
    ATarget := TAtlasSectionTarget.InterfacePart;
  end
  else if SameText(AId, TAtlasToolbarItems.cGotoImplementation) then
  begin
    ATarget := TAtlasSectionTarget.ImplementationPart;
  end
  else if SameText(AId, TAtlasToolbarItems.cGotoUses) then
  begin
    ATarget := TAtlasSectionTarget.UsesClause;
  end
  else if SameText(AId, TAtlasToolbarItems.cGotoInitialization) then
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
  if SameText(AButton.Id, cProblemsId) and Assigned(mHooks.FindingsOf) and (AFileName <> '') then
  begin
    mFindings := mHooks.FindingsOf(AFileName);
    AButton.Dot := mFindings > 0;
    if mFindings > 0 then
    begin
      AButton.Hint := Format(TAtlasStrings.Text(TAtlasTextId.EditorToolbarFindings), [AButton.Hint, mFindings]);
    end;
  end
  else if SameText(AButton.Id, cBackId) and Assigned(mHooks.CanGoBack) then
  begin
    AButton.Enabled := mHooks.CanGoBack();
  end
  else if SameText(AButton.Id, cForwardId) and Assigned(mHooks.CanGoForward) then
  begin
    AButton.Enabled := mHooks.CanGoForward();
  end;
end;

/// <summary>Befehl eines Klicks: die Palette selbst oder ein Palettenbefehl.</summary>
procedure RunToolbarCommand(const AId: string);
begin
  if SameText(AId, TAtlasToolbarItems.cCommandPalette) then
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
  FTimer.Interval := cTickMs;
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
begin
  FHost.ForEach(
    procedure(ABar: TControl)
    begin
      TAtlasEditorToolbar(ABar).SetColors(TAtlasIdeStyle.BarColors);
    end);
end;

function TToolbarState.CrumbsOf(AHost: TWinControl): TAtlasBreadcrumbBar;
var
  mIndex: Integer;
begin
  for mIndex := 0 to AHost.ControlCount - 1 do
  begin
    if AHost.Controls[mIndex] is TAtlasBreadcrumbBar then
    begin
      Exit(TAtlasBreadcrumbBar(AHost.Controls[mIndex]));
    end;
  end;
  Result := nil;
end;

/// <summary>Eigene Methode: Jede Leiste braucht ihre eigene gefangene Variable. Einordnen und Wächter: Host.</summary>
function TToolbarState.CreateBar: TAtlasEditorToolbar;
var
  mBar: TAtlasEditorToolbar;
  mHost: TAtlasEditorBarHost;
begin
  mBar := TAtlasEditorToolbar.Create(nil);
  mHost := FHost;
  mBar.SetColors(TAtlasIdeStyle.BarColors);
  mBar.Labels := TAtlasIdeSettings.Current.EditorToolbarLabels;
  mBar.MoreHint := TAtlasStrings.Text(TAtlasTextId.EditorToolbarMore);
  mBar.GearHint := TAtlasStrings.Text(TAtlasTextId.EditorToolbarCustomizeCommand);
  mBar.CustomizeCaption := TAtlasStrings.Text(TAtlasTextId.EditorToolbarCustomizeCommand);
  mBar.OnDisabled :=
    procedure(ASender: TObject)
    begin
      mHost.Disabled(ASender);
    end;
  mBar.OnCommand :=
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
  mBar.OnReturn :=
    procedure
    begin
      TAtlasGuard.Log('Editorleiste: Klick auf Rücksprung');
      Later(
        procedure
        begin
          TAtlasIdeEditorToolbar.ReturnFromSection;
        end);
    end;
  mBar.OnCustomize :=
    procedure
    begin
      TAtlasGuard.Log('Editorleiste: Klick auf Leiste anpassen');
      Later(
        procedure
        begin
          TAtlasIdeEditorToolbar.Customize;
        end);
    end;
  Result := mBar;
end;

/// <summary>Leiste an ihre Stelle: rechts in der Brotkrumenzeile oder oben, unter bzw. über den Brotkrumen. Die
/// Brotkrumenleiste kann später kommen oder gehen; jeder Takt prüft die Reihenfolge.</summary>
procedure TToolbarState.Place(ABar: TAtlasEditorToolbar; AHost: TWinControl);
var
  mCrumbs: TAtlasBreadcrumbBar;
  mPosition: string;
  mWidth_: Integer;
begin
  mCrumbs := CrumbsOf(AHost);
  mPosition := TAtlasIdeSettings.Current.EditorToolbarPosition;
  if SameText(mPosition, cPositionInline) and (mCrumbs <> nil) then
  begin
    if ABar.Parent <> mCrumbs then
    begin
      ABar.Parent := nil;
      ABar.InlineMode := True;
      ABar.Align := alRight;
      ABar.Parent := mCrumbs;
    end;
    // So breit wie nötig, höchstens die halbe Zeile; der Rest geht ins ».
    mWidth_ := Min(ABar.PreferredWidth, Max(MulDiv(120, mCrumbs.CurrentPPI, 96), mCrumbs.ClientWidth div 2));
    if ABar.Width <> mWidth_ then
    begin
      ABar.Width := mWidth_;
    end;
    Exit;
  end;
  if ABar.Parent <> AHost then
  begin
    ABar.Parent := nil;
    ABar.InlineMode := False;
    ABar.Align := alNone;
    ABar.Top := 0;
    if (mCrumbs <> nil) and not SameText(mPosition, cPositionAbove) then
    begin
      ABar.Top := mCrumbs.Top + mCrumbs.Height;
    end;
    ABar.Align := alTop;
    ABar.Parent := AHost;
  end;
  if mCrumbs = nil then
  begin
    Exit;
  end;
  // alTop ordnet nach Top: kleiner steht weiter oben.
  if SameText(mPosition, cPositionAbove) then
  begin
    if ABar.Top > mCrumbs.Top then
    begin
      ABar.Top := mCrumbs.Top - 1;
    end;
  end
  else if ABar.Top < mCrumbs.Top then
  begin
    ABar.Top := mCrumbs.Top + mCrumbs.Height;
  end;
end;

function TToolbarState.SectionsOf(const AView: IOTAEditView; out AFileName: string): TAtlasUnitSections;
var
  mSnapshot: TAtlasEditorSnapshot;
begin
  mSnapshot := TAtlasEditorSnapshots.Get(AView);
  AFileName := mSnapshot.FileName;
  if (mSnapshot.Version <> FSectionsVersion) or not SameText(mSnapshot.FileName, FSectionsFile) then
  begin
    FSections := TAtlasSectionScanner.Scan(mSnapshot.Text);
    FSectionsVersion := mSnapshot.Version;
    FSectionsFile := mSnapshot.FileName;
  end;
  Result := FSections;
end;

function TToolbarState.CommandOf(const AId: string; out ACommand: TAtlasCommand): Boolean;
var
  mCommand: TAtlasCommand;
begin
  for mCommand in FCommands do
  begin
    if SameText(mCommand.Id, AId) then
    begin
      ACommand := mCommand;
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
  if SameText(AId, TAtlasToolbarItems.cCommandPalette) then
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
  mPoint: TAtlasReturnPoint;
  mHint: string;
begin
  ABar.Labels := TAtlasIdeSettings.Current.EditorToolbarLabels;
  ABar.SetButtons(ButtonsFor(AFileName, ALine, ACharacter));
  if TAtlasIdeSettings.Current.EditorToolbarReturnButton and FPoints.Find(AFileName, mPoint) then
  begin
    if mPoint.Context <> '' then
    begin
      mHint := Format(TAtlasStrings.Text(TAtlasTextId.EditorToolbarReturnLineIn), [mPoint.Line + 1, mPoint.Context]);
    end
    else
    begin
      mHint := Format(TAtlasStrings.Text(TAtlasTextId.EditorToolbarReturnLine), [mPoint.Line + 1]);
    end;
    ABar.SetReturn(True, IntToStr(mPoint.Line + 1), mHint);
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
  mKey: string;
  mCount, mKnown, mAnchor: Integer;
begin
  if FPoints.Count = 0 then
  begin
    FLineCounts.Clear;
    Exit;
  end;
  mKey := AnsiUpperCase(AFileName);
  mCount := AView.Buffer.GetLinesInBuffer;
  if FLineCounts.TryGetValue(mKey, mKnown) and (mKnown <> mCount) then
  begin
    // Eingefügt bzw. gelöscht wurde an der Cursorstelle vor oder nach der Änderung.
    mAnchor := ALine;
    if SameText(FLastFile, AFileName) and (FLastLine >= 0) then
    begin
      mAnchor := Min(mAnchor, FLastLine);
    end;
    FPoints.LinesChanged(AFileName, mAnchor, mCount - mKnown);
  end;
  FLineCounts.AddOrSetValue(mKey, mCount);
  FPoints.Caret(AFileName, ALine);
  FLastFile := AFileName;
  FLastLine := ALine;
end;

procedure TToolbarState.ForgetClosedFiles;
var
  mServices: IOTAModuleServices;
  mFiles: TArray<string>;
  mIndex: Integer;
begin
  if (FPoints.Count = 0) or not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  mFiles := nil;
  for mIndex := 0 to mServices.ModuleCount - 1 do
  begin
    mFiles := mFiles + [mServices.Modules[mIndex].FileName];
  end;
  FPoints.KeepOnly(mFiles);
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
    if FIdle < cSlowTicks then
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
  if FSlow < cSlowTicks then
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

/// <summary>Ein Takt unter dem Wächter: Leisten zeigen bzw. entfernen, Rücksprungpunkte nachführen, Leiste
/// füllen.</summary>
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
  mOwner: TToolbarState;
  mAction: TProc;
begin
  mOwner := Self;
  mAction := AAction;
  TAtlasMainThread.ForceQueue(TAtlasFeature.EditorToolbar,
    procedure
    begin
      if TAtlasIdeEditorToolbar.FState <> mOwner then
      begin
        Exit;
      end;
      TAtlasGuard.Run(TAtlasFeature.EditorToolbar, mAction);
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
  mView: IOTAEditView;
  mFileName: string;
  mSections: TAtlasUnitSections;
  mMark: TAtlasSectionMark;
  mLine, mCharacter, mRows: Integer;
  mContext: string;
  mOutline: TAtlasOutlineSnapshot;
begin
  if FState = nil then
  begin
    Exit;
  end;
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView = nil) or not TAtlasIdeFindMethod.CaretOf(mView, mLine, mCharacter) then
  begin
    Exit;
  end;
  mSections := State.SectionsOf(mView, mFileName);
  if mFileName = '' then
  begin
    mFileName := mView.Buffer.FileName;
  end;
  if not mSections.Target(ATarget, mLine, mCharacter, mMark) then
  begin
    Say(Format(TAtlasStrings.Text(TAtlasTextId.EditorToolbarNoSection), [SectionCaption(ATarget)]));
    Exit;
  end;
  // Methode der Ausgangszeile für den Tooltip „Zurück zu Zeile 214 · TfrmKunde.btnSpeichernClick“.
  mContext := '';
  mOutline := TAtlasIdeOutlineCache.Refresh(mView);
  if (mOutline.Status = TAtlasOutlineStatus.Ready) and SameText(mOutline.FileName, mFileName) then
  begin
    mContext := TAtlasReturnPoints.ContextAt(mOutline.Nodes, mLine);
  end;
  TAtlasGuard.Log(Format('Editorleiste: Abschnittssprung %d', [Ord(ATarget)]));
  TAtlasIdeNavigation.GoToLocation(mFileName, mMark.Line, mMark.Character);
  // Ziel ins obere Drittel: Darunter steht, was zum Abschnitt gehört.
  mView := TAtlasEditorBuffer.ActiveView;
  if mView <> nil then
  begin
    mRows := Max(1, mView.ViewSize.cy);
    mView.SetTopLeft(Max(1, mMark.Line + 1 - mRows div 3), mView.LeftColumn);
    mView.Paint;
  end;
  State.Points.Jumped(mFileName, mLine, mMark.Line, mContext);
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
  mView: IOTAEditView;
  mFileName, mText: string;
  mPoint: TAtlasReturnPoint;
  mCharacter: Integer;
begin
  if FState = nil then
  begin
    Exit;
  end;
  mView := TAtlasEditorBuffer.ActiveView;
  if mView = nil then
  begin
    Exit;
  end;
  mFileName := mView.Buffer.FileName;
  if not State.Points.Find(mFileName, mPoint) then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.EditorToolbarNoReturn));
    Exit;
  end;
  // Auf das erste Zeichen der Zeile; die Spalte merkt sich der Sprung nicht.
  mText := TAtlasEditorBuffer.LineText(mView, mPoint.Line + 1);
  mCharacter := Length(mText) - Length(TrimLeft(mText));
  TAtlasIdeNavigation.GoToLocation(mFileName, mPoint.Line, mCharacter);
  State.Points.Caret(mFileName, mPoint.Line);
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
  mCommand: TAtlasCommand;
begin
  Result := nil;
  if Assigned(FHooks.Commands) then
  begin
    for mCommand in FHooks.Commands() do
    begin
      Result := Result + [TAtlasToolbarCommandInfo.Create(mCommand.Id, PlainCaption(mCommand.Caption))];
    end;
  end;
  Result := Result + [TAtlasToolbarCommandInfo.Create(TAtlasToolbarItems.cCommandPalette,
    TAtlasStrings.Text(TAtlasTextId.CommandPaletteCommand))];
end;

class procedure TAtlasIdeEditorToolbar.Customize;
var
  mConfig: TAtlasToolbarConfig;
  mNext: TAtlasPluginSettings;
begin
  mNext := TAtlasIdeSettings.Stored;
  mConfig.Items := TAtlasToolbarItems.Parse(mNext.EditorToolbarItems);
  mConfig.Labels := mNext.EditorToolbarLabels;
  mConfig.Position := mNext.EditorToolbarPosition;
  if not TAtlasToolbarCustomizeDialog.Execute(CommandInfos, mConfig) then
  begin
    Exit;
  end;
  mNext.EditorToolbarItems := TAtlasToolbarItems.Format(mConfig.Items);
  mNext.EditorToolbarLabels := mConfig.Labels;
  mNext.EditorToolbarPosition := mConfig.Position;
  TAtlasIdeSettings.Update(mNext);
end;

end.
