unit Atlas.Common.Pascal.Preprocessor.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPascalPreprocessorTests = class
  public
    [Test]
    procedure KeepsCodeWithoutDirectives;
    [Test]
    procedure HandlesIfdefElse;
    [Test]
    procedure HandlesNestedConditions;
    [Test]
    procedure DefineAndUndefChangeSymbols;
    [Test]
    procedure DefinesInInactiveBranchAreIgnored;
    [Test]
    procedure EvaluatesIfExpressions;
    [Test]
    procedure HandlesElseIfChains;
    [Test]
    procedure ReportsInvalidExpression;
    [Test]
    procedure ReportsMissingEndif;
    [Test]
    procedure ReportsUnexpectedEndif;
    [Test]
    procedure CollectsInactiveRanges;
    [Test]
    procedure IncludesFilesWithOwnPositions;
    [Test]
    procedure ReportsMissingAndRecursiveIncludes;
    [Test]
    procedure TreatsIoSwitchNotAsInclude;
    [Test]
    procedure KeepsOtherDirectives;
    [Test]
    procedure PredefinesPlatformSymbols;
    [Test]
    procedure MapsBdsToCompilerVersion;
    [Test]
    procedure CompilerVersionFollowsVerDefine;
    /// <summary>#102: wirksame $DEFINE/$UNDEF mit Stelle, aus Include-Dateien an der $I-Direktive.</summary>
    [Test]
    procedure RecordsDefineSites;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Preprocessor;

function Options(const ADefines: array of string): TPreprocessorOptions;
var
  I: Integer;
begin
  Result := TPreprocessorOptions.Default;
  SetLength(Result.Defines, Length(ADefines));
  for I := 0 to High(ADefines) do
    Result.Defines[I] := ADefines[I];
  Result.CompilerVersion := 37.0;
  Result.RTLVersion := 37.0;
  Result.FileName := 'Main.pas';
end;

function Words(const AResult: TPreprocessorResult): string;
var
  Token: TPascalToken;
begin
  Result := '';
  for Token in AResult.Tokens do
  begin
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + Token.Text;
  end;
end;

function Run(const AText: string; const ADefines: array of string): TPreprocessorResult;
begin
  Result := TPascalPreprocessor.Process(AText, Options(ADefines));
end;

{ TPascalPreprocessorTests }

procedure TPascalPreprocessorTests.KeepsCodeWithoutDirectives;
var
  R: TPreprocessorResult;
begin
  R := Run('a b c', []);
  Assert.AreEqual('a b c', Words(R));
  Assert.AreEqual<NativeInt>(0, Length(R.Issues));
  Assert.AreEqual<NativeInt>(0, Length(R.InactiveRanges));
  Assert.AreEqual('Main.pas', R.Files[0]);
end;

procedure TPascalPreprocessorTests.HandlesIfdefElse;
begin
  Assert.AreEqual('a x c', Words(Run('a {$IFDEF DEBUG} x {$ELSE} y {$ENDIF} c', ['debug'])));
  Assert.AreEqual('a y c', Words(Run('a {$IFDEF DEBUG} x {$ELSE} y {$ENDIF} c', [])));
  Assert.AreEqual('a y c', Words(Run('a {$IFNDEF DEBUG} x {$ELSE} y {$ENDIF} c', ['DEBUG'])));
  Assert.AreEqual('a x c', Words(Run('a (*$IFDEF DEBUG*) x (*$ENDIF*) c', ['DEBUG'])));
end;

procedure TPascalPreprocessorTests.HandlesNestedConditions;
const
  Source = '{$IFDEF A} a {$IFDEF B} b {$ELSE} nb {$ENDIF} {$ELSE} na {$IFDEF B} b2 {$ENDIF} {$ENDIF}';
begin
  Assert.AreEqual('a b', Words(Run(Source, ['A', 'B'])));
  Assert.AreEqual('a nb', Words(Run(Source, ['A'])));
  Assert.AreEqual('na b2', Words(Run(Source, ['B'])));
  Assert.AreEqual('na', Words(Run(Source, [])));
end;

procedure TPascalPreprocessorTests.DefineAndUndefChangeSymbols;
var
  R: TPreprocessorResult;
begin
  R := Run('{$DEFINE X} {$IFDEF X} x {$ENDIF} {$UNDEF X} {$IFDEF X} y {$ENDIF}', []);
  Assert.AreEqual('x', Words(R));
  Assert.AreEqual<NativeInt>(0, Length(R.Defines));
  R := Run('{$DEFINE Zwei}', ['EINS']);
  Assert.AreEqual<NativeInt>(2, Length(R.Defines));
  Assert.AreEqual('EINS', R.Defines[0]);
  Assert.AreEqual('ZWEI', R.Defines[1]);
end;

procedure TPascalPreprocessorTests.DefinesInInactiveBranchAreIgnored;
begin
  Assert.AreEqual('', Words(Run('{$IFDEF NIE} {$DEFINE X} {$ENDIF} {$IFDEF X} x {$ENDIF}', [])));
end;

procedure TPascalPreprocessorTests.EvaluatesIfExpressions;
var
  Opts: TPreprocessorOptions;
  Error: string;
begin
  Opts := Options([]);
  Opts.Constants := [TPair<string, Double>.Create('MeineKonstante', 3)];
  Assert.IsTrue(TPascalPreprocessor.Evaluate('CompilerVersion >= 37.0', Opts, [], Error));
  Assert.IsFalse(TPascalPreprocessor.Evaluate('CompilerVersion < 36', Opts, [], Error));
  Assert.IsTrue(TPascalPreprocessor.Evaluate('Defined(MSWINDOWS) and not Defined(LINUX)', Opts, ['MSWINDOWS'], Error));
  Assert.IsTrue(TPascalPreprocessor.Evaluate('Defined(A) or (RTLVersion > 30)', Opts, [], Error));
  Assert.IsTrue(TPascalPreprocessor.Evaluate('MeineKonstante * 2 = 6', Opts, [], Error));
  Assert.IsFalse(TPascalPreprocessor.Evaluate('Declared(TFoo)', Opts, [], Error));
  Assert.AreEqual('', Error);
  Assert.AreEqual('ok', Words(TPascalPreprocessor.Process('{$IF CompilerVersion > 30} ok {$IFEND}', Opts)));
end;

procedure TPascalPreprocessorTests.HandlesElseIfChains;
const
  Source = '{$IF Defined(A)} a {$ELSEIF Defined(B)} b {$ELSEIF Defined(C)} c {$ELSE} n {$ENDIF}';
begin
  Assert.AreEqual('a', Words(Run(Source, ['A', 'B'])));
  Assert.AreEqual('b', Words(Run(Source, ['B', 'C'])));
  Assert.AreEqual('c', Words(Run(Source, ['C'])));
  Assert.AreEqual('n', Words(Run(Source, [])));
end;

procedure TPascalPreprocessorTests.ReportsInvalidExpression;
var
  R: TPreprocessorResult;
begin
  R := Run('{$IF Unbekannt > 1} x {$ELSE} y {$ENDIF}', []);
  Assert.AreEqual('y', Words(R));
  Assert.AreEqual<NativeInt>(1, Length(R.Issues));
  Assert.Contains(R.Issues[0].Message, 'Unbekannt');
  Assert.AreEqual(0, R.Issues[0].Range.StartPos.Character);
end;

procedure TPascalPreprocessorTests.ReportsMissingEndif;
var
  R: TPreprocessorResult;
begin
  R := Run('a'#10'{$IFDEF X} b', []);
  Assert.AreEqual('a', Words(R));
  Assert.AreEqual<NativeInt>(1, Length(R.Issues));
  Assert.AreEqual(1, R.Issues[0].Range.StartPos.Line);
end;

procedure TPascalPreprocessorTests.ReportsUnexpectedEndif;
var
  R: TPreprocessorResult;
begin
  R := Run('a {$ENDIF} {$ELSE} b', []);
  Assert.AreEqual('a b', Words(R));
  Assert.AreEqual<NativeInt>(2, Length(R.Issues));
end;

procedure TPascalPreprocessorTests.CollectsInactiveRanges;
var
  R: TPreprocessorResult;
begin
  // Zeile 0: {$IFDEF X}, Zeilen 1-2 inaktiv, Zeile 3: {$ENDIF}
  R := Run('{$IFDEF X}'#10'a'#10'b'#10'{$ENDIF}'#10'c', []);
  Assert.AreEqual('c', Words(R));
  Assert.AreEqual<NativeInt>(1, Length(R.InactiveRanges));
  Assert.AreEqual(0, R.InactiveRanges[0].Range.StartPos.Line);
  Assert.AreEqual(10, R.InactiveRanges[0].Range.StartPos.Character);
  Assert.AreEqual(3, R.InactiveRanges[0].Range.EndPos.Line);
  Assert.AreEqual(0, R.InactiveRanges[0].Range.EndPos.Character);
end;

function ResolveTestInclude(const AName, AFromFile: string; out AFileName, AText: string): Boolean;
begin
  Result := True;
  AFileName := LowerCase(AName);
  if SameText(AName, 'defs.inc') then
    AText := '{$DEFINE AUS_INC}'#10'  inc1'
  else if SameText(AName, 'self.inc') then
    AText := '{$I self.inc}'
  else
    Result := False;
end;

procedure TPascalPreprocessorTests.IncludesFilesWithOwnPositions;
var
  Opts: TPreprocessorOptions;
  R: TPreprocessorResult;
begin
  Opts := Options([]);
  Opts.ResolveInclude := ResolveTestInclude;
  R := TPascalPreprocessor.Process('a {$I ''defs.inc''} {$IFDEF AUS_INC} b {$ENDIF}', Opts);
  Assert.AreEqual('a inc1 b', Words(R));
  Assert.AreEqual<NativeInt>(2, Length(R.Files));
  Assert.AreEqual('defs.inc', R.Files[1]);
  Assert.AreEqual(0, R.FileIndexes[0]);
  Assert.AreEqual(1, R.FileIndexes[1]);
  Assert.AreEqual(0, R.FileIndexes[2]);
  // inc1 steht in Zeile 1, Spalte 2 der Include-Datei.
  Assert.AreEqual(1, R.Tokens[1].StartPos.Line);
  Assert.AreEqual(2, R.Tokens[1].StartPos.Character);
end;

procedure TPascalPreprocessorTests.RecordsDefineSites;
var
  Opts: TPreprocessorOptions;
  R: TPreprocessorResult;
begin
  Opts := Options([]);
  Opts.ResolveInclude := ResolveTestInclude;
  R := TPascalPreprocessor.Process('{$DEFINE A}'#10'{$IFDEF NIE}{$DEFINE B}{$ENDIF}'#10'  {$I defs.inc}'#10 +
    '{$UNDEF a}', Opts);
  // B liegt im inaktiven Zweig und zählt nicht.
  Assert.AreEqual(3, Integer(Length(R.DefineSites)));
  Assert.AreEqual('A', R.DefineSites[0].Name);
  Assert.AreEqual(0, R.DefineSites[0].FileIndex);
  Assert.IsFalse(R.DefineSites[0].Undefine);
  // Aus defs.inc: Stelle in der Include-Datei, RootPos an der $I-Direktive.
  Assert.AreEqual('AUS_INC', R.DefineSites[1].Name);
  Assert.AreEqual(1, R.DefineSites[1].FileIndex);
  Assert.AreEqual(0, R.DefineSites[1].Range.StartPos.Line);
  Assert.AreEqual(2, R.DefineSites[1].RootPos.Line);
  Assert.AreEqual(2, R.DefineSites[1].RootPos.Character);
  Assert.AreEqual('A', R.DefineSites[2].Name);
  Assert.IsTrue(R.DefineSites[2].Undefine);
  Assert.AreEqual(3, R.DefineSites[2].RootPos.Line);
end;

procedure TPascalPreprocessorTests.ReportsMissingAndRecursiveIncludes;
var
  Opts: TPreprocessorOptions;
  R: TPreprocessorResult;
begin
  Opts := Options([]);
  Opts.ResolveInclude := ResolveTestInclude;
  R := TPascalPreprocessor.Process('{$INCLUDE fehlt.inc} {$I self.inc}', Opts);
  Assert.AreEqual<NativeInt>(2, Length(R.Issues));
  Assert.Contains(R.Issues[0].Message, 'fehlt.inc');
  Assert.AreEqual(1, R.Issues[1].FileIndex);
end;

procedure TPascalPreprocessorTests.TreatsIoSwitchNotAsInclude;
var
  R: TPreprocessorResult;
begin
  R := Run('{$I-} a {$I+}', []);
  Assert.AreEqual<NativeInt>(0, Length(R.Issues));
  Assert.AreEqual('{$I-} a {$I+}', Words(R));
end;

procedure TPascalPreprocessorTests.KeepsOtherDirectives;
begin
  Assert.AreEqual('{$R *.res} a', Words(Run('{$R *.res} a {$IFDEF X} {$R x.res} {$ENDIF}', [])));
end;

procedure TPascalPreprocessorTests.PredefinesPlatformSymbols;
var
  Symbols: TArray<string>;

  function Has(const AName: string): Boolean;
  var
    S: string;
  begin
    Result := False;
    for S in Symbols do
      if S = AName then
        Exit(True);
  end;

begin
  Symbols := TPascalPreprocessor.PredefinedSymbols('Win64', 37.0);
  Assert.IsTrue(Has('MSWINDOWS'));
  Assert.IsTrue(Has('WIN64'));
  Assert.IsTrue(Has('CPUX64'));
  Assert.IsTrue(Has('VER370'));
  Assert.IsFalse(Has('WIN32'));
  Symbols := TPascalPreprocessor.PredefinedSymbols('Linux64', 37.0);
  Assert.IsTrue(Has('LINUX'));
  Assert.IsTrue(Has('POSIX'));
  Assert.IsFalse(Has('MSWINDOWS'));
end;

procedure TPascalPreprocessorTests.MapsBdsToCompilerVersion;
begin
  // Delphi 12 hat BDS 23.0, aber Compilerversion 36.0 (VER360); ab Delphi 13 sind beide 37.0.
  Assert.AreEqual(36.0, TPascalPreprocessor.CompilerVersionOfBds(23.0), 0.001);
  Assert.AreEqual(35.0, TPascalPreprocessor.CompilerVersionOfBds(22.0), 0.001);
  Assert.AreEqual(37.0, TPascalPreprocessor.CompilerVersionOfBds(37.0), 0.001);
  Assert.AreEqual(0.0, TPascalPreprocessor.CompilerVersionOfBds(0), 0.001);
end;

procedure TPascalPreprocessorTests.CompilerVersionFollowsVerDefine;

  function Branch(const ADefine: string; const AName: string = 'CompilerVersion'): string;
  var
    Opts: TPreprocessorOptions;
  begin
    // Ohne ausdrückliche CompilerVersion, wie im Server.
    Opts := TPreprocessorOptions.Default;
    Opts.Defines := [ADefine];
    Result := Words(TPascalPreprocessor.Process('{$IF ' + AName + ' >= 36} neu {$ELSE} alt {$IFEND}', Opts));
  end;

begin
  Assert.AreEqual(36.0, TPascalPreprocessor.CompilerVersionFromDefines(['DEBUG', 'VER360']), 0.001);
  Assert.AreEqual(0.0, TPascalPreprocessor.CompilerVersionFromDefines(['VERBOSE']), 0.001);
  Assert.AreEqual('neu', Branch('VER360'));
  Assert.AreEqual('neu', Branch('VER360', 'RTLVersion'));
  Assert.AreEqual('alt', Branch('VER350'));
end;

initialization
  TDUnitX.RegisterTestFixture(TPascalPreprocessorTests);

end.
