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
    TDirectory.Delete(FFolder, True);
  FFolder := '';
end;

procedure TShellPlatformTests.MoveReplacingOverwritesTarget;
var
  Source, Target: string;
begin
  Source := TPath.Combine(FFolder, 'neu.txt');
  Target := TPath.Combine(FFolder, 'alt.txt');
  TFile.WriteAllText(Source, 'neu');
  TFile.WriteAllText(Target, 'alt');
  Assert.IsTrue(TShellPlatform.MoveReplacing(Source, Target), 'ersetzt');
  Assert.IsFalse(TFile.Exists(Source), 'Quelle weg');
  Assert.AreEqual('neu', TFile.ReadAllText(Target, TEncoding.UTF8));
  Assert.IsFalse(TShellPlatform.MoveReplacing(Source, Target), 'fehlende Quelle');
end;

procedure TShellPlatformTests.CanonicalizePathKeepsExistingFile;
var
  FileName, Canonical: string;
begin
  FileName := TPath.Combine(FFolder, 'Unit1.pas');
  TFile.WriteAllText(FileName, 'unit Unit1;');
  Canonical := TShellPlatform.CanonicalizePath(FileName);
  Assert.IsTrue(TFile.Exists(Canonical), Canonical);
  Assert.AreEqual(Canonical, TShellPlatform.CanonicalizePath(Canonical), 'stabil');
  Assert.AreEqual('Unit1.pas', ExtractFileName(Canonical));
end;

procedure TShellPlatformTests.CurrentProcessIdIsRunning;
begin
  Assert.IsTrue(TShellPlatform.CurrentProcessId > 0);
  Assert.IsTrue(TProcessInstances.Running(TShellPlatform.CurrentProcessId));
end;

procedure TShellPlatformTests.VcsRunnerRefusesMainThreadAndHonoursTimeout;
var
  Runner: IAtlasVcsRunner;
  Command: TProbe;
  Answer: TAtlasVcsRunResult;
  Started: UInt64;
begin
  Command := Probe;
  Runner := TShellPlatform.CreateVcsRunner(False, nil);
  Answer := Runner.Run(Command.Executable, Command.Quick, '', 5000);
  Assert.IsTrue(Answer.Outcome = TAtlasVcsOutcome.MainThread, 'Hauptthread abgelehnt');
  Runner := TShellPlatform.CreateVcsRunner(True, nil);
  Answer := Runner.Run(TPath.Combine(FFolder, 'gibt-es-nicht.exe'), nil, '', 5000);
  Assert.IsTrue(Answer.Outcome = TAtlasVcsOutcome.ToolMissing, 'fehlendes Programm');
  Started := TThread.GetTickCount64;
  Answer := Runner.Run(Command.Executable, Command.Slow, '', 300);
  Assert.IsTrue(Answer.Outcome = TAtlasVcsOutcome.TimedOut, 'Zeitlimit');
  Assert.IsTrue(TThread.GetTickCount64 - Started < 5000, 'Prozess beendet, nicht abgewartet');
  Answer := Runner.Run(Command.Executable, Command.Quick, FFolder, 10000);
  Assert.IsTrue(Answer.Outcome = TAtlasVcsOutcome.Ok, 'gelaufen');
  Assert.AreEqual(0, Answer.ExitCode);
  Assert.IsTrue(Length(Answer.Output) > 0, 'stdout gelesen');
end;

initialization
  TDUnitX.RegisterTestFixture(TShellPlatformTests);

end.
