unit Cm.E2507;

// E2507 CLASS constraint and RECORD constraint cannot be specified together
// Erwartet: E2507

interface

type
  TBehaelter<T: class, record> = class // <- E2507
  end;

implementation

end.
