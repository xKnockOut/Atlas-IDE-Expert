unit Cm.E2115;

// E2115 Error in numeric constant
// Erwartet: E2115
// Plattform: Win32
// Vermutung.

interface

implementation

procedure Fall;
begin
  asm
    mov eax, 1Gh // <- E2115
  end;
end;

end.
