unit Cm.W1005b;

// W1005 Unit is specific to a platform
// Erwartet: -
// Gegenfall zu Cm.W1005 (#1378): {$WARN UNIT_PLATFORM OFF} vor uses.

interface

implementation

{$WARN UNIT_PLATFORM OFF}
uses
  Cm.Hilfe.W1005; // <- ohne Meldung
{$WARN UNIT_PLATFORM DEFAULT}

end.
