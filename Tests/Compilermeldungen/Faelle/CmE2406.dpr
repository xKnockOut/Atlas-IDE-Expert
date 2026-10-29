library CmE2406;

// E2406 EXPORTS section allowed only if compiling with $UNSAFECODE ON
// Erwartet: E2406
// Vermutung; .NET.

{$UNSAFECODE OFF}

procedure Ziel;
begin
end;

exports
  Ziel; // <- E2406

begin
end.
