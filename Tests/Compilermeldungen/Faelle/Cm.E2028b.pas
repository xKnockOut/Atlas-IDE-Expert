unit Cm.E2028b;

// E2028 Sets may have at most 256 elements
// Erwartet: E2028
// #1372: eingebauter Typ und benannter Teilbereich als Basis.

interface

type
  TBereich = 1..1000;
  TWorte = set of Word; // <- E2028
  TMenge = set of TBereich; // <- E2028

implementation

end.
