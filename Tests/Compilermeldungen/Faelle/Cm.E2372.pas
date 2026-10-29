unit Cm.E2372;

// E2372 Identifier expected
// Erwartet: E2372

interface

implementation

procedure Fall;
var
  mObjekt: TObject;
begin
  mObjekt := nil;
  mObjekt. := nil; // <- E2372
end;

end.
