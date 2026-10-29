unit Cm.E2112;

// E2112 Invalid register combination
// Erwartet: E2112
// Plattform: Win32

interface

implementation

procedure Fall;
begin
  asm
    mov eax, [eax + esp * 2] // <- E2112
  end;
end;

end.
