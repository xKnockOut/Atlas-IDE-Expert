unit Cm.W1048c;

// W1048 Unsafe typecast
// Erwartet: -
// Gegenfall zu Cm.W1048 (#1378): ohne {$WARN UNSAFE_CAST ON} schweigt dcc.

interface

implementation

function Umwandeln(AZeiger: Pointer): TObject;
begin
  Result := TObject(AZeiger); // <- ohne Meldung
end;

end.
