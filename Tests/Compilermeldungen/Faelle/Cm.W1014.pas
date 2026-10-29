unit Cm.W1014;

// W1014 String constant truncated to fit STRING[%ld]
// Erwartet: W1014

interface

implementation

procedure Kuerzen;
var
  mKurz: string[3];
begin
  mKurz := 'abcdef'; // <- W1014
  if mKurz = '' then
    Exit;
end;

end.
