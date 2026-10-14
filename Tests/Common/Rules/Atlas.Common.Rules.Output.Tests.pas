unit Atlas.Common.Rules.Output.Tests;

// Tests für den Kommandozeilen-Linter: Prüfung eines Textes, Filter,
// Ausgabe als Text, JSON und SARIF, Quellwurzel für SARIF und Exit-Code
// nach --fail-on (#95).

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
    procedure SarifPathsRelativeToSourceRoot;
    [Test]
    procedure SarifMessageEnglishWithoutConfidence;
    [Test]
    procedure FileUriEncodesSpecialCharacters;
    [Test]
    procedure FindGitRootWalksUp;
    [Test]
    procedure ExitCodeFailOnError;
    [Test]
    procedure ExitCodeFailOnWarning;
    [Test]
    procedure ExitCodeFailOnNever;
    [Test]
    procedure ParsesFormat;
    [Test]
    procedure ParsesFailOn;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.Filter,
  Atlas.Common.Rules.Output;

function MakeFinding(const ARuleId: string; ASeverity: TRuleSeverity; ALine: Integer = 0): TRuleFinding;
begin
  Result := Default(TRuleFinding);
  Result.RuleId := ARuleId;
  Result.Severity := ASeverity;
  Result.Confidence := TRuleConfidence.High;
  Result.Message := 'Meldung';
  Result.Range := TTextRange.Create(ALine, 2, ALine, 5);
end;

function MakeFile(const APath: string; const AFindings: TArray<TRuleFinding>;
  const AFullPath: string = ''): TCheckedFile;
begin
  Result := Default(TCheckedFile);
  Result.Path := APath;
  Result.FullPath := AFullPath;
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
  Assert.IsTrue(Pos('Src\U.pas(5,3): error syntax [Konfidenz hoch]: Meldung', Output) = 1, Output);
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
  Assert.IsTrue(Pos('"rules":[{"id":"syntax","name":"Syntax error"', Output) > 0, Output);
  Assert.IsTrue(Pos('"fullDescription":{"text":"The parser could not read the source code."}', Output) > 0, Output);
  Assert.IsTrue(Pos('"helpUri":"https://github.com/xKnockOut/Atlas-IDE-Expert/blob/main/docs/Regeln.md#syntax"',
    Output) > 0, Output);
  Assert.IsTrue(Pos('"ruleId":"syntax","level":"note"', Output) > 0, Output);
  Assert.IsTrue(Pos('"artifactLocation":{"uri":"Src/U.pas"}', Output) > 0, Output);
  Assert.IsTrue(Pos('"region":{"startLine":1,"startColumn":3,"endLine":1,"endColumn":6}', Output) > 0, Output);
end;

procedure TLinterOutputTests.EscapesJsonStrings;
begin
  Assert.AreEqual('"a\"b\\c\nd\u0001"', TFindingsOutput.JsonString('a"b\c'#10'd'#1));
end;

procedure TLinterOutputTests.SarifPathsRelativeToSourceRoot;
var
  Output: string;
begin
  // .dproj in C:\Repo\App, eine Unit über den Suchpfad ..\Shared, eine außerhalb des Repositorys.
  Output := TFindingsOutput.Render([
    MakeFile('Main.dpr', [MakeFinding('syntax', TRuleSeverity.Error)], 'C:\Repo\App\Main.dpr'),
    MakeFile('..\Shared\X.pas', [MakeFinding('syntax', TRuleSeverity.Error)], 'C:\Repo\Shared\X.pas'),
    MakeFile('..\..\Fremd\Y.pas', [MakeFinding('syntax', TRuleSeverity.Error)], 'D:\Fremd\Y.pas')],
    TFindingsFormat.Sarif, [TFileChecker.SyntaxDescriptor], 'C:\Repo');
  Assert.IsTrue(Pos('"originalUriBaseIds":{"%SRCROOT%":{"uri":"file:///C:/Repo/"}}', Output) > 0, Output);
  Assert.IsTrue(Pos('"artifactLocation":{"uri":"App/Main.dpr","uriBaseId":"%SRCROOT%"}', Output) > 0, Output);
  Assert.IsTrue(Pos('"artifactLocation":{"uri":"Shared/X.pas","uriBaseId":"%SRCROOT%"}', Output) > 0, Output);
  Assert.IsTrue(Pos('"artifactLocation":{"uri":"file:///D:/Fremd/Y.pas"}', Output) > 0, Output);
  Assert.AreEqual(0, Pos('../', Output), Output);
end;

procedure TLinterOutputTests.SarifMessageEnglishWithoutConfidence;
var
  Finding: TRuleFinding;
  Output: string;
begin
  Finding := MakeFinding('syntax', TRuleSeverity.Error);
  Finding.Confidence := TRuleConfidence.Medium;
  Output := TFindingsOutput.Render([MakeFile('U.pas', [Finding])], TFindingsFormat.Sarif,
    [TFileChecker.SyntaxDescriptor]);
  Assert.IsTrue(Pos('"message":{"text":"Syntax error"}', Output) > 0, Output);
  Assert.AreEqual(0, Pos('Konfidenz', Output), Output);
  Assert.IsTrue(Pos('"properties":{"confidence":"medium","detail":"Meldung"}', Output) > 0, Output);
end;

procedure TLinterOutputTests.FileUriEncodesSpecialCharacters;
var
  Relative: Boolean;
begin
  Assert.AreEqual('file:///C:/Mein%20Ordner/%C3%84nderung.pas',
    TFindingsOutput.FileUri('C:\Mein Ordner\'#$00C4'nderung.pas'));
  Assert.AreEqual('file://server/freigabe/U.pas', TFindingsOutput.FileUri('\\server\freigabe\U.pas'));
  Assert.AreEqual('Src/A%23B.pas', TFindingsOutput.SarifUri('c:\repo\Src\A#B.pas', 'C:\Repo\', Relative));
  Assert.IsTrue(Relative);
  TFindingsOutput.SarifUri('C:\Repository\U.pas', 'C:\Repo', Relative);
  Assert.IsFalse(Relative, 'Präfix ohne Trennzeichen ist kein Unterordner');
end;

procedure TLinterOutputTests.FindGitRootWalksUp;
var
  Repo, App: string;
begin
  Repo := 'R' + PathDelim + 'Repo';
  App := Repo + PathDelim + 'App';
  Assert.AreEqual(Repo, TFindingsOutput.FindGitRoot(App,
    function(const APath: string): Boolean
    begin
      Result := APath = Repo + PathDelim + '.git';
    end));
  Assert.AreEqual('', TFindingsOutput.FindGitRoot(App,
    function(const APath: string): Boolean
    begin
      Result := False;
    end));
end;

procedure TLinterOutputTests.ExitCodeFailOnError;
begin
  Assert.AreEqual(0, TFindingsOutput.ExitCode([MakeFile('a', [MakeFinding('x', TRuleSeverity.Warning)])]));
  Assert.AreEqual(0, TFindingsOutput.ExitCode([MakeFile('a', [MakeFinding('x', TRuleSeverity.Warning)])],
    TFailOn.Error));
  Assert.AreEqual(1, TFindingsOutput.ExitCode([MakeFile('a', [MakeFinding('x', TRuleSeverity.Warning)]),
    MakeFile('b', [MakeFinding('y', TRuleSeverity.Error)])]));
  Assert.AreEqual(0, TFindingsOutput.ExitCode(nil));
end;

procedure TLinterOutputTests.ExitCodeFailOnWarning;
begin
  Assert.AreEqual(1, TFindingsOutput.ExitCode([MakeFile('a', [MakeFinding('x', TRuleSeverity.Warning)])],
    TFailOn.Warning));
  Assert.AreEqual(1, TFindingsOutput.ExitCode([MakeFile('a', [MakeFinding('x', TRuleSeverity.Error)])],
    TFailOn.Warning));
  Assert.AreEqual(0, TFindingsOutput.ExitCode([MakeFile('a', [MakeFinding('x', TRuleSeverity.Information),
    MakeFinding('y', TRuleSeverity.Hint)])], TFailOn.Warning));
end;

procedure TLinterOutputTests.ExitCodeFailOnNever;
begin
  Assert.AreEqual(0, TFindingsOutput.ExitCode([MakeFile('a', [MakeFinding('x', TRuleSeverity.Error)])],
    TFailOn.Never));
end;

procedure TLinterOutputTests.ParsesFormat;
var
  Format: TFindingsFormat;
begin
  Assert.IsTrue(TFindingsOutput.TryParseFormat('SARIF', Format));
  Assert.AreEqual(Ord(TFindingsFormat.Sarif), Ord(Format));
  Assert.IsFalse(TFindingsOutput.TryParseFormat('xml', Format));
end;

procedure TLinterOutputTests.ParsesFailOn;
var
  FailOn: TFailOn;
begin
  Assert.IsTrue(TFindingsOutput.TryParseFailOn('Warning', FailOn));
  Assert.AreEqual(Ord(TFailOn.Warning), Ord(FailOn));
  Assert.IsTrue(TFindingsOutput.TryParseFailOn('never', FailOn));
  Assert.AreEqual(Ord(TFailOn.Never), Ord(FailOn));
  Assert.IsFalse(TFindingsOutput.TryParseFailOn('hint', FailOn));
  Assert.AreEqual(Ord(TFailOn.Error), Ord(FailOn));
end;

initialization
  TDUnitX.RegisterTestFixture(TLinterOutputTests);

end.
