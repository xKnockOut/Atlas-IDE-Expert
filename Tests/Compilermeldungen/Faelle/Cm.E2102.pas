unit Cm.E2102;

// E2102 Integer constant too large
// Erwartet: E2102

interface

implementation

procedure Fall;
var
  mZahl: Int64;
begin
  mZahl := $1FFFFFFFFFFFFFFFF; // <- E2102
end;

end.
