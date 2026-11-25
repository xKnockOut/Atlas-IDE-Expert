# ADR 0017: Zuordnung der Units zu Packages

- Bezug: #1455, #1456; Regeln für Laden, Entladen und Versionen in [docs/Architektur.md](../Architektur.md) („Module und Verträge des Plugins“)

## Entscheidung

Jede Unit des Plugins gehört zu genau einem Package: `Atlas.IDE.Base` oder einem Modul. Welche das ist, ergibt sich zuerst aus dem Ordner unter `Core/`, `IDE/` oder `UI/` (Ordnertabelle), alle übrigen Ordner gehören zu Base. Ein Modul mit eigenem Package-Ordner hat seine Quellen unter `Packages/<Modul>/Source` (#1456).

Die Zuordnung ist Daten, kein Text: Sie steht in drei TSV-Dateien neben dem Prüfskript, eine Zeile je Eintrag, Spalten durch Tabulator getrennt, die erste Zeile nennt die Spalten.

| Datei | Spalten | Inhalt |
|---|---|---|
| `Tools/UnitAssignment.tsv` | `Package`, `Unit`, `Datei`, `Grund` | jede Unit des Plugins, `Datei` relativ zu `Packages/<Package>/Source`, sortiert nach Package und Unit (ohne Groß-/Kleinschreibung) |
| `Tools/UnitAssignment.Folders.tsv` | `Ordner`, `Package` | Ordnertabelle, `*` steht für alle übrigen Ordner |
| `Tools/UnitAssignment.Boundaries.tsv` | `Art`, `Von`, `Nach`, `Grund` | Verweise über Modulgrenzen: `Ausnahme` (befristet genehmigt, wird übergangen) oder `Verstoß` (bekannt, wird bei jedem Lauf genannt) |

Maßgeblich ist die Zeile der Unit. Weicht sie von der Ordnertabelle ab, ist sie eine der Ausnahmen unten und braucht eine eigene Begründung, nicht nur „Ordner …“. `Tools/Check-PackageDependencies.ps1` liest die drei Dateien (#1455) und schlägt fehl, wenn eine Unit keine Zeile hat, eine Zeile keine Unit mehr, eine Datei woanders liegt, eine Zeile unsortiert steht oder ein Eintrag in `Boundaries.tsv` nicht mehr vorkommt. `Tools/Check-TestCoverage.ps1` leitet daraus die Testkategorie je Modul ab.

Eine neue Unit bekommt eine Zeile an ihrer sortierten Stelle, zum Beispiel:

```text
Atlas.IDE.Base	Atlas.Core.Editor.Probe	Core/Editor/Atlas.Core.Editor.Probe.pas	Ordner `Core/Editor`
```

Gründe dafür: Eine Markdown-Tabelle, die ein Skript als Daten liest, ist eine Konfigurationsdatei im falschen Format. Viele Pull Requests tragen gleichzeitig Units ein; in einer sortierten Datei mit einer Zeile je Unit landen ihre Zeilen an verschiedenen Stellen, und `Tools/Merge-Integration.py` löst Ergänzungen beider Seiten an derselben Stelle und sortiert danach wieder.

## Ausnahmen von der Ordnertabelle

- KI-Assistenten (#1888): Die Eingänge für Aufträge von MCP-Clients (Builds über `build_project`, Änderungen an offenen Dateien) bilden das Modul `Atlas.IDE.Assistants`; gebaut wird über `IDE.Contracts.BuildRequests` des Moduls Build-Pipeline. Die Liste offener und ungespeicherter Dateien (`IDE.Files.DirtyExport`) bleibt im Kern: Sie schützt Dateien auch ohne das Modul vor dem Überschreiben durch den Server.
- Versionsverwaltung (#1891): Git und SVN (Anbieter, Parser, Auswahl), der Dienst der IDE und die Dialoge „Branch anlegen“ und „Arbeitskopien“ bilden das Modul `Atlas.IDE.VersionControl`. Im Kern bleiben der Vertrag (`Core.Vcs.Contract`, `IDE.Contracts.VersionControl` samt Zugang `TAtlasIdeVcs` und Null-Objekt) und die reine Logik ohne Prozessaufruf unter `Core/VersionControl` (Branch-Plan, Pull, Arbeitskopien, Werkzeugsuche, Serverzugang) und der allgemeine Prozessläufer, den auch das Modul Tests braucht. Einstellungsseiten und Änderungsmarken stehen seit #1905 im Modul; Base fragt die Marken über den Vertrag `IDE.Contracts.LineChanges`.
- Der allgemeine Tooltip `Atlas.Vcl.Popup.TitledTip` (bis #1455 `Atlas.UI.Notes.Tip`) liegt im Platform-Package `Atlas.Vcl`.
- Die Build-Pipeline ist ein eigenes Modul (#1455): Läufer der Builds auf Auftrag mit MCP-Eingang, Prüfung vor dem Kompilieren, Release-Wächter, Bewertung nach der 0/0/0-Regel mit Zusammenfassung (Ordner `BuildPipeline`, Schalter `buildPipeline`). Im Kern bleiben die Bewertung als Typen und `IAtlasBuildVerdictListener` (`Build.Verdict`, die Benachrichtigungszentrale hört darauf), was Base der Pipeline gibt (`Build.Pipeline`), die Werte ihrer Einstellungen (`Build.PipelineSettings`, `Build.OpenBuildSettings`), die Meldungen des letzten Builds (`IDE.Build.LastMessages`), `Build.IdleGate` (Diagnose-Zeitmessung) und `IDE.Build.Target` (Probleme, Projekt-Einstellungen). Andere Module bauen über `Atlas.IDE.Contracts.BuildPipeline`. Das Modul Build umfasst, was der Schalter `buildTools` abschaltet: Bauen beim Öffnen, Projektaufgaben, Startprofile, Compiler-Schalter.
- Code Lens mit Code-Metriken (#66) im Modul Analyse (#1756): Zeichnen (`IDE.Analysis.MetricsLens`) und Beschriftung (`Core.Analysis.MetricsLens`). Im Kern bleiben die Antwort von `atlas.server.metrics` (`Core.Editor.Metrics`) und ihr Abruf je Editor (`IDE.Editor.MetricsSource`), weil die Atlas-Statusleiste Zeilen und CC am Cursor daraus liest und der Metrikbericht dieselben Typen nutzt; die Lens meldet beim Abruf nur Bedarf an. `codeLens.metrics` hängt am Modulschalter `analysis.enabled`.
- Aus `SymbolPath/` liegen das Modell eines Wegs (`Core.SymbolPath.Model`) und seine Kette (`UI.SymbolPath.Chain`) im Kern (#1455): Das Ergebnisfenster von Base zeigt den Weg; Suche, Dialog und Befehle gehören zum Modul Analyse.
- Aus `StartProfiles/` liegt die lokale Datei (`Core.StartProfiles.Store`) im Kern, dazu `IDE.Foundation.StartOptions` (#1455): Startoptionen schreiben und „Start“ auslösen brauchen die Startprofile (Modul Build) und „Test debuggen“ (Modul Tests); kein Modul kennt das andere.
- Aus `Build/` bleiben im Kern: Compilermeldungen (`Build.Messages`, `Build.MessageView`), Prüfen nach dem Speichern (`Build.CheckOnSave`), Compile-Ereignisse (`Build.Events`, `Build.Notifier`) und die Build-Auswahl für den Server (`Build.Target`). Compilermeldungen und Prüfen nach dem Speichern bleiben ausdrücklich im Kern, weil sie auch ohne das Modul gebraucht werden.
- `Atlas.IDE.Rules` (#1455, festgeschrieben; seit #1755 alles Regelspezifische): Ordner `Core/IDE/UI/Rules`, dazu Sammelkorrektur (`Core.Problems.BulkFix`, `UI.Rules.BulkFix`) und Eigenschaftsregeln (`IDE.Editor.DfmPropertyRules`). Das Modul hat Regeltabelle und Regel-Editor, den Abschnitt „Prüfregeln“ mit Baseline und Unterdrückungen, den Dialog der Einstellungsdateien mit Regel-Editor (`IAtlasSettingsDialogProvider`) und die Regel-Aktionen am Befund (`IAtlasRuleActions`: einstellen, unterdrücken, abschalten). Im Kern bleibt die Anzeige der Befunde: Fenster „Atlas-Prüfung“ mit Erklären (`Core.Problems.Explanation`), Inline-Hinweise, Übersichtsleiste, Prüfen beim Speichern, der Hinweis bei abgeschaltetem Modul (`RuleChecksNotice`), Stand und Format der Baseline-Datei und die Verträge. Ohne Modul fehlen die Regel-Einträge im Menü, und der Dialog zeigt „rules“ als JSON-Text.
- `Atlas.Plugin.Localization.Strings` und die erzeugte Schema-Unit bleiben vorerst im Kern; ihr Schnitt hängt an den offenen Entscheidungen zu Texten und Einstellungen.

## Grenzen zwischen Base, Modulen und Verträgen

Regeln (Abschnitt Verträge; Regel 9 „Base kennt kein Modul“), geprüft über alle `uses` der Units der Plugin-Packages:

- Base verwendet kein Modul.
- Ein Modul verwendet kein anderes Modul; Querbezüge laufen über die Verträge zwischen Modulen, die in Base unter `Source/Contracts` liegen (`Atlas.IDE.Contracts.*`; kein eigenes Package).
- Erlaubt: Modul → Base (auch die Verträge), alles innerhalb eines Packages.

In `Tools/UnitAssignment.Boundaries.tsv` steht unter `Von` eine Unit, unter `Nach` ein Package oder eine Unit. Eine Zeile, die nicht mehr vorkommt, meldet das Skript als Fehler: Sie wird dann gestrichen, die Liste soll nur schrumpfen. Zurzeit ist sie leer.
