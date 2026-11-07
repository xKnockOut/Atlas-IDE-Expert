unit Shell.Composition.Stdio;

// Protokoll und Transport für den stdio-Betrieb: Logger mit Debug-Senke, stderr, Auszug der Sitzung und --log,
// Transport über stdin/stdout, mit --trace hinter einem Mitschnitt.

interface

uses
  System.Classes,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.Logging.Providers.RecentSink,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.TracingTransport,
  Atlas.Common.Diagnostics.Anonymizer,
  Shell.CommandLine;

type
  /// <summary>Was der stdio-Betrieb der Komposition mitgibt.</summary>
  TShellStdioChannel = record
    Logger: ILogger;
    Transport: IJsonRpcTransport;
    /// <summary>Mitschnitt aus --trace; nil ohne.</summary>
    Tracing: TJsonRpcTracingTransport;
    RecentLog: IRecentLogLines;
    Anonymizer: ILogAnonymizer;
  end;

  /// <summary>Richtet Protokoll und Transport für den stdio-Betrieb ein.</summary>
  TShellStdio = class
  public const
    /// <summary>Protokoll der Sitzung im Speicher für Fehlerbericht und Diagnosepaket (#1356).</summary>
    cSessionLogLines = 10000;
  public
    /// <summary>Stacktraces und Schutzseiten der Plattform, Logger, Transport, window/logMessage und die Warnungen
    /// der Befehlszeile.</summary>
    class function Open(const AOptions: TCommandLineOptions): TShellStdioChannel; static;
    /// <summary>Protokoll für den stdio-Betrieb: Debug-Senke der Plattform, stderr nur für Fehler, Auszug der
    /// Sitzung und die Datei aus --log samt Anonymisierer.</summary>
    class function NewLogger(const AOptions: TCommandLineOptions; out ARecentLog: IRecentLogLines;
      out AAnonymizer: ILogAnonymizer): TLogger; static;
    /// <summary>Transport über stdin/stdout, mit --trace hinter einem Mitschnitt (ATracing, sonst nil).</summary>
    class function NewTransport(const AOptions: TCommandLineOptions; const ALogger: ILogger;
      out ATracing: TJsonRpcTracingTransport): IJsonRpcTransport; static;
    /// <summary>Meldet den Abbruch des Mitschnitts. Fängt nur den Logger ein; den Zyklus Logger → Sink → Transport →
    /// Closure bricht das einmalige Leeren beim Melden bzw. Destroy (S-07). Anonym: Klasse und Meldung, kein Pfad.
    /// </summary>
    class procedure WatchTracing(ATracing: TJsonRpcTracingTransport; const ALogger: ILogger); static;
    /// <summary>Mitschnitt anlegen. Rotiert bei Überlänge (#283). Hält ihn schon ein anderer Server (jede
    /// RAD-Studio-IDE startet einen eigenen), weicht er auf einen Namen mit AFallbackTag aus, statt ganz ohne
    /// Mitschnitt zu laufen. AActualName ist die tatsächlich benutzte Datei.</summary>
    class function CreateTraceStream(const AFileName, AFallbackTag: string; out AActualName: string): TStream; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Logging.Providers.StreamSink,
  Atlas.Common.Logging.RotatingFileStream,
  Atlas.Common.JsonRpc.StreamTransport,
  Atlas.Common.Lsp.Adapters.LogMessageSink,
  Shell.Platform,
  Shell.Diagnostics,
  Atlas.Text.LogMarks;

class function TShellStdio.CreateTraceStream(const AFileName, AFallbackTag: string; out AActualName: string): TStream;
var
  mDirectory: string;
  mStream: TRotatingFileStream;
begin
  mDirectory := TPath.GetDirectoryName(TPath.GetFullPath(AFileName));
  if mDirectory <> '' then
  begin
    ForceDirectories(mDirectory);
  end;
  mStream := TRotatingFileStream.Create(AFileName, False, AFallbackTag);
  AActualName := mStream.FileName;
  Result := mStream;
end;

class function TShellStdio.NewLogger(const AOptions: TCommandLineOptions; out ARecentLog: IRecentLogLines;
  out AAnonymizer: ILogAnonymizer): TLogger;
var
  mDebugSink: ILogSink;
  mRecentSink: TRecentLogSink;
begin
  Result := TLogger.Create;
  mDebugSink := TShellPlatform.DebugLogSink;
  if mDebugSink <> nil then
  begin
    Result.AddSink(mDebugSink, TLogLevel.Debug);
  end;
  // stderr zeigt VS Code ebenfalls im Ausgabefenster; dort nur Fehler, um
  // Doppelungen mit window/logMessage zu vermeiden.
  Result.AddSink(TStreamLogSink.Create(TStdStreams.CreateError, True), TLogLevel.Error);
  // Auszug für den Fehlerbericht (#108) und das Protokoll der Sitzung im Diagnosepaket (#1356), unabhängig von
  // --log.
  mRecentSink := TRecentLogSink.Create(cSessionLogLines);
  ARecentLog := mRecentSink;
  Result.AddSink(mRecentSink, TLogLevel.Info);
  TShellDiagnostics.AddLogFile(Result, AOptions.LogFile, IntToStr(TParentWatcher.CurrentProcessId),
    AOptions.LogNames, AOptions.LogLevel, AAnonymizer);
  // Ohne --log bzw. mit --log-names trotzdem einer: Er sammelt die Namen der Projekte für den anonymen Status im
  // Diagnosepaket (#1356).
  if AAnonymizer = nil then
  begin
    AAnonymizer := TLogAnonymizer.Create(TProcessInfo.IdentityNames);
  end;
end;

class function TShellStdio.NewTransport(const AOptions: TCommandLineOptions; const ALogger: ILogger;
  out ATracing: TJsonRpcTracingTransport): IJsonRpcTransport;
var
  mTraceName: string;
begin
  ATracing := nil;
  // Ab hier erreichen versehentliche Ausgaben (Writeln, Bibliotheken) nur noch stderr.
  Result := TJsonRpcStreamTransport.Create(TStdStreams.CreateInput, TStdStreams.ReserveOutputForProtocol, True);
  if AOptions.TraceFile = '' then
  begin
    Exit;
  end;
  try
    ATracing := TJsonRpcTracingTransport.Create(Result,
      CreateTraceStream(AOptions.TraceFile, IntToStr(TParentWatcher.CurrentProcessId), mTraceName), True);
    Result := ATracing;
    if not SameText(mTraceName, AOptions.TraceFile) then
    begin
      ALogger.Info(Format('Mitschnitt "%s" ist belegt, schreibe nach "%s"', [TLogMarks.Path(AOptions.TraceFile),
        TLogMarks.Path(mTraceName)]));
    end;
  except
    on E: Exception do
      ALogger.Error(Format('Mitschnitt "%s" kann nicht angelegt werden: %s', [TLogMarks.Path(AOptions.TraceFile),
        TLogMarks.Text(E.Message)]));
  end;
end;

class procedure TShellStdio.WatchTracing(ATracing: TJsonRpcTracingTransport; const ALogger: ILogger);
begin
  ATracing.OnFailed :=
    procedure(const AReason: string)
    begin
      ALogger.Warning('Mitschnitt abgebrochen, der Server arbeitet ohne weiter: ' + TLogMarks.Text(AReason));
    end;
end;

class function TShellStdio.Open(const AOptions: TCommandLineOptions): TShellStdioChannel;
var
  mLoggerImpl: TLogger;
  mWarning: TCommandLineWarning;
begin
  Result := Default(TShellStdioChannel);
  // Stacktraces für das Absturzprotokoll (Exception.StackTrace).
  TStackTrace.Install;
  // Schutzseite nach Stapelüberlauf (#1094) und Lesen mit FILE_SHARE_DELETE (Bericht M5), soweit die
  // Plattform sie braucht.
  TShellPlatform.InstallGuards;
  mLoggerImpl := NewLogger(AOptions, Result.RecentLog, Result.Anonymizer);
  Result.Logger := mLoggerImpl;
  Result.Transport := NewTransport(AOptions, Result.Logger, Result.Tracing);
  mLoggerImpl.AddSink(TLspLogMessageSink.Create(Result.Transport), AOptions.LogLevel);
  for mWarning in AOptions.Warnings do
  begin
    Result.Logger.Warning(mWarning.Text);
  end;
  if Result.Tracing <> nil then
  begin
    WatchTracing(Result.Tracing, Result.Logger);
  end;
end;

end.
