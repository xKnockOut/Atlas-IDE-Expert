unit Cm.E2055;

// E2055 Illegal type in Read/Readln statement
// Erwartet: E2055

interface

implementation

procedure Fall;
var
  mObjekt: TObject;
begin
  Readln(mObjekt); // <- E2055
end;

end.
