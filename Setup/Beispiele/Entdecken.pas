unit Entdecken;

// Beispiel zur Karte „Atlas entdecken“ (#757). „Ausprobieren“ setzt den
// Cursor an die passende Stelle; dann das angezeigte Tastenkürzel drücken:
//   Code-Aktionen       auf Rabatt in Gesamtpreis (unbekannter Name)
//   Auswahl erweitern   in Gesamtpreis, mehrmals hintereinander
//   Umbenennen          auf TKunde
//   Referenzen          auf Name
//   Implementierungen   auf IPreisliste.Preis
//   Aufrufer            auf Gesamtpreis
// Die Datei gehört zur Installation; Änderungen hier speichert man besser
// unter einem anderen Namen.

interface

type
  IPreisliste = interface
    function Preis(const AArtikel: string): Currency;
  end;

  TKunde = class
  private
    FName: string;
  public
    constructor Create(const AName: string);
    property Name: string read FName;
  end;

  TStandardpreise = class(TInterfacedObject, IPreisliste)
  public
    function Preis(const AArtikel: string): Currency;
  end;

function Gesamtpreis(AKunde: TKunde; const APreise: IPreisliste; const AArtikel: array of string): Currency;
function Beschriftung(AKunde: TKunde): string;

implementation

constructor TKunde.Create(const AName: string);
begin
  inherited Create;
  FName := AName;
end;

function TStandardpreise.Preis(const AArtikel: string): Currency;
begin
  Result := Length(AArtikel) * 1.5;
end;

function Gesamtpreis(AKunde: TKunde; const APreise: IPreisliste; const AArtikel: array of string): Currency;
var
  Artikel: string;
begin
  Result := 0;
  for Artikel in AArtikel do
    Result := Result + APreise.Preis(Artikel);
  Result := Result * (1 - Rabatt / 100);
end;

function Beschriftung(AKunde: TKunde): string;
begin
  Result := AKunde.Name + ': ' + CurrToStr(Gesamtpreis(AKunde, TStandardpreise.Create, ['Tee', 'Kaffee']));
end;

end.
