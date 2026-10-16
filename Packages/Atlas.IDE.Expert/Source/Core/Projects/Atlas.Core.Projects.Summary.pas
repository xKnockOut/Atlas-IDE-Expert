unit Atlas.Core.Projects.Summary;

// Projekt-Zusammenfassung (#592), ohne VCL und Open Tools API: je Projekt
// eine kleine JSON-Datei mit dem, was Atlas zuletzt über das Projekt wusste.
// Die Willkommensseite liest nur diese Dateien und startet keinen Server;
// spätere Bereiche (#755 Weiterarbeiten, #758 Projektverlauf, #762, #763,
// #764) bauen darauf auf.
//
// Ablage: %LOCALAPPDATA%\Atlas\projects\<schlüssel>.json. Der Schlüssel ist
// FNV-1a (64 Bit) über die UTF-16-Codeeinheiten (je zwei Bytes, niedriges
// zuerst) des normierten Projektpfads, als 16 Hexziffern klein geschrieben.
// Normiert: ohne Leerraum am Rand, „/“ wird „\“, ASCII-Buchstaben groß.
// Beispiel: "C:\Projekte\Demo.dproj" → siehe Tests (KeyOf).
//
// Format 1 (UTF-8 ohne BOM; Zeiten in UTC als "2026-10-15T09:30:00Z"):
//   {
//     "format": 1,
//     "project": "C:\\Projekte\\Demo.dproj",
//     "lastOpened": "…", "lastClosed": "…",   // fehlt = unbekannt
//     "hidden": true,                           // nur, wenn aus der Liste entfernt
//     "vcs": {"at": "…", "kind": "git|svn|none", "branch": "main",
//             "revision": "…", "changed": 3, "ahead": 1, "behind": 0},
//     "build": {"at": "…", "kind": "build|make|check|…", "configuration": "Debug",
//               "platform": "Win32", "succeeded": true, "errors": 0,
//               "warnings": 0, "hints": 0, "durationMs": 12480, "first": {…}},
//     "check": {"at": "…", "errors": 2, "first": {"file": "…", "line": 12,
//               "column": 5, "code": "E2003", "text": "…"}},
//     "rules": {"at": "…", "newHits": 3},
//     "metrics": {"at": "…", "files": 12, "methods": 340, "overLimits": 5,
//                 "average": {"length": 12.5, "nesting": 1.2, "cyclomatic": 3.1,
//                             "cognitive": 2.4, "parameters": 1.3},
//                 "maximum": {"length": 140, …}, "exceeded": {"length": 2, …}},
//     "todos": {"at": "…", "files": 4, "open": 9, "done": 2,
//               "keywords": {"FIXME": 2, "TODO": 7}},
//     "baseline": {"at": "…", "exists": true, "valid": true, "entries": 40,
//                  "hits": 52, "orphaned": 2, "updated": "…", "added": 3,
//                  "removed": 5},
//     "trends": {"builds": 31, "points": [{"at": "…", "build": 31,
//                "branch": "main", "commit": "…", "warnings": 3, "ruleHits": 12,
//                "todos": 9, "duration": 12.5, "methodLength": 11.8}, …]},
//     "setup": {"dismissed": true, "dismissedAt": "…",
//               "paths": {"at": "…", "files": 12, "unreadable": 0,
//                         "missingUnits": 2, "undefinedDefines": 1,
//                         "uncertainUnits": 1, "uncertainDefines": 0,
//                         "skippedMacros": ["MYLIB"],
//                         "units": [{"name": "Foo", "file": "Src\\Main.pas",
//                                    "line": 12, "count": 2,
//                                    "uncertain": true}, …],
//                         "defines": [{"name": "USE_LOG", …}, …]}},
//     "tests": {"at": "…", "project": "C:\\Projekte\\Demo.Tests.dproj",
//               "configuration": "Debug", "platform": "Win64", "passed": 40,
//               "failed": 1, "errors": 1, "skipped": 2, "durationMs": 1250,
//               "failures": [{"test": "Demo.Tests.TRechner.Summe.Gross",
//                             "message": "…", "file": "C:\\…\\Demo.Tests.pas",
//                             "line": 35}, …]},
//     "release": {"checkedAt": "…", "configuration": "Release",
//                 "platform": "Win64", "findings": 2, "blocked": true,
//                 "rules": ["release-debug-define", …],
//                 "builds": [{"configuration": "Release", "platform": "Win64",
//                             "version": "1.2.0.0", "at": "…"}, …]},
//     "ci": {"provider": "jenkins", "server": "https://ci.firma.de",
//            "job": "team/kasse", "branch": "main", "attempt": "…",
//            "error": "timeout", "at": "…", "number": 482,
//            "result": "unstable", "started": "…", "durationMs": 61000,
//            "passed": 410, "failed": 2, "skipped": 3,
//            "failures": [{"test": "Demo.Tests.TRechner.Summe",
//                          "message": "…"}, …]}
//   }
// "changed", "ahead", "behind" = -1: unbekannt. "first" ist die erste Fehler-
// meldung (Zeile und Spalte ab 1). "build" ist der letzte Lauf des Benutzers,
// "check" die letzte Hintergrundprüfung (#548), "rules" neue Regeltreffer
// gegenüber der Baseline (#97, nur wenn bekannt). "metrics" sind die
// Code-Metriken des Projekts (#66) beim letzten Build: Dateien, Methoden,
// Methoden über einem Grenzwert, Mittelwert (eine Nachkommastelle), Maximum
// und Zahl der Methoden über dem Grenzwert je Kennzahl. Der Projektverlauf
// (#758) liest daraus z. B. die mittlere Methodenlänge zum Zeitpunkt "at".
// "todos" ist die TODO-Übersicht (#68) beim letzten Build: Dateien mit
// offenen Einträgen, offene und erledigte Einträge, offene je Marke; der
// Projektverlauf liest daraus die Reihe „offene TODOs“ ("open").
// "baseline" ist die Baseline des Projekts (#97), gelesen nach jedem Build
// und nach „Baseline des Projekts aktualisieren“: "exists" = atlas-baseline.json
// (oder der frühere Name) liegt im Projektordner, "valid" = lesbar, "entries"
// Einträge, "hits" Treffer darin, "orphaned" Treffer in Einträgen, deren
// Datei es nicht mehr gibt. "updated", "added" und "removed" stammen vom
// letzten Aktualisieren über Atlas (fehlen = unbekannt; ein Build ändert sie
// nicht). Der Projektverlauf (#758) zeigt „Regeltreffer seit Baseline“
// ("rules.newHits") nur, wenn "exists" gilt, sonst eine Lücke; die Einrichtung
// (#759) liest „Baseline vorhanden“ aus "exists" und bietet sonst
// „Baseline erzeugen“ (Befehl atlas.updateBaseline) an.
// "build.durationMs" ist die Dauer des Compiles (#527, bei einer Projektgruppe
// die der Gruppe); fehlt = unbekannt.
// "trends" ist der Projektverlauf (#758): je Build des Benutzers ein Messpunkt
// (Ringpuffer, höchstens welcomePage.trends.points), älteste zuerst. "builds"
// zählt alle Builds, "build" ist die laufende Nummer des Punkts. Je Reihe der
// Wert zum Zeitpunkt des Builds: "warnings" Warnungen plus Hinweise, "ruleHits"
// neue Regeltreffer gegenüber der Baseline (nur mit Baseline), "todos" offene
// TODOs, "duration" Build-Dauer in s, "methodLength" mittlere Methodenlänge in
// Zeilen (beide mit einer Nachkommastelle). Fehlt ein Wert, war er nicht
// bekannt; der Verlauf zeigt dort eine Lücke. Unbekannte Felder eines Punkts
// bleiben erhalten (zugeordnet über "build").
// "setup" ist die Einrichtung des Projekts für Atlas (#759): "dismissed" =
// „Für dieses Projekt nicht mehr fragen“ (die Karte erscheint nicht mehr;
// der Befehl „Projekt für Atlas einrichten“ hebt es auf). "paths" ist das
// Ergebnis von „Suchpfade und Defines prüfen“: gelesene und nicht lesbare
// Dateien, Zahl der fehlenden Units und der Defines ohne Quelle und die
// ersten Funde (höchstens TAtlasProjectSetup.MaxFindings je Liste; Datei
// relativ zum Projektordner, Zeile ab 1, "count" Stellen im Projekt).
// "skippedMacros" sind unbekannte Makros übersprungener Suchpfade; Funde mit
// "uncertain" sind deshalb nicht sicher ("uncertainUnits" und
// "uncertainDefines" zählen sie, auch über die gespeicherten hinaus). Bei
// einer Projektgruppe steht die Prüfung je Projekt in dessen Zusammenfassung.
// "tests" ist der letzte DUnitX-Lauf aus der IDE (#69; Grundlage der Karte
// Tests #763): Testprojekt, Konfiguration, Plattform, Zahlen, Dauer und die
// fehlgeschlagenen Tests (höchstens TAtlasProjectTests.MaxFailures; "failed"
// und "errors" zählen alle). "test" ist der volle Name aus dem Bericht von
// DUnitX; „Fehlgeschlagene erneut ausführen“ übergibt genau diese Namen an
// --run. "file" ist absolut, "line" ab 1 (Methodenkopf), beide fehlen ohne
// Fundstelle. Läufe über das MCP-Werkzeug run_tests schreiben hier nicht.
// "release" ist der Release-Build-Wächter (#533): "checkedAt" bis "rules" die
// letzte Prüfung vor einem Release-Build (Konfiguration, Plattform, Zahl der
// Verstöße, ob der Build abgebrochen wurde, Regel-IDs der Verstöße ohne
// Doppelte), "builds" je Konfiguration und Plattform die Version des letzten
// erfolgreichen Release-Builds (Grundlage von „unveränderte Version“; auch
// für die Schnellaktion „Öffnen und bauen“ #764).
// "ci" ist der letzte Abruf vom Build-Server (#763, Bereich Testergebnisse):
// Anbieter, Server (nur Schema, Rechner und Port, nie Zugangsdaten), Job und
// bei Multibranch der Branch, zu dem der Stand gehört; "attempt" der letzte
// Versuch, "error" dessen Fehler ("timeout", "network", "unauthorized" …;
// fehlt = gelungen), "at" der letzte gelungene Abruf. "number" bis
// "durationMs" sind der letzte abgeschlossene Build ("result" wie
// TAtlasCiBuild.OutcomeKey), "passed" bis "failures" sein Testbericht (fehlen
// ohne Bericht; höchstens TAtlasCiBuild.MaxFailures Fehlschläge mit vollem
// Namen und erster Zeile der Meldung). Schlägt ein Abruf fehl, bleibt der
// letzte Build stehen („Stand vom …“).
//
// Erweitern: Neue Felder und Abschnitte dürfen jederzeit dazukommen, ohne
// "format" zu erhöhen. Leser übergehen, was sie nicht kennen; Schreiber
// behalten es (auch innerhalb bekannter Abschnitte, z. B. "build.metrics"
// aus #758). "format" steigt nur bei einer inkompatiblen Änderung; eine
// Datei mit höherem "format" liest diese Fassung nicht und überschreibt sie
// nicht.
// Nicht threadsicher je Datei: Die IDE schreibt nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract;

type
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
    /// <summary>Liest die Antwort von atlas.server.metrics im Modus "summary" ({"summary": {…}}) oder einen
    /// Abschnitt "metrics"; AAtUtc wird der Zeitpunkt. False bei ungültigem Text.</summary>
    class function FromServer(const AJson: string; AAtUtc: TDateTime; out AMetrics: TAtlasProjectMetrics): Boolean;
      static;
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
    /// <summary>Offene Einträge mit der Marke AKeyword; 0, wenn es keine gibt.</summary>
    function CountOf(const AKeyword: string): Integer;
    /// <summary>Liest die Antwort von atlas.server.todos im Modus "summary" ({"summary": {…}}) oder einen
    /// Abschnitt "todos"; AAtUtc wird der Zeitpunkt. False bei ungültigem Text.</summary>
    class function FromServer(const AJson: string; AAtUtc: TDateTime; out ATodos: TAtlasProjectTodos): Boolean;
      static;
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
    /// <summary>Nur in der Zusammenfassung einer Projektgruppe: Name des Projekts; nicht gespeichert.</summary>
    Project: string;
  end;

  /// <summary>Einrichtung des Projekts für Atlas (#759).</summary>
  TAtlasProjectSetup = record
  public const
    /// <summary>Höchstens so viele Funde je Liste stehen in der Datei.</summary>
    MaxFindings = 50;
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

  /// <summary>Letzter DUnitX-Lauf aus der IDE (#69), Grundlage der Karte Tests (#763).</summary>
  TAtlasProjectTests = record
  public const
    /// <summary>Höchstens so viele fehlgeschlagene Tests stehen in der Datei.</summary>
    MaxFailures = 50;
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
    MaxBuilds = 20;
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

  TAtlasProjectSummaryChange = reference to procedure(var ASummary: TAtlasProjectSummary);

  TAtlasProjectSummaries = class
  public const
    /// <summary>Format, das diese Fassung liest und schreibt.</summary>
    Format = 1;
    /// <summary>Kennzahlen im Abschnitt "metrics" (wie atlas.server.metrics, #66).</summary>
    MetricKeys: array[0..4] of string = ('length', 'nesting', 'cyclomatic', 'cognitive', 'parameters');
    /// <summary>Namen der Reihen im Abschnitt "trends" und in welcomePage.trends.series (#758).</summary>
    TrendKeys: array[TAtlasTrendSeries] of string = ('warnings', 'ruleHits', 'todos', 'duration', 'methodLength');
    /// <summary>Reihen mit einer Nachkommastelle in der Datei; die übrigen sind ganze Zahlen.</summary>
    TrendDecimals: array[TAtlasTrendSeries] of Boolean = (False, False, False, True, True);
    /// <summary>Unterordner von %LOCALAPPDATA%\Atlas.</summary>
    FolderName = 'projects';
  public
    /// <summary>Normierter Pfad für Vergleich und Schlüssel.</summary>
    class function NormalizedPath(const AProject: string): string; static;
    /// <summary>16 Hexziffern (FNV-1a 64 über den normierten Pfad).</summary>
    class function KeyOf(const AProject: string): string; static;
    /// <summary>AFolder\&lt;schlüssel&gt;.json; AFolder ist der Ordner "projects".</summary>
    class function FileFor(const AFolder, AProject: string): string; static;
    /// <summary>Zeit in UTC als "2026-10-15T09:30:00Z"; '' für 0.</summary>
    class function TimeText(AUtc: TDateTime): string; static;
    /// <summary>Umkehrung von TimeText; Bruchteile und Zeitzone "Z" erlaubt; 0 bei ungültigem Text.</summary>
    class function TimeOf(const AText: string): TDateTime; static;
    /// <summary>Liest AJson. False bei ungültigem Inhalt oder höherem Format; ASummary ist dann leer.</summary>
    class function Parse(const AJson: string; out ASummary: TAtlasProjectSummary): Boolean; static;
    /// <summary>JSON der Zusammenfassung; unbekannte Felder aus ASummary.Raw bleiben erhalten.</summary>
    class function ToJson(const ASummary: TAtlasProjectSummary): string; static;
    /// <summary>Format einer Datei (0 ohne oder bei ungültigem Inhalt).</summary>
    class function FormatOf(const AJson: string): Integer; static;
    /// <summary>Liest die Datei zu AProject; False ohne oder bei ungültiger Datei (ASummary dann leer mit
    /// Project = AProject).</summary>
    class function Load(const AFolder, AProject: string; out ASummary: TAtlasProjectSummary): Boolean; static;
    /// <summary>Schreibt (über eine temporäre Datei); False bei Fehler oder wenn die vorhandene Datei ein
    /// höheres Format hat.</summary>
    class function Save(const AFolder: string; const ASummary: TAtlasProjectSummary): Boolean; static;
    /// <summary>Lesen, AChange anwenden, schreiben.</summary>
    class function Update(const AFolder, AProject: string; const AChange: TAtlasProjectSummaryChange): Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Generics.Collections,
  System.Classes,
  System.IOUtils,
  System.JSON;

{$OVERFLOWCHECKS OFF}
{$RANGECHECKS OFF}

const
  // Bekannte Felder; alles andere übernimmt ToJson unverändert aus Raw.
  TopKeys: array[0..16] of string = ('format', 'project', 'lastOpened', 'lastClosed', 'hidden', 'vcs', 'build',
    'check', 'rules', 'metrics', 'todos', 'baseline', 'trends', 'setup', 'tests', 'release', 'ci');
  VcsKeys: array[0..6] of string = ('at', 'kind', 'branch', 'revision', 'changed', 'ahead', 'behind');
  BuildKeys: array[0..9] of string = ('at', 'kind', 'configuration', 'platform', 'succeeded', 'errors', 'warnings',
    'hints', 'durationMs', 'first');
  CheckKeys: array[0..2] of string = ('at', 'errors', 'first');
  RulesKeys: array[0..1] of string = ('at', 'newHits');
  MetricsKeys: array[0..6] of string = ('at', 'files', 'methods', 'overLimits', 'average', 'maximum', 'exceeded');
  TodosKeys: array[0..4] of string = ('at', 'files', 'open', 'done', 'keywords');
  BaselineKeys: array[0..8] of string = ('at', 'exists', 'valid', 'entries', 'hits', 'orphaned', 'updated', 'added',
    'removed');
  TrendsKeys: array[0..1] of string = ('builds', 'points');
  TrendPointKeys: array[0..8] of string = ('at', 'build', 'branch', 'commit', 'warnings', 'ruleHits', 'todos',
    'duration', 'methodLength');
  SetupKeys: array[0..2] of string = ('dismissed', 'dismissedAt', 'paths');
  TestsKeys: array[0..9] of string = ('at', 'project', 'configuration', 'platform', 'passed', 'failed', 'errors',
    'skipped', 'durationMs', 'failures');
  ReleaseKeys: array[0..6] of string = ('checkedAt', 'configuration', 'platform', 'findings', 'blocked', 'rules',
    'builds');
  CiKeys: array[0..14] of string = ('provider', 'server', 'job', 'branch', 'attempt', 'error', 'at', 'number',
    'result', 'started', 'durationMs', 'passed', 'failed', 'skipped', 'failures');
  CiFailureKeys: array[0..1] of string = ('test', 'message');
  ReleaseBuildKeys: array[0..3] of string = ('configuration', 'platform', 'version', 'at');
  PathsKeys: array[0..9] of string = ('at', 'files', 'unreadable', 'missingUnits', 'undefinedDefines', 'units',
    'defines', 'uncertainUnits', 'uncertainDefines', 'skippedMacros');

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
  Index: Integer;
begin
  // Ohne ExtractFileName: Der Pfad hat immer „\“, auch wenn die Tests nicht unter Windows laufen.
  Result := Project;
  for Index := Length(Result) downto 1 do
    if CharInSet(Result[Index], ['\', '/']) then
    begin
      Result := Copy(Result, Index + 1, MaxInt);
      Break;
    end;
  for Index := Length(Result) downto 1 do
    if Result[Index] = '.' then
    begin
      Result := Copy(Result, 1, Index - 1);
      Break;
    end;
end;

{ JSON-Helfer }

function Known(const AKeys: array of string; const AName: string): Boolean;
var
  Key: string;
begin
  Result := False;
  for Key in AKeys do
    if Key = AName then
      Exit(True);
end;

function TextOf(AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if Value is TJSONString then
    Result := TJSONString(Value).Value;
end;

function NumberOf(AObject: TJSONObject; const AName: string; ADefault: Integer): Integer;
var
  Value: TJSONValue;
begin
  Result := ADefault;
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if Value is TJSONNumber then
    Result := TJSONNumber(Value).AsInt
  else if Value is TJSONString then
    Result := StrToIntDef(TJSONString(Value).Value, ADefault);
end;

function FlagOf(AObject: TJSONObject; const AName: string): Boolean;
var
  Value: TJSONValue;
begin
  Result := False;
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if Value is TJSONBool then
    Result := SameText(Value.Value, 'true');
end;

function ObjectOf(AObject: TJSONObject; const AName: string): TJSONObject;
var
  Value: TJSONValue;
begin
  Result := nil;
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if Value is TJSONObject then
    Result := TJSONObject(Value);
end;

function LocationOf(AObject: TJSONObject): TAtlasProjectLocation;
begin
  Result := Default(TAtlasProjectLocation);
  if AObject = nil then
    Exit;
  Result.FileName := TextOf(AObject, 'file');
  Result.Line := NumberOf(AObject, 'line', 0);
  Result.Column := NumberOf(AObject, 'column', 0);
  Result.Code := TextOf(AObject, 'code');
  Result.Text := TextOf(AObject, 'text');
end;

function LocationJson(const ALocation: TAtlasProjectLocation): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('file', ALocation.FileName);
  Result.AddPair('line', TJSONNumber.Create(ALocation.Line));
  Result.AddPair('column', TJSONNumber.Create(ALocation.Column));
  if ALocation.Code <> '' then
    Result.AddPair('code', ALocation.Code);
  if ALocation.Text <> '' then
    Result.AddPair('text', ALocation.Text);
end;

/// <summary>Unbekannte Felder aus AOriginal (darf nil sein) an ATarget anhängen.</summary>
procedure KeepUnknown(ATarget, AOriginal: TJSONObject; const AKeys: array of string);
var
  Index: Integer;
  Pair: TJSONPair;
begin
  if AOriginal = nil then
    Exit;
  for Index := 0 to AOriginal.Count - 1 do
  begin
    Pair := AOriginal.Pairs[Index];
    if not Known(AKeys, Pair.JsonString.Value) then
      ATarget.AddPair(Pair.JsonString.Value, TJSONValue(Pair.JsonValue.Clone));
  end;
end;

procedure AddTime(AObject: TJSONObject; const AName: string; AUtc: TDateTime);
begin
  if AUtc > 0 then
    AObject.AddPair(AName, TAtlasProjectSummaries.TimeText(AUtc));
end;

/// <summary>Zahlen je Kennzahl aus AObject; ATenths: Dezimalzahlen als Zehntel. Fehlende bleiben 0.</summary>
function MetricNumbersOf(AObject: TJSONObject; ATenths: Boolean): TAtlasMetricNumbers;
var
  Index: Integer;
  Value: TJSONValue;
begin
  for Index := Low(Result) to High(Result) do
  begin
    Result[Index] := 0;
    if AObject = nil then
      Continue;
    Value := AObject.GetValue(TAtlasProjectSummaries.MetricKeys[Index]);
    if not (Value is TJSONNumber) then
      Continue;
    if ATenths then
      Result[Index] := Round(TJSONNumber(Value).AsDouble * 10)
    else
      Result[Index] := TJSONNumber(Value).AsInt;
  end;
end;

/// <summary>Objekt {"length": …, …}; ATenths: Werte als Dezimalzahl mit einer Nachkommastelle.</summary>
function MetricNumbersJson(const ANumbers: TAtlasMetricNumbers; ATenths: Boolean): TJSONObject;
var
  Index: Integer;
begin
  Result := TJSONObject.Create;
  for Index := Low(ANumbers) to High(ANumbers) do
    if ATenths then
      Result.AddPair(TAtlasProjectSummaries.MetricKeys[Index], TJSONNumber.Create(ANumbers[Index] / 10))
    else
      Result.AddPair(TAtlasProjectSummaries.MetricKeys[Index], TJSONNumber.Create(ANumbers[Index]));
end;

/// <summary>Kennzahlen aus einem Objekt mit files, methods, overLimits, average, maximum, exceeded.</summary>
function MetricsOf(ASection: TJSONObject): TAtlasProjectMetrics;
begin
  Result := TAtlasProjectMetrics.Empty;
  if ASection = nil then
    Exit;
  Result.Known := True;
  Result.At := TAtlasProjectSummaries.TimeOf(TextOf(ASection, 'at'));
  Result.Files := NumberOf(ASection, 'files', 0);
  Result.Methods := NumberOf(ASection, 'methods', 0);
  Result.OverLimits := NumberOf(ASection, 'overLimits', 0);
  Result.AverageTenths := MetricNumbersOf(ObjectOf(ASection, 'average'), True);
  Result.Maximum := MetricNumbersOf(ObjectOf(ASection, 'maximum'), False);
  Result.Exceeded := MetricNumbersOf(ObjectOf(ASection, 'exceeded'), False);
end;

{ TAtlasProjectMetrics }

class function TAtlasProjectMetrics.Empty: TAtlasProjectMetrics;
begin
  Result := Default(TAtlasProjectMetrics);
end;

class function TAtlasProjectMetrics.FromServer(const AJson: string; AAtUtc: TDateTime;
  out AMetrics: TAtlasProjectMetrics): Boolean;
var
  Value: TJSONValue;
  Section: TJSONObject;
begin
  AMetrics := TAtlasProjectMetrics.Empty;
  Result := False;
  try
    Value := TJSONObject.ParseJSONValue(AJson);
  except
    on Exception do
      Value := nil;
  end;
  try
    if not (Value is TJSONObject) then
      Exit;
    Section := ObjectOf(TJSONObject(Value), 'summary');
    if Section = nil then
      Section := ObjectOf(TJSONObject(Value), 'metrics');
    if Section = nil then
      Section := TJSONObject(Value);
    if not (Section.GetValue('methods') is TJSONNumber) then
      Exit;
    AMetrics := MetricsOf(Section);
    AMetrics.At := AAtUtc;
    Result := True;
  finally
    Value.Free;
  end;
end;

/// <summary>Zahlen aus einem Objekt mit files, open, done, keywords.</summary>
function TodosOf(ASection: TJSONObject): TAtlasProjectTodos;
var
  Keywords: TJSONObject;
  Index: Integer;
  Pair: TJSONPair;
begin
  Result := TAtlasProjectTodos.Empty;
  if ASection = nil then
    Exit;
  Result.Known := True;
  Result.At := TAtlasProjectSummaries.TimeOf(TextOf(ASection, 'at'));
  Result.Files := NumberOf(ASection, 'files', 0);
  Result.Open := NumberOf(ASection, 'open', 0);
  Result.Done := NumberOf(ASection, 'done', 0);
  Keywords := ObjectOf(ASection, 'keywords');
  if Keywords = nil then
    Exit;
  for Index := 0 to Keywords.Count - 1 do
  begin
    Pair := Keywords.Pairs[Index];
    if Pair.JsonValue is TJSONNumber then
    begin
      Result.Keywords := Result.Keywords + [Pair.JsonString.Value];
      Result.KeywordCounts := Result.KeywordCounts + [TJSONNumber(Pair.JsonValue).AsInt];
    end;
  end;
end;

{ TAtlasProjectTodos }

class function TAtlasProjectTodos.Empty: TAtlasProjectTodos;
begin
  Result := Default(TAtlasProjectTodos);
  Result.Keywords := nil;
  Result.KeywordCounts := nil;
end;

function TAtlasProjectTodos.CountOf(const AKeyword: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Keywords) do
    if SameText(Keywords[Index], AKeyword) then
      Exit(KeywordCounts[Index]);
  Result := 0;
end;

class function TAtlasProjectTodos.FromServer(const AJson: string; AAtUtc: TDateTime;
  out ATodos: TAtlasProjectTodos): Boolean;
var
  Value: TJSONValue;
  Section: TJSONObject;
begin
  ATodos := TAtlasProjectTodos.Empty;
  Result := False;
  try
    Value := TJSONObject.ParseJSONValue(AJson);
  except
    on Exception do
      Value := nil;
  end;
  try
    if not (Value is TJSONObject) then
      Exit;
    Section := ObjectOf(TJSONObject(Value), 'summary');
    if Section = nil then
      Section := ObjectOf(TJSONObject(Value), 'todos');
    if Section = nil then
      Section := TJSONObject(Value);
    if not (Section.GetValue('open') is TJSONNumber) then
      Exit;
    ATodos := TodosOf(Section);
    ATodos.At := AAtUtc;
    Result := True;
  finally
    Value.Free;
  end;
end;

/// <summary>Abschnitt "trends"; leer ohne Abschnitt. Punkte ohne gültige Nummer bekommen eine nach der letzten.
/// </summary>
function TrendsOf(ASection: TJSONObject): TAtlasProjectTrends;
var
  Points: TJSONValue;
  Item: TJSONValue;
  Index: Integer;
  Series: TAtlasTrendSeries;
  Point: TAtlasTrendPoint;
  Value: TJSONValue;
  Highest: Integer;
begin
  Result := TAtlasProjectTrends.Empty;
  if ASection = nil then
    Exit;
  Result.Known := True;
  Result.Builds := NumberOf(ASection, 'builds', 0);
  Highest := 0;
  Points := ASection.GetValue('points');
  if Points is TJSONArray then
    for Index := 0 to TJSONArray(Points).Count - 1 do
    begin
      Item := TJSONArray(Points).Items[Index];
      if not (Item is TJSONObject) then
        Continue;
      Point := TAtlasTrendPoint.Create(TAtlasProjectSummaries.TimeOf(TextOf(TJSONObject(Item), 'at')),
        NumberOf(TJSONObject(Item), 'build', 0));
      if Point.Build <= Highest then
        Point.Build := Highest + 1;
      Highest := Point.Build;
      Point.Branch := TextOf(TJSONObject(Item), 'branch');
      Point.Commit := TextOf(TJSONObject(Item), 'commit');
      for Series := Low(TAtlasTrendSeries) to High(TAtlasTrendSeries) do
      begin
        Value := TJSONObject(Item).GetValue(TAtlasProjectSummaries.TrendKeys[Series]);
        if Value is TJSONNumber then
          Point.SetValue(Series, Round(TJSONNumber(Value).AsDouble * 10));
      end;
      Result.Points := Result.Points + [Point];
    end;
  // Ohne oder mit zu kleinem Zähler: mindestens die höchste Nummer.
  if Result.Builds < Highest then
    Result.Builds := Highest;
end;

/// <summary>Punkt mit der Nummer ABuild aus dem Abschnitt "trends" von AOriginal (darf nil sein); nil ohne.</summary>
function OriginalPoint(AOriginal: TJSONObject; ABuild: Integer): TJSONObject;
var
  Points: TJSONValue;
  Index: Integer;
  Item: TJSONValue;
begin
  Result := nil;
  if AOriginal = nil then
    Exit;
  Points := AOriginal.GetValue('points');
  if not (Points is TJSONArray) then
    Exit;
  for Index := 0 to TJSONArray(Points).Count - 1 do
  begin
    Item := TJSONArray(Points).Items[Index];
    if (Item is TJSONObject) and (NumberOf(TJSONObject(Item), 'build', 0) = ABuild) then
      Exit(TJSONObject(Item));
  end;
end;

function TrendsJson(const ATrends: TAtlasProjectTrends; AOriginal: TJSONObject): TJSONObject;
var
  Points: TJSONArray;
  Item: TJSONObject;
  Point: TAtlasTrendPoint;
  Series: TAtlasTrendSeries;
begin
  Result := TJSONObject.Create;
  Result.AddPair('builds', TJSONNumber.Create(ATrends.Builds));
  Points := TJSONArray.Create;
  Result.AddPair('points', Points);
  for Point in ATrends.Points do
  begin
    Item := TJSONObject.Create;
    Points.AddElement(Item);
    AddTime(Item, 'at', Point.At);
    Item.AddPair('build', TJSONNumber.Create(Point.Build));
    if Point.Branch <> '' then
      Item.AddPair('branch', Point.Branch);
    if Point.Commit <> '' then
      Item.AddPair('commit', Point.Commit);
    for Series := Low(TAtlasTrendSeries) to High(TAtlasTrendSeries) do
    begin
      // Lücke: kein Feld.
      if not Point.Has[Series] then
        Continue;
      if TAtlasProjectSummaries.TrendDecimals[Series] then
        Item.AddPair(TAtlasProjectSummaries.TrendKeys[Series], TJSONNumber.Create(Point.Values[Series] / 10))
      else
        Item.AddPair(TAtlasProjectSummaries.TrendKeys[Series], TJSONNumber.Create(Point.Values[Series] div 10));
    end;
    KeepUnknown(Item, OriginalPoint(AOriginal, Point.Build), TrendPointKeys);
  end;
  KeepUnknown(Result, AOriginal, TrendsKeys);
end;

/// <summary>Funde aus einem Array [{"name", "file", "line", "count"}]; Einträge ohne Namen fallen weg.</summary>
function SetupFindingsOf(AValue: TJSONValue): TArray<TAtlasSetupFinding>;
var
  Index: Integer;
  Item: TJSONValue;
  Finding: TAtlasSetupFinding;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
    Exit;
  for Index := 0 to TJSONArray(AValue).Count - 1 do
  begin
    Item := TJSONArray(AValue).Items[Index];
    if not (Item is TJSONObject) then
      Continue;
    Finding.Name := TextOf(TJSONObject(Item), 'name');
    Finding.FileName := TextOf(TJSONObject(Item), 'file');
    Finding.Line := NumberOf(TJSONObject(Item), 'line', 0);
    Finding.Count := NumberOf(TJSONObject(Item), 'count', 1);
    Finding.Uncertain := FlagOf(TJSONObject(Item), 'uncertain');
    if (Finding.Name <> '') and (Length(Result) < TAtlasProjectSetup.MaxFindings) then
      Result := Result + [Finding];
  end;
end;

function SetupFindingsJson(const AFindings: TArray<TAtlasSetupFinding>): TJSONArray;
var
  Index: Integer;
  Item: TJSONObject;
begin
  Result := TJSONArray.Create;
  for Index := 0 to High(AFindings) do
  begin
    if Index >= TAtlasProjectSetup.MaxFindings then
      Break;
    Item := TJSONObject.Create;
    Result.AddElement(Item);
    Item.AddPair('name', AFindings[Index].Name);
    if AFindings[Index].FileName <> '' then
      Item.AddPair('file', AFindings[Index].FileName);
    if AFindings[Index].Line > 0 then
      Item.AddPair('line', TJSONNumber.Create(AFindings[Index].Line));
    Item.AddPair('count', TJSONNumber.Create(AFindings[Index].Count));
    if AFindings[Index].Uncertain then
      Item.AddPair('uncertain', TJSONBool.Create(True));
  end;
end;

/// <summary>Texte aus einem Array von Zeichenketten; anderes (auch Zahlen) fällt weg.</summary>
function TextsOfSetup(AValue: TJSONValue): TArray<string>;
var
  Index: Integer;
  Item: TJSONValue;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
    Exit;
  for Index := 0 to TJSONArray(AValue).Count - 1 do
  begin
    Item := TJSONArray(AValue).Items[Index];
    // TJSONNumber erbt von TJSONString.
    if (Item is TJSONString) and not (Item is TJSONNumber) and (Item.Value <> '') then
      Result := Result + [Item.Value];
  end;
end;

/// <summary>Abschnitt "setup"; leer ohne Abschnitt.</summary>
function SetupOf(ASection: TJSONObject): TAtlasProjectSetup;
var
  Paths: TJSONObject;
begin
  Result := TAtlasProjectSetup.Empty;
  if ASection = nil then
    Exit;
  Result.Known := True;
  Result.Dismissed := FlagOf(ASection, 'dismissed');
  Result.DismissedAt := TAtlasProjectSummaries.TimeOf(TextOf(ASection, 'dismissedAt'));
  Paths := ObjectOf(ASection, 'paths');
  if Paths = nil then
    Exit;
  Result.Checked := True;
  Result.CheckedAt := TAtlasProjectSummaries.TimeOf(TextOf(Paths, 'at'));
  Result.Files := NumberOf(Paths, 'files', 0);
  Result.Unreadable := NumberOf(Paths, 'unreadable', 0);
  Result.MissingUnits := SetupFindingsOf(Paths.GetValue('units'));
  Result.UndefinedDefines := SetupFindingsOf(Paths.GetValue('defines'));
  // Die Zähler sind nie kleiner als die gespeicherten Funde.
  Result.MissingUnitCount := NumberOf(Paths, 'missingUnits', 0);
  if Result.MissingUnitCount < Length(Result.MissingUnits) then
    Result.MissingUnitCount := Length(Result.MissingUnits);
  Result.UndefinedDefineCount := NumberOf(Paths, 'undefinedDefines', 0);
  if Result.UndefinedDefineCount < Length(Result.UndefinedDefines) then
    Result.UndefinedDefineCount := Length(Result.UndefinedDefines);
  // Unsichere nie mehr als alle.
  Result.UncertainUnitCount := NumberOf(Paths, 'uncertainUnits', 0);
  if Result.UncertainUnitCount > Result.MissingUnitCount then
    Result.UncertainUnitCount := Result.MissingUnitCount;
  Result.UncertainDefineCount := NumberOf(Paths, 'uncertainDefines', 0);
  if Result.UncertainDefineCount > Result.UndefinedDefineCount then
    Result.UncertainDefineCount := Result.UndefinedDefineCount;
  Result.SkippedMacros := TextsOfSetup(Paths.GetValue('skippedMacros'));
end;

function SetupJson(const ASetup: TAtlasProjectSetup; AOriginal: TJSONObject): TJSONObject;
var
  Paths: TJSONObject;
  Macros: TJSONArray;
  Macro: string;
begin
  Result := TJSONObject.Create;
  if ASetup.Dismissed then
  begin
    Result.AddPair('dismissed', TJSONBool.Create(True));
    AddTime(Result, 'dismissedAt', ASetup.DismissedAt);
  end;
  if ASetup.Checked then
  begin
    Paths := TJSONObject.Create;
    Result.AddPair('paths', Paths);
    AddTime(Paths, 'at', ASetup.CheckedAt);
    Paths.AddPair('files', TJSONNumber.Create(ASetup.Files));
    Paths.AddPair('unreadable', TJSONNumber.Create(ASetup.Unreadable));
    Paths.AddPair('missingUnits', TJSONNumber.Create(ASetup.MissingUnitCount));
    Paths.AddPair('undefinedDefines', TJSONNumber.Create(ASetup.UndefinedDefineCount));
    if ASetup.UncertainUnitCount > 0 then
      Paths.AddPair('uncertainUnits', TJSONNumber.Create(ASetup.UncertainUnitCount));
    if ASetup.UncertainDefineCount > 0 then
      Paths.AddPair('uncertainDefines', TJSONNumber.Create(ASetup.UncertainDefineCount));
    if Length(ASetup.SkippedMacros) > 0 then
    begin
      Macros := TJSONArray.Create;
      Paths.AddPair('skippedMacros', Macros);
      for Macro in ASetup.SkippedMacros do
        Macros.Add(Macro);
    end;
    Paths.AddPair('units', SetupFindingsJson(ASetup.MissingUnits));
    Paths.AddPair('defines', SetupFindingsJson(ASetup.UndefinedDefines));
    KeepUnknown(Paths, ObjectOf(AOriginal, 'paths'), PathsKeys);
  end;
  KeepUnknown(Result, AOriginal, SetupKeys);
end;

{ TAtlasProjectTests }

class function TAtlasProjectTests.Empty: TAtlasProjectTests;
begin
  Result := Default(TAtlasProjectTests);
  Result.Failures := nil;
end;

function TAtlasProjectTests.FailedTests: TArray<string>;
var
  Failure: TAtlasProjectTestFailure;
  Name: string;
  Seen: Boolean;
begin
  Result := nil;
  for Failure in Failures do
  begin
    if Failure.Test = '' then
      Continue;
    Seen := False;
    for Name in Result do
      if SameText(Name, Failure.Test) then
        Seen := True;
    if not Seen then
      Result := Result + [Failure.Test];
  end;
end;

function TAtlasProjectTests.Total: Integer;
begin
  Result := Passed + Failed + Errors + Skipped;
end;

function TestsOf(ASection: TJSONObject): TAtlasProjectTests;
var
  Items: TJSONValue;
  Item: TJSONValue;
  Failure: TAtlasProjectTestFailure;
begin
  Result := TAtlasProjectTests.Empty;
  if ASection = nil then
    Exit;
  Result.Known := True;
  Result.At := TAtlasProjectSummaries.TimeOf(TextOf(ASection, 'at'));
  Result.Project := TextOf(ASection, 'project');
  Result.Configuration := TextOf(ASection, 'configuration');
  Result.Platform := TextOf(ASection, 'platform');
  Result.Passed := NumberOf(ASection, 'passed', 0);
  Result.Failed := NumberOf(ASection, 'failed', 0);
  Result.Errors := NumberOf(ASection, 'errors', 0);
  Result.Skipped := NumberOf(ASection, 'skipped', 0);
  Result.DurationMs := NumberOf(ASection, 'durationMs', 0);
  Items := ASection.GetValue('failures');
  if not (Items is TJSONArray) then
    Exit;
  for Item in TJSONArray(Items) do
  begin
    if not (Item is TJSONObject) or (Length(Result.Failures) >= TAtlasProjectTests.MaxFailures) then
      Continue;
    Failure := Default(TAtlasProjectTestFailure);
    Failure.Test := TextOf(TJSONObject(Item), 'test');
    Failure.Message := TextOf(TJSONObject(Item), 'message');
    Failure.FileName := TextOf(TJSONObject(Item), 'file');
    Failure.Line := NumberOf(TJSONObject(Item), 'line', 0);
    if Failure.Test <> '' then
      Result.Failures := Result.Failures + [Failure];
  end;
end;

function TestsJson(const ATests: TAtlasProjectTests; AOriginal: TJSONObject): TJSONObject;
var
  Items: TJSONArray;
  Item: TJSONObject;
  Index: Integer;
begin
  Result := TJSONObject.Create;
  AddTime(Result, 'at', ATests.At);
  Result.AddPair('project', ATests.Project);
  if ATests.Configuration <> '' then
    Result.AddPair('configuration', ATests.Configuration);
  if ATests.Platform <> '' then
    Result.AddPair('platform', ATests.Platform);
  Result.AddPair('passed', TJSONNumber.Create(ATests.Passed));
  Result.AddPair('failed', TJSONNumber.Create(ATests.Failed));
  Result.AddPair('errors', TJSONNumber.Create(ATests.Errors));
  Result.AddPair('skipped', TJSONNumber.Create(ATests.Skipped));
  Result.AddPair('durationMs', TJSONNumber.Create(ATests.DurationMs));
  Items := TJSONArray.Create;
  Result.AddPair('failures', Items);
  for Index := 0 to High(ATests.Failures) do
  begin
    if Index >= TAtlasProjectTests.MaxFailures then
      Break;
    Item := TJSONObject.Create;
    Items.AddElement(Item);
    Item.AddPair('test', ATests.Failures[Index].Test);
    if ATests.Failures[Index].Message <> '' then
      Item.AddPair('message', ATests.Failures[Index].Message);
    if ATests.Failures[Index].FileName <> '' then
      Item.AddPair('file', ATests.Failures[Index].FileName);
    if ATests.Failures[Index].Line > 0 then
      Item.AddPair('line', TJSONNumber.Create(ATests.Failures[Index].Line));
  end;
  KeepUnknown(Result, AOriginal, TestsKeys);
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
  Build: TAtlasProjectReleaseBuild;
begin
  Result := '';
  for Build in Builds do
    if SameText(Build.Configuration, AConfiguration) and SameText(Build.Platform, APlatform) then
      Exit(Build.Version);
end;

procedure TAtlasProjectRelease.Remember(const AConfiguration, APlatform, AVersion: string; AAtUtc: TDateTime);
var
  Entry: TAtlasProjectReleaseBuild;
  Kept: TArray<TAtlasProjectReleaseBuild>;
  Build: TAtlasProjectReleaseBuild;
begin
  Entry.Configuration := AConfiguration;
  Entry.Platform := APlatform;
  Entry.Version := AVersion;
  Entry.At := AAtUtc;
  Kept := nil;
  Kept := Kept + [Entry];
  for Build in Builds do
    if (Length(Kept) < MaxBuilds) and
      not (SameText(Build.Configuration, AConfiguration) and SameText(Build.Platform, APlatform)) then
      Kept := Kept + [Build];
  Builds := Kept;
  Known := True;
end;

function ReleaseOf(ASection: TJSONObject): TAtlasProjectRelease;
var
  Items: TJSONValue;
  Item: TJSONValue;
  Build: TAtlasProjectReleaseBuild;
begin
  Result := TAtlasProjectRelease.Empty;
  if ASection = nil then
    Exit;
  Result.Known := True;
  Result.CheckedAt := TAtlasProjectSummaries.TimeOf(TextOf(ASection, 'checkedAt'));
  Result.Configuration := TextOf(ASection, 'configuration');
  Result.Platform := TextOf(ASection, 'platform');
  Result.Findings := NumberOf(ASection, 'findings', 0);
  Result.Blocked := FlagOf(ASection, 'blocked');
  Items := ASection.GetValue('rules');
  if Items is TJSONArray then
    for Item in TJSONArray(Items) do
      if (Item is TJSONString) and (TJSONString(Item).Value <> '') then
        Result.Rules := Result.Rules + [TJSONString(Item).Value];
  Items := ASection.GetValue('builds');
  if not (Items is TJSONArray) then
    Exit;
  for Item in TJSONArray(Items) do
  begin
    if not (Item is TJSONObject) or (Length(Result.Builds) >= TAtlasProjectRelease.MaxBuilds) then
      Continue;
    Build := Default(TAtlasProjectReleaseBuild);
    Build.Configuration := TextOf(TJSONObject(Item), 'configuration');
    Build.Platform := TextOf(TJSONObject(Item), 'platform');
    Build.Version := TextOf(TJSONObject(Item), 'version');
    Build.At := TAtlasProjectSummaries.TimeOf(TextOf(TJSONObject(Item), 'at'));
    if Build.Configuration <> '' then
      Result.Builds := Result.Builds + [Build];
  end;
end;

/// <summary>Eintrag in "builds" zu AConfiguration/APlatform aus dem gelesenen Text (für unbekannte Felder).</summary>
function OriginalReleaseBuild(AOriginal: TJSONObject; const AConfiguration, APlatform: string): TJSONObject;
var
  Items: TJSONValue;
  Item: TJSONValue;
begin
  Result := nil;
  if AOriginal = nil then
    Exit;
  Items := AOriginal.GetValue('builds');
  if not (Items is TJSONArray) then
    Exit;
  for Item in TJSONArray(Items) do
    if (Item is TJSONObject) and SameText(TextOf(TJSONObject(Item), 'configuration'), AConfiguration) and
      SameText(TextOf(TJSONObject(Item), 'platform'), APlatform) then
      Exit(TJSONObject(Item));
end;

function ReleaseJson(const ARelease: TAtlasProjectRelease; AOriginal: TJSONObject): TJSONObject;
var
  Items: TJSONArray;
  Item: TJSONObject;
  Rule: string;
  Build: TAtlasProjectReleaseBuild;
begin
  Result := TJSONObject.Create;
  if ARelease.CheckedAt > 0 then
  begin
    AddTime(Result, 'checkedAt', ARelease.CheckedAt);
    Result.AddPair('configuration', ARelease.Configuration);
    Result.AddPair('platform', ARelease.Platform);
    Result.AddPair('findings', TJSONNumber.Create(ARelease.Findings));
    Result.AddPair('blocked', TJSONBool.Create(ARelease.Blocked));
    Items := TJSONArray.Create;
    Result.AddPair('rules', Items);
    for Rule in ARelease.Rules do
      Items.Add(Rule);
  end;
  Items := TJSONArray.Create;
  Result.AddPair('builds', Items);
  for Build in ARelease.Builds do
  begin
    Item := TJSONObject.Create;
    Items.AddElement(Item);
    Item.AddPair('configuration', Build.Configuration);
    Item.AddPair('platform', Build.Platform);
    Item.AddPair('version', Build.Version);
    AddTime(Item, 'at', Build.At);
    KeepUnknown(Item, OriginalReleaseBuild(AOriginal, Build.Configuration, Build.Platform), ReleaseBuildKeys);
  end;
  KeepUnknown(Result, AOriginal, ReleaseKeys);
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

function CiOf(ASection: TJSONObject): TAtlasProjectCi;
var
  Items: TJSONValue;
  Item: TJSONValue;
  Failure: TAtlasCiFailure;
begin
  Result := TAtlasProjectCi.Empty;
  if ASection = nil then
    Exit;
  Result.Known := True;
  Result.Provider := TextOf(ASection, 'provider');
  Result.Server := TextOf(ASection, 'server');
  Result.Job := TextOf(ASection, 'job');
  Result.Branch := TextOf(ASection, 'branch');
  Result.Attempt := TAtlasProjectSummaries.TimeOf(TextOf(ASection, 'attempt'));
  Result.Error := TAtlasCiBuild.ErrorOf(TextOf(ASection, 'error'));
  Result.At := TAtlasProjectSummaries.TimeOf(TextOf(ASection, 'at'));
  Result.Build.Number := NumberOf(ASection, 'number', 0);
  if Result.Build.Number < 0 then
    Result.Build.Number := 0;
  Result.Build.Outcome := TAtlasCiBuild.OutcomeOf(TextOf(ASection, 'result'));
  Result.Build.StartedUtc := TAtlasProjectSummaries.TimeOf(TextOf(ASection, 'started'));
  Result.Build.DurationMs := NumberOf(ASection, 'durationMs', 0);
  Items := ASection.GetValue('failures');
  Result.Build.TestsKnown := (ASection.GetValue('passed') is TJSONNumber) or (Items is TJSONArray);
  Result.Build.Passed := NumberOf(ASection, 'passed', 0);
  Result.Build.Failed := NumberOf(ASection, 'failed', 0);
  Result.Build.Skipped := NumberOf(ASection, 'skipped', 0);
  if not (Items is TJSONArray) then
    Exit;
  for Item in TJSONArray(Items) do
  begin
    if not (Item is TJSONObject) or (Length(Result.Build.Failures) >= TAtlasCiBuild.MaxFailures) then
      Continue;
    Failure.Test := TextOf(TJSONObject(Item), 'test');
    Failure.Message := TextOf(TJSONObject(Item), 'message');
    if Failure.Test <> '' then
      Result.Build.Failures := Result.Build.Failures + [Failure];
  end;
end;

/// <summary>Eintrag in "failures" zu ATest aus dem gelesenen Text (für unbekannte Felder).</summary>
function OriginalCiFailure(AOriginal: TJSONObject; const ATest: string): TJSONObject;
var
  Items: TJSONValue;
  Item: TJSONValue;
begin
  Result := nil;
  if AOriginal = nil then
    Exit;
  Items := AOriginal.GetValue('failures');
  if not (Items is TJSONArray) then
    Exit;
  for Item in TJSONArray(Items) do
    if (Item is TJSONObject) and (TextOf(TJSONObject(Item), 'test') = ATest) then
      Exit(TJSONObject(Item));
end;

function CiJson(const ACi: TAtlasProjectCi; AOriginal: TJSONObject): TJSONObject;
var
  Items: TJSONArray;
  Item: TJSONObject;
  Index: Integer;
begin
  Result := TJSONObject.Create;
  Result.AddPair('provider', ACi.Provider);
  Result.AddPair('server', ACi.Server);
  Result.AddPair('job', ACi.Job);
  if ACi.Branch <> '' then
    Result.AddPair('branch', ACi.Branch);
  AddTime(Result, 'attempt', ACi.Attempt);
  if ACi.Error <> TAtlasCiFetchError.None then
    Result.AddPair('error', TAtlasCiBuild.ErrorKey(ACi.Error));
  AddTime(Result, 'at', ACi.At);
  if ACi.Build.Number > 0 then
  begin
    Result.AddPair('number', TJSONNumber.Create(ACi.Build.Number));
    Result.AddPair('result', TAtlasCiBuild.OutcomeKey(ACi.Build.Outcome));
    AddTime(Result, 'started', ACi.Build.StartedUtc);
    if ACi.Build.DurationMs > 0 then
      Result.AddPair('durationMs', TJSONNumber.Create(ACi.Build.DurationMs));
    if ACi.Build.TestsKnown then
    begin
      Result.AddPair('passed', TJSONNumber.Create(ACi.Build.Passed));
      Result.AddPair('failed', TJSONNumber.Create(ACi.Build.Failed));
      Result.AddPair('skipped', TJSONNumber.Create(ACi.Build.Skipped));
      Items := TJSONArray.Create;
      Result.AddPair('failures', Items);
      for Index := 0 to High(ACi.Build.Failures) do
      begin
        if Index >= TAtlasCiBuild.MaxFailures then
          Break;
        Item := TJSONObject.Create;
        Items.AddElement(Item);
        Item.AddPair('test', ACi.Build.Failures[Index].Test);
        if ACi.Build.Failures[Index].Message <> '' then
          Item.AddPair('message', ACi.Build.Failures[Index].Message);
        KeepUnknown(Item, OriginalCiFailure(AOriginal, ACi.Build.Failures[Index].Test), CiFailureKeys);
      end;
    end;
  end;
  KeepUnknown(Result, AOriginal, CiKeys);
end;

{ TAtlasProjectSummaries }

class function TAtlasProjectSummaries.NormalizedPath(const AProject: string): string;
var
  Index: Integer;
begin
  Result := Trim(AProject);
  for Index := 1 to Length(Result) do
    if Result[Index] = '/' then
      Result[Index] := '\'
    else if CharInSet(Result[Index], ['a'..'z']) then
      Result[Index] := Chr(Ord(Result[Index]) - 32);
end;

class function TAtlasProjectSummaries.KeyOf(const AProject: string): string;
const
  Offset: UInt64 = $CBF29CE484222325;
  Prime: UInt64 = $00000100000001B3;
  Digits: string = '0123456789abcdef';
var
  Text: string;
  Hash: UInt64;
  Index, Shift: Integer;
  Unit_: Word;
begin
  Text := NormalizedPath(AProject);
  Hash := Offset;
  for Index := 1 to Length(Text) do
  begin
    Unit_ := Ord(Text[Index]);
    Hash := (Hash xor (Unit_ and $FF)) * Prime;
    Hash := (Hash xor (Unit_ shr 8)) * Prime;
  end;
  Result := '';
  Shift := 60;
  while Shift >= 0 do
  begin
    Result := Result + Digits[((Hash shr Shift) and $F) + 1];
    Dec(Shift, 4);
  end;
end;

class function TAtlasProjectSummaries.FileFor(const AFolder, AProject: string): string;
begin
  Result := IncludeTrailingPathDelimiter(AFolder) + KeyOf(AProject) + '.json';
end;

class function TAtlasProjectSummaries.TimeText(AUtc: TDateTime): string;
var
  Year, Month, Day, Hour, Minute, Second, MSec: Word;
begin
  Result := '';
  if AUtc <= 0 then
    Exit;
  DecodeDate(AUtc, Year, Month, Day);
  DecodeTime(AUtc, Hour, Minute, Second, MSec);
  Result := System.SysUtils.Format('%.4d-%.2d-%.2dT%.2d:%.2d:%.2dZ', [Year, Month, Day, Hour, Minute, Second]);
end;

class function TAtlasProjectSummaries.TimeOf(const AText: string): TDateTime;
var
  Text: string;
  Year, Month, Day, Hour, Minute, Second: Integer;
  DatePart, TimePart: TDateTime;
begin
  Result := 0;
  Text := Trim(AText);
  // yyyy-mm-ddThh:nn:ss, danach höchstens Bruchteile und "Z".
  if (Length(Text) < 19) or (Text[5] <> '-') or (Text[8] <> '-') or not CharInSet(Text[11], ['T', 't', ' ']) or
    (Text[14] <> ':') or (Text[17] <> ':') then
    Exit;
  Year := StrToIntDef(Copy(Text, 1, 4), -1);
  Month := StrToIntDef(Copy(Text, 6, 2), -1);
  Day := StrToIntDef(Copy(Text, 9, 2), -1);
  Hour := StrToIntDef(Copy(Text, 12, 2), -1);
  Minute := StrToIntDef(Copy(Text, 15, 2), -1);
  Second := StrToIntDef(Copy(Text, 18, 2), -1);
  if (Year < 1) or (Month < 1) or (Day < 1) or (Hour < 0) or (Minute < 0) or (Second < 0) then
    Exit;
  if not TryEncodeDate(Year, Month, Day, DatePart) or not TryEncodeTime(Hour, Minute, Second, 0, TimePart) then
    Exit;
  Result := DatePart + TimePart;
end;

class function TAtlasProjectSummaries.FormatOf(const AJson: string): Integer;
var
  Value: TJSONValue;
begin
  Result := 0;
  try
    Value := TJSONObject.ParseJSONValue(AJson);
  except
    on Exception do
      Value := nil;
  end;
  try
    if Value is TJSONObject then
      Result := NumberOf(TJSONObject(Value), 'format', 0);
  finally
    Value.Free;
  end;
end;

class function TAtlasProjectSummaries.Parse(const AJson: string; out ASummary: TAtlasProjectSummary): Boolean;
var
  Value: TJSONValue;
  Root, Section: TJSONObject;
begin
  ASummary := TAtlasProjectSummary.Create('');
  Result := False;
  try
    Value := TJSONObject.ParseJSONValue(AJson);
  except
    on Exception do
      Value := nil;
  end;
  try
    if not (Value is TJSONObject) then
      Exit;
    Root := TJSONObject(Value);
    // Ohne "format" gilt 1; ein höheres Format kennt diese Fassung nicht.
    if NumberOf(Root, 'format', 1) > Format then
      Exit;
    ASummary.Raw := AJson;
    ASummary.Project := TextOf(Root, 'project');
    ASummary.LastOpened := TimeOf(TextOf(Root, 'lastOpened'));
    ASummary.LastClosed := TimeOf(TextOf(Root, 'lastClosed'));
    ASummary.Hidden := FlagOf(Root, 'hidden');
    Section := ObjectOf(Root, 'vcs');
    if Section <> nil then
    begin
      ASummary.Vcs.Known := True;
      ASummary.Vcs.At := TimeOf(TextOf(Section, 'at'));
      ASummary.Vcs.Kind := LowerCase(TextOf(Section, 'kind'));
      ASummary.Vcs.Branch := TextOf(Section, 'branch');
      ASummary.Vcs.Revision := TextOf(Section, 'revision');
      ASummary.Vcs.Changed := NumberOf(Section, 'changed', -1);
      ASummary.Vcs.Ahead := NumberOf(Section, 'ahead', -1);
      ASummary.Vcs.Behind := NumberOf(Section, 'behind', -1);
    end;
    Section := ObjectOf(Root, 'build');
    if Section <> nil then
    begin
      ASummary.Build.Known := True;
      ASummary.Build.At := TimeOf(TextOf(Section, 'at'));
      ASummary.Build.Kind := TextOf(Section, 'kind');
      ASummary.Build.Configuration := TextOf(Section, 'configuration');
      ASummary.Build.Platform := TextOf(Section, 'platform');
      ASummary.Build.Succeeded := FlagOf(Section, 'succeeded');
      ASummary.Build.Errors := NumberOf(Section, 'errors', 0);
      ASummary.Build.Warnings := NumberOf(Section, 'warnings', 0);
      ASummary.Build.Hints := NumberOf(Section, 'hints', 0);
      ASummary.Build.DurationMs := NumberOf(Section, 'durationMs', 0);
      ASummary.Build.First := LocationOf(ObjectOf(Section, 'first'));
    end;
    Section := ObjectOf(Root, 'check');
    if Section <> nil then
    begin
      ASummary.Check.Known := True;
      ASummary.Check.At := TimeOf(TextOf(Section, 'at'));
      ASummary.Check.Errors := NumberOf(Section, 'errors', 0);
      ASummary.Check.First := LocationOf(ObjectOf(Section, 'first'));
    end;
    Section := ObjectOf(Root, 'rules');
    if Section <> nil then
    begin
      ASummary.Rules.Known := True;
      ASummary.Rules.At := TimeOf(TextOf(Section, 'at'));
      ASummary.Rules.NewHits := NumberOf(Section, 'newHits', 0);
    end;
    ASummary.Metrics := MetricsOf(ObjectOf(Root, 'metrics'));
    ASummary.Todos := TodosOf(ObjectOf(Root, 'todos'));
    Section := ObjectOf(Root, 'baseline');
    if Section <> nil then
    begin
      ASummary.Baseline.Known := True;
      ASummary.Baseline.At := TimeOf(TextOf(Section, 'at'));
      ASummary.Baseline.Exists := FlagOf(Section, 'exists');
      ASummary.Baseline.Valid := FlagOf(Section, 'valid');
      ASummary.Baseline.Entries := NumberOf(Section, 'entries', 0);
      ASummary.Baseline.Hits := NumberOf(Section, 'hits', 0);
      ASummary.Baseline.Orphaned := NumberOf(Section, 'orphaned', 0);
      ASummary.Baseline.Updated := TimeOf(TextOf(Section, 'updated'));
      ASummary.Baseline.Added := NumberOf(Section, 'added', 0);
      ASummary.Baseline.Removed := NumberOf(Section, 'removed', 0);
    end;
    ASummary.Trends := TrendsOf(ObjectOf(Root, 'trends'));
    ASummary.Setup := SetupOf(ObjectOf(Root, 'setup'));
    ASummary.Tests := TestsOf(ObjectOf(Root, 'tests'));
    ASummary.Release := ReleaseOf(ObjectOf(Root, 'release'));
    ASummary.Ci := CiOf(ObjectOf(Root, 'ci'));
    Result := True;
  finally
    Value.Free;
  end;
end;

class function TAtlasProjectSummaries.ToJson(const ASummary: TAtlasProjectSummary): string;
var
  Value: TJSONValue;
  Original, Root, Section, Keywords: TJSONObject;
  Index: Integer;
begin
  Value := nil;
  if ASummary.Raw <> '' then
    try
      Value := TJSONObject.ParseJSONValue(ASummary.Raw);
    except
      on Exception do
        Value := nil;
    end;
  Root := TJSONObject.Create;
  try
    Original := nil;
    if Value is TJSONObject then
      Original := TJSONObject(Value);
    Root.AddPair('format', TJSONNumber.Create(Format));
    Root.AddPair('project', ASummary.Project);
    AddTime(Root, 'lastOpened', ASummary.LastOpened);
    AddTime(Root, 'lastClosed', ASummary.LastClosed);
    if ASummary.Hidden then
      Root.AddPair('hidden', TJSONBool.Create(True));
    if ASummary.Vcs.Known then
    begin
      Section := TJSONObject.Create;
      Root.AddPair('vcs', Section);
      AddTime(Section, 'at', ASummary.Vcs.At);
      Section.AddPair('kind', ASummary.Vcs.Kind);
      if ASummary.Vcs.Branch <> '' then
        Section.AddPair('branch', ASummary.Vcs.Branch);
      if ASummary.Vcs.Revision <> '' then
        Section.AddPair('revision', ASummary.Vcs.Revision);
      Section.AddPair('changed', TJSONNumber.Create(ASummary.Vcs.Changed));
      Section.AddPair('ahead', TJSONNumber.Create(ASummary.Vcs.Ahead));
      Section.AddPair('behind', TJSONNumber.Create(ASummary.Vcs.Behind));
      KeepUnknown(Section, ObjectOf(Original, 'vcs'), VcsKeys);
    end;
    if ASummary.Build.Known then
    begin
      Section := TJSONObject.Create;
      Root.AddPair('build', Section);
      AddTime(Section, 'at', ASummary.Build.At);
      Section.AddPair('kind', ASummary.Build.Kind);
      Section.AddPair('configuration', ASummary.Build.Configuration);
      Section.AddPair('platform', ASummary.Build.Platform);
      Section.AddPair('succeeded', TJSONBool.Create(ASummary.Build.Succeeded));
      Section.AddPair('errors', TJSONNumber.Create(ASummary.Build.Errors));
      Section.AddPair('warnings', TJSONNumber.Create(ASummary.Build.Warnings));
      Section.AddPair('hints', TJSONNumber.Create(ASummary.Build.Hints));
      if ASummary.Build.DurationMs > 0 then
        Section.AddPair('durationMs', TJSONNumber.Create(ASummary.Build.DurationMs));
      if not ASummary.Build.First.IsEmpty then
        Section.AddPair('first', LocationJson(ASummary.Build.First));
      KeepUnknown(Section, ObjectOf(Original, 'build'), BuildKeys);
    end;
    if ASummary.Check.Known then
    begin
      Section := TJSONObject.Create;
      Root.AddPair('check', Section);
      AddTime(Section, 'at', ASummary.Check.At);
      Section.AddPair('errors', TJSONNumber.Create(ASummary.Check.Errors));
      if not ASummary.Check.First.IsEmpty then
        Section.AddPair('first', LocationJson(ASummary.Check.First));
      KeepUnknown(Section, ObjectOf(Original, 'check'), CheckKeys);
    end;
    if ASummary.Rules.Known then
    begin
      Section := TJSONObject.Create;
      Root.AddPair('rules', Section);
      AddTime(Section, 'at', ASummary.Rules.At);
      Section.AddPair('newHits', TJSONNumber.Create(ASummary.Rules.NewHits));
      KeepUnknown(Section, ObjectOf(Original, 'rules'), RulesKeys);
    end;
    if ASummary.Metrics.Known then
    begin
      Section := TJSONObject.Create;
      Root.AddPair('metrics', Section);
      AddTime(Section, 'at', ASummary.Metrics.At);
      Section.AddPair('files', TJSONNumber.Create(ASummary.Metrics.Files));
      Section.AddPair('methods', TJSONNumber.Create(ASummary.Metrics.Methods));
      Section.AddPair('overLimits', TJSONNumber.Create(ASummary.Metrics.OverLimits));
      Section.AddPair('average', MetricNumbersJson(ASummary.Metrics.AverageTenths, True));
      Section.AddPair('maximum', MetricNumbersJson(ASummary.Metrics.Maximum, False));
      Section.AddPair('exceeded', MetricNumbersJson(ASummary.Metrics.Exceeded, False));
      KeepUnknown(Section, ObjectOf(Original, 'metrics'), MetricsKeys);
    end;
    if ASummary.Todos.Known then
    begin
      Section := TJSONObject.Create;
      Root.AddPair('todos', Section);
      AddTime(Section, 'at', ASummary.Todos.At);
      Section.AddPair('files', TJSONNumber.Create(ASummary.Todos.Files));
      Section.AddPair('open', TJSONNumber.Create(ASummary.Todos.Open));
      Section.AddPair('done', TJSONNumber.Create(ASummary.Todos.Done));
      Keywords := TJSONObject.Create;
      Section.AddPair('keywords', Keywords);
      for Index := 0 to High(ASummary.Todos.Keywords) do
        Keywords.AddPair(ASummary.Todos.Keywords[Index], TJSONNumber.Create(ASummary.Todos.KeywordCounts[Index]));
      KeepUnknown(Section, ObjectOf(Original, 'todos'), TodosKeys);
    end;
    if ASummary.Baseline.Known then
    begin
      Section := TJSONObject.Create;
      Root.AddPair('baseline', Section);
      AddTime(Section, 'at', ASummary.Baseline.At);
      Section.AddPair('exists', TJSONBool.Create(ASummary.Baseline.Exists));
      Section.AddPair('valid', TJSONBool.Create(ASummary.Baseline.Valid));
      Section.AddPair('entries', TJSONNumber.Create(ASummary.Baseline.Entries));
      Section.AddPair('hits', TJSONNumber.Create(ASummary.Baseline.Hits));
      Section.AddPair('orphaned', TJSONNumber.Create(ASummary.Baseline.Orphaned));
      if ASummary.Baseline.Updated <> 0 then
      begin
        AddTime(Section, 'updated', ASummary.Baseline.Updated);
        Section.AddPair('added', TJSONNumber.Create(ASummary.Baseline.Added));
        Section.AddPair('removed', TJSONNumber.Create(ASummary.Baseline.Removed));
      end;
      KeepUnknown(Section, ObjectOf(Original, 'baseline'), BaselineKeys);
    end;
    if ASummary.Trends.Known then
      Root.AddPair('trends', TrendsJson(ASummary.Trends, ObjectOf(Original, 'trends')));
    if ASummary.Setup.Known then
      Root.AddPair('setup', SetupJson(ASummary.Setup, ObjectOf(Original, 'setup')));
    if ASummary.Tests.Known then
      Root.AddPair('tests', TestsJson(ASummary.Tests, ObjectOf(Original, 'tests')));
    if ASummary.Release.Known then
      Root.AddPair('release', ReleaseJson(ASummary.Release, ObjectOf(Original, 'release')));
    if ASummary.Ci.Known then
      Root.AddPair('ci', CiJson(ASummary.Ci, ObjectOf(Original, 'ci')));
    KeepUnknown(Root, Original, TopKeys);
    Result := Root.ToJSON;
  finally
    Root.Free;
    Value.Free;
  end;
end;

function ReadText(const AFileName: string): string;
var
  Bytes: TBytes;
begin
  Bytes := TFile.ReadAllBytes(AFileName);
  // Mit oder ohne BOM.
  if (Length(Bytes) >= 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF) then
    Result := TEncoding.UTF8.GetString(Bytes, 3, Length(Bytes) - 3)
  else
    Result := TEncoding.UTF8.GetString(Bytes);
end;

class function TAtlasProjectSummaries.Load(const AFolder, AProject: string;
  out ASummary: TAtlasProjectSummary): Boolean;
var
  FileName, Text: string;
begin
  ASummary := TAtlasProjectSummary.Create(AProject);
  Result := False;
  if (AFolder = '') or (Trim(AProject) = '') then
    Exit;
  FileName := FileFor(AFolder, AProject);
  if not FileExists(FileName) then
    Exit;
  try
    Text := ReadText(FileName);
  except
    // Gesperrt oder unlesbar: wie ohne Datei.
    on Exception do
      Exit;
  end;
  Result := Parse(Text, ASummary);
  if not Result then
    ASummary := TAtlasProjectSummary.Create(AProject)
  else if ASummary.Project = '' then
    ASummary.Project := AProject;
end;

class function TAtlasProjectSummaries.Save(const AFolder: string; const ASummary: TAtlasProjectSummary): Boolean;
var
  FileName, Temp: string;
begin
  Result := False;
  if (AFolder = '') or (Trim(ASummary.Project) = '') then
    Exit;
  FileName := FileFor(AFolder, ASummary.Project);
  try
    // Eine neuere Fassung hat die Datei geschrieben: nicht überschreiben.
    if FileExists(FileName) and (FormatOf(ReadText(FileName)) > Format) then
      Exit;
    ForceDirectories(AFolder);
    Temp := FileName + '.tmp';
    // Ohne BOM: UTF-8 wie JSON üblich.
    TFile.WriteAllBytes(Temp, TEncoding.UTF8.GetBytes(ToJson(ASummary)));
    if FileExists(FileName) then
      System.SysUtils.DeleteFile(FileName);
    Result := RenameFile(Temp, FileName);
  except
    on Exception do
      Result := False;
  end;
end;

class function TAtlasProjectSummaries.Update(const AFolder, AProject: string;
  const AChange: TAtlasProjectSummaryChange): Boolean;
var
  Summary: TAtlasProjectSummary;
begin
  Result := False;
  if (AFolder = '') or (Trim(AProject) = '') then
    Exit;
  // Ohne lesbare Datei beginnt eine neue; eine Datei mit höherem Format bleibt unangetastet (Save prüft das).
  Load(AFolder, AProject, Summary);
  if Assigned(AChange) then
    AChange(Summary);
  Result := Save(AFolder, Summary);
end;

end.
