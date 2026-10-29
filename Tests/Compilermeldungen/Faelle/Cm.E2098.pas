unit Cm.E2098;

// E2098 Division by zero
// Erwartet: E2098

interface

const
  cNull = 1 div 0; // <- E2098

implementation

end.
