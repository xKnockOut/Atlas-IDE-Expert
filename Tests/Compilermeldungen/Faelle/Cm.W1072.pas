{$WARN IMPLICIT_CONVERSION_LOSS ON}
unit Cm.W1072;

// W1072 Implicit conversion may lose significant digits
// Erwartet: W1072

interface

implementation

function Kuerzen(AWert: Int64): Single;
begin
  Result := AWert; // <- W1072
end;

end.
