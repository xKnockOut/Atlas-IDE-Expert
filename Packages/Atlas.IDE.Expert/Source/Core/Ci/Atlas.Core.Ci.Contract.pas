unit Atlas.Core.Ci.Contract;

// Build-Server (CI) für den Bereich „Testergebnisse“ der Willkommensseite
// (#763), ohne VCL und Open Tools API.
// - IAtlasCiProvider: ein CI-Anbieter (zuerst Jenkins,
//   Atlas.Core.Ci.Providers.Jenkins). Weitere Anbieter (GitHub Actions,
//   GitLab CI, TeamCity) kommen als eigene Umsetzung dazu, ohne dass sich der
//   Bereich ändert; die Komposition wählt sie über TAtlasCiJob.Provider.
// - IAtlasCiTransport: ein GET mit Zeitlimit. Die echte Umsetzung
//   (Atlas.Core.Ci.Adapters.Http) sendet Benutzer und Token aus dem
//   Anmeldespeicher von Windows (Atlas.Core.Ci.Adapters.Credentials); Tests
//   setzen eine Fassung mit festen Antworten ein.
// - IAtlasCiSend (#1273): Schreiben (POST, PATCH) mit JSON, nur angemeldet;
//   die Issue-Vorschau schreibt darüber abgehakte Checklisten zurück.
// - TAtlasCiJob: Server, Job und Branch aus der Projektdatei .atlas (#486)
//   und der Versionsverwaltung (#571); nie Zugangsdaten.
// - TAtlasCiBuild: letzter abgeschlossener Build mit Testbericht.
// Abfragen laufen im Hintergrund; nichts davon zeigt einen Dialog.

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  /// <summary>Ergebnis eines Builds auf dem Server.</summary>
  TAtlasCiOutcome = (Unknown, Success, Unstable, Failure, Aborted, NotBuilt);

  /// <summary>Warum eine Abfrage nichts brachte.</summary>
  TAtlasCiFetchError = (None, NotConfigured, Network, Timeout, Unauthorized, NotFound, Server, Invalid, Cancelled,
    UnknownProvider);
{$SCOPEDENUMS OFF}

  /// <summary>Fehlgeschlagener Test auf dem Server.</summary>
  TAtlasCiFailure = record
    /// <summary>Voller Name wie bei DUnitX (Klasse.Methode), damit „erneut ausführen“ ihn an --run geben kann.
    /// </summary>
    Test: string;
    /// <summary>Erste Zeile der Fehlermeldung; '' ohne.</summary>
    Message: string;
  end;

  /// <summary>Letzter abgeschlossener Build mit Testbericht.</summary>
  TAtlasCiBuild = record
  public const
    /// <summary>Höchstens so viele fehlgeschlagene Tests werden gelesen und gespeichert.</summary>
    MaxFailures = 50;
  public
    /// <summary>Build-Nummer; 0 = kein Build bekannt.</summary>
    Number: Integer;
    Outcome: TAtlasCiOutcome;
    /// <summary>Start des Builds (UTC); 0 = unbekannt.</summary>
    StartedUtc: TDateTime;
    /// <summary>Dauer in ms; 0 = unbekannt.</summary>
    DurationMs: Int64;
    /// <summary>Der Build hat einen Testbericht (JUnit-Plugin).</summary>
    TestsKnown: Boolean;
    Passed: Integer;
    /// <summary>Alle fehlgeschlagenen Tests, auch über MaxFailures hinaus.</summary>
    Failed: Integer;
    Skipped: Integer;
    Failures: TArray<TAtlasCiFailure>;
    class function Empty: TAtlasCiBuild; static;
    /// <summary>"success", "unstable", "failure", "aborted", "notBuilt" bzw. "unknown".</summary>
    class function OutcomeKey(AOutcome: TAtlasCiOutcome): string; static;
    /// <summary>Umkehrung von OutcomeKey; Unknown für fremde Texte.</summary>
    class function OutcomeOf(const AKey: string): TAtlasCiOutcome; static;
    /// <summary>Kennung für Datei und Protokoll ("timeout", "unauthorized" …); '' für None.</summary>
    class function ErrorKey(AError: TAtlasCiFetchError): string; static;
    class function ErrorOf(const AKey: string): TAtlasCiFetchError; static;
  end;

  /// <summary>Was abgefragt wird; ohne Zugangsdaten.</summary>
  TAtlasCiJob = record
    /// <summary>"jenkins".</summary>
    Provider: string;
    /// <summary>Adresse des Servers, z. B. "https://ci.firma.de" (ohne /job/…).</summary>
    Url: string;
    /// <summary>Job; Ordner mit „/“ getrennt, z. B. "team/kasse".</summary>
    Job: string;
    /// <summary>Multibranch-Job: abgefragt wird der Job des Branches.</summary>
    Multibranch: Boolean;
    /// <summary>Aktueller Branch des Projekts (#571); nur bei Multibranch Teil der Adresse.</summary>
    Branch: string;
    class function Create(const AProvider, AUrl, AJob: string; AMultibranch: Boolean;
      const ABranch: string): TAtlasCiJob; static;
    /// <summary>Server, Job und (bei Multibranch) Branch bekannt.</summary>
    function Configured: Boolean;
    /// <summary>Branch, der zur Abfrage gehört: bei Multibranch Branch, sonst ''.</summary>
    function JobBranch: string;
    /// <summary>Kennung für Vergleich und Merker (klein, ohne „/“ am Ende).</summary>
    function Key: string;
    /// <summary>Schema, Rechner und Port in Kleinbuchstaben, z. B. "https://ci.firma.de:8443"; '' bei
    /// ungültiger Adresse.</summary>
    function Server: string;
    /// <summary>Name des Eintrags im Anmeldespeicher von Windows: "Atlas:ci:" + Server.</summary>
    function CredentialTarget: string;
    /// <summary>Server mit https://.</summary>
    function Secure: Boolean;
  end;

  IAtlasCiTransport = interface
    ['{3E8B5C21-7D4A-4F96-A0B3-6C2E9F1D7A58}']
    /// <summary>GET auf AUrl mit höchstens ATimeoutMs. True, wenn eine Antwort kam (auch 404); AStatus ist der
    /// HTTP-Status, AText der Inhalt. False ohne Antwort (kein Netz, Zeitlimit, Abbruch) mit AError.</summary>
    function Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
  end;

  /// <summary>Binäre Inhalte (Bilder und Anhänge der Issue-Vorschau, #1264) über denselben Transport, unter
  /// denselben Regeln für Anmeldung, Server und Weiterleitungen.</summary>
  IAtlasCiDownload = interface
    ['{5B1E8D43-2C7A-4F09-9E36-A84D1C7F2B65}']
    /// <summary>GET auf AUrl, höchstens AMaxBytes und ATimeoutMs; sonst wie IAtlasCiTransport.Get.</summary>
    function GetBytes(const AUrl: string; ATimeoutMs, AMaxBytes: Integer; out AStatus: Integer; out ABytes: TBytes;
      out AError: TAtlasCiFetchError): Boolean;
  end;

  /// <summary>Schreiben über denselben Transport, für alle schreibenden Anfragen an den Tracker (#1273 Checklisten,
  /// #1279 Unteraufgaben und Verknüpfungen).</summary>
  IAtlasCiSend = interface
    ['{2D7A4E19-8B3C-4F61-A5D0-71E9C3B84F26}']
    /// <summary>AMethod ("POST", "PATCH") auf AUrl mit dem JSON ABody, höchstens ATimeoutMs. Nur mit Anmeldung beim
    /// eingetragenen Server über https (sonst False mit Unauthorized, ohne Netz); eine Weiterleitung ist ein Fehler
    /// (False mit Server), damit der Inhalt nie an ein anderes Ziel geht. True, wenn eine Antwort kam (auch 4xx);
    /// AStatus und AText wie bei IAtlasCiTransport.Get.</summary>
    function Send(const AMethod, AUrl, ABody: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
  end;

  /// <summary>Laufende und künftige Anfragen eines Transports abbrechen (Fenster geschlossen, #1264); sie enden
  /// mit TAtlasCiFetchError.Cancelled.</summary>
  IAtlasCiCancel = interface
    ['{9C4F2A71-6D3B-4E58-B1A7-3E0D5C8F9A24}']
    procedure Cancel;
  end;

  /// <summary>Bedingte Abfrage (#1271, GitHub /notifications): sendet If-Modified-Since und liest Last-Modified und
  /// X-Poll-Interval aus der Antwort, unter denselben Regeln wie IAtlasCiTransport.Get.</summary>
  IAtlasCiConditional = interface
    ['{E2A7C953-4B18-4D6F-9C31-7F5A0B2D8E46}']
    /// <summary>GET auf AUrl; AIfModifiedSince '' = ohne Bedingung. 304 heißt „unverändert“ (AText leer).
    /// ALastModified ist der Kopf Last-Modified ('' ohne), APollSeconds X-Poll-Interval (0 ohne).</summary>
    function GetConditional(const AUrl, AIfModifiedSince: string; ATimeoutMs: Integer; out AStatus: Integer;
      out AText, ALastModified: string; out APollSeconds: Integer; out AError: TAtlasCiFetchError): Boolean;
  end;

  /// <summary>POST beliebigen Inhalts an den Tracker (Anhänge und Kommentare, #1276) über denselben Transport, unter
  /// denselben Regeln wie IAtlasCiSend: nur mit Token über https an den eingetragenen Server (sonst False mit
  /// Unauthorized, ohne Netz); eine Weiterleitung ist ein Fehler.</summary>
  IAtlasCiPost = interface
    ['{2D7A5E19-8C43-4B6F-A1E0-7F3B9C25D814}']
    /// <summary>POST von ABody (AContentType) an AUrl mit höchstens ATimeoutMs. True, wenn eine Antwort kam (auch
    /// 4xx); AStatus ist der HTTP-Status, AText der Inhalt der Antwort. False ohne Antwort mit AError.</summary>
    function Post(const AUrl, AContentType: string; const ABody: TBytes; ATimeoutMs: Integer; out AStatus: Integer;
      out AText: string; out AError: TAtlasCiFetchError): Boolean;
  end;

  IAtlasCiProvider = interface
    ['{9A4D7E12-5B3C-4E81-8F6A-1D2C7B9E4F30}']
    /// <summary>Kennung wie in .atlas, z. B. "jenkins".</summary>
    function Name: string;
    /// <summary>Letzter abgeschlossener Build von AJob samt Testbericht, insgesamt höchstens ATimeoutMs; im
    /// Hintergrund. False mit AError, wenn kein Build gelesen werden konnte.</summary>
    function Fetch(const AJob: TAtlasCiJob; const ATransport: IAtlasCiTransport; ATimeoutMs: Integer;
      out ABuild: TAtlasCiBuild; out AError: TAtlasCiFetchError): Boolean;
    /// <summary>Seite des Builds ANumber für den Browser; '' ohne.</summary>
    function BuildPage(const AJob: TAtlasCiJob; ANumber: Integer): string;
  end;

implementation

const
  OutcomeKeys: array[TAtlasCiOutcome] of string = ('unknown', 'success', 'unstable', 'failure', 'aborted',
    'notBuilt');
  ErrorKeys: array[TAtlasCiFetchError] of string = ('', 'notConfigured', 'network', 'timeout', 'unauthorized',
    'notFound', 'server', 'invalid', 'cancelled', 'unknownProvider');

{ TAtlasCiBuild }

class function TAtlasCiBuild.Empty: TAtlasCiBuild;
begin
  Result := Default(TAtlasCiBuild);
  Result.Failures := nil;
end;

class function TAtlasCiBuild.OutcomeKey(AOutcome: TAtlasCiOutcome): string;
begin
  Result := OutcomeKeys[AOutcome];
end;

class function TAtlasCiBuild.OutcomeOf(const AKey: string): TAtlasCiOutcome;
var
  Outcome: TAtlasCiOutcome;
begin
  for Outcome := Low(TAtlasCiOutcome) to High(TAtlasCiOutcome) do
    if SameText(OutcomeKeys[Outcome], AKey) then
      Exit(Outcome);
  Result := TAtlasCiOutcome.Unknown;
end;

class function TAtlasCiBuild.ErrorKey(AError: TAtlasCiFetchError): string;
begin
  Result := ErrorKeys[AError];
end;

class function TAtlasCiBuild.ErrorOf(const AKey: string): TAtlasCiFetchError;
var
  Error: TAtlasCiFetchError;
begin
  if AKey = '' then
    Exit(TAtlasCiFetchError.None);
  for Error := Succ(Low(TAtlasCiFetchError)) to High(TAtlasCiFetchError) do
    if SameText(ErrorKeys[Error], AKey) then
      Exit(Error);
  // Unbekannte Kennung aus einer neueren Fassung: als Netzfehler zeigen.
  Result := TAtlasCiFetchError.Network;
end;

{ TAtlasCiJob }

class function TAtlasCiJob.Create(const AProvider, AUrl, AJob: string; AMultibranch: Boolean;
  const ABranch: string): TAtlasCiJob;
begin
  Result.Provider := LowerCase(Trim(AProvider));
  Result.Url := Trim(AUrl);
  while (Result.Url <> '') and (Result.Url[Length(Result.Url)] = '/') do
    Delete(Result.Url, Length(Result.Url), 1);
  Result.Job := Trim(AJob);
  while (Result.Job <> '') and (Result.Job[1] = '/') do
    Delete(Result.Job, 1, 1);
  while (Result.Job <> '') and (Result.Job[Length(Result.Job)] = '/') do
    Delete(Result.Job, Length(Result.Job), 1);
  Result.Multibranch := AMultibranch;
  Result.Branch := Trim(ABranch);
end;

function TAtlasCiJob.Configured: Boolean;
begin
  Result := (Provider <> '') and (Server <> '') and (Job <> '') and (not Multibranch or (Branch <> ''));
end;

function TAtlasCiJob.JobBranch: string;
begin
  Result := '';
  if Multibranch then
    Result := Branch;
end;

function TAtlasCiJob.Key: string;
begin
  Result := LowerCase(Provider + '|' + Url + '|' + Job + '|' + JobBranch);
end;

function TAtlasCiJob.Server: string;
var
  Rest: string;
  Scheme: string;
  Index: Integer;
begin
  Result := '';
  if SameText(Copy(Url, 1, 8), 'https://') then
    Scheme := 'https://'
  else if SameText(Copy(Url, 1, 7), 'http://') then
    Scheme := 'http://'
  else
    Exit;
  Rest := Copy(Url, Length(Scheme) + 1, MaxInt);
  Index := Pos('/', Rest);
  if Index > 0 then
    Rest := Copy(Rest, 1, Index - 1);
  // Benutzer in der Adresse („user@host“) lässt .atlas nicht zu; hier trotzdem nie übernehmen.
  if (Rest = '') or (Pos('@', Rest) > 0) or (Pos(' ', Rest) > 0) then
    Exit;
  Result := LowerCase(Scheme + Rest);
end;

function TAtlasCiJob.CredentialTarget: string;
begin
  Result := '';
  if Server <> '' then
    Result := 'Atlas:ci:' + Server;
end;

function TAtlasCiJob.Secure: Boolean;
begin
  Result := SameText(Copy(Server, 1, 8), 'https://');
end;

end.
