unit Argus.Common.JsonRpc.PendingRequests;

// Offene Anfragen einer Verbindung: Abbruchsignale je Anfrage-id,
// $/cancelRequest und ein Zähler für Arbeit, die in Worker-Threads läuft.
// Ändert eine Benachrichtigung wie textDocument/didChange ein Dokument, werden
// offene Anfragen zu dessen URI mit ContentModified abgebrochen (#283).
//
// Das Objekt ist referenzgezählt und threadsicher. Lese-Thread, Dispatcher und
// Worker halten jeweils eine Referenz, damit keiner von ihnen auf ein bereits
// freigegebenes Objekt zugreift.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  System.JSON,
  Argus.Common.JsonRpc.Contract;

type
  /// <summary>Abbruchsignal mit Auslöser.</summary>
  IJsonRpcCancellationSource = interface(IJsonRpcCancellationToken)
    ['{A4E7D0B9-5C21-4F3A-8E6D-1B9C2F7A3E58}']
    procedure Cancel;
    /// <summary>Abbruch, weil das Dokument sich geändert hat.</summary>
    procedure CancelModified;
  end;

  TJsonRpcCancellation = class(TInterfacedObject, IJsonRpcCancellationToken, IJsonRpcCancellationSource)
  private
    /// <summary>0 = offen, 1 = abgebrochen, 2 = Dokument geändert.</summary>
    FCancelled: Integer;
  public
    function IsCancellationRequested: Boolean;
    procedure ThrowIfCancellationRequested;
    procedure Cancel;
    procedure CancelModified;
  end;

  IJsonRpcPendingRequests = interface
    ['{6D2B9E14-3A7C-4B58-9F01-C5E8A2D7B436}']
    /// <summary>
    /// Sieht eine eingelesene Nachricht vor ihrer Verarbeitung: Anfragen werden
    /// als offen vermerkt, $/cancelRequest wird sofort ausgeführt. Liefert True,
    /// wenn die Nachricht damit erledigt ist. Wird vom Lese-Thread aufgerufen,
    /// damit ein Abbruch auch wirkt, während die Nachrichtenschleife beschäftigt ist.
    /// </summary>
    function Observe(const AMessage: TJSONObject): Boolean;
    /// <summary>Abbruchsignal der Anfrage AId; vermerkt sie als offen, falls nötig.</summary>
    function Acquire(const AId: TJSONValue): IJsonRpcCancellationToken;
    /// <summary>Die Anfrage ist beantwortet; ein späterer Abbruch wird ignoriert.</summary>
    procedure Release(const AId: TJSONValue; const AToken: IJsonRpcCancellationToken);
    /// <summary>Bricht die offene Anfrage AId ab; unbekannte ids werden ignoriert.</summary>
    procedure Cancel(const AId: TJSONValue);
    /// <summary>Bricht alle offenen Anfragen ab, z. B. beim Beenden der Verbindung.</summary>
    procedure CancelAll;
    /// <summary>Benachrichtigungen dieser Methode ändern das Dokument aus params.textDocument.uri.</summary>
    procedure AddContentChangeMethod(const AMethod: string);
    /// <summary>Bricht offene Anfragen zu AUri mit ContentModified ab.</summary>
    procedure CancelForUri(const AUri: string);
    /// <summary>Zählt eine Arbeit, die in einem Worker-Thread läuft.</summary>
    procedure BeginWork;
    procedure EndWork;
    /// <summary>Wartet, bis keine Arbeit mehr läuft. False bei Zeitüberschreitung.</summary>
    function WaitForWork(ATimeout: Cardinal): Boolean;
  end;

  TJsonRpcPendingRequests = class(TInterfacedObject, IJsonRpcPendingRequests)
  private
    FLock: TCriticalSection;
    FRequests: TDictionary<string, IJsonRpcCancellationSource>;
    /// <summary>Anfrage-Schlüssel → URI des Dokuments.</summary>
    FUris: TDictionary<string, string>;
    FChangeMethods: TArray<string>;
    FWorkCount: Integer;
    FIdle: TLightweightEvent;
    class function KeyOf(const AId: TJSONValue): string; static;
  public
    constructor Create;
    destructor Destroy; override;
    { IJsonRpcPendingRequests }
    function Observe(const AMessage: TJSONObject): Boolean;
    function Acquire(const AId: TJSONValue): IJsonRpcCancellationToken;
    procedure Release(const AId: TJSONValue; const AToken: IJsonRpcCancellationToken);
    procedure Cancel(const AId: TJSONValue);
    procedure CancelAll;
    procedure AddContentChangeMethod(const AMethod: string);
    procedure CancelForUri(const AUri: string);
    procedure BeginWork;
    procedure EndWork;
    function WaitForWork(ATimeout: Cardinal): Boolean;
  end;

implementation

/// <summary>params.textDocument.uri oder ''.</summary>
function DocumentUri(const AMessage: TJSONObject): string;
var
  Params, Document, Uri: TJSONValue;
begin
  Result := '';
  Params := AMessage.GetValue('params');
  if not (Params is TJSONObject) then
    Exit;
  Document := TJSONObject(Params).GetValue('textDocument');
  if not (Document is TJSONObject) then
    Exit;
  Uri := TJSONObject(Document).GetValue('uri');
  if Uri is TJSONString then
    Result := Uri.Value;
end;

{ TJsonRpcCancellation }

function TJsonRpcCancellation.IsCancellationRequested: Boolean;
begin
  Result := TInterlocked.CompareExchange(FCancelled, 0, 0) <> 0;
end;

procedure TJsonRpcCancellation.ThrowIfCancellationRequested;
begin
  case TInterlocked.CompareExchange(FCancelled, 0, 0) of
    1:
      raise EJsonRpcRequestCancelled.Create;
    2:
      raise EJsonRpcContentModified.Create;
  end;
end;

procedure TJsonRpcCancellation.Cancel;
begin
  TInterlocked.Exchange(FCancelled, 1);
end;

procedure TJsonRpcCancellation.CancelModified;
begin
  // Ein ausdrücklicher Abbruch bleibt ein Abbruch.
  TInterlocked.CompareExchange(FCancelled, 2, 0);
end;

{ TJsonRpcPendingRequests }

constructor TJsonRpcPendingRequests.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FRequests := TDictionary<string, IJsonRpcCancellationSource>.Create;
  FUris := TDictionary<string, string>.Create;
  FIdle := TLightweightEvent.Create(True);
end;

destructor TJsonRpcPendingRequests.Destroy;
begin
  FIdle.Free;
  FUris.Free;
  FRequests.Free;
  FLock.Free;
  inherited;
end;

class function TJsonRpcPendingRequests.KeyOf(const AId: TJSONValue): string;
begin
  // ToJSON unterscheidet die id 1 von der id "1".
  if AId = nil then
    Result := 'null'
  else
    Result := AId.ToJSON;
end;

function TJsonRpcPendingRequests.Observe(const AMessage: TJSONObject): Boolean;
var
  Method: TJSONValue;
  Id: TJSONValue;
  Params: TJSONValue;
  Uri: string;

  function IsChangeMethod(const AName: string): Boolean;
  var
    Name: string;
  begin
    FLock.Enter;
    try
      for Name in FChangeMethods do
        if Name = AName then
          Exit(True);
    finally
      FLock.Leave;
    end;
    Result := False;
  end;

begin
  Result := False;
  Method := AMessage.GetValue('method');
  if not (Method is TJSONString) then
    Exit;
  Id := AMessage.GetValue('id');
  if Id <> nil then
  begin
    Acquire(Id);
    Uri := DocumentUri(AMessage);
    if Uri <> '' then
    begin
      FLock.Enter;
      try
        FUris.AddOrSetValue(KeyOf(Id), Uri);
      finally
        FLock.Leave;
      end;
    end;
  end
  else if Method.Value = JsonRpcCancelRequestMethod then
  begin
    Params := AMessage.GetValue('params');
    if Params is TJSONObject then
    begin
      Id := TJSONObject(Params).GetValue('id');
      if Id <> nil then
        Cancel(Id);
    end;
    Result := True;
  end
  else if IsChangeMethod(Method.Value) then
  begin
    Uri := DocumentUri(AMessage);
    if Uri <> '' then
      CancelForUri(Uri);
  end;
end;

function TJsonRpcPendingRequests.Acquire(const AId: TJSONValue): IJsonRpcCancellationToken;
var
  Key: string;
  Source: IJsonRpcCancellationSource;
begin
  Key := KeyOf(AId);
  FLock.Enter;
  try
    if not FRequests.TryGetValue(Key, Source) then
    begin
      Source := TJsonRpcCancellation.Create;
      FRequests.Add(Key, Source);
    end;
  finally
    FLock.Leave;
  end;
  Result := Source;
end;

procedure TJsonRpcPendingRequests.Release(const AId: TJSONValue; const AToken: IJsonRpcCancellationToken);
var
  Key: string;
  Source: IJsonRpcCancellationSource;
begin
  Key := KeyOf(AId);
  FLock.Enter;
  try
    // Nur den eigenen Eintrag entfernen, falls die Gegenseite eine id doppelt vergibt.
    if FRequests.TryGetValue(Key, Source) and ((Source as IInterface) = (AToken as IInterface)) then
    begin
      FRequests.Remove(Key);
      FUris.Remove(Key);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TJsonRpcPendingRequests.Cancel(const AId: TJSONValue);
var
  Source: IJsonRpcCancellationSource;
begin
  FLock.Enter;
  try
    if FRequests.TryGetValue(KeyOf(AId), Source) then
      Source.Cancel;
  finally
    FLock.Leave;
  end;
end;

procedure TJsonRpcPendingRequests.CancelAll;
var
  Source: IJsonRpcCancellationSource;
begin
  FLock.Enter;
  try
    for Source in FRequests.Values do
      Source.Cancel;
  finally
    FLock.Leave;
  end;
end;

procedure TJsonRpcPendingRequests.AddContentChangeMethod(const AMethod: string);
begin
  FLock.Enter;
  try
    FChangeMethods := FChangeMethods + [AMethod];
  finally
    FLock.Leave;
  end;
end;

procedure TJsonRpcPendingRequests.CancelForUri(const AUri: string);
var
  Pair: TPair<string, string>;
  Source: IJsonRpcCancellationSource;
begin
  FLock.Enter;
  try
    for Pair in FUris do
      if (Pair.Value = AUri) and FRequests.TryGetValue(Pair.Key, Source) then
        Source.CancelModified;
  finally
    FLock.Leave;
  end;
end;

procedure TJsonRpcPendingRequests.BeginWork;
begin
  FLock.Enter;
  try
    Inc(FWorkCount);
    if FWorkCount = 1 then
      FIdle.ResetEvent;
  finally
    FLock.Leave;
  end;
end;

procedure TJsonRpcPendingRequests.EndWork;
begin
  FLock.Enter;
  try
    Dec(FWorkCount);
    if FWorkCount = 0 then
      FIdle.SetEvent;
  finally
    FLock.Leave;
  end;
end;

function TJsonRpcPendingRequests.WaitForWork(ATimeout: Cardinal): Boolean;
begin
  Result := FIdle.WaitFor(ATimeout) = TWaitResult.wrSignaled;
end;

end.
