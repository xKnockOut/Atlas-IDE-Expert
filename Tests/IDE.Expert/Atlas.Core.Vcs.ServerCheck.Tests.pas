unit Atlas.Core.Vcs.ServerCheck.Tests;

// Zugang zum Server der Versionsverwaltung (#1287) ohne Netz und Prozess:
// Zuordnung von Exit-Code und Fehlerkennung zu den Zuständen für Git und SVN
// aus Fixture-Texten, Argumente und Umgebung ohne Rückfrage, Zeitgrenze und
// Ablauf der Prüfung über eine Attrappe von IAtlasVcsRunner, Adressen ohne
// Zugangsdaten und die Befehlszeile für „Anmelden …“.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasVcsServerCheckTests = class
  public
    /// <summary>Abnahme: Git-Fehlertexte (englisch und deutsch) → Anmeldung nötig, nicht erreichbar, kein
    /// Server; Zeitgrenze = nicht erreichbar.</summary>
    [Test]
    procedure GitStatesFromFixtures;
    /// <summary>Abnahme: SVN-Fehlerkennungen E170001/E215004 → Anmeldung nötig, E170013/E731001 → nicht erreichbar.
    /// </summary>
    [Test]
    procedure SvnStatesFromFixtures;
    /// <summary>fetch, pull und push melden LoginNeeded statt Failed.</summary>
    [Test]
    procedure OutcomeMarksMissingLogin;
    /// <summary>Abnahme: GIT_TERMINAL_PROMPT=0 und GCM_INTERACTIVE=never ersetzen vorhandene Werte.</summary>
    [Test]
    procedure EnvironmentNeverPrompts;
    /// <summary>Rechner und Remote aus Adressen; Benutzer und Kennwort fallen weg.</summary>
    [Test]
    procedure HostsRemotesAndCredentials;
    /// <summary>Abnahme: Git-Prüfung mit Remote des verfolgten Branchs, ls-remote ohne Rückfrage, Zeitgrenze
    /// 10 s.</summary>
    [Test]
    procedure GitCheckRunsLsRemote;
    /// <summary>Ohne Remote „kein Server“, ohne Programm „Programm fehlt“, Zeitgrenze „nicht erreichbar“.</summary>
    [Test]
    procedure GitCheckWithoutRemoteOrTool;
    /// <summary>Abnahme: SVN-Prüfung mit Repository-Wurzel und info --non-interactive ^/.</summary>
    [Test]
    procedure SvnCheckRunsInfo;
    /// <summary>„Anmelden …“: sichtbare Konsole mit git fetch bzw. svn info "^/", unsicherer Remote abgelehnt.
    /// </summary>
    [Test]
    procedure LoginCommandLines;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.ServerAccess,
  Atlas.Core.Vcs.ServerCheck;

type
  /// <summary>Antwortet je Befehl (erstes Wort ohne Optionen davor bzw. Text in den Argumenten) mit Ausgabe,
  /// Exit-Code und stderr.</summary>
  TScriptedRunner = class(TInterfacedObject, IAtlasVcsRunner)
  public
    Calls: TArray<string>;
    Timeouts: TArray<Cardinal>;
    Keys: TArray<string>;
    Outputs: TArray<string>;
    ExitCodes: TArray<Integer>;
    Errors: TArray<string>;
    Outcomes: TArray<TAtlasVcsOutcome>;
    procedure Answer(const AKey, AOutput: string; AExitCode: Integer; const AError: string;
      AOutcome: TAtlasVcsOutcome);
    function Run(const AExecutable: string; const AArguments: TArray<string>; const AWorkingDir: string;
      ATimeoutMs: Cardinal): TAtlasVcsRunResult;
  end;

procedure TScriptedRunner.Answer(const AKey, AOutput: string; AExitCode: Integer; const AError: string;
  AOutcome: TAtlasVcsOutcome);
begin
  Keys := Keys + [AKey];
  Outputs := Outputs + [AOutput];
  ExitCodes := ExitCodes + [AExitCode];
  Errors := Errors + [AError];
  Outcomes := Outcomes + [AOutcome];
end;

function TScriptedRunner.Run(const AExecutable: string; const AArguments: TArray<string>;
  const AWorkingDir: string; ATimeoutMs: Cardinal): TAtlasVcsRunResult;
var
  mCall: string;
  mIndex: Integer;
begin
  mCall := string.Join(' ', AArguments);
  Calls := Calls + [mCall];
  Timeouts := Timeouts + [ATimeoutMs];
  Result := TAtlasVcsRunResult.Make(TAtlasVcsOutcome.Ok, 0, nil);
  // Der zuletzt eingetragene passende Schlüssel gewinnt ("remote get-url" nach "remote").
  for mIndex := 0 to High(Keys) do
    if Pos(Keys[mIndex], mCall) = 1 then
    begin
      Result := TAtlasVcsRunResult.Make(Outcomes[mIndex], ExitCodes[mIndex],
        TEncoding.UTF8.GetBytes(Outputs[mIndex]));
      Result.ErrorText := Errors[mIndex];
    end;
end;

function Answer(AOutcome: TAtlasVcsOutcome; AExitCode: Integer; const AError: string): TAtlasVcsRunResult;
begin
  Result := TAtlasVcsRunResult.Make(AOutcome, AExitCode, nil);
  Result.ErrorText := AError;
end;

function GitState(AExitCode: Integer; const AError: string): TAtlasVcsServerState;
begin
  Result := TAtlasVcsServerAccess.State(TAtlasVcsKind.Git, Answer(TAtlasVcsOutcome.Ok, AExitCode, AError));
end;

function SvnState(AExitCode: Integer; const AError: string): TAtlasVcsServerState;
begin
  Result := TAtlasVcsServerAccess.State(TAtlasVcsKind.Svn, Answer(TAtlasVcsOutcome.Ok, AExitCode, AError));
end;

{ TAtlasVcsServerCheckTests }

procedure TAtlasVcsServerCheckTests.GitStatesFromFixtures;
begin
  Assert.IsTrue(GitState(0, '') = TAtlasVcsServerState.Reachable);
  Assert.IsTrue(GitState(128, 'remote: HTTP Basic: Access denied' + sLineBreak +
    'fatal: Authentication failed for ''https://gitlab.firma.local/kasse.git/''') =
    TAtlasVcsServerState.LoginNeeded);
  Assert.IsTrue(GitState(128, 'fatal: could not read Username for ''https://github.com'': terminal prompts disabled') =
    TAtlasVcsServerState.LoginNeeded);
  Assert.IsTrue(GitState(128, 'git@github.com: Permission denied (publickey).' + sLineBreak +
    'fatal: Could not read from remote repository.') = TAtlasVcsServerState.LoginNeeded);
  Assert.IsTrue(GitState(128, 'fatal: Authentifizierung für ''https://github.com/x/y.git/'' fehlgeschlagen') =
    TAtlasVcsServerState.LoginNeeded, 'deutsche Meldung von git');
  Assert.IsTrue(GitState(128, 'fatal: unable to access ''https://git.firma.local/kasse.git/'': ' +
    'Could not resolve host: git.firma.local') = TAtlasVcsServerState.Unreachable);
  Assert.IsTrue(GitState(128, 'ssh: connect to host git.firma.local port 22: Connection timed out') =
    TAtlasVcsServerState.Unreachable);
  Assert.IsTrue(GitState(128, 'fatal: ''origin'' does not appear to be a git repository') =
    TAtlasVcsServerState.NoServer);
  Assert.IsTrue(GitState(128, 'fatal: something else') = TAtlasVcsServerState.Failed);
  Assert.IsTrue(TAtlasVcsServerAccess.State(TAtlasVcsKind.Git, Answer(TAtlasVcsOutcome.TimedOut, -1, '')) =
    TAtlasVcsServerState.Unreachable, 'Zeitgrenze');
  Assert.IsTrue(TAtlasVcsServerAccess.State(TAtlasVcsKind.Git, Answer(TAtlasVcsOutcome.ToolMissing, -1, '')) =
    TAtlasVcsServerState.ToolMissing);
  Assert.IsTrue(TAtlasVcsServerAccess.State(TAtlasVcsKind.Git, Answer(TAtlasVcsOutcome.Cancelled, -1, '')) =
    TAtlasVcsServerState.Failed);
end;

procedure TAtlasVcsServerCheckTests.SvnStatesFromFixtures;
begin
  Assert.IsTrue(SvnState(0, '') = TAtlasVcsServerState.Reachable);
  Assert.IsTrue(SvnState(1, 'svn: E170001: Authentication required for ''<https://svn.firma.local:443> Firma''') =
    TAtlasVcsServerState.LoginNeeded);
  Assert.IsTrue(SvnState(1, 'svn: E215004: No more credentials or we tried too many times.' + sLineBreak +
    'Authentication failed') = TAtlasVcsServerState.LoginNeeded);
  Assert.IsTrue(SvnState(1, 'svn: E170013: Unable to connect to a repository at URL ''https://svn.firma.local/x''' +
    sLineBreak + 'svn: E731001: Unbekannter Host') = TAtlasVcsServerState.Unreachable);
  Assert.IsTrue(SvnState(1, 'svn: E155007: ''C:\Projekte\Kasse'' is not a working copy') =
    TAtlasVcsServerState.NoServer);
  Assert.IsTrue(SvnState(1, 'svn: E000001: anderes') = TAtlasVcsServerState.Failed);
end;

procedure TAtlasVcsServerCheckTests.OutcomeMarksMissingLogin;
begin
  Assert.IsTrue(TAtlasVcsServerAccess.OutcomeOf(TAtlasVcsKind.Git, Answer(TAtlasVcsOutcome.Ok, 0, '')) =
    TAtlasVcsOutcome.Ok);
  Assert.IsTrue(TAtlasVcsServerAccess.OutcomeOf(TAtlasVcsKind.Git, Answer(TAtlasVcsOutcome.Ok, 128,
    'fatal: Authentication failed')) = TAtlasVcsOutcome.LoginNeeded);
  Assert.IsTrue(TAtlasVcsServerAccess.OutcomeOf(TAtlasVcsKind.Git, Answer(TAtlasVcsOutcome.Ok, 1,
    'error: failed to push some refs')) = TAtlasVcsOutcome.Failed);
  Assert.IsTrue(TAtlasVcsServerAccess.OutcomeOf(TAtlasVcsKind.Svn, Answer(TAtlasVcsOutcome.Ok, 1,
    'svn: E215004: No more credentials')) = TAtlasVcsOutcome.LoginNeeded);
  Assert.IsTrue(TAtlasVcsServerAccess.OutcomeOf(TAtlasVcsKind.Git, Answer(TAtlasVcsOutcome.TimedOut, -1, '')) =
    TAtlasVcsOutcome.TimedOut);
end;

procedure TAtlasVcsServerCheckTests.EnvironmentNeverPrompts;
var
  mEnvironment: TArray<string>;
begin
  mEnvironment := TAtlasVcsServerAccess.NoPromptEnvironment(TArray<string>.Create('=C:=C:\Projekte',
    'Path=C:\Windows', 'git_terminal_prompt=1', 'GCM_INTERACTIVE=auto'));
  Assert.AreEqual(4, Integer(Length(mEnvironment)));
  Assert.AreEqual('=C:=C:\Projekte', mEnvironment[0], 'Laufwerkseintrag bleibt');
  Assert.AreEqual('Path=C:\Windows', mEnvironment[1]);
  Assert.AreEqual('GIT_TERMINAL_PROMPT=0', mEnvironment[2]);
  Assert.AreEqual('GCM_INTERACTIVE=never', mEnvironment[3]);
  Assert.AreEqual('', TAtlasVcsServerAccess.VariableName('=C:=C:\Projekte'));
  Assert.AreEqual('Path', TAtlasVcsServerAccess.VariableName('Path=C:\Windows'));
  mEnvironment := TAtlasVcsServerAccess.NoPromptEnvironment(nil);
  Assert.AreEqual(2, Integer(Length(mEnvironment)));
end;

procedure TAtlasVcsServerCheckTests.HostsRemotesAndCredentials;
var
  mCheck: TAtlasVcsServerCheck;
begin
  Assert.AreEqual('github.com', TAtlasVcsServerChecks.HostOf('https://github.com/xKnockOut/Atlas-IDE-Expert.git'));
  Assert.AreEqual('github.com', TAtlasVcsServerChecks.HostOf('git@github.com:xKnockOut/Atlas-IDE-Expert.git'));
  Assert.AreEqual('git.firma.local', TAtlasVcsServerChecks.HostOf('ssh://git@Git.Firma.local:2222/kasse.git'));
  Assert.AreEqual('git.firma.local', TAtlasVcsServerChecks.HostOf('https://marco:geheim@git.firma.local:8443/k'));
  Assert.AreEqual('', TAtlasVcsServerChecks.HostOf('C:\Repos\Kasse.git'));
  Assert.AreEqual('', TAtlasVcsServerChecks.HostOf('file:///C:/Repos/Kasse.git'));
  Assert.AreEqual('', TAtlasVcsServerChecks.HostOf('/srv/git/kasse.git'));
  Assert.AreEqual('https://git.firma.local/kasse.git',
    TAtlasVcsServerChecks.WithoutCredentials('https://marco:ge@heim@git.firma.local/kasse.git'));
  Assert.AreEqual('https://svn.firma.local/repos', TAtlasVcsServerChecks.WithoutCredentials(
    'https://svn.firma.local/repos'));
  Assert.AreEqual('git@github.com:x/y.git', TAtlasVcsServerChecks.WithoutCredentials('git@github.com:x/y.git'));
  Assert.AreEqual('upstream', TAtlasVcsServerChecks.RemoteFor('upstream/main',
    TArray<string>.Create('origin', 'upstream')));
  Assert.AreEqual('team/a', TAtlasVcsServerChecks.RemoteFor('team/a/main', TArray<string>.Create('team', 'team/a')),
    'längstes Remote');
  Assert.AreEqual('origin', TAtlasVcsServerChecks.RemoteFor('', TArray<string>.Create('fork', 'origin')));
  Assert.AreEqual('fork', TAtlasVcsServerChecks.RemoteFor('', TArray<string>.Create('fork')));
  Assert.AreEqual('', TAtlasVcsServerChecks.RemoteFor('origin/main', nil));
  mCheck := TAtlasVcsServerCheck.Empty;
  mCheck.Kind := TAtlasVcsKind.Git;
  mCheck.Remote := 'origin';
  mCheck.Url := 'https://github.com/x/y.git';
  Assert.AreEqual('origin · github.com', mCheck.ServerText);
  mCheck.Url := 'C:\Repos\Kasse.git';
  Assert.AreEqual('origin · C:\Repos\Kasse.git', mCheck.ServerText);
  mCheck.Kind := TAtlasVcsKind.Svn;
  mCheck.Url := 'https://svn.firma.local/repos';
  Assert.AreEqual('https://svn.firma.local/repos', mCheck.ServerText);
end;

procedure TAtlasVcsServerCheckTests.GitCheckRunsLsRemote;
var
  mRunner: TScriptedRunner;
  mRef: IAtlasVcsRunner;
  mCheck: TAtlasVcsServerCheck;
begin
  mRunner := TScriptedRunner.Create;
  mRef := mRunner;
  mRunner.Answer('remote', 'origin'#10'upstream'#10, 0, '', TAtlasVcsOutcome.Ok);
  mRunner.Answer('rev-parse', 'upstream/main'#10, 0, '', TAtlasVcsOutcome.Ok);
  mRunner.Answer('remote get-url', 'https://marco:token@github.com/x/y.git'#10, 0, '', TAtlasVcsOutcome.Ok);
  mRunner.Answer('-c credential.interactive=never', '', 128,
    'fatal: could not read Username for ''https://github.com'': terminal prompts disabled', TAtlasVcsOutcome.Ok);
  mCheck := TAtlasVcsServerChecks.Check(mRef, TAtlasVcsKind.Git, 'git.exe', 'C:\Projekte\Kasse',
    TAtlasVcsServerChecks.TimeoutMs, EncodeDate(2026, 10, 28));
  Assert.AreEqual(4, Integer(Length(mRunner.Calls)));
  Assert.AreEqual('remote', mRunner.Calls[0]);
  Assert.AreEqual('rev-parse --abbrev-ref --symbolic-full-name @{u}', mRunner.Calls[1]);
  Assert.AreEqual('remote get-url upstream', mRunner.Calls[2]);
  Assert.AreEqual('-c credential.interactive=never -c core.askPass= ls-remote --heads upstream', mRunner.Calls[3]);
  Assert.IsTrue(mRunner.Timeouts[3] = 10000, 'Zeitgrenze 10 s');
  Assert.IsTrue(mCheck.State = TAtlasVcsServerState.LoginNeeded);
  Assert.AreEqual('upstream', mCheck.Remote);
  Assert.AreEqual('https://github.com/x/y.git', mCheck.Url, 'ohne Zugangsdaten');
  Assert.AreEqual('upstream · github.com', mCheck.ServerText);
  Assert.IsTrue(mCheck.CanLogin);
  Assert.IsTrue(mCheck.CheckedAt = EncodeDate(2026, 10, 28));
  // Mit Anmeldung: erreichbar.
  mRunner.ExitCodes[3] := 0;
  mRunner.Errors[3] := '';
  mCheck := TAtlasVcsServerChecks.Check(mRef, TAtlasVcsKind.Git, 'git.exe', 'C:\Projekte\Kasse',
    TAtlasVcsServerChecks.TimeoutMs, Now);
  Assert.IsTrue(mCheck.State = TAtlasVcsServerState.Reachable);
  Assert.IsFalse(mCheck.CanLogin);
end;

procedure TAtlasVcsServerCheckTests.GitCheckWithoutRemoteOrTool;
var
  mRunner: TScriptedRunner;
  mRef: IAtlasVcsRunner;
  mCheck: TAtlasVcsServerCheck;
begin
  mRunner := TScriptedRunner.Create;
  mRef := mRunner;
  mRunner.Answer('remote', '', 0, '', TAtlasVcsOutcome.Ok);
  mCheck := TAtlasVcsServerChecks.Check(mRef, TAtlasVcsKind.Git, 'git.exe', 'C:\Projekte\Kasse', 10000, Now);
  Assert.IsTrue(mCheck.State = TAtlasVcsServerState.NoServer);
  Assert.AreEqual(2, Integer(Length(mRunner.Calls)), 'ohne Remote keine Abfrage beim Server');
  mCheck := TAtlasVcsServerChecks.Check(mRef, TAtlasVcsKind.Git, '', 'C:\Projekte\Kasse', 10000, Now);
  Assert.IsTrue(mCheck.State = TAtlasVcsServerState.ToolMissing);
  Assert.AreEqual(2, Integer(Length(mRunner.Calls)));
  // Zeitgrenze: nicht erreichbar.
  mRunner.Outputs[0] := 'origin'#10;
  mRunner.Answer('-c', '', -1, '', TAtlasVcsOutcome.TimedOut);
  mCheck := TAtlasVcsServerChecks.Check(mRef, TAtlasVcsKind.Git, 'git.exe', 'C:\Projekte\Kasse', 10000, Now);
  Assert.IsTrue(mCheck.State = TAtlasVcsServerState.Unreachable);
  Assert.AreEqual('origin', mCheck.Remote, 'ohne verfolgten Branch origin');
  mCheck := TAtlasVcsServerChecks.Check(mRef, TAtlasVcsKind.None, 'git.exe', 'C:\Projekte\Kasse', 10000, Now);
  Assert.IsTrue(mCheck.State = TAtlasVcsServerState.NoServer);
end;

procedure TAtlasVcsServerCheckTests.SvnCheckRunsInfo;
var
  mRunner: TScriptedRunner;
  mRef: IAtlasVcsRunner;
  mCheck: TAtlasVcsServerCheck;
begin
  mRunner := TScriptedRunner.Create;
  mRef := mRunner;
  mRunner.Answer('info --show-item', 'https://svn.firma.local/repos/kasse'#13#10, 0, '', TAtlasVcsOutcome.Ok);
  mRunner.Answer('info --non-interactive', '', 1, 'svn: E215004: No more credentials or we tried too many times.',
    TAtlasVcsOutcome.Ok);
  mCheck := TAtlasVcsServerChecks.Check(mRef, TAtlasVcsKind.Svn, 'svn.exe', 'C:\Projekte\Kasse', 10000, Now);
  Assert.AreEqual('info --show-item repos-root-url --non-interactive', mRunner.Calls[0]);
  Assert.AreEqual('info --non-interactive ^/', mRunner.Calls[1]);
  Assert.IsTrue(mCheck.State = TAtlasVcsServerState.LoginNeeded);
  Assert.AreEqual('https://svn.firma.local/repos/kasse', mCheck.ServerText);
  Assert.IsTrue(mCheck.CanLogin);
  // Keine Arbeitskopie: kein Server.
  mRunner.ExitCodes[0] := 1;
  mRunner.Errors[0] := 'svn: E155007: ''C:\Projekte\Kasse'' is not a working copy';
  mCheck := TAtlasVcsServerChecks.Check(mRef, TAtlasVcsKind.Svn, 'svn.exe', 'C:\Projekte\Kasse', 10000, Now);
  Assert.IsTrue(mCheck.State = TAtlasVcsServerState.NoServer);
end;

procedure TAtlasVcsServerCheckTests.LoginCommandLines;
begin
  Assert.AreEqual('"C:\Windows\system32\cmd.exe" /s /k ""C:\Program Files\Git\cmd\git.exe" fetch origin"',
    TAtlasVcsServerChecks.LoginCommandLine('C:\Windows\system32\cmd.exe', 'C:\Program Files\Git\cmd\git.exe',
    TAtlasVcsKind.Git, 'origin'));
  Assert.AreEqual('"cmd.exe" /s /k ""C:\Program Files\TortoiseSVN\bin\svn.exe" info "^/""',
    TAtlasVcsServerChecks.LoginCommandLine('cmd.exe', 'C:\Program Files\TortoiseSVN\bin\svn.exe',
    TAtlasVcsKind.Svn, ''));
  Assert.AreEqual('', TAtlasVcsServerChecks.LoginCommandLine('cmd.exe', 'git.exe', TAtlasVcsKind.Git,
    'origin & del *'), 'unsicherer Remote');
  Assert.AreEqual('', TAtlasVcsServerChecks.LoginCommandLine('cmd.exe', 'git.exe', TAtlasVcsKind.Git,
    '--upload-pack'));
  Assert.AreEqual('', TAtlasVcsServerChecks.LoginCommandLine('', 'git.exe', TAtlasVcsKind.Git, 'origin'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasVcsServerCheckTests);

end.
