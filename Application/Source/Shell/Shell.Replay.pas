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
// bis die Indizierung ruht ($/progress ohne offene Vorgänge für cSettleQuietMs,
// höchstens cSettleMaxMs).
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
    cSettleQuietMs = 1500;
    cSettleMaxMs = 120000;
    /// <summary>So lange wartet das Nachstellen höchstens auf die Antwort (ohne Zeitlimit im Fall).</summary>
    cAnswerMs = 60000;
    cExitReproduced = 1;
    cExitNotReproduced = 0;
    cExitUnreadable = 2;
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
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TReplayText = (Original, Isolated, Reproduced, NotReproduced, Unreadable, NoAnswer, NoError, Error);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TReplayText] of TAtlasText = (
    (De: 'mit den Projekten des Absturzes'; En: 'with the projects of the crash'),
    (De: 'isoliert'; En: 'isolated'),
    (De: 'reproduziert (%s): %s'; En: 'reproduced (%s): %s'),
    (De: 'nicht reproduziert (%s): %s'; En: 'not reproduced (%s): %s'),
    (De: 'Fall nicht lesbar: %s'; En: 'Case not readable: %s'),
    (De: 'keine Antwort'; En: 'no answer'),
    (De: 'Antwort ohne Fehler'; En: 'answer without error'),
    (De: 'Fehler %d: %s'; En: 'Error %d: %s'));

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
  while TThread.GetTickCount64 - mStart < TShellReplay.cSettleMaxMs do
  begin
    System.TMonitor.Enter(FLock);
    try
      mOpen := FOpenProgress;
      mLast := FLastProgress;
    finally
      System.TMonitor.Exit(FLock);
    end;
    if (mOpen <= 0) and (TThread.GetTickCount64 - mLast >= TShellReplay.cSettleQuietMs) then
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
  Result := (mId is TJSONString) and (mId.Value = cRequestId) and (AMessage.GetValue('method') = nil);
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

{ TReplayResult }

function TReplayResult.Text: string;
var
  mPlace: string;
begin
  if Original then
  begin
    mPlace := cTexts[TReplayText.Original].Text;
  end
  else
  begin
    mPlace := cTexts[TReplayText.Isolated].Text;
  end;
  case Outcome of
    TReplayOutcome.Reproduced:
      Result := cTexts[TReplayText.Reproduced].Fmt([mPlace, Detail]);
    TReplayOutcome.NotReproduced:
      Result := cTexts[TReplayText.NotReproduced].Fmt([mPlace, Detail]);
  else
    Result := cTexts[TReplayText.Unreadable].Fmt([Detail]);
  end;
end;

{ TShellReplay }

function NewMessage(const AId: string; const AMethod: string; AParams: TJSONValue): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', TJsonRpcMessages.cVersion);
  if AId <> '' then
  begin
    Result.AddPair('id', AId);
  end;
  Result.AddPair('method', AMethod);
  if AParams <> nil then
  begin
    Result.AddPair('params', AParams);
  end;
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
    begin
      if (mObject.Pairs[mIndex].JsonValue is TJSONString) and
        not (mObject.Pairs[mIndex].JsonValue is TJSONNumber) and
        SameText(mObject.Pairs[mIndex].JsonValue.Value, AFrom) then
      begin
        mName := mObject.Pairs[mIndex].JsonString.Value;
        mObject.RemovePair(mName).Free;
        mObject.AddPair(mName, ATo);
      end
      else
      begin
        ReplaceStrings(mObject.Pairs[mIndex].JsonValue, AFrom, ATo);
      end;
    end;
  end
  else if AValue is TJSONArray then
  begin
    for mIndex := 0 to TJSONArray(AValue).Count - 1 do
    begin
      ReplaceStrings(TJSONArray(AValue).Items[mIndex], AFrom, ATo);
    end;
  end;
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
  begin
    mCapabilities := TJSONObject(AOriginal).GetValue('capabilities');
  end;
  if mCapabilities <> nil then
  begin
    Result.AddPair('capabilities', TJSONValue(mCapabilities.Clone));
  end
  else
  begin
    Result.AddPair('capabilities', TJSONObject.Create);
  end;
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
    ADetail := cTexts[TReplayText.NoAnswer].Text;
    Exit;
  end;
  mError := AResponse.GetValue('error');
  if not (mError is TJSONObject) then
  begin
    ADetail := cTexts[TReplayText.NoError].Text;
    Exit;
  end;
  mCode := 0;
  mValue := TJSONObject(mError).GetValue('code');
  if mValue is TJSONNumber then
  begin
    mCode := TJSONNumber(mValue).AsInt;
  end;
  mText := '';
  mValue := TJSONObject(mError).GetValue('message');
  if mValue is TJSONString then
  begin
    mText := mValue.Value;
  end;
  ADetail := cTexts[TReplayText.Error].Fmt([mCode, mText]);
  if ACase.Kind = TCrashCaseKind.Timeout then
  begin
    Result := mCode = TJsonRpcErrorCode.cRequestCancelled;
  end
  else
  begin
    Result := (mCode = TJsonRpcErrorCode.cInternalError) and
      ((ACase.ExceptionClass = '') or StartsText(ACase.ExceptionClass + ':', mText));
  end;
end;

type
  /// <summary>Was das Nachstellen eines Falls vorbereitet: Ordner, Einstellungen, Dokument und Anfrage.</summary>
  TReplaySetup = record
    Folder: string;
    SettingsFile: string;
    Uri: string;
    /// <summary>Im Originalordner des Falls statt in einer Kopie.</summary>
    Original: Boolean;
    Initialize: TJSONValue;
    Params: TJSONValue;
  end;

/// <summary>JSON aus AText; nil bei '' oder ungültigem Text.</summary>
function ParseOrNilText(const AText: string): TJSONValue;
begin
  Result := nil;
  if AText <> '' then
  begin
    Result := TCrashCases.ParseOrNil(AText);
  end;
end;

function NewReplayFolder: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'Atlas' + PathDelim + 'replay' + PathDelim +
    FormatDateTime('yyyymmdd"-"hhnnsszzz', Now) + '-' + IntToStr(Random(1000000)));
end;

/// <summary>Schreibt die Einstellungsdatei AName des Falls nach AFolder; False, wenn der Fall keine hat.</summary>
function WriteCaseSetting(const ACase: TCrashCase; const AName, AFolder: string): Boolean;
var
  mSetting: TCrashCaseSetting;
begin
  Result := False;
  for mSetting in ACase.Settings do
  begin
    if SameText(mSetting.Name, AName) then
    begin
      TFile.WriteAllText(TPath.Combine(AFolder, AName), mSetting.Text, TEncoding.UTF8);
      Result := True;
    end;
  end;
end;

/// <summary>settings.json des Falls (ohne: leer) in AFolder; liefert den Pfad.</summary>
function WriteSettingsFile(const ACase: TCrashCase; const AFolder: string): string;
begin
  Result := TPath.Combine(AFolder, 'settings.json');
  if not WriteCaseSetting(ACase, 'settings.json', AFolder) then
  begin
    TFile.WriteAllText(Result, '{}', TEncoding.UTF8);
  end;
end;

/// <summary>Eigener Ordner mit Schnappschuss und atlas.json des Falls; Uri und Params zeigen danach auf die Kopie.
/// </summary>
procedure IsolateCase(const ACase: TCrashCase; var ASetup: TReplaySetup);
var
  mFileName: string;
begin
  WriteCaseSetting(ACase, 'atlas.json', ASetup.Folder);
  mFileName := ACase.SnapshotName;
  if mFileName = '' then
  begin
    mFileName := TCrashCases.cBufferName;
  end;
  mFileName := TPath.Combine(ASetup.Folder, mFileName);
  if ACase.HasText then
  begin
    TFile.WriteAllText(mFileName, ACase.Text, TEncoding.UTF8);
  end;
  if ASetup.Uri = '' then
  begin
    Exit;
  end;
  if ASetup.Params <> nil then
  begin
    ReplaceStrings(ASetup.Params, ASetup.Uri, TDocumentUris.FromPath(mFileName));
  end;
  ASetup.Uri := TDocumentUris.FromPath(mFileName);
end;

function DidOpenMessage(const AUri, AText: string): TJSONObject;
var
  mDocument: TJSONObject;
begin
  mDocument := TJSONObject.Create;
  mDocument.AddPair('uri', AUri);
  mDocument.AddPair('languageId', 'pascal');
  mDocument.AddPair('version', TJSONNumber.Create(1));
  mDocument.AddPair('text', AText);
  Result := NewMessage('', 'textDocument/didOpen', TJSONObject.Create(TJSONPair.Create('textDocument', mDocument)));
end;

/// <summary>Die Nachrichten des Nachstellens; ASetup.Params geht in die Anfrage über (danach nil).</summary>
function ReplayMessages(const ACase: TCrashCase; var ASetup: TReplaySetup; out ARequestIndex: Integer):
  TArray<TJSONObject>;
var
  mInitialize: TJSONObject;
begin
  if ASetup.Original then
  begin
    mInitialize := OriginalInitialize(ASetup.Initialize);
  end
  else
  begin
    mInitialize := IsolatedInitialize(ASetup.Folder, ASetup.Initialize);
  end;
  Result := TArray<TJSONObject>.Create(NewMessage(cInitializeId, 'initialize', mInitialize),
    NewMessage('', 'initialized', TJSONObject.Create));
  if ACase.HasText and (ASetup.Uri <> '') then
  begin
    Result := Result + [DidOpenMessage(ASetup.Uri, ACase.Text)];
  end;
  ARequestIndex := Length(Result);
  Result := Result + [NewMessage(cRequestId, ACase.Method, ASetup.Params)];
  ASetup.Params := nil;
  Result := Result + [NewMessage(cShutdownId, 'shutdown', nil), NewMessage('', 'exit', nil)];
end;

/// <summary>Ergebnis aus der Antwort auf die Anfrage des Falls.</summary>
procedure Judge(const ACase: TCrashCase; ATransport: TReplayTransport; var AResult: TReplayResult);
var
  mAnswer: TJSONObject;
  mDetail: string;
begin
  mAnswer := ATransport.TakeAnswer;
  try
    AResult.Outcome := TReplayOutcome.NotReproduced;
    if TShellReplay.Reproduces(ACase, mAnswer, mDetail) then
    begin
      AResult.Outcome := TReplayOutcome.Reproduced;
    end;
    AResult.Detail := mDetail;
  finally
    mAnswer.Free;
  end;
end;

procedure DeleteReplayFolder(const AFolder: string);
begin
  try
    TDirectory.Delete(AFolder, True);
  except
    // Noch gesperrt (Index-Threads): bleibt im Temp-Ordner liegen.
    on Exception do
      ;
  end;
end;

class function TShellReplay.Run(const ACase: TCrashCase; APlace: TReplayPlace; const ALogger: ILogger;
  const AServer: TReplayServer): TReplayResult;
var
  mSetup: TReplaySetup;
  mTransport: TReplayTransport;
  mTransportRef: IJsonRpcTransport;
  mLogger: ILogger;
  mRequestIndex: Integer;
  mMessages: TArray<TJSONObject>;
begin
  Result := Default(TReplayResult);
  Result.Outcome := TReplayOutcome.Unreadable;
  mLogger := ALogger;
  if mLogger = nil then
  begin
    mLogger := TLogger.Create;
  end;
  mSetup := Default(TReplaySetup);
  mSetup.Initialize := ParseOrNilText(ACase.Initialize);
  mSetup.Params := ParseOrNilText(ACase.Params);
  mSetup.Folder := NewReplayFolder;
  try
    TDirectory.CreateDirectory(mSetup.Folder);
    mSetup.SettingsFile := WriteSettingsFile(ACase, mSetup.Folder);
    mSetup.Original := (APlace = TReplayPlace.Automatic) and (mSetup.Initialize is TJSONObject) and
      (ACase.FileName <> '') and TFile.Exists(ACase.FileName);
    Result.Original := mSetup.Original;
    mSetup.Uri := ACase.Uri;
    if not mSetup.Original then
    begin
      IsolateCase(ACase, mSetup);
    end;
    mMessages := ReplayMessages(ACase, mSetup, mRequestIndex);
    mTransport := TReplayTransport.Create(mMessages, mRequestIndex, cAnswerMs + 2 * ACase.TimeoutMs);
    mTransportRef := mTransport;
    AServer(mTransportRef, mLogger, mSetup.SettingsFile);
    Judge(ACase, mTransport, Result);
  finally
    mSetup.Params.Free;
    mSetup.Initialize.Free;
    DeleteReplayFolder(mSetup.Folder);
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
      Result := cExitReproduced;
    TReplayOutcome.NotReproduced:
      Result := cExitNotReproduced;
  else
    Result := cExitUnreadable;
  end;
end;

initialization
  TAtlasTextTables.Add('Shell.Replay', cTexts);

end.
