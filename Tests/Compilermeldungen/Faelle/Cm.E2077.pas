unit Cm.E2077;

// E2077 Cannot return a value from a procedure
// Erwartet: E2077

interface

implementation

procedure Fall;
begin
  Exit(1); // <- E2077
end;

end.
