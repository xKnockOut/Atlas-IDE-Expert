unit Cm.E2016;

// E2016 Array type required
// Erwartet: E2016

interface

implementation

procedure Fall;
var
  mZahl: Integer;
begin
  mZahl[1] := 0; // <- E2016
end;

end.
