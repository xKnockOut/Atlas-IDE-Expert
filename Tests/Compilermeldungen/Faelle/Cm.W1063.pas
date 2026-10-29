{$WARN CVT_ACHAR_TO_WCHAR ON}
unit Cm.W1063;

// W1063 Widening given AnsiChar constant to WideChar lost information
// Erwartet: W1063
// Vermutung: Zeichen über 127 hängen von der Codepage ab.

interface

implementation

const
  cZeichen: AnsiChar = #$80;

function Zeichen: WideChar;
begin
  Result := WideChar(AnsiChar(#$80)); // <- W1063
end;

end.
