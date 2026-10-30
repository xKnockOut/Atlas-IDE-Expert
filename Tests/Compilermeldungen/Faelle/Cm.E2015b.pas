unit Cm.E2015b;

// E2015 Operator not applicable to this operand type
// Erwartet: E2015
// div mit Gleitkommazahl (#1369).

interface

implementation

function Fall(AWert: Double): Double;
begin
  Result := AWert div 2; // <- E2015
end;

end.
