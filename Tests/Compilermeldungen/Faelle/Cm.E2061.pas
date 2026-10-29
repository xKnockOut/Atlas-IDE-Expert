unit Cm.E2061;

// E2061 Local class types not allowed
// Erwartet: E2061
// Vermutung zum Code: lokale Klasse.

interface

implementation

procedure Fall;
type
  TLokal = class // <- E2061
  end;
begin
end;

end.
