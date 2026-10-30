unit Atlas.Common.Pascal.AsmStatements.Tests;

// Tests der Zerlegung von asm-Blöcken (#1375): Zeilen und ";" als Grenzen,
// Operanden mit Klammern, fehlende Operanden, Sprungmarken, Präfixe,
// Win64-Direktiven, Kommentare, unsichere Anweisungen mit Direktiven und die
// Registertabelle.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAsmStatementsTests = class
  public
    [Test]
    procedure LinesAndSemicolons;
    [Test]
    procedure OperandsWithBrackets;
    [Test]
    procedure MissingOperand;
    [Test]
    procedure LabelsAndPrefixes;
    [Test]
    procedure Win64Directives;
    [Test]
    procedure CommentsDoNotCount;
    [Test]
    procedure DirectivesMakeStatementsUncertain;
    [Test]
    procedure OtherBranchesAreLeftOut;
    [Test]
    procedure Registers;
  end;

implementation

uses
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Pascal.AsmStatements;

/// <summary>Anweisungen des Textes AText (alle Token).</summary>
function Statements(const AText: string; out ATokens: TArray<TPascalToken>): TArray<TAsmStatement>; overload;
begin
  ATokens := TPascalLexer.Tokenize(AText);
  Result := TAsmStatements.Split(ATokens, 0, High(ATokens));
end;

function Statements(const AText: string): TArray<TAsmStatement>; overload;
var
  mTokens: TArray<TPascalToken>;
begin
  Result := Statements(AText, mTokens);
end;

/// <summary>Text des Operanden, Token mit Leerzeichen getrennt.</summary>
function OperandText(const ATokens: TArray<TPascalToken>; const AOperand: TAsmOperand): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex in AOperand.Tokens do
  begin
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + ATokens[mIndex].Text;
  end;
end;

{ TAsmStatementsTests }

procedure TAsmStatementsTests.LinesAndSemicolons;
var
  mFound: TArray<TAsmStatement>;
begin
  mFound := Statements('  mov eax, 1'#10'  add eax, ebx; ret'#10#10'  NOP'#10);
  Assert.AreEqual(4, Integer(Length(mFound)));
  Assert.AreEqual('mov', mFound[0].Mnemonic);
  Assert.AreEqual(2, Integer(Length(mFound[0].Operands)));
  Assert.AreEqual('add', mFound[1].Mnemonic);
  Assert.AreEqual('ret', mFound[2].Mnemonic);
  Assert.AreEqual(0, Integer(Length(mFound[2].Operands)));
  Assert.AreEqual('nop', mFound[3].Mnemonic);
  Assert.IsFalse(mFound[0].Uncertain);
end;

procedure TAsmStatementsTests.OperandsWithBrackets;
var
  mTokens: TArray<TPascalToken>;
  mFound: TArray<TAsmStatement>;
begin
  mFound := Statements('mov eax, dword ptr [ebx + ecx * 4 + 8]'#10'push (1 + 2)'#10'and eax, $FF', mTokens);
  Assert.AreEqual(3, Integer(Length(mFound)));
  Assert.AreEqual(2, Integer(Length(mFound[0].Operands)));
  Assert.AreEqual('eax', OperandText(mTokens, mFound[0].Operands[0]));
  Assert.AreEqual('dword ptr [ ebx + ecx * 4 + 8 ]', OperandText(mTokens, mFound[0].Operands[1]));
  Assert.AreEqual(1, Integer(Length(mFound[1].Operands)));
  // and ist für den Lexer ein reserviertes Wort, im asm-Block ein Befehl.
  Assert.AreEqual('and', mFound[2].Mnemonic);
  Assert.AreEqual('$FF', OperandText(mTokens, mFound[2].Operands[1]));
end;

procedure TAsmStatementsTests.MissingOperand;
var
  mFound: TArray<TAsmStatement>;
begin
  mFound := Statements('mov eax, // fehlt'#10'mov , ebx');
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual(2, Integer(Length(mFound[0].Operands)));
  Assert.AreEqual(0, Integer(Length(mFound[0].Operands[1].Tokens)));
  Assert.AreEqual(0, Integer(Length(mFound[1].Operands[0].Tokens)));
end;

procedure TAsmStatementsTests.LabelsAndPrefixes;
var
  mTokens: TArray<TPascalToken>;
  mFound: TArray<TAsmStatement>;
begin
  mFound := Statements('@@Schleife: dec ecx'#10'@Ende:'#10'Marke: lock xadd [eax], ecx'#10'rep movsb'#10 +
    '@@1: jnz @@Schleife', mTokens);
  Assert.AreEqual(5, Integer(Length(mFound)));
  Assert.AreEqual('dec', mFound[0].Mnemonic);
  Assert.AreEqual('dec', mTokens[mFound[0].FirstToken].Text);
  Assert.AreEqual('', mFound[1].Mnemonic);
  Assert.AreEqual(-1, mFound[1].MnemonicToken);
  Assert.AreEqual('xadd', mFound[2].Mnemonic);
  Assert.AreEqual('movsb', mFound[3].Mnemonic);
  Assert.AreEqual('jnz', mFound[4].Mnemonic);
  Assert.AreEqual('@ @ Schleife', OperandText(mTokens, mFound[4].Operands[0]));
end;

procedure TAsmStatementsTests.Win64Directives;
var
  mFound: TArray<TAsmStatement>;
begin
  mFound := Statements('.noframe'#10'.params 2'#10'mov rax, rcx');
  Assert.AreEqual(3, Integer(Length(mFound)));
  Assert.AreEqual('.noframe', mFound[0].Mnemonic);
  Assert.AreEqual('.params', mFound[1].Mnemonic);
  Assert.AreEqual(1, Integer(Length(mFound[1].Operands)));
end;

procedure TAsmStatementsTests.CommentsDoNotCount;
var
  mFound: TArray<TAsmStatement>;
begin
  mFound := Statements('{ Kopf }'#10'mov eax, ebx // Ende'#10'(* nur Kommentar *)'#10'ret { Ende }'#10 +
    'ldmea r11,{r11,r13,r15}');
  Assert.AreEqual(3, Integer(Length(mFound)));
  Assert.AreEqual(2, Integer(Length(mFound[0].Operands)));
  Assert.AreEqual(1, Integer(Length(mFound[0].Operands[1].Tokens)));
  Assert.IsFalse(mFound[0].Uncertain);
  // { } hinter dem Befehl: unsicher (ARM-Registerliste bei Free Pascal), auch am Zeilenende.
  Assert.IsTrue(mFound[1].Uncertain);
  Assert.IsTrue(mFound[2].Uncertain);
end;

procedure TAsmStatementsTests.DirectivesMakeStatementsUncertain;
var
  mFound: TArray<TAsmStatement>;
begin
  // Direktiven in eigenen Zeilen lassen die Anweisungen davor und danach sicher.
  mFound := Statements('{$IFDEF CPUX64}'#10'mov rax, rcx'#10'{$ELSE}'#10'mov eax, ecx'#10'{$ENDIF}');
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.IsFalse(mFound[0].Uncertain);
  Assert.IsFalse(mFound[1].Uncertain);
  // In derselben Zeile entscheidet erst der Präprozessor.
  mFound := Statements('mov eax, {$IFDEF X} ebx {$ELSE} ecx {$ENDIF}'#10'{$IFDEF X} ret {$ENDIF}'#10'nop');
  Assert.AreEqual(3, Integer(Length(mFound)));
  Assert.IsTrue(mFound[0].Uncertain);
  Assert.IsTrue(mFound[1].Uncertain);
  Assert.IsFalse(mFound[2].Uncertain);
  // Unbekannte Zeichen (AT&T-Schreibweise von Free Pascal) ebenso.
  mFound := Statements('movl %eax, %ebx');
  Assert.IsTrue(mFound[0].Uncertain);
end;

procedure TAsmStatementsTests.OtherBranchesAreLeftOut;
var
  mTokens: TArray<TPascalToken>;
  mFound: TArray<TAsmStatement>;
begin
  // {$IFDEF X} asm … {$ELSE} begin … {$ENDIF}: nur der asm-Zweig, verschachtelte Bedingungen im asm zählen.
  mTokens := TPascalLexer.Tokenize('{$IFDEF X}'#10'asm'#10'  mov eax,'#10'  {$IFDEF Y}'#10'  nop'#10'  {$ENDIF}'#10 +
    '{$ELSE}'#10'begin'#10'  Weiter(A,'#10'    B);'#10'{$ENDIF}'#10'end');
  mFound := TAsmStatements.Split(mTokens, TConditionalBranches.Paths(mTokens), 1, 2, High(mTokens) - 1);
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual('mov', mFound[0].Mnemonic);
  Assert.AreEqual('nop', mFound[1].Mnemonic);
  Assert.IsFalse(mFound[1].Uncertain);
end;

procedure TAsmStatementsTests.Registers;
begin
  Assert.AreEqual(1, TAsmStatements.RegisterSize('AL'));
  Assert.AreEqual(1, TAsmStatements.RegisterSize('dh'));
  Assert.AreEqual(2, TAsmStatements.RegisterSize('sp'));
  Assert.AreEqual(4, TAsmStatements.RegisterSize('Ebx'));
  Assert.AreEqual(0, TAsmStatements.RegisterSize('rax'));
  Assert.AreEqual(0, TAsmStatements.RegisterSize('r8d'));
  Assert.AreEqual(0, TAsmStatements.RegisterSize('ds'));
  Assert.AreEqual(0, TAsmStatements.RegisterSize('mZahl'));
  Assert.IsTrue(TAsmStatements.IsDataDirective('db'));
  Assert.IsTrue(TAsmStatements.IsDataDirective('dq'));
  Assert.IsFalse(TAsmStatements.IsDataDirective('mov'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAsmStatementsTests);

end.
