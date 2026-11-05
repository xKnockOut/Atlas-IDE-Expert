unit Shell.Composition.Session;

// Teilwurzel Sitzung der Komposition: Diagnoselog als Beobachter des Verteilers (#647), Wächter des
// Editor-Prozesses (#283), Name des Clients (#62), Grund für das Ende und Zeitlimit der Anfragen. Run führt die
// Verbindung mit Start- und Endzeile des Diagnoselogs.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Logging.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.JsonRpc.Connection,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Diagnostics.Contract,
  Atlas.Common.Lsp.Lifecycle,
  Shell.Platform,
  Shell.Diagnostics;

type
  /// <summary>Was die Sitzung von der Komposition braucht.</summary>
  TShellSessionServices = record
    Logger: ILogger;
    Documents: IDocumentStore;
    Index: ISymbolIndex;
    /// <summary>Verteiler, an dem das Diagnoselog beobachtet; nennt auch die letzte Nachricht.</summary>
    Dispatcher: TJsonRpcDispatcher;
    /// <summary>Zahl der Ordner, deren Index gerade lädt.</summary>
    IndexLoading: TFunc<Integer>;
    /// <summary>Beendet die Verbindung, wenn der Editor-Prozess endet.</summary>
    Stop: TProc;
  end;

  /// <summary>Hält Diagnoselog, Wächter des Editor-Prozesses, Client, Endgrund und Zeitlimit.</summary>
  TShellSession = class
  private
    FServices: TShellSessionServices;
    /// <summary>Prozessnummer des Editors aus der Befehlszeile (#283); 0 = keine.</summary>
    FClientProcessId: Cardinal;
    /// <summary>clientInfo.name aus initialize, für „Prozesse am Projekt“ (#62).</summary>
    FClientName: string;
    FParentWatcher: TParentWatcher;
    /// <summary>Anonymisiertes Diagnoselog (#647); FDiagnosticsRef hält die Instanz am Leben.</summary>
    FDiagnostics: TShellDiagnostics;
    FDiagnosticsRef: IJsonRpcRequestObserver;
    /// <summary>Grund für die Endzeile des Diagnoselogs; InputClosed, solange nichts anderes gemeldet ist.</summary>
    FEndReason: TDiagnosticEndReason;
    /// <summary>Zuletzt gesetztes Zeitlimit für Anfragen, für die Einordnung als timeout.</summary>
    FRequestTimeout: Cardinal;
    function CurrentRequestTimeout: Cardinal;
    function IndexLoading: Integer;
    procedure ParentExited(AProcessId: Cardinal);
  public
    /// <summary>Legt das Diagnoselog an und meldet es als Beobachter am Verteiler an.</summary>
    constructor Create(const AServices: TShellSessionServices; ARequestTimeoutMs: Cardinal);
    /// <summary>Beendet den Wächter und gibt das Diagnoselog frei; der Verteiler beobachtet dann nicht mehr.</summary>
    destructor Destroy; override;
    /// <summary>Überwacht den Editor-Prozess aus initialize oder der Befehlszeile.</summary>
    procedure WatchParent(const AInitializeParams: TJSONObject);
    /// <summary>Beendet den Wächter des Editor-Prozesses; vor dem Freigeben der Verbindung.</summary>
    procedure StopWatchingParent;
    /// <summary>Anonyme Bezeichnung einer Unit im Diagnoselog (#1094).</summary>
    function FileLabel(const AFileName: string): string;
    /// <summary>Fehler mit letzter Nachricht und Stapel für das Server-Log.</summary>
    function DescribeFailure(const AError: Exception): string;
    /// <summary>Zeitlimit und Einstellungen des Diagnoselogs aus den Servereinstellungen.</summary>
    procedure ApplySettings(const ASettings: TServerSettings);
    /// <summary>Führt die Verbindung mit Start- und Endzeile im Diagnoselog; liefert den Exit-Code.</summary>
    function Run(AConnection: TJsonRpcConnection; ALifecycle: TLspLifecycle): Integer;
    property ClientProcessId: Cardinal read FClientProcessId write FClientProcessId;
    property ClientName: string read FClientName write FClientName;
    property EndReason: TDiagnosticEndReason read FEndReason write FEndReason;
    /// <summary>Zuletzt gesetztes Zeitlimit für Anfragen.</summary>
    property RequestTimeout: Cardinal read FRequestTimeout;
    property Diagnostics: TShellDiagnostics read FDiagnostics;
  end;

implementation

uses
  Atlas.Common.Diagnostics.ShutdownLeaks,
  Atlas.Common.Product.Version,
  Atlas.Text.LogMarks;

function AllocatedBytes: Int64;
begin
  Result := TShutdownLeaks.AllocatedBytes;
end;

constructor TShellSession.Create(const AServices: TShellSessionServices; ARequestTimeoutMs: Cardinal);
begin
  inherited Create;
  FServices := AServices;
  FEndReason := TDiagnosticEndReason.InputClosed;
  FRequestTimeout := ARequestTimeoutMs;
  FDiagnostics := TShellDiagnostics.Create(TShellDiagnostics.DefaultFolder, IntToStr(TShellPlatform.CurrentProcessId),
    FServices.Documents, FServices.Index);
  FDiagnosticsRef := FDiagnostics;
  FDiagnostics.TimeoutMs := CurrentRequestTimeout;
  FDiagnostics.IndexLoading := IndexLoading;
  FServices.Dispatcher.Observer := FDiagnosticsRef;
end;

destructor TShellSession.Destroy;
begin
  StopWatchingParent;
  FDiagnostics := nil;
  FDiagnosticsRef := nil;
  FServices := Default(TShellSessionServices);
  inherited;
end;

function TShellSession.CurrentRequestTimeout: Cardinal;
begin
  Result := FRequestTimeout;
end;

function TShellSession.IndexLoading: Integer;
begin
  Result := FServices.IndexLoading();
end;

procedure TShellSession.ParentExited(AProcessId: Cardinal);
begin
  FServices.Logger.Warning(Format('Editor-Prozess %d ist beendet; der Server beendet sich', [AProcessId]));
  FEndReason := TDiagnosticEndReason.ParentExited;
  FServices.Stop();
end;

procedure TShellSession.WatchParent(const AInitializeParams: TJSONObject);
var
  mProcessId: Cardinal;
  mValue: TJSONValue;
begin
  mProcessId := FClientProcessId;
  if AInitializeParams <> nil then
  begin
    mValue := AInitializeParams.GetValue('processId');
    if mValue is TJSONNumber then
    begin
      mProcessId := Cardinal(TJSONNumber(mValue).AsInt64);
    end;
  end;
  if (mProcessId = 0) or (FParentWatcher <> nil) then
  begin
    Exit;
  end;
  FParentWatcher := TParentWatcher.Create(mProcessId,
    procedure
    begin
      ParentExited(mProcessId);
    end);
end;

procedure TShellSession.StopWatchingParent;
begin
  FreeAndNil(FParentWatcher);
end;

function TShellSession.FileLabel(const AFileName: string): string;
begin
  Result := 'unit';
  if FDiagnostics <> nil then
  begin
    Result := FDiagnostics.FileLabel(AFileName);
  end;
end;

function TShellSession.DescribeFailure(const AError: Exception): string;
var
  mStack: string;
begin
  Result := Format('%s: %s%sLetzte Nachricht: %s', [AError.ClassName, TLogMarks.Text(AError.Message), sLineBreak,
    TLogMarks.Text(FServices.Dispatcher.LastMessage)]);
  mStack := TShellPlatform.StackTraceOf(AError);
  if mStack <> '' then
  begin
    Result := Result + sLineBreak + mStack;
  end;
end;

procedure TShellSession.ApplySettings(const ASettings: TServerSettings);
begin
  FRequestTimeout := ASettings.RequestTimeoutMs;
  FDiagnostics.ApplySettings(ASettings);
end;

function TShellSession.Run(AConnection: TJsonRpcConnection; ALifecycle: TLspLifecycle): Integer;
var
  mPrevious: Integer;
begin
  FServices.Logger.Info(Format('%s %s gestartet', [TProductVersion.Name, TProductVersion.Version]));
  FDiagnostics.AllowMethods(FServices.Dispatcher.Methods);
  mPrevious := FDiagnostics.BeginRun(TProductVersion.Version, AllocatedBytes);
  // Neustarts erklären (#175): Die IDE beendet ihren Server hart (Projektwechsel, IDE geschlossen);
  // dann fehlt dessen Endzeile, und der nächste Start meldet das hier.
  if mPrevious > 0 then
  begin
    FServices.Logger.Info(Format('%d frühere Serverläufe ohne Endzeile (von der IDE beendet oder abgestürzt)',
      [mPrevious]));
  end;
  // Endzeile, sobald die Eingabe endet: Das Plugin beendet den Prozess nach 2 s, auch wenn noch
  // Anfragen laufen; sonst meldete der nächste Lauf einen Absturz (#647).
  AConnection.OnLoopEnded :=
    procedure
    begin
      FServices.Logger.Info('Verbindung beendet: ' + TShellDiagnostics.EndReasonText(FEndReason));
      FDiagnostics.EndRun(FEndReason, ALifecycle.ExitCode, AllocatedBytes);
    end;
  try
    AConnection.Run;
    Result := ALifecycle.ExitCode;
    FDiagnostics.EndRun(FEndReason, Result, AllocatedBytes);
  except
    on E: Exception do
    begin
      FServices.Logger.Error('Server abgebrochen: ' + DescribeFailure(E));
      Result := 1;
      FDiagnostics.EndRun(TDiagnosticEndReason.Exception_, Result, AllocatedBytes, E);
    end;
  end;
  FServices.Logger.Info(Format('Beendet mit Exit-Code %d', [Result]));
end;

end.
