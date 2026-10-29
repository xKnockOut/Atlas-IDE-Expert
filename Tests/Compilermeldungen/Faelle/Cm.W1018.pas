unit Cm.W1018;

// W1018 Case label outside of range of case expression
// Erwartet: W1018

interface

implementation

function Bewerte(AWert: Byte): Integer;
begin
  case AWert of
    1: Result := 1;
    300: Result := 2; // <- W1018
  else
    Result := 0;
  end;
end;

end.
