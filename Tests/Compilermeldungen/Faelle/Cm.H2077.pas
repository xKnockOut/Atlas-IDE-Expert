unit Cm.H2077;

// H2077 Value assigned to '%s' never used
// Erwartet: H2077

interface

implementation

function Liefere: Integer;
var
  mWert: Integer;
begin
  mWert := 1; // <- H2077
  mWert := 2;
  Result := mWert;
end;

end.
