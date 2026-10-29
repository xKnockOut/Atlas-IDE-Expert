unit Cm.W1057;

// W1057 Implicit string cast
// Erwartet: W1057

interface

implementation

function Breit(const AText: AnsiString): string;
begin
  Result := AText; // <- W1057
end;

end.
