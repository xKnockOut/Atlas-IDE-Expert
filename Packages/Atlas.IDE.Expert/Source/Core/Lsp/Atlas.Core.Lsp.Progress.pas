unit Atlas.Core.Lsp.Progress;

// Index des Servers im Plugin (#492):
// - TLspProgress: verfolgt $/progress des Servers (begin/report/end) aus dem
//   Lese-Thread; Text liefert dem Hauptthread den aktuellen Stand, z. B.
//   "Index 45 %". Mehrere laufende Vorgänge: der zuletzt gemeldete zählt.
// - TLspIndexStatus: Antwort von atlas.server.status als Zeilen für die
//   Meldungsansicht (Units, Symbole, Indexgröße, letzter Lauf je Ordner).

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
  public
    constructor Create;
    destructor Destroy; override;
    procedure Handle(const AParams: TJSONValue);
    function Text: string;
  end;

  TLspIndexStatus = class
  public
    /// <summary>Zeilen aus der JSON-Antwort von atlas.server.status; leer bei unbekanntem Format.</summary>
    class function Lines(const AStatus: TJSONValue): TArray<string>; static;
  end;

implementation

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
begin
  if not (AParams is TJSONObject) then
    Exit;
  Token := TJSONObject(AParams).GetValue<string>('token', '');
  Value := TJSONObject(AParams).GetValue('value');
  if not (Value is TJSONObject) then
    Exit;
  Kind := TJSONObject(Value).GetValue<string>('kind', '');
  FLock.Enter;
  try
    if Kind = 'end' then
    begin
      FRunning.Remove(Token);
      if FLast = Token then
        FLast := '';
      Exit;
    end;
    if not FRunning.TryGetValue(Token, Entry) then
    begin
      Entry.Title := '';
      Entry.Percent := -1;
    end;
    if TJSONObject(Value).GetValue('title') <> nil then
      Entry.Title := TJSONObject(Value).GetValue<string>('title', '');
    if TJSONObject(Value).GetValue('percentage') <> nil then
      Entry.Percent := TJSONObject(Value).GetValue<Integer>('percentage', -1);
    FRunning.AddOrSetValue(Token, Entry);
    FLast := Token;
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
      Exit;
    Result := Entry.Title;
    if Result = '' then
      Result := '…';
    if Entry.Percent >= 0 then
      Result := Format('%s %d %%', [Result, Entry.Percent]);
  finally
    FLock.Leave;
  end;
end;

{ TLspIndexStatus }

class function TLspIndexStatus.Lines(const AStatus: TJSONValue): TArray<string>;
var
  Status: TJSONObject;
  Workspaces: TJSONValue;
  Item: TJSONValue;
  Bytes: Int64;
begin
  Result := nil;
  if not (AStatus is TJSONObject) then
    Exit;
  Status := TJSONObject(AStatus);
  Bytes := Status.GetValue<Int64>('indexBytes', 0);
  Result := Result + [Format('Atlas-Index: %d Units, %d Symbole, %.1f MB im Speicher',
    [Status.GetValue<Integer>('units', 0), Status.GetValue<Integer>('symbols', 0), Bytes / (1024 * 1024)])];
  Workspaces := Status.GetValue('workspaces');
  if Workspaces is TJSONArray then
    for Item in TJSONArray(Workspaces) do
      if Item is TJSONObject then
        Result := Result + [Format('    %s: letzter Lauf %d ms, %d gelesen, %d aus dem Cache, %d fehlen',
          [TJSONObject(Item).GetValue<string>('name', ''), TJSONObject(Item).GetValue<Integer>('lastIndexMs', 0),
          TJSONObject(Item).GetValue<Integer>('parsed', 0), TJSONObject(Item).GetValue<Integer>('fromCache', 0),
          TJSONObject(Item).GetValue<Integer>('missing', 0)])];
end;

end.
