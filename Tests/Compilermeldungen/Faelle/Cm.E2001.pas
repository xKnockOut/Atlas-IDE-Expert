unit Cm.E2001;

// E2001 Ordinal type required
// Erwartet: E2001

interface

implementation

procedure Fall;
var
  mWert: Double;
begin
  mWert := 1;
  Inc(mWert); // <- E2001
end;

end.
