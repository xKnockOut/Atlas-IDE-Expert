unit Atlas.Core.Vcs.ServerAccess;

// Zugang zum Server der Versionsverwaltung (#1287), ohne Prozess:
// - State ordnet Exit-Code und feste Fehlerkennungen aus stderr von git bzw.
//   svn einem Zustand zu (erreichbar, Anmeldung nötig, nicht erreichbar, kein
//   Server). stderr wird nur durchsucht, nie weitergegeben oder protokolliert.
// - OutcomeOf macht daraus das Ergebnis eines Aufrufs: „Anmeldung nötig“ wird
//   TAtlasVcsOutcome.LoginNeeded, damit fetch, pull und push (#755, #762, #764)
//   nicht still scheitern.
// - NoPromptEnvironment ergänzt die Umgebung jedes Prozesses um
//   GIT_TERMINAL_PROMPT=0 und GCM_INTERACTIVE=never: git und Git Credential
//   Manager fragen nie nach Zugangsdaten (der Prozessläufer ist unsichtbar).
// Auch der Server übersetzt diese Unit (über Atlas.Core.Vcs.Tools); deshalb
// nur RTL und Atlas.Core.Vcs.Contract.

interface

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract;

type
{$SCOPEDENUMS ON}
  /// <summary>Zugang zum Server. Unknown: nicht geprüft. Reachable: Antwort mit gültiger Anmeldung.
  /// LoginNeeded: Server verlangt Zugangsdaten, die fehlen oder abgelehnt werden. Unreachable: DNS, Verbindung
  /// oder Zeitgrenze. NoServer: kein Remote bzw. keine Repository-Wurzel. ToolMissing: git bzw. svn fehlt.
  /// Failed: anderer Fehler.</summary>
  TAtlasVcsServerState = (Unknown, Reachable, LoginNeeded, Unreachable, NoServer, ToolMissing, Failed);
{$SCOPEDENUMS OFF}

  TAtlasVcsServerAccess = class
  public
    /// <summary>Zustand aus dem Ergebnis eines Aufrufs von git (AKind Git) bzw. svn (AKind Svn), der mit dem
    /// Server spricht. Ok mit Exit-Code 0 = Reachable; TimedOut = Unreachable.</summary>
    class function State(AKind: TAtlasVcsKind; const AResult: TAtlasVcsRunResult): TAtlasVcsServerState; static;
    /// <summary>Ergebnis eines Aufrufs mit dem Server: wie TAtlasVcsCommand.Run (Failed bei Exit-Code ungleich
    /// 0), aber LoginNeeded, wenn die Anmeldung fehlt.</summary>
    class function OutcomeOf(AKind: TAtlasVcsKind; const AResult: TAtlasVcsRunResult): TAtlasVcsOutcome; static;
    /// <summary>AEnvironment (Einträge NAME=Wert) mit GIT_TERMINAL_PROMPT=0 und GCM_INTERACTIVE=never;
    /// vorhandene Einträge gleichen Namens (Groß-/Kleinschreibung egal) werden ersetzt.</summary>
    class function NoPromptEnvironment(const AEnvironment: TArray<string>): TArray<string>; static;
    /// <summary>Name eines Eintrags NAME=Wert; '' ohne „=“ (Einträge wie „=C:=C:\“ bleiben unberührt).</summary>
    class function VariableName(const AEntry: string): string; static;
  end;

implementation

const
  // Variablen, die jeder Prozess der Versionsverwaltung bekommt.
  NoPromptVariables: array[0..1] of string = ('GIT_TERMINAL_PROMPT=0', 'GCM_INTERACTIVE=never');
  // git: Anmeldung fehlt oder wird abgelehnt (HTTPS, Credential Manager, SSH); englisch und deutsch, weil git
  // seine eigenen Meldungen übersetzt (curl und ssh nicht).
  GitLogin: array[0..13] of string = ('authentication failed', 'could not read username',
    'could not read password', 'terminal prompts disabled', 'http basic: access denied',
    'permission denied (publickey', 'the requested url returned error: 401',
    'the requested url returned error: 403', 'invalid username or password', 'access denied',
    'authentifizierung', 'benutzername', 'passwort', 'terminal-prompts deaktiviert');
  // git: Server nicht erreichbar.
  GitUnreachable: array[0..8] of string = ('could not resolve host', 'could not resolve hostname',
    'failed to connect', 'connection refused', 'connection timed out', 'operation timed out',
    'network is unreachable', 'no route to host', 'connection reset');
  // git: kein Remote.
  GitNoServer: array[0..4] of string = ('does not appear to be a git repository', 'no such remote',
    'no remote repository specified', 'scheint kein git-repository zu sein', 'kein solches remote');
  // svn: Anmeldung fehlt oder Zertifikat muss bestätigt werden.
  SvnLogin: array[0..3] of string = ('e170001', 'e215004', 'e215000', 'e230001');
  // svn: Server nicht erreichbar.
  SvnUnreachable: array[0..9] of string = ('e170013', 'e175002', 'e670002', 'e670008', 'e731001', 'e731004',
    'e730060', 'e730061', 'e730065', 'e730110');
  // svn: keine Arbeitskopie bzw. keine Repository-Wurzel.
  SvnNoServer: array[0..2] of string = ('e155007', 'e155010', 'e200009');

function HasAny(const AText: string; const AMarkers: array of string): Boolean;
var
  mMarker: string;
begin
  Result := False;
  for mMarker in AMarkers do
    if Pos(mMarker, AText) > 0 then
      Exit(True);
end;

{ TAtlasVcsServerAccess }

class function TAtlasVcsServerAccess.State(AKind: TAtlasVcsKind;
  const AResult: TAtlasVcsRunResult): TAtlasVcsServerState;
var
  mText: string;
begin
  case AResult.Outcome of
    TAtlasVcsOutcome.Ok:
      ;
    TAtlasVcsOutcome.TimedOut:
      Exit(TAtlasVcsServerState.Unreachable);
    TAtlasVcsOutcome.ToolMissing:
      Exit(TAtlasVcsServerState.ToolMissing);
    TAtlasVcsOutcome.NoWorkingCopy:
      Exit(TAtlasVcsServerState.NoServer);
    TAtlasVcsOutcome.LoginNeeded:
      Exit(TAtlasVcsServerState.LoginNeeded);
  else
    Exit(TAtlasVcsServerState.Failed);
  end;
  if AResult.ExitCode = 0 then
    Exit(TAtlasVcsServerState.Reachable);
  mText := LowerCase(AResult.ErrorText);
  Result := TAtlasVcsServerState.Failed;
  if AKind = TAtlasVcsKind.Svn then
  begin
    // Feste Fehlerkennungen (svn: E170001: …); die Anmeldung zuerst, weil svn mehrere Zeilen schreibt.
    if HasAny(mText, SvnLogin) then
      Result := TAtlasVcsServerState.LoginNeeded
    else if HasAny(mText, SvnUnreachable) then
      Result := TAtlasVcsServerState.Unreachable
    else if HasAny(mText, SvnNoServer) then
      Result := TAtlasVcsServerState.NoServer;
    Exit;
  end;
  if AKind <> TAtlasVcsKind.Git then
    Exit;
  // git endet bei Fehlern mit dem Server mit 128; die Meldung unterscheidet die Ursache.
  if HasAny(mText, GitNoServer) then
    Result := TAtlasVcsServerState.NoServer
  else if HasAny(mText, GitLogin) then
    Result := TAtlasVcsServerState.LoginNeeded
  else if HasAny(mText, GitUnreachable) then
    Result := TAtlasVcsServerState.Unreachable;
end;

class function TAtlasVcsServerAccess.OutcomeOf(AKind: TAtlasVcsKind;
  const AResult: TAtlasVcsRunResult): TAtlasVcsOutcome;
begin
  Result := AResult.Outcome;
  if (Result <> TAtlasVcsOutcome.Ok) or (AResult.ExitCode = 0) then
    Exit;
  Result := TAtlasVcsOutcome.Failed;
  if State(AKind, AResult) = TAtlasVcsServerState.LoginNeeded then
    Result := TAtlasVcsOutcome.LoginNeeded;
end;

class function TAtlasVcsServerAccess.VariableName(const AEntry: string): string;
var
  mAt: Integer;
begin
  // Einträge der Laufwerke („=C:=C:\…“) sind keine Variablen.
  if AEntry.StartsWith('=') then
    Exit('');
  mAt := Pos('=', AEntry);
  if mAt <= 1 then
    Exit('');
  Result := Copy(AEntry, 1, mAt - 1);
end;

class function TAtlasVcsServerAccess.NoPromptEnvironment(const AEnvironment: TArray<string>): TArray<string>;
var
  mEntry, mVariable: string;
  mReplaced: Boolean;
begin
  Result := nil;
  for mEntry in AEnvironment do
  begin
    mReplaced := False;
    for mVariable in NoPromptVariables do
      if SameText(VariableName(mEntry), VariableName(mVariable)) then
        mReplaced := True;
    if not mReplaced then
      Result := Result + [mEntry];
  end;
  for mVariable in NoPromptVariables do
    Result := Result + [mVariable];
end;

end.
