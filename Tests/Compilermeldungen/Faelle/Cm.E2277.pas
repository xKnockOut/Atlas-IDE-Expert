unit Cm.E2277;

// E2277 Only external cdecl functions may use varargs
// Erwartet: E2277

interface

implementation

procedure Fall(AWert: Integer); cdecl; varargs; // <- E2277
begin
end;

end.
