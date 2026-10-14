unit Ref.Daten.Kunden;

// FireDAC-Zugriffe für die Framework-Profile. Nur im optionalen Projekt
// RefDaten (#94); meldet beim Start die Kundensuche aus Ref.Daten.Suche an.

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
  private
    FVerbindung: TFDConnection;
    FAbfrage: TFDQuery;
  public
    constructor Create;
    destructor Destroy; override;
    class function Instanz: TKundenDaten;
    class destructor Aufraeumen;
    function Suchen(const AName: string): TDataSet;
    /// <summary>Namen der gefundenen Kunden, für TKundenSuche.</summary>
    function Namen(const AName: string): TArray<string>;
    procedure Speichern(AId: Integer; const AName: string);
  end;

implementation

uses
  FireDAC.Stan.Def,
  FireDAC.Stan.Async,
  FireDAC.DApt,
  FireDAC.Phys.SQLite,
  FireDAC.VCLUI.Wait,
  Ref.Daten.Suche;

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

function TKundenDaten.Namen(const AName: string): TArray<string>;
var
  Daten: TDataSet;
begin
  Result := nil;
  Daten := Suchen(AName);
  while not Daten.Eof do
  begin
    Result := Result + [Daten.FieldByName('Name').AsString];
    Daten.Next;
  end;
  Daten.Close;
end;

procedure TKundenDaten.Speichern(AId: Integer; const AName: string);
begin
  FVerbindung.ExecSQL('UPDATE Kunden SET Name = :Name WHERE Id = :Id', [AName, AId]);
end;

initialization
  TKundenSuche.Anmelden(
    function(AName: string): TArray<string>
    begin
      Result := TKundenDaten.Instanz.Namen(AName);
    end);

finalization
  TKundenSuche.Anmelden(nil);

end.
