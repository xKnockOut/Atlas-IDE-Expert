unit Atlas.Core.Tests.Lists.Tests;

// Tests der Testlisten (#2167): Blätter, Muster, Regeln (Kategorie an Fixture
// und Test, Muster, Stand, „und“), feste Listen, Zählen, Argumente eines
// Laufs (Kategorie-Optionen, zusammengefasste Namen, Fälle, leere und zu
// lange Listen) und Lesen und Schreiben des JSON.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasTestListTests = class
  public
    [Test]
    procedure ItemsAreLeavesWithCategories;
    [Test]
    [TestCase('Stern', 'Atlas.Common.Pascal.*,Atlas.Common.Pascal.Lexer,True')]
    [TestCase('SternMitte', '*.Slow.*,Demo.Slow.Tests,True')]
    [TestCase('Fragezeichen', 'Demo.?ests,Demo.Tests,True')]
    [TestCase('GrossKlein', 'demo.TESTS,Demo.Tests,True')]
    [TestCase('KeinTreffer', 'Atlas.*,Demo.Tests,False')]
    [TestCase('ZuKurz', 'Demo,Demo.Tests,False')]
    procedure PatternMatches(const APattern, AText: string; AExpected: Boolean);
    [Test]
    procedure CategoryRuleSeesFixtureAndTest;
    [Test]
    procedure PatternAndStateRulesCombine;
    [Test]
    procedure NewTestJoinsDynamicList;
    [Test]
    procedure FixedListTakesNamedParts;
    [Test]
    procedure CountSkipsIgnored;
    [Test]
    procedure TestCategoryGoesAsOption;
    [Test]
    procedure FixtureCategoryIsEvaluated;
    [Test]
    procedure NamesUseCommonPrefix;
    [Test]
    procedure PrefixOnlyWhenAllFixturesFull;
    [Test]
    procedure CasesNamedSingly;
    [Test]
    procedure EmptyAndTooLong;
    [Test]
    procedure JsonRoundTrip;
    [Test]
    procedure ParseDropsInvalid;
    [Test]
    procedure AddRemoveAndUniqueName;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.DUnitX,
  Atlas.Core.Tests.Lists;

function NewTest(const AMethod: string; const ACategories: TArray<string>): TDUnitXTest;
begin
  Result := Default(TDUnitXTest);
  Result.Method := AMethod;
  Result.Categories := ACategories;
end;

function NewFixture(const AName: string; const ACategories: TArray<string>;
  const ATests: TArray<TDUnitXTest>): TDUnitXFixture;
begin
  Result := Default(TDUnitXFixture);
  Result.Name := AName;
  Result.Categories := ACategories;
  Result.Tests := ATests;
end;

function NewUnit(const AName: string; const AFixtures: TArray<TDUnitXFixture>): TDUnitXUnit;
begin
  Result := Default(TDUnitXUnit);
  Result.UnitName := AName;
  Result.Fixtures := AFixtures;
end;

/// <summary>Drei Units: Parser mit zwei Fixtures (eine als Modul gekennzeichnet), Slow mit einem Benchmark,
/// Rechner mit einem [TestCase]-Test und einem ignorierten Test.</summary>
function Sample: TArray<TDUnitXUnit>;
var
  mCases: TDUnitXTest;
  mIgnored: TDUnitXTest;
begin
  mCases := NewTest('Summe', nil);
  mCases.Cases := ['Klein', 'Gross'];
  mIgnored := NewTest('Alt', nil);
  mIgnored.Ignored := True;
  Result := [
    NewUnit('Atlas.Common.Pascal.Lexer.Tests', [
      NewFixture('TLexerTests', ['Parser'], [NewTest('Zahl', nil), NewTest('Wort', nil)]),
      NewFixture('TLexerTestsMore', nil, [NewTest('Rest', nil)])]),
    NewUnit('Demo.Slow.Tests', [
      NewFixture('TSlowTests', nil, [NewTest('Messen', ['Benchmark']), NewTest('Schnell', nil)])]),
    NewUnit('Demo.Rechner.Tests', [
      NewFixture('TRechnerTests', nil, [mCases, mIgnored])])];
end;

function Dynamic(const ARules: TArray<TAtlasTestListRule>): TAtlasTestList;
begin
  Result := Default(TAtlasTestList);
  Result.Name := 'Liste';
  Result.Rules := ARules;
end;

function Fixed(const ATests: TArray<string>): TAtlasTestList;
begin
  Result := Default(TAtlasTestList);
  Result.Name := 'Fest';
  Result.Tests := ATests;
end;

function Joined(const AItems: TArray<string>): string;
begin
  Result := string.Join('|', AItems);
end;

/// <summary>Volle Namen der Blätter von AItems, die zu AList gehören.</summary>
function MemberNames(const AList: TAtlasTestList; const AItems: TAtlasTestListItems): string;
var
  mMembers: TArray<Boolean>;
  mIndex: Integer;
  mNames: TArray<string>;
begin
  mMembers := TAtlasTestListModel.Members(AList, AItems);
  mNames := nil;
  for mIndex := 0 to High(AItems) do
  begin
    if mMembers[mIndex] then
    begin
      mNames := mNames + [AItems[mIndex].FullName];
    end;
  end;
  Result := Joined(mNames);
end;

{ TAtlasTestListTests }

procedure TAtlasTestListTests.ItemsAreLeavesWithCategories;
var
  mItems: TAtlasTestListItems;
begin
  mItems := TAtlasTestListModel.Items(Sample);
  Assert.AreEqual(8, Integer(Length(mItems)), '2 + 1 + 2 + 2 Fälle + 1 ignoriert');
  Assert.AreEqual('Atlas.Common.Pascal.Lexer.Tests.TLexerTests.Zahl', mItems[0].FullName);
  Assert.AreEqual('Atlas.Common.Pascal.Lexer.Tests.TLexerTests', mItems[0].FixtureName);
  Assert.AreEqual('Parser', Joined(mItems[0].Categories), 'Kategorie der Fixture');
  Assert.AreEqual('Benchmark', Joined(mItems[3].Categories), 'Kategorie des Tests');
  Assert.AreEqual('Demo.Rechner.Tests.TRechnerTests.Summe.Gross', mItems[6].FullName);
  Assert.AreEqual(1, mItems[6].CaseIndex);
  Assert.IsTrue(mItems[7].Ignored);
  Assert.AreEqual(-1, mItems[7].CaseIndex);
  Assert.IsTrue(mItems[0].NotRun, 'ohne Lauf');
  Assert.AreEqual(-1, mItems[0].Node);
end;

procedure TAtlasTestListTests.PatternMatches(const APattern, AText: string; AExpected: Boolean);
begin
  Assert.AreEqual(AExpected, TAtlasTestListModel.PatternMatches(APattern, AText));
end;

procedure TAtlasTestListTests.CategoryRuleSeesFixtureAndTest;
var
  mItems: TAtlasTestListItems;
begin
  mItems := TAtlasTestListModel.Items(Sample);
  Assert.AreEqual('Atlas.Common.Pascal.Lexer.Tests.TLexerTests.Zahl|Atlas.Common.Pascal.Lexer.Tests.TLexerTests.Wort',
    MemberNames(Dynamic([TAtlasTestListRule.Category('parser', False)]), mItems), 'an der Fixture');
  Assert.AreEqual('Demo.Slow.Tests.TSlowTests.Messen',
    MemberNames(Dynamic([TAtlasTestListRule.Category('Benchmark', False)]), mItems), 'am Test');
  Assert.IsFalse(Pos('Messen', MemberNames(Dynamic([TAtlasTestListRule.Category('Benchmark', True)]), mItems)) > 0,
    'ist nicht');
end;

procedure TAtlasTestListTests.PatternAndStateRulesCombine;
var
  mItems: TAtlasTestListItems;
  mList: TAtlasTestList;
begin
  mItems := TAtlasTestListModel.Items(Sample);
  mItems[0].Failed := True;
  mItems[0].NotRun := False;
  mItems[3].Failed := True;
  mItems[3].NotRun := False;
  mList := Dynamic([TAtlasTestListRule.Pattern('Atlas.Common.Pascal.*', False),
    TAtlasTestListRule.OfState(TAtlasTestListState.Failed, False)]);
  Assert.AreEqual('Atlas.Common.Pascal.Lexer.Tests.TLexerTests.Zahl', MemberNames(mList, mItems),
    'Muster und Stand mit „und“');
  mList := Dynamic([TAtlasTestListRule.Pattern('*.TLexerTestsMore', False)]);
  Assert.AreEqual('Atlas.Common.Pascal.Lexer.Tests.TLexerTestsMore.Rest', MemberNames(mList, mItems),
    'Muster auf Unit.Fixture');
  mList := Dynamic([TAtlasTestListRule.Pattern('*.Slow.*', True),
    TAtlasTestListRule.OfState(TAtlasTestListState.NotRun, False)]);
  Assert.AreEqual(5, Integer(Length(MemberNames(mList, mItems).Split(['|']))), 'ohne Slow, nur nicht gelaufene');
  mItems[4].Stale := True;
  Assert.AreEqual('Demo.Slow.Tests.TSlowTests.Schnell',
    MemberNames(Dynamic([TAtlasTestListRule.OfState(TAtlasTestListState.Stale, False)]), mItems));
end;

procedure TAtlasTestListTests.NewTestJoinsDynamicList;
var
  mUnits: TArray<TDUnitXUnit>;
  mList: TAtlasTestList;
  mBefore, mAfter: Integer;
  mTotal: Integer;
begin
  mUnits := Sample;
  mList := Dynamic([TAtlasTestListRule.Category('Benchmark', True)]);
  TAtlasTestListModel.Count(TAtlasTestListModel.Items(mUnits),
    TAtlasTestListModel.Members(mList, TAtlasTestListModel.Items(mUnits)), mBefore, mTotal);
  mUnits[1].Fixtures[0].Tests := mUnits[1].Fixtures[0].Tests + [NewTest('Neu', nil)];
  TAtlasTestListModel.Count(TAtlasTestListModel.Items(mUnits),
    TAtlasTestListModel.Members(mList, TAtlasTestListModel.Items(mUnits)), mAfter, mTotal);
  Assert.AreEqual(mBefore + 1, mAfter, 'neuer Test ohne Kategorie ist ohne Zutun dabei');
end;

procedure TAtlasTestListTests.FixedListTakesNamedParts;
var
  mItems: TAtlasTestListItems;
begin
  mItems := TAtlasTestListModel.Items(Sample);
  Assert.AreEqual('Atlas.Common.Pascal.Lexer.Tests.TLexerTests.Wort|Demo.Slow.Tests.TSlowTests.Messen|' +
    'Demo.Rechner.Tests.TRechnerTests.Summe.Klein',
    MemberNames(Fixed(['Atlas.Common.Pascal.Lexer.Tests.TLexerTests.Wort', 'Demo.Slow.Tests.TSlowTests.Messen',
    'Demo.Rechner.Tests.TRechnerTests.Summe.Klein']), mItems), 'genau diese drei');
  Assert.AreEqual('Atlas.Common.Pascal.Lexer.Tests.TLexerTests.Zahl|Atlas.Common.Pascal.Lexer.Tests.TLexerTests.Wort',
    MemberNames(Fixed(['Atlas.Common.Pascal.Lexer.Tests.TLexerTests']), mItems),
    'Fixture: nicht die Fixture mit gleichem Anfang');
  Assert.AreEqual(3, Integer(Length(MemberNames(Fixed(['Demo.Rechner.Tests']), mItems).Split(['|']))), 'Unit');
end;

procedure TAtlasTestListTests.CountSkipsIgnored;
var
  mItems: TAtlasTestListItems;
  mInList, mTotal: Integer;
begin
  mItems := TAtlasTestListModel.Items(Sample);
  TAtlasTestListModel.Count(mItems, TAtlasTestListModel.Members(Fixed(['Demo.Rechner.Tests']), mItems), mInList,
    mTotal);
  Assert.AreEqual(7, mTotal);
  Assert.AreEqual(2, mInList, 'ignorierter Test zählt nicht');
end;

procedure TAtlasTestListTests.TestCategoryGoesAsOption;
var
  mUnits: TArray<TDUnitXUnit>;
  mArguments: TArray<string>;
begin
  mUnits := Sample;
  Assert.AreEqual<TAtlasTestListRun>(TAtlasTestListRun.Ready,
    TAtlasTestListModel.RunArguments(Dynamic([TAtlasTestListRule.Category('Benchmark', True)]),
    TAtlasTestListModel.Items(mUnits), mUnits, mArguments));
  Assert.AreEqual('--exclude:Benchmark', Joined(mArguments), 'nur am Test: DUnitX wertet aus');
  TAtlasTestListModel.RunArguments(Dynamic([TAtlasTestListRule.Category('Benchmark', False),
    TAtlasTestListRule.Pattern('Demo.*', False)]), TAtlasTestListModel.Items(mUnits), mUnits, mArguments);
  Assert.AreEqual('--include:Benchmark|Demo', Joined(mArguments), 'Option und Namen zusammen');
end;

procedure TAtlasTestListTests.FixtureCategoryIsEvaluated;
var
  mUnits: TArray<TDUnitXUnit>;
  mArguments: TArray<string>;
begin
  mUnits := Sample;
  TAtlasTestListModel.RunArguments(Dynamic([TAtlasTestListRule.Category('Parser', False)]),
    TAtlasTestListModel.Items(mUnits), mUnits, mArguments);
  Assert.AreEqual('Atlas.Common.Pascal.Lexer.Tests.TLexerTests.Zahl|Atlas.Common.Pascal.Lexer.Tests.TLexerTests.Wort',
    Joined(mArguments), 'an einer Fixture: über die Namen; TLexerTests ist Anfang von TLexerTestsMore');
end;

procedure TAtlasTestListTests.NamesUseCommonPrefix;
var
  mUnits: TArray<TDUnitXUnit>;
  mArguments: TArray<string>;
begin
  mUnits := Sample;
  TAtlasTestListModel.RunArguments(Dynamic([TAtlasTestListRule.Pattern('Atlas.*', True)]),
    TAtlasTestListModel.Items(mUnits), mUnits, mArguments);
  Assert.AreEqual('Demo', Joined(mArguments), 'alle Demo-Fixtures ganz: ein Name');
  TAtlasTestListModel.RunArguments(Fixed(['Demo.Slow.Tests']), TAtlasTestListModel.Items(mUnits), mUnits,
    mArguments);
  Assert.AreEqual('Demo.Slow', Joined(mArguments), 'kürzester Anfang, den nur ganze Fixtures haben');
end;

procedure TAtlasTestListTests.PrefixOnlyWhenAllFixturesFull;
var
  mUnits: TArray<TDUnitXUnit>;
  mArguments: TArray<string>;
begin
  mUnits := Sample;
  TAtlasTestListModel.RunArguments(Fixed(['Atlas.Common.Pascal.Lexer.Tests.TLexerTestsMore']),
    TAtlasTestListModel.Items(mUnits), mUnits, mArguments);
  Assert.AreEqual('Atlas.Common.Pascal.Lexer.Tests.TLexerTestsMore', Joined(mArguments));
  TAtlasTestListModel.RunArguments(Fixed(['Atlas.Common.Pascal.Lexer.Tests.TLexerTests.Zahl',
    'Demo.Slow.Tests.TSlowTests.Schnell']), TAtlasTestListModel.Items(mUnits), mUnits, mArguments);
  Assert.AreEqual('Atlas.Common.Pascal.Lexer.Tests.TLexerTests.Zahl|Demo.Slow.Tests.TSlowTests.Schnell',
    Joined(mArguments), 'einzelne Tests');
end;

procedure TAtlasTestListTests.CasesNamedSingly;
var
  mUnits: TArray<TDUnitXUnit>;
  mArguments: TArray<string>;
begin
  mUnits := Sample;
  TAtlasTestListModel.RunArguments(Fixed(['Demo.Rechner.Tests.TRechnerTests.Summe.Gross']),
    TAtlasTestListModel.Items(mUnits), mUnits, mArguments);
  Assert.AreEqual('Demo.Rechner.Tests.TRechnerTests.Summe.Gross', Joined(mArguments));
  TAtlasTestListModel.RunArguments(Fixed(['Demo.Rechner.Tests.TRechnerTests.Summe']),
    TAtlasTestListModel.Items(mUnits), mUnits, mArguments);
  Assert.AreEqual('Demo.Rechner', Joined(mArguments), 'ignorierter Test steht einer ganzen Fixture nicht im Weg');
end;

procedure TAtlasTestListTests.EmptyAndTooLong;
var
  mUnits: TArray<TDUnitXUnit>;
  mArguments: TArray<string>;
  mTests: TArray<TDUnitXTest>;
  mIndex: Integer;
  mList: TAtlasTestList;
begin
  mUnits := Sample;
  Assert.AreEqual<TAtlasTestListRun>(TAtlasTestListRun.Empty,
    TAtlasTestListModel.RunArguments(Fixed(['Gibt.Es.Nicht']), TAtlasTestListModel.Items(mUnits),
    mUnits, mArguments));
  mTests := nil;
  mList := Fixed(nil);
  for mIndex := 0 to 2000 do
  begin
    mTests := mTests + [NewTest(Format('Test%.4d', [mIndex]), nil)];
    if Odd(mIndex) then
    begin
      mList.Tests := mList.Tests + [Format('Viele.TVieleTests.Test%.4d', [mIndex])];
    end;
  end;
  mUnits := [NewUnit('Viele', [NewFixture('TVieleTests', nil, mTests)])];
  Assert.AreEqual<TAtlasTestListRun>(TAtlasTestListRun.TooLong,
    TAtlasTestListModel.RunArguments(mList, TAtlasTestListModel.Items(mUnits), mUnits, mArguments));
  Assert.AreEqual(0, Integer(Length(mArguments)));
end;

procedure TAtlasTestListTests.JsonRoundTrip;
var
  mLists, mRead: TAtlasTestLists;
  mJson: string;
begin
  mLists := [Dynamic([TAtlasTestListRule.Category('Benchmark', True), TAtlasTestListRule.Pattern('*.Slow.*', True),
    TAtlasTestListRule.OfState(TAtlasTestListState.NotRun, False)]), Fixed(['Ä.TÖ.Ü', 'B'])];
  mLists[0].Name := 'Vor dem Commit';
  mJson := TAtlasTestListModel.ToJson(mLists, '');
  Assert.IsTrue(Pos('"exclude": true', mJson) > 0, mJson);
  Assert.IsTrue(Pos('"Ä.TÖ.Ü"', mJson) > 0, 'Umlaute lesbar');
  Assert.IsTrue(Pos('"notRun"', mJson) > 0, mJson);
  mRead := TAtlasTestListModel.Parse(mJson, TAtlasTestListStore.Personal);
  Assert.AreEqual(2, Integer(Length(mRead)));
  Assert.AreEqual('Vor dem Commit', mRead[0].Name);
  Assert.AreEqual<TAtlasTestListStore>(TAtlasTestListStore.Personal, mRead[0].Store);
  Assert.AreEqual(3, Integer(Length(mRead[0].Rules)));
  Assert.AreEqual<TAtlasTestListRuleKind>(TAtlasTestListRuleKind.Category, mRead[0].Rules[0].Kind);
  Assert.IsTrue(mRead[0].Rules[0].Exclude);
  Assert.AreEqual<TAtlasTestListRuleKind>(TAtlasTestListRuleKind.Pattern, mRead[0].Rules[1].Kind);
  Assert.AreEqual('*.Slow.*', mRead[0].Rules[1].Value);
  Assert.AreEqual<TAtlasTestListState>(TAtlasTestListState.NotRun, mRead[0].Rules[2].State);
  Assert.IsFalse(mRead[0].Rules[2].Exclude);
  Assert.IsFalse(mRead[1].IsDynamic);
  Assert.AreEqual('Ä.TÖ.Ü|B', Joined(mRead[1].Tests));
  Assert.AreEqual('[]', TAtlasTestListModel.ToJson(nil, ''));
  // Unter einem Schlüssel mit zwei Leerzeichen: Einträge vier, schließende Klammer zwei.
  mJson := TAtlasTestListModel.ToJson([Fixed(['A'])], '  ');
  Assert.IsTrue(Pos(#13#10'    {"name"', mJson) > 0, mJson);
  Assert.IsTrue(Pos(#13#10'        "A"'#13#10'      ]}'#13#10'  ]', mJson) > 0, mJson);
end;

procedure TAtlasTestListTests.ParseDropsInvalid;
var
  mRead: TAtlasTestLists;
begin
  mRead := TAtlasTestListModel.Parse('[{"name": ""}, {"name": "A", "rules": [{"state": "gelb"}, {"unit": 3}, ' +
    '{"category": "K"}], "tests": [1, "X"]}, {"name": "a"}, 5]', TAtlasTestListStore.Project);
  Assert.AreEqual(1, Integer(Length(mRead)), 'ohne Namen, doppelter Name und kein Objekt fallen weg');
  Assert.AreEqual(1, Integer(Length(mRead[0].Rules)), 'unbekannter Stand und Zahl als Muster fallen weg');
  Assert.AreEqual('X', Joined(mRead[0].Tests));
  Assert.AreEqual(0, Integer(Length(TAtlasTestListModel.Parse('{kaputt', TAtlasTestListStore.Project))));
  Assert.AreEqual(0, Integer(Length(TAtlasTestListModel.Parse('{"name": "A"}', TAtlasTestListStore.Project))));
end;

procedure TAtlasTestListTests.AddRemoveAndUniqueName;
var
  mList: TAtlasTestList;
  mLists: TAtlasTestLists;
begin
  mList := Fixed(['U.TF']);
  Assert.AreEqual(1, TAtlasTestListModel.AddTests(mList, ['U.TF.Test', 'U.TG', 'u.tg', '']),
    'unter einem vorhandenen Namen und doppelte nicht');
  Assert.AreEqual('U.TF|U.TG', Joined(mList.Tests));
  Assert.AreEqual(1, TAtlasTestListModel.RemoveTests(mList, ['U.TG']));
  Assert.AreEqual('U.TF', Joined(mList.Tests));
  Assert.AreEqual(1, TAtlasTestListModel.RemoveTests(mList, ['U']), 'Unit entfernt die Fixture darunter');
  mLists := [Fixed(nil), Fixed(nil)];
  mLists[1].Name := 'Fest (2)';
  Assert.AreEqual('Fest (3)', TAtlasTestListModel.UniqueName(mLists, 'Fest'));
  Assert.AreEqual('Neu', TAtlasTestListModel.UniqueName(mLists, 'Neu'));
  Assert.AreEqual(1, TAtlasTestListModel.IndexOf(mLists, 'fest (2)'));
  mLists[0].Store := TAtlasTestListStore.Personal;
  Assert.AreEqual('Fest (2)', TAtlasTestListModel.OfStore(mLists, TAtlasTestListStore.Project)[0].Name);
  Assert.AreEqual(1, Integer(Length(TAtlasTestListModel.OfStore(mLists, TAtlasTestListStore.Personal))));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTestListTests);

end.
