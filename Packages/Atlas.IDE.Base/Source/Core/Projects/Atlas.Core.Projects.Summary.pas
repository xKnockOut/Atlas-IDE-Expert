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
  Atlas.Core.CiBuild.Contract,
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
  TAtlasProjectReleaseBuild = Atlas.Core.Projects.Summary.Sections.TAtlasProjectReleaseBuild;
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
    /// <summary>Ersetzt die Datei atomar (TAtlasDataFile.Write); False bei Fehler (einmal protokolliert), wenn
    /// die vorhandene Datei ein höheres Format hat oder gerade nicht lesbar ist.</summary>
    class function Save(const AFolder: string; const ASummary: TAtlasProjectSummary): Boolean; static;
    /// <summary>Lesen, AChange anwenden, schreiben. Eine unbrauchbare Datei liegt danach als .defekt daneben
    /// (Bericht N3); eine gesperrte bleibt unverändert (False).</summary>
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
  Atlas.Core.Projects.Summary.Json;

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
  Index: Integer;
begin
  // Ohne ExtractFileName: Der Pfad hat immer „\“, auch wenn die Tests nicht unter Windows laufen.
  Result := Project;
  for Index := Length(Result) downto 1 do
  begin
    if CharInSet(Result[Index], ['\', '/']) then
    begin
      Result := Copy(Result, Index + 1, MaxInt);
      Break;
    end;
  end;
  for Index := Length(Result) downto 1 do
  begin
    if Result[Index] = '.' then
    begin
      Result := Copy(Result, 1, Index - 1);
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
  Index: Integer;
  Value: TJSONValue;
begin
  for Index := Low(Result) to High(Result) do
  begin
    Result[Index] := 0;
    if AObject = nil then
    begin
      Continue;
    end;
    Value := AObject.GetValue(TAtlasProjectSummaries.MetricKeys[Index]);
    if not (Value is TJSONNumber) then
    begin
      Continue;
    end;
    if ATenths then
    begin
      Result[Index] := Round(TJSONNumber(Value).AsDouble * 10);
    end
    else
    begin
      Result[Index] := TJSONNumber(Value).AsInt;
    end;
  end;
end;

/// <summary>Objekt {"length": …, …}; ATenths: Werte als Dezimalzahl mit einer Nachkommastelle.</summary>
function MetricNumbersJson(const ANumbers: TAtlasMetricNumbers; ATenths: Boolean): TJSONObject;
var
  Index: Integer;
begin
  Result := TJSONObject.Create;
  for Index := Low(ANumbers) to High(ANumbers) do
  begin
    if ATenths then
    begin
      Result.AddPair(TAtlasProjectSummaries.MetricKeys[Index], TJSONNumber.Create(ANumbers[Index] / 10));
    end
    else
    begin
      Result.AddPair(TAtlasProjectSummaries.MetricKeys[Index], TJSONNumber.Create(ANumbers[Index]));
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
    begin
      Exit;
    end;
    Section := ObjectOf(TJSONObject(Value), 'summary');
    if Section = nil then
    begin
      Section := ObjectOf(TJSONObject(Value), 'metrics');
    end;
    if Section = nil then
    begin
      Section := TJSONObject(Value);
    end;
    if not (Section.GetValue('methods') is TJSONNumber) then
    begin
      Exit;
    end;
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
  begin
    Exit;
  end;
  Result.Known := True;
  Result.At := TAtlasProjectSummaries.TimeOf(TextOf(ASection, 'at'));
  Result.Files := NumberOf(ASection, 'files', 0);
  Result.Open := NumberOf(ASection, 'open', 0);
  Result.Done := NumberOf(ASection, 'done', 0);
  Keywords := ObjectOf(ASection, 'keywords');
  if Keywords = nil then
  begin
    Exit;
  end;
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
  begin
    if SameText(Keywords[Index], AKeyword) then
    begin
      Exit(KeywordCounts[Index]);
    end;
  end;
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
    begin
      Exit;
    end;
    Section := ObjectOf(TJSONObject(Value), 'summary');
    if Section = nil then
    begin
      Section := ObjectOf(TJSONObject(Value), 'todos');
    end;
    if Section = nil then
    begin
      Section := TJSONObject(Value);
    end;
    if not (Section.GetValue('open') is TJSONNumber) then
    begin
      Exit;
    end;
    ATodos := TodosOf(Section);
    ATodos.At := AAtUtc;
    Result := True;
  finally
    Value.Free;
  end;
end;

/// <summary>Abschnitt "trends"; leer ohne Abschnitt. Punkte ohne gültige Nummer bekommen eine nach der letzten.
/// </summary>
/// <summary>Messpunkt aus AItem; Werte in Zehnteln, fehlende bleiben Lücken.</summary>
function TrendPointOf(AItem: TJSONObject): TAtlasTrendPoint;
var
  Series: TAtlasTrendSeries;
  Value: TJSONValue;
begin
  Result := TAtlasTrendPoint.Create(SummaryTimeOf(TextOf(AItem, 'at')), NumberOf(AItem, 'build', 0));
  Result.Branch := TextOf(AItem, 'branch');
  Result.Commit := TextOf(AItem, 'commit');
  for Series := Low(TAtlasTrendSeries) to High(TAtlasTrendSeries) do
  begin
    Value := AItem.GetValue(TAtlasProjectSummaries.TrendKeys[Series]);
    if Value is TJSONNumber then
    begin
      Result.SetValue(Series, Round(TJSONNumber(Value).AsDouble * 10));
    end;
  end;
end;

function TrendsOf(ASection: TJSONObject): TAtlasProjectTrends;
var
  Points: TJSONValue;
  Item: TJSONValue;
  Index: Integer;
  Point: TAtlasTrendPoint;
  Highest: Integer;
begin
  Result := TAtlasProjectTrends.Empty;
  if ASection = nil then
  begin
    Exit;
  end;
  Result.Known := True;
  Result.Builds := NumberOf(ASection, 'builds', 0);
  Highest := 0;
  Points := ASection.GetValue('points');
  if Points is TJSONArray then
  begin
    for Index := 0 to TJSONArray(Points).Count - 1 do
    begin
      Item := TJSONArray(Points).Items[Index];
      if not (Item is TJSONObject) then
      begin
        Continue;
      end;
      Point := TrendPointOf(TJSONObject(Item));
      // Nummern steigen streng: Doppelte oder Rückschritte rücken hinter den höchsten.
      if Point.Build <= Highest then
      begin
        Point.Build := Highest + 1;
      end;
      Highest := Point.Build;
      Result.Points := Result.Points + [Point];
    end;
  end;
  // Ohne oder mit zu kleinem Zähler: mindestens die höchste Nummer.
  if Result.Builds < Highest then
  begin
    Result.Builds := Highest;
  end;
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
  begin
    Exit;
  end;
  Points := AOriginal.GetValue('points');
  if not (Points is TJSONArray) then
  begin
    Exit;
  end;
  for Index := 0 to TJSONArray(Points).Count - 1 do
  begin
    Item := TJSONArray(Points).Items[Index];
    if (Item is TJSONObject) and (NumberOf(TJSONObject(Item), 'build', 0) = ABuild) then
    begin
      Exit(TJSONObject(Item));
    end;
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
    begin
      Item.AddPair('branch', Point.Branch);
    end;
    if Point.Commit <> '' then
    begin
      Item.AddPair('commit', Point.Commit);
    end;
    for Series := Low(TAtlasTrendSeries) to High(TAtlasTrendSeries) do
    begin
      // Lücke: kein Feld.
      if not Point.Has[Series] then
      begin
        Continue;
      end;
      if TAtlasProjectSummaries.TrendDecimals[Series] then
      begin
        Item.AddPair(TAtlasProjectSummaries.TrendKeys[Series], TJSONNumber.Create(Point.Values[Series] / 10));
      end
      else
      begin
        Item.AddPair(TAtlasProjectSummaries.TrendKeys[Series], TJSONNumber.Create(Point.Values[Series] div 10));
      end;
    end;
    KeepUnknown(Item, OriginalPoint(AOriginal, Point.Build), TrendPointKeys);
  end;
  KeepUnknown(Result, AOriginal, TrendsKeys);
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
  Result.At := TAtlasProjectSummaries.TimeOf(TextOf(ASection, 'at'));
  Result.Kind := LowerCase(TextOf(ASection, 'kind'));
  Result.Branch := TextOf(ASection, 'branch');
  Result.Revision := TextOf(ASection, 'revision');
  Result.Changed := NumberOf(ASection, 'changed', -1);
  Result.Ahead := NumberOf(ASection, 'ahead', -1);
  Result.Behind := NumberOf(ASection, 'behind', -1);
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
  Result.At := TAtlasProjectSummaries.TimeOf(TextOf(ASection, 'at'));
  Result.Kind := TextOf(ASection, 'kind');
  Result.Configuration := TextOf(ASection, 'configuration');
  Result.Platform := TextOf(ASection, 'platform');
  Result.Succeeded := FlagOf(ASection, 'succeeded');
  Result.Errors := NumberOf(ASection, 'errors', 0);
  Result.Warnings := NumberOf(ASection, 'warnings', 0);
  Result.Hints := NumberOf(ASection, 'hints', 0);
  Result.DurationMs := NumberOf(ASection, 'durationMs', 0);
  Result.First := LocationOf(ObjectOf(ASection, 'first'));
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
  Result.At := TAtlasProjectSummaries.TimeOf(TextOf(ASection, 'at'));
  Result.Errors := NumberOf(ASection, 'errors', 0);
  Result.First := LocationOf(ObjectOf(ASection, 'first'));
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
  Result.At := TAtlasProjectSummaries.TimeOf(TextOf(ASection, 'at'));
  Result.NewHits := NumberOf(ASection, 'newHits', 0);
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
  Result.At := TAtlasProjectSummaries.TimeOf(TextOf(ASection, 'at'));
  Result.Exists := FlagOf(ASection, 'exists');
  Result.Valid := FlagOf(ASection, 'valid');
  Result.Entries := NumberOf(ASection, 'entries', 0);
  Result.Hits := NumberOf(ASection, 'hits', 0);
  Result.Orphaned := NumberOf(ASection, 'orphaned', 0);
  Result.Updated := TAtlasProjectSummaries.TimeOf(TextOf(ASection, 'updated'));
  Result.Added := NumberOf(ASection, 'added', 0);
  Result.Removed := NumberOf(ASection, 'removed', 0);
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
  KeepUnknown(Result, AOriginal, VcsKeys);
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
  KeepUnknown(Result, AOriginal, BuildKeys);
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
  KeepUnknown(Result, AOriginal, CheckKeys);
end;

function RulesJson(const ARules: TAtlasProjectRules; AOriginal: TJSONObject): TJSONObject;
begin
  Result := TJSONObject.Create;
  AddTime(Result, 'at', ARules.At);
  Result.AddPair('newHits', TJSONNumber.Create(ARules.NewHits));
  KeepUnknown(Result, AOriginal, RulesKeys);
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
  KeepUnknown(Result, AOriginal, MetricsKeys);
end;

function TodosJson(const ATodos: TAtlasProjectTodos; AOriginal: TJSONObject): TJSONObject;
var
  Keywords: TJSONObject;
  Index: Integer;
begin
  Result := TJSONObject.Create;
  AddTime(Result, 'at', ATodos.At);
  Result.AddPair('files', TJSONNumber.Create(ATodos.Files));
  Result.AddPair('open', TJSONNumber.Create(ATodos.Open));
  Result.AddPair('done', TJSONNumber.Create(ATodos.Done));
  Keywords := TJSONObject.Create;
  Result.AddPair('keywords', Keywords);
  for Index := 0 to High(ATodos.Keywords) do
  begin
    Keywords.AddPair(ATodos.Keywords[Index], TJSONNumber.Create(ATodos.KeywordCounts[Index]));
  end;
  KeepUnknown(Result, AOriginal, TodosKeys);
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
  KeepUnknown(Result, AOriginal, BaselineKeys);
end;

/// <summary>Bekannte Abschnitte von ASummary an ARoot; AOriginal ist die gelesene Datei (darf nil sein).</summary>
procedure AddSections(ARoot, AOriginal: TJSONObject; const ASummary: TAtlasProjectSummary);
begin
  if ASummary.Vcs.Known then
  begin
    ARoot.AddPair('vcs', VcsJson(ASummary.Vcs, ObjectOf(AOriginal, 'vcs')));
  end;
  if ASummary.Build.Known then
  begin
    ARoot.AddPair('build', BuildJson(ASummary.Build, ObjectOf(AOriginal, 'build')));
  end;
  if ASummary.Check.Known then
  begin
    ARoot.AddPair('check', CheckJson(ASummary.Check, ObjectOf(AOriginal, 'check')));
  end;
  if ASummary.Rules.Known then
  begin
    ARoot.AddPair('rules', RulesJson(ASummary.Rules, ObjectOf(AOriginal, 'rules')));
  end;
  if ASummary.Metrics.Known then
  begin
    ARoot.AddPair('metrics', MetricsJson(ASummary.Metrics, ObjectOf(AOriginal, 'metrics')));
  end;
  if ASummary.Todos.Known then
  begin
    ARoot.AddPair('todos', TodosJson(ASummary.Todos, ObjectOf(AOriginal, 'todos')));
  end;
  if ASummary.Baseline.Known then
  begin
    ARoot.AddPair('baseline', BaselineJson(ASummary.Baseline, ObjectOf(AOriginal, 'baseline')));
  end;
  if ASummary.Trends.Known then
  begin
    ARoot.AddPair('trends', TrendsJson(ASummary.Trends, ObjectOf(AOriginal, 'trends')));
  end;
  if ASummary.Setup.Known then
  begin
    ARoot.AddPair('setup', TAtlasSummarySections.SetupJson(ASummary.Setup, ObjectOf(AOriginal, 'setup')));
  end;
  if ASummary.Tests.Known then
  begin
    ARoot.AddPair('tests', TAtlasSummarySections.TestsJson(ASummary.Tests, ObjectOf(AOriginal, 'tests')));
  end;
  if ASummary.Release.Known then
  begin
    ARoot.AddPair('release', TAtlasSummarySections.ReleaseJson(ASummary.Release, ObjectOf(AOriginal, 'release')));
  end;
  if ASummary.Ci.Known then
  begin
    ARoot.AddPair('ci', TAtlasSummarySections.CiJson(ASummary.Ci, ObjectOf(AOriginal, 'ci')));
  end;
end;

{ TAtlasProjectSummaries }

class function TAtlasProjectSummaries.NormalizedPath(const AProject: string): string;
var
  Index: Integer;
begin
  Result := Trim(AProject);
  for Index := 1 to Length(Result) do
  begin
    if Result[Index] = '/' then
    begin
      Result[Index] := '\';
    end
    else if CharInSet(Result[Index], ['a'..'z']) then
    begin
      Result[Index] := Chr(Ord(Result[Index]) - 32);
    end;
  end;
end;

// FNV-1a rechnet modulo 2^64: die Überlaufprüfung ist nur hier aus, danach wie vorher (#972).
{$IFOPT Q+}{$DEFINE ATLAS_HASH_UEBERLAUF}{$Q-}{$ENDIF}
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
    begin
      Result := NumberOf(TJSONObject(Value), 'format', 0);
    end;
  finally
    Value.Free;
  end;
end;

class function TAtlasProjectSummaries.Parse(const AJson: string; out ASummary: TAtlasProjectSummary): Boolean;
var
  Value: TJSONValue;
  Root: TJSONObject;
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
    begin
      Exit;
    end;
    Root := TJSONObject(Value);
    // Ohne "format" gilt 1; ein höheres Format kennt diese Fassung nicht.
    if NumberOf(Root, 'format', 1) > Format then
    begin
      Exit;
    end;
    ASummary.Raw := AJson;
    ASummary.Project := TextOf(Root, 'project');
    ASummary.LastOpened := TimeOf(TextOf(Root, 'lastOpened'));
    ASummary.LastClosed := TimeOf(TextOf(Root, 'lastClosed'));
    ASummary.Hidden := FlagOf(Root, 'hidden');
    ASummary.Vcs := VcsOf(ObjectOf(Root, 'vcs'));
    ASummary.Build := BuildOf(ObjectOf(Root, 'build'));
    ASummary.Check := CheckOf(ObjectOf(Root, 'check'));
    ASummary.Rules := RulesOf(ObjectOf(Root, 'rules'));
    ASummary.Metrics := MetricsOf(ObjectOf(Root, 'metrics'));
    ASummary.Todos := TodosOf(ObjectOf(Root, 'todos'));
    ASummary.Baseline := BaselineOf(ObjectOf(Root, 'baseline'));
    ASummary.Trends := TrendsOf(ObjectOf(Root, 'trends'));
    ASummary.Setup := TAtlasSummarySections.SetupOf(ObjectOf(Root, 'setup'));
    ASummary.Tests := TAtlasSummarySections.TestsOf(ObjectOf(Root, 'tests'));
    ASummary.Release := TAtlasSummarySections.ReleaseOf(ObjectOf(Root, 'release'));
    ASummary.Ci := TAtlasSummarySections.CiOf(ObjectOf(Root, 'ci'));
    Result := True;
  finally
    Value.Free;
  end;
end;

class function TAtlasProjectSummaries.ToJson(const ASummary: TAtlasProjectSummary): string;
var
  Value: TJSONValue;
  Original, Root: TJSONObject;
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
    begin
      Original := TJSONObject(Value);
    end;
    Root.AddPair('format', TJSONNumber.Create(Format));
    Root.AddPair('project', ASummary.Project);
    AddTime(Root, 'lastOpened', ASummary.LastOpened);
    AddTime(Root, 'lastClosed', ASummary.LastClosed);
    if ASummary.Hidden then
    begin
      Root.AddPair('hidden', TJSONBool.Create(True));
    end;
    AddSections(Root, Original, ASummary);
    KeepUnknown(Root, Original, TopKeys);
    Result := Root.ToJSON;
  finally
    Root.Free;
    Value.Free;
  end;
end;

/// <summary>Liest die Übersicht aus AFileName über TAtlasDataFile (Bericht N3). AParsed: gelesen; sonst ist
/// ASummary leer mit Project = AProject. Ergebnis Kept: vorhanden, aber nicht gelesen; nicht überschreiben.
/// </summary>
function ReadSummary(const AFileName, AProject: string; out ASummary: TAtlasProjectSummary;
  out AParsed: Boolean): TAtlasDataLoad;
var
  Summary: TAtlasProjectSummary;
  Parsed: Boolean;
begin
  Parsed := False;
  Result := TAtlasDataFile.Load(AFileName, 'Projektübersicht',
    function(const AText: string): Boolean
    begin
      Parsed := TAtlasProjectSummaries.Parse(AText, Summary);
      // Ein höheres Format ist nicht unbrauchbar: nicht beiseitelegen; Save überschreibt es nicht.
      Result := Parsed or (TAtlasProjectSummaries.FormatOf(AText) > TAtlasProjectSummaries.Format);
    end);
  AParsed := Parsed and (Result = TAtlasDataLoad.Loaded);
  if AParsed then
  begin
    ASummary := Summary;
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
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), FolderName);
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
  FileName, Text: string;
begin
  Result := False;
  if (AFolder = '') or (Trim(ASummary.Project) = '') then
  begin
    Exit;
  end;
  FileName := FileFor(AFolder, ASummary.Project);
  try
    // Eine neuere Fassung hat die Datei geschrieben oder sie ist gerade nicht lesbar: nicht überschreiben.
    if FileExists(FileName) and (not TAtlasDataFile.TryRead(FileName, Text) or (FormatOf(Text) > Format)) then
    begin
      Exit;
    end;
    // Atomar ersetzt, UTF-8 ohne BOM wie JSON üblich.
    TAtlasDataFile.Write(FileName, ToJson(ASummary));
    Result := True;
  except
    on E: Exception do
      TAtlasDataFile.ReportNotWritten('Projektübersicht', E);
  end;
end;

class function TAtlasProjectSummaries.Update(const AFolder, AProject: string;
  const AChange: TAtlasProjectSummaryChange): Boolean;
var
  Summary: TAtlasProjectSummary;
  Parsed: Boolean;
begin
  Result := False;
  if (AFolder = '') or (Trim(AProject) = '') then
  begin
    Exit;
  end;
  // Ohne Datei oder mit unbrauchbarer (jetzt .defekt) beginnt eine neue; eine gesperrte bleibt unverändert,
  // sonst ginge ihr Inhalt verloren. Eine Datei mit höherem Format bleibt unangetastet (Save prüft das).
  if not TAtlasDataFile.Writable(ReadSummary(FileFor(AFolder, AProject), AProject, Summary, Parsed)) then
  begin
    Exit;
  end;
  if Assigned(AChange) then
  begin
    AChange(Summary);
  end;
  Result := Save(AFolder, Summary);
end;

end.
