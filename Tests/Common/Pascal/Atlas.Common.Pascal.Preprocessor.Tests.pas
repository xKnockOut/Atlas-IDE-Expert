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
    /// <summary>#1380: Plattform zu den Symbolen; ParseActive legt sie am Baum ab.</summary>
    [Test]
    procedure PlatformFromSymbols;
    [Test]
    procedure MapsBdsToCompilerVersion;
    [Test]
    procedure CompilerVersionFollowsVerDefine;
    /// <summary>#102: wirksame $DEFINE/$UNDEF mit Stelle, aus Include-Dateien an der $I-Direktive.</summary>
    [Test]
    procedure RecordsDefineSites;
    /// <summary>#847: SizeOf, High, Low und Ord nach Zielplattform, mit Teilwerten für den Hover.</summary>
    [Test]
    procedure EvaluatesSizeOfHighLowOrd;
    /// <summary>#847: RTLVersion111 usw. aus der Compilerversion, auch in Declared.</summary>
    [Test]
    procedure EvaluatesRtlVersionConstants;
    /// <summary>#847: Unbekannte Werte gelten als aktiv, das $ELSE dazu ebenfalls; kein Befund.</summary>
    [Test]
    procedure UnknownValuesKeepBothBranchesActive;
    /// <summary>#847: Declared fragt Options.Declared bzw. den Index über SetDeclaredProvider.</summary>
    [Test]
    procedure DeclaredAsksIndex;
    /// <summary>#847: $IFOPT folgt den Schaltern der .dproj und lokalen Schaltern davor.</summary>
    [Test]
    procedure IfoptFollowsProjectAndLocalSwitches;
    /// <summary>#847: $PUSHOPT/$POPOPT sichern und stellen den Schalterstand wieder her.</summary>
    [Test]
    procedure PushOptRestoresSwitches;
    /// <summary>#847: Schalter aus den Eigenschaften der .dproj.</summary>
    [Test]
    procedure MapsProjectPropertiesToSwitches;
    /// <summary>#847: Jede ausgewertete Bedingung steht mit Wert und Teilwerten in Checks.</summary>
    [Test]
    procedure RecordsConditionChecks;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Pascal.SyntaxTree,
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

/// <summary>Wie Words, ohne die übrigen Direktiven (Schalter bleiben als Token erhalten).</summary>
function Code(const AResult: TPreprocessorResult): string;
var
  Token: TPascalToken;
begin
  Result := '';
  for Token in AResult.Tokens do
    if Token.Kind <> TPascalTokenKind.Directive then
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
  // Unbekannt gilt als aktiv (#847).
  Assert.IsTrue(TPascalPreprocessor.Evaluate('Declared(TFoo)', Opts, [], Error));
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
  R := Run('{$IF Unbekannt(1) > 1} x {$ELSE} y {$ENDIF}', []);
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

procedure TPascalPreprocessorTests.PlatformFromSymbols;
var
  mTree: TSyntaxTree;
begin
  Assert.AreEqual('Win64', TPascalPreprocessor.PlatformOf(TPascalPreprocessor.PredefinedSymbols('Win64', 37.0)));
  Assert.AreEqual('Win32', TPascalPreprocessor.PlatformOf(TPascalPreprocessor.PredefinedSymbols('Win32', 36.0)));
  Assert.AreEqual('Linux64', TPascalPreprocessor.PlatformOf(TPascalPreprocessor.PredefinedSymbols('Linux64', 37.0)));
  Assert.AreEqual('Win32', TPascalPreprocessor.PlatformOf(TArray<string>.Create('debug', 'win32')));
  Assert.AreEqual('', TPascalPreprocessor.PlatformOf(TArray<string>.Create('DEBUG')));
  // Ohne Symbole liest der Editor für Win32; Parse ohne Präprozessor kennt keine Plattform.
  mTree := TPascalParser.ParseActive('unit A;'#10'interface'#10'implementation'#10'end.', nil);
  try
    Assert.AreEqual('Win32', mTree.Platform);
  finally
    mTree.Free;
  end;
  mTree := TPascalParser.ParseActive('unit A;'#10'interface'#10'{$IFDEF X}{$ENDIF}'#10'implementation'#10'end.',
    TPascalPreprocessor.PredefinedSymbols('Win64', 37.0));
  try
    Assert.AreEqual('Win64', mTree.Platform);
  finally
    mTree.Free;
  end;
  mTree := TPascalParser.Parse('unit A;'#10'interface'#10'implementation'#10'end.');
  try
    Assert.AreEqual('', mTree.Platform);
  finally
    mTree.Free;
  end;
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

function Part(const AParts: TArray<TConditionPart>; const AText: string): TConditionPart;
var
  Item: TConditionPart;
begin
  for Item in AParts do
    if Item.Text = AText then
      Exit(Item);
  Result.Text := '';
  Result.Value := '';
  Result.Origin := '';
end;

procedure TPascalPreprocessorTests.EvaluatesSizeOfHighLowOrd;
var
  Opts: TPreprocessorOptions;
  Parts: TArray<TConditionPart>;
  Error: string;
  Win64, Win32: TArray<string>;
begin
  Opts := Options([]);
  Win64 := ['MSWINDOWS', 'WIN64', 'CPU64BITS', 'CPUX64'];
  Win32 := ['MSWINDOWS', 'WIN32', 'CPU32BITS', 'CPUX86'];
  Assert.IsTrue(TConditionValue.Yes = TPascalPreprocessor.Explain('SizeOf(Pointer) = 8', Opts, Win64, Parts, Error));
  Assert.AreEqual('8', Part(Parts, 'SizeOf(Pointer)').Value);
  Assert.AreEqual('Zielplattform Win64', Part(Parts, 'SizeOf(Pointer)').Origin);
  Assert.IsTrue(TConditionValue.No = TPascalPreprocessor.Explain('SizeOf(Pointer) = 8', Opts, Win32, Parts, Error));
  Assert.IsTrue(TConditionValue.Yes = TPascalPreprocessor.Explain('SizeOf(Integer) = 4', Opts, Win32, Parts, Error));
  Assert.IsTrue(TConditionValue.Yes =
    TPascalPreprocessor.Explain('High(NativeInt) > High(Integer)', Opts, Win64, Parts, Error));
  Assert.IsTrue(TConditionValue.No =
    TPascalPreprocessor.Explain('High(NativeInt) > High(Integer)', Opts, Win32, Parts, Error));
  Assert.IsTrue(TConditionValue.Yes = TPascalPreprocessor.Explain('Low(Integer) < 0', Opts, Win32, Parts, Error));
  Assert.IsTrue(TConditionValue.Yes = TPascalPreprocessor.Explain('High(Byte) = 255', Opts, [], Parts, Error));
  Assert.IsTrue(TConditionValue.Yes = TPascalPreprocessor.Explain('Ord(''A'') = 65', Opts, [], Parts, Error));
  // Ohne Plattform ist die Zeigergröße unbekannt.
  Assert.IsTrue(TConditionValue.Unknown = TPascalPreprocessor.Explain('SizeOf(Pointer) = 8', Opts, [], Parts, Error));
  Assert.AreEqual('', Error);
  Assert.AreEqual('a', Words(Run('{$IF SizeOf(Pointer) = 8} a {$ELSE} b {$ENDIF}', ['WIN64', 'CPU64BITS'])));
end;

procedure TPascalPreprocessorTests.EvaluatesRtlVersionConstants;
var
  Opts: TPreprocessorOptions;
  Parts: TArray<TConditionPart>;
  Error: string;
begin
  Opts := Options([]);
  Assert.IsTrue(TConditionValue.Yes = TPascalPreprocessor.Explain('RTLVersion111', Opts, [], Parts, Error));
  Assert.AreEqual('wahr', Part(Parts, 'RTLVersion111').Value);
  Assert.AreEqual('Delphi 13', Part(Parts, 'RTLVersion111').Origin);
  Assert.IsTrue(TConditionValue.Yes = TPascalPreprocessor.Explain('Declared(RTLVersion111)', Opts, [], Parts, Error));
  Assert.AreEqual('wahr', Part(Parts, 'Declared(RTLVersion111)').Value);
  Opts.CompilerVersion := 34;
  Assert.IsTrue(TConditionValue.No = TPascalPreprocessor.Explain('RTLVersion111', Opts, [], Parts, Error));
  Opts.CompilerVersion := 36;
  Assert.IsTrue(TConditionValue.Yes = TPascalPreprocessor.Explain('RTLVersion122', Opts, [], Parts, Error));
  Assert.IsTrue(TConditionValue.No = TPascalPreprocessor.Explain('RTLVersion131', Opts, [], Parts, Error));
  Assert.AreEqual('Delphi 12', TPascalPreprocessor.ProductName(36));
  Assert.AreEqual('', Error);
end;

procedure TPascalPreprocessorTests.UnknownValuesKeepBothBranchesActive;
var
  R: TPreprocessorResult;
  Opts: TPreprocessorOptions;
  Parts: TArray<TConditionPart>;
  Error: string;
begin
  R := Run('{$IF Declared(Unbekannt)} a {$ELSE} b {$ENDIF}', []);
  Assert.AreEqual('a b', Words(R));
  Assert.AreEqual<NativeInt>(0, Length(R.Issues));
  Assert.AreEqual<NativeInt>(0, Length(R.InactiveRanges));
  R := Run('{$IF MeineKonstante > 2} a {$ELSE} b {$ENDIF}', []);
  Assert.AreEqual('a b', Words(R));
  Assert.AreEqual<NativeInt>(0, Length(R.Issues));
  // Ein bekannter Teil entscheidet trotzdem: falsch und unbekannt = falsch.
  Assert.AreEqual('b', Words(Run('{$IF Defined(NIE) and (MeineKonstante > 2)} a {$ELSE} b {$ENDIF}', [])));
  Assert.AreEqual('a', Words(Run('{$IF Defined(X) or (MeineKonstante > 2)} a {$ELSE} b {$ENDIF}', ['X'])));
  // $ELSEIF nach einem unbekannten Zweig bleibt ebenfalls aktiv.
  Assert.AreEqual('a b', Words(Run('{$IF MeineKonstante > 2} a {$ELSEIF Defined(X)} b {$ELSE} c {$ENDIF}', ['X'])));
  Assert.AreEqual('a c', Words(Run('{$IF MeineKonstante > 2} a {$ELSEIF Defined(X)} b {$ELSE} c {$ENDIF}', [])));
  Opts := Options([]);
  Assert.IsTrue(TConditionValue.Unknown =
    TPascalPreprocessor.Explain('Declared(Unbekannt)', Opts, [], Parts, Error));
  Assert.AreEqual('unbekannt', Part(Parts, 'Declared(Unbekannt)').Value);
  Assert.IsTrue(TConditionValue.Unknown = TPascalPreprocessor.Explain('MeineKonstante > 2', Opts, [], Parts, Error));
  Assert.AreEqual('Konstante aus dem Code', Part(Parts, 'MeineKonstante').Origin);
end;

procedure TPascalPreprocessorTests.DeclaredAsksIndex;
var
  Opts: TPreprocessorOptions;
  Parts: TArray<TConditionPart>;
  Error: string;
  Provider: TDeclaredFunc;
begin
  Opts := Options([]);
  Provider :=
    function(const AName: string): Boolean
    begin
      Result := SameText(AName, 'TFoo');
    end;
  TPascalPreprocessor.SetDeclaredProvider(Provider);
  try
    Assert.IsTrue(TConditionValue.Yes = TPascalPreprocessor.Explain('Declared(TFoo)', Opts, [], Parts, Error));
    Assert.AreEqual('Index', Part(Parts, 'Declared(TFoo)').Origin);
    Assert.IsTrue(TConditionValue.Unknown = TPascalPreprocessor.Explain('Declared(TBar)', Opts, [], Parts, Error));
    Assert.AreEqual('b', Words(TPascalPreprocessor.Process('{$IF not Declared(TFoo)} a {$ELSE} b {$ENDIF}', Opts)));
  finally
    TPascalPreprocessor.SetDeclaredProvider(nil);
  end;
  Assert.IsTrue(TConditionValue.Unknown = TPascalPreprocessor.Explain('Declared(TFoo)', Opts, [], Parts, Error));
  Opts.Declared := Provider;
  Assert.IsTrue(TConditionValue.Yes = TPascalPreprocessor.Explain('Declared(TFoo)', Opts, [], Parts, Error));
end;

procedure TPascalPreprocessorTests.IfoptFollowsProjectAndLocalSwitches;
const
  Source = '{$IFOPT R+} a {$ELSE} b {$ENDIF}';
var
  R: TPreprocessorResult;
begin
  R := Run(Source, ['$R+']);
  Assert.AreEqual('a', Code(R));
  Assert.AreEqual<NativeInt>(1, Length(R.Checks));
  Assert.AreEqual('IFOPT', R.Checks[0].Directive);
  Assert.AreEqual('R+', R.Checks[0].Parts[0].Value);
  Assert.AreEqual('DCC_RangeChecking', R.Checks[0].Parts[0].Origin);
  Assert.AreEqual('b', Code(Run(Source, ['$R-'])));
  // Unbekannt: beide Zweige aktiv.
  Assert.AreEqual('a b', Code(Run(Source, [])));
  // Schaltereinträge sind keine Symbole.
  Assert.AreEqual<NativeInt>(0, Length(Run(Source, ['$R+']).Defines));
  R := Run('x'#10'{$R-}'#10 + Source, ['$R+']);
  Assert.AreEqual('x b', Code(R));
  Assert.AreEqual('{$R-} in Zeile 2', R.Checks[0].Parts[0].Origin);
  Assert.AreEqual('a', Code(Run('{$R-,Q+} {$IFOPT Q+} a {$ENDIF} {$IFOPT R+} b {$ENDIF}', ['$R+'])));
  Assert.AreEqual('b', Code(Run('{$RANGECHECKS OFF} ' + Source, ['$R+'])));
  // {$R Datei.res} ist kein Schalter.
  Assert.AreEqual('a', Code(Run('{$R *.res} ' + Source, ['$R+'])));
  R := Run('{$IFOPT ?} a {$ENDIF}', []);
  Assert.AreEqual<NativeInt>(1, Length(R.Issues));
end;

procedure TPascalPreprocessorTests.PushOptRestoresSwitches;
var
  R: TPreprocessorResult;
begin
  R := Run('{$PUSHOPT} {$R-} {$IFOPT R+} a {$ENDIF} {$POPOPT} {$IFOPT R+} b {$ENDIF}', ['$R+']);
  Assert.AreEqual('b', Code(R));
  Assert.AreEqual<NativeInt>(0, Length(R.Issues));
  // Verschachtelt, auch für {$M+}.
  Assert.AreEqual('a c', Code(Run('{$M-} {$PUSHOPT} {$M+} {$PUSHOPT} {$M-} {$POPOPT} {$IFOPT M+} a {$ENDIF} ' +
    '{$POPOPT} {$IFOPT M+} b {$ELSE} c {$ENDIF}', [])));
  R := Run('{$POPOPT} a', []);
  Assert.AreEqual('a', Code(R));
  Assert.AreEqual<NativeInt>(1, Length(R.Issues));
end;

procedure TPascalPreprocessorTests.MapsProjectPropertiesToSwitches;
var
  Switches: TArray<string>;
  R: TPreprocessorResult;
begin
  Switches := TPascalPreprocessor.ProjectSwitches([
    TPair<string, string>.Create('DCC_RangeChecking', 'true'),
    TPair<string, string>.Create('DCC_Optimize', 'false'),
    TPair<string, string>.Create('DCC_DebugInformation', '2'),
    TPair<string, string>.Create('DCC_IntegerOverflowCheck', 'True'),
    TPair<string, string>.Create('DCC_AssertionsAtRuntime', 'false'),
    TPair<string, string>.Create('DCC_Define', 'DEBUG')]);
  Assert.AreEqual('$C-,$D+,$I+*,$J-*,$L+*,$O-,$Q+,$R+,$W-*', string.Join(',', Switches));
  // Die Vorgabe des Compilers gilt mit eigener Herkunft.
  R := Run('{$IFOPT W+} a {$ELSE} b {$ENDIF}', Switches);
  Assert.AreEqual('b', Code(R));
  Assert.AreEqual('DCC_GenerateStackFrames (Vorgabe des Compilers)', R.Checks[0].Parts[0].Origin);
  Assert.IsTrue(TPascalPreprocessor.IsSwitchEntry('$R+'));
  Assert.IsFalse(TPascalPreprocessor.IsSwitchEntry('DEBUG'));
  Assert.AreEqual('DCC_RangeChecking', TPascalPreprocessor.SwitchProperty('r'));
  Assert.AreEqual('', TPascalPreprocessor.SwitchProperty('M'));
end;

procedure TPascalPreprocessorTests.RecordsConditionChecks;
var
  R: TPreprocessorResult;
begin
  R := Run('{$IFDEF X} {$IF SizeOf(Pointer) = 8} a {$ENDIF} {$ENDIF}'#10 +
    '{$IF Defined(A)} b {$ELSEIF RTLVersion111} c {$ENDIF}',
    ['WIN64', 'CPU64BITS']);
  // Der $IF im inaktiven $IFDEF wird nicht ausgewertet.
  Assert.AreEqual('c', Words(R));
  Assert.AreEqual<NativeInt>(2, Length(R.Checks));
  Assert.AreEqual('IF', R.Checks[0].Directive);
  Assert.AreEqual('Defined(A)', R.Checks[0].Expression);
  Assert.IsTrue(TConditionValue.No = R.Checks[0].Value);
  Assert.AreEqual(1, R.Checks[0].Range.StartPos.Line);
  Assert.AreEqual('ELSEIF', R.Checks[1].Directive);
  Assert.IsTrue(TConditionValue.Yes = R.Checks[1].Value);
  Assert.AreEqual('Delphi 13', Part(R.Checks[1].Parts, 'RTLVersion111').Origin);
end;

initialization
  TDUnitX.RegisterTestFixture(TPascalPreprocessorTests);

end.
