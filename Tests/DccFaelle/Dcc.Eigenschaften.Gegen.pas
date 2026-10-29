unit Dcc.Eigenschaften.Gegen;

// #1328, Gegentests zu property-accessor-invalid: Hier soll dcc melden.

interface

type
  TGegen = class
  private
    FZ: Integer;
    function GetZ: Integer;
    function GetQ(const AText: string): Integer; overload;
    function GetQ(AEins, AZwei: Integer): Integer; overload;
    class var FZaehler: Integer;
    class function GetZaehler: Integer; static;
  public
    class property KlasseZ: Integer read GetZ; // PG1: Klassen-Property mit Instanzmethode als Getter
    property Z: Integer index 3 read GetZ; // PG2: index-Angabe, der Getter hat keinen Indexparameter
    property Q: Integer read GetQ; // PG3: überladener Getter, keine Überladung passt
    property W: Integer read FW; // PG4: Feld, das es nicht gibt
    property Zaehler: Integer read FZaehler; // PG5: class var hinter read einer Instanz-Property
    property ZaehlerStatisch: Integer read GetZaehler; // PG6: statische Klassenmethode als Getter einer Instanz-Property
  end;

implementation

function TGegen.GetZ: Integer;
begin
  Result := FZ;
end;

class function TGegen.GetZaehler: Integer;
begin
  Result := FZaehler;
end;

function TGegen.GetQ(const AText: string): Integer;
begin
  Result := Length(AText);
end;

function TGegen.GetQ(AEins, AZwei: Integer): Integer;
begin
  Result := AEins + AZwei;
end;

end.
