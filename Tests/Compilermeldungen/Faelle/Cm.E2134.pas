unit Cm.E2134;

// E2134 Type '%s' has no type info
// Erwartet: E2134

interface

implementation

type
  TLuecke = (luA = 1, luB = 5);

procedure Fall;
var
  mInfo: Pointer;
begin
  mInfo := TypeInfo(TLuecke); // <- E2134
end;

end.
