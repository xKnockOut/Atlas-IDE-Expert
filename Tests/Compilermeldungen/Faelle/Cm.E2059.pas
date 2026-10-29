unit Cm.E2059;

// E2059 Local class, interface or object types not allowed
// Erwartet: E2059
// Vermutung zum Code: lokales Interface.

interface

implementation

procedure Fall;
type
  ILokal = interface // <- E2059
  end;
begin
end;

end.
