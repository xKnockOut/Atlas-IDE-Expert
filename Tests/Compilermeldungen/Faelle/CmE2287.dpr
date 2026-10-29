library CmE2287;

// E2287 Cannot export '%s' multiple times
// Erwartet: E2287

procedure Ziel;
begin
end;

exports
  Ziel,
  Ziel; // <- E2287

begin
end.
