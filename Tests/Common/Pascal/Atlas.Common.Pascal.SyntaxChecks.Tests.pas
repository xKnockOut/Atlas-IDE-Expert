unit Atlas.Common.Pascal.SyntaxChecks.Tests;

// Syntaxfehler mit den Codes des Compilers (#1022): Meldungen des Parsers,
// Prüfungen am fertigen Baum (Pascal.SyntaxChecks) und die Korrekturen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSyntaxChecksTests = class
  public
    [Test]
    procedure SemicolonBeforeElseReportsE2153;
    [Test]
    procedure SemicolonBeforeElseFixParsesCleanly;
    [Test]
    procedure SemicolonBeforeCaseElseIsSilent;
    [Test]
    procedure SemicolonBeforeExceptElseIsSilent;
    [Test]
    procedure IfWithoutSemicolonBeforeElseIsSilent;
    [Test]
    procedure MissingSemicolonReportsE2066WithFix;
    [Test]
    procedure UnexpectedTokenUsesCompilerText;
    [Test]
    procedure UnexpectedEndOfFileUsesCompilerText;
    [Test]
    procedure UnterminatedStringReportsE2052Only;
    [Test]
    procedure UnterminatedCommentReportsE2057Only;
    [Test]
    procedure RealWithoutExponentReportsE2053;
    [Test]
    procedure AbsoluteAddressReportsE2088;
    [Test]
    procedure TrailingDotReportsE2372;
    [Test]
    procedure StatementsInInterfaceReportE2050;
    [Test]
    procedure StrictWithoutVisibilityReportsE2375;
    [Test]
    procedure ClassBeforeFieldReportsE2123;
    [Test]
    procedure ClassOperatorInClassReportsE2123;
    [Test]
    procedure TryWithoutHandlerReportsE2125;
    [Test]
    procedure ForWithoutVariableReportsE2088;
    [Test]
    procedure ProcedureWithResultTypeReportsE2025;
    [Test]
    procedure FunctionWithoutResultTypeReportsE2023;
    [Test]
    procedure ImplementationWithoutResultTypeIsSilent;
    [Test]
    procedure MissingParameterTypeReportsE2067;
    [Test]
    procedure UntypedVarParameterIsSilent;
    [Test]
    procedure LocalVariableInitReportsE2195;
    [Test]
    procedure GlobalVariableInitIsSilent;
    [Test]
    procedure MultipleVariablesInitReportE2196;
    [Test]
    procedure ClassTypeInVarReportsE2058;
    [Test]
    procedure LocalClassTypeReportsE2059;
    [Test]
    procedure LocalObjectTypeReportsE2059;
    [Test]
    procedure LocalRecordAndClassRefAreSilent;
    [Test]
    procedure LabelInInterfaceReportsE2049;
    [Test]
    procedure GotoUndeclaredLabelReportsE2031;
    [Test]
    procedure GotoDeclaredLabelIsSilent;
    [Test]
    procedure InactiveBranchIsSilent;
    [Test]
    procedure SyntaxFindingsCarryFix;
    [Test]
    procedure SyntaxFindingsRespectSeverityOff;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Checker;

function Lines(const ALines: array of string): string;
begin
  Result := string.Join(#13#10, ALines);
end;

function Diagnostics(const AText: string): TArray<TSyntaxDiagnostic>;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := mTree.Diagnostics;
  finally
    mTree.Free;
  end;
end;

/// <summary>Codes der Diagnosen in Reihenfolge, z. B. "E2153,E2029"; ohne Code "-".</summary>
function Codes(const AText: string): string;
var
  mDiagnostic: TSyntaxDiagnostic;
  mCode: string;
begin
  Result := '';
  for mDiagnostic in Diagnostics(AText) do
  begin
    mCode := mDiagnostic.Code;
    if mCode = '' then
    begin
      mCode := '-';
    end;
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + mCode;
  end;
end;

function ApplyEdits(const AText: string; const AEdits: TArray<TTextEdit>): string;
var
  mIndex: Integer;
  mEdit: TTextEdit;

  function OffsetOf(const APosition: TTextPosition): Integer;
  var
    mLine, mPosition: Integer;
  begin
    mPosition := 0;
    for mLine := 1 to APosition.Line do
    begin
      mPosition := Pos(#10, AText, mPosition + 1);
    end;
    Result := mPosition + APosition.Character;
  end;

begin
  Result := AText;
  for mIndex := High(AEdits) downto 0 do
  begin
    mEdit := AEdits[mIndex];
    Result := Copy(Result, 1, OffsetOf(mEdit.Range.StartPos)) + mEdit.NewText +
      Copy(Result, OffsetOf(mEdit.Range.EndPos) + 1, MaxInt);
  end;
end;

function InProgram(const ABody: array of string): string;
var
  mBody: TArray<string>;
  mIndex: Integer;
begin
  SetLength(mBody, Length(ABody));
  for mIndex := 0 to High(ABody) do
  begin
    mBody[mIndex] := ABody[mIndex];
  end;
  // Mit TArray beginnen: Ein Literal vorn läse Delphi als Menge (E2001).
  Result := Lines(TArray<string>.Create('program P;', 'var', '  A: Boolean;', '  B: Integer;', 'begin') + mBody +
    ['end.']);
end;

function InUnit(const AInterface, AImplementation: array of string): string;
var
  mText: TArray<string>;
  mIndex: Integer;
begin
  mText := ['unit U;', '', 'interface', ''];
  for mIndex := 0 to High(AInterface) do
  begin
    mText := mText + [AInterface[mIndex]];
  end;
  mText := mText + ['', 'implementation', ''];
  for mIndex := 0 to High(AImplementation) do
  begin
    mText := mText + [AImplementation[mIndex]];
  end;
  Result := Lines(mText + ['', 'end.']);
end;

{ TSyntaxChecksTests }

procedure TSyntaxChecksTests.SemicolonBeforeElseReportsE2153;
var
  mFound: TArray<TSyntaxDiagnostic>;
begin
  mFound := Diagnostics(InProgram(['  if A then', '    B := 1;', '  else', '    B := 2;']));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('E2153', mFound[0].Code);
  Assert.AreEqual(''';'' vor ''else'' ist nicht erlaubt (wie E2153).', mFound[0].Message);
  Assert.AreEqual(6, mFound[0].StartPos.Line);
  Assert.AreEqual(10, mFound[0].StartPos.Character);
  Assert.AreEqual(6, mFound[0].EndPos.Line);
  Assert.AreEqual(11, mFound[0].EndPos.Character);
  Assert.AreEqual(''';'' entfernen', mFound[0].FixTitle);
  Assert.IsTrue(mFound[0].FixSafe);
end;

procedure TSyntaxChecksTests.SemicolonBeforeElseFixParsesCleanly;
var
  mText, mFixed: string;
  mFound: TArray<TSyntaxDiagnostic>;
begin
  mText := InProgram(['  if A then', '    B := 1;', '  else', '    B := 2;']);
  mFound := Diagnostics(mText);
  Assert.AreEqual(1, Integer(Length(mFound)));
  mFixed := ApplyEdits(mText, mFound[0].FixEdits);
  Assert.AreEqual(InProgram(['  if A then', '    B := 1', '  else', '    B := 2;']), mFixed);
  Assert.AreEqual('', Codes(mFixed));
end;

procedure TSyntaxChecksTests.SemicolonBeforeCaseElseIsSilent;
begin
  // Das "; else" gehört zum case, nicht zum if.
  Assert.AreEqual('', Codes(InProgram(['  case B of', '    1: if A then B := 2;', '  else', '    B := 3;',
    '  end;'])));
end;

procedure TSyntaxChecksTests.SemicolonBeforeExceptElseIsSilent;
begin
  Assert.AreEqual('', Codes(InProgram(['  try', '    B := 1;', '  except', '    on E: Exception do',
    '      if A then B := 2;', '  else', '    B := 3;', '  end;'])));
end;

procedure TSyntaxChecksTests.IfWithoutSemicolonBeforeElseIsSilent;
begin
  Assert.AreEqual('', Codes(InProgram(['  if A then', '    B := 1', '  else', '    B := 2;',
    '  if A then', '  begin', '    B := 1;', '  end', '  else', '    B := 2;'])));
end;

procedure TSyntaxChecksTests.MissingSemicolonReportsE2066WithFix;
var
  mText: string;
  mFound: TArray<TSyntaxDiagnostic>;
begin
  mText := InProgram(['  B := 1', '  B := 2;']);
  mFound := Diagnostics(mText);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('E2066', mFound[0].Code);
  Assert.AreEqual(''';'' ergänzen', mFound[0].FixTitle);
  Assert.IsFalse(mFound[0].FixSafe);
  Assert.AreEqual(InProgram(['  B := 1;', '  B := 2;']), ApplyEdits(mText, mFound[0].FixEdits));
end;

procedure TSyntaxChecksTests.UnexpectedTokenUsesCompilerText;
var
  mFound: TArray<TSyntaxDiagnostic>;
begin
  // Zwischen Anweisungen fehlt ein Operator oder das Semikolon.
  mFound := Diagnostics(InProgram(['  B := 1 2;']));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('E2066', mFound[0].Code);
  Assert.AreEqual('Operator oder '';'' fehlt (wie E2066).', mFound[0].Message);
  // In Deklarationen der Text des Compilers.
  mFound := Diagnostics(InUnit(['var', '  I: Integer J: Integer;'], []));
  Assert.IsTrue(Length(mFound) > 0);
  Assert.AreEqual(''';'' erwartet, aber ''J'' gefunden (wie E2029).', mFound[0].Message);
end;

procedure TSyntaxChecksTests.UnexpectedEndOfFileUsesCompilerText;
var
  mFound: TArray<TSyntaxDiagnostic>;
begin
  mFound := Diagnostics(Lines(['unit U;', 'interface', 'implementation', 'end']));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('''.'' erwartet, aber Dateiende gefunden (wie E2029).', mFound[0].Message);
end;

procedure TSyntaxChecksTests.UnterminatedStringReportsE2052Only;
var
  mText: string;
  mFound: TArray<TSyntaxDiagnostic>;
begin
  mText := Lines(['program P;', 'var', '  S: string;', 'begin', '  S := ''abc;', 'end.']);
  mFound := Diagnostics(mText);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('E2052', mFound[0].Code);
  Assert.AreEqual('Unvollständiger String (wie E2052).', mFound[0].Message);
  Assert.AreEqual('String schließen', mFound[0].FixTitle);
  Assert.AreEqual('', Codes(ApplyEdits(mText, mFound[0].FixEdits)));
end;

procedure TSyntaxChecksTests.UnterminatedCommentReportsE2057Only;
var
  mText: string;
  mFound: TArray<TSyntaxDiagnostic>;
begin
  mText := InProgram(['  { offen', '  B := 1;']);
  mFound := Diagnostics(mText);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('E2057', mFound[0].Code);
  Assert.AreEqual('Unerwartetes Dateiende im Kommentar ab Zeile 6 (wie E2057).', mFound[0].Message);
  Assert.AreEqual('Kommentar in Zeile 6 schließen', mFound[0].FixTitle);
  Assert.AreEqual(InProgram(['  { offen}', '  B := 1;']), ApplyEdits(mText, mFound[0].FixEdits));
end;

procedure TSyntaxChecksTests.RealWithoutExponentReportsE2053;
var
  mFound: TArray<TSyntaxDiagnostic>;
  mTokens: TArray<TPascalToken>;
begin
  // Fall Cm.E2053 (#1382): nur E2053, kein ';' fehlt und kein Bezeichner e.
  mFound := Diagnostics(InProgram(['  B := 1.5e;']));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('E2053', mFound[0].Code);
  Assert.AreEqual('Syntaxfehler in Gleitkommazahl (wie E2053).', mFound[0].Message);
  Assert.AreEqual('', Codes(InProgram(['  B := Round(1.5e3 + 2E-1 + 3e+2);'])));
  // 1Eh (Hexadezimalzahl im asm-Block) bleibt Zahl und Bezeichner.
  mTokens := TPascalLexer.Tokenize('1Eh');
  Assert.AreEqual(2, Integer(Length(mTokens)));
  Assert.AreEqual('1', mTokens[0].Text);
  Assert.IsTrue(mTokens[0].Terminated);
end;

procedure TSyntaxChecksTests.AbsoluteAddressReportsE2088;
var
  mFound: TArray<TSyntaxDiagnostic>;
begin
  // Fall Cm.E2091 (#1382): Delphi 13 meldet E2088, nicht E2029 zum ':'.
  mFound := Diagnostics(InUnit(['var', '  GTastatur: Byte absolute $40:$17;'], []));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('E2088', mFound[0].Code);
  Assert.AreEqual('Variable erwartet, aber ''$40'' gefunden (wie E2088).', mFound[0].Message);
  Assert.AreEqual('', Codes(InUnit(['var', '  GWert: Integer;', '  GBytes: array[0..3] of Byte absolute GWert;'],
    [])));
end;

procedure TSyntaxChecksTests.TrailingDotReportsE2372;
begin
  Assert.AreEqual('E2372', Codes(InUnit(['uses', '  System.;'], [])));
end;

procedure TSyntaxChecksTests.StatementsInInterfaceReportE2050;
begin
  Assert.AreEqual('E2050', Codes(InUnit(['begin', '  Writeln;', 'end;'], [])));
end;

procedure TSyntaxChecksTests.StrictWithoutVisibilityReportsE2375;
begin
  Assert.AreEqual('E2375', Codes(InUnit(['type', '  TFoo = class', '  strict public', '    FWert: Integer;',
    '  end;'], [])));
end;

procedure TSyntaxChecksTests.ClassBeforeFieldReportsE2123;
var
  mFound: TArray<TSyntaxDiagnostic>;
begin
  // Delphi 13 meldet E2123 (Fall Cm.E2123, #1382).
  mFound := Diagnostics(InUnit(['type', '  TFoo = class', '    class FWert: Integer;', '  end;'], []));
  Assert.IsTrue(Length(mFound) > 0);
  Assert.AreEqual('E2123', mFound[0].Code);
  Assert.AreEqual('''procedure'', ''function'', ''property'' oder ''var'' erwartet, aber ''FWert'' gefunden ' +
    '(wie E2123).', mFound[0].Message);
end;

procedure TSyntaxChecksTests.ClassOperatorInClassReportsE2123;
var
  mFound: TArray<TSyntaxDiagnostic>;
begin
  // Operatoren gibt es nur in Records; in Klassen meldet Delphi 13 E2123 (Fall Cm.E2522, #1382).
  mFound := Diagnostics(InUnit(['type', '  TBasis = class', '  end;', '  TKind = class(TBasis)', '  public',
    '    class operator Implicit(A: TKind): TBasis;', '  end;'], []));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('E2123', mFound[0].Code);
  Assert.AreEqual('''procedure'', ''function'', ''property'' oder ''var'' erwartet, aber ''operator'' gefunden ' +
    '(wie E2123).', mFound[0].Message);
  Assert.AreEqual(9, mFound[0].StartPos.Line);
  Assert.AreEqual(10, mFound[0].StartPos.Character);
  // Im Record still.
  Assert.AreEqual('', Codes(InUnit(['type', '  TGeld = record', '    class operator Add(const A, B: TGeld): TGeld;',
    '  end;'], [])));
end;

procedure TSyntaxChecksTests.TryWithoutHandlerReportsE2125;
begin
  Assert.AreEqual('E2125', Codes(InProgram(['  try', '    B := 1;', '  end;'])));
end;

procedure TSyntaxChecksTests.ForWithoutVariableReportsE2088;
var
  mFound: TArray<TSyntaxDiagnostic>;
begin
  mFound := Diagnostics(InProgram(['  for := 1 to 3 do', '    B := 1;']));
  Assert.IsTrue(Length(mFound) > 0);
  Assert.AreEqual('E2088', mFound[0].Code);
end;

procedure TSyntaxChecksTests.ProcedureWithResultTypeReportsE2025;
var
  mFound: TArray<TSyntaxDiagnostic>;
begin
  mFound := Diagnostics(InUnit(['procedure Rechne: Integer;'], ['procedure Rechne: Integer;', 'begin', 'end;']));
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual('E2025', mFound[0].Code);
  Assert.AreEqual('Eine Prozedur kann keinen Ergebnistyp haben (wie E2025).', mFound[0].Message);
  Assert.AreEqual('E2025', mFound[1].Code);
end;

procedure TSyntaxChecksTests.FunctionWithoutResultTypeReportsE2023;
begin
  // interface-Deklaration, Methode in der Klasse und freie Routine ohne Deklaration.
  Assert.AreEqual('E2023', Codes(InUnit(['function Rechne;'], [])));
  Assert.AreEqual('E2023', Codes(InUnit(['type', '  TFoo = class', '    function Wert;', '  end;'], [])));
  Assert.AreEqual('E2023', Codes(InUnit([], ['function Lokal;', 'begin', 'end;'])));
end;

procedure TSyntaxChecksTests.ImplementationWithoutResultTypeIsSilent;
begin
  // Kurzform der Implementierung: Der Ergebnistyp steht an der Deklaration.
  Assert.AreEqual('', Codes(InUnit(['function Rechne: Integer;', 'type', '  TFoo = class',
    '    function Wert: Integer;', '  end;'], ['function Rechne;', 'begin', '  Result := 1;', 'end;', '',
    'function TFoo.Wert;', 'begin', '  Result := 2;', 'end;', '', 'function Vorab: Integer; forward;', '',
    'function Vorab;', 'begin', '  Result := 3;', 'end;'])));
end;

procedure TSyntaxChecksTests.MissingParameterTypeReportsE2067;
var
  mFound: TArray<TSyntaxDiagnostic>;
begin
  mFound := Diagnostics(InUnit(['procedure Rechne(A, B);'], []));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('E2067', mFound[0].Code);
  Assert.AreEqual('Parametertyp fehlt bei A, B (wie E2067).', mFound[0].Message);
end;

procedure TSyntaxChecksTests.UntypedVarParameterIsSilent;
begin
  Assert.AreEqual('', Codes(InUnit(['procedure Rechne(const A; var B; out C; A2: Integer);'], [])));
end;

procedure TSyntaxChecksTests.LocalVariableInitReportsE2195;
var
  mFound: TArray<TSyntaxDiagnostic>;
begin
  mFound := Diagnostics(InUnit([], ['procedure Rechne;', 'var', '  I: Integer = 0;', 'begin', 'end;']));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('E2195', mFound[0].Code);
  Assert.AreEqual(9, mFound[0].StartPos.Line);
  Assert.AreEqual(13, mFound[0].StartPos.Character);
end;

procedure TSyntaxChecksTests.GlobalVariableInitIsSilent;
begin
  Assert.AreEqual('', Codes(InUnit(['var', '  I: Integer = 0;', '  P: Pointer absolute I;'],
    ['var', '  J: Integer = 1;'])));
end;

procedure TSyntaxChecksTests.MultipleVariablesInitReportE2196;
begin
  Assert.AreEqual('E2196', Codes(InUnit(['var', '  I, J: Integer = 0;'], [])));
end;

procedure TSyntaxChecksTests.ClassTypeInVarReportsE2058;
begin
  // Delphi 13 meldet E2058 statt E2060, in einer Routine dazu E2059 am Namen (Fälle Cm.E2058, Cm.E2060, #1382).
  Assert.AreEqual('E2058', Codes(InUnit(['var', '  X: class', '  end;'], [])));
  Assert.AreEqual('E2058', Codes(InUnit(['var', '  X: interface', '  end;'], [])));
  Assert.AreEqual('E2059,E2058', Codes(InUnit([], ['procedure Rechne;', 'var', '  X: class', '  end;', 'begin',
    'end;'])));
  Assert.AreEqual('E2059,E2058', Codes(InUnit([], ['procedure Rechne;', 'var', '  X: object', '    Wert: Integer;',
    '  end;', 'begin', 'end;'])));
end;

procedure TSyntaxChecksTests.LocalClassTypeReportsE2059;
begin
  // Delphi 13 meldet E2059 statt E2061 (Fälle Cm.E2059, Cm.E2061, #1382).
  Assert.AreEqual('E2059', Codes(InUnit([], ['procedure Rechne;', 'type', '  TLokal = class', '  end;', 'begin',
    'end;'])));
  Assert.AreEqual('E2059', Codes(InUnit([], ['procedure Rechne;', 'type', '  ILokal = interface', '  end;',
    'begin', 'end;'])));
end;

procedure TSyntaxChecksTests.LocalObjectTypeReportsE2059;
begin
  Assert.AreEqual('E2059', Codes(InUnit([], ['procedure Rechne;', 'type', '  TLokal = object', '  end;', 'begin',
    'end;'])));
end;

procedure TSyntaxChecksTests.LocalRecordAndClassRefAreSilent;
begin
  Assert.AreEqual('', Codes(InUnit([], ['procedure Rechne;', 'type', '  TPunkt = record', '    X: Integer;',
    '  end;', '  TKlasse = class of TObject;', '  TListe = array of TPunkt;', 'begin', 'end;'])));
end;

procedure TSyntaxChecksTests.LabelInInterfaceReportsE2049;
begin
  Assert.AreEqual('E2049', Codes(InUnit(['label', '  Ende;'], [])));
end;

procedure TSyntaxChecksTests.GotoUndeclaredLabelReportsE2031;
var
  mFound: TArray<TSyntaxDiagnostic>;
begin
  mFound := Diagnostics(InUnit([], ['procedure Rechne;', 'begin', '  goto Ende;', 'end;']));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('E2031', mFound[0].Code);
  Assert.AreEqual('Marke erwartet: Ende ist nicht als label deklariert (wie E2031).', mFound[0].Message);
  Assert.AreEqual(9, mFound[0].StartPos.Line);
  Assert.AreEqual(7, mFound[0].StartPos.Character);
  // Prüfung am fertigen Baum: Regeln wie label-misuse dürfen dem Baum dort trauen.
  Assert.IsTrue(mFound[0].TreeIntact);
end;

procedure TSyntaxChecksTests.GotoDeclaredLabelIsSilent;
begin
  Assert.AreEqual('', Codes(InUnit([], ['procedure Rechne;', 'label', '  Ende, 10;', 'begin', '  goto Ende;',
    '  goto 010;', '  Ende:', '  10: ;', 'end;'])));
  // Marke der umgebenden Routine: das meldet label-misuse als E2093, nicht die Syntaxprüfung.
  Assert.AreEqual('', Codes(InUnit([], ['procedure Rechne;', 'label', '  Ende;', '  procedure Innen;', '  begin',
    '    goto Ende;', '  end;', 'begin', '  Innen;', 'Ende:', 'end;'])));
end;

procedure TSyntaxChecksTests.InactiveBranchIsSilent;
var
  mFound: TArray<TSyntaxDiagnostic>;
begin
  Assert.IsTrue(TPascalParser.ActiveDiagnostics(InUnit(['{$IFDEF NIE_DEFINIERT}', 'procedure Rechne: Integer;',
    '{$ENDIF}'], []), nil, mFound));
  Assert.AreEqual(0, Integer(Length(mFound)));
end;

procedure TSyntaxChecksTests.SyntaxFindingsCarryFix;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TFileChecker.SyntaxFindings(Diagnostics(InProgram(['  if A then B := 1;', '  else B := 2;'])),
    Default(TServerSettings));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(cSyntaxRuleId, mFindings[0].RuleId);
  Assert.AreEqual<TRuleSeverity>(TRuleSeverity.Error, mFindings[0].Severity);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual(''';'' entfernen', mFindings[0].Fixes[0].Title);
  Assert.IsTrue(mFindings[0].Fixes[0].Safe);
end;

procedure TSyntaxChecksTests.SyntaxFindingsRespectSeverityOff;
var
  mSettings: TServerSettings;
  mRule: TRuleSetting;
begin
  mSettings := Default(TServerSettings);
  mRule := Default(TRuleSetting);
  mRule.Id := cSyntaxRuleId;
  mRule.Severity := TRuleSeverity.Off;
  mSettings.Rules := [mRule];
  Assert.AreEqual(0, Integer(Length(TFileChecker.SyntaxFindings(Diagnostics(InProgram(['  B := 1 2;'])),
    mSettings))));
end;

initialization
  TDUnitX.RegisterTestFixture(TSyntaxChecksTests);

end.
