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
    procedure JsonConfidenceInProperties;
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
    /// <summary>Abnahme #97: SARIF enthält partialFingerprints und baselineState.</summary>
    [Test]
    procedure SarifCarriesFingerprintsAndBaselineState;
    [Test]
    procedure SarifNumbersIdenticalFingerprints;
    [Test]
    procedure SarifWithoutBaselineHasNoState;
    [Test]
    procedure CheckerReturnsScopes;
    [Test]
    procedure CheckerPassesPackageToRules;
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
  Atlas.Common.Rules.Scopes,
  Atlas.Common.Rules.Baseline,
  Atlas.Common.Rules.Output,
  Atlas.Common.Rules.Builtin.Concurrency,
  Atlas.Common.Projects.PackageReader;

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

function MakeMark(const AFinding: TRuleFinding; AState: TBaselineState; const ARoutine: string): TBaselineMark;
begin
  Result := Default(TBaselineMark);
  Result.Finding := AFinding;
  Result.Routine := ARoutine;
  Result.Fingerprint := '0badf00d';
  Result.Context := 'c0ffee00';
  Result.State := AState;
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
    '"end":{"line":1,"character":5}},"properties":{"confidence":"high"}}]}],"summary":{"files":1,"errors":0,"warnings":1,' +
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
  Assert.IsTrue(Pos('"fullDescription":{"text":"The source code does not parse. ', Output) > 0, Output);
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

procedure TLinterOutputTests.JsonConfidenceInProperties;
var
  Finding: TRuleFinding;
  Output: string;
begin
  Finding := MakeFinding('a', TRuleSeverity.Hint);
  Finding.Confidence := TRuleConfidence.Low;
  Output := TFindingsOutput.Render([MakeFile('U.pas', [Finding])], TFindingsFormat.Json, nil);
  Assert.IsTrue(Pos('"properties":{"confidence":"low"}', Output) > 0, Output);
  Assert.IsTrue(Pos('"message":"Meldung"', Output) > 0, Output);
  Assert.AreEqual(0, Pos('Konfidenz', Output), Output);
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

procedure TLinterOutputTests.SarifCarriesFingerprintsAndBaselineState;
var
  CheckedFile: TCheckedFile;
  Absent: TBaselineMark;
  Output, Hash: string;
begin
  CheckedFile := MakeFile('Src\U.pas', [MakeFinding('syntax', TRuleSeverity.Error, 3)]);
  Absent := MakeMark(Default(TRuleFinding), TBaselineState.Absent, 'TFoo.Alt');
  Absent.Finding.RuleId := 'syntax';
  CheckedFile.Marks := [MakeMark(MakeFinding('syntax', TRuleSeverity.Error, 3), TBaselineState.New, 'TFoo.Bar'),
    MakeMark(MakeFinding('syntax', TRuleSeverity.Error, 7), TBaselineState.Unchanged, 'TFoo.Baz'), Absent];
  Output := TFindingsOutput.Render([CheckedFile], TFindingsFormat.Sarif, [TFileChecker.SyntaxDescriptor]);
  Hash := TRuleBaseline.SarifFingerprint(CheckedFile.Marks[0]);
  Assert.IsTrue(Pos('"partialFingerprints":{"atlasBaseline/v1":"' + Hash + ':1","atlasContext/v1":"c0ffee00:1"}',
    Output) > 0, Output);
  Assert.IsTrue(Pos('"baselineState":"new"', Output) > 0, Output);
  Assert.IsTrue(Pos('"baselineState":"unchanged","suppressions":[{"kind":"external","justification":' +
    '"atlas-baseline.json"}]', Output) > 0, Output);
  Assert.IsTrue(Pos('"baselineState":"absent"', Output) > 0, Output);
  Assert.IsTrue(Pos('"routine":"TFoo.Bar"', Output) > 0, Output);
  // Nicht mehr gefunden: ohne Region, Schweregrad der Regel.
  Assert.IsTrue(Pos('"artifactLocation":{"uri":"Src/U.pas"}}}],"partialFingerprints"', Output) > 0, Output);
  Assert.IsTrue(Pos('"startLine":4', Output) > 0, Output);
  Assert.IsTrue(Pos('"startLine":8', Output) > 0, Output);
  // Unverändert und nicht mehr gefunden zählen nicht für den Exit-Code: der zählt nur Findings.
  CheckedFile.Findings := nil;
  Assert.AreEqual(TFindingsOutput.ExitClean, TFindingsOutput.ExitCode([CheckedFile], TFailOn.Warning));
end;

procedure TLinterOutputTests.SarifNumbersIdenticalFingerprints;
var
  CheckedFile: TCheckedFile;
  Output, Hash: string;
begin
  CheckedFile := MakeFile('U.pas', nil);
  CheckedFile.Marks := [MakeMark(MakeFinding('a', TRuleSeverity.Hint, 3), TBaselineState.New, 'P'),
    MakeMark(MakeFinding('a', TRuleSeverity.Hint, 9), TBaselineState.New, 'P')];
  Output := TFindingsOutput.Render([CheckedFile], TFindingsFormat.Sarif, nil);
  Hash := TRuleBaseline.SarifFingerprint(CheckedFile.Marks[0]);
  Assert.IsTrue(Pos('"atlasBaseline/v1":"' + Hash + ':1"', Output) > 0, Output);
  Assert.IsTrue(Pos('"atlasBaseline/v1":"' + Hash + ':2"', Output) > 0, Output);
  Assert.IsTrue(Pos('"atlasContext/v1":"c0ffee00:2"', Output) > 0, Output);
end;

procedure TLinterOutputTests.SarifWithoutBaselineHasNoState;
var
  CheckedFile: TCheckedFile;
  Output: string;
begin
  CheckedFile := MakeFile('U.pas', [MakeFinding('a', TRuleSeverity.Hint, 3)]);
  CheckedFile.Marks := [MakeMark(CheckedFile.Findings[0], TBaselineState.None, 'P')];
  Output := TFindingsOutput.Render([CheckedFile], TFindingsFormat.Sarif, nil);
  Assert.IsTrue(Pos('"partialFingerprints"', Output) > 0, Output);
  Assert.IsTrue(Pos('baselineState', Output) = 0, Output);
  Assert.IsTrue(Pos('suppressions', Output) = 0, Output);
  // Text und JSON bleiben unverändert.
  Assert.IsTrue(Pos('partialFingerprints', TFindingsOutput.Render([CheckedFile], TFindingsFormat.Json, nil)) = 0);
end;

procedure TLinterOutputTests.CheckerReturnsScopes;
var
  Scopes: TFindingScopes;
begin
  TFileChecker.CheckText(nil, Settings('{}'), 'U.pas',
    'unit U; interface implementation procedure TFoo.Bar; begin end; end.', Scopes);
  Assert.AreEqual(1, Scopes.RoutineCount);
  Assert.AreEqual('TFoo.Bar', Scopes.At(0));
end;

procedure TLinterOutputTests.CheckerPassesPackageToRules;
const
  Source = 'unit Laden;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10 +
    '  TThread.Queue(nil, Start);'#10'end;'#10'end.';
var
  Packages: TArray<TPackageSource>;
  Project: TCheckProject;
  Findings: TArray<TRuleFinding>;
begin
  Packages := [TPackageReader.Read('package Werkzeuge;'#10'requires rtl;'#10'contains'#10 +
    '  Laden in ''Laden.pas'';'#10'end.')];
  Project := TFileChecker.PackageOf(Packages, 'laden');
  Assert.AreEqual(Ord(TRuleApplicationKind.Package), Ord(Project.Application));
  Assert.AreEqual('Werkzeuge', Project.Name);
  Assert.AreEqual(Ord(TRuleApplicationKind.Unknown), Ord(TFileChecker.PackageOf(Packages, 'Andere').Application));
  // queue-nil-in-package (#943) meldet nur mit Package.
  Findings := TFileChecker.CheckText([TQueueNilInPackageRule.Create], Settings('{}'), 'Laden.pas', Source, Project);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.Contains(Findings[0].Message, 'Werkzeuge.bpl');
  Assert.AreEqual(0, Integer(Length(TFileChecker.CheckText([TQueueNilInPackageRule.Create], Settings('{}'),
    'Laden.pas', Source))));
end;

initialization
  TDUnitX.RegisterTestFixture(TLinterOutputTests);

end.
