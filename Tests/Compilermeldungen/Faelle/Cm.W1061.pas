unit Cm.W1061;

// W1061 Narrowing given WideChar constant to AnsiChar lost information
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).

interface

implementation

function Zeichen: AnsiChar;
begin
  Result := #$20AC; // <- ohne Meldung
end;

end.
