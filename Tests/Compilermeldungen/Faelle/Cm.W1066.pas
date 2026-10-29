unit Cm.W1066;

// W1066 Lost Extended floating point precision. Reduced to Double
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).
// Plattform: Win64
// Unter Win64 ist Extended gleich Double.

interface

implementation

const
  cGenau: Extended = 1.18973149535723176502E+4932; // <- ohne Meldung

end.
