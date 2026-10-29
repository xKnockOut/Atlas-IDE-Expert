unit Cm.E2088;

// E2088 Variable name expected
// Erwartet: E2029
// Delphi 13 meldet hier E2029 statt E2088.

interface

implementation

procedure Fall;
begin
  for := 0 to 2 do // <- E2029
    ;
end;

end.
