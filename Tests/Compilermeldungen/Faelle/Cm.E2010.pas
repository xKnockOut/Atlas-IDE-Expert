unit Cm.E2010;

// E2010 Incompatible types: '%s' and '%s'
// Erwartet: E2010

interface

implementation

procedure Fall;
var
  mZahl: Integer;
begin
  mZahl := 'abc'; // <- E2010
end;

end.
