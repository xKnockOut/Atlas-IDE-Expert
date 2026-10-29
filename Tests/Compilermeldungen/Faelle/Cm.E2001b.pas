unit Cm.E2001b;

// E2001 Ordinal type required
// Erwartet: E2001
// Zweiter Versuch: case über eine Gleitkommazahl.

interface

implementation

procedure Fall;
var
  mWert: Double;
begin
  mWert := 1;
  case mWert of // <- E2001
    0: mWert := 2;
  end;
end;

end.
