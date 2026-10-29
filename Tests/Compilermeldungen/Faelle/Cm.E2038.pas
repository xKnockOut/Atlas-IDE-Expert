unit Cm.E2038;

// E2038 Illegal character in input file
// Erwartet: E2038

interface

implementation

procedure Fall;
var
  mZahl: Integer;
begin
  mZahl := 1 ! 2; // <- E2038
end;

end.
