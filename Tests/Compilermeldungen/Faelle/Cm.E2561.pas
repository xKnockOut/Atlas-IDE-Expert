unit Cm.E2561;

// E2561 Specified options for $EXTERNALSYM and $NODEFINE are not allowed for '%s'
// Erwartet: E2561
// Vermutung zum Code.

interface

type
  TZahl = Integer;
  {$EXTERNALSYM TZahl 'a' 'b' 'c'} // <- E2561

implementation

end.
