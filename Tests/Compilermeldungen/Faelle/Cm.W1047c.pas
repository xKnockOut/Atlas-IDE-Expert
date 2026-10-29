unit Cm.W1047c;

// W1047 Unsafe code
// Erwartet: -
// Gegenfall zu Cm.W1047 (#1378): ohne {$WARN UNSAFE_CODE ON} schweigt dcc.

interface

implementation

function Adresse(var AWert: Integer): Pointer;
begin
  Result := @AWert; // <- ohne Meldung
end;

end.
