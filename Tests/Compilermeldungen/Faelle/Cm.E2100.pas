unit Cm.E2100;

// E2100 Data type too large: exceeds 2 GB
// Erwartet: E2100

interface

type
  TRiesig = array[0..MaxInt] of Int64; // <- E2100

implementation

end.
