unit Atlas.Common.Pascal.ConditionalSyntax.Tests;

// Syntaxfehler und bedingte Kompilierung: inaktive Zweige von $IFDEF/$IF/$ELSE
// erzeugen keine Syntaxfehler, auch nicht mit Code eines anderen Compilers oder
// Text, der kein Pascal ist. Die 21 Fälle stammen aus dem Fehlerbericht des
// Projekts XML-Inspector (Delphi und Free Pascal aus denselben Quellen); jede
// Unit ist unter Delphi gültig.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TConditionalSyntaxTests = class
  public
    /// <summary>Ohne Projekt: Vordefinitionen von Delphi, FPC nicht gesetzt.</summary>
    [Test]
    [TestCase('P01', '0')]
    [TestCase('P02', '1')]
    [TestCase('P03', '2')]
    [TestCase('P04', '3')]
    [TestCase('P05', '4')]
    [TestCase('P06', '5')]
    [TestCase('P07', '6')]
    [TestCase('P08', '7')]
    [TestCase('P09', '8')]
    [TestCase('P10', '9')]
    [TestCase('P11', '10')]
    [TestCase('P12', '11')]
    [TestCase('P13', '12')]
    [TestCase('P14', '13')]
    [TestCase('P15', '14')]
    [TestCase('P16', '15')]
    [TestCase('P17', '16')]
    [TestCase('P18', '17')]
    [TestCase('P19', '18')]
    [TestCase('P20', '19')]
    [TestCase('P21', '20')]
    procedure NoSyntaxErrorsWithDelphiSymbols(AIndex: Integer);
    /// <summary>Mit FPC; P17 fehlt, Atlas muss Free-Pascal-Syntax nicht parsen.</summary>
    [Test]
    [TestCase('P01', '0')]
    [TestCase('P02', '1')]
    [TestCase('P03', '2')]
    [TestCase('P04', '3')]
    [TestCase('P05', '4')]
    [TestCase('P06', '5')]
    [TestCase('P07', '6')]
    [TestCase('P08', '7')]
    [TestCase('P09', '8')]
    [TestCase('P10', '9')]
    [TestCase('P11', '10')]
    [TestCase('P12', '11')]
    [TestCase('P13', '12')]
    [TestCase('P14', '13')]
    [TestCase('P15', '14')]
    [TestCase('P16', '15')]
    [TestCase('P18', '17')]
    [TestCase('P19', '18')]
    [TestCase('P20', '19')]
    [TestCase('P21', '20')]
    procedure NoSyntaxErrorsWithFpc(AIndex: Integer);
    /// <summary>Weg des Linters (--check): TFileChecker.</summary>
    [Test]
    procedure FileCheckerIgnoresInactiveBranches;
    /// <summary>Weg des Editors bzw. MCP: Diagnosen der LSP-Schicht.</summary>
    [Test]
    procedure LspDiagnosticsIgnoreInactiveBranches;
    /// <summary>Fehler im aktiven Zweig bleiben Fehler.</summary>
    [Test]
    procedure ActiveBranchStillReportsErrors;
    /// <summary>Ohne bedingte Direktiven gelten die Diagnosen des Baums.</summary>
    [Test]
    procedure WithoutConditionalsUsesTree;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Lsp.SyntaxDiagnostics;

const
  cCrlf = #13#10;
  cCases: array[0..20] of string = (
    // P01
    'unit P01;' + cCrlf +
    '' + cCrlf +
    '{ uses: je Zweig eigene Liste mit ; }' + cCrlf +
    'interface' + cCrlf +
    'uses' + cCrlf +
    '{$IFDEF FPC}' + cCrlf +
    '  SysUtils;' + cCrlf +
    '{$ELSE}' + cCrlf +
    '  System.SysUtils;' + cCrlf +
    '{$ENDIF}' + cCrlf +
    'implementation' + cCrlf +
    'end.',
    // P02
    'unit P02;' + cCrlf +
    '' + cCrlf +
    '{ uses: gemeinsamer Rest nach dem bedingten Teil }' + cCrlf +
    'interface' + cCrlf +
    'uses' + cCrlf +
    '{$IFDEF FPC}' + cCrlf +
    '  SysUtils, Classes,' + cCrlf +
    '{$ELSE}' + cCrlf +
    '  System.SysUtils, System.Classes,' + cCrlf +
    '{$ENDIF}' + cCrlf +
    '  System.Math;' + cCrlf +
    'implementation' + cCrlf +
    'end.',
    // P03
    'unit P03;' + cCrlf +
    '' + cCrlf +
    '{ uses: Zweig nur mit IFNDEF, kein ELSE }' + cCrlf +
    'interface' + cCrlf +
    'uses' + cCrlf +
    '  System.SysUtils' + cCrlf +
    '{$IFNDEF FPC}' + cCrlf +
    '  , System.Classes' + cCrlf +
    '{$ENDIF}' + cCrlf +
    '  ;' + cCrlf +
    'implementation' + cCrlf +
    'end.',
    // P04
    'unit P04;' + cCrlf +
    '' + cCrlf +
    '{ uses im implementation-Teil je Zweig }' + cCrlf +
    'interface' + cCrlf +
    'implementation' + cCrlf +
    'uses' + cCrlf +
    '{$IFDEF FPC}' + cCrlf +
    '  LCLType, Clipbrd;' + cCrlf +
    '{$ELSE}' + cCrlf +
    '  Winapi.Windows, Vcl.Clipbrd;' + cCrlf +
    '{$ENDIF}' + cCrlf +
    'end.',
    // P05
    'unit P05;' + cCrlf +
    '' + cCrlf +
    '{ Routinenrumpf je Zweig (var und begin..end zweimal) }' + cCrlf +
    'interface' + cCrlf +
    'function F(var A: string): Boolean;' + cCrlf +
    'implementation' + cCrlf +
    'function F(var A: string): Boolean;' + cCrlf +
    '{$IFDEF FPC}' + cCrlf +
    'var' + cCrlf +
    '  S: AnsiString;' + cCrlf +
    'begin' + cCrlf +
    '  S := AnsiString(A);' + cCrlf +
    '  Result := S <> '''';' + cCrlf +
    'end;' + cCrlf +
    '{$ELSE}' + cCrlf +
    'begin' + cCrlf +
    '  Result := A <> '''';' + cCrlf +
    'end;' + cCrlf +
    '{$ENDIF}' + cCrlf +
    'end.',
    // P06
    'unit P06;' + cCrlf +
    '' + cCrlf +
    '{ Routinenkopf je Zweig, Rumpf gemeinsam }' + cCrlf +
    'interface' + cCrlf +
    'implementation' + cCrlf +
    '{$IFDEF FPC}' + cCrlf +
    'procedure P(const A: AnsiString);' + cCrlf +
    '{$ELSE}' + cCrlf +
    'procedure P(const A: string);' + cCrlf +
    '{$ENDIF}' + cCrlf +
    'begin' + cCrlf +
    '  if A = '''' then' + cCrlf +
    '    Exit;' + cCrlf +
    'end;' + cCrlf +
    'end.',
    // P07
    'unit P07;' + cCrlf +
    '' + cCrlf +
    '{ Bedingter Block als letzte Anweisung }' + cCrlf +
    'interface' + cCrlf +
    'implementation' + cCrlf +
    'procedure P(B: Boolean);' + cCrlf +
    'var' + cCrlf +
    '  I: Integer;' + cCrlf +
    'begin' + cCrlf +
    '  I := 0;' + cCrlf +
    '{$IFNDEF FPC}' + cCrlf +
    '  if B then' + cCrlf +
    '    Inc(I);' + cCrlf +
    '{$ENDIF}' + cCrlf +
    'end;' + cCrlf +
    'end.',
    // P08
    'unit P08;' + cCrlf +
    '' + cCrlf +
    '{ Bedingter else-Teil einer if-Anweisung }' + cCrlf +
    'interface' + cCrlf +
    'implementation' + cCrlf +
    'procedure P(B: Boolean);' + cCrlf +
    'var' + cCrlf +
    '  I: Integer;' + cCrlf +
    'begin' + cCrlf +
    '  if B then' + cCrlf +
    '    I := 1' + cCrlf +
    '{$IFNDEF FPC}' + cCrlf +
    '  else' + cCrlf +
    '    I := 2' + cCrlf +
    '{$ENDIF}' + cCrlf +
    '  ;' + cCrlf +
    'end;' + cCrlf +
    'end.',
    // P09
    'unit P09;' + cCrlf +
    '' + cCrlf +
    '{ Bedingung mitten in einer Typdeklaration }' + cCrlf +
    'interface' + cCrlf +
    'uses' + cCrlf +
    '  Winapi.Messages;' + cCrlf +
    'type' + cCrlf +
    '  THookMessage = {$IFDEF FPC}TLMessage{$ELSE}TMessage{$ENDIF};' + cCrlf +
    'implementation' + cCrlf +
    'end.',
    // P10
    'unit P10;' + cCrlf +
    '' + cCrlf +
    '{ Bedingung mitten in einem Ausdruck }' + cCrlf +
    'interface' + cCrlf +
    'implementation' + cCrlf +
    'uses' + cCrlf +
    '  Winapi.Messages;' + cCrlf +
    'function IsKey(Msg: Cardinal): Boolean;' + cCrlf +
    'begin' + cCrlf +
    '  Result := (Msg = {$IFDEF FPC}LM_KEYDOWN{$ELSE}WM_KEYDOWN{$ENDIF}) or (Msg = 0);' + cCrlf +
    'end;' + cCrlf +
    'end.',
    // P11
    'unit P11;' + cCrlf +
    '' + cCrlf +
    '{ Bedingung in einer Parameterliste }' + cCrlf +
    'interface' + cCrlf +
    'procedure P(A: Integer{$IFNDEF FPC}; B: Integer = 0{$ENDIF});' + cCrlf +
    'implementation' + cCrlf +
    'procedure P(A: Integer{$IFNDEF FPC}; B: Integer{$ENDIF});' + cCrlf +
    'begin' + cCrlf +
    'end;' + cCrlf +
    'end.',
    // P12
    'unit P12;' + cCrlf +
    '' + cCrlf +
    '{ Schlüsselwort je Zweig (const/resourcestring) }' + cCrlf +
    'interface' + cCrlf +
    '{$IFDEF FPC}const{$ELSE}resourcestring{$ENDIF}' + cCrlf +
    '  SHello = ''Hallo'';' + cCrlf +
    'implementation' + cCrlf +
    'end.',
    // P13
    'unit P13;' + cCrlf +
    '' + cCrlf +
    '{ Klassenmitglieder je Zweig }' + cCrlf +
    'interface' + cCrlf +
    'uses' + cCrlf +
    '  System.Classes;' + cCrlf +
    'type' + cCrlf +
    '  TFoo = class(TComponent)' + cCrlf +
    '  private' + cCrlf +
    '{$IFDEF FPC}' + cCrlf +
    '    procedure WMKey(var M: TLMKey); message LM_KEYDOWN;' + cCrlf +
    '{$ELSE}' + cCrlf +
    '    FHandle: NativeUInt;' + cCrlf +
    '    procedure Paint;' + cCrlf +
    '{$ENDIF}' + cCrlf +
    '  end;' + cCrlf +
    'implementation' + cCrlf +
    'procedure TFoo.Paint;' + cCrlf +
    'begin' + cCrlf +
    'end;' + cCrlf +
    'end.',
    // P14
    'unit P14;' + cCrlf +
    '' + cCrlf +
    '{ Vorfahr der Klasse je Zweig }' + cCrlf +
    'interface' + cCrlf +
    'uses' + cCrlf +
    '  System.Classes;' + cCrlf +
    'type' + cCrlf +
    '  TFoo = class({$IFDEF FPC}TPersistent{$ELSE}TComponent{$ENDIF})' + cCrlf +
    '  end;' + cCrlf +
    'implementation' + cCrlf +
    'end.',
    // P15
    'unit P15;' + cCrlf +
    '' + cCrlf +
    '{ Verschachtelte Bedingungen }' + cCrlf +
    'interface' + cCrlf +
    'uses' + cCrlf +
    '{$IFDEF FPC}' + cCrlf +
    '  {$IFDEF UNIX}cthreads,{$ENDIF}' + cCrlf +
    '  SysUtils;' + cCrlf +
    '{$ELSE}' + cCrlf +
    '  {$IFDEF MSWINDOWS}Winapi.Windows,{$ENDIF}' + cCrlf +
    '  System.SysUtils;' + cCrlf +
    '{$ENDIF}' + cCrlf +
    'implementation' + cCrlf +
    'end.',
    // P16
    'unit P16;' + cCrlf +
    '' + cCrlf +
    '{ $IF mit DEFINED und ELSEIF }' + cCrlf +
    'interface' + cCrlf +
    'uses' + cCrlf +
    '{$IF DEFINED(FPC)}' + cCrlf +
    '  SysUtils;' + cCrlf +
    '{$ELSEIF DEFINED(MSWINDOWS)}' + cCrlf +
    '  Winapi.Windows, System.SysUtils;' + cCrlf +
    '{$ELSE}' + cCrlf +
    '  System.SysUtils;' + cCrlf +
    '{$IFEND}' + cCrlf +
    'implementation' + cCrlf +
    'end.',
    // P17
    'unit P17;' + cCrlf +
    '' + cCrlf +
    '{ Inaktiver Zweig mit Syntax, die nur FPC kennt }' + cCrlf +
    '{$IFDEF FPC}{$MODE OBJFPC}{$ENDIF}' + cCrlf +
    'interface' + cCrlf +
    'implementation' + cCrlf +
    '{$IFDEF FPC}' + cCrlf +
    'generic function Max<T>(A, B: T): T;' + cCrlf +
    'begin' + cCrlf +
    '  if A > B then Result := A else Result := B;' + cCrlf +
    'end;' + cCrlf +
    'operator := (const A: Integer): string;' + cCrlf +
    'begin' + cCrlf +
    '  Result := '''';' + cCrlf +
    'end;' + cCrlf +
    '{$ENDIF}' + cCrlf +
    'end.',
    // P18
    'unit P18;' + cCrlf +
    '' + cCrlf +
    '{ Inaktiver Zweig mit Text, der kein Pascal ist }' + cCrlf +
    'interface' + cCrlf +
    'implementation' + cCrlf +
    'procedure P;' + cCrlf +
    'begin' + cCrlf +
    '{$IFDEF NIEMALS}' + cCrlf +
    '  das ist kein Pascal ((' + cCrlf +
    '{$ENDIF}' + cCrlf +
    'end;' + cCrlf +
    'end.',
    // P19
    'unit P19;' + cCrlf +
    '' + cCrlf +
    '{ initialization je Zweig }' + cCrlf +
    'interface' + cCrlf +
    'implementation' + cCrlf +
    'var' + cCrlf +
    '  G: Integer;' + cCrlf +
    'initialization' + cCrlf +
    '{$IFDEF FPC}' + cCrlf +
    '  G := 1;' + cCrlf +
    '{$ELSE}' + cCrlf +
    '  G := 2;' + cCrlf +
    '{$ENDIF}' + cCrlf +
    'finalization' + cCrlf +
    '  G := 0;' + cCrlf +
    'end.',
    // P20
    'unit P20;' + cCrlf +
    '' + cCrlf +
    '{ IFOPT, DEFINE und UNDEF }' + cCrlf +
    'interface' + cCrlf +
    'implementation' + cCrlf +
    '{$IFOPT R+}{$DEFINE RANGE_ON}{$R-}{$ENDIF}' + cCrlf +
    'function Sum(A, B: Integer): Integer;' + cCrlf +
    'begin' + cCrlf +
    '  Result := A + B;' + cCrlf +
    'end;' + cCrlf +
    '{$IFDEF RANGE_ON}{$R+}{$UNDEF RANGE_ON}{$ENDIF}' + cCrlf +
    'end.',
    // P21
    'unit P21;' + cCrlf +
    '' + cCrlf +
    '{ Symbol aus dem Projekt (DCC_Define) entscheidet den Zweig }' + cCrlf +
    'interface' + cCrlf +
    'implementation' + cCrlf +
    'procedure P;' + cCrlf +
    'begin' + cCrlf +
    '{$IFDEF XMLI_TEST_FEATURES}' + cCrlf +
    '  Writeln(''Test'');' + cCrlf +
    '{$ELSE}' + cCrlf +
    '  Writeln(''Normal'')' + cCrlf +
    '{$ENDIF}' + cCrlf +
    'end;' + cCrlf +
    'end.');

function Describe(const ADiagnostics: TArray<TSyntaxDiagnostic>): string;
var
  mDiagnostic: TSyntaxDiagnostic;
begin
  Result := '';
  for mDiagnostic in ADiagnostics do
  begin
    Result := Result + Format('Z. %d: %s; ', [mDiagnostic.StartPos.Line + 1, mDiagnostic.Message]);
  end;
end;

function SyntaxErrors(const AText: string; const ADefines: TArray<string>): TArray<TSyntaxDiagnostic>;
var
  mTree: TSyntaxTree;
begin
  if TPascalParser.ActiveDiagnostics(AText, ADefines, Result) then
  begin
    Exit;
  end;
  mTree := TPascalParser.Parse(AText);
  try
    Result := mTree.Diagnostics;
  finally
    mTree.Free;
  end;
end;

{ TConditionalSyntaxTests }

procedure TConditionalSyntaxTests.NoSyntaxErrorsWithDelphiSymbols(AIndex: Integer);
var
  mErrors: TArray<TSyntaxDiagnostic>;
begin
  mErrors := SyntaxErrors(cCases[AIndex], nil);
  Assert.AreEqual(0, Integer(Length(mErrors)), Describe(mErrors));
end;

procedure TConditionalSyntaxTests.NoSyntaxErrorsWithFpc(AIndex: Integer);
var
  mErrors: TArray<TSyntaxDiagnostic>;
begin
  mErrors := SyntaxErrors(cCases[AIndex], ['FPC', 'MSWINDOWS']);
  Assert.AreEqual(0, Integer(Length(mErrors)), Describe(mErrors));
end;

procedure TConditionalSyntaxTests.FileCheckerIgnoresInactiveBranches;
var
  mText: string;
  mFindings: TArray<TRuleFinding>;
begin
  for mText in cCases do
  begin
    mFindings := TFileChecker.CheckText(nil, TServerSettings.Default, '', mText);
    Assert.AreEqual(0, Integer(Length(mFindings)), mText);
  end;
end;

procedure TConditionalSyntaxTests.LspDiagnosticsIgnoreInactiveBranches;
var
  mStore: IDocumentStore;
  mParams: TJSONObject;
begin
  mStore := TDocumentStore.Create;
  mParams := TLspSyntaxDiagnostics.BuildParams(mStore.Open('file:///c:/p18.pas', 'objectpascal', 1, cCases[17]));
  try
    Assert.AreEqual(0, mParams.GetValue<TJSONArray>('diagnostics').Count, mParams.ToJSON);
  finally
    mParams.Free;
  end;
end;

procedure TConditionalSyntaxTests.ActiveBranchStillReportsErrors;
const
  cText = 'unit A;' + cCrlf + 'interface' + cCrlf + 'implementation' + cCrlf + 'procedure P;' + cCrlf + 'begin' + cCrlf +
    '{$IFNDEF NIEMALS}' + cCrlf + '  das ist kein Pascal ((' + cCrlf + '{$ENDIF}' + cCrlf + 'end;' + cCrlf + 'end.';
begin
  Assert.IsTrue(Length(SyntaxErrors(cText, nil)) > 0);
end;

procedure TConditionalSyntaxTests.WithoutConditionalsUsesTree;
var
  mDiagnostics: TArray<TSyntaxDiagnostic>;
begin
  Assert.IsFalse(TPascalParser.ActiveDiagnostics('unit A; interface implementation end.', nil, mDiagnostics));
end;

end.
