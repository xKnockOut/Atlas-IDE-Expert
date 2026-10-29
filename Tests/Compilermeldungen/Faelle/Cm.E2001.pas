unit Cm.E2001;

// E2001 Ordinal type required
// Erwartet: E2064
// Delphi 13 meldet hier E2064 statt E2001.

interface

implementation

procedure Fall;
var
  mWert: Double;
begin
  mWert := 1;
  Inc(mWert); // <- E2064
end;

end.
