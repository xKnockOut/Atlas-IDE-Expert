unit Cm.W1012b;

// W1012 Constant expression violates subrange bounds
// Erwartet: W1012
// #1372: Werte, die als gleich breite Zahl mit anderem Vorzeichen passen.

interface

implementation

procedure Setzen;
var
  mZahl: Integer;
  mWort: Cardinal;
begin
  mZahl := $FFFFFFFF; // <- W1012
  mWort := -1; // <- W1012
  if (mZahl > 0) and (mWort > 0) then
    Exit;
end;

end.
