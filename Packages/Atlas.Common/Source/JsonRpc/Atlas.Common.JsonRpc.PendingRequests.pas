unit Atlas.Common.JsonRpc.PendingRequests;

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
  Atlas.Common.JsonRpc.Contract;

type
  /// <summary>Abbruchsignal mit Auslöser.</summary>
  IJsonRpcCancellationSource = interface(IJsonRpcCancellationToken)
    ['{A4E7D0B9-5C21-4F3A-8E6D-1B9C2F7A3E58}']
    procedure Cancel;
    /// <summary>Abbruch, weil das Dokument sich geändert hat.</summary>
    procedure CancelModified;
    /// <summary>Abbruch, weil das Zeitlimit abgelaufen ist (Watchdog); ein späteres Cancel überschreibt ihn.
    /// </summary>
    procedure Expire;
    /// <summary>True, wenn nur das Zeitlimit abgelaufen ist: kein ausdrücklicher Abbruch ($/cancelRequest, Ende
    /// der Verbindung), kein geändertes Dokument. Eine Arbeit, deren Ergebnis gespeichert wird, darf dann zu Ende
    /// laufen.</summary>
    function OnlyExpired: Boolean;
    /// <summary>Beansprucht die einzige Antwort auf die Anfrage: True genau beim ersten Aufruf (Worker oder
    /// Watchdog). Threadsicher.</summary>
    function TryAnswer: Boolean;
  end;

  TJsonRpcCancellation = class(TInterfacedObject, IJsonRpcCancellationToken, IJsonRpcCancellationSource)
  private
    /// <summary>0 = offen, 1 = abgebrochen, 2 = Dokument geändert, 3 = Zeitlimit abgelaufen.</summary>
    FCancelled: Integer;
    /// <summary>1, sobald jemand die Antwort beansprucht hat.</summary>
    FAnswered: Integer;
  public
    function IsCancellationRequested: Boolean;
    procedure ThrowIfCancellationRequested;
    procedure Cancel;
    procedure CancelModified;
    procedure Expire;
    function OnlyExpired: Boolean;
    function TryAnswer: Boolean;
  end;

  /// <summary>Signal einer Anfrage ohne ihr bloßes Zeitlimit (#1761): für Arbeit, deren Ergebnis gespeichert wird
  /// und die nach dem Zeitlimit zu Ende laufen darf, auch für tiefe Aufrufe über TJsonRpcCurrentRequest.
  /// Ausdrücklicher Abbruch und geändertes Dokument gelten weiter.</summary>
  TJsonRpcPastTimeout = class(TInterfacedObject, IJsonRpcCancellationToken)
  private
    FRequest: IJsonRpcCancellationToken;
  public
    /// <summary>ARequest darf nil sein (nie abgebrochen).</summary>
    constructor Create(const ARequest: IJsonRpcCancellationToken);
    function IsCancellationRequested: Boolean;
    procedure ThrowIfCancellationRequested;
    /// <summary>True, wenn bei ARequest nur das Zeitlimit abgelaufen ist (IJsonRpcCancellationSource.OnlyExpired).
    /// </summary>
    class function OnlyExpired(const ARequest: IJsonRpcCancellationToken): Boolean; static;
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
    /// <summary>True, wenn die offene Anfrage AId schon vor ihrem Zeitlimit abgebrochen wurde
    /// ($/cancelRequest, geändertes Dokument, Ende der Verbindung): Niemand wartet mehr auf sie.</summary>
    function Abandoned(const AId: TJSONValue): Boolean;
    /// <summary>Zeitlimit abgelaufen: bricht über AToken ab und beansprucht die Antwort. True: Der
    /// Aufrufer sendet die Fehlerantwort; die spätere Antwort des Handlers wird verworfen. False, wenn der
    /// Handler schon geantwortet hat oder AToken fremd ist.</summary>
    function Expire(const AToken: IJsonRpcCancellationToken): Boolean;
    /// <summary>True, wenn der Aufrufer antworten darf (noch niemand hat geantwortet); fremde Token: True.</summary>
    function TryAnswer(const AToken: IJsonRpcCancellationToken): Boolean;
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
    /// <summary>Benachrichtigungen der Methode AName ändern ein Dokument.</summary>
    function IsChangeMethod(const AName: string): Boolean;
    /// <summary>Vermerkt die Anfrage AId als offen, mit dem Dokument aus AMessage.</summary>
    procedure ObserveRequest(const AMessage: TJSONObject; const AId: TJSONValue);
    /// <summary>Cancel, wenn AId gesetzt ist.</summary>
    procedure CancelById(const AId: TJSONValue);
  public
    constructor Create;
    destructor Destroy; override;
    { IJsonRpcPendingRequests }
    function Observe(const AMessage: TJSONObject): Boolean;
    function Acquire(const AId: TJSONValue): IJsonRpcCancellationToken;
    procedure Release(const AId: TJSONValue; const AToken: IJsonRpcCancellationToken);
    procedure Cancel(const AId: TJSONValue);
    procedure CancelAll;
    function Abandoned(const AId: TJSONValue): Boolean;
    function Expire(const AToken: IJsonRpcCancellationToken): Boolean;
    function TryAnswer(const AToken: IJsonRpcCancellationToken): Boolean;
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
  mParams, mDocument, mUri: TJSONValue;
begin
  Result := '';
  mParams := AMessage.GetValue('params');
  if not (mParams is TJSONObject) then
  begin
    Exit;
  end;
  mDocument := TJSONObject(mParams).GetValue('textDocument');
  if not (mDocument is TJSONObject) then
  begin
    Exit;
  end;
  mUri := TJSONObject(mDocument).GetValue('uri');
  if mUri is TJSONString then
  begin
    Result := mUri.Value;
  end;
end;

{ TJsonRpcCancellation }

function TJsonRpcCancellation.IsCancellationRequested: Boolean;
begin
  Result := TInterlocked.CompareExchange(FCancelled, 0, 0) <> 0;
end;

procedure TJsonRpcCancellation.ThrowIfCancellationRequested;
begin
  case TInterlocked.CompareExchange(FCancelled, 0, 0) of
    1, 3:
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
  // Ein ausdrücklicher Abbruch bleibt ein Abbruch; ein geändertes Dokument wiegt schwerer als das Zeitlimit.
  if TInterlocked.CompareExchange(FCancelled, 2, 0) = 3 then
  begin
    TInterlocked.CompareExchange(FCancelled, 2, 3);
  end;
end;

procedure TJsonRpcCancellation.Expire;
begin
  TInterlocked.CompareExchange(FCancelled, 3, 0);
end;

function TJsonRpcCancellation.OnlyExpired: Boolean;
begin
  Result := TInterlocked.CompareExchange(FCancelled, 0, 0) = 3;
end;

function TJsonRpcCancellation.TryAnswer: Boolean;
begin
  Result := TInterlocked.CompareExchange(FAnswered, 1, 0) = 0;
end;

{ TJsonRpcPastTimeout }

constructor TJsonRpcPastTimeout.Create(const ARequest: IJsonRpcCancellationToken);
begin
  inherited Create;
  FRequest := ARequest;
end;

class function TJsonRpcPastTimeout.OnlyExpired(const ARequest: IJsonRpcCancellationToken): Boolean;
var
  mSource: IJsonRpcCancellationSource;
begin
  Result := Supports(ARequest, IJsonRpcCancellationSource, mSource) and mSource.OnlyExpired;
end;

function TJsonRpcPastTimeout.IsCancellationRequested: Boolean;
begin
  Result := (FRequest <> nil) and FRequest.IsCancellationRequested and not OnlyExpired(FRequest);
end;

procedure TJsonRpcPastTimeout.ThrowIfCancellationRequested;
begin
  if IsCancellationRequested then
  begin
    FRequest.ThrowIfCancellationRequested;
  end;
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
  begin
    Result := 'null';
  end
  else
  begin
    Result := AId.ToJSON;
  end;
end;

/// <summary>Id der abzubrechenden Anfrage aus params.AKey; nil ohne.</summary>
function CancelledId(const AMessage: TJSONObject; const AKey: string): TJSONValue;
var
  mParams: TJSONValue;
begin
  Result := nil;
  mParams := AMessage.GetValue('params');
  if mParams is TJSONObject then
  begin
    Result := TJSONObject(mParams).GetValue(AKey);
  end;
end;

function TJsonRpcPendingRequests.IsChangeMethod(const AName: string): Boolean;
var
  mName: string;
begin
  FLock.Enter;
  try
    for mName in FChangeMethods do
    begin
      if mName = AName then
      begin
        Exit(True);
      end;
    end;
  finally
    FLock.Leave;
  end;
  Result := False;
end;

procedure TJsonRpcPendingRequests.ObserveRequest(const AMessage: TJSONObject; const AId: TJSONValue);
var
  mUri: string;
begin
  Acquire(AId);
  mUri := DocumentUri(AMessage);
  if mUri <> '' then
  begin
    FLock.Enter;
    try
      FUris.AddOrSetValue(KeyOf(AId), mUri);
    finally
      FLock.Leave;
    end;
  end;
end;

procedure TJsonRpcPendingRequests.CancelById(const AId: TJSONValue);
begin
  if AId <> nil then
  begin
    Cancel(AId);
  end;
end;

function TJsonRpcPendingRequests.Observe(const AMessage: TJSONObject): Boolean;
var
  mMethod, mId: TJSONValue;
  mUri: string;
begin
  Result := False;
  mMethod := AMessage.GetValue('method');
  if not (mMethod is TJSONString) then
  begin
    Exit;
  end;
  mId := AMessage.GetValue('id');
  if mId <> nil then
  begin
    ObserveRequest(AMessage, mId);
  end
  else if mMethod.Value = cJsonRpcCancelRequestMethod then
  begin
    CancelById(CancelledId(AMessage, 'id'));
    Result := True;
  end
  else if mMethod.Value = cMcpCancelledMethod then
  begin
    CancelById(CancelledId(AMessage, 'requestId'));
    Result := True;
  end
  else if IsChangeMethod(mMethod.Value) then
  begin
    mUri := DocumentUri(AMessage);
    if mUri <> '' then
    begin
      CancelForUri(mUri);
    end;
  end;
end;

function TJsonRpcPendingRequests.Acquire(const AId: TJSONValue): IJsonRpcCancellationToken;
var
  mKey: string;
  mSource: IJsonRpcCancellationSource;
begin
  mKey := KeyOf(AId);
  FLock.Enter;
  try
    if not FRequests.TryGetValue(mKey, mSource) then
    begin
      mSource := TJsonRpcCancellation.Create;
      FRequests.Add(mKey, mSource);
    end;
  finally
    FLock.Leave;
  end;
  Result := mSource;
end;

procedure TJsonRpcPendingRequests.Release(const AId: TJSONValue; const AToken: IJsonRpcCancellationToken);
var
  mKey: string;
  mSource: IJsonRpcCancellationSource;
begin
  mKey := KeyOf(AId);
  FLock.Enter;
  try
    // Nur den eigenen Eintrag entfernen, falls die Gegenseite eine id doppelt vergibt.
    if FRequests.TryGetValue(mKey, mSource) and ((mSource as IInterface) = (AToken as IInterface)) then
    begin
      FRequests.Remove(mKey);
      FUris.Remove(mKey);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TJsonRpcPendingRequests.Cancel(const AId: TJSONValue);
var
  mSource: IJsonRpcCancellationSource;
begin
  FLock.Enter;
  try
    if FRequests.TryGetValue(KeyOf(AId), mSource) then
    begin
      mSource.Cancel;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TJsonRpcPendingRequests.CancelAll;
var
  mSource: IJsonRpcCancellationSource;
begin
  FLock.Enter;
  try
    for mSource in FRequests.Values do
    begin
      mSource.Cancel;
    end;
  finally
    FLock.Leave;
  end;
end;

function TJsonRpcPendingRequests.Abandoned(const AId: TJSONValue): Boolean;
var
  mSource: IJsonRpcCancellationSource;
begin
  Result := False;
  FLock.Enter;
  try
    if FRequests.TryGetValue(KeyOf(AId), mSource) then
    begin
      Result := mSource.IsCancellationRequested and not mSource.OnlyExpired;
    end;
  finally
    FLock.Leave;
  end;
end;

function TJsonRpcPendingRequests.Expire(const AToken: IJsonRpcCancellationToken): Boolean;
var
  mSource: IJsonRpcCancellationSource;
begin
  if not Supports(AToken, IJsonRpcCancellationSource, mSource) then
  begin
    Exit(False);
  end;
  mSource.Expire;
  Result := mSource.TryAnswer;
end;

function TJsonRpcPendingRequests.TryAnswer(const AToken: IJsonRpcCancellationToken): Boolean;
var
  mSource: IJsonRpcCancellationSource;
begin
  // Fremde Token (Tests, eigene Implementierungen) kennen keine Antwortsperre.
  if not Supports(AToken, IJsonRpcCancellationSource, mSource) then
  begin
    Exit(True);
  end;
  Result := mSource.TryAnswer;
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
  mPair: TPair<string, string>;
  mSource: IJsonRpcCancellationSource;
begin
  FLock.Enter;
  try
    for mPair in FUris do
    begin
      if (mPair.Value = AUri) and FRequests.TryGetValue(mPair.Key, mSource) then
      begin
        mSource.CancelModified;
      end;
    end;
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
    begin
      FIdle.ResetEvent;
    end;
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
    begin
      FIdle.SetEvent;
    end;
  finally
    FLock.Leave;
  end;
end;

function TJsonRpcPendingRequests.WaitForWork(ATimeout: Cardinal): Boolean;
begin
  Result := FIdle.WaitFor(ATimeout) = TWaitResult.wrSignaled;
end;

end.
