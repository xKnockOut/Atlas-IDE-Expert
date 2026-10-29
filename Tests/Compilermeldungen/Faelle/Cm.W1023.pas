unit Cm.W1023;

// W1023 Comparing signed and unsigned types - widened both operands
// Erwartet: W1023

interface

implementation

function Pruefe(AZahl: Integer; AMenge: Cardinal): Boolean;
begin
  Result := AZahl < AMenge; // <- W1023
end;

end.
