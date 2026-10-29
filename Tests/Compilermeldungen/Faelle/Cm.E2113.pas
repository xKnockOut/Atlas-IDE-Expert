unit Cm.E2113;

// E2113 Numeric overflow
// Erwartet: E2113
// Plattform: Win32

interface

implementation

procedure Fall;
begin
  asm
    mov eax, 99999999999999999999 // <- E2113
  end;
end;

end.
