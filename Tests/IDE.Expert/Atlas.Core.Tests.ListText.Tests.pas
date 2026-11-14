unit Atlas.Core.Tests.ListText.Tests;

// Tests der Beschreibung einer Testliste (#2167): Regeln mit „und“, Stand als
// Text, feste Liste mit Zahl der Einträge; Einwände des Dialogs.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasTestListTextTests = class
  public
    [Test]
    procedure RulesJoinedWithAnd;
    [Test]
    procedure FixedListShowsCount;
    [Test]
    procedure ProblemsOfDialog;
  end;

implementation

uses
  Atlas.Core.Tests.Lists,
  Atlas.Core.Tests.ListText;

function Texts: TAtlasTestListTexts;
begin
  Result := Default(TAtlasTestListTexts);
  Result.Rules[TAtlasTestListRuleKind.Category, False] := 'Kategorie ist %s';
  Result.Rules[TAtlasTestListRuleKind.Category, True] := 'Kategorie ist nicht %s';
  Result.Rules[TAtlasTestListRuleKind.Pattern, False] := 'passt auf %s';
  Result.Rules[TAtlasTestListRuleKind.Pattern, True] := 'passt nicht auf %s';
  Result.Rules[TAtlasTestListRuleKind.State, False] := 'Stand ist %s';
  Result.Rules[TAtlasTestListRuleKind.State, True] := 'Stand ist nicht %s';
  Result.States[TAtlasTestListState.Failed] := 'fehlgeschlagen';
  Result.States[TAtlasTestListState.NotRun] := 'nicht gelaufen';
  Result.States[TAtlasTestListState.Stale] := 'veraltet';
  Result.AndText := ' und ';
  Result.Fixed := 'fest mit %d';
end;

procedure TAtlasTestListTextTests.RulesJoinedWithAnd;
var
  mList: TAtlasTestList;
begin
  mList := Default(TAtlasTestList);
  mList.Rules := [TAtlasTestListRule.Category('Benchmark', True), TAtlasTestListRule.Pattern('*.Slow.*', False),
    TAtlasTestListRule.OfState(TAtlasTestListState.Stale, False)];
  Assert.AreEqual('Kategorie ist nicht Benchmark und passt auf *.Slow.* und Stand ist veraltet',
    TAtlasTestListText.Describe(mList, Texts));
  Assert.AreEqual('Stand ist nicht fehlgeschlagen', TAtlasTestListText.RuleText(
    TAtlasTestListRule.OfState(TAtlasTestListState.Failed, True), Texts));
end;

procedure TAtlasTestListTextTests.FixedListShowsCount;
var
  mList: TAtlasTestList;
begin
  mList := Default(TAtlasTestList);
  mList.Tests := ['A', 'B.TFix'];
  Assert.AreEqual('fest mit 2', TAtlasTestListText.Describe(mList, Texts));
end;

procedure TAtlasTestListTextTests.ProblemsOfDialog;
var
  mList: TAtlasTestList;
begin
  mList := Default(TAtlasTestList);
  mList.Name := '  ';
  Assert.AreEqual<TAtlasTestListProblem>(TAtlasTestListProblem.NameMissing,
    TAtlasTestListText.Problem(mList, False, nil));
  mList.Name := 'Schnell ';
  Assert.AreEqual<TAtlasTestListProblem>(TAtlasTestListProblem.NameTaken,
    TAtlasTestListText.Problem(mList, False, ['Langsam', 'SCHNELL']));
  Assert.AreEqual<TAtlasTestListProblem>(TAtlasTestListProblem.NoRule,
    TAtlasTestListText.Problem(mList, True, ['Langsam']));
  Assert.AreEqual<TAtlasTestListProblem>(TAtlasTestListProblem.None,
    TAtlasTestListText.Problem(mList, False, ['Langsam']));
  mList.Rules := [TAtlasTestListRule.Category('Schnell', False)];
  Assert.AreEqual<TAtlasTestListProblem>(TAtlasTestListProblem.None, TAtlasTestListText.Problem(mList, True, nil));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTestListTextTests);

end.
