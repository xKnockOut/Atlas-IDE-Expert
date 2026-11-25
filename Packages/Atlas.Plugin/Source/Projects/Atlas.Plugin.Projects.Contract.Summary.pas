unit Atlas.Plugin.Projects.Contract.Summary;

// Datentypen der Projekt-Zusammenfassung (#592) als Vertrag: Die Willkommensseite und andere Features tragen sie
// in den Signaturen ihrer Schnittstellen. Lesen und Schreiben der JSON-Datei bleibt in
// Atlas.Core.Projects.Summary und Atlas.Core.Projects.Summary.Sections; beide führen die Namen als Alias weiter.

interface

uses
  System.SysUtils,
  Atlas.Plugin.CiBuild.Contract;

type
  /// <summary>Fund der Pfadprüfung (#759): fehlende Unit oder Define ohne Quelle.</summary>
  TAtlasSetupFinding = record
    Name: string;
    /// <summary>Datei der ersten Stelle, relativ zum Projektordner.</summary>
    FileName: string;
    /// <summary>Zeile ab 1.</summary>
    Line: Integer;
    /// <summary>Stellen im Projekt.</summary>
    Count: Integer;
    /// <summary>Kein sicherer Fund (Suchpfad mit unbekanntem Makro übersprungen).</summary>
    Uncertain: Boolean;
    /// <summary>Define: ähnliches bekanntes Symbol; Hinweis: Unit im Suchpfad ('' = Package ohne Quelle).</summary>
    Note: string;
    /// <summary>Nur in der Zusammenfassung einer Projektgruppe: Name des Projekts; nicht gespeichert.</summary>
    Project: string;
  end;

  /// <summary>Einrichtung des Projekts für Atlas (#759).</summary>
  TAtlasProjectSetup = record
  public const
    /// <summary>Höchstens so viele Funde je Liste stehen in der Datei.</summary>
    cMaxFindings = 50;
  public
    Known: Boolean;
    /// <summary>„Für dieses Projekt nicht mehr fragen“.</summary>
    Dismissed: Boolean;
    DismissedAt: TDateTime;
    /// <summary>„Suchpfade und Defines prüfen“ lief; die übrigen Felder gelten nur dann.</summary>
    Checked: Boolean;
    CheckedAt: TDateTime;
    Files: Integer;
    Unreadable: Integer;
    /// <summary>Alle fehlenden Units bzw. Defines ohne Quelle, auch über MaxFindings hinaus.</summary>
    MissingUnitCount: Integer;
    UndefinedDefineCount: Integer;
    MissingUnits: TArray<TAtlasSetupFinding>;
    UndefinedDefines: TArray<TAtlasSetupFinding>;
    /// <summary>Hinweise zu requires-Packages (#759); kein Fehler.</summary>
    Hints: TArray<TAtlasSetupFinding>;
    /// <summary>Davon unsicher (in MissingUnitCount bzw. UndefinedDefineCount enthalten).</summary>
    UncertainUnitCount: Integer;
    UncertainDefineCount: Integer;
    /// <summary>Unbekannte Makros übersprungener Such- und Bibliothekspfade.</summary>
    SkippedMacros: TArray<string>;
    class function Empty: TAtlasProjectSetup; static;
    /// <summary>Die letzte Prüfung lief und fand nichts Sicheres (unsichere Funde zählen nicht).</summary>
    function PathsClean: Boolean;
  end;

  /// <summary>Fehlgeschlagener Test des letzten Laufs (#69).</summary>
  TAtlasProjectTestFailure = record
    /// <summary>Voller Name aus dem Bericht von DUnitX (Unit.Fixture.Methode[.Fall]).</summary>
    Test: string;
    Message: string;
    /// <summary>Datei des Tests (absolut); '' ohne Fundstelle.</summary>
    FileName: string;
    /// <summary>Zeile ab 1; 0 = ohne.</summary>
    Line: Integer;
  end;

  /// <summary>Einer der langsamsten Tests des letzten Laufs (#1772).</summary>
  TAtlasProjectSlowTest = record
    /// <summary>Voller Name aus dem Bericht von DUnitX (Unit.Fixture.Methode[.Fall]).</summary>
    Test: string;
    /// <summary>Datei des Tests (absolut); '' ohne Fundstelle.</summary>
    FileName: string;
    /// <summary>Zeile ab 1; 0 = ohne.</summary>
    Line: Integer;
    DurationMs: Integer;
  end;

  /// <summary>Letzter DUnitX-Lauf aus der IDE (#69), Grundlage der Karte Tests (#763).</summary>
  TAtlasProjectTests = record
  public const
    /// <summary>Höchstens so viele fehlgeschlagene Tests stehen in der Datei.</summary>
    cMaxFailures = 50;
    /// <summary>So viele langsamste Tests stehen in der Datei (#1772).</summary>
    cMaxSlowest = 5;
  public
    Known: Boolean;
    /// <summary>Ende des Laufs (UTC).</summary>
    At: TDateTime;
    /// <summary>Testprojekt (.dproj).</summary>
    Project: string;
    Configuration: string;
    Platform: string;
    Passed: Integer;
    Failed: Integer;
    Errors: Integer;
    Skipped: Integer;
    DurationMs: Integer;
    Failures: TArray<TAtlasProjectTestFailure>;
    /// <summary>Die langsamsten Tests, der langsamste zuerst; höchstens cMaxSlowest (#1772).</summary>
    Slowest: TArray<TAtlasProjectSlowTest>;
    class function Empty: TAtlasProjectTests; static;
    /// <summary>Namen der gespeicherten fehlgeschlagenen Tests ohne Doppelte, für --run.</summary>
    function FailedTests: TArray<string>;
    function Total: Integer;
  end;

  /// <summary>Letzter erfolgreicher Release-Build einer Konfiguration und Plattform (#533).</summary>
  TAtlasProjectReleaseBuild = record
    Configuration: string;
    Platform: string;
    Version: string;
    /// <summary>Ende des Builds (UTC).</summary>
    At: TDateTime;
  end;

  /// <summary>Release-Build-Wächter (#533): letzte Prüfung und Versionen der Release-Builds.</summary>
  TAtlasProjectRelease = record
  public const
    /// <summary>Höchstens so viele Einträge in "builds" (je Konfiguration und Plattform einer).</summary>
    cMaxBuilds = 20;
  public
    Known: Boolean;
    /// <summary>Letzte Prüfung (UTC); 0 = noch keine.</summary>
    CheckedAt: TDateTime;
    Configuration: string;
    Platform: string;
    Findings: Integer;
    /// <summary>Die Prüfung hat den Build abgebrochen (build.gate = block).</summary>
    Blocked: Boolean;
    /// <summary>Regel-IDs der Verstöße ohne Doppelte, z. B. release-debug-define.</summary>
    Rules: TArray<string>;
    Builds: TArray<TAtlasProjectReleaseBuild>;
    class function Empty: TAtlasProjectRelease; static;
    /// <summary>Version des letzten erfolgreichen Release-Builds von AConfiguration/APlatform; '' = keiner.
    /// </summary>
    function VersionOf(const AConfiguration, APlatform: string): string;
    /// <summary>Merkt AVersion für AConfiguration/APlatform (ersetzt den alten Eintrag, neueste zuerst).</summary>
    procedure Remember(const AConfiguration, APlatform, AVersion: string; AAtUtc: TDateTime);
  end;

  /// <summary>Letzter Abruf vom Build-Server (#763).</summary>
  TAtlasProjectCi = record
    Known: Boolean;
    /// <summary>"jenkins".</summary>
    Provider: string;
    /// <summary>TAtlasCiJob.Server, z. B. "https://ci.firma.de".</summary>
    Server: string;
    Job: string;
    /// <summary>Branch des Multibranch-Jobs; '' sonst.</summary>
    Branch: string;
    /// <summary>Letzter Versuch (UTC); 0 = noch keiner.</summary>
    Attempt: TDateTime;
    /// <summary>Fehler des letzten Versuchs; None = gelungen.</summary>
    Error: TAtlasCiFetchError;
    /// <summary>Letzter gelungener Abruf (UTC); 0 = noch keiner. Build gilt für diesen Stand.</summary>
    At: TDateTime;
    Build: TAtlasCiBuild;
    class function Empty: TAtlasProjectCi; static;
    /// <summary>Der Stand gehört zu AJob (Anbieter, Server, Job und Branch gleich).</summary>
    function Matches(const AJob: TAtlasCiJob): Boolean;
    /// <summary>Ein Build ist bekannt.</summary>
    function HasBuild: Boolean;
  end;

  /// <summary>Stelle einer Meldung; Zeile und Spalte ab 1, 0 = ohne.</summary>
  TAtlasProjectLocation = record
    FileName: string;
    Line: Integer;
    Column: Integer;
    Code: string;
    Text: string;
    function IsEmpty: Boolean;
  end;

  /// <summary>Stand der Versionsverwaltung beim letzten Abfragen.</summary>
  TAtlasProjectVcs = record
    Known: Boolean;
    /// <summary>Zeitpunkt der Abfrage (UTC).</summary>
    At: TDateTime;
    /// <summary>"git", "svn" oder "none" (keine Arbeitskopie bzw. abgeschaltet).</summary>
    Kind: string;
    /// <summary>Git: Branch ('' bei losgelöstem HEAD); SVN: Pfad wie "trunk".</summary>
    Branch: string;
    Revision: string;
    /// <summary>Geänderte und neue Dateien; -1 unbekannt.</summary>
    Changed: Integer;
    /// <summary>Commits vor bzw. hinter dem Upstream; -1 unbekannt.</summary>
    Ahead: Integer;
    Behind: Integer;
    class function Empty: TAtlasProjectVcs; static;
    /// <summary>Gehört zu einer Arbeitskopie (Git oder SVN).</summary>
    function InWorkingCopy: Boolean;
  end;

  /// <summary>Letzter Build des Benutzers (#527).</summary>
  TAtlasProjectBuild = record
    Known: Boolean;
    At: TDateTime;
    Kind: string;
    Configuration: string;
    Platform: string;
    Succeeded: Boolean;
    Errors: Integer;
    Warnings: Integer;
    Hints: Integer;
    /// <summary>Dauer des Compiles in ms (#758); 0 = unbekannt.</summary>
    DurationMs: Integer;
    First: TAtlasProjectLocation;
    class function Empty: TAtlasProjectBuild; static;
  end;

  /// <summary>Letzte Hintergrundprüfung (#548).</summary>
  TAtlasProjectCheck = record
    Known: Boolean;
    At: TDateTime;
    Errors: Integer;
    First: TAtlasProjectLocation;
    class function Empty: TAtlasProjectCheck; static;
  end;

  /// <summary>Werte je Kennzahl der Code-Metriken in der Reihenfolge von MetricKeys.</summary>
  TAtlasMetricNumbers = array[0..4] of Integer;

  /// <summary>Code-Metriken des Projekts beim letzten Build (#66), Grundlage des Projektverlaufs (#758).</summary>
  TAtlasProjectMetrics = record
    Known: Boolean;
    /// <summary>Zeitpunkt des Builds (UTC).</summary>
    At: TDateTime;
    Files: Integer;
    Methods: Integer;
    /// <summary>Methoden mit mindestens einer Überschreitung.</summary>
    OverLimits: Integer;
    /// <summary>Mittelwert in Zehnteln (125 = 12,5).</summary>
    AverageTenths: TAtlasMetricNumbers;
    Maximum: TAtlasMetricNumbers;
    /// <summary>Methoden über dem Grenzwert je Kennzahl.</summary>
    Exceeded: TAtlasMetricNumbers;
    class function Empty: TAtlasProjectMetrics; static;
  end;

  /// <summary>TODO-Einträge des Projekts beim letzten Build (#68), Grundlage des Projektverlaufs (#758).</summary>
  TAtlasProjectTodos = record
    Known: Boolean;
    /// <summary>Zeitpunkt des Builds (UTC).</summary>
    At: TDateTime;
    /// <summary>Dateien mit mindestens einem offenen Eintrag.</summary>
    Files: Integer;
    Open: Integer;
    Done: Integer;
    /// <summary>Marken der offenen Einträge (TODO, FIXME …); Anzahl in KeywordCounts.</summary>
    Keywords: TArray<string>;
    KeywordCounts: TArray<Integer>;
    class function Empty: TAtlasProjectTodos; static;
  end;

  /// <summary>Neue Regeltreffer gegenüber der Baseline (#97).</summary>
  TAtlasProjectRules = record
    Known: Boolean;
    At: TDateTime;
    NewHits: Integer;
    class function Empty: TAtlasProjectRules; static;
  end;

  /// <summary>Baseline des Projekts (#97); Grundlage für Projektverlauf (#758) und Einrichtung (#759).</summary>
  TAtlasProjectBaseline = record
    Known: Boolean;
    /// <summary>Zeitpunkt des Lesens (UTC): Build oder Aktualisieren.</summary>
    At: TDateTime;
    /// <summary>Die Datei liegt im Projektordner.</summary>
    Exists: Boolean;
    /// <summary>Die Datei ist eine lesbare Baseline; ohne Datei False.</summary>
    Valid: Boolean;
    Entries: Integer;
    /// <summary>Treffer in der Baseline (Summe von "count").</summary>
    Hits: Integer;
    /// <summary>Treffer in Einträgen, deren Datei es nicht mehr gibt.</summary>
    Orphaned: Integer;
    /// <summary>Letztes Aktualisieren über Atlas (UTC); 0 = unbekannt, dann gelten Added und Removed nicht.</summary>
    Updated: TDateTime;
    Added: Integer;
    Removed: Integer;
    class function Empty: TAtlasProjectBaseline; static;
  end;

  {$SCOPEDENUMS ON}
  /// <summary>Reihen des Projektverlaufs (#758) in der Reihenfolge der Kacheln.</summary>
  TAtlasTrendSeries = (Warnings, RuleHits, Todos, Duration, MethodLength);
  {$SCOPEDENUMS OFF}

  TAtlasTrendNumbers = array[TAtlasTrendSeries] of Integer;

  TAtlasTrendFlags = array[TAtlasTrendSeries] of Boolean;

  /// <summary>Messpunkt des Projektverlaufs (#758): Werte eines Builds.</summary>
  TAtlasTrendPoint = record
    /// <summary>Zeitpunkt des Builds (UTC).</summary>
    At: TDateTime;
    /// <summary>Laufende Nummer des Builds (ab 1).</summary>
    Build: Integer;
    /// <summary>Branch bzw. SVN-Pfad zum Zeitpunkt des Builds; '' = unbekannt.</summary>
    Branch: string;
    /// <summary>Commit bzw. Revision; '' = unbekannt.</summary>
    Commit: string;
    /// <summary>Wert je Reihe in Zehnteln (3 Warnungen = 30, 12,5 s = 125); gilt nur mit Has.</summary>
    Values: TAtlasTrendNumbers;
    /// <summary>Wert bekannt; sonst Lücke.</summary>
    Has: TAtlasTrendFlags;
    class function Create(AAtUtc: TDateTime; ABuild: Integer): TAtlasTrendPoint; static;
    procedure SetValue(ASeries: TAtlasTrendSeries; ATenths: Integer);
    procedure Clear(ASeries: TAtlasTrendSeries);
  end;

  /// <summary>Projektverlauf (#758): Ringpuffer der Messpunkte, älteste zuerst.</summary>
  TAtlasProjectTrends = record
    Known: Boolean;
    /// <summary>Builds bisher; Nummer des nächsten Punkts ist Builds + 1.</summary>
    Builds: Integer;
    Points: TArray<TAtlasTrendPoint>;
    class function Empty: TAtlasProjectTrends; static;
  end;

  TAtlasProjectSummary = record
    /// <summary>Vollständiger Pfad der Projektdatei (.dproj, .groupproj …).</summary>
    Project: string;
    /// <summary>UTC; 0 = unbekannt.</summary>
    LastOpened: TDateTime;
    LastClosed: TDateTime;
    /// <summary>„Aus Liste entfernen“ auf der Willkommensseite; Öffnen hebt es auf.</summary>
    Hidden: Boolean;
    Vcs: TAtlasProjectVcs;
    Build: TAtlasProjectBuild;
    Check: TAtlasProjectCheck;
    Rules: TAtlasProjectRules;
    Metrics: TAtlasProjectMetrics;
    Todos: TAtlasProjectTodos;
    Baseline: TAtlasProjectBaseline;
    Trends: TAtlasProjectTrends;
    Setup: TAtlasProjectSetup;
    Tests: TAtlasProjectTests;
    Release: TAtlasProjectRelease;
    Ci: TAtlasProjectCi;
    /// <summary>Gelesener Text der Datei; ToJson behält daraus alle unbekannten Felder.</summary>
    Raw: string;
    class function Create(const AProject: string): TAtlasProjectSummary; static;
    /// <summary>Dateiname ohne Endung.</summary>
    function Name: string;
  end;

  {$SCOPEDENUMS ON}
  /// <summary>Vorlagen in der Reihenfolge der Auswahlliste; Existing ist die Vorgabe.</summary>
  TAtlasSetupTemplate = (Existing, NewStrict, Legacy);

  TAtlasSetupStep = (Found, Config, Baseline, Paths);
  {$SCOPEDENUMS OFF}

  /// <summary>Was die Schritte brauchen: Dateien neben dem Projekt und der Abschnitt "setup".</summary>
  TAtlasSetupFacts = record
    /// <summary>Projektdatei (.dproj, .groupproj); '' = kein Projekt.</summary>
    Project: string;
    /// <summary>atlas.json oder delphi-lsp.json liegt neben der Projektdatei.</summary>
    ConfigExists: Boolean;
    /// <summary>Baseline liegt im Projektordner.</summary>
    BaselineExists: Boolean;
    Setup: TAtlasProjectSetup;
  end;

implementation

{ TAtlasProjectSetup }

class function TAtlasProjectSetup.Empty: TAtlasProjectSetup;
begin
  Result := Default(TAtlasProjectSetup);
  Result.MissingUnits := nil;
  Result.UndefinedDefines := nil;
end;

function TAtlasProjectSetup.PathsClean: Boolean;
begin
  Result := Checked and (MissingUnitCount <= UncertainUnitCount) and (UndefinedDefineCount <= UncertainDefineCount);
end;

{ TAtlasProjectTests }

class function TAtlasProjectTests.Empty: TAtlasProjectTests;
begin
  Result := Default(TAtlasProjectTests);
  Result.Failures := nil;
  Result.Slowest := nil;
end;

function TAtlasProjectTests.FailedTests: TArray<string>;
var
  mFailure: TAtlasProjectTestFailure;
  mName: string;
  mSeen: Boolean;
begin
  Result := nil;
  for mFailure in Failures do
  begin
    if mFailure.Test = '' then
    begin
      Continue;
    end;
    mSeen := False;
    for mName in Result do
    begin
      if SameText(mName, mFailure.Test) then
      begin
        mSeen := True;
      end;
    end;
    if not mSeen then
    begin
      Result := Result + [mFailure.Test];
    end;
  end;
end;

function TAtlasProjectTests.Total: Integer;
begin
  Result := Passed + Failed + Errors + Skipped;
end;

{ TAtlasProjectRelease }

class function TAtlasProjectRelease.Empty: TAtlasProjectRelease;
begin
  Result := Default(TAtlasProjectRelease);
  Result.Rules := nil;
  Result.Builds := nil;
end;

function TAtlasProjectRelease.VersionOf(const AConfiguration, APlatform: string): string;
var
  mBuild: TAtlasProjectReleaseBuild;
begin
  Result := '';
  for mBuild in Builds do
  begin
    if SameText(mBuild.Configuration, AConfiguration) and SameText(mBuild.Platform, APlatform) then
    begin
      Exit(mBuild.Version);
    end;
  end;
end;

procedure TAtlasProjectRelease.Remember(const AConfiguration, APlatform, AVersion: string; AAtUtc: TDateTime);
var
  mEntry: TAtlasProjectReleaseBuild;
  mKept: TArray<TAtlasProjectReleaseBuild>;
  mBuild: TAtlasProjectReleaseBuild;
begin
  mEntry.Configuration := AConfiguration;
  mEntry.Platform := APlatform;
  mEntry.Version := AVersion;
  mEntry.At := AAtUtc;
  mKept := nil;
  mKept := mKept + [mEntry];
  for mBuild in Builds do
  begin
    if (Length(mKept) < cMaxBuilds) and
      not (SameText(mBuild.Configuration, AConfiguration) and SameText(mBuild.Platform, APlatform)) then
    begin
      mKept := mKept + [mBuild];
    end;
  end;
  Builds := mKept;
  Known := True;
end;

{ TAtlasProjectCi }

class function TAtlasProjectCi.Empty: TAtlasProjectCi;
begin
  Result := Default(TAtlasProjectCi);
  Result.Build := TAtlasCiBuild.Empty;
end;

function TAtlasProjectCi.Matches(const AJob: TAtlasCiJob): Boolean;
begin
  Result := Known and SameText(Provider, AJob.Provider) and SameText(Server, AJob.Server) and
    SameText(Job, AJob.Job) and SameText(Branch, AJob.JobBranch);
end;

function TAtlasProjectCi.HasBuild: Boolean;
begin
  Result := Known and (Build.Number > 0);
end;

{ TAtlasProjectLocation }

function TAtlasProjectLocation.IsEmpty: Boolean;
begin
  Result := FileName = '';
end;

{ TAtlasProjectVcs }

class function TAtlasProjectVcs.Empty: TAtlasProjectVcs;
begin
  Result := Default(TAtlasProjectVcs);
  Result.Changed := -1;
  Result.Ahead := -1;
  Result.Behind := -1;
end;

function TAtlasProjectVcs.InWorkingCopy: Boolean;
begin
  Result := Known and (SameText(Kind, 'git') or SameText(Kind, 'svn'));
end;

{ TAtlasProjectBuild }

class function TAtlasProjectBuild.Empty: TAtlasProjectBuild;
begin
  Result := Default(TAtlasProjectBuild);
end;

{ TAtlasProjectCheck }

class function TAtlasProjectCheck.Empty: TAtlasProjectCheck;
begin
  Result := Default(TAtlasProjectCheck);
end;

{ TAtlasProjectMetrics }

class function TAtlasProjectMetrics.Empty: TAtlasProjectMetrics;
begin
  Result := Default(TAtlasProjectMetrics);
end;

{ TAtlasProjectTodos }

class function TAtlasProjectTodos.Empty: TAtlasProjectTodos;
begin
  Result := Default(TAtlasProjectTodos);
  Result.Keywords := nil;
  Result.KeywordCounts := nil;
end;

{ TAtlasProjectRules }

class function TAtlasProjectRules.Empty: TAtlasProjectRules;
begin
  Result := Default(TAtlasProjectRules);
end;

{ TAtlasProjectBaseline }

class function TAtlasProjectBaseline.Empty: TAtlasProjectBaseline;
begin
  Result := Default(TAtlasProjectBaseline);
end;

{ TAtlasTrendPoint }

class function TAtlasTrendPoint.Create(AAtUtc: TDateTime; ABuild: Integer): TAtlasTrendPoint;
begin
  Result := Default(TAtlasTrendPoint);
  Result.At := AAtUtc;
  Result.Build := ABuild;
end;

procedure TAtlasTrendPoint.SetValue(ASeries: TAtlasTrendSeries; ATenths: Integer);
begin
  Values[ASeries] := ATenths;
  Has[ASeries] := True;
end;

procedure TAtlasTrendPoint.Clear(ASeries: TAtlasTrendSeries);
begin
  Values[ASeries] := 0;
  Has[ASeries] := False;
end;

{ TAtlasProjectTrends }

class function TAtlasProjectTrends.Empty: TAtlasProjectTrends;
begin
  Result := Default(TAtlasProjectTrends);
  Result.Points := nil;
end;

{ TAtlasProjectSummary }

class function TAtlasProjectSummary.Create(const AProject: string): TAtlasProjectSummary;
begin
  Result := Default(TAtlasProjectSummary);
  Result.Project := AProject;
  Result.Vcs := TAtlasProjectVcs.Empty;
  Result.Build := TAtlasProjectBuild.Empty;
  Result.Check := TAtlasProjectCheck.Empty;
  Result.Rules := TAtlasProjectRules.Empty;
  Result.Metrics := TAtlasProjectMetrics.Empty;
  Result.Todos := TAtlasProjectTodos.Empty;
  Result.Baseline := TAtlasProjectBaseline.Empty;
  Result.Trends := TAtlasProjectTrends.Empty;
  Result.Setup := TAtlasProjectSetup.Empty;
  Result.Tests := TAtlasProjectTests.Empty;
  Result.Release := TAtlasProjectRelease.Empty;
  Result.Ci := TAtlasProjectCi.Empty;
end;

function TAtlasProjectSummary.Name: string;
var
  mIndex: Integer;
begin
  // Ohne ExtractFileName: Der Pfad hat immer „\“, auch wenn die Tests nicht unter Windows laufen.
  Result := Project;
  for mIndex := Length(Result) downto 1 do
  begin
    if CharInSet(Result[mIndex], ['\', '/']) then
    begin
      Result := Copy(Result, mIndex + 1, MaxInt);
      Break;
    end;
  end;
  for mIndex := Length(Result) downto 1 do
  begin
    if Result[mIndex] = '.' then
    begin
      Result := Copy(Result, 1, mIndex - 1);
      Break;
    end;
  end;
end;

end.
