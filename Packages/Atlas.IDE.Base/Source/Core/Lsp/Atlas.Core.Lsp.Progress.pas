unit Atlas.Core.Lsp.Progress;

// Index des Servers im Plugin (#492):
// - TLspProgress: verfolgt $/progress des Servers (begin/report/end) aus dem
//   Lese-Thread; Text liefert dem Hauptthread den aktuellen Stand, z. B.
//   "Index 45 %". Mehrere laufende Vorgänge: der zuletzt gemeldete zählt.
// - TLspIndexStatus: Antwort von atlas.server.status als Zeilen für die
//   Meldungsansicht (Units, Symbole, Indexgröße, letzter Lauf je Ordner) und
//   als Kennzahlen für die Einstellungsseite (Units, Deklarationen, Größe im
//   Speicher und auf der Platte, letzte Aktualisierung).
// - IndexingText: Text für die Statusleiste des Editors, solange der Server
//   indiziert ("Atlas indiziert … (45 %)"); die Vervollständigung zeigt
//   dann "eingeschränkt".
// - OnChanged (#591): nach jeder $/progress-Nachricht, im Lese-Thread; das
//   Atlas-Statusfeld aktualisiert so die Zeile „Index“ ohne Abfrage.

interface

uses
  System.SysUtils,
  System.JSON,
  System.SyncObjs,
  System.Generics.Collections;

type
  ILspProgress = interface
    ['{4E7D2B8A-91C3-4F65-B0D2-7A3E5C9F1B24}']
    /// <summary>params einer $/progress-Nachricht übernehmen (Lese-Thread).</summary>
    procedure Handle(const AParams: TJSONValue);
    /// <summary>Kurzer Stand ("Index 45 %"); '' ohne laufenden Vorgang.</summary>
    function Text: string;
    /// <summary>Statusleiste: "Atlas indiziert … (45 %)"; '' ohne laufenden Vorgang.</summary>
    function IndexingText: string;
    /// <summary>Fortschritt in Prozent (-1 = unbekannt) und ob ein Vorgang läuft.</summary>
    function Active(out APercent: Integer): Boolean;
    /// <summary>Beobachter für Änderungen; läuft im Lese-Thread.</summary>
    procedure SetOnChanged(const AProc: TProc);
  end;

  TLspProgress = class(TInterfacedObject, ILspProgress)
  private type
    TEntry = record
      Title: string;
      Percent: Integer;
    end;
  private
    FLock: TCriticalSection;
    FRunning: TDictionary<string, TEntry>;
    FLast: string;
    FOnChanged: TProc;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Handle(const AParams: TJSONValue);
    function Text: string;
    function IndexingText: string;
    function Active(out APercent: Integer): Boolean;
    procedure SetOnChanged(const AProc: TProc);
    /// <summary>Wie IndexingText aus Prozent (-1 = unbekannt); '' wenn nicht AActive.</summary>
    class function IndexingTextOf(AActive: Boolean; APercent: Integer): string; static;
  end;

  /// <summary>Kennzahlen des Index für die Einstellungsseite (#492).</summary>
  TLspIndexMetrics = record
    Valid: Boolean;
    Units: Integer;
    Declarations: Integer;
    MemoryBytes: Int64;
    BudgetBytes: Int64;
    OffloadedUnits: Integer;
    DiskBytes: Int64;
    /// <summary>Jüngste Aktualisierung aller Ordner (Ortszeit); 0 = keine.</summary>
    LastUpdate: TDateTime;
    /// <summary>Mehrzeiliger Text für die Einstellungsseite.</summary>
    function Text: string;
  end;

  TLspIndexStatus = class
  public
    /// <summary>Zeilen aus der JSON-Antwort von atlas.server.status; leer bei unbekanntem Format.</summary>
    class function Lines(const AStatus: TJSONValue): TArray<string>; static;
    /// <summary>Kennzahlen aus derselben Antwort; Valid = False bei unbekanntem Format.</summary>
    class function Metrics(const AStatus: TJSONValue): TLspIndexMetrics; static;
    /// <summary>Meldung zur Antwort von atlas.server.clearIndex.</summary>
    class function ClearedText(const AAnswer: TJSONValue): string; static;
    /// <summary>Größe für Menschen: "12,3 MB".</summary>
    class function SizeText(ABytes: Int64): string; static;
  end;

implementation

uses
  System.DateUtils;

{ TLspProgress }

constructor TLspProgress.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FRunning := TDictionary<string, TEntry>.Create;
end;

destructor TLspProgress.Destroy;
begin
  FRunning.Free;
  FLock.Free;
  inherited;
end;

procedure TLspProgress.Handle(const AParams: TJSONValue);
var
  Token, Kind: string;
  Value: TJSONValue;
  Entry: TEntry;
  Changed: TProc;
begin
  if not (AParams is TJSONObject) then
  begin
    Exit;
  end;
  Token := TJSONObject(AParams).GetValue<string>('token', '');
  Value := TJSONObject(AParams).GetValue('value');
  if not (Value is TJSONObject) then
  begin
    Exit;
  end;
  Kind := TJSONObject(Value).GetValue<string>('kind', '');
  FLock.Enter;
  try
    Changed := FOnChanged;
    if Kind = 'end' then
    begin
      FRunning.Remove(Token);
      if FLast = Token then
      begin
        FLast := '';
      end;
    end
    else
    begin
      if not FRunning.TryGetValue(Token, Entry) then
      begin
        Entry.Title := '';
        Entry.Percent := -1;
      end;
      if TJSONObject(Value).GetValue('title') <> nil then
      begin
        Entry.Title := TJSONObject(Value).GetValue<string>('title', '');
      end;
      if TJSONObject(Value).GetValue('percentage') <> nil then
      begin
        Entry.Percent := TJSONObject(Value).GetValue<Integer>('percentage', -1);
      end;
      FRunning.AddOrSetValue(Token, Entry);
      FLast := Token;
    end;
  finally
    FLock.Leave;
  end;
  if Assigned(Changed) then
  begin
    Changed();
  end;
end;

procedure TLspProgress.SetOnChanged(const AProc: TProc);
begin
  FLock.Enter;
  try
    FOnChanged := AProc;
  finally
    FLock.Leave;
  end;
end;

function TLspProgress.Active(out APercent: Integer): Boolean;
var
  Entry: TEntry;
  Key: string;
begin
  APercent := -1;
  FLock.Enter;
  try
    Key := FLast;
    Result := (Key <> '') and FRunning.TryGetValue(Key, Entry);
    if not Result then
    begin
      for Key in FRunning.Keys do
      begin
        Result := FRunning.TryGetValue(Key, Entry);
        Break;
      end;
    end;
    if Result then
    begin
      APercent := Entry.Percent;
    end;
  finally
    FLock.Leave;
  end;
end;

function TLspProgress.Text: string;
var
  Entry: TEntry;
  Key, Candidate: string;
begin
  FLock.Enter;
  try
    Result := '';
    Key := FLast;
    if (Key = '') or not FRunning.ContainsKey(Key) then
    begin
      Key := '';
      for Candidate in FRunning.Keys do
      begin
        Key := Candidate;
        Break;
      end;
    end;
    if (Key = '') or not FRunning.TryGetValue(Key, Entry) then
    begin
      Exit;
    end;
    Result := Entry.Title;
    if Result = '' then
    begin
      Result := '…';
    end;
    if Entry.Percent >= 0 then
    begin
      Result := Format('%s %d %%', [Result, Entry.Percent]);
    end;
  finally
    FLock.Leave;
  end;
end;

class function TLspProgress.IndexingTextOf(AActive: Boolean; APercent: Integer): string;
begin
  if not AActive then
  begin
    Result := '';
  end
  else if APercent >= 0 then
  begin
    Result := Format('Atlas indiziert … (%d %%)', [APercent]);
  end
  else
  begin
    Result := 'Atlas indiziert …';
  end;
end;

function TLspProgress.IndexingText: string;
var
  Entry: TEntry;
  Key: string;
  Active: Boolean;
begin
  FLock.Enter;
  try
    Key := FLast;
    Active := (Key <> '') and FRunning.TryGetValue(Key, Entry);
    if not Active then
    begin
      for Key in FRunning.Keys do
      begin
        Active := FRunning.TryGetValue(Key, Entry);
        Break;
      end;
    end;
  finally
    FLock.Leave;
  end;
  if Active then
  begin
    Result := IndexingTextOf(True, Entry.Percent);
  end
  else
  begin
    Result := '';
  end;
end;

{ TLspIndexMetrics }

function TLspIndexMetrics.Text: string;
begin
  if not Valid then
  begin
    Exit('Kennzahlen nicht verfügbar (Server läuft nicht).');
  end;
  Result := Format('Units: %d · Deklarationen: %d', [Units, Declarations]) + sLineBreak +
    'Im Speicher: ' + TLspIndexStatus.SizeText(MemoryBytes);
  if BudgetBytes > 0 then
  begin
    Result := Result + ' von ' + TLspIndexStatus.SizeText(BudgetBytes);
  end;
  if OffloadedUnits > 0 then
  begin
    Result := Result + Format(' (Verwendungen von %d Units ausgelagert)', [OffloadedUnits]);
  end;
  Result := Result + sLineBreak + 'Auf der Platte: ' + TLspIndexStatus.SizeText(DiskBytes) + sLineBreak +
    'Letzte Aktualisierung: ';
  if LastUpdate = 0 then
  begin
    Result := Result + '–';
  end
  else
  begin
    Result := Result + FormatDateTime('dd.mm.yyyy hh":"nn":"ss', LastUpdate);
  end;
end;

{ TLspIndexStatus }

class function TLspIndexStatus.SizeText(ABytes: Int64): string;
var
  Settings: TFormatSettings;
begin
  Settings := TFormatSettings.Invariant;
  Settings.DecimalSeparator := ',';
  if ABytes < 1024 * 1024 then
  begin
    Result := FormatFloat('0.0', ABytes / 1024, Settings) + ' KB';
  end
  else
  begin
    Result := FormatFloat('0.0', ABytes / (1024 * 1024), Settings) + ' MB';
  end;
end;

function LocalTimeOf(const AText: string): TDateTime;
begin
  Result := 0;
  if AText = '' then
  begin
    Exit;
  end;
  try
    Result := ISO8601ToDate(AText, False);
  except
    on Exception do
      Result := 0;
  end;
end;

class function TLspIndexStatus.Metrics(const AStatus: TJSONValue): TLspIndexMetrics;
var
  Status: TJSONObject;
  Workspaces, Item: TJSONValue;
  Update: TDateTime;
begin
  Result := Default(TLspIndexMetrics);
  if not (AStatus is TJSONObject) then
  begin
    Exit;
  end;
  Status := TJSONObject(AStatus);
  if Status.GetValue('units') = nil then
  begin
    Exit;
  end;
  Result.Valid := True;
  Result.Units := Status.GetValue<Integer>('units', 0);
  Result.Declarations := Status.GetValue<Integer>('symbols', 0);
  Result.MemoryBytes := Status.GetValue<Int64>('indexBytes', 0);
  Result.BudgetBytes := Status.GetValue<Int64>('budgetBytes', 0);
  Result.OffloadedUnits := Status.GetValue<Integer>('offloadedUnits', 0);
  Result.DiskBytes := Status.GetValue<Int64>('diskBytes', 0);
  Workspaces := Status.GetValue('workspaces');
  if Workspaces is TJSONArray then
  begin
    for Item in TJSONArray(Workspaces) do
    begin
      if Item is TJSONObject then
      begin
        Update := LocalTimeOf(TJSONObject(Item).GetValue<string>('lastUpdate', ''));
        if Update > Result.LastUpdate then
        begin
          Result.LastUpdate := Update;
        end;
      end;
    end;
  end;
end;

class function TLspIndexStatus.ClearedText(const AAnswer: TJSONValue): string;
begin
  if not (AAnswer is TJSONObject) then
  begin
    Exit('Index gelöscht; er wird neu aufgebaut.');
  end;
  Result := Format('Index gelöscht: %d Caches, %s frei; er wird neu aufgebaut.',
    [TJSONObject(AAnswer).GetValue<Integer>('removed', 0),
     SizeText(TJSONObject(AAnswer).GetValue<Int64>('freedBytes', 0))]);
end;

class function TLspIndexStatus.Lines(const AStatus: TJSONValue): TArray<string>;
var
  Status: TJSONObject;
  Workspaces: TJSONValue;
  Item: TJSONValue;
  Bytes: Int64;
begin
  Result := nil;
  if not (AStatus is TJSONObject) then
  begin
    Exit;
  end;
  Status := TJSONObject(AStatus);
  Bytes := Status.GetValue<Int64>('indexBytes', 0);
  // Beide Größen wie SizeText mit Dezimalkomma, unabhängig vom Gebietsschema.
  Result := Result + [Format('Atlas-Index: %d Units, %d Symbole, %s im Speicher, %s auf der Platte',
    [Status.GetValue<Integer>('units', 0), Status.GetValue<Integer>('symbols', 0), SizeText(Bytes),
     SizeText(Status.GetValue<Int64>('diskBytes', 0))])];
  Workspaces := Status.GetValue('workspaces');
  if Workspaces is TJSONArray then
  begin
    for Item in TJSONArray(Workspaces) do
    begin
      if Item is TJSONObject then
      begin
        Result := Result + [Format('    %s: letzter Lauf %d ms, %d gelesen, %d aus dem Cache, %d fehlen, Cache %s',
          [TJSONObject(Item).GetValue<string>('name', ''), TJSONObject(Item).GetValue<Integer>('lastIndexMs', 0),
          TJSONObject(Item).GetValue<Integer>('parsed', 0), TJSONObject(Item).GetValue<Integer>('fromCache', 0),
          TJSONObject(Item).GetValue<Integer>('missing', 0),
          SizeText(TJSONObject(Item).GetValue<Int64>('cacheBytes', 0) +
            TJSONObject(Item).GetValue<Int64>('libraryCacheBytes', 0))])];
      end;
    end;
  end;
end;

end.
