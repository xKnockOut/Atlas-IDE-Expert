unit Cm.E2108;

// E2108 Memory reference expected
// Erwartet: E2107
// Delphi 13 meldet hier E2107 statt E2108.
// Plattform: Win32

interface

implementation

procedure Fall;
begin
  asm
    lea eax, 5 // <- E2107
  end;
end;

end.
