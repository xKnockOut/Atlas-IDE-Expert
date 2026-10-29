unit Shell.CrashCases;

// Host-Rolle Shell: Absturzfälle des Servers (#1355).
// - Fall sichern (server.crashCases): Bei einer unerwarteten Ausnahme in einer
//   Anfrage (Dispatcher, OnRequestFailed) und beim Abbruch durch den Watchdog
//   (OnExpired) legt RequestFailed bzw. TimedOut einen Fall unter
//   %LOCALAPPDATA%\Atlas\crash an (TCrashCases): Anfrage mit Parametern, die
//   letzten Nachrichten, Schnappschuss des Puffers bzw. der Datei, die
//   Einstellungen ohne Zugangsdaten, Aufrufstapel und wiederholen.cmd. Bei
//   EStackOverflow schreibt der vorher reservierte Thread (TCrashReserve).
//   Danach geht atlas/crashCase an den Client (Meldung im Plugin).
// - Sicherheitsnetz (server.crashSkip), zusätzlich zur Behebung, nicht statt
//   ihr: Der zweite Absturz derselben Anfrage an derselben unveränderten Datei
//   (TCrashSkips) lässt Guard diese Anfrage für diese Datei mit
//   „Übersprungen nach Absturz“ beantworten, bis sich die Datei ändert
//   (DocumentChanged) oder der Benutzer „Erneut versuchen“ wählt (Befehl
//   atlas.crash.retry). Beginn und Ende gehen als atlas/crashSkip an den Client
//   (Statusleiste, Prüffenster) und als Warnung mit Verweis auf den Fall ins
//   Log. Der Merker liegt als uebersprungen.json neben den Fällen und gilt
//   über einen Neustart hinweg; Announce meldet ihn dem neuen Client.
// - Kein Netzzugriff: Fälle bleiben lokal, bis der Benutzer sie weitergibt.
// - Testschalter ATLAS_CRASH_TEST (Umgebung): lässt eine Methode künstlich
//   abstürzen (mit „:overflow“ als echter Stapelüberlauf), für Handtests und
//   --replay.
// Fehler beim Sichern landen im Log und verhindern nie die Antwort.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.JsonRpc.RecentMessages,
  Atlas.Common.Diagnostics.CrashCase,
  Atlas.Common.Diagnostics.CrashSkip,
  Atlas.Common.Diagnostics.CrashReserve;

type
  /// <summary>Künstlicher Absturz des Testschalters TShellCrashCases.TestVariable.</summary>
  ECrashTest = class(Exception);

  /// <summary>Einstellungsdateien (Pfade) zur Datei AUri: settings.json und die atlas.json ihres Ordners.</summary>
  TShellCrashSettingsFunc = reference to function(const AUri: string): TArray<string>;
  /// <summary>Benachrichtigung an den Client; AParams geht über.</summary>
  TShellCrashNotify = reference to procedure(const AMethod: string; AParams: TJSONObject);

  TShellCrashCases = class
  public const
    CaseNotification = 'atlas/crashCase';
    SkipNotification = 'atlas/crashSkip';
    RetryCommand = 'atlas.crash.retry';
    SkipsFileName = 'uebersprungen.json';
    SkipMessage = 'Übersprungen nach Absturz';
    /// <summary>Testschalter (Umgebungsvariable): „textDocument/hover“ lässt jede Hover-Anfrage mit ECrashTest
    /// abstürzen, „textDocument/hover:overflow“ mit einem echten Stapelüberlauf.</summary>
    TestVariable = 'ATLAS_CRASH_TEST';
  private
    FRoot: string;
    FLogger: ILogger;
    FDocuments: IDocumentStore;
    FRecent: IJsonRpcRecentMessages;
    FSkips: TCrashSkips;
    FReserve: TCrashReserve;
    FEnabled: Boolean;
    FSkipEnabled: Boolean;
    FSettingsFiles: TShellCrashSettingsFunc;
    FInitialize: TFunc<string>;
    FNotify: TShellCrashNotify;
    FServerPath: string;
    FAtlasVersion: string;
    FClient: string;
    FTestMethod: string;
    FTestOverflow: Boolean;
    /// <summary>Überspringen nach Absturz für AMethod an AUri (Guard).</summary>
    procedure CheckSkip(const AMethod, AUri: string);
    /// <summary>Künstlicher Absturz des Testschalters.</summary>
    procedure TestCrash(const AMethod: string);
    function NewCase(AKind: TCrashCaseKind; const AMethod, AId, AParams: string): TCrashCase;
    /// <summary>Schreibt den Fall (bei AOverflow im reservierten Thread); '' bei einem Fehler.</summary>
    function Store(const ACase: TCrashCase; AOverflow: Boolean): string;
    function CurrentText(const AUri: string; out AText: string): Boolean;
    procedure SaveSkips;
    procedure SendCase(const ACase: TCrashCase; const AFolder: string; ASkipping: Boolean);
    procedure SendSkip(const AEntry: TCrashSkipEntry; AActive: Boolean);
    function SkipsFile: string;
  public
    /// <summary>ARoot: Ordner der Fälle ('' = DefaultRoot). ARecent: die letzten Nachrichten des Dispatchers.
    /// </summary>
    constructor Create(const ARoot: string; const ALogger: ILogger; const ADocuments: IDocumentStore;
      const ARecent: IJsonRpcRecentMessages);
    destructor Destroy; override;
    /// <summary>OnRequestFailed des Dispatchers; AStack: Aufrufstapel der Ausnahme ('' ohne).</summary>
    procedure RequestFailed(const AMethod: string; const AParams: TJSONValue; const AError: Exception;
      const AStack: string);
    /// <summary>OnExpired des Watchdogs.</summary>
    procedure TimedOut(const AId, AMethod: string; ATimeoutMs: Cardinal);
    /// <summary>RequestGuard des Dispatchers: EJsonRpcError „Übersprungen nach Absturz“ für eine gemerkte
    /// Anfrage an eine unveränderte Datei.</summary>
    procedure Guard(const AMethod: string; const AParams: TJSONValue);
    /// <summary>Inhalt von AUri geändert: Überspringen für diese Datei endet.</summary>
    procedure DocumentChanged(const AUri, AText: string);
    /// <summary>„Erneut versuchen“ für AUri ('' = alle); Zahl der beendeten Überspringen.</summary>
    function Retry(const AUri: string): Integer;
    /// <summary>Meldet dem Client, was gerade übersprungen wird (nach initialized).</summary>
    procedure Announce;
    /// <summary>Gerade übersprungene Anfragen.</summary>
    function Skipped: TArray<TCrashSkipEntry>;
    /// <summary>%LOCALAPPDATA%\Atlas\crash (unter Linux im Cache-Ordner des Benutzers).</summary>
    class function DefaultRoot: string; static;
    /// <summary>Text der Fehlerantwort beim Überspringen.</summary>
    class function SkipText(const AEntry: TCrashSkipEntry): string; static;
    property Root: string read FRoot;
    /// <summary>server.crashCases: Fälle sichern und melden.</summary>
    property Enabled: Boolean read FEnabled write FEnabled;
    /// <summary>server.crashSkip: Sicherheitsnetz Überspringen.</summary>
    property SkipEnabled: Boolean read FSkipEnabled write FSkipEnabled;
    property SettingsFiles: TShellCrashSettingsFunc read FSettingsFiles write FSettingsFiles;
    /// <summary>Parameter von initialize als JSON-Text.</summary>
    property Initialize: TFunc<string> read FInitialize write FInitialize;
    property Notify: TShellCrashNotify read FNotify write FNotify;
    property ServerPath: string read FServerPath write FServerPath;
    property AtlasVersion: string read FAtlasVersion write FAtlasVersion;
    /// <summary>clientInfo aus initialize, etwa „RAD Studio 37.0“.</summary>
    property Client: string read FClient write FClient;
    /// <summary>Testschalter: Methode, die künstlich abstürzt ('' = keine); Vorgabe aus TestVariable.</summary>
    property TestMethod: string read FTestMethod write FTestMethod;
    /// <summary>Testschalter: als echter Stapelüberlauf statt ECrashTest.</summary>
    property TestOverflow: Boolean read FTestOverflow write FTestOverflow;
  end;

implementation

uses
  System.IOUtils,
  System.StrUtils,
  Atlas.Common.Documents.Uris,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Diagnostics.StackGuard,
  Shell.Bootstrap,
  Shell.Platform;

function BuildCompilerText: string;
begin
  {$IFDEF FPC}
  Result := 'Free Pascal ' + {$I %FPCVERSION%};
  {$ELSE}
  Result := Format('Delphi %.1f', [CompilerVersion], TFormatSettings.Invariant);
  {$ENDIF}
end;

{ TShellCrashCases }

constructor TShellCrashCases.Create(const ARoot: string; const ALogger: ILogger; const ADocuments: IDocumentStore;
  const ARecent: IJsonRpcRecentMessages);
begin
  inherited Create;
  FRoot := ARoot;
  if FRoot = '' then
    FRoot := DefaultRoot;
  FLogger := ALogger;
  FDocuments := ADocuments;
  FRecent := ARecent;
  FEnabled := True;
  FSkipEnabled := True;
  FSkips := TCrashSkips.Create;
  try
    if TFile.Exists(SkipsFile) then
      FSkips.Load(TFile.ReadAllText(SkipsFile, TEncoding.UTF8));
  except
    on E: Exception do
      FLogger.Warning('Absturzfälle: Merker nicht lesbar, beginne leer: ' + E.ClassName);
  end;
  FReserve := TCrashReserve.Create;
  FTestMethod := GetEnvironmentVariable(TestVariable);
  FTestOverflow := EndsText(':overflow', FTestMethod);
  if FTestOverflow then
    FTestMethod := Copy(FTestMethod, 1, Length(FTestMethod) - Length(':overflow'));
  if FTestMethod <> '' then
    FLogger.Warning(Format('Testschalter %s gesetzt: %s stürzt künstlich ab', [TestVariable, FTestMethod]));
end;

destructor TShellCrashCases.Destroy;
begin
  FReserve.Free;
  FSkips.Free;
  inherited;
end;

class function TShellCrashCases.DefaultRoot: string;
begin
  // Wie die Index-Caches (TIndexCacheDirectory.DefaultRoot): Windows %LOCALAPPDATA%\Atlas.
  Result := TPath.Combine(TPath.Combine(TPath.GetCachePath, 'Atlas'), 'crash');
end;

class function TShellCrashCases.SkipText(const AEntry: TCrashSkipEntry): string;
begin
  Result := Format('%s: %s ist an dieser Datei %d-mal abgestürzt (%s)', [SkipMessage, AEntry.Method,
    AEntry.Crashes, AEntry.ExceptionClass]);
  if AEntry.CaseFolder <> '' then
    Result := Result + '; Fall ' + AEntry.CaseFolder;
end;

function TShellCrashCases.SkipsFile: string;
begin
  Result := TPath.Combine(FRoot, SkipsFileName);
end;

function TShellCrashCases.CurrentText(const AUri: string; out AText: string): Boolean;
var
  mDocument: ITextDocument;
begin
  AText := '';
  if (FDocuments <> nil) and FDocuments.TryGet(AUri, mDocument) then
  begin
    AText := mDocument.Text;
    Exit(True);
  end;
  Result := StartsText('file:', AUri) and TShellBootstrap.ReadSourceText(TDocumentUris.ToPath(AUri), AText);
end;

function TShellCrashCases.NewCase(AKind: TCrashCaseKind; const AMethod, AId, AParams: string): TCrashCase;
var
  mParams: TJSONValue;
  mFile: string;
  mText: string;
begin
  Result := TCrashCase.Empty;
  Result.Kind := AKind;
  Result.Time := Now;
  Result.ProcessId := TShellPlatform.CurrentProcessId;
  Result.Method := AMethod;
  Result.Id := AId;
  Result.Params := AParams;
  Result.AtlasVersion := FAtlasVersion;
  Result.BuildCompiler := BuildCompilerText;
  Result.Client := FClient;
  Result.ServerPath := FServerPath;
  if FRecent <> nil then
    Result.Recent := FRecent.Last(TJsonRpcRecentMessages.ReportCount);
  if Assigned(FInitialize) then
    Result.Initialize := FInitialize();
  mParams := nil;
  if AParams <> '' then
    mParams := TCrashCases.ParseOrNil(AParams);
  try
    if TCrashCases.DocumentOf(mParams, Result.Uri, Result.Line) then
    begin
      if StartsText('file:', Result.Uri) then
        Result.FileName := TDocumentUris.ToPath(Result.Uri);
      Result.HasText := CurrentText(Result.Uri, mText);
      if Result.HasText then
        Result.Text := mText;
    end;
  finally
    mParams.Free;
  end;
  if Assigned(FSettingsFiles) then
    for mFile in FSettingsFiles(Result.Uri) do
      if (mFile <> '') and TFile.Exists(mFile) then
        try
          Result.Settings := Result.Settings + [TCrashCaseSetting.Create(ExtractFileName(mFile),
            TFile.ReadAllText(mFile, TEncoding.UTF8))];
        except
          // Gesperrt oder unlesbar: der Fall ohne diese Datei.
          on E: Exception do
            FLogger.Warning('Absturzfall: Einstellungen nicht lesbar (' + ExtractFileName(mFile) + ')');
        end;
end;

function TShellCrashCases.Store(const ACase: TCrashCase; AOverflow: Boolean): string;
var
  mFolder, mFailure: string;
  mCase: TCrashCase;
  mRoot: string;
begin
  Result := '';
  mFolder := '';
  mFailure := '';
  try
    if AOverflow then
    begin
      // Nicht auf dem eben erschöpften Stapel: im beim Start reservierten Thread mit eigener Speicherreserve.
      mCase := ACase;
      mRoot := FRoot;
      if not FReserve.Run(
        procedure
        begin
          mFolder := TCrashCases.Write(mRoot, mCase);
        end, mFailure) then
        mFolder := '';
    end
    else
      mFolder := TCrashCases.Write(FRoot, ACase);
  except
    on E: Exception do
      mFailure := E.ClassName + ': ' + E.Message;
  end;
  if mFolder = '' then
  begin
    FLogger.Error('Absturzfall nicht gesichert: ' + mFailure);
    Exit;
  end;
  Result := mFolder;
  FLogger.Warning(Format('Absturzfall gesichert: %s; %s', [ACase.Summary, mFolder]));
end;

procedure TShellCrashCases.SendCase(const ACase: TCrashCase; const AFolder: string; ASkipping: Boolean);
var
  mParams: TJSONObject;
begin
  if not Assigned(FNotify) then
    Exit;
  mParams := TJSONObject.Create;
  mParams.AddPair('summary', ACase.Summary);
  mParams.AddPair('folder', AFolder);
  mParams.AddPair('method', ACase.Method);
  if ACase.Kind = TCrashCaseKind.Timeout then
    mParams.AddPair('kind', 'timeout')
  else
    mParams.AddPair('kind', 'exception');
  mParams.AddPair('file', ACase.FileName);
  mParams.AddPair('uri', ACase.Uri);
  mParams.AddPair('line', TJSONNumber.Create(ACase.Line));
  mParams.AddPair('exception', ACase.ExceptionClass);
  mParams.AddPair('message', TCrashCases.WithoutUserInfo(ACase.ExceptionMessage));
  mParams.AddPair('version', ACase.AtlasVersion);
  mParams.AddPair('skipping', TJSONBool.Create(ASkipping));
  try
    FNotify(CaseNotification, mParams);
  except
    on E: Exception do
      FLogger.Warning('Absturzfall: Meldung an den Client fehlgeschlagen: ' + E.ClassName);
  end;
end;

procedure TShellCrashCases.SendSkip(const AEntry: TCrashSkipEntry; AActive: Boolean);
var
  mParams: TJSONObject;
begin
  if not Assigned(FNotify) then
    Exit;
  mParams := TJSONObject.Create;
  mParams.AddPair('active', TJSONBool.Create(AActive));
  mParams.AddPair('method', AEntry.Method);
  mParams.AddPair('uri', AEntry.Uri);
  if StartsText('file:', AEntry.Uri) then
    mParams.AddPair('file', TDocumentUris.ToPath(AEntry.Uri))
  else
    mParams.AddPair('file', '');
  mParams.AddPair('crashes', TJSONNumber.Create(AEntry.Crashes));
  mParams.AddPair('exception', AEntry.ExceptionClass);
  mParams.AddPair('folder', AEntry.CaseFolder);
  try
    FNotify(SkipNotification, mParams);
  except
    on E: Exception do
      FLogger.Warning('Überspringen: Meldung an den Client fehlgeschlagen: ' + E.ClassName);
  end;
end;

procedure TShellCrashCases.SaveSkips;
begin
  try
    if (FSkips.Count = 0) and not TFile.Exists(SkipsFile) then
      Exit;
    TDirectory.CreateDirectory(FRoot);
    TFile.WriteAllText(SkipsFile, FSkips.ToJson, TEncoding.UTF8);
  except
    on E: Exception do
      FLogger.Warning('Überspringen: Merker nicht gespeichert: ' + E.ClassName);
  end;
end;

procedure TShellCrashCases.RequestFailed(const AMethod: string; const AParams: TJSONValue; const AError: Exception;
  const AStack: string);
var
  mCase: TCrashCase;
  mParams, mFolder, mText: string;
  mSkipping: Boolean;
  mSkipped: TArray<TCrashSkipEntry>;
begin
  if not (FEnabled or FSkipEnabled) or (AError = nil) then
    Exit;
  try
    mParams := '';
    if AParams <> nil then
      mParams := AParams.ToJSON;
    mCase := NewCase(TCrashCaseKind.Exception_, AMethod, '', mParams);
    mCase.ExceptionClass := AError.ClassName;
    mCase.ExceptionMessage := AError.Message;
    mCase.Stack := AStack;
    mFolder := '';
    if FEnabled then
      mFolder := Store(mCase, TStackGuard.IsOverflow(AError));
    mSkipping := False;
    if FSkipEnabled and (mCase.Uri <> '') then
    begin
      mText := '';
      if mCase.HasText then
        mText := mCase.Text;
      mSkipping := FSkips.Crashed(AMethod, mCase.Uri, TCrashSkips.Checksum(mText), mFolder, AError.ClassName);
      SaveSkips;
      if mSkipping then
      begin
        FLogger.Warning(Format('Sicherheitsnetz: %s an %s wird bis zur nächsten Änderung übersprungen ' +
          '(zweiter Absturz, %s); Fall %s', [AMethod, ExtractFileName(mCase.FileName), AError.ClassName,
          mFolder]));
        // Der eben abgestürzte Eintrag steht in der Liste hinten (TCrashSkips.Crashed).
        mSkipped := FSkips.Skipped;
        SendSkip(mSkipped[High(mSkipped)], True);
      end;
    end;
    if FEnabled and (mFolder <> '') then
      SendCase(mCase, mFolder, mSkipping);
  except
    // Das Sichern darf die Fehlerantwort nicht verhindern (der Dispatcher verschluckt ohnehin).
    on E: Exception do
      FLogger.Error('Absturzfall: ' + E.ClassName + ': ' + E.Message);
  end;
end;

procedure TShellCrashCases.TimedOut(const AId, AMethod: string; ATimeoutMs: Cardinal);
var
  mCase: TCrashCase;
  mMethod, mParams, mFolder: string;
begin
  if not FEnabled then
    Exit;
  try
    mMethod := AMethod;
    mParams := '';
    if FRecent <> nil then
      FRecent.FindRequest(AId, mMethod, mParams);
    if mMethod = '' then
      mMethod := AMethod;
    mCase := NewCase(TCrashCaseKind.Timeout, mMethod, AId, mParams);
    mCase.TimeoutMs := ATimeoutMs;
    mCase.ExceptionClass := 'Zeitlimit';
    mCase.ExceptionMessage := Format('Abbruch durch den Watchdog nach %d ms', [ATimeoutMs]);
    // Ein Abbruch durch den Watchdog zählt nicht für das Überspringen: Langsam ist nicht abgestürzt.
    mFolder := Store(mCase, False);
    if mFolder <> '' then
      SendCase(mCase, mFolder, False);
  except
    on E: Exception do
      FLogger.Error('Absturzfall (Zeitlimit): ' + E.ClassName + ': ' + E.Message);
  end;
end;

// Rekursion ohne Ende mit Platz auf dem Stapel: echter Stapelüberlauf für den Testschalter.
function Deeper(ADepth: Integer): Integer;
var
  mPad: array[0..255] of Byte;
begin
  FillChar(mPad, SizeOf(mPad), Byte(ADepth));
  Result := Deeper(ADepth + 1) + mPad[ADepth mod Length(mPad)];
end;

procedure TShellCrashCases.TestCrash(const AMethod: string);
begin
  FLogger.Warning(Format('Testschalter %s: künstlicher Absturz in %s', [TestVariable, AMethod]));
  if FTestOverflow then
    Deeper(0);
  raise ECrashTest.Create('Künstlicher Absturz (Testschalter ' + TestVariable + ')');
end;

procedure TShellCrashCases.Guard(const AMethod: string; const AParams: TJSONValue);
var
  mUri: string;
  mLine: Integer;
begin
  // Testschalter zuletzt: Auch der künstliche Absturz wird nach dem zweiten Mal übersprungen.
  if FSkipEnabled and (FSkips.Count > 0) and TCrashCases.DocumentOf(AParams, mUri, mLine) and
    FSkips.Watched(AMethod, mUri) then
    CheckSkip(AMethod, mUri);
  if (FTestMethod <> '') and SameText(AMethod, FTestMethod) then
    TestCrash(AMethod);
end;

procedure TShellCrashCases.CheckSkip(const AMethod, AUri: string);
var
  mUri, mText: string;
  mEntry: TCrashSkipEntry;
  mChanged: Boolean;
begin
  mUri := AUri;
  // Erst jetzt die Prüfsumme: nur für Anfragen, die schon einmal an dieser Datei abgestürzt sind.
  if not CurrentText(mUri, mText) then
    mText := '';
  if FSkips.Skip(AMethod, mUri, TCrashSkips.Checksum(mText), mEntry, mChanged) then
  begin
    FLogger.Warning(Format('Sicherheitsnetz: %s an %s übersprungen nach Absturz; Fall %s', [AMethod,
      ExtractFileName(TDocumentUris.ToPath(mUri)), mEntry.CaseFolder]));
    raise EJsonRpcError.Create(TJsonRpcErrorCode.RequestFailed, SkipText(mEntry));
  end;
  if mChanged then
  begin
    SaveSkips;
    SendSkip(mEntry, False);
  end;
end;

procedure TShellCrashCases.DocumentChanged(const AUri, AText: string);
var
  mEntry: TCrashSkipEntry;
  mEnded: TArray<TCrashSkipEntry>;
begin
  // Je Tastendruck: die Prüfsumme nur für Dateien mit Einträgen.
  if not FSkips.WatchedUri(AUri) then
    Exit;
  mEnded := FSkips.Changed(AUri, TCrashSkips.Checksum(AText));
  if Length(mEnded) = 0 then
    Exit;
  SaveSkips;
  for mEntry in mEnded do
  begin
    FLogger.Info(Format('Sicherheitsnetz: %s an %s wieder aktiv (Datei geändert)', [mEntry.Method,
      ExtractFileName(TDocumentUris.ToPath(mEntry.Uri))]));
    SendSkip(mEntry, False);
  end;
end;

function TShellCrashCases.Retry(const AUri: string): Integer;
var
  mEntry: TCrashSkipEntry;
  mEnded: TArray<TCrashSkipEntry>;
begin
  mEnded := FSkips.Retry(AUri);
  SaveSkips;
  for mEntry in mEnded do
  begin
    FLogger.Info(Format('Sicherheitsnetz: %s an %s wieder aktiv (Erneut versuchen)', [mEntry.Method,
      ExtractFileName(TDocumentUris.ToPath(mEntry.Uri))]));
    SendSkip(mEntry, False);
  end;
  Result := Length(mEnded);
end;

procedure TShellCrashCases.Announce;
var
  mEntry: TCrashSkipEntry;
begin
  if not FSkipEnabled then
    Exit;
  for mEntry in FSkips.Skipped do
    SendSkip(mEntry, True);
end;

function TShellCrashCases.Skipped: TArray<TCrashSkipEntry>;
begin
  Result := FSkips.Skipped;
end;

end.
