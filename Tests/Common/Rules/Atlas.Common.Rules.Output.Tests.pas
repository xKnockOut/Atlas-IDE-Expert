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
    procedure CheckerReportsLanguageFeaturesBelowMinDelphiVersion;
    [Test]
    procedure CheckerLeavesIfExpressionsToTheirRule;
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
  Atlas.Common.Rules.Builtin.Concurrency.MainThread,
  Atlas.Common.Projects.PackageReader;

function MakeFinding(const ARuleId: string; ASeverity: TRuleSeverity; ALine: Integer): TRuleFinding; overload;
begin
  Result := Default(TRuleFinding);
  Result.RuleId := ARuleId;
  Result.Severity := ASeverity;
  Result.Confidence := TRuleConfidence.High;
  Result.Message := 'Meldung';
  Result.Range := TTextRange.Create(ALine, 2, ALine, 5);
end;

function MakeFinding(const ARuleId: string; ASeverity: TRuleSeverity): TRuleFinding; overload;
begin
  Result := MakeFinding(ARuleId, ASeverity, 0);
end;

function MakeFile(const APath: string; const AFindings: TArray<TRuleFinding>;
  const AFullPath: string): TCheckedFile; overload;
begin
  Result := Default(TCheckedFile);
  Result.Path := APath;
  Result.FullPath := AFullPath;
  Result.Findings := AFindings;
end;

function MakeFile(const APath: string; const AFindings: TArray<TRuleFinding>): TCheckedFile; overload;
begin
  Result := MakeFile(APath, AFindings, '');
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
  mIssues: TArray<TConfigurationIssue>;
begin
  Result := TConfigurationParser.Parse(AJson, mIssues);
end;

{ TLinterOutputTests }

procedure TLinterOutputTests.CheckerReportsSyntaxErrors;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TFileChecker.CheckText(nil, TServerSettings.Default, 'U.pas',
    'unit U; interface implementation procedure P; begin if then end; end.');
  Assert.IsTrue(Length(mFindings) > 0);
  Assert.AreEqual(cSyntaxRuleId, mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(mFindings[0].Severity));
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

procedure TLinterOutputTests.CheckerReportsLanguageFeaturesBelowMinDelphiVersion;
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

procedure TLinterOutputTests.CheckerLeavesIfExpressionsToTheirRule;
const
  cSource = 'unit U; interface implementation function F(A: Boolean): Integer; ' +
    'begin Result := if A then 1 else 2; end; end.';
begin
  // #684 mit #1126: Bedingungsausdrücke meldet conditional-expression-version als Fehler mit Korrektur, nicht
  // zusätzlich language-feature.
  Assert.AreEqual(0, Integer(Length(TFileChecker.CheckText(nil, Settings('{ "minDelphiVersion": "12" }'), 'U.pas',
    cSource))));
end;

procedure TLinterOutputTests.FilterByRule;
var
  mFilter: TFindingFilter;
begin
  mFilter := Default(TFindingFilter);
  mFilter.Rules := ['Empty-Except'];
  Assert.IsTrue(mFilter.AcceptsFinding(MakeFinding('empty-except', TRuleSeverity.Hint)));
  Assert.IsFalse(mFilter.AcceptsFinding(MakeFinding('syntax', TRuleSeverity.Error)));
end;

procedure TLinterOutputTests.FilterBySeverity;
var
  mFilter: TFindingFilter;
begin
  mFilter := Default(TFindingFilter);
  mFilter.MinSeverity := TRuleSeverity.Warning;
  Assert.AreEqual(2, Integer(Length(mFilter.Apply([MakeFinding('a', TRuleSeverity.Hint),
    MakeFinding('b', TRuleSeverity.Warning), MakeFinding('c', TRuleSeverity.Information),
    MakeFinding('d', TRuleSeverity.Error)]))));
end;

procedure TLinterOutputTests.FilterByUnitNameAndGlob;
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

procedure TLinterOutputTests.SplitListTrimsAndSkipsEmpty;
var
  mParts: TArray<string>;
begin
  mParts := TFindingFilter.SplitList(' a, ,b ,');
  Assert.AreEqual(2, Integer(Length(mParts)));
  Assert.AreEqual('a', mParts[0]);
  Assert.AreEqual('b', mParts[1]);
end;

procedure TLinterOutputTests.RendersTextLikeCompiler;
var
  mOutput: string;
begin
  mOutput := TFindingsOutput.Render([MakeFile('Src\U.pas', [MakeFinding('syntax', TRuleSeverity.Error, 4)]),
    MakeFile('Src\V.pas', nil)], TFindingsFormat.Text, nil);
  Assert.AreEqual(1, Pos('Src\U.pas(5,3): error syntax [Konfidenz hoch]: Meldung', mOutput), mOutput);
  Assert.IsTrue(Pos('1 Treffer in 1 von 2 Dateien', mOutput) > 0, mOutput);
end;

procedure TLinterOutputTests.RendersJsonWithSummary;
var
  mOutput: string;
begin
  mOutput := TFindingsOutput.Render([MakeFile('Src\U.pas', [MakeFinding('a', TRuleSeverity.Warning, 1)])],
    TFindingsFormat.Json, nil);
  Assert.AreEqual('{"files":[{"path":"Src/U.pas","findings":[{"rule":"a","severity":"warning",' +
    '"confidence":"high","message":"Meldung","range":{"start":{"line":1,"character":2},' +
    '"end":{"line":1,"character":5}},"properties":{"confidence":"high"}}]}],"summary":{"files":1,"errors":0,"warnings":1,' +
    '"information":0,"hints":0}}', mOutput);
end;

procedure TLinterOutputTests.RendersSarifResult;
var
  mOutput: string;
begin
  mOutput := TFindingsOutput.Render([MakeFile('Src\U.pas', [MakeFinding('syntax', TRuleSeverity.Hint, 0)])],
    TFindingsFormat.Sarif, [TFileChecker.SyntaxDescriptor]);
  Assert.IsTrue(Pos('"version":"2.1.0"', mOutput) > 0, mOutput);
  Assert.IsTrue(Pos('"rules":[{"id":"syntax","name":"Syntax error"', mOutput) > 0, mOutput);
  Assert.IsTrue(Pos('"fullDescription":{"text":"The source code does not parse. ', mOutput) > 0, mOutput);
  Assert.IsTrue(Pos('"helpUri":"https://github.com/xKnockOut/Atlas-IDE-Expert/blob/main/docs/Regeln.md#syntax"',
    mOutput) > 0, mOutput);
  Assert.IsTrue(Pos('"ruleId":"syntax","level":"note"', mOutput) > 0, mOutput);
  Assert.IsTrue(Pos('"artifactLocation":{"uri":"Src/U.pas"}', mOutput) > 0, mOutput);
  Assert.IsTrue(Pos('"region":{"startLine":1,"startColumn":3,"endLine":1,"endColumn":6}', mOutput) > 0, mOutput);
end;

procedure TLinterOutputTests.EscapesJsonStrings;
begin
  Assert.AreEqual('"a\"b\\c\nd\u0001"', TFindingsOutput.JsonString('a"b\c'#10'd'#1));
end;

procedure TLinterOutputTests.SarifPathsRelativeToSourceRoot;
var
  mOutput: string;
begin
  // .dproj in C:\Repo\App, eine Unit über den Suchpfad ..\Shared, eine außerhalb des Repositorys.
  mOutput := TFindingsOutput.Render([
    MakeFile('Main.dpr', [MakeFinding('syntax', TRuleSeverity.Error)], 'C:\Repo\App\Main.dpr'),
    MakeFile('..\Shared\X.pas', [MakeFinding('syntax', TRuleSeverity.Error)], 'C:\Repo\Shared\X.pas'),
    MakeFile('..\..\Fremd\Y.pas', [MakeFinding('syntax', TRuleSeverity.Error)], 'D:\Fremd\Y.pas')],
    TFindingsFormat.Sarif, [TFileChecker.SyntaxDescriptor], 'C:\Repo');
  Assert.IsTrue(Pos('"originalUriBaseIds":{"%SRCROOT%":{"uri":"file:///C:/Repo/"}}', mOutput) > 0, mOutput);
  Assert.IsTrue(Pos('"artifactLocation":{"uri":"App/Main.dpr","uriBaseId":"%SRCROOT%"}', mOutput) > 0, mOutput);
  Assert.IsTrue(Pos('"artifactLocation":{"uri":"Shared/X.pas","uriBaseId":"%SRCROOT%"}', mOutput) > 0, mOutput);
  Assert.IsTrue(Pos('"artifactLocation":{"uri":"file:///D:/Fremd/Y.pas"}', mOutput) > 0, mOutput);
  Assert.AreEqual(0, Pos('../', mOutput), mOutput);
end;

procedure TLinterOutputTests.SarifMessageEnglishWithoutConfidence;
var
  mFinding: TRuleFinding;
  mOutput: string;
begin
  mFinding := MakeFinding('syntax', TRuleSeverity.Error);
  mFinding.Confidence := TRuleConfidence.Medium;
  mOutput := TFindingsOutput.Render([MakeFile('U.pas', [mFinding])], TFindingsFormat.Sarif,
    [TFileChecker.SyntaxDescriptor]);
  Assert.IsTrue(Pos('"message":{"text":"Syntax error"}', mOutput) > 0, mOutput);
  Assert.AreEqual(0, Pos('Konfidenz', mOutput), mOutput);
  Assert.IsTrue(Pos('"properties":{"confidence":"medium","detail":"Meldung"}', mOutput) > 0, mOutput);
end;

procedure TLinterOutputTests.JsonConfidenceInProperties;
var
  mFinding: TRuleFinding;
  mOutput: string;
begin
  mFinding := MakeFinding('a', TRuleSeverity.Hint);
  mFinding.Confidence := TRuleConfidence.Low;
  mOutput := TFindingsOutput.Render([MakeFile('U.pas', [mFinding])], TFindingsFormat.Json, nil);
  Assert.IsTrue(Pos('"properties":{"confidence":"low"}', mOutput) > 0, mOutput);
  Assert.IsTrue(Pos('"message":"Meldung"', mOutput) > 0, mOutput);
  Assert.AreEqual(0, Pos('Konfidenz', mOutput), mOutput);
end;

procedure TLinterOutputTests.FileUriEncodesSpecialCharacters;
var
  mRelative: Boolean;
begin
  Assert.AreEqual('file:///C:/Mein%20Ordner/%C3%84nderung.pas',
    TFindingsOutput.FileUri('C:\Mein Ordner\'#$00C4'nderung.pas'));
  Assert.AreEqual('file://server/freigabe/U.pas', TFindingsOutput.FileUri('\\server\freigabe\U.pas'));
  Assert.AreEqual('Src/A%23B.pas', TFindingsOutput.SarifUri('c:\repo\Src\A#B.pas', 'C:\Repo\', mRelative));
  Assert.IsTrue(mRelative);
  TFindingsOutput.SarifUri('C:\Repository\U.pas', 'C:\Repo', mRelative);
  Assert.IsFalse(mRelative, 'Präfix ohne Trennzeichen ist kein Unterordner');
end;

procedure TLinterOutputTests.FindGitRootWalksUp;
var
  mRepo, mApp: string;
begin
  mRepo := 'R' + PathDelim + 'Repo';
  mApp := mRepo + PathDelim + 'App';
  Assert.AreEqual(mRepo, TFindingsOutput.FindGitRoot(mApp,
    function(const APath: string): Boolean
    begin
      Result := APath = mRepo + PathDelim + '.git';
    end));
  Assert.AreEqual('', TFindingsOutput.FindGitRoot(mApp,
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
  mFormat: TFindingsFormat;
begin
  Assert.IsTrue(TFindingsOutput.TryParseFormat('SARIF', mFormat));
  Assert.AreEqual(Ord(TFindingsFormat.Sarif), Ord(mFormat));
  Assert.IsFalse(TFindingsOutput.TryParseFormat('xml', mFormat));
end;

procedure TLinterOutputTests.ParsesFailOn;
var
  mFailOn: TFailOn;
begin
  Assert.IsTrue(TFindingsOutput.TryParseFailOn('Warning', mFailOn));
  Assert.AreEqual(Ord(TFailOn.Warning), Ord(mFailOn));
  Assert.IsTrue(TFindingsOutput.TryParseFailOn('never', mFailOn));
  Assert.AreEqual(Ord(TFailOn.Never), Ord(mFailOn));
  Assert.IsFalse(TFindingsOutput.TryParseFailOn('hint', mFailOn));
  Assert.AreEqual(Ord(TFailOn.Error), Ord(mFailOn));
end;

procedure TLinterOutputTests.SarifCarriesFingerprintsAndBaselineState;
var
  mCheckedFile: TCheckedFile;
  mAbsent: TBaselineMark;
  mOutput, mHash: string;
begin
  mCheckedFile := MakeFile('Src\U.pas', [MakeFinding('syntax', TRuleSeverity.Error, 3)]);
  mAbsent := MakeMark(Default(TRuleFinding), TBaselineState.Absent, 'TFoo.Alt');
  mAbsent.Finding.RuleId := 'syntax';
  mCheckedFile.Marks := [MakeMark(MakeFinding('syntax', TRuleSeverity.Error, 3), TBaselineState.New, 'TFoo.Bar'),
    MakeMark(MakeFinding('syntax', TRuleSeverity.Error, 7), TBaselineState.Unchanged, 'TFoo.Baz'), mAbsent];
  mOutput := TFindingsOutput.Render([mCheckedFile], TFindingsFormat.Sarif, [TFileChecker.SyntaxDescriptor]);
  mHash := TRuleBaseline.SarifFingerprint(mCheckedFile.Marks[0]);
  Assert.IsTrue(Pos('"partialFingerprints":{"atlasBaseline/v1":"' + mHash + ':1","atlasContext/v1":"c0ffee00:1"}',
    mOutput) > 0, mOutput);
  Assert.IsTrue(Pos('"baselineState":"new"', mOutput) > 0, mOutput);
  Assert.IsTrue(Pos('"baselineState":"unchanged","suppressions":[{"kind":"external","justification":' +
    '"atlas-baseline.json"}]', mOutput) > 0, mOutput);
  Assert.IsTrue(Pos('"baselineState":"absent"', mOutput) > 0, mOutput);
  Assert.IsTrue(Pos('"routine":"TFoo.Bar"', mOutput) > 0, mOutput);
  // Nicht mehr gefunden: ohne Region, Schweregrad der Regel.
  Assert.IsTrue(Pos('"artifactLocation":{"uri":"Src/U.pas"}}}],"partialFingerprints"', mOutput) > 0, mOutput);
  Assert.IsTrue(Pos('"startLine":4', mOutput) > 0, mOutput);
  Assert.IsTrue(Pos('"startLine":8', mOutput) > 0, mOutput);
  // Unverändert und nicht mehr gefunden zählen nicht für den Exit-Code: der zählt nur Findings.
  mCheckedFile.Findings := nil;
  Assert.AreEqual(TFindingsOutput.cExitClean, TFindingsOutput.ExitCode([mCheckedFile], TFailOn.Warning));
end;

procedure TLinterOutputTests.SarifNumbersIdenticalFingerprints;
var
  mCheckedFile: TCheckedFile;
  mOutput, mHash: string;
begin
  mCheckedFile := MakeFile('U.pas', nil);
  mCheckedFile.Marks := [MakeMark(MakeFinding('a', TRuleSeverity.Hint, 3), TBaselineState.New, 'P'),
    MakeMark(MakeFinding('a', TRuleSeverity.Hint, 9), TBaselineState.New, 'P')];
  mOutput := TFindingsOutput.Render([mCheckedFile], TFindingsFormat.Sarif, nil);
  mHash := TRuleBaseline.SarifFingerprint(mCheckedFile.Marks[0]);
  Assert.IsTrue(Pos('"atlasBaseline/v1":"' + mHash + ':1"', mOutput) > 0, mOutput);
  Assert.IsTrue(Pos('"atlasBaseline/v1":"' + mHash + ':2"', mOutput) > 0, mOutput);
  Assert.IsTrue(Pos('"atlasContext/v1":"c0ffee00:2"', mOutput) > 0, mOutput);
end;

procedure TLinterOutputTests.SarifWithoutBaselineHasNoState;
var
  mCheckedFile: TCheckedFile;
  mOutput: string;
begin
  mCheckedFile := MakeFile('U.pas', [MakeFinding('a', TRuleSeverity.Hint, 3)]);
  mCheckedFile.Marks := [MakeMark(mCheckedFile.Findings[0], TBaselineState.None, 'P')];
  mOutput := TFindingsOutput.Render([mCheckedFile], TFindingsFormat.Sarif, nil);
  Assert.IsTrue(Pos('"partialFingerprints"', mOutput) > 0, mOutput);
  Assert.AreEqual(0, Pos('baselineState', mOutput), mOutput);
  Assert.AreEqual(0, Pos('suppressions', mOutput), mOutput);
  // Text und JSON bleiben unverändert.
  Assert.AreEqual(0, Pos('partialFingerprints', TFindingsOutput.Render([mCheckedFile], TFindingsFormat.Json, nil)));
end;

procedure TLinterOutputTests.CheckerReturnsScopes;
var
  mScopes: TFindingScopes;
begin
  TFileChecker.CheckText(nil, Settings('{}'), 'U.pas',
    'unit U; interface implementation procedure TFoo.Bar; begin end; end.', mScopes);
  Assert.AreEqual(1, mScopes.RoutineCount);
  Assert.AreEqual('TFoo.Bar', mScopes.At(0));
end;

procedure TLinterOutputTests.CheckerPassesPackageToRules;
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
  TDUnitX.RegisterTestFixture(TLinterOutputTests);

end.
