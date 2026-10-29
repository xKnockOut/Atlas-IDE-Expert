unit Shell.Replay;

// Host-Rolle Shell: Absturzfall nachstellen (AtlasServer --replay
// <anfrage.json>, #1355). Ein Server läuft im eigenen Prozess gegen einen
// Transport, der die Nachrichten des Falls einspielt (den vollständigen Server
// TServerComposition legt Shell.ReplayServer an, Tests einen eigenen):
//   initialize, initialized, didOpen mit dem Schnappschuss, die Anfrage des
//   Falls, nach ihrer Antwort shutdown und exit.
// Ort der Datei:
// - Original (Vorgabe, wenn die Datei des Falls noch existiert): dieselbe Uri
//   und dieselben Parameter von initialize wie beim Absturz (Projekte und
//   Ordner auf diesem Rechner); der Puffer kommt aus dem Schnappschuss.
// - Isoliert (sonst, und immer für die Testunits aus Tools/New-CrashTest.ps1):
//   Schnappschuss und atlas.json in einem eigenen Ordner unter %TEMP%, die
//   Uri der Anfrage zeigt dorthin, initialize nennt nur diesen Ordner.
// settings.json kommt in beiden Fällen aus dem Fall (Zugangsdaten sind dort
// schon entfernt), nicht vom Benutzer. Vor der Anfrage wartet der Transport,
// bis die Indizierung ruht ($/progress ohne offene Vorgänge für SettleQuietMs,
// höchstens SettleMaxMs).
// Ergebnis: „reproduziert“, wenn die Antwort wieder ein interner Fehler mit
// derselben Ausnahmeklasse ist (beim Watchdog-Fall: wieder RequestCancelled
// wegen des Zeitlimits), sonst „nicht reproduziert“. Der Server sichert beim
// Nachstellen keine eigenen Fälle und überspringt nichts.
// Ausgabe nur über den Logger (stderr, Shell.ReplayServer), nie auf stdout.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Logging.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Diagnostics.CrashCase;

type
{$SCOPEDENUMS ON}
  TReplayOutcome = (Reproduced, NotReproduced, Unreadable);
  TReplayPlace = (Automatic, Isolated);
{$SCOPEDENUMS OFF}

  /// <summary>Lässt einen Server gegen ATransport laufen, bis die Eingabe endet; settings.json aus ASettingsFile,
  /// ohne eigene Absturzfälle.</summary>
  TReplayServer = reference to procedure(const ATransport: IJsonRpcTransport; const ALogger: ILogger;
    const ASettingsFile: string);

  TReplayResult = record
    Outcome: TReplayOutcome;
    /// <summary>Antwort des Servers bzw. Grund, kurz.</summary>
    Detail: string;
    /// <summary>Lief der Fall mit der Uri und den Projekten des Absturzes?</summary>
    Original: Boolean;
    /// <summary>„reproduziert: …“ bzw. „nicht reproduziert: …“.</summary>
    function Text: string;
  end;

  TShellReplay = class
  public const
    SettleQuietMs = 1500;
    SettleMaxMs = 120000;
    /// <summary>So lange wartet das Nachstellen höchstens auf die Antwort (ohne Zeitlimit im Fall).</summary>
    AnswerMs = 60000;
    ExitReproduced = 1;
    ExitNotReproduced = 0;
    ExitUnreadable = 2;
  public
    /// <summary>Spielt ACase mit AServer nach; ALogger bekommt die Meldungen des Servers (nil = keine).</summary>
    class function Run(const ACase: TCrashCase; APlace: TReplayPlace; const ALogger: ILogger;
      const AServer: TReplayServer): TReplayResult; overload; static;
    /// <summary>Liest anfrage.json und spielt den Fall nach.</summary>
    class function Run(const AFileName: string; const ALogger: ILogger; const AServer: TReplayServer): TReplayResult;
      overload; static;
    /// <summary>Exit-Code der Kommandozeile zum Ergebnis.</summary>
    class function ExitCodeOf(const AResult: TReplayResult): Integer; static;
    /// <summary>Ist AResponse die Antwort, die den Absturz von ACase wiederholt?</summary>
    class function Reproduces(const ACase: TCrashCase; const AResponse: TJSONObject; out ADetail: string): Boolean;
      static;
  end;

implementation

uses
  System.Classes,
  System.SyncObjs,
  System.IOUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Messages,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Logging.Providers.Logger;

const
  cRequestId = 'atlas-replay';
  cInitializeId = 'atlas-replay-initialize';
  cShutdownId = 'atlas-replay-shutdown';

type
  /// <summary>Spielt die Nachrichten des Falls ein und fängt die Antwort auf die Anfrage ab.</summary>
  TReplayTransport = class(TInterfacedObject, IJsonRpcTransport)
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
    /// <summary>Kopie der Antwort; nil ohne.</summary>
    function TakeAnswer: TJSONObject;
  end;

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
    FMessages.Add(mMessage);
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
  while TThread.GetTickCount64 - mStart < TShellReplay.SettleMaxMs do
  begin
    System.TMonitor.Enter(FLock);
    try
      mOpen := FOpenProgress;
      mLast := FLastProgress;
    finally
      System.TMonitor.Exit(FLock);
    end;
    if (mOpen <= 0) and (TThread.GetTickCount64 - mLast >= TShellReplay.SettleQuietMs) then
      Exit;
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
    raise EJsonRpcTransportClosed.Create('Nachstellen beendet');
  if mIndex = FRequestIndex then
    Settle;
  // Nach der Anfrage erst weiter, wenn sie beantwortet ist (oder die Zeit abläuft): shutdown käme sonst zu früh.
  if mIndex = FRequestIndex + 1 then
    FAnswered.WaitFor(FAnswerMs);
  Result := TJSONObject(FMessages[mIndex].Clone);
end;

procedure TReplayTransport.WriteMessage(const AMessage: TJSONObject);
var
  mId, mValue, mKind: TJSONValue;
begin
  if AMessage = nil then
    Exit;
  mId := AMessage.GetValue('id');
  if (mId is TJSONString) and (mId.Value = cRequestId) and (AMessage.GetValue('method') = nil) then
  begin
    System.TMonitor.Enter(FLock);
    try
      if FAnswer = nil then
        FAnswer := TJSONObject(AMessage.Clone);
    finally
      System.TMonitor.Exit(FLock);
    end;
    FAnswered.SetEvent;
    Exit;
  end;
  mValue := AMessage.GetValue('method');
  if (mValue is TJSONString) and (mValue.Value = '$/progress') then
  begin
    mKind := nil;
    mValue := AMessage.GetValue('params');
    if mValue is TJSONObject then
    begin
      mValue := TJSONObject(mValue).GetValue('value');
      if mValue is TJSONObject then
        mKind := TJSONObject(mValue).GetValue('kind');
    end;
    System.TMonitor.Enter(FLock);
    try
      FLastProgress := TThread.GetTickCount64;
      if mKind is TJSONString then
      begin
        if mKind.Value = 'begin' then
          Inc(FOpenProgress)
        else if mKind.Value = 'end' then
          Dec(FOpenProgress);
      end;
    finally
      System.TMonitor.Exit(FLock);
    end;
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

{ TReplayResult }

function TReplayResult.Text: string;
var
  mPlace: string;
begin
  if Original then
    mPlace := 'mit den Projekten des Absturzes'
  else
    mPlace := 'isoliert';
  case Outcome of
    TReplayOutcome.Reproduced:
      Result := 'reproduziert (' + mPlace + '): ' + Detail;
    TReplayOutcome.NotReproduced:
      Result := 'nicht reproduziert (' + mPlace + '): ' + Detail;
  else
    Result := 'Fall nicht lesbar: ' + Detail;
  end;
end;

{ TShellReplay }

function NewMessage(const AId: string; const AMethod: string; AParams: TJSONValue): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', TJsonRpcMessages.Version);
  if AId <> '' then
    Result.AddPair('id', AId);
  Result.AddPair('method', AMethod);
  if AParams <> nil then
    Result.AddPair('params', AParams);
end;

/// <summary>Ersetzt in AValue jede Zeichenkette AFrom durch ATo (Uri der Anfrage).</summary>
procedure ReplaceStrings(const AValue: TJSONValue; const AFrom, ATo: string);
var
  mIndex: Integer;
  mObject: TJSONObject;
  mName: string;
begin
  if AValue is TJSONObject then
  begin
    mObject := TJSONObject(AValue);
    for mIndex := mObject.Count - 1 downto 0 do
      if (mObject.Pairs[mIndex].JsonValue is TJSONString) and
        not (mObject.Pairs[mIndex].JsonValue is TJSONNumber) and
        SameText(mObject.Pairs[mIndex].JsonValue.Value, AFrom) then
      begin
        mName := mObject.Pairs[mIndex].JsonString.Value;
        mObject.RemovePair(mName).Free;
        mObject.AddPair(mName, ATo);
      end
      else
        ReplaceStrings(mObject.Pairs[mIndex].JsonValue, AFrom, ATo);
  end
  else if AValue is TJSONArray then
    for mIndex := 0 to TJSONArray(AValue).Count - 1 do
      ReplaceStrings(TJSONArray(AValue).Items[mIndex], AFrom, ATo);
end;

function IsolatedInitialize(const AFolder: string; const AOriginal: TJSONValue): TJSONObject;
var
  mFolders: TJSONArray;
  mFolder: TJSONObject;
  mCapabilities: TJSONValue;
begin
  Result := TJSONObject.Create;
  Result.AddPair('processId', TJSONNull.Create);
  Result.AddPair('rootUri', TDocumentUris.FromPath(AFolder));
  mFolders := TJSONArray.Create;
  mFolder := TJSONObject.Create;
  mFolder.AddPair('uri', TDocumentUris.FromPath(AFolder));
  mFolder.AddPair('name', 'replay');
  mFolders.AddElement(mFolder);
  Result.AddPair('workspaceFolders', mFolders);
  // Fähigkeiten des Clients wie beim Absturz (Pull-Diagnosen, Fortschritt, Markdown), ohne seine Projekte.
  mCapabilities := nil;
  if AOriginal is TJSONObject then
    mCapabilities := TJSONObject(AOriginal).GetValue('capabilities');
  if mCapabilities <> nil then
    Result.AddPair('capabilities', TJSONValue(mCapabilities.Clone))
  else
    Result.AddPair('capabilities', TJSONObject.Create);
end;

function OriginalInitialize(const AOriginal: TJSONValue): TJSONObject;
begin
  Result := TJSONObject(AOriginal.Clone);
  // Den Editor von damals gibt es nicht mehr: sonst beendete sich der Server sofort.
  Result.RemovePair('processId').Free;
  Result.AddPair('processId', TJSONNull.Create);
end;

class function TShellReplay.Reproduces(const ACase: TCrashCase; const AResponse: TJSONObject;
  out ADetail: string): Boolean;
var
  mError, mValue: TJSONValue;
  mCode: Integer;
  mText: string;
begin
  Result := False;
  if AResponse = nil then
  begin
    ADetail := 'keine Antwort';
    Exit;
  end;
  mError := AResponse.GetValue('error');
  if not (mError is TJSONObject) then
  begin
    ADetail := 'Antwort ohne Fehler';
    Exit;
  end;
  mCode := 0;
  mValue := TJSONObject(mError).GetValue('code');
  if mValue is TJSONNumber then
    mCode := TJSONNumber(mValue).AsInt;
  mText := '';
  mValue := TJSONObject(mError).GetValue('message');
  if mValue is TJSONString then
    mText := mValue.Value;
  ADetail := Format('Fehler %d: %s', [mCode, mText]);
  if ACase.Kind = TCrashCaseKind.Timeout then
    Result := mCode = TJsonRpcErrorCode.RequestCancelled
  else
    Result := (mCode = TJsonRpcErrorCode.InternalError) and
      ((ACase.ExceptionClass = '') or StartsText(ACase.ExceptionClass + ':', mText));
end;

class function TShellReplay.Run(const ACase: TCrashCase; APlace: TReplayPlace; const ALogger: ILogger;
  const AServer: TReplayServer): TReplayResult;
var
  mFolder, mUri, mSettingsFile, mFileName: string;
  mInitialize, mParams: TJSONValue;
  mSetting: TCrashCaseSetting;
  mMessages: TArray<TJSONObject>;
  mTransport: TReplayTransport;
  mTransportRef: IJsonRpcTransport;
  mDocument: TJSONObject;
  mAnswer: TJSONObject;
  mLogger: ILogger;
  mDetail: string;
  mRequestIndex: Integer;
begin
  Result := Default(TReplayResult);
  Result.Outcome := TReplayOutcome.Unreadable;
  mLogger := ALogger;
  if mLogger = nil then
    mLogger := TLogger.Create;
  mInitialize := nil;
  if ACase.Initialize <> '' then
    mInitialize := TCrashCases.ParseOrNil(ACase.Initialize);
  mParams := nil;
  if ACase.Params <> '' then
    mParams := TCrashCases.ParseOrNil(ACase.Params);
  mFolder := TPath.Combine(TPath.GetTempPath, 'Atlas' + PathDelim + 'replay' + PathDelim +
    FormatDateTime('yyyymmdd"-"hhnnsszzz', Now) + '-' + IntToStr(Random(1000000)));
  try
    TDirectory.CreateDirectory(mFolder);
    mSettingsFile := TPath.Combine(mFolder, 'settings.json');
    TFile.WriteAllText(mSettingsFile, '{}', TEncoding.UTF8);
    for mSetting in ACase.Settings do
      if SameText(mSetting.Name, 'settings.json') then
        TFile.WriteAllText(mSettingsFile, mSetting.Text, TEncoding.UTF8);
    Result.Original := (APlace = TReplayPlace.Automatic) and (mInitialize is TJSONObject) and
      (ACase.FileName <> '') and TFile.Exists(ACase.FileName);
    mUri := ACase.Uri;
    if not Result.Original then
    begin
      // Eigener Ordner mit Schnappschuss und atlas.json des Falls; die Anfrage zeigt auf die Kopie.
      for mSetting in ACase.Settings do
        if SameText(mSetting.Name, 'atlas.json') then
          TFile.WriteAllText(TPath.Combine(mFolder, 'atlas.json'), mSetting.Text, TEncoding.UTF8);
      mFileName := ACase.SnapshotName;
      if mFileName = '' then
        mFileName := TCrashCases.BufferName;
      mFileName := TPath.Combine(mFolder, mFileName);
      if ACase.HasText then
        TFile.WriteAllText(mFileName, ACase.Text, TEncoding.UTF8);
      if (mUri <> '') and (mParams <> nil) then
        ReplaceStrings(mParams, mUri, TDocumentUris.FromPath(mFileName));
      if mUri <> '' then
        mUri := TDocumentUris.FromPath(mFileName);
    end;
    mMessages := nil;
    if Result.Original then
      mMessages := mMessages + [NewMessage(cInitializeId, 'initialize', OriginalInitialize(mInitialize))]
    else
      mMessages := mMessages + [NewMessage(cInitializeId, 'initialize', IsolatedInitialize(mFolder, mInitialize))];
    mMessages := mMessages + [NewMessage('', 'initialized', TJSONObject.Create)];
    if ACase.HasText and (mUri <> '') then
    begin
      mDocument := TJSONObject.Create;
      mDocument.AddPair('uri', mUri);
      mDocument.AddPair('languageId', 'pascal');
      mDocument.AddPair('version', TJSONNumber.Create(1));
      mDocument.AddPair('text', ACase.Text);
      mMessages := mMessages + [NewMessage('', 'textDocument/didOpen',
        TJSONObject.Create(TJSONPair.Create('textDocument', mDocument)))];
    end;
    mRequestIndex := Length(mMessages);
    mMessages := mMessages + [NewMessage(cRequestId, ACase.Method, mParams)];
    mParams := nil;
    mMessages := mMessages + [NewMessage(cShutdownId, 'shutdown', nil), NewMessage('', 'exit', nil)];
    mTransport := TReplayTransport.Create(mMessages, mRequestIndex, AnswerMs + 2 * ACase.TimeoutMs);
    mTransportRef := mTransport;
    AServer(mTransportRef, mLogger, mSettingsFile);
    mAnswer := mTransport.TakeAnswer;
    try
      if Reproduces(ACase, mAnswer, mDetail) then
        Result.Outcome := TReplayOutcome.Reproduced
      else
        Result.Outcome := TReplayOutcome.NotReproduced;
      Result.Detail := mDetail;
    finally
      mAnswer.Free;
    end;
  finally
    mParams.Free;
    mInitialize.Free;
    try
      TDirectory.Delete(mFolder, True);
    except
      // Noch gesperrt (Index-Threads): bleibt im Temp-Ordner liegen.
      on Exception do
        ;
    end;
  end;
end;

class function TShellReplay.Run(const AFileName: string; const ALogger: ILogger;
  const AServer: TReplayServer): TReplayResult;
var
  mCase: TCrashCase;
  mError: string;
begin
  if not TCrashCases.Load(AFileName, mCase, mError) then
  begin
    Result := Default(TReplayResult);
    Result.Outcome := TReplayOutcome.Unreadable;
    Result.Detail := mError;
    Exit;
  end;
  Result := Run(mCase, TReplayPlace.Automatic, ALogger, AServer);
end;

class function TShellReplay.ExitCodeOf(const AResult: TReplayResult): Integer;
begin
  case AResult.Outcome of
    TReplayOutcome.Reproduced:
      Result := ExitReproduced;
    TReplayOutcome.NotReproduced:
      Result := ExitNotReproduced;
  else
    Result := ExitUnreadable;
  end;
end;

end.
