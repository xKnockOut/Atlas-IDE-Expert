unit Shell.Composition.Stdio.Tests;

// Protokoll und Mitschnitt für den stdio-Betrieb: Auszug der Sitzung und Anonymisierer auch ohne --log,
// Mitschnitt legt fehlende Ordner an.

interface

uses
  DUnitX.TestFramework,
  Shell.Composition.Stdio;

type
  [TestFixture]
  TShellStdioTests = class
  private
    FTempDir: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Ohne --log: Auszug der Sitzung (#108, #1356) und Anonymisierer sind trotzdem da.</summary>
    [Test]
    procedure LoggerWithoutLogFile;
    /// <summary>Der Mitschnitt legt fehlende Ordner an und nennt die benutzte Datei (#283).</summary>
    [Test]
    procedure TraceStreamCreatesFolder;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Logging.Providers.RecentSink,
  Atlas.Common.Diagnostics.Anonymizer,
  Shell.CommandLine;

procedure TShellStdioTests.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath, 'AtlasStdio' + TGUID.NewGuid.ToString);
end;

procedure TShellStdioTests.TearDown;
begin
  if TDirectory.Exists(FTempDir) then
  begin
    TDirectory.Delete(FTempDir, True);
  end;
  FTempDir := '';
end;

procedure TShellStdioTests.LoggerWithoutLogFile;
var
  mOptions: TCommandLineOptions;
  mRecent: IRecentLogLines;
  mAnonymizer: ILogAnonymizer;
  mLogger: ILogger;
begin
  mOptions := Default(TCommandLineOptions);
  mOptions.LogLevel := TCommandLineOptions.cDefaultLogLevel;
  mLogger := TShellStdio.NewLogger(mOptions, mRecent, mAnonymizer);
  Assert.IsNotNull(mRecent);
  Assert.IsNotNull(mAnonymizer);
  mLogger.Info('Zeile für den Auszug');
  Assert.IsTrue(string.Join(sLineBreak, mRecent.Lines).Contains('Zeile für den Auszug'));
end;

procedure TShellStdioTests.TraceStreamCreatesFolder;
var
  mFile: string;
  mActual: string;
  mStream: TStream;
begin
  mFile := TPath.Combine(TPath.Combine(FTempDir, 'Unter'), 'trace.log');
  mStream := TShellStdio.CreateTraceStream(mFile, '1', mActual);
  try
    Assert.IsTrue(TDirectory.Exists(TPath.Combine(FTempDir, 'Unter')));
    Assert.AreEqual(mFile, mActual);
  finally
    mStream.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TShellStdioTests);

end.
