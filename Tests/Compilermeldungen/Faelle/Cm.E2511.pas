unit Cm.E2511;

// E2511 Type parameter '%s' must be a class type
// Erwartet: E2511

interface

type
  TBehaelter<T: class> = class
  end;

implementation

var
  GBehaelter: TBehaelter<Integer>; // <- E2511

end.
