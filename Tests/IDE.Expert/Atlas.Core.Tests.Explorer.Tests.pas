unit Atlas.Core.Tests.Explorer.Tests;

// Tests des Baummodells im Fenster „Atlas-Tests“ (#1776): Knoten, Stand,
// Zähler und Dauer, ignorierte und veraltete Tests, Filter und Suche,
// Namen für --run einer Mehrfachauswahl, Einzelheiten und Stacktrace.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasTestExplorerTests = class
  public
    [Test]
    procedure BuildsTreeWithTallies;
    [Test]
    procedure StatesAndCounters;
    [Test]
    procedure IgnoredTestDoesNotCount;
    [Test]
    procedure StalePassedIsGrey;
    [Test]
    procedure FilterKeepsPathToMatches;
    [Test]
    procedure SearchMatchesFullName;
    [Test]
    procedure RowsLinkVisibleParents;
    [Test]
    procedure RunNamesSkipChildrenOfSelected;
    [Test]
    procedure UnitsSortedByName;
    [Test]
    procedure StackLinesTakeLongestUnit;
    [Test]
    procedure DetailLinesOfFailure;
    [Test]
    procedure DetailLinesWithoutRun;
    [Test]
    procedure MergedReplacesByName;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.DUnitX,
  Atlas.Text.TestResults,
  Atlas.Core.Tests.Run,
  Atlas.Core.Tests.Stale,
  Atlas.Core.Tests.Explorer;

const
  cFile = 'C:\Projekt\Demo.Tests.pas';
  // Indizes der Knoten von DemoUnit in Build.
  cUnitNode = 0;
  cFixtureNode = 1;
  cAddiert = 2;
  cTeilt = 3;
  cEins = 4;
  cZwei = 5;
  cSpaeter = 6;

function DemoLines: TArray<string>;
begin
  Result := TArray<string>.Create(
    'unit Demo.Tests;',
    'interface',
    'uses DUnitX.TestFramework;',
    'type',
    '  [TestFixture]',
    '  TRechnerTests = class',
    '  public',
    '    [Test]',
    '    procedure Addiert;',
    '    [Test]',
    '    [TestCase(''Eins'', ''1'')]',
    '    [TestCase(''Zwei'', ''2'')]',
    '    procedure Teilt(A: Integer);',
    '    [Test]',
    '    [Ignore(''später'')]',
    '    procedure Spaeter;',
    '  end;',
    'implementation',
    'procedure TRechnerTests.Addiert;',
    'begin',
    'end;',
    'procedure TRechnerTests.Teilt(A: Integer);',
    'begin',
    'end;',
    'procedure TRechnerTests.Spaeter;',
    'begin',
    'end;',
    'end.');
end;

function DemoUnit(const AStaleKeys: TArray<string>): TAtlasTestUnitInput;
begin
  Result := Default(TAtlasTestUnitInput);
  Result.FileName := cFile;
  Result.Found := TDUnitXSource.Scan(DemoLines);
  Result.StaleKeys := AStaleKeys;
end;

function CaseOf(const AMethod, ACase: string; AOutcome: TTestOutcome; ADurationMs: Int64): TTestCaseResult;
begin
  Result := Default(TTestCaseResult);
  Result.UnitName := 'Demo.Tests';
  Result.Fixture := 'TRechnerTests';
  Result.Method := AMethod;
  Result.CaseName := ACase;
  Result.FullName := TDUnitXCommandLine.CaseName('Demo.Tests', 'TRechnerTests', AMethod, ACase);
  Result.Outcome := AOutcome;
  Result.DurationMs := ADurationMs;
end;

/// <summary>Addiert bestanden (12 ms), Teilt.Eins fehlgeschlagen (3 ms), Teilt.Zwei nicht gelaufen.</summary>
function DemoResults: TArray<TTestCaseResult>;
var
  mFailed: TTestCaseResult;
begin
  mFailed := CaseOf('Teilt', 'Eins', TTestOutcome.Failed, 3);
  mFailed.Message := 'Expected 2 but got 3';
  mFailed.HasValues := True;
  mFailed.Expected := '2';
  mFailed.Actual := '3';
  mFailed.StackTrace := 'DUnitX.Assert 120' + #10 + 'Demo.Tests 22 +1 TRechnerTests.Teilt';
  Result := TArray<TTestCaseResult>.Create(CaseOf('Addiert', '', TTestOutcome.Passed, 12), mFailed);
end;

function DemoNodes: TArray<TAtlasTestNode>;
begin
  Result := TAtlasTestExplorer.Build(TArray<TAtlasTestUnitInput>.Create(DemoUnit(nil)), DemoResults);
end;

function RowTexts: TAtlasTestRowTexts;
begin
  Result := Default(TAtlasTestRowTexts);
  Result.Ignored := '%s (ignoriert)';
  Result.DecimalSeparator := ',';
end;

function DetailTexts: TAtlasTestDetailTexts;
begin
  Result := Default(TAtlasTestDetailTexts);
  Result.Passed := 'Bestanden (%s)';
  Result.NotRun := 'Noch nicht gelaufen.';
  Result.Skipped := 'Übersprungen: %s';
  Result.Message := 'Meldung: %s';
  Result.Expected := 'Erwartet: %s';
  Result.Actual := 'Erhalten: %s';
  Result.Stack := 'Stacktrace:';
  Result.DecimalSeparator := ',';
end;

procedure TAtlasTestExplorerTests.BuildsTreeWithTallies;
var
  mNodes: TArray<TAtlasTestNode>;
begin
  mNodes := DemoNodes;
  Assert.AreEqual(7, Integer(Length(mNodes)), 'Unit, Fixture, Addiert, Teilt, zwei Fälle, Spaeter');
  Assert.AreEqual<TAtlasTestNodeKind>(TAtlasTestNodeKind.TestUnit, mNodes[cUnitNode].Kind);
  Assert.AreEqual(-1, mNodes[cUnitNode].Parent);
  Assert.AreEqual('Demo.Tests', mNodes[cUnitNode].Caption);
  Assert.AreEqual(cUnitNode, mNodes[cFixtureNode].Parent);
  Assert.AreEqual('TRechnerTests', mNodes[cFixtureNode].Caption);
  Assert.AreEqual(cFixtureNode, mNodes[cTeilt].Parent);
  Assert.AreEqual(cTeilt, mNodes[cZwei].Parent);
  Assert.AreEqual<TAtlasTestNodeKind>(TAtlasTestNodeKind.TestCase, mNodes[cZwei].Kind);
  Assert.AreEqual('Demo.Tests.TRechnerTests.Teilt.Zwei', mNodes[cZwei].FullName);
  Assert.AreEqual(18, mNodes[cAddiert].Line, 'Sprung zum Methodenkopf im implementation-Teil');
  Assert.AreEqual(11, mNodes[cZwei].Line, 'Sprung zum [TestCase] des Falls');
  // Spaeter ist ignoriert: drei Tests (Addiert und zwei Fälle), zwei mit Ergebnis.
  Assert.AreEqual(3, mNodes[cFixtureNode].Tally.Total);
  Assert.AreEqual(2, mNodes[cFixtureNode].Tally.Ran);
  Assert.AreEqual(1, mNodes[cFixtureNode].Tally.Passed);
  Assert.AreEqual(1, mNodes[cFixtureNode].Tally.Failed);
  Assert.AreEqual(Int64(15), mNodes[cUnitNode].Tally.DurationMs, 'Summe der Dauer');
  Assert.AreEqual(Int64(12), mNodes[cUnitNode].Tally.SlowestMs, 'langsamster Test');
end;

procedure TAtlasTestExplorerTests.StatesAndCounters;
var
  mNodes: TArray<TAtlasTestNode>;
  mTotal, mPassed, mFailed, mNotRun: Integer;
begin
  mNodes := DemoNodes;
  Assert.AreEqual<TAtlasTestNodeState>(TAtlasTestNodeState.Passed, TAtlasTestExplorer.StateOf(mNodes[cAddiert]));
  Assert.AreEqual<TAtlasTestNodeState>(TAtlasTestNodeState.Failed, TAtlasTestExplorer.StateOf(mNodes[cEins]));
  Assert.AreEqual<TAtlasTestNodeState>(TAtlasTestNodeState.NotRun, TAtlasTestExplorer.StateOf(mNodes[cZwei]));
  Assert.AreEqual<TAtlasTestNodeState>(TAtlasTestNodeState.Failed, TAtlasTestExplorer.StateOf(mNodes[cTeilt]), 'ein Fall rot');
  Assert.AreEqual<TAtlasTestNodeState>(TAtlasTestNodeState.Failed, TAtlasTestExplorer.StateOf(mNodes[cFixtureNode]));
  Assert.AreEqual('1/3', TAtlasTestExplorer.Counter(mNodes[cFixtureNode]));
  Assert.AreEqual('TRechnerTests · 1/3 · 15 ms', TAtlasTestExplorer.RowText(mNodes[cFixtureNode], RowTexts));
  Assert.AreEqual('Addiert · 12 ms', TAtlasTestExplorer.RowText(mNodes[cAddiert], RowTexts),
    'ein einzelner Test ohne Zähler');
  Assert.AreEqual('Teilt · 0/2 · 3 ms', TAtlasTestExplorer.RowText(mNodes[cTeilt], RowTexts));
  Assert.AreEqual('Zwei', TAtlasTestExplorer.RowText(mNodes[cZwei], RowTexts), 'ohne Lauf ohne Dauer');
  TAtlasTestExplorer.Totals(mNodes, mTotal, mPassed, mFailed, mNotRun);
  Assert.AreEqual(3, mTotal);
  Assert.AreEqual(1, mPassed);
  Assert.AreEqual(1, mFailed);
  Assert.AreEqual(1, mNotRun);
end;

procedure TAtlasTestExplorerTests.IgnoredTestDoesNotCount;
var
  mNodes: TArray<TAtlasTestNode>;
begin
  mNodes := DemoNodes;
  Assert.IsTrue(mNodes[cSpaeter].Ignored);
  Assert.AreEqual(0, mNodes[cSpaeter].Tally.Total);
  Assert.AreEqual('Spaeter (ignoriert)', TAtlasTestExplorer.RowText(mNodes[cSpaeter], RowTexts));
  Assert.IsFalse(mNodes[cFixtureNode].Ignored, 'Fixture mit anderen Tests');
end;

procedure TAtlasTestExplorerTests.StalePassedIsGrey;
var
  mNodes: TArray<TAtlasTestNode>;
begin
  mNodes := TAtlasTestExplorer.Build(TArray<TAtlasTestUnitInput>.Create(DemoUnit(
    TArray<string>.Create(TAtlasTestStamps.KeyOf('Demo.Tests', 'TRechnerTests', 'Addiert')))), DemoResults);
  Assert.AreEqual<TAtlasTestNodeState>(TAtlasTestNodeState.Stale, TAtlasTestExplorer.StateOf(mNodes[cAddiert]), 'bestanden, aber veraltet');
  Assert.AreEqual('0/3', TAtlasTestExplorer.Counter(mNodes[cFixtureNode]), 'veraltet zählt nicht als bestanden');
end;

procedure TAtlasTestExplorerTests.FilterKeepsPathToMatches;
var
  mNodes: TArray<TAtlasTestNode>;
  mVisible: TArray<Boolean>;
begin
  mNodes := DemoNodes;
  mVisible := TAtlasTestExplorer.Visible(mNodes, [TAtlasTestFilter.Failed], '', 500);
  Assert.IsTrue(mVisible[cEins], 'fehlgeschlagener Fall');
  Assert.IsTrue(mVisible[cTeilt] and mVisible[cFixtureNode] and mVisible[cUnitNode], 'Weg dorthin');
  Assert.IsFalse(mVisible[cAddiert]);
  Assert.IsFalse(mVisible[cZwei]);
  Assert.IsFalse(mVisible[cSpaeter]);
  mVisible := TAtlasTestExplorer.Visible(mNodes, [TAtlasTestFilter.NotRun], '', 500);
  Assert.IsTrue(mVisible[cZwei], 'nicht gelaufen');
  Assert.IsFalse(mVisible[cSpaeter], 'ignoriert gilt nicht als nicht gelaufen');
  Assert.IsFalse(mVisible[cEins]);
  mVisible := TAtlasTestExplorer.Visible(mNodes, [TAtlasTestFilter.Slow], '', 10);
  Assert.IsTrue(mVisible[cAddiert], '12 ms über 10 ms');
  Assert.IsFalse(mVisible[cEins], '3 ms');
  mVisible := TAtlasTestExplorer.Visible(mNodes, [TAtlasTestFilter.Failed, TAtlasTestFilter.Slow], '', 10);
  Assert.IsTrue(mVisible[cAddiert] and mVisible[cEins], 'mehrere Filter mit oder');
  mVisible := TAtlasTestExplorer.Visible(mNodes, [], '', 500);
  Assert.IsTrue(mVisible[cSpaeter] and mVisible[cZwei] and mVisible[cAddiert], 'ohne Filter alles');
end;

procedure TAtlasTestExplorerTests.SearchMatchesFullName;
var
  mNodes: TArray<TAtlasTestNode>;
  mVisible: TArray<Boolean>;
begin
  mNodes := DemoNodes;
  mVisible := TAtlasTestExplorer.Visible(mNodes, [], 'ZWEI', 500);
  Assert.IsTrue(mVisible[cZwei], 'ohne Groß-/Kleinschreibung');
  Assert.IsTrue(mVisible[cTeilt] and mVisible[cFixtureNode] and mVisible[cUnitNode]);
  Assert.IsFalse(mVisible[cEins]);
  Assert.IsFalse(mVisible[cAddiert]);
  mVisible := TAtlasTestExplorer.Visible(mNodes, [], 'rechner', 500);
  Assert.IsTrue(mVisible[cAddiert] and mVisible[cEins] and mVisible[cSpaeter], 'Fixture im Namen: alle darunter');
  mVisible := TAtlasTestExplorer.Visible(mNodes, [TAtlasTestFilter.Failed], 'addiert', 500);
  Assert.IsFalse(mVisible[cUnitNode], 'Filter und Suche zugleich: kein Treffer');
end;

procedure TAtlasTestExplorerTests.RowsLinkVisibleParents;
var
  mNodes: TArray<TAtlasTestNode>;
  mRows: TArray<TAtlasTestRow>;
begin
  mNodes := DemoNodes;
  mRows := TAtlasTestExplorer.Rows(mNodes, TAtlasTestExplorer.Visible(mNodes, [TAtlasTestFilter.Failed], '', 500),
    RowTexts);
  Assert.AreEqual(4, Integer(Length(mRows)), 'Unit, Fixture, Teilt, Eins');
  Assert.AreEqual(-1, mRows[0].Parent);
  Assert.AreEqual(0, mRows[1].Parent);
  Assert.AreEqual(1, mRows[2].Parent);
  Assert.AreEqual(2, mRows[3].Parent);
  Assert.AreEqual(cEins, mRows[3].Node);
  Assert.AreEqual<TAtlasTestNodeState>(TAtlasTestNodeState.Failed, mRows[3].State);
  Assert.AreEqual('Eins · 3 ms', mRows[3].Text);
end;

procedure TAtlasTestExplorerTests.RunNamesSkipChildrenOfSelected;
var
  mUnits: TArray<TAtlasTestUnitInput>;
  mNodes: TArray<TAtlasTestNode>;
  mNames, mExpected: TArray<string>;
begin
  mUnits := TArray<TAtlasTestUnitInput>.Create(DemoUnit(nil));
  mNodes := TAtlasTestExplorer.Build(mUnits, nil);
  // Fixture und ein Fall darin: nur die Fixture.
  mNames := TAtlasTestExplorer.RunNames(mUnits, mNodes, TArray<Integer>.Create(cEins, cFixtureNode));
  mExpected := TDUnitXCommandLine.RunNames(mUnits[0].Found, 0, -1, -1);
  Assert.AreEqual(Integer(Length(mExpected)), Integer(Length(mNames)));
  Assert.AreEqual(mExpected[0], mNames[0]);
  // Test und ein Fall eines anderen Tests: beide, keiner doppelt.
  mNames := TAtlasTestExplorer.RunNames(mUnits, mNodes, TArray<Integer>.Create(cAddiert, cEins, cAddiert));
  Assert.AreEqual(2, Integer(Length(mNames)));
  Assert.AreEqual('Demo.Tests.TRechnerTests.Addiert', mNames[0]);
  Assert.AreEqual('Demo.Tests.TRechnerTests.Teilt.Eins', mNames[1]);
  // Die Testunit: alle Fixtures.
  mNames := TAtlasTestExplorer.RunNames(mUnits, mNodes, TArray<Integer>.Create(cUnitNode));
  Assert.AreEqual(mExpected[0], mNames[0]);
  Assert.AreEqual(0, Integer(Length(TAtlasTestExplorer.RunNames(mUnits, mNodes, nil))), 'ohne Auswahl nichts');
end;

procedure TAtlasTestExplorerTests.UnitsSortedByName;
var
  mFirst, mSecond: TAtlasTestUnitInput;
  mNodes: TArray<TAtlasTestNode>;
  mLines: TArray<string>;
begin
  mFirst := DemoUnit(nil);
  mLines := DemoLines;
  mLines[0] := 'unit Alpha.Tests;';
  mSecond := Default(TAtlasTestUnitInput);
  mSecond.FileName := 'C:\Projekt\Alpha.Tests.pas';
  mSecond.Found := TDUnitXSource.Scan(mLines);
  mNodes := TAtlasTestExplorer.Build(TArray<TAtlasTestUnitInput>.Create(mFirst, mSecond), nil);
  Assert.AreEqual('Alpha.Tests', mNodes[0].Caption);
  Assert.AreEqual(1, mNodes[0].UnitIndex, 'Index in die Eingabe bleibt');
  Assert.AreEqual('Demo.Tests', mNodes[7].Caption);
  Assert.AreEqual(7, mNodes[8].Parent);
end;

procedure TAtlasTestExplorerTests.StackLinesTakeLongestUnit;
var
  mRefs: TArray<TAtlasTestUnitRef>;
  mLines: TArray<TAtlasTestStackLine>;
begin
  SetLength(mRefs, 2);
  mRefs[0].UnitName := 'Demo';
  mRefs[0].FileName := 'C:\Projekt\Demo.pas';
  mRefs[1].UnitName := 'Demo.Tests';
  mRefs[1].FileName := cFile;
  mLines := TAtlasTestExplorer.StackLines('DUnitX.Assert 120' + #13#10 + 'Demo.Tests 22 +1 TRechnerTests.Teilt' + #10 +
    'Demo.pas:7' + #10 + #10, mRefs);
  Assert.AreEqual(3, Integer(Length(mLines)), 'leere Zeilen fallen weg');
  Assert.AreEqual('', mLines[0].FileName, 'DUnitX ist keine Unit des Projekts');
  Assert.AreEqual(-1, mLines[0].Line);
  Assert.AreEqual('DUnitX.Assert 120', mLines[0].Text, 'ohne Zeilenende');
  Assert.AreEqual(cFile, mLines[1].FileName, 'Demo.Tests statt Demo');
  Assert.AreEqual(21, mLines[1].Line);
  Assert.AreEqual('C:\Projekt\Demo.pas', mLines[2].FileName);
  Assert.AreEqual(6, mLines[2].Line);
end;

procedure TAtlasTestExplorerTests.DetailLinesOfFailure;
var
  mNodes: TArray<TAtlasTestNode>;
  mUnits: TArray<TAtlasTestUnitInput>;
  mRefs: TArray<TAtlasTestUnitRef>;
  mLines: TArray<TAtlasTestStackLine>;
begin
  mUnits := TArray<TAtlasTestUnitInput>.Create(DemoUnit(nil));
  mNodes := TAtlasTestExplorer.Build(mUnits, DemoResults);
  SetLength(mRefs, 1);
  mRefs[0].UnitName := 'Demo.Tests';
  mRefs[0].FileName := cFile;
  // Der Test Teilt: der Fehlschlag seines Falls zuerst.
  mLines := TAtlasTestExplorer.DetailLines(TAtlasTestExplorer.ResultsOf(mNodes[cTeilt], mUnits, DemoResults), mRefs,
    DetailTexts);
  Assert.AreEqual(6, Integer(Length(mLines)));
  Assert.AreEqual('Meldung: Expected 2 but got 3', mLines[0].Text);
  Assert.AreEqual('Erwartet: 2', mLines[1].Text);
  Assert.AreEqual('Erhalten: 3', mLines[2].Text);
  Assert.AreEqual('Stacktrace:', mLines[3].Text);
  Assert.AreEqual(cFile, mLines[5].FileName);
  Assert.AreEqual(21, mLines[5].Line);
  mLines := TAtlasTestExplorer.DetailLines(TAtlasTestExplorer.ResultsOf(mNodes[cAddiert], mUnits, DemoResults), mRefs,
    DetailTexts);
  Assert.AreEqual(1, Integer(Length(mLines)));
  Assert.AreEqual('Bestanden (12 ms)', mLines[0].Text);
end;

procedure TAtlasTestExplorerTests.DetailLinesWithoutRun;
var
  mNodes: TArray<TAtlasTestNode>;
  mUnits: TArray<TAtlasTestUnitInput>;
  mLines: TArray<TAtlasTestStackLine>;
begin
  mUnits := TArray<TAtlasTestUnitInput>.Create(DemoUnit(nil));
  mNodes := TAtlasTestExplorer.Build(mUnits, DemoResults);
  Assert.AreEqual(0, Integer(Length(TAtlasTestExplorer.ResultsOf(mNodes[cZwei], mUnits, DemoResults))));
  Assert.AreEqual(0, Integer(Length(TAtlasTestExplorer.ResultsOf(mNodes[cUnitNode], mUnits, DemoResults))),
    'eine Testunit hat keine Einzelheiten');
  mLines := TAtlasTestExplorer.DetailLines(nil, nil, DetailTexts);
  Assert.AreEqual(1, Integer(Length(mLines)));
  Assert.AreEqual('Noch nicht gelaufen.', mLines[0].Text);
end;

procedure TAtlasTestExplorerTests.MergedReplacesByName;
var
  mOld, mFresh, mMerged: TArray<TTestCaseResult>;
begin
  mOld := DemoResults;
  mFresh := TArray<TTestCaseResult>.Create(CaseOf('Teilt', 'Eins', TTestOutcome.Passed, 4));
  mFresh[0].FullName := LowerCase(mFresh[0].FullName);
  mMerged := TAtlasTestRun.Merged(mOld, mFresh);
  Assert.AreEqual(2, Integer(Length(mMerged)), 'Fall ersetzt, nicht doppelt');
  Assert.AreEqual('Addiert', mMerged[0].Method);
  Assert.AreEqual<TTestOutcome>(TTestOutcome.Passed, mMerged[1].Outcome, 'neues Ergebnis hinten');
end;

end.
