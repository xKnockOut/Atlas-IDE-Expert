unit BDLsp.Common.Rules.Output.Tests;

// Tests für den Kommandozeilen-Linter: Prüfung eines Textes, Filter,
// Ausgabe als Text, JSON und SARIF sowie Exit-Code (#95).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLinterOutputTests = class
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
    procedure FilterByRule;
    [Test]
    procedure FilterBySeverity;
    [Test]
    procedure FilterByUnitNameAndGlob;
    [Test]
    procedure SplitListTrimsAndSkipsEmpty;
    [Test]
    procedure RendersTextLikeCompiler;
    [Test]
    procedure RendersJsonWithSummary;
    [Test]
    procedure RendersSarifResult;
    [Test]
    procedure EscapesJsonStrings;
    [Test]
    procedure ExitCodeFollowsHighestSeverity;
    [Test]
    procedure ParsesFormat;
  end;

implementation

uses
  System.SysUtils,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Configuration.Parser,
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Rules.Checker,
  BDLsp.Common.Rules.Filter,
  BDLsp.Common.Rules.Output;

function MakeFinding(const ARuleId: string; ASeverity: TRuleSeverity; ALine: Integer = 0): TRuleFinding;
begin
  Result := Default(TRuleFinding);
  Result.RuleId := ARuleId;
  Result.Severity := ASeverity;
  Result.Confidence := TRuleConfidence.High;
  Result.Message := 'Meldung';
  Result.Range := TTextRange.Create(ALine, 2, ALine, 5);
end;

function MakeFile(const APath: string; const AFindings: TArray<TRuleFinding>): TCheckedFile;
begin
  Result.Path := APath;
  Result.Findings := AFindings;
end;

function Settings(const AJson: string): TServerSettings;
var
  Issues: TArray<TConfigurationIssue>;
begin
  Result := TConfigurationParser.Parse(AJson, Issues);
end;

{ TLinterOutputTests }

procedure TLinterOutputTests.CheckerReportsSyntaxErrors;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TFileChecker.CheckText(nil, TServerSettings.Default, 'U.pas',
    'unit U; interface implementation procedure P; begin if then end; end.');
  Assert.IsTrue(Length(Findings) > 0);
  Assert.AreEqual(SyntaxRuleId, Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
end;

procedure TLinterOutputTests.CheckerSilentOnValidCode;
begin
  Assert.AreEqual(0, Integer(Length(TFileChecker.CheckText(nil, TServerSettings.Default, 'U.pas',
    'unit U; interface implementation end.'))));
end;

procedure TLinterOutputTests.CheckerSkipsExcludedFile;
begin
  Assert.AreEqual(0, Integer(Length(TFileChecker.CheckText(nil, Settings('{ "exclude": ["Gen/**"] }'),
    'Gen\U.pas', 'unit U; begin if then'))));
end;

procedure TLinterOutputTests.CheckerSyntaxRuleCanBeTurnedOff;
begin
  Assert.AreEqual(0, Integer(Length(TFileChecker.CheckText(nil, Settings('{ "rules": { "syntax": "off" } }'),
    'U.pas', 'unit U; begin if then'))));
end;

procedure TLinterOutputTests.FilterByRule;
var
  Filter: TFindingFilter;
begin
  Filter := Default(TFindingFilter);
  Filter.Rules := ['Empty-Except'];
  Assert.IsTrue(Filter.AcceptsFinding(MakeFinding('empty-except', TRuleSeverity.Hint)));
  Assert.IsFalse(Filter.AcceptsFinding(MakeFinding('syntax', TRuleSeverity.Error)));
end;

procedure TLinterOutputTests.FilterBySeverity;
var
  Filter: TFindingFilter;
begin
  Filter := Default(TFindingFilter);
  Filter.MinSeverity := TRuleSeverity.Warning;
  Assert.AreEqual(2, Integer(Length(Filter.Apply([MakeFinding('a', TRuleSeverity.Hint),
    MakeFinding('b', TRuleSeverity.Warning), MakeFinding('c', TRuleSeverity.Information),
    MakeFinding('d', TRuleSeverity.Error)]))));
end;

procedure TLinterOutputTests.FilterByUnitNameAndGlob;
var
  Filter: TFindingFilter;
begin
  Filter := Default(TFindingFilter);
  Assert.IsTrue(Filter.AcceptsFile('Src\Any.pas'));
  Filter.Units := ['Main.Form', 'Legacy/**'];
  Assert.IsTrue(Filter.AcceptsFile('Src\Main.Form.pas'));
  Assert.IsTrue(Filter.AcceptsFile('Legacy\Alt\X.pas'));
  Assert.IsFalse(Filter.AcceptsFile('Src\Other.pas'));
end;

procedure TLinterOutputTests.SplitListTrimsAndSkipsEmpty;
var
  Parts: TArray<string>;
begin
  Parts := TFindingFilter.SplitList(' a, ,b ,');
  Assert.AreEqual(2, Integer(Length(Parts)));
  Assert.AreEqual('a', Parts[0]);
  Assert.AreEqual('b', Parts[1]);
end;

procedure TLinterOutputTests.RendersTextLikeCompiler;
var
  Output: string;
begin
  Output := TFindingsOutput.Render([MakeFile('Src\U.pas', [MakeFinding('syntax', TRuleSeverity.Error, 4)]),
    MakeFile('Src\V.pas', nil)], TFindingsFormat.Text, nil);
  Assert.IsTrue(Pos('Src\U.pas(5,3): error syntax: Meldung', Output) = 1, Output);
  Assert.IsTrue(Pos('1 Treffer in 1 von 2 Dateien', Output) > 0, Output);
end;

procedure TLinterOutputTests.RendersJsonWithSummary;
var
  Output: string;
begin
  Output := TFindingsOutput.Render([MakeFile('Src\U.pas', [MakeFinding('a', TRuleSeverity.Warning, 1)])],
    TFindingsFormat.Json, nil);
  Assert.AreEqual('{"files":[{"path":"Src/U.pas","findings":[{"rule":"a","severity":"warning",' +
    '"confidence":"high","message":"Meldung","range":{"start":{"line":1,"character":2},' +
    '"end":{"line":1,"character":5}}}]}],"summary":{"files":1,"errors":0,"warnings":1,' +
    '"information":0,"hints":0}}', Output);
end;

procedure TLinterOutputTests.RendersSarifResult;
var
  Output: string;
begin
  Output := TFindingsOutput.Render([MakeFile('Src\U.pas', [MakeFinding('syntax', TRuleSeverity.Hint, 0)])],
    TFindingsFormat.Sarif, [TFileChecker.SyntaxDescriptor]);
  Assert.IsTrue(Pos('"version":"2.1.0"', Output) > 0, Output);
  Assert.IsTrue(Pos('"rules":[{"id":"syntax"', Output) > 0, Output);
  Assert.IsTrue(Pos('"ruleId":"syntax","level":"note"', Output) > 0, Output);
  Assert.IsTrue(Pos('"artifactLocation":{"uri":"Src/U.pas"}', Output) > 0, Output);
  Assert.IsTrue(Pos('"region":{"startLine":1,"startColumn":3,"endLine":1,"endColumn":6}', Output) > 0, Output);
end;

procedure TLinterOutputTests.EscapesJsonStrings;
begin
  Assert.AreEqual('"a\"b\\c\nd\u0001"', TFindingsOutput.JsonString('a"b\c'#10'd'#1));
end;

procedure TLinterOutputTests.ExitCodeFollowsHighestSeverity;
begin
  Assert.AreEqual(0, TFindingsOutput.ExitCode([MakeFile('a', [MakeFinding('x', TRuleSeverity.Hint)])]));
  Assert.AreEqual(1, TFindingsOutput.ExitCode([MakeFile('a', [MakeFinding('x', TRuleSeverity.Warning)])]));
  Assert.AreEqual(2, TFindingsOutput.ExitCode([MakeFile('a', [MakeFinding('x', TRuleSeverity.Warning)]),
    MakeFile('b', [MakeFinding('y', TRuleSeverity.Error)])]));
  Assert.AreEqual(0, TFindingsOutput.ExitCode(nil));
end;

procedure TLinterOutputTests.ParsesFormat;
var
  Format: TFindingsFormat;
begin
  Assert.IsTrue(TFindingsOutput.TryParseFormat('SARIF', Format));
  Assert.AreEqual(Ord(TFindingsFormat.Sarif), Ord(Format));
  Assert.IsFalse(TFindingsOutput.TryParseFormat('xml', Format));
end;

initialization
  TDUnitX.RegisterTestFixture(TLinterOutputTests);

end.
