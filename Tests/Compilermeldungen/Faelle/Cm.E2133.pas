unit Cm.E2133;

// E2133 TYPEINFO standard function expects a type identifier
// Erwartet: E2133

interface

implementation

procedure Fall;
var
  mZahl: Integer;
  mInfo: Pointer;
begin
  mZahl := 1;
  mInfo := TypeInfo(mZahl); // <- E2133
end;

end.
