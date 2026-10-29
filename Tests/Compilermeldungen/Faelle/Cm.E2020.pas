unit Cm.E2020;

// E2020 Object or class type required
// Erwartet: E2015
// Delphi 13 meldet hier E2015 statt E2020.
// Vermutung.

interface

implementation

procedure Fall;
var
  mObjekt: TObject;
begin
  mObjekt := nil;
  if mObjekt is Integer then // <- E2015
    Exit;
end;

end.
