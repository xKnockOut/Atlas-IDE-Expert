unit Ref.Daten.Kunden;

// FireDAC-Zugriffe für die Framework-Profile.

interface

uses
  System.Classes,
  Data.DB,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param;

type
  TKundenDaten = class
  private
    class var FInstanz: TKundenDaten;
    FVerbindung: TFDConnection;
    FAbfrage: TFDQuery;
  public
    constructor Create;
    destructor Destroy; override;
    class function Instanz: TKundenDaten;
    class destructor Aufraeumen;
    function Suchen(const AName: string): TDataSet;
    procedure Speichern(AId: Integer; const AName: string);
  end;

implementation

constructor TKundenDaten.Create;
begin
  inherited Create;
  FVerbindung := TFDConnection.Create(nil);
  FVerbindung.DriverName := 'SQLite';
  FVerbindung.Params.Database := 'kunden.db';
  FAbfrage := TFDQuery.Create(nil);
  FAbfrage.Connection := FVerbindung;
end;

destructor TKundenDaten.Destroy;
begin
  FAbfrage.Free;
  FVerbindung.Free;
  inherited;
end;

class destructor TKundenDaten.Aufraeumen;
begin
  FInstanz.Free;
end;

class function TKundenDaten.Instanz: TKundenDaten;
begin
  if FInstanz = nil then
    FInstanz := TKundenDaten.Create;
  Result := FInstanz;
end;

function TKundenDaten.Suchen(const AName: string): TDataSet;
begin
  FAbfrage.SQL.Text := 'SELECT Id, Name FROM Kunden WHERE Name LIKE :Name';
  FAbfrage.ParamByName('Name').AsString := AName + '%';
  FAbfrage.Open;
  Result := FAbfrage;
end;

procedure TKundenDaten.Speichern(AId: Integer; const AName: string);
begin
  FVerbindung.ExecSQL('UPDATE Kunden SET Name = :Name WHERE Id = :Id', [AName, AId]);
end;

end.
