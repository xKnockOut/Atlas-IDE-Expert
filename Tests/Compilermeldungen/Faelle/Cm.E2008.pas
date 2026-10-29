unit Cm.E2008;

// E2008 Incompatible types
// Erwartet: E2010
// Delphi 13 meldet hier E2010 statt E2008.
// Vermutung: Menge aus Zahlen und Zeichen.

interface

implementation

procedure Fall;
var
  mMenge: set of Byte;
begin
  mMenge := [1] + ['a']; // <- E2010
end;

end.
