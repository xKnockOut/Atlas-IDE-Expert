unit Cm.E2062;

// E2062 Virtual constructors are not allowed
// Erwartet: E2062

interface

type
  TAltObjekt = object
    constructor Init; virtual; // <- E2062
  end;

implementation

constructor TAltObjekt.Init;
begin
end;

end.
