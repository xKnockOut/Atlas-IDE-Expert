unit Cm.E2054;

// E2054 Illegal type in Write/Writeln statement
// Erwartet: E2054

interface

implementation

procedure Fall;
var
  mObjekt: TObject;
begin
  mObjekt := nil;
  Writeln(ErrOutput, mObjekt); // <- E2054
end;

end.
