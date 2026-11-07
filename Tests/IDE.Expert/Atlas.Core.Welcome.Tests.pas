unit Atlas.Core.Welcome.Tests;

// Tests der Atlas-Willkommensseite ohne VCL (#753): Bereichsregister,
// Atlas-Layout und Verteilung auf Spalten, Grußzeile, Sicherung des
// Registry-Schlüssels WelcomePage (exakt zurück, auch „gab es nicht“),
// Raster der IDE nach dem Export aus Delphi 12, Atlas-Layout darin, Aufräumen
// der Atlas-Bereiche auf der Willkommensseite der IDE (#1114), Schritte beim
// Umschalten von welcomePage.ideWelcomePage (#761) und die Einstellungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasWelcomeSectionsTests = class
  public
    [Test]
    procedure SortsByOrderThenId;
    [Test]
    procedure AddReplacesSameId;
    [Test]
    procedure VisibleFollowsSwitch;
    [Test]
    procedure ListenersHearChanges;
    [Test]
    procedure PluginIdsRoundTrip;
  end;

  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasWelcomeLayoutTests = class
  public
    [Test]
    procedure AtlasLayoutMatchesMockup;
    [Test]
    procedure OneColumnStacksRightUnderLeft;
    [Test]
    procedure UnknownSectionGoesToItsColumn;
    [Test]
    procedure HiddenSectionsLeaveNoGap;
    [Test]
    procedure JsonRoundTrip;
    [Test]
    procedure InvalidJsonGivesAtlas;
    [Test]
    procedure MovedToTopLeadsFirstColumn;
  end;

  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasWelcomeGreetingTests = class
  public
    [Test]
    procedure DayTimeByHour;
    [Test]
    procedure FirstNameFromDisplayName;
    [Test]
    procedure FirstNameFromLastCommaFirst;
    [Test]
    procedure FirstNameFromUserName;
  end;

  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasWelcomeBackupTests = class
  public
    [Test]
    procedure RestoresEveryKindExactly;
    [Test]
    procedure RemovesKeyThatDidNotExist;
    [Test]
    procedure MatchesDetectsChanges;
    [Test]
    procedure RejectsInvalidSnapshot;
    [Test]
    procedure KeyAndFileNames;
  end;

  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasHostLayoutTests = class
  public
    [Test]
    procedure ReadsDelphi12Export;
    [Test]
    procedure NoLayoutKeyMeansNoGrid;
    [Test]
    procedure WithoutAtlasRemovesBoardAndMovesUp;
    [Test]
    procedure WithoutAtlasDropsSingleAndHiddenSections;
    [Test]
    procedure WithoutAtlasClosesGapInTheMiddle;
    [Test]
    procedure WriteKeepsBackgroundValues;
    [Test]
    procedure WriteWithoutSectionsDropsGrid;
    [Test]
    procedure IdeDefaultMatchesDelphi12Export;
    [Test]
    procedure AtlasOnTopShiftsOtherSections;
    [Test]
    procedure AtlasOnTopDropsSingleAtlasSections;
    [Test]
    procedure DetectsMovedBoard;
    [Test]
    procedure WithoutAtlasUndoesAtlasOnTop;
  end;

  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasIdePageStepsTests = class
  public
    [Test]
    procedure FirstSyncDoesNothing;
    [Test]
    procedure SwitchingOffRetires;
    [Test]
    procedure SwitchingOnClearsPendingAndPlacesBoard;
    [Test]
    procedure LayoutChangeOnlyWhileShown;
  end;

  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasWelcomeRetireTests = class
  public
    [Test]
    procedure RestoresBackup;
    [Test]
    procedure RemovesAtlasWithoutBackup;
    [Test]
    procedure BrokenBackupFallsBackToRemoving;
    [Test]
    procedure CleanLayoutStaysUntouched;
  end;

  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasWelcomeSettingsTests = class
  public
    [Test]
    procedure DefaultsOpenWindowOnlyOnRequest;
    [Test]
    procedure DefaultsShowSectionsOnIdePage;
    [Test]
    procedure NormalizeMapsUnknownValues;
    [Test]
    procedure SaveAndLoadRoundTrip;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Welcome.Sections,
  Atlas.Core.Welcome.Layout,
  Atlas.Core.Welcome.Greeting,
  Atlas.Core.Welcome.Backup,
  Atlas.Core.Welcome.HostLayout;

const
  cWelcomePath = 'Software\Embarcadero\BDS\23.0\WelcomePage';

function Section(const AId: string; AOrder: Integer; AColumn: TAtlasWelcomeColumn): TAtlasWelcomeSection;
begin
  Result := TAtlasWelcomeSection.Create(AId, AId, AOrder, AColumn, nil);
end;

function Joined(const AIds: TArray<string>): string;
var
  mId: string;
begin
  Result := '';
  for mId in AIds do
  begin
    if Result = '' then
    begin
      Result := mId;
    end
    else
    begin
      Result := Result + ',' + mId;
    end;
  end;
end;

function Number(const AName: string; AValue: Integer): TAtlasRegValue;
begin
  Result := TAtlasRegValue.Create(AName, TAtlasRegKind.Number, IntToStr(AValue));
end;

/// <summary>Kachel AId an APlace: Zeile, Spalte, Zeilen- und Spaltenspanne.</summary>
procedure AddItem(ALayout: TAtlasRegKey; AIndex: Integer; const AId: string; const APlace: array of Integer);
var
  mItem: TAtlasRegKey;
begin
  Assert.AreEqual(4, Integer(Length(APlace)), 'Zeile, Spalte, Zeilenspanne, Spaltenspanne');
  mItem := ALayout.AddKey('Item ' + IntToStr(AIndex));
  mItem.SetValue(TAtlasRegValue.Create('PluginID', TAtlasRegKind.Text, AId));
  mItem.SetValue(Number('Row', APlace[0]));
  mItem.SetValue(Number('Column', APlace[1]));
  mItem.SetValue(Number('RowSpan', APlace[2]));
  mItem.SetValue(Number('ColumnSpan', APlace[3]));
end;

/// <summary>Schlüssel WelcomePage wie in Marcos Export aus Delphi 12 (BDS 23.0).</summary>
function Delphi12Export: TAtlasRegKey;
var
  mLayout, mAvailable: TAtlasRegKey;
begin
  Result := TAtlasRegKey.Create('WelcomePage');
  Result.SetValue(TAtlasRegValue.Create('Background_Dark', TAtlasRegKind.Text,
    'C:\ProgramData\Embarcadero\BDS\23.0\Background images\Lights at the Night Circus.jpg'));
  Result.SetValue(TAtlasRegValue.Create('Background_Light', TAtlasRegKind.Text, ''));
  mAvailable := Result.AddKey('AvailablePlugins');
  mAvailable.SetValue(TAtlasRegValue.Create('0', TAtlasRegKind.Text, 'Embarcadero.WelcomePagePlugin.GetItPromoted'));
  mAvailable.SetValue(TAtlasRegValue.Create('1', TAtlasRegKind.Text, 'Embarcadero.WelcomePagePlugin.CreateNew'));
  mLayout := Result.AddKey('Layout');
  mLayout.SetValue(Number('RowsCount', 2));
  mLayout.SetValue(Number('ColumnsCount', 3));
  AddItem(mLayout, 0, 'Embarcadero.WelcomePagePlugin.GetItNewIn', [0, 0, 2, 1]);
  AddItem(mLayout, 1, 'Embarcadero.WelcomePagePlugin.OpenRecent', [0, 1, 2, 1]);
  AddItem(mLayout, 2, 'Embarcadero.WelcomePagePlugin.Learn', [0, 2, 2, 1]);
end;

/// <summary>Schlüssel WelcomePage nach „Atlas-Layout anwenden“ früherer Fassungen: „Atlas“ oben über zwei
/// Zeilen, die Bereiche der IDE darunter, „Neu in Atlas“ ausgeblendet.</summary>
function OldAtlasLayout: TAtlasRegKey;
var
  mLayout, mAvailable: TAtlasRegKey;
begin
  Result := TAtlasRegKey.Create('WelcomePage');
  Result.SetValue(TAtlasRegValue.Create('Background_Dark', TAtlasRegKind.Text, 'Nacht.jpg'));
  mAvailable := Result.AddKey('AvailablePlugins');
  mAvailable.SetValue(TAtlasRegValue.Create('0', TAtlasRegKind.Text, 'Embarcadero.WelcomePagePlugin.GetItPromoted'));
  mAvailable.SetValue(TAtlasRegValue.Create('1', TAtlasRegKind.Text, 'Atlas.Welcome.news'));
  mAvailable.SetValue(TAtlasRegValue.Create('2', TAtlasRegKind.Text, 'Embarcadero.WelcomePagePlugin.CreateNew'));
  mLayout := Result.AddKey('Layout');
  mLayout.SetValue(Number('RowsCount', 4));
  mLayout.SetValue(Number('ColumnsCount', 3));
  AddItem(mLayout, 0, 'Atlas.Welcome.board', [0, 0, 2, 3]);
  AddItem(mLayout, 1, 'Embarcadero.WelcomePagePlugin.GetItNewIn', [2, 0, 2, 1]);
  AddItem(mLayout, 2, 'Embarcadero.WelcomePagePlugin.OpenRecent', [2, 1, 2, 1]);
  AddItem(mLayout, 3, 'Embarcadero.WelcomePagePlugin.Learn', [2, 2, 2, 1]);
end;

function ReadLayout(AKey: TAtlasRegKey): TAtlasHostLayout;
begin
  try
    Assert.IsTrue(TAtlasHostLayout.Read(AKey, Result), 'Raster lesbar');
  finally
    AKey.Free;
  end;
end;

{ TAtlasWelcomeSectionsTests }

procedure TAtlasWelcomeSectionsTests.SortsByOrderThenId;
var
  mSections: TAtlasWelcomeSections;
begin
  mSections := TAtlasWelcomeSections.Create;
  try
    mSections.Add(Section('atlas.news', 20, TAtlasWelcomeColumn.Right));
    mSections.Add(Section('atlas.continue', 10, TAtlasWelcomeColumn.Left));
    mSections.Add(Section('atlas.b', 30, TAtlasWelcomeColumn.Left));
    mSections.Add(Section('atlas.a', 30, TAtlasWelcomeColumn.Left));
    Assert.AreEqual('atlas.continue,atlas.news,atlas.a,atlas.b', Joined(mSections.VisibleIds));
  finally
    mSections.Free;
  end;
end;

procedure TAtlasWelcomeSectionsTests.AddReplacesSameId;
var
  mSections: TAtlasWelcomeSections;
  mFound: TAtlasWelcomeSection;
begin
  mSections := TAtlasWelcomeSections.Create;
  try
    mSections.Add(Section('atlas.news', 20, TAtlasWelcomeColumn.Right));
    mSections.Add(TAtlasWelcomeSection.Create('ATLAS.NEWS', 'Neu in Atlas', 5, TAtlasWelcomeColumn.Right, nil));
    Assert.AreEqual(1, Integer(Length(mSections.All)));
    Assert.IsTrue(mSections.Find('atlas.news', mFound));
    Assert.AreEqual('Neu in Atlas', mFound.Title);
    mSections.Remove('atlas.news');
    Assert.IsFalse(mSections.Find('atlas.news', mFound));
    Assert.AreEqual('', mFound.Id);
  finally
    mSections.Free;
  end;
end;

procedure TAtlasWelcomeSectionsTests.VisibleFollowsSwitch;
var
  mSections: TAtlasWelcomeSections;
  mShown: Boolean;
begin
  mShown := False;
  mSections := TAtlasWelcomeSections.Create;
  try
    mSections.Add(TAtlasWelcomeSection.Create('atlas.tests', 'Tests', 10, TAtlasWelcomeColumn.Right,
      function: Boolean
      begin
        Result := mShown;
      end));
    mSections.Add(Section('atlas.help', 20, TAtlasWelcomeColumn.Right));
    Assert.AreEqual('atlas.help', Joined(mSections.VisibleIds), 'Schalter aus');
    mShown := True;
    Assert.AreEqual('atlas.tests,atlas.help', Joined(mSections.VisibleIds), 'Schalter an');
    Assert.AreEqual(2, Integer(Length(mSections.All)));
  finally
    mSections.Free;
  end;
end;

procedure TAtlasWelcomeSectionsTests.ListenersHearChanges;
var
  mSections: TAtlasWelcomeSections;
  mHeard: TList<string>;
  mHandle, mVersion: Integer;
begin
  mHeard := TList<string>.Create;
  mSections := TAtlasWelcomeSections.Create;
  try
    mHandle := mSections.AddListener(
      procedure(AId: string)
      begin
        mHeard.Add(AId);
      end);
    mVersion := mSections.Version;
    mSections.Add(Section('atlas.state', 10, TAtlasWelcomeColumn.Right));
    mSections.Changed('atlas.state');
    mSections.Changed;
    Assert.AreEqual(3, Integer(mHeard.Count));
    Assert.AreEqual('', mHeard[0], 'Hinzufügen ändert die Menge');
    Assert.AreEqual('atlas.state', mHeard[1], 'Inhalt eines Bereichs');
    Assert.AreEqual('', mHeard[2]);
    Assert.AreEqual(mVersion + 3, mSections.Version);
    mSections.RemoveListener(mHandle);
    mSections.Changed;
    Assert.AreEqual(3, Integer(mHeard.Count), 'abgemeldet');
  finally
    mSections.Free;
    mHeard.Free;
  end;
end;

procedure TAtlasWelcomeSectionsTests.PluginIdsRoundTrip;
begin
  Assert.AreEqual('Atlas.Welcome.state', TAtlasWelcomeIds.PluginId(TAtlasWelcomeIds.cState));
  Assert.AreEqual('Atlas.Welcome.board', TAtlasWelcomeIds.PluginId(TAtlasWelcomeIds.cBoard));
  Assert.AreEqual(TAtlasWelcomeIds.cHeader, TAtlasWelcomeIds.SectionOf('Atlas.Welcome.header'));
  Assert.AreEqual(TAtlasWelcomeIds.cHeader, TAtlasWelcomeIds.SectionOf('atlas.welcome.HEADER'));
  Assert.AreEqual('', TAtlasWelcomeIds.SectionOf('Embarcadero.WelcomePagePlugin.OpenRecent'));
end;

{ TAtlasWelcomeLayoutTests }

function MockupSections: TArray<TAtlasWelcomeSection>;
begin
  Result := [Section(TAtlasWelcomeIds.cState, 10, TAtlasWelcomeColumn.Right),
    Section(TAtlasWelcomeIds.cContinue, 20, TAtlasWelcomeColumn.Left),
    Section(TAtlasWelcomeIds.cProjects, 30, TAtlasWelcomeColumn.Left),
    Section(TAtlasWelcomeIds.cHistory, 40, TAtlasWelcomeColumn.Left),
    Section(TAtlasWelcomeIds.cNews, 50, TAtlasWelcomeColumn.Right),
    Section(TAtlasWelcomeIds.cDiscover, 60, TAtlasWelcomeColumn.Right),
    Section(TAtlasWelcomeIds.cSetup, 70, TAtlasWelcomeColumn.Right)];
end;

procedure TAtlasWelcomeLayoutTests.AtlasLayoutMatchesMockup;
var
  mColumns: TArray<TArray<string>>;
begin
  mColumns := TAtlasWelcomeLayout.Atlas.Arrange(MockupSections, 2);
  Assert.AreEqual(2, Integer(Length(mColumns)));
  Assert.AreEqual('atlas.continue,atlas.projects,atlas.history', Joined(mColumns[0]));
  Assert.AreEqual('atlas.state,atlas.news,atlas.discover,atlas.setup', Joined(mColumns[1]));
end;

procedure TAtlasWelcomeLayoutTests.OneColumnStacksRightUnderLeft;
var
  mColumns: TArray<TArray<string>>;
begin
  mColumns := TAtlasWelcomeLayout.Atlas.Arrange(MockupSections, 1);
  Assert.AreEqual(1, Integer(Length(mColumns)));
  Assert.AreEqual('atlas.continue,atlas.projects,atlas.history,atlas.state,atlas.news,atlas.discover,atlas.setup',
    Joined(mColumns[0]));
  // Null Spalten gibt es nicht; mehr als drei auch nicht.
  Assert.AreEqual(1, Integer(Length(TAtlasWelcomeLayout.Atlas.Arrange(MockupSections, 0))));
  Assert.AreEqual(3, Integer(Length(TAtlasWelcomeLayout.Atlas.Arrange(MockupSections, 9))));
end;

procedure TAtlasWelcomeLayoutTests.UnknownSectionGoesToItsColumn;
var
  mColumns: TArray<TArray<string>>;
begin
  // Bereiche, die das Layout nicht kennt (fremde Plugins, spätere Versionen), nach ihrer Vorzugsspalte.
  mColumns := TAtlasWelcomeLayout.Atlas.Arrange(MockupSections + [Section('plugin.right', 80,
    TAtlasWelcomeColumn.Right), Section('plugin.left', 5, TAtlasWelcomeColumn.Left)], 2);
  Assert.AreEqual('atlas.continue,atlas.projects,atlas.history,plugin.left', Joined(mColumns[0]));
  Assert.AreEqual('atlas.state,atlas.news,atlas.discover,atlas.setup,plugin.right', Joined(mColumns[1]));
end;

procedure TAtlasWelcomeLayoutTests.HiddenSectionsLeaveNoGap;
var
  mColumns: TArray<TArray<string>>;
begin
  mColumns := TAtlasWelcomeLayout.Atlas.Arrange([Section(TAtlasWelcomeIds.cHistory, 40, TAtlasWelcomeColumn.Left),
    Section(TAtlasWelcomeIds.cSetup, 70, TAtlasWelcomeColumn.Right)], 2);
  Assert.AreEqual('atlas.history', Joined(mColumns[0]));
  Assert.AreEqual('atlas.setup', Joined(mColumns[1]));
  mColumns := TAtlasWelcomeLayout.Atlas.Arrange(nil, 2);
  Assert.AreEqual(2, Integer(Length(mColumns)));
  Assert.AreEqual(0, Integer(Length(mColumns[0])));
end;

procedure TAtlasWelcomeLayoutTests.JsonRoundTrip;
var
  mLayout, mLoaded: TAtlasWelcomeLayout;
begin
  mLayout := TAtlasWelcomeLayout.Atlas;
  mLayout.Name := 'Eigenes';
  mLayout.Columns := 3;
  mLayout.Slots := mLayout.Slots + [TAtlasWelcomeSlot.Create('plugin.extra', 2)];
  Assert.IsTrue(TAtlasWelcomeLayout.FromJson(mLayout.ToJson, mLoaded));
  Assert.IsTrue(TAtlasWelcomeLayout.Same(mLayout, mLoaded));
  Assert.AreEqual('Eigenes', mLoaded.Name);
  Assert.IsFalse(TAtlasWelcomeLayout.Same(TAtlasWelcomeLayout.Atlas, mLoaded));
end;

procedure TAtlasWelcomeLayoutTests.InvalidJsonGivesAtlas;
var
  mLoaded: TAtlasWelcomeLayout;
begin
  Assert.IsFalse(TAtlasWelcomeLayout.FromJson('kein JSON', mLoaded));
  Assert.IsTrue(TAtlasWelcomeLayout.Same(TAtlasWelcomeLayout.Atlas, mLoaded));
  Assert.IsFalse(TAtlasWelcomeLayout.FromJson('{"slots":[{"column":1}]}', mLoaded), 'Platz ohne Kennung');
  Assert.IsTrue(TAtlasWelcomeLayout.Same(TAtlasWelcomeLayout.Atlas, mLoaded));
  // Spalten außerhalb des Bereichs werden begrenzt.
  Assert.IsTrue(TAtlasWelcomeLayout.FromJson('{"columns":7,"slots":[{"id":"atlas.news","column":9}]}', mLoaded));
  Assert.AreEqual(TAtlasWelcomeLayout.cMaxColumns, mLoaded.Columns);
  Assert.AreEqual(TAtlasWelcomeLayout.cMaxColumns - 1, mLoaded.Slots[0].Column);
end;

procedure TAtlasWelcomeLayoutTests.MovedToTopLeadsFirstColumn;
var
  mMoved: TAtlasWelcomeLayout;
  mColumns: TArray<TArray<string>>;
  mSections: TArray<TAtlasWelcomeSection>;
begin
  // #756: Nach einem Update steht „Neu in Atlas“ oben links statt in der rechten Spalte.
  mMoved := TAtlasWelcomeLayout.Atlas.MovedToTop(TAtlasWelcomeIds.cNews);
  Assert.AreEqual(Integer(Length(TAtlasWelcomeLayout.Atlas.Slots)), Integer(Length(mMoved.Slots)));
  mSections := [Section(TAtlasWelcomeIds.cContinue, 10, TAtlasWelcomeColumn.Left),
    Section(TAtlasWelcomeIds.cState, 40, TAtlasWelcomeColumn.Right),
    Section(TAtlasWelcomeIds.cNews, 50, TAtlasWelcomeColumn.Right)];
  mColumns := mMoved.Arrange(mSections, 2);
  Assert.AreEqual('atlas.news,atlas.continue', Joined(mColumns[0]));
  Assert.AreEqual('atlas.state', Joined(mColumns[1]));
  mColumns := TAtlasWelcomeLayout.Atlas.Arrange(mSections, 2);
  Assert.AreEqual('atlas.continue', Joined(mColumns[0]));
  Assert.AreEqual('atlas.state,atlas.news', Joined(mColumns[1]));
  // Eine Spalte: ganz oben.
  mColumns := mMoved.Arrange(mSections, 1);
  Assert.AreEqual('atlas.news,atlas.continue,atlas.state', Joined(mColumns[0]));
  // Unbekannte Kennung kommt dazu, das Original bleibt unverändert.
  Assert.AreEqual(Integer(Length(TAtlasWelcomeLayout.Atlas.Slots)) + 1,
    Integer(Length(TAtlasWelcomeLayout.Atlas.MovedToTop('atlas.neu').Slots)));
end;

{ TAtlasWelcomeGreetingTests }

procedure TAtlasWelcomeGreetingTests.DayTimeByHour;
begin
  Assert.IsTrue(TAtlasWelcomeGreeting.DayTimeOf(0) = TAtlasDayTime.Night);
  Assert.IsTrue(TAtlasWelcomeGreeting.DayTimeOf(4) = TAtlasDayTime.Night);
  Assert.IsTrue(TAtlasWelcomeGreeting.DayTimeOf(5) = TAtlasDayTime.Morning);
  Assert.IsTrue(TAtlasWelcomeGreeting.DayTimeOf(10) = TAtlasDayTime.Morning);
  Assert.IsTrue(TAtlasWelcomeGreeting.DayTimeOf(11) = TAtlasDayTime.Day);
  Assert.IsTrue(TAtlasWelcomeGreeting.DayTimeOf(17) = TAtlasDayTime.Day);
  Assert.IsTrue(TAtlasWelcomeGreeting.DayTimeOf(18) = TAtlasDayTime.Evening);
  Assert.IsTrue(TAtlasWelcomeGreeting.DayTimeOf(23) = TAtlasDayTime.Evening);
end;

procedure TAtlasWelcomeGreetingTests.FirstNameFromDisplayName;
begin
  Assert.AreEqual('Marco', TAtlasWelcomeGreeting.FirstName('Marco Beispiel', 'mbeispiel'));
  Assert.AreEqual('Marco', TAtlasWelcomeGreeting.FirstName('  Marco  ', ''));
end;

procedure TAtlasWelcomeGreetingTests.FirstNameFromLastCommaFirst;
begin
  Assert.AreEqual('Marco', TAtlasWelcomeGreeting.FirstName('Beispiel, Marco', 'mbeispiel'));
  Assert.AreEqual('Anna', TAtlasWelcomeGreeting.FirstName('Muster-Frau, Anna Lena', ''));
end;

procedure TAtlasWelcomeGreetingTests.FirstNameFromUserName;
begin
  Assert.AreEqual('Marco', TAtlasWelcomeGreeting.FirstName('', 'marco.beispiel'));
  Assert.AreEqual('Marco', TAtlasWelcomeGreeting.FirstName('', 'FIRMA\marco_beispiel'));
  Assert.AreEqual('Marco', TAtlasWelcomeGreeting.FirstName('', 'marco@example.com'));
  Assert.AreEqual('Dev', TAtlasWelcomeGreeting.FirstName('', 'dev'));
  Assert.AreEqual('', TAtlasWelcomeGreeting.FirstName('', ''));
end;

{ TAtlasWelcomeBackupTests }

procedure TAtlasWelcomeBackupTests.RestoresEveryKindExactly;
var
  mRegistry: IAtlasRegistryAccess;
  mOriginal, mChanged, mRestored: TAtlasRegKey;
  mSnapshot: string;
  mMulti: TAtlasRegValue;
begin
  mRegistry := TAtlasMemoryRegistry.Create;
  mOriginal := Delphi12Export;
  try
    mOriginal.SetValue(TAtlasRegValue.Create('Pfad', TAtlasRegKind.ExpandText, '%APPDATA%\Atlas'));
    mMulti := TAtlasRegValue.Create('Liste', TAtlasRegKind.MultiText, '');
    mMulti.Lines := ['eins', '', 'drei'];
    mOriginal.SetValue(mMulti);
    mOriginal.SetValue(TAtlasRegValue.Create('Groß', TAtlasRegKind.Number64, '18446744073709551615'));
    mOriginal.SetValue(TAtlasRegValue.Create('Daten', TAtlasRegKind.Binary, '00FF10'));
    mOriginal.SetValue(TAtlasRegValue.Create('Leer', TAtlasRegKind.Binary, ''));
    mOriginal.SetValue(TAtlasRegValue.Create('Höchst', TAtlasRegKind.Number, '4294967295'));
    mRegistry.Replace(cWelcomePath, mOriginal);
    mSnapshot := TAtlasWelcomeBackup.Snapshot(mRegistry, cWelcomePath);
    // Atlas ändert das Layout …
    mChanged := TAtlasRegKey.Create('WelcomePage');
    try
      mChanged.SetValue(Number('Fremd', 1));
      mRegistry.Replace(cWelcomePath, mChanged);
    finally
      mChanged.Free;
    end;
    // … und die Sicherung bringt den alten Stand exakt zurück.
    Assert.IsTrue(TAtlasWelcomeBackup.Restore(mRegistry, mSnapshot));
    mRestored := mRegistry.Read(cWelcomePath);
    try
      Assert.IsTrue(mOriginal.SameAs(mRestored));
      Assert.IsTrue(mRestored.SameAs(mOriginal));
    finally
      mRestored.Free;
    end;
  finally
    mOriginal.Free;
  end;
end;

procedure TAtlasWelcomeBackupTests.RemovesKeyThatDidNotExist;
var
  mRegistry: IAtlasRegistryAccess;
  mSnapshot: string;
  mKey, mRead: TAtlasRegKey;
begin
  mRegistry := TAtlasMemoryRegistry.Create;
  mSnapshot := TAtlasWelcomeBackup.Snapshot(mRegistry, cWelcomePath);
  Assert.IsTrue(Pos('"existed":false', mSnapshot) > 0);
  mKey := Delphi12Export;
  try
    mRegistry.Replace(cWelcomePath, mKey);
  finally
    mKey.Free;
  end;
  Assert.IsTrue(TAtlasWelcomeBackup.Restore(mRegistry, mSnapshot));
  mRead := mRegistry.Read(cWelcomePath);
  Assert.IsNull(mRead, 'vorher gab es den Schlüssel nicht');
  mRead.Free;
end;

procedure TAtlasWelcomeBackupTests.MatchesDetectsChanges;
var
  mRegistry: IAtlasRegistryAccess;
  mSnapshot: string;
  mKey: TAtlasRegKey;
begin
  mRegistry := TAtlasMemoryRegistry.Create;
  mKey := Delphi12Export;
  try
    mRegistry.Replace(cWelcomePath, mKey);
    mSnapshot := TAtlasWelcomeBackup.Snapshot(mRegistry, cWelcomePath);
    Assert.IsTrue(TAtlasWelcomeBackup.Matches(mRegistry, mSnapshot));
    mKey.FindKey('Layout').SetValue(Number('RowsCount', 4));
    mRegistry.Replace(cWelcomePath, mKey);
    Assert.IsFalse(TAtlasWelcomeBackup.Matches(mRegistry, mSnapshot), 'Raster geändert');
    mRegistry.Replace(cWelcomePath, nil);
    Assert.IsFalse(TAtlasWelcomeBackup.Matches(mRegistry, mSnapshot), 'Schlüssel fehlt');
  finally
    mKey.Free;
  end;
  mSnapshot := TAtlasWelcomeBackup.Snapshot(mRegistry, cWelcomePath);
  Assert.IsTrue(TAtlasWelcomeBackup.Matches(mRegistry, mSnapshot), 'fehlt wie gesichert');
end;

procedure TAtlasWelcomeBackupTests.RejectsInvalidSnapshot;
var
  mRegistry: IAtlasRegistryAccess;
begin
  mRegistry := TAtlasMemoryRegistry.Create;
  Assert.IsFalse(TAtlasWelcomeBackup.Restore(mRegistry, ''));
  Assert.IsFalse(TAtlasWelcomeBackup.Restore(mRegistry, '{"existed":true}'), 'ohne Pfad');
  Assert.IsFalse(TAtlasWelcomeBackup.Restore(mRegistry, '{"path":"x","key":{"values":[{"kind":"neu"}]}}'));
  Assert.IsFalse(TAtlasWelcomeBackup.Matches(mRegistry, 'kaputt'));
end;

procedure TAtlasWelcomeBackupTests.KeyAndFileNames;
begin
  Assert.AreEqual('Software\Embarcadero\BDS\37.0\WelcomePage',
    TAtlasWelcomeBackup.WelcomeKey('\Software\Embarcadero\BDS\37.0\'));
  Assert.AreEqual('C:\Users\x\AppData\Local\Atlas' + PathDelim + 'welcomepage-layout-backup.json',
    TAtlasWelcomeBackup.BackupFile('C:\Users\x\AppData\Local\Atlas'));
end;

{ TAtlasHostLayoutTests }

procedure TAtlasHostLayoutTests.ReadsDelphi12Export;
var
  mKey: TAtlasRegKey;
  mLayout: TAtlasHostLayout;
begin
  mKey := Delphi12Export;
  try
    Assert.IsTrue(TAtlasHostLayout.Read(mKey, mLayout));
    Assert.AreEqual(2, mLayout.Rows);
    Assert.AreEqual(3, mLayout.Columns);
    Assert.AreEqual(3, Integer(Length(mLayout.Items)));
    Assert.AreEqual(1, mLayout.IndexOf('embarcadero.welcomepageplugin.openrecent'));
    Assert.AreEqual(2, mLayout.Items[2].Column);
    Assert.AreEqual(2, mLayout.Items[2].RowSpan);
    Assert.AreEqual('Embarcadero.WelcomePagePlugin.GetItPromoted,Embarcadero.WelcomePagePlugin.CreateNew',
      Joined(mLayout.Available));
  finally
    mKey.Free;
  end;
end;

procedure TAtlasHostLayoutTests.NoLayoutKeyMeansNoGrid;
var
  mKey: TAtlasRegKey;
  mLayout: TAtlasHostLayout;
begin
  mKey := TAtlasRegKey.Create('WelcomePage');
  try
    Assert.IsFalse(TAtlasHostLayout.Read(mKey, mLayout));
    Assert.IsFalse(TAtlasHostLayout.Read(nil, mLayout));
  finally
    mKey.Free;
  end;
end;

procedure TAtlasHostLayoutTests.WithoutAtlasRemovesBoardAndMovesUp;
var
  mLayout, mCleaned, mExport: TAtlasHostLayout;
  mIndex: Integer;
begin
  mLayout := ReadLayout(OldAtlasLayout);
  Assert.IsTrue(mLayout.ContainsAtlas(TAtlasWelcomeIds.cPluginPrefix));
  mCleaned := mLayout.WithoutAtlas(TAtlasWelcomeIds.cPluginPrefix);
  Assert.IsFalse(mCleaned.ContainsAtlas(TAtlasWelcomeIds.cPluginPrefix));
  // Wieder wie vor dem Atlas-Layout: drei Bereiche nebeneinander, zwei Zeilen hoch, oben.
  mExport := ReadLayout(Delphi12Export);
  Assert.AreEqual(mExport.Rows, mCleaned.Rows);
  Assert.AreEqual(mExport.Columns, mCleaned.Columns);
  Assert.AreEqual(Integer(Length(mExport.Items)), Integer(Length(mCleaned.Items)));
  for mIndex := 0 to High(mExport.Items) do
  begin
    Assert.AreEqual(mExport.Items[mIndex].PluginId, mCleaned.Items[mIndex].PluginId);
    Assert.AreEqual(mExport.Items[mIndex].Row, mCleaned.Items[mIndex].Row);
    Assert.AreEqual(mExport.Items[mIndex].Column, mCleaned.Items[mIndex].Column);
    Assert.AreEqual(mExport.Items[mIndex].RowSpan, mCleaned.Items[mIndex].RowSpan);
  end;
  Assert.AreEqual(Joined(mExport.Available), Joined(mCleaned.Available), 'ausgeblendete ohne Atlas');
end;

procedure TAtlasHostLayoutTests.WithoutAtlasDropsSingleAndHiddenSections;
var
  mLayout, mCleaned: TAtlasHostLayout;
begin
  mLayout := ReadLayout(Delphi12Export);
  Assert.IsFalse(mLayout.ContainsAtlas(TAtlasWelcomeIds.cPluginPrefix));
  // Einzelne Atlas-Bereiche, wie sie die IDE ohne Atlas-Layout selbst unten anordnete.
  mLayout.Rows := 3;
  mLayout.Items := mLayout.Items + [TAtlasHostItem.Create('Atlas.Welcome.state', 2, 0, 1, 1),
    TAtlasHostItem.Create('ATLAS.WELCOME.continue', 2, 1, 1, 2)];
  mLayout.Available := mLayout.Available + ['Atlas.Welcome.header'];
  Assert.IsTrue(mLayout.ContainsAtlas(TAtlasWelcomeIds.cPluginPrefix));
  mCleaned := mLayout.WithoutAtlas(TAtlasWelcomeIds.cPluginPrefix);
  Assert.AreEqual(2, mCleaned.Rows, 'die leere Zeile entfällt');
  Assert.AreEqual(3, Integer(Length(mCleaned.Items)));
  Assert.IsFalse(mCleaned.Contains('Atlas.Welcome.state'));
  Assert.IsFalse(mCleaned.Contains('Atlas.Welcome.continue'), 'Groß-/Kleinschreibung egal');
  Assert.AreEqual('Embarcadero.WelcomePagePlugin.GetItPromoted,Embarcadero.WelcomePagePlugin.CreateNew',
    Joined(mCleaned.Available));
end;

procedure TAtlasHostLayoutTests.WithoutAtlasClosesGapInTheMiddle;
var
  mLayout, mCleaned: TAtlasHostLayout;
begin
  mLayout.Rows := 4;
  mLayout.Columns := 2;
  mLayout.Items := [TAtlasHostItem.Create('A', 0, 0, 1, 2), TAtlasHostItem.Create('Atlas.Welcome.board', 1, 0, 2, 2),
    TAtlasHostItem.Create('B', 3, 1, 1, 1), TAtlasHostItem.Create('C', 3, 0, 1, 1)];
  mLayout.Available := nil;
  mCleaned := mLayout.WithoutAtlas(TAtlasWelcomeIds.cPluginPrefix);
  Assert.AreEqual(2, mCleaned.Rows);
  Assert.AreEqual(0, mCleaned.Items[mCleaned.IndexOf('A')].Row);
  Assert.AreEqual(1, mCleaned.Items[mCleaned.IndexOf('B')].Row, 'rückt über die Lücke nach oben');
  Assert.AreEqual(1, mCleaned.Items[mCleaned.IndexOf('C')].Row);
  Assert.AreEqual(1, mCleaned.Items[mCleaned.IndexOf('B')].Column, 'Spalte bleibt');
  // Ohne Atlas ändert sich nichts.
  mLayout := mCleaned.WithoutAtlas(TAtlasWelcomeIds.cPluginPrefix);
  Assert.AreEqual(2, mLayout.Rows);
  Assert.AreEqual(3, Integer(Length(mLayout.Items)));
end;

procedure TAtlasHostLayoutTests.WriteKeepsBackgroundValues;
var
  mKey: TAtlasRegKey;
  mLayout, mCleaned, mRead: TAtlasHostLayout;
  mValue: TAtlasRegValue;
begin
  mKey := OldAtlasLayout;
  try
    TAtlasHostLayout.Read(mKey, mLayout);
    mCleaned := mLayout.WithoutAtlas(TAtlasWelcomeIds.cPluginPrefix);
    mCleaned.WriteTo(mKey);
    Assert.IsTrue(mKey.FindValue('Background_Dark', mValue), 'Hintergrund bleibt');
    Assert.IsNotNull(mKey.FindKey('Layout').FindKey('Item 2'));
    Assert.IsNull(mKey.FindKey('Layout').FindKey('Item 3'), 'alte Einträge entfallen');
    Assert.IsTrue(TAtlasHostLayout.Read(mKey, mRead));
    Assert.AreEqual(mCleaned.Rows, mRead.Rows);
    Assert.AreEqual(Integer(Length(mCleaned.Items)), Integer(Length(mRead.Items)));
    Assert.AreEqual(Joined(mCleaned.Available), Joined(mRead.Available));
  finally
    mKey.Free;
  end;
end;

procedure TAtlasHostLayoutTests.WriteWithoutSectionsDropsGrid;
var
  mKey: TAtlasRegKey;
  mLayout, mCleaned: TAtlasHostLayout;
  mValue: TAtlasRegValue;
begin
  mKey := TAtlasRegKey.Create('WelcomePage');
  try
    mKey.SetValue(TAtlasRegValue.Create('Background_Light', TAtlasRegKind.Text, 'Tag.jpg'));
    mLayout.Rows := 2;
    mLayout.Columns := 1;
    mLayout.Items := [TAtlasHostItem.Create('Atlas.Welcome.board', 0, 0, 2, 1)];
    mLayout.Available := nil;
    mLayout.WriteTo(mKey);
    mCleaned := mLayout.WithoutAtlas(TAtlasWelcomeIds.cPluginPrefix);
    Assert.AreEqual(0, Integer(Length(mCleaned.Items)));
    mCleaned.WriteTo(mKey);
    Assert.IsNull(mKey.FindKey('Layout'), 'ohne Raster zeigt die IDE ihre Vorgabe');
    Assert.IsFalse(TAtlasHostLayout.Read(mKey, mLayout));
    Assert.IsTrue(mKey.FindValue('Background_Light', mValue));
  finally
    mKey.Free;
  end;
end;

procedure TAtlasHostLayoutTests.IdeDefaultMatchesDelphi12Export;
var
  mLayout, mIdeLayout: TAtlasHostLayout;
begin
  // Die Vorgabe der IDE gleicht dem frischen Export.
  mLayout := ReadLayout(Delphi12Export);
  mIdeLayout := TAtlasHostLayout.IdeDefault;
  Assert.AreEqual(mLayout.Rows, mIdeLayout.Rows);
  Assert.AreEqual(mLayout.Columns, mIdeLayout.Columns);
  Assert.AreEqual(Integer(Length(mLayout.Items)), Integer(Length(mIdeLayout.Items)));
  Assert.AreEqual(Joined(mLayout.Available), Joined(mIdeLayout.Available));
end;

procedure TAtlasHostLayoutTests.AtlasOnTopShiftsOtherSections;
var
  mLayout, mPlaced: TAtlasHostLayout;
begin
  mLayout := ReadLayout(Delphi12Export);
  mPlaced := mLayout.WithAtlasOnTop('Atlas.Welcome.board', TAtlasWelcomeIds.cPluginPrefix);
  Assert.AreEqual(2 + TAtlasHostLayout.cBoardRows, mPlaced.Rows);
  Assert.AreEqual(3, mPlaced.Columns);
  Assert.AreEqual(4, Integer(Length(mPlaced.Items)));
  Assert.AreEqual('Atlas.Welcome.board', mPlaced.Items[0].PluginId);
  Assert.AreEqual(0, mPlaced.Items[0].Row);
  Assert.AreEqual(0, mPlaced.Items[0].Column);
  Assert.AreEqual(TAtlasHostLayout.cBoardRows, mPlaced.Items[0].RowSpan);
  Assert.AreEqual(3, mPlaced.Items[0].ColumnSpan, 'über alle Spalten');
  Assert.AreEqual(TAtlasHostLayout.cBoardRows, mPlaced.Items[mPlaced.IndexOf('Embarcadero.WelcomePagePlugin.Learn')].Row);
  Assert.AreEqual(2, mPlaced.Items[mPlaced.IndexOf('Embarcadero.WelcomePagePlugin.Learn')].Column);
  Assert.IsTrue(mPlaced.HasAtlasOnTop('Atlas.Welcome.board', TAtlasWelcomeIds.cPluginPrefix));
  Assert.IsFalse(mLayout.HasAtlasOnTop('Atlas.Welcome.board', TAtlasWelcomeIds.cPluginPrefix));
  // Zweimal anwenden ändert nichts mehr an der Lage.
  mPlaced := mPlaced.WithAtlasOnTop('Atlas.Welcome.board', TAtlasWelcomeIds.cPluginPrefix);
  Assert.AreEqual(4, Integer(Length(mPlaced.Items)));
end;

procedure TAtlasHostLayoutTests.AtlasOnTopDropsSingleAtlasSections;
var
  mLayout, mPlaced: TAtlasHostLayout;
begin
  mLayout := TAtlasHostLayout.IdeDefault;
  mLayout.Items := mLayout.Items + [TAtlasHostItem.Create('Atlas.Welcome.state', 2, 0, 1, 1)];
  mLayout.Available := mLayout.Available + ['Atlas.Welcome.news', 'Atlas.Welcome.board'];
  mPlaced := mLayout.WithAtlasOnTop('Atlas.Welcome.board', TAtlasWelcomeIds.cPluginPrefix);
  Assert.IsFalse(mPlaced.Contains('Atlas.Welcome.state'));
  Assert.AreEqual('Embarcadero.WelcomePagePlugin.GetItPromoted,Embarcadero.WelcomePagePlugin.CreateNew',
    Joined(mPlaced.Available), 'Atlas weder ausgeblendet noch einzeln');
end;

procedure TAtlasHostLayoutTests.DetectsMovedBoard;
var
  mPlaced: TAtlasHostLayout;
  mItem: TAtlasHostItem;
begin
  mPlaced := TAtlasHostLayout.IdeDefault.WithAtlasOnTop('Atlas.Welcome.board', TAtlasWelcomeIds.cPluginPrefix);
  mItem := mPlaced.Items[0];
  mItem.Row := 2;
  mPlaced.Items[0] := mItem;
  Assert.IsFalse(mPlaced.HasAtlasOnTop('Atlas.Welcome.board', TAtlasWelcomeIds.cPluginPrefix), 'verschoben');
  mPlaced := TAtlasHostLayout.IdeDefault.WithAtlasOnTop('Atlas.Welcome.board', TAtlasWelcomeIds.cPluginPrefix);
  mPlaced.Available := mPlaced.Available + ['Atlas.Welcome.board'];
  Assert.IsFalse(mPlaced.HasAtlasOnTop('Atlas.Welcome.board', TAtlasWelcomeIds.cPluginPrefix), 'ausgeblendet');
end;

procedure TAtlasHostLayoutTests.WithoutAtlasUndoesAtlasOnTop;
var
  mLayout, mPlaced, mBack: TAtlasHostLayout;
  mIndex: Integer;
begin
  // Abschalten (welcomePage.ideWelcomePage, #761) ohne Sicherung: wieder das Raster von vorher.
  mLayout := TAtlasHostLayout.IdeDefault;
  mPlaced := mLayout.WithAtlasOnTop('Atlas.Welcome.board', TAtlasWelcomeIds.cPluginPrefix);
  mBack := mPlaced.WithoutAtlas(TAtlasWelcomeIds.cPluginPrefix);
  Assert.AreEqual(mLayout.Rows, mBack.Rows);
  Assert.AreEqual(mLayout.Columns, mBack.Columns);
  Assert.AreEqual(Integer(Length(mLayout.Items)), Integer(Length(mBack.Items)));
  for mIndex := 0 to High(mLayout.Items) do
  begin
    Assert.AreEqual(mLayout.Items[mIndex].PluginId, mBack.Items[mIndex].PluginId);
    Assert.AreEqual(mLayout.Items[mIndex].Row, mBack.Items[mIndex].Row);
    Assert.AreEqual(mLayout.Items[mIndex].Column, mBack.Items[mIndex].Column);
  end;
  Assert.AreEqual(Joined(mLayout.Available), Joined(mBack.Available));
end;

{ TAtlasIdePageStepsTests }

function Steps(const ASteps: TArray<TAtlasIdePageStep>): string;
var
  mStep: TAtlasIdePageStep;
begin
  Result := '';
  for mStep in ASteps do
  begin
    Result := Result + IntToStr(Ord(mStep)) + ';';
  end;
end;

function Expected(const ASteps: array of TAtlasIdePageStep): string;
var
  mStep: TAtlasIdePageStep;
begin
  Result := '';
  for mStep in ASteps do
  begin
    Result := Result + IntToStr(Ord(mStep)) + ';';
  end;
end;

procedure TAtlasIdePageStepsTests.FirstSyncDoesNothing;
begin
  // Beim Start gilt, was die IDE aus der Registry liest; aufgeräumt hat schon der Konstruktor.
  Assert.AreEqual('', Steps(TAtlasIdePageSteps.After(False, False, True, '', 'atlas')));
  Assert.AreEqual('', Steps(TAtlasIdePageSteps.After(False, False, False, '', 'off')));
end;

procedure TAtlasIdePageStepsTests.SwitchingOffRetires;
begin
  Assert.AreEqual(Expected([TAtlasIdePageStep.Retire]),
    Steps(TAtlasIdePageSteps.After(True, True, False, 'off', 'off')));
  Assert.AreEqual(Expected([TAtlasIdePageStep.Retire]),
    Steps(TAtlasIdePageSteps.After(True, True, False, 'atlas', 'atlas')), 'Sicherung des Atlas-Layouts zurück');
  Assert.AreEqual('', Steps(TAtlasIdePageSteps.After(True, False, False, 'off', 'atlas')), 'war schon aus');
end;

procedure TAtlasIdePageStepsTests.SwitchingOnClearsPendingAndPlacesBoard;
begin
  Assert.AreEqual(Expected([TAtlasIdePageStep.ClearPending]),
    Steps(TAtlasIdePageSteps.After(True, False, True, 'off', 'off')));
  Assert.AreEqual(Expected([TAtlasIdePageStep.ClearPending, TAtlasIdePageStep.PlaceBoard]),
    Steps(TAtlasIdePageSteps.After(True, False, True, 'atlas', 'ATLAS')));
end;

procedure TAtlasIdePageStepsTests.LayoutChangeOnlyWhileShown;
begin
  Assert.AreEqual(Expected([TAtlasIdePageStep.PlaceBoard]),
    Steps(TAtlasIdePageSteps.After(True, True, True, 'off', 'atlas')));
  Assert.AreEqual(Expected([TAtlasIdePageStep.Unplace]),
    Steps(TAtlasIdePageSteps.After(True, True, True, 'atlas', 'off')));
  Assert.AreEqual('', Steps(TAtlasIdePageSteps.After(True, True, True, 'atlas', 'atlas')), 'unverändert');
end;

{ TAtlasWelcomeRetireTests }

procedure TAtlasWelcomeRetireTests.RestoresBackup;
var
  mRegistry: IAtlasRegistryAccess;
  mKey, mRead: TAtlasRegKey;
  mBackup, mSnapshot: string;
begin
  mRegistry := TAtlasMemoryRegistry.Create;
  mKey := Delphi12Export;
  try
    mRegistry.Replace(cWelcomePath, mKey);
  finally
    mKey.Free;
  end;
  mBackup := TAtlasWelcomeBackup.Snapshot(mRegistry, cWelcomePath);
  mKey := OldAtlasLayout;
  try
    mRegistry.Replace(cWelcomePath, mKey);
  finally
    mKey.Free;
  end;
  Assert.AreEqual(Ord(TAtlasRetireResult.Restored),
    Ord(TAtlasWelcomeRetire.Run(mRegistry, cWelcomePath, mBackup, TAtlasWelcomeIds.cPluginPrefix, mSnapshot)));
  Assert.AreEqual(mBackup, mSnapshot, 'die Sicherung ist der gewünschte Stand');
  mRead := mRegistry.Read(cWelcomePath);
  mKey := Delphi12Export;
  try
    Assert.IsTrue(mKey.SameAs(mRead), 'exakt wie vor dem Atlas-Layout');
  finally
    mKey.Free;
    mRead.Free;
  end;
end;

procedure TAtlasWelcomeRetireTests.RemovesAtlasWithoutBackup;
var
  mRegistry: IAtlasRegistryAccess;
  mKey: TAtlasRegKey;
  mSnapshot: string;
  mLayout: TAtlasHostLayout;
begin
  mRegistry := TAtlasMemoryRegistry.Create;
  mKey := OldAtlasLayout;
  try
    mRegistry.Replace(cWelcomePath, mKey);
  finally
    mKey.Free;
  end;
  Assert.AreEqual(Ord(TAtlasRetireResult.Removed),
    Ord(TAtlasWelcomeRetire.Run(mRegistry, cWelcomePath, '', TAtlasWelcomeIds.cPluginPrefix, mSnapshot)));
  Assert.IsTrue(TAtlasWelcomeBackup.Matches(mRegistry, mSnapshot), 'Marke = geschriebener Stand');
  mLayout := ReadLayout(mRegistry.Read(cWelcomePath));
  Assert.IsFalse(mLayout.ContainsAtlas(TAtlasWelcomeIds.cPluginPrefix));
  Assert.AreEqual(2, mLayout.Rows);
  // Ein zweiter Start findet nichts mehr.
  Assert.AreEqual(Ord(TAtlasRetireResult.Nothing),
    Ord(TAtlasWelcomeRetire.Run(mRegistry, cWelcomePath, '', TAtlasWelcomeIds.cPluginPrefix, mSnapshot)));
  Assert.AreEqual('', mSnapshot);
end;

procedure TAtlasWelcomeRetireTests.BrokenBackupFallsBackToRemoving;
var
  mRegistry: IAtlasRegistryAccess;
  mKey: TAtlasRegKey;
  mSnapshot: string;
begin
  mRegistry := TAtlasMemoryRegistry.Create;
  mKey := OldAtlasLayout;
  try
    mRegistry.Replace(cWelcomePath, mKey);
  finally
    mKey.Free;
  end;
  Assert.AreEqual(Ord(TAtlasRetireResult.Removed),
    Ord(TAtlasWelcomeRetire.Run(mRegistry, cWelcomePath, 'kaputt', TAtlasWelcomeIds.cPluginPrefix, mSnapshot)));
  Assert.IsFalse(ReadLayout(mRegistry.Read(cWelcomePath)).ContainsAtlas(TAtlasWelcomeIds.cPluginPrefix));
end;

procedure TAtlasWelcomeRetireTests.CleanLayoutStaysUntouched;
var
  mRegistry: IAtlasRegistryAccess;
  mKey, mRead: TAtlasRegKey;
  mSnapshot: string;
begin
  mRegistry := TAtlasMemoryRegistry.Create;
  Assert.AreEqual(Ord(TAtlasRetireResult.Nothing),
    Ord(TAtlasWelcomeRetire.Run(mRegistry, cWelcomePath, '', TAtlasWelcomeIds.cPluginPrefix, mSnapshot)), 'kein Schlüssel');
  mRead := mRegistry.Read(cWelcomePath);
  Assert.IsNull(mRead, 'legt nichts an');
  mRead.Free;
  mKey := Delphi12Export;
  try
    mRegistry.Replace(cWelcomePath, mKey);
    Assert.AreEqual(Ord(TAtlasRetireResult.Nothing),
      Ord(TAtlasWelcomeRetire.Run(mRegistry, cWelcomePath, '', TAtlasWelcomeIds.cPluginPrefix, mSnapshot)));
    Assert.AreEqual('', mSnapshot);
    mRead := mRegistry.Read(cWelcomePath);
    try
      Assert.IsTrue(mKey.SameAs(mRead));
    finally
      mRead.Free;
    end;
  finally
    mKey.Free;
  end;
end;

{ TAtlasWelcomeSettingsTests }

type
  TMemoryStore = class(TInterfacedObject, IAtlasSettingsStore)
  private
    FValues: TDictionary<string, string>;
  public
    constructor Create;
    destructor Destroy; override;
    function ReadInteger(const AName: string; ADefault: Integer): Integer;
    procedure WriteInteger(const AName: string; AValue: Integer);
    function ReadString(const AName, ADefault: string): string;
    procedure WriteString(const AName, AValue: string);
  end;

constructor TMemoryStore.Create;
begin
  inherited Create;
  FValues := TDictionary<string, string>.Create;
end;

destructor TMemoryStore.Destroy;
begin
  FValues.Free;
  inherited;
end;

function TMemoryStore.ReadInteger(const AName: string; ADefault: Integer): Integer;
var
  mText: string;
begin
  Result := ADefault;
  if FValues.TryGetValue(AName, mText) then
  begin
    Result := StrToIntDef(mText, ADefault);
  end;
end;

procedure TMemoryStore.WriteInteger(const AName: string; AValue: Integer);
begin
  FValues.AddOrSetValue(AName, IntToStr(AValue));
end;

function TMemoryStore.ReadString(const AName, ADefault: string): string;
begin
  if not FValues.TryGetValue(AName, Result) then
  begin
    Result := ADefault;
  end;
end;

procedure TMemoryStore.WriteString(const AName, AValue: string);
begin
  FValues.AddOrSetValue(AName, AValue);
end;

procedure TAtlasWelcomeSettingsTests.DefaultsOpenWindowOnlyOnRequest;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.WelcomePage);
  // #1114: „Atlas-Start“ öffnet nur auf Wunsch (Menü, Palette, Desktop).
  Assert.IsFalse(mSettings.WelcomePageOpenOnStart);
  Assert.IsTrue(mSettings.WelcomePageHeader);
  Assert.IsTrue(mSettings.WelcomePageGreeting);
  Assert.AreEqual('afterUpdate', mSettings.WelcomePageWhatsNew);
  Assert.AreEqual('', mSettings.WhatsNewSeen, 'vor dem ersten Start nichts gesehen');
  // #754: Zustandskachel an, auch bei allem grün.
  Assert.IsTrue(mSettings.WelcomePageStatusTile);
  Assert.IsFalse(mSettings.WelcomePageStatusTileOnlyProblems);
  // #757: Karte „Atlas entdecken“ an, Nutzung lokal zählen an.
  Assert.IsTrue(mSettings.WelcomePageDiscover);
  Assert.IsTrue(mSettings.TipsUsageTracking);
  // #766: Bereich „Hilfe und Rückmeldung“ an, Issue-Seite des Repositorys, Desktop.
  Assert.IsTrue(mSettings.WelcomePageHelp);
  Assert.AreEqual(TAtlasPluginSettings.cDefaultHelpReportUrl, mSettings.WelcomePageHelpReportUrl);
  Assert.AreEqual('https://github.com/xKnockOut/Atlas-IDE-Expert/issues/new', mSettings.WelcomePageHelpReportUrl);
  Assert.AreEqual('', mSettings.WelcomePageHelpReportFolder, 'leer = Desktop');
  // #759: Einrichtungskarte und „Neu mit Atlas“ an.
  Assert.IsTrue(mSettings.WelcomePageProjectSetup);
  Assert.IsTrue(mSettings.WelcomePageNewFromTemplate);
  // #755: Weiterarbeiten an mit 5 Arbeitsständen, eingehende Commits an, fetch aus, „Gemerkt“ an.
  Assert.IsTrue(mSettings.WelcomePageContinue);
  Assert.AreEqual(5, mSettings.WelcomePageContinueCount);
  Assert.IsTrue(mSettings.WelcomePageContinueIncoming);
  Assert.IsFalse(mSettings.WelcomePageContinueFetch, 'kein Netzzugriff ohne Zustimmung');
  Assert.IsTrue(mSettings.WelcomePageSaved);
  // #767: frei anordnen an, zwei Spalten, Vorgabe-Layout „Standard“ (leer gespeichert).
  Assert.IsTrue(mSettings.WelcomePageCustomLayout);
  Assert.AreEqual(2, mSettings.WelcomePageColumns);
  Assert.AreEqual('', mSettings.WelcomePageLayouts);
  Assert.AreEqual('Standard', mSettings.WelcomePageActiveLayout);
end;

procedure TAtlasWelcomeSettingsTests.DefaultsShowSectionsOnIdePage;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  // #761: wieder auf der Willkommensseite der IDE, das Layout der IDE bleibt, bis man es anwendet.
  Assert.IsTrue(mSettings.WelcomePageIdePage);
  Assert.AreEqual('off', mSettings.WelcomePageLayout);
  // Das Fenster bleibt unabhängig davon (#1114).
  Assert.IsFalse(mSettings.WelcomePageOpenOnStart);
  Assert.IsTrue(mSettings.WelcomePageOpenWhenNoProject);
end;

procedure TAtlasWelcomeSettingsTests.NormalizeMapsUnknownValues;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.WelcomePageLayout := ' Atlas ';
  mSettings.Normalize;
  Assert.AreEqual('atlas', mSettings.WelcomePageLayout);
  mSettings.WelcomePageLayout := 'eigen';
  mSettings.Normalize;
  Assert.AreEqual('off', mSettings.WelcomePageLayout);
  mSettings.WelcomePageWhatsNew := ' ALWAYS ';
  mSettings.WhatsNewSeen := ' 1.1.0 ';
  mSettings.Normalize;
  Assert.AreEqual('always', mSettings.WelcomePageWhatsNew);
  Assert.AreEqual('1.1.0', mSettings.WhatsNewSeen);
  mSettings.WelcomePageWhatsNew := 'manchmal';
  mSettings.Normalize;
  Assert.AreEqual('afterUpdate', mSettings.WelcomePageWhatsNew);
  mSettings.WelcomePageWhatsNew := 'Off';
  mSettings.Normalize;
  Assert.AreEqual('off', mSettings.WelcomePageWhatsNew);
  // #766: Ziel der Issue-Seite nur als Webadresse, sonst die Vorgabe; Leerzeichen weg.
  mSettings.WelcomePageHelpReportUrl := '  https://example.org/issues/new  ';
  mSettings.WelcomePageHelpReportFolder := '  D:\Diagnose  ';
  mSettings.Normalize;
  Assert.AreEqual('https://example.org/issues/new', mSettings.WelcomePageHelpReportUrl);
  Assert.AreEqual('D:\Diagnose', mSettings.WelcomePageHelpReportFolder);
  mSettings.WelcomePageHelpReportUrl := 'http://intern/issues';
  mSettings.Normalize;
  Assert.AreEqual('http://intern/issues', mSettings.WelcomePageHelpReportUrl);
  mSettings.WelcomePageHelpReportUrl := 'file:///C:/Windows/System32/cmd.exe';
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cDefaultHelpReportUrl, mSettings.WelcomePageHelpReportUrl, 'keine Datei');
  mSettings.WelcomePageHelpReportUrl := 'cmd.exe';
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cDefaultHelpReportUrl, mSettings.WelcomePageHelpReportUrl, 'kein Programm');
  mSettings.WelcomePageHelpReportUrl := '';
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cDefaultHelpReportUrl, mSettings.WelcomePageHelpReportUrl, 'leer = Vorgabe');
  // #755: Anzahl der Arbeitsstände 1–20.
  mSettings.WelcomePageContinueCount := 0;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinContinueCount, mSettings.WelcomePageContinueCount);
  mSettings.WelcomePageContinueCount := 99;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxContinueCount, mSettings.WelcomePageContinueCount);
  // #767: Spalten 1–3, leeres aktives Layout = „Standard“.
  mSettings.WelcomePageColumns := 0;
  mSettings.WelcomePageActiveLayout := '  ';
  mSettings.Normalize;
  Assert.AreEqual(1, mSettings.WelcomePageColumns);
  Assert.AreEqual('Standard', mSettings.WelcomePageActiveLayout);
  mSettings.WelcomePageColumns := 9;
  mSettings.WelcomePageActiveLayout := ' Arbeit ';
  mSettings.Normalize;
  Assert.AreEqual(3, mSettings.WelcomePageColumns);
  Assert.AreEqual('Arbeit', mSettings.WelcomePageActiveLayout);
end;

/// <summary>Einstellungen der Willkommensseite, alle abweichend von der Vorgabe.</summary>
function ChangedWelcomeSettings: TAtlasPluginSettings;
begin
  Result := TAtlasPluginSettings.Defaults;
  Result.WelcomePage := False;
  Result.WelcomePageOpenOnStart := True;
  Result.WelcomePageIdePage := False;
  Result.WelcomePageLayout := 'atlas';
  Result.WelcomePageHeader := False;
  Result.WelcomePageGreeting := False;
  Result.WelcomePageWhatsNew := 'always';
  Result.WhatsNewSeen := '1.1.0';
  Result.WelcomePageContinue := False;
  Result.WelcomePageContinueCount := 7;
  Result.WelcomePageContinueIncoming := False;
  Result.WelcomePageContinueFetch := True;
  Result.WelcomePageSaved := False;
  Result.WelcomePageProjectStatus := False;
  Result.WelcomePageMaxProjects := 12;
  Result.WelcomePageRefreshVcs := False;
  Result.WelcomePageUnsaved := False;
  Result.WelcomePageUnsavedMinAgeHours := 3;
  Result.WelcomePageUnsavedWarnHours := 10;
  Result.WelcomePageUnsavedAlertHours := 20;
  Result.WelcomePageUnsavedHideWhenClean := True;
  Result.WelcomePageStatusTile := False;
  Result.WelcomePageStatusTileOnlyProblems := True;
  Result.WelcomePageDiscover := False;
  Result.TipsUsageTracking := False;
  Result.WelcomePageHelp := False;
  Result.WelcomePageHelpReportUrl := 'https://example.org/issues/new';
  Result.WelcomePageHelpReportFolder := 'D:\Diagnose';
  Result.WelcomePageProjectSetup := False;
  Result.WelcomePageNewFromTemplate := False;
  Result.WelcomePageCustomLayout := False;
  Result.WelcomePageColumns := 3;
  Result.WelcomePageLayouts := '[{"name":"Arbeit","columns":3,"slots":[]}]';
  Result.WelcomePageActiveLayout := 'Arbeit';
end;

/// <summary>Die geänderten Einstellungen stehen unter ihren Registry-Namen im Speicher.</summary>
procedure AssertWelcomeStored(const AStore: IAtlasSettingsStore);
begin
  Assert.AreEqual(0, AStore.ReadInteger('WelcomePageCustomLayout', 1), 'Registry-Name (#767)');
  Assert.AreEqual(3, AStore.ReadInteger('WelcomePageColumns', 0));
  Assert.AreEqual('[{"name":"Arbeit","columns":3,"slots":[]}]', AStore.ReadString('WelcomePageLayouts', ''));
  Assert.AreEqual('Arbeit', AStore.ReadString('WelcomePageActiveLayout', ''));
  Assert.AreEqual(0, AStore.ReadInteger('WelcomePageHelp', 1), 'Registry-Name (#766)');
  Assert.AreEqual('https://example.org/issues/new', AStore.ReadString('WelcomePageHelpReportUrl', ''));
  Assert.AreEqual('D:\Diagnose', AStore.ReadString('WelcomePageHelpReportFolder', ''));
  Assert.AreEqual(0, AStore.ReadInteger('WelcomePageProjectSetup', 1), 'Registry-Name (#759)');
  Assert.AreEqual(0, AStore.ReadInteger('WelcomePageNewFromTemplate', 1), 'Registry-Name (#759)');
  Assert.AreEqual(0, AStore.ReadInteger('WelcomePageDiscover', 1), 'Registry-Name (#757)');
  Assert.AreEqual(0, AStore.ReadInteger('TipsUsageTracking', 1), 'Registry-Name (#757)');
  Assert.AreEqual(0, AStore.ReadInteger('WelcomePageStatusTile', 1), 'Registry-Name (#754)');
  Assert.AreEqual(1, AStore.ReadInteger('WelcomePageStatusTileOnlyProblems', 0));
  Assert.AreEqual(0, AStore.ReadInteger('WelcomePageUnsaved', 1), 'Registry-Name (#762)');
  Assert.AreEqual(3, AStore.ReadInteger('WelcomePageUnsavedMinAgeHours', 0));
  Assert.AreEqual(10, AStore.ReadInteger('WelcomePageUnsavedWarnHours', 0));
  Assert.AreEqual(20, AStore.ReadInteger('WelcomePageUnsavedAlertHours', 0));
  Assert.AreEqual(1, AStore.ReadInteger('WelcomePageUnsavedHideWhenClean', 0));
  Assert.AreEqual(0, AStore.ReadInteger('WelcomePageContinue', 1), 'Registry-Name (#755)');
  Assert.AreEqual(7, AStore.ReadInteger('WelcomePageContinueCount', 0));
  Assert.AreEqual(0, AStore.ReadInteger('WelcomePageContinueIncoming', 1));
  Assert.AreEqual(1, AStore.ReadInteger('WelcomePageContinueFetch', 0));
  Assert.AreEqual(0, AStore.ReadInteger('WelcomePageSaved', 1));
  Assert.AreEqual(0, AStore.ReadInteger('WelcomePageProjectStatus', 1), 'Registry-Name (#592)');
  Assert.AreEqual(12, AStore.ReadInteger('WelcomePageMaxProjects', 0));
  Assert.AreEqual(0, AStore.ReadInteger('WelcomePageRefreshVcs', 1));
  Assert.AreEqual(0, AStore.ReadInteger('WelcomePage', 1), 'Registry-Name');
  Assert.AreEqual(1, AStore.ReadInteger('WelcomePageOpenOnStart', 0), 'Registry-Name (#1114)');
  Assert.AreEqual(0, AStore.ReadInteger('WelcomePageIdePage', 1), 'Registry-Name (#761)');
  Assert.AreEqual('atlas', AStore.ReadString('WelcomePageLayout', ''));
  Assert.AreEqual('always', AStore.ReadString('WelcomePageWhatsNew', ''));
  Assert.AreEqual('1.1.0', AStore.ReadString('WhatsNewSeen', ''));
end;

/// <summary>Geladen kommen alle geänderten Einstellungen wieder.</summary>
procedure AssertWelcomeLoaded(const ALoaded: TAtlasPluginSettings);
begin
  Assert.IsFalse(ALoaded.WelcomePage);
  Assert.IsTrue(ALoaded.WelcomePageOpenOnStart);
  Assert.IsFalse(ALoaded.WelcomePageIdePage);
  Assert.AreEqual('atlas', ALoaded.WelcomePageLayout);
  Assert.IsFalse(ALoaded.WelcomePageHeader);
  Assert.IsFalse(ALoaded.WelcomePageGreeting);
  Assert.AreEqual('always', ALoaded.WelcomePageWhatsNew);
  Assert.AreEqual('1.1.0', ALoaded.WhatsNewSeen);
  Assert.IsFalse(ALoaded.WelcomePageContinue);
  Assert.AreEqual(7, ALoaded.WelcomePageContinueCount);
  Assert.IsFalse(ALoaded.WelcomePageContinueIncoming);
  Assert.IsTrue(ALoaded.WelcomePageContinueFetch);
  Assert.IsFalse(ALoaded.WelcomePageSaved);
  Assert.IsFalse(ALoaded.WelcomePageCustomLayout);
  Assert.AreEqual(3, ALoaded.WelcomePageColumns);
  Assert.AreEqual('[{"name":"Arbeit","columns":3,"slots":[]}]', ALoaded.WelcomePageLayouts);
  Assert.AreEqual('Arbeit', ALoaded.WelcomePageActiveLayout);
  Assert.IsFalse(ALoaded.WelcomePageProjectStatus);
  Assert.AreEqual(12, ALoaded.WelcomePageMaxProjects);
  Assert.IsFalse(ALoaded.WelcomePageRefreshVcs);
  Assert.IsFalse(ALoaded.WelcomePageUnsaved);
  Assert.AreEqual(3, ALoaded.WelcomePageUnsavedMinAgeHours);
  Assert.AreEqual(10, ALoaded.WelcomePageUnsavedWarnHours);
  Assert.AreEqual(20, ALoaded.WelcomePageUnsavedAlertHours);
  Assert.IsTrue(ALoaded.WelcomePageUnsavedHideWhenClean);
  Assert.IsFalse(ALoaded.WelcomePageStatusTile);
  Assert.IsTrue(ALoaded.WelcomePageStatusTileOnlyProblems);
  Assert.IsFalse(ALoaded.WelcomePageDiscover);
  Assert.IsFalse(ALoaded.TipsUsageTracking);
  Assert.IsFalse(ALoaded.WelcomePageHelp);
  Assert.AreEqual('https://example.org/issues/new', ALoaded.WelcomePageHelpReportUrl);
  Assert.AreEqual('D:\Diagnose', ALoaded.WelcomePageHelpReportFolder);
  Assert.IsFalse(ALoaded.WelcomePageProjectSetup);
  Assert.IsFalse(ALoaded.WelcomePageNewFromTemplate);
end;

procedure TAtlasWelcomeSettingsTests.SaveAndLoadRoundTrip;
var
  mStore: IAtlasSettingsStore;
  mSaved, mLoaded: TAtlasPluginSettings;
begin
  mStore := TMemoryStore.Create;
  mSaved := ChangedWelcomeSettings;
  mSaved.Save(mStore);
  AssertWelcomeStored(mStore);
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  AssertWelcomeLoaded(mLoaded);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeSectionsTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeLayoutTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeGreetingTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeBackupTests);
  TDUnitX.RegisterTestFixture(TAtlasIdePageStepsTests);
  TDUnitX.RegisterTestFixture(TAtlasHostLayoutTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeRetireTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeSettingsTests);

end.
