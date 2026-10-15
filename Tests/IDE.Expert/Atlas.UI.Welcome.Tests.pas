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
// Knöpfe nach Lage, leere Karte, Klicks über die Nachrichtenschleife.

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
  end;

implementation

uses
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
  Atlas.Core.Welcome.Search,
  Atlas.UI.Welcome.Search,
  Atlas.Core.Welcome.WhatsNew,
  Atlas.UI.Welcome.WhatsNew,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Welcome.Projects,
  Atlas.UI.Welcome.Projects,
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
  Atlas.UI.Welcome.Discover;

type
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

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeHeaderTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeSearchBoxTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeBoardTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeWhatsNewFrameTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeProjectsFrameTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeUnsavedFrameTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeStateFrameTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeDiscoverFrameTests);

end.
