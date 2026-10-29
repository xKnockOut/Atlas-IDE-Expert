unit Cm.W1024;

// W1024 Combining signed and unsigned types - widened both operands
// Erwartet: W1024

interface

implementation

function Summe(AZahl: Integer; AMenge: Cardinal): Int64;
begin
  Result := AZahl + AMenge; // <- W1024
end;

end.
