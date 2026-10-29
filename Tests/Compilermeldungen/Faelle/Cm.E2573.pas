unit Cm.E2573;

// E2573 Illegal value for the ALIGN directive
// Erwartet: E1030
// Delphi 13 meldet hier E1030 statt E2573.

interface

{$ALIGN 3} // <- E1030

implementation

end.
