unit Cm.E2603;

// E2603 Constraint '%s' cannot be specified more than once
// Erwartet: E2603

interface

type
  TBehaelter<T: class, class> = class // <- E2603
  end;

implementation

end.
