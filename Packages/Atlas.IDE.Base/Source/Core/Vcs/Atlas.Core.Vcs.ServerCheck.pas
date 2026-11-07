unit Atlas.Core.Vcs.ServerCheck;

// Zugang zum Server prüfen (#1287), für die Tabelle „Server“ der Seite
// Versionsverwaltung. Nur auf Klick, einmal im Hintergrund, Zeitgrenze 10 s,
// ohne Rückfrage nach Zugangsdaten:
//   Git  remote, rev-parse --abbrev-ref --symbolic-full-name @{u} und
//        remote get-url <Remote> (lokal), dann
//        -c credential.interactive=never -c core.askPass= ls-remote --heads <Remote>
//   SVN  info --show-item repos-root-url (lokal), dann info --non-interactive ^/
// Der Prozessläufer setzt GIT_TERMINAL_PROMPT=0 und GCM_INTERACTIVE=never.
// Zustände aus Exit-Code und festen Fehlerkennungen
// (Atlas.Core.Vcs.ServerAccess); stderr geht nirgends hin.
// „Anmelden …“ öffnet eine sichtbare Konsole mit git fetch <Remote> bzw.
// svn info ^/, damit Git Credential Manager bzw. svn wie gewohnt fragen und
// die Anmeldung speichern; Atlas speichert keine Zugangsdaten.
// Nur im Plugin (der Server übersetzt die Unit nicht).

interface

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.ServerAccess;

type
  /// <summary>Ergebnis der Prüfung einer Arbeitskopie.</summary>
  TAtlasVcsServerCheck = record
    Kind: TAtlasVcsKind;
    /// <summary>Wurzel der Arbeitskopie.</summary>
    Root: string;
    /// <summary>Git: Remote des verfolgten Branchs (sonst origin bzw. das erste); SVN: ''.</summary>
    Remote: string;
    /// <summary>Git: Adresse des Remotes; SVN: Repository-Wurzel. Ohne Benutzer und Kennwort.</summary>
    Url: string;
    State: TAtlasVcsServerState;
    /// <summary>Zeitpunkt der Prüfung (Ortszeit); 0 = nie geprüft.</summary>
    CheckedAt: TDateTime;
    class function Empty: TAtlasVcsServerCheck; static;
    /// <summary>„origin · github.com“ bzw. die Repository-Wurzel; '' ohne Server.</summary>
    function ServerText: string;
    /// <summary>„Anmelden …“ ist möglich: Anmeldung nötig und ein Server bekannt.</summary>
    function CanLogin: Boolean;
  end;

  TAtlasVcsServerChecks = class
  public const
    /// <summary>Zeitgrenze der Prüfung.</summary>
    cTimeoutMs = 10000;
  public
    /// <summary>Rechnername aus einer Adresse (https://, ssh://, git@host:pfad); '' für lokale Pfade.</summary>
    class function HostOf(const AUrl: string): string; static;
    /// <summary>AUrl ohne Benutzer und Kennwort (https://user:token@host/… → https://host/…).</summary>
    class function WithoutCredentials(const AUrl: string): string; static;
    /// <summary>Remote zu einem verfolgten Branch wie "origin/main": das längste Remote aus ARemotes, mit dem
    /// AUpstream beginnt; ohne Treffer origin bzw. das erste Remote; '' ohne Remotes.</summary>
    class function RemoteFor(const AUpstream: string; const ARemotes: TArray<string>): string; static;
    /// <summary>Name, der sich gefahrlos auf eine Befehlszeile setzen lässt (Buchstaben, Ziffern, . _ - /).
    /// </summary>
    class function SafeRemote(const AName: string): Boolean; static;
    /// <summary>Argumente der Prüfung für git (ARemote) bzw. svn.</summary>
    class function ProbeArguments(AKind: TAtlasVcsKind; const ARemote: string): TArray<string>; static;
    /// <summary>Befehlszeile für „Anmelden …“: AShell (cmd.exe) /s /k mit git fetch &lt;Remote&gt; bzw.
    /// svn info "^/"; das Fenster bleibt offen, bis man es schließt. '' bei unsicherem Remote.</summary>
    class function LoginCommandLine(const AShell, AExecutable: string; AKind: TAtlasVcsKind;
      const ARemote: string): string; static;
    /// <summary>Prüft die Arbeitskopie ARoot (startet Prozesse: nur im Hintergrund). AExecutable '' = Programm
    /// fehlt. ANow: Zeitpunkt für CheckedAt.</summary>
    class function Check(const ARunner: IAtlasVcsRunner; AKind: TAtlasVcsKind; const AExecutable, ARoot: string;
      ATimeoutMs: Cardinal; ANow: TDateTime): TAtlasVcsServerCheck; static;
  end;

implementation

uses
  Atlas.Core.Vcs.Internals.Text;

{ TAtlasVcsServerCheck }

class function TAtlasVcsServerCheck.Empty: TAtlasVcsServerCheck;
begin
  Result.Kind := TAtlasVcsKind.None;
  Result.Root := '';
  Result.Remote := '';
  Result.Url := '';
  Result.State := TAtlasVcsServerState.Unknown;
  Result.CheckedAt := 0;
end;

function TAtlasVcsServerCheck.ServerText: string;
var
  mHost: string;
begin
  if Kind = TAtlasVcsKind.Svn then
  begin
    Exit(Url);
  end;
  if Remote = '' then
  begin
    Exit('');
  end;
  mHost := TAtlasVcsServerChecks.HostOf(Url);
  if mHost = '' then
  begin
    mHost := Url;
  end;
  if mHost = '' then
  begin
    Exit(Remote);
  end;
  Result := Remote + ' · ' + mHost;
end;

function TAtlasVcsServerCheck.CanLogin: Boolean;
begin
  Result := (State = TAtlasVcsServerState.LoginNeeded) and (Root <> '') and
    ((Kind = TAtlasVcsKind.Svn) or ((Kind = TAtlasVcsKind.Git) and (Remote <> '')));
end;

{ TAtlasVcsServerChecks }

class function TAtlasVcsServerChecks.WithoutCredentials(const AUrl: string): string;
var
  mStart, mEnd: Integer;
  mAuthority: string;
begin
  Result := Trim(AUrl);
  mStart := Pos('://', Result);
  if mStart = 0 then
  begin
    Exit;
  end;
  Inc(mStart, 3);
  mEnd := Pos('/', Result, mStart);
  if mEnd = 0 then
  begin
    mEnd := Length(Result) + 1;
  end;
  // Bis zum letzten „@“ vor dem Pfad stehen Benutzer und Kennwort.
  mAuthority := Copy(Result, mStart, mEnd - mStart);
  if LastDelimiter('@', mAuthority) = 0 then
  begin
    Exit;
  end;
  Result := Copy(Result, 1, mStart - 1) + Copy(mAuthority, LastDelimiter('@', mAuthority) + 1, MaxInt) +
    Copy(Result, mEnd, MaxInt);
end;

/// <summary>Rechner aus dem Teil hinter "schema://" ohne Benutzer und Port (IPv6 in eckigen Klammern bleibt).
/// </summary>
function AuthorityHost(const AText: string): string;
var
  mEnd, mAt, mColon: Integer;
begin
  Result := AText;
  mEnd := Pos('/', Result);
  if mEnd > 0 then
  begin
    Result := Copy(Result, 1, mEnd - 1);
  end;
  mAt := LastDelimiter('@', Result);
  if mAt > 0 then
  begin
    Result := Copy(Result, mAt + 1, MaxInt);
  end;
  mColon := LastDelimiter(':', Result);
  if (mColon > 0) and (mColon > LastDelimiter(']', Result)) then
  begin
    Result := Copy(Result, 1, mColon - 1);
  end;
  Result := LowerCase(Result);
end;

/// <summary>Rechner der scp-Form [benutzer@]host:pfad; '' für ein Laufwerk wie C:\ oder einen Pfad.</summary>
function ScpHost(const AText: string): string;
var
  mColon, mBackslash: Integer;
  mHost: string;
begin
  Result := '';
  mColon := Pos(':', AText);
  mBackslash := Pos('\', AText);
  if (mColon <= 2) or ((mBackslash > 0) and (mBackslash < mColon)) then
  begin
    Exit;
  end;
  mHost := Copy(AText, 1, mColon - 1);
  if Pos('/', mHost) = 0 then
  begin
    Result := LowerCase(Copy(mHost, LastDelimiter('@', mHost) + 1, MaxInt));
  end;
end;

class function TAtlasVcsServerChecks.HostOf(const AUrl: string): string;
var
  mText: string;
  mScheme: Integer;
begin
  mText := Trim(AUrl);
  mScheme := Pos('://', mText);
  if mScheme = 0 then
  begin
    Result := ScpHost(mText);
  end
  else if SameText(Copy(mText, 1, mScheme - 1), 'file') then
  begin
    Result := '';
  end
  else
  begin
    Result := AuthorityHost(Copy(mText, mScheme + 3, MaxInt));
  end;
end;

class function TAtlasVcsServerChecks.RemoteFor(const AUpstream: string; const ARemotes: TArray<string>): string;
var
  mRemote: string;
begin
  Result := '';
  for mRemote in ARemotes do
  begin
    if (mRemote <> '') and (Length(mRemote) > Length(Result)) and
      (Copy(AUpstream, 1, Length(mRemote) + 1) = mRemote + '/') then
    begin
      Result := mRemote;
    end;
  end;
  if Result <> '' then
  begin
    Exit;
  end;
  for mRemote in ARemotes do
  begin
    if mRemote = 'origin' then
    begin
      Exit(mRemote);
    end;
  end;
  if Length(ARemotes) > 0 then
  begin
    Result := ARemotes[0];
  end;
end;

class function TAtlasVcsServerChecks.SafeRemote(const AName: string): Boolean;
var
  mIndex: Integer;
begin
  Result := (AName <> '') and (AName[1] <> '-');
  for mIndex := 1 to Length(AName) do
  begin
    if not CharInSet(AName[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '.', '_', '-', '/']) then
    begin
      Exit(False);
    end;
  end;
end;

class function TAtlasVcsServerChecks.ProbeArguments(AKind: TAtlasVcsKind; const ARemote: string): TArray<string>;
begin
  if AKind = TAtlasVcsKind.Svn then
  begin
    Result := TArray<string>.Create('info', '--non-interactive', '^/');
  end
  else
  begin
    Result := TArray<string>.Create('-c', 'credential.interactive=never', '-c', 'core.askPass=', 'ls-remote',
      '--heads', ARemote);
  end;
end;

class function TAtlasVcsServerChecks.LoginCommandLine(const AShell, AExecutable: string; AKind: TAtlasVcsKind;
  const ARemote: string): string;
var
  mCommand: string;
begin
  Result := '';
  if (AShell = '') or (AExecutable = '') or (Pos('"', AExecutable) > 0) then
  begin
    Exit;
  end;
  if AKind = TAtlasVcsKind.Svn then
  begin
    // In Anführungszeichen ist ^ für cmd kein Fluchtzeichen.
    mCommand := '"' + AExecutable + '" info "^/"';
  end
  else if (AKind = TAtlasVcsKind.Git) and SafeRemote(ARemote) then
  begin
    mCommand := '"' + AExecutable + '" fetch ' + ARemote;
  end
  else
  begin
    Exit;
  end;
  // /s: cmd nimmt nur die äußeren Anführungszeichen weg; /k: das Fenster bleibt offen.
  Result := '"' + AShell + '" /s /k "' + mCommand + '"';
end;

function FirstLine(const AOutput: TBytes): string;
var
  mText: string;
  mEnd: Integer;
begin
  mText := VcsUtf8(AOutput);
  mEnd := Pos(#10, mText);
  if mEnd > 0 then
  begin
    mText := Copy(mText, 1, mEnd - 1);
  end;
  Result := Trim(mText);
end;

function Lines(const AOutput: TBytes): TArray<string>;
var
  mLine: string;
begin
  Result := nil;
  for mLine in VcsUtf8(AOutput).Split([#10]) do
  begin
    if Trim(mLine) <> '' then
    begin
      Result := Result + [Trim(mLine)];
    end;
  end;
end;

/// <summary>Lief der Aufruf und endete mit 0?</summary>
function Succeeded(const AAnswer: TAtlasVcsRunResult): Boolean;
begin
  Result := (AAnswer.Outcome = TAtlasVcsOutcome.Ok) and (AAnswer.ExitCode = 0);
end;

/// <summary>svn: Wurzel des Repositorys aus der Arbeitskopie (ohne Netz) in ACheck.Url; False mit ACheck.State,
/// wenn es keinen Server gibt.</summary>
function SvnTarget(const ARunner: IAtlasVcsRunner; const AExecutable, ARoot: string; ATimeoutMs: Cardinal;
  var ACheck: TAtlasVcsServerCheck): Boolean;
var
  mAnswer: TAtlasVcsRunResult;
begin
  mAnswer := ARunner.Run(AExecutable, TArray<string>.Create('info', '--show-item', 'repos-root-url',
    '--non-interactive'), ARoot, ATimeoutMs);
  Result := False;
  if not Succeeded(mAnswer) then
  begin
    ACheck.State := TAtlasVcsServerAccess.State(TAtlasVcsKind.Svn, mAnswer);
    if ACheck.State = TAtlasVcsServerState.Failed then
    begin
      ACheck.State := TAtlasVcsServerState.NoServer;
    end;
    Exit;
  end;
  ACheck.Url := TAtlasVcsServerChecks.WithoutCredentials(FirstLine(mAnswer.Output));
  Result := ACheck.Url <> '';
  if not Result then
  begin
    ACheck.State := TAtlasVcsServerState.NoServer;
  end;
end;

/// <summary>git: Remote des verfolgten Branchs, ohne verfolgten Branch origin bzw. das erste, in ACheck.Remote samt
/// Adresse; False mit ACheck.State, wenn es kein brauchbares Remote gibt.</summary>
function GitTarget(const ARunner: IAtlasVcsRunner; const AExecutable, ARoot: string; ATimeoutMs: Cardinal;
  var ACheck: TAtlasVcsServerCheck): Boolean;
var
  mAnswer: TAtlasVcsRunResult;
  mRemotes: TArray<string>;
  mUpstream: string;
begin
  Result := False;
  mAnswer := ARunner.Run(AExecutable, TArray<string>.Create('remote'), ARoot, ATimeoutMs);
  if not Succeeded(mAnswer) then
  begin
    ACheck.State := TAtlasVcsServerAccess.State(TAtlasVcsKind.Git, mAnswer);
    Exit;
  end;
  mRemotes := Lines(mAnswer.Output);
  mUpstream := '';
  mAnswer := ARunner.Run(AExecutable, TArray<string>.Create('rev-parse', '--abbrev-ref', '--symbolic-full-name',
    '@{u}'), ARoot, ATimeoutMs);
  if Succeeded(mAnswer) then
  begin
    mUpstream := FirstLine(mAnswer.Output);
  end;
  ACheck.Remote := TAtlasVcsServerChecks.RemoteFor(mUpstream, mRemotes);
  if ACheck.Remote = '' then
  begin
    ACheck.State := TAtlasVcsServerState.NoServer;
    Exit;
  end;
  if not TAtlasVcsServerChecks.SafeRemote(ACheck.Remote) then
  begin
    ACheck.State := TAtlasVcsServerState.Failed;
    Exit;
  end;
  mAnswer := ARunner.Run(AExecutable, TArray<string>.Create('remote', 'get-url', ACheck.Remote), ARoot,
    ATimeoutMs);
  if Succeeded(mAnswer) then
  begin
    ACheck.Url := TAtlasVcsServerChecks.WithoutCredentials(FirstLine(mAnswer.Output));
  end;
  Result := True;
end;

class function TAtlasVcsServerChecks.Check(const ARunner: IAtlasVcsRunner; AKind: TAtlasVcsKind;
  const AExecutable, ARoot: string; ATimeoutMs: Cardinal; ANow: TDateTime): TAtlasVcsServerCheck;
var
  mReady: Boolean;
begin
  Result := TAtlasVcsServerCheck.Empty;
  Result.Kind := AKind;
  Result.Root := ARoot;
  Result.CheckedAt := ANow;
  if (AKind = TAtlasVcsKind.None) or (ARoot = '') then
  begin
    Result.State := TAtlasVcsServerState.NoServer;
    Exit;
  end;
  if (AExecutable = '') or (ARunner = nil) then
  begin
    Result.State := TAtlasVcsServerState.ToolMissing;
    Exit;
  end;
  if AKind = TAtlasVcsKind.Svn then
  begin
    mReady := SvnTarget(ARunner, AExecutable, ARoot, ATimeoutMs, Result);
  end
  else
  begin
    mReady := GitTarget(ARunner, AExecutable, ARoot, ATimeoutMs, Result);
  end;
  // Die eigentliche Prüfung: einmal mit dem Server sprechen.
  if mReady then
  begin
    Result.State := TAtlasVcsServerAccess.State(AKind, ARunner.Run(AExecutable, ProbeArguments(AKind, Result.Remote),
      ARoot, ATimeoutMs));
  end;
end;

end.
