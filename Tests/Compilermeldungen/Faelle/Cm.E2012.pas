unit Cm.E2012;

// E2012 Type of expression must be BOOLEAN
// Erwartet: E2012

interface

implementation

procedure Fall;
var
  mZahl: Integer;
begin
  mZahl := 1;
  if mZahl then // <- E2012
    mZahl := 2;
end;

end.
