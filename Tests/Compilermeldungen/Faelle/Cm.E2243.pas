unit Cm.E2243;

// E2243 Expression needs no Initialize/Finalize
// Erwartet: E2243

interface

implementation

procedure Fall;
var
  mZahl: Integer;
begin
  mZahl := 1;
  Finalize(mZahl); // <- E2243
end;

end.
