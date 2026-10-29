unit Cm.E2005;

// E2005 '%s' is not a type identifier
// Erwartet: E2029
// Delphi 13 meldet hier E2029 statt E2005.

interface

implementation

const
  cZahl = 1;

procedure Fall;
var
  mWert: cZahl; // <- E2029
begin
  mWert := 1;
end;

end.
