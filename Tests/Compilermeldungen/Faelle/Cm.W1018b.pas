unit Cm.W1018b;

// W1018 Case label outside of range of case expression
// Erwartet: W1018
// #1372: Marke, die als Zahl mit Vorzeichen in 8 Bit passt, und Bereich außerhalb.

interface

implementation

function Bewerte(AWert: Byte): Integer;
begin
  case AWert of
    1: Result := 1;
    -1: Result := 2; // <- W1018
    256..300: Result := 3; // <- W1018
  else
    Result := 0;
  end;
end;

end.
