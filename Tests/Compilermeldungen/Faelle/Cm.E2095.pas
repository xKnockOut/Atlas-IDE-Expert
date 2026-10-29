unit Cm.E2095;

// E2095 Missing ENDIF directive
// Erwartet: E2280
// Delphi 13 meldet hier E2280 statt E2095.

interface

{$IFDEF CM_NIE} // <- E2280

implementation

end.
