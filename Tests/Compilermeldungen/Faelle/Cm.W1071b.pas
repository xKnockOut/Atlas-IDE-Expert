unit Cm.W1071b;

// W1071 Implicit integer cast with potential data loss
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64, #1383). Geprüfte Vermutung: Schalter hinter "unit" und Zuweisung an
// eine lokale Variable (Cm.W1071: Schalter vor
// "unit", Zuweisung an Result, still).

{$WARN IMPLICIT_INTEGER_CAST_LOSS ON}

interface

implementation

function Kuerzen(AWert: Int64): Integer;
var
  mWert: Integer;
begin
  mWert := AWert; // <- ohne Meldung
  Result := mWert;
end;

end.
