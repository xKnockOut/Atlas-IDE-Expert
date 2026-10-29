unit Cm.E2053;

// E2053 Syntax error in real number
// Erwartet: E2053

interface

implementation

procedure Fall;
var
  mWert: Double;
begin
  mWert := 1.5e; // <- E2053
end;

end.
