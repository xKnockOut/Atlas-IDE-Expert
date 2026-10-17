unit Atlas.UI.Welcome.Tests;

// Oberfläche der Atlas-Willkommensseite (#753): Texte im Kopf (Grußzeile,
// Kurzstatus, Tausendertrennzeichen je Sprache), Fabriken der Bereiche und
// der Frame „Atlas“ mit Kopf und Bereichen in Spalten; Suchfeld im Kopf
// (#760): Ein-/Ausblenden, Abfrage, Auswahl mit Grenzen, Öffnen und Esc;
// Karte „Neu in Atlas“ (#756): Zeilen mit Schalter, Taste und
// „Ausprobieren“, Gruppen je Version, Auf- und Zuklappen, Kontextmenü;
// Bereich „Projekte“ (#592): Texte der Marken, Zeilen und Höhe, Tooltip,
// Klicks auf Zeile, Fehler-Marke und Kontextmenü; Bereich „Nicht gesichert“
// (#762): Texte je Art und Alter, leerer Bereich, nur die Schaltfläche löst
// eine Aktion aus, Kontextmenü, Rückfrage vor dem Push mit „Abbrechen“ als
// Vorgabe; Zustandskachel „Atlas“ (#754): Ersatztexte, „Jetzt aktualisieren“
// nur mit Update, Klicks auf Zeilen mit Aktion und auf die Knöpfe; Karte
// „Atlas entdecken“ (#757): Hinweise zur Nutzung, Tipp mit Kürzel und Stelle,
// Knöpfe nach Lage, leere Karte, Klicks über die Nachrichtenschleife;
// Bereich „Hilfe und Rückmeldung“ (#766): Texte, drei Knöpfe mit Umbruch,
// „Tastenkürzel“ nur mit Übersicht, Klicks über die Nachrichtenschleife;
// Bereich „Weiterarbeiten“ (#755): Texte (Reiter, Zeit, Commit, Zeile der
// Liste „Gemerkt“), „Fortsetzen“ und Commits über die Nachrichtenschleife,
// Abschnitt der eingehenden Commits nur mit Daten, Reiter „Gemerkt“ nur mit
// welcomePage.saved, Filter und Öffnen per Enter bzw. Doppelklick;
// Bereich „Projektverlauf“ (#758): Wert, Vorwert und Einheit je Kachel,
// Klick auf einen Punkt zeigt Build, Datum, Branch und Commit, leere
// Zustände, Umbruch der Kacheln; Auswahl in „Projekte“ (Klick wählt,
// Doppelklick und „Öffnen“ öffnen); frei anordnen (#767): Leiste,
// Bearbeitungsmodus mit Griff, Strg+Pfeiltasten, Breite und Auge, Menüs
// „Layout“ und „Bereich hinzufügen“, Leiste „Ausgeblendet“ und Rechtsklick
// „Ausblenden“; ohne welcomePage.customLayout kein Bearbeitungsmodus.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasWelcomeHeaderTests = class
  public
    [Test]
    procedure GreetingFollowsHourAndName;
    [Test]
    procedure StatusShowsServerAndIndex;
    [Test]
    procedure ThousandsFollowLanguage;
    [Test]
    procedure InfoShowsVersion;
    [Test]
    procedure ShowInfoFillsLabels;
  end;

  [TestFixture]
  TAtlasWelcomeBoardTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure ViewsCreateFramesWithId;
    [Test]
    procedure BoardPlacesSectionsInColumns;
    [Test]
    procedure BoardKeepsAndDropsFrames;
  end;

  [TestFixture]
  TAtlasWelcomeArrangeBoardTests = class
  public
    /// <summary>Erste Benutzung (Menüs, Bearbeitungsleiste) ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure BarFollowsCustomLayoutAndEditing;
    [Test]
    procedure CtrlArrowsMoveAndSave;
    [Test]
    procedure ToolsChangeWidthAndHide;
    [Test]
    procedure BarPartsReachSource;
    [Test]
    procedure AddMenuAndHiddenBarShowAtTarget;
    [Test]
    procedure LayoutMenuSwitchesAndAsksNames;
    [Test]
    procedure SectionMenuHidesAndOpensSettings;
  end;

  [TestFixture]
  TAtlasWelcomeSearchBoxTests = class
  public
    [Test]
    procedure HeaderShowsAndHidesSearch;
    [Test]
    procedure QueryFillsHitsAndRows;
    [Test]
    procedure SelectStaysInRange;
    [Test]
    procedure OpenSelectedHandsHitAndClears;
    [Test]
    procedure GroupCaptionsFollowLanguage;
  end;

  [TestFixture]
  TAtlasWelcomeWhatsNewFrameTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure UnreadShowsRowsWithSwitchKeyAndTry;
    [Test]
    procedure JumpGroupsByVersion;
    [Test]
    procedure AllVersionsCollapseExceptNewest;
    [Test]
    procedure ClicksReachSource;
    [Test]
    procedure TitleNamesSingleVersion;
    [Test]
    procedure BoardSizesCardToItsText;
  end;

  [TestFixture]
  TAtlasWelcomeProjectsFrameTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure PillTextsFollowKind;
    [Test]
    procedure RowsSetHeightAndAskForRefresh;
    [Test]
    procedure DetailAndHintNameState;
    [Test]
    procedure ClicksReachSource;
    [Test]
    procedure HitTestFindsRows;
    /// <summary>Mit Projektverlauf (#758): Klick wählt, Doppelklick und „Öffnen“ öffnen, rote Marke springt.
    /// </summary>
    [Test]
    procedure ClickSelectsForHistory;
    /// <summary>Schnellaktionen (#764): Knöpfe je Zeile, Tasten ohne Maus, Enter öffnet, aus = keine Knöpfe.
    /// </summary>
    [Test]
    procedure QuickActionsInRows;
  end;

  [TestFixture]
  TAtlasWelcomeContinueFrameTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure TextsFollowLanguageAndAge;
    [Test]
    procedure ResumeAndCommitReachSource;
    [Test]
    procedure IncomingSectionOnlyWithData;
    [Test]
    procedure SavedTabFiltersAndOpens;
    [Test]
    procedure WithoutSavedOnlyRecent;
    /// <summary>Schnellaktionen (#764) in „Zuletzt“: Knöpfe je Arbeitsstand, Enter setzt fort, Strg+B baut.
    /// </summary>
    [Test]
    procedure QuickActionsInRecent;
  end;

  [TestFixture]
  TAtlasWelcomeUnsavedFrameTests = class
  public
    [Test]
    procedure TextsFollowKindAndAge;
    [Test]
    procedure EmptyTextNamesState;
    [Test]
    procedure OnlyButtonAndMenuReachSource;
    [Test]
    procedure PushDialogCancelsByDefault;
  end;

  [TestFixture]
  TAtlasWelcomeStateFrameTests = class
  public
    [Test]
    procedure TextsUseLineOrFallback;
    [Test]
    procedure UpdateButtonOnlyWithUpdate;
    [Test]
    procedure ClicksReachSource;
    [Test]
    procedure HitTestFindsRows;
  end;

  [TestFixture]
  TAtlasWelcomeDiscoverFrameTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure AgeTextsFollowKind;
    [Test]
    procedure CardShowsTipAndButtons;
    [Test]
    procedure ClicksReachSource;
    [Test]
    procedure ImageFitsColumn;
  end;

  [TestFixture]
  TAtlasWelcomeHelpFrameTests = class
  public
    [Test]
    procedure TextsFollowLanguage;
    [Test]
    procedure ButtonsFollowSourceAndWidth;
    [Test]
    procedure ClicksReachSource;
  end;

  /// <summary>Bereich „<Projekt> für Atlas einrichten“ (#759).</summary>
  [TestFixture]
  TAtlasWelcomeSetupFrameTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure TextsFollowLanguage;
    /// <summary>Mockup #ws7: erledigte Schritte grün mit ✓ und ohne Knöpfe, offene mit Knopf.</summary>
    [Test]
    procedure StepsShowMarksAndButtons;
    /// <summary>Abnahme: Ein fehlender Suchpfad wird mit dem Unit-Namen gemeldet.</summary>
    [Test]
    procedure FindingNamesUnit;
    /// <summary>Unsichere Funde nennen das Makro; bei einer Gruppe das Projekt und den Stand der Prüfung.
    /// </summary>
    [Test]
    procedure UncertainAndGroupCaptions;
    /// <summary>Abnahme: Ohne Karte nur „Neu mit Atlas“; ohne beides nichts; ohne Projekt keine Knöpfe.</summary>
    [Test]
    procedure CardAndNewRowFollowCard;
    [Test]
    procedure ClicksReachSource;
    [Test]
    procedure RunningStepShowsSeconds;
    /// <summary>Vorschau zeigt den Inhalt vor dem Anlegen; Esc schreibt nichts.</summary>
    [Test]
    procedure PreviewShowsContent;
  end;

  [TestFixture]
  TAtlasWelcomeTrendsFrameTests = class
  public
    /// <summary>Abnahme: 12, 9, 6, 3, 0 Hinweise ergeben „0“ und „vorher 3“; Einheiten je Sprache.</summary>
    [Test]
    procedure TextsShowValueAndPrevious;
    /// <summary>Abnahme: Klick auf einen Punkt zeigt Build, Datum, Branch und Commit.</summary>
    [Test]
    procedure ClickShowsBuild;
    /// <summary>Abnahme: Anderes Projekt gewählt, anderer Verlauf; der gewählte Punkt gehört zum alten.</summary>
    [Test]
    procedure OtherProjectResetsChoice;
    [Test]
    procedure HitTestFindsPoints;
    [Test]
    procedure EmptyStates;
    [Test]
    procedure TilesWrapByWidth;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Atlas.Core.Status.Lines,
  Atlas.Core.Welcome.Sections,
  Atlas.Core.Welcome.Layout,
  Atlas.UI.Strings,
  Atlas.UI.Welcome.Frame,
  Atlas.UI.Welcome.Header,
  Atlas.UI.Welcome.Board,
  Atlas.UI.Welcome.Arrange,
  System.Types,
  Vcl.Menus,
  Atlas.Core.Welcome.Search,
  Atlas.UI.Welcome.Search,
  Atlas.Core.Welcome.WhatsNew,
  Atlas.UI.Welcome.WhatsNew,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Welcome.Projects,
  Atlas.UI.Welcome.Projects,
  Atlas.Core.Projects.Trends,
  Atlas.Core.Welcome.Trends,
  Atlas.UI.Welcome.Trends,
  System.DateUtils,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Welcome.Unsaved,
  Atlas.UI.Welcome.Unsaved,
  Atlas.UI.Welcome.Push,
  Atlas.Core.Status.Contract,
  Atlas.Core.Status.Registry,
  Atlas.Core.Welcome.State,
  Atlas.UI.Welcome.State,
  Atlas.Core.Welcome.Discover,
  Atlas.UI.Welcome.Discover,
  Atlas.Core.Welcome.Help,
  Atlas.UI.Welcome.Help,
  Atlas.Core.Projects.Setup,
  Atlas.Core.Generate.FileTemplates,
  Atlas.Core.Welcome.Setup,
  Atlas.UI.Welcome.Setup,
  Atlas.UI.Welcome.SetupPreview,
  Atlas.Core.Welcome.Continue,
  Atlas.Core.Welcome.Saved,
  Atlas.UI.Welcome.Continue,
  Atlas.Core.Welcome.QuickActions,
  Atlas.UI.Welcome.QuickActions,
  Atlas.UI.Welcome.QuickActions.Tests,
  System.IOUtils,
  Vcl.Imaging.pngimage;

type
  /// <summary>Quelle des Bereichs „Weiterarbeiten“ für die Tests; merkt sich die Aufrufe.</summary>
  TFakeContinue = class(TInterfacedObject, IAtlasContinueSource)
  public
    FEntries: TAtlasContinueEntries;
    FIncoming: TAtlasContinueIncoming;
    FQuerying: Boolean;
    FSavedEnabled: Boolean;
    FSaved: TAtlasSavedItems;
    FNotice: string;
    Calls: TArray<string>;
    function Entries: TAtlasContinueEntries;
    function Incoming: TAtlasContinueIncoming;
    function IncomingQuerying: Boolean;
    function SavedEnabled: Boolean;
    function Saved: TAtlasSavedItems;
    function Notice: string;
    procedure Resume(const AProject: string);
    procedure ShowCommit(const AProject: string; const ACommit: TAtlasContinueCommit);
    procedure OpenSaved(const AItem: TAtlasSavedItem);
    procedure Shown;
  end;

  /// <summary>Quelle des Bereichs „Hilfe und Rückmeldung“ für die Tests; merkt sich die Aufrufe.</summary>
  TFakeHelp = class(TInterfacedObject, IAtlasHelpSource)
  public
    Keys: Boolean;
    Calls: TArray<string>;
    function KeysAvailable: Boolean;
    procedure OpenDocs;
    procedure ShowKeys;
    procedure ReportProblem;
    procedure Donate;
  end;

  /// <summary>Quelle des Bereichs „Projekt für Atlas einrichten“ für die Tests; merkt sich die Aufrufe.</summary>
  TFakeSetup = class(TInterfacedObject, IAtlasSetupSource)
  public
    Card_: TAtlasSetupCard;
    Calls: TArray<string>;
    function Card: TAtlasSetupCard;
    procedure CreateConfig(ATemplate: TAtlasSetupTemplate);
    procedure StartBaseline;
    procedure CheckPaths;
    procedure OpenOptions;
    procedure OpenProject;
    procedure Dismiss;
    procedure NewFile(AKind: TAtlasNewFileKind);
  end;

  /// <summary>Quelle der Karte „Atlas entdecken“ für die Tests; merkt sich die Aufrufe.</summary>
  TFakeDiscover = class(TInterfacedObject, IAtlasDiscoverSource)
  public
    HasCard: Boolean;
    Card_: TAtlasDiscoverCard;
    Calls: TArray<string>;
    function Card(out ACard: TAtlasDiscoverCard): Boolean;
    procedure TryTip(const AId: string);
    procedure NextTip(const AId: string);
    procedure BlockTip(const AId: string);
  end;

  /// <summary>Quelle der Zustandskachel für die Tests; merkt sich die Aufrufe.</summary>
  TFakeState = class(TInterfacedObject, IAtlasStateSource)
  public
    Registry: IAtlasStatusRegistry;
    Calls: TArray<string>;
    function Rows: TAtlasStateRows;
    procedure RunRow(const AId: string);
    procedure Run(AButton: TAtlasStateButton);
  end;

  /// <summary>Quelle des Bereichs „Nicht gesichert“ für die Tests; merkt sich die Aufrufe.</summary>
  TFakeUnsaved = class(TInterfacedObject, IAtlasUnsavedSource)
  public
    FView: TAtlasUnsavedView;
    Calls: TArray<string>;
    function View: TAtlasUnsavedView;
    procedure Show(const ARow: TAtlasUnsavedRow);
    procedure Push(const ARow: TAtlasUnsavedRow);
    procedure OpenFolder(const ARow: TAtlasUnsavedRow);
    procedure Ignore(const ARow: TAtlasUnsavedRow);
    procedure Shown;
  end;

  /// <summary>Quelle des Bereichs „Projekte“ für die Tests; merkt sich die Aufrufe.</summary>
  TFakeProjects = class(TInterfacedObject, IAtlasProjectsSource)
  public
    FEntries: TAtlasProjectEntries;
    Calls: TArray<string>;
    function Entries: TAtlasProjectEntries;
    procedure Open(const AProject: string);
    procedure OpenAt(const AProject: string; const ATarget: TAtlasProjectLocation);
    procedure OpenFolder(const AProject: string);
    procedure Remove(const AProject: string);
    procedure Shown;
    function Selectable: Boolean;
    procedure Select(const AProject: string);
    function Selected: string;
  public
    /// <summary>Projektverlauf an (#758): Klick wählt.</summary>
    FSelectable: Boolean;
    FSelected: string;
  end;

  /// <summary>Quelle des Bereichs „Projektverlauf“ für die Tests.</summary>
  TFakeTrends = class(TInterfacedObject, IAtlasTrendsSource)
  public
    FView: TAtlasTrendView;
    function View: TAtlasTrendView;
  end;

  /// <summary>Quelle der Karte für die Tests; merkt sich die Aufrufe.</summary>
  TFakeWhatsNew = class(TInterfacedObject, IAtlasWhatsNewSource)
  public
    FView: TAtlasWhatsNewView;
    FVersions: TAtlasWhatsNewVersions;
    Calls: TArray<string>;
    function View: TAtlasWhatsNewView;
    function Versions: TAtlasWhatsNewVersions;
    function SwitchOf(const ASetting: string): TAtlasWhatsNewSwitch;
    function KeyText(const AKey: string): string;
    function CanTry(const AItem: TAtlasWhatsNewItem): Boolean;
    procedure SetSwitch(const ASetting: string; AOn: Boolean);
    procedure TryItem(const AItem: TAtlasWhatsNewItem);
    procedure Dismiss;
    procedure Show(AView: TAtlasWhatsNewView);
  end;

function TFakeWhatsNew.View: TAtlasWhatsNewView;
begin
  Result := FView;
end;

function TFakeWhatsNew.Versions: TAtlasWhatsNewVersions;
begin
  Result := FVersions;
end;

function TFakeWhatsNew.SwitchOf(const ASetting: string): TAtlasWhatsNewSwitch;
begin
  if ASetting = 'An' then
    Result := TAtlasWhatsNewSwitch.On
  else if ASetting = 'Aus' then
    Result := TAtlasWhatsNewSwitch.Off
  else
    Result := TAtlasWhatsNewSwitch.None;
end;

function TFakeWhatsNew.KeyText(const AKey: string): string;
begin
  Result := '';
  if AKey = 'Taste' then
    Result := 'Ctrl+E';
end;

function TFakeWhatsNew.CanTry(const AItem: TAtlasWhatsNewItem): Boolean;
begin
  Result := (AItem.Command <> '') or (AItem.Sample <> '');
end;

procedure TFakeWhatsNew.SetSwitch(const ASetting: string; AOn: Boolean);
begin
  Calls := Calls + [Format('switch %s %s', [ASetting, BoolToStr(AOn, True)])];
end;

procedure TFakeWhatsNew.TryItem(const AItem: TAtlasWhatsNewItem);
begin
  Calls := Calls + ['try ' + AItem.Title];
end;

procedure TFakeWhatsNew.Dismiss;
begin
  Calls := Calls + ['dismiss'];
end;

procedure TFakeWhatsNew.Show(AView: TAtlasWhatsNewView);
begin
  Calls := Calls + [Format('show %d', [Ord(AView)])];
end;

{ TFakeProjects }

function TFakeProjects.Entries: TAtlasProjectEntries;
begin
  Result := FEntries;
end;

procedure TFakeProjects.Open(const AProject: string);
begin
  Calls := Calls + ['open ' + AProject];
end;

procedure TFakeProjects.OpenAt(const AProject: string; const ATarget: TAtlasProjectLocation);
begin
  Calls := Calls + [Format('openAt %s %s %d', [AProject, ATarget.FileName, ATarget.Line])];
end;

procedure TFakeProjects.OpenFolder(const AProject: string);
begin
  Calls := Calls + ['folder ' + AProject];
end;

procedure TFakeProjects.Remove(const AProject: string);
begin
  Calls := Calls + ['remove ' + AProject];
end;

procedure TFakeProjects.Shown;
begin
  Calls := Calls + ['shown'];
end;

function TFakeProjects.Selectable: Boolean;
begin
  Result := FSelectable;
end;

procedure TFakeProjects.Select(const AProject: string);
begin
  Calls := Calls + ['select ' + AProject];
  FSelected := AProject;
end;

function TFakeProjects.Selected: string;
begin
  Result := FSelected;
end;

{ TFakeTrends }

function TFakeTrends.View: TAtlasTrendView;
begin
  Result := FView;
end;

/// <summary>Projekt mit einem Build je Wert in AHints (Hinweise), Dauer 12,48 s, Branch main, eigener Commit je
/// Build, TODOs ab dem zweiten.</summary>
function TrendSummary(const AProject: string; const AHints: array of Integer): TAtlasProjectSummary;
var
  Index: Integer;
  Stamp: TDateTime;
begin
  Result := TAtlasProjectSummary.Create(AProject);
  for Index := 0 to High(AHints) do
  begin
    Stamp := EncodeDateTime(2026, 10, 10 + Index, 9, 30, 0, 0);
    Result.Build := TAtlasProjectBuild.Empty;
    Result.Build.Known := True;
    Result.Build.At := Stamp;
    Result.Build.Hints := AHints[Index];
    Result.Build.DurationMs := 12480;
    Result.Vcs := TAtlasProjectVcs.Empty;
    Result.Vcs.Known := True;
    Result.Vcs.Kind := 'git';
    Result.Vcs.Branch := 'main';
    Result.Vcs.Revision := Format('1a2b3c%dd5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b', [Index]);
    if Index > 0 then
    begin
      Result.Todos := TAtlasProjectTodos.Empty;
      Result.Todos.Known := True;
      Result.Todos.At := Stamp;
      Result.Todos.Open := 7;
    end;
    TAtlasProjectTrendLog.Append(Result, Stamp, 30);
  end;
end;

function TrendsFrame(AHost: TForm; const ASource: IAtlasTrendsSource): TAtlasWelcomeTrendsFrame;
begin
  Result := TAtlasWelcomeTrendsFrame.Create(AHost);
  Result.Parent := AHost;
  Result.Width := 600;
  Result.Source := ASource;
end;

/// <summary>Projekt auf main; mit AErrors &gt; 0 ein fehlgeschlagener Build mit Sprungziel.</summary>
function ProjectEntry(const AProject: string; AErrors: Integer): TAtlasProjectEntry;
begin
  Result := Default(TAtlasProjectEntry);
  Result.HasSummary := True;
  Result.Summary := TAtlasProjectSummary.Create(AProject);
  Result.Summary.Vcs.Known := True;
  Result.Summary.Vcs.Kind := 'git';
  Result.Summary.Vcs.Branch := 'main';
  Result.Summary.Vcs.Changed := 0;
  Result.Summary.Vcs.At := EncodeDate(2026, 10, 14) + EncodeTime(17, 45, 0, 0);
  Result.Summary.Build.Known := True;
  Result.Summary.Build.Kind := 'build';
  Result.Summary.Build.Succeeded := AErrors = 0;
  Result.Summary.Build.Errors := AErrors;
  if AErrors > 0 then
  begin
    Result.Summary.Build.First.FileName := 'C:\P\Main.pas';
    Result.Summary.Build.First.Line := 12;
    Result.Summary.Build.First.Code := 'E2003';
  end;
end;

function ProjectsFrame(AHost: TForm; const ASource: IAtlasProjectsSource): TAtlasWelcomeProjectsFrame;
begin
  Result := TAtlasWelcomeProjectsFrame.Create(AHost);
  Result.Parent := AHost;
  Result.Width := 600;
  Result.Source := ASource;
end;

function NewsItem(const ATitle, ASetting, AKey, ACommand: string): TAtlasWhatsNewItem;
begin
  Result := Default(TAtlasWhatsNewItem);
  Result.Title := ATitle;
  Result.Text := 'Ein Satz zu ' + ATitle + ', lang genug, damit er in einer schmalen Karte umbricht.';
  Result.Setting := ASetting;
  Result.Key := AKey;
  Result.Command := ACommand;
end;

function NewsVersion(const AVersion: string; const AItems: TArray<TAtlasWhatsNewItem>): TAtlasWhatsNewVersion;
begin
  Result.Version := AVersion;
  Result.Items := AItems;
end;

/// <summary>Karte in einem Formular (Labels brauchen ein Fenster zum Messen).</summary>
function NewsFrame(AHost: TForm; const ASource: IAtlasWhatsNewSource): TAtlasWelcomeWhatsNewFrame;
begin
  Result := TAtlasWelcomeWhatsNewFrame.Create(AHost);
  Result.Parent := AHost;
  Result.SetBounds(0, 0, 420, 300);
  Result.Source := ASource;
end;

{ TAtlasWelcomeHeaderTests }

procedure TAtlasWelcomeHeaderTests.GreetingFollowsHourAndName;
var
  Saved: TAtlasLanguage;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('Guten Morgen, Marco', TAtlasWelcomeHeaderFrame.GreetingText(8, 'Marco'));
    Assert.AreEqual('Guten Tag, Marco', TAtlasWelcomeHeaderFrame.GreetingText(14, 'Marco'));
    Assert.AreEqual('Guten Abend, Marco', TAtlasWelcomeHeaderFrame.GreetingText(20, 'Marco'));
    Assert.AreEqual('Gute Nacht', TAtlasWelcomeHeaderFrame.GreetingText(2, ''), 'ohne Namen nur der Gruß');
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('Good evening, Marco', TAtlasWelcomeHeaderFrame.GreetingText(20, 'Marco'));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasWelcomeHeaderTests.StatusShowsServerAndIndex;
var
  Saved: TAtlasLanguage;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('Server läuft · 1.284 Units im Index',
      TAtlasWelcomeHeaderFrame.StatusText(TAtlasServerPhase.Running, 1284, False, -1));
    Assert.AreEqual('Server läuft · Index wird aufgebaut (45 %)',
      TAtlasWelcomeHeaderFrame.StatusText(TAtlasServerPhase.Running, 1284, True, 45));
    Assert.AreEqual('Server läuft · Index wird aufgebaut',
      TAtlasWelcomeHeaderFrame.StatusText(TAtlasServerPhase.Running, -1, True, -1));
    Assert.AreEqual('Server läuft', TAtlasWelcomeHeaderFrame.StatusText(TAtlasServerPhase.Running, -1, False, -1),
      'Units unbekannt');
    Assert.AreEqual('Server startet mit dem ersten Projekt',
      TAtlasWelcomeHeaderFrame.StatusText(TAtlasServerPhase.NotStarted, 10, False, -1));
    Assert.AreEqual('Server fehlt', TAtlasWelcomeHeaderFrame.StatusText(TAtlasServerPhase.Failed, 10, True, 5),
      'Index nur bei laufendem Server');
    Assert.AreEqual('Server gestoppt', TAtlasWelcomeHeaderFrame.StatusText(TAtlasServerPhase.Stopped, 10, False, -1));
    Assert.AreEqual('Server startet', TAtlasWelcomeHeaderFrame.StatusText(TAtlasServerPhase.Starting, 10, False, -1));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasWelcomeHeaderTests.ThousandsFollowLanguage;
var
  Saved: TAtlasLanguage;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('1.234.567', TAtlasWelcomeHeaderFrame.Thousands(1234567));
    Assert.AreEqual('0', TAtlasWelcomeHeaderFrame.Thousands(0));
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('1,284', TAtlasWelcomeHeaderFrame.Thousands(1284));
    Assert.AreEqual('Server running · 1,284 units in the index',
      TAtlasWelcomeHeaderFrame.StatusText(TAtlasServerPhase.Running, 1284, False, -1));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasWelcomeHeaderTests.InfoShowsVersion;
var
  Saved: TAtlasLanguage;
  Info: TAtlasWelcomeHeaderInfo;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Info := Default(TAtlasWelcomeHeaderInfo);
    Info.Version := '1.0.0';
    Info.Phase := TAtlasServerPhase.Stopped;
    Info.Units := -1;
    Info.Percent := -1;
    Assert.AreEqual('Atlas 1.0.0 · Server gestoppt', TAtlasWelcomeHeaderFrame.InfoText(Info));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasWelcomeHeaderTests.ShowInfoFillsLabels;
var
  Saved: TAtlasLanguage;
  Header: TAtlasWelcomeHeaderFrame;
  Info: TAtlasWelcomeHeaderInfo;
begin
  Saved := TAtlasStrings.Language;
  Header := TAtlasWelcomeHeaderFrame.Create(nil);
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Info := Default(TAtlasWelcomeHeaderInfo);
    Info.Greeting := True;
    Info.Hour := 9;
    Info.FirstName := 'Marco';
    Info.Version := '1.0.0';
    Info.Phase := TAtlasServerPhase.Running;
    Info.Units := 42;
    Info.Percent := -1;
    Header.ShowInfo(Info);
    Assert.AreEqual('Guten Morgen, Marco', Header.GreetingLabel.Caption);
    Assert.AreEqual('Atlas 1.0.0 · Server läuft · 42 Units im Index', Header.InfoLabel.Caption);
    Assert.AreEqual(0, Header.SearchHost.Width, 'Platz für das Suchfeld (#760) noch leer');
    // welcomePage.greeting aus: nur „Atlas“.
    Info.Greeting := False;
    Header.ShowInfo(Info);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.WelcomeHeaderTitle), Header.GreetingLabel.Caption);
  finally
    Header.Free;
    TAtlasStrings.Language := Saved;
  end;
end;

{ TAtlasWelcomeBoardTests }

type
  TTestSection = class(TAtlasWelcomeSectionFrame)
  public
    Updates: Integer;
    procedure UpdateContent; override;
  end;

procedure TTestSection.UpdateContent;
begin
  Inc(Updates);
  inherited;
end;

procedure RegisterViews(const AIds: array of string);
var
  Id: string;
begin
  for Id in AIds do
    TAtlasWelcomeViews.Register(Id,
      function(AOwner: TComponent): TAtlasWelcomeSectionFrame
      begin
        Result := TTestSection.Create(AOwner);
      end);
end;

function Section(const AId: string; AOrder: Integer; AColumn: TAtlasWelcomeColumn): TAtlasWelcomeSection;
begin
  Result := TAtlasWelcomeSection.Create(AId, 'Titel ' + AId, AOrder, AColumn, nil);
end;

procedure TAtlasWelcomeBoardTests.WarmUpFirstUse;
begin
  BoardPlacesSectionsInColumns;
end;

procedure TAtlasWelcomeBoardTests.ViewsCreateFramesWithId;
var
  View: TAtlasWelcomeSectionFrame;
begin
  RegisterViews([TAtlasWelcomeIds.State]);
  try
    Assert.IsTrue(TAtlasWelcomeViews.Exists('ATLAS.STATE'));
    Assert.IsFalse(TAtlasWelcomeViews.Exists(TAtlasWelcomeIds.News));
    Assert.IsNull(TAtlasWelcomeViews.CreateView(TAtlasWelcomeIds.News, nil));
    View := TAtlasWelcomeViews.CreateView(TAtlasWelcomeIds.State, nil);
    try
      Assert.IsNotNull(View);
      Assert.AreEqual(TAtlasWelcomeIds.State, View.SectionId);
      Assert.IsTrue(View.ShowTitle);
      Assert.AreEqual(TAtlasWelcomeSectionFrame.TitleHeight + TAtlasWelcomeSectionFrame.DefaultBodyHeight,
        View.PreferredHeight);
      View.ShowTitle := False;
      Assert.AreEqual(TAtlasWelcomeSectionFrame.DefaultBodyHeight, View.PreferredHeight);
    finally
      View.Free;
    end;
    TAtlasWelcomeViews.Unregister(TAtlasWelcomeIds.State);
    Assert.IsFalse(TAtlasWelcomeViews.Exists(TAtlasWelcomeIds.State));
  finally
    TAtlasWelcomeViews.Release;
  end;
end;

procedure TAtlasWelcomeBoardTests.BoardPlacesSectionsInColumns;
var
  Host: TForm;
  Board: TAtlasWelcomeBoardFrame;
  Left, Right, Below: TAtlasWelcomeSectionFrame;
begin
  RegisterViews([TAtlasWelcomeIds.Continue, TAtlasWelcomeIds.Projects, TAtlasWelcomeIds.State]);
  Host := TForm.CreateNew(nil);
  try
    Host.ClientWidth := 800;
    Host.ClientHeight := 600;
    Board := TAtlasWelcomeBoardFrame.Create(Host);
    Board.Parent := Host;
    Board.Align := alClient;
    Board.Rebuild([Section(TAtlasWelcomeIds.State, 10, TAtlasWelcomeColumn.Right),
      Section(TAtlasWelcomeIds.Continue, 20, TAtlasWelcomeColumn.Left),
      Section(TAtlasWelcomeIds.Projects, 30, TAtlasWelcomeColumn.Left),
      Section(TAtlasWelcomeIds.News, 40, TAtlasWelcomeColumn.Right)], TAtlasWelcomeLayout.Atlas, 2);
    Assert.AreEqual(2, Integer(Length(Board.Columns)));
    Left := Board.View(TAtlasWelcomeIds.Continue);
    Below := Board.View(TAtlasWelcomeIds.Projects);
    Right := Board.View(TAtlasWelcomeIds.State);
    Assert.IsNotNull(Left);
    Assert.IsNull(Board.View(TAtlasWelcomeIds.News), 'ohne Fabrik kein Frame');
    Assert.AreEqual('Titel ' + TAtlasWelcomeIds.Continue, Left.Title);
    Assert.IsTrue(Left.ShowTitle);
    Assert.AreEqual(Left.Left, Below.Left, 'gleiche Spalte');
    Assert.IsTrue(Below.Top > Left.Top + Left.Height - 1, 'untereinander');
    Assert.IsTrue(Right.Left > Left.Left + Left.Width - 1, 'rechte Spalte');
    Assert.AreEqual(Left.Top, Right.Top);
    Assert.IsTrue(TTestSection(Left).Updates > 0, 'neuer Frame liest seinen Inhalt');
    // Eine Spalte (Fenster „Atlas-Start“): alles untereinander.
    Board.Rebuild([Section(TAtlasWelcomeIds.State, 10, TAtlasWelcomeColumn.Right),
      Section(TAtlasWelcomeIds.Continue, 20, TAtlasWelcomeColumn.Left)], TAtlasWelcomeLayout.Atlas, 1);
    Assert.AreEqual(Board.View(TAtlasWelcomeIds.Continue).Left, Board.View(TAtlasWelcomeIds.State).Left);
    Assert.IsTrue(Board.View(TAtlasWelcomeIds.State).Top > Board.View(TAtlasWelcomeIds.Continue).Top);
  finally
    Host.Free;
    TAtlasWelcomeViews.Release;
  end;
end;

procedure TAtlasWelcomeBoardTests.BoardKeepsAndDropsFrames;
var
  Host: TForm;
  Board: TAtlasWelcomeBoardFrame;
  Kept: TAtlasWelcomeSectionFrame;
  Before: Integer;
begin
  RegisterViews([TAtlasWelcomeIds.Continue, TAtlasWelcomeIds.State]);
  // Wie in der IDE: Die Tafel hängt an einem Fenster.
  Host := TForm.CreateNew(nil);
  Board := TAtlasWelcomeBoardFrame.Create(nil);
  try
    Board.Parent := Host;
    Board.Rebuild([Section(TAtlasWelcomeIds.Continue, 20, TAtlasWelcomeColumn.Left),
      Section(TAtlasWelcomeIds.State, 10, TAtlasWelcomeColumn.Right)], TAtlasWelcomeLayout.Atlas, 2);
    Kept := Board.View(TAtlasWelcomeIds.Continue);
    Board.Rebuild([Section(TAtlasWelcomeIds.Continue, 20, TAtlasWelcomeColumn.Left)], TAtlasWelcomeLayout.Atlas, 2);
    Assert.IsTrue(Kept = Board.View(TAtlasWelcomeIds.Continue), 'sichtbarer Bereich behält seinen Frame');
    Assert.IsNull(Board.View(TAtlasWelcomeIds.State), 'ausgeschalteter Bereich verschwindet');
    Before := TTestSection(Kept).Updates;
    Board.UpdateSection(TAtlasWelcomeIds.Continue);
    Assert.AreEqual(Before + 1, TTestSection(Kept).Updates);
    Board.UpdateContent;
    Assert.AreEqual(Before + 2, TTestSection(Kept).Updates);
  finally
    Board.Free;
    Host.Free;
    TAtlasWelcomeViews.Release;
  end;
end;

{ TAtlasWelcomeArrangeBoardTests }

type
  /// <summary>Quelle für „Seite anpassen“, die jeden Aufruf mitschreibt.</summary>
  TFakeArrangeSource = class(TInterfacedObject, IAtlasWelcomeArrangeSource)
  public
    Can: Boolean;
    EditingOn: Boolean;
    Names: TArray<string>;
    Active: string;
    Entries: TArray<TAtlasWelcomeCatalogEntry>;
    Calls: TArray<string>;
    Arranged: TAtlasWelcomeLayout;
    function CanCustomize: Boolean;
    function Editing: Boolean;
    procedure SetEditing(AOn: Boolean);
    function LayoutNames: TArray<string>;
    function ActiveLayout: string;
    function Catalog: TArray<TAtlasWelcomeCatalogEntry>;
    procedure Arrange(const ALayout: TAtlasWelcomeLayout);
    procedure ShowSection(const AId: string; AColumn: Integer; const ABefore: string);
    procedure HideSection(const AId: string);
    procedure HideSectionAt(const AId: string; const APoint: TPoint);
    procedure ShowSectionSettings(const AId: string);
    procedure SwitchLayout(const AName: string);
    function AddLayout(const AName: string): Boolean;
    function RenameLayout(const AName: string): Boolean;
    function DeleteLayout: Boolean;
    procedure ResetLayout;
    function Last: string;
  end;

function TFakeArrangeSource.CanCustomize: Boolean;
begin
  Result := Can;
end;

function TFakeArrangeSource.Editing: Boolean;
begin
  Result := EditingOn;
end;

procedure TFakeArrangeSource.SetEditing(AOn: Boolean);
begin
  Calls := Calls + ['edit ' + BoolToStr(AOn, True)];
end;

function TFakeArrangeSource.LayoutNames: TArray<string>;
begin
  Result := Names;
end;

function TFakeArrangeSource.ActiveLayout: string;
begin
  Result := Active;
end;

function TFakeArrangeSource.Catalog: TArray<TAtlasWelcomeCatalogEntry>;
begin
  Result := Entries;
end;

procedure TFakeArrangeSource.Arrange(const ALayout: TAtlasWelcomeLayout);
begin
  Arranged := ALayout;
  Calls := Calls + ['arrange'];
end;

procedure TFakeArrangeSource.ShowSection(const AId: string; AColumn: Integer; const ABefore: string);
begin
  Calls := Calls + [Format('show %s %d %s', [AId, AColumn, ABefore])];
end;

procedure TFakeArrangeSource.HideSection(const AId: string);
begin
  Calls := Calls + ['hide ' + AId];
end;

procedure TFakeArrangeSource.HideSectionAt(const AId: string; const APoint: TPoint);
begin
  Calls := Calls + ['hideAt ' + AId];
end;

procedure TFakeArrangeSource.ShowSectionSettings(const AId: string);
begin
  Calls := Calls + ['settings ' + AId];
end;

procedure TFakeArrangeSource.SwitchLayout(const AName: string);
begin
  Calls := Calls + ['switch ' + AName];
end;

function TFakeArrangeSource.AddLayout(const AName: string): Boolean;
begin
  Calls := Calls + ['add ' + AName];
  Result := True;
end;

function TFakeArrangeSource.RenameLayout(const AName: string): Boolean;
begin
  Calls := Calls + ['rename ' + AName];
  Result := True;
end;

function TFakeArrangeSource.DeleteLayout: Boolean;
begin
  Calls := Calls + ['delete'];
  Result := True;
end;

procedure TFakeArrangeSource.ResetLayout;
begin
  Calls := Calls + ['reset'];
end;

function TFakeArrangeSource.Last: string;
begin
  Result := '';
  if Length(Calls) > 0 then
    Result := Calls[High(Calls)];
end;

function ArrangeSource(AEditing: Boolean): TFakeArrangeSource;
begin
  Result := TFakeArrangeSource.Create;
  Result.Can := True;
  Result.EditingOn := AEditing;
  Result.Names := ['Standard'];
  Result.Active := 'Standard';
  Result.Entries := [
    TAtlasWelcomeCatalogEntry.Create(TAtlasWelcomeIds.Continue, 'Weiterarbeiten', 'Zuletzt', True),
    TAtlasWelcomeCatalogEntry.Create(TAtlasWelcomeIds.Projects, 'Projekte', 'Zustand', True),
    TAtlasWelcomeCatalogEntry.Create(TAtlasWelcomeIds.Tests, 'Testergebnisse', 'Letzter Lauf', False),
    TAtlasWelcomeCatalogEntry.Create(TAtlasWelcomeIds.State, 'Atlas', 'Zustandskachel', True)];
end;

/// <summary>Tafel mit Weiterarbeiten und Projekten links, Zustandskachel rechts.</summary>
function ArrangeBoard(AHost: TForm; const ASource: IAtlasWelcomeArrangeSource): TAtlasWelcomeBoardFrame;
begin
  RegisterViews([TAtlasWelcomeIds.Continue, TAtlasWelcomeIds.Projects, TAtlasWelcomeIds.State]);
  AHost.ClientWidth := 800;
  AHost.ClientHeight := 600;
  Result := TAtlasWelcomeBoardFrame.Create(AHost);
  Result.Parent := AHost;
  Result.Align := alClient;
  Result.Source := ASource;
  Result.Rebuild([Section(TAtlasWelcomeIds.State, 10, TAtlasWelcomeColumn.Right),
    Section(TAtlasWelcomeIds.Continue, 20, TAtlasWelcomeColumn.Left),
    Section(TAtlasWelcomeIds.Projects, 30, TAtlasWelcomeColumn.Left)], TAtlasWelcomeLayout.Atlas, 2);
end;

procedure TAtlasWelcomeArrangeBoardTests.WarmUpFirstUse;
begin
  try
    BarFollowsCustomLayoutAndEditing;
  except
    on Exception do
      ;
  end;
end;

procedure TAtlasWelcomeArrangeBoardTests.BarFollowsCustomLayoutAndEditing;
var
  Host: TForm;
  Board: TAtlasWelcomeBoardFrame;
  Source: TFakeArrangeSource;
  Keep: IAtlasWelcomeArrangeSource;
begin
  Host := TForm.CreateNew(nil);
  try
    Source := ArrangeSource(False);
    Keep := Source;
    Board := ArrangeBoard(Host, Keep);
    // Außerhalb des Bearbeitungsmodus: nur der Stift, keine Griffe, keine Leiste „Ausgeblendet“.
    Assert.IsTrue(Board.Bar.Visible);
    Assert.IsTrue(Board.Bar.IndexOf(TAtlasArrangePartKind.Edit, '') >= 0);
    Assert.AreEqual(-1, Board.Bar.IndexOf(TAtlasArrangePartKind.Column, '2'));
    Assert.AreEqual(-1, Board.Bar.IndexOf(TAtlasArrangePartKind.Layout, ''), 'ein Layout: kein Umschalter');
    Assert.IsNull(Board.GripOf(TAtlasWelcomeIds.State));
    Assert.IsFalse(Board.HiddenBar.Visible);
    Assert.IsFalse(Board.InsertLine.Visible);
    Assert.IsTrue(Board.View(TAtlasWelcomeIds.State).TitleBar.PopupMenu = Board.SectionMenu, 'Rechtsklick');
    // Bearbeitungsmodus.
    Source.EditingOn := True;
    Board.Rebuild([Section(TAtlasWelcomeIds.State, 10, TAtlasWelcomeColumn.Right),
      Section(TAtlasWelcomeIds.Continue, 20, TAtlasWelcomeColumn.Left),
      Section(TAtlasWelcomeIds.Projects, 30, TAtlasWelcomeColumn.Left)], TAtlasWelcomeLayout.Atlas, 2);
    Assert.IsTrue(Board.Editing);
    Assert.IsNotNull(Board.GripOf(TAtlasWelcomeIds.State));
    Assert.IsNotNull(Board.ToolsOf(TAtlasWelcomeIds.State));
    Assert.IsTrue(Board.GripOf(TAtlasWelcomeIds.State).TabStop, 'Tab erreicht den Griff');
    Assert.IsTrue(Board.Bar.Parts[Board.Bar.IndexOf(TAtlasArrangePartKind.Column, '2')].Down);
    Assert.IsTrue(Board.Bar.IndexOf(TAtlasArrangePartKind.Add, '') >= 0);
    Assert.IsTrue(Board.Bar.IndexOf(TAtlasArrangePartKind.Reset, '') >= 0);
    Assert.IsTrue(Board.Bar.IndexOf(TAtlasArrangePartKind.Layout, '') >= 0);
    Assert.IsTrue(Board.HiddenBar.Visible);
    Assert.IsTrue(Board.HiddenBar.IndexOf(TAtlasArrangePartKind.Hidden, TAtlasWelcomeIds.Tests) >= 0);
    Assert.AreEqual(-1, Board.HiddenBar.IndexOf(TAtlasArrangePartKind.Hidden, TAtlasWelcomeIds.State));
    Assert.IsTrue(Board.InsertLine.Visible);
    // welcomePage.customLayout aus: kein Bearbeitungsmodus, keine Leiste, festes Layout.
    Source.Can := False;
    Board.Rebuild([Section(TAtlasWelcomeIds.State, 10, TAtlasWelcomeColumn.Right),
      Section(TAtlasWelcomeIds.Continue, 20, TAtlasWelcomeColumn.Left)], TAtlasWelcomeLayout.Atlas, 2);
    Assert.IsFalse(Board.Editing);
    Assert.IsFalse(Board.Bar.Visible);
    Assert.IsNull(Board.GripOf(TAtlasWelcomeIds.State));
    Assert.IsNull(Board.ToolsOf(TAtlasWelcomeIds.State));
    Assert.IsFalse(Board.HiddenBar.Visible);
    // Ohne Quelle (Tests, ältere Aufrufer): kein Rechtsklick-Menü.
    Board.Source := nil;
    Board.Rebuild([Section(TAtlasWelcomeIds.State, 10, TAtlasWelcomeColumn.Right)], TAtlasWelcomeLayout.Atlas, 2);
    Assert.IsNull(Board.View(TAtlasWelcomeIds.State).TitleBar.PopupMenu);
  finally
    Host.Free;
    TAtlasWelcomeViews.Release;
  end;
end;

procedure TAtlasWelcomeArrangeBoardTests.CtrlArrowsMoveAndSave;
var
  Host: TForm;
  Board: TAtlasWelcomeBoardFrame;
  Source: TFakeArrangeSource;
  Keep: IAtlasWelcomeArrangeSource;
  Grip: TAtlasWelcomeGrip;
begin
  Host := TForm.CreateNew(nil);
  try
    Source := ArrangeSource(True);
    Keep := Source;
    Board := ArrangeBoard(Host, Keep);
    Grip := Board.GripOf(TAtlasWelcomeIds.State);
    Assert.IsFalse(Grip.HandleKey(VK_LEFT, []), 'ohne Strg nichts');
    // Akzeptanz: nur mit Tastatur nach links oben.
    Assert.IsTrue(Grip.HandleKey(VK_LEFT, [ssCtrl]));
    Assert.AreEqual(TAtlasWelcomeIds.State, Board.Columns[0][0], 'sofort sichtbar');
    Assert.AreEqual(Board.View(TAtlasWelcomeIds.Continue).Left, Board.View(TAtlasWelcomeIds.State).Left);
    Assert.IsTrue(Board.View(TAtlasWelcomeIds.Continue).Top > Board.View(TAtlasWelcomeIds.State).Top);
    Assert.AreEqual(0, Integer(Length(Source.Calls)), 'gespeichert wird über die Warteschlange');
    CheckSynchronize;
    Assert.AreEqual('arrange', Source.Last);
    Assert.AreEqual(TAtlasWelcomeIds.State, Source.Arranged.Arrange([Section(TAtlasWelcomeIds.State, 10,
      TAtlasWelcomeColumn.Right), Section(TAtlasWelcomeIds.Continue, 20, TAtlasWelcomeColumn.Left)], 2)[0][0]);
    // Am Rand: verarbeitet (der Fokus wandert nicht), aber nichts gespeichert.
    Source.Calls := nil;
    Assert.IsTrue(Board.GripOf(TAtlasWelcomeIds.State).HandleKey(VK_UP, [ssCtrl]));
    CheckSynchronize;
    Assert.AreEqual(0, Integer(Length(Source.Calls)));
  finally
    Host.Free;
    TAtlasWelcomeViews.Release;
  end;
end;

procedure TAtlasWelcomeArrangeBoardTests.ToolsChangeWidthAndHide;
var
  Host: TForm;
  Board: TAtlasWelcomeBoardFrame;
  Source: TFakeArrangeSource;
  Keep: IAtlasWelcomeArrangeSource;
begin
  Host := TForm.CreateNew(nil);
  try
    Source := ArrangeSource(True);
    Keep := Source;
    Board := ArrangeBoard(Host, Keep);
    Assert.IsFalse(Board.ToolsOf(TAtlasWelcomeIds.Projects).Wide);
    Board.ToolsOf(TAtlasWelcomeIds.Projects).Click(TAtlasWelcomeTool.Width);
    Assert.AreEqual(2, Board.Layout.WidthOf(TAtlasWelcomeIds.Projects));
    Assert.IsTrue(Board.ToolsOf(TAtlasWelcomeIds.Projects).Wide);
    Assert.AreEqual(Board.View(TAtlasWelcomeIds.Continue).Width * 2 + TAtlasWelcomeBoardFrame.Gap,
      Board.View(TAtlasWelcomeIds.Projects).Width, 'über zwei Spalten');
    CheckSynchronize;
    Assert.AreEqual('arrange', Source.Last);
    // Akzeptanz: das Auge schaltet die Einstellung des Bereichs aus.
    Board.ToolsOf(TAtlasWelcomeIds.State).Click(TAtlasWelcomeTool.Eye);
    CheckSynchronize;
    Assert.AreEqual('hide ' + TAtlasWelcomeIds.State, Source.Last);
  finally
    Host.Free;
    TAtlasWelcomeViews.Release;
  end;
end;

procedure TAtlasWelcomeArrangeBoardTests.BarPartsReachSource;
var
  Host: TForm;
  Board: TAtlasWelcomeBoardFrame;
  Source: TFakeArrangeSource;
  Keep: IAtlasWelcomeArrangeSource;
begin
  Host := TForm.CreateNew(nil);
  try
    Source := ArrangeSource(True);
    Keep := Source;
    Board := ArrangeBoard(Host, Keep);
    Board.Bar.ClickPart(Board.Bar.IndexOf(TAtlasArrangePartKind.Column, '1'));
    Assert.AreEqual(1, Board.Layout.Columns);
    Assert.AreEqual(1, Integer(Length(Board.Columns)));
    Assert.IsTrue(Board.Bar.Parts[Board.Bar.IndexOf(TAtlasArrangePartKind.Column, '1')].Down);
    CheckSynchronize;
    Assert.AreEqual('arrange', Source.Last);
    Assert.AreEqual(1, Source.Arranged.Columns);
    Board.Bar.ClickPart(Board.Bar.IndexOf(TAtlasArrangePartKind.Reset, ''));
    CheckSynchronize;
    Assert.AreEqual('reset', Source.Last);
    Board.Bar.ClickPart(Board.Bar.IndexOf(TAtlasArrangePartKind.Edit, ''));
    CheckSynchronize;
    Assert.AreEqual('edit False', Source.Last, '„Fertig“');
  finally
    Host.Free;
    TAtlasWelcomeViews.Release;
  end;
end;

procedure TAtlasWelcomeArrangeBoardTests.AddMenuAndHiddenBarShowAtTarget;
var
  Host: TForm;
  Board: TAtlasWelcomeBoardFrame;
  Source: TFakeArrangeSource;
  Keep: IAtlasWelcomeArrangeSource;
  Column: Integer;
  Before: string;
begin
  Host := TForm.CreateNew(nil);
  try
    Source := ArrangeSource(True);
    Keep := Source;
    Board := ArrangeBoard(Host, Keep);
    // Akzeptanz: „Bereich hinzufügen“ listet alle Bereiche; sichtbare sind abgehakt.
    Board.BuildAddMenu;
    Assert.AreEqual(4, Board.BarMenu.Items.Count);
    Assert.IsTrue(Board.BarMenu.Items[0].Checked);
    Assert.IsFalse(Board.BarMenu.Items[0].Enabled);
    Assert.IsFalse(Board.BarMenu.Items[2].Checked);
    Assert.IsTrue(Board.BarMenu.Items[2].Enabled);
    Assert.AreEqual('Testergebnisse – Letzter Lauf', StripHotkey(Board.BarMenu.Items[2].Caption));
    // Der Ausgeblendete erscheint an der Einfügelinie.
    Board.SetTarget(0, TAtlasWelcomeIds.Projects);
    Board.Target(Column, Before);
    Assert.AreEqual(0, Column);
    Assert.AreEqual(Board.View(TAtlasWelcomeIds.Projects).Top - TAtlasWelcomeBoardFrame.Gap div 2 - 1,
      Board.InsertLine.Top);
    Board.BarMenu.Items[2].Click;
    CheckSynchronize;
    Assert.AreEqual('show atlas.tests 0 atlas.projects', Source.Last);
    // Danach wieder die Vorgabe: Ende der Spalte mit dem meisten Platz (rechts steht nur die Kachel).
    Board.Target(Column, Before);
    Assert.AreEqual(1, Column);
    Assert.AreEqual('', Before);
    Board.HiddenBar.ClickPart(Board.HiddenBar.IndexOf(TAtlasArrangePartKind.Hidden, TAtlasWelcomeIds.Tests));
    CheckSynchronize;
    Assert.AreEqual('show atlas.tests 1 ', Source.Last);
  finally
    Host.Free;
    TAtlasWelcomeViews.Release;
  end;
end;

procedure TAtlasWelcomeArrangeBoardTests.LayoutMenuSwitchesAndAsksNames;
var
  Host: TForm;
  Board: TAtlasWelcomeBoardFrame;
  Source: TFakeArrangeSource;
  Keep: IAtlasWelcomeArrangeSource;
  Answer, Told: string;
begin
  Host := TForm.CreateNew(nil);
  try
    Source := ArrangeSource(False);
    Source.Names := ['Arbeit', 'Präsentation'];
    Source.Active := 'Arbeit';
    Keep := Source;
    Board := ArrangeBoard(Host, Keep);
    // Akzeptanz: zwei Layouts lassen sich im Kopf umschalten, auch ohne Bearbeitungsmodus.
    Assert.IsTrue(Board.Bar.IndexOf(TAtlasArrangePartKind.Layout, '') >= 0);
    Board.BuildLayoutMenu;
    Assert.AreEqual(6, Board.BarMenu.Items.Count, 'zwei Layouts, Strich, Neu, Umbenennen, Löschen');
    Assert.IsTrue(Board.BarMenu.Items[0].Checked);
    Assert.IsTrue(Board.BarMenu.Items[5].Enabled);
    Board.BarMenu.Items[1].Click;
    CheckSynchronize;
    Assert.AreEqual('switch Präsentation', Source.Last);
    // Neu: vergebener Name wird gemeldet, nichts angelegt.
    Board.OnAskName :=
      function(const APrompt: string; var AName: string): Boolean
      begin
        AName := Answer;
        Result := True;
      end;
    Board.OnConfirm :=
      function(const AText: string; AQuestion: Boolean): Boolean
      begin
        Told := AText;
        Result := True;
      end;
    Source.Calls := nil;
    Answer := 'arbeit';
    Board.BarMenu.Items[3].Click;
    CheckSynchronize;
    Assert.AreEqual(0, Integer(Length(Source.Calls)));
    Assert.IsTrue(Pos('arbeit', Told) > 0);
    Answer := ' Vortrag ';
    Board.BarMenu.Items[3].Click;
    CheckSynchronize;
    Assert.AreEqual('add Vortrag', Source.Last);
    Answer := 'Arbeit 2';
    Board.BarMenu.Items[4].Click;
    CheckSynchronize;
    Assert.AreEqual('rename Arbeit 2', Source.Last);
    Board.BarMenu.Items[5].Click;
    CheckSynchronize;
    Assert.AreEqual('delete', Source.Last);
  finally
    Host.Free;
    TAtlasWelcomeViews.Release;
  end;
end;

procedure TAtlasWelcomeArrangeBoardTests.SectionMenuHidesAndOpensSettings;
var
  Host: TForm;
  Board: TAtlasWelcomeBoardFrame;
  Source: TFakeArrangeSource;
  Keep: IAtlasWelcomeArrangeSource;
begin
  Host := TForm.CreateNew(nil);
  try
    Source := ArrangeSource(False);
    Keep := Source;
    Board := ArrangeBoard(Host, Keep);
    Board.PrepareSectionMenu(TAtlasWelcomeIds.State);
    Assert.IsTrue(Board.SectionMenu.Items[0].Enabled);
    Assert.IsTrue(Board.SectionMenu.Items[3].Visible, '„Seite anpassen“');
    Board.SectionMenu.Items[0].Click;
    CheckSynchronize;
    Assert.AreEqual('hideAt ' + TAtlasWelcomeIds.State, Source.Last);
    Board.SectionMenu.Items[1].Click;
    CheckSynchronize;
    Assert.AreEqual('settings ' + TAtlasWelcomeIds.State, Source.Last);
    Board.SectionMenu.Items[3].Click;
    CheckSynchronize;
    Assert.AreEqual('edit True', Source.Last);
    // Fremder Bereich ohne Schalter: nichts auszublenden.
    Board.PrepareSectionMenu('plugin.fremd');
    Assert.IsFalse(Board.SectionMenu.Items[0].Enabled);
    // Ohne welcomePage.customLayout: „Ausblenden“ bleibt, „Seite anpassen“ fehlt.
    Source.Can := False;
    Board.Rebuild([Section(TAtlasWelcomeIds.State, 10, TAtlasWelcomeColumn.Right)], TAtlasWelcomeLayout.Atlas, 2);
    Board.PrepareSectionMenu(TAtlasWelcomeIds.State);
    Assert.IsTrue(Board.SectionMenu.Items[0].Enabled);
    Assert.IsFalse(Board.SectionMenu.Items[3].Visible);
  finally
    Host.Free;
    TAtlasWelcomeViews.Release;
  end;
end;

{ TAtlasWelcomeSearchBoxTests }

function SampleQuery: TAtlasWelcomeSearchQuery;
begin
  Result :=
    function(const APattern: string): TArray<TAtlasWelcomeSearchResult>
    var
      Hits: TArray<TAtlasWelcomeHit>;
    begin
      Hits := [TAtlasWelcomeHit.Create(TAtlasWelcomeSearchGroup.Files, 'Atlas.IDE.Expert.WelcomePage.pas', 'Atlas',
        'C:\P\Atlas.IDE.Expert.WelcomePage.pas'),
        TAtlasWelcomeHit.Create(TAtlasWelcomeSearchGroup.Files, 'Welcome.pas', 'Atlas', 'C:\P\Welcome.pas'),
        TAtlasWelcomeHit.Create(TAtlasWelcomeSearchGroup.Commands, 'Atlas-Layout anwenden', '', 'Atlas.WelcomeApply')];
      Hits[2].Alias := 'WelcomeApply';
      Result := TAtlasWelcomeSearch.Search(APattern, Hits, 'Hinweis');
    end;
end;

procedure TAtlasWelcomeSearchBoxTests.HeaderShowsAndHidesSearch;
var
  Header: TAtlasWelcomeHeaderFrame;
begin
  Header := TAtlasWelcomeHeaderFrame.Create(nil);
  try
    Assert.IsNull(Header.Search);
    Assert.AreEqual(0, Header.SearchHost.Width);
    Header.ShowSearch(True);
    Assert.IsNotNull(Header.Search);
    Assert.IsTrue(Header.Search.Visible);
    Assert.IsTrue(Header.SearchHost.Width > 0);
    Header.Search.Edit.Text := 'wel';
    Header.ShowSearch(False);
    Assert.IsFalse(Header.Search.Visible);
    Assert.AreEqual('', Header.Search.Edit.Text);
    Assert.AreEqual(0, Header.SearchHost.Width);
  finally
    Header.Free;
  end;
end;

procedure TAtlasWelcomeSearchBoxTests.QueryFillsHitsAndRows;
var
  Box: TAtlasWelcomeSearchBox;
begin
  Box := TAtlasWelcomeSearchBox.Create(nil);
  try
    Box.OnQuery := SampleQuery();
    Box.Edit.Text := 'wel';
    Box.Query;
    // Dateien (2), Symbole mit Hinweis, Befehle (1).
    Assert.AreEqual(3, Integer(Length(Box.Hits)));
    Assert.AreEqual(3, Integer(Length(Box.Results)));
    Assert.AreEqual(7, Integer(Length(Box.Rows)));
    Assert.AreEqual(0, Box.Selected);
    Box.Edit.Text := '';
    Assert.AreEqual(0, Integer(Length(Box.Hits)));
    Assert.AreEqual(-1, Box.Selected);
  finally
    Box.Free;
  end;
end;

procedure TAtlasWelcomeSearchBoxTests.SelectStaysInRange;
var
  Box: TAtlasWelcomeSearchBox;
begin
  Box := TAtlasWelcomeSearchBox.Create(nil);
  try
    Box.OnQuery := SampleQuery();
    Box.Edit.Text := 'wel';
    Box.Query;
    Box.Select(-5);
    Assert.AreEqual(0, Box.Selected);
    Box.Select(2);
    Assert.AreEqual(2, Box.Selected);
    Box.Select(9);
    Assert.AreEqual(2, Box.Selected);
  finally
    Box.Free;
  end;
end;

procedure TAtlasWelcomeSearchBoxTests.OpenSelectedHandsHitAndClears;
var
  Box: TAtlasWelcomeSearchBox;
  Opened: string;
begin
  Opened := '';
  Box := TAtlasWelcomeSearchBox.Create(nil);
  try
    Box.OnQuery := SampleQuery();
    Box.OnOpen :=
      procedure(const AHit: TAtlasWelcomeHit)
      begin
        Opened := AHit.Target;
      end;
    Box.Edit.Text := 'wel';
    Box.Query;
    Box.Select(2);
    Box.OpenSelected;
    // Geöffnet wird nach dem Schließen der Liste über die Warteschlange.
    Assert.AreEqual('', Box.Edit.Text);
    Assert.AreEqual(0, Integer(Length(Box.Hits)));
    CheckSynchronize;
    Assert.AreEqual('Atlas.WelcomeApply', Opened);
    // Esc bzw. Clear ohne Treffer öffnet nichts.
    Opened := '';
    Box.OpenSelected;
    CheckSynchronize;
    Assert.AreEqual('', Opened);
  finally
    Box.Free;
  end;
end;

procedure TAtlasWelcomeSearchBoxTests.GroupCaptionsFollowLanguage;
var
  Saved: TAtlasLanguage;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('Projekte', TAtlasWelcomeSearchBox.GroupCaption(TAtlasWelcomeSearchGroup.Projects));
    Assert.AreEqual('Befehle', TAtlasWelcomeSearchBox.GroupCaption(TAtlasWelcomeSearchGroup.Commands));
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('Files', TAtlasWelcomeSearchBox.GroupCaption(TAtlasWelcomeSearchGroup.Files));
    Assert.AreEqual('Symbols', TAtlasWelcomeSearchBox.GroupCaption(TAtlasWelcomeSearchGroup.Symbols));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

{ TAtlasWelcomeWhatsNewFrameTests }

procedure TAtlasWelcomeWhatsNewFrameTests.WarmUpFirstUse;
begin
  UnreadShowsRowsWithSwitchKeyAndTry;
end;

procedure TAtlasWelcomeWhatsNewFrameTests.UnreadShowsRowsWithSwitchKeyAndTry;
var
  Host: TForm;
  Fake: TFakeWhatsNew;
  Source: IAtlasWhatsNewSource;
  Frame: TAtlasWelcomeWhatsNewFrame;
begin
  Fake := TFakeWhatsNew.Create;
  Source := Fake;
  Fake.FView := TAtlasWhatsNewView.Unread;
  Fake.FVersions := [NewsVersion('1.1.0', [NewsItem('Suchfeld', 'An', 'Taste', 'Atlas.WelcomeStart'),
    NewsItem('Ohne alles', '', '', ''), NewsItem('Aus', 'Aus', '', '')])];
  Host := TForm.CreateNew(nil);
  try
    Frame := NewsFrame(Host, Source);
    Assert.AreEqual(3, Integer(Length(Frame.Rows)));
    Assert.AreEqual(0, Integer(Length(Frame.Headings)), 'eine Version: keine Überschrift');
    Assert.AreEqual('Suchfeld', Frame.Rows[0].Title.Caption);
    Assert.AreEqual('Ctrl+E', Frame.Rows[0].Key.Caption, 'tatsächliche Belegung');
    Assert.IsTrue(Frame.Rows[0].Switch.Checked);
    Assert.IsNotNull(Frame.Rows[0].TryButton);
    Assert.IsNull(Frame.Rows[1].Key);
    Assert.IsNull(Frame.Rows[1].Switch, 'ohne Einstellung kein Schalter');
    Assert.IsNull(Frame.Rows[1].TryButton, 'ohne Befehl und Beispiel kein „Ausprobieren“');
    Assert.IsFalse(Frame.Rows[2].Switch.Checked);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.WelcomeNewsRead), Frame.DismissButton.Caption);
    Assert.IsTrue(Frame.Rows[1].Title.Top > Frame.Rows[0].Text.Top, 'Zeilen untereinander');
    Assert.IsTrue(Frame.Rows[0].Switch.Left > Frame.Rows[0].Title.Left + Frame.Rows[0].Title.Width,
      'Schalter rechts vom Titel');
    Assert.IsTrue(Frame.PreferredHeight > Frame.DismissButton.Top, 'Höhe nach dem Inhalt');
    Assert.AreSame(Source, Frame.Menu.Source);
    // Danach ohne Ungelesenes: „Schließen“ statt „Gelesen“.
    Fake.FView := TAtlasWhatsNewView.Current;
    Frame.UpdateContent;
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.WelcomeNewsClose), Frame.DismissButton.Caption);
    Fake.FView := TAtlasWhatsNewView.Hidden;
    Fake.FVersions := nil;
    Frame.UpdateContent;
    Assert.IsNull(Frame.DismissButton);
    Assert.AreEqual(0, Integer(Length(Frame.Rows)));
  finally
    Host.Free;
  end;
end;

procedure TAtlasWelcomeWhatsNewFrameTests.JumpGroupsByVersion;
var
  Host: TForm;
  Fake: TFakeWhatsNew;
  Source: IAtlasWhatsNewSource;
  Frame: TAtlasWelcomeWhatsNewFrame;
begin
  Fake := TFakeWhatsNew.Create;
  Source := Fake;
  Fake.FView := TAtlasWhatsNewView.Unread;
  Fake.FVersions := [NewsVersion('1.2.0', [NewsItem('Neu 2', '', '', '')]),
    NewsVersion('1.1.0', [NewsItem('Neu 1a', '', '', ''), NewsItem('Neu 1b', '', '', '')])];
  Host := TForm.CreateNew(nil);
  try
    Frame := NewsFrame(Host, Source);
    Assert.AreEqual(2, Integer(Length(Frame.Headings)));
    Assert.AreEqual(3, Integer(Length(Frame.Rows)), 'Neuerungen aller übersprungenen Versionen');
    Assert.AreEqual(TAtlasWelcomeWhatsNewFrame.HeadingText('1.2.0', False, True), Frame.Headings[0].Caption);
    Assert.AreEqual('1.1.0', Frame.Rows[1].Version);
    Assert.IsTrue(Frame.Headings[1].Top > Frame.Rows[0].Title.Top, 'Gruppe 1.1.0 unter 1.2.0');
    Assert.IsTrue(Frame.Rows[1].Title.Top > Frame.Headings[1].Top);
  finally
    Host.Free;
  end;
end;

procedure TAtlasWelcomeWhatsNewFrameTests.AllVersionsCollapseExceptNewest;
var
  Host: TForm;
  Fake: TFakeWhatsNew;
  Source: IAtlasWhatsNewSource;
  Frame: TAtlasWelcomeWhatsNewFrame;
begin
  Fake := TFakeWhatsNew.Create;
  Source := Fake;
  Fake.FView := TAtlasWhatsNewView.All;
  Fake.FVersions := [NewsVersion('1.2.0', [NewsItem('Neu 2', '', '', '')]),
    NewsVersion('1.1.0', [NewsItem('Neu 1', '', '', '')]), NewsVersion('1.0.0', [NewsItem('Erste', '', '', '')])];
  Host := TForm.CreateNew(nil);
  try
    Frame := NewsFrame(Host, Source);
    Assert.AreEqual(3, Integer(Length(Frame.Headings)));
    Assert.AreEqual(1, Integer(Length(Frame.Rows)), 'nur die neueste aufgeklappt');
    Assert.IsTrue(Frame.IsExpanded('1.2.0'));
    Assert.IsFalse(Frame.IsExpanded('1.0.0'));
    Assert.AreEqual(TAtlasWelcomeWhatsNewFrame.HeadingText('1.0.0', True, False), Frame.Headings[2].Caption);
    Assert.AreNotEqual(TAtlasWelcomeWhatsNewFrame.HeadingText('1.0.0', True, False),
      TAtlasWelcomeWhatsNewFrame.HeadingText('1.0.0', True, True), 'Pfeil zeigt den Zustand');
    Frame.Toggle('1.0.0');
    Assert.AreEqual(2, Integer(Length(Frame.Rows)));
    Assert.AreEqual('Erste', Frame.Rows[1].Title.Caption);
    Frame.Toggle('1.2.0');
    Assert.AreEqual(1, Integer(Length(Frame.Rows)));
    // Neu lesen behält den Zustand, solange „Alle Versionen“ bleibt.
    Frame.UpdateContent;
    Assert.AreEqual('Erste', Frame.Rows[0].Title.Caption);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.WelcomeNewsClose), Frame.DismissButton.Caption);
  finally
    Host.Free;
  end;
end;

procedure TAtlasWelcomeWhatsNewFrameTests.ClicksReachSource;
var
  Host: TForm;
  Fake: TFakeWhatsNew;
  Source: IAtlasWhatsNewSource;
  Frame: TAtlasWelcomeWhatsNewFrame;
begin
  Fake := TFakeWhatsNew.Create;
  Source := Fake;
  Fake.FView := TAtlasWhatsNewView.Unread;
  Fake.FVersions := [NewsVersion('1.1.0', [NewsItem('Suchfeld', 'An', 'Taste', 'Atlas.WelcomeStart')])];
  Host := TForm.CreateNew(nil);
  try
    Frame := NewsFrame(Host, Source);
    Frame.Rows[0].Switch.Checked := False;
    Frame.Rows[0].TryButton.Click;
    Frame.DismissButton.Click;
    Frame.Menu.AllItem.Click;
    Frame.Menu.CurrentItem.Click;
    // Alles läuft über die Nachrichtenschleife.
    Assert.AreEqual(0, Integer(Length(Fake.Calls)));
    CheckSynchronize;
    Assert.AreEqual(5, Integer(Length(Fake.Calls)));
    Assert.AreEqual('switch An False', Fake.Calls[0]);
    Assert.AreEqual('try Suchfeld', Fake.Calls[1]);
    Assert.AreEqual('dismiss', Fake.Calls[2]);
    Assert.AreEqual(Format('show %d', [Ord(TAtlasWhatsNewView.All)]), Fake.Calls[3]);
    Assert.AreEqual(Format('show %d', [Ord(TAtlasWhatsNewView.Current)]), Fake.Calls[4]);
    // Neu lesen setzt den Schalter, ohne die Quelle zu rufen.
    Frame.UpdateContent;
    CheckSynchronize;
    Assert.AreEqual(5, Integer(Length(Fake.Calls)));
  finally
    Host.Free;
  end;
end;

procedure TAtlasWelcomeWhatsNewFrameTests.TitleNamesSingleVersion;
var
  Saved: TAtlasLanguage;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('Neu in Atlas 1.1.0', TAtlasWelcomeWhatsNewFrame.TitleFor(TAtlasWhatsNewView.Unread,
      [NewsVersion('1.1.0', [NewsItem('A', '', '', '')])]));
    Assert.AreEqual('Neu in Atlas', TAtlasWelcomeWhatsNewFrame.TitleFor(TAtlasWhatsNewView.Unread,
      [NewsVersion('1.2.0', [NewsItem('A', '', '', '')]), NewsVersion('1.1.0', [NewsItem('B', '', '', '')])]));
    Assert.AreEqual('Neu in Atlas', TAtlasWelcomeWhatsNewFrame.TitleFor(TAtlasWhatsNewView.All,
      [NewsVersion('1.1.0', [NewsItem('A', '', '', '')])]));
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('New in Atlas 1.1.0', TAtlasWelcomeWhatsNewFrame.TitleFor(TAtlasWhatsNewView.Current,
      [NewsVersion('1.1.0', [NewsItem('A', '', '', '')])]));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasWelcomeWhatsNewFrameTests.BoardSizesCardToItsText;
var
  Host: TForm;
  Board: TAtlasWelcomeBoardFrame;
  Fake: TFakeWhatsNew;
  Source: IAtlasWhatsNewSource;
  Card: TAtlasWelcomeSectionFrame;
  Narrow, Wide: Integer;
begin
  Fake := TFakeWhatsNew.Create;
  Source := Fake;
  Fake.FView := TAtlasWhatsNewView.Unread;
  Fake.FVersions := [NewsVersion('1.1.0', [NewsItem('Suchfeld', 'An', 'Taste', 'Atlas.WelcomeStart'),
    NewsItem('Zweite', 'Aus', '', '')])];
  TAtlasWelcomeViews.Register(TAtlasWelcomeIds.News,
    function(AOwner: TComponent): TAtlasWelcomeSectionFrame
    var
      Frame: TAtlasWelcomeWhatsNewFrame;
    begin
      Frame := TAtlasWelcomeWhatsNewFrame.Create(AOwner);
      Frame.Source := Source;
      Result := Frame;
    end);
  Host := TForm.CreateNew(nil);
  try
    Host.ClientWidth := 1200;
    Host.ClientHeight := 600;
    Board := TAtlasWelcomeBoardFrame.Create(Host);
    Board.Parent := Host;
    Board.Align := alClient;
    // Nach einem Update oben links (#756).
    Board.Rebuild([Section(TAtlasWelcomeIds.News, 50, TAtlasWelcomeColumn.Right)],
      TAtlasWelcomeLayout.Atlas.MovedToTop(TAtlasWelcomeIds.News), 2);
    Card := Board.View(TAtlasWelcomeIds.News);
    Assert.IsNotNull(Card);
    Assert.AreEqual(TAtlasWelcomeIds.News, Board.Columns[0][0]);
    Assert.AreEqual(Card.PreferredHeight, Card.Height, 'Höhe nach der gesetzten Breite');
    Assert.IsTrue(Assigned(Card.OnHeightChanged), 'Aufklappen ordnet die Spalten neu');
    // Schmal: Der Text bricht um, die Karte wird höher.
    Card.Width := 900;
    Wide := Card.PreferredHeight;
    Card.Width := 260;
    Narrow := Card.PreferredHeight;
    Assert.IsTrue(Narrow > Wide, Format('schmal %d, breit %d', [Narrow, Wide]));
  finally
    Host.Free;
    TAtlasWelcomeViews.Release;
  end;
end;

{ TAtlasWelcomeProjectsFrameTests }

procedure TAtlasWelcomeProjectsFrameTests.WarmUpFirstUse;
begin
  RowsSetHeightAndAskForRefresh;
end;

procedure TAtlasWelcomeProjectsFrameTests.PillTextsFollowKind;
var
  Saved: TAtlasLanguage;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('Build 0/0/0', TAtlasWelcomeProjectsFrame.PillText(
      TAtlasProjectPill.Create(TAtlasProjectPillKind.Build, TAtlasProjectPillLevel.Good, 0, 0, 0)));
    Assert.AreEqual('Build 0/3/1', TAtlasWelcomeProjectsFrame.PillText(
      TAtlasProjectPill.Create(TAtlasProjectPillKind.Build, TAtlasProjectPillLevel.Warning, 0, 3, 1)));
    Assert.AreEqual('2 Fehler', TAtlasWelcomeProjectsFrame.PillText(
      TAtlasProjectPill.Create(TAtlasProjectPillKind.BuildErrors, TAtlasProjectPillLevel.Error, 2, 0, 0)));
    Assert.AreEqual('Prüfung: 1 Fehler', TAtlasWelcomeProjectsFrame.PillText(
      TAtlasProjectPill.Create(TAtlasProjectPillKind.CheckErrors, TAtlasProjectPillLevel.Error, 1, 0, 0)));
    Assert.AreEqual('3 geändert', TAtlasWelcomeProjectsFrame.PillText(
      TAtlasProjectPill.Create(TAtlasProjectPillKind.Changes, TAtlasProjectPillLevel.Warning, 3, 0, 0)));
    Assert.AreEqual(#$2191'1 '#$2193'2', TAtlasWelcomeProjectsFrame.PillText(
      TAtlasProjectPill.Create(TAtlasProjectPillKind.Sync, TAtlasProjectPillLevel.Neutral, 1, 2, 0)));
    Assert.AreEqual('5 neue Treffer', TAtlasWelcomeProjectsFrame.PillText(
      TAtlasProjectPill.Create(TAtlasProjectPillKind.Rules, TAtlasProjectPillLevel.Warning, 5, 0, 0)));
    Assert.AreNotEqual(Integer(TAtlasWelcomeProjectsFrame.PillColor(TAtlasProjectPillLevel.Good)),
      Integer(TAtlasWelcomeProjectsFrame.PillColor(TAtlasProjectPillLevel.Error)));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasWelcomeProjectsFrameTests.RowsSetHeightAndAskForRefresh;
var
  Host: TForm;
  Fake: TFakeProjects;
  Source: IAtlasProjectsSource;
  Frame: TAtlasWelcomeProjectsFrame;
  Empty, Two: Integer;
begin
  Fake := TFakeProjects.Create;
  Source := Fake;
  Host := TForm.CreateNew(nil);
  try
    Frame := ProjectsFrame(Host, Source);
    Assert.AreEqual(1, Integer(Length(Fake.Calls)), 'beim Anzeigen frisch abfragen');
    Assert.AreEqual('shown', Fake.Calls[0]);
    Assert.AreEqual(0, Integer(Length(Frame.Entries)));
    Empty := Frame.PreferredHeight;
    Fake.FEntries := [ProjectEntry('C:\P\Eins.dproj', 0), ProjectEntry('C:\P\Zwei.dproj', 2)];
    Frame.UpdateContent;
    Assert.AreEqual(2, Integer(Length(Frame.Entries)));
    Two := Frame.PreferredHeight;
    Assert.IsTrue(Two > Empty, Format('leer %d, zwei Zeilen %d', [Empty, Two]));
    Assert.AreEqual(1, Integer(Length(Fake.Calls)), 'Neu lesen fragt nicht erneut ab');
  finally
    Host.Free;
  end;
end;

procedure TAtlasWelcomeProjectsFrameTests.DetailAndHintNameState;
var
  Saved: TAtlasLanguage;
  Item: TAtlasProjectEntry;
  Hint, Detail: string;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Item := ProjectEntry('C:\P\Zwei.dproj', 2);
    Detail := TAtlasWelcomeProjectsFrame.DetailText(Item);
    Assert.Contains(Detail, 'C:\P\Zwei.dproj');
    Assert.Contains(Detail, 'Stand vom', 'gespeicherter Stand');
    Item.VcsFresh := True;
    Assert.IsFalse(TAtlasWelcomeProjectsFrame.DetailText(Item).Contains('Stand vom'), 'frisch abgefragt');
    Hint := TAtlasWelcomeProjectsFrame.HintFor(Item);
    Assert.Contains(Hint, 'main');
    Assert.Contains(Hint, '2 Fehler');
    Assert.Contains(Hint, 'Main.pas (12)');
    Assert.Contains(Hint, 'E2003');
    Item.Summary.Build := TAtlasProjectBuild.Empty;
    Assert.Contains(TAtlasWelcomeProjectsFrame.HintFor(Item),
      TAtlasStrings.Text(TAtlasTextId.WelcomeProjectsHintNoBuild));
    Assert.AreEqual('', TAtlasWelcomeProjectsFrame.LocalText(0));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasWelcomeProjectsFrameTests.ClicksReachSource;
var
  Host: TForm;
  Fake: TFakeProjects;
  Source: IAtlasProjectsSource;
  Frame: TAtlasWelcomeProjectsFrame;
  Hit: TAtlasProjectsHit;
begin
  Fake := TFakeProjects.Create;
  Source := Fake;
  Fake.FEntries := [ProjectEntry('C:\P\Eins.dproj', 0), ProjectEntry('C:\P\Zwei.dproj', 2)];
  Host := TForm.CreateNew(nil);
  try
    Frame := ProjectsFrame(Host, Source);
    Fake.Calls := nil;
    Hit.Row := 0;
    Hit.Pill := -1;
    Frame.ClickAt(Hit);
    // Rote Marke: Projekt öffnen und zur ersten Meldung springen.
    Hit.Row := 1;
    Hit.Pill := 0;
    Frame.ClickAt(Hit);
    // Grüne Marke ist kein Sprungziel: öffnet nur das Projekt.
    Hit.Row := 0;
    Hit.Pill := 0;
    Frame.ClickAt(Hit);
    Frame.MenuRow := 1;
    Frame.OpenFolderItem.Click;
    Frame.RemoveItem.Click;
    Assert.AreEqual(0, Integer(Length(Fake.Calls)), 'alles über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(5, Integer(Length(Fake.Calls)));
    Assert.AreEqual('open C:\P\Eins.dproj', Fake.Calls[0]);
    Assert.AreEqual('openAt C:\P\Zwei.dproj C:\P\Main.pas 12', Fake.Calls[1]);
    Assert.AreEqual('open C:\P\Eins.dproj', Fake.Calls[2]);
    Assert.AreEqual('folder C:\P\Zwei.dproj', Fake.Calls[3]);
    Assert.AreEqual('remove C:\P\Zwei.dproj', Fake.Calls[4]);
  finally
    Host.Free;
  end;
end;

procedure TAtlasWelcomeProjectsFrameTests.HitTestFindsRows;
var
  Host: TForm;
  Fake: TFakeProjects;
  Source: IAtlasProjectsSource;
  Frame: TAtlasWelcomeProjectsFrame;
  Row: Integer;
begin
  Fake := TFakeProjects.Create;
  Source := Fake;
  Fake.FEntries := [ProjectEntry('C:\P\Eins.dproj', 0), ProjectEntry('C:\P\Zwei.dproj', 0)];
  Host := TForm.CreateNew(nil);
  try
    Frame := ProjectsFrame(Host, Source);
    Row := Frame.ScaleValue(TAtlasWelcomeProjectsFrame.RowHeight);
    Assert.AreEqual(0, Frame.HitTest(20, Row div 2).Row);
    Assert.AreEqual(1, Frame.HitTest(20, Row + Row div 2).Row);
    Assert.AreEqual(-1, Frame.HitTest(20, 5 * Row).Row, 'unter der letzten Zeile');
  finally
    Host.Free;
  end;
end;

procedure TAtlasWelcomeProjectsFrameTests.QuickActionsInRows;
var
  Host: TForm;
  Fake: TFakeProjects;
  Source: IAtlasProjectsSource;
  Quick: TAtlasFakeQuickActions;
  QuickSource: IAtlasQuickActionsSource;
  Frame: TAtlasWelcomeProjectsFrame;
begin
  Fake := TFakeProjects.Create;
  Source := Fake;
  Quick := TAtlasFakeQuickActions.Create;
  QuickSource := Quick;
  Fake.FEntries := [ProjectEntry('C:\P\Eins.dproj', 0), ProjectEntry('C:\P\Zwei.dproj', 0)];
  Host := TForm.CreateNew(nil);
  try
    Frame := ProjectsFrame(Host, Source);
    Frame.QuickActions := QuickSource;
    Assert.AreEqual(6, Integer(Length(Frame.Quick.ButtonsOf(0))));
    // items ohne console: nur dieser Knopf fehlt.
    Quick.Items := TAtlasWelcomeQuickActions.ParseItems('build,tests,run,pull,folder');
    Frame.UpdateContent;
    Assert.AreEqual(5, Integer(Length(Frame.Quick.ButtonsOf(0))));
    Assert.AreEqual(-1, TAtlasWelcomeQuickActions.IndexOf(Frame.Quick.ButtonsOf(0), TAtlasQuickAction.Console));
    Fake.Calls := nil;
    // Ohne Maus: Pfeil ab, Strg+B, Strg+T, Pos1 und Enter öffnet.
    Quick.FTests := ['C:\P\Tests\Zwei.Tests.dproj'];
    Assert.IsTrue(Frame.Quick.HandleKey(VK_DOWN, []));
    Assert.IsTrue(Frame.Quick.HandleKey(Ord('B'), [ssCtrl]));
    Assert.IsTrue(Frame.Quick.HandleKey(Ord('T'), [ssCtrl]));
    Assert.IsTrue(Frame.Quick.HandleKey(VK_HOME, []));
    Assert.IsTrue(Frame.Quick.HandleKey(VK_RETURN, []));
    Assert.AreEqual(0, Integer(Length(Quick.Calls)), 'alles über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(2, Integer(Length(Quick.Calls)));
    Assert.AreEqual('build C:\P\Zwei.dproj', Quick.Calls[0]);
    Assert.AreEqual('tests C:\P\Zwei.dproj', Quick.Calls[1]);
    Assert.AreEqual(1, Integer(Length(Fake.Calls)));
    Assert.AreEqual('open C:\P\Zwei.dproj', Fake.Calls[0]);
    // Ausgeschaltet bzw. ohne Quelle: keine Knöpfe, Tasten bleiben bei der IDE.
    Quick.IsOn := False;
    Frame.UpdateContent;
    Assert.AreEqual(0, Integer(Length(Frame.Quick.ButtonsOf(0))));
    Assert.IsFalse(Frame.Quick.HandleKey(Ord('B'), [ssCtrl]));
    Frame.QuickActions := nil;
    Assert.IsFalse(Frame.Quick.Active);
  finally
    Host.Free;
  end;
end;

procedure TAtlasWelcomeProjectsFrameTests.ClickSelectsForHistory;
var
  Host: TForm;
  Fake: TFakeProjects;
  Source: IAtlasProjectsSource;
  Frame: TAtlasWelcomeProjectsFrame;
  Hit: TAtlasProjectsHit;
begin
  Fake := TFakeProjects.Create;
  Source := Fake;
  Fake.FEntries := [ProjectEntry('C:\P\Eins.dproj', 0), ProjectEntry('C:\P\Zwei.dproj', 2)];
  Host := TForm.CreateNew(nil);
  try
    Frame := ProjectsFrame(Host, Source);
    Assert.AreEqual(-1, Frame.SelectedRow, 'ohne Projektverlauf keine Auswahl');
    Hit.Row := 0;
    Hit.Pill := -1;
    Fake.Calls := nil;
    Frame.DoubleClickAt(Hit);
    CheckSynchronize;
    Assert.AreEqual(0, Integer(Length(Fake.Calls)), 'ohne Auswahl öffnet schon der Klick');
    Fake.FSelectable := True;
    Assert.AreEqual(0, Frame.SelectedRow, 'ohne Auswahl das oberste');
    Hit.Row := 1;
    Frame.ClickAt(Hit);
    // Rote Marke springt weiter.
    Hit.Pill := 0;
    Frame.ClickAt(Hit);
    Hit.Row := 0;
    Hit.Pill := -1;
    Frame.DoubleClickAt(Hit);
    Frame.MenuRow := 1;
    Frame.OpenItem.Click;
    Assert.AreEqual(0, Integer(Length(Fake.Calls)), 'alles über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(4, Integer(Length(Fake.Calls)));
    Assert.AreEqual('select C:\P\Zwei.dproj', Fake.Calls[0]);
    Assert.AreEqual('openAt C:\P\Zwei.dproj C:\P\Main.pas 12', Fake.Calls[1]);
    Assert.AreEqual('open C:\P\Eins.dproj', Fake.Calls[2]);
    Assert.AreEqual('open C:\P\Zwei.dproj', Fake.Calls[3]);
    Assert.AreEqual(1, Frame.SelectedRow);
    Fake.FSelected := 'c:/p/eins.DPROJ';
    Assert.AreEqual(0, Frame.SelectedRow, 'Schreibweise egal');
    Assert.Contains(TAtlasWelcomeProjectsFrame.HintFor(Fake.FEntries[0], True),
      TAtlasStrings.Text(TAtlasTextId.WelcomeProjectsHintSelect));
    Assert.Contains(TAtlasWelcomeProjectsFrame.HintFor(Fake.FEntries[0], False),
      TAtlasStrings.Text(TAtlasTextId.WelcomeProjectsHintClick));
  finally
    Host.Free;
  end;
end;

{ TAtlasWelcomeTrendsFrameTests }

procedure TAtlasWelcomeTrendsFrameTests.TextsShowValueAndPrevious;
var
  Saved: TAtlasLanguage;
  View: TAtlasTrendView;
  Tile: TAtlasTrendTile;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    View := TAtlasWelcomeTrends.View(TrendSummary('C:\P\Kasse.dproj', [12, 9, 6, 3, 0]),
      TAtlasWelcomeTrends.ParseSeries(TAtlasWelcomeTrends.DefaultSeries), 30);
    Assert.AreEqual(5, Integer(Length(View.Tiles)));
    Tile := View.Tiles[0];
    Assert.AreEqual('0', TAtlasWelcomeTrendsFrame.ValueLine(Tile));
    Assert.AreEqual('vorher 3', TAtlasWelcomeTrendsFrame.PreviousLine(Tile));
    // Regeltreffer ohne Baseline: kein Wert statt 0, kein Vorwert.
    Tile := View.Tiles[1];
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.WelcomeTrendsNoValue), TAtlasWelcomeTrendsFrame.ValueLine(Tile));
    Assert.AreEqual('', TAtlasWelcomeTrendsFrame.PreviousLine(Tile));
    Assert.AreEqual('7', TAtlasWelcomeTrendsFrame.ValueLine(View.Tiles[2]));
    Assert.AreEqual('12,5 s', TAtlasWelcomeTrendsFrame.ValueLine(View.Tiles[3]));
    Assert.AreEqual('vorher 12,5 s', TAtlasWelcomeTrendsFrame.PreviousLine(View.Tiles[3]));
    Assert.AreEqual('11,8 Zeilen', TAtlasWelcomeTrendsFrame.ValueWithUnit(TAtlasTrendSeries.MethodLength, 118));
    Assert.AreEqual('Projektverlauf', TAtlasWelcomeTrendsFrame.TitleText);
    Assert.AreEqual('Warnungen + Hinweise', TAtlasWelcomeTrendsFrame.SeriesTitle(TAtlasTrendSeries.Warnings));
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('11.8 lines', TAtlasWelcomeTrendsFrame.ValueWithUnit(TAtlasTrendSeries.MethodLength, 118));
    Assert.AreEqual('before 3', TAtlasWelcomeTrendsFrame.PreviousLine(View.Tiles[0]));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasWelcomeTrendsFrameTests.ClickShowsBuild;
var
  Saved: TAtlasLanguage;
  Host: TForm;
  Fake: TFakeTrends;
  Source: IAtlasTrendsSource;
  Frame: TAtlasWelcomeTrendsFrame;
  Hit: TAtlasTrendsHit;
  Info: string;
begin
  Saved := TAtlasStrings.Language;
  Fake := TFakeTrends.Create;
  Source := Fake;
  Fake.FView := TAtlasWelcomeTrends.View(TrendSummary('C:\P\Kasse.dproj', [12, 9, 6, 3, 0]),
    TAtlasWelcomeTrends.ParseSeries(TAtlasWelcomeTrends.DefaultSeries), 30);
  Host := TForm.CreateNew(nil);
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Frame := TrendsFrame(Host, Source);
    Assert.AreEqual('Kasse · letzte 30 Builds', Frame.HeadingText);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.WelcomeTrendsClickHint), Frame.InfoText, 'vor dem Klick');
    Hit.Tile := 0;
    Hit.Point := 2;
    Frame.ClickAt(Hit);
    Assert.AreEqual(2, Frame.ChosenPoint);
    Assert.AreEqual(0, Frame.ChosenTile);
    Info := Frame.InfoText;
    Assert.Contains(Info, 'Build 3 von 5', 'Position wie im Mockup');
    Assert.IsFalse(Info.Contains('Nr.'), 'laufende Nummer gleich der Position: nicht doppelt');
    Assert.Contains(Info, TAtlasWelcomeTrendsFrame.LocalText(Fake.FView.Points[2].At), 'Datum');
    Assert.Contains(Info, 'main', 'Branch');
    Assert.Contains(Info, '1a2b3c2', 'Commit gekürzt');
    Assert.Contains(Info, 'Warnungen + Hinweise: 6', 'Wert');
    // Lücke: kein Wert.
    Hit.Tile := 2;
    Hit.Point := 0;
    Frame.ClickAt(Hit);
    Assert.Contains(Frame.InfoText, 'Offene TODOs: ' + TAtlasStrings.Text(TAtlasTextId.WelcomeTrendsNoValue));
    // Daneben: nichts ändert sich.
    Hit.Tile := -1;
    Hit.Point := -1;
    Frame.ClickAt(Hit);
    Assert.Contains(Frame.InfoText, 'Offene TODOs');
    // Neu laden (gleiches Projekt, neuer Build): Auswahl bleibt am Build.
    Frame.UpdateContent;
    Assert.AreEqual(0, Frame.ChosenPoint);
    // Nur die letzten 3 Builds gezeigt: Position in der Reihe, dazu die laufende Nummer.
    Fake.FView := TAtlasWelcomeTrends.View(TrendSummary('C:\P\Kasse.dproj', [12, 9, 6, 3, 0]),
      [TAtlasTrendSeries.Warnings], 3);
    Frame.UpdateContent;
    Hit.Tile := 0;
    Hit.Point := 0;
    Frame.ClickAt(Hit);
    Assert.Contains(Frame.InfoText, 'Build 1 von 3 · Nr. 3 · ');
    Info := TAtlasWelcomeTrendsFrame.PointInfo(Frame.View, 0, 0, False);
    Assert.Contains(Info, 'Build 1 von 3 · ');
    Assert.IsFalse(Info.Contains('Nr.'), 'ohne Platz ohne laufende Nummer');
    Assert.Contains(Info, 'Warnungen + Hinweise: 6');
  finally
    Host.Free;
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasWelcomeTrendsFrameTests.OtherProjectResetsChoice;
var
  Host: TForm;
  Fake: TFakeTrends;
  Source: IAtlasTrendsSource;
  Frame: TAtlasWelcomeTrendsFrame;
  Hit: TAtlasTrendsHit;
begin
  Fake := TFakeTrends.Create;
  Source := Fake;
  Fake.FView := TAtlasWelcomeTrends.View(TrendSummary('C:\P\Eins.dproj', [1, 2, 3]),
    [TAtlasTrendSeries.Warnings], 30);
  Host := TForm.CreateNew(nil);
  try
    Frame := TrendsFrame(Host, Source);
    Hit.Tile := 0;
    Hit.Point := 1;
    Frame.ClickAt(Hit);
    Assert.AreEqual(1, Frame.ChosenPoint);
    Fake.FView := TAtlasWelcomeTrends.View(TrendSummary('C:\P\Zwei.dproj', [8, 4]), [TAtlasTrendSeries.Warnings], 30);
    Frame.UpdateContent;
    Assert.AreEqual('C:\P\Zwei.dproj', Frame.View.Project);
    Assert.AreEqual(2, Integer(Length(Frame.View.Points)));
    Assert.AreEqual(-1, Frame.ChosenPoint, 'Punkt gehörte zum anderen Projekt');
    Assert.AreEqual(40, Frame.View.Tiles[0].Last);
  finally
    Host.Free;
  end;
end;

procedure TAtlasWelcomeTrendsFrameTests.HitTestFindsPoints;
var
  Host: TForm;
  Fake: TFakeTrends;
  Source: IAtlasTrendsSource;
  Frame: TAtlasWelcomeTrendsFrame;
  Tile, Spark: TRect;
  Hit: TAtlasTrendsHit;
begin
  Fake := TFakeTrends.Create;
  Source := Fake;
  Fake.FView := TAtlasWelcomeTrends.View(TrendSummary('C:\P\Kasse.dproj', [12, 9, 6, 3, 0]),
    [TAtlasTrendSeries.Warnings, TAtlasTrendSeries.Todos], 30);
  Host := TForm.CreateNew(nil);
  try
    Frame := TrendsFrame(Host, Source);
    Tile := Frame.TileRect(1, Frame.ClientWidth);
    Spark := Frame.SparkRect(Tile);
    Hit := Frame.HitTest(Spark.Left, Spark.Top + Spark.Height div 2);
    Assert.AreEqual(1, Hit.Tile);
    Assert.AreEqual(0, Hit.Point);
    Hit := Frame.HitTest(Spark.Right, Spark.Bottom);
    Assert.AreEqual(4, Hit.Point, 'letzter Punkt rechts');
    Hit := Frame.HitTest(Tile.Left + 4, Tile.Top + 4);
    Assert.AreEqual(1, Hit.Tile, 'Bezeichnung: Kachel, aber kein Punkt');
    Assert.AreEqual(-1, Hit.Point);
    Hit := Frame.HitTest(2, 2);
    Assert.AreEqual(-1, Hit.Tile, 'Kopfzeile');
  finally
    Host.Free;
  end;
end;

procedure TAtlasWelcomeTrendsFrameTests.EmptyStates;
var
  Saved: TAtlasLanguage;
  Host: TForm;
  Fake: TFakeTrends;
  Source: IAtlasTrendsSource;
  Frame: TAtlasWelcomeTrendsFrame;
begin
  Saved := TAtlasStrings.Language;
  Fake := TFakeTrends.Create;
  Source := Fake;
  Host := TForm.CreateNew(nil);
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Frame := TrendsFrame(Host, Source);
    Assert.AreEqual('', Frame.HeadingText);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.WelcomeTrendsNoProject), Frame.InfoText);
    Assert.IsTrue(Frame.PreferredHeight > 0);
    Fake.FView := TAtlasWelcomeTrends.View(TAtlasProjectSummary.Create('C:\P\Neu.dproj'),
      [TAtlasTrendSeries.Warnings], 30);
    Frame.UpdateContent;
    Assert.Contains(Frame.InfoText, 'Neu:');
    Assert.AreEqual(-1, Frame.HitTest(20, 60).Tile, 'ohne Punkte keine Kacheln');
    Fake.FView := TAtlasWelcomeTrends.View(TrendSummary('C:\P\Kasse.dproj', [1, 2]), nil, 30);
    Frame.UpdateContent;
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.WelcomeTrendsNoSeries), Frame.InfoText);
  finally
    Host.Free;
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasWelcomeTrendsFrameTests.TilesWrapByWidth;
var
  Host: TForm;
  Fake: TFakeTrends;
  Source: IAtlasTrendsSource;
  Frame: TAtlasWelcomeTrendsFrame;
  Wide, Narrow, One: Integer;
begin
  Fake := TFakeTrends.Create;
  Source := Fake;
  Fake.FView := TAtlasWelcomeTrends.View(TrendSummary('C:\P\Kasse.dproj', [3, 2, 1]),
    TAtlasWelcomeTrends.ParseSeries(TAtlasWelcomeTrends.DefaultSeries), 30);
  Host := TForm.CreateNew(nil);
  try
    Frame := TrendsFrame(Host, Source);
    Frame.Width := Frame.ScaleValue(900);
    Wide := Frame.PreferredHeight;
    Frame.Width := Frame.ScaleValue(340);
    Narrow := Frame.PreferredHeight;
    Assert.IsTrue(Narrow > Wide, Format('breit %d, schmal %d', [Wide, Narrow]));
    Assert.AreEqual(Frame.TileRect(0, Frame.ScaleValue(900)).Top, Frame.TileRect(4, Frame.ScaleValue(900)).Top,
      'breit: eine Reihe');
    Assert.IsTrue(Frame.TileRect(2, Frame.ScaleValue(340)).Top > Frame.TileRect(0, Frame.ScaleValue(340)).Top,
      'schmal: umgebrochen');
    Fake.FView := TAtlasWelcomeTrends.View(TrendSummary('C:\P\Kasse.dproj', [3, 2, 1]),
      [TAtlasTrendSeries.Todos], 30);
    Frame.UpdateContent;
    One := Frame.PreferredHeight;
    Assert.IsTrue(One < Narrow, 'eine Reihe weniger Kacheln');
  finally
    Host.Free;
  end;
end;

{ TFakeUnsaved }

function TFakeUnsaved.View: TAtlasUnsavedView;
begin
  Result := FView;
end;

procedure TFakeUnsaved.Show(const ARow: TAtlasUnsavedRow);
begin
  Calls := Calls + ['show ' + ARow.Name + ' ' + TAtlasWelcomeUnsaved.KindName(ARow.Item.Kind)];
end;

procedure TFakeUnsaved.Push(const ARow: TAtlasUnsavedRow);
begin
  Calls := Calls + ['push ' + ARow.Name + ' ' + TAtlasWelcomeUnsaved.KindName(ARow.Item.Kind)];
end;

procedure TFakeUnsaved.OpenFolder(const ARow: TAtlasUnsavedRow);
begin
  Calls := Calls + ['folder ' + ARow.Name];
end;

procedure TFakeUnsaved.Ignore(const ARow: TAtlasUnsavedRow);
begin
  Calls := Calls + ['ignore ' + ARow.Name + ' ' + TAtlasWelcomeUnsaved.KindName(ARow.Item.Kind)];
end;

procedure TFakeUnsaved.Shown;
begin
  Calls := Calls + ['shown'];
end;

function UnsavedRow(const AName: string; AKind: TAtlasUnsavedKind; ACount: Integer;
  ASince: TDateTime): TAtlasUnsavedRow;
begin
  Result := Default(TAtlasUnsavedRow);
  Result.Project := 'C:\P\' + AName + '.dproj';
  Result.Name := AName;
  Result.Branch := 'main';
  Result.VcsKind := 'git';
  Result.Item := TAtlasUnsavedItem.Create(AKind, ACount);
  Result.Item.Since := ASince;
end;

{ TAtlasWelcomeUnsavedFrameTests }

procedure TAtlasWelcomeUnsavedFrameTests.TextsFollowKindAndAge;
var
  Saved: TAtlasLanguage;
  NowUtc: TDateTime;
  Row: TAtlasUnsavedRow;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    NowUtc := EncodeDateTime(2026, 10, 15, 12, 0, 0, 0);
    // Abnahme: SVN-Projekt mit 2 geänderten Dateien.
    Row := UnsavedRow('Svn', TAtlasUnsavedKind.Changes, 2, IncHour(NowUtc, -3));
    Row.Item.Modified := 2;
    Assert.AreEqual('2 Dateien geändert', TAtlasWelcomeUnsavedFrame.WhatText(Row.Item));
    Assert.AreEqual('2 Dateien geändert · seit 3 Std.', TAtlasWelcomeUnsavedFrame.DetailText(Row, NowUtc));
    Assert.AreEqual('Ansehen', TAtlasWelcomeUnsavedFrame.ButtonText(Row.Item));
    Assert.AreEqual('Svn · main', TAtlasWelcomeUnsavedFrame.TitleText(Row));
    Row.Item.Count := 1;
    Row.Item.Modified := 1;
    Assert.AreEqual('1 Datei geändert', TAtlasWelcomeUnsavedFrame.WhatText(Row.Item));
    // Gemischt: geändert, neu, gelöscht.
    Row.Item.Count := 4;
    Row.Item.Modified := 2;
    Row.Item.Added := 1;
    Row.Item.Deleted := 1;
    Assert.AreEqual('4 Dateien: 2 geändert, 1 neu, 1 gelöscht', TAtlasWelcomeUnsavedFrame.WhatText(Row.Item));
    Row := UnsavedRow('Git', TAtlasUnsavedKind.Commits, 3, IncDay(NowUtc, -2));
    Row.Item.Branches := ['main'];
    Assert.AreEqual('3 Commits nicht gepusht (main) · seit 2 Tagen',
      TAtlasWelcomeUnsavedFrame.DetailText(Row, NowUtc));
    Assert.AreEqual('Push …', TAtlasWelcomeUnsavedFrame.ButtonText(Row.Item));
    Row := UnsavedRow('Git', TAtlasUnsavedKind.NoUpstream, 1, 0);
    Row.Item.Branches := ['feature/x'];
    Row.Item.Commits := 2;
    Assert.AreEqual('Branch feature/x ohne Upstream, 2 Commits nur lokal',
      TAtlasWelcomeUnsavedFrame.DetailText(Row, NowUtc), 'ohne Alter keine Zeitangabe');
    Assert.AreEqual('Push …', TAtlasWelcomeUnsavedFrame.ButtonText(Row.Item));
    Row := UnsavedRow('Git', TAtlasUnsavedKind.Conflicts, 2, 0);
    Assert.AreEqual('2 Dateien im Konflikt', TAtlasWelcomeUnsavedFrame.WhatText(Row.Item));
    Assert.AreEqual('Ansehen', TAtlasWelcomeUnsavedFrame.ButtonText(Row.Item));
    Row := UnsavedRow('Git', TAtlasUnsavedKind.Stashes, 1, IncMinute(NowUtc, -20));
    Row.Item.Name := 'Versuch';
    Assert.StartsWith('Stash „Versuch“ vom ', TAtlasWelcomeUnsavedFrame.WhatText(Row.Item));
    Assert.EndsWith(' · seit 20 Min.', TAtlasWelcomeUnsavedFrame.DetailText(Row, NowUtc));
    Assert.AreEqual('Ansehen', TAtlasWelcomeUnsavedFrame.ButtonText(Row.Item));
    Assert.AreEqual('seit 1 Tag', TAtlasWelcomeUnsavedFrame.AgeText(IncHour(NowUtc, -30), NowUtc));
    Assert.AreEqual('', TAtlasWelcomeUnsavedFrame.AgeText(0, NowUtc));
    Assert.IsTrue(TAtlasWelcomeUnsavedFrame.LevelColor(TAtlasUnsavedLevel.Fresh) <>
      TAtlasWelcomeUnsavedFrame.LevelColor(TAtlasUnsavedLevel.Alert), 'rot ist nicht grün');
    Assert.IsTrue(TAtlasWelcomeUnsavedFrame.LevelColor(TAtlasUnsavedLevel.Warning) <>
      TAtlasWelcomeUnsavedFrame.LevelColor(TAtlasUnsavedLevel.Alert), 'gelb ist nicht rot');
    Assert.Contains(TAtlasWelcomeUnsavedFrame.HintFor(Row), 'C:\P\Git.dproj');
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('View', TAtlasWelcomeUnsavedFrame.ButtonText(Row.Item));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasWelcomeUnsavedFrameTests.EmptyTextNamesState;
var
  Saved: TAtlasLanguage;
  View: TAtlasUnsavedView;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    View := Default(TAtlasUnsavedView);
    View.Known := True;
    Assert.AreEqual('Alles gesichert', TAtlasWelcomeUnsavedFrame.EmptyText(View));
    View.Known := False;
    View.Querying := True;
    Assert.AreEqual('Versionsverwaltung wird abgefragt …', TAtlasWelcomeUnsavedFrame.EmptyText(View));
    View.Hidden := 2;
    Assert.StartsWith('Nichts zu zeigen (2 ', TAtlasWelcomeUnsavedFrame.EmptyText(View));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasWelcomeUnsavedFrameTests.OnlyButtonAndMenuReachSource;
var
  Host: TForm;
  Fake: TFakeUnsaved;
  Source: IAtlasUnsavedSource;
  Frame: TAtlasWelcomeUnsavedFrame;
  Hit: TAtlasUnsavedHit;
  Height: Integer;
begin
  Fake := TFakeUnsaved.Create;
  Source := Fake;
  Fake.FView.Known := True;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeUnsavedFrame.Create(Host);
    Frame.Parent := Host;
    Frame.Width := 600;
    Frame.Source := Source;
    Assert.AreEqual(1, Integer(Length(Fake.Calls)), 'Shown beim Setzen der Quelle');
    Assert.AreEqual('shown', Fake.Calls[0]);
    Height := Frame.PreferredHeight;
    Fake.FView.Rows := [UnsavedRow('Eins', TAtlasUnsavedKind.Changes, 4, 0),
      UnsavedRow('Zwei', TAtlasUnsavedKind.Commits, 3, 0)];
    Frame.UpdateContent;
    Assert.IsTrue(Frame.PreferredHeight > Height, 'zwei Zeilen brauchen mehr Platz als der leere Bereich');
    Fake.Calls := nil;
    // Klick auf die Zeile außerhalb der Schaltfläche: nichts.
    Hit.Row := 0;
    Hit.Button := False;
    Frame.ClickAt(Hit);
    Hit.Row := 0;
    Hit.Button := True;
    Frame.ClickAt(Hit);
    Hit.Row := 1;
    Hit.Button := True;
    Frame.ClickAt(Hit);
    Hit.Row := 5;
    Frame.ClickAt(Hit);
    Frame.MenuRow := 1;
    Frame.OpenFolderItem.Click;
    Frame.IgnoreItem.Click;
    Assert.AreEqual(0, Integer(Length(Fake.Calls)), 'alles über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(4, Integer(Length(Fake.Calls)));
    Assert.AreEqual('show Eins changes', Fake.Calls[0]);
    Assert.AreEqual('push Zwei commits', Fake.Calls[1], '„Push …“ fragt in der Quelle erst nach');
    Assert.AreEqual('folder Zwei', Fake.Calls[2]);
    Assert.AreEqual('ignore Zwei commits', Fake.Calls[3]);
    Assert.AreEqual(-1, Frame.HitTest(20, 0).Row, 'über der ersten Zeile');
  finally
    Host.Free;
  end;
end;

procedure TAtlasWelcomeUnsavedFrameTests.PushDialogCancelsByDefault;
var
  Saved: TAtlasLanguage;
  Plan: TAtlasUnsavedPush;
  Commit: TAtlasVcsCommit;
  Dialog: TAtlasPushDialog;
  Text: string;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Plan := Default(TAtlasUnsavedPush);
    Plan.Branch := 'feature/x';
    Plan.Remote := 'origin';
    Plan.RemoteRef := 'refs/heads/feature/x';
    Plan.SetUpstream := True;
    Commit := Default(TAtlasVcsCommit);
    Commit.Hash := '0123456789abcdef';
    Commit.Date := EncodeDateTime(2026, 10, 14, 9, 0, 0, 0);
    Commit.Summary := 'Erster Schritt';
    Plan.Commits := [Commit];
    Plan.More := True;
    Text := TAtlasPushDialog.DetailText([Plan]);
    Assert.Contains(Text, 'feature/x → origin/feature/x (neu auf dem Server');
    Assert.Contains(Text, '0123456');
    Assert.Contains(Text, 'Erster Schritt');
    Assert.Contains(Text, '… und weitere');
    Dialog := TAtlasPushDialog.CreateDialog(nil, 'Atlas', [Plan]);
    try
      Assert.AreEqual('Push – Atlas', Dialog.Caption);
      Assert.AreEqual(Text, Dialog.Details.Text);
      // Enter und Esc pushen nie.
      Assert.IsTrue(Dialog.CancelButton.Default);
      Assert.IsTrue(Dialog.CancelButton.Cancel);
      Assert.IsFalse(Dialog.PushButton.Default);
      Assert.IsTrue(Dialog.ActiveControl = Dialog.CancelButton);
      Assert.AreEqual(Integer(mrOk), Integer(Dialog.PushButton.ModalResult));
      Assert.AreEqual(Integer(mrCancel), Integer(Dialog.CancelButton.ModalResult));
    finally
      Dialog.Free;
    end;
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

{ TFakeState }

function TFakeState.Rows: TAtlasStateRows;
begin
  Result := TAtlasWelcomeState.Rows(Registry.Items);
end;

procedure TFakeState.RunRow(const AId: string);
begin
  Calls := Calls + ['row ' + AId];
end;

procedure TFakeState.Run(AButton: TAtlasStateButton);
begin
  Calls := Calls + [Format('button %d', [Ord(AButton)])];
end;

/// <summary>Zeile im Statusfeld; mit AAction anklickbar.</summary>
procedure AddLine(const ARegistry: IAtlasStatusRegistry; const AId, AText: string; AState: TAtlasStatusState;
  const ABrief, ADetail: string; AAction: Boolean);
var
  Line: TAtlasStatusLine;
  Ref: IAtlasStatusItem;
  Action: TProc;
begin
  Action :=
    procedure
    begin
    end;
  if AAction then
    Line := TAtlasStatusLine.Create(ARegistry, AId, 0, Action)
  else
    Line := TAtlasStatusLine.Create(ARegistry, AId, 0);
  Ref := Line;
  Line.Update(AText, AState, '', ABrief, ADetail);
  ARegistry.Add(Ref);
end;

function StateFake: TFakeState;
begin
  Result := TFakeState.Create;
  Result.Registry := TAtlasStatusRegistry.Create;
  AddLine(Result.Registry, TAtlasStatusLines.ServerId, 'Server: läuft seit 19:02', TAtlasStatusState.Green,
    'Server läuft', 'seit 19:02', False);
  AddLine(Result.Registry, TAtlasStatusLines.IndexId, 'Index: 1284 Units', TAtlasStatusState.Green,
    'Index: 1284 Units', 'indiziert 18:40', False);
  AddLine(Result.Registry, TAtlasStatusLines.SetupId, 'Einrichtung: 5 von 6 erledigt', TAtlasStatusState.Yellow,
    '', '', True);
end;

{ TAtlasWelcomeStateFrameTests }

procedure TAtlasWelcomeStateFrameTests.TextsUseLineOrFallback;
var
  Saved: TAtlasLanguage;
  Rows: TAtlasStateRows;
  Fake: TFakeState;
  Source: IAtlasStateSource;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Fake := StateFake;
    Source := Fake;
    Rows := Source.Rows;
    Assert.AreEqual('Server läuft', TAtlasWelcomeStateFrame.RowText(Rows[0]));
    Assert.AreEqual('seit 19:02', TAtlasWelcomeStateFrame.DetailText(Rows[0]));
    Assert.AreEqual('Einrichtung: 5 von 6 erledigt', TAtlasWelcomeStateFrame.RowText(Rows[3]));
    // Ohne Zeile im Statusfeld: Ersatztexte.
    Assert.AreEqual('Diagnosemodus aus', TAtlasWelcomeStateFrame.RowText(Rows[4]));
    Assert.AreEqual('', TAtlasWelcomeStateFrame.DetailText(Rows[4]));
    Assert.IsTrue(TAtlasWelcomeStateFrame.RowText(Rows[1]).StartsWith('Atlas '), 'Version ohne Update-Prüfung');
    Rows := TAtlasWelcomeState.Rows(nil);
    Assert.AreEqual('Einrichtung noch nicht geprüft', TAtlasWelcomeStateFrame.RowText(Rows[3]));
    Assert.AreEqual('Index unbekannt', TAtlasWelcomeStateFrame.RowText(Rows[2]));
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('Diagnostic mode off', TAtlasWelcomeStateFrame.RowText(Rows[4]));
    Assert.AreEqual('Restart server', TAtlasWelcomeStateFrame.ButtonCaption(TAtlasStateButton.Restart));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasWelcomeStateFrameTests.UpdateButtonOnlyWithUpdate;
var
  Host: TForm;
  Fake: TFakeState;
  Source: IAtlasStateSource;
  Frame: TAtlasWelcomeStateFrame;
begin
  Fake := StateFake;
  Source := Fake;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeStateFrame.Create(Host);
    Frame.Parent := Host;
    Frame.Source := Source;
    Assert.AreEqual(5, Integer(Length(Frame.Rows)));
    Assert.IsTrue(Frame.Button(TAtlasStateButton.Restart).Visible);
    Assert.IsTrue(Frame.Button(TAtlasStateButton.Settings).Visible);
    Assert.IsTrue(Frame.Button(TAtlasStateButton.LogFolder).Visible);
    Assert.IsFalse(Frame.Button(TAtlasStateButton.Update).Visible);
    AddLine(Fake.Registry, TAtlasStatusLines.VersionId, 'Version: Atlas 1.0.0, Update 1.0.1 bereit',
      TAtlasStatusState.Yellow, 'Update 1.0.1 bereit', 'installiert 1.0.0', True);
    Frame.UpdateContent;
    Assert.IsTrue(Frame.Button(TAtlasStateButton.Update).Visible);
    Assert.IsTrue(Frame.PreferredHeight > 5 * Frame.ScaleValue(TAtlasWelcomeStateFrame.RowHeight));
  finally
    Host.Free;
  end;
end;

procedure TAtlasWelcomeStateFrameTests.ClicksReachSource;
var
  Host: TForm;
  Fake: TFakeState;
  Source: IAtlasStateSource;
  Frame: TAtlasWelcomeStateFrame;
begin
  Fake := StateFake;
  Source := Fake;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeStateFrame.Create(Host);
    Frame.Parent := Host;
    Frame.Source := Source;
    // Zeile ohne Aktion (Server) und ohne Zeile im Statusfeld (Diagnosemodus): nichts.
    Frame.ClickRow(0);
    Frame.ClickRow(4);
    // Einrichtung: Aktion der Statusfeld-Zeile (Prüfliste).
    Frame.ClickRow(3);
    Frame.Button(TAtlasStateButton.Restart).Click;
    Frame.Button(TAtlasStateButton.LogFolder).Click;
    Assert.AreEqual(0, Integer(Length(Fake.Calls)), 'über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(3, Integer(Length(Fake.Calls)));
    Assert.AreEqual('row atlas.setup', Fake.Calls[0]);
    Assert.AreEqual(Format('button %d', [Ord(TAtlasStateButton.Restart)]), Fake.Calls[1]);
    Assert.AreEqual(Format('button %d', [Ord(TAtlasStateButton.LogFolder)]), Fake.Calls[2]);
  finally
    Host.Free;
  end;
end;

procedure TAtlasWelcomeStateFrameTests.HitTestFindsRows;
var
  Host: TForm;
  Fake: TFakeState;
  Source: IAtlasStateSource;
  Frame: TAtlasWelcomeStateFrame;
  Row: Integer;
begin
  Fake := StateFake;
  Source := Fake;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeStateFrame.Create(Host);
    Frame.Parent := Host;
    Frame.Source := Source;
    Row := Frame.ScaleValue(TAtlasWelcomeStateFrame.RowHeight);
    Assert.AreEqual(-1, Frame.HitTest(10, 0));
    Assert.AreEqual(0, Frame.HitTest(10, Frame.ScaleValue(TAtlasWelcomeStateFrame.Indent) div 2 + 1));
    Assert.AreEqual(3, Frame.HitTest(10, Frame.ScaleValue(TAtlasWelcomeStateFrame.Indent) div 2 + 3 * Row + 1));
    Assert.AreEqual(-1, Frame.HitTest(10, Frame.ScaleValue(TAtlasWelcomeStateFrame.Indent) div 2 + 5 * Row + 1));
  finally
    Host.Free;
  end;
end;

{ TFakeDiscover }

function TFakeDiscover.Card(out ACard: TAtlasDiscoverCard): Boolean;
begin
  ACard := Card_;
  Result := HasCard;
end;

procedure TFakeDiscover.TryTip(const AId: string);
begin
  Calls := Calls + ['try ' + AId];
end;

procedure TFakeDiscover.NextTip(const AId: string);
begin
  Calls := Calls + ['next ' + AId];
end;

procedure TFakeDiscover.BlockTip(const AId: string);
begin
  Calls := Calls + ['block ' + AId];
end;

function DiscoverFake: TFakeDiscover;
begin
  Result := TFakeDiscover.Create;
  Result.HasCard := True;
  Result.Card_.Id := 'codeActions';
  Result.Card_.Title := 'Code-Aktionen';
  Result.Card_.Text := 'Zeigt, was Atlas an dieser Stelle kann, und führt es aus.';
  Result.Card_.KeyText := 'Ctrl+.';
  Result.Card_.Age := TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.Never, 0);
  Result.Card_.CanTry := True;
  Result.Card_.Position := 2;
  Result.Card_.Count := 5;
end;

{ TAtlasWelcomeDiscoverFrameTests }

procedure TAtlasWelcomeDiscoverFrameTests.WarmUpFirstUse;
begin
  CardShowsTipAndButtons;
end;

procedure TAtlasWelcomeDiscoverFrameTests.AgeTextsFollowKind;
var
  Saved: TAtlasLanguage;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('Noch nie benutzt',
      TAtlasWelcomeDiscoverFrame.AgeText(TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.Never, 0)));
    Assert.AreEqual('Zuletzt vor 3 Wochen',
      TAtlasWelcomeDiscoverFrame.AgeText(TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.Weeks, 3)));
    Assert.AreEqual('Zuletzt vor 1 Jahr',
      TAtlasWelcomeDiscoverFrame.AgeText(TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.Years, 1)));
    Assert.AreEqual('Zuletzt gestern benutzt',
      TAtlasWelcomeDiscoverFrame.AgeText(TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.Yesterday, 1)));
    Assert.AreEqual('', TAtlasWelcomeDiscoverFrame.AgeText(TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.None, 0)),
      'ohne Zählung kein Hinweis');
    Assert.AreEqual('Tipp 2 von 5', TAtlasWelcomeDiscoverFrame.PositionText(2, 5));
    Assert.AreEqual('', TAtlasWelcomeDiscoverFrame.PositionText(1, 1), 'ein Tipp: keine Stelle');
    Assert.AreEqual('Atlas entdecken', TAtlasWelcomeDiscoverFrame.TitleText);
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('Last used 3 weeks ago',
      TAtlasWelcomeDiscoverFrame.AgeText(TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.Weeks, 3)));
    Assert.AreEqual('Don''t show again', TAtlasWelcomeDiscoverFrame.ButtonCaption(TAtlasDiscoverButton.Block));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasWelcomeDiscoverFrameTests.CardShowsTipAndButtons;
var
  Host: TForm;
  Fake: TFakeDiscover;
  Source: IAtlasDiscoverSource;
  Frame: TAtlasWelcomeDiscoverFrame;
begin
  Fake := DiscoverFake;
  Source := Fake;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeDiscoverFrame.Create(Host);
    Frame.Parent := Host;
    Frame.SetBounds(0, 0, 420, 200);
    Frame.Source := Source;
    Assert.IsTrue(Frame.HasCard);
    Assert.AreEqual('Code-Aktionen', Frame.TipTitle.Caption);
    Assert.AreEqual('Ctrl+.', Frame.KeyLabel.Caption, 'tatsächliche Belegung');
    Assert.IsTrue(Frame.KeyLabel.Left > Frame.TipTitle.Left, 'Kürzel neben dem Titel');
    Assert.AreEqual(TAtlasWelcomeDiscoverFrame.AgeText(Fake.Card_.Age), Frame.AgeLabel.Caption);
    Assert.IsTrue(Frame.TextLabel.Top > Frame.TipTitle.Top, 'Text unter dem Titel');
    Assert.IsFalse(Frame.Image.Visible, 'ohne Bild kein Platz dafür');
    Assert.IsTrue(Frame.Button(TAtlasDiscoverButton.TryIt).Enabled);
    Assert.IsTrue(Frame.Button(TAtlasDiscoverButton.Next).Enabled);
    Assert.IsTrue(Frame.Button(TAtlasDiscoverButton.Block).Visible);
    Assert.IsTrue(Frame.Button(TAtlasDiscoverButton.TryIt).Top > Frame.AgeLabel.Top, 'Knöpfe unten');
    Assert.IsTrue(Frame.PreferredHeight > Frame.Button(TAtlasDiscoverButton.TryIt).Top, 'Höhe nach dem Inhalt');
    Assert.IsFalse(Frame.EmptyLabel.Visible);
    // Einziger Tipp, nichts zum Ausprobieren, Zählung aus.
    Fake.Card_.Count := 1;
    Fake.Card_.Position := 1;
    Fake.Card_.CanTry := False;
    Fake.Card_.Age := TAtlasDiscoverAge.Create(TAtlasDiscoverAgeKind.None, 0);
    Fake.Card_.KeyText := '';
    Frame.UpdateContent;
    Assert.IsFalse(Frame.Button(TAtlasDiscoverButton.Next).Enabled, 'kein nächster Tipp');
    Assert.IsFalse(Frame.Button(TAtlasDiscoverButton.TryIt).Enabled);
    Assert.IsFalse(Frame.AgeLabel.Visible);
    Assert.IsFalse(Frame.PositionLabel.Visible);
    Assert.IsFalse(Frame.KeyLabel.Visible);
    // Kein Tipp (alle gesperrt): nur der Hinweis.
    Fake.HasCard := False;
    Frame.UpdateContent;
    Assert.IsFalse(Frame.HasCard);
    Assert.IsTrue(Frame.EmptyLabel.Visible);
    Assert.IsFalse(Frame.Button(TAtlasDiscoverButton.Block).Visible);
    Assert.IsFalse(Frame.TipTitle.Visible);
  finally
    Host.Free;
  end;
end;

procedure TAtlasWelcomeDiscoverFrameTests.ClicksReachSource;
var
  Host: TForm;
  Fake: TFakeDiscover;
  Source: IAtlasDiscoverSource;
  Frame: TAtlasWelcomeDiscoverFrame;
begin
  Fake := DiscoverFake;
  Source := Fake;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeDiscoverFrame.Create(Host);
    Frame.Parent := Host;
    Frame.Source := Source;
    Frame.Button(TAtlasDiscoverButton.TryIt).Click;
    Frame.Button(TAtlasDiscoverButton.Next).Click;
    Frame.Button(TAtlasDiscoverButton.Block).Click;
    Assert.AreEqual(0, Integer(Length(Fake.Calls)), 'über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(3, Integer(Length(Fake.Calls)));
    Assert.AreEqual('try codeActions', Fake.Calls[0]);
    Assert.AreEqual('next codeActions', Fake.Calls[1]);
    Assert.AreEqual('block codeActions', Fake.Calls[2]);
    // Ausgegraute Knöpfe tun nichts.
    Fake.Card_.Count := 1;
    Fake.Card_.CanTry := False;
    Frame.UpdateContent;
    Frame.ClickButton(TAtlasDiscoverButton.Next);
    Frame.ClickButton(TAtlasDiscoverButton.TryIt);
    CheckSynchronize;
    Assert.AreEqual(3, Integer(Length(Fake.Calls)));
  finally
    Host.Free;
  end;
end;

{ TFakeHelp }

function TFakeHelp.KeysAvailable: Boolean;
begin
  Result := Keys;
end;

procedure TFakeHelp.OpenDocs;
begin
  Calls := Calls + ['docs'];
end;

procedure TFakeHelp.ShowKeys;
begin
  Calls := Calls + ['keys'];
end;

procedure TFakeHelp.ReportProblem;
begin
  Calls := Calls + ['report'];
end;

procedure TFakeHelp.Donate;
begin
  Calls := Calls + ['donate'];
end;

{ TAtlasWelcomeHelpFrameTests }

procedure TAtlasWelcomeHelpFrameTests.TextsFollowLanguage;
var
  Saved: TAtlasLanguage;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('Hilfe und Rückmeldung', TAtlasWelcomeHelpFrame.TitleText);
    Assert.AreEqual('Atlas-Doku', TAtlasWelcomeHelpFrame.ButtonCaption(TAtlasHelpButton.Docs));
    Assert.AreEqual('Tastenkürzel', TAtlasWelcomeHelpFrame.ButtonCaption(TAtlasHelpButton.Keys));
    Assert.AreEqual('Problem melden …', TAtlasWelcomeHelpFrame.ButtonCaption(TAtlasHelpButton.Report));
    Assert.AreEqual('Atlas unterstützen ♥', TAtlasWelcomeHelpFrame.ButtonCaption(TAtlasHelpButton.Donate));
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('Help and feedback', TAtlasWelcomeHelpFrame.TitleText);
    Assert.AreEqual('Report a problem …', TAtlasWelcomeHelpFrame.ButtonCaption(TAtlasHelpButton.Report));
    Assert.AreEqual('Support Atlas ♥', TAtlasWelcomeHelpFrame.ButtonCaption(TAtlasHelpButton.Donate));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasWelcomeHelpFrameTests.ButtonsFollowSourceAndWidth;
var
  Host: TForm;
  Fake: TFakeHelp;
  Source: IAtlasHelpSource;
  Frame: TAtlasWelcomeHelpFrame;
  Kind: TAtlasHelpButton;
  Wide: Integer;
begin
  Fake := TFakeHelp.Create;
  Fake.Keys := True;
  Source := Fake;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeHelpFrame.Create(Host);
    Frame.Parent := Host;
    Frame.SetBounds(0, 0, 600, 120);
    // Ohne Quelle geht nichts.
    for Kind := Low(TAtlasHelpButton) to High(TAtlasHelpButton) do
      Assert.IsFalse(Frame.Button(Kind).Enabled, 'ohne Quelle ausgegraut');
    Frame.Source := Source;
    for Kind := Low(TAtlasHelpButton) to High(TAtlasHelpButton) do
      Assert.IsTrue(Frame.Button(Kind).Enabled);
    Assert.AreEqual(Frame.Button(TAtlasHelpButton.Docs).Top, Frame.Button(TAtlasHelpButton.Report).Top,
      'genug Breite: eine Reihe');
    Assert.IsTrue(Frame.Button(TAtlasHelpButton.Keys).Left > Frame.Button(TAtlasHelpButton.Docs).Left);
    Assert.IsTrue(Frame.NoteLabel.Top > Frame.Button(TAtlasHelpButton.Docs).Top, 'Hinweis unter den Knöpfen');
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.WelcomeHelpNote), Frame.NoteLabel.Caption);
    Assert.IsTrue(Frame.PreferredHeight > Frame.NoteLabel.Top, 'Höhe nach dem Inhalt');
    Wide := Frame.PreferredHeight;
    // Schmal: weitere Reihen, der Bereich wird höher.
    Frame.Width := 120;
    Frame.UpdateContent;
    Assert.IsTrue(Frame.Button(TAtlasHelpButton.Report).Top > Frame.Button(TAtlasHelpButton.Docs).Top,
      'schmal: Umbruch');
    Assert.IsTrue(Frame.PreferredHeight > Wide);
    // Übersicht aus (keys.overview): „Tastenkürzel“ ausgegraut, die anderen gehen.
    Fake.Keys := False;
    Frame.UpdateContent;
    Assert.IsFalse(Frame.Button(TAtlasHelpButton.Keys).Enabled);
    Assert.IsTrue(Frame.Button(TAtlasHelpButton.Docs).Enabled);
    Assert.IsTrue(Frame.Button(TAtlasHelpButton.Report).Enabled);
  finally
    Host.Free;
  end;
end;

procedure TAtlasWelcomeHelpFrameTests.ClicksReachSource;
var
  Host: TForm;
  Fake: TFakeHelp;
  Source: IAtlasHelpSource;
  Frame: TAtlasWelcomeHelpFrame;
begin
  Fake := TFakeHelp.Create;
  Fake.Keys := True;
  Source := Fake;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeHelpFrame.Create(Host);
    Frame.Parent := Host;
    Frame.Source := Source;
    Frame.Button(TAtlasHelpButton.Docs).Click;
    Frame.Button(TAtlasHelpButton.Keys).Click;
    Frame.Button(TAtlasHelpButton.Report).Click;
    Frame.Button(TAtlasHelpButton.Donate).Click;
    Assert.AreEqual(0, Integer(Length(Fake.Calls)), 'über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(4, Integer(Length(Fake.Calls)));
    Assert.AreEqual('docs', Fake.Calls[0]);
    Assert.AreEqual('keys', Fake.Calls[1]);
    Assert.AreEqual('report', Fake.Calls[2]);
    Assert.AreEqual('donate', Fake.Calls[3]);
    // Ausgegrauter Knopf tut nichts.
    Fake.Keys := False;
    Frame.UpdateContent;
    Frame.ClickButton(TAtlasHelpButton.Keys);
    CheckSynchronize;
    Assert.AreEqual(4, Integer(Length(Fake.Calls)));
  finally
    Host.Free;
  end;
end;

{ TFakeSetup }

function TFakeSetup.Card: TAtlasSetupCard;
begin
  Result := Card_;
end;

procedure TFakeSetup.CreateConfig(ATemplate: TAtlasSetupTemplate);
begin
  Calls := Calls + ['config:' + TAtlasProjectSetups.TemplateId(ATemplate)];
end;

procedure TFakeSetup.StartBaseline;
begin
  Calls := Calls + ['baseline'];
end;

procedure TFakeSetup.CheckPaths;
begin
  Calls := Calls + ['paths'];
end;

procedure TFakeSetup.OpenOptions;
begin
  Calls := Calls + ['options'];
end;

procedure TFakeSetup.OpenProject;
begin
  Calls := Calls + ['open'];
end;

procedure TFakeSetup.Dismiss;
begin
  Calls := Calls + ['dismiss'];
end;

procedure TFakeSetup.NewFile(AKind: TAtlasNewFileKind);
begin
  Calls := Calls + ['new:' + TAtlasFileTemplates.KindWord(AKind)];
end;

/// <summary>Karte für XmlInspector: Projekt offen, keine atlas.json, keine Baseline, nicht geprüft.</summary>
function SetupCard: TAtlasSetupCard;
begin
  Result := TAtlasSetupCard.Empty;
  Result.Project := 'C:\Src\XmlInspector\XmlInspector.dproj';
  Result.ProjectName := 'XmlInspector';
  Result.ProjectOpen := True;
  Result.Facts.Project := Result.Project;
  Result.ShowCard := True;
  Result.ShowNew := True;
end;

function SetupFinding(const AName, AFileName: string; ALine, ACount: Integer): TAtlasSetupFinding;
begin
  Result := Default(TAtlasSetupFinding);
  Result.Name := AName;
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.Count := ACount;
end;

{ TAtlasWelcomeSetupFrameTests }

procedure TAtlasWelcomeSetupFrameTests.WarmUpFirstUse;
begin
  PreviewShowsContent;
end;

procedure TAtlasWelcomeSetupFrameTests.TextsFollowLanguage;
var
  Saved: TAtlasLanguage;
  Card: TAtlasSetupCard;
begin
  Saved := TAtlasStrings.Language;
  try
    Card := SetupCard;
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('XmlInspector für Atlas einrichten', TAtlasWelcomeSetupFrame.TitleText(Card));
    Assert.AreEqual('Projekt gefunden, keine atlas.json',
      TAtlasWelcomeSetupFrame.StepCaption(TAtlasSetupStep.Found, Card, 0));
    Assert.AreEqual('atlas.json anlegen', TAtlasWelcomeSetupFrame.StepCaption(TAtlasSetupStep.Config, Card, 0));
    Assert.AreEqual('Baseline erzeugen', TAtlasWelcomeSetupFrame.StepCaption(TAtlasSetupStep.Baseline, Card, 0));
    Assert.AreEqual('Suchpfade und Defines prüfen',
      TAtlasWelcomeSetupFrame.StepCaption(TAtlasSetupStep.Paths, Card, 0));
    Assert.AreEqual('Bestehendes Projekt', TAtlasWelcomeSetupFrame.TemplateCaption(TAtlasSetupTemplate.Existing));
    Assert.AreEqual('Neues Projekt, streng', TAtlasWelcomeSetupFrame.TemplateCaption(TAtlasSetupTemplate.NewStrict));
    Assert.AreEqual('Altprojekt mit Baseline', TAtlasWelcomeSetupFrame.TemplateCaption(TAtlasSetupTemplate.Legacy));
    Assert.AreEqual('Starten', TAtlasWelcomeSetupFrame.ButtonCaption(TAtlasSetupButton.Baseline));
    Assert.AreEqual('Prüfen', TAtlasWelcomeSetupFrame.ButtonCaption(TAtlasSetupButton.Paths));
    Assert.AreEqual('Für dieses Projekt nicht mehr fragen',
      TAtlasWelcomeSetupFrame.ButtonCaption(TAtlasSetupButton.Dismiss));
    Assert.AreEqual('Testklasse', TAtlasWelcomeSetupFrame.ButtonCaption(TAtlasSetupButton.NewTest));
    Card.Facts.ConfigExists := True;
    Card.ConfigName := 'atlas.json';
    Assert.AreEqual('Projekt gefunden', TAtlasWelcomeSetupFrame.StepCaption(TAtlasSetupStep.Found, Card, 0));
    Assert.AreEqual('atlas.json vorhanden', TAtlasWelcomeSetupFrame.StepCaption(TAtlasSetupStep.Config, Card, 0));
    Card.ShowCard := False;
    Assert.AreEqual('Neu mit Atlas', TAtlasWelcomeSetupFrame.TitleText(Card));
    TAtlasStrings.Language := TAtlasLanguage.English;
    Card.ShowCard := True;
    Assert.AreEqual('Set up XmlInspector for Atlas', TAtlasWelcomeSetupFrame.TitleText(Card));
    Assert.AreEqual('Test class', TAtlasWelcomeSetupFrame.ButtonCaption(TAtlasSetupButton.NewTest));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasWelcomeSetupFrameTests.StepsShowMarksAndButtons;
var
  Host: TForm;
  Fake: TFakeSetup;
  Source: IAtlasSetupSource;
  Frame: TAtlasWelcomeSetupFrame;
begin
  Fake := TFakeSetup.Create;
  Fake.Card_ := SetupCard;
  Source := Fake;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeSetupFrame.Create(Host);
    Frame.Parent := Host;
    Frame.SetBounds(0, 0, 640, 300);
    Frame.Source := Source;
    // Schritt 1 erledigt, die anderen offen.
    Assert.AreEqual(string(#$2713), Frame.StepMark(TAtlasSetupStep.Found).Caption);
    Assert.AreEqual(Integer(TAtlasWelcomeSetupFrame.DoneColor),
      Integer(Frame.StepText(TAtlasSetupStep.Found).Font.Color));
    Assert.AreNotEqual(string(#$2713), Frame.StepMark(TAtlasSetupStep.Config).Caption);
    Assert.IsTrue(Frame.TemplateBox.Visible);
    Assert.IsTrue(Frame.Button(TAtlasSetupButton.CreateConfig).Visible);
    Assert.IsTrue(Frame.Button(TAtlasSetupButton.Baseline).Visible);
    Assert.IsTrue(Frame.Button(TAtlasSetupButton.Paths).Visible);
    Assert.IsTrue(Frame.DismissLabel.Visible);
    Assert.IsFalse(Frame.Button(TAtlasSetupButton.Options).Visible, 'ohne Funde keine Projektoptionen');
    // Vorgabe der Vorlage: Bestehendes Projekt.
    Assert.IsTrue(Frame.SelectedTemplate = TAtlasSetupTemplate.Existing);
    Assert.AreEqual(3, Integer(Frame.TemplateBox.Items.Count));
    Assert.AreEqual(Integer(Ord(TAtlasSetupTemplate.Existing)), Frame.TemplateBox.ItemIndex);
    // Knöpfe rechts neben dem Text ihres Schritts, Schritte untereinander.
    Assert.IsTrue(Frame.Button(TAtlasSetupButton.CreateConfig).Left > Frame.TemplateBox.Left);
    Assert.IsTrue(Frame.TemplateBox.Left > Frame.StepText(TAtlasSetupStep.Config).Left);
    Assert.IsTrue(Frame.StepText(TAtlasSetupStep.Baseline).Top > Frame.StepText(TAtlasSetupStep.Config).Top);
    Assert.IsTrue(Frame.StepText(TAtlasSetupStep.Paths).Top > Frame.StepText(TAtlasSetupStep.Baseline).Top);
    Assert.IsTrue(Frame.DismissLabel.Top > Frame.StepText(TAtlasSetupStep.Paths).Top);
    // Abnahme: Nach „Anlegen“ ist Schritt 2 abgehakt; nach der Baseline Schritt 3 mit „neue Treffer: 0“.
    Fake.Card_.Facts.ConfigExists := True;
    Fake.Card_.ConfigName := 'atlas.json';
    Fake.Card_.Facts.BaselineExists := True;
    Fake.Card_.Baseline := TAtlasSetupRun.Done;
    Fake.Card_.BaselineTotal := 120;
    Fake.Card_.BaselineFiles := 14;
    Fake.Card_.BaselineNewHits := 0;
    Frame.UpdateContent;
    Assert.AreEqual(string(#$2713), Frame.StepMark(TAtlasSetupStep.Config).Caption);
    Assert.AreEqual(Integer(TAtlasWelcomeSetupFrame.DoneColor),
      Integer(Frame.StepText(TAtlasSetupStep.Config).Font.Color));
    Assert.IsFalse(Frame.TemplateBox.Visible);
    Assert.IsFalse(Frame.Button(TAtlasSetupButton.CreateConfig).Visible);
    Assert.AreEqual(string(#$2713), Frame.StepMark(TAtlasSetupStep.Baseline).Caption);
    Assert.IsFalse(Frame.Button(TAtlasSetupButton.Baseline).Visible);
    Assert.IsTrue(Frame.BaselineInfo.Visible);
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.WelcomeSetupBaselineResult, [120, 14, 0]),
      Frame.BaselineInfo.Caption);
    Assert.Contains(Frame.BaselineInfo.Caption, ': 0');
    // Ohne geöffnetes Projekt heißen die Knöpfe „Projekt öffnen“.
    Fake.Card_.Facts.BaselineExists := False;
    Fake.Card_.Baseline := TAtlasSetupRun.Idle;
    Fake.Card_.ProjectOpen := False;
    Frame.UpdateContent;
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.WelcomeSetupOpenProject),
      Frame.Button(TAtlasSetupButton.Baseline).Caption);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.WelcomeSetupOpenProject),
      Frame.Button(TAtlasSetupButton.Paths).Caption);
  finally
    Host.Free;
  end;
end;

procedure TAtlasWelcomeSetupFrameTests.FindingNamesUnit;
var
  Saved: TAtlasLanguage;
  Host: TForm;
  Fake: TFakeSetup;
  Source: IAtlasSetupSource;
  Frame: TAtlasWelcomeSetupFrame;
  Line: TAtlasSetupLine;
  Index: Integer;
begin
  Saved := TAtlasStrings.Language;
  Fake := TFakeSetup.Create;
  Fake.Card_ := SetupCard;
  Fake.Card_.Facts.Setup.Known := True;
  Fake.Card_.Facts.Setup.Checked := True;
  Fake.Card_.Facts.Setup.Files := 12;
  Fake.Card_.Facts.Setup.MissingUnitCount := 9;
  Fake.Card_.Facts.Setup.UndefinedDefineCount := 1;
  Fake.Card_.Facts.Setup.MissingUnits := [SetupFinding('Xml.Helpers', 'Src\Main.pas', 12, 3)];
  for Index := 2 to 9 do
    Fake.Card_.Facts.Setup.MissingUnits := Fake.Card_.Facts.Setup.MissingUnits +
      [SetupFinding('Unit' + IntToStr(Index), 'Src\Main.pas', 12 + Index, 1)];
  Fake.Card_.Facts.Setup.UndefinedDefines := [SetupFinding('USE_XML', 'Src\Main.pas', 3, 1)];
  Fake.Card_.Paths := TAtlasSetupRun.Done;
  Source := Fake;
  Host := TForm.CreateNew(nil);
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Line := Default(TAtlasSetupLine);
    Line.Kind := TAtlasSetupFindingKind.MissingUnit;
    Line.Name := 'Xml.Helpers';
    Line.FileName := 'Src\Main.pas';
    Line.Line := 12;
    Line.Count := 1;
    Assert.AreEqual('Unit „Xml.Helpers“ nicht gefunden – Src\Main.pas, Zeile 12',
      TAtlasWelcomeSetupFrame.FindingCaption(Line));
    Line.Count := 3;
    Assert.AreEqual('Unit „Xml.Helpers“ nicht gefunden – Src\Main.pas, Zeile 12 (3×)',
      TAtlasWelcomeSetupFrame.FindingCaption(Line));
    Line.Kind := TAtlasSetupFindingKind.UndefinedDefine;
    Line.Name := 'USE_XML';
    Line.Count := 1;
    Assert.AreEqual('Define „USE_XML“ ohne Quelle – Src\Main.pas, Zeile 12',
      TAtlasWelcomeSetupFrame.FindingCaption(Line));
    Frame := TAtlasWelcomeSetupFrame.Create(Host);
    Frame.Parent := Host;
    Frame.SetBounds(0, 0, 640, 300);
    Frame.Source := Source;
    // Schritt 4 offen, Zusammenfassung, höchstens MaxLines Funde, der Rest als „… und n weitere“.
    Assert.AreNotEqual(string(#$2713), Frame.StepMark(TAtlasSetupStep.Paths).Caption);
    Assert.IsTrue(Frame.PathsInfo.Visible);
    Assert.AreEqual('9 Units nicht gefunden, 1 Defines ohne Quelle (12 Dateien geprüft)', Frame.PathsInfo.Caption);
    Assert.IsTrue(Frame.Finding(0).Visible);
    Assert.Contains(Frame.Finding(0).Caption, 'Xml.Helpers');
    Assert.IsTrue(Frame.Finding(TAtlasWelcomeSetup.MaxLines - 1).Visible);
    Assert.IsTrue(Frame.MoreLabel.Visible);
    Assert.AreEqual('… und 4 weitere', Frame.MoreLabel.Caption);
    Assert.IsTrue(Frame.Button(TAtlasSetupButton.Options).Visible);
    Assert.IsTrue(Frame.Finding(0).Top > Frame.StepText(TAtlasSetupStep.Paths).Top);
    // Ein Klick auf den Fund öffnet die Projektoptionen.
    Frame.Finding(0).OnClick(Frame.Finding(0));
    CheckSynchronize;
    Assert.AreEqual(1, Integer(Length(Fake.Calls)));
    Assert.AreEqual('options', Fake.Calls[0]);
    // Saubere Prüfung: Schritt 4 grün, keine Funde.
    Fake.Card_.Facts.Setup.MissingUnitCount := 0;
    Fake.Card_.Facts.Setup.UndefinedDefineCount := 0;
    Fake.Card_.Facts.Setup.MissingUnits := nil;
    Fake.Card_.Facts.Setup.UndefinedDefines := nil;
    Frame.UpdateContent;
    Assert.AreEqual(string(#$2713), Frame.StepMark(TAtlasSetupStep.Paths).Caption);
    Assert.IsFalse(Frame.Finding(0).Visible);
    Assert.IsFalse(Frame.PathsInfo.Visible);
    Assert.IsFalse(Frame.Button(TAtlasSetupButton.Options).Visible);
  finally
    Host.Free;
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasWelcomeSetupFrameTests.UncertainAndGroupCaptions;
var
  Saved: TAtlasLanguage;
  Line: TAtlasSetupLine;
  Card: TAtlasSetupCard;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Line := Default(TAtlasSetupLine);
    Line.Kind := TAtlasSetupFindingKind.MissingUnit;
    Line.Name := 'Lib.Core';
    Line.FileName := 'App\App.dpr';
    Line.Line := 3;
    Line.Count := 1;
    Line.Uncertain := True;
    Line.Macros := '$(MYLIB)';
    Assert.AreEqual('Unit „Lib.Core“ nicht gefunden (unsicher, Suchpfad mit unbekanntem Makro $(MYLIB) ' +
      'übersprungen) – App\App.dpr, Zeile 3', TAtlasWelcomeSetupFrame.FindingCaption(Line));
    Line.Project := 'App';
    Line.Kind := TAtlasSetupFindingKind.UndefinedDefine;
    Line.Name := 'USE_LIB';
    Assert.AreEqual('App: Define „USE_LIB“ ohne Quelle (unsicher, Suchpfad mit unbekanntem Makro $(MYLIB) ' +
      'übersprungen) – App\App.dpr, Zeile 3', TAtlasWelcomeSetupFrame.FindingCaption(Line));
    Card := SetupCard;
    Card.GroupProjects := 3;
    Card.GroupChecked := 1;
    Card.Facts.Setup.MissingUnitCount := 2;
    Card.Facts.Setup.UncertainUnitCount := 1;
    Card.Facts.Setup.Files := 5;
    Card.Facts.Setup.SkippedMacros := ['MYLIB'];
    Assert.AreEqual('1 von 3 Projekten der Gruppe geprüft' + sLineBreak +
      '2 Units nicht gefunden, 0 Defines ohne Quelle (5 Dateien geprüft)' + sLineBreak +
      'Davon unsicher: 1 (Suchpfad mit unbekanntem Makro $(MYLIB) übersprungen)',
      TAtlasWelcomeSetupFrame.PathsCaption(Card));
    // Fehler gehen vor.
    Card.Paths := TAtlasSetupRun.Failed;
    Card.PathsError := 'kaputt';
    Assert.AreEqual('kaputt', TAtlasWelcomeSetupFrame.PathsCaption(Card));
    // Einzelprojekt ohne Prüfung: nichts.
    Assert.AreEqual('', TAtlasWelcomeSetupFrame.PathsCaption(SetupCard));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasWelcomeSetupFrameTests.CardAndNewRowFollowCard;
var
  Host: TForm;
  Fake: TFakeSetup;
  Source: IAtlasSetupSource;
  Frame: TAtlasWelcomeSetupFrame;
  Step: TAtlasSetupStep;
  Full: Integer;
begin
  Fake := TFakeSetup.Create;
  Fake.Card_ := SetupCard;
  Source := Fake;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeSetupFrame.Create(Host);
    Frame.Parent := Host;
    Frame.SetBounds(0, 0, 640, 300);
    Frame.Source := Source;
    Assert.IsTrue(Frame.NewRowLabel.Visible);
    Assert.IsTrue(Frame.Button(TAtlasSetupButton.NewUnit).Visible);
    Assert.IsTrue(Frame.Button(TAtlasSetupButton.NewForm).Visible);
    Assert.IsTrue(Frame.Button(TAtlasSetupButton.NewTest).Visible);
    Assert.IsTrue(Frame.NewRowLabel.Top > Frame.DismissLabel.Top, '„Neu mit Atlas“ unter der Karte');
    Assert.AreEqual(Frame.Button(TAtlasSetupButton.NewUnit).Top, Frame.Button(TAtlasSetupButton.NewTest).Top);
    Full := Frame.PreferredHeight;
    // Vollständig eingerichtet bzw. abgewählt: keine Karte, nur „Neu mit Atlas“.
    Fake.Card_.ShowCard := False;
    Frame.UpdateContent;
    for Step := Low(TAtlasSetupStep) to High(TAtlasSetupStep) do
      Assert.IsFalse(Frame.StepText(Step).Visible);
    Assert.IsFalse(Frame.TemplateBox.Visible);
    Assert.IsFalse(Frame.Button(TAtlasSetupButton.Baseline).Visible);
    Assert.IsFalse(Frame.DismissLabel.Visible);
    Assert.IsTrue(Frame.Button(TAtlasSetupButton.NewUnit).Visible);
    Assert.IsTrue(Frame.PreferredHeight < Full);
    // newFromTemplate aus: nur die Karte.
    Fake.Card_.ShowCard := True;
    Fake.Card_.ShowNew := False;
    Frame.UpdateContent;
    Assert.IsTrue(Frame.StepText(TAtlasSetupStep.Config).Visible);
    Assert.IsFalse(Frame.NewRowLabel.Visible);
    Assert.IsFalse(Frame.Button(TAtlasSetupButton.NewUnit).Visible);
    Assert.IsFalse(Frame.Button(TAtlasSetupButton.NewTest).Visible);
    // Schmal: Knöpfe brechen um, der Bereich wird höher.
    Full := Frame.PreferredHeight;
    Frame.Width := 200;
    Frame.UpdateContent;
    Assert.IsTrue(Frame.Button(TAtlasSetupButton.CreateConfig).Top > Frame.StepText(TAtlasSetupStep.Config).Top);
    Assert.IsTrue(Frame.PreferredHeight > Full);
  finally
    Host.Free;
  end;
end;

procedure TAtlasWelcomeSetupFrameTests.ClicksReachSource;
var
  Host: TForm;
  Fake: TFakeSetup;
  Source: IAtlasSetupSource;
  Frame: TAtlasWelcomeSetupFrame;
begin
  Fake := TFakeSetup.Create;
  Fake.Card_ := SetupCard;
  Source := Fake;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeSetupFrame.Create(Host);
    Frame.Parent := Host;
    Frame.SetBounds(0, 0, 640, 300);
    // Ohne Quelle geht nichts.
    Frame.ClickButton(TAtlasSetupButton.CreateConfig);
    CheckSynchronize;
    Assert.AreEqual(0, Integer(Length(Fake.Calls)));
    Frame.Source := Source;
    Frame.SelectTemplate(TAtlasSetupTemplate.Legacy);
    Frame.Button(TAtlasSetupButton.CreateConfig).Click;
    Frame.Button(TAtlasSetupButton.Baseline).Click;
    Frame.Button(TAtlasSetupButton.Paths).Click;
    Frame.DismissLabel.OnClick(Frame.DismissLabel);
    Frame.Button(TAtlasSetupButton.NewUnit).Click;
    Frame.Button(TAtlasSetupButton.NewForm).Click;
    Frame.Button(TAtlasSetupButton.NewTest).Click;
    Assert.AreEqual(0, Integer(Length(Fake.Calls)), 'über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(7, Integer(Length(Fake.Calls)));
    Assert.AreEqual('config:legacy', Fake.Calls[0]);
    Assert.AreEqual('baseline', Fake.Calls[1]);
    Assert.AreEqual('paths', Fake.Calls[2]);
    Assert.AreEqual('dismiss', Fake.Calls[3]);
    Assert.AreEqual('new:unit', Fake.Calls[4]);
    Assert.AreEqual('new:form', Fake.Calls[5]);
    Assert.AreEqual('new:test', Fake.Calls[6]);
    // Projekt nicht offen: Baseline und Prüfung öffnen erst das Projekt.
    Fake.Calls := nil;
    Fake.Card_.ProjectOpen := False;
    Frame.UpdateContent;
    Frame.ClickButton(TAtlasSetupButton.Baseline);
    Frame.ClickButton(TAtlasSetupButton.Paths);
    CheckSynchronize;
    Assert.AreEqual(2, Integer(Length(Fake.Calls)));
    Assert.AreEqual('open', Fake.Calls[0]);
    Assert.AreEqual('open', Fake.Calls[1]);
    // Unsichtbare Knöpfe tun nichts: Schritt 2 erledigt, keine Karte.
    Fake.Calls := nil;
    Fake.Card_.Facts.ConfigExists := True;
    Fake.Card_.ShowCard := False;
    Frame.UpdateContent;
    Frame.ClickButton(TAtlasSetupButton.CreateConfig);
    Frame.ClickButton(TAtlasSetupButton.Dismiss);
    Frame.ClickButton(TAtlasSetupButton.Options);
    CheckSynchronize;
    Assert.AreEqual(0, Integer(Length(Fake.Calls)));
  finally
    Host.Free;
  end;
end;

procedure TAtlasWelcomeSetupFrameTests.RunningStepShowsSeconds;
var
  Saved: TAtlasLanguage;
  Host: TForm;
  Fake: TFakeSetup;
  Source: IAtlasSetupSource;
  Frame: TAtlasWelcomeSetupFrame;
  Card: TAtlasSetupCard;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Card := SetupCard;
    Card.Baseline := TAtlasSetupRun.Running;
    Card.BaselineStarted := 1000;
    Assert.AreEqual('Baseline wird erzeugt … 12 s',
      TAtlasWelcomeSetupFrame.StepCaption(TAtlasSetupStep.Baseline, Card, 13500));
    Card.Paths := TAtlasSetupRun.Running;
    Card.PathsStarted := 1000;
    Assert.AreEqual('Suchpfade und Defines werden geprüft … 2 s',
      TAtlasWelcomeSetupFrame.StepCaption(TAtlasSetupStep.Paths, Card, 3000));
    Fake := TFakeSetup.Create;
    Fake.Card_ := Card;
    Fake.Card_.BaselineStarted := TThread.GetTickCount64;
    Fake.Card_.PathsStarted := TThread.GetTickCount64;
    Source := Fake;
    Host := TForm.CreateNew(nil);
    try
      Frame := TAtlasWelcomeSetupFrame.Create(Host);
      Frame.Parent := Host;
      Frame.SetBounds(0, 0, 640, 300);
      Frame.Source := Source;
      // Laufender Schritt: Knopf bleibt sichtbar, aber ausgegraut (kein zweiter Lauf).
      Assert.IsTrue(Frame.Button(TAtlasSetupButton.Baseline).Visible);
      Assert.IsFalse(Frame.Button(TAtlasSetupButton.Baseline).Enabled);
      Assert.IsFalse(Frame.Button(TAtlasSetupButton.Paths).Enabled);
      Assert.Contains(Frame.StepText(TAtlasSetupStep.Baseline).Caption, '0 s');
      Frame.ClickButton(TAtlasSetupButton.Baseline);
      CheckSynchronize;
      Assert.AreEqual(0, Integer(Length(Fake.Calls)));
      // Fehler: Grund unter dem Schritt.
      Fake.Card_.Baseline := TAtlasSetupRun.Failed;
      Fake.Card_.BaselineError := 'Server nicht bereit';
      Frame.UpdateContent;
      Assert.IsTrue(Frame.Button(TAtlasSetupButton.Baseline).Enabled);
      Assert.IsTrue(Frame.BaselineInfo.Visible);
      Assert.AreEqual('Server nicht bereit', Frame.BaselineInfo.Caption);
    finally
      Host.Free;
    end;
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasWelcomeSetupFrameTests.PreviewShowsContent;
var
  Saved: TAtlasLanguage;
  Dialog: TAtlasSetupPreviewDialog;
  Text: string;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Text := StringReplace(TAtlasProjectSetups.BuiltIn(TAtlasSetupTemplate.Existing), #10, sLineBreak,
      [rfReplaceAll]);
    Dialog := TAtlasSetupPreviewDialog.CreateDialog(nil, 'atlas.json', 'XmlInspector.dproj', 'Bestehendes Projekt',
      Text);
    try
      Assert.AreEqual('atlas.json anlegen', Dialog.Caption);
      Assert.AreEqual('Atlas legt atlas.json neben XmlInspector.dproj an (Vorlage „Bestehendes Projekt“). Inhalt:',
        Dialog.Intro.Caption);
      Assert.Contains(Dialog.Content.Text, '"profile": "standard"');
      Assert.IsTrue(Dialog.Content.ReadOnly);
      Assert.IsTrue(Dialog.CreateButton.Default);
      Assert.IsTrue(Dialog.CancelButton.Cancel, 'Esc schreibt nichts');
      Assert.AreEqual(Integer(mrOk), Integer(Dialog.CreateButton.ModalResult));
      Assert.AreEqual(Integer(mrCancel), Integer(Dialog.CancelButton.ModalResult));
    finally
      Dialog.Free;
    end;
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasWelcomeDiscoverFrameTests.ImageFitsColumn;
var
  Host: TForm;
  Fake: TFakeDiscover;
  Source: IAtlasDiscoverSource;
  Frame: TAtlasWelcomeDiscoverFrame;
  Folder, FileName: string;
  Png: TPngImage;
begin
  Folder := TPath.Combine(TPath.GetTempPath, 'AtlasDiscoverImage' + IntToStr(Random(1000000)));
  ForceDirectories(Folder);
  FileName := TPath.Combine(Folder, 'tipp.png');
  Png := TPngImage.CreateBlank(COLOR_RGB, 8, TAtlasWelcomeDiscoverFrame.ImageWidth,
    TAtlasWelcomeDiscoverFrame.ImageHeight);
  try
    Png.SaveToFile(FileName);
  finally
    Png.Free;
  end;
  Fake := DiscoverFake;
  Fake.Card_.ImageFile := FileName;
  Source := Fake;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeDiscoverFrame.Create(Host);
    Frame.Parent := Host;
    // Schmale Spalte: Bild oben, höchstens so breit wie die Spalte, Seitenverhältnis 16:9; Text darunter.
    Frame.SetBounds(0, 0, 420, 200);
    Frame.Source := Source;
    Assert.IsTrue(Frame.Image.Visible, 'Bild geladen');
    Assert.IsTrue(Frame.Image.Width <= Frame.ClientWidth);
    Assert.IsTrue(Frame.Image.Width >= TAtlasWelcomeDiscoverFrame.ImageWidth, 'bei 100 % volle Größe, sonst mehr');
    Assert.IsTrue(Abs(Frame.Image.Height - Frame.Image.Width * TAtlasWelcomeDiscoverFrame.ImageHeight div
      TAtlasWelcomeDiscoverFrame.ImageWidth) <= 1, 'Seitenverhältnis bleibt');
    Assert.IsTrue(Frame.TipTitle.Top >= Frame.Image.Top + Frame.Image.Height, 'Titel unter dem Bild');
    Assert.AreEqual(Frame.Image.Left, Frame.TipTitle.Left, 'Text bündig mit dem Bild');
    Assert.IsTrue(Frame.PreferredHeight > Frame.Image.Height, 'Höhe mit Bild');
    // Breite Spalte: Text neben dem Bild.
    Frame.SetBounds(0, 0, 2000, 200);
    Frame.UpdateContent;
    Assert.IsTrue(Frame.TipTitle.Left >= Frame.Image.Left + Frame.Image.Width, 'Titel neben dem Bild');
    Assert.IsTrue(Frame.TipTitle.Top < Frame.Image.Top + Frame.Image.Height);
    // Ohne Bild: kein Platz dafür.
    Fake.Card_.ImageFile := '';
    Frame.UpdateContent;
    Assert.IsFalse(Frame.Image.Visible);
    Assert.AreEqual(Frame.ScaleValue(TAtlasWelcomeDiscoverFrame.Indent), Frame.TipTitle.Left);
  finally
    Host.Free;
    TDirectory.Delete(Folder, True);
  end;
end;

{ TFakeContinue }

function TFakeContinue.Entries: TAtlasContinueEntries;
begin
  Result := FEntries;
end;

function TFakeContinue.Incoming: TAtlasContinueIncoming;
begin
  Result := FIncoming;
end;

function TFakeContinue.IncomingQuerying: Boolean;
begin
  Result := FQuerying;
end;

function TFakeContinue.SavedEnabled: Boolean;
begin
  Result := FSavedEnabled;
end;

function TFakeContinue.Saved: TAtlasSavedItems;
begin
  Calls := Calls + ['saved'];
  Result := FSaved;
end;

function TFakeContinue.Notice: string;
begin
  Result := FNotice;
end;

procedure TFakeContinue.Resume(const AProject: string);
begin
  Calls := Calls + ['resume ' + AProject];
end;

procedure TFakeContinue.ShowCommit(const AProject: string; const ACommit: TAtlasContinueCommit);
begin
  Calls := Calls + ['commit ' + AProject + ' ' + ACommit.Commit.ShortHash];
end;

procedure TFakeContinue.OpenSaved(const AItem: TAtlasSavedItem);
begin
  Calls := Calls + ['open ' + AItem.Id];
end;

procedure TFakeContinue.Shown;
begin
  Calls := Calls + ['shown'];
end;

function ContinueEntry(const AProject: string; ATabs: Integer; AAtUtc: TDateTime): TAtlasContinueEntry;
var
  Index: Integer;
begin
  Result := Default(TAtlasContinueEntry);
  Result.Project := AProject;
  Result.State := TAtlasWorkState.Empty;
  Result.State.Known := True;
  Result.State.At := AAtUtc;
  for Index := 1 to ATabs do
    Result.State.Tabs := Result.State.Tabs + [TAtlasWorkTab.Create('C:\Repo\Unit' + IntToStr(Index) + '.pas', 1, 1)];
end;

function ContinueCommit(const AHash, ASummary, AAuthor, AFile: string): TAtlasContinueCommit;
begin
  Result := Default(TAtlasContinueCommit);
  Result.Commit.Hash := AHash;
  Result.Commit.Summary := ASummary;
  Result.Commit.Author := AAuthor;
  Result.Commit.Files := [AFile, 'C:\Repo\Neu.pas'];
  Result.Files := [AFile];
end;

function SavedItem(AKind: TAtlasSavedKind; const AId, AText, AFileName, AProject: string;
  ALine: Integer): TAtlasSavedItem;
begin
  Result := Default(TAtlasSavedItem);
  Result.Kind := AKind;
  Result.Id := AId;
  Result.Text := AText;
  Result.FileName := AFileName;
  Result.Project := AProject;
  Result.Line := ALine;
end;

{ TAtlasWelcomeContinueFrameTests }

procedure TAtlasWelcomeContinueFrameTests.WarmUpFirstUse;
begin
  ResumeAndCommitReachSource;
end;

procedure TAtlasWelcomeContinueFrameTests.TextsFollowLanguageAndAge;
var
  Saved: TAtlasLanguage;
  Entry: TAtlasContinueEntry;
  NowUtc: TDateTime;
  Favorite: TAtlasSavedItem;
  Cells: TArray<string>;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    NowUtc := TAtlasWelcomeContinueFrame.NowUtc;
    Entry := ContinueEntry('C:\Repo\Atlas.dproj', 7, NowUtc - 2 * OneHour - 5 * OneMinute);
    Entry.State.Tabs[3].Changed := True;
    Entry.State.Tabs[3].ChangedAt := NowUtc - OneHour;
    Entry.State.Tabs[3].Method := 'TKunde.Laden';
    Entry.State.Tabs[3].Line := 42;
    Assert.AreEqual('Atlas · 7 Reiter', TAtlasWelcomeContinueFrame.TitleText(Entry));
    Assert.AreEqual('Unit4.pas › TKunde.Laden', TAtlasWelcomeContinueFrame.DetailText(Entry),
      'zuletzt bearbeitete Datei und Methode');
    Assert.AreEqual('1 Reiter', TAtlasWelcomeContinueFrame.TabsText(1));
    Assert.Contains(TAtlasWelcomeContinueFrame.HintFor(Entry, NowUtc), 'Unit4.pas:42');
    Assert.AreEqual('gerade eben', TAtlasWelcomeContinueFrame.AgeText(NowUtc - 10 * OneSecond, NowUtc));
    Assert.AreEqual('vor 5 Min.', TAtlasWelcomeContinueFrame.AgeText(NowUtc - 5 * OneMinute - OneSecond, NowUtc));
    Assert.AreEqual('', TAtlasWelcomeContinueFrame.AgeText(0, NowUtc), 'unbekannt');
    Assert.AreEqual('abc1234  Kunde: Prüfung — Eva · Kunde.pas', TAtlasWelcomeContinueFrame.CommitText(
      ContinueCommit('abc1234ffff', 'Kunde: Prüfung', 'Eva', 'C:\Repo\Kunde.pas')));
    Assert.Contains(TAtlasWelcomeContinueFrame.CommitHint(ContinueCommit('abc1234ffff', 'Kunde: Prüfung', 'Eva',
      'C:\Repo\Kunde.pas')), 'Autor: Eva');
    Cells := TAtlasWelcomeContinueFrame.SavedCells(SavedItem(TAtlasSavedKind.Bookmark, 'b1', 'Speichern',
      'C:\Repo\Kunde.pas', 'C:\Repo\Atlas.dproj', 79));
    Assert.AreEqual(4, Integer(Length(Cells)));
    Assert.AreEqual('Lesezeichen', Cells[0]);
    Assert.AreEqual('Speichern', Cells[1]);
    Assert.AreEqual('Kunde.pas:80', Cells[2]);
    Assert.AreEqual('Atlas', Cells[3]);
    Favorite := SavedItem(TAtlasSavedKind.Favorite, 'tdataset|open', 'TDataSet.Open', '', '', -1);
    Favorite.UnitName := 'Data.DB';
    Cells := TAtlasWelcomeContinueFrame.SavedCells(Favorite);
    Assert.AreEqual('Favorit', Cells[0]);
    Assert.AreEqual('Data.DB', Cells[2]);
    Assert.AreEqual('alle Projekte', Cells[3]);
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('Atlas · 7 tabs', TAtlasWelcomeContinueFrame.TitleText(Entry));
    Assert.AreEqual('5 min ago', TAtlasWelcomeContinueFrame.AgeText(NowUtc - 5 * OneMinute - OneSecond, NowUtc));
    Assert.AreEqual('Note', TAtlasWelcomeContinueFrame.KindText(TAtlasSavedKind.Note));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasWelcomeContinueFrameTests.ResumeAndCommitReachSource;
var
  Host: TForm;
  Fake: TFakeContinue;
  Source: IAtlasContinueSource;
  Frame: TAtlasWelcomeContinueFrame;
  Hit: TAtlasContinueHit;
  Height: Integer;
begin
  Fake := TFakeContinue.Create;
  Source := Fake;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeContinueFrame.Create(Host);
    Frame.Parent := Host;
    Frame.Width := 600;
    Frame.Source := Source;
    Assert.AreEqual('shown', Fake.Calls[0], 'Shown beim Setzen der Quelle');
    Height := Frame.PreferredHeight;
    Fake.FEntries := [ContinueEntry('C:\Repo\Atlas.dproj', 7, Now), ContinueEntry('C:\Alt\Alt.groupproj', 2, Now)];
    Fake.FIncoming.Available := True;
    Fake.FIncoming.Project := 'C:\Repo\Atlas.dproj';
    Fake.FIncoming.Upstream := 'origin/main';
    Fake.FIncoming.Commits := [ContinueCommit('abc1234ffff', 'Kunde: Prüfung', 'Eva', 'C:\Repo\Kunde.pas')];
    Frame.UpdateContent;
    Assert.IsTrue(Frame.PreferredHeight > Height, 'zwei Arbeitsstände und ein Commit brauchen mehr Platz');
    Assert.AreEqual(2, Integer(Length(Frame.Entries)));
    Fake.Calls := nil;
    // Klick auf die Zeile außerhalb von „Fortsetzen“: nichts.
    Hit.Row := 0;
    Hit.Button := False;
    Hit.Commit := -1;
    Frame.ClickAt(Hit);
    Hit.Row := 1;
    Hit.Button := True;
    Frame.ClickAt(Hit);
    Hit.Row := -1;
    Hit.Button := False;
    Hit.Commit := 0;
    Frame.ClickAt(Hit);
    Hit.Commit := 3;
    Frame.ClickAt(Hit);
    Assert.AreEqual(0, Integer(Length(Fake.Calls)), 'alles über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(2, Integer(Length(Fake.Calls)));
    Assert.AreEqual('resume C:\Alt\Alt.groupproj', Fake.Calls[0]);
    Assert.AreEqual('commit C:\Repo\Atlas.dproj abc1234', Fake.Calls[1]);
    Assert.AreEqual(-1, Frame.HitTest(20, -5).Row, 'über der ersten Zeile');
    Assert.AreEqual(1, Frame.HitTest(20, Frame.RowTop(1) + 4).Row);
  finally
    Host.Free;
  end;
end;

procedure TAtlasWelcomeContinueFrameTests.QuickActionsInRecent;
var
  Host: TForm;
  Fake: TFakeContinue;
  Source: IAtlasContinueSource;
  Quick: TAtlasFakeQuickActions;
  QuickSource: IAtlasQuickActionsSource;
  Frame: TAtlasWelcomeContinueFrame;
begin
  Fake := TFakeContinue.Create;
  Source := Fake;
  Quick := TAtlasFakeQuickActions.Create;
  QuickSource := Quick;
  Fake.FEntries := [ContinueEntry('C:\Repo\Atlas.dproj', 7, Now), ContinueEntry('C:\Alt\Alt.groupproj', 2, Now)];
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeContinueFrame.Create(Host);
    Frame.Parent := Host;
    Frame.Width := 600;
    Frame.Source := Source;
    Assert.AreEqual(0, Integer(Length(Frame.Quick.ButtonsOf(0))), 'ohne Quelle keine Knöpfe');
    Frame.QuickActions := QuickSource;
    Assert.AreEqual(6, Integer(Length(Frame.Quick.ButtonsOf(1))));
    Assert.IsTrue(Frame.Quick.Sink.Visible, 'Tastatur auf „Zuletzt“');
    Fake.Calls := nil;
    // Ohne Maus: Pfeil ab, Strg+B baut die Gruppe, Pos1 und Enter setzen fort.
    Assert.IsTrue(Frame.Quick.HandleKey(VK_DOWN, []));
    Assert.IsTrue(Frame.Quick.HandleKey(Ord('B'), [ssCtrl]));
    Assert.IsTrue(Frame.Quick.HandleKey(VK_HOME, []));
    Assert.IsTrue(Frame.Quick.HandleKey(VK_RETURN, []));
    CheckSynchronize;
    Assert.AreEqual(1, Integer(Length(Quick.Calls)));
    Assert.AreEqual('build C:\Alt\Alt.groupproj', Quick.Calls[0]);
    Assert.AreEqual(1, Integer(Length(Fake.Calls)));
    Assert.AreEqual('resume C:\Alt\Alt.groupproj', Fake.Calls[0]);
    // Ausgeschaltet: keine Knöpfe mehr.
    Quick.IsOn := False;
    Frame.UpdateContent;
    Assert.AreEqual(0, Integer(Length(Frame.Quick.ButtonsOf(1))));
  finally
    Host.Free;
  end;
end;

procedure TAtlasWelcomeContinueFrameTests.IncomingSectionOnlyWithData;
var
  Host: TForm;
  Fake: TFakeContinue;
  Source: IAtlasContinueSource;
  Frame: TAtlasWelcomeContinueFrame;
  Without, Querying, WithCommit: Integer;
begin
  Fake := TFakeContinue.Create;
  Source := Fake;
  Fake.FEntries := [ContinueEntry('C:\Repo\Atlas.dproj', 3, Now)];
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeContinueFrame.Create(Host);
    Frame.Parent := Host;
    Frame.Width := 600;
    Frame.Source := Source;
    // Ohne Versionsverwaltung bzw. ohne Ergebnis: kein Abschnitt.
    Without := Frame.PreferredHeight;
    Assert.AreEqual(-1, Frame.HitTest(20, Frame.IncomingTop + 2 * Frame.ScaleValue(
      TAtlasWelcomeContinueFrame.LineHeight)).Commit);
    Fake.FQuerying := True;
    Frame.UpdateContent;
    Querying := Frame.PreferredHeight;
    Assert.IsTrue(Querying > Without, '„wird abgefragt …“');
    Fake.FQuerying := False;
    Fake.FIncoming.Available := True;
    Fake.FIncoming.Project := 'C:\Repo\Atlas.dproj';
    Fake.FIncoming.Upstream := 'origin/main';
    Fake.FIncoming.Commits := [ContinueCommit('abc1234ffff', 'Eins', 'Eva', 'C:\Repo\Unit1.pas'),
      ContinueCommit('def5678ffff', 'Zwei', 'Max', 'C:\Repo\Unit2.pas')];
    Fake.FIncoming.More := True;
    Frame.UpdateContent;
    WithCommit := Frame.PreferredHeight;
    Assert.IsTrue(WithCommit > Querying, 'zwei Commits und „… und weitere“');
    Assert.AreEqual(1, Frame.HitTest(20, Frame.IncomingTop + 2 * Frame.ScaleValue(
      TAtlasWelcomeContinueFrame.LineHeight) + 2).Commit, 'Überschrift, dann die Commits');
    // Ohne Arbeitsstand auch kein Abschnitt.
    Fake.FEntries := nil;
    Frame.UpdateContent;
    Assert.IsTrue(Frame.PreferredHeight < WithCommit);
    // Hinweis der Quelle (übersprungene Dateien) braucht eine Zeile.
    Fake.FEntries := [ContinueEntry('C:\Repo\Atlas.dproj', 3, Now)];
    Fake.FIncoming := Default(TAtlasContinueIncoming);
    Frame.UpdateContent;
    Without := Frame.PreferredHeight;
    Fake.FNotice := 'nicht mehr vorhanden, übersprungen: Weg.pas';
    Frame.UpdateContent;
    Assert.IsTrue(Frame.PreferredHeight > Without);
  finally
    Host.Free;
  end;
end;

procedure TAtlasWelcomeContinueFrameTests.SavedTabFiltersAndOpens;
var
  Host: TForm;
  Fake: TFakeContinue;
  Source: IAtlasContinueSource;
  Frame: TAtlasWelcomeContinueFrame;
  Key: Word;
begin
  Fake := TFakeContinue.Create;
  Source := Fake;
  Fake.FSavedEnabled := True;
  Fake.FSaved := [SavedItem(TAtlasSavedKind.Note, 'n1', 'Prüfen', 'C:\Repo\Kunde.pas', 'C:\Repo\Atlas.dproj', 4),
    SavedItem(TAtlasSavedKind.Bookmark, 'b1', 'Speichern', 'C:\Zeta\Haupt.pas', 'C:\Zeta\Zeta.dproj', 9)];
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeContinueFrame.Create(Host);
    Frame.Parent := Host;
    Frame.Width := 600;
    Frame.Source := Source;
    Assert.IsTrue(Frame.Tabs.Visible, 'Reiter „Zuletzt“ und „Gemerkt“');
    Assert.AreEqual(2, Integer(Frame.Tabs.Tabs.Count));
    Assert.AreEqual(TAtlasWelcomeContinueFrame.PageRecent, Frame.Page);
    Assert.AreEqual(0, Integer(Length(Fake.Calls)) - 1, '„Gemerkt“ erst beim Wechsel lesen');
    Frame.Page := TAtlasWelcomeContinueFrame.PageSaved;
    Assert.AreEqual(TAtlasWelcomeContinueFrame.PageSaved, Frame.Page);
    Assert.AreEqual(2, Integer(Frame.List.Items.Count));
    Assert.AreEqual('Notiz', Frame.List.Items[0].Caption);
    Assert.AreEqual('Kunde.pas:5', Frame.List.Items[0].SubItems[1]);
    Assert.AreEqual('Zeta', Frame.List.Items[1].SubItems[2]);
    Frame.Filter.Text := 'zeta';
    Assert.AreEqual(1, Integer(Frame.List.Items.Count), 'Filter');
    Assert.AreEqual('b1', Frame.ShownSaved[0].Id);
    Frame.Filter.Text := 'gibtsnicht';
    Assert.IsTrue(Frame.SavedEmptyLabel.Visible);
    Assert.IsFalse(Frame.List.Visible);
    Frame.Filter.Text := '';
    Frame.List.Items[1].Selected := True;
    Fake.Calls := nil;
    Frame.OpenSelected;
    Assert.AreEqual(0, Integer(Length(Fake.Calls)), 'über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(1, Integer(Length(Fake.Calls)));
    Assert.AreEqual('open b1', Fake.Calls[0]);
    // Enter im Filterfeld öffnet den gewählten Eintrag.
    Fake.Calls := nil;
    Key := VK_RETURN;
    Frame.Filter.OnKeyDown(Frame.Filter, Key, []);
    Assert.AreEqual(0, Integer(Key));
    CheckSynchronize;
    Assert.AreEqual('open b1', Fake.Calls[0], 'Enter öffnet den gewählten Eintrag');
  finally
    Host.Free;
  end;
end;

procedure TAtlasWelcomeContinueFrameTests.WithoutSavedOnlyRecent;
var
  Host: TForm;
  Fake: TFakeContinue;
  Source: IAtlasContinueSource;
  Frame: TAtlasWelcomeContinueFrame;
begin
  Fake := TFakeContinue.Create;
  Source := Fake;
  Fake.FSavedEnabled := False;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeContinueFrame.Create(Host);
    Frame.Parent := Host;
    Frame.Width := 600;
    Frame.Source := Source;
    Assert.IsFalse(Frame.Tabs.Visible, 'welcomePage.saved aus: keine Reiter');
    Frame.Page := TAtlasWelcomeContinueFrame.PageSaved;
    Assert.AreEqual(TAtlasWelcomeContinueFrame.PageRecent, Frame.Page);
    Assert.IsTrue(Frame.PaintBox.Visible);
    Assert.AreEqual(1, Integer(Length(Fake.Calls)), 'nichts gelesen außer Shown');
  finally
    Host.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeContinueFrameTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeHeaderTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeSearchBoxTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeBoardTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeArrangeBoardTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeWhatsNewFrameTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeProjectsFrameTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeUnsavedFrameTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeStateFrameTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeDiscoverFrameTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeHelpFrameTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeSetupFrameTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeTrendsFrameTests);

end.
