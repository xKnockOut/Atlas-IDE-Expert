unit Cm.W1022;

// W1022 Comparison always evaluates to True
// Erwartet: W1022

interface

implementation

function Pruefe(AWert: Byte): Boolean;
begin
  Result := AWert >= 0; // <- W1022
end;

end.
