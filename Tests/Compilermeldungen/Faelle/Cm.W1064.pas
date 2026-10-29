{$WARN CVT_WIDENING_STRING_LOST ON}
unit Cm.W1064;

// W1064 Widening given AnsiString constant lost information
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).
// Vermutung.

interface

implementation

function Text: string;
begin
  Result := string(AnsiString(#$80#$81)); // <- ohne Meldung
end;

end.
