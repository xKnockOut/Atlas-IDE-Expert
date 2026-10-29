unit Cm.E2516;

// E2516 Constraint '%s' is conflicting with previous constraints
// Erwartet: E2516
// Vermutung zum Code.

interface

type
  TBehaelter<T: record, constructor> = class // <- E2516
  end;

implementation

end.
