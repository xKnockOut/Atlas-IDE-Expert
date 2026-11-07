unit Atlas.Core.CiBuild.Contract;

// Stand des Build-Servers (CI, #763) als Daten, ohne VCL, Open Tools API und
// Netz: Ergebnis und Testbericht des letzten Builds (TAtlasCiBuild), Fehlerart
// einer Abfrage und der abgefragte Job (TAtlasCiJob, aus der .atlas #486 und
// der Versionsverwaltung #571; nie Zugangsdaten). Liegt in Base, weil die
// Projekt-Zusammenfassung (Atlas.Core.Projects.Summary) den Stand speichert
// (#1455, vorher in Atlas.Core.Ci.Contract); Abfrage, Anbieter und Transport
// bleiben im Modul Tracker (Atlas.Core.Ci.Contract).

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  /// <summary>Ergebnis eines Builds auf dem Server.</summary>
  TAtlasCiOutcome = (Unknown, Success, Unstable, Failure, Aborted, NotBuilt);

  /// <summary>Warum eine Abfrage nichts brachte.</summary>
  TAtlasCiFetchError = (None, NotConfigured, Network, Timeout, Unauthorized, NotFound, Server, Invalid, Cancelled,
    UnknownProvider, NoCredentials);
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
    cMaxFailures = 50;
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

implementation

const
  cOutcomeKeys: array[TAtlasCiOutcome] of string = ('unknown', 'success', 'unstable', 'failure', 'aborted',
    'notBuilt');
  cErrorKeys: array[TAtlasCiFetchError] of string = ('', 'notConfigured', 'network', 'timeout', 'unauthorized',
    'notFound', 'server', 'invalid', 'cancelled', 'unknownProvider', 'noCredentials');

{ TAtlasCiBuild }

class function TAtlasCiBuild.Empty: TAtlasCiBuild;
begin
  Result := Default(TAtlasCiBuild);
  Result.Failures := nil;
end;

class function TAtlasCiBuild.OutcomeKey(AOutcome: TAtlasCiOutcome): string;
begin
  Result := cOutcomeKeys[AOutcome];
end;

class function TAtlasCiBuild.OutcomeOf(const AKey: string): TAtlasCiOutcome;
var
  mOutcome: TAtlasCiOutcome;
begin
  for mOutcome := Low(TAtlasCiOutcome) to High(TAtlasCiOutcome) do
  begin
    if SameText(cOutcomeKeys[mOutcome], AKey) then
    begin
      Exit(mOutcome);
    end;
  end;
  Result := TAtlasCiOutcome.Unknown;
end;

class function TAtlasCiBuild.ErrorKey(AError: TAtlasCiFetchError): string;
begin
  Result := cErrorKeys[AError];
end;

class function TAtlasCiBuild.ErrorOf(const AKey: string): TAtlasCiFetchError;
var
  mError: TAtlasCiFetchError;
begin
  if AKey = '' then
  begin
    Exit(TAtlasCiFetchError.None);
  end;
  for mError := Succ(Low(TAtlasCiFetchError)) to High(TAtlasCiFetchError) do
  begin
    if SameText(cErrorKeys[mError], AKey) then
    begin
      Exit(mError);
    end;
  end;
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
  begin
    Delete(Result.Url, Length(Result.Url), 1);
  end;
  Result.Job := Trim(AJob);
  while (Result.Job <> '') and (Result.Job[1] = '/') do
  begin
    Delete(Result.Job, 1, 1);
  end;
  while (Result.Job <> '') and (Result.Job[Length(Result.Job)] = '/') do
  begin
    Delete(Result.Job, Length(Result.Job), 1);
  end;
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
  begin
    Result := Branch;
  end;
end;

function TAtlasCiJob.Key: string;
begin
  Result := LowerCase(Provider + '|' + Url + '|' + Job + '|' + JobBranch);
end;

function TAtlasCiJob.Server: string;
var
  mRest: string;
  mScheme: string;
  mIndex: Integer;
begin
  Result := '';
  if SameText(Copy(Url, 1, 8), 'https://') then
  begin
    mScheme := 'https://';
  end
  else if SameText(Copy(Url, 1, 7), 'http://') then
  begin
    mScheme := 'http://';
  end
  else
  begin
    Exit;
  end;
  mRest := Copy(Url, Length(mScheme) + 1, MaxInt);
  mIndex := Pos('/', mRest);
  if mIndex > 0 then
  begin
    mRest := Copy(mRest, 1, mIndex - 1);
  end;
  // Benutzer in der Adresse („user@host“) lässt .atlas nicht zu; hier trotzdem nie übernehmen.
  if (mRest = '') or (Pos('@', mRest) > 0) or (Pos(' ', mRest) > 0) then
  begin
    Exit;
  end;
  Result := LowerCase(mScheme + mRest);
end;

function TAtlasCiJob.CredentialTarget: string;
begin
  Result := '';
  if Server <> '' then
  begin
    Result := 'Atlas:ci:' + Server;
  end;
end;

function TAtlasCiJob.Secure: Boolean;
begin
  Result := SameText(Copy(Server, 1, 8), 'https://');
end;

end.
