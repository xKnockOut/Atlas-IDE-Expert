unit Cm.W1073;

// W1073 Combining signed type and unsigned 64-bit type - treated as an unsigned type
// Erwartet: W1073

interface

implementation

function Summe(AZahl: Int64; AMenge: UInt64): UInt64;
begin
  Result := AZahl + AMenge; // <- W1073
end;

end.
