// Include-Datei für Ref.Daten.Auftraege (#500).
type
  /// <summary>Ein Auftrag mit Nummer und Betrag.</summary>
  TAuftrag = class
  private
    FNummer: Integer;
    FBetrag: Currency;
  public
    /// <summary>Betrag inklusive Mehrwertsteuer.</summary>
    function Brutto: Currency;
    property Nummer: Integer read FNummer write FNummer;
    property Betrag: Currency read FBetrag write FBetrag;
  end;

const
  /// <summary>Mehrwertsteuersatz in Prozent.</summary>
  Mehrwertsteuer = 19;