unit Cm.E2118;

// E2118 Division by zero (Assembler)
// Erwartet: E2118
// Plattform: Win32

interface

implementation

procedure Fall;
begin
  asm
    mov eax, 1 / 0 // <- E2118
  end;
end;

end.
