unit Cm.E2143;

// E2143 Expression has no value
// Erwartet: E2143

interface

implementation

procedure Nichts;
begin
end;

procedure Fall;
var
  mZahl: Integer;
begin
  mZahl := Nichts; // <- E2143
end;

end.
