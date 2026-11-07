unit Atlas.Core.Status.IndexStore;

// Letzter Index-Stand (#754), ohne VCL und Open Tools API: Läuft der Server
// nicht, zeigen die Zeile „Index“ des Statusfelds (#591) und damit die
// Zustandskachel der Willkommensseite die gespeicherten Werte mit
// „Stand vom …“ statt nichts.
// - TAtlasIndexSnapshot: Units im Index, Ende der letzten vollständigen
//   Indizierung und Zeitpunkt, zu dem die Werte zuletzt galten (Ortszeit mit
//   Zeitzone). Als JSON in %LOCALAPPDATA%\Atlas\index-state.json:
//   {"format": 1, "units": 1284, "fullIndexAt": "…", "at": "…"}.
//   Die Datei gehört nur dem Plugin; sie hält keinen Pfad und keinen Namen.
//   Geschrieben wird atomar über TAtlasDataFile (Bericht N3); eine
//   unbrauchbare Datei wird nicht beiseitegelegt: Sie hält nur einen Stand,
//   den der nächste laufende Server neu liefert.
// - TAtlasIndexTracker: verfolgt bei laufendem Server, was das Statusfeld
//   ohnehin abfragt (Fortschritt aus $/progress, Units aus atlas.server.status
//   alle 5 s). Endet eine Indizierung, gilt das als vollständige Indizierung.
//   Units während der Indizierung zählen nicht (Zwischenstand). Gespeichert
//   wird nur bei einer Änderung (Units, vollständige Indizierung) und wenn
//   der Server aufhört zu laufen; die Zeile selbst braucht keinen Zeitgeber.

interface

uses
  System.SysUtils,
  Atlas.Core.Status.Lines;

type
  TAtlasIndexSnapshot = record
  public const
    FormatVersion = 1;
  public
    /// <summary>Units im Index; -1 = unbekannt.</summary>
    Units: Integer;
    /// <summary>Ende der letzten vollständigen Indizierung; 0 = unbekannt.</summary>
    FullAt: TDateTime;
    /// <summary>Zuletzt bestätigt (Server lief, Units bekannt); 0 = nie.</summary>
    At: TDateTime;
    class function Empty: TAtlasIndexSnapshot; static;
    /// <summary>Units und Stand bekannt.</summary>
    function Known: Boolean;
    function ToJson: string;
    /// <summary>Ungültiger Text oder falsches Format: Empty.</summary>
    class function FromJson(const AText: string): TAtlasIndexSnapshot; static;
    class function Same(const ALeft, ARight: TAtlasIndexSnapshot): Boolean; static;
  end;

  TAtlasIndexTracker = class
  private
    FSnapshot: TAtlasIndexSnapshot;
    FWasIndexing: Boolean;
    FWasRunning: Boolean;
  public
    /// <summary>AStored: gespeicherter Stand (z. B. aus der Datei) oder Empty.</summary>
    constructor Create(const AStored: TAtlasIndexSnapshot);
    /// <summary>Neuer Stand des Statusfelds; True, wenn Snapshot gespeichert werden soll. AUnits -1 = unbekannt.</summary>
    function Observe(ARunning, AIndexing: Boolean; AUnits: Integer; ANow: TDateTime): Boolean;
    /// <summary>Daten der Zeile „Index“: bei laufendem Server die aktuellen Werte mit FullAt, sonst die
    /// gespeicherten (Offline).</summary>
    function Info(ARunning, AIndexing: Boolean; APercent, AUnits: Integer): TAtlasIndexInfo;
    property Snapshot: TAtlasIndexSnapshot read FSnapshot;
  end;

  TAtlasIndexStore = class
  public const
    FileName = 'index-state.json';
  public
    /// <summary>%LOCALAPPDATA%\Atlas\index-state.json.</summary>
    class function DefaultFile: string; static;
    /// <summary>Fehlt die Datei oder ist sie ungültig: Empty.</summary>
    class function Load(const AFileName: string): TAtlasIndexSnapshot; static;
    /// <summary>False, wenn nicht geschrieben werden konnte; legt den Ordner bei Bedarf an.</summary>
    class function Save(const AFileName: string; const ASnapshot: TAtlasIndexSnapshot): Boolean; static;
  end;

implementation

uses
  System.IOUtils,
  System.DateUtils,
  System.JSON,
  Atlas.Core.Files.DataFile;

function DateText(AValue: TDateTime): string;
begin
  // Ortszeit mit Zeitzone: liest sich nach einer Umstellung der Uhr richtig zurück.
  Result := DateToISO8601(AValue, False);
end;

function ReadDate(AObject: TJSONObject; const AName: string): TDateTime;
var
  mField: TJSONValue;
begin
  Result := 0;
  mField := AObject.GetValue(AName);
  if not (mField is TJSONString) or (mField.Value = '') then
  begin
    Exit;
  end;
  if not TryISO8601ToDate(mField.Value, Result, False) then
  begin
    Result := 0;
  end;
end;

/// <summary>Ganze Zahl des Felds AName; False ohne Zahl.</summary>
function ReadInteger(AObject: TJSONObject; const AName: string; out AValue: Integer): Boolean;
var
  mField: TJSONValue;
begin
  AValue := 0;
  mField := AObject.GetValue(AName);
  Result := mField is TJSONNumber;
  if Result then
  begin
    AValue := TJSONNumber(mField).AsInt;
  end;
end;

{ TAtlasIndexSnapshot }

class function TAtlasIndexSnapshot.Empty: TAtlasIndexSnapshot;
begin
  Result.Units := -1;
  Result.FullAt := 0;
  Result.At := 0;
end;

function TAtlasIndexSnapshot.Known: Boolean;
begin
  Result := (Units >= 0) and (At > 0);
end;

function TAtlasIndexSnapshot.ToJson: string;
var
  mRoot: TJSONObject;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('format', TJSONNumber.Create(FormatVersion));
    mRoot.AddPair('units', TJSONNumber.Create(Units));
    if FullAt > 0 then
    begin
      mRoot.AddPair('fullIndexAt', DateText(FullAt));
    end;
    if At > 0 then
    begin
      mRoot.AddPair('at', DateText(At));
    end;
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasIndexSnapshot.FromJson(const AText: string): TAtlasIndexSnapshot;
var
  mValue: TJSONValue;
  mRoot: TJSONObject;
  mNumber: Integer;
begin
  Result := Empty;
  try
    mValue := TJSONObject.ParseJSONValue(AText);
  except
    on Exception do
      mValue := nil;
  end;
  try
    if not (mValue is TJSONObject) then
    begin
      Exit;
    end;
    mRoot := TJSONObject(mValue);
    if not ReadInteger(mRoot, 'format', mNumber) or (mNumber <> FormatVersion) then
    begin
      Exit;
    end;
    if ReadInteger(mRoot, 'units', mNumber) and (mNumber >= 0) then
    begin
      Result.Units := mNumber;
    end;
    Result.FullAt := ReadDate(mRoot, 'fullIndexAt');
    Result.At := ReadDate(mRoot, 'at');
  finally
    mValue.Free;
  end;
end;

class function TAtlasIndexSnapshot.Same(const ALeft, ARight: TAtlasIndexSnapshot): Boolean;
begin
  Result := (ALeft.Units = ARight.Units) and (ALeft.FullAt = ARight.FullAt) and (ALeft.At = ARight.At);
end;

{ TAtlasIndexTracker }

constructor TAtlasIndexTracker.Create(const AStored: TAtlasIndexSnapshot);
begin
  inherited Create;
  FSnapshot := AStored;
end;

function TAtlasIndexTracker.Observe(ARunning, AIndexing: Boolean; AUnits: Integer; ANow: TDateTime): Boolean;
begin
  Result := False;
  if not ARunning then
  begin
    // Der Server hört auf: den letzten bestätigten Stand sichern.
    Result := FWasRunning and FSnapshot.Known;
    FWasRunning := False;
    FWasIndexing := False;
    Exit;
  end;
  FWasRunning := True;
  if AIndexing then
  begin
    FWasIndexing := True;
    Exit;
  end;
  if FWasIndexing then
  begin
    // Die Indizierung ist zu Ende: das ist die letzte vollständige.
    FWasIndexing := False;
    FSnapshot.FullAt := ANow;
    Result := True;
  end;
  if AUnits < 0 then
  begin
    Exit;
  end;
  if AUnits <> FSnapshot.Units then
  begin
    FSnapshot.Units := AUnits;
    Result := True;
  end;
  // Der Stand gilt ab jetzt; geschrieben wird deswegen nur beim ersten Mal.
  if FSnapshot.At <= 0 then
  begin
    Result := True;
  end;
  FSnapshot.At := ANow;
end;

function TAtlasIndexTracker.Info(ARunning, AIndexing: Boolean; APercent, AUnits: Integer): TAtlasIndexInfo;
begin
  Result := Default(TAtlasIndexInfo);
  Result.Units := -1;
  Result.Percent := -1;
  Result.FullAt := FSnapshot.FullAt;
  if not ARunning then
  begin
    Result.Offline := True;
    if FSnapshot.Known then
    begin
      Result.Units := FSnapshot.Units;
      Result.StoredAt := FSnapshot.At;
    end;
    Exit;
  end;
  Result.Units := AUnits;
  Result.Indexing := AIndexing;
  Result.Percent := APercent;
end;

{ TAtlasIndexStore }

class function TAtlasIndexStore.DefaultFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), FileName);
end;

class function TAtlasIndexStore.Load(const AFileName: string): TAtlasIndexSnapshot;
var
  mText: string;
begin
  // Fehlt, gesperrt oder unbrauchbar: kein gespeicherter Stand.
  Result := TAtlasIndexSnapshot.Empty;
  if TAtlasDataFile.TryRead(AFileName, mText) then
    try
      Result := TAtlasIndexSnapshot.FromJson(mText);
    except
      // Unerwarteter Inhalt, den FromJson nicht abfängt: ebenso kein gespeicherter Stand.
      on Exception do
        Result := TAtlasIndexSnapshot.Empty;
    end;
end;

class function TAtlasIndexStore.Save(const AFileName: string; const ASnapshot: TAtlasIndexSnapshot): Boolean;
begin
  Result := False;
  try
    TAtlasDataFile.Write(AFileName, ASnapshot.ToJson);
    Result := True;
  except
    on E: Exception do
      TAtlasDataFile.ReportNotWritten('Index-Stand', E);
  end;
end;

end.
