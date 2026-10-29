unit Cm.E2028;

// E2028 Sets may have at most 256 elements
// Erwartet: E2028

interface

type
  TGrosseMenge = set of 0..300; // <- E2028

implementation

end.
