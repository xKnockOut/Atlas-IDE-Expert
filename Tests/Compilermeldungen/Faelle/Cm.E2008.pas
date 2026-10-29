unit Cm.E2008;

// E2008 Incompatible types
// Erwartet: E2008
// Vermutung: Menge aus Zahlen und Zeichen.

interface

implementation

procedure Fall;
var
  mMenge: set of Byte;
begin
  mMenge := [1] + ['a']; // <- E2008
end;

end.
