unit Atlas.UI.Welcome.SettingsSection;

// Abschnitt „Willkommensseite“ des Moduls im Optionsdialog (#1456, ADR 0017
// Entscheidung 3; vorher Teil von Atlas.UI.Settings.Page). Die Seite von Base
// baut ihn über IAtlasSettingsSectionHost in den Bereich „welcome“, unter den
// Modulschalter, der bei Base bleibt. Schalter, Zahlen, Texte und Auswahlen
// hängen an ihrem Schlüssel und lädt und speichert die Seite selbst. Eigene
// Zeilen liest und schreibt der Abschnitt in Load und Save:
// - Layout der IDE („atlas“/„off“ als Häkchen), die drei Tasten als Text wie
//   im Menü, Reihen des Projektverlaufs und Knöpfe der Schnellaktionen als
//   Häkchen je Eintrag, Programm der Konsole bereinigt.
// - Benannte Layouts (#767): TAtlasWelcomeSettingsLayouts.
// - Knöpfe ohne Schlüssel: Weg zur Seite Issue-Tracker, „Zählung
//   zurücksetzen“ und „Gesperrte Tipps wieder zeigen“ (#757, über Hooks; ohne
//   Haken nichts), Ordnerauswahl der Hilfe.
// Close gibt eigene Steuerelemente und Haken frei; danach erreicht den
// Abschnitt nichts mehr (Regel 3).

interface

uses
  Atlas.UI.Welcome.Strings,
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Atlas.Core.Settings.Contract,
  Atlas.UI.Settings.Contract,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Welcome.QuickActions,
  Atlas.UI.Welcome.SettingsLayouts;

type
  /// <summary>Haken des Abschnitts zur IDE und die Knöpfe, die sie auslösen; nil = Knopf ohne Wirkung bzw. Dialog
  /// von Windows.</summary>
  TAtlasWelcomeSettingsHooks = class
  private
    FOnResetUsage: TProc;
    FOnUnblockTips: TProc;
    FOnBrowseFolder: TFunc<string, string>;
    FHost: IAtlasSettingsSectionHost;
    FFolder: TEdit;
    function BrowseFolder(const AFolder: string): string;
  public
    /// <summary>Seite und Ordnerfeld der Hilfe für die Knöpfe; Detach beim Schließen.</summary>
    procedure Attach(const AHost: IAtlasSettingsSectionHost; AFolder: TEdit);
    procedure Detach;
    /// <summary>„Meine Issues“: Hauptknoten der Seite Issue-Tracker, ohne Modul Tracker dessen Schalter.</summary>
    procedure IssuesLinkClick(Sender: TObject);
    /// <summary>Ruft OnResetUsage bzw. OnUnblockTips; danach ist der Knopf bis zum nächsten Öffnen gesperrt.
    /// </summary>
    procedure ResetUsageClick(Sender: TObject);
    procedure UnblockTipsClick(Sender: TObject);
    procedure HelpFolderBrowseClick(Sender: TObject);
    /// <summary>„Zählung zurücksetzen“ (#757).</summary>
    property OnResetUsage: TProc read FOnResetUsage write FOnResetUsage;
    /// <summary>„Gesperrte Tipps wieder zeigen“ (#757).</summary>
    property OnUnblockTips: TProc read FOnUnblockTips write FOnUnblockTips;
    /// <summary>Ordner für die ZIP der Hilfe wählen, Vorgabe der bisherige; '' bei Abbruch. nil = Ordnerauswahl von
    /// Windows.</summary>
    property OnBrowseFolder: TFunc<string, string> read FOnBrowseFolder write FOnBrowseFolder;
  end;

  /// <summary>Start, Layout, Kopf, Suche und „Neu in Atlas“.</summary>
  TAtlasWelcomeStartView = record
    IdePage: TCheckBox;
    Layout: TCheckBox;
    OpenOnStart: TCheckBox;
    OpenWhenNoProject: TCheckBox;
    CustomLayout: TCheckBox;
    Columns: TEdit;
    Header: TCheckBox;
    Greeting: TCheckBox;
    Search: TCheckBox;
    SearchSymbols: TCheckBox;
    SearchKey: TEdit;
    WhatsNew: TAtlasChoiceBox;
  end;

  /// <summary>Bereiche Weiterarbeiten, Projekte, Projektverlauf, Testergebnisse, Meine Issues und Sprint.</summary>
  TAtlasWelcomeTilesView = record
    Continue: TCheckBox;
    ContinueCount: TEdit;
    ContinueIncoming: TCheckBox;
    ContinueFetch: TCheckBox;
    Saved: TCheckBox;
    Projects: TCheckBox;
    MaxProjects: TEdit;
    RefreshVcs: TCheckBox;
    Trends: TCheckBox;
    TrendsPoints: TEdit;
    TrendsSeries: array[TAtlasTrendSeries] of TCheckBox;
    Tests: TCheckBox;
    TestsMaxFailures: TEdit;
    TestsCi: TCheckBox;
    TestsCiProvider: TAtlasChoiceBox;
    TestsCiInterval: TEdit;
    TestsCiNotify: TCheckBox;
    CiLogin: TCheckBox;
    Issues: TCheckBox;
    IssuesLink: TButton;
    Sprint: TCheckBox;
  end;

  /// <summary>Schnellaktionen, Nicht gesichert, Zustand, Atlas entdecken, Hilfe und Einrichten.</summary>
  TAtlasWelcomeMoreView = record
    QuickActions: TCheckBox;
    QuickActionsItems: array[TAtlasQuickAction] of TCheckBox;
    QuickActionsConsole: TEdit;
    QuickActionsBuildKey: TEdit;
    QuickActionsTestKey: TEdit;
    Unsaved: TCheckBox;
    UnsavedMinAge: TEdit;
    UnsavedWarn: TEdit;
    UnsavedAlert: TEdit;
    UnsavedHideClean: TCheckBox;
    StatusTile: TCheckBox;
    StatusTileOnlyProblems: TCheckBox;
    Discover: TCheckBox;
    TipsUsageTracking: TCheckBox;
    ResetUsage: TButton;
    UnblockTips: TButton;
    Help: TCheckBox;
    HelpReportUrl: TEdit;
    HelpReportFolder: TEdit;
    HelpFolderBrowse: TButton;
    ProjectSetup: TCheckBox;
    NewFromTemplate: TCheckBox;
  end;

  TAtlasWelcomeSettingsSection = class(TInterfacedObject, IAtlasSettingsSection)
  public const
    cOwnerId = 'atlas.welcome';
    cAreaId = 'welcome';
  private
    FHost: IAtlasSettingsSectionHost;
    FOwner: TComponent;
    FHooks: TAtlasWelcomeSettingsHooks;
    FLayouts: TAtlasWelcomeSettingsLayouts;
    FStart: TAtlasWelcomeStartView;
    FTiles: TAtlasWelcomeTilesView;
    FMore: TAtlasWelcomeMoreView;
    FFieldLeft: Integer;
    FClosed: Boolean;
    function Check(const AKey: string; AText: TAtlasWelcomeTextId): TCheckBox;
    function Number(const AKey: string; AText: TAtlasWelcomeTextId): TEdit;
    function Line(const AKey: string; AText: TAtlasWelcomeTextId): TEdit;
    function OwnCheck(const AKey, ACaption: string): TCheckBox;
    function KeyEdit(const AKey, ACaption: string): TEdit;
    function AddButton(AParent: TWinControl; ALeft, AWidth: Integer; const ACaption: string;
      AClick: TNotifyEvent): TButton;
    procedure BuildStart;
    procedure BuildContinue;
    procedure BuildTests;
    procedure BuildQuickActions;
    procedure BuildMore;
    procedure BuildDiscover;
    procedure BuildHelp;
    procedure TrackLayouts;
  public
    constructor Create;
    destructor Destroy; override;
    { IAtlasSettingsSection }
    function OwnerId: string;
    function AreaId: string;
    procedure Build(const AHost: IAtlasSettingsSectionHost);
    procedure Load(const AValues: IAtlasSettingsValues);
    procedure Save(const AValues: IAtlasSettingsValues);
    procedure WindowReady;
    function Show(const AKey, AArgument: string): Boolean;
    procedure Close;
    property Closed: Boolean read FClosed;
    property Hooks: TAtlasWelcomeSettingsHooks read FHooks;
    property Layouts: TAtlasWelcomeSettingsLayouts read FLayouts;
    property Start: TAtlasWelcomeStartView read FStart;
    property Tiles: TAtlasWelcomeTilesView read FTiles;
    property More: TAtlasWelcomeMoreView read FMore;
  end;

implementation

uses
  System.Generics.Collections,
  Vcl.Menus,
  Vcl.Dialogs,
  Atlas.Core.Welcome.Trends,
  Atlas.UI.Strings,
  Atlas.UI.Welcome.QuickActions,
  Atlas.UI.Welcome.Trends;

const
  cRowHeight = 26;
  cButtonRow = 32;
  cLabelTop = 5;
  cControlTop = 1;
  cButtonTop = 3;
  cKeyWidth = 140;
  cCheckWidth = 400;
  cBrowseWidth = 30;
  cBrowseGap = 6;
  cLayoutKey = 'welcomePage.layout';
  cSearchKey = 'welcomePage.search.key';
  cSeriesKey = 'welcomePage.trends.series';
  cItemsKey = 'welcomePage.quickActions.items';
  cConsoleKey = 'welcomePage.quickActions.console';
  cBuildKey = 'welcomePage.quickActions.buildKey';
  cTestKey = 'welcomePage.quickActions.testKey';
  cIssuesTrackerKey = 'issues.tracker';
  cIssuesEnabledKey = 'issues.enabled';

{ TAtlasWelcomeSettingsHooks }

procedure TAtlasWelcomeSettingsHooks.Attach(const AHost: IAtlasSettingsSectionHost; AFolder: TEdit);
begin
  FHost := AHost;
  FFolder := AFolder;
end;

procedure TAtlasWelcomeSettingsHooks.Detach;
begin
  FHost := nil;
  FFolder := nil;
end;

procedure TAtlasWelcomeSettingsHooks.IssuesLinkClick(Sender: TObject);
begin
  // Hauptknoten der Seite Issue-Tracker: dort steht der Anbieter. Ohne Modul Tracker bleibt dessen Schalter.
  if (FHost <> nil) and not FHost.Reveal(cIssuesTrackerKey) then
  begin
    FHost.Reveal(cIssuesEnabledKey);
  end;
end;

procedure TAtlasWelcomeSettingsHooks.ResetUsageClick(Sender: TObject);
begin
  if Assigned(FOnResetUsage) then
  begin
    FOnResetUsage();
  end;
  if (FHost <> nil) and (Sender is TControl) then
  begin
    FHost.Allow(TControl(Sender), False);
  end;
end;

procedure TAtlasWelcomeSettingsHooks.UnblockTipsClick(Sender: TObject);
begin
  if Assigned(FOnUnblockTips) then
  begin
    FOnUnblockTips();
  end;
  if (FHost <> nil) and (Sender is TControl) then
  begin
    FHost.Allow(TControl(Sender), False);
  end;
end;

function TAtlasWelcomeSettingsHooks.BrowseFolder(const AFolder: string): string;
var
  mDialog: TFileOpenDialog;
begin
  Result := '';
  mDialog := TFileOpenDialog.Create(nil);
  try
    mDialog.Options := mDialog.Options + [fdoPickFolders, fdoPathMustExist];
    if AFolder <> '' then
    begin
      mDialog.DefaultFolder := AFolder;
    end;
    if mDialog.Execute then
    begin
      Result := mDialog.FileName;
    end;
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasWelcomeSettingsHooks.HelpFolderBrowseClick(Sender: TObject);
var
  mFolder: string;
begin
  if FFolder = nil then
  begin
    Exit;
  end;
  if Assigned(FOnBrowseFolder) then
  begin
    mFolder := FOnBrowseFolder(FFolder.Text);
  end
  else
  begin
    mFolder := BrowseFolder(FFolder.Text);
  end;
  if mFolder <> '' then
  begin
    FFolder.Text := mFolder;
  end;
end;

{ TAtlasWelcomeSettingsSection }

constructor TAtlasWelcomeSettingsSection.Create;
begin
  inherited Create;
  FHooks := TAtlasWelcomeSettingsHooks.Create;
  FLayouts := TAtlasWelcomeSettingsLayouts.Create;
end;

destructor TAtlasWelcomeSettingsSection.Destroy;
begin
  Close;
  FreeAndNil(FLayouts);
  inherited Destroy;
end;

function TAtlasWelcomeSettingsSection.OwnerId: string;
begin
  Result := cOwnerId;
end;

function TAtlasWelcomeSettingsSection.AreaId: string;
begin
  Result := cAreaId;
end;

function TAtlasWelcomeSettingsSection.Check(const AKey: string; AText: TAtlasWelcomeTextId): TCheckBox;
begin
  Result := FHost.AddSwitch(AKey, TAtlasWelcomeStrings.Text(AText)) as TCheckBox;
end;

function TAtlasWelcomeSettingsSection.Number(const AKey: string; AText: TAtlasWelcomeTextId): TEdit;
begin
  Result := FHost.AddNumber(AKey, TAtlasWelcomeStrings.Text(AText)) as TEdit;
end;

function TAtlasWelcomeSettingsSection.Line(const AKey: string; AText: TAtlasWelcomeTextId): TEdit;
begin
  Result := FHost.AddText(AKey, TAtlasWelcomeStrings.Text(AText)) as TEdit;
end;

function TAtlasWelcomeSettingsSection.OwnCheck(const AKey, ACaption: string): TCheckBox;
var
  mRow: TWinControl;
begin
  mRow := FHost.AddRow(cRowHeight, TArray<string>.Create(AKey));
  Result := TCheckBox.Create(FOwner);
  Result.Parent := mRow;
  Result.Caption := ACaption;
  Result.Left := 0;
  Result.Top := cButtonTop;
  Result.Width := cCheckWidth;
  Result.Anchors := [akLeft, akTop, akRight];
end;

function TAtlasWelcomeSettingsSection.KeyEdit(const AKey, ACaption: string): TEdit;
var
  mRow: TWinControl;
  mCaption: TLabel;
begin
  // Als Text wie im Menü („Strg+Umschalt+P“); leer = keine Taste.
  mRow := FHost.AddRow(cRowHeight, TArray<string>.Create(AKey));
  mCaption := TLabel.Create(FOwner);
  mCaption.Parent := mRow;
  mCaption.Caption := StringReplace(ACaption, '…', '', []);
  mCaption.Left := 0;
  mCaption.Top := cLabelTop;
  Result := TEdit.Create(FOwner);
  Result.Parent := mRow;
  Result.Left := FFieldLeft;
  Result.Top := cControlTop;
  Result.Width := cKeyWidth;
end;

function TAtlasWelcomeSettingsSection.AddButton(AParent: TWinControl; ALeft, AWidth: Integer;
  const ACaption: string; AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(FOwner);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Left := ALeft;
  Result.Top := cButtonTop;
  Result.Width := AWidth;
  Result.OnClick := AClick;
end;

procedure TAtlasWelcomeSettingsSection.Build(const AHost: IAtlasSettingsSectionHost);
begin
  if FClosed or (FOwner <> nil) then
  begin
    Exit;
  end;
  FHost := AHost;
  FOwner := TComponent.Create(nil);
  BuildStart;
  BuildContinue;
  BuildTests;
  BuildQuickActions;
  BuildMore;
  FHooks.Attach(AHost, FMore.HelpReportFolder);
  TrackLayouts;
end;

procedure TAtlasWelcomeSettingsSection.BuildStart;
begin
  // Willkommensseite der IDE und Fenster „Atlas-Start“ unabhängig (#761); Atlas-Layout der IDE (#753).
  FStart.IdePage := Check('welcomePage.ideWelcomePage', TAtlasWelcomeTextId.SettingsWelcomeIdePage);
  FStart.Layout := OwnCheck(cLayoutKey, TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.SettingsWelcomeLayout));
  FStart.OpenOnStart := Check('welcomePage.openOnStart', TAtlasWelcomeTextId.SettingsWelcomeOpenOnStart);
  FStart.OpenWhenNoProject := Check('welcomePage.openWhenNoProject',
    TAtlasWelcomeTextId.SettingsWelcomeOpenWhenNoProject);
  // Freies Layout (#767): Bearbeitungsmodus „Seite anpassen“, Spalten, benannte Layouts.
  FStart.CustomLayout := Check('welcomePage.customLayout', TAtlasWelcomeTextId.SettingsWelcomeCustomLayout);
  FStart.Columns := Number(TAtlasWelcomeSettingsLayouts.cColumnsKey, TAtlasWelcomeTextId.SettingsWelcomeColumns);
  FFieldLeft := FStart.Columns.Left;
  FLayouts.Build(FHost, FOwner, FStart.Columns, FFieldLeft);
  FStart.Header := Check('welcomePage.header', TAtlasWelcomeTextId.SettingsWelcomeHeader);
  FStart.Greeting := Check('welcomePage.greeting', TAtlasWelcomeTextId.SettingsWelcomeGreeting);
  FStart.Search := Check('welcomePage.search', TAtlasWelcomeTextId.SettingsWelcomeSearch);
  FStart.SearchSymbols := Check('welcomePage.search.symbols', TAtlasWelcomeTextId.SettingsWelcomeSearchSymbols);
  FStart.SearchKey := KeyEdit(cSearchKey, TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeSearchKey));
  // Karte „Neu in Atlas“ (#756); Reihenfolge wie TAtlasWhatsNewMode: off, afterUpdate, always.
  FStart.WhatsNew := FHost.AddChoice('welcomePage.whatsNew',
    TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.SettingsWelcomeWhatsNew),
    TArray<string>.Create(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.SettingsWelcomeWhatsNewOff),
    TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.SettingsWelcomeWhatsNewAfterUpdate),
    TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.SettingsWelcomeWhatsNewAlways)),
    TArray<string>.Create('off', 'afterUpdate', 'always')) as TAtlasChoiceBox;
end;

procedure TAtlasWelcomeSettingsSection.BuildContinue;
var
  mSeries: TAtlasTrendSeries;
begin
  // Bereich „Weiterarbeiten“ (#755) mit Reiter „Gemerkt“.
  FTiles.Continue := Check('welcomePage.continue', TAtlasWelcomeTextId.SettingsWelcomeContinue);
  FTiles.ContinueCount := Number('welcomePage.continue.count', TAtlasWelcomeTextId.SettingsWelcomeContinueCount);
  FTiles.ContinueIncoming := Check('welcomePage.continue.incoming',
    TAtlasWelcomeTextId.SettingsWelcomeContinueIncoming);
  FTiles.ContinueFetch := Check('welcomePage.continue.fetch', TAtlasWelcomeTextId.SettingsWelcomeContinueFetch);
  FTiles.Saved := Check('welcomePage.saved', TAtlasWelcomeTextId.SettingsWelcomeSaved);
  // Bereich „Projekte“ (#592).
  FTiles.Projects := Check('welcomePage.projectStatus', TAtlasWelcomeTextId.SettingsWelcomeProjects);
  FTiles.MaxProjects := Number('welcomePage.maxProjects', TAtlasWelcomeTextId.SettingsWelcomeMaxProjects);
  FTiles.RefreshVcs := Check('welcomePage.refreshVcs', TAtlasWelcomeTextId.SettingsWelcomeRefreshVcs);
  // Bereich „Projektverlauf“ (#758): Schalter, Anzahl der Builds und je Reihe ein Häkchen.
  FTiles.Trends := Check('welcomePage.trends', TAtlasWelcomeTextId.SettingsWelcomeTrends);
  FTiles.TrendsPoints := Number('welcomePage.trends.points', TAtlasWelcomeTextId.SettingsWelcomeTrendsPoints);
  for mSeries := Low(TAtlasTrendSeries) to High(TAtlasTrendSeries) do
  begin
    FTiles.TrendsSeries[mSeries] := OwnCheck(cSeriesKey,
      TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.SettingsWelcomeTrendsSeries,
      [TAtlasWelcomeTrendsFrame.SeriesTitle(mSeries)]));
  end;
end;

procedure TAtlasWelcomeSettingsSection.BuildTests;
var
  mRow: TWinControl;
begin
  // Bereich „Testergebnisse“ (#763): lokal und vom Build-Server; Anbieter bisher nur Jenkins.
  FTiles.Tests := Check('welcomePage.tests', TAtlasWelcomeTextId.SettingsWelcomeTests);
  FTiles.TestsMaxFailures := Number('welcomePage.tests.maxFailures',
    TAtlasWelcomeTextId.SettingsWelcomeTestsMaxFailures);
  FTiles.TestsCi := Check('welcomePage.tests.ci', TAtlasWelcomeTextId.SettingsWelcomeTestsCi);
  FTiles.TestsCiProvider := FHost.AddChoice('welcomePage.tests.ci.provider',
    TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.SettingsWelcomeTestsCiProvider),
    TArray<string>.Create(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.SettingsWelcomeTestsCiJenkins)),
    TArray<string>.Create('jenkins')) as TAtlasChoiceBox;
  FTiles.TestsCiInterval := Number('welcomePage.tests.ci.intervalMinutes',
    TAtlasWelcomeTextId.SettingsWelcomeTestsCiInterval);
  FTiles.TestsCiNotify := Check('welcomePage.tests.ci.notify', TAtlasWelcomeTextId.SettingsWelcomeTestsCiNotify);
  FTiles.CiLogin := Check('welcomePage.tests.ci.login', TAtlasWelcomeTextId.SettingsCiLogin);
  // Meine Issues (#765): nur der Bereich; Tracker, Abfrage und Muster stehen auf der Seite Issue-Tracker (#1280).
  FTiles.Issues := Check('welcomePage.issues', TAtlasWelcomeTextId.SettingsWelcomeIssues);
  mRow := FHost.AddRow(cButtonRow, nil);
  FTiles.IssuesLink := AddButton(mRow, 0, 200, TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.SettingsWelcomeIssuesLink),
    FHooks.IssuesLinkClick);
  FHost.Attach(mRow, FTiles.Issues);
  // Sprint-Kachel (#1277): nur der Bereich; Burndown und Vergleich auf der Seite Issue-Tracker.
  FTiles.Sprint := Check('welcomePage.sprint', TAtlasWelcomeTextId.SettingsWelcomeSprint);
end;

procedure TAtlasWelcomeSettingsSection.BuildQuickActions;
var
  mAction: TAtlasQuickAction;
begin
  // Schnellaktionen je Projekt (#764): Schalter, je Knopf ein Häkchen, Programm für „Konsole“, zwei Tasten.
  FMore.QuickActions := Check('welcomePage.quickActions', TAtlasWelcomeTextId.SettingsWelcomeQuickActions);
  for mAction := Low(TAtlasQuickAction) to High(TAtlasQuickAction) do
  begin
    FMore.QuickActionsItems[mAction] := OwnCheck(cItemsKey,
      TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.SettingsWelcomeQuickActionsItem, [QuickActionTitle(mAction)]));
  end;
  FMore.QuickActionsConsole := Line(cConsoleKey, TAtlasWelcomeTextId.SettingsWelcomeQuickActionsConsole);
  FMore.QuickActionsBuildKey := KeyEdit(cBuildKey,
    TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeQuickActionsBuildKey));
  FMore.QuickActionsTestKey := KeyEdit(cTestKey,
    TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeQuickActionsTestKey));
end;

procedure TAtlasWelcomeSettingsSection.BuildMore;
begin
  // Bereich „Nicht gesichert“ (#762).
  FMore.Unsaved := Check('welcomePage.unsaved', TAtlasWelcomeTextId.SettingsWelcomeUnsaved);
  FMore.UnsavedMinAge := Number('welcomePage.unsaved.minAgeHours', TAtlasWelcomeTextId.SettingsWelcomeUnsavedMinAge);
  FMore.UnsavedWarn := Number('welcomePage.unsaved.warnHours', TAtlasWelcomeTextId.SettingsWelcomeUnsavedWarn);
  FMore.UnsavedAlert := Number('welcomePage.unsaved.alertHours', TAtlasWelcomeTextId.SettingsWelcomeUnsavedAlert);
  FMore.UnsavedHideClean := Check('welcomePage.unsaved.hideWhenClean',
    TAtlasWelcomeTextId.SettingsWelcomeUnsavedHideClean);
  // Zustandskachel „Atlas“ (#754).
  FMore.StatusTile := Check('welcomePage.statusTile', TAtlasWelcomeTextId.SettingsWelcomeStatusTile);
  FMore.StatusTileOnlyProblems := Check('welcomePage.statusTile.onlyProblems',
    TAtlasWelcomeTextId.SettingsWelcomeStatusTileOnlyProblems);
  BuildDiscover;
  BuildHelp;
  // Karte „Projekt für Atlas einrichten“ und Knöpfe „Neu mit Atlas“ (#759).
  FMore.ProjectSetup := Check('welcomePage.projectSetup', TAtlasWelcomeTextId.SettingsWelcomeProjectSetup);
  FMore.NewFromTemplate := Check('welcomePage.newFromTemplate', TAtlasWelcomeTextId.SettingsWelcomeNewFromTemplate);
end;

procedure TAtlasWelcomeSettingsSection.BuildDiscover;
var
  mRow: TWinControl;
begin
  // Karte „Atlas entdecken“ und Nutzungszählung (#757); die Knöpfe sind nur mit dem Schalter frei (#890).
  FMore.Discover := Check('welcomePage.discover', TAtlasWelcomeTextId.SettingsWelcomeDiscover);
  FMore.TipsUsageTracking := Check('tips.usageTracking', TAtlasWelcomeTextId.SettingsTipsUsageTracking);
  mRow := FHost.AddRow(cButtonRow, nil);
  FMore.ResetUsage := AddButton(mRow, 0, 180, TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.SettingsResetUsage),
    FHooks.ResetUsageClick);
  FMore.UnblockTips := AddButton(mRow, 190, 200, TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.SettingsUnblockTips),
    FHooks.UnblockTipsClick);
  FHost.Attach(mRow, FMore.Discover);
end;

procedure TAtlasWelcomeSettingsSection.BuildHelp;
begin
  // Bereich „Hilfe und Rückmeldung“ (#766): Schalter, Ziel der Issue-Seite, Ordner der ZIP (leer = Desktop).
  FMore.Help := Check('welcomePage.help', TAtlasWelcomeTextId.SettingsWelcomeHelp);
  FMore.HelpReportUrl := Line('welcomePage.help.reportUrl', TAtlasWelcomeTextId.SettingsWelcomeHelpReportUrl);
  FMore.HelpReportFolder := Line('welcomePage.help.reportFolder',
    TAtlasWelcomeTextId.SettingsWelcomeHelpReportFolder);
  FMore.HelpReportFolder.TextHint := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.SettingsWelcomeHelpDesktop);
  FMore.HelpReportFolder.Width := FMore.HelpReportFolder.Width - cBrowseWidth - cBrowseGap;
  FMore.HelpFolderBrowse := AddButton(FMore.HelpReportFolder.Parent,
    FMore.HelpReportFolder.Left + FMore.HelpReportFolder.Width + cBrowseGap, cBrowseWidth, '…',
    FHooks.HelpFolderBrowseClick);
  FMore.HelpFolderBrowse.Top := 0;
  FMore.HelpFolderBrowse.Anchors := [akTop, akRight];
end;

procedure TAtlasWelcomeSettingsSection.TrackLayouts;
var
  mSwitches: TArray<TAtlasWelcomeSwitch>;

  procedure Add(const ASetting: string; ACheck: TCheckBox);
  var
    mSwitch: TAtlasWelcomeSwitch;
  begin
    mSwitch.Setting := ASetting;
    mSwitch.Check := ACheck;
    mSwitches := mSwitches + [mSwitch];
  end;

begin
  // Namen wie im Katalog von TAtlasWelcomeCustomizing.
  mSwitches := nil;
  Add('WelcomePageContinue', FTiles.Continue);
  Add('WelcomePageProjectStatus', FTiles.Projects);
  Add('WelcomePageTrends', FTiles.Trends);
  Add('WelcomePageTests', FTiles.Tests);
  Add('WelcomePageStatusTile', FMore.StatusTile);
  Add('WelcomePageUnsaved', FMore.Unsaved);
  Add('WelcomePageDiscover', FMore.Discover);
  Add('WelcomePageProjectSetup', FMore.ProjectSetup);
  Add('WelcomePageIssues', FTiles.Issues);
  Add('WelcomePageSprint', FTiles.Sprint);
  Add('WelcomePageHelp', FMore.Help);
  FLayouts.Track(mSwitches, FStart.WhatsNew);
end;

procedure TAtlasWelcomeSettingsSection.Load(const AValues: IAtlasSettingsValues);
var
  mSeries: TAtlasTrendSeries;
  mShown: TAtlasTrendSeriesList;
  mItems: TAtlasQuickActions;
  mAction: TAtlasQuickAction;
begin
  if FClosed or (FOwner = nil) then
  begin
    Exit;
  end;
  FStart.Layout.Checked := AValues.ReadString(cLayoutKey) = 'atlas';
  FStart.SearchKey.Text := ShortCutToText(TShortCut(AValues.ReadInteger(cSearchKey)));
  mShown := TAtlasWelcomeTrends.ParseSeries(AValues.ReadString(cSeriesKey));
  for mSeries := Low(TAtlasTrendSeries) to High(TAtlasTrendSeries) do
  begin
    FTiles.TrendsSeries[mSeries].Checked := TArray.IndexOf<TAtlasTrendSeries>(mShown, mSeries) >= 0;
  end;
  mItems := TAtlasWelcomeQuickActions.ParseItems(AValues.ReadString(cItemsKey));
  for mAction := Low(TAtlasQuickAction) to High(TAtlasQuickAction) do
  begin
    FMore.QuickActionsItems[mAction].Checked := mAction in mItems;
  end;
  FMore.QuickActionsBuildKey.Text := ShortCutToText(TShortCut(AValues.ReadInteger(cBuildKey)));
  FMore.QuickActionsTestKey.Text := ShortCutToText(TShortCut(AValues.ReadInteger(cTestKey)));
  FLayouts.Load(AValues);
end;

procedure TAtlasWelcomeSettingsSection.Save(const AValues: IAtlasSettingsValues);
var
  mSeries: TAtlasTrendSeries;
  mShown: TAtlasTrendSeriesList;
  mItems: TAtlasQuickActions;
  mAction: TAtlasQuickAction;
begin
  if FClosed or (FOwner = nil) then
  begin
    Exit;
  end;
  if FStart.Layout.Checked then
  begin
    AValues.WriteString(cLayoutKey, 'atlas');
  end
  else
  begin
    AValues.WriteString(cLayoutKey, 'off');
  end;
  AValues.WriteInteger(cSearchKey, Integer(TextToShortCut(Trim(FStart.SearchKey.Text))));
  mShown := nil;
  for mSeries := Low(TAtlasTrendSeries) to High(TAtlasTrendSeries) do
  begin
    if FTiles.TrendsSeries[mSeries].Checked then
    begin
      mShown := mShown + [mSeries];
    end;
  end;
  AValues.WriteString(cSeriesKey, TAtlasWelcomeTrends.SeriesText(mShown));
  mItems := [];
  for mAction := Low(TAtlasQuickAction) to High(TAtlasQuickAction) do
  begin
    if FMore.QuickActionsItems[mAction].Checked then
    begin
      Include(mItems, mAction);
    end;
  end;
  AValues.WriteString(cItemsKey, TAtlasWelcomeQuickActions.ItemsText(mItems));
  AValues.WriteString(cConsoleKey, TAtlasWelcomeQuickActions.NormalizedConsole(FMore.QuickActionsConsole.Text));
  AValues.WriteInteger(cBuildKey, Integer(TextToShortCut(Trim(FMore.QuickActionsBuildKey.Text))));
  AValues.WriteInteger(cTestKey, Integer(TextToShortCut(Trim(FMore.QuickActionsTestKey.Text))));
  FLayouts.Save(AValues);
end;

procedure TAtlasWelcomeSettingsSection.WindowReady;
begin
  // Keine Listen: nichts nachzuholen.
end;

function TAtlasWelcomeSettingsSection.Show(const AKey, AArgument: string): Boolean;
begin
  // „Einstellung zeigen“ findet die Seite über die gebundenen Schlüssel selbst; keine Vorgaben.
  Result := False;
end;

procedure TAtlasWelcomeSettingsSection.Close;
begin
  if FClosed then
  begin
    Exit;
  end;
  FClosed := True;
  if FLayouts <> nil then
  begin
    FLayouts.Close;
  end;
  FHost := nil;
  FHooks.Detach;
  // Die Zeilen und gebundenen Felder gehören der Seite; die eigenen Elemente darin dem Abschnitt.
  FreeAndNil(FOwner);
  FStart := Default(TAtlasWelcomeStartView);
  FTiles := Default(TAtlasWelcomeTilesView);
  FMore := Default(TAtlasWelcomeMoreView);
  FreeAndNil(FHooks);
end;

end.
