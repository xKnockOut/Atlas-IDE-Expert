unit Shell.ReplayServer;

// Host-Rolle Shell: der vollständige Server für das Nachstellen eines
// Absturzfalls (--replay, #1355). Legt TServerComposition gegen den Transport
// von Shell.Replay an, mit settings.json aus dem Fall und ohne eigene
// Absturzfälle (PrepareReplay), und schreibt das Ergebnis über den Logger auf
// stderr. Die Logik des Nachstellens (Nachrichten, Warten, Bewertung) liegt in
// Shell.Replay und ist dort getestet; Testunits aus Tools/New-CrashTest.ps1
// nutzen Run.

interface

uses
  Atlas.Common.Logging.Contract,
  Atlas.Common.Diagnostics.CrashCase,
  Shell.Replay;

type
  TShellReplayServer = class
  public
    /// <summary>TReplayServer mit TServerComposition.</summary>
    class function Server: TReplayServer; static;
    /// <summary>ACase isoliert bzw. mit den Projekten des Absturzes nachstellen.</summary>
    class function Run(const ACase: TCrashCase; APlace: TReplayPlace; const ALogger: ILogger): TReplayResult; static;
    /// <summary>Kommandozeile --replay: Ergebnis auf stderr, Exit-Code wie TShellReplay.ExitCodeOf.</summary>
    class function Main(const AFileName: string): Integer; static;
  end;

implementation

uses
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.Logging.Providers.StreamSink,
  Shell.Platform,
  Shell.Composition;

procedure RunComposition(const ATransport: IJsonRpcTransport; const ALogger: ILogger; const ASettingsFile: string);
var
  mComposition: TServerComposition;
begin
  mComposition := TServerComposition.Create(ATransport, ALogger);
  try
    mComposition.PrepareReplay(ASettingsFile);
    mComposition.Run;
  finally
    mComposition.Free;
  end;
end;

class function TShellReplayServer.Server: TReplayServer;
begin
  Result := RunComposition;
end;

class function TShellReplayServer.Run(const ACase: TCrashCase; APlace: TReplayPlace;
  const ALogger: ILogger): TReplayResult;
begin
  Result := TShellReplay.Run(ACase, APlace, ALogger, Server);
end;

class function TShellReplayServer.Main(const AFileName: string): Integer;
var
  mLoggerImpl: TLogger;
  mLogger: ILogger;
  mResult: TReplayResult;
begin
  mLoggerImpl := TLogger.Create;
  mLogger := mLoggerImpl;
  mLoggerImpl.AddSink(TStreamLogSink.Create(TStdStreams.CreateError, True), TLogLevel.Warning);
  mResult := TShellReplay.Run(AFileName, mLogger, Server);
  mLogger.Warning(mResult.Text);
  Result := TShellReplay.ExitCodeOf(mResult);
end;

end.
