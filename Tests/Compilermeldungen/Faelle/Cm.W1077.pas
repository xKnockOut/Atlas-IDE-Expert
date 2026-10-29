{$WARN POINTER_INTEGER_CAST ON}
unit Cm.W1077;

// W1077 Typecasting between pointer and 32-bit integer types can cause problems on 64-bit targets
// Erwartet: W1077
// Plattform: Win32
// Name der $WARN-Option vermutet.

interface

implementation

function Kuerzen(AZeiger: Pointer): Integer;
begin
  Result := Integer(AZeiger); // <- W1077
end;

end.
