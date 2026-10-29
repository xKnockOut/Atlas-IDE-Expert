unit Cm.W1034;

// W1034 $HPPEMIT ignored
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).
// Vermutung: $HPPEMIT im implementation-Teil.

interface

implementation

{$HPPEMIT '#include <Cm.h>'} // <- ohne Meldung

end.
