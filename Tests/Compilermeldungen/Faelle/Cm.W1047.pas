{$WARN UNSAFE_CODE ON}
unit Cm.W1047;

// W1047 Unsafe code
// Erwartet: W1047

interface

implementation

function Adresse(var AWert: Integer): Pointer;
begin
  Result := @AWert; // <- W1047
end;

end.
