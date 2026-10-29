unit Cm.E2537;

// E2537 DEFAULT standard function expects a type identifier
// Erwartet: E2537

interface

implementation

procedure Fall;
var
  mZahl: Integer;
begin
  mZahl := Default(mZahl); // <- E2537
end;

end.
