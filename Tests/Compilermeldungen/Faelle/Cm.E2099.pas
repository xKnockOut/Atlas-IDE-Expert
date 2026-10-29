unit Cm.E2099;

// E2099 Overflow in conversion or arithmetic operation
// Erwartet: E2099

interface

const
  cGross = High(Int64) + 1; // <- E2099

implementation

end.
