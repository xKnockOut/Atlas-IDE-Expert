{$WARN UNSAFE_CAST ON}
unit Cm.W1048;

// W1048 Unsafe typecast
// Erwartet: W1048

interface

implementation

function Umwandeln(AZeiger: Pointer): TObject;
begin
  Result := TObject(AZeiger); // <- W1048
end;

end.
