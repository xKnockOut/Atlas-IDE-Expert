unit Cm.W1058;

// W1058 Implicit string cast with potential data loss
// Erwartet: W1058

interface

implementation

function Schmal(const AText: string): AnsiString;
begin
  Result := AText; // <- W1058
end;

end.
