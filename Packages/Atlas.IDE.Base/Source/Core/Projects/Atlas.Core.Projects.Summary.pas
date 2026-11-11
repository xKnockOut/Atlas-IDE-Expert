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
// ersten Funde (höchstens TAtlasProjectSetup.cMaxFindings je Liste; Datei
// relativ zum Projektordner, Zeile ab 1, "count" Stellen im Projekt).
// "skippedMacros" sind unbekannte Makros übersprungener Suchpfade; Funde mit
// "uncertain" sind deshalb nicht sicher ("uncertainUnits" und
// "uncertainDefines" zählen sie, auch über die gespeicherten hinaus). Bei
// einer Projektgruppe steht die Prüfung je Projekt in dessen Zusammenfassung.
// "tests" ist der letzte DUnitX-Lauf aus der IDE (#69; Grundlage der Karte
// Tests #763): Testprojekt, Konfiguration, Plattform, Zahlen, Dauer und die
// fehlgeschlagenen Tests (höchstens TAtlasProjectTests.cMaxFailures; "failed"
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
// ohne Bericht; höchstens TAtlasCiBuild.cMaxFailures Fehlschläge mit vollem
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
  Atlas.Core.Projects.Summary.Sections;

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

  TAtlasSetupFinding = Atlas.Core.Projects.Summary.Sections.TAtlasSetupFinding;
  TAtlasProjectSetup = Atlas.Core.Projects.Summary.Sections.TAtlasProjectSetup;
  TAtlasProjectTestFailure = Atlas.Core.Projects.Summary.Sections.TAtlasProjectTestFailure;
  TAtlasProjectTests = Atlas.Core.Projects.Summary.Sections.TAtlasProjectTests;
  TAtlasProjectRelease = Atlas.Core.Projects.Summary.Sections.TAtlasProjectRelease;
  TAtlasProjectCi = Atlas.Core.Projects.Summary.Sections.TAtlasProjectCi;

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
    cFormat = 1;
    /// <summary>Kennzahlen im Abschnitt "metrics" (wie atlas.server.metrics, #66).</summary>
    cMetricKeys: array[0..4] of string = ('length', 'nesting', 'cyclomatic', 'cognitive', 'parameters');
    /// <summary>Namen der Reihen im Abschnitt "trends" und in welcomePage.trends.series (#758).</summary>
    cTrendKeys: array[TAtlasTrendSeries] of string = ('warnings', 'ruleHits', 'todos', 'duration', 'methodLength');
    /// <summary>Reihen mit einer Nachkommastelle in der Datei; die übrigen sind ganze Zahlen.</summary>
    cTrendDecimals: array[TAtlasTrendSeries] of Boolean = (False, False, False, True, True);
    /// <summary>Unterordner von %LOCALAPPDATA%\Atlas.</summary>
    cFolderName = 'projects';
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
    /// <summary>Ersetzt die Datei atomar (TAtlasDataFile.Write); False bei Fehler (einmal protokolliert), wenn
    /// die vorhandene Datei ein höheres Format hat oder gerade nicht lesbar ist.</summary>
    class function Save(const AFolder: string; const ASummary: TAtlasProjectSummary): Boolean; static;
    /// <summary>Lesen, AChange anwenden, schreiben. Eine unbrauchbare Datei liegt danach als .defekt daneben
    ///; eine gesperrte bleibt unverändert (False).</summary>
    class function Update(const AFolder, AProject: string; const AChange: TAtlasProjectSummaryChange): Boolean; static;
    /// <summary>Ordner "projects" unter %LOCALAPPDATA%\Atlas (Willkommensseite und Tests lesen dieselben Dateien).
    /// </summary>
    class function DefaultFolder: string; static;
    /// <summary>Fehlgeschlagene Tests des letzten gespeicherten Laufs von ATestProject (#69, „Fehlgeschlagene
    /// erneut ausführen“ nach einem Neustart); leer ohne Datei oder wenn der Lauf zu einem anderen Testprojekt
    /// gehört.</summary>
    class function FailedTestsOf(const AFolder, ATestProject: string): TArray<string>; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Generics.Collections,
  System.Classes,
  System.IOUtils,
  System.JSON,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Projects.Summary.Json,
  Atlas.Text.Json;

const
  // Bekannte Felder; alles andere übernimmt ToJson unverändert aus Raw.
  cTopKeys: array[0..16] of string = ('format', 'project', 'lastOpened', 'lastClosed', 'hidden', 'vcs', 'build',
    'check', 'rules', 'metrics', 'todos', 'baseline', 'trends', 'setup', 'tests', 'release', 'ci');
  cVcsKeys: array[0..6] of string = ('at', 'kind', 'branch', 'revision', 'changed', 'ahead', 'behind');
  cBuildKeys: array[0..9] of string = ('at', 'kind', 'configuration', 'platform', 'succeeded', 'errors', 'warnings',
    'hints', 'durationMs', 'first');
  cCheckKeys: array[0..2] of string = ('at', 'errors', 'first');
  cRulesKeys: array[0..1] of string = ('at', 'newHits');
  cMetricsKeys: array[0..6] of string = ('at', 'files', 'methods', 'overLimits', 'average', 'maximum', 'exceeded');
  cTodosKeys: array[0..4] of string = ('at', 'files', 'open', 'done', 'keywords');
  cBaselineKeys: array[0..8] of string = ('at', 'exists', 'valid', 'entries', 'hits', 'orphaned', 'updated', 'added',
    'removed');
  cTrendsKeys: array[0..1] of string = ('builds', 'points');
  cTrendPointKeys: array[0..8] of string = ('at', 'build', 'branch', 'commit', 'warnings', 'ruleHits', 'todos',
    'duration', 'methodLength');

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

{ JSON-Helfer }

function LocationOf(AObject: TJSONObject): TAtlasProjectLocation;
begin
  Result := Default(TAtlasProjectLocation);
  if AObject = nil then
  begin
    Exit;
  end;
  Result.FileName := TJsonRead.Text(AObject, 'file');
  Result.Line := TJsonRead.IntOr(AObject, 'line', 0);
  Result.Column := TJsonRead.IntOr(AObject, 'column', 0);
  Result.Code := TJsonRead.Text(AObject, 'code');
  Result.Text := TJsonRead.Text(AObject, 'text');
end;

function LocationJson(const ALocation: TAtlasProjectLocation): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('file', ALocation.FileName);
  Result.AddPair('line', TJSONNumber.Create(ALocation.Line));
  Result.AddPair('column', TJSONNumber.Create(ALocation.Column));
  if ALocation.Code <> '' then
  begin
    Result.AddPair('code', ALocation.Code);
  end;
  if ALocation.Text <> '' then
  begin
    Result.AddPair('text', ALocation.Text);
  end;
end;

/// <summary>Zahlen je Kennzahl aus AObject; ATenths: Dezimalzahlen als Zehntel. Fehlende bleiben 0.</summary>
function MetricNumbersOf(AObject: TJSONObject; ATenths: Boolean): TAtlasMetricNumbers;
var
  mIndex: Integer;
  mValue: TJSONValue;
begin
  for mIndex := Low(Result) to High(Result) do
  begin
    Result[mIndex] := 0;
    if AObject = nil then
    begin
      Continue;
    end;
    mValue := AObject.GetValue(TAtlasProjectSummaries.cMetricKeys[mIndex]);
    if not (mValue is TJSONNumber) then
    begin
      Continue;
    end;
    if ATenths then
    begin
      Result[mIndex] := Round(TJSONNumber(mValue).AsDouble * 10);
    end
    else
    begin
      Result[mIndex] := TJSONNumber(mValue).AsInt;
    end;
  end;
end;

/// <summary>Objekt {"length": …, …}; ATenths: Werte als Dezimalzahl mit einer Nachkommastelle.</summary>
function MetricNumbersJson(const ANumbers: TAtlasMetricNumbers; ATenths: Boolean): TJSONObject;
var
  mIndex: Integer;
begin
  Result := TJSONObject.Create;
  for mIndex := Low(ANumbers) to High(ANumbers) do
  begin
    if ATenths then
    begin
      Result.AddPair(TAtlasProjectSummaries.cMetricKeys[mIndex], TJSONNumber.Create(ANumbers[mIndex] / 10));
    end
    else
    begin
      Result.AddPair(TAtlasProjectSummaries.cMetricKeys[mIndex], TJSONNumber.Create(ANumbers[mIndex]));
    end;
  end;
end;

/// <summary>Kennzahlen aus einem Objekt mit files, methods, overLimits, average, maximum, exceeded.</summary>
function MetricsOf(ASection: TJSONObject): TAtlasProjectMetrics;
begin
  Result := TAtlasProjectMetrics.Empty;
  if ASection = nil then
  begin
    Exit;
  end;
  Result.Known := True;
  Result.At := TAtlasProjectSummaries.TimeOf(TJsonRead.Text(ASection, 'at'));
  Result.Files := TJsonRead.IntOr(ASection, 'files', 0);
  Result.Methods := TJsonRead.IntOr(ASection, 'methods', 0);
  Result.OverLimits := TJsonRead.IntOr(ASection, 'overLimits', 0);
  Result.AverageTenths := MetricNumbersOf(TJsonRead.Obj(ASection, 'average'), True);
  Result.Maximum := MetricNumbersOf(TJsonRead.Obj(ASection, 'maximum'), False);
  Result.Exceeded := MetricNumbersOf(TJsonRead.Obj(ASection, 'exceeded'), False);
end;

{ TAtlasProjectMetrics }

class function TAtlasProjectMetrics.Empty: TAtlasProjectMetrics;
begin
  Result := Default(TAtlasProjectMetrics);
end;

class function TAtlasProjectMetrics.FromServer(const AJson: string; AAtUtc: TDateTime;
  out AMetrics: TAtlasProjectMetrics): Boolean;
var
  mValue: TJSONValue;
  mSection: TJSONObject;
begin
  AMetrics := TAtlasProjectMetrics.Empty;
  Result := False;
  try
    mValue := TJSONObject.ParseJSONValue(AJson);
  except
    on Exception do
      mValue := nil;
  end;
  try
    if not (mValue is TJSONObject) then
    begin
      Exit;
    end;
    mSection := TJsonRead.Obj(TJSONObject(mValue), 'summary');
    if mSection = nil then
    begin
      mSection := TJsonRead.Obj(TJSONObject(mValue), 'metrics');
    end;
    if mSection = nil then
    begin
      mSection := TJSONObject(mValue);
    end;
    if not (mSection.GetValue('methods') is TJSONNumber) then
    begin
      Exit;
    end;
    AMetrics := MetricsOf(mSection);
    AMetrics.At := AAtUtc;
    Result := True;
  finally
    mValue.Free;
  end;
end;

/// <summary>Zahlen aus einem Objekt mit files, open, done, keywords.</summary>
function TodosOf(ASection: TJSONObject): TAtlasProjectTodos;
var
  mKeywords: TJSONObject;
  mIndex: Integer;
  mPair: TJSONPair;
begin
  Result := TAtlasProjectTodos.Empty;
  if ASection = nil then
  begin
    Exit;
  end;
  Result.Known := True;
  Result.At := TAtlasProjectSummaries.TimeOf(TJsonRead.Text(ASection, 'at'));
  Result.Files := TJsonRead.IntOr(ASection, 'files', 0);
  Result.Open := TJsonRead.IntOr(ASection, 'open', 0);
  Result.Done := TJsonRead.IntOr(ASection, 'done', 0);
  mKeywords := TJsonRead.Obj(ASection, 'keywords');
  if mKeywords = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mKeywords.Count - 1 do
  begin
    mPair := mKeywords.Pairs[mIndex];
    if mPair.JsonValue is TJSONNumber then
    begin
      Result.Keywords := Result.Keywords + [mPair.JsonString.Value];
      Result.KeywordCounts := Result.KeywordCounts + [TJSONNumber(mPair.JsonValue).AsInt];
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
  mIndex: Integer;
begin
  for mIndex := 0 to High(Keywords) do
  begin
    if SameText(Keywords[mIndex], AKeyword) then
    begin
      Exit(KeywordCounts[mIndex]);
    end;
  end;
  Result := 0;
end;

class function TAtlasProjectTodos.FromServer(const AJson: string; AAtUtc: TDateTime;
  out ATodos: TAtlasProjectTodos): Boolean;
var
  mValue: TJSONValue;
  mSection: TJSONObject;
begin
  ATodos := TAtlasProjectTodos.Empty;
  Result := False;
  try
    mValue := TJSONObject.ParseJSONValue(AJson);
  except
    on Exception do
      mValue := nil;
  end;
  try
    if not (mValue is TJSONObject) then
    begin
      Exit;
    end;
    mSection := TJsonRead.Obj(TJSONObject(mValue), 'summary');
    if mSection = nil then
    begin
      mSection := TJsonRead.Obj(TJSONObject(mValue), 'todos');
    end;
    if mSection = nil then
    begin
      mSection := TJSONObject(mValue);
    end;
    if not (mSection.GetValue('open') is TJSONNumber) then
    begin
      Exit;
    end;
    ATodos := TodosOf(mSection);
    ATodos.At := AAtUtc;
    Result := True;
  finally
    mValue.Free;
  end;
end;

/// <summary>Messpunkt aus AItem; Werte in Zehnteln, fehlende bleiben Lücken.</summary>
function TrendPointOf(AItem: TJSONObject): TAtlasTrendPoint;
var
  mSeries: TAtlasTrendSeries;
  mValue: TJSONValue;
begin
  Result := TAtlasTrendPoint.Create(SummaryTimeOf(TJsonRead.Text(AItem, 'at')), TJsonRead.IntOr(AItem, 'build', 0));
  Result.Branch := TJsonRead.Text(AItem, 'branch');
  Result.Commit := TJsonRead.Text(AItem, 'commit');
  for mSeries := Low(TAtlasTrendSeries) to High(TAtlasTrendSeries) do
  begin
    mValue := AItem.GetValue(TAtlasProjectSummaries.cTrendKeys[mSeries]);
    if mValue is TJSONNumber then
    begin
      Result.SetValue(mSeries, Round(TJSONNumber(mValue).AsDouble * 10));
    end;
  end;
end;

/// <summary>Abschnitt "trends"; leer ohne Abschnitt. Punkte ohne gültige Nummer bekommen eine nach der letzten.
/// </summary>
function TrendsOf(ASection: TJSONObject): TAtlasProjectTrends;
var
  mPoints: TJSONValue;
  mItem: TJSONValue;
  mIndex: Integer;
  mPoint: TAtlasTrendPoint;
  mHighest: Integer;
begin
  Result := TAtlasProjectTrends.Empty;
  if ASection = nil then
  begin
    Exit;
  end;
  Result.Known := True;
  Result.Builds := TJsonRead.IntOr(ASection, 'builds', 0);
  mHighest := 0;
  mPoints := ASection.GetValue('points');
  if mPoints is TJSONArray then
  begin
    for mIndex := 0 to TJSONArray(mPoints).Count - 1 do
    begin
      mItem := TJSONArray(mPoints).Items[mIndex];
      if not (mItem is TJSONObject) then
      begin
        Continue;
      end;
      mPoint := TrendPointOf(TJSONObject(mItem));
      // Nummern steigen streng: Doppelte oder Rückschritte rücken hinter den höchsten.
      if mPoint.Build <= mHighest then
      begin
        mPoint.Build := mHighest + 1;
      end;
      mHighest := mPoint.Build;
      Result.Points := Result.Points + [mPoint];
    end;
  end;
  // Ohne oder mit zu kleinem Zähler: mindestens die höchste Nummer.
  if Result.Builds < mHighest then
  begin
    Result.Builds := mHighest;
  end;
end;

/// <summary>Punkt mit der Nummer ABuild aus dem Abschnitt "trends" von AOriginal (darf nil sein); nil ohne.</summary>
function OriginalPoint(AOriginal: TJSONObject; ABuild: Integer): TJSONObject;
var
  mPoints: TJSONValue;
  mIndex: Integer;
  mItem: TJSONValue;
begin
  Result := nil;
  if AOriginal = nil then
  begin
    Exit;
  end;
  mPoints := AOriginal.GetValue('points');
  if not (mPoints is TJSONArray) then
  begin
    Exit;
  end;
  for mIndex := 0 to TJSONArray(mPoints).Count - 1 do
  begin
    mItem := TJSONArray(mPoints).Items[mIndex];
    if (mItem is TJSONObject) and (TJsonRead.IntOr(TJSONObject(mItem), 'build', 0) = ABuild) then
    begin
      Exit(TJSONObject(mItem));
    end;
  end;
end;

function TrendsJson(const ATrends: TAtlasProjectTrends; AOriginal: TJSONObject): TJSONObject;
var
  mPoints: TJSONArray;
  mItem: TJSONObject;
  mPoint: TAtlasTrendPoint;
  mSeries: TAtlasTrendSeries;
begin
  Result := TJSONObject.Create;
  Result.AddPair('builds', TJSONNumber.Create(ATrends.Builds));
  mPoints := TJSONArray.Create;
  Result.AddPair('points', mPoints);
  for mPoint in ATrends.Points do
  begin
    mItem := TJSONObject.Create;
    mPoints.AddElement(mItem);
    AddTime(mItem, 'at', mPoint.At);
    mItem.AddPair('build', TJSONNumber.Create(mPoint.Build));
    if mPoint.Branch <> '' then
    begin
      mItem.AddPair('branch', mPoint.Branch);
    end;
    if mPoint.Commit <> '' then
    begin
      mItem.AddPair('commit', mPoint.Commit);
    end;
    for mSeries := Low(TAtlasTrendSeries) to High(TAtlasTrendSeries) do
    begin
      // Lücke: kein Feld.
      if not mPoint.Has[mSeries] then
      begin
        Continue;
      end;
      if TAtlasProjectSummaries.cTrendDecimals[mSeries] then
      begin
        mItem.AddPair(TAtlasProjectSummaries.cTrendKeys[mSeries], TJSONNumber.Create(mPoint.Values[mSeries] / 10));
      end
      else
      begin
        mItem.AddPair(TAtlasProjectSummaries.cTrendKeys[mSeries], TJSONNumber.Create(mPoint.Values[mSeries] div 10));
      end;
    end;
    KeepUnknown(mItem, OriginalPoint(AOriginal, mPoint.Build), cTrendPointKeys);
  end;
  KeepUnknown(Result, AOriginal, cTrendsKeys);
end;

/// <summary>Abschnitt "vcs"; Empty ohne Abschnitt.</summary>
function VcsOf(ASection: TJSONObject): TAtlasProjectVcs;
begin
  Result := TAtlasProjectVcs.Empty;
  if ASection = nil then
  begin
    Exit;
  end;
  Result.Known := True;
  Result.At := TAtlasProjectSummaries.TimeOf(TJsonRead.Text(ASection, 'at'));
  Result.Kind := LowerCase(TJsonRead.Text(ASection, 'kind'));
  Result.Branch := TJsonRead.Text(ASection, 'branch');
  Result.Revision := TJsonRead.Text(ASection, 'revision');
  Result.Changed := TJsonRead.IntOr(ASection, 'changed', -1);
  Result.Ahead := TJsonRead.IntOr(ASection, 'ahead', -1);
  Result.Behind := TJsonRead.IntOr(ASection, 'behind', -1);
end;

/// <summary>Abschnitt "build"; Empty ohne Abschnitt.</summary>
function BuildOf(ASection: TJSONObject): TAtlasProjectBuild;
begin
  Result := TAtlasProjectBuild.Empty;
  if ASection = nil then
  begin
    Exit;
  end;
  Result.Known := True;
  Result.At := TAtlasProjectSummaries.TimeOf(TJsonRead.Text(ASection, 'at'));
  Result.Kind := TJsonRead.Text(ASection, 'kind');
  Result.Configuration := TJsonRead.Text(ASection, 'configuration');
  Result.Platform := TJsonRead.Text(ASection, 'platform');
  Result.Succeeded := TJsonRead.Flag(ASection, 'succeeded');
  Result.Errors := TJsonRead.IntOr(ASection, 'errors', 0);
  Result.Warnings := TJsonRead.IntOr(ASection, 'warnings', 0);
  Result.Hints := TJsonRead.IntOr(ASection, 'hints', 0);
  Result.DurationMs := TJsonRead.IntOr(ASection, 'durationMs', 0);
  Result.First := LocationOf(TJsonRead.Obj(ASection, 'first'));
end;

/// <summary>Abschnitt "check"; Empty ohne Abschnitt.</summary>
function CheckOf(ASection: TJSONObject): TAtlasProjectCheck;
begin
  Result := TAtlasProjectCheck.Empty;
  if ASection = nil then
  begin
    Exit;
  end;
  Result.Known := True;
  Result.At := TAtlasProjectSummaries.TimeOf(TJsonRead.Text(ASection, 'at'));
  Result.Errors := TJsonRead.IntOr(ASection, 'errors', 0);
  Result.First := LocationOf(TJsonRead.Obj(ASection, 'first'));
end;

/// <summary>Abschnitt "rules"; Empty ohne Abschnitt.</summary>
function RulesOf(ASection: TJSONObject): TAtlasProjectRules;
begin
  Result := TAtlasProjectRules.Empty;
  if ASection = nil then
  begin
    Exit;
  end;
  Result.Known := True;
  Result.At := TAtlasProjectSummaries.TimeOf(TJsonRead.Text(ASection, 'at'));
  Result.NewHits := TJsonRead.IntOr(ASection, 'newHits', 0);
end;

/// <summary>Abschnitt "baseline"; Empty ohne Abschnitt.</summary>
function BaselineOf(ASection: TJSONObject): TAtlasProjectBaseline;
begin
  Result := TAtlasProjectBaseline.Empty;
  if ASection = nil then
  begin
    Exit;
  end;
  Result.Known := True;
  Result.At := TAtlasProjectSummaries.TimeOf(TJsonRead.Text(ASection, 'at'));
  Result.Exists := TJsonRead.Flag(ASection, 'exists');
  Result.Valid := TJsonRead.Flag(ASection, 'valid');
  Result.Entries := TJsonRead.IntOr(ASection, 'entries', 0);
  Result.Hits := TJsonRead.IntOr(ASection, 'hits', 0);
  Result.Orphaned := TJsonRead.IntOr(ASection, 'orphaned', 0);
  Result.Updated := TAtlasProjectSummaries.TimeOf(TJsonRead.Text(ASection, 'updated'));
  Result.Added := TJsonRead.IntOr(ASection, 'added', 0);
  Result.Removed := TJsonRead.IntOr(ASection, 'removed', 0);
end;

function VcsJson(const AVcs: TAtlasProjectVcs; AOriginal: TJSONObject): TJSONObject;
begin
  Result := TJSONObject.Create;
  AddTime(Result, 'at', AVcs.At);
  Result.AddPair('kind', AVcs.Kind);
  if AVcs.Branch <> '' then
  begin
    Result.AddPair('branch', AVcs.Branch);
  end;
  if AVcs.Revision <> '' then
  begin
    Result.AddPair('revision', AVcs.Revision);
  end;
  Result.AddPair('changed', TJSONNumber.Create(AVcs.Changed));
  Result.AddPair('ahead', TJSONNumber.Create(AVcs.Ahead));
  Result.AddPair('behind', TJSONNumber.Create(AVcs.Behind));
  KeepUnknown(Result, AOriginal, cVcsKeys);
end;

function BuildJson(const ABuild: TAtlasProjectBuild; AOriginal: TJSONObject): TJSONObject;
begin
  Result := TJSONObject.Create;
  AddTime(Result, 'at', ABuild.At);
  Result.AddPair('kind', ABuild.Kind);
  Result.AddPair('configuration', ABuild.Configuration);
  Result.AddPair('platform', ABuild.Platform);
  Result.AddPair('succeeded', TJSONBool.Create(ABuild.Succeeded));
  Result.AddPair('errors', TJSONNumber.Create(ABuild.Errors));
  Result.AddPair('warnings', TJSONNumber.Create(ABuild.Warnings));
  Result.AddPair('hints', TJSONNumber.Create(ABuild.Hints));
  if ABuild.DurationMs > 0 then
  begin
    Result.AddPair('durationMs', TJSONNumber.Create(ABuild.DurationMs));
  end;
  if not ABuild.First.IsEmpty then
  begin
    Result.AddPair('first', LocationJson(ABuild.First));
  end;
  KeepUnknown(Result, AOriginal, cBuildKeys);
end;

function CheckJson(const ACheck: TAtlasProjectCheck; AOriginal: TJSONObject): TJSONObject;
begin
  Result := TJSONObject.Create;
  AddTime(Result, 'at', ACheck.At);
  Result.AddPair('errors', TJSONNumber.Create(ACheck.Errors));
  if not ACheck.First.IsEmpty then
  begin
    Result.AddPair('first', LocationJson(ACheck.First));
  end;
  KeepUnknown(Result, AOriginal, cCheckKeys);
end;

function RulesJson(const ARules: TAtlasProjectRules; AOriginal: TJSONObject): TJSONObject;
begin
  Result := TJSONObject.Create;
  AddTime(Result, 'at', ARules.At);
  Result.AddPair('newHits', TJSONNumber.Create(ARules.NewHits));
  KeepUnknown(Result, AOriginal, cRulesKeys);
end;

function MetricsJson(const AMetrics: TAtlasProjectMetrics; AOriginal: TJSONObject): TJSONObject;
begin
  Result := TJSONObject.Create;
  AddTime(Result, 'at', AMetrics.At);
  Result.AddPair('files', TJSONNumber.Create(AMetrics.Files));
  Result.AddPair('methods', TJSONNumber.Create(AMetrics.Methods));
  Result.AddPair('overLimits', TJSONNumber.Create(AMetrics.OverLimits));
  Result.AddPair('average', MetricNumbersJson(AMetrics.AverageTenths, True));
  Result.AddPair('maximum', MetricNumbersJson(AMetrics.Maximum, False));
  Result.AddPair('exceeded', MetricNumbersJson(AMetrics.Exceeded, False));
  KeepUnknown(Result, AOriginal, cMetricsKeys);
end;

function TodosJson(const ATodos: TAtlasProjectTodos; AOriginal: TJSONObject): TJSONObject;
var
  mKeywords: TJSONObject;
  mIndex: Integer;
begin
  Result := TJSONObject.Create;
  AddTime(Result, 'at', ATodos.At);
  Result.AddPair('files', TJSONNumber.Create(ATodos.Files));
  Result.AddPair('open', TJSONNumber.Create(ATodos.Open));
  Result.AddPair('done', TJSONNumber.Create(ATodos.Done));
  mKeywords := TJSONObject.Create;
  Result.AddPair('keywords', mKeywords);
  for mIndex := 0 to High(ATodos.Keywords) do
  begin
    mKeywords.AddPair(ATodos.Keywords[mIndex], TJSONNumber.Create(ATodos.KeywordCounts[mIndex]));
  end;
  KeepUnknown(Result, AOriginal, cTodosKeys);
end;

function BaselineJson(const ABaseline: TAtlasProjectBaseline; AOriginal: TJSONObject): TJSONObject;
begin
  Result := TJSONObject.Create;
  AddTime(Result, 'at', ABaseline.At);
  Result.AddPair('exists', TJSONBool.Create(ABaseline.Exists));
  Result.AddPair('valid', TJSONBool.Create(ABaseline.Valid));
  Result.AddPair('entries', TJSONNumber.Create(ABaseline.Entries));
  Result.AddPair('hits', TJSONNumber.Create(ABaseline.Hits));
  Result.AddPair('orphaned', TJSONNumber.Create(ABaseline.Orphaned));
  if ABaseline.Updated <> 0 then
  begin
    AddTime(Result, 'updated', ABaseline.Updated);
    Result.AddPair('added', TJSONNumber.Create(ABaseline.Added));
    Result.AddPair('removed', TJSONNumber.Create(ABaseline.Removed));
  end;
  KeepUnknown(Result, AOriginal, cBaselineKeys);
end;

/// <summary>Bekannte Abschnitte von ASummary an ARoot; AOriginal ist die gelesene Datei (darf nil sein).</summary>
procedure AddSections(ARoot, AOriginal: TJSONObject; const ASummary: TAtlasProjectSummary);
begin
  if ASummary.Vcs.Known then
  begin
    ARoot.AddPair('vcs', VcsJson(ASummary.Vcs, TJsonRead.Obj(AOriginal, 'vcs')));
  end;
  if ASummary.Build.Known then
  begin
    ARoot.AddPair('build', BuildJson(ASummary.Build, TJsonRead.Obj(AOriginal, 'build')));
  end;
  if ASummary.Check.Known then
  begin
    ARoot.AddPair('check', CheckJson(ASummary.Check, TJsonRead.Obj(AOriginal, 'check')));
  end;
  if ASummary.Rules.Known then
  begin
    ARoot.AddPair('rules', RulesJson(ASummary.Rules, TJsonRead.Obj(AOriginal, 'rules')));
  end;
  if ASummary.Metrics.Known then
  begin
    ARoot.AddPair('metrics', MetricsJson(ASummary.Metrics, TJsonRead.Obj(AOriginal, 'metrics')));
  end;
  if ASummary.Todos.Known then
  begin
    ARoot.AddPair('todos', TodosJson(ASummary.Todos, TJsonRead.Obj(AOriginal, 'todos')));
  end;
  if ASummary.Baseline.Known then
  begin
    ARoot.AddPair('baseline', BaselineJson(ASummary.Baseline, TJsonRead.Obj(AOriginal, 'baseline')));
  end;
  if ASummary.Trends.Known then
  begin
    ARoot.AddPair('trends', TrendsJson(ASummary.Trends, TJsonRead.Obj(AOriginal, 'trends')));
  end;
  if ASummary.Setup.Known then
  begin
    ARoot.AddPair('setup', TAtlasSummarySections.SetupJson(ASummary.Setup, TJsonRead.Obj(AOriginal, 'setup')));
  end;
  if ASummary.Tests.Known then
  begin
    ARoot.AddPair('tests', TAtlasSummarySections.TestsJson(ASummary.Tests, TJsonRead.Obj(AOriginal, 'tests')));
  end;
  if ASummary.Release.Known then
  begin
    ARoot.AddPair('release', TAtlasSummarySections.ReleaseJson(ASummary.Release, TJsonRead.Obj(AOriginal, 'release')));
  end;
  if ASummary.Ci.Known then
  begin
    ARoot.AddPair('ci', TAtlasSummarySections.CiJson(ASummary.Ci, TJsonRead.Obj(AOriginal, 'ci')));
  end;
end;

{ TAtlasProjectSummaries }

class function TAtlasProjectSummaries.NormalizedPath(const AProject: string): string;
var
  mIndex: Integer;
begin
  Result := Trim(AProject);
  for mIndex := 1 to Length(Result) do
  begin
    if Result[mIndex] = '/' then
    begin
      Result[mIndex] := '\';
    end
    else if CharInSet(Result[mIndex], ['a'..'z']) then
    begin
      Result[mIndex] := Chr(Ord(Result[mIndex]) - 32);
    end;
  end;
end;

// FNV-1a rechnet modulo 2^64: die Überlaufprüfung ist nur hier aus, danach wie vorher (#972).
{$IFOPT Q+}{$DEFINE ATLAS_HASH_UEBERLAUF}{$Q-}{$ENDIF}
class function TAtlasProjectSummaries.KeyOf(const AProject: string): string;
const
  cOffset: UInt64 = $CBF29CE484222325;
  cPrime: UInt64 = $00000100000001B3;
  cDigits: string = '0123456789abcdef';
var
  mText: string;
  mHash: UInt64;
  mIndex, mShift: Integer;
  mUnit_: Word;
begin
  mText := NormalizedPath(AProject);
  mHash := cOffset;
  for mIndex := 1 to Length(mText) do
  begin
    mUnit_ := Ord(mText[mIndex]);
    mHash := (mHash xor (mUnit_ and $FF)) * cPrime;
    mHash := (mHash xor (mUnit_ shr 8)) * cPrime;
  end;
  Result := '';
  mShift := 60;
  while mShift >= 0 do
  begin
    Result := Result + cDigits[((mHash shr mShift) and $F) + 1];
    Dec(mShift, 4);
  end;
end;
{$IFDEF ATLAS_HASH_UEBERLAUF}{$Q+}{$UNDEF ATLAS_HASH_UEBERLAUF}{$ENDIF}

class function TAtlasProjectSummaries.FileFor(const AFolder, AProject: string): string;
begin
  Result := IncludeTrailingPathDelimiter(AFolder) + KeyOf(AProject) + '.json';
end;

class function TAtlasProjectSummaries.TimeText(AUtc: TDateTime): string;
begin
  Result := SummaryTimeText(AUtc);
end;

class function TAtlasProjectSummaries.TimeOf(const AText: string): TDateTime;
begin
  Result := SummaryTimeOf(AText);
end;

class function TAtlasProjectSummaries.FormatOf(const AJson: string): Integer;
var
  mValue: TJSONValue;
begin
  Result := 0;
  try
    mValue := TJSONObject.ParseJSONValue(AJson);
  except
    on Exception do
      mValue := nil;
  end;
  try
    if mValue is TJSONObject then
    begin
      Result := TJsonRead.IntOr(TJSONObject(mValue), 'format', 0);
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasProjectSummaries.Parse(const AJson: string; out ASummary: TAtlasProjectSummary): Boolean;
var
  mValue: TJSONValue;
  mRoot: TJSONObject;
begin
  ASummary := TAtlasProjectSummary.Create('');
  Result := False;
  try
    mValue := TJSONObject.ParseJSONValue(AJson);
  except
    on Exception do
      mValue := nil;
  end;
  try
    if not (mValue is TJSONObject) then
    begin
      Exit;
    end;
    mRoot := TJSONObject(mValue);
    // Ohne "format" gilt 1; ein höheres Format kennt diese Fassung nicht.
    if TJsonRead.IntOr(mRoot, 'format', 1) > cFormat then
    begin
      Exit;
    end;
    ASummary.Raw := AJson;
    ASummary.Project := TJsonRead.Text(mRoot, 'project');
    ASummary.LastOpened := TimeOf(TJsonRead.Text(mRoot, 'lastOpened'));
    ASummary.LastClosed := TimeOf(TJsonRead.Text(mRoot, 'lastClosed'));
    ASummary.Hidden := TJsonRead.Flag(mRoot, 'hidden');
    ASummary.Vcs := VcsOf(TJsonRead.Obj(mRoot, 'vcs'));
    ASummary.Build := BuildOf(TJsonRead.Obj(mRoot, 'build'));
    ASummary.Check := CheckOf(TJsonRead.Obj(mRoot, 'check'));
    ASummary.Rules := RulesOf(TJsonRead.Obj(mRoot, 'rules'));
    ASummary.Metrics := MetricsOf(TJsonRead.Obj(mRoot, 'metrics'));
    ASummary.Todos := TodosOf(TJsonRead.Obj(mRoot, 'todos'));
    ASummary.Baseline := BaselineOf(TJsonRead.Obj(mRoot, 'baseline'));
    ASummary.Trends := TrendsOf(TJsonRead.Obj(mRoot, 'trends'));
    ASummary.Setup := TAtlasSummarySections.SetupOf(TJsonRead.Obj(mRoot, 'setup'));
    ASummary.Tests := TAtlasSummarySections.TestsOf(TJsonRead.Obj(mRoot, 'tests'));
    ASummary.Release := TAtlasSummarySections.ReleaseOf(TJsonRead.Obj(mRoot, 'release'));
    ASummary.Ci := TAtlasSummarySections.CiOf(TJsonRead.Obj(mRoot, 'ci'));
    Result := True;
  finally
    mValue.Free;
  end;
end;

class function TAtlasProjectSummaries.ToJson(const ASummary: TAtlasProjectSummary): string;
var
  mValue: TJSONValue;
  mOriginal, mRoot: TJSONObject;
begin
  mValue := nil;
  if ASummary.Raw <> '' then
    try
      mValue := TJSONObject.ParseJSONValue(ASummary.Raw);
    except
      on Exception do
        mValue := nil;
    end;
  mRoot := TJSONObject.Create;
  try
    mOriginal := nil;
    if mValue is TJSONObject then
    begin
      mOriginal := TJSONObject(mValue);
    end;
    mRoot.AddPair('format', TJSONNumber.Create(cFormat));
    mRoot.AddPair('project', ASummary.Project);
    AddTime(mRoot, 'lastOpened', ASummary.LastOpened);
    AddTime(mRoot, 'lastClosed', ASummary.LastClosed);
    if ASummary.Hidden then
    begin
      mRoot.AddPair('hidden', TJSONBool.Create(True));
    end;
    AddSections(mRoot, mOriginal, ASummary);
    KeepUnknown(mRoot, mOriginal, cTopKeys);
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
    mValue.Free;
  end;
end;

/// <summary>Liest die Übersicht aus AFileName über TAtlasDataFile. AParsed: gelesen; sonst ist
/// ASummary leer mit Project = AProject. Ergebnis Kept: vorhanden, aber nicht gelesen; nicht überschreiben.
/// </summary>
function ReadSummary(const AFileName, AProject: string; out ASummary: TAtlasProjectSummary;
  out AParsed: Boolean): TAtlasDataLoad;
var
  mSummary: TAtlasProjectSummary;
  mParsed: Boolean;
begin
  mParsed := False;
  Result := TAtlasDataFile.Load(AFileName, 'Projektübersicht',
    function(const AText: string): Boolean
    begin
      mParsed := TAtlasProjectSummaries.Parse(AText, mSummary);
      // Ein höheres Format ist nicht unbrauchbar: nicht beiseitelegen; Save überschreibt es nicht.
      Result := mParsed or (TAtlasProjectSummaries.FormatOf(AText) > TAtlasProjectSummaries.cFormat);
    end);
  AParsed := mParsed and (Result = TAtlasDataLoad.Loaded);
  if AParsed then
  begin
    ASummary := mSummary;
    if ASummary.Project = '' then
    begin
      ASummary.Project := AProject;
    end;
  end
  else
  begin
    ASummary := TAtlasProjectSummary.Create(AProject);
  end;
end;

class function TAtlasProjectSummaries.DefaultFolder: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), cFolderName);
end;

class function TAtlasProjectSummaries.FailedTestsOf(const AFolder, ATestProject: string): TArray<string>;
var
  mSummary: TAtlasProjectSummary;
begin
  Result := nil;
  if (ATestProject <> '') and Load(AFolder, ATestProject, mSummary) and mSummary.Tests.Known and
    SameText(mSummary.Tests.Project, ATestProject) then
  begin
    Result := mSummary.Tests.FailedTests;
  end;
end;

class function TAtlasProjectSummaries.Load(const AFolder, AProject: string;
  out ASummary: TAtlasProjectSummary): Boolean;
begin
  ASummary := TAtlasProjectSummary.Create(AProject);
  Result := False;
  if (AFolder = '') or (Trim(AProject) = '') then
  begin
    Exit;
  end;
  // Fehlt, unbrauchbar (dann als .defekt beiseitegelegt) oder gesperrt: leere Übersicht.
  ReadSummary(FileFor(AFolder, AProject), AProject, ASummary, Result);
end;

class function TAtlasProjectSummaries.Save(const AFolder: string; const ASummary: TAtlasProjectSummary): Boolean;
var
  mFileName, mText: string;
begin
  Result := False;
  if (AFolder = '') or (Trim(ASummary.Project) = '') then
  begin
    Exit;
  end;
  mFileName := FileFor(AFolder, ASummary.Project);
  try
    // Eine neuere Fassung hat die Datei geschrieben oder sie ist gerade nicht lesbar: nicht überschreiben.
    if FileExists(mFileName) and (not TAtlasDataFile.TryRead(mFileName, mText) or (FormatOf(mText) > cFormat)) then
    begin
      Exit;
    end;
    // Atomar ersetzt, UTF-8 ohne BOM wie JSON üblich.
    TAtlasDataFile.Write(mFileName, ToJson(ASummary));
    Result := True;
  except
    on E: Exception do
      TAtlasDataFile.ReportNotWritten('Projektübersicht', E);
  end;
end;

class function TAtlasProjectSummaries.Update(const AFolder, AProject: string;
  const AChange: TAtlasProjectSummaryChange): Boolean;
var
  mSummary: TAtlasProjectSummary;
  mParsed: Boolean;
begin
  Result := False;
  if (AFolder = '') or (Trim(AProject) = '') then
  begin
    Exit;
  end;
  // Ohne Datei oder mit unbrauchbarer (jetzt .defekt) beginnt eine neue; eine gesperrte bleibt unverändert,
  // sonst ginge ihr Inhalt verloren. Eine Datei mit höherem Format bleibt unangetastet (Save prüft das).
  if not TAtlasDataFile.Writable(ReadSummary(FileFor(AFolder, AProject), AProject, mSummary, mParsed)) then
  begin
    Exit;
  end;
  if Assigned(AChange) then
  begin
    AChange(mSummary);
  end;
  Result := Save(AFolder, mSummary);
end;

end.
