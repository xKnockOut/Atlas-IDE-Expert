{$WARN IMPLICIT_INTEGER_CAST_LOSS ON}
unit Cm.W1071;

// W1071 Implicit integer cast with potential data loss
// Erwartet: W1071

interface

implementation

function Kuerzen(AWert: Int64): Integer;
begin
  Result := AWert; // <- W1071
end;

end.
