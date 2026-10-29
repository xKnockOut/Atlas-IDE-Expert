unit Cm.E2116;

// E2116 Invalid combination of opcode and operands
// Erwartet: E2116
// Plattform: Win32

interface

implementation

procedure Fall;
begin
  asm
    mov 5, eax // <- E2116
  end;
end;

end.
