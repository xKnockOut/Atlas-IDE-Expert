unit Cm.E2014b;

// E2014 Statement expected, but expression of type '%s' found
// Erwartet: E2014
// Zweiter Versuch: Ausdruck ohne Zuweisung.

interface

implementation

procedure Fall;
var
  mZahl: Integer;
begin
  mZahl := 1;
  mZahl + 1; // <- E2014
end;

end.
