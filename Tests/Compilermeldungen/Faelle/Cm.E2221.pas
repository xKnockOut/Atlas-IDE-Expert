unit Cm.E2221;

// E2221 $WEAKPACKAGEUNIT '%s' cannot have initialization or finalization code
// Erwartet: E2221

{$WEAKPACKAGEUNIT ON}

interface

implementation

initialization // <- E2221

end.
