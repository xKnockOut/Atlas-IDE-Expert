unit Cm.E2005;

// E2005 '%s' is not a type identifier
// Erwartet: E2005

interface

implementation

const
  cZahl = 1;

procedure Fall;
var
  mWert: cZahl; // <- E2005
begin
  mWert := 1;
end;

end.
