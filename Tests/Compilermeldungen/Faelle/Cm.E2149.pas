unit Cm.E2149;

// E2149 Class does not have a default property
// Erwartet: E2149

interface

implementation

procedure Fall;
var
  mObjekt: TObject;
begin
  mObjekt := nil;
  mObjekt[0] := nil; // <- E2149
end;

end.
