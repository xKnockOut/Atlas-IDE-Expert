unit Dcc.Sichtbarkeit.Gegen;

// #1328, Gegentests zu inaccessible-member: Hier soll dcc melden.

interface

uses
  Dcc.Sichtbarkeit.Basis;

function Wert(AObjekt: TEinfach): Integer;
function Anzahl(ABaum: TBaumBasis): Integer;

implementation

function Wert(AObjekt: TEinfach): Integer;
begin
  Result := AObjekt.FWert; // SG1: protected-Feld einer nicht generischen Klasse
end;

function Anzahl(ABaum: TBaumBasis): Integer;
begin
  Result := ABaum.FAnzahl; // SG2: protected-Feld, nicht generischer Code
end;

end.
