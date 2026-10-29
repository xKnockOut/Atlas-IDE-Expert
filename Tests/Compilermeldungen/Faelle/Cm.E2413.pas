unit Cm.E2413;

// E2413 Dynamic array type needed
// Erwartet: E2413
// Vermutung zum Code.

interface

implementation

procedure Fall;
var
  mFeld: array[0..2] of Integer;
begin
  mFeld := nil; // <- E2413
end;

end.
