{$WARN CVT_WIDENING_STRING_LOST ON}
unit Cm.W1064;

// W1064 Widening given AnsiString constant lost information
// Erwartet: W1064
// Vermutung.

interface

implementation

function Text: string;
begin
  Result := string(AnsiString(#$80#$81)); // <- W1064
end;

end.
