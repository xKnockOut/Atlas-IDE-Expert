unit Cm.E2279;

// E2279 Too many nested conditional directives
// Erwartet: E1030
// Delphi 13 meldet hier E1030 statt E2279.
// Vermutung zum Code: $ENDIF ohne $IF.

interface

implementation

{$ENDIF} // <- E1030

end.
