unit Atlas.Text.StepFilter.Tests;

// Tests für die Arten und Muster der Schrittfilter (#850): Arten lesen und
// schreiben, Muster mit * und weggelassenen Teilen vorn, Listen mit ; und
// Zeilen, Hinzufügen und Entfernen fürs Kontextmenü.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TStepFilterNamesTests = class
  public
    [Test]
    procedure KindsInFixedOrderWithoutUnknown;
    [Test]
    procedure DefaultKindsAreGettersAndTrivial;
    [Test]
    procedure WildcardMatchesAcrossDots;
    [Test]
    procedure LeadingPartsMayBeOmitted;
    [Test]
    procedure WithoutWildcardWholePartsOnly;
    [Test]
    procedure CaseIsIgnored;
    [Test]
    procedure InvalidPatternsNeverMatch;
    [Test]
    procedure PatternListSeparatorsAndDuplicates;
    [Test]
    procedure GenericArgumentsKeepTheirComma;
    [Test]
    procedure AddAndRemovePattern;
    [Test]
    procedure MatchingPatternIndex;
  end;

implementation

uses
  Atlas.Text.StepFilter;

{ TStepFilterNamesTests }

procedure TStepFilterNamesTests.KindsInFixedOrderWithoutUnknown;
begin
  Assert.AreEqual('getters,trivial,operators',
    TStepFilterNames.NormalizeKinds(' Operators, getters ;TRIVIAL, quatsch'));
  Assert.AreEqual('', TStepFilterNames.NormalizeKinds(''));
  Assert.AreEqual('getters,setters,trivial,operators,emptyConstructors',
    TStepFilterNames.KindsText(TStepFilterNames.AllKinds));
  Assert.IsTrue(TStepFilterNames.ParseKinds('emptyconstructors') = [TStepFilterKind.EmptyConstructors]);
end;

procedure TStepFilterNamesTests.DefaultKindsAreGettersAndTrivial;
begin
  Assert.AreEqual('getters,trivial', TStepFilterNames.KindsText(TStepFilterNames.DefaultKinds));
end;

procedure TStepFilterNamesTests.WildcardMatchesAcrossDots;
begin
  Assert.IsTrue(TStepFilterNames.Matches('*.Log*', 'Protokoll.TProtokoll.LogInfo'));
  Assert.IsTrue(TStepFilterNames.Matches('Protokoll.*', 'Protokoll.TProtokoll.LogInfo'));
  Assert.IsTrue(TStepFilterNames.Matches('*Info', 'Protokoll.TProtokoll.LogInfo'));
  Assert.IsTrue(TStepFilterNames.Matches('Pro*Log*o', 'Protokoll.TProtokoll.LogInfo'));
  Assert.IsFalse(TStepFilterNames.Matches('*.Log*', 'Protokoll.TProtokoll.Schreibe'));
  Assert.IsFalse(TStepFilterNames.Matches('*.Log', 'Protokoll.TProtokoll.LogInfo'));
end;

procedure TStepFilterNamesTests.LeadingPartsMayBeOmitted;
begin
  Assert.IsTrue(TStepFilterNames.Matches('TBasisForm.*', 'Formulare.TBasisForm.Zeigen'));
  Assert.IsTrue(TStepFilterNames.Matches('TKunde.GetName', 'Kunden.TKunde.GetName'));
  Assert.IsTrue(TStepFilterNames.Matches('GetName', 'Kunden.TKunde.GetName'));
  Assert.IsFalse(TStepFilterNames.Matches('TBasisForm.*', 'Formulare.TAnderesForm.Zeigen'));
end;

procedure TStepFilterNamesTests.WithoutWildcardWholePartsOnly;
begin
  Assert.IsFalse(TStepFilterNames.Matches('Kunde.GetName', 'Kunden.TKunde.GetName'));
  Assert.IsFalse(TStepFilterNames.Matches('Name', 'Kunden.TKunde.GetName'));
  Assert.IsFalse(TStepFilterNames.Matches('TKunde', 'Kunden.TKunde.GetName'));
end;

procedure TStepFilterNamesTests.CaseIsIgnored;
begin
  Assert.IsTrue(TStepFilterNames.Matches('*.log*', 'Protokoll.TProtokoll.LogInfo'));
  Assert.IsTrue(TStepFilterNames.Matches('tbasisform.*', 'Formulare.TBasisForm.Zeigen'));
end;

procedure TStepFilterNamesTests.InvalidPatternsNeverMatch;
begin
  Assert.IsFalse(TStepFilterNames.IsValidPattern(''));
  Assert.IsFalse(TStepFilterNames.IsValidPattern('*.*'));
  Assert.IsFalse(TStepFilterNames.IsValidPattern('T Kunde.*'));
  Assert.IsFalse(TStepFilterNames.IsValidPattern('A;B'));
  Assert.IsTrue(TStepFilterNames.IsValidPattern('*X'));
  Assert.IsFalse(TStepFilterNames.Matches('*.*', 'Protokoll.TProtokoll.LogInfo'));
  Assert.IsFalse(TStepFilterNames.Matches('*.Log*', ''));
end;

procedure TStepFilterNamesTests.PatternListSeparatorsAndDuplicates;
var
  mPatterns: TArray<string>;
begin
  mPatterns := TStepFilterNames.ParsePatterns(' *.Log* ;TBasisForm.*'#13#10'*.log*;;Ungültig Muster;X.Y');
  Assert.AreEqual(3, Integer(Length(mPatterns)));
  Assert.AreEqual('*.Log*', mPatterns[0]);
  Assert.AreEqual('TBasisForm.*', mPatterns[1]);
  Assert.AreEqual('X.Y', mPatterns[2]);
  Assert.AreEqual('*.Log*;TBasisForm.*;X.Y', TStepFilterNames.PatternsText(mPatterns));
  Assert.AreEqual('', TStepFilterNames.NormalizePatterns(' ; '));
end;

procedure TStepFilterNamesTests.GenericArgumentsKeepTheirComma;
var
  mPatterns: TArray<string>;
begin
  mPatterns := TStepFilterNames.ParsePatterns('TDictionary<K,V>.Add;B.*');
  Assert.AreEqual(2, Integer(Length(mPatterns)));
  Assert.AreEqual('TDictionary<K,V>.Add', mPatterns[0]);
end;

procedure TStepFilterNamesTests.AddAndRemovePattern;
var
  mPatterns: TArray<string>;
begin
  mPatterns := TStepFilterNames.WithPattern(nil, 'Kunden.TKunde.GetName');
  Assert.AreEqual(1, Integer(Length(mPatterns)));
  mPatterns := TStepFilterNames.WithPattern(mPatterns, 'kunden.tkunde.getname');
  Assert.AreEqual(1, Integer(Length(mPatterns)), 'doppelt ohne Groß-/Kleinschreibung');
  mPatterns := TStepFilterNames.WithPattern(mPatterns, ' ');
  Assert.AreEqual(1, Integer(Length(mPatterns)), 'ungültig');
  mPatterns := TStepFilterNames.WithPattern(mPatterns, '*.Log*');
  Assert.AreEqual(1, TStepFilterNames.IndexOfPattern(mPatterns, '*.LOG*'));
  mPatterns := TStepFilterNames.WithoutPattern(mPatterns, 'KUNDEN.TKUNDE.GETNAME');
  Assert.AreEqual(1, Integer(Length(mPatterns)));
  Assert.AreEqual('*.Log*', mPatterns[0]);
end;

procedure TStepFilterNamesTests.MatchingPatternIndex;
var
  mPatterns: TArray<string>;
begin
  mPatterns := TArray<string>.Create('TBasisForm.*', '*.Log*');
  Assert.AreEqual(1, TStepFilterNames.MatchingPattern(mPatterns, 'Protokoll.TProtokoll.LogInfo'));
  Assert.AreEqual(0, TStepFilterNames.MatchingPattern(mPatterns, 'Formulare.TBasisForm.Log'));
  Assert.AreEqual(-1, TStepFilterNames.MatchingPattern(mPatterns, 'Kunden.TKunde.GetName'));
end;

initialization
  TDUnitX.RegisterTestFixture(TStepFilterNamesTests);

end.
