unit Cm.E2512;

// E2512 Type parameter '%s' must be a non-nullable value type
// Erwartet: E2512

interface

type
  TBehaelter<T: record> = class
  end;

implementation

var
  GBehaelter: TBehaelter<TObject>; // <- E2512

end.
