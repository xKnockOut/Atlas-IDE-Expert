unit Cm.E1012b;

// E1012 Constant expression violates subrange bounds
// Erwartet: E1012
// #1372: benannter Array-Typ, Konstante als Index, lesend; typisierte Konstante als Array.

interface

implementation

type
  TTabelle = array[1..3] of Integer;

const
  cLetzte = 4;
  cPrimzahlen: array[0..2] of Integer = (2, 3, 5);

function Summe: Integer;
var
  mTabelle: TTabelle;
begin
  mTabelle[1] := 0;
  Result := mTabelle[cLetzte]; // <- E1012
  Result := Result + cPrimzahlen[3]; // <- E1012
end;

end.
