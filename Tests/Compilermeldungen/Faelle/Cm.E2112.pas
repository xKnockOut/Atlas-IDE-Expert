unit Cm.E2112;

// E2112 Invalid register combination
// Erwartet: E2105
// Delphi 13 meldet hier E2105 statt E2112.
// Plattform: Win32

interface

implementation

procedure Fall;
begin
  asm
    mov eax, [eax + esp * 2] // <- E2105
  end;
end;

end.
