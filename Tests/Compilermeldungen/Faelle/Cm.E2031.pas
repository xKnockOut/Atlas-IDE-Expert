unit Cm.E2031;

// E2031 Label expected
// Erwartet: E2031

interface

implementation

procedure Fall;
var
  mZahl: Integer;
begin
  mZahl := 1;
  goto mZahl; // <- E2031
end;

end.
