unit Cm.W1002b;

// W1002 Symbol is specific to a platform
// Erwartet: -
// Gegenfall zu Cm.W1002 (#1378): {$WARN SYMBOL_PLATFORM OFF} vor der Verwendung.

interface

implementation

procedure Alt; platform;
begin
end;

procedure Benutze;
begin
  {$WARN SYMBOL_PLATFORM OFF}
  Alt; // <- ohne Meldung
  {$WARN SYMBOL_PLATFORM DEFAULT}
end;

end.
