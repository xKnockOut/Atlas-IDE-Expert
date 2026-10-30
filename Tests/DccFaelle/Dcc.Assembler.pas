unit Dcc.Assembler;

// #1375, Inline-Assembler, den dcc übersetzt: asm-invalid bleibt still.
// Nur Win32; Win64 kennt keine asm-Anweisung in einem Pascal-Block.

interface

implementation

{$IFDEF CPUX86}
type
  TPunkt = record
    X, Y: Integer;
  end;

const
  cWert = 5;

var
  Global: Integer;

procedure Sauber;
var
  mZahl: Integer;
begin
  asm
    mov eax, [esp + eax * 2] // AK1: esp als Basis
    mov eax, [esp + 8] // AK2
    movzx eax, al // AK3: Befehle mit verschieden großen Operanden
    movsx ecx, bx // AK4
    shl eax, cl // AK5
    mov ax, ds // AK6: Segmentregister
    mov al, byte ptr [eax] // AK7: Speicher statt Register
    mov al, ah // AK8
    lea eax, [ebx + 5] // AK9: Adresse statt Zahl
    out 5, al // AK10: Port als Zahl
    db cWert // AK11: Konstante
    db 1, 2, 'abc' // AK12
    mov eax, OFFSET Global // AK13
    mov eax, OFFSET Global + 4 // AK14
    mov eax, 'abcd' // AK15: vier Zeichen passen
    mov eax, 8 / 2 // AK16
    mov eax, [eax].TPunkt.Y // AK17
    mov eax, 0FFFFFFFFh // AK18: Hex mit Nachsilbe
    mov eax, mZahl // AK19: Variable als Operand
    mov eax, TYPE TPunkt // AK20
    test ecx, ecx // AK21
    jz @@Ende
    lock xadd [eax], ecx // AK22: Präfixe
    rep movsb // AK23
@@Ende:
    mov Global, eax
  end;
end;

// AK24: gemeinsames end zweier Zweige (wie in FastMM5); der Pascal-Zweig gehört nicht zum asm-Block.
procedure Zweige(A, B: Integer);
{$IFNDEF ATLAS_PASCAL}
asm
  mov eax, edx
{$ELSE}
var
  mZahl: Integer;
begin
  mZahl := A +
    B;
  Global := mZahl div 0;
{$ENDIF}
end;

initialization
  if Global < 0 then
  begin
    Sauber;
    Zweige(1, 2);
  end;
{$ENDIF}

end.
