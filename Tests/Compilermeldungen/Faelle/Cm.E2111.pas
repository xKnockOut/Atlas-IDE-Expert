unit Cm.E2111;

// E2111 Cannot add or subtract relocatable symbols
// Erwartet: E2111
// Plattform: Win32

interface

implementation

procedure Fall;
begin
  asm
    mov eax, OFFSET Fall + OFFSET Fall // <- E2111
  end;
end;

end.
