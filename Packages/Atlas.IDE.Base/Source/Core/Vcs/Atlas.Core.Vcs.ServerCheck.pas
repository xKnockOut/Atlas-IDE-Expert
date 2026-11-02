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
    TimeoutMs = 10000;
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
    Exit(Url);
  if Remote = '' then
    Exit('');
  mHost := TAtlasVcsServerChecks.HostOf(Url);
  if mHost = '' then
    mHost := Url;
  if mHost = '' then
    Exit(Remote);
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
    Exit;
  Inc(mStart, 3);
  mEnd := Pos('/', Result, mStart);
  if mEnd = 0 then
    mEnd := Length(Result) + 1;
  // Bis zum letzten „@“ vor dem Pfad stehen Benutzer und Kennwort.
  mAuthority := Copy(Result, mStart, mEnd - mStart);
  if LastDelimiter('@', mAuthority) = 0 then
    Exit;
  Result := Copy(Result, 1, mStart - 1) + Copy(mAuthority, LastDelimiter('@', mAuthority) + 1, MaxInt) +
    Copy(Result, mEnd, MaxInt);
end;

class function TAtlasVcsServerChecks.HostOf(const AUrl: string): string;
var
  mText: string;
  mScheme, mEnd, mAt, mColon: Integer;
begin
  mText := Trim(AUrl);
  Result := '';
  if mText = '' then
    Exit;
  mScheme := Pos('://', mText);
  if mScheme > 0 then
  begin
    if SameText(Copy(mText, 1, mScheme - 1), 'file') then
      Exit;
    mText := Copy(mText, mScheme + 3, MaxInt);
    mEnd := Pos('/', mText);
    if mEnd > 0 then
      mText := Copy(mText, 1, mEnd - 1);
    mAt := LastDelimiter('@', mText);
    if mAt > 0 then
      mText := Copy(mText, mAt + 1, MaxInt);
    // Port abschneiden (IPv6 in eckigen Klammern behalten).
    mColon := LastDelimiter(':', mText);
    if (mColon > 0) and (mColon > LastDelimiter(']', mText)) then
      mText := Copy(mText, 1, mColon - 1);
    Exit(LowerCase(mText));
  end;
  // scp-Form: [benutzer@]host:pfad; ein Laufwerk wie C:\ ist kein Rechner.
  mColon := Pos(':', mText);
  if (mColon <= 2) or ((Pos('\', mText) > 0) and (Pos('\', mText) < mColon)) then
    Exit;
  mText := Copy(mText, 1, mColon - 1);
  if Pos('/', mText) > 0 then
    Exit;
  mAt := LastDelimiter('@', mText);
  Result := LowerCase(Copy(mText, mAt + 1, MaxInt));
end;

class function TAtlasVcsServerChecks.RemoteFor(const AUpstream: string; const ARemotes: TArray<string>): string;
var
  mRemote: string;
begin
  Result := '';
  for mRemote in ARemotes do
    if (mRemote <> '') and (Length(mRemote) > Length(Result)) and
      (Copy(AUpstream, 1, Length(mRemote) + 1) = mRemote + '/') then
      Result := mRemote;
  if Result <> '' then
    Exit;
  for mRemote in ARemotes do
    if mRemote = 'origin' then
      Exit(mRemote);
  if Length(ARemotes) > 0 then
    Result := ARemotes[0];
end;

class function TAtlasVcsServerChecks.SafeRemote(const AName: string): Boolean;
var
  mIndex: Integer;
begin
  Result := (AName <> '') and (AName[1] <> '-');
  for mIndex := 1 to Length(AName) do
    if not CharInSet(AName[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '.', '_', '-', '/']) then
      Exit(False);
end;

class function TAtlasVcsServerChecks.ProbeArguments(AKind: TAtlasVcsKind; const ARemote: string): TArray<string>;
begin
  if AKind = TAtlasVcsKind.Svn then
    Result := TArray<string>.Create('info', '--non-interactive', '^/')
  else
    Result := TArray<string>.Create('-c', 'credential.interactive=never', '-c', 'core.askPass=', 'ls-remote',
      '--heads', ARemote);
end;

class function TAtlasVcsServerChecks.LoginCommandLine(const AShell, AExecutable: string; AKind: TAtlasVcsKind;
  const ARemote: string): string;
var
  mCommand: string;
begin
  Result := '';
  if (AShell = '') or (AExecutable = '') or (Pos('"', AExecutable) > 0) then
    Exit;
  if AKind = TAtlasVcsKind.Svn then
    // In Anführungszeichen ist ^ für cmd kein Fluchtzeichen.
    mCommand := '"' + AExecutable + '" info "^/"'
  else if (AKind = TAtlasVcsKind.Git) and SafeRemote(ARemote) then
    mCommand := '"' + AExecutable + '" fetch ' + ARemote
  else
    Exit;
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
    mText := Copy(mText, 1, mEnd - 1);
  Result := Trim(mText);
end;

function Lines(const AOutput: TBytes): TArray<string>;
var
  mLine: string;
begin
  Result := nil;
  for mLine in VcsUtf8(AOutput).Split([#10]) do
    if Trim(mLine) <> '' then
      Result := Result + [Trim(mLine)];
end;

class function TAtlasVcsServerChecks.Check(const ARunner: IAtlasVcsRunner; AKind: TAtlasVcsKind;
  const AExecutable, ARoot: string; ATimeoutMs: Cardinal; ANow: TDateTime): TAtlasVcsServerCheck;
var
  mAnswer: TAtlasVcsRunResult;
  mRemotes: TArray<string>;
  mUpstream: string;
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
    // Wurzel des Repositorys aus der Arbeitskopie (ohne Netz).
    mAnswer := ARunner.Run(AExecutable, TArray<string>.Create('info', '--show-item', 'repos-root-url',
      '--non-interactive'), ARoot, ATimeoutMs);
    if (mAnswer.Outcome <> TAtlasVcsOutcome.Ok) or (mAnswer.ExitCode <> 0) then
    begin
      Result.State := TAtlasVcsServerAccess.State(AKind, mAnswer);
      if Result.State = TAtlasVcsServerState.Failed then
        Result.State := TAtlasVcsServerState.NoServer;
      Exit;
    end;
    Result.Url := TAtlasVcsServerChecks.WithoutCredentials(FirstLine(mAnswer.Output));
    if Result.Url = '' then
    begin
      Result.State := TAtlasVcsServerState.NoServer;
      Exit;
    end;
  end
  else
  begin
    mAnswer := ARunner.Run(AExecutable, TArray<string>.Create('remote'), ARoot, ATimeoutMs);
    if (mAnswer.Outcome <> TAtlasVcsOutcome.Ok) or (mAnswer.ExitCode <> 0) then
    begin
      Result.State := TAtlasVcsServerAccess.State(AKind, mAnswer);
      Exit;
    end;
    mRemotes := Lines(mAnswer.Output);
    // Remote des verfolgten Branchs; ohne verfolgten Branch origin bzw. das erste.
    mUpstream := '';
    mAnswer := ARunner.Run(AExecutable, TArray<string>.Create('rev-parse', '--abbrev-ref', '--symbolic-full-name',
      '@{u}'), ARoot, ATimeoutMs);
    if (mAnswer.Outcome = TAtlasVcsOutcome.Ok) and (mAnswer.ExitCode = 0) then
      mUpstream := FirstLine(mAnswer.Output);
    Result.Remote := RemoteFor(mUpstream, mRemotes);
    if Result.Remote = '' then
    begin
      Result.State := TAtlasVcsServerState.NoServer;
      Exit;
    end;
    if not SafeRemote(Result.Remote) then
    begin
      Result.State := TAtlasVcsServerState.Failed;
      Exit;
    end;
    mAnswer := ARunner.Run(AExecutable, TArray<string>.Create('remote', 'get-url', Result.Remote), ARoot,
      ATimeoutMs);
    if (mAnswer.Outcome = TAtlasVcsOutcome.Ok) and (mAnswer.ExitCode = 0) then
      Result.Url := WithoutCredentials(FirstLine(mAnswer.Output));
  end;
  // Die eigentliche Prüfung: einmal mit dem Server sprechen.
  mAnswer := ARunner.Run(AExecutable, ProbeArguments(AKind, Result.Remote), ARoot, ATimeoutMs);
  Result.State := TAtlasVcsServerAccess.State(AKind, mAnswer);
end;

end.
