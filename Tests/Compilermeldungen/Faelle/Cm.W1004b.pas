unit Cm.W1004b;

// W1004 Unit is specific to a library
// Erwartet: -
// Gegenfall zu Cm.W1004 (#1378): {$WARN UNIT_LIBRARY OFF} vor uses.

interface

implementation

{$WARN UNIT_LIBRARY OFF}
uses
  Cm.Hilfe.W1004; // <- ohne Meldung
{$WARN UNIT_LIBRARY DEFAULT}

end.
