unit Cm.E2560;

// E2560 $OBJTYPENAME not allowed for '%s'; only global and non-alias type symbol
// Erwartet: E2560

interface

type
  TZahl = Integer;
  {$OBJTYPENAME TZahl 'Bzahl'} // <- E2560

implementation

end.
