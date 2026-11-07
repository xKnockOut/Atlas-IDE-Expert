unit Shell.Platform.Tests;

// Tests für die Plattformweiche des Servers (#1109): Ersetzendes Umbenennen,
// kanonische Pfade, eigene Prozessnummer und der Prozessläufer für git und svn
// (unter Windows TAtlasVcsProcessRunner, unter Linux Shell.Platform.VcsRunner):
// Hauptthread abgelehnt, fehlendes Programm, Zeitlimit, stdout gelesen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TShellPlatformTests = class
  private
    FFolder: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure MoveReplacingOverwritesTarget;
    [Test]
    procedure CanonicalizePathKeepsExistingFile;
    [Test]
    procedure CurrentProcessIdIsRunning;
    [Test]
    procedure VcsRunnerRefusesMainThreadAndHonoursTimeout;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Atlas.Core.Vcs.Contract,
  Shell.Platform;

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

{ TShellPlatformTests }

procedure TShellPlatformTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'AtlasPlatform-' + TGUID.NewGuid.ToString.Substring(1, 8));
  TDirectory.CreateDirectory(FFolder);
end;

procedure TShellPlatformTests.TearDown;
begin
  if TDirectory.Exists(FFolder) then
  begin
    TDirectory.Delete(FFolder, True);
  end;
  FFolder := '';
end;

procedure TShellPlatformTests.MoveReplacingOverwritesTarget;
var
  mSource, mTarget: string;
begin
  mSource := TPath.Combine(FFolder, 'neu.txt');
  mTarget := TPath.Combine(FFolder, 'alt.txt');
  TFile.WriteAllText(mSource, 'neu');
  TFile.WriteAllText(mTarget, 'alt');
  Assert.IsTrue(TShellPlatform.MoveReplacing(mSource, mTarget), 'ersetzt');
  Assert.IsFalse(TFile.Exists(mSource), 'Quelle weg');
  Assert.AreEqual('neu', TFile.ReadAllText(mTarget, TEncoding.UTF8));
  Assert.IsFalse(TShellPlatform.MoveReplacing(mSource, mTarget), 'fehlende Quelle');
end;

procedure TShellPlatformTests.CanonicalizePathKeepsExistingFile;
var
  mFileName, mCanonical: string;
begin
  mFileName := TPath.Combine(FFolder, 'Unit1.pas');
  TFile.WriteAllText(mFileName, 'unit Unit1;');
  mCanonical := TShellPlatform.CanonicalizePath(mFileName);
  Assert.IsTrue(TFile.Exists(mCanonical), mCanonical);
  Assert.AreEqual(mCanonical, TShellPlatform.CanonicalizePath(mCanonical), 'stabil');
  Assert.AreEqual('Unit1.pas', ExtractFileName(mCanonical));
end;

procedure TShellPlatformTests.CurrentProcessIdIsRunning;
begin
  Assert.IsTrue(TShellPlatform.CurrentProcessId > 0);
  Assert.IsTrue(TProcessInstances.Running(TShellPlatform.CurrentProcessId));
end;

procedure TShellPlatformTests.VcsRunnerRefusesMainThreadAndHonoursTimeout;
var
  mRunner: IAtlasVcsRunner;
  mCommand: TProbe;
  mAnswer: TAtlasVcsRunResult;
  mStarted: UInt64;
begin
  mCommand := Probe;
  mRunner := TShellPlatform.CreateVcsRunner(False, nil);
  mAnswer := mRunner.Run(mCommand.Executable, mCommand.Quick, '', 5000);
  Assert.IsTrue(mAnswer.Outcome = TAtlasVcsOutcome.MainThread, 'Hauptthread abgelehnt');
  mRunner := TShellPlatform.CreateVcsRunner(True, nil);
  mAnswer := mRunner.Run(TPath.Combine(FFolder, 'gibt-es-nicht.exe'), nil, '', 5000);
  Assert.IsTrue(mAnswer.Outcome = TAtlasVcsOutcome.ToolMissing, 'fehlendes Programm');
  mStarted := TThread.GetTickCount64;
  mAnswer := mRunner.Run(mCommand.Executable, mCommand.Slow, '', 300);
  Assert.IsTrue(mAnswer.Outcome = TAtlasVcsOutcome.TimedOut, 'Zeitlimit');
  Assert.IsTrue(TThread.GetTickCount64 - mStarted < 5000, 'Prozess beendet, nicht abgewartet');
  mAnswer := mRunner.Run(mCommand.Executable, mCommand.Quick, FFolder, 10000);
  Assert.IsTrue(mAnswer.Outcome = TAtlasVcsOutcome.Ok, 'gelaufen');
  Assert.AreEqual(0, mAnswer.ExitCode);
  Assert.IsTrue(Length(mAnswer.Output) > 0, 'stdout gelesen');
end;

initialization
  TDUnitX.RegisterTestFixture(TShellPlatformTests);

end.
