unit Cm.W1021;

// W1021 Comparison always evaluates to False
// Erwartet: W1021

interface

implementation

function Pruefe(AWert: Byte): Boolean;
begin
  Result := AWert < 0; // <- W1021
end;

end.
