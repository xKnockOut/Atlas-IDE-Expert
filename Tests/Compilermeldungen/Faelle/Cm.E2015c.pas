unit Cm.E2015c;

// E2015 Operator not applicable to this operand type
// Erwartet: E2015
// Boolean + Integer (#1369).

interface

implementation

function Fall(AFlag: Boolean): Integer;
begin
  Result := AFlag + 1; // <- E2015
end;

end.
