unit Cm.W1025;

// W1025 Unsupported language feature
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).
// Plattform: Win64
// Vermutung: Real48 unter Win64.

interface

implementation

procedure Alt;
var
  mWert: Real48; // <- ohne Meldung
begin
  mWert := 1;
  if mWert > 0 then
    Exit;
end;

end.
