unit Atlas.Core.Architecture.Model.Tests;

// Fenster „Atlas-Architektur“ (#1118), Kern: Antwort des Servers lesen
// (dieselben Daten wie TArchitectureReport.Json), Sortieren, Filter, Pfade,
// Farben und Umrechnung der Karte; Vergleich mit einem gespeicherten Stand
// (#1121) und die Argumente dazu; Feinheit der Teilsysteme (#1366): Regler,
// settings.json, Argumente und Hinweis im Vergleich; Zuordnung der Units
// (#1368).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasArchitectureModelTests = class
  public
    [Test]
    procedure ParsesServerAnswer;
    [Test]
    procedure DisabledAndBrokenAnswers;
    [Test]
    procedure SortsStableAndFilters;
    [Test]
    procedure FullPathAndCyclePath;
    [Test]
    procedure PaletteAndDarkness;
    [Test]
    procedure ViewFitsZoomsAndHits;
    [Test]
    procedure CommandArguments;
    [Test]
    procedure ShortestPathOverUses;
    [Test]
    procedure ParsesComparison;
    [Test]
    procedure ComparisonErrorAndAbsence;
    [Test]
    procedure CommandArgumentsWithComparison;
    [Test]
    procedure RouteOfSymbolPath;
    [Test]
    procedure ResolutionScaleIsLogarithmic;
    [Test]
    procedure GroupingSettingsReadAndWrite;
    [Test]
    procedure ParsesResolution;
    [Test]
    procedure CommandArgumentsWithResolution;
    [Test]
    procedure ParsesSplitSubsystems;
    [Test]
    procedure PaletteShades;
    [Test]
    procedure ParsesFoundation;
    [Test]
    procedure ParsesAssignment;
    [Test]
    procedure AssignmentWithFoundationAndBrokenRows;
  end;

/// <summary>Antwort von atlas.architecture zu einem kleinen Projekt mit Zyklus (für Kern- und UI-Tests).</summary>
function SampleAnswer: string;
/// <summary>Wie SampleAnswer mit Vergleich (#1121): Im alten Stand gab es App.Old, aber weder den Zyklus
/// Db ↔ Cache noch App.Ui.Grid → App.Data.</summary>
function SampleComparisonAnswer: string;
/// <summary>Wie SampleComparisonAnswer, der aktuelle Stand aber mit Feinheit γ = 2 gerechnet (#1366).</summary>
function SampleResolutionAnswer: string;
/// <summary>Drei Teilsysteme Core, Data, Ui; das erste und das letzte als Teile des nachgeteilten „App“ (#1364).
/// </summary>
function SampleSplitAnswer: string;
/// <summary>Wie SampleSplitAnswer ohne Teile; das erste Teilsystem ist das „Fundament“ (#1365).</summary>
function SampleFoundationAnswer: string;
/// <summary>Zuordnung (#1368): Z.Own.Mid mit 8 gewichteten Kanten zu Own und 6 zu Oth, knapp.</summary>
function SampleAssignmentAnswer: string;
/// <summary>Zuordnung mit Teilsystem „Fundament“ (#1365, #1368), ohne Nachteilung.</summary>
function SampleAssignmentFoundationAnswer: string;

implementation

uses
  System.SysUtils,
  System.Math,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Architecture.Overview,
  Atlas.Common.Architecture.Service,
  Atlas.Common.Architecture.Layout,
  Atlas.Common.Architecture.Report,
  Atlas.Common.Architecture.Snapshot,
  Atlas.Common.Architecture.Comparison,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Architecture.UsesGraph.Tests,
  Atlas.Common.Architecture.Snapshot.Tests,
  Atlas.Common.Architecture.Overview.Tests,
  Atlas.Core.Architecture.Model;

/// <summary>Kleines Projekt; AOlder: der frühere Stand (siehe SampleComparisonAnswer).</summary>
function SampleOverview(AOlder: Boolean): TArchitectureOverview; overload; forward;

/// <summary>Wie oben mit Feinheit AResolution (#1366).</summary>
function SampleOverview(AOlder: Boolean; AResolution: Double): TArchitectureOverview; overload;
var
  mOverview: TArchitectureOverview;
begin
  mOverview := SampleOverview(AOlder);
  mOverview.Grouping.Resolution := AResolution;
  Result := mOverview;
end;

function SampleOverview(AOlder: Boolean): TArchitectureOverview;
var
  Index: ISymbolIndex;
  Service: TArchitectureService;
  Request: TArchitectureRequest;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(UsesUnit('App.Main', ['App.Data', 'App.Ui.Form'], nil));
  Index.AddUnit(UsesUnit('App.Data', ['App.Data.Db'], nil));
  Index.AddUnit(UsesUnit('App.Data.Db', ['App.Data.Cache'], nil));
  Index.AddUnit(UsesUnit('App.Ui.Form', ['App.Ui.Grid'], nil));
  if AOlder then
  begin
    Index.AddUnit(UsesUnit('App.Data.Cache', nil, nil));
    Index.AddUnit(UsesUnit('App.Ui.Grid', nil, nil));
    Index.AddUnit(UsesUnit('App.Old', ['App.Data'], nil));
  end
  else
  begin
    Index.AddUnit(UsesUnit('App.Data.Cache', nil, ['App.Data.Db']));
    Index.AddUnit(UsesUnit('App.Ui.Grid', ['App.Data'], nil));
  end;
  Service := TArchitectureService.Create(Index,
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := '';
      Result := False;
    end,
    function(const AFileName: string): TArray<string>
    begin
      Result := nil;
    end);
  try
    Request := Default(TArchitectureRequest);
    Request.Title := 'App';
    Request.Root := 'C:\Projekt';
    Request.Scope := 'project';
    Request.CentralUnits := 3;
    Request.Exclude := ['Tests/**'];
    Result := Service.Overview(Request);
  finally
    Service.Free;
  end;
end;

function AnswerOf(const AOverview: TArchitectureOverview; const AExtra: string): string;
begin
  Result := '{"enabled":true,"root":"C:\\Projekt","format":"json","data":' +
    TArchitectureReport.Json(AOverview, TArchitectureLayouter.Compute(AOverview)) + AExtra + '}';
end;

function SampleAnswer: string;
begin
  Result := AnswerOf(SampleOverview(False), '');
end;

function SampleComparisonAnswer: string;
var
  Current: TArchitectureOverview;
  Comparison: TArchitectureComparison;
begin
  Current := SampleOverview(False);
  Comparison := TArchitectureComparer.Compare(TArchitectureSnapshots.FromOverview(SampleOverview(True)),
    TArchitectureSnapshots.FromOverview(Current));
  Result := AnswerOf(Current, ',"baseline":"C:\\Projekt\\stand.json","comparison":' +
    TArchitectureComparer.Json(Comparison, TArchitectureComparer.DefaultFailOn));
end;

function SampleResolutionAnswer: string;
var
  mCurrent: TArchitectureOverview;
  mComparison: TArchitectureComparison;
begin
  mCurrent := SampleOverview(False, 2);
  mComparison := TArchitectureComparer.Compare(TArchitectureSnapshots.FromOverview(SampleOverview(True)),
    TArchitectureSnapshots.FromOverview(mCurrent));
  Result := AnswerOf(mCurrent, ',"baseline":"C:\\Projekt\\stand.json","comparison":' +
    TArchitectureComparer.Json(mComparison, TArchitectureComparer.DefaultFailOn));
end;

function SampleSplitAnswer: string;
var
  mOverview: TArchitectureOverview;
  mLast: Integer;
begin
  mOverview := ArchitectureOverviewOf(ArchitectureSampleUnits);
  mLast := High(mOverview.Subsystems);
  mOverview.Subsystems[0].Parent := 'App';
  mOverview.Subsystems[mLast].Parent := 'App';
  mOverview.Subsystems[mLast].ColorSlot := 0;
  mOverview.Subsystems[mLast].Shade := 1;
  Result := AnswerOf(mOverview, '');
end;

function SampleFoundationAnswer: string;
var
  mOverview: TArchitectureOverview;
begin
  mOverview := ArchitectureOverviewOf(ArchitectureSampleUnits);
  mOverview.Subsystems[0].Name := TArchitectureAnalyzer.FoundationName;
  mOverview.Subsystems[0].Foundation := True;
  mOverview.Subsystems[0].ColorSlot := -1;
  Result := AnswerOf(mOverview, '');
end;

function AssignmentAnswerOf(const AUnits: TArray<TUnitIndex>; const AGrouping: TArchitectureGrouping): string;
var
  mGraph: TUsesGraph;
  mOverview: TArchitectureOverview;
begin
  mGraph := TUsesGraph.Create(AUnits, TUsesGraphOptions.Default);
  try
    mOverview := TArchitectureAnalyzer.Analyze(mGraph, nil, 5, AGrouping);
  finally
    mGraph.Free;
  end;
  mOverview.Title := 'Zuordnung';
  Result := AnswerOf(mOverview, '');
end;

function SampleAssignmentAnswer: string;
begin
  Result := AssignmentAnswerOf(AssignmentProject, TArchitectureGrouping.Default);
end;

function SampleAssignmentFoundationAnswer: string;
var
  mGrouping: TArchitectureGrouping;
begin
  mGrouping := TArchitectureGrouping.Default;
  mGrouping.MaxShare := 0;
  mGrouping.MinCohesion := 0;
  Result := AssignmentAnswerOf(FoundationProject, mGrouping);
end;

{ TAtlasArchitectureModelTests }

procedure TAtlasArchitectureModelTests.ParsesAssignment;
var
  mModel: TAtlasArchitectureModel;
  mEnabled: Boolean;
  mMid: Integer;
  mUnit: TAtlasArchUnit;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleAssignmentAnswer, mModel, mEnabled));
  Assert.IsTrue(mModel.HasAssignment);
  Assert.StartsWith('Atlas bildet die Teilsysteme', mModel.Explanation);
  Assert.AreEqual(Double(0.25), mModel.MaxShare, 1E-9);
  Assert.AreEqual(Double(0.3), mModel.MinCohesion, 1E-9);
  Assert.AreEqual('separate', mModel.Foundations);
  mMid := mModel.IndexOf('Z.Own.Mid');
  mUnit := mModel.Units[mMid];
  Assert.AreEqual(2, Integer(Length(mUnit.Assignment)));
  Assert.AreEqual(0, mModel.OwnRow(mMid));
  Assert.AreEqual(1, mModel.RivalRow(mMid));
  Assert.AreEqual(mUnit.Subsystem, mUnit.Assignment[0].Subsystem);
  Assert.AreEqual(3, mUnit.Assignment[0].Interfaces);
  Assert.AreEqual(2, mUnit.Assignment[0].Implementations);
  Assert.AreEqual(8, mUnit.Assignment[0].Sum);
  Assert.AreEqual('Oth', mModel.SubsystemName(mUnit.Assignment[1].Subsystem));
  Assert.AreEqual(6, mUnit.Assignment[1].Sum);
  Assert.IsTrue(mUnit.Assignment[1].Counts);
  Assert.IsTrue(mUnit.Close);
  Assert.AreEqual(3, mUnit.Missing);
  Assert.IsFalse(mModel.Units[mModel.IndexOf('Z.Own.U1')].Close);
  Assert.AreEqual(-1, mModel.RivalRow(mModel.IndexOf('Z.Own.U1')));
  Assert.AreEqual(-1, mModel.OwnRow(-1));
  // Ohne explainAssignment (wie SampleAnswer aus einer Anfrage ohne den Schalter): nichts.
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleAnswer, mModel, mEnabled));
  Assert.IsFalse(mModel.HasAssignment);
  Assert.AreEqual('', mModel.Explanation);
end;

procedure TAtlasArchitectureModelTests.AssignmentWithFoundationAndBrokenRows;
var
  mModel: TAtlasArchitectureModel;
  mEnabled: Boolean;
  mU2: Integer;
  mRow: TAtlasArchAssignmentRow;
  mFound: Boolean;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleAssignmentFoundationAnswer, mModel, mEnabled));
  Assert.AreEqual(Double(0), mModel.MaxShare, 1E-9);
  Assert.AreEqual(Double(0), mModel.MinCohesion, 1E-9);
  mU2 := mModel.IndexOf('App.Ui.U2');
  mFound := False;
  for mRow in mModel.Units[mU2].Assignment do
    if mModel.Subsystems[mRow.Subsystem].Foundation then
    begin
      mFound := True;
      Assert.IsFalse(mRow.Counts);
    end;
  Assert.IsTrue(mFound);
  Assert.AreEqual(-1, mModel.RivalRow(mU2));
  // Teilsystem außerhalb und falscher Aufbau: Antwort ungültig.
  Assert.IsFalse(TAtlasArchitectureModel.Parse(StringReplace(SampleAssignmentAnswer, '"assignment":[[',
    '"assignment":[[99,0,0],[', []), mModel, mEnabled));
  Assert.IsFalse(TAtlasArchitectureModel.Parse(StringReplace(SampleAssignmentAnswer, '"assignment":[[',
    '"assignment":[["a",0,0],[', []), mModel, mEnabled));
  Assert.IsFalse(TAtlasArchitectureModel.Parse(StringReplace(SampleAssignmentAnswer, '"assignment":[[',
    '"assignment":[[0,0],[', []), mModel, mEnabled));
end;

procedure TAtlasArchitectureModelTests.ParsesServerAnswer;
var
  Model: TAtlasArchitectureModel;
  Enabled: Boolean;
  Db: Integer;
  Subsystem: TAtlasArchSubsystem;
  Count: Integer;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleAnswer, Model, Enabled));
  Assert.IsTrue(Enabled);
  Assert.AreEqual('App', Model.Title);
  Assert.AreEqual('C:\Projekt', Model.Root);
  Assert.AreEqual('project', Model.Scope);
  Assert.AreEqual(1, Integer(Length(Model.Excludes)));
  Assert.AreEqual('Tests/**', Model.Excludes[0]);
  Assert.AreEqual(6, Integer(Length(Model.Units)));
  Assert.AreEqual(3, Integer(Length(Model.Central)));
  Assert.AreEqual(Integer(Length(Model.Edges)), Model.EdgeCount);
  Assert.AreEqual(1, Integer(Length(Model.Cycles)));
  Db := Model.IndexOf('app.data.db');
  Assert.IsTrue(Db >= 0);
  Assert.IsTrue(Model.Units[Db].OnCycle);
  Assert.IsFalse(Model.Units[Model.IndexOf('App.Main')].OnCycle);
  Assert.AreEqual('App/Data/Db.pas', Model.Units[Db].FileName);
  Assert.IsTrue(Length(Model.Cycles[0].Edges) >= 2);
  Count := 0;
  for Subsystem in Model.Subsystems do
  begin
    Inc(Count, Length(Subsystem.Units));
    Assert.IsTrue(Subsystem.R > 0, 'Kreis der Karte');
  end;
  Assert.AreEqual(6, Count, 'jede Unit in genau einem Teilsystem');
  Assert.AreEqual(Model.Units[Db].Outlier, Model.OutlierOf(Db) >= 0);
end;

procedure TAtlasArchitectureModelTests.DisabledAndBrokenAnswers;
var
  Model: TAtlasArchitectureModel;
  Enabled: Boolean;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse('{"enabled":false}', Model, Enabled));
  Assert.IsFalse(Enabled);
  Assert.AreEqual(0, Integer(Length(Model.Units)));
  Assert.IsFalse(TAtlasArchitectureModel.Parse('', Model, Enabled));
  Assert.IsFalse(TAtlasArchitectureModel.Parse('[]', Model, Enabled));
  Assert.IsFalse(TAtlasArchitectureModel.Parse('{"enabled":true,"data":{"format":2}}', Model, Enabled),
    'fremdes Format');
  // Verweis auf eine Unit, die es nicht gibt: lieber nichts zeigen als abstürzen.
  Assert.IsFalse(TAtlasArchitectureModel.Parse('{"enabled":true,"data":{"format":1,"units":[],' +
    '"edges":[[0,1,"i"]],"subsystems":[]}}', Model, Enabled));
  Assert.AreEqual(0, Integer(Length(Model.Edges)));
end;

procedure TAtlasArchitectureModelTests.SortsStableAndFilters;
var
  Model: TAtlasArchitectureModel;
  Enabled: Boolean;
  All, Sorted: TArray<Integer>;
  Index: Integer;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleAnswer, Model, Enabled));
  All := nil;
  for Index := 0 to High(Model.Units) do
    All := All + [Index];
  Sorted := Model.Sorted(All, TAtlasArchColumn.Name, False);
  for Index := 1 to High(Sorted) do
    Assert.IsTrue(CompareText(Model.Units[Sorted[Index - 1]].Name, Model.Units[Sorted[Index]].Name) < 0);
  Sorted := Model.Sorted(All, TAtlasArchColumn.Name, True);
  Assert.AreEqual('App.Ui.Grid', Model.Units[Sorted[0]].Name);
  Sorted := Model.Sorted(All, TAtlasArchColumn.Total, True);
  for Index := 1 to High(Sorted) do
  begin
    Assert.IsTrue(Model.Units[Sorted[Index - 1]].Total >= Model.Units[Sorted[Index]].Total);
    // Gleichstand: nach Name aufsteigend, auch absteigend sortiert.
    if Model.Units[Sorted[Index - 1]].Total = Model.Units[Sorted[Index]].Total then
      Assert.IsTrue(CompareText(Model.Units[Sorted[Index - 1]].Name, Model.Units[Sorted[Index]].Name) < 0);
  end;
  Assert.IsTrue(Model.Matches(Model.IndexOf('App.Data.Db'), 'data db'));
  Assert.IsFalse(Model.Matches(Model.IndexOf('App.Data.Db'), 'data ui'));
  Assert.IsTrue(Model.Matches(0, ''));
  Assert.IsFalse(Model.Matches(99, ''));
end;

procedure TAtlasArchitectureModelTests.FullPathAndCyclePath;
var
  Model: TAtlasArchitectureModel;
  Enabled: Boolean;
  Path: string;
  Parts: TArray<string>;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleAnswer, Model, Enabled));
  Path := Model.FullPath('App/Data/Db.pas');
  Assert.AreEqual(IncludeTrailingPathDelimiter('C:\Projekt') + 'App' + PathDelim + 'Data' + PathDelim + 'Db.pas', Path);
  Assert.AreEqual('D:' + PathDelim + 'X.pas', Model.FullPath('D:/X.pas'), 'absolut bleibt');
  Model.Root := '';
  Assert.AreEqual('X.pas', Model.FullPath('X.pas'));
  // Der Zyklus beginnt bei einer seiner Units und kehrt zu ihr zurück.
  Parts := Model.CyclePath(Model.Cycles[0]).Split([' → ']);
  Assert.AreEqual(3, Integer(Length(Parts)));
  Assert.AreEqual(Parts[0], Parts[2]);
  Assert.IsTrue((Parts[0] = 'App.Data.Db') or (Parts[0] = 'App.Data.Cache'));
  Assert.AreNotEqual(Parts[0], Parts[1]);
end;

procedure TAtlasArchitectureModelTests.PaletteAndDarkness;
begin
  // #2F6FB3 als $00BBGGRR.
  Assert.AreEqual(Cardinal($B36F2F), TAtlasArchitecturePalette.Color(0, False));
  Assert.AreEqual(TAtlasArchitecturePalette.Color(1, True), TAtlasArchitecturePalette.Color(11, True));
  Assert.AreNotEqual(TAtlasArchitecturePalette.Color(2, False), TAtlasArchitecturePalette.Color(2, True));
  Assert.IsTrue(TAtlasArchitecturePalette.IsDark($00202020));
  Assert.IsFalse(TAtlasArchitecturePalette.IsDark($00FFFFFF));
end;

procedure TAtlasArchitectureModelTests.ViewFitsZoomsAndHits;
var
  Model: TAtlasArchitectureModel;
  Enabled: Boolean;
  View: TAtlasArchitectureView;
  Subsystem: TAtlasArchSubsystem;
  X, Y: Double;
  Db: Integer;
  Hidden: TArray<Boolean>;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleAnswer, Model, Enabled));
  View := Default(TAtlasArchitectureView);
  View.Fit(Model, 800, 600);
  Assert.IsTrue(View.Scale > 0);
  for Subsystem in Model.Subsystems do
  begin
    Assert.IsTrue(View.ScreenX(Subsystem.X - Subsystem.R) >= TAtlasArchitectureView.Margin - 0.5);
    Assert.IsTrue(View.ScreenX(Subsystem.X + Subsystem.R) <= 800 - TAtlasArchitectureView.Margin + 0.5);
    Assert.IsTrue(View.ScreenY(Subsystem.Y + Subsystem.R) <= 600 - TAtlasArchitectureView.Margin + 0.5);
  end;
  Db := Model.IndexOf('App.Data.Db');
  X := View.ScreenX(Model.Units[Db].X);
  Y := View.ScreenY(Model.Units[Db].Y);
  Assert.AreEqual(Db, View.UnitAt(Model, X, Y));
  // Units ausgeblendeter Teilsysteme sind nicht treffbar.
  SetLength(Hidden, Length(Model.Subsystems));
  Hidden[Model.Units[Db].Subsystem] := True;
  Assert.AreNotEqual(Db, View.UnitAt(Model, X, Y, Hidden));
  // Zoomen um den Punkt der Unit: Sie bleibt unter dem Mauszeiger.
  View.ZoomAt(2, X, Y);
  Assert.AreEqual(X, View.ScreenX(Model.Units[Db].X), 0.001);
  Assert.AreEqual(Y, View.ScreenY(Model.Units[Db].Y), 0.001);
  View.Pan(10, -5);
  Assert.AreEqual(X + 10, View.ScreenX(Model.Units[Db].X), 0.001);
  Assert.AreEqual(-1, View.UnitAt(Model, -1000, -1000));
  View.ZoomAt(1000, 0, 0);
  Assert.AreEqual(Double(TAtlasArchitectureView.MaxScale), View.Scale, 0.0001);
end;

procedure TAtlasArchitectureModelTests.CommandArguments;
var
  Value: TJSONValue;
  Items: TJSONArray;
  Options: TJSONObject;
begin
  Value := TJSONObject.ParseJSONValue(TAtlasArchitectureCommands.Arguments('file:///C:/P/App.dproj', 'project', True));
  try
    Items := Value as TJSONArray;
    Assert.AreEqual('file:///C:/P/App.dproj', Items.Items[0].Value);
    Options := Items.Items[1] as TJSONObject;
    Assert.AreEqual('project', Options.GetValue<string>('scope'));
    Assert.IsTrue(Options.GetValue<Boolean>('includeLibraryUnits'));
    Assert.AreEqual('json', Options.GetValue<string>('format'));
  finally
    Value.Free;
  end;
  Value := TJSONObject.ParseJSONValue(TAtlasArchitectureCommands.SaveArguments('file:///C:/P/App.dproj',
    'C:\P\Architektur.html', 'projectGroup', False));
  try
    Items := Value as TJSONArray;
    Assert.AreEqual(3, Integer(Items.Count));
    Assert.AreEqual('C:\P\Architektur.html', Items.Items[1].Value);
    Assert.AreEqual('projectGroup', (Items.Items[2] as TJSONObject).GetValue<string>('scope'));
  finally
    Value.Free;
  end;
  Assert.AreEqual('C:\P\a.md', TAtlasArchitectureCommands.SavedFile('{"file":"C:\\P\\a.md","units":3}'));
  Assert.AreEqual('', TAtlasArchitectureCommands.SavedFile('kein JSON'));
end;

procedure TAtlasArchitectureModelTests.ShortestPathOverUses;
var
  Model: TAtlasArchitectureModel;
  Enabled: Boolean;
  Path: TArray<Integer>;
  Hidden: TArray<Boolean>;
  Main, Cache, Db: Integer;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleAnswer, Model, Enabled));
  Main := Model.IndexOf('App.Main');
  Cache := Model.IndexOf('App.Data.Cache');
  Db := Model.IndexOf('App.Data.Db');
  // Kürzester Weg in Richtung der uses: Main → Data → Db → Cache, nicht über Ui.
  Assert.IsTrue(Model.ShortestPath(Main, Cache, True, nil, Path));
  Assert.AreEqual(3, Integer(Length(Path)));
  Assert.AreEqual('App.Main → App.Data → App.Data.Db → App.Data.Cache', Model.PathText(Main, Path));
  // Gegen die Richtung gibt es keinen Weg, ebenso nicht zu sich selbst.
  Assert.IsFalse(Model.ShortestPath(Cache, Main, True, nil, Path));
  Assert.AreEqual(0, Integer(Length(Path)));
  Assert.IsFalse(Model.ShortestPath(Main, Main, True, nil, Path));
  // Cache → Db geht nur über implementation.
  Assert.IsTrue(Model.ShortestPath(Cache, Db, True, nil, Path));
  Assert.IsFalse(Model.ShortestPath(Cache, Db, False, nil, Path));
  // Ein ausgeblendetes Teilsystem sperrt seine Units als Ziel und Zwischenschritt.
  SetLength(Hidden, Length(Model.Subsystems));
  Hidden[Model.Units[Cache].Subsystem] := True;
  Assert.IsTrue(Model.IsHidden(Cache, Hidden));
  Assert.IsFalse(Model.ShortestPath(Main, Cache, True, Hidden, Path));
  Assert.AreEqual(-1, Model.IndexOf('Fehlt'));
end;

procedure TAtlasArchitectureModelTests.ParsesComparison;
var
  Model: TAtlasArchitectureModel;
  Enabled: Boolean;
  Cycles, Removed, Added: TArray<TAtlasArchChange>;
  Edge: Integer;
  Names: TArray<string>;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleComparisonAnswer, Model, Enabled));
  Assert.IsTrue(Model.Comparison.Present);
  Assert.AreEqual('C:\Projekt\stand.json', Model.Comparison.Baseline);
  Assert.AreEqual('App', Model.Comparison.BaselineTitle);
  Assert.AreEqual(7, Model.Comparison.BaselineUnits);
  Assert.AreEqual(Integer(Ord(High(TAtlasArchChangeKind)) + 1), Integer(Length(Model.Comparison.Sections)),
    'alle Abschnitte, auch leere');
  Cycles := Model.Comparison.Section(TAtlasArchChangeKind.NewCycles);
  Assert.AreEqual(1, Integer(Length(Cycles)));
  Assert.Contains(Cycles[0].Text, 'App.Data.Cache');
  Assert.IsTrue(Cycles[0].Unit_ >= 0, 'Unit zum Springen');
  Assert.AreEqual(1, Integer(Length(Model.Comparison.Failed)));
  Assert.AreEqual('newCycle', Model.Comparison.Failed[0]);
  Removed := Model.Comparison.Section(TAtlasArchChangeKind.RemovedUnits);
  Assert.AreEqual(1, Integer(Length(Removed)));
  Assert.AreEqual('App.Old', Removed[0].Text);
  Assert.AreEqual(-1, Removed[0].Unit_, 'entfernte Unit gibt es nicht mehr');
  Assert.AreEqual(0, Integer(Length(Model.Comparison.Section(TAtlasArchChangeKind.RemovedCycles))));
  Assert.IsTrue(Model.Comparison.Count >= 2);
  // Karte: neue Kanten als Nummern in Edges (Grid → Data, Cache → Db), entfernte nur zwischen Units, die es gibt.
  Names := nil;
  for Edge in Model.Comparison.AddedEdges do
    Names := Names + [Model.Units[Model.Edges[Edge].Source].Name + '>' + Model.Units[Model.Edges[Edge].Target].Name];
  Assert.AreEqual(2, Integer(Length(Names)));
  Assert.Contains(string.Join(' ', Names), 'App.Ui.Grid>App.Data');
  Assert.Contains(string.Join(' ', Names), 'App.Data.Cache>App.Data.Db');
  Assert.AreEqual(0, Integer(Length(Model.Comparison.DroppedEdges)), 'App.Old → App.Data: App.Old fehlt');
  Added := Model.Comparison.Section(TAtlasArchChangeKind.NewUnits);
  Assert.AreEqual(0, Integer(Length(Added)));
end;

procedure TAtlasArchitectureModelTests.ComparisonErrorAndAbsence;
var
  Model: TAtlasArchitectureModel;
  Enabled: Boolean;
  Answer: string;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleAnswer, Model, Enabled));
  Assert.IsFalse(Model.Comparison.Present);
  Assert.AreEqual('', Model.Comparison.Error);
  Assert.AreEqual(0, Model.Comparison.Count);
  // Unlesbarer Stand: die Übersicht kommt trotzdem, dazu die Meldung.
  Answer := SampleAnswer;
  Answer := Copy(Answer, 1, Length(Answer) - 1) + ',"comparisonError":"Architekturstand ist beschädigt"}';
  Assert.IsTrue(TAtlasArchitectureModel.Parse(Answer, Model, Enabled));
  Assert.IsFalse(Model.Comparison.Present);
  Assert.AreEqual('Architekturstand ist beschädigt', Model.Comparison.Error);
  Assert.AreEqual(6, Integer(Length(Model.Units)));
end;

procedure TAtlasArchitectureModelTests.CommandArgumentsWithComparison;
var
  Value: TJSONValue;
  Options: TJSONObject;
begin
  Value := TJSONObject.ParseJSONValue(TAtlasArchitectureCommands.Arguments('file:///C:/P/App.dproj', 'project', False,
    'C:\P\stand.json', True));
  try
    Options := (Value as TJSONArray).Items[1] as TJSONObject;
    Assert.AreEqual('C:\P\stand.json', Options.GetValue<string>('compareWith'));
    Assert.IsNull(Options.GetValue('compare'));
  finally
    Value.Free;
  end;
  // Vergleich aufgehoben: auch nicht mit architecture.baseline.
  Value := TJSONObject.ParseJSONValue(TAtlasArchitectureCommands.Arguments('file:///C:/P/App.dproj', 'project', False,
    '', False));
  try
    Options := (Value as TJSONArray).Items[1] as TJSONObject;
    Assert.IsNull(Options.GetValue('compareWith'));
    Assert.IsFalse(Options.GetValue<Boolean>('compare'));
  finally
    Value.Free;
  end;
  // Vorgabe: Server vergleicht mit architecture.baseline, keine Angabe nötig.
  Value := TJSONObject.ParseJSONValue(TAtlasArchitectureCommands.Arguments('file:///C:/P/App.dproj', 'project', False));
  try
    Options := (Value as TJSONArray).Items[1] as TJSONObject;
    Assert.IsNull(Options.GetValue('compareWith'));
    Assert.IsNull(Options.GetValue('compare'));
  finally
    Value.Free;
  end;
  Value := TJSONObject.ParseJSONValue(TAtlasArchitectureCommands.SaveArguments('file:///C:/P/App.dproj',
    'C:\P\stand.json', 'project', False, '', False));
  try
    Assert.AreEqual('C:\P\stand.json', (Value as TJSONArray).Items[1].Value);
    Assert.IsFalse(((Value as TJSONArray).Items[2] as TJSONObject).GetValue<Boolean>('compare'));
  finally
    Value.Free;
  end;
end;

procedure TAtlasArchitectureModelTests.RouteOfSymbolPath;
var
  Model: TAtlasArchitectureModel;
  Enabled: Boolean;
  Units, Edges: TArray<Integer>;
  Main, Data: Integer;
begin
  // Weg aus „Weg zwischen Symbolen“ (#1117): Wiederholungen und Units außerhalb des Umfangs fallen weg,
  // Data → Cache hat keine direkte Kante und wird über Db überbrückt.
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleAnswer, Model, Enabled));
  Assert.IsTrue(Model.RouteOf(TArray<string>.Create('App.Main', 'app.main', 'App.Data', 'System.SysUtils',
    'App.Data.Cache'), Units, Edges));
  Assert.AreEqual('App.Main → App.Data → App.Data.Db → App.Data.Cache', Model.RouteText(Units));
  Assert.AreEqual(3, Integer(Length(Edges)));
  // Gegen die uses-Richtung (etwa über eine Umsetzung) gilt die Kante der Gegenrichtung.
  Main := Model.IndexOf('App.Main');
  Data := Model.IndexOf('App.Data');
  Assert.IsTrue(Model.RouteOf(TArray<string>.Create('App.Data', 'App.Main'), Units, Edges));
  Assert.AreEqual(1, Integer(Length(Edges)));
  Assert.AreEqual(Main, Model.Edges[Edges[0]].Source);
  Assert.AreEqual(Data, Model.Edges[Edges[0]].Target);
  // Eine einzelne Unit ist ein Weg ohne Kanten, eine fremde keiner.
  Assert.IsTrue(Model.RouteOf(TArray<string>.Create('App.Main'), Units, Edges));
  Assert.AreEqual(0, Integer(Length(Edges)));
  Assert.IsFalse(Model.RouteOf(TArray<string>.Create('System.SysUtils'), Units, Edges));
  Assert.AreEqual(0, Integer(Length(Units)));
end;

procedure TAtlasArchitectureModelTests.ResolutionScaleIsLogarithmic;
var
  mFormat: TFormatSettings;
begin
  Assert.AreEqual(Double(0.2), TAtlasArchResolution.ValueAt(0), 1E-9);
  Assert.AreEqual(Double(1), TAtlasArchResolution.ValueAt(TAtlasArchResolution.Steps div 2), 1E-9);
  Assert.AreEqual(Double(5), TAtlasArchResolution.ValueAt(TAtlasArchResolution.Steps), 1E-9);
  // Logarithmisch: ein Viertel des Wegs ist √5 · 0,2 ≈ 0,45, drei Viertel ≈ 2,24.
  Assert.AreEqual(Double(0.45), TAtlasArchResolution.ValueAt(25), 1E-9);
  Assert.AreEqual(Double(2.24), TAtlasArchResolution.ValueAt(75), 1E-9);
  Assert.AreEqual(50, TAtlasArchResolution.PositionOf(1));
  Assert.AreEqual(0, TAtlasArchResolution.PositionOf(0.2));
  Assert.AreEqual(100, TAtlasArchResolution.PositionOf(5));
  // Außerhalb begrenzt, ungültig = 1.
  Assert.AreEqual(0, TAtlasArchResolution.PositionOf(0.01));
  Assert.AreEqual(100, TAtlasArchResolution.PositionOf(80));
  Assert.AreEqual(50, TAtlasArchResolution.PositionOf(0));
  Assert.AreEqual(Double(1), TAtlasArchResolution.Clamp(-3), 1E-9);
  mFormat := TFormatSettings.Invariant;
  mFormat.DecimalSeparator := ',';
  Assert.AreEqual('1,0', TAtlasArchResolution.Text(1, mFormat));
  Assert.AreEqual('2,24', TAtlasArchResolution.Text(2.24, mFormat));
  Assert.AreEqual('0.5', TAtlasArchResolution.Text(0.5, TFormatSettings.Invariant));
end;

procedure TAtlasArchitectureModelTests.GroupingSettingsReadAndWrite;
var
  mResolution: Double;
  mSlider: Boolean;
  mText: string;
begin
  TAtlasArchitectureGroupingSettings.Read('', mResolution, mSlider);
  Assert.AreEqual(Double(1), mResolution, 1E-9);
  Assert.IsTrue(mSlider);
  TAtlasArchitectureGroupingSettings.Read('{"architecture": {"grouping": {"resolution": 2.5, ' +
    '"showResolutionSlider": false}}}', mResolution, mSlider);
  Assert.AreEqual(Double(2.5), mResolution, 1E-9);
  Assert.IsFalse(mSlider);
  // Ungültiges wie die Vorgabe.
  TAtlasArchitectureGroupingSettings.Read('{"architecture": {"grouping": {"resolution": "fein"}}}', mResolution,
    mSlider);
  Assert.AreEqual(Double(1), mResolution, 1E-9);
  // Schreiben lässt den übrigen Text stehen und legt fehlende Objekte an.
  mText := TAtlasArchitectureGroupingSettings.WithResolution('{' + sLineBreak + '  "language": "de"' + sLineBreak +
    '}' + sLineBreak, 1.75);
  Assert.Contains(mText, '"language": "de"');
  TAtlasArchitectureGroupingSettings.Read(mText, mResolution, mSlider);
  Assert.AreEqual(Double(1.75), mResolution, 1E-9);
  mText := TAtlasArchitectureGroupingSettings.WithResolution(mText, 0.5);
  TAtlasArchitectureGroupingSettings.Read(mText, mResolution, mSlider);
  Assert.AreEqual(Double(0.5), mResolution, 1E-9);
  Assert.IsTrue(mSlider);
end;

procedure TAtlasArchitectureModelTests.ParsesResolution;
var
  mModel: TAtlasArchitectureModel;
  mEnabled: Boolean;
  mAnswer: string;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleAnswer, mModel, mEnabled));
  Assert.AreEqual(Double(1), mModel.Resolution, 1E-9);
  Assert.AreEqual(Integer(Length(mModel.Subsystems)), mModel.SubsystemCount);
  // Stand mit γ 1,0, aktueller mit 2,0: Hinweis im Vergleich.
  mAnswer := SampleResolutionAnswer;
  Assert.IsTrue(TAtlasArchitectureModel.Parse(mAnswer, mModel, mEnabled));
  Assert.AreEqual(Double(2), mModel.Resolution, 1E-9);
  Assert.AreEqual(Double(1), mModel.Comparison.BaselineResolution, 1E-9);
  Assert.AreEqual(Double(2), mModel.Comparison.Resolution, 1E-9);
  Assert.IsTrue(mModel.Comparison.ResolutionDiffers);
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleComparisonAnswer, mModel, mEnabled));
  Assert.IsFalse(mModel.Comparison.ResolutionDiffers);
end;

procedure TAtlasArchitectureModelTests.ParsesSplitSubsystems;
var
  mModel: TAtlasArchitectureModel;
  mEnabled: Boolean;
  mLast, mIndex: Integer;
  mOrder: TArray<Integer>;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleSplitAnswer, mModel, mEnabled));
  mLast := High(mModel.Subsystems);
  Assert.IsTrue(mLast >= 2, 'mindestens drei Teilsysteme');
  Assert.AreEqual('App', mModel.Subsystems[0].Parent);
  Assert.AreEqual('App', mModel.Subsystems[mLast].Parent);
  Assert.AreEqual('', mModel.Subsystems[1].Parent);
  Assert.AreEqual(0, mModel.Subsystems[mLast].ColorSlot);
  Assert.AreEqual(1, mModel.Subsystems[mLast].Shade);
  Assert.AreEqual(1, mModel.Subsystems[1].ColorSlot);
  Assert.AreEqual(TAtlasArchitecturePalette.Color(0, 1, False), mModel.SubsystemColor(mLast, False));
  Assert.AreEqual(TAtlasArchitecturePalette.Color(1, True), mModel.SubsystemColor(1, True));
  // Legende: die Teile von „App“ zusammen an der Stelle des ersten.
  mOrder := mModel.LegendOrder;
  Assert.AreEqual(Integer(Length(mModel.Subsystems)), Integer(Length(mOrder)));
  Assert.AreEqual(0, mOrder[0]);
  Assert.AreEqual(mLast, mOrder[1]);
  Assert.AreEqual(1, mOrder[2]);
  // Ohne Nachteilung: Reihenfolge und Farben wie vor #1364.
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleAnswer, mModel, mEnabled));
  mOrder := mModel.LegendOrder;
  for mIndex := 0 to High(mOrder) do
  begin
    Assert.AreEqual(mIndex, mOrder[mIndex]);
    Assert.AreEqual(TAtlasArchitecturePalette.Color(mIndex, False), mModel.SubsystemColor(mIndex, False));
  end;
end;

procedure TAtlasArchitectureModelTests.PaletteShades;
var
  mBase, mLight, mDark: Cardinal;
begin
  mBase := TAtlasArchitecturePalette.Color(0, False);
  Assert.AreEqual(mBase, TAtlasArchitecturePalette.Color(0, 0, False));
  mLight := TAtlasArchitecturePalette.Color(0, 1, False);
  mDark := TAtlasArchitecturePalette.Color(0, -1, False);
  // #2F6FB3 mit 22 % Weiß: 2F → 5D, 6F → 8F, B3 → C4; mit 22 % Schwarz: 25, 57, 8C.
  Assert.AreEqual(Cardinal($C48F5D), mLight);
  Assert.AreEqual(Cardinal($8C5725), mDark);
  // Höchstens 60 %.
  Assert.AreEqual(TAtlasArchitecturePalette.Color(0, 3, False), TAtlasArchitecturePalette.Color(0, 5, False));
end;

procedure TAtlasArchitectureModelTests.ParsesFoundation;
var
  mModel: TAtlasArchitectureModel;
  mEnabled: Boolean;
  mEdge: TAtlasArchEdge;
  mInside, mOutside: Boolean;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleAnswer, mModel, mEnabled));
  Assert.IsFalse(mModel.HasFoundation);
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleFoundationAnswer, mModel, mEnabled));
  Assert.IsTrue(mModel.HasFoundation);
  Assert.IsTrue(mModel.Subsystems[0].Foundation);
  Assert.IsFalse(mModel.Subsystems[1].Foundation);
  Assert.AreEqual(TAtlasArchitecturePalette.FoundationColor(True), mModel.SubsystemColor(0, True));
  Assert.AreEqual(Cardinal($76655D), TAtlasArchitecturePalette.FoundationColor(False));
  Assert.AreEqual(TAtlasArchitecturePalette.Color(1, False), mModel.SubsystemColor(1, False));
  // Kanten ins Fundament erkennt TouchesFoundation.
  mInside := False;
  mOutside := False;
  for mEdge in mModel.Edges do
    if (mModel.Units[mEdge.Source].Subsystem = 0) or (mModel.Units[mEdge.Target].Subsystem = 0) then
    begin
      Assert.IsTrue(mModel.TouchesFoundation(mEdge));
      mInside := True;
    end
    else
    begin
      Assert.IsFalse(mModel.TouchesFoundation(mEdge));
      mOutside := True;
    end;
  Assert.IsTrue(mInside and mOutside);
end;

procedure TAtlasArchitectureModelTests.CommandArgumentsWithResolution;
var
  mValue: TJSONValue;
  mOptions: TAtlasArchitectureOptions;
  mItem: TJSONObject;
  mNumber: Double;
begin
  mOptions := TAtlasArchitectureOptions.Create('project', True);
  mValue := TJSONObject.ParseJSONValue(TAtlasArchitectureCommands.Arguments('file:///C:/P/App.dproj', mOptions));
  try
    mItem := (mValue as TJSONArray).Items[1] as TJSONObject;
    Assert.IsNull(mItem.GetValue('resolution'));
    Assert.AreEqual('json', mItem.GetValue<string>('format'));
  finally
    mValue.Free;
  end;
  mOptions.Resolution := 1.5;
  mOptions.CompareWith := 'C:\P\stand.json';
  mValue := TJSONObject.ParseJSONValue(TAtlasArchitectureCommands.Arguments('file:///C:/P/App.dproj', mOptions));
  try
    mItem := (mValue as TJSONArray).Items[1] as TJSONObject;
    mNumber := mItem.GetValue<Double>('resolution');
    Assert.AreEqual(Double(1.5), mNumber, 1E-9);
    Assert.AreEqual('C:\P\stand.json', mItem.GetValue<string>('compareWith'));
  finally
    mValue.Free;
  end;
  mValue := TJSONObject.ParseJSONValue(TAtlasArchitectureCommands.SaveArguments('file:///C:/P/App.dproj',
    'C:\Pericht.html', mOptions));
  try
    mItem := (mValue as TJSONArray).Items[2] as TJSONObject;
    mNumber := mItem.GetValue<Double>('resolution');
    Assert.AreEqual(Double(1.5), mNumber, 1E-9);
    Assert.IsNull(mItem.GetValue('format'));
  finally
    mValue.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasArchitectureModelTests);

end.
