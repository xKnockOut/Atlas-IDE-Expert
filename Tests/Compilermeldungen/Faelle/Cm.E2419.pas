unit Cm.E2419;

// E2419 Record type too large: exceeds 1 MB
// Erwartet: E2419
// Vermutung; die Grenze gilt vermutlich nur in bestimmten Fällen.

interface

type
  TRiesig = record
    Feld: array[0..2000000] of Byte; // <- E2419
  end;

implementation

end.
