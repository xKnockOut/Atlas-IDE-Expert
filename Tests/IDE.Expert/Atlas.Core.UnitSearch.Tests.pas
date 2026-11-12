unit Atlas.Core.UnitSearch.Tests;

// Tests für das Fenster „Units suchen“ (#777) ohne VCL: Filtersyntax,
// Rangfolge, Gruppierung, Pfadkürzung in der Mitte, Art und gemerkter Zustand.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  Atlas.Core.UnitSearch.Model,
  Atlas.Core.UnitSearch.Sections,
  Atlas.Core.UnitSearch.State;

type
  [TestFixture]
  [Category('Atlas.IDE.Search')]
  TAtlasUnitSearchTests = class
  private
    function Entries: TAtlasUnitEntries;
    function Names(const AEntries: TAtlasUnitEntries; const AOrder: TArray<Integer>): string;
    class function ManyUnits: TAtlasUnitEntries; static;
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
    /// <summary>#1310: Suchwörter passen auch als Teiltext der Caption eines Formulars, schwächer als der Name.
    /// </summary>
    [Test]
    procedure FindsFormsByCaption;
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
    /// <summary>Unbrauchbare Datei liegt danach als .defekt daneben; eine beim Lesen gesperrte wird nicht
    /// überschrieben.</summary>
    [Test]
    procedure BrokenFileSetAsideLockedFileKept;
    [Test]
    procedure FiveThousandUnitsPerKeystroke;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  System.Diagnostics,
  System.Math,
  Atlas.Core.Files.DataFile;

const
  cRoot = 'C:\Arbeit\Atlas-IDE-Expert-claude-project-thread-j9xhhv';
  cAnswer =
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
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(cAnswer);
  try
    Result := TAtlasUnitSearch.FromJson(mValue, 'Atlas.IDE.Expert', Path);
  finally
    mValue.Free;
  end;
end;

function TAtlasUnitSearchTests.Names(const AEntries: TAtlasUnitEntries; const AOrder: TArray<Integer>): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex in AOrder do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + AEntries[mIndex].Name;
  end;
end;

procedure TAtlasUnitSearchTests.ParsesFilterSyntax;
var
  mQuery: TAtlasUnitQuery;
begin
  mQuery := TAtlasUnitQuery.Parse('-t:test sett', True);
  Assert.AreEqual(1, Integer(Length(mQuery.Words)));
  Assert.AreEqual('sett', mQuery.Words[0]);
  Assert.IsTrue(TAtlasUnitKind.Test in mQuery.NotKinds);
  Assert.IsTrue(mQuery.Kinds = []);
  mQuery := TAtlasUnitQuery.Parse('p:ide  t:form|frame  -p:tests', True);
  Assert.IsFalse(mQuery.HasWords);
  Assert.AreEqual('ide', mQuery.Projects[0]);
  Assert.AreEqual('tests', mQuery.NotProjects[0]);
  Assert.IsTrue(mQuery.Kinds = [TAtlasUnitKind.Form, TAtlasUnitKind.Frame]);
  // Unvollständige oder unbekannte Filter bleiben Suchtext.
  mQuery := TAtlasUnitQuery.Parse('t: t:xyz p:', True);
  Assert.AreEqual(3, Integer(Length(mQuery.Words)));
  Assert.IsTrue(TAtlasUnitQuery.IsFilter('-t:dm'));
  Assert.IsTrue(TAtlasUnitQuery.IsFilter('T:INC'));
  Assert.IsFalse(TAtlasUnitQuery.IsFilter('x:inc'));
end;

procedure TAtlasUnitSearchTests.WithoutSyntaxEverythingIsText;
var
  mQuery: TAtlasUnitQuery;
begin
  mQuery := TAtlasUnitQuery.Parse('p:ide form', False);
  Assert.AreEqual(2, Integer(Length(mQuery.Words)));
  Assert.IsTrue(mQuery.Kinds = []);
  Assert.AreEqual(0, Integer(Length(mQuery.Projects)));
end;

procedure TAtlasUnitSearchTests.ReadsServerAnswer;
var
  mList: TAtlasUnitEntries;
  mValue: TJSONValue;
begin
  mList := Entries;
  Assert.AreEqual(9, Integer(Length(mList)));
  Assert.IsTrue(mList[0].Origin = TAtlasUnitOrigin.Group, 'anderes Projekt der Gruppe');
  Assert.IsTrue(mList[2].Origin = TAtlasUnitOrigin.Active);
  Assert.IsTrue(mList[6].Origin = TAtlasUnitOrigin.SearchPath);
  Assert.IsTrue(mList[7].Origin = TAtlasUnitOrigin.Library_);
  // Gehört die Unit auch zum aktiven Projekt, ist das ihr Projekt.
  Assert.AreEqual('Atlas.IDE.Expert', mList[5].Project);
  Assert.IsTrue(mList[5].Origin = TAtlasUnitOrigin.Active);
  Assert.AreEqual('Atlas.Tests', mList[4].Project);
  mValue := TJSONObject.ParseJSONValue(cAnswer);
  try
    Assert.AreEqual(3, Integer(Length(TAtlasUnitSearch.ProjectsFromJson(mValue))));
    // Ohne aktives Projekt zählen alle Projekte als aktiv.
    Assert.IsTrue(TAtlasUnitSearch.FromJson(mValue, '', Path)[0].Origin = TAtlasUnitOrigin.Active);
  finally
    mValue.Free;
  end;
  Assert.AreEqual(0, Integer(Length(TAtlasUnitSearch.FromJson(nil, '', Path))));
end;

procedure TAtlasUnitSearchTests.KindFromText;
var
  mKind: TAtlasUnitKind;
begin
  Assert.IsTrue(TAtlasUnitSearch.KindFromText('dm', mKind));
  Assert.IsTrue(mKind = TAtlasUnitKind.DataModule);
  Assert.IsTrue(TAtlasUnitSearch.KindFromText('DataModule', mKind));
  Assert.IsTrue(mKind = TAtlasUnitKind.DataModule);
  Assert.IsTrue(TAtlasUnitSearch.KindFromText('INC', mKind));
  Assert.IsTrue(mKind = TAtlasUnitKind.Include);
  Assert.IsFalse(TAtlasUnitSearch.KindFromText('formular', mKind));
  Assert.AreEqual('frame', TAtlasUnitSearch.KindText(TAtlasUnitKind.Frame));
end;

procedure TAtlasUnitSearchTests.FiltersByKindProjectAndOrigin;
var
  mList: TAtlasUnitEntries;
  mAll: TAtlasUnitOrigins;
begin
  mList := Entries;
  TAtlasUnitSearch.SortByName(mList);
  mAll := TAtlasUnitSearch.OriginsForScope('library');
  // Abnahme #777: "-t:test sett" blendet Tests aus.
  Assert.AreEqual('Atlas.Core.Settings.Plugin,Atlas.UI.Settings.Page',
    Names(mList, TAtlasUnitSearch.Order(mList, TAtlasUnitQuery.Parse('-t:test sett', True), mAll, [])));
  // "p:ide t:form" zeigt nur Formulare aus Atlas.IDE.Expert.
  Assert.AreEqual('Atlas.UI.Results.Frame',
    Names(mList, TAtlasUnitSearch.Order(mList, TAtlasUnitQuery.Parse('p:ide t:form', True), mAll, [])));
  // Chips: nur Tests, nur Projekt-Units.
  Assert.AreEqual('Atlas.Common.Dfm.BinaryForm.Tests,Atlas.Core.Settings.Tests',
    Names(mList, TAtlasUnitSearch.Order(mList, TAtlasUnitQuery.Parse('', True), mAll, [TAtlasUnitKind.Test])));
  Assert.AreEqual(3, Integer(Length(TAtlasUnitSearch.Order(mList, TAtlasUnitQuery.Parse('', True),
    [TAtlasUnitOrigin.Active], []))));
  Assert.AreEqual('Hilfe', Names(mList, TAtlasUnitSearch.Order(mList, TAtlasUnitQuery.Parse('hil', True),
    TAtlasUnitSearch.OriginsForScope('searchPath'), [])));
  Assert.AreEqual('', Names(mList, TAtlasUnitSearch.Order(mList, TAtlasUnitQuery.Parse('sysutils', True),
    TAtlasUnitSearch.OriginsForScope('searchPath'), [])));
end;

procedure TAtlasUnitSearchTests.RanksOpenThenActiveProject;
var
  mList: TAtlasUnitEntries;
  mOrder: TArray<Integer>;
  mIndex: Integer;
begin
  mList := Entries;
  TAtlasUnitSearch.SortByName(mList);
  // "Settings" trifft Page (aktives Projekt), Tests (andere) und Plugin (aktiv) gleich gut.
  mOrder := TAtlasUnitSearch.Order(mList, TAtlasUnitQuery.Parse('Settings', True),
    TAtlasUnitSearch.OriginsForScope('group'), []);
  Assert.AreEqual('Atlas.Core.Settings.Plugin,Atlas.UI.Settings.Page,Atlas.Core.Settings.Tests', Names(mList, mOrder));
  for mIndex := 0 to High(mList) do
  begin
    mList[mIndex].IsOpen := mList[mIndex].Name = 'Atlas.Core.Settings.Tests';
  end;
  mOrder := TAtlasUnitSearch.Order(mList, TAtlasUnitQuery.Parse('Settings', True),
    TAtlasUnitSearch.OriginsForScope('group'), []);
  Assert.AreEqual('Atlas.Core.Settings.Tests', mList[mOrder[0]].Name, 'offene Unit zuerst');
end;

procedure TAtlasUnitSearchTests.MatchesCamelCaseAndLastSegment;
begin
  Assert.IsTrue(TAtlasUnitSearch.Score('ACDB', 'Atlas.Common.Dfm.BinaryForm') > 0, 'Wortanfänge');
  Assert.IsTrue(TAtlasUnitSearch.Score('BinaryForm', 'Atlas.Common.Dfm.BinaryForm') >
    TAtlasUnitSearch.Score('BinaryForm', 'Atlas.Common.Dfm.BinaryForm.Tests'), 'letzter Teil genau');
  Assert.AreEqual(TAtlasUnitSearch.cScoreSubsequence, TAtlasUnitSearch.Score('acmbf', 'Atlas.Common.Dfm.BinaryForm'));
  Assert.IsTrue(TAtlasUnitSearch.Score('xyz', 'Atlas.Common.Dfm.BinaryForm') < 0);
end;

procedure TAtlasUnitSearchTests.FindsFormsByCaption;
const
  cCaptionAnswer =
    '{"units":[' +
    '{"name":"uKundeEdit","uri":"C:\\P\\uKundeEdit.pas","origin":"project","kind":"form","projects":["App"],' +
    '"caption":"Kunden bearbeiten"},' +
    '{"name":"Kunden.Liste","uri":"C:\\P\\Kunden.Liste.pas","origin":"project","kind":"unit","projects":["App"]},' +
    '{"name":"uHaupt","uri":"C:\\P\\uHaupt.pas","origin":"project","kind":"form","projects":["App"]}' +
    '],"projects":[{"name":"App"}],"count":3}';
var
  mValue: TJSONValue;
  mList: TAtlasUnitEntries;
  mAll: TAtlasUnitOrigins;
begin
  mValue := TJSONObject.ParseJSONValue(cCaptionAnswer);
  try
    mList := TAtlasUnitSearch.FromJson(mValue, 'App', Path);
  finally
    mValue.Free;
  end;
  TAtlasUnitSearch.SortByName(mList);
  mAll := TAtlasUnitSearch.OriginsForScope('library');
  Assert.AreEqual('Kunden bearbeiten', mList[2].Caption);
  // Nur über die Caption, ohne Rücksicht auf Groß- und Kleinschreibung.
  Assert.AreEqual('uKundeEdit', Names(mList, TAtlasUnitSearch.Order(mList, TAtlasUnitQuery.Parse('BEARBEITEN', True),
    mAll, [])));
  // Jedes Wort muss passen, gleich ob über Name oder Caption.
  Assert.AreEqual('uKundeEdit', Names(mList, TAtlasUnitSearch.Order(mList, TAtlasUnitQuery.Parse('edit bearb', True),
    mAll, [])));
  // Treffer im Namen vor Treffern nur über die Caption.
  Assert.AreEqual('Kunden.Liste,uKundeEdit', Names(mList, TAtlasUnitSearch.Order(mList,
    TAtlasUnitQuery.Parse('kunden', True), mAll, [])));
  Assert.AreEqual('', Names(mList, TAtlasUnitSearch.Order(mList, TAtlasUnitQuery.Parse('rechnung', True), mAll, [])));
  // Ohne Captions in der Antwort (Einstellung aus) fragt die Suche sie gar nicht ab.
  Assert.AreEqual('[]', TAtlasUnitSearch.UnitsArguments(False));
  Assert.AreEqual('[{"captions":true}]', TAtlasUnitSearch.UnitsArguments(True));
end;

procedure TAtlasUnitSearchTests.GroupsByProjectWithCounts;
var
  mList: TAtlasUnitEntries;
  mOrder: TArray<Integer>;
  mRows: TAtlasUnitRows;
begin
  mList := Entries;
  mOrder := TAtlasUnitSearch.Order(mList, TAtlasUnitQuery.Parse('', True), TAtlasUnitSearch.OriginsForScope('group'), []);
  mRows := TAtlasUnitSearch.Rows(mList, mOrder,
    TAtlasUnitLayout.Create(TAtlasUnitGrouping.Project, cRoot, 'Atlas.IDE.Expert', nil, False));
  // Aktives Projekt oben, dann alphabetisch.
  Assert.IsTrue(mRows[0].IsGroup);
  Assert.AreEqual('Atlas.IDE.Expert', mRows[0].Group);
  Assert.AreEqual(3, Integer(mRows[0].Count));
  Assert.AreEqual(3 + 1 + 2 + 1 + 2 + 1, Integer(Length(mRows)));
  Assert.AreEqual('Atlas.Common', mRows[4].Group);
  Assert.AreEqual(2, Integer(mRows[4].Count), 'BinaryForm und Optionen.inc');
  // Eingeklappt: nur der Kopf.
  mRows := TAtlasUnitSearch.Rows(mList, mOrder,
    TAtlasUnitLayout.Create(TAtlasUnitGrouping.Project, cRoot, 'Atlas.IDE.Expert', ['atlas.common'], False));
  Assert.AreEqual(3 + 1 + 1 + 2 + 1, Integer(Length(mRows)));
  Assert.IsTrue(mRows[4].Collapsed);
  Assert.AreEqual(2, Integer(mRows[4].Count));
  // Ohne Gruppierung keine Köpfe.
  mRows := TAtlasUnitSearch.Rows(mList, mOrder,
    TAtlasUnitLayout.Create(TAtlasUnitGrouping.None, cRoot, '', nil, False));
  Assert.AreEqual(Integer(Length(mOrder)), Integer(Length(mRows)));
  Assert.IsFalse(mRows[0].IsGroup);
end;

procedure TAtlasUnitSearchTests.GroupsByFolderBestFirstWhenSearching;
var
  mList: TAtlasUnitEntries;
  mOrder: TArray<Integer>;
  mRows: TAtlasUnitRows;
begin
  mList := Entries;
  mOrder := TAtlasUnitSearch.Order(mList, TAtlasUnitQuery.Parse('settingstests', True),
    TAtlasUnitSearch.OriginsForScope('group'), []);
  mRows := TAtlasUnitSearch.Rows(mList, mOrder,
    TAtlasUnitLayout.Create(TAtlasUnitGrouping.Folder, cRoot, 'Atlas.IDE.Expert', nil, True));
  Assert.AreEqual('Tests\IDE.Expert', mRows[0].Group);
  Assert.AreEqual('Packages\Atlas.IDE.Expert\Source\Core\Settings',
    TAtlasUnitSearch.GroupOf(mList[5], TAtlasUnitGrouping.Folder, cRoot));
  Assert.AreEqual('', TAtlasUnitSearch.GroupOf(mList[8], TAtlasUnitGrouping.Folder, cRoot), 'Datei in der Wurzel');
end;

procedure TAtlasUnitSearchTests.ShortensPathInTheMiddle;
var
  mFileName: string;
begin
  Assert.AreEqual('abcdef', TAtlasUnitSearch.MiddleEllipsis('abcdef', 6));
  Assert.AreEqual('ab…fg', TAtlasUnitSearch.MiddleEllipsis('abcdefg', 5));
  Assert.AreEqual('a…g', TAtlasUnitSearch.MiddleEllipsis('abcdefg', 3));
  Assert.AreEqual(10, Integer(Length(TAtlasUnitSearch.MiddleEllipsis('Packages\Atlas.Common\Source\Dfm\X.pas', 10))));
  mFileName := cRoot + '\Packages\Atlas.Common\Source\Dfm\Atlas.Common.Dfm.BinaryForm.pas';
  Assert.AreEqual('Packages\Atlas.Common\Source\Dfm\Atlas.Common.Dfm.BinaryForm.pas',
    TAtlasUnitSearch.DisplayPath(mFileName, cRoot, TAtlasUnitPathStyle.Relative, 20));
  Assert.IsTrue(TAtlasUnitSearch.DisplayPath(mFileName, cRoot, TAtlasUnitPathStyle.Compact, 30).EndsWith('BinaryForm.pas'));
  Assert.AreEqual(30, Integer(Length(TAtlasUnitSearch.DisplayPath(mFileName, cRoot, TAtlasUnitPathStyle.Compact, 30))));
  Assert.AreEqual(mFileName, TAtlasUnitSearch.DisplayPath(mFileName, cRoot, TAtlasUnitPathStyle.Absolute, 30));
  Assert.AreEqual('C:\Lib\Hilfe.pas', TAtlasUnitSearch.DisplayPath('C:\Lib\Hilfe.pas', cRoot,
    TAtlasUnitPathStyle.Relative, 0), 'außerhalb absolut');
  Assert.AreEqual('C:\P', TAtlasUnitSearch.CommonRoot(['C:\P\A\x.pas', 'C:\P\B\y.pas', 'C:\P\z.pas']));
  Assert.AreEqual('', TAtlasUnitSearch.CommonRoot(['C:\P\x.pas', 'D:\Q\y.pas']));
end;

procedure TAtlasUnitSearchTests.DistinguishesFormAndTests;
var
  mList: TAtlasUnitEntries;
  mOrder: TArray<Integer>;
  mFirst, mSecond: string;
begin
  // Abnahme #777: lange Ordnernamen schneiden den unterscheidenden Teil nicht ab.
  mList := Entries;
  mOrder := TAtlasUnitSearch.Order(mList, TAtlasUnitQuery.Parse('BinaryForm', True),
    TAtlasUnitSearch.OriginsForScope('group'), []);
  Assert.AreEqual(2, Integer(Length(mOrder)));
  mFirst := TAtlasUnitSearch.DisplayPath(mList[mOrder[0]].FileName, cRoot, TAtlasUnitPathStyle.Compact, 40);
  mSecond := TAtlasUnitSearch.DisplayPath(mList[mOrder[1]].FileName, cRoot, TAtlasUnitPathStyle.Compact, 40);
  Assert.AreNotEqual(mFirst, mSecond);
  Assert.IsFalse(mFirst.Contains('j9xhhv'), 'relativ ab der Projektgruppe');
  Assert.IsTrue(mList[mOrder[0]].Kind <> mList[mOrder[1]].Kind);
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
  mValue: TJSONValue;
  mPreview: TAtlasUnitPreview;
begin
  mValue := TJSONObject.ParseJSONValue('{"uri":"C:\\P\\Haupt.pas","header":"Kopf","lines":120,' +
    '"modified":"2026-10-15T08:30:00.000Z","git":"modified","types":[{"name":"THaupt","kind":"class"}],' +
    '"typeCount":24,"uses":["Kunden","Basis"],"usedBy":3,"usedByUnits":["A","B","C"],"form":{"class":"THaupt","caption":"Kunden","width":400,"height":300,' +
    '"items":[["Kopf","TPanel","",0,0,400,40,1]]}}');
  try
    mPreview := TAtlasUnitPreview.FromJson(mValue, Path);
  finally
    mValue.Free;
  end;
  Assert.AreEqual('C:\P\Haupt.pas', mPreview.FileName);
  Assert.AreEqual('Kopf', mPreview.Header);
  Assert.AreEqual(120, mPreview.Lines);
  Assert.IsTrue(mPreview.Modified > 0);
  Assert.AreEqual('modified', mPreview.Git);
  Assert.AreEqual('THaupt', mPreview.Types[0].Name);
  Assert.AreEqual(24, mPreview.TypeCount);
  Assert.AreEqual('Kunden,Basis', string.Join(',', mPreview.Uses_));
  Assert.AreEqual(3, mPreview.UsedBy);
  Assert.AreEqual(3, Integer(Length(mPreview.UsedByUnits)));
  Assert.IsTrue(mPreview.HasForm);
  Assert.AreEqual(400, mPreview.FormWidth);
  Assert.AreEqual('TPanel', mPreview.FormItems[0].TypeName);
  Assert.AreEqual(40, mPreview.FormItems[0].Height);
  mPreview := TAtlasUnitPreview.FromJson(nil, Path);
  Assert.AreEqual(-1, mPreview.UsedBy);
  Assert.IsFalse(mPreview.HasForm);
end;

procedure TAtlasUnitSearchTests.StateRoundTrip;
var
  mState, mLoaded: TAtlasUnitSearchState;
  mOrigins: TAtlasUnitOrigins;
  mKinds: TAtlasUnitKinds;
begin
  mState := TAtlasUnitSearchState.Create;
  mLoaded := TAtlasUnitSearchState.Create;
  try
    Assert.IsFalse(mState.Filters('C:\P\Gruppe.groupproj', mOrigins, mKinds));
    mState.SetCollapsed('C:\P\Gruppe.groupproj', TAtlasUnitGrouping.Project, ['Atlas.Common', 'atlas.tests']);
    mState.SetCollapsed('C:\P\Gruppe.groupproj', TAtlasUnitGrouping.Folder, ['Tests']);
    mState.SetFilters('C:\P\Gruppe.groupproj', [TAtlasUnitOrigin.Active, TAtlasUnitOrigin.Library_],
      [TAtlasUnitKind.Form]);
    mState.Left := 10;
    mState.Width := 900;
    mState.PreviewWidth := 320;
    mState.PreviewVisible := False;
    mState.Sections[TAtlasPreviewSection.Types] := TAtlasSectionChoice.HandClosed;
    Assert.IsTrue(mLoaded.LoadJson(mState.ToJson));
    Assert.IsTrue(mLoaded.Sections[TAtlasPreviewSection.Types] = TAtlasSectionChoice.Auto,
      'Abschnitte gelten nur für die Sitzung (#876)');
    Assert.AreEqual(2, Integer(Length(mLoaded.Collapsed('c:\p\gruppe.groupproj', TAtlasUnitGrouping.Project))));
    Assert.AreEqual('atlas.common', mLoaded.Collapsed('C:\P\Gruppe.groupproj', TAtlasUnitGrouping.Project)[0]);
    Assert.AreEqual('tests', mLoaded.Collapsed('C:\P\Gruppe.groupproj', TAtlasUnitGrouping.Folder)[0]);
    Assert.IsTrue(mLoaded.Filters('C:\P\Gruppe.groupproj', mOrigins, mKinds));
    Assert.IsTrue(mOrigins = [TAtlasUnitOrigin.Active, TAtlasUnitOrigin.Library_]);
    Assert.IsTrue(mKinds = [TAtlasUnitKind.Form]);
    Assert.AreEqual(10, mLoaded.Left);
    Assert.AreEqual(900, mLoaded.Width);
    Assert.AreEqual(320, mLoaded.PreviewWidth);
    Assert.IsFalse(mLoaded.PreviewVisible);
    // Neu setzen ersetzt nur die eigene Gruppierung.
    mLoaded.SetCollapsed('C:\P\Gruppe.groupproj', TAtlasUnitGrouping.Project, nil);
    Assert.AreEqual(0, Integer(Length(mLoaded.Collapsed('C:\P\Gruppe.groupproj', TAtlasUnitGrouping.Project))));
    Assert.AreEqual(1, Integer(Length(mLoaded.Collapsed('C:\P\Gruppe.groupproj', TAtlasUnitGrouping.Folder))));
    Assert.IsFalse(mLoaded.LoadJson('kein json'));
    Assert.AreEqual(0, mLoaded.Width);
    Assert.IsTrue(mLoaded.PreviewVisible);
  finally
    mLoaded.Free;
    mState.Free;
  end;
end;

/// <summary>Namen wie in einer großen Projektgruppe: Bereich, Feature, Rolle (10 × 25 × 20 = 5000).</summary>
class function TAtlasUnitSearchTests.ManyUnits: TAtlasUnitEntries;
const
  cCount = 5000;
  cAreas: array[0..9] of string = ('Common', 'Windows', 'Core', 'UI', 'IDE', 'Server', 'Setup', 'Tests', 'Tools',
    'Shell');
  cFeatures: array[0..24] of string = ('Settings', 'Completion', 'Hover', 'Index', 'Lsp', 'Dfm', 'Editing', 'Rules',
    'Results', 'Problems', 'Forms', 'Build', 'Debug', 'Status', 'Style', 'Undo', 'Updates', 'Files', 'Projects',
    'Commands', 'Signature', 'Documentation', 'Diagnostics', 'UnitSearch', 'Palette');
  cRoles: array[0..19] of string = ('Page', 'Contract', 'Model', 'Window', 'Controller', 'Store', 'Parser', 'Writer',
    'Reader', 'Provider', 'Editor', 'Painter', 'Commands', 'State', 'Tests', 'Frame', 'Dialog', 'Adapter', 'Cache',
    'Composition');
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, cCount);
  for mIndex := 0 to cCount - 1 do
  begin
    Result[mIndex].Name := Format('Atlas.%s.%s.%s', [cAreas[mIndex mod 10], cFeatures[(mIndex div 10) mod 25],
      cRoles[mIndex div 250]]);
    Result[mIndex].FileName := Format('%s\Packages\P%d\Source\Feature%d\%s.pas',
      [cRoot, mIndex mod 7, mIndex mod 97, Result[mIndex].Name]);
    Result[mIndex].Project := Format('Atlas.IDE.P%d', [mIndex mod 7]);
    Result[mIndex].Projects := [Result[mIndex].Project];
    Result[mIndex].Origin := TAtlasUnitOrigin.Group;
    Result[mIndex].Kind := TAtlasUnitKind(mIndex mod 6);
  end;
end;

procedure TAtlasUnitSearchTests.FiveThousandUnitsPerKeystroke;
const
  // Tastendruck für Tastendruck wie im Fenster; „-t:test “ wird beim Leerzeichen zum Filter.
  cTyped: array[0..11] of string = ('s', 'se', 'set', 'sett', 'settp', 'settpa', 'settpag', 'settpage',
    '-t:test ', '-t:test s', '-t:test se', '-t:test settpage');
var
  mUnits: TAtlasUnitEntries;
  mPattern: string;
  mWatch: TStopwatch;
  mOrder: TArray<Integer>;
  mWorst: Int64;
  mQuery, mPrevious: TAtlasUnitQuery;
  mHasPrevious: Boolean;
  mAll: TAtlasUnitOrigins;
begin
  // Abnahme #777: unter 50 ms je Tastendruck bei 5000 Units (Filtern, Ordnen, Gruppen bilden).
  mUnits := ManyUnits;
  TAtlasUnitSearch.SortByName(mUnits);
  mAll := [Low(TAtlasUnitOrigin)..High(TAtlasUnitOrigin)];
  mWorst := 0;
  mHasPrevious := False;
  for mPattern in cTyped do
  begin
    mWatch := TStopwatch.StartNew;
    mQuery := TAtlasUnitQuery.Parse(mPattern, True);
    if mHasPrevious and mQuery.Narrows(mPrevious) then
    begin
      mOrder := TAtlasUnitSearch.Order(mUnits, mQuery, mAll, [], mOrder);
    end
    else
    begin
      mOrder := TAtlasUnitSearch.Order(mUnits, mQuery, mAll, []);
    end;
    mPrevious := mQuery;
    mHasPrevious := True;
    TAtlasUnitSearch.Rows(mUnits, mOrder,
      TAtlasUnitLayout.Create(TAtlasUnitGrouping.Folder, cRoot, 'Atlas.IDE.P1', nil, True));
    mWorst := Max(mWorst, mWatch.ElapsedMilliseconds);
    Assert.IsTrue(Length(mOrder) > 0, mPattern);
  end;
  Assert.IsTrue(mWorst < 50, Format('langsamster Tastendruck %d ms', [mWorst]));
end;

procedure TAtlasUnitSearchTests.BrokenFileSetAsideLockedFileKept;
var
  mState: TAtlasUnitSearchState;
  mFileName: string;
  mLock: TFileStream;
begin
  mFileName := TPath.Combine(TPath.GetTempPath, 'atlas-unitsearch-' + IntToStr(Random(MaxInt)) + '.json');
  mState := TAtlasUnitSearchState.Create;
  try
    TFile.WriteAllText(mFileName, '[1, 2]');
    Assert.IsTrue(mState.LoadFromFile(mFileName) = TAtlasDataLoad.Renewed);
    Assert.IsTrue(TFile.Exists(mFileName + TAtlasDataFile.cDefectExtension), 'beiseitegelegt');
    mState.Width := 937;
    Assert.IsTrue(mState.SaveToFile(mFileName));
    mLock := TFileStream.Create(mFileName, fmOpenRead or fmShareExclusive);
    try
      Assert.IsTrue(mState.LoadFromFile(mFileName) = TAtlasDataLoad.Kept);
    finally
      mLock.Free;
    end;
    Assert.AreEqual(0, mState.Width);
    mState.Width := 400;
    Assert.IsFalse(mState.SaveToFile(mFileName), 'beim Lesen gesperrt: nicht überschreiben');
    Assert.Contains(TFile.ReadAllText(mFileName, TEncoding.UTF8), '937');
  finally
    mState.Free;
    System.SysUtils.DeleteFile(mFileName);
    System.SysUtils.DeleteFile(mFileName + TAtlasDataFile.cDefectExtension);
  end;
  // Gemeldete Datendateien vergessen: Das Register bliebe sonst als Leck stehen.
  TAtlasDataFile.ForgetReports;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasUnitSearchTests);

end.
