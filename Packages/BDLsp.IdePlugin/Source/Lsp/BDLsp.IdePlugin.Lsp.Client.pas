unit BDLsp.IdePlugin.Lsp.Client;

// Schlanker LSP-Client für das IDE-Plugin (ADR 0006): JSON-RPC mit
// Content-Length-Rahmung, Zuordnung der Antworten zu Anfragen und Warten mit
// Zeitlimit. Der Transport ist ausgelagert: Gesendet wird über ASend (fertig
// gerahmte Bytes), empfangene Bytes kommen über Receive herein, auch in
// beliebigen Stücken und aus einem anderen Thread.
// Anfragen des Servers (z. B. window/workDoneProgress/create) beantwortet der
// Client mit null; Benachrichtigungen ignoriert er.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.JSON,
  System.Generics.Collections;

type
  TLspSendProc = reference to procedure(const ABytes: TBytes);

  ELspClientError = class(Exception);

  TLspClient = class
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
    FNextId: Integer;
    FBuffer: TBytes;
    FClosed: Boolean;
    procedure SendText(const AText: string);
    procedure HandleMessage(const AText: string);
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
    function Request(const AMethod: string; AParams: TJSONValue; ATimeoutMs: Cardinal): TJSONValue;
    /// <summary>Sendet eine Benachrichtigung. Übernimmt AParams.</summary>
    procedure Notify(const AMethod: string; AParams: TJSONValue);
    /// <summary>Empfangene Bytes vom Server; threadsicher.</summary>
    procedure Receive(const ABytes: TBytes; ACount: Integer);
    /// <summary>Verbindung beendet: Wartende Anfragen schlagen fehl, neue auch.</summary>
    procedure Close;
    property Closed: Boolean read FClosed;
  end;

implementation

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
end;

destructor TLspClient.Destroy;
begin
  Close;
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
      SendText(Text);
      if Pending.Done.WaitFor(ATimeoutMs) <> wrSignaled then
        raise ELspClientError.CreateFmt('Keine Antwort auf %s innerhalb von %d ms', [AMethod, ATimeoutMs]);
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

procedure TLspClient.HandleMessage(const AText: string);
var
  Value: TJSONValue;
  Message: TJSONObject;
  IdValue, ResultValue, ErrorValue: TJSONValue;
  Pending: TPending;
  Reply: TJSONObject;
  ReplyText: string;
begin
  Value := TJSONObject.ParseJSONValue(AText);
  try
    if not (Value is TJSONObject) then
      Exit;
    Message := TJSONObject(Value);
    IdValue := Message.GetValue('id');
    if Message.GetValue('method') <> nil then
    begin
      // Anfrage des Servers: mit null beantworten, damit er nicht wartet.
      if IdValue <> nil then
      begin
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
      end;
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
begin
  TMonitor.Enter(FLock);
  try
    FClosed := True;
    for Pending in FPending.Values do
    begin
      Pending.Error := 'Verbindung zum Server ist beendet';
      Pending.Done.SetEvent;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

end.
