unit Cm.E2003;

// E2003 Undeclared identifier
// Erwartet: E2003

interface

implementation

procedure Fall;
var
  mZahl: Integer;
begin
  mZahl := GibtEsNicht; // <- E2003
end;

end.
