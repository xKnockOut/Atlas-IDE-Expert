unit Cm.E2114;

// E2114 String constant too long
// Erwartet: E2114
// Plattform: Win32

interface

implementation

procedure Fall;
begin
  asm
    mov eax, 'abcdefgh' // <- E2114
  end;
end;

end.
