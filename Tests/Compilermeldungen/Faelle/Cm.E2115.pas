unit Cm.E2115;

// E2115 Error in numeric constant
// Erwartet: E2003
// Delphi 13 meldet hier E2003 statt E2115.
// Plattform: Win32
// Vermutung.

interface

implementation

procedure Fall;
begin
  asm
    mov eax, 1Gh // <- E2003
  end;
end;

end.
