unit Cm.E1012;

// E1012 Constant expression violates subrange bounds
// Erwartet: E1012

interface

implementation

procedure Fall;
var
  mFeld: array[0..2] of Integer;
begin
  mFeld[5] := 0; // <- E1012
end;

end.
