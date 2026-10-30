unit Atlas.Common.Rules.Builtin.Assembler.Tests;

// Tests der Regel asm-invalid (#1375): je Code die Form aus dem Testprojekt
// Tests/Compilermeldungen (Cm.E2105 … Cm.E2118) und Gegenfälle, die dcc
// übersetzt; ganze asm-Routinen, Direktiven in der Anweisung, Dateien für
// Free Pascal, Abschalten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAsmInvalidTests = class
  public
    [Test]
    procedure MissingOperand;
    [Test]
    procedure ScaledEspIndex;
    [Test]
    procedure OperandSizeMismatch;
    [Test]
    procedure LeaWithNumber;
    [Test]
    procedure NumberAsMovTarget;
    [Test]
    procedure LocalVariableInDb;
    [Test]
    procedure RelocatableSymbolsAdded;
    [Test]
    procedure NumericOverflow;
    [Test]
    procedure StringConstantTooLong;
    [Test]
    procedure DivisionByZero;
    [Test]
    procedure ValidCodeIsSilent;
    [Test]
    procedure AsmRoutine;
    [Test]
    procedure UncertainStatementsAreSilent;
    [Test]
    procedure FreePascalFilesAreSilent;
    [Test]
    procedure OffAndGroup;
  end;

implementation

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Assembler,
  Atlas.Tests.RuleAssert;

/// <summary>Unit mit der Prozedur Fall: Deklarationen ADecls, asm-Block mit den Zeilen ABody.</summary>
function Source(const ADecls, ABody: string): string; overload;
begin
  Result := 'unit Cm;'#10'interface'#10'implementation'#10'procedure Fall;'#10 + ADecls + 'begin'#10'  asm'#10 +
    ABody + '  end;'#10'end;'#10'end.';
end;

function Source(const ABody: string): string; overload;
begin
  Result := Source('', ABody);
end;

function Findings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TAsmInvalidRule.Create, ASource);
end;

function Findings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TAsmInvalidRule.Create, ASource, AConfig, APath);
end;

/// <summary>Genau ein Befund mit der Meldung AMessage in Zeile ALine.</summary>
procedure ReportsOnce(const ASource, AMessage: string; ALine: Integer);
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(ASource);
  Assert.AreEqual(1, Integer(Length(mFound)), ASource);
  Assert.AreEqual(AsmInvalidRuleId, mFound[0].RuleId);
  Assert.AreEqual(AMessage, mFound[0].Message);
  Assert.AreEqual(ALine, mFound[0].Range.StartPos.Line);
end;

procedure Silent(const ABody: string); overload;
begin
  TRuleAssert.Silent(TAsmInvalidRule.Create, Source(ABody));
end;

{ TAsmInvalidTests }

procedure TAsmInvalidTests.MissingOperand;
var
  mFound: TArray<TRuleFinding>;
begin
  // Cm.E2105
  ReportsOnce(Source('    mov eax, // <- E2105'#10), 'Hinter mov fehlt ein Operand (wie E2105).', 6);
  mFound := Findings(Source('    mov eax,'#10));
  Assert.AreEqual(4, mFound[0].Range.StartPos.Character);
  Assert.AreEqual(12, mFound[0].Range.EndPos.Character);
  ReportsOnce(Source('    add , ebx'#10), 'Hinter add fehlt ein Operand (wie E2105).', 6);
  ReportsOnce(Source('    push eax,,ebx'#10), 'Hinter push fehlt ein Operand (wie E2105).', 6);
end;

procedure TAsmInvalidTests.ScaledEspIndex;
begin
  // Cm.E2112: dcc meldet E2105.
  ReportsOnce(Source('    mov eax, [eax + esp * 2]'#10), 'esp kann nicht Indexregister mit Faktor sein (wie E2105).', 6);
  ReportsOnce(Source('    lea eax, [4 * ESP]'#10), 'esp kann nicht Indexregister mit Faktor sein (wie E2105).', 6);
  // esp als Basis und mit Faktor 1 übersetzt dcc.
  Silent('    mov eax, [esp + eax * 2]'#10'    mov eax, [esp + 8]'#10'    lea eax, [esp * 1]'#10);
end;

procedure TAsmInvalidTests.OperandSizeMismatch;
begin
  // Cm.E2107
  ReportsOnce(Source('    mov al, ebx // <- E2107'#10),
    'Operandengröße stimmt nicht überein: al hat 1 Byte, ebx 4 Byte (wie E2107).', 6);
  ReportsOnce(Source('    and ax, ecx'#10), 'Operandengröße stimmt nicht überein: ax hat 2 Byte, ecx 4 Byte (wie E2107).',
    6);
  ReportsOnce(Source('    cmp EDX, DL'#10), 'Operandengröße stimmt nicht überein: EDX hat 4 Byte, DL 1 Byte (wie E2107).',
    6);
  // Befehle mit verschieden großen Operanden, Segmentregister, Speicher und Register von Win64 bleiben still.
  Silent('    movzx eax, al'#10'    movsx ecx, bx'#10'    shl eax, cl'#10'    in al, dx'#10'    out dx, al'#10 +
    '    mov ax, ds'#10'    mov al, byte ptr [eax]'#10'    mov eax, r8'#10'    mov al, ah'#10'    xchg ax, bx'#10);
end;

procedure TAsmInvalidTests.LeaWithNumber;
begin
  // Cm.E2108: dcc meldet E2107.
  ReportsOnce(Source('    lea eax, 5 // <- E2107'#10), 'lea braucht eine Speicheradresse, keine Zahl (wie E2107).', 6);
  Silent('    lea eax, [ebx + 5]'#10'    lea eax, [5]'#10'    mov eax, 5'#10);
end;

procedure TAsmInvalidTests.NumberAsMovTarget;
begin
  // Cm.E2116: dcc meldet E2107.
  ReportsOnce(Source('    mov 5, eax // <- E2107'#10), 'Eine Zahl kann nicht Ziel von mov sein (wie E2107).', 6);
  // out mit Port als Zahl ist gültig; [5] ist eine Speicheradresse.
  Silent('    out 5, al'#10'    mov [5], eax'#10'    enter 8, 0'#10);
end;

procedure TAsmInvalidTests.LocalVariableInDb;
begin
  // Cm.E2109
  ReportsOnce(Source('var'#10'  mZahl: Integer;'#10, '    db mZahl // <- E2109'#10),
    'mZahl ist eine lokale Variable; db braucht eine Konstante (wie E2109).', 8);
  ReportsOnce(Source('var'#10'  mA, mB: Byte;'#10, '    db 1, MB'#10),
    'MB ist eine lokale Variable; db braucht eine Konstante (wie E2109).', 8);
  // Konstanten, Zahlen, Strings, unbekannte Namen und Variablen außerhalb der Routine bleiben still.
  TRuleAssert.Silent(TAsmInvalidRule.Create, Source('const'#10'  cWert = 5;'#10'var'#10'  mZahl: Integer;'#10,
    '    db cWert'#10'    db 1, 2, ''abc'''#10'    db Global'#10'    dd mZahl'#10'    mov eax, mZahl'#10));
end;

procedure TAsmInvalidTests.RelocatableSymbolsAdded;
begin
  // Cm.E2111
  ReportsOnce(Source('    mov eax, OFFSET Fall + OFFSET Fall // <- E2111'#10),
    'Zwei relozierbare Adressen lassen sich nicht addieren (wie E2111).', 6);
  ReportsOnce(Source('    mov eax, offset TFoo.Bar + offset Fall'#10),
    'Zwei relozierbare Adressen lassen sich nicht addieren (wie E2111).', 6);
  Silent('    mov eax, OFFSET Fall'#10'    mov eax, OFFSET Fall + 4'#10'    mov eax, 4 + OFFSET Fall'#10);
end;

procedure TAsmInvalidTests.NumericOverflow;
begin
  // Cm.E2113
  ReportsOnce(Source('    mov eax, 99999999999999999999 // <- E2113'#10),
    'Die Zahl 99999999999999999999 passt nicht in 64 Bit (wie E2113).', 6);
  ReportsOnce(Source('    mov eax, $10000000000000000'#10),
    'Die Zahl $10000000000000000 passt nicht in 64 Bit (wie E2113).', 6);
  // Höchstwert, führende Nullen, Hex mit Nachsilbe h, Datenbefehle (dt nimmt Gleitkomma).
  Silent('    mov eax, 18446744073709551615'#10'    mov eax, $00000000000000000FF'#10 +
    '    mov eax, 0FFFFFFFFh'#10'    dt 99999999999999999999'#10);
end;

procedure TAsmInvalidTests.StringConstantTooLong;
begin
  // Cm.E2114
  ReportsOnce(Source('    mov eax, ''abcdefgh'' // <- E2114'#10),
    'Die Stringkonstante hat 8 Zeichen, eax fasst 4 (wie E2114).', 6);
  ReportsOnce(Source('    cmp ebx, ''ab''''cd'''#10), 'Die Stringkonstante hat 5 Zeichen, ebx fasst 4 (wie E2114).', 6);
  Silent('    mov eax, ''abcd'''#10'    db ''abcdefgh'''#10'    mov rax, ''abcdefgh'''#10);
end;

procedure TAsmInvalidTests.DivisionByZero;
begin
  // Cm.E2118
  ReportsOnce(Source('    mov eax, 1 / 0 // <- E2118'#10), 'Division durch null (wie E2118).', 6);
  ReportsOnce(Source('    mov eax, [ebx + 8 mod $00]'#10), 'Division durch null (wie E2118).', 6);
  // 0FFh ist kein null, 0.5 keine ganze Zahl.
  Silent('    mov eax, 8 / 2'#10'    mov eax, 8 / 0FFh'#10'    mov eax, 0 / 4'#10);
end;

procedure TAsmInvalidTests.ValidCodeIsSilent;
begin
  // Übliche Formen aus der RTL und aus Bibliotheken.
  Silent('    push ebx'#10'    mov ebx, eax'#10'    xor eax, eax'#10'    test ecx, ecx'#10'    jz @@Ende'#10 +
    '@@Schleife:'#10'    mov dl, [ebx + ecx - 1]'#10'    lock xadd [eax], ecx'#10'    rep movsb'#10 +
    '    mov eax, fs:[0]'#10'    call TObject.Free'#10'    mov eax, [eax].TPunkt.X'#10'    dec ecx; jnz @@Schleife'#10 +
    '@@Ende:'#10'    pop ebx'#10'    db $90, 0, 1'#10'    dd 0'#10'    mov eax, TYPE Integer'#10'    and al, 7'#10);
end;

procedure TAsmInvalidTests.AsmRoutine;
var
  mSource: string;
begin
  // Win64 kennt nur ganze asm-Routinen.
  mSource := 'unit Cm;'#10'interface'#10'implementation'#10'function Fall(A: Integer): Integer;'#10'asm'#10 +
    '  .noframe'#10'  mov eax, ecx'#10'  mov al, ecx'#10'end;'#10'end.';
  ReportsOnce(mSource, 'Operandengröße stimmt nicht überein: al hat 1 Byte, ecx 4 Byte (wie E2107).', 7);
end;

procedure TAsmInvalidTests.UncertainStatementsAreSilent;
begin
  Silent('    mov eax, {$IFDEF X} ebx {$ELSE} bl {$ENDIF}'#10'    mov al, {$I wert.inc}'#10);
  // ARM-Assembler von Free Pascal (mORMot2): { } ist dort eine Registerliste.
  Silent('    ldmea r11,{r11,r13,r15}'#10'    mov al, { Kommentar } ebx'#10);
  // In eigenen Zeilen zählen beide Zweige.
  ReportsOnce(Source('{$IFDEF CPUX86}'#10'    mov al, ebx'#10'{$ENDIF}'#10),
    'Operandengröße stimmt nicht überein: al hat 1 Byte, ebx 4 Byte (wie E2107).', 7);
  // Gemeinsames end zweier Zweige (FastMM5): Der Pascal-Zweig gehört nicht zum asm-Block.
  TRuleAssert.Silent(TAsmInvalidRule.Create, 'unit Cm;'#10'interface'#10'implementation'#10 +
    'procedure Fall(A, B: Integer);'#10'{$IFDEF X86ASM}'#10'asm'#10'  mov eax, edx'#10'{$ELSE}'#10'var'#10 +
    '  mZahl: Integer;'#10'begin'#10'  Weiter(A,'#10'    B);'#10'  mZahl := 1 div 0;'#10'{$ENDIF}'#10'end;'#10'end.');
  // Unvollständiger Block ohne end.
  TRuleAssert.Silent(TAsmInvalidRule.Create, 'unit Cm;'#10'interface'#10'implementation'#10'procedure Fall;'#10 +
    'begin'#10'  asm'#10'    mov al, ebx'#10);
end;

procedure TAsmInvalidTests.FreePascalFilesAreSilent;
begin
  TRuleAssert.Silent(TAsmInvalidRule.Create, '{$MODE DELPHI}'#10 + Source('    mov al, ebx'#10));
  TRuleAssert.Silent(TAsmInvalidRule.Create, '{$IFDEF FPC}{$ASMMODE INTEL}{$ENDIF}'#10 + Source('    mov al, ebx'#10));
end;

procedure TAsmInvalidTests.OffAndGroup;
var
  mSource: string;
begin
  mSource := Source('    mov al, ebx'#10);
  Assert.AreEqual(1, Integer(Length(Findings(mSource, '', 'Source/Cm.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(mSource, '{"rules": {"asm-invalid": "off"}}', 'Source/Cm.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(mSource, '{"rules": {"group:compiler": "off"}}', 'Source/Cm.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TAsmInvalidTests);

end.
