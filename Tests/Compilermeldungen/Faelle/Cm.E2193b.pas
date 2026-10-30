unit Cm.E2193b;

// E2193 Slice standard function only allowed as open array argument
// Erwartet: E2193
// Gegenprobe zu type-kind-required (#1370): Slice an einen Parameter vom Typ Integer.

interface

implementation

procedure Zahl(AWert: Integer);
begin
end;

procedure Fall;
var
  mQuelle: array[0..3] of Integer;
begin
  mQuelle[0] := 1;
  Zahl(Slice(mQuelle, 2)); // <- E2193
end;

end.
