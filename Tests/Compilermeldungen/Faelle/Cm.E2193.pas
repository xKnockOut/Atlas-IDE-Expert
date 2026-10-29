unit Cm.E2193;

// E2193 Slice standard function only allowed as open array argument
// Erwartet: E2193

interface

implementation

procedure Fall;
var
  mQuelle: array[0..3] of Integer;
  mZiel: array of Integer;
begin
  mZiel := Slice(mQuelle, 2); // <- E2193
end;

end.
