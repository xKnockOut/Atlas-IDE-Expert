unit Cm.W1040;

// W1040 Implicit use of Variants unit
// Erwartet: W1040

interface

implementation

function Wert: Integer;
var
  mWert: Variant;
begin
  mWert := 1; // <- W1040
  Result := mWert;
end;

end.
