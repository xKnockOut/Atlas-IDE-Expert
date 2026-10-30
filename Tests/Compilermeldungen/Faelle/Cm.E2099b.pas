unit Cm.E2099b;

// E2099 Overflow in conversion or arithmetic operation
// Erwartet: E2099
// #1372: Multiplikation über High(Int64) mit lauter Operanden mit Vorzeichen.

interface

const
  cDoppelt = High(Int64) * 2; // <- E2099

implementation

end.
