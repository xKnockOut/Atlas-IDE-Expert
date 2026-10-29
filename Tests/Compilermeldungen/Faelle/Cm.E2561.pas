unit Cm.E2561;

// E2561 Specified options for $EXTERNALSYM and $NODEFINE are not allowed for '%s'
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).
// Vermutung zum Code.

interface

type
  TZahl = Integer;
  {$EXTERNALSYM TZahl 'a' 'b' 'c'} // <- ohne Meldung

implementation

end.
