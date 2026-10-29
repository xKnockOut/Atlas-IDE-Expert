unit Cm.H2135;

// H2135 FOR or WHILE loop executes zero times - deleted
// Erwartet: H2135

interface

implementation

var
  GSumme: Integer;

procedure Schleife;
var
  mIndex: Integer;
begin
  for mIndex := 2 to 1 do // <- H2135
    GSumme := GSumme + mIndex;
end;

end.
