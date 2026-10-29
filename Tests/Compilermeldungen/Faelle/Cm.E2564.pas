unit Cm.E2564;

// E2564 Undefined type '%s'
// Erwartet: E2564

interface

type
  PGibtEsNicht = ^TGibtEsNicht; // <- E2564

implementation

end.
