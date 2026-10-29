unit Cm.E2549;

// E2549 Cannot declare parameterized type derived from custom attribute class
// Erwartet: E2549

interface

type
  TMarkeAttribute<T> = class(TCustomAttribute) // <- E2549
  end;

implementation

end.
