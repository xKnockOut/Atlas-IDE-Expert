unit Cm.W1061;

// W1061 Narrowing given WideChar constant to AnsiChar lost information
// Erwartet: W1061

interface

implementation

function Zeichen: AnsiChar;
begin
  Result := #$20AC; // <- W1061
end;

end.
