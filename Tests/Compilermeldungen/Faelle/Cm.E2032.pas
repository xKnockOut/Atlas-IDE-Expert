unit Cm.E2032;

// E2032 For loop control variable must have ordinal type
// Erwartet: E2032

interface

implementation

procedure Fall;
var
  mWert: Double;
begin
  for mWert := 0 to 2 do // <- E2032
    ;
end;

end.
