unit Cm.E2107;

// E2107 Operand size mismatch
// Erwartet: E2107
// Plattform: Win32

interface

implementation

procedure Fall;
begin
  asm
    mov al, ebx // <- E2107
  end;
end;

end.
