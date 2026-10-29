unit Cm.E2419;

// E2419 Record type too large: exceeds 1 MB
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).
// Vermutung; die Grenze gilt vermutlich nur in bestimmten Fällen.

interface

type
  TRiesig = record
    Feld: array[0..2000000] of Byte; // <- ohne Meldung
  end;

implementation

end.
