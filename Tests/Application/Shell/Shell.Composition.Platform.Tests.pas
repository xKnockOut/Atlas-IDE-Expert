unit Shell.Composition.Platform.Tests;

// Tests für die plattformabhängigen Adapter der Shell (#1109): der Prozessläufer für git und svn
// (unter Windows TAtlasVcsProcessRunner, unter Linux Adapters.VersionControl.LinuxRunner):
// Hauptthread abgelehnt, fehlendes Programm, Zeitlimit, stdout gelesen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TShellPlatformAdaptersTests = class
  private
    FFolder: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure VcsRunnerRefusesMainThreadAndHonoursTimeout;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Atlas.Core.VersionControl.Contract,
  Shell.Composition.Platform,
  Atlas.Tests.TempFolder;

type
  /// <summary>Programm und Argumente für einen kurzen und einen langen Lauf mit Ausgabe auf stdout.</summary>
  TProbe = record
    Executable: string;
    Quick: TArray<string>;
    Slow: TArray<string>;
  end;

function Probe: TProbe;
begin
{$IFDEF MSWINDOWS}
  Result.Executable := TPath.Combine(GetEnvironmentVariable('SystemRoot'), 'System32\PING.EXE');
  Result.Quick := TArray<string>.Create('-n', '1', '127.0.0.1');
  Result.Slow := TArray<string>.Create('-n', '30', '127.0.0.1');
{$ELSE}
  Result.Executable := '/bin/sh';
  Result.Quick := TArray<string>.Create('-c', 'echo atlas');
  Result.Slow := TArray<string>.Create('-c', 'sleep 30');
{$ENDIF}
end;

{ TShellPlatformAdaptersTests }

procedure TShellPlatformAdaptersTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'AtlasPlatform-' + TGUID.NewGuid.ToString.Substring(1, 8));
  TDirectory.CreateDirectory(FFolder);
end;

procedure TShellPlatformAdaptersTests.TearDown;
begin
  TTestTempFolder.Remove(FFolder);
end;

procedure TShellPlatformAdaptersTests.VcsRunnerRefusesMainThreadAndHonoursTimeout;
var
  mRunner: IAtlasVcsRunner;
  mCommand: TProbe;
  mAnswer: TAtlasVcsRunResult;
  mStarted: UInt64;
begin
  mCommand := Probe;
  mRunner := TShellPlatformAdapters.CreateVcsRunner(False, nil);
  mAnswer := mRunner.Run(mCommand.Executable, mCommand.Quick, '', 5000);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.MainThread, mAnswer.Outcome, 'Hauptthread abgelehnt');
  mRunner := TShellPlatformAdapters.CreateVcsRunner(True, nil);
  mAnswer := mRunner.Run(TPath.Combine(FFolder, 'gibt-es-nicht.exe'), nil, '', 5000);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.ToolMissing, mAnswer.Outcome, 'fehlendes Programm');
  mStarted := TThread.GetTickCount64;
  mAnswer := mRunner.Run(mCommand.Executable, mCommand.Slow, '', 300);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.TimedOut, mAnswer.Outcome, 'Zeitlimit');
  Assert.IsTrue(TThread.GetTickCount64 - mStarted < 5000, 'Prozess beendet, nicht abgewartet');
  mAnswer := mRunner.Run(mCommand.Executable, mCommand.Quick, FFolder, 10000);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mAnswer.Outcome, 'gelaufen');
  Assert.AreEqual(0, mAnswer.ExitCode);
  Assert.IsTrue(Length(mAnswer.Output) > 0, 'stdout gelesen');
end;

initialization
  TDUnitX.RegisterTestFixture(TShellPlatformAdaptersTests);

end.
