unit Cm.E2412;

// E2412 CREATE expected
// Erwartet: E2412
// Vermutung zum Code.

interface

implementation

procedure Fall;
var
  mObjekt: TObject;
begin
  mObjekt := TObject.; // <- E2412
end;

end.
