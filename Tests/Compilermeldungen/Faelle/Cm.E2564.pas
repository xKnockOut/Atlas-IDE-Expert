unit Cm.E2564;

// E2564 Undefined type '%s'
// Erwartet: E2003
// Delphi 13 meldet hier E2003 statt E2564.

interface

type
  PGibtEsNicht = ^TGibtEsNicht; // <- E2003

implementation

end.
