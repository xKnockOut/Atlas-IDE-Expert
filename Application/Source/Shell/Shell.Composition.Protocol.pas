unit Shell.Composition.Protocol;

// Teilwurzel Protokoll der Komposition: Verteiler mit Watchdog, Statistik und den letzten Nachrichten,
// Lebenszyklus (initialize/shutdown) und die Absturzfälle samt Sicherheitsnetz (#1355). Die Komposition reicht
// Logger, Transport, Zeitlimit und die Fähigkeiten für initialize herein.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Logging.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.JsonRpc.Statistics,
  Atlas.Common.JsonRpc.RecentMessages,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Lifecycle,
  Shell.CrashCases;

type
  /// <summary>Was das Protokoll von der Komposition braucht.</summary>
  TShellProtocolServices = record
    Logger: ILogger;
    /// <summary>Anfragen, die länger laufen, bricht der Watchdog ab und meldet sie.</summary>
    TimeoutMs: Cardinal;
    /// <summary>Fähigkeiten für die Antwort auf initialize.</summary>
    Capabilities: TLspCapabilitiesFactory;
  end;

  /// <summary>Hält Verteiler, Statistik, letzte Nachrichten, Lebenszyklus und Absturzfälle.</summary>
  TShellProtocol = class
  private
    FServices: TShellProtocolServices;
    FDispatcher: TJsonRpcDispatcher;
    FStatistics: IJsonRpcStatistics;
    /// <summary>Die letzten Nachrichten des Clients für Absturzfälle (#1355).</summary>
    FRecent: IJsonRpcRecentMessages;
    FLifecycle: TLspLifecycle;
    /// <summary>Absturzfälle und Sicherheitsnetz (#1355); erst mit CreateCrashCases.</summary>
    FCrashCases: TShellCrashCases;
    /// <summary>Meldung des Watchdogs, wenn eine Anfrage ihr Zeitlimit überschreitet.</summary>
    procedure RequestTimedOut(const AMethod: string; ATimeoutMs: Cardinal; AAnswered: Boolean);
    /// <summary>Absturzfall beim Abbruch durch den Watchdog (#1355); läuft im Thread des Watchdogs.</summary>
    procedure RequestExpired(const AId, AMethod: string; ATimeoutMs: Cardinal);
    /// <summary>Überspringt eine Anfrage, die an derselben unveränderten Datei zweimal abstürzte (#1355).</summary>
    procedure GuardRequest(const AMethod: string; const AParams: TJSONValue);
    /// <summary>Protokolliert eine fehlgeschlagene Anfrage und hält sie als Absturzfall fest.</summary>
    procedure RequestFailed(const AMethod: string; const AParams: TJSONValue; const AError: Exception);
    function InitializeText: string;
  public
    /// <summary>Verteiler mit Watchdog und Fehlerprotokoll, Lebenszyklus am Verteiler.</summary>
    constructor Create(const AServices: TShellProtocolServices);
    /// <summary>Gibt Absturzfälle, Lebenszyklus und Verteiler in dieser Reihenfolge frei.</summary>
    destructor Destroy; override;
    /// <summary>Legt die Absturzfälle an, sobald es den Dokumentspeicher gibt. ASettingsFiles nennt die
    /// Einstellungsdateien zu einer URI, ANotify meldet an den Client.</summary>
    procedure CreateCrashCases(const ADocuments: IDocumentStore; const ASettingsFiles: TShellCrashSettingsFunc;
      const ANotify: TShellCrashNotify);
    property Dispatcher: TJsonRpcDispatcher read FDispatcher;
    property Statistics: IJsonRpcStatistics read FStatistics;
    property Lifecycle: TLspLifecycle read FLifecycle;
    property CrashCases: TShellCrashCases read FCrashCases;
  end;

implementation

uses
  Atlas.Common.JsonRpc.Watchdog,
  Atlas.Common.Product.Version,
  Shell.Platform,
  Atlas.Text.LogMarks;

constructor TShellProtocol.Create(const AServices: TShellProtocolServices);
var
  mWatchdog: TJsonRpcWatchdog;
begin
  inherited Create;
  FServices := AServices;
  FDispatcher := TJsonRpcDispatcher.Create;
  FStatistics := TJsonRpcStatistics.Create;
  FDispatcher.Statistics := FStatistics;
  FRecent := TJsonRpcRecentMessages.Create;
  FDispatcher.Recent := FRecent;
  mWatchdog := TJsonRpcWatchdog.Create(FDispatcher.PendingRequests, FServices.TimeoutMs, RequestTimedOut);
  // Absturzfall auch beim Abbruch durch den Watchdog (#1355); läuft im Thread des Watchdogs.
  mWatchdog.OnExpired := RequestExpired;
  FDispatcher.Watchdog := mWatchdog;
  // Sicherheitsnetz (#1355): eine Anfrage, die an derselben unveränderten Datei zweimal abstürzte, überspringen.
  FDispatcher.RequestGuard := GuardRequest;
  FDispatcher.OnRequestFailed := RequestFailed;
  FLifecycle := TLspLifecycle.Create(TProductVersion.cName, TProductVersion.cVersion, FServices.Capabilities);
  FLifecycle.Attach(FDispatcher);
  // Ändert der Client ein Dokument, sind laufende Anfragen dazu überholt (#283).
  FDispatcher.PendingRequests.AddContentChangeMethod('textDocument/didChange');
end;

destructor TShellProtocol.Destroy;
begin
  // Nach der Verbindung und dem Watchdog: Niemand meldet mehr einen Absturz.
  FreeAndNil(FCrashCases);
  FreeAndNil(FLifecycle);
  FreeAndNil(FDispatcher);
  inherited;
end;

procedure TShellProtocol.CreateCrashCases(const ADocuments: IDocumentStore;
  const ASettingsFiles: TShellCrashSettingsFunc; const ANotify: TShellCrashNotify);
begin
  FCrashCases := TShellCrashCases.Create('', FServices.Logger, ADocuments, FRecent);
  FCrashCases.AtlasVersion := TProductVersion.cVersion;
  FCrashCases.ServerPath := ParamStr(0);
  FCrashCases.Initialize := InitializeText;
  FCrashCases.SettingsFiles := ASettingsFiles;
  FCrashCases.Notify := ANotify;
end;

function TShellProtocol.InitializeText: string;
begin
  Result := '';
  if (FLifecycle <> nil) and (FLifecycle.InitializeParams <> nil) then
  begin
    Result := FLifecycle.InitializeParams.ToJSON;
  end;
end;

procedure TShellProtocol.RequestTimedOut(const AMethod: string; ATimeoutMs: Cardinal; AAnswered: Boolean);
begin
  // Code-Review A-06: Nebenläufige Anfragen beantwortet der Watchdog selbst, die übrigen brechen nur ab.
  if AAnswered then
  begin
    FServices.Logger.Warning(Format('Anfrage %s nach %d ms mit RequestCancelled beantwortet (Zeitlimit)',
      [AMethod, ATimeoutMs]));
  end
  else
  begin
    FServices.Logger.Warning(Format('Anfrage %s hat das Zeitlimit von %d ms überschritten; Abbruch angefordert',
      [AMethod, ATimeoutMs]));
  end;
end;

procedure TShellProtocol.RequestExpired(const AId, AMethod: string; ATimeoutMs: Cardinal);
begin
  if FCrashCases <> nil then
  begin
    FCrashCases.TimedOut(AId, AMethod, ATimeoutMs);
  end;
end;

procedure TShellProtocol.GuardRequest(const AMethod: string; const AParams: TJSONValue);
begin
  if FCrashCases <> nil then
  begin
    FCrashCases.Guard(AMethod, AParams);
  end;
end;

procedure TShellProtocol.RequestFailed(const AMethod: string; const AParams: TJSONValue; const AError: Exception);
var
  mParams: string;
begin
  mParams := '';
  if AParams <> nil then
  begin
    mParams := AParams.ToJSON;
  end;
  if Length(mParams) > 500 then
  begin
    mParams := Copy(mParams, 1, 500) + '…';
  end;
  FServices.Logger.Error(Format('Anfrage %s fehlgeschlagen: %s: %s%sParameter: %s%s%s',
    [AMethod, AError.ClassName, TLogMarks.Text(AError.Message), sLineBreak,
      TLogMarks.Text(mParams), sLineBreak, TShellPlatform.StackTraceOf(AError)]));
  // Nachstellbarer Fall (#1355): Anfrage, Datei, Stapel; danach Meldung an den Client.
  if FCrashCases <> nil then
  begin
    FCrashCases.RequestFailed(AMethod, AParams, AError, TShellPlatform.StackTraceOf(AError));
  end;
end;

end.
