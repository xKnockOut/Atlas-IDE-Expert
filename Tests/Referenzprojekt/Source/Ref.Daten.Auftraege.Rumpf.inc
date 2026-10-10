// Methodenrümpfe für Ref.Daten.Auftraege (#500).

function TAuftrag.Brutto: Currency;
begin
  Result := FBetrag * (100 + Mehrwertsteuer) / 100;
end;