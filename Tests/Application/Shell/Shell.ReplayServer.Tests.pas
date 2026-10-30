unit Shell.ReplayServer.Tests;

// Tests für TShellReplayServer (#1355): ein Fall gegen den vollständigen Server
// (TServerComposition). TCrashReplayTest legt einen eingebetteten Fall
// (anfrage.json und Dateien daneben) in einen Temp-Ordner und stellt ihn
// isoliert nach; die Testunits aus Tools/New-CrashTest.ps1 nutzen es.

interface

uses
  DUnitX.TestFramework,
  Shell.Replay;

type
  /// <summary>Datei eines eingebetteten Falls: Name im Ordner und Inhalt.</summary>
  TCrashReplayFile = record
    Name: string;
    Text: string;
    class function Create(const AName, AText: string): TCrashReplayFile; static;
  end;

  TCrashReplayTest = class
  public
    /// <summary>Protokoll des Servers beim letzten Replay (Warnungen und mehr).</summary>
    class var LastLog: TArray<string>;
    /// <summary>Schreibt ARequest als anfrage.json und AFiles daneben und stellt den Fall isoliert mit dem
    /// vollständigen Server nach.</summary>
    class function Replay(const ARequest: string; const AFiles: TArray<TCrashReplayFile>): TReplayResult; static;
  end;

  [TestFixture]
  TShellReplayServerTests = class
  public
    /// <summary>Hover auf einer gesunden Unit stürzt nicht ab: „nicht reproduziert“, Exit-Code 0.</summary>
    [Test]
    procedure HealthyHoverIsNotReproduced;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.Logging.Providers.RecentSink,
  Atlas.Common.Diagnostics.CrashCase,
  Shell.ReplayServer;

{ TCrashReplayFile }

class function TCrashReplayFile.Create(const AName, AText: string): TCrashReplayFile;
begin
  Result.Name := AName;
  Result.Text := AText;
end;

{ TCrashReplayTest }

class function TCrashReplayTest.Replay(const ARequest: string; const AFiles: TArray<TCrashReplayFile>): TReplayResult;
var
  mFolder, mError: string;
  mFile: TCrashReplayFile;
  mCase: TCrashCase;
  mLoggerImpl: TLogger;
  mLogger: ILogger;
  mSink: TRecentLogSink;
  mSinkRef: ILogSink;
begin
  LastLog := nil;
  mFolder := TPath.Combine(TPath.GetTempPath, 'AtlasCrashReplay_' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(mFolder);
  try
    TFile.WriteAllText(TPath.Combine(mFolder, TCrashCases.RequestName), ARequest, TEncoding.UTF8);
    for mFile in AFiles do
      TFile.WriteAllText(TPath.Combine(mFolder, mFile.Name), mFile.Text, TEncoding.UTF8);
    if not TCrashCases.Load(TPath.Combine(mFolder, TCrashCases.RequestName), mCase, mError) then
    begin
      Result := Default(TReplayResult);
      Result.Outcome := TReplayOutcome.Unreadable;
      Result.Detail := mError;
      Exit;
    end;
    mLoggerImpl := TLogger.Create;
    mLogger := mLoggerImpl;
    mSink := TRecentLogSink.Create;
    mSinkRef := mSink;
    mLoggerImpl.AddSink(mSinkRef, TLogLevel.Debug);
    Result := TShellReplayServer.Run(mCase, TReplayPlace.Isolated, mLogger);
    LastLog := mSink.Lines;
  finally
    TDirectory.Delete(mFolder, True);
  end;
end;

{ TShellReplayServerTests }

procedure TShellReplayServerTests.HealthyHoverIsNotReproduced;
var
  mResult: TReplayResult;
begin
  mResult := TCrashReplayTest.Replay(
    '{"format":1,"kind":"exception","method":"textDocument/hover","id":1,' +
    '"params":{"textDocument":{"uri":"file:///C:/Fall/Demo.pas"},"position":{"line":2,"character":10}},' +
    '"uri":"file:///C:/Fall/Demo.pas","file":"C:\\Fall\\Demo.pas","line":2,' +
    '"exception":{"class":"EStackOverflow","message":"Stack overflow"},' +
    '"files":{"snapshot":"Demo.pas","stack":"stapel.txt","settings":[]}}',
    TArray<TCrashReplayFile>.Create(TCrashReplayFile.Create('Demo.pas',
      'unit Demo;'#13#10'interface'#13#10'procedure Hallo;'#13#10'implementation'#13#10 +
      'procedure Hallo;'#13#10'begin'#13#10'end;'#13#10'end.'#13#10)));
  Assert.IsTrue(mResult.Outcome = TReplayOutcome.NotReproduced, mResult.Text);
  Assert.AreEqual(TShellReplay.ExitNotReproduced, TShellReplay.ExitCodeOf(mResult));
  // Sauber beendet: Liefen beim Ende noch Anfragen, gibt die Komposition ihre Objekte absichtlich nicht frei.
  Assert.IsFalse(string.Join(#10, TCrashReplayTest.LastLog).Contains('liefen noch Anfragen'),
    string.Join(#10, TCrashReplayTest.LastLog));
  TCrashReplayTest.LastLog := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TShellReplayServerTests);

end.
