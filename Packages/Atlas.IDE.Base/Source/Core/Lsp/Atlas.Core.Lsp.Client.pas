unit Atlas.Core.Lsp.Client;

// Schlanker LSP-Client für das IDE-Plugin: JSON-RPC, Zuordnung der Antworten
// zu Anfragen und Warten mit Zeitlimit. Die Content-Length-Rahmung liegt in
// Atlas.Core.Lsp.Framing (TLspFrameReader). Der Transport ist ausgelagert: Gesendet wird über ASend (fertig
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
// Ende der Verbindung: CloseInfo nennt die zuletzt gesendete
// Anfrage, die beim Ende noch offenen und, wenn der Transport sie über
// CloseWith mitgibt, Exit-Code, Laufzeit und Zeilen auf stderr des Servers.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.JSON,
  System.Diagnostics,
  System.Generics.Collections,
  Atlas.Core.Lsp.Framing;

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

  /// <summary>Fehler des Clients (Rahmung, Fehlerantwort, Zeitlimit, Abbruch, beendete Verbindung).</summary>
  ELspClientError = Atlas.Core.Lsp.Framing.ELspClientError;
  /// <summary>Keine Antwort innerhalb des Zeitlimits.</summary>
  ELspTimeoutError = class(ELspClientError);
  /// <summary>Der Aufrufer hat die Anfrage abgebrochen.</summary>
  ELspCancelledError = class(ELspClientError);

  /// <summary>Wie die Verbindung endete; Exit-Angaben setzt der Transport über CloseWith.</summary>
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
    cSamples = 50;
  private
    FTimes: array[0..cSamples - 1] of Int64;
    FCount: Integer;
    FNext: Integer;
  public
    /// <summary>Nimmt eine Antwortzeit auf; die älteste fällt heraus, wenn Samples erreicht sind.</summary>
    procedure Add(AMilliseconds: Int64);
    /// <summary>Mittelwert der gemerkten Zeiten, 0 ohne Zeiten; ASamples ist ihre Anzahl.</summary>
    function Average(out ASamples: Integer): Double;
    /// <summary>Geht die Antwortzeit von AMethod in den Durchschnitt ein? Nicht bei Long-Polling.</summary>
    class function Counts(const AMethod: string): Boolean; static;
  end;

  TLspClient = class
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
    FReader: TLspFrameReader;
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
    function DoRequest(const AMethod: string; AParams: TJSONValue; ATimeoutMs: Cardinal;
      const ACancelled: TFunc<Boolean>): TJSONValue;
  public const
    /// <summary>So oft fragt Request mit Abbruch nach, ob abgebrochen wurde.</summary>
    cCancelPollMs = 100;
  public
    constructor Create(const ASend: TLspSendProc);
    destructor Destroy; override;
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
    /// <summary>Mittlere Antwortzeit der letzten TLspResponseTimes.cSamples Anfragen in ms; ASamples = deren
    /// Anzahl.</summary>
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

  /// <summary>Laufender Sprachserver mit seinem Client; die Freigabe beendet den Prozess. Den Prozess
  /// startet die Kompositionswurzel (TLspServerProcess).</summary>
  IAtlasLspServer = interface
    ['{EAC5AE10-77D6-42EA-8AD8-CF869F7B79EC}']
    function Running: Boolean;
    function GetClient: TLspClient;
    property Client: TLspClient read GetClient;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Diagnostics.PluginTimings,
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TClientText = (ErrorResponseFromTheServer, ConnectionToTheServerHas, Cancelled, NoAnswerToAtlasIs,
    NoAnswerToWithinMs);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TClientText] of string = (
    ('Fehlerantwort des Servers',
     'Verbindung zum Server ist beendet',
     '%s abgebrochen',
     'Keine Antwort auf %s: Atlas wird beendet',
     'Keine Antwort auf %s innerhalb von %d ms'),
    ('Error response from the server',
     'Connection to the server has ended',
     '%s cancelled',
     'No answer to %s: Atlas is shutting down',
     'No answer to %s within %d ms'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TClientText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

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
  mMessage: TJSONObject;
begin
  mMessage := TJSONObject.Create;
  try
    mMessage.AddPair('jsonrpc', '2.0');
    if AId > 0 then
    begin
      mMessage.AddPair('id', TJSONNumber.Create(AId));
    end;
    mMessage.AddPair('method', AMethod);
    if AParams <> nil then
    begin
      mMessage.AddPair('params', AParams);
    end;
    Result := mMessage.ToJSON;
  finally
    mMessage.Free;
  end;
end;

/// <summary>Antwort mit result null auf die Anfrage mit AId (AId bleibt beim Aufrufer).</summary>
function NullReplyText(AId: TJSONValue): string;
var
  mReply: TJSONObject;
begin
  mReply := TJSONObject.Create;
  try
    mReply.AddPair('jsonrpc', '2.0');
    mReply.AddPair('id', TJSONValue(AId.Clone));
    mReply.AddPair('result', TJSONNull.Create);
    Result := mReply.ToJSON;
  finally
    mReply.Free;
  end;
end;

/// <summary>Gibt die Anfrage AMessage an OnServerRequest; True, wenn der Empfänger sie übernommen hat und
/// später selbst antwortet.</summary>
function OfferServerRequest(AClient: TLspClient; AMessage: TJSONObject; AIdValue: TJSONValue): Boolean;
var
  mIdCopy: TJSONValue;
begin
  Result := False;
  if not Assigned(AClient.FOnServerRequest) then
  begin
    Exit;
  end;
  mIdCopy := TJSONValue(AIdValue.Clone);
  try
    Result := AClient.FOnServerRequest(AMessage.GetValue<string>('method', ''), AMessage.GetValue('params'), mIdCopy);
  except
    on Exception do
      Result := False;
  end;
  if not Result then
  begin
    mIdCopy.Free;
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
  mPending: TLspClient.TPending;
  mResultValue, mErrorValue: TJSONValue;
begin
  TMonitor.Enter(AClient.FLock);
  try
    if not AClient.FPending.TryGetValue(AId, mPending) then
    begin
      Exit;
    end;
    mErrorValue := AMessage.GetValue('error');
    mResultValue := AMessage.GetValue('result');
    if mErrorValue is TJSONObject then
    begin
      mPending.Error := TJSONObject(mErrorValue).GetValue<string>('message', UiText(TClientText.ErrorResponseFromTheServer));
    end
    else if (mResultValue <> nil) and not (mResultValue is TJSONNull) then
    begin
      mPending.Result := TJSONValue(mResultValue.Clone);
    end;
    mPending.Done.SetEvent;
  finally
    TMonitor.Exit(AClient.FLock);
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
      raise ELspClientError.Create(UiText(TClientText.ConnectionToTheServerHas));
    end;
    Inc(FClient.FNextId);
    FId := FClient.FNextId;
    FClient.FPending.Add(FId, FPending);
    if TLspResponseTimes.Counts(FMethod) then
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
  mSlice, mWaited: Cardinal;
begin
  // In Scheiben warten, damit „Abbrechen“ nicht bis zum Zeitlimit hängt.
  mWaited := 0;
  repeat
    mSlice := TLspClient.cCancelPollMs;
    if FTimeoutMs - mWaited < mSlice then
    begin
      mSlice := FTimeoutMs - mWaited;
    end;
    Result := TAtlasShutdown.WaitFor(FPending.Done, mSlice);
    Inc(mWaited, mSlice);
    if (Result = wrTimeout) and FCancelled() then
    begin
      FClient.CancelOnServer(FId);
      raise ELspCancelledError.CreateFmt(UiText(TClientText.Cancelled), [FMethod]);
    end;
  until (Result <> wrTimeout) or (mWaited >= FTimeoutMs);
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
  mCounts: Boolean;
begin
  mCounts := TLspResponseTimes.Counts(FMethod);
  case AWait of
    wrSignaled:
      // Beendete Verbindung ist keine Antwort und zählt nicht.
      if not FClient.FClosed and mCounts then
      begin
        FClient.AddResponseTime(AElapsedMs);
      end;
    wrAbandoned:
      raise ELspClientError.CreateFmt(UiText(TClientText.NoAnswerToAtlasIs), [FMethod]);
  else
    begin
      if mCounts then
      begin
        FClient.AddResponseTime(FTimeoutMs);
      end;
      // Sonst rechnet der Server weiter, während schon die nächste Anfrage kommt (CPU-Last).
      FClient.CancelOnServer(FId);
      raise ELspTimeoutError.CreateFmt(UiText(TClientText.NoAnswerToWithinMs), [FMethod, FTimeoutMs]);
    end;
  end;
end;

function TLspRequestRun.Execute(AParams: TJSONValue): TJSONValue;
var
  mText: string;
  mWatch: TStopwatch;
begin
  Register(AParams);
  mText := MessageText(FId, FMethod, AParams);
  try
    mWatch := TStopwatch.StartNew;
    FClient.SendText(mText);
    Check(Wait, mWatch.ElapsedMilliseconds);
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
  FReader := TLspFrameReader.Create;
end;

destructor TLspClient.Destroy;
begin
  Close;
  FReader.Free;
  FPartials.Free;
  FPending.Free;
  FLock.Free;
  inherited;
end;

procedure TLspClient.SendText(const AText: string);
begin
  FSend(TLspFrameReader.Frame(AText));
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

procedure TLspClient.HandleMessage(const AText: string);
var
  mValue: TJSONValue;
  mMessage: TJSONObject;
  mIdValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(AText);
  try
    if mValue is TJSONObject then
    begin
      mMessage := TJSONObject(mValue);
      mIdValue := mMessage.GetValue('id');
      if mMessage.GetValue('method') <> nil then
      begin
        HandleServerMessage(Self, mMessage, mIdValue);
      end
      else if mIdValue is TJSONNumber then
      begin
        AnswerPending(Self, mMessage, TJSONNumber(mIdValue).AsInt);
      end;
    end;
  finally
    mValue.Free;
  end;
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

function TLspClient.HandlePartial(AMessage: TJSONObject): Boolean;
var
  mParams, mToken: TJSONValue;
  mPartial: TLspPartialProc;
begin
  Result := False;
  if AMessage.GetValue<string>('method', '') <> '$/progress' then
  begin
    Exit;
  end;
  mParams := AMessage.GetValue('params');
  if not (mParams is TJSONObject) then
  begin
    Exit;
  end;
  mToken := TJSONObject(mParams).GetValue('token');
  if not (mToken is TJSONString) then
  begin
    Exit;
  end;
  TMonitor.Enter(FLock);
  try
    if not FPartials.TryGetValue(TJSONString(mToken).Value, mPartial) then
    begin
      Exit;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  Result := True;
  try
    mPartial(TJSONObject(mParams).GetValue('value'));
  except
    // Ein Fehler im Empfänger darf den Lese-Thread nicht beenden.
    on Exception do
      ;
  end;
end;


function TLspClient.DoRequest(const AMethod: string; AParams: TJSONValue; ATimeoutMs: Cardinal;
  const ACancelled: TFunc<Boolean>): TJSONValue;
var
  mRun: TLspRequestRun;
begin
  mRun := TLspRequestRun.Create(Self, AMethod, ATimeoutMs, ACancelled);
  try
    Result := mRun.Execute(AParams);
  finally
    mRun.Free;
  end;
end;


function TLspClient.Request(const AMethod: string; AParams: TJSONValue; ATimeoutMs: Cardinal): TJSONValue;
begin
  Result := RequestCancellable(AMethod, AParams, ATimeoutMs, nil);
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

function TLspClient.Request(const AMethod: string; AParams: TJSONObject; ATimeoutMs: Cardinal;
  const AOnPartial: TLspPartialProc): TJSONValue;
var
  mToken: string;
begin
  if not Assigned(AOnPartial) then
  begin
    Exit(Request(AMethod, AParams, ATimeoutMs));
  end;
  TMonitor.Enter(FLock);
  try
    Inc(FNextPartial);
    mToken := 'atlas-partial-' + IntToStr(FNextPartial);
    FPartials.Add(mToken, AOnPartial);
  finally
    TMonitor.Exit(FLock);
  end;
  try
    AParams.AddPair('partialResultToken', mToken);
    Result := Request(AMethod, AParams, ATimeoutMs);
  finally
    TMonitor.Enter(FLock);
    try
      FPartials.Remove(mToken);
    finally
      TMonitor.Exit(FLock);
    end;
  end;
end;

procedure TLspClient.Notify(const AMethod: string; AParams: TJSONValue);
var
  mText: string;
begin
  mText := MessageText(0, AMethod, AParams);
  if not FClosed then
  begin
    SendText(mText);
  end;
end;

procedure TLspClient.Respond(AId, AResult: TJSONValue);
var
  mReply: TJSONObject;
  mText: string;
begin
  mReply := TJSONObject.Create;
  try
    mReply.AddPair('jsonrpc', '2.0');
    mReply.AddPair('id', AId);
    if AResult = nil then
    begin
      mReply.AddPair('result', TJSONNull.Create);
    end
    else
    begin
      mReply.AddPair('result', AResult);
    end;
    mText := mReply.ToJSON;
  finally
    mReply.Free;
  end;
  if not FClosed then
  begin
    SendText(mText);
  end;
end;

procedure TLspClient.Receive(const ABytes: TBytes; ACount: Integer);
var
  mMessages: TList<string>;
  mText: string;
begin
  mMessages := TList<string>.Create;
  try
    TMonitor.Enter(FLock);
    try
      FReader.Append(ABytes, ACount);
      mText := '';
      while FReader.TakeMessage(mText) do
      begin
        if mText <> '' then
        begin
          mMessages.Add(mText);
          mText := '';
        end;
      end;
    finally
      TMonitor.Exit(FLock);
    end;
    // Außerhalb der Sperre: HandleMessage sperrt selbst und sendet ggf.
    for mText in mMessages do
    begin
      HandleMessage(mText);
    end;
  finally
    mMessages.Free;
  end;
end;

procedure TLspClient.Close;
begin
  CloseWith(Default(TLspCloseInfo));
end;

procedure TLspClient.CloseWith(const AInfo: TLspCloseInfo);
var
  mPending: TPending;
  mWasOpen: Boolean;
  mHandler: TProc;
begin
  TMonitor.Enter(FLock);
  try
    mWasOpen := not FClosed;
    FClosed := True;
    if mWasOpen then
    begin
      FCloseInfo := AInfo;
      FCloseInfo.LastMethod := FLastMethod;
      FCloseInfo.OpenMethods := nil;
      for mPending in FPending.Values do
      begin
        if TLspResponseTimes.Counts(mPending.Method) then
        begin
          FCloseInfo.OpenMethods := FCloseInfo.OpenMethods + [mPending.Method];
        end;
      end;
    end;
    for mPending in FPending.Values do
    begin
      mPending.Error := UiText(TClientText.ConnectionToTheServerHas);
      mPending.Done.SetEvent;
    end;
    mHandler := FOnClosed;
  finally
    TMonitor.Exit(FLock);
  end;
  if mWasOpen and Assigned(mHandler) then
    try
      mHandler();
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
  FNext := (FNext + 1) mod cSamples;
  if FCount < cSamples then
  begin
    Inc(FCount);
  end;
end;

function TLspResponseTimes.Average(out ASamples: Integer): Double;
var
  mIndex: Integer;
  mSum: Int64;
begin
  ASamples := FCount;
  mSum := 0;
  for mIndex := 0 to FCount - 1 do
  begin
    Inc(mSum, FTimes[mIndex]);
  end;
  Result := 0;
  if ASamples > 0 then
  begin
    Result := mSum / ASamples;
  end;
end;

class function TLspResponseTimes.Counts(const AMethod: string): Boolean;
begin
  Result := not SameText(AMethod, 'workspace/diagnostic');
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.Core.Lsp.Client', cTexts[TAtlasLanguage.German], cTexts[TAtlasLanguage.English]);

end.
