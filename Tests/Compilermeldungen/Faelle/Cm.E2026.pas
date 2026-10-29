unit Cm.E2026;

// E2026 Constant expression expected
// Erwartet: E2026

interface

var
  GGroesse: Integer;

type
  TFeld = array[0..GGroesse] of Integer; // <- E2026

implementation

end.
