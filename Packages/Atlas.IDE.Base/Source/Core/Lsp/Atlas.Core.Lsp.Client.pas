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
// OnClosed (etwa wenn der Serverprozess beendet wurde). workspace/diagnostic
// zählt nicht mit: Der Server hält es absichtlich bis zu 10 s offen
// (Long-Polling), das Statusfeld meldete sonst dauerhaft "langsam"
// (Rückmeldung 15.10.2026).
// Ende der Verbindung (Bericht H5): CloseInfo nennt die zuletzt gesendete
// Anfrage, die beim Ende noch offenen und, wenn der Transport sie über
// CloseWith mitgibt, Exit-Code, Laufzeit und Zeilen auf stderr des Servers.

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
  /// <summary>Keine Antwort innerhalb des Zeitlimits.</summary>
  ELspTimeoutError = class(ELspClientError);
  /// <summary>Der Aufrufer hat die Anfrage abgebrochen.</summary>
  ELspCancelledError = class(ELspClientError);

  /// <summary>Wie die Verbindung endete (Bericht H5); Exit-Angaben setzt der Transport über CloseWith.</summary>
  TLspCloseInfo = record
    /// <summary>Exit-Code des Serverprozesses bekannt?</summary>
    ExitKnown: Boolean;
    ExitCode: Cardinal;
    /// <summary>Laufzeit des Serverprozesses in ms; 0 = unbekannt.</summary>
    RuntimeMs: Int64;
    /// <summary>Zeilen, die der Server in diesem Lauf auf stderr schrieb.</summary>
    ErrorLines: Integer;
    /// <summary>Zuletzt gesendete Anfrage ohne Long-Polling; setzt der Client.</summary>
    LastMethod: string;
    /// <summary>Beim Ende noch offene Anfragen ohne Long-Polling; setzt der Client.</summary>
    OpenMethods: TArray<string>;
  end;

  /// <summary>Ringpuffer der Antwortzeiten der letzten Samples Anfragen (#591); nicht threadsicher, TLspClient
  /// sperrt.</summary>
  TLspResponseTimes = record
  public const
    Samples = 50;
  private
    FTimes: array[0..Samples - 1] of Int64;
    FCount: Integer;
    FNext: Integer;
  public
    /// <summary>Nimmt eine Antwortzeit auf; die älteste fällt heraus, wenn Samples erreicht sind.</summary>
    procedure Add(AMilliseconds: Int64);
    /// <summary>Mittelwert der gemerkten Zeiten, 0 ohne Zeiten; ASamples ist ihre Anzahl.</summary>
    function Average(out ASamples: Integer): Double;
  end;

  TLspClient = class
  public const
    /// <summary>Obergrenzen der Rahmung wie im Server (Atlas.Common.JsonRpc.StreamTransport): Kopf 8 KB,
    /// Inhalt 256 MB (Code-Review D-10). Darüber gilt die Verbindung als kaputt.</summary>
    MaxHeaderLength = 8 * 1024;
    MaxContentLength = 256 * 1024 * 1024;
  private type
    TPending = class
    public
      Method: string;
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
    FLastMethod: string;
    FCloseInfo: TLspCloseInfo;
    FOnServerMessage: TLspServerMessageProc;
    FOnServerRequest: TLspServerRequestFunc;
    FOnClosed: TProc;
    FTimes: TLspResponseTimes;
    procedure SendText(const AText: string);
    /// <summary>$/cancelRequest für eine Anfrage, auf die der Client nicht mehr wartet.</summary>
    procedure CancelOnServer(AId: Integer);
    procedure HandleMessage(const AText: string);
    /// <summary>$/progress zu einem Token aus Request mit Teilergebnissen; False, wenn es keines ist.</summary>
    function HandlePartial(AMessage: TJSONObject): Boolean;
    function TakeMessage(out AText: string): Boolean;
    function DoRequest(const AMethod: string; AParams: TJSONValue; ATimeoutMs: Cardinal;
      const ACancelled: TFunc<Boolean>): TJSONValue;
  public const
    /// <summary>So oft fragt Request mit Abbruch nach, ob abgebrochen wurde.</summary>
    CancelPollMs = 100;
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
    /// <summary>Wie oben, abbrechbar (#1351): Meldet ACancelled True, schickt der Client $/cancelRequest und löst
    /// ELspClientError aus, ohne auf die Antwort zu warten.</summary>
    function RequestCancellable(const AMethod: string; AParams: TJSONValue; ATimeoutMs: Cardinal;
      const ACancelled: TFunc<Boolean>): TJSONValue;
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
    /// <summary>Wie Close, mit den Angaben des Transports zum Ende des Servers (Exit-Code, Laufzeit, stderr).
    /// Nur das erste Close zählt.</summary>
    procedure CloseWith(const AInfo: TLspCloseInfo);
    /// <summary>Angaben zum Ende der Verbindung; leer, solange sie offen ist.</summary>
    function CloseInfo: TLspCloseInfo;
    /// <summary>Antwortzeit einer Anfrage merken; Request ruft das selbst (öffentlich für Tests).</summary>
    procedure AddResponseTime(AMilliseconds: Int64);
    /// <summary>Mittlere Antwortzeit der letzten TLspResponseTimes.Samples Anfragen in ms; ASamples = deren Anzahl.</summary>
    function AverageMs(out ASamples: Integer): Double;
    /// <summary>Geht die Antwortzeit von AMethod in AverageMs ein? Nicht bei Long-Polling.</summary>
    class function CountsResponseTime(const AMethod: string): Boolean; static;
    property Closed: Boolean read FClosed;
    /// <summary>Einmal beim Schließen der Verbindung, im Thread des Schließenden (Lese-Thread bei
    /// beendetem Prozess).</summary>
    property OnClosed: TProc read FOnClosed write FOnClosed;
    /// <summary>Vor dem ersten Receive setzen.</summary>
    property OnServerMessage: TLspServerMessageProc read FOnServerMessage write FOnServerMessage;
    /// <summary>Vor dem ersten Receive setzen.</summary>
    property OnServerRequest: TLspServerRequestFunc read FOnServerRequest write FOnServerRequest;
  end;

  /// <summary>Laufender Sprachserver mit seinem Client; die Freigabe beendet den Prozess. Den Prozess
  /// startet die Kompositionswurzel (TLspServerProcess, A-09).</summary>
  IAtlasLspServer = interface
    ['{EAC5AE10-77D6-42EA-8AD8-CF869F7B79EC}']
    function Running: Boolean;
    function GetClient: TLspClient;
    property Client: TLspClient read GetClient;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Diagnostics.PluginTimings;

const
  HeaderEnd: array[0..3] of Byte = (13, 10, 13, 10);

type
  /// <summary>Ablauf einer Anfrage aus TLspClient.DoRequest: anmelden, senden, auf die Antwort warten,
  /// auswerten und abmelden.</summary>
  TLspRequestRun = class
  private
    FClient: TLspClient;
    FPending: TLspClient.TPending;
    FId: Integer;
    FMethod: string;
    FTimeoutMs: Cardinal;
    FCancelled: TFunc<Boolean>;
    procedure Register(AParams: TJSONValue);
    procedure Unregister;
    function WaitSliced: TWaitResult;
    function Wait: TWaitResult;
    procedure Check(AWait: TWaitResult; AElapsedMs: Int64);
  public
    constructor Create(AClient: TLspClient; const AMethod: string; ATimeoutMs: Cardinal;
      const ACancelled: TFunc<Boolean>);
    destructor Destroy; override;
    /// <summary>Sendet die Anfrage mit AParams (gehen in jedem Fall in den Besitz des Ablaufs über) und liefert
    /// das Ergebnis; ELspClientError bei Fehlerantwort, Zeitlimit, Abbruch oder beendeter Verbindung.</summary>
    function Execute(AParams: TJSONValue): TJSONValue;
  end;

/// <summary>JSON-RPC-Nachricht mit jsonrpc, id (nur wenn AId > 0), method und params (AParams geht in die
/// Nachricht über).</summary>
function MessageText(AId: Integer; const AMethod: string; AParams: TJSONValue): string;
var
  Message: TJSONObject;
begin
  Message := TJSONObject.Create;
  try
    Message.AddPair('jsonrpc', '2.0');
    if AId > 0 then
    begin
      Message.AddPair('id', TJSONNumber.Create(AId));
    end;
    Message.AddPair('method', AMethod);
    if AParams <> nil then
    begin
      Message.AddPair('params', AParams);
    end;
    Result := Message.ToJSON;
  finally
    Message.Free;
  end;
end;

/// <summary>Antwort mit result null auf die Anfrage mit AId (AId bleibt beim Aufrufer).</summary>
function NullReplyText(AId: TJSONValue): string;
var
  Reply: TJSONObject;
begin
  Reply := TJSONObject.Create;
  try
    Reply.AddPair('jsonrpc', '2.0');
    Reply.AddPair('id', TJSONValue(AId.Clone));
    Reply.AddPair('result', TJSONNull.Create);
    Result := Reply.ToJSON;
  finally
    Reply.Free;
  end;
end;

/// <summary>Gibt die Anfrage AMessage an OnServerRequest; True, wenn der Empfänger sie übernommen hat und
/// später selbst antwortet.</summary>
function OfferServerRequest(AClient: TLspClient; AMessage: TJSONObject; AIdValue: TJSONValue): Boolean;
var
  IdCopy: TJSONValue;
begin
  Result := False;
  if not Assigned(AClient.FOnServerRequest) then
  begin
    Exit;
  end;
  IdCopy := TJSONValue(AIdValue.Clone);
  try
    Result := AClient.FOnServerRequest(AMessage.GetValue<string>('method', ''), AMessage.GetValue('params'), IdCopy);
  except
    on Exception do
      Result := False;
  end;
  if not Result then
  begin
    IdCopy.Free;
  end;
end;

/// <summary>Anfrage oder Benachrichtigung des Servers: Teilergebnis, OnServerMessage und bei Anfragen
/// OnServerRequest oder eine Antwort mit null, damit der Server nicht wartet.</summary>
procedure HandleServerMessage(AClient: TLspClient; AMessage: TJSONObject; AIdValue: TJSONValue);
begin
  if (AIdValue = nil) and AClient.HandlePartial(AMessage) then
  begin
    Exit;
  end;
  if Assigned(AClient.FOnServerMessage) then
    try
      AClient.FOnServerMessage(AMessage.GetValue<string>('method', ''), AMessage.GetValue('params'));
    except
      // Ein Fehler im Empfänger darf den Lese-Thread nicht beenden.
      on Exception do
        ;
    end;
  if (AIdValue <> nil) and not OfferServerRequest(AClient, AMessage, AIdValue) then
  begin
    AClient.SendText(NullReplyText(AIdValue));
  end;
end;

/// <summary>Antwort auf die eigene Anfrage AId: Ergebnis oder Fehler an die wartende Anfrage geben.</summary>
procedure AnswerPending(AClient: TLspClient; AMessage: TJSONObject; AId: Integer);
var
  Pending: TLspClient.TPending;
  ResultValue, ErrorValue: TJSONValue;
begin
  TMonitor.Enter(AClient.FLock);
  try
    if not AClient.FPending.TryGetValue(AId, Pending) then
    begin
      Exit;
    end;
    ErrorValue := AMessage.GetValue('error');
    ResultValue := AMessage.GetValue('result');
    if ErrorValue is TJSONObject then
    begin
      Pending.Error := TJSONObject(ErrorValue).GetValue<string>('message', 'Fehlerantwort des Servers');
    end
    else if (ResultValue <> nil) and not (ResultValue is TJSONNull) then
    begin
      Pending.Result := TJSONValue(ResultValue.Clone);
    end;
    Pending.Done.SetEvent;
  finally
    TMonitor.Exit(AClient.FLock);
  end;
end;

/// <summary>Index des Kopfendes (CR LF CR LF) in den ersten MaxHeaderLength Bytes, -1 ohne.</summary>
function HeaderEndIndex(const ABuffer: TBytes): Integer;
var
  Index, Last: Integer;
begin
  Result := -1;
  // Nur im möglichen Kopf suchen, nicht im ganzen Puffer (Code-Review D-10).
  Last := Length(ABuffer) - Length(HeaderEnd);
  if Last > TLspClient.MaxHeaderLength then
  begin
    Last := TLspClient.MaxHeaderLength;
  end;
  Index := 0;
  while (Result < 0) and (Index <= Last) do
  begin
    if CompareMem(@ABuffer[Index], @HeaderEnd[0], Length(HeaderEnd)) then
    begin
      Result := Index;
    end;
    Inc(Index);
  end;
end;

/// <summary>Kein Kopfende in den ersten MaxHeaderLength Bytes: kein LSP, Verbindung aufgeben statt den
/// Speicher zu füllen.</summary>
procedure RejectEndlessHeader(var ABuffer: TBytes);
begin
  if Length(ABuffer) >= TLspClient.MaxHeaderLength + Length(HeaderEnd) then
  begin
    ABuffer := nil;
    raise ELspClientError.Create('Servernachricht ohne Kopfende');
  end;
end;

/// <summary>Nachricht über MaxContentLength: Verbindung aufgeben statt den Speicher zu füllen.</summary>
procedure RejectOversizedBody(var ABuffer: TBytes; ABodyLength: Integer);
begin
  if ABodyLength > TLspClient.MaxContentLength then
  begin
    ABuffer := nil;
    raise ELspClientError.CreateFmt('Servernachricht mit %d Bytes über der Grenze von %d Bytes',
      [ABodyLength, TLspClient.MaxContentLength]);
  end;
end;

/// <summary>Wert von Content-Length im Kopf, -1 ohne oder bei ungültiger Zahl.</summary>
function ContentLengthOf(const AHeader: string): Integer;
var
  Line: string;
begin
  Result := -1;
  for Line in AHeader.Split([#13#10]) do
  begin
    if Line.StartsWith('Content-Length:', True) then
    begin
      Result := StrToIntDef(Line.Substring(Length('Content-Length:')).Trim, -1);
    end;
  end;
end;

{ TLspRequestRun }

constructor TLspRequestRun.Create(AClient: TLspClient; const AMethod: string; ATimeoutMs: Cardinal;
  const ACancelled: TFunc<Boolean>);
begin
  inherited Create;
  FClient := AClient;
  FMethod := AMethod;
  FTimeoutMs := ATimeoutMs;
  FCancelled := ACancelled;
  FPending := TLspClient.TPending.Create;
  FPending.Method := AMethod;
end;

destructor TLspRequestRun.Destroy;
begin
  FPending.Free;
  inherited;
end;

procedure TLspRequestRun.Register(AParams: TJSONValue);
begin
  TMonitor.Enter(FClient.FLock);
  try
    if FClient.FClosed then
    begin
      AParams.Free;
      raise ELspClientError.Create('Verbindung zum Server ist beendet');
    end;
    Inc(FClient.FNextId);
    FId := FClient.FNextId;
    FClient.FPending.Add(FId, FPending);
    if TLspClient.CountsResponseTime(FMethod) then
    begin
      FClient.FLastMethod := FMethod;
    end;
  finally
    TMonitor.Exit(FClient.FLock);
  end;
end;

procedure TLspRequestRun.Unregister;
begin
  TMonitor.Enter(FClient.FLock);
  try
    FClient.FPending.Remove(FId);
  finally
    TMonitor.Exit(FClient.FLock);
  end;
end;

function TLspRequestRun.WaitSliced: TWaitResult;
var
  Slice, Waited: Cardinal;
begin
  // In Scheiben warten, damit „Abbrechen“ nicht bis zum Zeitlimit hängt.
  Waited := 0;
  repeat
    Slice := TLspClient.CancelPollMs;
    if FTimeoutMs - Waited < Slice then
    begin
      Slice := FTimeoutMs - Waited;
    end;
    Result := TAtlasShutdown.WaitFor(FPending.Done, Slice);
    Inc(Waited, Slice);
    if (Result = wrTimeout) and FCancelled() then
    begin
      FClient.CancelOnServer(FId);
      raise ELspCancelledError.CreateFmt('%s abgebrochen', [FMethod]);
    end;
  until (Result <> wrTimeout) or (Waited >= FTimeoutMs);
end;

function TLspRequestRun.Wait: TWaitResult;
begin
  if Assigned(FCancelled) then
  begin
    Result := WaitSliced;
  end
  else
  begin
    Result := TAtlasShutdown.WaitFor(FPending.Done, FTimeoutMs);
  end;
end;

procedure TLspRequestRun.Check(AWait: TWaitResult; AElapsedMs: Int64);
var
  Counts: Boolean;
begin
  Counts := TLspClient.CountsResponseTime(FMethod);
  case AWait of
    wrSignaled:
      // Beendete Verbindung ist keine Antwort und zählt nicht.
      if not FClient.FClosed and Counts then
      begin
        FClient.AddResponseTime(AElapsedMs);
      end;
    wrAbandoned:
      raise ELspClientError.CreateFmt('Keine Antwort auf %s: Atlas wird beendet', [FMethod]);
  else
    begin
      if Counts then
      begin
        FClient.AddResponseTime(FTimeoutMs);
      end;
      // Sonst rechnet der Server weiter, während schon die nächste Anfrage kommt (CPU-Last).
      FClient.CancelOnServer(FId);
      raise ELspTimeoutError.CreateFmt('Keine Antwort auf %s innerhalb von %d ms', [FMethod, FTimeoutMs]);
    end;
  end;
end;

function TLspRequestRun.Execute(AParams: TJSONValue): TJSONValue;
var
  Text: string;
  Watch: TStopwatch;
begin
  Register(AParams);
  Text := MessageText(FId, FMethod, AParams);
  try
    Watch := TStopwatch.StartNew;
    FClient.SendText(Text);
    Check(Wait, Watch.ElapsedMilliseconds);
  finally
    Unregister;
  end;
  if FPending.Error <> '' then
  begin
    raise ELspClientError.Create(FPending.Error);
  end;
  Result := FPending.Result;
  FPending.Result := nil;
end;

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
begin
  Result := RequestCancellable(AMethod, AParams, ATimeoutMs, nil);
end;

/// <summary>Name der Anfrage im Diagnose-Fenster: bei workspace/executeCommand mit dem Befehl
/// (2.0-stable: alle Serverbefehle standen in einer Zeile, ohne zu zeigen, welcher scheitert).</summary>
function RequestLabel(const AMethod: string; AParams: TJSONValue): string;
var
  mCommand: string;
begin
  Result := AMethod;
  if (AMethod = 'workspace/executeCommand') and (AParams is TJSONObject) and
    TJSONObject(AParams).TryGetValue<string>('command', mCommand) then
  begin
    Result := AMethod + ' ' + mCommand;
  end;
end;

function TLspClient.RequestCancellable(const AMethod: string; AParams: TJSONValue; ATimeoutMs: Cardinal;
  const ACancelled: TFunc<Boolean>): TJSONValue;
var
  mWatch: TStopwatch;
  mOutcome: TAtlasRequestOutcome;
  mLabel: string;
begin
  if not TAtlasPluginTimings.Enabled then
  begin
    Exit(DoRequest(AMethod, AParams, ATimeoutMs, ACancelled));
  end;
  // Diagnose-Fenster, Reiter „Server“: Dauer und Ausgang jeder Anfrage. Der Name vorher: DoRequest übernimmt
  // AParams.
  mLabel := RequestLabel(AMethod, AParams);
  mWatch := TStopwatch.StartNew;
  mOutcome := TAtlasRequestOutcome.Failed;
  try
    try
      Result := DoRequest(AMethod, AParams, ATimeoutMs, ACancelled);
      mOutcome := TAtlasRequestOutcome.Done;
    except
      on ELspTimeoutError do
      begin
        mOutcome := TAtlasRequestOutcome.TimedOut;
        raise;
      end;
      on ELspCancelledError do
      begin
        mOutcome := TAtlasRequestOutcome.Cancelled;
        raise;
      end;
    end;
  finally
    TAtlasPluginTimings.NoteRequest(mLabel, mWatch.Elapsed.TotalMilliseconds, mOutcome);
  end;
end;

function TLspClient.DoRequest(const AMethod: string; AParams: TJSONValue; ATimeoutMs: Cardinal;
  const ACancelled: TFunc<Boolean>): TJSONValue;
var
  Run: TLspRequestRun;
begin
  Run := TLspRequestRun.Create(Self, AMethod, ATimeoutMs, ACancelled);
  try
    Result := Run.Execute(AParams);
  finally
    Run.Free;
  end;
end;

function TLspClient.Request(const AMethod: string; AParams: TJSONObject; ATimeoutMs: Cardinal;
  const AOnPartial: TLspPartialProc): TJSONValue;
var
  Token: string;
begin
  if not Assigned(AOnPartial) then
  begin
    Exit(Request(AMethod, AParams, ATimeoutMs));
  end;
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
  Text: string;
begin
  Text := MessageText(0, AMethod, AParams);
  if not FClosed then
  begin
    SendText(Text);
  end;
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
  begin
    Exit;
  end;
  Params := AMessage.GetValue('params');
  if not (Params is TJSONObject) then
  begin
    Exit;
  end;
  Token := TJSONObject(Params).GetValue('token');
  if not (Token is TJSONString) then
  begin
    Exit;
  end;
  TMonitor.Enter(FLock);
  try
    if not FPartials.TryGetValue(TJSONString(Token).Value, Partial) then
    begin
      Exit;
    end;
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
  IdValue: TJSONValue;
begin
  Value := TJSONObject.ParseJSONValue(AText);
  try
    if Value is TJSONObject then
    begin
      Message := TJSONObject(Value);
      IdValue := Message.GetValue('id');
      if Message.GetValue('method') <> nil then
      begin
        HandleServerMessage(Self, Message, IdValue);
      end
      else if IdValue is TJSONNumber then
      begin
        AnswerPending(Self, Message, TJSONNumber(IdValue).AsInt);
      end;
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
    begin
      Reply.AddPair('result', TJSONNull.Create);
    end
    else
    begin
      Reply.AddPair('result', AResult);
    end;
    Text := Reply.ToJSON;
  finally
    Reply.Free;
  end;
  if not FClosed then
  begin
    SendText(Text);
  end;
end;

function TLspClient.TakeMessage(out AText: string): Boolean;
var
  HeaderLength, Len, BodyLength: Integer;
begin
  Result := False;
  HeaderLength := HeaderEndIndex(FBuffer);
  if HeaderLength < 0 then
  begin
    RejectEndlessHeader(FBuffer);
    Exit;
  end;
  BodyLength := ContentLengthOf(TEncoding.UTF8.GetString(FBuffer, 0, HeaderLength));
  Len := HeaderLength + Length(HeaderEnd);
  if BodyLength < 0 then
  begin
    // Kaputter Kopf: verwerfen und weitermachen.
    Delete(FBuffer, 0, Len);
    Exit(True);
  end;
  RejectOversizedBody(FBuffer, BodyLength);
  if Length(FBuffer) >= Len + BodyLength then
  begin
    AText := TEncoding.UTF8.GetString(FBuffer, Len, BodyLength);
    Delete(FBuffer, 0, Len + BodyLength);
    Result := True;
  end;
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
      begin
        Move(ABytes[0], FBuffer[Start], ACount);
      end;
      Text := '';
      while TakeMessage(Text) do
      begin
        if Text <> '' then
        begin
          Messages.Add(Text);
          Text := '';
        end;
      end;
    finally
      TMonitor.Exit(FLock);
    end;
    // Außerhalb der Sperre: HandleMessage sperrt selbst und sendet ggf.
    for Text in Messages do
    begin
      HandleMessage(Text);
    end;
  finally
    Messages.Free;
  end;
end;

procedure TLspClient.Close;
begin
  CloseWith(Default(TLspCloseInfo));
end;

procedure TLspClient.CloseWith(const AInfo: TLspCloseInfo);
var
  Pending: TPending;
  WasOpen: Boolean;
  Handler: TProc;
begin
  TMonitor.Enter(FLock);
  try
    WasOpen := not FClosed;
    FClosed := True;
    if WasOpen then
    begin
      FCloseInfo := AInfo;
      FCloseInfo.LastMethod := FLastMethod;
      FCloseInfo.OpenMethods := nil;
      for Pending in FPending.Values do
      begin
        if CountsResponseTime(Pending.Method) then
        begin
          FCloseInfo.OpenMethods := FCloseInfo.OpenMethods + [Pending.Method];
        end;
      end;
    end;
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

function TLspClient.CloseInfo: TLspCloseInfo;
begin
  TMonitor.Enter(FLock);
  try
    Result := FCloseInfo;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TLspClient.AddResponseTime(AMilliseconds: Int64);
begin
  TMonitor.Enter(FLock);
  try
    FTimes.Add(AMilliseconds);
  finally
    TMonitor.Exit(FLock);
  end;
end;

class function TLspClient.CountsResponseTime(const AMethod: string): Boolean;
begin
  Result := not SameText(AMethod, 'workspace/diagnostic');
end;

function TLspClient.AverageMs(out ASamples: Integer): Double;
begin
  TMonitor.Enter(FLock);
  try
    Result := FTimes.Average(ASamples);
  finally
    TMonitor.Exit(FLock);
  end;
end;

{ TLspResponseTimes }

procedure TLspResponseTimes.Add(AMilliseconds: Int64);
begin
  FTimes[FNext] := AMilliseconds;
  FNext := (FNext + 1) mod Samples;
  if FCount < Samples then
  begin
    Inc(FCount);
  end;
end;

function TLspResponseTimes.Average(out ASamples: Integer): Double;
var
  Index: Integer;
  Sum: Int64;
begin
  ASamples := FCount;
  Sum := 0;
  for Index := 0 to FCount - 1 do
  begin
    Inc(Sum, FTimes[Index]);
  end;
  Result := 0;
  if ASamples > 0 then
  begin
    Result := Sum / ASamples;
  end;
end;

end.
