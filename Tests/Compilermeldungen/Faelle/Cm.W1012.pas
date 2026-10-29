unit Cm.W1012;

// W1012 Constant expression violates subrange bounds
// Erwartet: W1012

interface

implementation

procedure Setzen;
var
  mWert: Byte;
begin
  mWert := 300; // <- W1012
  if mWert > 0 then
    Exit;
end;

end.
