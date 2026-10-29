unit Cm.W1025;

// W1025 Unsupported language feature
// Erwartet: W1025
// Plattform: Win64
// Vermutung: Real48 unter Win64.

interface

implementation

procedure Alt;
var
  mWert: Real48; // <- W1025
begin
  mWert := 1;
  if mWert > 0 then
    Exit;
end;

end.
