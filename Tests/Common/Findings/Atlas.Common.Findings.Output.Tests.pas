unit Atlas.Common.Findings.Output.Tests;

// Tests für die Ausgabe des Kommandozeilen-Linters: Text, JSON und SARIF, Quellwurzel für SARIF und
// Exit-Code nach --fail-on (#95).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFindingsOutputTests = class
  public
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
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Findings.Contract,
  Atlas.Common.Findings.Baseline,
  Atlas.Common.Findings.Output;

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
  Result := TCheckedFile.Create(APath, AFullPath, AFindings);
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

/// <summary>Regel "syntax" mit den englischen Texten des Katalogs, wie sie der Aufrufer für SARIF übergibt.</summary>
function SyntaxRule: TFindingRuleInfo;
begin
  Result := Default(TFindingRuleInfo);
  Result.Id := 'syntax';
  Result.Name := 'Syntax error';
  Result.Description := 'The source code does not parse. Atlas reports where the parser stopped.';
  Result.Category := 'bug';
  Result.DefaultSeverity := TRuleSeverity.Error;
  Result.HelpUri := 'https://github.com/xKnockOut/Atlas-IDE-Expert/blob/main/docs/Regeln.md#syntax';
end;

{ TFindingsOutputTests }

procedure TFindingsOutputTests.RendersTextLikeCompiler;
var
  mOutput: string;
begin
  mOutput := TFindingsOutput.Render([MakeFile('Src\U.pas', [MakeFinding('syntax', TRuleSeverity.Error, 4)]),
    MakeFile('Src\V.pas', nil)], TFindingsFormat.Text, nil);
  Assert.AreEqual(1, Pos('Src\U.pas(5,3): error syntax [Konfidenz hoch]: Meldung', mOutput), mOutput);
  Assert.IsTrue(Pos('1 Treffer in 1 von 2 Dateien', mOutput) > 0, mOutput);
end;

procedure TFindingsOutputTests.RendersJsonWithSummary;
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

procedure TFindingsOutputTests.RendersSarifResult;
var
  mOutput: string;
begin
  mOutput := TFindingsOutput.Render([MakeFile('Src\U.pas', [MakeFinding('syntax', TRuleSeverity.Hint, 0)])],
    TFindingsFormat.Sarif, [SyntaxRule]);
  Assert.IsTrue(Pos('"version":"2.1.0"', mOutput) > 0, mOutput);
  Assert.IsTrue(Pos('"rules":[{"id":"syntax","name":"Syntax error"', mOutput) > 0, mOutput);
  Assert.IsTrue(Pos('"fullDescription":{"text":"The source code does not parse. ', mOutput) > 0, mOutput);
  Assert.IsTrue(Pos('"helpUri":"https://github.com/xKnockOut/Atlas-IDE-Expert/blob/main/docs/Regeln.md#syntax"',
    mOutput) > 0, mOutput);
  Assert.IsTrue(Pos('"ruleId":"syntax","level":"note"', mOutput) > 0, mOutput);
  Assert.IsTrue(Pos('"artifactLocation":{"uri":"Src/U.pas"}', mOutput) > 0, mOutput);
  Assert.IsTrue(Pos('"region":{"startLine":1,"startColumn":3,"endLine":1,"endColumn":6}', mOutput) > 0, mOutput);
end;

procedure TFindingsOutputTests.EscapesJsonStrings;
begin
  Assert.AreEqual('"a\"b\\c\nd\u0001"', TFindingsOutput.JsonString('a"b\c'#10'd'#1));
end;

procedure TFindingsOutputTests.SarifPathsRelativeToSourceRoot;
var
  mOutput: string;
begin
  // .dproj in C:\Repo\App, eine Unit über den Suchpfad ..\Shared, eine außerhalb des Repositorys.
  mOutput := TFindingsOutput.Render([
    MakeFile('Main.dpr', [MakeFinding('syntax', TRuleSeverity.Error)], 'C:\Repo\App\Main.dpr'),
    MakeFile('..\Shared\X.pas', [MakeFinding('syntax', TRuleSeverity.Error)], 'C:\Repo\Shared\X.pas'),
    MakeFile('..\..\Fremd\Y.pas', [MakeFinding('syntax', TRuleSeverity.Error)], 'D:\Fremd\Y.pas')],
    TFindingsFormat.Sarif, [SyntaxRule], 'C:\Repo');
  Assert.IsTrue(Pos('"originalUriBaseIds":{"%SRCROOT%":{"uri":"file:///C:/Repo/"}}', mOutput) > 0, mOutput);
  Assert.IsTrue(Pos('"artifactLocation":{"uri":"App/Main.dpr","uriBaseId":"%SRCROOT%"}', mOutput) > 0, mOutput);
  Assert.IsTrue(Pos('"artifactLocation":{"uri":"Shared/X.pas","uriBaseId":"%SRCROOT%"}', mOutput) > 0, mOutput);
  Assert.IsTrue(Pos('"artifactLocation":{"uri":"file:///D:/Fremd/Y.pas"}', mOutput) > 0, mOutput);
  Assert.AreEqual(0, Pos('../', mOutput), mOutput);
end;

procedure TFindingsOutputTests.SarifMessageEnglishWithoutConfidence;
var
  mFinding: TRuleFinding;
  mOutput: string;
begin
  mFinding := MakeFinding('syntax', TRuleSeverity.Error);
  mFinding.Confidence := TRuleConfidence.Medium;
  mOutput := TFindingsOutput.Render([MakeFile('U.pas', [mFinding])], TFindingsFormat.Sarif,
    [SyntaxRule]);
  Assert.IsTrue(Pos('"message":{"text":"Syntax error"}', mOutput) > 0, mOutput);
  Assert.AreEqual(0, Pos('Konfidenz', mOutput), mOutput);
  Assert.IsTrue(Pos('"properties":{"confidence":"medium","detail":"Meldung"}', mOutput) > 0, mOutput);
end;

procedure TFindingsOutputTests.JsonConfidenceInProperties;
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

procedure TFindingsOutputTests.FileUriEncodesSpecialCharacters;
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

procedure TFindingsOutputTests.FindGitRootWalksUp;
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

procedure TFindingsOutputTests.ExitCodeFailOnError;
begin
  Assert.AreEqual(0, TFindingsOutput.ExitCode([MakeFile('a', [MakeFinding('x', TRuleSeverity.Warning)])]));
  Assert.AreEqual(0, TFindingsOutput.ExitCode([MakeFile('a', [MakeFinding('x', TRuleSeverity.Warning)])],
    TFailOn.Error));
  Assert.AreEqual(1, TFindingsOutput.ExitCode([MakeFile('a', [MakeFinding('x', TRuleSeverity.Warning)]),
    MakeFile('b', [MakeFinding('y', TRuleSeverity.Error)])]));
  Assert.AreEqual(0, TFindingsOutput.ExitCode(nil));
end;

procedure TFindingsOutputTests.ExitCodeFailOnWarning;
begin
  Assert.AreEqual(1, TFindingsOutput.ExitCode([MakeFile('a', [MakeFinding('x', TRuleSeverity.Warning)])],
    TFailOn.Warning));
  Assert.AreEqual(1, TFindingsOutput.ExitCode([MakeFile('a', [MakeFinding('x', TRuleSeverity.Error)])],
    TFailOn.Warning));
  Assert.AreEqual(0, TFindingsOutput.ExitCode([MakeFile('a', [MakeFinding('x', TRuleSeverity.Information),
    MakeFinding('y', TRuleSeverity.Hint)])], TFailOn.Warning));
end;

procedure TFindingsOutputTests.ExitCodeFailOnNever;
begin
  Assert.AreEqual(0, TFindingsOutput.ExitCode([MakeFile('a', [MakeFinding('x', TRuleSeverity.Error)])],
    TFailOn.Never));
end;

procedure TFindingsOutputTests.ParsesFormat;
var
  mFormat: TFindingsFormat;
begin
  Assert.IsTrue(TFindingsOutput.TryParseFormat('SARIF', mFormat));
  Assert.AreEqual(Ord(TFindingsFormat.Sarif), Ord(mFormat));
  Assert.IsFalse(TFindingsOutput.TryParseFormat('xml', mFormat));
end;

procedure TFindingsOutputTests.ParsesFailOn;
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

procedure TFindingsOutputTests.SarifCarriesFingerprintsAndBaselineState;
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
  mOutput := TFindingsOutput.Render([mCheckedFile], TFindingsFormat.Sarif, [SyntaxRule]);
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

procedure TFindingsOutputTests.SarifNumbersIdenticalFingerprints;
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

procedure TFindingsOutputTests.SarifWithoutBaselineHasNoState;
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

initialization
  TDUnitX.RegisterTestFixture(TFindingsOutputTests);

end.
