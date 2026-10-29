unit Cm.E2058;

// E2058 Class, interface and object types only allowed in type section
// Erwartet: E2058
// Vermutung zum Code: object-Typ im var-Abschnitt.

interface

implementation

procedure Fall;
var
  mObjekt: object // <- E2058
    Wert: Integer;
  end;
begin

end;

end.
