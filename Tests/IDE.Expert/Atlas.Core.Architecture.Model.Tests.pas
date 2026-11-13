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
  [Category('Atlas.IDE.Analysis')]
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
    /// <summary>Angleichung (#1367): "aligned" lesen, "renameSubsystems" schicken.</summary>
    [Test]
    procedure ParsesAlignmentAndSendsRename;
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
/// <summary>Angleichung (#1367): Index.A*, Index.B* (vier Units) und Ui.X*, angeglichen an den Stand vom
/// 29.10.2026 14:23 aus architecture.baseline.</summary>
function SampleAlignedAnswer: string;

implementation

uses
  System.SysUtils,
  System.Math,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Architecture.Overview,
  Atlas.Common.Architecture.Grouping,
  Atlas.Common.Architecture.Service,
  Atlas.Common.Architecture.Layout,
  Atlas.Common.Architecture.Report,
  Atlas.Common.Architecture.Snapshot,
  Atlas.Common.Architecture.Comparison,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Architecture.UsesGraph.Tests,
  Atlas.Common.Architecture.Snapshot.Tests,
  Atlas.Common.Architecture.Overview.Tests,
  Atlas.Common.Architecture.Alignment,
  Atlas.Common.Architecture.Alignment.Tests,
  Atlas.Core.Architecture.Model,
  Atlas.Core.Architecture.Commands,
  Atlas.Core.Architecture.View;

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
  mIndex: ISymbolIndex;
  mService: TArchitectureService;
  mRequest: TArchitectureRequest;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(UsesUnit('App.Main', ['App.Data', 'App.Ui.Form'], nil));
  mIndex.AddUnit(UsesUnit('App.Data', ['App.Data.Db'], nil));
  mIndex.AddUnit(UsesUnit('App.Data.Db', ['App.Data.Cache'], nil));
  mIndex.AddUnit(UsesUnit('App.Ui.Form', ['App.Ui.Grid'], nil));
  if AOlder then
  begin
    mIndex.AddUnit(UsesUnit('App.Data.Cache', nil, nil));
    mIndex.AddUnit(UsesUnit('App.Ui.Grid', nil, nil));
    mIndex.AddUnit(UsesUnit('App.Old', ['App.Data'], nil));
  end
  else
  begin
    mIndex.AddUnit(UsesUnit('App.Data.Cache', nil, ['App.Data.Db']));
    mIndex.AddUnit(UsesUnit('App.Ui.Grid', ['App.Data'], nil));
  end;
  mService := TArchitectureService.Create(mIndex,
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
    mRequest := Default(TArchitectureRequest);
    mRequest.Title := 'App';
    mRequest.Root := 'C:\Projekt';
    mRequest.Scope := 'project';
    mRequest.CentralUnits := 3;
    mRequest.Exclude := ['Tests/**'];
    Result := mService.Overview(mRequest);
  finally
    mService.Free;
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
  mCurrent: TArchitectureOverview;
  mComparison: TArchitectureComparison;
begin
  mCurrent := SampleOverview(False);
  mComparison := TArchitectureComparer.Compare(TArchitectureSnapshots.FromOverview(SampleOverview(True)),
    TArchitectureSnapshots.FromOverview(mCurrent));
  Result := AnswerOf(mCurrent, ',"baseline":"C:\\Projekt\\stand.json","comparison":' +
    TArchitectureComparer.Json(mComparison, TArchitectureComparer.DefaultFailOn));
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
  mOverview.Subsystems[0].Name := TArchitectureAnalyzer.cFoundationName;
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
  begin
    if mModel.Subsystems[mRow.Subsystem].Foundation then
    begin
      mFound := True;
      Assert.IsFalse(mRow.Counts);
    end;
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
  mModel: TAtlasArchitectureModel;
  mEnabled: Boolean;
  mDb: Integer;
  mSubsystem: TAtlasArchSubsystem;
  mCount: Integer;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleAnswer, mModel, mEnabled));
  Assert.IsTrue(mEnabled);
  Assert.AreEqual('App', mModel.Title);
  Assert.AreEqual('C:\Projekt', mModel.Root);
  Assert.AreEqual('project', mModel.Scope);
  Assert.AreEqual(1, Integer(Length(mModel.Excludes)));
  Assert.AreEqual('Tests/**', mModel.Excludes[0]);
  Assert.AreEqual(6, Integer(Length(mModel.Units)));
  Assert.AreEqual(3, Integer(Length(mModel.Central)));
  Assert.AreEqual(Integer(Length(mModel.Edges)), mModel.EdgeCount);
  Assert.AreEqual(1, Integer(Length(mModel.Cycles)));
  mDb := mModel.IndexOf('app.data.db');
  Assert.IsTrue(mDb >= 0);
  Assert.IsTrue(mModel.Units[mDb].OnCycle);
  Assert.IsFalse(mModel.Units[mModel.IndexOf('App.Main')].OnCycle);
  Assert.AreEqual('App/Data/Db.pas', mModel.Units[mDb].FileName);
  Assert.IsTrue(Length(mModel.Cycles[0].Edges) >= 2);
  mCount := 0;
  for mSubsystem in mModel.Subsystems do
  begin
    Inc(mCount, Length(mSubsystem.Units));
    Assert.IsTrue(mSubsystem.R > 0, 'Kreis der Karte');
  end;
  Assert.AreEqual(6, mCount, 'jede Unit in genau einem Teilsystem');
  Assert.AreEqual(mModel.Units[mDb].Outlier, mModel.OutlierOf(mDb) >= 0);
end;

procedure TAtlasArchitectureModelTests.DisabledAndBrokenAnswers;
var
  mModel: TAtlasArchitectureModel;
  mEnabled: Boolean;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse('{"enabled":false}', mModel, mEnabled));
  Assert.IsFalse(mEnabled);
  Assert.AreEqual(0, Integer(Length(mModel.Units)));
  Assert.IsFalse(TAtlasArchitectureModel.Parse('', mModel, mEnabled));
  Assert.IsFalse(TAtlasArchitectureModel.Parse('[]', mModel, mEnabled));
  Assert.IsFalse(TAtlasArchitectureModel.Parse('{"enabled":true,"data":{"format":2}}', mModel, mEnabled),
    'fremdes Format');
  // Verweis auf eine Unit, die es nicht gibt: lieber nichts zeigen als abstürzen.
  Assert.IsFalse(TAtlasArchitectureModel.Parse('{"enabled":true,"data":{"format":1,"units":[],' +
    '"edges":[[0,1,"i"]],"subsystems":[]}}', mModel, mEnabled));
  Assert.AreEqual(0, Integer(Length(mModel.Edges)));
end;

procedure TAtlasArchitectureModelTests.SortsStableAndFilters;
var
  mModel: TAtlasArchitectureModel;
  mEnabled: Boolean;
  mAll, mSorted: TArray<Integer>;
  mIndex: Integer;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleAnswer, mModel, mEnabled));
  mAll := nil;
  for mIndex := 0 to High(mModel.Units) do
  begin
    mAll := mAll + [mIndex];
  end;
  mSorted := mModel.Sorted(mAll, TAtlasArchColumn.Name, False);
  for mIndex := 1 to High(mSorted) do
  begin
    Assert.IsTrue(CompareText(mModel.Units[mSorted[mIndex - 1]].Name, mModel.Units[mSorted[mIndex]].Name) < 0);
  end;
  mSorted := mModel.Sorted(mAll, TAtlasArchColumn.Name, True);
  Assert.AreEqual('App.Ui.Grid', mModel.Units[mSorted[0]].Name);
  mSorted := mModel.Sorted(mAll, TAtlasArchColumn.Total, True);
  for mIndex := 1 to High(mSorted) do
  begin
    Assert.IsTrue(mModel.Units[mSorted[mIndex - 1]].Total >= mModel.Units[mSorted[mIndex]].Total);
    // Gleichstand: nach Name aufsteigend, auch absteigend sortiert.
    if mModel.Units[mSorted[mIndex - 1]].Total = mModel.Units[mSorted[mIndex]].Total then
    begin
      Assert.IsTrue(CompareText(mModel.Units[mSorted[mIndex - 1]].Name, mModel.Units[mSorted[mIndex]].Name) < 0);
    end;
  end;
  Assert.IsTrue(mModel.Matches(mModel.IndexOf('App.Data.Db'), 'data db'));
  Assert.IsFalse(mModel.Matches(mModel.IndexOf('App.Data.Db'), 'data ui'));
  Assert.IsTrue(mModel.Matches(0, ''));
  Assert.IsFalse(mModel.Matches(99, ''));
end;

procedure TAtlasArchitectureModelTests.FullPathAndCyclePath;
var
  mModel: TAtlasArchitectureModel;
  mEnabled: Boolean;
  mPath: string;
  mParts: TArray<string>;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleAnswer, mModel, mEnabled));
  mPath := mModel.FullPath('App/Data/Db.pas');
  Assert.AreEqual(IncludeTrailingPathDelimiter('C:\Projekt') + 'App' + PathDelim + 'Data' + PathDelim + 'Db.pas', mPath);
  Assert.AreEqual('D:' + PathDelim + 'X.pas', mModel.FullPath('D:/X.pas'), 'absolut bleibt');
  mModel.Root := '';
  Assert.AreEqual('X.pas', mModel.FullPath('X.pas'));
  // Der Zyklus beginnt bei einer seiner Units und kehrt zu ihr zurück.
  mParts := mModel.CyclePath(mModel.Cycles[0]).Split([' → ']);
  Assert.AreEqual(3, Integer(Length(mParts)));
  Assert.AreEqual(mParts[0], mParts[2]);
  Assert.IsTrue((mParts[0] = 'App.Data.Db') or (mParts[0] = 'App.Data.Cache'));
  Assert.AreNotEqual(mParts[0], mParts[1]);
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
  mModel: TAtlasArchitectureModel;
  mEnabled: Boolean;
  mView: TAtlasArchitectureView;
  mSubsystem: TAtlasArchSubsystem;
  X, Y: Double;
  mDb: Integer;
  mHidden: TArray<Boolean>;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleAnswer, mModel, mEnabled));
  mView := Default(TAtlasArchitectureView);
  mView.Fit(mModel, 800, 600);
  Assert.IsTrue(mView.Scale > 0);
  for mSubsystem in mModel.Subsystems do
  begin
    Assert.IsTrue(mView.ScreenX(mSubsystem.X - mSubsystem.R) >= TAtlasArchitectureView.cMargin - 0.5);
    Assert.IsTrue(mView.ScreenX(mSubsystem.X + mSubsystem.R) <= 800 - TAtlasArchitectureView.cMargin + 0.5);
    Assert.IsTrue(mView.ScreenY(mSubsystem.Y + mSubsystem.R) <= 600 - TAtlasArchitectureView.cMargin + 0.5);
  end;
  mDb := mModel.IndexOf('App.Data.Db');
  X := mView.ScreenX(mModel.Units[mDb].X);
  Y := mView.ScreenY(mModel.Units[mDb].Y);
  Assert.AreEqual(mDb, mView.UnitAt(mModel, X, Y));
  // Units ausgeblendeter Teilsysteme sind nicht treffbar.
  SetLength(mHidden, Length(mModel.Subsystems));
  mHidden[mModel.Units[mDb].Subsystem] := True;
  Assert.AreNotEqual(mDb, mView.UnitAt(mModel, X, Y, mHidden));
  // Zoomen um den Punkt der Unit: Sie bleibt unter dem Mauszeiger.
  mView.ZoomAt(2, X, Y);
  Assert.AreEqual(X, mView.ScreenX(mModel.Units[mDb].X), 0.001);
  Assert.AreEqual(Y, mView.ScreenY(mModel.Units[mDb].Y), 0.001);
  mView.Pan(10, -5);
  Assert.AreEqual(X + 10, mView.ScreenX(mModel.Units[mDb].X), 0.001);
  Assert.AreEqual(-1, mView.UnitAt(mModel, -1000, -1000));
  mView.ZoomAt(1000, 0, 0);
  Assert.AreEqual(Double(TAtlasArchitectureView.cMaxScale), mView.Scale, 0.0001);
end;

procedure TAtlasArchitectureModelTests.CommandArguments;
var
  mValue: TJSONValue;
  mItems: TJSONArray;
  mOptions: TJSONObject;
begin
  mValue := TJSONObject.ParseJSONValue(TAtlasArchitectureCommands.Arguments('file:///C:/P/App.dproj', 'project', True));
  try
    mItems := mValue as TJSONArray;
    Assert.AreEqual('file:///C:/P/App.dproj', mItems.Items[0].Value);
    mOptions := mItems.Items[1] as TJSONObject;
    Assert.AreEqual('project', mOptions.GetValue<string>('scope'));
    Assert.IsTrue(mOptions.GetValue<Boolean>('includeLibraryUnits'));
    Assert.AreEqual('json', mOptions.GetValue<string>('format'));
  finally
    mValue.Free;
  end;
  mValue := TJSONObject.ParseJSONValue(TAtlasArchitectureCommands.SaveArguments('file:///C:/P/App.dproj',
    'C:\P\Architektur.html', 'projectGroup', False));
  try
    mItems := mValue as TJSONArray;
    Assert.AreEqual(3, Integer(mItems.Count));
    Assert.AreEqual('C:\P\Architektur.html', mItems.Items[1].Value);
    Assert.AreEqual('projectGroup', (mItems.Items[2] as TJSONObject).GetValue<string>('scope'));
  finally
    mValue.Free;
  end;
  Assert.AreEqual('C:\P\a.md', TAtlasArchitectureCommands.SavedFile('{"file":"C:\\P\\a.md","units":3}'));
  Assert.AreEqual('', TAtlasArchitectureCommands.SavedFile('kein JSON'));
end;

procedure TAtlasArchitectureModelTests.ShortestPathOverUses;
var
  mModel: TAtlasArchitectureModel;
  mEnabled: Boolean;
  mPath: TArray<Integer>;
  mHidden: TArray<Boolean>;
  mMain, mCache, mDb: Integer;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleAnswer, mModel, mEnabled));
  mMain := mModel.IndexOf('App.Main');
  mCache := mModel.IndexOf('App.Data.Cache');
  mDb := mModel.IndexOf('App.Data.Db');
  // Kürzester Weg in Richtung der uses: Main → Data → Db → Cache, nicht über Ui.
  Assert.IsTrue(mModel.ShortestPath(mMain, mCache, True, nil, mPath));
  Assert.AreEqual(3, Integer(Length(mPath)));
  Assert.AreEqual('App.Main → App.Data → App.Data.Db → App.Data.Cache', mModel.PathText(mMain, mPath));
  // Gegen die Richtung gibt es keinen Weg, ebenso nicht zu sich selbst.
  Assert.IsFalse(mModel.ShortestPath(mCache, mMain, True, nil, mPath));
  Assert.AreEqual(0, Integer(Length(mPath)));
  Assert.IsFalse(mModel.ShortestPath(mMain, mMain, True, nil, mPath));
  // Cache → Db geht nur über implementation.
  Assert.IsTrue(mModel.ShortestPath(mCache, mDb, True, nil, mPath));
  Assert.IsFalse(mModel.ShortestPath(mCache, mDb, False, nil, mPath));
  // Ein ausgeblendetes Teilsystem sperrt seine Units als Ziel und Zwischenschritt.
  SetLength(mHidden, Length(mModel.Subsystems));
  mHidden[mModel.Units[mCache].Subsystem] := True;
  Assert.IsTrue(mModel.IsHidden(mCache, mHidden));
  Assert.IsFalse(mModel.ShortestPath(mMain, mCache, True, mHidden, mPath));
  Assert.AreEqual(-1, mModel.IndexOf('Fehlt'));
end;

procedure TAtlasArchitectureModelTests.ParsesComparison;
var
  mModel: TAtlasArchitectureModel;
  mEnabled: Boolean;
  mCycles, mRemoved, mAdded: TArray<TAtlasArchChange>;
  mEdge: Integer;
  mNames: TArray<string>;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleComparisonAnswer, mModel, mEnabled));
  Assert.IsTrue(mModel.Comparison.Present);
  Assert.AreEqual('C:\Projekt\stand.json', mModel.Comparison.Baseline);
  Assert.AreEqual('App', mModel.Comparison.BaselineTitle);
  Assert.AreEqual(7, mModel.Comparison.BaselineUnits);
  Assert.AreEqual(Integer(Ord(High(TAtlasArchChangeKind)) + 1), Integer(Length(mModel.Comparison.Sections)),
    'alle Abschnitte, auch leere');
  mCycles := mModel.Comparison.Section(TAtlasArchChangeKind.NewCycles);
  Assert.AreEqual(1, Integer(Length(mCycles)));
  Assert.Contains(mCycles[0].Text, 'App.Data.Cache');
  Assert.IsTrue(mCycles[0].Unit_ >= 0, 'Unit zum Springen');
  Assert.AreEqual(1, Integer(Length(mModel.Comparison.Failed)));
  Assert.AreEqual('newCycle', mModel.Comparison.Failed[0]);
  mRemoved := mModel.Comparison.Section(TAtlasArchChangeKind.RemovedUnits);
  Assert.AreEqual(1, Integer(Length(mRemoved)));
  Assert.AreEqual('App.Old', mRemoved[0].Text);
  Assert.AreEqual(-1, mRemoved[0].Unit_, 'entfernte Unit gibt es nicht mehr');
  Assert.AreEqual(0, Integer(Length(mModel.Comparison.Section(TAtlasArchChangeKind.RemovedCycles))));
  Assert.IsTrue(mModel.Comparison.Count >= 2);
  // Karte: neue Kanten als Nummern in Edges (Grid → Data, Cache → Db), entfernte nur zwischen Units, die es gibt.
  mNames := nil;
  for mEdge in mModel.Comparison.AddedEdges do
  begin
    mNames := mNames + [mModel.Units[mModel.Edges[mEdge].Source].Name + '>' +
      mModel.Units[mModel.Edges[mEdge].Target].Name];
  end;
  Assert.AreEqual(2, Integer(Length(mNames)));
  Assert.Contains(string.Join(' ', mNames), 'App.Ui.Grid>App.Data');
  Assert.Contains(string.Join(' ', mNames), 'App.Data.Cache>App.Data.Db');
  Assert.AreEqual(0, Integer(Length(mModel.Comparison.DroppedEdges)), 'App.Old → App.Data: App.Old fehlt');
  mAdded := mModel.Comparison.Section(TAtlasArchChangeKind.NewUnits);
  Assert.AreEqual(0, Integer(Length(mAdded)));
end;

procedure TAtlasArchitectureModelTests.ComparisonErrorAndAbsence;
var
  mModel: TAtlasArchitectureModel;
  mEnabled: Boolean;
  mAnswer: string;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleAnswer, mModel, mEnabled));
  Assert.IsFalse(mModel.Comparison.Present);
  Assert.AreEqual('', mModel.Comparison.Error);
  Assert.AreEqual(0, mModel.Comparison.Count);
  // Unlesbarer Stand: die Übersicht kommt trotzdem, dazu die Meldung.
  mAnswer := SampleAnswer;
  mAnswer := Copy(mAnswer, 1, Length(mAnswer) - 1) + ',"comparisonError":"Architekturstand ist beschädigt"}';
  Assert.IsTrue(TAtlasArchitectureModel.Parse(mAnswer, mModel, mEnabled));
  Assert.IsFalse(mModel.Comparison.Present);
  Assert.AreEqual('Architekturstand ist beschädigt', mModel.Comparison.Error);
  Assert.AreEqual(6, Integer(Length(mModel.Units)));
end;

procedure TAtlasArchitectureModelTests.CommandArgumentsWithComparison;
var
  mValue: TJSONValue;
  mOptions: TJSONObject;
begin
  mValue := TJSONObject.ParseJSONValue(TAtlasArchitectureCommands.Arguments('file:///C:/P/App.dproj', 'project', False,
    'C:\P\stand.json', True));
  try
    mOptions := (mValue as TJSONArray).Items[1] as TJSONObject;
    Assert.AreEqual('C:\P\stand.json', mOptions.GetValue<string>('compareWith'));
    Assert.IsNull(mOptions.GetValue('compare'));
  finally
    mValue.Free;
  end;
  // Vergleich aufgehoben: auch nicht mit architecture.baseline.
  mValue := TJSONObject.ParseJSONValue(TAtlasArchitectureCommands.Arguments('file:///C:/P/App.dproj', 'project', False,
    '', False));
  try
    mOptions := (mValue as TJSONArray).Items[1] as TJSONObject;
    Assert.IsNull(mOptions.GetValue('compareWith'));
    Assert.IsFalse(mOptions.GetValue<Boolean>('compare'));
  finally
    mValue.Free;
  end;
  // Vorgabe: Server vergleicht mit architecture.baseline, keine Angabe nötig.
  mValue := TJSONObject.ParseJSONValue(TAtlasArchitectureCommands.Arguments('file:///C:/P/App.dproj', 'project', False));
  try
    mOptions := (mValue as TJSONArray).Items[1] as TJSONObject;
    Assert.IsNull(mOptions.GetValue('compareWith'));
    Assert.IsNull(mOptions.GetValue('compare'));
  finally
    mValue.Free;
  end;
  mValue := TJSONObject.ParseJSONValue(TAtlasArchitectureCommands.SaveArguments('file:///C:/P/App.dproj',
    'C:\P\stand.json', 'project', False, '', False));
  try
    Assert.AreEqual('C:\P\stand.json', (mValue as TJSONArray).Items[1].Value);
    Assert.IsFalse(((mValue as TJSONArray).Items[2] as TJSONObject).GetValue<Boolean>('compare'));
  finally
    mValue.Free;
  end;
end;

procedure TAtlasArchitectureModelTests.RouteOfSymbolPath;
var
  mModel: TAtlasArchitectureModel;
  mEnabled: Boolean;
  mUnits, mEdges: TArray<Integer>;
  mMain, mData: Integer;
begin
  // Weg aus „Weg zwischen Symbolen“ (#1117): Wiederholungen und Units außerhalb des Umfangs fallen weg,
  // Data → Cache hat keine direkte Kante und wird über Db überbrückt.
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleAnswer, mModel, mEnabled));
  Assert.IsTrue(mModel.RouteOf(TArray<string>.Create('App.Main', 'app.main', 'App.Data', 'System.SysUtils',
    'App.Data.Cache'), mUnits, mEdges));
  Assert.AreEqual('App.Main → App.Data → App.Data.Db → App.Data.Cache', mModel.RouteText(mUnits));
  Assert.AreEqual(3, Integer(Length(mEdges)));
  // Gegen die uses-Richtung (etwa über eine Umsetzung) gilt die Kante der Gegenrichtung.
  mMain := mModel.IndexOf('App.Main');
  mData := mModel.IndexOf('App.Data');
  Assert.IsTrue(mModel.RouteOf(TArray<string>.Create('App.Data', 'App.Main'), mUnits, mEdges));
  Assert.AreEqual(1, Integer(Length(mEdges)));
  Assert.AreEqual(mMain, mModel.Edges[mEdges[0]].Source);
  Assert.AreEqual(mData, mModel.Edges[mEdges[0]].Target);
  // Eine einzelne Unit ist ein Weg ohne Kanten, eine fremde keiner.
  Assert.IsTrue(mModel.RouteOf(TArray<string>.Create('App.Main'), mUnits, mEdges));
  Assert.AreEqual(0, Integer(Length(mEdges)));
  Assert.IsFalse(mModel.RouteOf(TArray<string>.Create('System.SysUtils'), mUnits, mEdges));
  Assert.AreEqual(0, Integer(Length(mUnits)));
end;

procedure TAtlasArchitectureModelTests.ResolutionScaleIsLogarithmic;
var
  mFormat: TFormatSettings;
begin
  Assert.AreEqual(Double(0.2), TAtlasArchResolution.ValueAt(0), 1E-9);
  Assert.AreEqual(Double(1), TAtlasArchResolution.ValueAt(TAtlasArchResolution.cSteps div 2), 1E-9);
  Assert.AreEqual(Double(5), TAtlasArchResolution.ValueAt(TAtlasArchResolution.cSteps), 1E-9);
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
  begin
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
  end;
  Assert.IsTrue(mInside and mOutside);
end;

function SampleAlignedAnswer: string;
var
  mOverview: TArchitectureOverview;
begin
  mOverview := AlignmentOverview(True);
  TArchitectureAlignment.Align(mOverview, TArchitectureSnapshots.FromOverview(AlignmentOverview(False)),
    TArchitectureAnalyzer.cAlignedBaseline, EncodeDate(2026, 10, 29) + EncodeTime(14, 23, 0, 0));
  Result := AnswerOf(mOverview, '');
end;

procedure TAtlasArchitectureModelTests.ParsesAlignmentAndSendsRename;
var
  mModel: TAtlasArchitectureModel;
  mEnabled: Boolean;
  mValue: TJSONValue;
  mOptions: TAtlasArchitectureOptions;
  mItem: TJSONObject;
  mIndex: Integer;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleAlignedAnswer, mModel, mEnabled));
  Assert.AreEqual('baseline', mModel.AlignedSource);
  Assert.AreEqual('2026-10-29 14:23', mModel.AlignedText);
  Assert.AreEqual(3, mModel.AlignedKept);
  // Farben aus "color": Index.B* behält die 1, obwohl es jetzt vorn steht.
  mIndex := mModel.Subsystems[mModel.Units[mModel.IndexOf('Index.B1')].Subsystem].ColorSlot;
  Assert.AreEqual(1, mIndex);
  Assert.IsTrue(TAtlasArchitectureModel.Parse(SampleAnswer, mModel, mEnabled));
  Assert.AreEqual('', mModel.AlignedSource);
  Assert.AreEqual('', mModel.AlignedText);
  mOptions := TAtlasArchitectureOptions.Create('project', True);
  Assert.IsFalse(mOptions.RenameSubsystems);
  mValue := TJSONObject.ParseJSONValue(TAtlasArchitectureCommands.Arguments('file:///C:/P/App.dproj', mOptions));
  try
    mItem := (mValue as TJSONArray).Items[1] as TJSONObject;
    Assert.IsNull(mItem.GetValue('renameSubsystems'));
  finally
    mValue.Free;
  end;
  mOptions.RenameSubsystems := True;
  mValue := TJSONObject.ParseJSONValue(TAtlasArchitectureCommands.Arguments('file:///C:/P/App.dproj', mOptions));
  try
    mItem := (mValue as TJSONArray).Items[1] as TJSONObject;
    Assert.IsTrue(mItem.GetValue<Boolean>('renameSubsystems'));
  finally
    mValue.Free;
  end;
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
    'C:\P\bericht.html', mOptions));
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
