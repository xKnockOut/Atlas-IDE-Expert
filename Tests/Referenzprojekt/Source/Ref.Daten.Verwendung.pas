unit Ref.Daten.Verwendung;

// Nutzt Typen aus einer Include-Datei einer anderen Unit (#500):
// Strg+Klick auf TAuftrag springt nach Ref.Daten.Auftraege.inc.

interface

uses
  Ref.Daten.Auftraege;

function NeuerAuftrag(ANummer: Integer): TAuftrag; // ERWARTET-PROJEKT: unused-public-member

implementation

function NeuerAuftrag(ANummer: Integer): TAuftrag;
begin
  Result := TAuftrag.Create;
  Result.Nummer := ANummer;
  Result.Betrag := Mehrwertsteuer;
end;

end.