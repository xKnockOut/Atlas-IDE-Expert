unit Cm.E2005b;

// E2005 '%s' is not a type identifier
// Erwartet: E2005
// Zweiter Versuch: Routine als Typ.

interface

implementation

procedure Nichts;
begin
end;

procedure Fall;
var
  mWert: Nichts; // <- E2005
begin
end;

end.
