unit Cm.E2453;

// E2453 Destination cannot be assigned to
// Erwartet: E2064
// Delphi 13 meldet hier E2064 statt E2453.
// Vermutung zum Code.

interface

implementation

procedure Fall;
var
  mZahl: Integer;
begin
  mZahl := 1;
  Integer(5) := mZahl; // <- E2064
end;

end.
