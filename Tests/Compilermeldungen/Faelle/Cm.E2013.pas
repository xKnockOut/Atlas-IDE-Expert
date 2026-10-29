unit Cm.E2013;

// E2013 Type of expression must be INTEGER
// Erwartet: E2013
// Vermutung.

interface

implementation

procedure Fall;
var
  mZahl: Integer;
begin
  mZahl := 1;
  Inc(mZahl, 1.5); // <- E2013
end;

end.
