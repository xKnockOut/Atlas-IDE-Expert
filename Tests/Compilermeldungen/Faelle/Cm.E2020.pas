unit Cm.E2020;

// E2020 Object or class type required
// Erwartet: E2020
// Vermutung.

interface

implementation

procedure Fall;
var
  mObjekt: TObject;
begin
  mObjekt := nil;
  if mObjekt is Integer then // <- E2020
    Exit;
end;

end.
