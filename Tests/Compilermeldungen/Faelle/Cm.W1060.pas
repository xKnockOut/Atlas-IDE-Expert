{$WARN EXPLICIT_STRING_CAST_LOSS ON}
unit Cm.W1060;

// W1060 Explicit string cast with potential data loss
// Erwartet: W1060

interface

implementation

function Schmal(const AText: string): AnsiString;
begin
  Result := AnsiString(AText); // <- W1060
end;

end.
