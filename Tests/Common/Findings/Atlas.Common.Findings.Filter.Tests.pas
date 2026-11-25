unit Atlas.Common.Findings.Filter.Tests;

// Tests für den Filter der Linter-Ausgabe: Regeln, Schweregrad, Units und Masken (#95).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFindingFilterTests = class
  public
    [Test]
    procedure FilterByRule;
    [Test]
    procedure FilterBySeverity;
    [Test]
    procedure FilterByUnitNameAndGlob;
    [Test]
    procedure SplitListTrimsAndSkipsEmpty;
  end;

implementation

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Findings.Contract,
  Atlas.Common.Findings.Filter;

function MakeFinding(const ARuleId: string; ASeverity: TRuleSeverity): TRuleFinding;
begin
  Result := Default(TRuleFinding);
  Result.RuleId := ARuleId;
  Result.Severity := ASeverity;
end;

{ TFindingFilterTests }

procedure TFindingFilterTests.FilterByRule;
var
  mFilter: TFindingFilter;
begin
  mFilter := Default(TFindingFilter);
  mFilter.Rules := ['Empty-Except'];
  Assert.IsTrue(mFilter.AcceptsFinding(MakeFinding('empty-except', TRuleSeverity.Hint)));
  Assert.IsFalse(mFilter.AcceptsFinding(MakeFinding('syntax', TRuleSeverity.Error)));
end;

procedure TFindingFilterTests.FilterBySeverity;
var
  mFilter: TFindingFilter;
begin
  mFilter := Default(TFindingFilter);
  mFilter.MinSeverity := TRuleSeverity.Warning;
  Assert.AreEqual(2, Integer(Length(mFilter.Apply([MakeFinding('a', TRuleSeverity.Hint),
    MakeFinding('b', TRuleSeverity.Warning), MakeFinding('c', TRuleSeverity.Information),
    MakeFinding('d', TRuleSeverity.Error)]))));
end;

procedure TFindingFilterTests.FilterByUnitNameAndGlob;
var
  mFilter: TFindingFilter;
begin
  mFilter := Default(TFindingFilter);
  Assert.IsTrue(mFilter.AcceptsFile('Src\Any.pas'));
  mFilter.Units := ['Main.Form', 'Legacy/**'];
  Assert.IsTrue(mFilter.AcceptsFile('Src\Main.Form.pas'));
  Assert.IsTrue(mFilter.AcceptsFile('Legacy\Alt\X.pas'));
  Assert.IsFalse(mFilter.AcceptsFile('Src\Other.pas'));
end;

procedure TFindingFilterTests.SplitListTrimsAndSkipsEmpty;
var
  mParts: TArray<string>;
begin
  mParts := TFindingFilter.SplitList(' a, ,b ,');
  Assert.AreEqual(2, Integer(Length(mParts)));
  Assert.AreEqual('a', mParts[0]);
  Assert.AreEqual('b', mParts[1]);
end;

initialization
  TDUnitX.RegisterTestFixture(TFindingFilterTests);

end.
