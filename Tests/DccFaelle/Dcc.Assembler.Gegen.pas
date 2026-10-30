unit Dcc.Assembler.Gegen;

// #1375, Gegentest zu asm-invalid: Hier soll dcc in jeder markierten Zeile
// melden. AF1–AF12 meldet Atlas (erwarteter Code in der Marke), AF13–AF18
// sind Kandidaten, die Atlas noch nicht meldet; der dcc-Lauf entscheidet, ob
// die Regel sie aufnimmt. Nur Win32.

interface

implementation

{$IFDEF CPUX86}
procedure Gegen(AParam: Integer);
var
  mA, mB: Byte;
  mZahl: Integer;
begin
  asm
    add , ebx // AF1: E2105
    push eax,,ebx // AF2: E2105
    lea eax, [4 * esp] // AF3: E2105
    and ax, ecx // AF4: E2107
    cmp edx, dl // AF5: E2107
    xchg al, ebx // AF6: E2107
    db 1, mB // AF7: E2109
    mov eax, OFFSET Gegen + OFFSET Gegen // AF8: E2111
    mov eax, $10000000000000000 // AF9: E2113
    cmp ebx, 'ab''cd' // AF10: E2114
    mov eax, [ebx + 8 mod 0] // AF11: E2118
    mov eax, 7 mod $00 // AF12: E2118
    dd mZahl // AF13: Kandidat
    db AParam // AF14: Kandidat
    mov al, 'ab' // AF15: Kandidat
    mov eax, $100000000 // AF16: Kandidat
    cmp 5, eax // AF17: Kandidat
    db 1 / 0 // AF18: Kandidat
  end;
  mA := 0;
  mZahl := mA;
  if mZahl > 0 then
    Gegen(mZahl);
end;

initialization
  Gegen(0);
{$ENDIF}

end.
