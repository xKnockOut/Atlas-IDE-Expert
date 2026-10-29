unit Cm.W1040;

// W1040 Implicit use of Variants unit
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).

interface

implementation

function Wert: Integer;
var
  mWert: Variant;
begin
  mWert := 1; // <- ohne Meldung
  Result := mWert;
end;

end.
