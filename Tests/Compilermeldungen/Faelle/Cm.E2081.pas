unit Cm.E2081;

// E2081 Assignment to FOR-Loop variable
// Erwartet: E2081

interface

implementation

procedure Fall;
var
  mIndex: Integer;
begin
  for mIndex := 0 to 2 do
    mIndex := 5; // <- E2081
end;

end.
