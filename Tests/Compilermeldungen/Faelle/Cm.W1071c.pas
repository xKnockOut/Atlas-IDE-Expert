unit Cm.W1071c;

// W1071 Implicit integer cast with potential data loss
// Erwartet: W1071
// Vermutung (#1383): Konstante außerhalb des Zielbereichs über eine Int64-Variable.

{$WARN IMPLICIT_INTEGER_CAST_LOSS ON}

interface

implementation

function Kuerzen: Byte;
var
  mGross: Int64;
begin
  mGross := 300;
  Result := mGross; // <- W1071
end;

end.
