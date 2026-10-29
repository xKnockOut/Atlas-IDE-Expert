unit Cm.E2036;

// E2036 Variable required
// Erwartet: E2036

interface

implementation

procedure Fall;
var
  mZahl: Integer;
  mZeiger: Pointer;
begin
  mZahl := 1;
  mZeiger := @(mZahl + 1); // <- E2036
end;

end.
