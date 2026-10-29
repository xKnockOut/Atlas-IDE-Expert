library CmE2406;

// E2406 EXPORTS section allowed only if compiling with $UNSAFECODE ON
// Erwartet: W1002
// Delphi 13 meldet hier W1002 statt E2406.
// Vermutung; .NET.

{$UNSAFECODE OFF}

procedure Ziel;
begin
end;

exports
  Ziel; // <- W1002

begin
end.
