unit Cm.E2148;

// E2148 Dynamic method or message handler not allowed here
// Erwartet: E2148
// Vermutung: dynamic im object-Typ.

interface

type
  TAltObjekt = object
    procedure Machen; dynamic; // <- E2148
  end;

implementation

procedure TAltObjekt.Machen;
begin
end;

end.
