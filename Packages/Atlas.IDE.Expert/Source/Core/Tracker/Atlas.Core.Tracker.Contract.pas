unit Atlas.Core.Tracker.Contract;

// Issue-Tracker für den Bereich „Meine Issues“ der Willkommensseite (#765),
// ohne VCL und Open Tools API.
// - IAtlasTrackerProvider: ein Anbieter (GitHub,
//   Atlas.Core.Tracker.Providers.GitHub; YouTrack,
//   Atlas.Core.Tracker.Providers.YouTrack). Weitere (GitLab, Jira, Redmine)
//   kommen als eigene Umsetzung dazu, ohne dass sich der Bereich ändert; die
//   Komposition wählt sie über TAtlasTrackerTarget.Provider.
// - Das Netz kommt wie beim Build-Server (#763) über IAtlasCiTransport; die
//   echte Umsetzung sendet das Token aus dem Anmeldespeicher von Windows als
//   „Authorization: Bearer“ nur über https und nur an ApiServer.
// - TAtlasTrackerTarget: Anbieter, Adresse und Projekt aus der Projektdatei
//   .atlas (Abschnitt "tracker"), die Abfrage aus den Einstellungen; nie
//   Zugangsdaten.
// - TAtlasTrackerIssue: ein Issue der Liste mit den Feldern, die der Bereich
//   zeigt (GitHub: Labels und verknüpfter Pull Request mit CI-Ampel;
//   YouTrack: Zustand, Priorität, Sprint).
// Abfragen laufen im Hintergrund; nichts davon zeigt einen Dialog.

interface

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract;

type
{$SCOPEDENUMS ON}
  /// <summary>Zustand der Prüfungen (CI) eines Pull Requests: Ampel im Bereich.</summary>
  TAtlasTrackerChecks = (Unknown, Pending, Success, Failure);
{$SCOPEDENUMS OFF}

  /// <summary>Offener Pull Request zu einem Issue (GitHub).</summary>
  TAtlasTrackerPullRequest = record
    /// <summary>0 = kein Pull Request.</summary>
    Number: Integer;
    Checks: TAtlasTrackerChecks;
    Draft: Boolean;
    /// <summary>"unknown", "pending", "success" bzw. "failure".</summary>
    class function ChecksKey(AChecks: TAtlasTrackerChecks): string; static;
    /// <summary>Umkehrung von ChecksKey; Unknown für fremde Texte.</summary>
    class function ChecksOf(const AKey: string): TAtlasTrackerChecks; static;
  end;

  /// <summary>Ein Issue der Liste.</summary>
  TAtlasTrackerIssue = record
  public const
    /// <summary>Höchstens so viele Labels werden gelesen und gespeichert.</summary>
    MaxLabels = 6;
    /// <summary>Höchstens so viele Zeichen eines Titels werden gespeichert.</summary>
    MaxTitle = 200;
  public
    /// <summary>Kennung wie im Tracker: "#753" (GitHub), "ATL-123" (YouTrack).</summary>
    Key: string;
    /// <summary>Nummer im Projekt (753 bzw. 123); 0 = unbekannt.</summary>
    Number: Integer;
    Title: string;
    /// <summary>GitHub: Namen der Labels.</summary>
    Labels: TArray<string>;
    /// <summary>YouTrack: Zustand, Priorität und Sprint bzw. Board; '' ohne.</summary>
    State: string;
    Priority: string;
    Sprint: string;
    /// <summary>GitHub: verknüpfter offener Pull Request.</summary>
    PullRequest: TAtlasTrackerPullRequest;
    class function Empty: TAtlasTrackerIssue; static;
  end;

  /// <summary>Was abgefragt wird; ohne Zugangsdaten.</summary>
  TAtlasTrackerTarget = record
  public const
    GitHub = 'github';
    YouTrack = 'youtrack';
    /// <summary>Adresse von GitHub, wenn .atlas keine nennt.</summary>
    GitHubUrl = 'https://github.com';
  public
    /// <summary>"github" oder "youtrack".</summary>
    Provider: string;
    /// <summary>Adresse ohne „/“ am Ende: "https://github.com", "https://firma.youtrack.cloud".</summary>
    Url: string;
    /// <summary>GitHub "owner/repo", YouTrack Projektkürzel ("ATL"); bei YouTrack darf es fehlen.</summary>
    Project: string;
    /// <summary>Abfrage in der Sprache des Trackers; '' = Vorgabe des Anbieters.</summary>
    Query: string;
    /// <summary>GitHub ohne Adresse: github.com; GitHub-Adresse mit "/owner/repo" und ohne Projekt: das Projekt
    /// kommt aus der Adresse.</summary>
    class function Create(const AProvider, AUrl, AProject, AQuery: string): TAtlasTrackerTarget; static;
    /// <summary>Anbieter und Server bekannt, bei GitHub auch "owner/repo".</summary>
    function Configured: Boolean;
    /// <summary>Schema, Rechner und Port in Kleinbuchstaben; '' bei ungültiger Adresse (wie TAtlasCiJob.Server).
    /// </summary>
    function Server: string;
    /// <summary>Name des Eintrags im Anmeldespeicher von Windows: "Atlas:tracker:" + Server.</summary>
    function CredentialTarget: string;
    /// <summary>Kennung für Vergleich und Merker (klein).</summary>
    function Key: string;
    /// <summary>Server mit https://.</summary>
    function Secure: Boolean;
  end;

  IAtlasTrackerProvider = interface
    ['{6F2A9C47-3E1B-4D85-B7A0-92C4E8D15F36}']
    /// <summary>Kennung wie in .atlas, z. B. "github".</summary>
    function Name: string;
    /// <summary>Anzeigename, z. B. "GitHub".</summary>
    function Caption: string;
    /// <summary>Abfrage, wenn issues.query leer ist.</summary>
    function DefaultQuery: string;
    /// <summary>Server der Schnittstelle (Origin), an den das Token gehen darf; '' ohne.</summary>
    function ApiServer(const ATarget: TAtlasTrackerTarget): string;
    /// <summary>Höchstens AMax Issues zur Abfrage, insgesamt höchstens ATimeoutMs; im Hintergrund. False mit AError,
    /// wenn keine Liste gelesen werden konnte.</summary>
    function Fetch(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; ATimeoutMs, AMax: Integer;
      out AIssues: TArray<TAtlasTrackerIssue>; out AError: TAtlasCiFetchError): Boolean;
    /// <summary>Seite des Issues für den Browser, aus der eingetragenen Adresse; '' ohne.</summary>
    function IssuePage(const ATarget: TAtlasTrackerTarget; const AKey: string): string;
    /// <summary>Seite eines Pull Requests; '' ohne (YouTrack).</summary>
    function PullRequestPage(const ATarget: TAtlasTrackerTarget; ANumber: Integer): string;
  end;

implementation

const
  ChecksKeys: array[TAtlasTrackerChecks] of string = ('unknown', 'pending', 'success', 'failure');

{ TAtlasTrackerPullRequest }

class function TAtlasTrackerPullRequest.ChecksKey(AChecks: TAtlasTrackerChecks): string;
begin
  Result := ChecksKeys[AChecks];
end;

class function TAtlasTrackerPullRequest.ChecksOf(const AKey: string): TAtlasTrackerChecks;
var
  Checks: TAtlasTrackerChecks;
begin
  for Checks := Low(TAtlasTrackerChecks) to High(TAtlasTrackerChecks) do
    if SameText(ChecksKeys[Checks], AKey) then
      Exit(Checks);
  Result := TAtlasTrackerChecks.Unknown;
end;

{ TAtlasTrackerIssue }

class function TAtlasTrackerIssue.Empty: TAtlasTrackerIssue;
begin
  Result := Default(TAtlasTrackerIssue);
  Result.Labels := nil;
end;

{ TAtlasTrackerTarget }

function TrimSlashes(const AText: string): string;
begin
  Result := Trim(AText);
  while (Result <> '') and (Result[1] = '/') do
    Delete(Result, 1, 1);
  while (Result <> '') and (Result[Length(Result)] = '/') do
    Delete(Result, Length(Result), 1);
end;

class function TAtlasTrackerTarget.Create(const AProvider, AUrl, AProject, AQuery: string): TAtlasTrackerTarget;
var
  Origin, Path: string;
  Parts: TArray<string>;
begin
  Result.Provider := LowerCase(Trim(AProvider));
  Result.Url := Trim(AUrl);
  while (Result.Url <> '') and (Result.Url[Length(Result.Url)] = '/') do
    Delete(Result.Url, Length(Result.Url), 1);
  Result.Project := TrimSlashes(AProject);
  Result.Query := Trim(AQuery);
  if Result.Provider <> GitHub then
    Exit;
  if Result.Url = '' then
    Result.Url := GitHubUrl;
  // "https://github.com/owner/repo" ohne Projekt: Projekt aus der Adresse.
  Origin := Result.Server;
  if Origin = '' then
    Exit;
  Path := TrimSlashes(Copy(Result.Url, Length(Origin) + 1, MaxInt));
  if Path = '' then
    Exit;
  Parts := Path.Split(['/']);
  if Length(Parts) = 2 then
  begin
    if Result.Project = '' then
      Result.Project := Path;
    Result.Url := Copy(Result.Url, 1, Length(Origin));
  end;
end;

function TAtlasTrackerTarget.Configured: Boolean;
begin
  Result := (Provider <> '') and (Server <> '');
  if Result and (Provider = GitHub) then
    Result := (Pos('/', Project) > 1) and (Pos('/', Project) < Length(Project));
end;

function TAtlasTrackerTarget.Server: string;
begin
  // Dieselben Regeln wie beim Build-Server: nur http(s), nie ein Benutzer in der Adresse.
  Result := TAtlasCiJob.Create('', Url, '', False, '').Server;
end;

function TAtlasTrackerTarget.CredentialTarget: string;
begin
  Result := '';
  if Server <> '' then
    Result := 'Atlas:tracker:' + Server;
end;

function TAtlasTrackerTarget.Key: string;
begin
  Result := LowerCase(Provider + '|' + Url + '|' + Project + '|' + Query);
end;

function TAtlasTrackerTarget.Secure: Boolean;
begin
  Result := SameText(Copy(Server, 1, 8), 'https://');
end;

end.
