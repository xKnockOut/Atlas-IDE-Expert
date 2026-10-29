unit Cm.E2560b;

// E2560 $OBJTYPENAME not allowed for '%s'; only global and non-alias type symbol
// Erwartet: -
// Gegenfall zu Cm.E2560 (#1379): Mit "type" ist TZahl ein eigener Typ, kein
// Alias.

interface

type
  TZahl = type Integer;
  {$OBJTYPENAME TZahl 'Bzahl'} // <- ohne Meldung

implementation

end.
