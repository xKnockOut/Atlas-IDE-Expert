unit Cm.W1037;

// W1037 FOR-Loop variable may be undefined after loop
// Erwartet: W1037

interface

implementation

function Letzter: Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to 2 do
    ;
  Result := mIndex; // <- W1037
end;

end.
