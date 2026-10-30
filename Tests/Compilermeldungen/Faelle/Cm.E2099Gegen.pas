unit Cm.E2099Gegen;

// E2099 Overflow in conversion or arithmetic operation
// Erwartet: -
// #1372: Gegenfall: Mit einem UInt64-Operanden rechnet Delphi bis High(UInt64).

interface

const
  cDarueber = UInt64(High(Int64)) + 1;
  cGrenze = High(Int64);
  cRand = High(Int64) - 1 + 1;

implementation

end.
