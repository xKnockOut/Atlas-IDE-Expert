unit Cm.E2015d;

// E2015 Operator not applicable to this operand type
// Erwartet: E2015
// not auf einem String (#1369).

interface

implementation

function Fall(const AText: string): Boolean;
begin
  Result := not AText; // <- E2015
end;

end.
