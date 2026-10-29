unit Atlas.Core.Vcs.ToolCheck.Tests;

// Seite Versionsverwaltung (#1285): Fundort von git und svn mit eigenem Pfad
// (Vorrang, kein Ersatz bei fehlender Datei, dann PATH, dann übliche Ordner)
// und „Prüfen“ (Versionsabfrage auswerten, Zustand zuordnen) mit einem
// Prozessläufer-Ersatz, ohne echtes git bzw. svn.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasVcsToolCheckTests = class
  public
    [Test]
    procedure ConfiguredPathWinsOverPath;
    [Test]
    procedure ConfiguredMissingDoesNotFallBack;
    [Test]
    procedure WithoutConfiguredPathSearchesPathThenKnownDirs;
    [Test]
    procedure ConfigureForgetsRememberedLocation;
    [Test]
    procedure VersionArgumentsPerProgram;
    [Test]
    procedure ParsesGitAndSvnVersions;
    [Test]
    procedure RejectsForeignOutput;
    [Test]
    procedure ClassifiesRunResults;
    [Test]
    procedure CheckRunsVersionQueryInProgramFolder;
    [Test]
    procedure CheckWithoutProgramRunsNothing;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.Tools,
  Atlas.Core.Vcs.ToolCheck;

type
  /// <summary>Merkt Programm, Argumente, Ordner und Zeitgrenze und antwortet fest.</summary>
  TFakeRunner = class(TInterfacedObject, IAtlasVcsRunner)
  public
    Executable: string;
    Arguments: string;
    WorkingDir: string;
    TimeoutMs: Cardinal;
    Calls: Integer;
    Answer: TAtlasVcsRunResult;
    function Run(const AExecutable: string; const AArguments: TArray<string>; const AWorkingDir: string;
      ATimeoutMs: Cardinal): TAtlasVcsRunResult;
  end;

function Root: string;
begin
  if PathDelim = '\' then
    Result := 'C:\Werkzeuge'
  else
    Result := '/werkzeuge';
end;

function Under(const ARelative: string): string;
begin
  Result := Root + PathDelim + StringReplace(ARelative, '/', PathDelim, [rfReplaceAll]);
end;

function Exe(const AName: string): string;
begin
  Result := AName;
  if PathDelim = '\' then
    Result := AName + '.exe';
end;

function Run(AOutcome: TAtlasVcsOutcome; AExitCode: Integer; const AOutput: string): TAtlasVcsRunResult;
begin
  Result := TAtlasVcsRunResult.Make(AOutcome, AExitCode, TEncoding.UTF8.GetBytes(AOutput));
end;

function Found(const AExecutable: string): TAtlasVcsToolLocation;
begin
  Result := TAtlasVcsToolLocation.Empty;
  Result.Executable := AExecutable;
  Result.Source := TAtlasVcsToolSource.Path;
end;

{ TFakeRunner }

function TFakeRunner.Run(const AExecutable: string; const AArguments: TArray<string>; const AWorkingDir: string;
  ATimeoutMs: Cardinal): TAtlasVcsRunResult;
begin
  Inc(Calls);
  Executable := AExecutable;
  Arguments := string.Join(' ', AArguments);
  WorkingDir := AWorkingDir;
  TimeoutMs := ATimeoutMs;
  Result := Answer;
end;

{ TAtlasVcsToolCheckTests }

procedure TAtlasVcsToolCheckTests.ConfiguredPathWinsOverPath;
var
  mLocation: TAtlasVcsToolLocation;
begin
  mLocation := TAtlasVcsTools.Resolve('git', ' "' + Under('Portable/git/' + Exe('git')) + '" ', Under('bin'), nil,
    function(const APath: string): Boolean
    begin
      Result := True;
    end);
  Assert.AreEqual(Under('Portable/git/' + Exe('git')), mLocation.Executable, 'ohne Anführungszeichen und Leerzeichen');
  Assert.IsTrue(mLocation.Source = TAtlasVcsToolSource.Configured, 'eigener Pfad vor PATH');
  Assert.AreEqual(Under('Portable/git/' + Exe('git')), mLocation.Configured);
end;

procedure TAtlasVcsToolCheckTests.ConfiguredMissingDoesNotFallBack;
var
  mLocation: TAtlasVcsToolLocation;
begin
  mLocation := TAtlasVcsTools.Resolve('svn', Under('fehlt/' + Exe('svn')), Under('bin'), [Under('TortoiseSVN/bin')],
    function(const APath: string): Boolean
    begin
      Result := APath <> Under('fehlt/' + Exe('svn'));
    end);
  Assert.AreEqual('', mLocation.Executable, 'kein Ersatz aus PATH, wenn der eigene Pfad fehlt');
  Assert.IsTrue(mLocation.Source = TAtlasVcsToolSource.ConfiguredMissing);
  Assert.AreEqual(Under('fehlt/' + Exe('svn')), mLocation.Configured, 'Pfad für die Meldung');
end;

procedure TAtlasVcsToolCheckTests.WithoutConfiguredPathSearchesPathThenKnownDirs;
var
  mLocation: TAtlasVcsToolLocation;
begin
  mLocation := TAtlasVcsTools.Resolve('svn', '', Under('bin'), [Under('TortoiseSVN/bin')],
    function(const APath: string): Boolean
    begin
      Result := True;
    end);
  Assert.AreEqual(Under('bin/' + Exe('svn')), mLocation.Executable);
  Assert.IsTrue(mLocation.Source = TAtlasVcsToolSource.Path, 'PATH vor üblichen Ordnern');
  mLocation := TAtlasVcsTools.Resolve('svn', '  ', Under('bin'), [Under('TortoiseSVN/bin')],
    function(const APath: string): Boolean
    begin
      Result := APath = Under('TortoiseSVN/bin/' + Exe('svn'));
    end);
  Assert.AreEqual(Under('TortoiseSVN/bin/' + Exe('svn')), mLocation.Executable);
  Assert.IsTrue(mLocation.Source = TAtlasVcsToolSource.KnownDir, 'leerer eigener Pfad = automatisch');
  mLocation := TAtlasVcsTools.Resolve('svn', '', Under('bin'), [Under('TortoiseSVN/bin')],
    function(const APath: string): Boolean
    begin
      Result := False;
    end);
  Assert.AreEqual('', mLocation.Executable);
  Assert.IsTrue(mLocation.Source = TAtlasVcsToolSource.None, 'nicht installiert');
end;

procedure TAtlasVcsToolCheckTests.ConfigureForgetsRememberedLocation;
begin
  TAtlasVcsTools.Preset(TAtlasVcsKind.Git, Under('alt/' + Exe('git')));
  try
    Assert.AreEqual(Under('alt/' + Exe('git')), TAtlasVcsTools.Find(TAtlasVcsKind.Git));
    TAtlasVcsTools.Configure(TAtlasVcsKind.Git, Under('neu/' + Exe('git')));
    Assert.AreEqual(Under('neu/' + Exe('git')), TAtlasVcsTools.Configured(TAtlasVcsKind.Git));
    Assert.IsTrue(TAtlasVcsTools.Where(TAtlasVcsKind.Git).Source = TAtlasVcsToolSource.ConfiguredMissing,
      'neuer Pfad gilt sofort, der alte Fund ist vergessen');
  finally
    TAtlasVcsTools.Configure(TAtlasVcsKind.Git, '');
    TAtlasVcsTools.Forget;
  end;
end;

procedure TAtlasVcsToolCheckTests.VersionArgumentsPerProgram;
begin
  Assert.AreEqual('--version', string.Join(' ', TAtlasVcsToolChecks.VersionArguments(TAtlasVcsKind.Git)));
  Assert.AreEqual('--version --quiet', string.Join(' ', TAtlasVcsToolChecks.VersionArguments(TAtlasVcsKind.Svn)));
end;

procedure TAtlasVcsToolCheckTests.ParsesGitAndSvnVersions;
begin
  Assert.AreEqual('git version 2.47.1',
    TAtlasVcsToolChecks.ParseVersion(TAtlasVcsKind.Git, 'git version 2.47.1.windows.1'#13#10));
  Assert.AreEqual('git version 2.43.0', TAtlasVcsToolChecks.ParseVersion(TAtlasVcsKind.Git, 'git version 2.43.0'#10));
  Assert.AreEqual('git version 2.39.3',
    TAtlasVcsToolChecks.ParseVersion(TAtlasVcsKind.Git, #10'git version 2.39.3 (Apple Git-146)'#10),
    'Zusatz in Klammern und Leerzeile davor');
  Assert.AreEqual('svn 1.14.3', TAtlasVcsToolChecks.ParseVersion(TAtlasVcsKind.Svn, '1.14.3'#13#10));
  Assert.AreEqual('svn 1.14.2', TAtlasVcsToolChecks.ParseVersion(TAtlasVcsKind.Svn, '1.14.2-SlikSvn'#10));
end;

procedure TAtlasVcsToolCheckTests.RejectsForeignOutput;
begin
  Assert.AreEqual('', TAtlasVcsToolChecks.ParseVersion(TAtlasVcsKind.Git, ''));
  Assert.AreEqual('', TAtlasVcsToolChecks.ParseVersion(TAtlasVcsKind.Git, 'usage: git [-v | --version]'));
  Assert.AreEqual('', TAtlasVcsToolChecks.ParseVersion(TAtlasVcsKind.Git, 'git version'));
  Assert.AreEqual('', TAtlasVcsToolChecks.ParseVersion(TAtlasVcsKind.Svn, 'svn, version 1.14.3 (r1914484)'),
    'ohne --quiet ist es nicht die erwartete Antwort');
  Assert.AreEqual('', TAtlasVcsToolChecks.ParseVersion(TAtlasVcsKind.None, '1.0'));
end;

procedure TAtlasVcsToolCheckTests.ClassifiesRunResults;
var
  mCheck: TAtlasVcsToolCheck;
  mGit: TAtlasVcsToolLocation;
begin
  mGit := Found(Under('bin/' + Exe('git')));
  mCheck := TAtlasVcsToolChecks.Classify(TAtlasVcsKind.Git, mGit, Run(TAtlasVcsOutcome.Ok, 0, 'git version 2.47.1'));
  Assert.IsTrue(mCheck.State = TAtlasVcsToolState.Found);
  Assert.AreEqual('git version 2.47.1', mCheck.Version);
  Assert.AreEqual(mGit.Executable, mCheck.Location.Executable);
  mCheck := TAtlasVcsToolChecks.Classify(TAtlasVcsKind.Git, mGit, Run(TAtlasVcsOutcome.Ok, 0, 'Hallo'));
  Assert.IsTrue(mCheck.State = TAtlasVcsToolState.NotRecognized, 'falsches Programm unter dem Namen');
  mCheck := TAtlasVcsToolChecks.Classify(TAtlasVcsKind.Git, mGit, Run(TAtlasVcsOutcome.Ok, 128, ''));
  Assert.IsTrue(mCheck.State = TAtlasVcsToolState.StartFailed);
  Assert.AreEqual(128, mCheck.ExitCode);
  mCheck := TAtlasVcsToolChecks.Classify(TAtlasVcsKind.Git, mGit, Run(TAtlasVcsOutcome.Failed, -1, ''));
  Assert.IsTrue(mCheck.State = TAtlasVcsToolState.StartFailed, 'Start misslungen');
  mCheck := TAtlasVcsToolChecks.Classify(TAtlasVcsKind.Git, mGit, Run(TAtlasVcsOutcome.TimedOut, -1, ''));
  Assert.IsTrue(mCheck.State = TAtlasVcsToolState.NoAnswer);
  mCheck := TAtlasVcsToolChecks.Classify(TAtlasVcsKind.Git, mGit, Run(TAtlasVcsOutcome.ToolMissing, -1, ''));
  Assert.IsTrue(mCheck.State = TAtlasVcsToolState.Missing);
  mCheck := TAtlasVcsToolChecks.Classify(TAtlasVcsKind.Svn, TAtlasVcsToolLocation.Empty,
    Run(TAtlasVcsOutcome.Ok, 0, '1.14.3'));
  Assert.IsTrue(mCheck.State = TAtlasVcsToolState.Missing, 'ohne Programm zählt keine Ausgabe');
  Assert.AreEqual(-1, mCheck.ExitCode);
end;

procedure TAtlasVcsToolCheckTests.CheckRunsVersionQueryInProgramFolder;
var
  mRunner: TFakeRunner;
  mKeep: IAtlasVcsRunner;
  mCheck: TAtlasVcsToolCheck;
begin
  mRunner := TFakeRunner.Create;
  mKeep := mRunner;
  mRunner.Answer := Run(TAtlasVcsOutcome.Ok, 0, '1.14.3'#13#10);
  mCheck := TAtlasVcsToolChecks.Check(TAtlasVcsKind.Svn, Found(Under('TortoiseSVN/bin/' + Exe('svn'))), mKeep);
  Assert.IsTrue(mCheck.State = TAtlasVcsToolState.Found);
  Assert.AreEqual('svn 1.14.3', mCheck.Version);
  Assert.AreEqual(Under('TortoiseSVN/bin/' + Exe('svn')), mRunner.Executable);
  Assert.AreEqual('--version --quiet', mRunner.Arguments);
  Assert.AreEqual(Under('TortoiseSVN/bin'), mRunner.WorkingDir);
  Assert.AreEqual(Integer(TAtlasVcsToolChecks.TimeoutMs), Integer(mRunner.TimeoutMs));
end;

procedure TAtlasVcsToolCheckTests.CheckWithoutProgramRunsNothing;
var
  mRunner: TFakeRunner;
  mKeep: IAtlasVcsRunner;
  mLocation: TAtlasVcsToolLocation;
  mCheck: TAtlasVcsToolCheck;
begin
  mRunner := TFakeRunner.Create;
  mKeep := mRunner;
  mLocation := TAtlasVcsToolLocation.Empty;
  mLocation.Source := TAtlasVcsToolSource.ConfiguredMissing;
  mLocation.Configured := Under('fehlt/' + Exe('git'));
  mCheck := TAtlasVcsToolChecks.Check(TAtlasVcsKind.Git, mLocation, mKeep);
  Assert.IsTrue(mCheck.State = TAtlasVcsToolState.Missing);
  Assert.AreEqual(Under('fehlt/' + Exe('git')), mCheck.Location.Configured);
  Assert.AreEqual(0, mRunner.Calls, 'kein Prozess ohne Programm');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasVcsToolCheckTests);

end.
