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
  Crlf = #13#10;
  Cases: array[0..20] of string = (
    // P01
    'unit P01;' + Crlf +
    '' + Crlf +
    '{ uses: je Zweig eigene Liste mit ; }' + Crlf +
    'interface' + Crlf +
    'uses' + Crlf +
    '{$IFDEF FPC}' + Crlf +
    '  SysUtils;' + Crlf +
    '{$ELSE}' + Crlf +
    '  System.SysUtils;' + Crlf +
    '{$ENDIF}' + Crlf +
    'implementation' + Crlf +
    'end.',
    // P02
    'unit P02;' + Crlf +
    '' + Crlf +
    '{ uses: gemeinsamer Rest nach dem bedingten Teil }' + Crlf +
    'interface' + Crlf +
    'uses' + Crlf +
    '{$IFDEF FPC}' + Crlf +
    '  SysUtils, Classes,' + Crlf +
    '{$ELSE}' + Crlf +
    '  System.SysUtils, System.Classes,' + Crlf +
    '{$ENDIF}' + Crlf +
    '  System.Math;' + Crlf +
    'implementation' + Crlf +
    'end.',
    // P03
    'unit P03;' + Crlf +
    '' + Crlf +
    '{ uses: Zweig nur mit IFNDEF, kein ELSE }' + Crlf +
    'interface' + Crlf +
    'uses' + Crlf +
    '  System.SysUtils' + Crlf +
    '{$IFNDEF FPC}' + Crlf +
    '  , System.Classes' + Crlf +
    '{$ENDIF}' + Crlf +
    '  ;' + Crlf +
    'implementation' + Crlf +
    'end.',
    // P04
    'unit P04;' + Crlf +
    '' + Crlf +
    '{ uses im implementation-Teil je Zweig }' + Crlf +
    'interface' + Crlf +
    'implementation' + Crlf +
    'uses' + Crlf +
    '{$IFDEF FPC}' + Crlf +
    '  LCLType, Clipbrd;' + Crlf +
    '{$ELSE}' + Crlf +
    '  Winapi.Windows, Vcl.Clipbrd;' + Crlf +
    '{$ENDIF}' + Crlf +
    'end.',
    // P05
    'unit P05;' + Crlf +
    '' + Crlf +
    '{ Routinenrumpf je Zweig (var und begin..end zweimal) }' + Crlf +
    'interface' + Crlf +
    'function F(var A: string): Boolean;' + Crlf +
    'implementation' + Crlf +
    'function F(var A: string): Boolean;' + Crlf +
    '{$IFDEF FPC}' + Crlf +
    'var' + Crlf +
    '  S: AnsiString;' + Crlf +
    'begin' + Crlf +
    '  S := AnsiString(A);' + Crlf +
    '  Result := S <> '''';' + Crlf +
    'end;' + Crlf +
    '{$ELSE}' + Crlf +
    'begin' + Crlf +
    '  Result := A <> '''';' + Crlf +
    'end;' + Crlf +
    '{$ENDIF}' + Crlf +
    'end.',
    // P06
    'unit P06;' + Crlf +
    '' + Crlf +
    '{ Routinenkopf je Zweig, Rumpf gemeinsam }' + Crlf +
    'interface' + Crlf +
    'implementation' + Crlf +
    '{$IFDEF FPC}' + Crlf +
    'procedure P(const A: AnsiString);' + Crlf +
    '{$ELSE}' + Crlf +
    'procedure P(const A: string);' + Crlf +
    '{$ENDIF}' + Crlf +
    'begin' + Crlf +
    '  if A = '''' then' + Crlf +
    '    Exit;' + Crlf +
    'end;' + Crlf +
    'end.',
    // P07
    'unit P07;' + Crlf +
    '' + Crlf +
    '{ Bedingter Block als letzte Anweisung }' + Crlf +
    'interface' + Crlf +
    'implementation' + Crlf +
    'procedure P(B: Boolean);' + Crlf +
    'var' + Crlf +
    '  I: Integer;' + Crlf +
    'begin' + Crlf +
    '  I := 0;' + Crlf +
    '{$IFNDEF FPC}' + Crlf +
    '  if B then' + Crlf +
    '    Inc(I);' + Crlf +
    '{$ENDIF}' + Crlf +
    'end;' + Crlf +
    'end.',
    // P08
    'unit P08;' + Crlf +
    '' + Crlf +
    '{ Bedingter else-Teil einer if-Anweisung }' + Crlf +
    'interface' + Crlf +
    'implementation' + Crlf +
    'procedure P(B: Boolean);' + Crlf +
    'var' + Crlf +
    '  I: Integer;' + Crlf +
    'begin' + Crlf +
    '  if B then' + Crlf +
    '    I := 1' + Crlf +
    '{$IFNDEF FPC}' + Crlf +
    '  else' + Crlf +
    '    I := 2' + Crlf +
    '{$ENDIF}' + Crlf +
    '  ;' + Crlf +
    'end;' + Crlf +
    'end.',
    // P09
    'unit P09;' + Crlf +
    '' + Crlf +
    '{ Bedingung mitten in einer Typdeklaration }' + Crlf +
    'interface' + Crlf +
    'uses' + Crlf +
    '  Winapi.Messages;' + Crlf +
    'type' + Crlf +
    '  THookMessage = {$IFDEF FPC}TLMessage{$ELSE}TMessage{$ENDIF};' + Crlf +
    'implementation' + Crlf +
    'end.',
    // P10
    'unit P10;' + Crlf +
    '' + Crlf +
    '{ Bedingung mitten in einem Ausdruck }' + Crlf +
    'interface' + Crlf +
    'implementation' + Crlf +
    'uses' + Crlf +
    '  Winapi.Messages;' + Crlf +
    'function IsKey(Msg: Cardinal): Boolean;' + Crlf +
    'begin' + Crlf +
    '  Result := (Msg = {$IFDEF FPC}LM_KEYDOWN{$ELSE}WM_KEYDOWN{$ENDIF}) or (Msg = 0);' + Crlf +
    'end;' + Crlf +
    'end.',
    // P11
    'unit P11;' + Crlf +
    '' + Crlf +
    '{ Bedingung in einer Parameterliste }' + Crlf +
    'interface' + Crlf +
    'procedure P(A: Integer{$IFNDEF FPC}; B: Integer = 0{$ENDIF});' + Crlf +
    'implementation' + Crlf +
    'procedure P(A: Integer{$IFNDEF FPC}; B: Integer{$ENDIF});' + Crlf +
    'begin' + Crlf +
    'end;' + Crlf +
    'end.',
    // P12
    'unit P12;' + Crlf +
    '' + Crlf +
    '{ Schlüsselwort je Zweig (const/resourcestring) }' + Crlf +
    'interface' + Crlf +
    '{$IFDEF FPC}const{$ELSE}resourcestring{$ENDIF}' + Crlf +
    '  SHello = ''Hallo'';' + Crlf +
    'implementation' + Crlf +
    'end.',
    // P13
    'unit P13;' + Crlf +
    '' + Crlf +
    '{ Klassenmitglieder je Zweig }' + Crlf +
    'interface' + Crlf +
    'uses' + Crlf +
    '  System.Classes;' + Crlf +
    'type' + Crlf +
    '  TFoo = class(TComponent)' + Crlf +
    '  private' + Crlf +
    '{$IFDEF FPC}' + Crlf +
    '    procedure WMKey(var M: TLMKey); message LM_KEYDOWN;' + Crlf +
    '{$ELSE}' + Crlf +
    '    FHandle: NativeUInt;' + Crlf +
    '    procedure Paint;' + Crlf +
    '{$ENDIF}' + Crlf +
    '  end;' + Crlf +
    'implementation' + Crlf +
    'procedure TFoo.Paint;' + Crlf +
    'begin' + Crlf +
    'end;' + Crlf +
    'end.',
    // P14
    'unit P14;' + Crlf +
    '' + Crlf +
    '{ Vorfahr der Klasse je Zweig }' + Crlf +
    'interface' + Crlf +
    'uses' + Crlf +
    '  System.Classes;' + Crlf +
    'type' + Crlf +
    '  TFoo = class({$IFDEF FPC}TPersistent{$ELSE}TComponent{$ENDIF})' + Crlf +
    '  end;' + Crlf +
    'implementation' + Crlf +
    'end.',
    // P15
    'unit P15;' + Crlf +
    '' + Crlf +
    '{ Verschachtelte Bedingungen }' + Crlf +
    'interface' + Crlf +
    'uses' + Crlf +
    '{$IFDEF FPC}' + Crlf +
    '  {$IFDEF UNIX}cthreads,{$ENDIF}' + Crlf +
    '  SysUtils;' + Crlf +
    '{$ELSE}' + Crlf +
    '  {$IFDEF MSWINDOWS}Winapi.Windows,{$ENDIF}' + Crlf +
    '  System.SysUtils;' + Crlf +
    '{$ENDIF}' + Crlf +
    'implementation' + Crlf +
    'end.',
    // P16
    'unit P16;' + Crlf +
    '' + Crlf +
    '{ $IF mit DEFINED und ELSEIF }' + Crlf +
    'interface' + Crlf +
    'uses' + Crlf +
    '{$IF DEFINED(FPC)}' + Crlf +
    '  SysUtils;' + Crlf +
    '{$ELSEIF DEFINED(MSWINDOWS)}' + Crlf +
    '  Winapi.Windows, System.SysUtils;' + Crlf +
    '{$ELSE}' + Crlf +
    '  System.SysUtils;' + Crlf +
    '{$IFEND}' + Crlf +
    'implementation' + Crlf +
    'end.',
    // P17
    'unit P17;' + Crlf +
    '' + Crlf +
    '{ Inaktiver Zweig mit Syntax, die nur FPC kennt }' + Crlf +
    '{$IFDEF FPC}{$MODE OBJFPC}{$ENDIF}' + Crlf +
    'interface' + Crlf +
    'implementation' + Crlf +
    '{$IFDEF FPC}' + Crlf +
    'generic function Max<T>(A, B: T): T;' + Crlf +
    'begin' + Crlf +
    '  if A > B then Result := A else Result := B;' + Crlf +
    'end;' + Crlf +
    'operator := (const A: Integer): string;' + Crlf +
    'begin' + Crlf +
    '  Result := '''';' + Crlf +
    'end;' + Crlf +
    '{$ENDIF}' + Crlf +
    'end.',
    // P18
    'unit P18;' + Crlf +
    '' + Crlf +
    '{ Inaktiver Zweig mit Text, der kein Pascal ist }' + Crlf +
    'interface' + Crlf +
    'implementation' + Crlf +
    'procedure P;' + Crlf +
    'begin' + Crlf +
    '{$IFDEF NIEMALS}' + Crlf +
    '  das ist kein Pascal ((' + Crlf +
    '{$ENDIF}' + Crlf +
    'end;' + Crlf +
    'end.',
    // P19
    'unit P19;' + Crlf +
    '' + Crlf +
    '{ initialization je Zweig }' + Crlf +
    'interface' + Crlf +
    'implementation' + Crlf +
    'var' + Crlf +
    '  G: Integer;' + Crlf +
    'initialization' + Crlf +
    '{$IFDEF FPC}' + Crlf +
    '  G := 1;' + Crlf +
    '{$ELSE}' + Crlf +
    '  G := 2;' + Crlf +
    '{$ENDIF}' + Crlf +
    'finalization' + Crlf +
    '  G := 0;' + Crlf +
    'end.',
    // P20
    'unit P20;' + Crlf +
    '' + Crlf +
    '{ IFOPT, DEFINE und UNDEF }' + Crlf +
    'interface' + Crlf +
    'implementation' + Crlf +
    '{$IFOPT R+}{$DEFINE RANGE_ON}{$R-}{$ENDIF}' + Crlf +
    'function Sum(A, B: Integer): Integer;' + Crlf +
    'begin' + Crlf +
    '  Result := A + B;' + Crlf +
    'end;' + Crlf +
    '{$IFDEF RANGE_ON}{$R+}{$UNDEF RANGE_ON}{$ENDIF}' + Crlf +
    'end.',
    // P21
    'unit P21;' + Crlf +
    '' + Crlf +
    '{ Symbol aus dem Projekt (DCC_Define) entscheidet den Zweig }' + Crlf +
    'interface' + Crlf +
    'implementation' + Crlf +
    'procedure P;' + Crlf +
    'begin' + Crlf +
    '{$IFDEF XMLI_TEST_FEATURES}' + Crlf +
    '  Writeln(''Test'');' + Crlf +
    '{$ELSE}' + Crlf +
    '  Writeln(''Normal'')' + Crlf +
    '{$ENDIF}' + Crlf +
    'end;' + Crlf +
    'end.');

function Describe(const ADiagnostics: TArray<TSyntaxDiagnostic>): string;
var
  Diagnostic: TSyntaxDiagnostic;
begin
  Result := '';
  for Diagnostic in ADiagnostics do
    Result := Result + Format('Z. %d: %s; ', [Diagnostic.StartPos.Line + 1, Diagnostic.Message]);
end;

function SyntaxErrors(const AText: string; const ADefines: TArray<string>): TArray<TSyntaxDiagnostic>;
var
  Tree: TSyntaxTree;
begin
  if TPascalParser.ActiveDiagnostics(AText, ADefines, Result) then
    Exit;
  Tree := TPascalParser.Parse(AText);
  try
    Result := Tree.Diagnostics;
  finally
    Tree.Free;
  end;
end;

{ TConditionalSyntaxTests }

procedure TConditionalSyntaxTests.NoSyntaxErrorsWithDelphiSymbols(AIndex: Integer);
var
  Errors: TArray<TSyntaxDiagnostic>;
begin
  Errors := SyntaxErrors(Cases[AIndex], nil);
  Assert.AreEqual(0, Integer(Length(Errors)), Describe(Errors));
end;

procedure TConditionalSyntaxTests.NoSyntaxErrorsWithFpc(AIndex: Integer);
var
  Errors: TArray<TSyntaxDiagnostic>;
begin
  Errors := SyntaxErrors(Cases[AIndex], ['FPC', 'MSWINDOWS']);
  Assert.AreEqual(0, Integer(Length(Errors)), Describe(Errors));
end;

procedure TConditionalSyntaxTests.FileCheckerIgnoresInactiveBranches;
var
  Text: string;
  Findings: TArray<TRuleFinding>;
begin
  for Text in Cases do
  begin
    Findings := TFileChecker.CheckText(nil, TServerSettings.Default, '', Text);
    Assert.AreEqual(0, Integer(Length(Findings)), Text);
  end;
end;

procedure TConditionalSyntaxTests.LspDiagnosticsIgnoreInactiveBranches;
var
  Store: IDocumentStore;
  Params: TJSONObject;
begin
  Store := TDocumentStore.Create;
  Params := TLspSyntaxDiagnostics.BuildParams(Store.Open('file:///c:/p18.pas', 'objectpascal', 1, Cases[17]));
  try
    Assert.AreEqual(0, Params.GetValue<TJSONArray>('diagnostics').Count, Params.ToJSON);
  finally
    Params.Free;
  end;
end;

procedure TConditionalSyntaxTests.ActiveBranchStillReportsErrors;
const
  Text = 'unit A;' + Crlf + 'interface' + Crlf + 'implementation' + Crlf + 'procedure P;' + Crlf + 'begin' + Crlf +
    '{$IFNDEF NIEMALS}' + Crlf + '  das ist kein Pascal ((' + Crlf + '{$ENDIF}' + Crlf + 'end;' + Crlf + 'end.';
begin
  Assert.IsTrue(Length(SyntaxErrors(Text, nil)) > 0);
end;

procedure TConditionalSyntaxTests.WithoutConditionalsUsesTree;
var
  Diagnostics: TArray<TSyntaxDiagnostic>;
begin
  Assert.IsFalse(TPascalParser.ActiveDiagnostics('unit A; interface implementation end.', nil, Diagnostics));
end;

end.
