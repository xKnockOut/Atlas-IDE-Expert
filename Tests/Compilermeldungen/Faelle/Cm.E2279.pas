unit Cm.E2279;

// E2279 Too many nested conditional directives
// Erwartet: E2279
// Vermutung zum Code: $ENDIF ohne $IF.

interface

implementation

{$ENDIF} // <- E2279

end.
