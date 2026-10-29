unit Cm.E2513;

// E2513 Type parameter '%s' must have one public parameterless constructor named Create
// Erwartet: E2513

interface

type
  TOhneCreate = class abstract
  end;

  TBehaelter<T: constructor> = class
  end;

implementation

var
  GBehaelter: TBehaelter<IInterface>; // <- E2513

end.
