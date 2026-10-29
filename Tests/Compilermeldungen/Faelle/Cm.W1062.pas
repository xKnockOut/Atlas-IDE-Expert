unit Cm.W1062;

// W1062 Narrowing given wide string constant lost information
// Erwartet: W1062

interface

implementation

function Text: AnsiString;
begin
  Result := 'Preis ' + #$20AC#$2603; // <- W1062
end;

end.
