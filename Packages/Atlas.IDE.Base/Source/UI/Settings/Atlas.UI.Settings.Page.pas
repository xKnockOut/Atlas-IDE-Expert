unit Atlas.UI.Settings.Page;

// Seite „Atlas“ unter Tools › Optionen › Drittanbieter (#227). Reine VCL, im Code aufgebaut: Reiter je
// Bereich, darin Steuerelemente untereinander; die IDE skaliert sie mit dem Dialog. Die DFM ist leer;
// TCustomFrame.Create verlangt für abgeleitete Frames eine Ressource. Laden und Speichern über
// TAtlasPluginSettings; die IDE-Schicht liest und schreibt die Registry.
// Die Tastenkürzel von Befehlspalette und Prüfung stehen auf der eigenen Seite „Tastenkonflikte“
// (Atlas.UI.Settings.Keys, #494). Der Reiter „Robustheit“ zeigt, was die Sicherung nach wiederholten
// Fehlern abgeschaltet hat, und schaltet es wieder ein (#493).
// Abschnitt Symbolindex (#492): Verwendungen an/aus, Speichergrenze, Kennzahlen (Units, Deklarationen,
// Größe, letzte Aktualisierung), „Index neu aufbauen“ und „Index löschen“. Die Seite kennt den Server
// nicht; die IDE-Schicht führt die Befehle über OnIndexMetrics, OnIndexRebuild, OnIndexClear im
// Hintergrund aus und meldet den Text mit IndexAnswered (#874). Bis dahin steht „Frage den Server …“ da,
// und die drei Knöpfe sind gesperrt; der Dialog bleibt bedienbar, auch wenn der Server gerade indexiert.
// Im Seitenkopf steht das Atlas-Symbol (#751) passend zu Thema und Skalierung.
// Jeder Reiter bleibt niedriger als die Seite: Sonst scrollt die IDE ihren Bereich beim Reiterwechsel
// zum Fokus, und die Seite „springt“.
// Reiter Vervollständigung: angeheftete Favoriten (#458) an/aus, Liste („TDataSet.Open“) mit „Entfernen“
// und „Alle entfernen“. Die Seite kennt die Ablage nicht; OnFavorites liefert die Liste, OnRemoveFavorites
// löst die Schlüssel sofort (nicht erst mit OK).
// Reveal (#628, „Einstellungen dazu …“ am gezeichneten Element): wählt den Reiter einer Einstellung über ihren
// Schlüssel (Name der Plugin-Einstellung), rollt sie ins Bild, setzt den Fokus und hebt die Zeile fett hervor.
// Bereich Prüfregeln (#909): Unterknoten „Prüffenster“ (problems.window*, problems.live) und „Compiler vorab“
// (problems.compilerMerge, problems.showCompilerCode). Den Weg zu den Regeln (Dialoge der Einstellungsdateien
// mit einem Knoten je Gruppe), Profile, Baseline und Unterdrückungen baut das Modul Prüfregeln als Abschnitt
// (#1755).
// Bereich Versionsverwaltung (#1285): Art (vcs.provider), Programme git und svn mit eigenem Pfad, „…“ und
// „Prüfen“ (Version und Fundort, im Hintergrund über OnVcsCheck), Zeitlimit je Aufruf und „Aktuelles Projekt“
// (beim ersten Zeigen der Seite einmal im Hintergrund abgefragt, OnVcsProject); Links auf die Seiten, die die
// Anzeige steuern. Ohne Klick startet kein Prozess: Beim Öffnen zeigt OnVcsLocate nur, welche Datei gälte.
// Bereich Issue-Tracker (#1280): nur der Modulschalter; Tracker, Abfrage, Start-Optionen, Muster und Zugang
// (issues.*) baut das Modul Tracker als Abschnitt (#1455). Auf der Willkommensseite bleibt nur die Sektion an/aus
// mit dem Sprung „Tracker-Einstellungen …“.
// Abschnitte der Module (#1455, ADR 0017 Entscheidung 3): Jeder IAtlasSettingsSectionProvider der Registry liefert
// der Seite einen eigenen Abschnitt, den sie in den Reiter seines Bereichs baut (Bausteine über
// IAtlasSettingsSectionHost). Geht ein Modul, schließt die Seite seinen Abschnitt; seine Werte bleiben erhalten.
// Suchfeld über dem Baum (#1884, settings.search): Treffer dieses Knotens zeigt die Seite selbst (Reveal), Treffer
// anderer Knoten öffnet OnOpenSetting (die IDE-Schicht springt im offenen Dialog zum Knoten).

interface

uses
  System.Classes,
  System.SysUtils,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.Forms,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.Search,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.Settings.Page.Tree,
  Atlas.UI.Settings.Page.Search,
  Atlas.UI.Style.Symbol;

type
  TAtlasSettingsPage = class(TAtlasSettingsPageTree)
  private
    FSymbol: TAtlasSymbolImage;
    FTitle: TLabel;
    FWidths: TAtlasPluginSettings;
    /// <summary>Reveal vor dem Fenster: folgt in CreateWnd.</summary>
    FPendingReveal: string;
    FExperimentalBanner: TWinControl;
    FFilterRow: TWinControl;
    FFilter: TAtlasChoiceBox;
    FOnOpenSetting: TProc<string, string>;
    procedure ApplyReveal(const AKey: string);
    /// <summary>AControl oder, wenn ein Hauptschalter es sperrt, dieser Schalter.</summary>
    function RevealTarget(AControl: TControl): TControl;
    procedure ExperimentalAllowClick(Sender: TObject);
    procedure FilterChange(Sender: TObject);
    procedure SearchOpen(AHit: TAtlasSettingHit);
    /// <summary>Kopf mit Symbol (#751) und Titel.</summary>
    procedure AddHeader;
    /// <summary>Kopfzeile mit Hinweis und Knopf „Erlauben“, solange experimental.enabled aus ist (#834).</summary>
    procedure AddExperimentalBanner;
    /// <summary>Zeile unten mit dem Filter Alle / Geändert / Nur experimentelle (#834).</summary>
    procedure AddFilterRow;
    procedure LoadControls(const ASettings: TAtlasPluginSettings);
    /// <summary>Bindet die Elemente an ihre Einstellungen (Punkt, Kontextmenü, Zurücksetzen je Seite).</summary>
    procedure BindControls;
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Werte der Seite (ungespeichert) über den zuletzt geladenen.</summary>
    function CurrentSettings: TAtlasPluginSettings; override;
    /// <summary>Punkte an geänderten Werten und Knöpfe neu setzen (#723).</summary>
    procedure RefreshMarks; override;
    /// <summary>Einstellungen ANames (Registry-Namen) auf der Seite auf den Standard setzen; gespeichert wird
    /// erst mit OK (#723).</summary>
    procedure ResetNames(const ANames: TArray<string>); override;
    /// <summary>Alle Einstellungen des sichtbaren Reiters auf den Standard setzen (#723).</summary>
    procedure ResetPage; override;
    procedure LoadFrom(const ASettings: TAtlasPluginSettings); override;
    procedure SaveTo(var ASettings: TAtlasPluginSettings);
    /// <summary>Zeigt die Einstellung AKey (Name der Plugin-Einstellung, #628): Reiter, ins Bild rollen, Fokus,
    /// Zeile fett. False, wenn die Seite den Schlüssel nicht kennt; ohne Fenster folgt es in CreateWnd.</summary>
    function Reveal(const AKey: string): Boolean; override;
    /// <summary>Zum Testen: Zahl der Reiter (Bereiche).</summary>
    function SheetCountForTests: Integer;
    /// <summary>Überschrift im Kopf (#1903: Name des Knotens, z. B. „Base“ oder „Tests“).</summary>
    procedure SetTitle(const ACaption: string);
    property ExperimentalBanner: TWinControl read FExperimentalBanner;
    property Filter: TAtlasChoiceBox read FFilter;
    /// <summary>Treffer der Suche in einem anderen Knoten: Einstellung (Name) und Modulschalter ('' = Base).
    /// </summary>
    property OnOpenSetting: TProc<string, string> read FOnOpenSetting write FOnOpenSetting;
    /// <summary>Suchfeld über dem Baum (#1884).</summary>
    property Search: TAtlasSettingsSearchBox read FSearch;
    property Symbol: TAtlasSymbolImage read FSymbol;
  end;

implementation

{$R *.dfm}

uses
  Atlas.Core.Settings.Transfer,
  Atlas.Core.Settings.Experimental,
  Atlas.Core.Settings.History,
  Atlas.Core.Settings.Groups,
  Atlas.UI.Settings.Page.Sheets,
  Atlas.UI.Settings.Page.Host,
  Atlas.UI.Settings.Page.Nodes,
  Atlas.UI.Settings.Page.Parts,
  Atlas.UI.Settings.Page.Sections,
  Atlas.UI.Settings.Page.General,
  Atlas.UI.Settings.Page.Transfer,
  Atlas.UI.Settings.Marks,
  Atlas.UI.Strings,
  Atlas.Core.Style.Symbol;

{ TAtlasSettingsPage }

constructor TAtlasSettingsPage.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Name := 'AtlasSettingsPage';
  Width := 480;
  // Die Reiter tragen den Inhalt; scrollt die Seite selbst, springt sie beim Reiterwechsel zum Fokus.
  AutoScroll := False;
  // Mit Reitern reicht die Höhe des längsten Reiters; höher, und die IDE scrollt ihren Bereich beim
  // Reiterwechsel zum Fokus (die Seite „springt“).
  Height := 440;
  // Kopf mit Symbol (#751) und Titel.
  AddHeader;
  AddExperimentalBanner;
  AddNavigation;
  TAtlasSettingsPageParts.Build(Self);
  // „Einstellungen dazu …“ am gezeichneten Element (#628) und an Bereichen der Willkommensseite (#767).
  BindControls;
  Part<TAtlasSettingsSectionsPart>.Build;
  AddFilterRow;
  BuildNodes;
  UpdateLocks;
  // Suche über die Einstellungen (#1884): Beschriftungen der Elemente und aktuelle Werte von der Seite.
  FSearch.OnLabel :=
    function(const AName: string): string
    begin
      Result := FMarks.TextOfName(AName);
    end;
  FSearch.OnSettings := CurrentSettings;
  FSearch.OnOpen := SearchOpen;
end;

procedure TAtlasSettingsPage.SearchOpen(AHit: TAtlasSettingHit);
begin
  if SameText(AHit.Module, Scope.Switch) and Reveal(AHit.Name) then
  begin
    Exit;
  end;
  if Assigned(FOnOpenSetting) then
  begin
    FOnOpenSetting(AHit.Name, AHit.Module);
  end;
end;

procedure TAtlasSettingsPage.AddHeader;
var
  mPanel: TWinControl;
  mTitle: TLabel;
begin
  mPanel := TAtlasSettingsRow.Create(Self);
  mPanel.Parent := Self;
  mPanel.Align := alTop;
  mPanel.Height := 40;
  FSymbol := TAtlasSymbolImage.Create(Self);
  FSymbol.Parent := mPanel;
  FSymbol.LogicalSize := TAtlasSymbol.cHeaderSize;
  FSymbol.Left := 4;
  FSymbol.Top := 4;
  mTitle := TLabel.Create(Self);
  mTitle.Parent := mPanel;
  mTitle.Left := 44;
  mTitle.Top := 12;
  mTitle.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsTitle);
  mTitle.Font.Style := [fsBold];
  FTitle := mTitle;
end;

procedure TAtlasSettingsPage.AddExperimentalBanner;
var
  mText: TLabel;
  mButton: TButton;
begin
  FExperimentalBanner := TAtlasSettingsRow.Create(Self);
  FExperimentalBanner.Parent := Self;
  FExperimentalBanner.Align := alTop;
  FExperimentalBanner.AlignWithMargins := True;
  FExperimentalBanner.Top := 50;
  FExperimentalBanner.Height := 28;
  FExperimentalBanner.Visible := False;
  mButton := TButton.Create(Self);
  mButton.Parent := FExperimentalBanner;
  mButton.Align := alRight;
  mButton.Width := 90;
  mButton.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsExperimentalAllow);
  mButton.OnClick := ExperimentalAllowClick;
  mText := TLabel.Create(Self);
  mText.Parent := FExperimentalBanner;
  mText.Align := alClient;
  mText.Layout := tlCenter;
  mText.WordWrap := True;
  mText.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsExperimentalOff);
end;

procedure TAtlasSettingsPage.AddFilterRow;
var
  mCaption: TLabel;
begin
  FFilterRow := TAtlasSettingsRow.Create(Self);
  FFilterRow.Parent := Self;
  FFilterRow.Align := alBottom;
  FFilterRow.AlignWithMargins := True;
  FFilterRow.Height := 26;
  mCaption := TLabel.Create(Self);
  mCaption.Parent := FFilterRow;
  mCaption.Left := 0;
  mCaption.Top := 5;
  mCaption.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsFilter);
  // Reihenfolge wie TAtlasSettingsFilter.
  FFilter := TAtlasChoiceBox.Create(Self);
  FFilter.Parent := FFilterRow;
  FFilter.Left := 60;
  FFilter.Top := 1;
  FFilter.Width := 180;
  FFilter.SetChoices([TAtlasStrings.Text(TAtlasTextId.SettingsFilterAll),
    TAtlasStrings.Text(TAtlasTextId.SettingsFilterModified),
    TAtlasStrings.Text(TAtlasTextId.SettingsFilterExperimental)]);
  FFilter.Choice := 0;
  FFilter.OnChange := FilterChange;
  FMarks.MarkExperimental(TAtlasExperimental.PluginNames(Catalog));
end;

procedure TAtlasSettingsPage.ExperimentalAllowClick(Sender: TObject);
begin
  // Wie ein Klick auf das Kontrollkästchen: Punkte und Hinweis folgen über die Bindung.
  Part<TAtlasSettingsGeneralPart>.ExperimentalEnabled.Checked := True;
end;

procedure TAtlasSettingsPage.FilterChange(Sender: TObject);
begin
  if (FFilter.Choice >= Ord(Low(TAtlasSettingsFilter))) and (FFilter.Choice <= Ord(High(TAtlasSettingsFilter))) then
  begin
    FMarks.ApplyFilter(TAtlasSettingsFilter(FFilter.Choice));
  end;
  // Knoten ohne Treffer fallen aus dem Baum (#890).
  if ListReady(FTree) then
  begin
    FillTree;
  end;
end;

procedure TAtlasSettingsPage.SetTitle(const ACaption: string);
begin
  FTitle.Caption := ACaption;
end;

function TAtlasSettingsPage.Reveal(const AKey: string): Boolean;
begin
  Result := ControlOf(AKey) <> nil;
  if not Result then
  begin
    Exit;
  end;
  if HandleAllocated then
  begin
    ApplyReveal(AKey);
  end
  else
  begin
    FPendingReveal := AKey;
  end;
end;

/// <summary>Rollt AControl in seinem Kasten ins Bild.</summary>
procedure ScrollToControl(AControl: TControl);
var
  mParent: TWinControl;
begin
  mParent := AControl.Parent;
  while (mParent <> nil) and not (mParent is TScrollBox) do
  begin
    mParent := mParent.Parent;
  end;
  if mParent is TScrollBox then
  begin
    TScrollBox(mParent).ScrollInView(AControl);
  end;
end;

/// <summary>Zeile hervorheben: Kontrollkästchen fett, sonst die Beschriftung der Zeile.</summary>
procedure HighlightRow(AControl: TControl);
var
  mChild: Integer;
begin
  if AControl is TCheckBox then
  begin
    TCheckBox(AControl).Font.Style := [fsBold];
    Exit;
  end;
  if AControl.Parent = nil then
  begin
    Exit;
  end;
  for mChild := 0 to AControl.Parent.ControlCount - 1 do
  begin
    if AControl.Parent.Controls[mChild] is TLabel then
    begin
      TLabel(AControl.Parent.Controls[mChild]).Font.Style := [fsBold];
    end;
  end;
end;

/// <summary>Fokus nur mit sichtbarer Form: CanFocus allein lässt eine noch verborgene Form durch („kann den Fokus
/// nicht erhalten“).</summary>
procedure FocusShown(AControl: TControl);
begin
  if (AControl is TWinControl) and TWinControl(AControl).CanFocus and (GetParentForm(AControl) <> nil) and
    GetParentForm(AControl).Visible then
  begin
    TWinControl(AControl).SetFocus;
  end;
end;

function TAtlasSettingsPage.RevealTarget(AControl: TControl): TControl;
var
  mNames: TArray<string>;
  mLock: TAtlasSettingsLock;
  mMaster: TControl;
begin
  // Gesperrt (#890): den Hauptschalter zeigen, der sie freigibt.
  Result := AControl;
  mNames := FMarks.NamesOf(AControl);
  if (Length(mNames) = 0) or (FGroups = nil) then
  begin
    Exit;
  end;
  mLock := LockOfName(mNames[0]);
  if mLock.Locked then
  begin
    mMaster := FMarks.ControlOfName(mLock.Master);
    if mMaster <> nil then
    begin
      Result := mMaster;
    end;
  end;
end;

procedure TAtlasSettingsPage.ApplyReveal(const AKey: string);
var
  mControl: TControl;
begin
  FPendingReveal := '';
  mControl := ControlOf(AKey);
  if mControl = nil then
  begin
    Exit;
  end;
  mControl := RevealTarget(mControl);
  // Knoten des Elements wählen, wie ein Klick im Baum links.
  SelectPage(PageOf(mControl));
  ScrollToControl(mControl);
  HighlightRow(mControl);
  FocusShown(mControl);
end;

// Art und Hauptbranch je Projekt (#1286): wie die Tabelle Projekte der Seite Issue-Tracker (#1261), dieselbe
// Auflösung (Atlas.Core.Projects.Matching).

// Serverzugang (#1287): nur auf Klick, Zustand aus der Sitzung.

procedure TAtlasSettingsPage.BindControls;
var
  mPart: TAtlasSettingsPagePart;
  mIndex: Integer;
begin
  for mPart in FParts do
  begin
    mPart.BindMarks;
  end;
  // Gebundene Elemente erst jetzt: Die Markierung übernimmt OnClick und Hint, die der Aufbau gesetzt hat.
  for mIndex := 0 to FBindings.Count - 1 do
  begin
    FMarks.Bind(FBindings.Item(mIndex).Control, [FBindings.Item(mIndex).Name]);
  end;
end;

function TAtlasSettingsPage.CurrentSettings: TAtlasPluginSettings;
begin
  Result := FWidths;
  SaveTo(Result);
end;

procedure TAtlasSettingsPage.RefreshMarks;
begin
  Part<TAtlasSettingsTransferPart>.ShowModified;
  FExperimentalBanner.Visible := FMarks.HasExperimental and
    not Part<TAtlasSettingsGeneralPart>.ExperimentalEnabled.Checked;
  UpdateLocks;
  // Geänderte Werte ändern sich mit jeder Eingabe; der Filter folgt, auch im Baum.
  if FMarks.Filter = sfModified then
  begin
    FMarks.ApplyFilter(sfModified);
    if ListReady(FTree) then
    begin
      FillTree;
    end;
  end;
end;

procedure TAtlasSettingsPage.ResetNames(const ANames: TArray<string>);
begin
  if Length(ANames) = 0 then
  begin
    Exit;
  end;
  LoadFrom(TAtlasSettingsTransfer.ResetNames(Catalog, CurrentSettings, ANames));
end;

procedure TAtlasSettingsPage.ResetPage;
var
  mCurrent, mIndex: Integer;
  mNames: TArray<string>;
begin
  // Ohne Fenster hängen die Reiter noch nicht am PageControl.
  mCurrent := ActiveNode;
  if mCurrent < 0 then
  begin
    Exit;
  end;
  // Unterpunkt: nur seine Einstellungen; Hauptknoten: der ganze Bereich mit allen Unterpunkten (#890).
  if FNodePages[mCurrent].Node <> '' then
  begin
    mNames := FMarks.NamesIn(FNodePages[mCurrent].Box);
  end
  else
  begin
    mNames := nil;
    for mIndex := 0 to High(FNodePages) do
    begin
      if FNodePages[mIndex].Area = FNodePages[mCurrent].Area then
      begin
        mNames := mNames + FMarks.NamesIn(FNodePages[mIndex].Box);
      end;
    end;
  end;
  ResetNames(mNames);
end;

procedure TAtlasSettingsPage.CreateWnd;
var
  mPage: TAtlasSettingsNodePage;
  mPart: TAtlasSettingsPagePart;
begin
  inherited CreateWnd;
  // Je Knoten ein Reiter, in der Reihenfolge des Baums.
  for mPage in FNodePages do
  begin
    if mPage.Sheet.PageControl = nil then
    begin
      mPage.Sheet.PageControl := FPages;
      mPage.Sheet.TabVisible := False;
    end;
  end;
  // Der Baum braucht ein Fenster für seine Knoten (wie die Reiter); zeigt die zuletzt gewählte Seite.
  FillTree;
  // Listen der Teile brauchen ein Fenster; vorher bleiben sie leer.
  for mPart in FParts do
  begin
    mPart.WindowReady;
  end;
  // Gewünschte Einstellung (#628) erst mit Fenster zeigen.
  if FPendingReveal <> '' then
  begin
    ApplyReveal(FPendingReveal);
  end;
end;


// Prüfregeln (#909).


procedure TAtlasSettingsPage.LoadFrom(const ASettings: TAtlasPluginSettings);
begin
  // Während des Ladens lösen die Elemente keine Neuberechnung der Punkte aus.
  FMarks.BeginLoad;
  try
    LoadControls(ASettings);
  finally
    FMarks.EndLoad;
  end;
  RefreshMarks;
end;

procedure TAtlasSettingsPage.LoadControls(const ASettings: TAtlasPluginSettings);
var
  mPart: TAtlasSettingsPagePart;
begin
  FWidths := ASettings;
  FSearch.SetAvailable(ASettings.SettingsSearch);
  FBindings.Load(TAtlasMemorySettingsStore.FromSettings(ASettings));
  for mPart in FParts do
  begin
    mPart.Load(ASettings);
  end;
end;

procedure TAtlasSettingsPage.SaveTo(var ASettings: TAtlasPluginSettings);
var
  mPart: TAtlasSettingsPagePart;
  mStore: IAtlasMemorySettingsStore;
begin
  mStore := TAtlasMemorySettingsStore.FromSettings(ASettings);
  FBindings.Save(mStore);
  ASettings.Load(mStore);
  for mPart in FParts do
  begin
    mPart.Save(ASettings);
  end;
  ASettings.Normalize;
end;


function TAtlasSettingsPage.SheetCountForTests: Integer;
begin
  Result := Length(FSheets);
end;

end.
