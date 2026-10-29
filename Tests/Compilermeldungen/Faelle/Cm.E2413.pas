unit Cm.E2413;

// E2413 Dynamic array type needed
// Erwartet: E2010
// Delphi 13 meldet hier E2010 statt E2413.
// Vermutung zum Code.

interface

implementation

procedure Fall;
var
  mFeld: array[0..2] of Integer;
begin
  mFeld := nil; // <- E2010
end;

end.
