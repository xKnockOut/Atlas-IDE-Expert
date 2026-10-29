unit Cm.E2018;

// E2018 Record, object or class type required
// Erwartet: E2018

interface

implementation

procedure Fall;
var
  mZahl: Integer;
begin
  mZahl.Wert := 0; // <- E2018
end;

end.
