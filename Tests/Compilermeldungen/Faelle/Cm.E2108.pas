unit Cm.E2108;

// E2108 Memory reference expected
// Erwartet: E2108
// Plattform: Win32

interface

implementation

procedure Fall;
begin
  asm
    lea eax, 5 // <- E2108
  end;
end;

end.
