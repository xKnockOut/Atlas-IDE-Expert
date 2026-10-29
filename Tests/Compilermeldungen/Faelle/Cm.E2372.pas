unit Cm.E2372;

// E2372 Identifier expected
// Erwartet: E2029
// Delphi 13 meldet hier E2029 statt E2372.

interface

implementation

procedure Fall;
var
  mObjekt: TObject;
begin
  mObjekt := nil;
  mObjekt. := nil; // <- E2029
end;

end.
