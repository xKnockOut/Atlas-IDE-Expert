unit Cm.E2222;

// E2222 $WEAKPACKAGEUNIT & $DENYPACKAGEUNIT both specified
// Erwartet: E2222

{$WEAKPACKAGEUNIT ON}
{$DENYPACKAGEUNIT ON} // <- E2222

interface

implementation

end.
