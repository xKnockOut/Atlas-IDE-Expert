unit BDLsp.Common.Rules.Builtin.Exceptions.Tests;

// Tests für die Exception-Regeln (#277): je Regel ein positiver und ein negativer Fall.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TExceptionRulesTests = class
  public
    [Test]
    procedure GenericExceptionReported;
    [Test]
    procedure OwnExceptionClassSilent;
    [Test]
    procedure CatchAllWithoutRaiseReportedWhenEnabled;
    [Test]
    procedure CatchAllWithRaiseOrSpecificSilent;
    [Test]
    procedure FreedInHandlerReported;
    [Test]
    procedure FreedAfterRaiseReported;
    [Test]
    procedure NoDoubleFreeSilent;
  end;

implementation

uses
  System.SysUtils,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Rules.Builtin.Exceptions,
  BDLsp.Tests.RuleAssert;

const
  CatchAllOn = '{ "rules": { "catch-all-without-raise": "warning" } }';

function InRoutine(const ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10 + ABody + #10'end;'#10'end.';
end;

procedure TExceptionRulesTests.GenericExceptionReported;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TGenericExceptionRaisedRule.Create,
    InRoutine('  raise Exception.Create(''Kunde fehlt'');'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
  TRuleAssert.Reports(TGenericExceptionRaisedRule.Create,
    InRoutine('  raise System.SysUtils.Exception.CreateFmt(''%d'', [N]);'));
end;

procedure TExceptionRulesTests.OwnExceptionClassSilent;
begin
  TRuleAssert.Silent(TGenericExceptionRaisedRule.Create,
    InRoutine('  raise EKundeFehlt.Create(''Kunde fehlt'');'#10 +
    '  raise EArgumentException.Create(''X'');'#10'  raise;'));
end;

procedure TExceptionRulesTests.CatchAllWithoutRaiseReportedWhenEnabled;
const
  Source = '  try'#10'    Save;'#10'  except'#10'    on E: Exception do'#10'      Log(E.Message);'#10'  end;';
var
  Findings: TArray<TRuleFinding>;
begin
  // Ohne Profil für Bibliothekscode aus.
  TRuleAssert.Silent(TCatchAllWithoutRaiseRule.Create, InRoutine(Source));
  Findings := TRuleAssert.Findings(TCatchAllWithoutRaiseRule.Create, InRoutine(Source), CatchAllOn);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(8, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
end;

procedure TExceptionRulesTests.CatchAllWithRaiseOrSpecificSilent;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TCatchAllWithoutRaiseRule.Create,
    InRoutine('  try Save; except on E: Exception do begin Log(E.Message); raise; end; end;'#10 +
    '  try Save; except on E: EInOutError do Log(E.Message); end;'), CatchAllOn))));
end;

procedure TExceptionRulesTests.FreedInHandlerReported;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TExceptionFreedRule.Create,
    InRoutine('  try Save; except on E: Exception do begin Log(E.Message); E.Free; end; end;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
  TRuleAssert.Reports(TExceptionFreedRule.Create,
    InRoutine('  try Save; except on Fehler: EInOutError do FreeAndNil(Fehler); end;'));
end;

procedure TExceptionRulesTests.FreedAfterRaiseReported;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TExceptionFreedRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
    'procedure P;'#10'var'#10'  E: EKunde;'#10'begin'#10'  E := EKunde.Create(''X'');'#10'  try'#10 +
    '    raise E;'#10'  finally'#10'    E.Free;'#10'  end;'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(11, Findings[0].Range.StartPos.Line);
end;

procedure TExceptionRulesTests.NoDoubleFreeSilent;
begin
  TRuleAssert.Silent(TExceptionFreedRule.Create,
    InRoutine('  try Save; except on E: Exception do Log(E.Message); end;'#10 +
    '  Liste.Free;'#10'  raise EKunde.Create(''X'');'));
  TRuleAssert.Silent(TExceptionFreedRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
    'procedure A;'#10'begin'#10'  raise E;'#10'end;'#10'procedure B;'#10'begin'#10'  E.Free;'#10'end;'#10'end.');
end;

initialization
  TDUnitX.RegisterTestFixture(TExceptionRulesTests);

end.
