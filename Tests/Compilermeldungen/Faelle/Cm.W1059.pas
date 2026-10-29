{$WARN EXPLICIT_STRING_CAST ON}
unit Cm.W1059;

// W1059 Explicit string cast
// Erwartet: W1059

interface

implementation

function Breit(const AText: AnsiString): string;
begin
  Result := string(AText); // <- W1059
end;

end.
