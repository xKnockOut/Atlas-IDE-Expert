unit Cm.E2095;

// E2095 Missing ENDIF directive
// Erwartet: E2095

interface

{$IFDEF CM_NIE} // <- E2095

implementation

end.
