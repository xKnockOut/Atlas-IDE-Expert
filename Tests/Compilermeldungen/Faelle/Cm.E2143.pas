unit Cm.E2143;

// E2143 Expression has no value
// Erwartet: E2010
// Delphi 13 meldet hier E2010 statt E2143.

interface

implementation

procedure Nichts;
begin
end;

procedure Fall;
var
  mZahl: Integer;
begin
  mZahl := Nichts; // <- E2010
end;

end.
