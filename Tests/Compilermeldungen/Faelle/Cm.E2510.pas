unit Cm.E2510;

// E2510 Type '%s' is not a valid constraint
// Erwartet: E2510

interface

type
  TBehaelter<T: Integer> = class // <- E2510
  end;

implementation

end.
