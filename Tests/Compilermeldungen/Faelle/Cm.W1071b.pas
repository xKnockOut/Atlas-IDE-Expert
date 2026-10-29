unit Cm.W1071b;

// W1071 Implicit integer cast with potential data loss
// Erwartet: W1071
// Vermutung (#1383): Schalter hinter "unit" und Zuweisung an eine lokale Variable (Cm.W1071: Schalter vor
// "unit", Zuweisung an Result, still).

{$WARN IMPLICIT_INTEGER_CAST_LOSS ON}

interface

implementation

function Kuerzen(AWert: Int64): Integer;
var
  mWert: Integer;
begin
  mWert := AWert; // <- W1071
  Result := mWert;
end;

end.
