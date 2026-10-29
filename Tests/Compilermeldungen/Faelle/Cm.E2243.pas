unit Cm.E2243;

// E2243 Expression needs no Initialize/Finalize
// Erwartet: H2243
// Delphi 13 meldet hier H2243 statt E2243.

interface

implementation

procedure Fall;
var
  mZahl: Integer;
begin
  mZahl := 1;
  Finalize(mZahl); // <- H2243
end;

end.
