unit Cm.E2072;

// E2072 Number of elements differs from declaration
// Erwartet: E2072

interface

const
  cFeld: array[0..2] of Integer = (1, 2); // <- E2072

implementation

end.
