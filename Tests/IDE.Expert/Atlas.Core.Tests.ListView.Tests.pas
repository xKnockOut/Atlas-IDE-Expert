unit Atlas.Core.Tests.ListView.Tests;

// Tests der Testlisten im Baum (#2167): Blätter mit Stand und Knoten,
// Sichtbarkeit im Reiter einer Liste (mit Filter), Namen gewählter Knoten und
// Kategorien des Testprojekts.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasTestListViewTests = class
  public
    [Test]
    procedure ItemsCarryNodeAndState;
    [Test]
    procedure VisibleKeepsPathToMembers;
    [Test]
    procedure VisibleRespectsFilter;
    [Test]
    procedure NamesSkipChildrenOfSelected;
    [Test]
    procedure CategoriesOfProject;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.DUnitX,
  Atlas.Text.TestResults,
  Atlas.Core.Tests.Explorer,
  Atlas.Core.Tests.Lists,
  Atlas.Core.Tests.ListView;

const
  // Knoten von Build: Unit, Fixture, Addiert, Teilt, Teilt.Eins, Teilt.Zwei, Spaeter.
  cUnitNode = 0;
  cFixtureNode = 1;
  cAddiert = 2;
  cTeilt = 3;
  cEins = 4;
  cZwei = 5;
  cSpaeter = 6;

function DemoInputs: TArray<TAtlasTestUnitInput>;
var
  mInput: TAtlasTestUnitInput;
begin
  mInput := Default(TAtlasTestUnitInput);
  mInput.FileName := 'C:\Projekt\Demo.Tests.pas';
  mInput.Found := TDUnitXSource.Scan(TArray<string>.Create(
    'unit Demo.Tests;',
    'interface',
    'uses DUnitX.TestFramework;',
    'type',
    '  [TestFixture]',
    '  TRechnerTests = class',
    '  public',
    '    [Test]',
    '    [Category(''Schnell'')]',
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
    'end.'));
  Result := TArray<TAtlasTestUnitInput>.Create(mInput);
end;

function CaseOf(const AMethod, ACase: string; AOutcome: TTestOutcome): TTestCaseResult;
begin
  Result := Default(TTestCaseResult);
  Result.UnitName := 'Demo.Tests';
  Result.Fixture := 'TRechnerTests';
  Result.Method := AMethod;
  Result.CaseName := ACase;
  Result.FullName := TDUnitXCommandLine.CaseName('Demo.Tests', 'TRechnerTests', AMethod, ACase);
  Result.Outcome := AOutcome;
end;

/// <summary>Addiert bestanden, Teilt.Eins fehlgeschlagen, Teilt.Zwei nicht gelaufen.</summary>
function DemoNodes: TArray<TAtlasTestNode>;
begin
  Result := TAtlasTestExplorer.Build(DemoInputs, TArray<TTestCaseResult>.Create(
    CaseOf('Addiert', '', TTestOutcome.Passed), CaseOf('Teilt', 'Eins', TTestOutcome.Failed)));
end;

function ListOf(const ARule: TAtlasTestListRule): TAtlasTestList;
begin
  Result := Default(TAtlasTestList);
  Result.Name := 'Liste';
  Result.Rules := TArray<TAtlasTestListRule>.Create(ARule);
end;

function AllVisible(ACount: Integer): TArray<Boolean>;
var
  mIndex: Integer;
begin
  SetLength(Result, ACount);
  for mIndex := 0 to High(Result) do
  begin
    Result[mIndex] := True;
  end;
end;

{ TAtlasTestListViewTests }

procedure TAtlasTestListViewTests.ItemsCarryNodeAndState;
var
  mItems: TAtlasTestListItems;
begin
  mItems := TAtlasTestListView.Items(DemoInputs, DemoNodes);
  Assert.AreEqual(4, Integer(Length(mItems)), 'Addiert, zwei Fälle, Spaeter');
  Assert.AreEqual(cAddiert, mItems[0].Node);
  Assert.IsFalse(mItems[0].NotRun);
  Assert.IsFalse(mItems[0].Failed);
  Assert.AreEqual(cEins, mItems[1].Node);
  Assert.IsTrue(mItems[1].Failed);
  Assert.AreEqual(cZwei, mItems[2].Node);
  Assert.IsTrue(mItems[2].NotRun);
  Assert.AreEqual(cSpaeter, mItems[3].Node);
  Assert.IsTrue(mItems[3].Ignored);
  Assert.AreEqual('Schnell', string.Join(',', mItems[0].Categories));
end;

procedure TAtlasTestListViewTests.VisibleKeepsPathToMembers;
var
  mNodes: TArray<TAtlasTestNode>;
  mItems: TAtlasTestListItems;
  mVisible: TArray<Boolean>;
  mList: TAtlasTestList;
begin
  mNodes := DemoNodes;
  mItems := TAtlasTestListView.Items(DemoInputs, mNodes);
  mList := ListOf(TAtlasTestListRule.OfState(TAtlasTestListState.Failed, False));
  mVisible := TAtlasTestListView.Visible(mNodes, AllVisible(Length(mNodes)), mItems,
    TAtlasTestListModel.Members(mList, mItems));
  Assert.IsTrue(mVisible[cUnitNode]);
  Assert.IsTrue(mVisible[cFixtureNode]);
  Assert.IsTrue(mVisible[cTeilt], 'Weg zum Fall');
  Assert.IsTrue(mVisible[cEins]);
  Assert.IsFalse(mVisible[cZwei]);
  Assert.IsFalse(mVisible[cAddiert]);
  Assert.IsFalse(mVisible[cSpaeter]);
end;

procedure TAtlasTestListViewTests.VisibleRespectsFilter;
var
  mNodes: TArray<TAtlasTestNode>;
  mItems: TAtlasTestListItems;
  mVisible: TArray<Boolean>;
  mList: TAtlasTestList;
begin
  mNodes := DemoNodes;
  mItems := TAtlasTestListView.Items(DemoInputs, mNodes);
  mList := ListOf(TAtlasTestListRule.Category('Schnell', True));
  // Filter „nicht gelaufen“: nur Teilt.Zwei und Spaeter passen.
  mVisible := TAtlasTestListView.Visible(mNodes, TAtlasTestExplorer.Visible(mNodes, [TAtlasTestFilter.NotRun], '',
    500), mItems, TAtlasTestListModel.Members(mList, mItems));
  Assert.IsFalse(mVisible[cAddiert], 'nicht in der Liste');
  Assert.IsFalse(mVisible[cEins], 'passt nicht zum Filter');
  Assert.IsTrue(mVisible[cZwei]);
  Assert.IsTrue(mVisible[cTeilt]);
  Assert.IsTrue(mVisible[cUnitNode]);
end;

procedure TAtlasTestListViewTests.NamesSkipChildrenOfSelected;
var
  mNames: TArray<string>;
begin
  mNames := TAtlasTestListView.Names(DemoNodes, TArray<Integer>.Create(cEins, cTeilt, cAddiert, 99));
  Assert.AreEqual('Demo.Tests.TRechnerTests.Teilt,Demo.Tests.TRechnerTests.Addiert', string.Join(',', mNames));
  mNames := TAtlasTestListView.Names(DemoNodes, TArray<Integer>.Create(cUnitNode));
  Assert.AreEqual('Demo.Tests', string.Join(',', mNames));
end;

procedure TAtlasTestListViewTests.CategoriesOfProject;
var
  mInputs: TArray<TAtlasTestUnitInput>;
begin
  mInputs := DemoInputs;
  mInputs[0].Found.Fixtures[0].Categories := TArray<string>.Create('Rechnen', 'schnell');
  Assert.AreEqual('Rechnen,schnell', string.Join(',', TAtlasTestListView.Categories(mInputs)),
    'sortiert, „schnell“ der Fixture und „Schnell“ des Tests einmal');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTestListViewTests);

end.
