unit Cm.E2109;

// E2109 Constant expected
// Erwartet: E2109
// Plattform: Win32
// Vermutung.

interface

implementation

procedure Fall;
var
  mZahl: Integer;
begin
  asm
    db mZahl // <- E2109
  end;
end;

end.
