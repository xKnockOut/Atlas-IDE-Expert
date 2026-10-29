library CmE2287;

// E2287 Cannot export '%s' multiple times
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).

procedure Ziel;
begin
end;

exports
  Ziel,
  Ziel; // <- ohne Meldung

begin
end.
