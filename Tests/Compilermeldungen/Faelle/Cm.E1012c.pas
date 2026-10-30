unit Cm.E1012c;

// E1012 Constant expression violates subrange bounds
// Erwartet: E1012
// #1372: typisierte Konstante und Teilbereichstyp.

interface

type
  TProzent = 0..100;

const
  cGrenze: Byte = 300; // <- E1012

implementation

procedure Setzen;
var
  mAnteil: TProzent;
begin
  mAnteil := 150; // <- E1012
  if mAnteil > 0 then
    Exit;
end;

end.
