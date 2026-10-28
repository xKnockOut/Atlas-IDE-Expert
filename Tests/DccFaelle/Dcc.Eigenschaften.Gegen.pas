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
  public
    // PG1: Klassen-Property mit Instanzmethode als Getter
    class property KlasseZ: Integer read GetZ;
    // PG2: index-Angabe, der Getter hat keinen Indexparameter
    property Z: Integer index 3 read GetZ;
    // PG3: überladener Getter, keine Überladung passt
    property Q: Integer read GetQ;
    // PG4: Feld, das es nicht gibt
    property W: Integer read FW;
  end;

implementation

function TGegen.GetZ: Integer;
begin
  Result := FZ;
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
