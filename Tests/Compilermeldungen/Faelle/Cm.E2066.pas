unit Cm.E2066;

// E2066 Missing operator or semicolon
// Erwartet: E2066

interface

implementation

procedure Fall;
var
  mZahl: Integer;
begin
  mZahl := 1 mZahl := 2; // <- E2066
end;

end.
