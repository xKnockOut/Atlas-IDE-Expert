unit Cm.E2535;

// E2535 Interface methods must not have parameterized methods
// Erwartet: E2535

interface

type
  IEins = interface
    procedure Machen<T>; // <- E2535
  end;

implementation

end.
