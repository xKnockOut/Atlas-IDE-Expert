unit Atlas.Core.Welcome.Tests;

// Tests der Atlas-Willkommensseite ohne VCL (#753): Bereichsregister,
// Atlas-Layout und Verteilung auf Spalten, Grußzeile, Sicherung des
// Registry-Schlüssels WelcomePage (exakt zurück, auch „gab es nicht“),
// Raster der IDE nach dem Export aus Delphi 12 und die Einstellungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
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
  TAtlasHostLayoutTests = class
  public
    [Test]
    procedure ReadsDelphi12Export;
    [Test]
    procedure NoLayoutKeyMeansIdeDefault;
    [Test]
    procedure AtlasOnTopShiftsOtherSections;
    [Test]
    procedure AtlasOnTopDropsSingleAtlasSections;
    [Test]
    procedure WriteKeepsBackgroundValues;
    [Test]
    procedure DetectsMovedBoard;
  end;

  [TestFixture]
  TAtlasWelcomeSettingsTests = class
  public
    [Test]
    procedure DefaultsShowSectionsWithoutLayout;
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
  WelcomePath = 'Software\Embarcadero\BDS\23.0\WelcomePage';

function Section(const AId: string; AOrder: Integer; AColumn: TAtlasWelcomeColumn): TAtlasWelcomeSection;
begin
  Result := TAtlasWelcomeSection.Create(AId, AId, AOrder, AColumn, nil);
end;

function Joined(const AIds: TArray<string>): string;
var
  Id: string;
begin
  Result := '';
  for Id in AIds do
    if Result = '' then
      Result := Id
    else
      Result := Result + ',' + Id;
end;

function Number(const AName: string; AValue: Integer): TAtlasRegValue;
begin
  Result := TAtlasRegValue.Create(AName, TAtlasRegKind.Number, IntToStr(AValue));
end;

procedure AddItem(ALayout: TAtlasRegKey; AIndex: Integer; const AId: string; ARow, AColumn, ARowSpan,
  AColumnSpan: Integer);
var
  Item: TAtlasRegKey;
begin
  Item := ALayout.AddKey('Item ' + IntToStr(AIndex));
  Item.SetValue(TAtlasRegValue.Create('PluginID', TAtlasRegKind.Text, AId));
  Item.SetValue(Number('Row', ARow));
  Item.SetValue(Number('Column', AColumn));
  Item.SetValue(Number('RowSpan', ARowSpan));
  Item.SetValue(Number('ColumnSpan', AColumnSpan));
end;

/// <summary>Schlüssel WelcomePage wie in Marcos Export aus Delphi 12 (BDS 23.0).</summary>
function Delphi12Export: TAtlasRegKey;
var
  Layout, Available: TAtlasRegKey;
begin
  Result := TAtlasRegKey.Create('WelcomePage');
  Result.SetValue(TAtlasRegValue.Create('Background_Dark', TAtlasRegKind.Text,
    'C:\ProgramData\Embarcadero\BDS\23.0\Background images\Lights at the Night Circus.jpg'));
  Result.SetValue(TAtlasRegValue.Create('Background_Light', TAtlasRegKind.Text, ''));
  Available := Result.AddKey('AvailablePlugins');
  Available.SetValue(TAtlasRegValue.Create('0', TAtlasRegKind.Text, 'Embarcadero.WelcomePagePlugin.GetItPromoted'));
  Available.SetValue(TAtlasRegValue.Create('1', TAtlasRegKind.Text, 'Embarcadero.WelcomePagePlugin.CreateNew'));
  Layout := Result.AddKey('Layout');
  Layout.SetValue(Number('RowsCount', 2));
  Layout.SetValue(Number('ColumnsCount', 3));
  AddItem(Layout, 0, 'Embarcadero.WelcomePagePlugin.GetItNewIn', 0, 0, 2, 1);
  AddItem(Layout, 1, 'Embarcadero.WelcomePagePlugin.OpenRecent', 0, 1, 2, 1);
  AddItem(Layout, 2, 'Embarcadero.WelcomePagePlugin.Learn', 0, 2, 2, 1);
end;

{ TAtlasWelcomeSectionsTests }

procedure TAtlasWelcomeSectionsTests.SortsByOrderThenId;
var
  Sections: TAtlasWelcomeSections;
begin
  Sections := TAtlasWelcomeSections.Create;
  try
    Sections.Add(Section('atlas.news', 20, TAtlasWelcomeColumn.Right));
    Sections.Add(Section('atlas.continue', 10, TAtlasWelcomeColumn.Left));
    Sections.Add(Section('atlas.b', 30, TAtlasWelcomeColumn.Left));
    Sections.Add(Section('atlas.a', 30, TAtlasWelcomeColumn.Left));
    Assert.AreEqual('atlas.continue,atlas.news,atlas.a,atlas.b', Joined(Sections.VisibleIds));
  finally
    Sections.Free;
  end;
end;

procedure TAtlasWelcomeSectionsTests.AddReplacesSameId;
var
  Sections: TAtlasWelcomeSections;
  Found: TAtlasWelcomeSection;
begin
  Sections := TAtlasWelcomeSections.Create;
  try
    Sections.Add(Section('atlas.news', 20, TAtlasWelcomeColumn.Right));
    Sections.Add(TAtlasWelcomeSection.Create('ATLAS.NEWS', 'Neu in Atlas', 5, TAtlasWelcomeColumn.Right, nil));
    Assert.AreEqual(1, Integer(Length(Sections.All)));
    Assert.IsTrue(Sections.Find('atlas.news', Found));
    Assert.AreEqual('Neu in Atlas', Found.Title);
    Sections.Remove('atlas.news');
    Assert.IsFalse(Sections.Find('atlas.news', Found));
    Assert.AreEqual('', Found.Id);
  finally
    Sections.Free;
  end;
end;

procedure TAtlasWelcomeSectionsTests.VisibleFollowsSwitch;
var
  Sections: TAtlasWelcomeSections;
  Shown: Boolean;
begin
  Shown := False;
  Sections := TAtlasWelcomeSections.Create;
  try
    Sections.Add(TAtlasWelcomeSection.Create('atlas.tests', 'Tests', 10, TAtlasWelcomeColumn.Right,
      function: Boolean
      begin
        Result := Shown;
      end));
    Sections.Add(Section('atlas.help', 20, TAtlasWelcomeColumn.Right));
    Assert.AreEqual('atlas.help', Joined(Sections.VisibleIds), 'Schalter aus');
    Shown := True;
    Assert.AreEqual('atlas.tests,atlas.help', Joined(Sections.VisibleIds), 'Schalter an');
    Assert.AreEqual(2, Integer(Length(Sections.All)));
  finally
    Sections.Free;
  end;
end;

procedure TAtlasWelcomeSectionsTests.ListenersHearChanges;
var
  Sections: TAtlasWelcomeSections;
  Heard: TList<string>;
  Handle, Version: Integer;
begin
  Heard := TList<string>.Create;
  Sections := TAtlasWelcomeSections.Create;
  try
    Handle := Sections.AddListener(
      procedure(AId: string)
      begin
        Heard.Add(AId);
      end);
    Version := Sections.Version;
    Sections.Add(Section('atlas.state', 10, TAtlasWelcomeColumn.Right));
    Sections.Changed('atlas.state');
    Sections.Changed;
    Assert.AreEqual(3, Integer(Heard.Count));
    Assert.AreEqual('', Heard[0], 'Hinzufügen ändert die Menge');
    Assert.AreEqual('atlas.state', Heard[1], 'Inhalt eines Bereichs');
    Assert.AreEqual('', Heard[2]);
    Assert.AreEqual(Version + 3, Sections.Version);
    Sections.RemoveListener(Handle);
    Sections.Changed;
    Assert.AreEqual(3, Integer(Heard.Count), 'abgemeldet');
  finally
    Sections.Free;
    Heard.Free;
  end;
end;

procedure TAtlasWelcomeSectionsTests.PluginIdsRoundTrip;
begin
  Assert.AreEqual('Atlas.Welcome.state', TAtlasWelcomeIds.PluginId(TAtlasWelcomeIds.State));
  Assert.AreEqual('Atlas.Welcome.board', TAtlasWelcomeIds.PluginId(TAtlasWelcomeIds.Board));
  Assert.AreEqual(TAtlasWelcomeIds.Header, TAtlasWelcomeIds.SectionOf('Atlas.Welcome.header'));
  Assert.AreEqual(TAtlasWelcomeIds.Header, TAtlasWelcomeIds.SectionOf('atlas.welcome.HEADER'));
  Assert.AreEqual('', TAtlasWelcomeIds.SectionOf('Embarcadero.WelcomePagePlugin.OpenRecent'));
end;

{ TAtlasWelcomeLayoutTests }

function MockupSections: TArray<TAtlasWelcomeSection>;
begin
  Result := [Section(TAtlasWelcomeIds.State, 10, TAtlasWelcomeColumn.Right),
    Section(TAtlasWelcomeIds.Continue, 20, TAtlasWelcomeColumn.Left),
    Section(TAtlasWelcomeIds.Projects, 30, TAtlasWelcomeColumn.Left),
    Section(TAtlasWelcomeIds.History, 40, TAtlasWelcomeColumn.Left),
    Section(TAtlasWelcomeIds.News, 50, TAtlasWelcomeColumn.Right),
    Section(TAtlasWelcomeIds.Discover, 60, TAtlasWelcomeColumn.Right),
    Section(TAtlasWelcomeIds.Setup, 70, TAtlasWelcomeColumn.Right)];
end;

procedure TAtlasWelcomeLayoutTests.AtlasLayoutMatchesMockup;
var
  Columns: TArray<TArray<string>>;
begin
  Columns := TAtlasWelcomeLayout.Atlas.Arrange(MockupSections, 2);
  Assert.AreEqual(2, Integer(Length(Columns)));
  Assert.AreEqual('atlas.continue,atlas.projects,atlas.history', Joined(Columns[0]));
  Assert.AreEqual('atlas.state,atlas.news,atlas.discover,atlas.setup', Joined(Columns[1]));
end;

procedure TAtlasWelcomeLayoutTests.OneColumnStacksRightUnderLeft;
var
  Columns: TArray<TArray<string>>;
begin
  Columns := TAtlasWelcomeLayout.Atlas.Arrange(MockupSections, 1);
  Assert.AreEqual(1, Integer(Length(Columns)));
  Assert.AreEqual('atlas.continue,atlas.projects,atlas.history,atlas.state,atlas.news,atlas.discover,atlas.setup',
    Joined(Columns[0]));
  // Null Spalten gibt es nicht; mehr als drei auch nicht.
  Assert.AreEqual(1, Integer(Length(TAtlasWelcomeLayout.Atlas.Arrange(MockupSections, 0))));
  Assert.AreEqual(3, Integer(Length(TAtlasWelcomeLayout.Atlas.Arrange(MockupSections, 9))));
end;

procedure TAtlasWelcomeLayoutTests.UnknownSectionGoesToItsColumn;
var
  Columns: TArray<TArray<string>>;
begin
  Columns := TAtlasWelcomeLayout.Atlas.Arrange(MockupSections + [Section(TAtlasWelcomeIds.Tests, 80,
    TAtlasWelcomeColumn.Right), Section(TAtlasWelcomeIds.Unsaved, 5, TAtlasWelcomeColumn.Left)], 2);
  Assert.AreEqual('atlas.continue,atlas.projects,atlas.history,atlas.unsaved', Joined(Columns[0]));
  Assert.AreEqual('atlas.state,atlas.news,atlas.discover,atlas.setup,atlas.tests', Joined(Columns[1]));
end;

procedure TAtlasWelcomeLayoutTests.HiddenSectionsLeaveNoGap;
var
  Columns: TArray<TArray<string>>;
begin
  Columns := TAtlasWelcomeLayout.Atlas.Arrange([Section(TAtlasWelcomeIds.History, 40, TAtlasWelcomeColumn.Left),
    Section(TAtlasWelcomeIds.Setup, 70, TAtlasWelcomeColumn.Right)], 2);
  Assert.AreEqual('atlas.history', Joined(Columns[0]));
  Assert.AreEqual('atlas.setup', Joined(Columns[1]));
  Columns := TAtlasWelcomeLayout.Atlas.Arrange(nil, 2);
  Assert.AreEqual(2, Integer(Length(Columns)));
  Assert.AreEqual(0, Integer(Length(Columns[0])));
end;

procedure TAtlasWelcomeLayoutTests.JsonRoundTrip;
var
  Layout, Loaded: TAtlasWelcomeLayout;
begin
  Layout := TAtlasWelcomeLayout.Atlas;
  Layout.Name := 'Eigenes';
  Layout.Columns := 3;
  Layout.Slots := Layout.Slots + [TAtlasWelcomeSlot.Create(TAtlasWelcomeIds.Tests, 2)];
  Assert.IsTrue(TAtlasWelcomeLayout.FromJson(Layout.ToJson, Loaded));
  Assert.IsTrue(TAtlasWelcomeLayout.Same(Layout, Loaded));
  Assert.AreEqual('Eigenes', Loaded.Name);
  Assert.IsFalse(TAtlasWelcomeLayout.Same(TAtlasWelcomeLayout.Atlas, Loaded));
end;

procedure TAtlasWelcomeLayoutTests.InvalidJsonGivesAtlas;
var
  Loaded: TAtlasWelcomeLayout;
begin
  Assert.IsFalse(TAtlasWelcomeLayout.FromJson('kein JSON', Loaded));
  Assert.IsTrue(TAtlasWelcomeLayout.Same(TAtlasWelcomeLayout.Atlas, Loaded));
  Assert.IsFalse(TAtlasWelcomeLayout.FromJson('{"slots":[{"column":1}]}', Loaded), 'Platz ohne Kennung');
  Assert.IsTrue(TAtlasWelcomeLayout.Same(TAtlasWelcomeLayout.Atlas, Loaded));
  // Spalten außerhalb des Bereichs werden begrenzt.
  Assert.IsTrue(TAtlasWelcomeLayout.FromJson('{"columns":7,"slots":[{"id":"atlas.news","column":9}]}', Loaded));
  Assert.AreEqual(TAtlasWelcomeLayout.MaxColumns, Loaded.Columns);
  Assert.AreEqual(TAtlasWelcomeLayout.MaxColumns - 1, Loaded.Slots[0].Column);
end;

procedure TAtlasWelcomeLayoutTests.MovedToTopLeadsFirstColumn;
var
  Moved: TAtlasWelcomeLayout;
  Columns: TArray<TArray<string>>;
  Sections: TArray<TAtlasWelcomeSection>;
begin
  // #756: Nach einem Update steht „Neu in Atlas“ oben links statt in der rechten Spalte.
  Moved := TAtlasWelcomeLayout.Atlas.MovedToTop(TAtlasWelcomeIds.News);
  Assert.AreEqual(Integer(Length(TAtlasWelcomeLayout.Atlas.Slots)), Integer(Length(Moved.Slots)));
  Sections := [Section(TAtlasWelcomeIds.Continue, 10, TAtlasWelcomeColumn.Left),
    Section(TAtlasWelcomeIds.State, 40, TAtlasWelcomeColumn.Right),
    Section(TAtlasWelcomeIds.News, 50, TAtlasWelcomeColumn.Right)];
  Columns := Moved.Arrange(Sections, 2);
  Assert.AreEqual('atlas.news,atlas.continue', Joined(Columns[0]));
  Assert.AreEqual('atlas.state', Joined(Columns[1]));
  Columns := TAtlasWelcomeLayout.Atlas.Arrange(Sections, 2);
  Assert.AreEqual('atlas.continue', Joined(Columns[0]));
  Assert.AreEqual('atlas.state,atlas.news', Joined(Columns[1]));
  // Eine Spalte: ganz oben.
  Columns := Moved.Arrange(Sections, 1);
  Assert.AreEqual('atlas.news,atlas.continue,atlas.state', Joined(Columns[0]));
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
  Registry: IAtlasRegistryAccess;
  Original, Changed, Restored: TAtlasRegKey;
  Snapshot: string;
  Multi: TAtlasRegValue;
begin
  Registry := TAtlasMemoryRegistry.Create;
  Original := Delphi12Export;
  try
    Original.SetValue(TAtlasRegValue.Create('Pfad', TAtlasRegKind.ExpandText, '%APPDATA%\Atlas'));
    Multi := TAtlasRegValue.Create('Liste', TAtlasRegKind.MultiText, '');
    Multi.Lines := ['eins', '', 'drei'];
    Original.SetValue(Multi);
    Original.SetValue(TAtlasRegValue.Create('Groß', TAtlasRegKind.Number64, '18446744073709551615'));
    Original.SetValue(TAtlasRegValue.Create('Daten', TAtlasRegKind.Binary, '00FF10'));
    Original.SetValue(TAtlasRegValue.Create('Leer', TAtlasRegKind.Binary, ''));
    Original.SetValue(TAtlasRegValue.Create('Höchst', TAtlasRegKind.Number, '4294967295'));
    Registry.Replace(WelcomePath, Original);
    Snapshot := TAtlasWelcomeBackup.Snapshot(Registry, WelcomePath);
    // Atlas ändert das Layout …
    Changed := TAtlasRegKey.Create('WelcomePage');
    try
      Changed.SetValue(Number('Fremd', 1));
      Registry.Replace(WelcomePath, Changed);
    finally
      Changed.Free;
    end;
    // … und die Sicherung bringt den alten Stand exakt zurück.
    Assert.IsTrue(TAtlasWelcomeBackup.Restore(Registry, Snapshot));
    Restored := Registry.Read(WelcomePath);
    try
      Assert.IsTrue(Original.SameAs(Restored));
      Assert.IsTrue(Restored.SameAs(Original));
    finally
      Restored.Free;
    end;
  finally
    Original.Free;
  end;
end;

procedure TAtlasWelcomeBackupTests.RemovesKeyThatDidNotExist;
var
  Registry: IAtlasRegistryAccess;
  Snapshot: string;
  Key, Read: TAtlasRegKey;
begin
  Registry := TAtlasMemoryRegistry.Create;
  Snapshot := TAtlasWelcomeBackup.Snapshot(Registry, WelcomePath);
  Assert.IsTrue(Pos('"existed":false', Snapshot) > 0);
  Key := Delphi12Export;
  try
    Registry.Replace(WelcomePath, Key);
  finally
    Key.Free;
  end;
  Assert.IsTrue(TAtlasWelcomeBackup.Restore(Registry, Snapshot));
  Read := Registry.Read(WelcomePath);
  Assert.IsNull(Read, 'vorher gab es den Schlüssel nicht');
  Read.Free;
end;

procedure TAtlasWelcomeBackupTests.MatchesDetectsChanges;
var
  Registry: IAtlasRegistryAccess;
  Snapshot: string;
  Key: TAtlasRegKey;
begin
  Registry := TAtlasMemoryRegistry.Create;
  Key := Delphi12Export;
  try
    Registry.Replace(WelcomePath, Key);
    Snapshot := TAtlasWelcomeBackup.Snapshot(Registry, WelcomePath);
    Assert.IsTrue(TAtlasWelcomeBackup.Matches(Registry, Snapshot));
    Key.FindKey('Layout').SetValue(Number('RowsCount', 4));
    Registry.Replace(WelcomePath, Key);
    Assert.IsFalse(TAtlasWelcomeBackup.Matches(Registry, Snapshot), 'Raster geändert');
    Registry.Replace(WelcomePath, nil);
    Assert.IsFalse(TAtlasWelcomeBackup.Matches(Registry, Snapshot), 'Schlüssel fehlt');
  finally
    Key.Free;
  end;
  Snapshot := TAtlasWelcomeBackup.Snapshot(Registry, WelcomePath);
  Assert.IsTrue(TAtlasWelcomeBackup.Matches(Registry, Snapshot), 'fehlt wie gesichert');
end;

procedure TAtlasWelcomeBackupTests.RejectsInvalidSnapshot;
var
  Registry: IAtlasRegistryAccess;
begin
  Registry := TAtlasMemoryRegistry.Create;
  Assert.IsFalse(TAtlasWelcomeBackup.Restore(Registry, ''));
  Assert.IsFalse(TAtlasWelcomeBackup.Restore(Registry, '{"existed":true}'), 'ohne Pfad');
  Assert.IsFalse(TAtlasWelcomeBackup.Restore(Registry, '{"path":"x","key":{"values":[{"kind":"neu"}]}}'));
  Assert.IsFalse(TAtlasWelcomeBackup.Matches(Registry, 'kaputt'));
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
  Key: TAtlasRegKey;
  Layout: TAtlasHostLayout;
begin
  Key := Delphi12Export;
  try
    Assert.IsTrue(TAtlasHostLayout.Read(Key, Layout));
    Assert.AreEqual(2, Layout.Rows);
    Assert.AreEqual(3, Layout.Columns);
    Assert.AreEqual(3, Integer(Length(Layout.Items)));
    Assert.AreEqual(1, Layout.IndexOf('embarcadero.welcomepageplugin.openrecent'));
    Assert.AreEqual(2, Layout.Items[2].Column);
    Assert.AreEqual(2, Layout.Items[2].RowSpan);
    Assert.AreEqual('Embarcadero.WelcomePagePlugin.GetItPromoted,Embarcadero.WelcomePagePlugin.CreateNew',
      Joined(Layout.Available));
  finally
    Key.Free;
  end;
end;

procedure TAtlasHostLayoutTests.NoLayoutKeyMeansIdeDefault;
var
  Key: TAtlasRegKey;
  Layout, IdeLayout: TAtlasHostLayout;
begin
  Key := TAtlasRegKey.Create('WelcomePage');
  try
    Assert.IsFalse(TAtlasHostLayout.Read(Key, Layout));
  finally
    Key.Free;
  end;
  // Die Vorgabe der IDE gleicht dem frischen Export.
  Key := Delphi12Export;
  try
    TAtlasHostLayout.Read(Key, Layout);
  finally
    Key.Free;
  end;
  IdeLayout := TAtlasHostLayout.IdeDefault;
  Assert.AreEqual(Layout.Rows, IdeLayout.Rows);
  Assert.AreEqual(Layout.Columns, IdeLayout.Columns);
  Assert.AreEqual(Integer(Length(Layout.Items)), Integer(Length(IdeLayout.Items)));
  Assert.AreEqual(Joined(Layout.Available), Joined(IdeLayout.Available));
end;

procedure TAtlasHostLayoutTests.AtlasOnTopShiftsOtherSections;
var
  Key: TAtlasRegKey;
  Layout, Placed: TAtlasHostLayout;
begin
  Key := Delphi12Export;
  try
    TAtlasHostLayout.Read(Key, Layout);
  finally
    Key.Free;
  end;
  Placed := Layout.WithAtlasOnTop('Atlas.Welcome.board', TAtlasWelcomeIds.PluginPrefix);
  Assert.AreEqual(2 + TAtlasHostLayout.BoardRows, Placed.Rows);
  Assert.AreEqual(3, Placed.Columns);
  Assert.AreEqual(4, Integer(Length(Placed.Items)));
  Assert.AreEqual('Atlas.Welcome.board', Placed.Items[0].PluginId);
  Assert.AreEqual(0, Placed.Items[0].Row);
  Assert.AreEqual(0, Placed.Items[0].Column);
  Assert.AreEqual(TAtlasHostLayout.BoardRows, Placed.Items[0].RowSpan);
  Assert.AreEqual(3, Placed.Items[0].ColumnSpan, 'über alle Spalten');
  Assert.AreEqual(TAtlasHostLayout.BoardRows, Placed.Items[Placed.IndexOf('Embarcadero.WelcomePagePlugin.Learn')].Row);
  Assert.AreEqual(2, Placed.Items[Placed.IndexOf('Embarcadero.WelcomePagePlugin.Learn')].Column);
  Assert.IsTrue(Placed.HasAtlasOnTop('Atlas.Welcome.board', TAtlasWelcomeIds.PluginPrefix));
  Assert.IsFalse(Layout.HasAtlasOnTop('Atlas.Welcome.board', TAtlasWelcomeIds.PluginPrefix));
  // Zweimal anwenden ändert nichts mehr an der Lage.
  Placed := Placed.WithAtlasOnTop('Atlas.Welcome.board', TAtlasWelcomeIds.PluginPrefix);
  Assert.AreEqual(4, Integer(Length(Placed.Items)));
end;

procedure TAtlasHostLayoutTests.AtlasOnTopDropsSingleAtlasSections;
var
  Layout, Placed: TAtlasHostLayout;
begin
  Layout := TAtlasHostLayout.IdeDefault;
  Layout.Items := Layout.Items + [TAtlasHostItem.Create('Atlas.Welcome.state', 2, 0, 1, 1)];
  Layout.Available := Layout.Available + ['Atlas.Welcome.news', 'Atlas.Welcome.board'];
  Placed := Layout.WithAtlasOnTop('Atlas.Welcome.board', TAtlasWelcomeIds.PluginPrefix);
  Assert.IsFalse(Placed.Contains('Atlas.Welcome.state'));
  Assert.AreEqual('Embarcadero.WelcomePagePlugin.GetItPromoted,Embarcadero.WelcomePagePlugin.CreateNew',
    Joined(Placed.Available), 'Atlas weder ausgeblendet noch einzeln');
end;

procedure TAtlasHostLayoutTests.WriteKeepsBackgroundValues;
var
  Key: TAtlasRegKey;
  Layout, Placed, Read: TAtlasHostLayout;
  Value: TAtlasRegValue;
begin
  Key := Delphi12Export;
  try
    TAtlasHostLayout.Read(Key, Layout);
    Placed := Layout.WithAtlasOnTop('Atlas.Welcome.board', TAtlasWelcomeIds.PluginPrefix);
    Placed.WriteTo(Key);
    Assert.IsTrue(Key.FindValue('Background_Dark', Value), 'Hintergrund bleibt');
    Assert.IsNotNull(Key.FindKey('Layout').FindKey('Item 3'));
    Assert.IsNull(Key.FindKey('Layout').FindKey('Item 4'));
    Assert.IsTrue(TAtlasHostLayout.Read(Key, Read));
    Assert.AreEqual(Placed.Rows, Read.Rows);
    Assert.AreEqual(Integer(Length(Placed.Items)), Integer(Length(Read.Items)));
    Assert.AreEqual('Atlas.Welcome.board', Read.Items[Read.IndexOf('Atlas.Welcome.board')].PluginId);
    Assert.AreEqual(Joined(Placed.Available), Joined(Read.Available));
  finally
    Key.Free;
  end;
end;

procedure TAtlasHostLayoutTests.DetectsMovedBoard;
var
  Placed: TAtlasHostLayout;
  Item: TAtlasHostItem;
begin
  Placed := TAtlasHostLayout.IdeDefault.WithAtlasOnTop('Atlas.Welcome.board', TAtlasWelcomeIds.PluginPrefix);
  Item := Placed.Items[0];
  Item.Row := 2;
  Placed.Items[0] := Item;
  Assert.IsFalse(Placed.HasAtlasOnTop('Atlas.Welcome.board', TAtlasWelcomeIds.PluginPrefix), 'verschoben');
  Placed := TAtlasHostLayout.IdeDefault.WithAtlasOnTop('Atlas.Welcome.board', TAtlasWelcomeIds.PluginPrefix);
  Placed.Available := Placed.Available + ['Atlas.Welcome.board'];
  Assert.IsFalse(Placed.HasAtlasOnTop('Atlas.Welcome.board', TAtlasWelcomeIds.PluginPrefix), 'ausgeblendet');
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
  Text: string;
begin
  Result := ADefault;
  if FValues.TryGetValue(AName, Text) then
    Result := StrToIntDef(Text, ADefault);
end;

procedure TMemoryStore.WriteInteger(const AName: string; AValue: Integer);
begin
  FValues.AddOrSetValue(AName, IntToStr(AValue));
end;

function TMemoryStore.ReadString(const AName, ADefault: string): string;
begin
  if not FValues.TryGetValue(AName, Result) then
    Result := ADefault;
end;

procedure TMemoryStore.WriteString(const AName, AValue: string);
begin
  FValues.AddOrSetValue(AName, AValue);
end;

procedure TAtlasWelcomeSettingsTests.DefaultsShowSectionsWithoutLayout;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.WelcomePage);
  Assert.AreEqual('welcomePage', Settings.WelcomePageHost);
  Assert.AreEqual('off', Settings.WelcomePageLayout, 'das Layout der IDE bleibt, bis man es anwendet');
  Assert.IsTrue(Settings.WelcomePageHeader);
  Assert.IsTrue(Settings.WelcomePageGreeting);
  Assert.AreEqual('afterUpdate', Settings.WelcomePageWhatsNew);
  Assert.AreEqual('', Settings.WhatsNewSeen, 'vor dem ersten Start nichts gesehen');
  // #754: Zustandskachel an, auch bei allem grün.
  Assert.IsTrue(Settings.WelcomePageStatusTile);
  Assert.IsFalse(Settings.WelcomePageStatusTileOnlyProblems);
  // #757: Karte „Atlas entdecken“ an, Nutzung lokal zählen an.
  Assert.IsTrue(Settings.WelcomePageDiscover);
  Assert.IsTrue(Settings.TipsUsageTracking);
end;

procedure TAtlasWelcomeSettingsTests.NormalizeMapsUnknownValues;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Settings.WelcomePageHost := ' DOCKWINDOW ';
  Settings.WelcomePageLayout := 'Atlas';
  Settings.WelcomePageWhatsNew := ' ALWAYS ';
  Settings.WhatsNewSeen := ' 1.1.0 ';
  Settings.Normalize;
  Assert.AreEqual('dockWindow', Settings.WelcomePageHost);
  Assert.AreEqual('atlas', Settings.WelcomePageLayout);
  Assert.AreEqual('always', Settings.WelcomePageWhatsNew);
  Assert.AreEqual('1.1.0', Settings.WhatsNewSeen);
  Settings.WelcomePageHost := 'irgendwo';
  Settings.WelcomePageLayout := 'eigen';
  Settings.WelcomePageWhatsNew := 'manchmal';
  Settings.Normalize;
  Assert.AreEqual('welcomePage', Settings.WelcomePageHost);
  Assert.AreEqual('off', Settings.WelcomePageLayout);
  Assert.AreEqual('afterUpdate', Settings.WelcomePageWhatsNew);
  Settings.WelcomePageWhatsNew := 'Off';
  Settings.Normalize;
  Assert.AreEqual('off', Settings.WelcomePageWhatsNew);
end;

procedure TAtlasWelcomeSettingsTests.SaveAndLoadRoundTrip;
var
  Store: IAtlasSettingsStore;
  Saved, Loaded: TAtlasPluginSettings;
begin
  Store := TMemoryStore.Create;
  Saved := TAtlasPluginSettings.Defaults;
  Saved.WelcomePage := False;
  Saved.WelcomePageHost := 'dockWindow';
  Saved.WelcomePageLayout := 'atlas';
  Saved.WelcomePageHeader := False;
  Saved.WelcomePageGreeting := False;
  Saved.WelcomePageWhatsNew := 'always';
  Saved.WhatsNewSeen := '1.1.0';
  Saved.WelcomePageProjectStatus := False;
  Saved.WelcomePageMaxProjects := 12;
  Saved.WelcomePageRefreshVcs := False;
  Saved.WelcomePageUnsaved := False;
  Saved.WelcomePageUnsavedMinAgeHours := 3;
  Saved.WelcomePageUnsavedWarnHours := 10;
  Saved.WelcomePageUnsavedAlertHours := 20;
  Saved.WelcomePageUnsavedHideWhenClean := True;
  Saved.WelcomePageStatusTile := False;
  Saved.WelcomePageStatusTileOnlyProblems := True;
  Saved.WelcomePageDiscover := False;
  Saved.TipsUsageTracking := False;
  Saved.Save(Store);
  Assert.AreEqual(0, Store.ReadInteger('WelcomePageDiscover', 1), 'Registry-Name (#757)');
  Assert.AreEqual(0, Store.ReadInteger('TipsUsageTracking', 1), 'Registry-Name (#757)');
  Assert.AreEqual(0, Store.ReadInteger('WelcomePageStatusTile', 1), 'Registry-Name (#754)');
  Assert.AreEqual(1, Store.ReadInteger('WelcomePageStatusTileOnlyProblems', 0));
  Assert.AreEqual(0, Store.ReadInteger('WelcomePageUnsaved', 1), 'Registry-Name (#762)');
  Assert.AreEqual(3, Store.ReadInteger('WelcomePageUnsavedMinAgeHours', 0));
  Assert.AreEqual(10, Store.ReadInteger('WelcomePageUnsavedWarnHours', 0));
  Assert.AreEqual(20, Store.ReadInteger('WelcomePageUnsavedAlertHours', 0));
  Assert.AreEqual(1, Store.ReadInteger('WelcomePageUnsavedHideWhenClean', 0));
  Assert.AreEqual(0, Store.ReadInteger('WelcomePageProjectStatus', 1), 'Registry-Name (#592)');
  Assert.AreEqual(12, Store.ReadInteger('WelcomePageMaxProjects', 0));
  Assert.AreEqual(0, Store.ReadInteger('WelcomePageRefreshVcs', 1));
  Assert.AreEqual(0, Store.ReadInteger('WelcomePage', 1), 'Registry-Name');
  Assert.AreEqual('atlas', Store.ReadString('WelcomePageLayout', ''));
  Assert.AreEqual('always', Store.ReadString('WelcomePageWhatsNew', ''));
  Assert.AreEqual('1.1.0', Store.ReadString('WhatsNewSeen', ''));
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.WelcomePage);
  Assert.AreEqual('dockWindow', Loaded.WelcomePageHost);
  Assert.AreEqual('atlas', Loaded.WelcomePageLayout);
  Assert.IsFalse(Loaded.WelcomePageHeader);
  Assert.IsFalse(Loaded.WelcomePageGreeting);
  Assert.AreEqual('always', Loaded.WelcomePageWhatsNew);
  Assert.AreEqual('1.1.0', Loaded.WhatsNewSeen);
  Assert.IsFalse(Loaded.WelcomePageProjectStatus);
  Assert.AreEqual(12, Loaded.WelcomePageMaxProjects);
  Assert.IsFalse(Loaded.WelcomePageRefreshVcs);
  Assert.IsFalse(Loaded.WelcomePageUnsaved);
  Assert.AreEqual(3, Loaded.WelcomePageUnsavedMinAgeHours);
  Assert.AreEqual(10, Loaded.WelcomePageUnsavedWarnHours);
  Assert.AreEqual(20, Loaded.WelcomePageUnsavedAlertHours);
  Assert.IsTrue(Loaded.WelcomePageUnsavedHideWhenClean);
  Assert.IsFalse(Loaded.WelcomePageStatusTile);
  Assert.IsTrue(Loaded.WelcomePageStatusTileOnlyProblems);
  Assert.IsFalse(Loaded.WelcomePageDiscover);
  Assert.IsFalse(Loaded.TipsUsageTracking);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeSectionsTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeLayoutTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeGreetingTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeBackupTests);
  TDUnitX.RegisterTestFixture(TAtlasHostLayoutTests);
  TDUnitX.RegisterTestFixture(TAtlasWelcomeSettingsTests);

end.
