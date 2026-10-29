unit Cm.E2009;

// E2009 Incompatible types: '%s'
// Erwartet: E2009
// Parameterlisten verschieden.

interface

implementation

procedure Fall;
var
  mProzedur: procedure(AWert: Integer);
begin
  mProzedur := Fall; // <- E2009
end;

end.
