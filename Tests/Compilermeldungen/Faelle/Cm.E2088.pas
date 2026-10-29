unit Cm.E2088;

// E2088 Variable name expected
// Erwartet: E2088

interface

implementation

procedure Fall;
begin
  for := 0 to 2 do // <- E2088
    ;
end;

end.
