unit Atlas.Common.Rules.Checker.Tests;

// Tests für die Prüfung eines Textes durch den Kommandozeilen-Linter: Syntax, Sprachstand, Ausschlüsse,
// Abschnitte und Package der Datei.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFileCheckerTests = class
  public
    [Test]
    procedure CheckerReportsSyntaxErrors;
    [Test]
    procedure CheckerSilentOnValidCode;
    [Test]
    procedure CheckerSkipsExcludedFile;
    [Test]
    procedure CheckerSyntaxRuleCanBeTurnedOff;
    [Test]
    procedure CheckerReportsLanguageFeaturesBelowMinDelphiVersion;
    [Test]
    procedure CheckerLeavesIfExpressionsToTheirRule;
    [Test]
    procedure CheckerReturnsScopes;
    [Test]
    procedure CheckerPassesPackageToRules;
  end;

implementation

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Findings.Scopes,
  Atlas.Common.Rules.Builtin.Concurrency.MainThread,
  Atlas.Common.Projects.PackageReader;

function Settings(const AJson: string): TServerSettings;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  Result := TConfigurationParser.Parse(AJson, mIssues);
end;

{ TFileCheckerTests }

procedure TFileCheckerTests.CheckerReportsSyntaxErrors;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TFileChecker.CheckText(nil, TServerSettings.Default, 'U.pas',
    'unit U; interface implementation procedure P; begin if then end; end.');
  Assert.IsTrue(Length(mFindings) > 0);
  Assert.AreEqual(cSyntaxRuleId, mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(mFindings[0].Severity));
end;

procedure TFileCheckerTests.CheckerSilentOnValidCode;
begin
  Assert.AreEqual(0, Integer(Length(TFileChecker.CheckText(nil, TServerSettings.Default, 'U.pas',
    'unit U; interface implementation end.'))));
end;

procedure TFileCheckerTests.CheckerSkipsExcludedFile;
begin
  Assert.AreEqual(0, Integer(Length(TFileChecker.CheckText(nil, Settings('{ "exclude": ["Gen/**"] }'),
    'Gen\U.pas', 'unit U; begin if then'))));
end;

procedure TFileCheckerTests.CheckerSyntaxRuleCanBeTurnedOff;
begin
  Assert.AreEqual(0, Integer(Length(TFileChecker.CheckText(nil, Settings('{ "rules": { "syntax": "off" } }'),
    'U.pas', 'unit U; begin if then'))));
end;

procedure TFileCheckerTests.CheckerReportsLanguageFeaturesBelowMinDelphiVersion;
const
  cSource = 'unit U; interface implementation function F(A: TObject): Boolean; ' +
    'begin Result := A is not TList; end; end.';
var
  mFindings: TArray<TRuleFinding>;
begin
  // #1126: Ohne Sprachstand meldet Atlas nichts; mit minDelphiVersion 12 ist "is not" (Delphi 13) ein Befund.
  Assert.AreEqual(0, Integer(Length(TFileChecker.CheckText(nil, Settings('{}'), 'U.pas', cSource))));
  mFindings := TFileChecker.CheckText(nil, Settings('{ "minDelphiVersion": "12" }'), 'U.pas', cSource);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(cLanguageFeatureRuleId, mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
  Assert.IsTrue(Pos('Delphi 13', mFindings[0].Message) > 0, mFindings[0].Message);
  Assert.AreEqual(0, Integer(Length(TFileChecker.CheckText(nil, Settings('{ "minDelphiVersion": "13" }'), 'U.pas',
    cSource))));
  Assert.AreEqual(0, Integer(Length(TFileChecker.CheckText(nil,
    Settings('{ "minDelphiVersion": "12", "rules": { "language-feature": "off" } }'), 'U.pas', cSource))));
end;

procedure TFileCheckerTests.CheckerLeavesIfExpressionsToTheirRule;
const
  cSource = 'unit U; interface implementation function F(A: Boolean): Integer; ' +
    'begin Result := if A then 1 else 2; end; end.';
begin
  // #684 mit #1126: Bedingungsausdrücke meldet conditional-expression-version als Fehler mit Korrektur, nicht
  // zusätzlich language-feature.
  Assert.AreEqual(0, Integer(Length(TFileChecker.CheckText(nil, Settings('{ "minDelphiVersion": "12" }'), 'U.pas',
    cSource))));
end;

procedure TFileCheckerTests.CheckerReturnsScopes;
var
  mScopes: TFindingScopes;
begin
  TFileChecker.CheckText(nil, Settings('{}'), 'U.pas',
    'unit U; interface implementation procedure TFoo.Bar; begin end; end.', mScopes);
  Assert.AreEqual(1, mScopes.RoutineCount);
  Assert.AreEqual('TFoo.Bar', mScopes.At(0));
end;

procedure TFileCheckerTests.CheckerPassesPackageToRules;
const
  cSource = 'unit Laden;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10 +
    '  TThread.Queue(nil, Start);'#10'end;'#10'end.';
var
  mPackages: TArray<TPackageSource>;
  mProject: TCheckProject;
  mFindings: TArray<TRuleFinding>;
begin
  mPackages := [TPackageReader.Read('package Werkzeuge;'#10'requires rtl;'#10'contains'#10 +
    '  Laden in ''Laden.pas'';'#10'end.')];
  mProject := TFileChecker.PackageOf(mPackages, 'laden');
  Assert.AreEqual(Ord(TRuleApplicationKind.Package), Ord(mProject.Application));
  Assert.AreEqual('Werkzeuge', mProject.Name);
  Assert.AreEqual(Ord(TRuleApplicationKind.Unknown), Ord(TFileChecker.PackageOf(mPackages, 'Andere').Application));
  // queue-nil-in-package (#943) meldet nur mit Package.
  mFindings := TFileChecker.CheckText([TQueueNilInPackageRule.Create], Settings('{}'), 'Laden.pas', cSource, mProject);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.Contains(mFindings[0].Message, 'Werkzeuge.bpl');
  Assert.AreEqual(0, Integer(Length(TFileChecker.CheckText([TQueueNilInPackageRule.Create], Settings('{}'),
    'Laden.pas', cSource))));
end;

initialization
  TDUnitX.RegisterTestFixture(TFileCheckerTests);

end.
