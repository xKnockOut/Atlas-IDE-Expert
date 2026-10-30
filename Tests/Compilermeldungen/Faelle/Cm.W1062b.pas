unit Cm.W1062b;

// W1062 Narrowing given wide string constant lost information
// Erwartet: W1062
// Zweiter Versuch (#1377): ein einziges Literal (ohne +) mit einem Zeichen außerhalb der Codepage 1252.

interface

implementation

function Text: AnsiString;
begin
  Result := 'Schnee '#$2603; // <- W1062
end;

end.
