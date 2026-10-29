unit Cm.E2514;

// E2514 Type parameter '%s' must support interface '%s'
// Erwartet: E2514

interface

type
  IEins = interface
  end;

  TBehaelter<T: IEins> = class
  end;

implementation

var
  GBehaelter: TBehaelter<IInterface>; // <- E2514

end.
