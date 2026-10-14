unit Atlas.Core.Lsp.Client;

// Schlanker LSP-Client für das IDE-Plugin (ADR 0006): JSON-RPC mit
// Content-Length-Rahmung, Zuordnung der Antworten zu Anfragen und Warten mit
// Zeitlimit. Der Transport ist ausgelagert: Gesendet wird über ASend (fertig
// gerahmte Bytes), empfangene Bytes kommen über Receive herein, auch in
// beliebigen Stücken und aus einem anderen Thread.
// Anfragen des Servers (z. B. window/workDoneProgress/create) beantwortet der
// Client mit null; Anfragen und Benachrichtigungen gehen außerdem an
// OnServerMessage (im Lese-Thread, z. B. workspace/diagnostic/refresh, #398).
// Anfragen, die OnServerRequest übernimmt (z. B. workspace/applyEdit, #397),
// beantwortet der Empfänger später selbst mit Respond.
// Teilergebnisse (#616): Request mit AOnPartial schickt einen partialResultToken mit; $/progress zu diesem
// Token geht an AOnPartial (im Lese-Thread, vor der Antwort), nicht an OnServerMessage.
// Das Warten auf eine Antwort endet auch beim gemeinsamen Abbruchsignal
// (TAtlasShutdown, #493), damit beim Entladen kein Thread im Zeitlimit hängt.
// Für das Statusfeld (#591) merkt sich der Client die Antwortzeiten der
// letzten 50 Anfragen (AverageMs) und meldet das Ende der Verbindung über
// OnClosed (etwa wenn der Serverprozess beendet wurde).

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.JSON,
  System.Diagnostics,
  System.Generics.Collections;

type
  TLspSendProc = reference to procedure(const ABytes: TBytes);
  /// <summary>Anfrage oder Benachrichtigung des Servers; läuft im Lese-Thread, AParams gehört dem Client.</summary>
  TLspServerMessageProc = reference to procedure(const AMethod: string; const AParams: TJSONValue);
  /// <summary>Teilergebnis zu einer Anfrage (#616); läuft im Lese-Thread, AValue gehört dem Client.</summary>
  TLspPartialProc = reference to procedure(const AValue: TJSONValue);
  /// <summary>Anfrage des Servers (#397); läuft im Lese-Thread. True: Der Empfänger antwortet später mit
  /// Respond(AId, …), AId gehört dann ihm. False: Der Client antwortet mit null und gibt AId frei.</summary>
  TLspServerRequestFunc = reference to function(const AMethod: string; const AParams: TJSONValue;
    AId: TJSONValue): Boolean;

  ELspClientError = class(Exception);

  TLspClient = class
  public const
    /// <summary>So viele Antwortzeiten gehen in AverageMs ein (#591).</summary>
    TimeSamples = 50;
  private type
    TPending = class
    public
      Done: TEvent;
      Result: TJSONValue;
      Error: string;
      constructor Create;
      destructor Destroy; override;
    end;
  private
    FSend: TLspSendProc;
    FLock: TObject;
    FPending: TDictionary<Integer, TPending>;
    FPartials: TDictionary<string, TLspPartialProc>;
    FNextId: Integer;
    FNextPartial: Integer;
    FBuffer: TBytes;
    FClosed: Boolean;
    FOnServerMessage: TLspServerMessageProc;
    FOnServerRequest: TLspServerRequestFunc;
    FOnClosed: TProc;
    FTimes: array[0..TimeSamples - 1] of Int64;
    FTimeCount: Integer;
    FTimeNext: Integer;
    procedure SendText(const AText: string);
    /// <summary>$/cancelRequest für eine Anfrage, auf die der Client nicht mehr wartet.</summary>
    procedure CancelOnServer(AId: Integer);
    procedure HandleMessage(const AText: string);
    /// <summary>$/progress zu einem Token aus Request mit Teilergebnissen; False, wenn es keines ist.</summary>
    function HandlePartial(AMessage: TJSONObject): Boolean;
    function TakeMessage(out AText: string): Boolean;
  public
    constructor Create(const ASend: TLspSendProc);
    destructor Destroy; override;
    /// <summary>Rahmt AText mit Content-Length.</summary>
    class function Frame(const AText: string): TBytes; static;
    /// <summary>
    /// Sendet eine Anfrage und wartet auf die Antwort. Übernimmt AParams.
    /// Liefert das Ergebnis (nil bei null), der Aufrufer gibt es frei.
    /// Löst ELspClientError bei Fehlerantwort, Zeitüberschreitung oder beendeter Verbindung aus.
    /// </summary>
    function Request(const AMethod: string; AParams: TJSONValue; ATimeoutMs: Cardinal): TJSONValue; overload;
    /// <summary>Wie oben mit Teilergebnissen (#616): AParams muss ein Objekt sein; es bekommt einen
    /// partialResultToken. AOnPartial läuft im Lese-Thread für jedes Teilergebnis vor der Antwort.</summary>
    function Request(const AMethod: string; AParams: TJSONObject; ATimeoutMs: Cardinal;
      const AOnPartial: TLspPartialProc): TJSONValue; overload;
    /// <summary>Sendet eine Benachrichtigung. Übernimmt AParams.</summary>
    procedure Notify(const AMethod: string; AParams: TJSONValue);
    /// <summary>Antwort auf eine Anfrage des Servers, die OnServerRequest übernommen hat; übernimmt AId und
    /// AResult (nil = null). Ohne Wirkung nach Close.</summary>
    procedure Respond(AId, AResult: TJSONValue);
    /// <summary>Empfangene Bytes vom Server; threadsicher.</summary>
    procedure Receive(const ABytes: TBytes; ACount: Integer);
    /// <summary>Verbindung beendet: Wartende Anfragen schlagen fehl, neue auch.</summary>
    procedure Close;
    /// <summary>Antwortzeit einer Anfrage merken; Request ruft das selbst (öffentlich für Tests).</summary>
    procedure AddResponseTime(AMilliseconds: Int64);
    /// <summary>Mittlere Antwortzeit der letzten TimeSamples Anfragen in ms; ASamples = deren Anzahl.</summary>
    function AverageMs(out ASamples: Integer): Double;
    property Closed: Boolean read FClosed;
    /// <summary>Einmal beim Schließen der Verbindung, im Thread des Schließenden (Lese-Thread bei
    /// beendetem Prozess).</summary>
    property OnClosed: TProc read FOnClosed write FOnClosed;
    /// <summary>Vor dem ersten Receive setzen.</summary>
    property OnServerMessage: TLspServerMessageProc read FOnServerMessage write FOnServerMessage;
    /// <summary>Vor dem ersten Receive setzen.</summary>
    property OnServerRequest: TLspServerRequestFunc read FOnServerRequest write FOnServerRequest;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Shutdown;

const
  HeaderEnd: array[0..3] of Byte = (13, 10, 13, 10);

{ TLspClient.TPending }

constructor TLspClient.TPending.Create;
begin
  inherited Create;
  Done := TEvent.Create(nil, True, False, '');
end;

destructor TLspClient.TPending.Destroy;
begin
  Result.Free;
  Done.Free;
  inherited;
end;

{ TLspClient }

constructor TLspClient.Create(const ASend: TLspSendProc);
begin
  inherited Create;
  FSend := ASend;
  FLock := TObject.Create;
  FPending := TDictionary<Integer, TPending>.Create;
  FPartials := TDictionary<string, TLspPartialProc>.Create;
end;

destructor TLspClient.Destroy;
begin
  Close;
  FPartials.Free;
  FPending.Free;
  FLock.Free;
  inherited;
end;

class function TLspClient.Frame(const AText: string): TBytes;
var
  Body: TBytes;
  Header: TBytes;
begin
  Body := TEncoding.UTF8.GetBytes(AText);
  Header := TEncoding.UTF8.GetBytes(Format('Content-Length: %d'#13#10#13#10, [Length(Body)]));
  Result := Header + Body;
end;

procedure TLspClient.SendText(const AText: string);
begin
  FSend(Frame(AText));
end;

function TLspClient.Request(const AMethod: string; AParams: TJSONValue; ATimeoutMs: Cardinal): TJSONValue;
var
  Message: TJSONObject;
  Pending: TPending;
  Id: Integer;
  Text: string;
  Watch: TStopwatch;
begin
  Pending := TPending.Create;
  try
    TMonitor.Enter(FLock);
    try
      if FClosed then
      begin
        AParams.Free;
        raise ELspClientError.Create('Verbindung zum Server ist beendet');
      end;
      Inc(FNextId);
      Id := FNextId;
      FPending.Add(Id, Pending);
    finally
      TMonitor.Exit(FLock);
    end;
    Message := TJSONObject.Create;
    try
      Message.AddPair('jsonrpc', '2.0');
      Message.AddPair('id', TJSONNumber.Create(Id));
      Message.AddPair('method', AMethod);
      if AParams <> nil then
        Message.AddPair('params', AParams);
      Text := Message.ToJSON;
    finally
      Message.Free;
    end;
    try
      Watch := TStopwatch.StartNew;
      SendText(Text);
      case TAtlasShutdown.WaitFor(Pending.Done, ATimeoutMs) of
        wrSignaled:
          // Beendete Verbindung ist keine Antwort und zählt nicht.
          if not FClosed then
            AddResponseTime(Watch.ElapsedMilliseconds);
        wrAbandoned:
          raise ELspClientError.CreateFmt('Keine Antwort auf %s: Atlas wird beendet', [AMethod]);
      else
        begin
          AddResponseTime(ATimeoutMs);
          // Sonst rechnet der Server weiter, während schon die nächste Anfrage kommt (CPU-Last).
          CancelOnServer(Id);
          raise ELspClientError.CreateFmt('Keine Antwort auf %s innerhalb von %d ms', [AMethod, ATimeoutMs]);
        end;
      end;
    finally
      TMonitor.Enter(FLock);
      try
        FPending.Remove(Id);
      finally
        TMonitor.Exit(FLock);
      end;
    end;
    if Pending.Error <> '' then
      raise ELspClientError.Create(Pending.Error);
    Result := Pending.Result;
    Pending.Result := nil;
  finally
    Pending.Free;
  end;
end;

function TLspClient.Request(const AMethod: string; AParams: TJSONObject; ATimeoutMs: Cardinal;
  const AOnPartial: TLspPartialProc): TJSONValue;
var
  Token: string;
begin
  if not Assigned(AOnPartial) then
    Exit(Request(AMethod, AParams, ATimeoutMs));
  TMonitor.Enter(FLock);
  try
    Inc(FNextPartial);
    Token := 'atlas-partial-' + IntToStr(FNextPartial);
    FPartials.Add(Token, AOnPartial);
  finally
    TMonitor.Exit(FLock);
  end;
  try
    AParams.AddPair('partialResultToken', Token);
    Result := Request(AMethod, AParams, ATimeoutMs);
  finally
    TMonitor.Enter(FLock);
    try
      FPartials.Remove(Token);
    finally
      TMonitor.Exit(FLock);
    end;
  end;
end;

procedure TLspClient.Notify(const AMethod: string; AParams: TJSONValue);
var
  Message: TJSONObject;
  Text: string;
begin
  Message := TJSONObject.Create;
  try
    Message.AddPair('jsonrpc', '2.0');
    Message.AddPair('method', AMethod);
    if AParams <> nil then
      Message.AddPair('params', AParams);
    Text := Message.ToJSON;
  finally
    Message.Free;
  end;
  if not FClosed then
    SendText(Text);
end;

procedure TLspClient.CancelOnServer(AId: Integer);
begin
  try
    Notify('$/cancelRequest', TJSONObject.Create.AddPair('id', TJSONNumber.Create(AId)));
  except
    // Abbruch ist ein Hinweis an den Server; scheitert das Senden, bleibt es bei der Zeitüberschreitung.
    on Exception do
      ;
  end;
end;

function TLspClient.HandlePartial(AMessage: TJSONObject): Boolean;
var
  Params, Token: TJSONValue;
  Partial: TLspPartialProc;
begin
  Result := False;
  if AMessage.GetValue<string>('method', '') <> '$/progress' then
    Exit;
  Params := AMessage.GetValue('params');
  if not (Params is TJSONObject) then
    Exit;
  Token := TJSONObject(Params).GetValue('token');
  if not (Token is TJSONString) then
    Exit;
  TMonitor.Enter(FLock);
  try
    if not FPartials.TryGetValue(TJSONString(Token).Value, Partial) then
      Exit;
  finally
    TMonitor.Exit(FLock);
  end;
  Result := True;
  try
    Partial(TJSONObject(Params).GetValue('value'));
  except
    // Ein Fehler im Empfänger darf den Lese-Thread nicht beenden.
    on Exception do
      ;
  end;
end;

procedure TLspClient.HandleMessage(const AText: string);
var
  Value: TJSONValue;
  Message: TJSONObject;
  IdValue, ResultValue, ErrorValue: TJSONValue;
  Pending: TPending;
  Reply: TJSONObject;
  ReplyText: string;
  IdCopy: TJSONValue;
  Taken: Boolean;
begin
  Value := TJSONObject.ParseJSONValue(AText);
  try
    if not (Value is TJSONObject) then
      Exit;
    Message := TJSONObject(Value);
    IdValue := Message.GetValue('id');
    if (IdValue = nil) and HandlePartial(Message) then
      Exit;
    if Message.GetValue('method') <> nil then
    begin
      if Assigned(FOnServerMessage) then
        try
          FOnServerMessage(Message.GetValue<string>('method', ''), Message.GetValue('params'));
        except
          // Ein Fehler im Empfänger darf den Lese-Thread nicht beenden.
          on Exception do
            ;
        end;
      if IdValue = nil then
        Exit;
      // Anfrage, die ein Empfänger selbst beantwortet.
      if Assigned(FOnServerRequest) then
      begin
        IdCopy := TJSONValue(IdValue.Clone);
        try
          Taken := FOnServerRequest(Message.GetValue<string>('method', ''), Message.GetValue('params'), IdCopy);
        except
          on Exception do
            Taken := False;
        end;
        if Taken then
          Exit;
        IdCopy.Free;
      end;
      // Sonst mit null beantworten, damit der Server nicht wartet.
      Reply := TJSONObject.Create;
      try
        Reply.AddPair('jsonrpc', '2.0');
        Reply.AddPair('id', TJSONValue(IdValue.Clone));
        Reply.AddPair('result', TJSONNull.Create);
        ReplyText := Reply.ToJSON;
      finally
        Reply.Free;
      end;
      SendText(ReplyText);
      Exit;
    end;
    if not (IdValue is TJSONNumber) then
      Exit;
    TMonitor.Enter(FLock);
    try
      if not FPending.TryGetValue(TJSONNumber(IdValue).AsInt, Pending) then
        Exit;
      ErrorValue := Message.GetValue('error');
      if ErrorValue is TJSONObject then
        Pending.Error := TJSONObject(ErrorValue).GetValue<string>('message', 'Fehlerantwort des Servers')
      else
      begin
        ResultValue := Message.GetValue('result');
        if (ResultValue <> nil) and not (ResultValue is TJSONNull) then
          Pending.Result := TJSONValue(ResultValue.Clone);
      end;
      Pending.Done.SetEvent;
    finally
      TMonitor.Exit(FLock);
    end;
  finally
    Value.Free;
  end;
end;

procedure TLspClient.Respond(AId, AResult: TJSONValue);
var
  Reply: TJSONObject;
  Text: string;
begin
  Reply := TJSONObject.Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    Reply.AddPair('id', AId);
    if AResult = nil then
      Reply.AddPair('result', TJSONNull.Create)
    else
      Reply.AddPair('result', AResult);
    Text := Reply.ToJSON;
  finally
    Reply.Free;
  end;
  if not FClosed then
    SendText(Text);
end;

function TLspClient.TakeMessage(out AText: string): Boolean;
var
  HeaderLength, Index, Len, BodyLength: Integer;
  Header, Line: string;
begin
  Result := False;
  HeaderLength := -1;
  for Index := 0 to Length(FBuffer) - 4 do
    if CompareMem(@FBuffer[Index], @HeaderEnd[0], 4) then
    begin
      HeaderLength := Index;
      Break;
    end;
  if HeaderLength < 0 then
    Exit;
  Header := TEncoding.UTF8.GetString(FBuffer, 0, HeaderLength);
  BodyLength := -1;
  for Line in Header.Split([#13#10]) do
    if Line.StartsWith('Content-Length:', True) then
      BodyLength := StrToIntDef(Line.Substring(Length('Content-Length:')).Trim, -1);
  Len := HeaderLength + 4;
  if BodyLength < 0 then
  begin
    // Kaputter Kopf: verwerfen und weitermachen.
    Delete(FBuffer, 0, Len);
    Exit(True);
  end;
  if Length(FBuffer) < Len + BodyLength then
    Exit;
  AText := TEncoding.UTF8.GetString(FBuffer, Len, BodyLength);
  Delete(FBuffer, 0, Len + BodyLength);
  Result := True;
end;

procedure TLspClient.Receive(const ABytes: TBytes; ACount: Integer);
var
  Messages: TList<string>;
  Text: string;
  Start: Integer;
begin
  Messages := TList<string>.Create;
  try
    TMonitor.Enter(FLock);
    try
      Start := Length(FBuffer);
      SetLength(FBuffer, Start + ACount);
      if ACount > 0 then
        Move(ABytes[0], FBuffer[Start], ACount);
      Text := '';
      while TakeMessage(Text) do
        if Text <> '' then
        begin
          Messages.Add(Text);
          Text := '';
        end;
    finally
      TMonitor.Exit(FLock);
    end;
    // Außerhalb der Sperre: HandleMessage sperrt selbst und sendet ggf.
    for Text in Messages do
      HandleMessage(Text);
  finally
    Messages.Free;
  end;
end;

procedure TLspClient.Close;
var
  Pending: TPending;
  WasOpen: Boolean;
  Handler: TProc;
begin
  TMonitor.Enter(FLock);
  try
    WasOpen := not FClosed;
    FClosed := True;
    for Pending in FPending.Values do
    begin
      Pending.Error := 'Verbindung zum Server ist beendet';
      Pending.Done.SetEvent;
    end;
    Handler := FOnClosed;
  finally
    TMonitor.Exit(FLock);
  end;
  if WasOpen and Assigned(Handler) then
    try
      Handler();
    except
      // Ein Fehler im Empfänger darf das Schließen nicht abbrechen.
      on Exception do
        ;
    end;
end;

procedure TLspClient.AddResponseTime(AMilliseconds: Int64);
begin
  TMonitor.Enter(FLock);
  try
    FTimes[FTimeNext] := AMilliseconds;
    FTimeNext := (FTimeNext + 1) mod TimeSamples;
    if FTimeCount < TimeSamples then
      Inc(FTimeCount);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TLspClient.AverageMs(out ASamples: Integer): Double;
var
  Index: Integer;
  Sum: Int64;
begin
  TMonitor.Enter(FLock);
  try
    ASamples := FTimeCount;
    Sum := 0;
    for Index := 0 to FTimeCount - 1 do
      Inc(Sum, FTimes[Index]);
  finally
    TMonitor.Exit(FLock);
  end;
  if ASamples = 0 then
    Result := 0
  else
    Result := Sum / ASamples;
end;

end.
