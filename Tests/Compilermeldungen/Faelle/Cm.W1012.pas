unit Cm.W1012;

// W1012 Constant expression violates subrange bounds
// Erwartet: E1012
// Delphi 13 meldet hier E1012 statt W1012.

interface

implementation

procedure Setzen;
var
  mWert: Byte;
begin
  mWert := 300; // <- E1012
  if mWert > 0 then
    Exit;
end;

end.
