unit Cm.E2105;

// E2105 Inline assembler syntax error
// Erwartet: E2105
// Plattform: Win32

interface

implementation

procedure Fall;
begin
  asm
    mov eax, // <- E2105
  end;
end;

end.
