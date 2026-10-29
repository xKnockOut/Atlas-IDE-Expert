unit Cm.E2453;

// E2453 Destination cannot be assigned to
// Erwartet: E2453
// Vermutung zum Code.

interface

implementation

procedure Fall;
var
  mZahl: Integer;
begin
  mZahl := 1;
  Integer(5) := mZahl; // <- E2453
end;

end.
