unit Cm.E2412;

// E2412 CREATE expected
// Erwartet: E2029
// Delphi 13 meldet hier E2029 statt E2412.
// Vermutung zum Code.

interface

implementation

procedure Fall;
var
  mObjekt: TObject;
begin
  mObjekt := TObject.; // <- E2029
end;

end.
