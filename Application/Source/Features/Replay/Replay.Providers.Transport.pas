unit Replay.Providers.Transport;

// Hosted-Feature Replay: Transport des Nachstellens (#1355). Spielt die Nachrichten eines Absturzfalls in den
// Server ein, wartet vor der Anfrage auf die Ruhe der Indizierung ($/progress ohne offene Vorgänge) und fängt die
// Antwort auf die Anfrage ab.

interface

uses
  System.SysUtils,
  System.JSON,
  System.SyncObjs,
  System.Generics.Collections,
  Replay.Contract;

type
  /// <summary>Spielt die Nachrichten des Falls ein und fängt die Antwort auf die Anfrage ab.</summary>
  TReplayTransport = class(TInterfacedObject, IReplayTransport)
  private
    FLock: TObject;
    FMessages: TObjectList<TJSONObject>;
    FNext: Integer;
    /// <summary>Vor dieser Nachricht (der Anfrage) auf die Ruhe der Indizierung warten, danach auf die Antwort.
    /// </summary>
    FRequestIndex: Integer;
    FAnswerMs: Cardinal;
    FAnswered: TEvent;
    FAnswer: TJSONObject;
    FOpenProgress: Integer;
    FLastProgress: UInt64;
    procedure Settle;
  public
    constructor Create(const AMessages: TArray<TJSONObject>; ARequestIndex: Integer; AAnswerMs: Cardinal);
    destructor Destroy; override;
    function ReadMessage: TJSONObject;
    procedure WriteMessage(const AMessage: TJSONObject);
    function TakeAnswer: TJSONObject;
    /// <summary>Erzeuger für TReplayPlayer.Run.</summary>
    class function Factory: TReplayTransportFactory; static;
  end;

implementation

uses
  System.Classes,
  Replay.Player,
  Atlas.Common.JsonRpc.Contract;

{ TReplayTransport }

constructor TReplayTransport.Create(const AMessages: TArray<TJSONObject>; ARequestIndex: Integer;
  AAnswerMs: Cardinal);
var
  mMessage: TJSONObject;
begin
  inherited Create;
  FLock := TObject.Create;
  FMessages := TObjectList<TJSONObject>.Create(True);
  for mMessage in AMessages do
  begin
    FMessages.Add(mMessage);
  end;
  FRequestIndex := ARequestIndex;
  FAnswerMs := AAnswerMs;
  FAnswered := TEvent.Create(nil, True, False, '');
  FLastProgress := TThread.GetTickCount64;
end;

destructor TReplayTransport.Destroy;
begin
  FAnswer.Free;
  FAnswered.Free;
  FMessages.Free;
  FLock.Free;
  inherited;
end;

procedure TReplayTransport.Settle;
var
  mStart: UInt64;
  mOpen: Integer;
  mLast: UInt64;
begin
  mStart := TThread.GetTickCount64;
  while TThread.GetTickCount64 - mStart < TReplayPlayer.cSettleMaxMs do
  begin
    System.TMonitor.Enter(FLock);
    try
      mOpen := FOpenProgress;
      mLast := FLastProgress;
    finally
      System.TMonitor.Exit(FLock);
    end;
    if (mOpen <= 0) and (TThread.GetTickCount64 - mLast >= TReplayPlayer.cSettleQuietMs) then
    begin
      Exit;
    end;
    TThread.Sleep(100);
  end;
end;

function TReplayTransport.ReadMessage: TJSONObject;
var
  mIndex: Integer;
begin
  System.TMonitor.Enter(FLock);
  try
    mIndex := FNext;
    Inc(FNext);
  finally
    System.TMonitor.Exit(FLock);
  end;
  if mIndex >= FMessages.Count then
  begin
    raise EJsonRpcTransportClosed.Create('Nachstellen beendet');
  end;
  if mIndex = FRequestIndex then
  begin
    Settle;
  end;
  // Nach der Anfrage erst weiter, wenn sie beantwortet ist (oder die Zeit abläuft): shutdown käme sonst zu früh.
  if mIndex = FRequestIndex + 1 then
  begin
    FAnswered.WaitFor(FAnswerMs);
  end;
  Result := TJSONObject(FMessages[mIndex].Clone);
end;

/// <summary>Ist AMessage die Antwort des Servers auf die nachgestellte Anfrage?</summary>
function IsRequestAnswer(const AMessage: TJSONObject): Boolean;
var
  mId: TJSONValue;
begin
  mId := AMessage.GetValue('id');
  Result := (mId is TJSONString) and (mId.Value = TReplayPlayer.cRequestId) and (AMessage.GetValue('method') = nil);
end;

/// <summary>Art einer $/progress-Meldung (begin, report, end; '' ohne); False bei anderen Nachrichten.</summary>
function ProgressKind(const AMessage: TJSONObject; out AKind: string): Boolean;
var
  mValue: TJSONValue;
begin
  AKind := '';
  mValue := AMessage.GetValue('method');
  Result := (mValue is TJSONString) and (mValue.Value = '$/progress');
  if not Result then
  begin
    Exit;
  end;
  mValue := AMessage.GetValue('params');
  if mValue is TJSONObject then
  begin
    mValue := TJSONObject(mValue).GetValue('value');
  end;
  if mValue is TJSONObject then
  begin
    mValue := TJSONObject(mValue).GetValue('kind');
  end;
  if mValue is TJSONString then
  begin
    AKind := mValue.Value;
  end;
end;

procedure TReplayTransport.WriteMessage(const AMessage: TJSONObject);
var
  mKind: string;
begin
  if AMessage = nil then
  begin
    Exit;
  end;
  if IsRequestAnswer(AMessage) then
  begin
    System.TMonitor.Enter(FLock);
    try
      if FAnswer = nil then
      begin
        FAnswer := TJSONObject(AMessage.Clone);
      end;
    finally
      System.TMonitor.Exit(FLock);
    end;
    FAnswered.SetEvent;
    Exit;
  end;
  if not ProgressKind(AMessage, mKind) then
  begin
    Exit;
  end;
  System.TMonitor.Enter(FLock);
  try
    FLastProgress := TThread.GetTickCount64;
    if mKind = 'begin' then
    begin
      Inc(FOpenProgress);
    end
    else if mKind = 'end' then
    begin
      Dec(FOpenProgress);
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TReplayTransport.TakeAnswer: TJSONObject;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := FAnswer;
    FAnswer := nil;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

class function TReplayTransport.Factory: TReplayTransportFactory;
begin
  Result :=
    function(const AMessages: TArray<TJSONObject>; ARequestIndex: Integer; AAnswerMs: Cardinal): IReplayTransport
    begin
      Result := TReplayTransport.Create(AMessages, ARequestIndex, AAnswerMs);
    end;
end;

end.
