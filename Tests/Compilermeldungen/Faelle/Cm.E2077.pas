unit Cm.E2077;

// E2077 Cannot return a value from a procedure
// Erwartet: E2025
// Delphi 13 meldet hier E2025 statt E2077.

interface

implementation

procedure Fall;
begin
  Exit(1); // <- E2025
end;

end.
