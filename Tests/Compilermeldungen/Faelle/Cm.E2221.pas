unit Cm.E2221;

// E2221 $WEAKPACKAGEUNIT '%s' cannot have initialization or finalization code
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).

{$WEAKPACKAGEUNIT ON}

interface

implementation

initialization // <- ohne Meldung

end.
