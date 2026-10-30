unit Cm.W1071c;

// W1071 Implicit integer cast with potential data loss
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64, #1383). Geprüfte Vermutung: Konstante außerhalb des Zielbereichs
// über eine Int64-Variable.

{$WARN IMPLICIT_INTEGER_CAST_LOSS ON}

interface

implementation

function Kuerzen: Byte;
var
  mGross: Int64;
begin
  mGross := 300;
  Result := mGross; // <- ohne Meldung
end;

end.
