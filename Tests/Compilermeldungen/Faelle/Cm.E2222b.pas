unit Cm.E2222b;

// E2222 $WEAKPACKAGEUNIT & $DENYPACKAGEUNIT both specified
// Erwartet: -
// Gegenfall zu Cm.E2222 (#1379): $WEAKPACKAGEUNIT ist wieder aus, bevor
// $DENYPACKAGEUNIT kommt.

{$WEAKPACKAGEUNIT ON}
{$WEAKPACKAGEUNIT OFF}
{$DENYPACKAGEUNIT ON} // <- ohne Meldung

interface

implementation

end.
