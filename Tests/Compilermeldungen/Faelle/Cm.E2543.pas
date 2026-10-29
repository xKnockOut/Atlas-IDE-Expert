unit Cm.E2543;

// E2543 Instantiated data type '%s' too large: exceeds 2 GB
// Erwartet: E2543

interface

type
  TBehaelter<T> = record
    Feld: array[0..MaxInt div 2] of T;
  end;

implementation

var
  GRiesig: TBehaelter<Int64>; // <- E2543

end.
