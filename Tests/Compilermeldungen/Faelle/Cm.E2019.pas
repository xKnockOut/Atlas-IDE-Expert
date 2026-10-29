unit Cm.E2019;

// E2019 Object type required
// Erwartet: E2019
// Vermutung: object mit Klassenvorfahr.

interface

type
  TAltObjekt = object(TObject) // <- E2019
  end;

implementation

end.
