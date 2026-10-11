unit Atlas.Common.Rules.Baseline.Tests;

// Tests für die Baseline bekannter Treffer (#97).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleBaselineTests = class
  public
    [Test]
    procedure HidesKnownFindings;
    [Test]
    procedure SurvivesShiftedLines;
    [Test]
    procedure ReportsChangedLine;
    [Test]
    procedure ReportsAdditionalIdenticalFinding;
    [Test]
    procedure MatchesPathsWithEitherSeparator;
    [Test]
    procedure IgnoresIndentation;
    [Test]
    procedure BuildDropsVanishedFindings;
    [Test]
    procedure BuildIsSortedAndCounts;
    [Test]
    procedure RejectsWrongVersion;
    [Test]
    procedure RejectsIncompleteEntry;
    [Test]
    procedure FilterDoesNotConsumeBaseline;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Baseline;

const
  Original = 'unit U;' + #10 + 'begin' + #10 + '  X := 1;' + #10 + 'end.';

function Finding(const ARuleId: string; ALine: Integer): TRuleFinding;
begin
  Result := Default(TRuleFinding);
  Result.RuleId := ARuleId;
  Result.Range := TTextRange.Create(TTextPosition.Create(ALine, 0), TTextPosition.Create(ALine, 1));
end;

function Source(const APath, AText: string; const AFindings: TArray<TRuleFinding>): TBaselineSource;
begin
  Result.Path := APath;
  Result.Text := AText;
  Result.Findings := AFindings;
end;

function BaselineOf(const ASources: TArray<TBaselineSource>): IRuleBaseline;
begin
  Result := TRuleBaseline.FromJson(TRuleBaseline.Build(ASources));
end;

procedure ExpectBaselineError(const AJson: string);
var
  Raised: Boolean;
begin
  Raised := False;
  try
    TRuleBaseline.FromJson(AJson);
  except
    on ERuleBaseline do
      Raised := True;
  end;
  Assert.IsTrue(Raised, AJson);
end;

{ TRuleBaselineTests }

procedure TRuleBaselineTests.HidesKnownFindings;
var
  Baseline: IRuleBaseline;
begin
  Baseline := BaselineOf([Source('Src\U.pas', Original, [Finding('a', 2)])]);
  Assert.AreEqual(1, Baseline.Count);
  Assert.AreEqual<NativeInt>(0, Length(Baseline.Filter('Src\U.pas', Original, [Finding('a', 2)])));
  // Andere Regel in derselben Zeile ist neu.
  Assert.AreEqual<NativeInt>(1, Length(Baseline.Filter('Src\U.pas', Original, [Finding('b', 2)])));
  // Andere Datei ebenso.
  Assert.AreEqual<NativeInt>(1, Length(Baseline.Filter('Src\V.pas', Original, [Finding('a', 2)])));
end;

procedure TRuleBaselineTests.SurvivesShiftedLines;
var
  Baseline: IRuleBaseline;
  Shifted: string;
begin
  Baseline := BaselineOf([Source('U.pas', Original, [Finding('a', 2)])]);
  Shifted := 'unit U;' + #10 + '// neu' + #10 + '// neu' + #10 + 'begin' + #10 + '  X := 1;' + #10 + 'end.';
  Assert.AreEqual<NativeInt>(0, Length(Baseline.Filter('U.pas', Shifted, [Finding('a', 4)])));
end;

procedure TRuleBaselineTests.ReportsChangedLine;
var
  Baseline: IRuleBaseline;
begin
  Baseline := BaselineOf([Source('U.pas', Original, [Finding('a', 2)])]);
  Assert.AreEqual<NativeInt>(1, Length(Baseline.Filter('U.pas', StringReplace(Original, 'X := 1', 'X := 2', []),
    [Finding('a', 2)])));
end;

procedure TRuleBaselineTests.ReportsAdditionalIdenticalFinding;
var
  Baseline: IRuleBaseline;
  Twice: string;
  Remaining: TArray<TRuleFinding>;
begin
  Baseline := BaselineOf([Source('U.pas', Original, [Finding('a', 2)])]);
  Twice := 'unit U;' + #10 + 'begin' + #10 + '  X := 1;' + #10 + '  X := 1;' + #10 + 'end.';
  Remaining := Baseline.Filter('U.pas', Twice, [Finding('a', 2), Finding('a', 3)]);
  Assert.AreEqual<NativeInt>(1, Length(Remaining));
  Assert.AreEqual(3, Remaining[0].Range.StartPos.Line);
end;

procedure TRuleBaselineTests.MatchesPathsWithEitherSeparator;
var
  Baseline: IRuleBaseline;
begin
  Baseline := BaselineOf([Source('Src\Sub\U.pas', Original, [Finding('a', 2)])]);
  Assert.AreEqual<NativeInt>(0, Length(Baseline.Filter('src/sub/u.pas', Original, [Finding('A', 2)])));
end;

procedure TRuleBaselineTests.IgnoresIndentation;
var
  Baseline: IRuleBaseline;
begin
  Baseline := BaselineOf([Source('U.pas', Original, [Finding('a', 2)])]);
  Assert.AreEqual<NativeInt>(0, Length(Baseline.Filter('U.pas',
    StringReplace(Original, '  X := 1;', #9'X  :=   1;'#13, []), [Finding('a', 2)])));
end;

procedure TRuleBaselineTests.BuildDropsVanishedFindings;
var
  Baseline: IRuleBaseline;
begin
  // Neu geschrieben enthält die Baseline nur, was aktuell gefunden wird.
  Baseline := BaselineOf([Source('U.pas', Original, [Finding('a', 2)]), Source('V.pas', Original, nil)]);
  Assert.AreEqual(1, Baseline.Count);
  Baseline := BaselineOf([Source('U.pas', Original, nil)]);
  Assert.AreEqual(0, Baseline.Count);
  Assert.AreEqual<NativeInt>(1, Length(Baseline.Filter('U.pas', Original, [Finding('a', 2)])));
end;

procedure TRuleBaselineTests.BuildIsSortedAndCounts;
var
  Json: string;
begin
  Json := TRuleBaseline.Build([Source('B.pas', Original, [Finding('z', 2)]),
    Source('A.pas', Original, [Finding('a', 2), Finding('a', 2)])]);
  Assert.IsTrue(Pos('"version": 1', Json) > 0, Json);
  Assert.IsTrue(Pos('"path": "A.pas"', Json) < Pos('"path": "B.pas"', Json), Json);
  Assert.IsTrue(Pos('"rule": "a", "fingerprint": "' + TRuleBaseline.Fingerprint(Original, Finding('a', 2)) +
    '", "count": 2', Json) > 0, Json);
end;

procedure TRuleBaselineTests.RejectsWrongVersion;
begin
  ExpectBaselineError('{"version":2,"findings":[]}');
  ExpectBaselineError('[]');
end;

procedure TRuleBaselineTests.RejectsIncompleteEntry;
begin
  ExpectBaselineError('{"version":1,"findings":[{"path":"U.pas","rule":"a"}]}');
end;

procedure TRuleBaselineTests.FilterDoesNotConsumeBaseline;
var
  Baseline: IRuleBaseline;
begin
  Baseline := BaselineOf([Source('U.pas', Original, [Finding('a', 2)])]);
  Assert.AreEqual<NativeInt>(0, Length(Baseline.Filter('U.pas', Original, [Finding('a', 2)])));
  Assert.AreEqual<NativeInt>(0, Length(Baseline.Filter('U.pas', Original, [Finding('a', 2)])));
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleBaselineTests);

end.
