unit Cm.E2004;

// E2004 Identifier redeclared
// Erwartet: E2004

interface

implementation

procedure Fall;
var
  mZahl: Integer;
  mZahl: string; // <- E2004
begin
  mZahl := 1;
end;

end.
