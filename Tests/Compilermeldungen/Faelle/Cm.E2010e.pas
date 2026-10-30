unit Cm.E2010e;

// E2010 Incompatible types: '%s' and '%s'
// Erwartet: -
// Delphi 13 soll hier nichts melden.
// Gegenfall zu type-mismatch (#1369): verträgliche Zuweisungen, Argumente und Operatoren.

interface

implementation

const
  cTrenner = ',';

procedure Nimm(AWert: Double; const AText: string);
begin
end;

function Fall(AZahl: Integer; AZeichen: Char; const AText: string; APreis: Currency): string;
var
  mWert: Double;
  mZeiger: PChar;
  mZeichen: Char;
begin
  mWert := AZahl + APreis;
  mZeiger := 'abc';
  mZeichen := cTrenner;
  Nimm(AZahl, AZeichen);
  Nimm(mWert, mZeiger);
  Result := AText + AZeichen + mZeichen + string(mZeiger) + Chr(Ord(AText[1]) + 1); // <- ohne Meldung
end;

end.
