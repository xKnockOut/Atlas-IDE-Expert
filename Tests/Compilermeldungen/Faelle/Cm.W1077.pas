{$WARN POINTER_INTEGER_CAST ON}
unit Cm.W1077;

// W1077 Typecasting between pointer and 32-bit integer types can cause problems on 64-bit targets
// Erwartet: E1030
// Delphi 13 meldet hier E1030 statt W1077.
// Plattform: Win32
// Name der $WARN-Option vermutet.

interface

implementation

function Kuerzen(AZeiger: Pointer): Integer;
begin
  Result := Integer(AZeiger); // <- E1030
end;

end.
