unit Cm.E2014;

// E2014 Statement expected, but expression of type '%s' found
// Erwartet: E2029
// Delphi 13 meldet hier E2029 statt E2014.

interface

implementation

procedure Fall;
var
  mZahl: Integer;
begin
  mZahl := 1;
  mZahl = 2; // <- E2029
end;

end.
