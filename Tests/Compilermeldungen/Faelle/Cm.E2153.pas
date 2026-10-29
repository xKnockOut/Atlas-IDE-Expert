unit Cm.E2153;

// E2153 ';' not allowed before 'ELSE'
// Erwartet: E2153

interface

implementation

procedure Fall;
var
  mZahl: Integer;
begin
  mZahl := 1;
  if mZahl > 0 then
    mZahl := 2;
  else // <- E2153
    mZahl := 3;
end;

end.
