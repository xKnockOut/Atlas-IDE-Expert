unit Atlas.Core.UnitSearch.Tests;

// Tests für das Fenster „Units suchen“ (#777) ohne VCL: Filtersyntax,
// Rangfolge, Gruppierung, Pfadkürzung in der Mitte, Art und gemerkter Zustand.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  Atlas.Core.UnitSearch.Model,
  Atlas.Core.UnitSearch.State;

type
  [TestFixture]
  TAtlasUnitSearchTests = class
  private
    function Entries: TAtlasUnitEntries;
    function Names(const AEntries: TAtlasUnitEntries; const AOrder: TArray<Integer>): string;
  public
    [Test]
    procedure ParsesFilterSyntax;
    [Test]
    procedure WithoutSyntaxEverythingIsText;
    [Test]
    procedure ReadsServerAnswer;
    [Test]
    procedure KindFromText;
    [Test]
    procedure FiltersByKindProjectAndOrigin;
    [Test]
    procedure RanksOpenThenActiveProject;
    [Test]
    procedure MatchesCamelCaseAndLastSegment;
    [Test]
    procedure GroupsByProjectWithCounts;
    [Test]
    procedure GroupsByFolderBestFirstWhenSearching;
    [Test]
    procedure ShortensPathInTheMiddle;
    [Test]
    procedure DistinguishesFormAndTests;
    [Test]
    procedure ScopesToOrigins;
    [Test]
    procedure ReadsPreview;
    [Test]
    procedure StateRoundTrip;
    [Test]
    procedure FiveThousandUnitsPerKeystroke;
  end;

implementation

uses
  System.JSON,
  System.Diagnostics,
  System.Math;

const
  Root = 'C:\Arbeit\Atlas-IDE-Expert-claude-project-thread-j9xhhv';
  Answer =
    '{"units":[' +
    '{"name":"Atlas.Common.Dfm.BinaryForm","uri":"C:\\Arbeit\\Atlas-IDE-Expert-claude-project-thread-j9xhhv\\Packages\\Atlas.Common\\Source\\Dfm\\Atlas.Common.Dfm.BinaryForm.pas","origin":"project","kind":"unit","projects":["Atlas.Common"]},' +
    '{"name":"Atlas.Common.Dfm.BinaryForm.Tests","uri":"C:\\Arbeit\\Atlas-IDE-Expert-claude-project-thread-j9xhhv\\Tests\\Common\\Dfm\\Atlas.Common.Dfm.BinaryForm.Tests.pas","origin":"project","kind":"test","projects":["Atlas.Tests"]},' +
    '{"name":"Atlas.UI.Settings.Page","uri":"C:\\Arbeit\\Atlas-IDE-Expert-claude-project-thread-j9xhhv\\Packages\\Atlas.IDE.Expert\\Source\\UI\\Settings\\Atlas.UI.Settings.Page.pas","origin":"project","kind":"frame","projects":["Atlas.IDE.Expert"]},' +
    '{"name":"Atlas.UI.Results.Frame","uri":"C:\\Arbeit\\Atlas-IDE-Expert-claude-project-thread-j9xhhv\\Packages\\Atlas.IDE.Expert\\Source\\UI\\Results\\Atlas.UI.Results.Frame.pas","origin":"project","kind":"form","projects":["Atlas.IDE.Expert"]},' +
    '{"name":"Atlas.Core.Settings.Tests","uri":"C:\\Arbeit\\Atlas-IDE-Expert-claude-project-thread-j9xhhv\\Tests\\IDE.Expert\\Atlas.Core.Settings.Tests.pas","origin":"project","kind":"test","projects":["Atlas.Tests"]},' +
    '{"name":"Atlas.Core.Settings.Plugin","uri":"C:\\Arbeit\\Atlas-IDE-Expert-claude-project-thread-j9xhhv\\Packages\\Atlas.IDE.Expert\\Source\\Core\\Settings\\Atlas.Core.Settings.Plugin.pas","origin":"project","kind":"unit","projects":["Atlas.IDE.Expert","Atlas.Tests"]},' +
    '{"name":"Hilfe","uri":"C:\\Lib\\Hilfe.pas","origin":"searchPath","kind":"unit","projects":[]},' +
    '{"name":"System.SysUtils","uri":"C:\\BDS\\source\\rtl\\sys\\System.SysUtils.pas","origin":"library","kind":"unit","projects":[]},' +
    '{"name":"Optionen.inc","uri":"C:\\Arbeit\\Atlas-IDE-Expert-claude-project-thread-j9xhhv\\Optionen.inc","origin":"project","kind":"inc","projects":["Atlas.Common"]}' +
    '],"projects":[{"name":"Atlas.Common"},{"name":"Atlas.IDE.Expert"},{"name":"Atlas.Tests","isTest":true}],"count":9}';

function Path(AUri: string): string;
begin
  Result := AUri;
end;

function TAtlasUnitSearchTests.Entries: TAtlasUnitEntries;
var
  Value: TJSONValue;
begin
  Value := TJSONObject.ParseJSONValue(Answer);
  try
    Result := TAtlasUnitSearch.FromJson(Value, 'Atlas.IDE.Expert', Path);
  finally
    Value.Free;
  end;
end;

function TAtlasUnitSearchTests.Names(const AEntries: TAtlasUnitEntries; const AOrder: TArray<Integer>): string;
var
  Index: Integer;
begin
  Result := '';
  for Index in AOrder do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + AEntries[Index].Name;
  end;
end;

procedure TAtlasUnitSearchTests.ParsesFilterSyntax;
var
  Query: TAtlasUnitQuery;
begin
  Query := TAtlasUnitQuery.Parse('-t:test sett', True);
  Assert.AreEqual(1, Integer(Length(Query.Words)));
  Assert.AreEqual('sett', Query.Words[0]);
  Assert.IsTrue(TAtlasUnitKind.Test in Query.NotKinds);
  Assert.IsTrue(Query.Kinds = []);
  Query := TAtlasUnitQuery.Parse('p:ide  t:form|frame  -p:tests', True);
  Assert.IsFalse(Query.HasWords);
  Assert.AreEqual('ide', Query.Projects[0]);
  Assert.AreEqual('tests', Query.NotProjects[0]);
  Assert.IsTrue(Query.Kinds = [TAtlasUnitKind.Form, TAtlasUnitKind.Frame]);
  // Unvollständige oder unbekannte Filter bleiben Suchtext.
  Query := TAtlasUnitQuery.Parse('t: t:xyz p:', True);
  Assert.AreEqual(3, Integer(Length(Query.Words)));
  Assert.IsTrue(TAtlasUnitQuery.IsFilter('-t:dm'));
  Assert.IsTrue(TAtlasUnitQuery.IsFilter('T:INC'));
  Assert.IsFalse(TAtlasUnitQuery.IsFilter('x:inc'));
end;

procedure TAtlasUnitSearchTests.WithoutSyntaxEverythingIsText;
var
  Query: TAtlasUnitQuery;
begin
  Query := TAtlasUnitQuery.Parse('p:ide form', False);
  Assert.AreEqual(2, Integer(Length(Query.Words)));
  Assert.IsTrue(Query.Kinds = []);
  Assert.AreEqual(0, Integer(Length(Query.Projects)));
end;

procedure TAtlasUnitSearchTests.ReadsServerAnswer;
var
  List: TAtlasUnitEntries;
  Value: TJSONValue;
begin
  List := Entries;
  Assert.AreEqual(9, Integer(Length(List)));
  Assert.IsTrue(List[0].Origin = TAtlasUnitOrigin.Group, 'anderes Projekt der Gruppe');
  Assert.IsTrue(List[2].Origin = TAtlasUnitOrigin.Active);
  Assert.IsTrue(List[6].Origin = TAtlasUnitOrigin.SearchPath);
  Assert.IsTrue(List[7].Origin = TAtlasUnitOrigin.Library_);
  // Gehört die Unit auch zum aktiven Projekt, ist das ihr Projekt.
  Assert.AreEqual('Atlas.IDE.Expert', List[5].Project);
  Assert.IsTrue(List[5].Origin = TAtlasUnitOrigin.Active);
  Assert.AreEqual('Atlas.Tests', List[4].Project);
  Value := TJSONObject.ParseJSONValue(Answer);
  try
    Assert.AreEqual(3, Integer(Length(TAtlasUnitSearch.ProjectsFromJson(Value))));
    // Ohne aktives Projekt zählen alle Projekte als aktiv.
    Assert.IsTrue(TAtlasUnitSearch.FromJson(Value, '', Path)[0].Origin = TAtlasUnitOrigin.Active);
  finally
    Value.Free;
  end;
  Assert.AreEqual(0, Integer(Length(TAtlasUnitSearch.FromJson(nil, '', Path))));
end;

procedure TAtlasUnitSearchTests.KindFromText;
var
  Kind: TAtlasUnitKind;
begin
  Assert.IsTrue(TAtlasUnitSearch.KindFromText('dm', Kind));
  Assert.IsTrue(Kind = TAtlasUnitKind.DataModule);
  Assert.IsTrue(TAtlasUnitSearch.KindFromText('DataModule', Kind));
  Assert.IsTrue(Kind = TAtlasUnitKind.DataModule);
  Assert.IsTrue(TAtlasUnitSearch.KindFromText('INC', Kind));
  Assert.IsTrue(Kind = TAtlasUnitKind.Include);
  Assert.IsFalse(TAtlasUnitSearch.KindFromText('formular', Kind));
  Assert.AreEqual('frame', TAtlasUnitSearch.KindText(TAtlasUnitKind.Frame));
end;

procedure TAtlasUnitSearchTests.FiltersByKindProjectAndOrigin;
var
  List: TAtlasUnitEntries;
  All: TAtlasUnitOrigins;
begin
  List := Entries;
  TAtlasUnitSearch.SortByName(List);
  All := TAtlasUnitSearch.OriginsForScope('library');
  // Abnahme #777: "-t:test sett" blendet Tests aus.
  Assert.AreEqual('Atlas.Core.Settings.Plugin,Atlas.UI.Settings.Page',
    Names(List, TAtlasUnitSearch.Order(List, TAtlasUnitQuery.Parse('-t:test sett', True), All, [])));
  // "p:ide t:form" zeigt nur Formulare aus Atlas.IDE.Expert.
  Assert.AreEqual('Atlas.UI.Results.Frame',
    Names(List, TAtlasUnitSearch.Order(List, TAtlasUnitQuery.Parse('p:ide t:form', True), All, [])));
  // Chips: nur Tests, nur Projekt-Units.
  Assert.AreEqual('Atlas.Common.Dfm.BinaryForm.Tests,Atlas.Core.Settings.Tests',
    Names(List, TAtlasUnitSearch.Order(List, TAtlasUnitQuery.Parse('', True), All, [TAtlasUnitKind.Test])));
  Assert.AreEqual(3, Integer(Length(TAtlasUnitSearch.Order(List, TAtlasUnitQuery.Parse('', True),
    [TAtlasUnitOrigin.Active], []))));
  Assert.AreEqual('Hilfe', Names(List, TAtlasUnitSearch.Order(List, TAtlasUnitQuery.Parse('hil', True),
    TAtlasUnitSearch.OriginsForScope('searchPath'), [])));
  Assert.AreEqual('', Names(List, TAtlasUnitSearch.Order(List, TAtlasUnitQuery.Parse('sysutils', True),
    TAtlasUnitSearch.OriginsForScope('searchPath'), [])));
end;

procedure TAtlasUnitSearchTests.RanksOpenThenActiveProject;
var
  List: TAtlasUnitEntries;
  Order: TArray<Integer>;
  Index: Integer;
begin
  List := Entries;
  TAtlasUnitSearch.SortByName(List);
  // "Settings" trifft Page (aktives Projekt), Tests (andere) und Plugin (aktiv) gleich gut.
  Order := TAtlasUnitSearch.Order(List, TAtlasUnitQuery.Parse('Settings', True),
    TAtlasUnitSearch.OriginsForScope('group'), []);
  Assert.AreEqual('Atlas.Core.Settings.Plugin,Atlas.UI.Settings.Page,Atlas.Core.Settings.Tests', Names(List, Order));
  for Index := 0 to High(List) do
    List[Index].IsOpen := List[Index].Name = 'Atlas.Core.Settings.Tests';
  Order := TAtlasUnitSearch.Order(List, TAtlasUnitQuery.Parse('Settings', True),
    TAtlasUnitSearch.OriginsForScope('group'), []);
  Assert.AreEqual('Atlas.Core.Settings.Tests', List[Order[0]].Name, 'offene Unit zuerst');
end;

procedure TAtlasUnitSearchTests.MatchesCamelCaseAndLastSegment;
begin
  Assert.IsTrue(TAtlasUnitSearch.Score('ACDB', 'Atlas.Common.Dfm.BinaryForm') > 0, 'Wortanfänge');
  Assert.IsTrue(TAtlasUnitSearch.Score('BinaryForm', 'Atlas.Common.Dfm.BinaryForm') >
    TAtlasUnitSearch.Score('BinaryForm', 'Atlas.Common.Dfm.BinaryForm.Tests'), 'letzter Teil genau');
  Assert.AreEqual(TAtlasUnitSearch.ScoreSubsequence, TAtlasUnitSearch.Score('acmbf', 'Atlas.Common.Dfm.BinaryForm'));
  Assert.IsTrue(TAtlasUnitSearch.Score('xyz', 'Atlas.Common.Dfm.BinaryForm') < 0);
end;

procedure TAtlasUnitSearchTests.GroupsByProjectWithCounts;
var
  List: TAtlasUnitEntries;
  Order: TArray<Integer>;
  Rows: TAtlasUnitRows;
begin
  List := Entries;
  Order := TAtlasUnitSearch.Order(List, TAtlasUnitQuery.Parse('', True), TAtlasUnitSearch.OriginsForScope('group'), []);
  Rows := TAtlasUnitSearch.Rows(List, Order, TAtlasUnitGrouping.Project, Root, 'Atlas.IDE.Expert', nil, False);
  // Aktives Projekt oben, dann alphabetisch.
  Assert.IsTrue(Rows[0].IsGroup);
  Assert.AreEqual('Atlas.IDE.Expert', Rows[0].Group);
  Assert.AreEqual(3, Rows[0].Count);
  Assert.AreEqual(3 + 1 + 2 + 1 + 2 + 1, Integer(Length(Rows)));
  Assert.AreEqual('Atlas.Common', Rows[4].Group);
  Assert.AreEqual(2, Rows[4].Count, 'BinaryForm und Optionen.inc');
  // Eingeklappt: nur der Kopf.
  Rows := TAtlasUnitSearch.Rows(List, Order, TAtlasUnitGrouping.Project, Root, 'Atlas.IDE.Expert',
    ['atlas.common'], False);
  Assert.AreEqual(3 + 1 + 1 + 2 + 1, Integer(Length(Rows)));
  Assert.IsTrue(Rows[4].Collapsed);
  Assert.AreEqual(2, Rows[4].Count);
  // Ohne Gruppierung keine Köpfe.
  Rows := TAtlasUnitSearch.Rows(List, Order, TAtlasUnitGrouping.None, Root, '', nil, False);
  Assert.AreEqual(Integer(Length(Order)), Integer(Length(Rows)));
  Assert.IsFalse(Rows[0].IsGroup);
end;

procedure TAtlasUnitSearchTests.GroupsByFolderBestFirstWhenSearching;
var
  List: TAtlasUnitEntries;
  Order: TArray<Integer>;
  Rows: TAtlasUnitRows;
begin
  List := Entries;
  Order := TAtlasUnitSearch.Order(List, TAtlasUnitQuery.Parse('settingstests', True),
    TAtlasUnitSearch.OriginsForScope('group'), []);
  Rows := TAtlasUnitSearch.Rows(List, Order, TAtlasUnitGrouping.Folder, Root, 'Atlas.IDE.Expert', nil, True);
  Assert.AreEqual('Tests\IDE.Expert', Rows[0].Group);
  Assert.AreEqual('Packages\Atlas.IDE.Expert\Source\Core\Settings',
    TAtlasUnitSearch.GroupOf(List[5], TAtlasUnitGrouping.Folder, Root));
  Assert.AreEqual('', TAtlasUnitSearch.GroupOf(List[8], TAtlasUnitGrouping.Folder, Root), 'Datei in der Wurzel');
end;

procedure TAtlasUnitSearchTests.ShortensPathInTheMiddle;
var
  FileName: string;
begin
  Assert.AreEqual('abcdef', TAtlasUnitSearch.MiddleEllipsis('abcdef', 6));
  Assert.AreEqual('ab…fg', TAtlasUnitSearch.MiddleEllipsis('abcdefg', 5));
  Assert.AreEqual('a…g', TAtlasUnitSearch.MiddleEllipsis('abcdefg', 3));
  Assert.AreEqual(10, Integer(Length(TAtlasUnitSearch.MiddleEllipsis('Packages\Atlas.Common\Source\Dfm\X.pas', 10))));
  FileName := Root + '\Packages\Atlas.Common\Source\Dfm\Atlas.Common.Dfm.BinaryForm.pas';
  Assert.AreEqual('Packages\Atlas.Common\Source\Dfm\Atlas.Common.Dfm.BinaryForm.pas',
    TAtlasUnitSearch.DisplayPath(FileName, Root, TAtlasUnitPathStyle.Relative, 20));
  Assert.IsTrue(TAtlasUnitSearch.DisplayPath(FileName, Root, TAtlasUnitPathStyle.Compact, 30).EndsWith('BinaryForm.pas'));
  Assert.AreEqual(30, Integer(Length(TAtlasUnitSearch.DisplayPath(FileName, Root, TAtlasUnitPathStyle.Compact, 30))));
  Assert.AreEqual(FileName, TAtlasUnitSearch.DisplayPath(FileName, Root, TAtlasUnitPathStyle.Absolute, 30));
  Assert.AreEqual('C:\Lib\Hilfe.pas', TAtlasUnitSearch.DisplayPath('C:\Lib\Hilfe.pas', Root,
    TAtlasUnitPathStyle.Relative, 0), 'außerhalb absolut');
  Assert.AreEqual('C:\P', TAtlasUnitSearch.CommonRoot(['C:\P\A\x.pas', 'C:\P\B\y.pas', 'C:\P\z.pas']));
  Assert.AreEqual('', TAtlasUnitSearch.CommonRoot(['C:\P\x.pas', 'D:\Q\y.pas']));
end;

procedure TAtlasUnitSearchTests.DistinguishesFormAndTests;
var
  List: TAtlasUnitEntries;
  Order: TArray<Integer>;
  First, Second: string;
begin
  // Abnahme #777: lange Ordnernamen schneiden den unterscheidenden Teil nicht ab.
  List := Entries;
  Order := TAtlasUnitSearch.Order(List, TAtlasUnitQuery.Parse('BinaryForm', True),
    TAtlasUnitSearch.OriginsForScope('group'), []);
  Assert.AreEqual(2, Integer(Length(Order)));
  First := TAtlasUnitSearch.DisplayPath(List[Order[0]].FileName, Root, TAtlasUnitPathStyle.Compact, 40);
  Second := TAtlasUnitSearch.DisplayPath(List[Order[1]].FileName, Root, TAtlasUnitPathStyle.Compact, 40);
  Assert.AreNotEqual(First, Second);
  Assert.IsFalse(First.Contains('j9xhhv'), 'relativ ab der Projektgruppe');
  Assert.IsTrue(List[Order[0]].Kind <> List[Order[1]].Kind);
end;

procedure TAtlasUnitSearchTests.ScopesToOrigins;
begin
  Assert.IsTrue(TAtlasUnitSearch.OriginsForScope('project') = [TAtlasUnitOrigin.Active]);
  Assert.IsTrue(TAtlasUnitSearch.OriginsForScope('group') = [TAtlasUnitOrigin.Active, TAtlasUnitOrigin.Group]);
  Assert.IsTrue(TAtlasUnitOrigin.SearchPath in TAtlasUnitSearch.OriginsForScope('searchPath'));
  Assert.IsFalse(TAtlasUnitOrigin.Library_ in TAtlasUnitSearch.OriginsForScope('searchPath'));
  Assert.IsTrue(TAtlasUnitOrigin.Library_ in TAtlasUnitSearch.OriginsForScope('library'));
  Assert.IsTrue(TAtlasUnitSearch.GroupingFromText('folder') = TAtlasUnitGrouping.Folder);
  Assert.IsTrue(TAtlasUnitSearch.GroupingFromText('x') = TAtlasUnitGrouping.Project);
  Assert.IsTrue(TAtlasUnitSearch.PathStyleFromText('compact') = TAtlasUnitPathStyle.Compact);
end;

procedure TAtlasUnitSearchTests.ReadsPreview;
var
  Value: TJSONValue;
  Preview: TAtlasUnitPreview;
begin
  Value := TJSONObject.ParseJSONValue('{"uri":"C:\\P\\Haupt.pas","header":"Kopf","lines":120,' +
    '"modified":"2026-10-15T08:30:00.000Z","git":"modified","types":[{"name":"THaupt","kind":"class"}],' +
    '"usedBy":3,"usedByUnits":["A","B","C"],"form":{"class":"THaupt","caption":"Kunden","width":400,"height":300,' +
    '"items":[["Kopf","TPanel","",0,0,400,40,1]]}}');
  try
    Preview := TAtlasUnitPreview.FromJson(Value, Path);
  finally
    Value.Free;
  end;
  Assert.AreEqual('C:\P\Haupt.pas', Preview.FileName);
  Assert.AreEqual('Kopf', Preview.Header);
  Assert.AreEqual(120, Preview.Lines);
  Assert.IsTrue(Preview.Modified > 0);
  Assert.AreEqual('modified', Preview.Git);
  Assert.AreEqual('THaupt', Preview.Types[0].Name);
  Assert.AreEqual(3, Preview.UsedBy);
  Assert.AreEqual(3, Integer(Length(Preview.UsedByUnits)));
  Assert.IsTrue(Preview.HasForm);
  Assert.AreEqual(400, Preview.FormWidth);
  Assert.AreEqual('TPanel', Preview.FormItems[0].TypeName);
  Assert.AreEqual(40, Preview.FormItems[0].Height);
  Preview := TAtlasUnitPreview.FromJson(nil, Path);
  Assert.AreEqual(-1, Preview.UsedBy);
  Assert.IsFalse(Preview.HasForm);
end;

procedure TAtlasUnitSearchTests.StateRoundTrip;
var
  State, Loaded: TAtlasUnitSearchState;
  Origins: TAtlasUnitOrigins;
  Kinds: TAtlasUnitKinds;
begin
  State := TAtlasUnitSearchState.Create;
  Loaded := TAtlasUnitSearchState.Create;
  try
    Assert.IsFalse(State.Filters('C:\P\Gruppe.groupproj', Origins, Kinds));
    State.SetCollapsed('C:\P\Gruppe.groupproj', TAtlasUnitGrouping.Project, ['Atlas.Common', 'atlas.tests']);
    State.SetCollapsed('C:\P\Gruppe.groupproj', TAtlasUnitGrouping.Folder, ['Tests']);
    State.SetFilters('C:\P\Gruppe.groupproj', [TAtlasUnitOrigin.Active, TAtlasUnitOrigin.Library_],
      [TAtlasUnitKind.Form]);
    State.Left := 10;
    State.Width := 900;
    State.PreviewWidth := 320;
    State.PreviewVisible := False;
    Loaded.LoadJson(State.ToJson);
    Assert.AreEqual(2, Integer(Length(Loaded.Collapsed('c:\p\gruppe.groupproj', TAtlasUnitGrouping.Project))));
    Assert.AreEqual('atlas.common', Loaded.Collapsed('C:\P\Gruppe.groupproj', TAtlasUnitGrouping.Project)[0]);
    Assert.AreEqual('tests', Loaded.Collapsed('C:\P\Gruppe.groupproj', TAtlasUnitGrouping.Folder)[0]);
    Assert.IsTrue(Loaded.Filters('C:\P\Gruppe.groupproj', Origins, Kinds));
    Assert.IsTrue(Origins = [TAtlasUnitOrigin.Active, TAtlasUnitOrigin.Library_]);
    Assert.IsTrue(Kinds = [TAtlasUnitKind.Form]);
    Assert.AreEqual(10, Loaded.Left);
    Assert.AreEqual(900, Loaded.Width);
    Assert.AreEqual(320, Loaded.PreviewWidth);
    Assert.IsFalse(Loaded.PreviewVisible);
    // Neu setzen ersetzt nur die eigene Gruppierung.
    Loaded.SetCollapsed('C:\P\Gruppe.groupproj', TAtlasUnitGrouping.Project, nil);
    Assert.AreEqual(0, Integer(Length(Loaded.Collapsed('C:\P\Gruppe.groupproj', TAtlasUnitGrouping.Project))));
    Assert.AreEqual(1, Integer(Length(Loaded.Collapsed('C:\P\Gruppe.groupproj', TAtlasUnitGrouping.Folder))));
    Loaded.LoadJson('kein json');
    Assert.AreEqual(0, Loaded.Width);
    Assert.IsTrue(Loaded.PreviewVisible);
  finally
    Loaded.Free;
    State.Free;
  end;
end;

procedure TAtlasUnitSearchTests.FiveThousandUnitsPerKeystroke;
const
  Count = 5000;
  // Tastendruck für Tastendruck wie im Fenster; „-t:test “ wird beim Leerzeichen zum Filter.
  Areas: array[0..9] of string = ('Common', 'Windows', 'Core', 'UI', 'IDE', 'Server', 'Setup', 'Tests', 'Tools',
    'Shell');
  Features: array[0..24] of string = ('Settings', 'Completion', 'Hover', 'Index', 'Lsp', 'Dfm', 'Editing', 'Rules',
    'Results', 'Problems', 'Forms', 'Build', 'Debug', 'Status', 'Style', 'Undo', 'Updates', 'Files', 'Projects',
    'Commands', 'Signature', 'Documentation', 'Diagnostics', 'UnitSearch', 'Palette');
  Roles: array[0..19] of string = ('Page', 'Contract', 'Model', 'Window', 'Controller', 'Store', 'Parser', 'Writer',
    'Reader', 'Provider', 'Editor', 'Painter', 'Commands', 'State', 'Tests', 'Frame', 'Dialog', 'Adapter', 'Cache',
    'Composition');
  Typed: array[0..11] of string = ('s', 'se', 'set', 'sett', 'settp', 'settpa', 'settpag', 'settpage',
    '-t:test ', '-t:test s', '-t:test se', '-t:test settpage');
var
  Units: TAtlasUnitEntries;
  Index: Integer;
  Pattern: string;
  Watch: TStopwatch;
  Order: TArray<Integer>;
  Worst: Int64;
  Query, Previous: TAtlasUnitQuery;
  HasPrevious: Boolean;
  All: TAtlasUnitOrigins;
begin
  // Abnahme #777: unter 50 ms je Tastendruck bei 5000 Units (Filtern, Ordnen, Gruppen bilden).
  SetLength(Units, Count);
  // Namen wie in einer großen Projektgruppe: Bereich, Feature, Rolle (10 × 25 × 20 = 5000).
  for Index := 0 to Count - 1 do
  begin
    Units[Index].Name := Format('Atlas.%s.%s.%s', [Areas[Index mod 10], Features[(Index div 10) mod 25],
      Roles[Index div 250]]);
    Units[Index].FileName := Format('%s\Packages\P%d\Source\Feature%d\%s.pas',
      [Root, Index mod 7, Index mod 97, Units[Index].Name]);
    Units[Index].Project := Format('Atlas.IDE.P%d', [Index mod 7]);
    Units[Index].Projects := [Units[Index].Project];
    Units[Index].Origin := TAtlasUnitOrigin.Group;
    Units[Index].Kind := TAtlasUnitKind(Index mod 6);
  end;
  TAtlasUnitSearch.SortByName(Units);
  All := [Low(TAtlasUnitOrigin)..High(TAtlasUnitOrigin)];
  Worst := 0;
  HasPrevious := False;
  for Pattern in Typed do
  begin
    Watch := TStopwatch.StartNew;
    Query := TAtlasUnitQuery.Parse(Pattern, True);
    if HasPrevious and Query.Narrows(Previous) then
      Order := TAtlasUnitSearch.Order(Units, Query, All, [], Order)
    else
      Order := TAtlasUnitSearch.Order(Units, Query, All, []);
    Previous := Query;
    HasPrevious := True;
    TAtlasUnitSearch.Rows(Units, Order, TAtlasUnitGrouping.Folder, Root, 'Atlas.IDE.P1', nil, True);
    Worst := Max(Worst, Watch.ElapsedMilliseconds);
    Assert.IsTrue(Length(Order) > 0, Pattern);
  end;
  Assert.IsTrue(Worst < 50, Format('langsamster Tastendruck %d ms', [Worst]));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasUnitSearchTests);

end.
