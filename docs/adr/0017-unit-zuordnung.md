# ADR 0017: Zuordnung der Units zu Packages

- Stand: 2026-11-01, Branch `Pilot-2.0.0-beta.1` (6364e487), nachgezogen auf ef9b9d95 (#1455), Quellen unter `Packages/Atlas.IDE.Base/Source`
- Bezug: ADR 0017, Abschnitt „Fortschreibung: Laden, Entladen, Versionen“; #1455, #1456

Diese Tabelle ersetzt den Verweis auf die Analyse vom 31.10.2026 (claude.ai-Dokument). Die Analyse enthielt nur Summen je Package, keine Liste je Unit. Die Liste hier ist aus dem Quellbaum erzeugt, nach diesen Regeln:

| Ordner (unter `Core/`, `IDE/`, `UI/`) | Package |
|---|---|
| `Debug` | `Atlas.IDE.Debugger` |
| `Tracker`, `Ci` | `Atlas.IDE.Tracker` |
| `Welcome` | `Atlas.IDE.Welcome` |
| `Analysis`, `Architecture`, `UnitRelations`, `SymbolPath`, `Hotspots` | `Atlas.IDE.Analysis` |
| `Rules` | `Atlas.IDE.Rules` |
| `Designer` | `Atlas.IDE.Designer` |
| `Help` | `Atlas.IDE.Help` |
| `Search`, `UnitSearch`, `Query` | `Atlas.IDE.Search` |
| `Tests` | `Atlas.IDE.Tests` |
| `Build`, `BuildTools`, `Tasks`, `StartProfiles` | `Atlas.IDE.Build` |
| `BuildPipeline` | `Atlas.IDE.BuildPipeline` |
| `Bookmarks`, `Notes`, `Todos` | `Atlas.IDE.Bookmarks` |
| `VersionControl` | `Atlas.IDE.VersionControl` |
| `Assistants` | `Atlas.IDE.Assistants` |
| alle übrigen | `Atlas.IDE.Base` |

Ausnahmen:

- KI-Assistenten (#1888): Die Eingänge für Aufträge von MCP-Clients (Builds über `build_project`, Änderungen an offenen Dateien) bilden das Modul `Atlas.IDE.Assistants`; gebaut wird über `IDE.Contracts.BuildRequests` des Moduls Build-Pipeline. Die Liste offener und ungespeicherter Dateien (`IDE.Files.DirtyExport`) bleibt im Kern: Sie schützt Dateien auch ohne das Modul vor dem Überschreiben durch den Server.
- Versionsverwaltung (#1891): Git und SVN (Anbieter, Parser, Auswahl), der Dienst der IDE und die Dialoge „Branch anlegen“ und „Arbeitskopien“ bilden das Modul `Atlas.IDE.VersionControl`. Im Kern bleiben der Vertrag (`Core.Vcs.Contract`, `IDE.Contracts.VersionControl` samt Zugang `TAtlasIdeVcs` und Null-Objekt) und die reine Logik ohne Prozessaufruf unter `Core/VersionControl` (Branch-Plan, Pull, Arbeitskopien, Werkzeugsuche, Serverzugang) und der allgemeine Prozessläufer, den auch das Modul Tests braucht. Einstellungsseiten und Änderungsmarken stehen seit #1905 im Modul; Base fragt die Marken über den Vertrag `IDE.Contracts.LineChanges`.
- Der allgemeine Tooltip `Atlas.UI.Popup.TitledTip` (bis #1455 `Atlas.UI.Notes.Tip`) liegt im Kern.
- Die Build-Pipeline ist ein eigenes Modul (#1455): Läufer der Builds auf Auftrag mit MCP-Eingang, Prüfung vor dem Kompilieren, Release-Wächter, Bewertung nach der 0/0/0-Regel mit Zusammenfassung (Ordner `BuildPipeline`, Schalter `buildPipeline`). Im Kern bleiben die Bewertung als Typen und `IAtlasBuildVerdictListener` (`Build.Verdict`, die Benachrichtigungszentrale hört darauf), was Base der Pipeline gibt (`Build.Pipeline`), die Werte ihrer Einstellungen (`Build.PipelineSettings`, `Build.OpenBuildSettings`), die Meldungen des letzten Builds (`IDE.Build.LastMessages`), `Build.IdleGate` (Diagnose-Zeitmessung) und `IDE.Build.Target` (Probleme, Projekt-Einstellungen). Andere Module bauen über `Atlas.IDE.Contracts.BuildPipeline`. Das Modul Build umfasst, was der Schalter `buildTools` abschaltet: Bauen beim Öffnen, Projektaufgaben, Startprofile, Compiler-Schalter.
- Code Lens mit Code-Metriken (#66) im Modul Analyse (#1756): Zeichnen (`IDE.Analysis.MetricsLens`) und Beschriftung (`Core.Analysis.MetricsLens`). Im Kern bleiben die Antwort von `atlas.server.metrics` (`Core.Editor.Metrics`) und ihr Abruf je Editor (`IDE.Editor.MetricsSource`), weil die Atlas-Statusleiste Zeilen und CC am Cursor daraus liest und der Metrikbericht dieselben Typen nutzt; die Lens meldet beim Abruf nur Bedarf an. `codeLens.metrics` hängt am Modulschalter `analysis.enabled`.
- Aus `SymbolPath/` liegen das Modell eines Wegs (`Core.SymbolPath.Model`) und seine Kette (`UI.SymbolPath.Chain`) im Kern (#1455): Das Ergebnisfenster von Base zeigt den Weg; Suche, Dialog und Befehle gehören zum Modul Analyse.
- Aus `StartProfiles/` liegt die lokale Datei (`Core.StartProfiles.Store`) im Kern, dazu `IDE.Foundation.StartOptions` (#1455): Startoptionen schreiben und „Start“ auslösen brauchen die Startprofile (Modul Build) und „Test debuggen“ (Modul Tests); kein Modul kennt das andere.
- Aus `Build/` bleiben im Kern: Compilermeldungen (`Build.Messages`, `Build.MessageView`), Prüfen nach dem Speichern (`Build.CheckOnSave`), Compile-Ereignisse (`Build.Events`, `Build.Notifier`) und die Build-Auswahl für den Server (`Build.Target`). ADR 0017 hält Compilermeldungen und Prüfen nach dem Speichern ausdrücklich im Kern.
- `Atlas.IDE.Rules` (#1455, festgeschrieben; seit #1755 alles Regelspezifische): Ordner `Core/IDE/UI/Rules`, dazu Sammelkorrektur (`Core/UI.Problems.BulkFix`) und Eigenschaftsregeln (`IDE.Editor.DfmPropertyRules`). Das Modul hat Regeltabelle und Regel-Editor, den Abschnitt „Prüfregeln“ mit Baseline und Unterdrückungen, den Dialog der Einstellungsdateien mit Regel-Editor (`IAtlasSettingsDialogProvider`) und die Regel-Aktionen am Befund (`IAtlasRuleActions`: einstellen, unterdrücken, abschalten). Im Kern bleibt die Anzeige der Befunde: Fenster „Atlas-Prüfung“ mit Erklären (`Core.Problems.Explanation`), Inline-Hinweise, Übersichtsleiste, Prüfen beim Speichern, der Hinweis bei abgeschaltetem Modul (`RuleChecksNotice`), Stand und Format der Baseline-Datei und die Verträge. Ohne Modul fehlen die Regel-Einträge im Menü, und der Dialog zeigt „rules“ als JSON-Text.
- `Atlas.UI.Strings` und die erzeugte Schema-Unit bleiben vorerst im Kern; ihr Schnitt hängt an den offenen Entscheidungen zu Texten und Einstellungen (ADR 0017, Fortschreibung).

Das Prüfskript `Tools/Check-PackageDependencies.ps1` liest diese Datei als Daten (#1455): die Ordnertabelle oben, die Tabellen je Package unten (Einzelzeilen) und die Tabellen unter „Grenzen zwischen Base, Modulen und Verträgen“. Maßgeblich ist die Einzelzeile. Weicht sie von der Ordnertabelle ab, ist sie eine der Ausnahmen oben und braucht eine eigene Begründung (nicht nur „Ordner …“). Eine neue Unit unter `Packages/Atlas.IDE.Base/Source` braucht eine Zeile hier, sonst schlägt das Skript fehl; ebenso eine Zeile, deren Datei es nicht mehr gibt.

## Grenzen zwischen Base, Modulen und Verträgen

Regeln (ADR 0017, Abschnitt Verträge; Regel 9 „Base kennt kein Modul“), geprüft über alle `uses` der Units unter `Packages/Atlas.IDE.Base/Source`:

- Base verwendet kein Modul.
- Ein Modul verwendet kein anderes Modul; Querbezüge laufen über die Verträge zwischen Modulen, die in Base unter `Source/Contracts` liegen (`Atlas.IDE.Contracts.*`; kein eigenes Package).
- Erlaubt: Modul → Base (auch die Verträge), alles innerhalb eines Packages.

In den beiden Tabellen steht unter „Von“ eine Unit, unter „Nach“ ein Package oder eine Unit. Eine Zeile, die nicht mehr vorkommt, meldet das Skript als Fehler: Sie wird dann gestrichen, die Listen sollen nur schrumpfen.

### Befristete Ausnahmen

Genehmigt im Auftrag zu #1455 (Paket 1, 01.11.2026). Das Skript übergeht diese Verweise.

| Von | Nach | Grund |
|---|---|---|

Seit Paket 2c (#1455) leer: Die Kompositionswurzel baut weder „Testergebnisse“ noch den Zugang zum Tracker, „Issue anlegen“ erreicht sie über `IAtlasIssueCreation` von Base.

### Bekannte Verstöße

Stand 01.11.2026 (8510d10a). Das sind echte Verstöße, nicht genehmigt. Das Skript nennt jeden bei jedem Lauf und schlägt nur bei neuen fehl. Wer einen behebt, streicht die Zeile.

| Von | Nach | Behebt |
|---|---|---|

Seit #1456 leer: Die Einstellungen der Willkommensseite baut das Modul als Abschnitt (`Atlas.UI.Welcome.SettingsSection`, Anbieter `Atlas.IDE.Welcome.Settings`) samt Modulschalter. Seit 05.11.2026 baut Base überhaupt keine Einstellungen eines Moduls mehr: Jedes Modul meldet seine Abschnitte `Atlas.UI.<Modul>.SettingsSection` an; ohne Modul fehlen seine Einstellungen im Optionsdialog.

## Summen

Stand der Summen: 6364e487, vor den Units von #1454/#1455.

| Package | Units | Zeilen |
|---|---:|---:|
| `Atlas.IDE.Base` | 448 | 224 327 |
| `Atlas.IDE.Debugger` | 47 | 23 568 |
| `Atlas.IDE.Tracker` | 63 | 39 536 |
| `Atlas.IDE.Welcome` | 63 | 40 104 |
| `Atlas.IDE.Analysis` | 21 | 11 819 |
| `Atlas.IDE.Designer` | 5 | 3 546 |
| `Atlas.IDE.Search` | 23 | 13 141 |
| `Atlas.IDE.Rules` | 7 | 3 152 |
| `Atlas.IDE.Tests` | 8 | 3 377 |
| `Atlas.IDE.Build` | 31 | 12 195 |
| `Atlas.IDE.Bookmarks` | 14 | 7 166 |
| zusammen | 730 | 381 931 |

## Atlas.IDE.Base

| Unit | Datei | Begründung |
|---|---|---|
| `Atlas.Core.Build.CheckOnSave` | `Core/Build/Atlas.Core.Build.CheckOnSave.pas` | Compilermeldungen und Prüfen nach dem Speichern bleiben im Kern (ADR 0017) |
| `Atlas.Core.Build.Events` | `Core/Build/Atlas.Core.Build.Events.pas` | Compile-Ereignisse (#527), Quelle für Compilermeldungen und Prüfen nach dem Speichern |
| `Atlas.Core.Build.IdleGate` | `Core/Build/Atlas.Core.Build.IdleGate.pas` | Warten, bis kein Compile läuft; Diagnose-Zeitmessung (Base), #1455 |
| `Atlas.Core.Build.Messages` | `Core/Build/Atlas.Core.Build.Messages.pas` | Compilermeldungen und Prüfen nach dem Speichern bleiben im Kern (ADR 0017) |
| `Atlas.Core.Build.Requests` | `Core/Build/Atlas.Core.Build.Requests.pas` | Daten der Builds auf Auftrag für Läufer, Eingang der KI-Assistenten und Vertrag (#1888) |
| `Atlas.Core.Build.OpenBuildSettings` | `Core/Build/Atlas.Core.Build.OpenBuildSettings.pas` | Werte der Einstellungen „Bauen beim Öffnen“ für Einstellungen und Optionsdialog, #1455 |
| `Atlas.Core.Build.Pipeline` | `Core/Build/Atlas.Core.Build.Pipeline.pas` | Was Base der Build-Pipeline gibt (Compilermeldungen, Bewertung) über die Registry, #1455 |
| `Atlas.Core.Build.PipelineSettings` | `Core/Build/Atlas.Core.Build.PipelineSettings.pas` | Werte der Einstellungen von Prüfung vor dem Kompilieren und Release-Wächter für Einstellungen und Optionsdialog, #1455 |
| `Atlas.Core.Build.Target` | `Core/Build/Atlas.Core.Build.Target.pas` | Konfiguration und Symbole für den Server ({$IFDEF}-Zweige, #615) |
| `Atlas.Core.Build.Verdict` | `Core/Build/Atlas.Core.Build.Verdict.pas` | Bewertung als Typen und `IAtlasBuildVerdictListener`; Benachrichtigungszentrale (Base) und Module lesen sie, #1455 |
| `Atlas.Core.CiBuild.Contract` | `Core/CiBuild/Atlas.Core.CiBuild.Contract.pas` | CI-Stand als Daten (Lauf, Job, Fehler); Projektzusammenfassung, Willkommensseite und Modul Tracker lesen ihn, #1455 |
| `Atlas.Core.Commands.KeyConflicts` | `Core/Commands/Atlas.Core.Commands.KeyConflicts.pas` | Ordner `Core/Commands` |
| `Atlas.Core.Commands.KeyMap` | `Core/Commands/Atlas.Core.Commands.KeyMap.pas` | Ordner `Core/Commands` |
| `Atlas.Core.Commands.KeyStroke` | `Core/Commands/Atlas.Core.Commands.KeyStroke.pas` | Ordner `Core/Commands` |
| `Atlas.Core.Commands.MenuSlots` | `Core/Commands/Atlas.Core.Commands.MenuSlots.pas` | Ordner `Core/Commands` |
| `Atlas.Core.Commands.ProjectSelection` | `Core/Commands/Atlas.Core.Commands.ProjectSelection.pas` | Ordner `Core/Commands` |
| `Atlas.Core.Commands.Palette` | `Core/Commands/Atlas.Core.Commands.Palette.pas` | Ordner `Core/Commands` |
| `Atlas.Core.Commands.SettingsPalette` | `Core/Commands/Atlas.Core.Commands.SettingsPalette.pas` | Ordner `Core/Commands`; Einstellungen mit @ in der Befehlspalette (#1884) |
| `Atlas.Core.Commands.QuickOpen` | `Core/Commands/Atlas.Core.Commands.QuickOpen.pas` | Ordner `Core/Commands` |
| `Atlas.Core.Commands.ShortcutTips` | `Core/Commands/Atlas.Core.Commands.ShortcutTips.pas` | Ordner `Core/Commands` |
| `Atlas.Core.Commands.Tips` | `Core/Commands/Atlas.Core.Commands.Tips.pas` | Ordner `Core/Commands` |
| `Atlas.Core.Commands.Usage` | `Core/Commands/Atlas.Core.Commands.Usage.pas` | Ordner `Core/Commands` |
| `Atlas.Core.Completion.Composite` | `Core/Completion/Atlas.Core.Completion.Composite.pas` | Ordner `Core/Completion` |
| `Atlas.Core.Completion.Contract` | `Core/Completion/Atlas.Core.Completion.Contract.pas` | Ordner `Core/Completion` |
| `Atlas.Core.Completion.Controller` | `Core/Completion/Atlas.Core.Completion.Controller.pas` | Ordner `Core/Completion` |
| `Atlas.Core.Completion.Favorites` | `Core/Completion/Atlas.Core.Completion.Favorites.pas` | Ordner `Core/Completion` |
| `Atlas.Core.Completion.Internals.Async` | `Core/Completion/Internals/Atlas.Core.Completion.Internals.Async.pas` | Ordner `Core/Completion/Internals` |
| `Atlas.Core.Completion.LiveTemplates` | `Core/Completion/Atlas.Core.Completion.LiveTemplates.pas` | Ordner `Core/Completion` |
| `Atlas.Core.Completion.Matching` | `Core/Completion/Atlas.Core.Completion.Matching.pas` | Ordner `Core/Completion` |
| `Atlas.Core.Completion.Parentheses` | `Core/Completion/Atlas.Core.Completion.Parentheses.pas` | Ordner `Core/Completion` |
| `Atlas.Core.Completion.Placeholders` | `Core/Completion/Atlas.Core.Completion.Placeholders.pas` | Ordner `Core/Completion` |
| `Atlas.Core.Completion.Presentation` | `Core/Completion/Atlas.Core.Completion.Presentation.pas` | Ordner `Core/Completion` |
| `Atlas.Core.Completion.Preview` | `Core/Completion/Atlas.Core.Completion.Preview.pas` | Ordner `Core/Completion` |
| `Atlas.Core.Completion.Providers.Expression` | `Core/Completion/Providers/Atlas.Core.Completion.Providers.Expression.pas` | Ordner `Core/Completion/Providers` |
| `Atlas.Core.Completion.Providers.Fixed` | `Core/Completion/Providers/Atlas.Core.Completion.Providers.Fixed.pas` | Ordner `Core/Completion/Providers` |
| `Atlas.Core.Completion.Providers.Server` | `Core/Completion/Providers/Atlas.Core.Completion.Providers.Server.pas` | Ordner `Core/Completion/Providers` |
| `Atlas.Core.Completion.Providers.Snippets` | `Core/Completion/Providers/Atlas.Core.Completion.Providers.Snippets.pas` | Ordner `Core/Completion/Providers` |
| `Atlas.Core.Completion.Providers.XmlDoc` | `Core/Completion/Providers/Atlas.Core.Completion.Providers.XmlDoc.pas` | Ordner `Core/Completion/Providers` |
| `Atlas.Core.Completion.Ranking` | `Core/Completion/Atlas.Core.Completion.Ranking.pas` | Ordner `Core/Completion` |
| `Atlas.Core.Completion.ServerPlaceholders` | `Core/Completion/Atlas.Core.Completion.ServerPlaceholders.pas` | Ordner `Core/Completion` |
| `Atlas.Core.Completion.Sets` | `Core/Completion/Atlas.Core.Completion.Sets.pas` | Ordner `Core/Completion` |
| `Atlas.Core.Completion.SnippetCatalog` | `Core/Completion/Atlas.Core.Completion.SnippetCatalog.pas` | Ordner `Core/Completion` |
| `Atlas.Core.Completion.Snippets` | `Core/Completion/Atlas.Core.Completion.Snippets.pas` | Ordner `Core/Completion` |
| `Atlas.Core.Completion.Usage` | `Core/Completion/Atlas.Core.Completion.Usage.pas` | Ordner `Core/Completion` |
| `Atlas.Core.Completion.Width` | `Core/Completion/Atlas.Core.Completion.Width.pas` | Ordner `Core/Completion` |
| `Atlas.Core.Completion.Word` | `Core/Completion/Atlas.Core.Completion.Word.pas` | Ordner `Core/Completion` |
| `Atlas.Core.Diagnostics.BugReport` | `Core/Diagnostics/Atlas.Core.Diagnostics.BugReport.pas` | Ordner `Core/Diagnostics` |
| `Atlas.Core.Diagnostics.Export` | `Core/Diagnostics/Atlas.Core.Diagnostics.Export.pas` | Ordner `Core/Diagnostics` |
| `Atlas.Core.Diagnostics.FeatureTable` | `Core/Diagnostics/Atlas.Core.Diagnostics.FeatureTable.pas` | Ordner `Core/Diagnostics` |
| `Atlas.Core.Diagnostics.Guard` | `Core/Diagnostics/Atlas.Core.Diagnostics.Guard.pas` | Ordner `Core/Diagnostics` |
| `Atlas.Core.Diagnostics.LogRedaction` | `Core/Diagnostics/Atlas.Core.Diagnostics.LogRedaction.pas` | Ordner `Core/Diagnostics` |
| `Atlas.Core.Diagnostics.Hangs` | `Core/Diagnostics/Atlas.Core.Diagnostics.Hangs.pas` | Ordner `Core/Diagnostics` |
| `Atlas.Core.Diagnostics.MainThread` | `Core/Diagnostics/Atlas.Core.Diagnostics.MainThread.pas` | Ordner `Core/Diagnostics` |
| `Atlas.Core.Diagnostics.ModuleHosting` | `Core/Diagnostics/Atlas.Core.Diagnostics.ModuleHosting.pas` | Module und ihre Teile in der Feature-Tabelle, #1455 |
| `Atlas.Core.Diagnostics.Package` | `Core/Diagnostics/Atlas.Core.Diagnostics.Package.pas` | Ordner `Core/Diagnostics` |
| `Atlas.Core.Diagnostics.PluginReport` | `Core/Diagnostics/Atlas.Core.Diagnostics.PluginReport.pas` | Ordner `Core/Diagnostics` |
| `Atlas.Core.Diagnostics.PluginTimings` | `Core/Diagnostics/Atlas.Core.Diagnostics.PluginTimings.pas` | Ordner `Core/Diagnostics` |
| `Atlas.Core.Diagnostics.Processes` | `Core/Diagnostics/Atlas.Core.Diagnostics.Processes.pas` | Ordner `Core/Diagnostics` |
| `Atlas.Core.Diagnostics.Edition` | `Core/Diagnostics/Atlas.Core.Diagnostics.Edition.pas` | Ordner `Core/Diagnostics` |
| `Atlas.Core.Diagnostics.SafeMode` | `Core/Diagnostics/Atlas.Core.Diagnostics.SafeMode.pas` | Ordner `Core/Diagnostics` |
| `Atlas.Core.Diagnostics.ServerPackage` | `Core/Diagnostics/Atlas.Core.Diagnostics.ServerPackage.pas` | Ordner `Core/Diagnostics` |
| `Atlas.Core.Diagnostics.Shutdown` | `Core/Diagnostics/Atlas.Core.Diagnostics.Shutdown.pas` | Ordner `Core/Diagnostics` |
| `Atlas.Core.Diagnostics.StackRing` | `Core/Diagnostics/Atlas.Core.Diagnostics.StackRing.pas` | Ordner `Core/Diagnostics` |
| `Atlas.Core.Diagnostics.StartTimes` | `Core/Diagnostics/Atlas.Core.Diagnostics.StartTimes.pas` | Ordner `Core/Diagnostics` |
| `Atlas.Core.Diagnostics.Teardown` | `Core/Diagnostics/Atlas.Core.Diagnostics.Teardown.pas` | Ordner `Core/Diagnostics` |
| `Atlas.Core.Diagnostics.ExitWatch` | `Core/Diagnostics/Atlas.Core.Diagnostics.ExitWatch.pas` | Ordner `Core/Diagnostics` |
| `Atlas.Core.Diagnostics.ThreadList` | `Core/Diagnostics/Atlas.Core.Diagnostics.ThreadList.pas` | Ordner `Core/Diagnostics` |
| `Atlas.Core.Diagnostics.TimeLimit` | `Core/Diagnostics/Atlas.Core.Diagnostics.TimeLimit.pas` | Ordner `Core/Diagnostics` |
| `Atlas.Core.Diagnostics.Timing` | `Core/Diagnostics/Atlas.Core.Diagnostics.Timing.pas` | Ordner `Core/Diagnostics` |
| `Atlas.Core.Dock.Plan` | `Core/Dock/Atlas.Core.Dock.Plan.pas` | Ordner `Core/Dock` |
| `Atlas.Core.Documentation.Contract` | `Core/Documentation/Atlas.Core.Documentation.Contract.pas` | Ordner `Core/Documentation` |
| `Atlas.Core.Documentation.Layout` | `Core/Documentation/Atlas.Core.Documentation.Layout.pas` | Ordner `Core/Documentation` |
| `Atlas.Core.Documentation.Typeset` | `Core/Documentation/Atlas.Core.Documentation.Typeset.pas` | Ordner `Core/Documentation` |
| `Atlas.Core.Editor.BlockComment` | `Core/Editor/Atlas.Core.Editor.BlockComment.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.ChangeSignature` | `Core/Editor/Atlas.Core.Editor.ChangeSignature.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.ClassExtraction` | `Core/Editor/Atlas.Core.Editor.ClassExtraction.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.CloseRules` | `Core/Editor/Atlas.Core.Editor.CloseRules.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.CodeInsightKeys` | `Core/Editor/Atlas.Core.Editor.CodeInsightKeys.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.CommentContinuation` | `Core/Editor/Atlas.Core.Editor.CommentContinuation.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.Conditionals` | `Core/Editor/Atlas.Core.Editor.Conditionals.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.DisableWarning` | `Core/Editor/Atlas.Core.Editor.DisableWarning.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.Elements` | `Core/Editor/Atlas.Core.Editor.Elements.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.ExitPoints` | `Core/Editor/Atlas.Core.Editor.ExitPoints.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.ExpressionType` | `Core/Editor/Atlas.Core.Editor.ExpressionType.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.FormatLog` | `Core/Editor/Atlas.Core.Editor.FormatLog.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.Guides` | `Core/Editor/Atlas.Core.Editor.Guides.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.GutterColumn` | `Core/Editor/Atlas.Core.Editor.GutterColumn.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.Hide` | `Core/Editor/Atlas.Core.Editor.Hide.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.LineAnchor` | `Core/Editor/Atlas.Core.Editor.LineAnchor.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.LineChanges` | `Core/Editor/Atlas.Core.Editor.LineChanges.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.LineTracking` | `Core/Editor/Atlas.Core.Editor.LineTracking.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.LineMove` | `Core/Editor/Atlas.Core.Editor.LineMove.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.LineTail` | `Core/Editor/Atlas.Core.Editor.LineTail.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.LinkedEditing` | `Core/Editor/Atlas.Core.Editor.LinkedEditing.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.Match` | `Core/Editor/Atlas.Core.Editor.Match.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.MethodPlacement` | `Core/Editor/Atlas.Core.Editor.MethodPlacement.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.RegionFolds` | `Core/Editor/Atlas.Core.Editor.RegionFolds.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.MethodToggle` | `Core/Editor/Atlas.Core.Editor.MethodToggle.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.LensAsk` | `Core/Editor/Atlas.Core.Editor.LensAsk.pas` | Ordner `Core/Editor`; ausstehende Frage einer Code Lens im Hintergrund, Antwort nur für die jüngste Frage |
| `Atlas.Core.Editor.Metrics` | `Core/Editor/Atlas.Core.Editor.Metrics.pas` | Ordner `Core/Editor`; Antwort von `atlas.server.metrics` für Statusleiste, Metrikbericht und Metrik-Lens (#1756) |
| `Atlas.Core.Editor.CrumbCard` | `Core/Editor/Atlas.Core.Editor.CrumbCard.pas` | Ordner `Core/Editor`; Kennzahlen-Karte der Brotkrumen aus `Core.Editor.Metrics` (Outline → Editor wäre ein Feature-Zyklus) |
| `Atlas.Core.Editor.LearnedSuggestions` | `Core/Editor/Atlas.Core.Editor.LearnedSuggestions.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.LearnedUsage` | `Core/Editor/Atlas.Core.Editor.LearnedUsage.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.MouseButtons` | `Core/Editor/Atlas.Core.Editor.MouseButtons.pas` | Ordner `Core/Editor`; Maustasten Zurück/Vor → Richtung im Verlauf (#1889) |
| `Atlas.Core.Editor.Minimap` | `Core/Editor/Atlas.Core.Editor.Minimap.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.MissingUnit` | `Core/Editor/Atlas.Core.Editor.MissingUnit.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.MultiCursor` | `Core/Editor/Atlas.Core.Editor.MultiCursor.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.NavHistory` | `Core/Editor/Atlas.Core.Editor.NavHistory.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.NewLine` | `Core/Editor/Atlas.Core.Editor.NewLine.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.Overview` | `Core/Editor/Atlas.Core.Editor.Overview.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.Pairs` | `Core/Editor/Atlas.Core.Editor.Pairs.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.PatternContinuation` | `Core/Editor/Atlas.Core.Editor.PatternContinuation.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.Peek` | `Core/Editor/Atlas.Core.Editor.Peek.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.Reassigned` | `Core/Editor/Atlas.Core.Editor.Reassigned.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.Recursion` | `Core/Editor/Atlas.Core.Editor.Recursion.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.RoutineNesting` | `Core/Editor/Atlas.Core.Editor.RoutineNesting.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.SafeDelete` | `Core/Editor/Atlas.Core.Editor.SafeDelete.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.Selection` | `Core/Editor/Atlas.Core.Editor.Selection.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.SelectionMatches` | `Core/Editor/Atlas.Core.Editor.SelectionMatches.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.SlashTrigger` | `Core/Editor/Atlas.Core.Editor.SlashTrigger.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.SmartIndent` | `Core/Editor/Atlas.Core.Editor.SmartIndent.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.SmartPaste` | `Core/Editor/Atlas.Core.Editor.SmartPaste.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.SnapshotPolicy` | `Core/Editor/Atlas.Core.Editor.SnapshotPolicy.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.StatementCompletion` | `Core/Editor/Atlas.Core.Editor.StatementCompletion.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.TestUnit` | `Core/Editor/Atlas.Core.Editor.TestUnit.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.Unwrap` | `Core/Editor/Atlas.Core.Editor.Unwrap.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.WorkspacePlan` | `Core/Editor/Atlas.Core.Editor.WorkspacePlan.pas` | Ordner `Core/Editor` |
| `Atlas.Core.Editor.WrapSelection` | `Core/Editor/Atlas.Core.Editor.WrapSelection.pas` | Ordner `Core/Editor` |
| `Atlas.Core.EditorToolbar.Glyphs` | `Core/EditorToolbar/Atlas.Core.EditorToolbar.Glyphs.pas` | Ordner `Core/EditorToolbar` |
| `Atlas.Core.EditorToolbar.Icons` | `Core/EditorToolbar/Atlas.Core.EditorToolbar.Icons.pas` | Ordner `Core/EditorToolbar` |
| `Atlas.Core.EditorToolbar.Layout` | `Core/EditorToolbar/Atlas.Core.EditorToolbar.Layout.pas` | Ordner `Core/EditorToolbar` |
| `Atlas.Core.EditorToolbar.ReturnPoint` | `Core/EditorToolbar/Atlas.Core.EditorToolbar.ReturnPoint.pas` | Ordner `Core/EditorToolbar` |
| `Atlas.Core.EditorToolbar.Sections` | `Core/EditorToolbar/Atlas.Core.EditorToolbar.Sections.pas` | Ordner `Core/EditorToolbar` |
| `Atlas.Core.Files.Adapters.FolderWatcher` | `Core/Files/Atlas.Core.Files.Adapters.FolderWatcher.pas` | Ordner `Core/Files` |
| `Atlas.Core.Files.Contract` | `Core/Files/Atlas.Core.Files.Contract.pas` | Ordner `Core/Files` |
| `Atlas.Core.Files.DataFile` | `Core/Files/Atlas.Core.Files.DataFile.pas` | Ordner `Core/Files` |
| `Atlas.Core.Files.ProcessLeftovers` | `Core/Files/Atlas.Core.Files.ProcessLeftovers.pas` | Ordner `Core/Files` |
| `Atlas.Core.Files.EncodingDefault` | `Core/Files/Atlas.Core.Files.EncodingDefault.pas` | Ordner `Core/Files` |
| `Atlas.Core.Files.ExternalChanges` | `Core/Files/Atlas.Core.Files.ExternalChanges.pas` | Ordner `Core/Files` |
| `Atlas.Core.Files.Format` | `Core/Files/Atlas.Core.Files.Format.pas` | Ordner `Core/Files` |
| `Atlas.Core.Files.TextDiff` | `Core/Files/Atlas.Core.Files.TextDiff.pas` | Ordner `Core/Files` |
| `Atlas.Core.Files.TextFile` | `Core/Files/Atlas.Core.Files.TextFile.pas` | Ordner `Core/Files` |
| `Atlas.Core.Files.WatchedChanges` | `Core/Files/Atlas.Core.Files.WatchedChanges.pas` | Ordner `Core/Files` |
| `Atlas.Core.Forms.Changes` | `Core/Forms/Atlas.Core.Forms.Changes.pas` | Ordner `Core/Forms` |
| `Atlas.Core.Forms.Text` | `Core/Forms/Atlas.Core.Forms.Text.pas` | Ordner `Core/Forms` |
| `Atlas.Core.Generate.Contract` | `Core/Generate/Atlas.Core.Generate.Contract.pas` | Ordner `Core/Generate` |
| `Atlas.Core.Generate.FileTemplates` | `Core/Generate/Atlas.Core.Generate.FileTemplates.pas` | Ordner `Core/Generate` |
| `Atlas.Core.Generate.Gallery` | `Core/Generate/Atlas.Core.Generate.Gallery.pas` | Ordner `Core/Generate`: Assistenten der Objektgalerie, #1821 |
| `Atlas.Core.Generate.Choice` | `Core/Generate/Atlas.Core.Generate.Choice.pas` | Ordner `Core/Generate`: Auswahl mit Suchfeld, #1821 |
| `Atlas.Core.Generate.Menu` | `Core/Generate/Atlas.Core.Generate.Menu.pas` | Ordner `Core/Generate` |
| `Atlas.Core.Generate.Protocol` | `Core/Generate/Atlas.Core.Generate.Protocol.pas` | Ordner `Core/Generate` |
| `Atlas.Core.Hover.Contract` | `Core/Hover/Atlas.Core.Hover.Contract.pas` | Ordner `Core/Hover` |
| `Atlas.Core.Hover.DebugValue` | `Core/Hover/Atlas.Core.Hover.DebugValue.pas` | Ordner `Core/Hover` |
| `Atlas.Core.Hover.Declaration` | `Core/Hover/Atlas.Core.Hover.Declaration.pas` | Ordner `Core/Hover`; Typ aus der Hover-Deklaration, bis #1455 im Debugger-Kern |
| `Atlas.Core.Hover.History` | `Core/Hover/Atlas.Core.Hover.History.pas` | Ordner `Core/Hover` |
| `Atlas.Core.Hover.Items` | `Core/Hover/Atlas.Core.Hover.Items.pas` | Ordner `Core/Hover`; Bausteine, Klickflächen und Rollbereich des Hover-Satzes (#1841) |
| `Atlas.Core.Hover.Layout` | `Core/Hover/Atlas.Core.Hover.Layout.pas` | Ordner `Core/Hover` |
| `Atlas.Core.Hover.Texts` | `Core/Hover/Atlas.Core.Hover.Texts.pas` | Ordner `Core/Hover` |
| `Atlas.Core.InlayHints.Store` | `Core/InlayHints/Atlas.Core.InlayHints.Store.pas` | Ordner `Core/InlayHints` |
| `Atlas.Core.Localization.Language` | `Core/Localization/Atlas.Core.Localization.Language.pas` | Sprache der Plugin-Texte für Core und UI, Texttabellen der Units (#1458) |
| `Atlas.Core.Lsp.AccessChains` | `Core/Lsp/Atlas.Core.Lsp.AccessChains.pas` | Ordner `Core/Lsp` |
| `Atlas.Core.Lsp.Adapters.ServerProcess` | `Core/Lsp/Atlas.Core.Lsp.Adapters.ServerProcess.pas` | Ordner `Core/Lsp` |
| `Atlas.Core.Lsp.Client` | `Core/Lsp/Atlas.Core.Lsp.Client.pas` | Ordner `Core/Lsp` |
| `Atlas.Core.Lsp.BackgroundRequest` | `Core/Lsp/Atlas.Core.Lsp.BackgroundRequest.pas` | Ordner `Core/Lsp` |
| `Atlas.Core.Lsp.Contract` | `Core/Lsp/Atlas.Core.Lsp.Contract.pas` | Ordner `Core/Lsp` |
| `Atlas.Core.Lsp.CrashCases` | `Core/Lsp/Atlas.Core.Lsp.CrashCases.pas` | Ordner `Core/Lsp` |
| `Atlas.Core.Lsp.Crashes` | `Core/Lsp/Atlas.Core.Lsp.Crashes.pas` | Ordner `Core/Lsp` |
| `Atlas.Core.Lsp.DataFlow` | `Core/Lsp/Atlas.Core.Lsp.DataFlow.pas` | Ordner `Core/Lsp` |
| `Atlas.Core.Lsp.Progress` | `Core/Lsp/Atlas.Core.Lsp.Progress.pas` | Ordner `Core/Lsp` |
| `Atlas.Core.Lsp.Session.Json` | `Core/Lsp/Atlas.Core.Lsp.Session.Json.pas` | Ordner `Core/Lsp` |
| `Atlas.Core.Lsp.IdeMembers` | `Core/Lsp/Atlas.Core.Lsp.IdeMembers.pas` | Ordner `Core/Lsp` |
| `Atlas.Core.Lsp.IdeTypes` | `Core/Lsp/Atlas.Core.Lsp.IdeTypes.pas` | Ordner `Core/Lsp` |
| `Atlas.Core.Lsp.Session.Base` | `Core/Lsp/Atlas.Core.Lsp.Session.Base.pas` | Ordner `Core/Lsp` |
| `Atlas.Core.Lsp.Session.Requests` | `Core/Lsp/Atlas.Core.Lsp.Session.Requests.pas` | Ordner `Core/Lsp` |
| `Atlas.Core.Lsp.Session` | `Core/Lsp/Atlas.Core.Lsp.Session.pas` | Ordner `Core/Lsp` |
| `Atlas.Core.Lsp.TextChanges` | `Core/Lsp/Atlas.Core.Lsp.TextChanges.pas` | Ordner `Core/Lsp` |
| `Atlas.Core.Lsp.Uris` | `Core/Lsp/Atlas.Core.Lsp.Uris.pas` | Ordner `Core/Lsp` |
| `Atlas.Core.Lsp.WorkspaceEdits` | `Core/Lsp/Atlas.Core.Lsp.WorkspaceEdits.pas` | Ordner `Core/Lsp` |
| `Atlas.Core.Modules.Answer` | `Core/Modules/Atlas.Core.Modules.Answer.pas` | späte Antwort an ein Modul nur bei offenem Scope (Regel 3), #1455 |
| `Atlas.IDE.Contracts.BuildTools` | `Contracts/Atlas.IDE.Contracts.BuildTools.pas` | Startprofile und Projektaufgaben für andere Module, Vertrag zwischen Modulen, #1455 |
| `Atlas.IDE.Contracts.BuildPipeline` | `Contracts/Atlas.IDE.Contracts.BuildPipeline.pas` | Builds auf Auftrag (Build-Pipeline → Tests, Build-Werkzeuge, Willkommensseite), Vertrag zwischen Modulen, #1455 |
| `Atlas.IDE.Contracts.BuildRequests` | `Contracts/Atlas.IDE.Contracts.BuildRequests.pas` | Vertrag zwischen Modulen: Builds auf Auftrag samt Compilermeldungen für den Eingang der KI-Assistenten (#1888) |
| `Atlas.IDE.Contracts.Help` | `Contracts/Atlas.IDE.Contracts.Help.pas` | Hilfe zum Element (Base → Hilfe, #1886), Vertrag zwischen Base und Modul |
| `Atlas.IDE.Contracts.WelcomeTiles` | `Contracts/Atlas.IDE.Contracts.WelcomeTiles.pas` | Kacheln anderer Module auf der Willkommensseite, Board und Projekte der Seite (Tracker ↔ Willkommensseite), Vertrag zwischen Modulen, #1455 |
| `Atlas.IDE.Contracts.VersionControl` | `Contracts/Atlas.IDE.Contracts.VersionControl.pas` | Vertrag zwischen Modulen: Dienst und Dialoge der Versionsverwaltung, Zugang TAtlasIdeVcs mit Null-Objekt ohne Modul (#1891) |
| `Atlas.IDE.Contracts.LineChanges` | `Contracts/Atlas.IDE.Contracts.LineChanges.pas` | Vertrag Änderungsmarken und Zeilenhistorie (#1905) |
| `Atlas.IDE.Contracts.GhostSuggestions` | `Contracts/Atlas.IDE.Contracts.GhostSuggestions.pas` | Vertrag für Anbieter von Schattentext-Vorschlägen nach Enter (gelernte Vorschläge, später weitere), #1890 |
| `Atlas.IDE.Contracts.MouseHistory` | `Contracts/Atlas.IDE.Contracts.MouseHistory.pas` | Vertrag Fenster mit eigenem Verlauf für die Maustasten Zurück/Vor (#1889) |
| `Atlas.IDE.Contracts.Tests` | `Contracts/Atlas.IDE.Contracts.Tests.pas` | Testprojekte ausführen, Tests debuggen und finden, Ende eines Laufs; für andere Module, Vertrag zwischen Modulen, #1455 |
| `Atlas.IDE.Contracts.DebugReport` | `Contracts/Atlas.IDE.Contracts.DebugReport.pas` | Debug-Notiz und Exception-Verlauf für „An Issue anhängen …“ (Debugger → Tracker), Vertrag zwischen Modulen, #1455 |
| `Atlas.IDE.Contracts.Rules` | `Contracts/Atlas.IDE.Contracts.Rules.pas` | Baseline aktualisieren (Prüfregeln → Willkommensseite) und Regel-Aktionen am Befund (Base → Prüfregeln, #1755), Vertrag zwischen Modulen, #1455 |
| `Atlas.Core.Modules.Contract` | `Core/Modules/Atlas.Core.Modules.Contract.pas` | Allgemeine Verträge (Modul, Registry, Scope, Beiträge), #1455 |
| `Atlas.Core.Modules.Contributions` | `Core/Modules/Atlas.Core.Modules.Contributions.pas` | Beiträge der Module einsammeln, #1455 |
| `Atlas.Core.Modules.FeatureParts` | `Core/Modules/Atlas.Core.Modules.FeatureParts.pas` | Teile eines Moduls für die Feature-Tabelle, #1455 |
| `Atlas.Core.Modules.Handshake` | `Core/Modules/Atlas.Core.Modules.Handshake.pas` | Vertragsversion von Base (Regel 7), #1455 |
| `Atlas.Core.Modules.KnownPackages` | `Core/Modules/Atlas.Core.Modules.KnownPackages.pas` | Module unter „Known Packages“ prüfen (Meldung 05.11.2026) |
| `Atlas.Core.Modules.Registration` | `Core/Modules/Atlas.Core.Modules.Registration.pas` | Ordner `Core/Modules`, #1455 |
| `Atlas.Core.Modules.Registry` | `Core/Modules/Atlas.Core.Modules.Registry.pas` | Registry der Module (Regel 1), #1455 |
| `Atlas.Core.Modules.Watch` | `Core/Modules/Atlas.Core.Modules.Watch.pas` | Liste bereitgestellter Objekte, folgt der Registry, #1455 |
| `Atlas.Core.Notifications.Build` | `Core/Notifications/Atlas.Core.Notifications.Build.pas` | Ordner `Core/Notifications` |
| `Atlas.Core.Notifications.Center` | `Core/Notifications/Atlas.Core.Notifications.Center.pas` | Ordner `Core/Notifications` |
| `Atlas.Core.Notifications.Contract` | `Core/Notifications/Atlas.Core.Notifications.Contract.pas` | Ordner `Core/Notifications` |
| `Atlas.Core.Notifications.Sources` | `Core/Notifications/Atlas.Core.Notifications.Sources.pas` | Ordner `Core/Notifications` |
| `Atlas.Core.Outline.Breadcrumbs` | `Core/Outline/Atlas.Core.Outline.Breadcrumbs.pas` | Ordner `Core/Outline` |
| `Atlas.Core.Outline.Conditionals` | `Core/Outline/Atlas.Core.Outline.Conditionals.pas` | Ordner `Core/Outline` |
| `Atlas.Core.Outline.CrumbMenu` | `Core/Outline/Atlas.Core.Outline.CrumbMenu.pas` | Ordner `Core/Outline` |
| `Atlas.Core.Outline.DeclarationBlocks` | `Core/Outline/Atlas.Core.Outline.DeclarationBlocks.pas` | Ordner `Core/Outline` |
| `Atlas.Core.Outline.Directives` | `Core/Outline/Atlas.Core.Outline.Directives.pas` | Ordner `Core/Outline` |
| `Atlas.Core.Outline.LoadGuard` | `Core/Outline/Atlas.Core.Outline.LoadGuard.pas` | Ordner `Core/Outline` |
| `Atlas.Core.Outline.MemberBlocks` | `Core/Outline/Atlas.Core.Outline.MemberBlocks.pas` | Ordner `Core/Outline` |
| `Atlas.Core.Outline.Model` | `Core/Outline/Atlas.Core.Outline.Model.pas` | Ordner `Core/Outline` |
| `Atlas.Core.Outline.NavigationOption` | `Core/Outline/Atlas.Core.Outline.NavigationOption.pas` | Ordner `Core/Outline` |
| `Atlas.Core.Outline.Overloads` | `Core/Outline/Atlas.Core.Outline.Overloads.pas` | Ordner `Core/Outline` |
| `Atlas.Core.Outline.Interfaces` | `Core/Outline/Atlas.Core.Outline.Interfaces.pas` | Ordner `Core/Outline` |
| `Atlas.Core.Outline.Regions` | `Core/Outline/Atlas.Core.Outline.Regions.pas` | Ordner `Core/Outline` |
| `Atlas.Core.Outline.Statements` | `Core/Outline/Atlas.Core.Outline.Statements.pas` | Ordner `Core/Outline` |
| `Atlas.Core.Outline.SectionEdit` | `Core/Outline/Atlas.Core.Outline.SectionEdit.pas` | Ordner `Core/Outline` |
| `Atlas.Core.Outline.StickyScroll` | `Core/Outline/Atlas.Core.Outline.StickyScroll.pas` | Ordner `Core/Outline` |
| `Atlas.Core.Outline.TypeText` | `Core/Outline/Atlas.Core.Outline.TypeText.pas` | Ordner `Core/Outline` |
| `Atlas.Core.Outline.VisibilitySections` | `Core/Outline/Atlas.Core.Outline.VisibilitySections.pas` | Ordner `Core/Outline` |
| `Atlas.Core.Problems.Colors` | `Core/Problems/Atlas.Core.Problems.Colors.pas` | Ordner `Core/Problems` |
| `Atlas.Core.Problems.Contract` | `Core/Problems/Atlas.Core.Problems.Contract.pas` | Ordner `Core/Problems` |
| `Atlas.Core.Problems.Explanation` | `Core/Problems/Atlas.Core.Problems.Explanation.pas` | Ordner `Core/Problems`: Katalogtext für „Regel erklären“ (#1755) |
| `Atlas.Core.Problems.Findings` | `Core/Problems/Atlas.Core.Problems.Findings.pas` | Ordner `Core/Problems` |
| `Atlas.Core.Problems.ScopeProjects` | `Core/Problems/Atlas.Core.Problems.ScopeProjects.pas` | Ordner `Core/Problems` |
| `Atlas.Core.Problems.FindingsCache` | `Core/Problems/Atlas.Core.Problems.FindingsCache.pas` | Ordner `Core/Problems` |
| `Atlas.Core.Problems.InlineHints` | `Core/Problems/Atlas.Core.Problems.InlineHints.pas` | Ordner `Core/Problems` |
| `Atlas.Core.Problems.Refresh` | `Core/Problems/Atlas.Core.Problems.Refresh.pas` | Ordner `Core/Problems` |
| `Atlas.Core.Problems.Store` | `Core/Problems/Atlas.Core.Problems.Store.pas` | Ordner `Core/Problems` |
| `Atlas.Core.Product.Version` | `Core/Product/Atlas.Core.Product.Version.pas` | Ordner `Core/Product` |
| `Atlas.Core.Projects.Baseline` | `Core/Projects/Atlas.Core.Projects.Baseline.pas` | Stand der Baseline-Datei; Build-Zusammenfassung, Projektverlauf und Modul Prüfregeln lesen ihn, #1455 |
| `Atlas.Core.Projects.Contract` | `Core/Projects/Atlas.Core.Projects.Contract.pas` | Ordner `Core/Projects` |
| `Atlas.Core.Projects.Matching` | `Core/Projects/Atlas.Core.Projects.Matching.pas` | Ordner `Core/Projects` |
| `Atlas.Core.Projects.PathCheck` | `Core/Projects/Atlas.Core.Projects.PathCheck.pas` | Ordner `Core/Projects` |
| `Atlas.Core.Projects.PathCheck.Scan` | `Core/Projects/Atlas.Core.Projects.PathCheck.Scan.pas` | Ordner `Core/Projects` |
| `Atlas.Core.Projects.Recording` | `Core/Projects/Atlas.Core.Projects.Recording.pas` | Build, Versionsverwaltung und Regeltreffer in die Projekt-Zusammenfassung, #1455 |
| `Atlas.Core.Projects.Setup` | `Core/Projects/Atlas.Core.Projects.Setup.pas` | Ordner `Core/Projects` |
| `Atlas.Core.Projects.Summary` | `Core/Projects/Atlas.Core.Projects.Summary.pas` | Ordner `Core/Projects` |
| `Atlas.Core.Projects.Summary.Json` | `Core/Projects/Atlas.Core.Projects.Summary.Json.pas` | Ordner `Core/Projects` |
| `Atlas.Core.Projects.Summary.Sections` | `Core/Projects/Atlas.Core.Projects.Summary.Sections.pas` | Ordner `Core/Projects` |
| `Atlas.Core.Projects.Todos` | `Core/Projects/Atlas.Core.Projects.Todos.pas` | Ordner `Core/Projects` |
| `Atlas.Core.Projects.Trends` | `Core/Projects/Atlas.Core.Projects.Trends.pas` | Ordner `Core/Projects` |
| `Atlas.Core.Projects.UnitRename` | `Core/Projects/Atlas.Core.Projects.UnitRename.pas` | Ordner `Core/Projects` |
| `Atlas.Core.Projects.VersionControl` | `Core/Projects/Atlas.Core.Projects.VersionControl.pas` | Ordner `Core/Projects` |
| `Atlas.Core.Results.CallDiagram` | `Core/Results/Atlas.Core.Results.CallDiagram.pas` | Ordner `Core/Results` |
| `Atlas.Core.Results.CallDiagramTemplate` | `Core/Results/Atlas.Core.Results.CallDiagramTemplate.pas` | Ordner `Core/Results` |
| `Atlas.Core.Results.DataFlow` | `Core/Results/Atlas.Core.Results.DataFlow.pas` | Ordner `Core/Results` |
| `Atlas.Core.Results.Model` | `Core/Results/Atlas.Core.Results.Model.pas` | Ordner `Core/Results` |
| `Atlas.Core.SavedPlaces.Contract` | `Core/SavedPlaces/Atlas.Core.SavedPlaces.Contract.pas` | Gemerkte Stellen als Daten und Quelle (Lesezeichen → Willkommensseite), #1456 |
| `Atlas.Core.Settings.Baseline` | `Core/Settings/Atlas.Core.Settings.Baseline.pas` | Format der Baseline-Datei; Einstellungsdialog und Stand der Datei, #1455 |
| `Atlas.Core.Settings.Catalog` | `Core/Settings/Atlas.Core.Settings.Catalog.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.Choices` | `Core/Settings/Atlas.Core.Settings.Choices.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.Contract` | `Core/Settings/Atlas.Core.Settings.Contract.pas` | Ordner `Core/Settings`; Vertrag für die Einstellungsteile der Module (#1455, Entscheidung 3) |
| `Atlas.Core.Settings.EventBreakNames` | `Core/Settings/Atlas.Core.Settings.EventBreakNames.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.Experimental` | `Core/Settings/Atlas.Core.Settings.Experimental.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.FolderList` | `Core/Settings/Atlas.Core.Settings.FolderList.pas` | Ordnerliste als Einstellungswert; Optionsdialog ohne Debugger, #1455 |
| `Atlas.Core.Settings.Groups` | `Core/Settings/Atlas.Core.Settings.Groups.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.HiddenPlaces` | `Core/Settings/Atlas.Core.Settings.HiddenPlaces.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.History` | `Core/Settings/Atlas.Core.Settings.History.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.NodeScope` | `Core/Settings/Atlas.Core.Settings.NodeScope.pas` | Ordner `Core/Settings`; Knoten je Package in den Optionen (#1903) |
| `Atlas.Core.Settings.Search` | `Core/Settings/Atlas.Core.Settings.Search.pas` | Ordner `Core/Settings`; Suche über die Einstellungen (#1884) |
| `Atlas.Core.Settings.JsonText` | `Core/Settings/Atlas.Core.Settings.JsonText.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.Layers` | `Core/Settings/Atlas.Core.Settings.Layers.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.ModuleSwitches` | `Core/Settings/Atlas.Core.Settings.ModuleSwitches.pas` | Ordner `Core/Settings`; Modul-Schalter (#1454) |
| `Atlas.Core.Settings.OverviewKinds` | `Core/Settings/Atlas.Core.Settings.OverviewKinds.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.PageNames` | `Core/Settings/Atlas.Core.Settings.PageNames.pas` | Englische Seitennamen der Einstellungen, #1458 |
| `Atlas.Core.Settings.Parts` | `Core/Settings/Atlas.Core.Settings.Parts.pas` | Ordner `Core/Settings`; zentrale Stelle der Einstellungsteile (#1455, Entscheidung 3) |
| `Atlas.Core.Settings.Plugin` | `Core/Settings/Atlas.Core.Settings.Plugin.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.Plugin.Store` | `Core/Settings/Atlas.Core.Settings.Plugin.Store.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.Plugin.Bookmarks` | `Core/Settings/Atlas.Core.Settings.Plugin.Bookmarks.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.Plugin.Build` | `Core/Settings/Atlas.Core.Settings.Plugin.Build.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.Plugin.CodeActions` | `Core/Settings/Atlas.Core.Settings.Plugin.CodeActions.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.Plugin.Completion` | `Core/Settings/Atlas.Core.Settings.Plugin.Completion.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.Plugin.Debug` | `Core/Settings/Atlas.Core.Settings.Plugin.Debug.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.Plugin.Editor` | `Core/Settings/Atlas.Core.Settings.Plugin.Editor.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.Plugin.General` | `Core/Settings/Atlas.Core.Settings.Plugin.General.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.Plugin.Highlighting` | `Core/Settings/Atlas.Core.Settings.Plugin.Highlighting.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.Plugin.Issues` | `Core/Settings/Atlas.Core.Settings.Plugin.Issues.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.Plugin.Keys` | `Core/Settings/Atlas.Core.Settings.Plugin.Keys.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.Plugin.Rules` | `Core/Settings/Atlas.Core.Settings.Plugin.Rules.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.Plugin.Snippets` | `Core/Settings/Atlas.Core.Settings.Plugin.Snippets.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.Plugin.VersionControl` | `Core/Settings/Atlas.Core.Settings.Plugin.VersionControl.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.Plugin.Welcome` | `Core/Settings/Atlas.Core.Settings.Plugin.Welcome.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.ProblemsUpdate` | `Core/Settings/Atlas.Core.Settings.ProblemsUpdate.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.PluginSchemaData` | `Core/Settings/Atlas.Core.Settings.PluginSchemaData.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.ProfileData` | `Core/Settings/Atlas.Core.Settings.ProfileData.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.QueryMigration` | `Core/Settings/Atlas.Core.Settings.QueryMigration.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.QuickToggles` | `Core/Settings/Atlas.Core.Settings.QuickToggles.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.Reassigned` | `Core/Settings/Atlas.Core.Settings.Reassigned.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.Renames` | `Core/Settings/Atlas.Core.Settings.Renames.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.RuleChecksNotice` | `Core/Settings/Atlas.Core.Settings.RuleChecksNotice.pas` | Hinweis „Prüfregeln sind aus“, #1454 |
| `Atlas.Core.Settings.Schema` | `Core/Settings/Atlas.Core.Settings.Schema.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.SchemaCheck` | `Core/Settings/Atlas.Core.Settings.SchemaCheck.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.SchemaData` | `Core/Settings/Atlas.Core.Settings.SchemaData.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.Scopes` | `Core/Settings/Atlas.Core.Settings.Scopes.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.StatusBarItems` | `Core/Settings/Atlas.Core.Settings.StatusBarItems.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.StoreValues` | `Core/Settings/Atlas.Core.Settings.StoreValues.pas` | Ordner `Core/Settings`; Werte des zentralen Records nach Schlüssel für die Abschnitte der Module (#1455) |
| `Atlas.Core.Settings.TeamFile` | `Core/Settings/Atlas.Core.Settings.TeamFile.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.ToolbarItems` | `Core/Settings/Atlas.Core.Settings.ToolbarItems.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.Transfer` | `Core/Settings/Atlas.Core.Settings.Transfer.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.Validation` | `Core/Settings/Atlas.Core.Settings.Validation.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Settings.VisualizerKinds` | `Core/Settings/Atlas.Core.Settings.VisualizerKinds.pas` | Ordner `Core/Settings` |
| `Atlas.Core.Setup.Checklist` | `Core/Setup/Atlas.Core.Setup.Checklist.pas` | Ordner `Core/Setup` |
| `Atlas.Core.Signature.CallScanner` | `Core/Signature/Atlas.Core.Signature.CallScanner.pas` | Ordner `Core/Signature` |
| `Atlas.Core.Signature.Contract` | `Core/Signature/Atlas.Core.Signature.Contract.pas` | Ordner `Core/Signature` |
| `Atlas.Core.Signature.Controller` | `Core/Signature/Atlas.Core.Signature.Controller.pas` | Ordner `Core/Signature` |
| `Atlas.Core.Signature.Format` | `Core/Signature/Atlas.Core.Signature.Format.pas` | Ordner `Core/Signature` |
| `Atlas.Core.Signature.Providers.Server` | `Core/Signature/Atlas.Core.Signature.Providers.Server.pas` | Ordner `Core/Signature` |
| `Atlas.Core.StartProfiles.Store` | `Core/StartProfiles/Atlas.Core.StartProfiles.Store.pas` | Lokale Datei der Startoptionen; Base liest und schreibt darin die vorübergehenden Startparameter, #1455 |
| `Atlas.Core.Status.Contract` | `Core/Status/Atlas.Core.Status.Contract.pas` | Ordner `Core/Status` |
| `Atlas.Core.Status.IndexStore` | `Core/Status/Atlas.Core.Status.IndexStore.pas` | Ordner `Core/Status` |
| `Atlas.Core.Status.Lines` | `Core/Status/Atlas.Core.Status.Lines.pas` | Ordner `Core/Status` |
| `Atlas.Core.Status.Registry` | `Core/Status/Atlas.Core.Status.Registry.pas` | Ordner `Core/Status` |
| `Atlas.Core.Status.Server` | `Core/Status/Atlas.Core.Status.Server.pas` | Ordner `Core/Status` |
| `Atlas.Core.StatusBar.Content` | `Core/StatusBar/Atlas.Core.StatusBar.Content.pas` | Ordner `Core/StatusBar` |
| `Atlas.Core.StatusBar.Layout` | `Core/StatusBar/Atlas.Core.StatusBar.Layout.pas` | Ordner `Core/StatusBar` |
| `Atlas.Core.Style.Color` | `Core/Style/Atlas.Core.Style.Color.pas` | Ordner `Core/Style` |
| `Atlas.Core.Style.Palette` | `Core/Style/Atlas.Core.Style.Palette.pas` | Ordner `Core/Style` |
| `Atlas.Core.Style.Scaling` | `Core/Style/Atlas.Core.Style.Scaling.pas` | Ordner `Core/Style` |
| `Atlas.Core.Style.Signal` | `Core/Style/Atlas.Core.Style.Signal.pas` | Ordner `Core/Style` |
| `Atlas.Core.Style.Symbol` | `Core/Style/Atlas.Core.Style.Symbol.pas` | Ordner `Core/Style` |
| `Atlas.Core.Style.Syntax` | `Core/Style/Atlas.Core.Style.Syntax.pas` | Ordner `Core/Style` |
| `Atlas.Core.Style.Wrap` | `Core/Style/Atlas.Core.Style.Wrap.pas` | Ordner `Core/Style` |
| `Atlas.Core.SymbolPath.Model` | `Core/SymbolPath/Atlas.Core.SymbolPath.Model.pas` | Darstellung eines Wegs zwischen Symbolen im Ergebnisfenster von Base (#1117); das Modul Analyse sucht den Weg, #1455 |
| `Atlas.Core.Undo.Adapters.DiskTarget` | `Core/Undo/Atlas.Core.Undo.Adapters.DiskTarget.pas` | Ordner `Core/Undo` |
| `Atlas.Core.Undo.Adapters.FileStore` | `Core/Undo/Atlas.Core.Undo.Adapters.FileStore.pas` | Ordner `Core/Undo` |
| `Atlas.Core.Undo.Contract` | `Core/Undo/Atlas.Core.Undo.Contract.pas` | Ordner `Core/Undo` |
| `Atlas.Core.Undo.Journal` | `Core/Undo/Atlas.Core.Undo.Journal.pas` | Ordner `Core/Undo` |
| `Atlas.Core.Undo.LinePatch` | `Core/Undo/Atlas.Core.Undo.LinePatch.pas` | Ordner `Core/Undo` |
| `Atlas.Core.Undo.Names` | `Core/Undo/Atlas.Core.Undo.Names.pas` | Ordner `Core/Undo` |
| `Atlas.Core.Updates.Adapters.HttpSource` | `Core/Updates/Atlas.Core.Updates.Adapters.HttpSource.pas` | Ordner `Core/Updates` |
| `Atlas.Core.Updates.Check` | `Core/Updates/Atlas.Core.Updates.Check.pas` | Ordner `Core/Updates` |
| `Atlas.Core.Updates.Contract` | `Core/Updates/Atlas.Core.Updates.Contract.pas` | Ordner `Core/Updates` |
| `Atlas.Core.Updates.Install` | `Core/Updates/Atlas.Core.Updates.Install.pas` | Ordner `Core/Updates` |
| `Atlas.Core.VersionControl.Adapters.ProcessRunner` | `Core/VersionControl/Atlas.Core.VersionControl.Adapters.ProcessRunner.pas` | Allgemeiner Prozessläufer (git, svn, Testprogramme des Moduls Tests); einziger Prozessaufruf im Kern (#1891) |
| `Atlas.Core.VersionControl.BranchNames` | `Core/VersionControl/Atlas.Core.VersionControl.BranchNames.pas` | Vertrag und reine Logik der Versionsverwaltung ohne Prozessaufruf (#1891): Daten, Branch-Plan, Pull, Arbeitskopien, Werkzeugsuche; Base, Tracker und Welcome nutzen sie, git und svn ruft nur das Modul auf |
| `Atlas.Core.VersionControl.BranchPlan` | `Core/VersionControl/Atlas.Core.VersionControl.BranchPlan.pas` | Vertrag und reine Logik der Versionsverwaltung ohne Prozessaufruf (#1891): Daten, Branch-Plan, Pull, Arbeitskopien, Werkzeugsuche; Base, Tracker und Welcome nutzen sie, git und svn ruft nur das Modul auf |
| `Atlas.Core.VersionControl.Contract` | `Core/VersionControl/Atlas.Core.VersionControl.Contract.pas` | Vertrag und reine Logik der Versionsverwaltung ohne Prozessaufruf (#1891): Daten, Branch-Plan, Pull, Arbeitskopien, Werkzeugsuche; Base, Tracker und Welcome nutzen sie, git und svn ruft nur das Modul auf |
| `Atlas.Core.VersionControl.Internals.SvnExternals` | `Core/VersionControl/Atlas.Core.VersionControl.Internals.SvnExternals.pas` | Vertrag und reine Logik der Versionsverwaltung ohne Prozessaufruf (#1891): Daten, Branch-Plan, Pull, Arbeitskopien, Werkzeugsuche; Base, Tracker und Welcome nutzen sie, git und svn ruft nur das Modul auf |
| `Atlas.Core.VersionControl.Internals.SvnLayout` | `Core/VersionControl/Atlas.Core.VersionControl.Internals.SvnLayout.pas` | Vertrag und reine Logik der Versionsverwaltung ohne Prozessaufruf (#1891): Daten, Branch-Plan, Pull, Arbeitskopien, Werkzeugsuche; Base, Tracker und Welcome nutzen sie, git und svn ruft nur das Modul auf |
| `Atlas.Core.VersionControl.Internals.Text` | `Core/VersionControl/Atlas.Core.VersionControl.Internals.Text.pas` | Vertrag und reine Logik der Versionsverwaltung ohne Prozessaufruf (#1891): Daten, Branch-Plan, Pull, Arbeitskopien, Werkzeugsuche; Base, Tracker und Welcome nutzen sie, git und svn ruft nur das Modul auf |
| `Atlas.Core.VersionControl.Providers.Null` | `Core/VersionControl/Atlas.Core.VersionControl.Providers.Null.pas` | Vertrag und reine Logik der Versionsverwaltung ohne Prozessaufruf (#1891): Daten, Branch-Plan, Pull, Arbeitskopien, Werkzeugsuche; Base, Tracker und Welcome nutzen sie, git und svn ruft nur das Modul auf |
| `Atlas.Core.VersionControl.Pull` | `Core/VersionControl/Atlas.Core.VersionControl.Pull.pas` | Holen der Arbeitskopie, aus `Atlas.Core.Welcome.QuickActions` für die Willkommensseite und „Arbeitskopien“, #1456 |
| `Atlas.Core.VersionControl.ServerAccess` | `Core/VersionControl/Atlas.Core.VersionControl.ServerAccess.pas` | Vertrag und reine Logik der Versionsverwaltung ohne Prozessaufruf (#1891): Daten, Branch-Plan, Pull, Arbeitskopien, Werkzeugsuche; Base, Tracker und Welcome nutzen sie, git und svn ruft nur das Modul auf |
| `Atlas.Core.VersionControl.ServerCheck` | `Core/VersionControl/Atlas.Core.VersionControl.ServerCheck.pas` | Vertrag und reine Logik der Versionsverwaltung ohne Prozessaufruf (#1891): Daten, Branch-Plan, Pull, Arbeitskopien, Werkzeugsuche; Base, Tracker und Welcome nutzen sie, git und svn ruft nur das Modul auf |
| `Atlas.Core.VersionControl.Switches` | `Core/VersionControl/Atlas.Core.VersionControl.Switches.pas` | Vertrag und reine Logik der Versionsverwaltung ohne Prozessaufruf (#1891): Daten, Branch-Plan, Pull, Arbeitskopien, Werkzeugsuche; Base, Tracker und Welcome nutzen sie, git und svn ruft nur das Modul auf |
| `Atlas.Core.VersionControl.ToolCheck` | `Core/VersionControl/Atlas.Core.VersionControl.ToolCheck.pas` | Vertrag und reine Logik der Versionsverwaltung ohne Prozessaufruf (#1891): Daten, Branch-Plan, Pull, Arbeitskopien, Werkzeugsuche; Base, Tracker und Welcome nutzen sie, git und svn ruft nur das Modul auf |
| `Atlas.Core.VersionControl.Tools` | `Core/VersionControl/Atlas.Core.VersionControl.Tools.pas` | Vertrag und reine Logik der Versionsverwaltung ohne Prozessaufruf (#1891): Daten, Branch-Plan, Pull, Arbeitskopien, Werkzeugsuche; Base, Tracker und Welcome nutzen sie, git und svn ruft nur das Modul auf |
| `Atlas.Core.VersionControl.Worker` | `Core/VersionControl/Atlas.Core.VersionControl.Worker.pas` | Vertrag und reine Logik der Versionsverwaltung ohne Prozessaufruf (#1891): Daten, Branch-Plan, Pull, Arbeitskopien, Werkzeugsuche; Base, Tracker und Welcome nutzen sie, git und svn ruft nur das Modul auf |
| `Atlas.Core.VersionControl.WorkingCopies` | `Core/VersionControl/Atlas.Core.VersionControl.WorkingCopies.pas` | Vertrag und reine Logik der Versionsverwaltung ohne Prozessaufruf (#1891): Daten, Branch-Plan, Pull, Arbeitskopien, Werkzeugsuche; Base, Tracker und Welcome nutzen sie, git und svn ruft nur das Modul auf |
| `Atlas.Core.Versions.Project` | `Core/Versions/Atlas.Core.Versions.Project.pas` | Versionsnummer eines Projekts; Release-Wächter und Modul Tracker lesen sie, #1455 |
| `Atlas.IDE.Build.CheckOnSave` | `IDE/Build/Atlas.IDE.Build.CheckOnSave.pas` | Compilermeldungen und Prüfen nach dem Speichern bleiben im Kern (ADR 0017) |
| `Atlas.IDE.Build.IdleGate` | `IDE/Build/Atlas.IDE.Build.IdleGate.pas` | Warten, bis kein Compile läuft; Diagnose-Zeitmessung (Base), #1455 |
| `Atlas.IDE.Build.LastMessages` | `IDE/Build/Atlas.IDE.Build.LastMessages.pas` | Compilermeldungen des letzten Builds; Modul Prüfregeln liest sie, auch ohne Build-Pipeline, #1455 |
| `Atlas.IDE.Build.MessageView` | `IDE/Build/Atlas.IDE.Build.MessageView.pas` | Compilermeldungen und Prüfen nach dem Speichern bleiben im Kern (ADR 0017) |
| `Atlas.IDE.Build.Notifier` | `IDE/Build/Atlas.IDE.Build.Notifier.pas` | Compile-Ereignisse (#527), Quelle für Compilermeldungen und Prüfen nach dem Speichern |
| `Atlas.IDE.Build.Target` | `IDE/Build/Atlas.IDE.Build.Target.pas` | Build-Auswahl für den Server; Probleme und Projekt-Einstellungen (Base), #1455 |
| `Atlas.IDE.CodeInsight.Composition` | `IDE/CodeInsight/Atlas.IDE.CodeInsight.Composition.pas` | Ordner `IDE/CodeInsight` |
| `Atlas.IDE.CodeInsight.Composition.Adapters` | `IDE/CodeInsight/Atlas.IDE.CodeInsight.Composition.Adapters.pas` | Ordner `IDE/CodeInsight` |
| `Atlas.IDE.CodeInsight.Composition.Appearance` | `IDE/CodeInsight/Atlas.IDE.CodeInsight.Composition.Appearance.pas` | Ordner `IDE/CodeInsight` |
| `Atlas.IDE.CodeInsight.Composition.Background` | `IDE/CodeInsight/Atlas.IDE.CodeInsight.Composition.Background.pas` | Ordner `IDE/CodeInsight` |
| `Atlas.IDE.CodeInsight.Composition.Build` | `IDE/CodeInsight/Atlas.IDE.CodeInsight.Composition.Build.pas` | Ordner `IDE/CodeInsight` |
| `Atlas.IDE.CodeInsight.Composition.Drawing` | `IDE/CodeInsight/Atlas.IDE.CodeInsight.Composition.Drawing.pas` | Ordner `IDE/CodeInsight` |
| `Atlas.IDE.CodeInsight.Composition.Editing` | `IDE/CodeInsight/Atlas.IDE.CodeInsight.Composition.Editing.pas` | Ordner `IDE/CodeInsight` |
| `Atlas.IDE.CodeInsight.Composition.EditorBars` | `IDE/CodeInsight/Atlas.IDE.CodeInsight.Composition.EditorBars.pas` | Ordner `IDE/CodeInsight` |
| `Atlas.IDE.CodeInsight.Composition.Features` | `IDE/CodeInsight/Atlas.IDE.CodeInsight.Composition.Features.pas` | Ordner `IDE/CodeInsight` |
| `Atlas.IDE.CodeInsight.Composition.Keys` | `IDE/CodeInsight/Atlas.IDE.CodeInsight.Composition.Keys.pas` | Ordner `IDE/CodeInsight` |
| `Atlas.IDE.CodeInsight.Composition.Leftovers` | `IDE/CodeInsight/Atlas.IDE.CodeInsight.Composition.Leftovers.pas` | Ordner `IDE/CodeInsight` |
| `Atlas.IDE.CodeInsight.Composition.Navigation` | `IDE/CodeInsight/Atlas.IDE.CodeInsight.Composition.Navigation.pas` | Ordner `IDE/CodeInsight` |
| `Atlas.IDE.CodeInsight.Composition.Palette` | `IDE/CodeInsight/Atlas.IDE.CodeInsight.Composition.Palette.pas` | Ordner `IDE/CodeInsight` |
| `Atlas.IDE.CodeInsight.Composition.PaletteEditing` | `IDE/CodeInsight/Atlas.IDE.CodeInsight.Composition.PaletteEditing.pas` | Ordner `IDE/CodeInsight` |
| `Atlas.IDE.CodeInsight.Composition.PaletteNavigation` | `IDE/CodeInsight/Atlas.IDE.CodeInsight.Composition.PaletteNavigation.pas` | Ordner `IDE/CodeInsight` |
| `Atlas.IDE.CodeInsight.Composition.Services` | `IDE/CodeInsight/Atlas.IDE.CodeInsight.Composition.Services.pas` | Ordner `IDE/CodeInsight` |
| `Atlas.IDE.CodeInsight.Composition.Session` | `IDE/CodeInsight/Atlas.IDE.CodeInsight.Composition.Session.pas` | Ordner `IDE/CodeInsight` |
| `Atlas.IDE.CodeInsight.Composition.Settings` | `IDE/CodeInsight/Atlas.IDE.CodeInsight.Composition.Settings.pas` | Ordner `IDE/CodeInsight` |
| `Atlas.IDE.CodeInsight.Composition.Startup` | `IDE/CodeInsight/Atlas.IDE.CodeInsight.Composition.Startup.pas` | Ordner `IDE/CodeInsight` |
| `Atlas.IDE.CodeInsight.Composition.Status` | `IDE/CodeInsight/Atlas.IDE.CodeInsight.Composition.Status.pas` | Ordner `IDE/CodeInsight` |
| `Atlas.IDE.CodeInsight.Composition.Tools` | `IDE/CodeInsight/Atlas.IDE.CodeInsight.Composition.Tools.pas` | Ordner `IDE/CodeInsight` |
| `Atlas.IDE.CodeInsight.Manager` | `IDE/CodeInsight/Atlas.IDE.CodeInsight.Manager.pas` | Ordner `IDE/CodeInsight` |
| `Atlas.IDE.CodeInsight.Manager.Commands` | `IDE/CodeInsight/Atlas.IDE.CodeInsight.Manager.Commands.pas` | Ordner `IDE/CodeInsight` |
| `Atlas.IDE.CodeInsight.Manager.Crashes` | `IDE/CodeInsight/Atlas.IDE.CodeInsight.Manager.Crashes.pas` | Ordner `IDE/CodeInsight` |
| `Atlas.IDE.CodeInsight.Manager.Editors` | `IDE/CodeInsight/Atlas.IDE.CodeInsight.Manager.Editors.pas` | Ordner `IDE/CodeInsight` |
| `Atlas.IDE.CodeInsight.Manager.Handlers` | `IDE/CodeInsight/Atlas.IDE.CodeInsight.Manager.Handlers.pas` | Ordner `IDE/CodeInsight` |
| `Atlas.IDE.CodeInsight.Manager.Paths` | `IDE/CodeInsight/Atlas.IDE.CodeInsight.Manager.Paths.pas` | Ordner `IDE/CodeInsight` |
| `Atlas.IDE.CodeInsight.Manager.Queries` | `IDE/CodeInsight/Atlas.IDE.CodeInsight.Manager.Queries.pas` | Ordner `IDE/CodeInsight` |
| `Atlas.IDE.CodeInsight.IdeMembers` | `IDE/CodeInsight/Atlas.IDE.CodeInsight.IdeMembers.pas` | Ordner `IDE/CodeInsight` |
| `Atlas.IDE.CodeInsight.IdeTypes` | `IDE/CodeInsight/Atlas.IDE.CodeInsight.IdeTypes.pas` | Ordner `IDE/CodeInsight` |
| `Atlas.IDE.CodeInsight.Manager.Session` | `IDE/CodeInsight/Atlas.IDE.CodeInsight.Manager.Session.pas` | Ordner `IDE/CodeInsight` |
| `Atlas.IDE.CodeInsight.Manager.State` | `IDE/CodeInsight/Atlas.IDE.CodeInsight.Manager.State.pas` | Ordner `IDE/CodeInsight` |
| `Atlas.IDE.Commands.KeyList` | `IDE/Commands/Atlas.IDE.Commands.KeyList.pas` | Ordner `IDE/Commands` |
| `Atlas.IDE.Commands.KeysEditing` | `IDE/Commands/Atlas.IDE.Commands.KeysEditing.pas` | Ordner `IDE/Commands` |
| `Atlas.IDE.Commands.KeysNavigation` | `IDE/Commands/Atlas.IDE.Commands.KeysNavigation.pas` | Ordner `IDE/Commands` |
| `Atlas.IDE.Commands.Bindings` | `IDE/Commands/Atlas.IDE.Commands.Bindings.pas` | Ordner `IDE/Commands` |
| `Atlas.IDE.Commands.ContextMenu` | `IDE/Commands/Atlas.IDE.Commands.ContextMenu.pas` | Ordner `IDE/Commands` |
| `Atlas.IDE.Commands.ProjectMenu` | `IDE/Commands/Atlas.IDE.Commands.ProjectMenu.pas` | Ordner `IDE/Commands` |
| `Atlas.IDE.Commands.EditorContext` | `IDE/Commands/Atlas.IDE.Commands.EditorContext.pas` | Ordner `IDE/Commands` |
| `Atlas.IDE.Commands.EditorSelection` | `IDE/Commands/Atlas.IDE.Commands.EditorSelection.pas` | Ordner `IDE/Commands` |
| `Atlas.IDE.Commands.EditorServer` | `IDE/Commands/Atlas.IDE.Commands.EditorServer.pas` | Ordner `IDE/Commands` |
| `Atlas.IDE.Commands.ClientCommands` | `IDE/Commands/Atlas.IDE.Commands.ClientCommands.pas` | Ordner `IDE/Commands` |
| `Atlas.IDE.Commands.EditorActions` | `IDE/Commands/Atlas.IDE.Commands.EditorActions.pas` | Ordner `IDE/Commands` |
| `Atlas.IDE.Commands.EditorMenu` | `IDE/Commands/Atlas.IDE.Commands.EditorMenu.pas` | Ordner `IDE/Commands` |
| `Atlas.IDE.Commands.Editor` | `IDE/Commands/Atlas.IDE.Commands.Editor.pas` | Ordner `IDE/Commands` |
| `Atlas.IDE.Commands.KeyMap` | `IDE/Commands/Atlas.IDE.Commands.KeyMap.pas` | Ordner `IDE/Commands` |
| `Atlas.IDE.Commands.MainMenu` | `IDE/Commands/Atlas.IDE.Commands.MainMenu.pas` | Ordner `IDE/Commands` |
| `Atlas.IDE.Commands.MenuActions` | `IDE/Commands/Atlas.IDE.Commands.MenuActions.pas` | Ordner `IDE/Commands` |
| `Atlas.IDE.Commands.MenuModules` | `IDE/Commands/Atlas.IDE.Commands.MenuModules.pas` | Ordner `IDE/Commands` |
| `Atlas.IDE.Commands.Palette` | `IDE/Commands/Atlas.IDE.Commands.Palette.pas` | Ordner `IDE/Commands` |
| `Atlas.IDE.Commands.QuickOpen` | `IDE/Commands/Atlas.IDE.Commands.QuickOpen.pas` | Ordner `IDE/Commands` |
| `Atlas.IDE.Commands.ShortcutKeys` | `IDE/Commands/Atlas.IDE.Commands.ShortcutKeys.pas` | Ordner `IDE/Commands` |
| `Atlas.IDE.Commands.ShortcutTips` | `IDE/Commands/Atlas.IDE.Commands.ShortcutTips.pas` | Ordner `IDE/Commands` |
| `Atlas.IDE.Commands.Usage` | `IDE/Commands/Atlas.IDE.Commands.Usage.pas` | Ordner `IDE/Commands` |
| `Atlas.IDE.Completion.Editor` | `IDE/Completion/Atlas.IDE.Completion.Editor.pas` | Ordner `IDE/Completion` |
| `Atlas.IDE.Completion.EditorState` | `IDE/Completion/Atlas.IDE.Completion.EditorState.pas` | Ordner `IDE/Completion` |
| `Atlas.IDE.Completion.EditorSnippets` | `IDE/Completion/Atlas.IDE.Completion.EditorSnippets.pas` | Ordner `IDE/Completion` |
| `Atlas.IDE.Completion.EditorOpen` | `IDE/Completion/Atlas.IDE.Completion.EditorOpen.pas` | Ordner `IDE/Completion` |
| `Atlas.IDE.Completion.EditorCommit` | `IDE/Completion/Atlas.IDE.Completion.EditorCommit.pas` | Ordner `IDE/Completion` |
| `Atlas.IDE.Completion.Favorites` | `IDE/Completion/Atlas.IDE.Completion.Favorites.pas` | Ordner `IDE/Completion` |
| `Atlas.IDE.Completion.History` | `IDE/Completion/Atlas.IDE.Completion.History.pas` | Ordner `IDE/Completion` |
| `Atlas.IDE.Completion.Placeholders` | `IDE/Completion/Atlas.IDE.Completion.Placeholders.pas` | Ordner `IDE/Completion` |
| `Atlas.IDE.Completion.Preview` | `IDE/Completion/Atlas.IDE.Completion.Preview.pas` | Ordner `IDE/Completion` |
| `Atlas.IDE.Diagnostics.BugReport` | `IDE/Diagnostics/Atlas.IDE.Diagnostics.BugReport.pas` | Ordner `IDE/Diagnostics` |
| `Atlas.IDE.Diagnostics.Export` | `IDE/Diagnostics/Atlas.IDE.Diagnostics.Export.pas` | Ordner `IDE/Diagnostics` |
| `Atlas.IDE.Diagnostics.PluginTimings` | `IDE/Diagnostics/Atlas.IDE.Diagnostics.PluginTimings.pas` | Ordner `IDE/Diagnostics` |
| `Atlas.IDE.Diagnostics.Edition` | `IDE/Diagnostics/Atlas.IDE.Diagnostics.Edition.pas` | Ordner `IDE/Diagnostics` |
| `Atlas.IDE.Diagnostics.SafeMode` | `IDE/Diagnostics/Atlas.IDE.Diagnostics.SafeMode.pas` | Ordner `IDE/Diagnostics` |
| `Atlas.IDE.Diagnostics.ServerPackage` | `IDE/Diagnostics/Atlas.IDE.Diagnostics.ServerPackage.pas` | Ordner `IDE/Diagnostics` |
| `Atlas.IDE.Diagnostics.StackCapture` | `IDE/Diagnostics/Atlas.IDE.Diagnostics.StackCapture.pas` | Ordner `IDE/Diagnostics` |
| `Atlas.IDE.Diagnostics.Timing` | `IDE/Diagnostics/Atlas.IDE.Diagnostics.Timing.pas` | Ordner `IDE/Diagnostics` |
| `Atlas.IDE.Diagnostics.TimingWindow` | `IDE/Diagnostics/Atlas.IDE.Diagnostics.TimingWindow.pas` | Ordner `IDE/Diagnostics` |
| `Atlas.IDE.Diagnostics.Watchdog` | `IDE/Diagnostics/Atlas.IDE.Diagnostics.Watchdog.pas` | Ordner `IDE/Diagnostics` |
| `Atlas.IDE.Diagnostics.KnownPackages` | `IDE/Diagnostics/Atlas.IDE.Diagnostics.KnownPackages.pas` | Ordner `IDE/Diagnostics` |
| `Atlas.IDE.Editor.AnonymousMethod` | `IDE/Editor/Atlas.IDE.Editor.AnonymousMethod.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.BlockComment` | `IDE/Editor/Atlas.IDE.Editor.BlockComment.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.ChangeSignature` | `IDE/Editor/Atlas.IDE.Editor.ChangeSignature.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.ClassExtraction` | `IDE/Editor/Atlas.IDE.Editor.ClassExtraction.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.CommentContinuation` | `IDE/Editor/Atlas.IDE.Editor.CommentContinuation.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.DisableWarning` | `IDE/Editor/Atlas.IDE.Editor.DisableWarning.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.EnterWatch` | `IDE/Editor/Atlas.IDE.Editor.EnterWatch.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.EnumTables` | `IDE/Editor/Atlas.IDE.Editor.EnumTables.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.ExitPoints` | `IDE/Editor/Atlas.IDE.Editor.ExitPoints.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.ExpressionType` | `IDE/Editor/Atlas.IDE.Editor.ExpressionType.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.ExtractInterface` | `IDE/Editor/Atlas.IDE.Editor.ExtractInterface.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.ExtractSuperclass` | `IDE/Editor/Atlas.IDE.Editor.ExtractSuperclass.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.GhostSuggestions` | `IDE/Editor/Atlas.IDE.Editor.GhostSuggestions.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.GutterColumn` | `IDE/Editor/Atlas.IDE.Editor.GutterColumn.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.GutterColumnState` | `IDE/Editor/Atlas.IDE.Editor.GutterColumnState.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.Hide` | `IDE/Editor/Atlas.IDE.Editor.Hide.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.HideTeamFile` | `IDE/Editor/Atlas.IDE.Editor.HideTeamFile.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.InlineAccessor` | `IDE/Editor/Atlas.IDE.Editor.InlineAccessor.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.InvertBoolean` | `IDE/Editor/Atlas.IDE.Editor.InvertBoolean.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.LearnedSuggestions` | `IDE/Editor/Atlas.IDE.Editor.LearnedSuggestions.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.LineMove` | `IDE/Editor/Atlas.IDE.Editor.LineMove.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.LinkedEditing` | `IDE/Editor/Atlas.IDE.Editor.LinkedEditing.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.LinkedEditingQuery` | `IDE/Editor/Atlas.IDE.Editor.LinkedEditingQuery.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.MethodKind` | `IDE/Editor/Atlas.IDE.Editor.MethodKind.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.MethodPlacement` | `IDE/Editor/Atlas.IDE.Editor.MethodPlacement.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.RegionFolds` | `IDE/Editor/Atlas.IDE.Editor.RegionFolds.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.MetricsSource` | `IDE/Editor/Atlas.IDE.Editor.MetricsSource.pas` | Ordner `IDE/Editor`; Abruf der Metriken für Statusleiste und Metrik-Lens (#1756) |
| `Atlas.IDE.Editor.Lens` | `IDE/Editor/Atlas.IDE.Editor.Lens.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.Minimap` | `IDE/Editor/Atlas.IDE.Editor.Minimap.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.MinimapFolds` | `IDE/Editor/Atlas.IDE.Editor.MinimapFolds.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.MinimapNotice` | `IDE/Editor/Atlas.IDE.Editor.MinimapNotice.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.MissingUnit` | `IDE/Editor/Atlas.IDE.Editor.MissingUnit.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.MoveClass` | `IDE/Editor/Atlas.IDE.Editor.MoveClass.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.MoveMember` | `IDE/Editor/Atlas.IDE.Editor.MoveMember.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.MultiCursor` | `IDE/Editor/Atlas.IDE.Editor.MultiCursor.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.MultiCursorState` | `IDE/Editor/Atlas.IDE.Editor.MultiCursorState.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.NamedRefactoring` | `IDE/Editor/Atlas.IDE.Editor.NamedRefactoring.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.NavHistory` | `IDE/Editor/Atlas.IDE.Editor.NavHistory.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.MouseButtons` | `IDE/Editor/Atlas.IDE.Editor.MouseButtons.pas` | Ordner `IDE/Editor`; Maustasten Zurück/Vor (#1889) |
| `Atlas.IDE.Editor.NewLine` | `IDE/Editor/Atlas.IDE.Editor.NewLine.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.Overloads` | `IDE/Editor/Atlas.IDE.Editor.Overloads.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.OverviewRuler` | `IDE/Editor/Atlas.IDE.Editor.OverviewRuler.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.PaintedLine` | `IDE/Editor/Atlas.IDE.Editor.PaintedLine.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.Pairs` | `IDE/Editor/Atlas.IDE.Editor.Pairs.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.PatternContinuation` | `IDE/Editor/Atlas.IDE.Editor.PatternContinuation.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.PromoteVariable` | `IDE/Editor/Atlas.IDE.Editor.PromoteVariable.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.PropertyFromAccessors` | `IDE/Editor/Atlas.IDE.Editor.PropertyFromAccessors.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.Reassigned` | `IDE/Editor/Atlas.IDE.Editor.Reassigned.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.RecursionGutter` | `IDE/Editor/Atlas.IDE.Editor.RecursionGutter.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.Rename` | `IDE/Editor/Atlas.IDE.Editor.Rename.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.SafeDelete` | `IDE/Editor/Atlas.IDE.Editor.SafeDelete.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.SelectionMatches` | `IDE/Editor/Atlas.IDE.Editor.SelectionMatches.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.ServerEdit` | `IDE/Editor/Atlas.IDE.Editor.ServerEdit.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.SmartIndent` | `IDE/Editor/Atlas.IDE.Editor.SmartIndent.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.SmartPaste` | `IDE/Editor/Atlas.IDE.Editor.SmartPaste.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.StatementCompletion` | `IDE/Editor/Atlas.IDE.Editor.StatementCompletion.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.TestUnitLens` | `IDE/Editor/Atlas.IDE.Editor.TestUnitLens.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.TypeAlias` | `IDE/Editor/Atlas.IDE.Editor.TypeAlias.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.UnitRename` | `IDE/Editor/Atlas.IDE.Editor.UnitRename.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.Unwrap` | `IDE/Editor/Atlas.IDE.Editor.Unwrap.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.WorkspaceEdit` | `IDE/Editor/Atlas.IDE.Editor.WorkspaceEdit.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.Editor.WrapSelection` | `IDE/Editor/Atlas.IDE.Editor.WrapSelection.pas` | Ordner `IDE/Editor` |
| `Atlas.IDE.EditorToolbar.FindMethod` | `IDE/EditorToolbar/Atlas.IDE.EditorToolbar.FindMethod.pas` | Ordner `IDE/EditorToolbar` |
| `Atlas.IDE.EditorToolbar.Service` | `IDE/EditorToolbar/Atlas.IDE.EditorToolbar.Service.pas` | Ordner `IDE/EditorToolbar` |
| `Atlas.IDE.Files.DirtyExport` | `IDE/Files/Atlas.IDE.Files.DirtyExport.pas` | Ordner `IDE/Files` |
| `Atlas.IDE.Files.Reloader` | `IDE/Files/Atlas.IDE.Files.Reloader.pas` | Ordner `IDE/Files` |
| `Atlas.IDE.Forms.Designer` | `IDE/Forms/Atlas.IDE.Forms.Designer.pas` | Ordner `IDE/Forms` |
| `Atlas.IDE.Foundation.DesignerView` | `IDE/Foundation/Atlas.IDE.Foundation.DesignerView.pas` | Ordner `IDE/Foundation` |
| `Atlas.IDE.Foundation.DockWindow` | `IDE/Foundation/Atlas.IDE.Foundation.DockWindow.pas` | Ordner `IDE/Foundation` |
| `Atlas.IDE.Foundation.EditorBarHost` | `IDE/Foundation/Atlas.IDE.Foundation.EditorBarHost.pas` | Ordner `IDE/Foundation` |
| `Atlas.IDE.Foundation.EditorBuffer` | `IDE/Foundation/Atlas.IDE.Foundation.EditorBuffer.pas` | Ordner `IDE/Foundation` |
| `Atlas.IDE.Foundation.EditorRefresh` | `IDE/Foundation/Atlas.IDE.Foundation.EditorRefresh.pas` | Ordner `IDE/Foundation` |
| `Atlas.IDE.Foundation.EditorSnapshot` | `IDE/Foundation/Atlas.IDE.Foundation.EditorSnapshot.pas` | Ordner `IDE/Foundation` |
| `Atlas.IDE.Foundation.EditorStyle` | `IDE/Foundation/Atlas.IDE.Foundation.EditorStyle.pas` | Ordner `IDE/Foundation` |
| `Atlas.IDE.Foundation.Elements` | `IDE/Foundation/Atlas.IDE.Foundation.Elements.pas` | Ordner `IDE/Foundation` |
| `Atlas.IDE.Foundation.Files` | `IDE/Foundation/Atlas.IDE.Foundation.Files.pas` | Ordner `IDE/Foundation` |
| `Atlas.IDE.Foundation.GutterColumns` | `IDE/Foundation/Atlas.IDE.Foundation.GutterColumns.pas` | Ordner `IDE/Foundation` |
| `Atlas.IDE.Foundation.GutterMarks` | `IDE/Foundation/Atlas.IDE.Foundation.GutterMarks.pas` | Ordner `IDE/Foundation` |
| `Atlas.IDE.ElementHelp.Keys` | `IDE/ElementHelp/Atlas.IDE.ElementHelp.Keys.pas` | Ordner `IDE/ElementHelp`: F1 in Atlas-Fenstern und auf der Optionsseite, fragt das Modul Hilfe nach `IAtlasHelpProvider` (#1886) |
| `Atlas.IDE.Foundation.Host` | `IDE/Foundation/Atlas.IDE.Foundation.Host.pas` | Dienste von Base für die Module (Sitzung, Serverbefehle, Meldungen, Warnungen, Log, Statusfeld), #1455 |
| `Atlas.IDE.Foundation.KeyHook` | `IDE/Foundation/Atlas.IDE.Foundation.KeyHook.pas` | Ordner `IDE/Foundation` |
| `Atlas.IDE.Foundation.LineTracker` | `IDE/Foundation/Atlas.IDE.Foundation.LineTracker.pas` | Ordner `IDE/Foundation` |
| `Atlas.IDE.Foundation.Keys` | `IDE/Foundation/Atlas.IDE.Foundation.Keys.pas` | Ordner `IDE/Foundation` |
| `Atlas.IDE.Foundation.Navigation` | `IDE/Foundation/Atlas.IDE.Foundation.Navigation.pas` | Ordner `IDE/Foundation` |
| `Atlas.IDE.Foundation.ResultsWindow` | `IDE/Foundation/Atlas.IDE.Foundation.ResultsWindow.pas` | Ordner `IDE/Foundation` |
| `Atlas.IDE.Foundation.Settings` | `IDE/Foundation/Atlas.IDE.Foundation.Settings.pas` | Ordner `IDE/Foundation` |
| `Atlas.IDE.Foundation.StartOptions` | `IDE/Foundation/Atlas.IDE.Foundation.StartOptions.pas` | Startoptionen und vorübergehende Startparameter; Startprofile (Build) und „Test debuggen“ (Tests) brauchen sie, #1455 |
| `Atlas.IDE.Foundation.StructureSwitch` | `IDE/Foundation/Atlas.IDE.Foundation.StructureSwitch.pas` | Ordner `IDE/Foundation` |
| `Atlas.IDE.Foundation.Symbol` | `IDE/Foundation/Atlas.IDE.Foundation.Symbol.pas` | Ordner `IDE/Foundation` |
| `Atlas.IDE.Foundation.TeamFile` | `IDE/Foundation/Atlas.IDE.Foundation.TeamFile.pas` | Ordner `IDE/Foundation` |
| `Atlas.IDE.Generate.Commands` | `IDE/Generate/Atlas.IDE.Generate.Commands.pas` | Ordner `IDE/Generate` |
| `Atlas.IDE.Generate.NewFile` | `IDE/Generate/Atlas.IDE.Generate.NewFile.pas` | Ordner `IDE/Generate` |
| `Atlas.IDE.Generate.Gallery` | `IDE/Generate/Atlas.IDE.Generate.Gallery.pas` | Ordner `IDE/Generate`: Kategorie Atlas in Datei › Neu › Weitere, #1821 |
| `Atlas.IDE.Hover.DebugValue` | `IDE/Hover/Atlas.IDE.Hover.DebugValue.pas` | Ordner `IDE/Hover` |
| `Atlas.IDE.Hover.Editor` | `IDE/Hover/Atlas.IDE.Hover.Editor.pas` | Ordner `IDE/Hover` |
| `Atlas.IDE.Hover.EditorContent` | `IDE/Hover/Atlas.IDE.Hover.EditorContent.pas` | Ordner `IDE/Hover` |
| `Atlas.IDE.InlayHints.Editor` | `IDE/InlayHints/Atlas.IDE.InlayHints.Editor.pas` | Ordner `IDE/InlayHints` |
| `Atlas.IDE.Notifications.Service` | `IDE/Notifications/Atlas.IDE.Notifications.Service.pas` | Ordner `IDE/Notifications` |
| `Atlas.IDE.Outline.Breadcrumbs` | `IDE/Outline/Atlas.IDE.Outline.Breadcrumbs.pas` | Ordner `IDE/Outline` |
| `Atlas.IDE.Outline.Cache` | `IDE/Outline/Atlas.IDE.Outline.Cache.pas` | Ordner `IDE/Outline` |
| `Atlas.IDE.Outline.CrumbMenu` | `IDE/Outline/Atlas.IDE.Outline.CrumbMenu.pas` | Ordner `IDE/Outline` |
| `Atlas.IDE.Outline.NavigationOption` | `IDE/Outline/Atlas.IDE.Outline.NavigationOption.pas` | Ordner `IDE/Outline` |
| `Atlas.IDE.Outline.SectionEdit` | `IDE/Outline/Atlas.IDE.Outline.SectionEdit.pas` | Ordner `IDE/Outline` |
| `Atlas.IDE.Outline.Service` | `IDE/Outline/Atlas.IDE.Outline.Service.pas` | Ordner `IDE/Outline` |
| `Atlas.IDE.Outline.StickyScroll` | `IDE/Outline/Atlas.IDE.Outline.StickyScroll.pas` | Ordner `IDE/Outline` |
| `Atlas.IDE.Outline.Window` | `IDE/Outline/Atlas.IDE.Outline.Window.pas` | Ordner `IDE/Outline` |
| `Atlas.IDE.Problems.Caret` | `IDE/Problems/Atlas.IDE.Problems.Caret.pas` | Ordner `IDE/Problems`: Befund unter der Einfügemarke für F1 (#1886) |
| `Atlas.IDE.Problems.Controller` | `IDE/Problems/Atlas.IDE.Problems.Controller.pas` | Ordner `IDE/Problems` |
| `Atlas.IDE.Problems.MessageList` | `IDE/Problems/Atlas.IDE.Problems.MessageList.pas` | Ordner `IDE/Problems` |
| `Atlas.IDE.Problems.Painter` | `IDE/Problems/Atlas.IDE.Problems.Painter.pas` | Ordner `IDE/Problems` |
| `Atlas.IDE.Problems.RuleActions` | `IDE/Problems/Atlas.IDE.Problems.RuleActions.pas` | Ordner `IDE/Problems`: fragt das Modul Prüfregeln nach `IAtlasRuleActions` (#1755) |
| `Atlas.IDE.Problems.Files` | `IDE/Problems/Atlas.IDE.Problems.Files.pas` | Ordner `IDE/Problems` |
| `Atlas.IDE.Problems.Service` | `IDE/Problems/Atlas.IDE.Problems.Service.pas` | Ordner `IDE/Problems` |
| `Atlas.IDE.Problems.Window` | `IDE/Problems/Atlas.IDE.Problems.Window.pas` | Ordner `IDE/Problems` |
| `Atlas.IDE.Projects.Context` | `IDE/Projects/Atlas.IDE.Projects.Context.pas` | Ordner `IDE/Projects` |
| `Atlas.IDE.Projects.Summaries` | `IDE/Projects/Atlas.IDE.Projects.Summaries.pas` | Projekt-Zusammenfassungen pflegen (auch ohne Willkommensseite), `IAtlasProjectSummaryListener`, #1455 |
| `Atlas.IDE.Results.Commands` | `IDE/Results/Atlas.IDE.Results.Commands.pas` | Ordner `IDE/Results` |
| `Atlas.IDE.Results.Impact` | `IDE/Results/Atlas.IDE.Results.Impact.pas` | Ordner `IDE/Results` |
| `Atlas.IDE.Results.Peek` | `IDE/Results/Atlas.IDE.Results.Peek.pas` | Ordner `IDE/Results` |
| `Atlas.IDE.Settings.Experimental` | `IDE/Settings/Atlas.IDE.Settings.Experimental.pas` | Ordner `IDE/Settings` |
| `Atlas.IDE.Settings.Options` | `IDE/Settings/Atlas.IDE.Settings.Options.pas` | Ordner `IDE/Settings` |
| `Atlas.IDE.Settings.PageOptions` | `IDE/Settings/Atlas.IDE.Settings.PageOptions.pas` | Ordner `IDE/Settings` |
| `Atlas.IDE.Settings.PaletteSearch` | `IDE/Settings/Atlas.IDE.Settings.PaletteSearch.pas` | Einstellungen mit „@“ in der Befehlspalette, #1884 |
| `Atlas.IDE.Settings.Project` | `IDE/Settings/Atlas.IDE.Settings.Project.pas` | Ordner `IDE/Settings` |
| `Atlas.IDE.Settings.QuickToggles` | `IDE/Settings/Atlas.IDE.Settings.QuickToggles.pas` | Ordner `IDE/Settings` |
| `Atlas.IDE.Settings.RuleChecksNotice` | `IDE/Settings/Atlas.IDE.Settings.RuleChecksNotice.pas` | Hinweis „Prüfregeln sind aus“, #1454 |
| `Atlas.IDE.Settings.ServerTool` | `IDE/Settings/Atlas.IDE.Settings.ServerTool.pas` | Ordner `IDE/Settings` |
| `Atlas.IDE.Settings.ServerActions` | `IDE/Settings/Atlas.IDE.Settings.ServerActions.pas` | AtlasServer.exe als Werkzeug starten und Index-Cache; Baseline und Unterdrückungen seit #1755 im Modul Prüfregeln |
| `Atlas.IDE.Settings.SubPages` | `IDE/Settings/Atlas.IDE.Settings.SubPages.pas` | Unterseiten Snippets, Tastenkonflikte und Server in Tools › Optionen |
| `Atlas.IDE.Settings.ModuleNodes` | `IDE/Settings/Atlas.IDE.Settings.ModuleNodes.pas` | Knoten „Module“, „Base“ und je Modul in Tools › Optionen (#1903) |
| `Atlas.IDE.Settings.Transfer` | `IDE/Settings/Atlas.IDE.Settings.Transfer.pas` | Ordner `IDE/Settings` |
| `Atlas.IDE.Setup.Checklist` | `IDE/Setup/Atlas.IDE.Setup.Checklist.pas` | Ordner `IDE/Setup` |
| `Atlas.IDE.Signature.Editor` | `IDE/Signature/Atlas.IDE.Signature.Editor.pas` | Ordner `IDE/Signature` |
| `Atlas.IDE.Signature.FormatMarks` | `IDE/Signature/Atlas.IDE.Signature.FormatMarks.pas` | Ordner `IDE/Signature` |
| `Atlas.IDE.Status.Field` | `IDE/Status/Atlas.IDE.Status.Field.pas` | Ordner `IDE/Status` |
| `Atlas.IDE.Status.Lines` | `IDE/Status/Atlas.IDE.Status.Lines.pas` | Ordner `IDE/Status` |
| `Atlas.IDE.Status.ServerWindow` | `IDE/Status/Atlas.IDE.Status.ServerWindow.pas` | Ordner `IDE/Status` |
| `Atlas.IDE.StatusBar.Service` | `IDE/StatusBar/Atlas.IDE.StatusBar.Service.pas` | Ordner `IDE/StatusBar` |
| `Atlas.IDE.StatusBar.View` | `IDE/StatusBar/Atlas.IDE.StatusBar.View.pas` | Ordner `IDE/StatusBar` |
| `Atlas.IDE.Undo.Changes` | `IDE/Undo/Atlas.IDE.Undo.Changes.pas` | Ordner `IDE/Undo` |
| `Atlas.IDE.Undo.Target` | `IDE/Undo/Atlas.IDE.Undo.Target.pas` | Ordner `IDE/Undo` |
| `Atlas.IDE.Updates.Check` | `IDE/Updates/Atlas.IDE.Updates.Check.pas` | Ordner `IDE/Updates` |
| `Atlas.IDE.Updates.Install` | `IDE/Updates/Atlas.IDE.Updates.Install.pas` | Ordner `IDE/Updates` |
| `Atlas.UI.Commands.KeyMap` | `UI/Commands/Atlas.UI.Commands.KeyMap.pas` | Ordner `UI/Commands` |
| `Atlas.UI.Commands.Palette` | `UI/Commands/Atlas.UI.Commands.Palette.pas` | Ordner `UI/Commands` |
| `Atlas.UI.Commands.ShortcutTip` | `UI/Commands/Atlas.UI.Commands.ShortcutTip.pas` | Ordner `UI/Commands` |
| `Atlas.UI.Completion.Details` | `UI/Completion/Atlas.UI.Completion.Details.pas` | Ordner `UI/Completion` |
| `Atlas.UI.Completion.Popup` | `UI/Completion/Atlas.UI.Completion.Popup.pas` | Ordner `UI/Completion` |
| `Atlas.UI.Completion.PopupState` | `UI/Completion/Atlas.UI.Completion.PopupState.pas` | Ordner `UI/Completion` |
| `Atlas.UI.Completion.PopupLayout` | `UI/Completion/Atlas.UI.Completion.PopupLayout.pas` | Ordner `UI/Completion` |
| `Atlas.UI.Completion.PopupPainter` | `UI/Completion/Atlas.UI.Completion.PopupPainter.pas` | Ordner `UI/Completion` |
| `Atlas.UI.Completion.PopupTexts` | `UI/Completion/Atlas.UI.Completion.PopupTexts.pas` | Ordner `UI/Completion` |
| `Atlas.UI.Diagnostics.ExportDialog` | `UI/Diagnostics/Atlas.UI.Diagnostics.ExportDialog.pas` | Ordner `UI/Diagnostics` |
| `Atlas.UI.Diagnostics.Grid` | `UI/Diagnostics/Atlas.UI.Diagnostics.Grid.pas` | Ordner `UI/Diagnostics` |
| `Atlas.UI.Diagnostics.MainThreadPage` | `UI/Diagnostics/Atlas.UI.Diagnostics.MainThreadPage.pas` | Ordner `UI/Diagnostics` |
| `Atlas.UI.Diagnostics.PluginFrame` | `UI/Diagnostics/Atlas.UI.Diagnostics.PluginFrame.pas` | Ordner `UI/Diagnostics` |
| `Atlas.UI.Diagnostics.PluginParts` | `UI/Diagnostics/Atlas.UI.Diagnostics.PluginParts.pas` | Ordner `UI/Diagnostics` |
| `Atlas.UI.Diagnostics.PluginRows` | `UI/Diagnostics/Atlas.UI.Diagnostics.PluginRows.pas` | Ordner `UI/Diagnostics` |
| `Atlas.UI.Diagnostics.ProcessesDialog` | `UI/Diagnostics/Atlas.UI.Diagnostics.ProcessesDialog.pas` | Ordner `UI/Diagnostics` |
| `Atlas.UI.Diagnostics.ReportDialog` | `UI/Diagnostics/Atlas.UI.Diagnostics.ReportDialog.pas` | Ordner `UI/Diagnostics` |
| `Atlas.UI.Diagnostics.Strings` | `UI/Diagnostics/Atlas.UI.Diagnostics.Strings.pas` | Ordner `UI/Diagnostics` |
| `Atlas.UI.Diagnostics.SafeModeNotice` | `UI/Diagnostics/Atlas.UI.Diagnostics.SafeModeNotice.pas` | Ordner `UI/Diagnostics` |
| `Atlas.UI.Diagnostics.TimingFrame` | `UI/Diagnostics/Atlas.UI.Diagnostics.TimingFrame.pas` | Ordner `UI/Diagnostics` |
| `Atlas.UI.Documentation.View` | `UI/Documentation/Atlas.UI.Documentation.View.pas` | Ordner `UI/Documentation` |
| `Atlas.UI.Editor.Bar` | `UI/Editor/Atlas.UI.Editor.Bar.pas` | Ordner `UI/Editor` |
| `Atlas.UI.Editor.ChangeSignature` | `UI/Editor/Atlas.UI.Editor.ChangeSignature.pas` | Ordner `UI/Editor` |
| `Atlas.UI.Editor.ExpressionType` | `UI/Editor/Atlas.UI.Editor.ExpressionType.pas` | Ordner `UI/Editor` |
| `Atlas.UI.Editor.ExtractMembers` | `UI/Editor/Atlas.UI.Editor.ExtractMembers.pas` | Ordner `UI/Editor` |
| `Atlas.UI.Editor.Hide` | `UI/Editor/Atlas.UI.Editor.Hide.pas` | Ordner `UI/Editor` |
| `Atlas.UI.Editor.LearnedSuggestions` | `UI/Editor/Atlas.UI.Editor.LearnedSuggestions.pas` | Ordner `UI/Editor` |
| `Atlas.UI.Editor.RegionFolds` | `UI/Editor/Atlas.UI.Editor.RegionFolds.pas` | Ordner `UI/Editor` |
| `Atlas.UI.Editor.Minimap` | `UI/Editor/Atlas.UI.Editor.Minimap.pas` | Ordner `UI/Editor` |
| `Atlas.UI.Editor.MinimapLayers` | `UI/Editor/Atlas.UI.Editor.MinimapLayers.pas` | Ordner `UI/Editor` |
| `Atlas.UI.Editor.OverviewRuler` | `UI/Editor/Atlas.UI.Editor.OverviewRuler.pas` | Ordner `UI/Editor` |
| `Atlas.UI.Editor.Peek` | `UI/Editor/Atlas.UI.Editor.Peek.pas` | Ordner `UI/Editor` |
| `Atlas.UI.Editor.SmartPaste` | `UI/Editor/Atlas.UI.Editor.SmartPaste.pas` | Ordner `UI/Editor` |
| `Atlas.UI.Editor.Unwrap` | `UI/Editor/Atlas.UI.Editor.Unwrap.pas` | Ordner `UI/Editor` |
| `Atlas.UI.EditorToolbar.Bar` | `UI/EditorToolbar/Atlas.UI.EditorToolbar.Bar.pas` | Ordner `UI/EditorToolbar` |
| `Atlas.UI.EditorToolbar.Customize` | `UI/EditorToolbar/Atlas.UI.EditorToolbar.Customize.pas` | Ordner `UI/EditorToolbar` |
| `Atlas.UI.EditorToolbar.Glyphs` | `UI/EditorToolbar/Atlas.UI.EditorToolbar.Glyphs.pas` | Ordner `UI/EditorToolbar` |
| `Atlas.UI.Generate.Window` | `UI/Generate/Atlas.UI.Generate.Window.pas` | Ordner `UI/Generate` |
| `Atlas.UI.Generate.Choice` | `UI/Generate/Atlas.UI.Generate.Choice.pas` | Ordner `UI/Generate`: Auswahldialog der Assistenten, #1821 |
| `Atlas.UI.Hover.Tip` | `UI/Hover/Atlas.UI.Hover.Tip.pas` | Ordner `UI/Hover` |
| `Atlas.UI.Notifications.Notice` | `UI/Notifications/Atlas.UI.Notifications.Notice.pas` | Ordner `UI/Notifications` |
| `Atlas.UI.Notifications.Window` | `UI/Notifications/Atlas.UI.Notifications.Window.pas` | Ordner `UI/Notifications` |
| `Atlas.UI.Outline.Breadcrumbs` | `UI/Outline/Atlas.UI.Outline.Breadcrumbs.pas` | Ordner `UI/Outline` |
| `Atlas.UI.Outline.Frame` | `UI/Outline/Atlas.UI.Outline.Frame.pas` | Ordner `UI/Outline` |
| `Atlas.UI.Outline.NavigationToolbar` | `UI/Outline/Atlas.UI.Outline.NavigationToolbar.pas` | Ordner `UI/Outline` |
| `Atlas.UI.Popup.Accessibility` | `UI/Popup/Atlas.UI.Popup.Accessibility.pas` | Ordner `UI/Popup` |
| `Atlas.UI.Popup.Draw` | `UI/Popup/Atlas.UI.Popup.Draw.pas` | Ordner `UI/Popup` |
| `Atlas.UI.Popup.Styled` | `UI/Popup/Atlas.UI.Popup.Styled.pas` | Ordner `UI/Popup` |
| `Atlas.UI.Popup.Tip` | `UI/Popup/Atlas.UI.Popup.Tip.pas` | Ordner `UI/Popup` |
| `Atlas.UI.Popup.TitledTip` | `UI/Popup/Atlas.UI.Popup.TitledTip.pas` | allgemeiner Tooltip, bis #1455 `Atlas.UI.Notes.Tip` |
| `Atlas.UI.Popup.CrumbCard` | `UI/Popup/Atlas.UI.Popup.CrumbCard.pas` | Kennzahlen-Karte der Brotkrumen (#1787) |
| `Atlas.UI.Popup.Window` | `UI/Popup/Atlas.UI.Popup.Window.pas` | Ordner `UI/Popup` |
| `Atlas.UI.Problems.Explain` | `UI/Problems/Atlas.UI.Problems.Explain.pas` | „Regel erklären“ in „Atlas-Prüfung“ (Base), #1455 |
| `Atlas.UI.Problems.Frame` | `UI/Problems/Atlas.UI.Problems.Frame.pas` | Ordner `UI/Problems` |
| `Atlas.UI.Problems.ScopeBox` | `UI/Problems/Atlas.UI.Problems.ScopeBox.pas` | Ordner `UI/Problems` |
| `Atlas.UI.Problems.KindIcon` | `UI/Problems/Atlas.UI.Problems.KindIcon.pas` | Ordner `UI/Problems` |
| `Atlas.UI.Results.CallDiagram` | `UI/Results/Atlas.UI.Results.CallDiagram.pas` | Ordner `UI/Results` |
| `Atlas.UI.Results.Changes` | `UI/Results/Atlas.UI.Results.Changes.pas` | Ordner `UI/Results`; Teil des Ergebnisfensters |
| `Atlas.UI.Results.DataFlow` | `UI/Results/Atlas.UI.Results.DataFlow.pas` | Ordner `UI/Results`; Teil des Ergebnisfensters |
| `Atlas.UI.Results.Entries` | `UI/Results/Atlas.UI.Results.Entries.pas` | Ordner `UI/Results`; Teil des Ergebnisfensters |
| `Atlas.UI.Results.Frame` | `UI/Results/Atlas.UI.Results.Frame.pas` | Ordner `UI/Results` |
| `Atlas.UI.Results.Hierarchy` | `UI/Results/Atlas.UI.Results.Hierarchy.pas` | Ordner `UI/Results`; Teil des Ergebnisfensters |
| `Atlas.UI.Results.Impact` | `UI/Results/Atlas.UI.Results.Impact.pas` | Ordner `UI/Results`; Teil des Ergebnisfensters |
| `Atlas.UI.Results.Issues` | `UI/Results/Atlas.UI.Results.Issues.pas` | Ordner `UI/Results`; Teil des Ergebnisfensters |
| `Atlas.UI.Results.Items` | `UI/Results/Atlas.UI.Results.Items.pas` | Ordner `UI/Results`; Teil des Ergebnisfensters |
| `Atlas.UI.Results.RenamePreview` | `UI/Results/Atlas.UI.Results.RenamePreview.pas` | Ordner `UI/Results` |
| `Atlas.UI.Results.SymbolPath` | `UI/Results/Atlas.UI.Results.SymbolPath.pas` | Ordner `UI/Results`; Teil des Ergebnisfensters |
| `Atlas.UI.Results.Texts` | `UI/Results/Atlas.UI.Results.Texts.pas` | Ordner `UI/Results`; Teil des Ergebnisfensters |
| `Atlas.UI.Results.View` | `UI/Results/Atlas.UI.Results.View.pas` | Ordner `UI/Results`; Teil des Ergebnisfensters |
| `Atlas.UI.Settings.ChoiceBox` | `UI/Settings/Atlas.UI.Settings.ChoiceBox.pas` | Ordner `UI/Settings` |
| `Atlas.UI.Settings.Bindings` | `UI/Settings/Atlas.UI.Settings.Bindings.pas` | Ordner `UI/Settings` |
| `Atlas.UI.Settings.Page.Sheets` | `UI/Settings/Atlas.UI.Settings.Page.Sheets.pas` | Ordner `UI/Settings` |
| `Atlas.UI.Settings.Page.Host` | `UI/Settings/Atlas.UI.Settings.Page.Host.pas` | Ordner `UI/Settings` |
| `Atlas.UI.Settings.Page.General` | `UI/Settings/Atlas.UI.Settings.Page.General.pas` | Ordner `UI/Settings` |
| `Atlas.UI.Settings.Page.Completion` | `UI/Settings/Atlas.UI.Settings.Page.Completion.pas` | Ordner `UI/Settings` |
| `Atlas.UI.Settings.Page.Transfer` | `UI/Settings/Atlas.UI.Settings.Page.Transfer.pas` | Ordner `UI/Settings` |
| `Atlas.UI.Settings.Page.TeamFile` | `UI/Settings/Atlas.UI.Settings.Page.TeamFile.pas` | Ordner `UI/Settings` |
| `Atlas.UI.Settings.Page.EditorView` | `UI/Settings/Atlas.UI.Settings.Page.EditorView.pas` | Ordner `UI/Settings` |
| `Atlas.UI.Settings.Page.EditorCode` | `UI/Settings/Atlas.UI.Settings.Page.EditorCode.pas` | Ordner `UI/Settings` |
| `Atlas.UI.Settings.Page.Colors` | `UI/Settings/Atlas.UI.Settings.Page.Colors.pas` | Ordner `UI/Settings` |
| `Atlas.UI.Settings.Page.Index` | `UI/Settings/Atlas.UI.Settings.Page.Index.pas` | Ordner `UI/Settings` |
| `Atlas.UI.Settings.Page.Build` | `UI/Settings/Atlas.UI.Settings.Page.Build.pas` | Ordner `UI/Settings` |
| `Atlas.UI.Settings.Page.Rules` | `UI/Settings/Atlas.UI.Settings.Page.Rules.pas` | Ordner `UI/Settings` |
| `Atlas.UI.Settings.Page.Commands` | `UI/Settings/Atlas.UI.Settings.Page.Commands.pas` | Ordner `UI/Settings` |
| `Atlas.UI.Settings.Page.Robustness` | `UI/Settings/Atlas.UI.Settings.Page.Robustness.pas` | Ordner `UI/Settings` |
| `Atlas.UI.Settings.Page.Startup` | `UI/Settings/Atlas.UI.Settings.Page.Startup.pas` | Ordner `UI/Settings` |
| `Atlas.UI.Settings.Page.Parts` | `UI/Settings/Atlas.UI.Settings.Page.Parts.pas` | Ordner `UI/Settings` |
| `Atlas.UI.Settings.Page.Sections` | `UI/Settings/Atlas.UI.Settings.Page.Sections.pas` | Ordner `UI/Settings` |
| `Atlas.UI.Settings.Page.Nodes` | `UI/Settings/Atlas.UI.Settings.Page.Nodes.pas` | Ordner `UI/Settings` |
| `Atlas.UI.Settings.Page.Tree` | `UI/Settings/Atlas.UI.Settings.Page.Tree.pas` | Ordner `UI/Settings` |
| `Atlas.UI.Settings.Contract` | `UI/Settings/Atlas.UI.Settings.Contract.pas` | Ordner `UI/Settings`; Abschnitte der Module im Optionsdialog (#1455, Entscheidung 3) |
| `Atlas.UI.Settings.Group` | `UI/Settings/Atlas.UI.Settings.Group.pas` | Ordner `UI/Settings` |
| `Atlas.UI.Settings.Keys` | `UI/Settings/Atlas.UI.Settings.Keys.pas` | Ordner `UI/Settings` |
| `Atlas.UI.Settings.Marks` | `UI/Settings/Atlas.UI.Settings.Marks.pas` | Ordner `UI/Settings` |
| `Atlas.UI.Settings.Page` | `UI/Settings/Atlas.UI.Settings.Page.pas` | Ordner `UI/Settings` |
| `Atlas.UI.Settings.ProjectDialog` | `UI/Settings/Atlas.UI.Settings.ProjectDialog.pas` | Ordner `UI/Settings` |
| `Atlas.UI.Settings.QuickToggles` | `UI/Settings/Atlas.UI.Settings.QuickToggles.pas` | Ordner `UI/Settings` |
| `Atlas.UI.Settings.Section` | `UI/Settings/Atlas.UI.Settings.Section.pas` | Ordner `UI/Settings`; Grundlage der Einstellungsabschnitte der Module (#1455, Entscheidung 3) |
| `Atlas.UI.Settings.Overview` | `UI/Settings/Atlas.UI.Settings.Overview.pas` | Ordner `UI/Settings`; Übersicht „Atlas“ in den Optionen (#1903) |
| `Atlas.UI.Settings.Page.Search` | `UI/Settings/Atlas.UI.Settings.Page.Search.pas` | Ordner `UI/Settings`; Suchfeld über dem Baum der Optionsseite (#1884) |
| `Atlas.UI.Settings.ServerPage` | `UI/Settings/Atlas.UI.Settings.ServerPage.pas` | Ordner `UI/Settings` |
| `Atlas.UI.Settings.SnippetsPage` | `UI/Settings/Atlas.UI.Settings.SnippetsPage.pas` | Ordner `UI/Settings` |
| `Atlas.UI.Settings.Transfer` | `UI/Settings/Atlas.UI.Settings.Transfer.pas` | Ordner `UI/Settings` |
| `Atlas.UI.Setup.Window` | `UI/Setup/Atlas.UI.Setup.Window.pas` | Ordner `UI/Setup` |
| `Atlas.UI.Signature.Hint` | `UI/Signature/Atlas.UI.Signature.Hint.pas` | Ordner `UI/Signature` |
| `Atlas.UI.Status.ServerFrame` | `UI/Status/Atlas.UI.Status.ServerFrame.pas` | Ordner `UI/Status` |
| `Atlas.UI.Status.Window` | `UI/Status/Atlas.UI.Status.Window.pas` | Ordner `UI/Status` |
| `Atlas.UI.StatusBar.Bar` | `UI/StatusBar/Atlas.UI.StatusBar.Bar.pas` | Ordner `UI/StatusBar` |
| `Atlas.UI.Strings` | `UI/Atlas.UI.Strings.pas` | Ordner `UI` |
| `Atlas.UI.Style.Canvas` | `UI/Style/Atlas.UI.Style.Canvas.pas` | Zeichenfläche ohne Flackern für Bereiche und Kacheln, bis #1455 `TAtlasWelcomeCanvas` |
| `Atlas.UI.Style.Symbol` | `UI/Style/Atlas.UI.Style.Symbol.pas` | Ordner `UI/Style` |
| `Atlas.UI.SymbolPath.Chain` | `UI/SymbolPath/Atlas.UI.SymbolPath.Chain.pas` | Darstellung eines Wegs zwischen Symbolen im Ergebnisfenster von Base (#1117); das Modul Analyse sucht den Weg, #1455 |
| `Atlas.UI.Undo.DiffView` | `UI/Undo/Atlas.UI.Undo.DiffView.pas` | Ordner `UI/Undo` |
| `Atlas.UI.Undo.Messages` | `UI/Undo/Atlas.UI.Undo.Messages.pas` | Ordner `UI/Undo` |
| `Atlas.UI.Updates.Consent` | `UI/Updates/Atlas.UI.Updates.Consent.pas` | Ordner `UI/Updates` |
| `Atlas.UI.Updates.Offer` | `UI/Updates/Atlas.UI.Updates.Offer.pas` | Ordner `UI/Updates` |
| `Atlas.UI.Updates.Selection` | `UI/Updates/Atlas.UI.Updates.Selection.pas` | Ordner `UI/Updates` |
| `Atlas.UI.Updates.Strings` | `UI/Updates/Atlas.UI.Updates.Strings.pas` | Ordner `UI/Updates` |
| `Atlas.UI.Updates.Texts` | `UI/Updates/Atlas.UI.Updates.Texts.pas` | Ordner `UI/Updates` |

## Atlas.IDE.Assistants

| Unit | Datei | Begründung |
|---|---|---|
| `Atlas.Core.Assistants.BuildInbox` | `Core/Assistants/Atlas.Core.Assistants.BuildInbox.pas` | Ordner `Core/Assistants` |
| `Atlas.Core.Assistants.EditInbox` | `Core/Assistants/Atlas.Core.Assistants.EditInbox.pas` | Ordner `Core/Assistants` |
| `Atlas.IDE.Assistants.BuildInbox` | `IDE/Assistants/Atlas.IDE.Assistants.BuildInbox.pas` | Ordner `IDE/Assistants` |
| `Atlas.IDE.Assistants.Composition` | `IDE/Assistants/Atlas.IDE.Assistants.Composition.pas` | Ordner `IDE/Assistants` |
| `Atlas.IDE.Assistants.EditInbox` | `IDE/Assistants/Atlas.IDE.Assistants.EditInbox.pas` | Ordner `IDE/Assistants` |
| `Atlas.UI.Assistants.SettingsSection` | `UI/Assistants/Atlas.UI.Assistants.SettingsSection.pas` | Ordner `UI/Assistants` |
| `Atlas.UI.Assistants.Strings` | `UI/Assistants/Atlas.UI.Assistants.Strings.pas` | Ordner `UI/Assistants` |

## Atlas.IDE.VersionControl

| Unit | Datei | Begründung |
|---|---|---|
| `Atlas.Core.VersionControl.Composition` | `Core/VersionControl/Atlas.Core.VersionControl.Composition.pas` | Ordner `Core/VersionControl` |
| `Atlas.Core.VersionControl.Detection` | `Core/VersionControl/Atlas.Core.VersionControl.Detection.pas` | Ordner `Core/VersionControl` |
| `Atlas.Core.VersionControl.Internals.GitParser` | `Core/VersionControl/Atlas.Core.VersionControl.Internals.GitParser.pas` | Ordner `Core/VersionControl` |
| `Atlas.Core.VersionControl.Internals.LineTrace` | `Core/VersionControl/Atlas.Core.VersionControl.Internals.LineTrace.pas` | Ordner `Core/VersionControl` |
| `Atlas.Core.VersionControl.Internals.SvnParser` | `Core/VersionControl/Atlas.Core.VersionControl.Internals.SvnParser.pas` | Ordner `Core/VersionControl` |
| `Atlas.Core.VersionControl.Providers.Git` | `Core/VersionControl/Atlas.Core.VersionControl.Providers.Git.pas` | Ordner `Core/VersionControl` |
| `Atlas.Core.VersionControl.Providers.Svn` | `Core/VersionControl/Atlas.Core.VersionControl.Providers.Svn.pas` | Ordner `Core/VersionControl` |
| `Atlas.IDE.VersionControl.Branching` | `IDE/VersionControl/Atlas.IDE.VersionControl.Branching.pas` | Ordner `IDE/VersionControl` |
| `Atlas.IDE.VersionControl.Composition` | `IDE/VersionControl/Atlas.IDE.VersionControl.Composition.pas` | Ordner `IDE/VersionControl` |
| `Atlas.IDE.VersionControl.Commands` | `IDE/VersionControl/Atlas.IDE.VersionControl.Commands.pas` | Befehle „Branch anlegen …“ und „Arbeitskopien“ (#1905) |
| `Atlas.IDE.VersionControl.LineChanges` | `IDE/VersionControl/Atlas.IDE.VersionControl.LineChanges.pas` | Änderungsmarken und Zeilenhistorie (#507, #1905) |
| `Atlas.IDE.VersionControl.LineChangesData` | `IDE/VersionControl/Atlas.IDE.VersionControl.LineChangesData.pas` | Daten der Änderungsmarken (#507, #1905) |
| `Atlas.IDE.VersionControl.Service` | `IDE/VersionControl/Atlas.IDE.VersionControl.Service.pas` | Ordner `IDE/VersionControl` |
| `Atlas.IDE.VersionControl.WorkingCopies` | `IDE/VersionControl/Atlas.IDE.VersionControl.WorkingCopies.pas` | Ordner `IDE/VersionControl` |
| `Atlas.UI.VersionControl.SettingsSection` | `UI/VersionControl/Atlas.UI.VersionControl.SettingsSection.pas` | Ordner `UI/VersionControl` |
| `Atlas.UI.VersionControl.SettingsPart` | `UI/VersionControl/Atlas.UI.VersionControl.SettingsPart.pas` | Bausteine der Seite Versionsverwaltung (#1905) |
| `Atlas.UI.VersionControl.SettingsKind` | `UI/VersionControl/Atlas.UI.VersionControl.SettingsKind.pas` | Art und Links (#1285, #1905) |
| `Atlas.UI.VersionControl.SettingsTools` | `UI/VersionControl/Atlas.UI.VersionControl.SettingsTools.pas` | Programme git und svn (#1285, #1905) |
| `Atlas.UI.VersionControl.SettingsProject` | `UI/VersionControl/Atlas.UI.VersionControl.SettingsProject.pas` | Zeitlimit und aktuelles Projekt (#1285, #1905) |
| `Atlas.UI.VersionControl.SettingsProjects` | `UI/VersionControl/Atlas.UI.VersionControl.SettingsProjects.pas` | Tabellen Projekte und Server (#1286, #1287, #1905) |
| `Atlas.UI.VersionControl.SettingsBranch` | `UI/VersionControl/Atlas.UI.VersionControl.SettingsBranch.pas` | Branches, SVN, Externals, Git (#1288–#1292, #1905) |
| `Atlas.IDE.VersionControl.Settings` | `IDE/VersionControl/Atlas.IDE.VersionControl.Settings.pas` | Anbieter und Haken des Abschnitts Versionsverwaltung (#1905) |
| `Atlas.UI.VersionControl.Strings` | `UI/VersionControl/Atlas.UI.VersionControl.Strings.pas` | Texte des Moduls Versionsverwaltung (#1905) |
| `Atlas.UI.VersionControl.BranchDialog` | `UI/VersionControl/Atlas.UI.VersionControl.BranchDialog.pas` | Ordner `UI/VersionControl` |
| `Atlas.UI.VersionControl.WorkingCopies` | `UI/VersionControl/Atlas.UI.VersionControl.WorkingCopies.pas` | Ordner `UI/VersionControl` |

## Atlas.IDE.Debugger

| Unit | Datei | Begründung |
|---|---|---|
| `Atlas.Core.Debug.AccessViolation` | `Core/Debug/Atlas.Core.Debug.AccessViolation.pas` | Ordner `Core/Debug` |
| `Atlas.Core.Debug.CallStack` | `Core/Debug/Atlas.Core.Debug.CallStack.pas` | Ordner `Core/Debug` |
| `Atlas.Core.Debug.DialogCompletion` | `Core/Debug/Atlas.Core.Debug.DialogCompletion.pas` | Ordner `Core/Debug` |
| `Atlas.Core.Debug.DisplayRules` | `Core/Debug/Atlas.Core.Debug.DisplayRules.pas` | Ordner `Core/Debug` |
| `Atlas.Core.Debug.Evaluate` | `Core/Debug/Atlas.Core.Debug.Evaluate.pas` | Ordner `Core/Debug` |
| `Atlas.Core.Debug.EventBreak` | `Core/Debug/Atlas.Core.Debug.EventBreak.pas` | Ordner `Core/Debug` |
| `Atlas.Core.Debug.ExceptionBanner` | `Core/Debug/Atlas.Core.Debug.ExceptionBanner.pas` | Ordner `Core/Debug` |
| `Atlas.Core.Debug.ExceptionDialog` | `Core/Debug/Atlas.Core.Debug.ExceptionDialog.pas` | Ordner `Core/Debug` |
| `Atlas.Core.Debug.Exceptions` | `Core/Debug/Atlas.Core.Debug.Exceptions.pas` | Ordner `Core/Debug` |
| `Atlas.Core.Debug.IgnoreList` | `Core/Debug/Atlas.Core.Debug.IgnoreList.pas` | Ordner `Core/Debug` |
| `Atlas.Core.Debug.InlineValues` | `Core/Debug/Atlas.Core.Debug.InlineValues.pas` | Ordner `Core/Debug` |
| `Atlas.Core.Debug.Note` | `Core/Debug/Atlas.Core.Debug.Note.pas` | Ordner `Core/Debug` |
| `Atlas.Core.Debug.OwnCode` | `Core/Debug/Atlas.Core.Debug.OwnCode.pas` | Ordner `Core/Debug` |
| `Atlas.Core.Debug.StepFilter` | `Core/Debug/Atlas.Core.Debug.StepFilter.pas` | Ordner `Core/Debug` |
| `Atlas.Core.Debug.StepInto` | `Core/Debug/Atlas.Core.Debug.StepInto.pas` | Ordner `Core/Debug` |
| `Atlas.Core.Debug.Unavailable` | `Core/Debug/Atlas.Core.Debug.Unavailable.pas` | Ordner `Core/Debug` |
| `Atlas.Core.Debug.Visualizers` | `Core/Debug/Atlas.Core.Debug.Visualizers.pas` | Ordner `Core/Debug` |
| `Atlas.IDE.Debug.AccessViolation` | `IDE/Debug/Atlas.IDE.Debug.AccessViolation.pas` | Ordner `IDE/Debug` |
| `Atlas.IDE.Debug.AccessViolationUnderline` | `IDE/Debug/Atlas.IDE.Debug.AccessViolationUnderline.pas` | Ordner `IDE/Debug` |
| `Atlas.IDE.Debug.Breakpoints` | `IDE/Debug/Atlas.IDE.Debug.Breakpoints.pas` | Ordner `IDE/Debug` |
| `Atlas.IDE.Debug.Composition` | `IDE/Debug/Atlas.IDE.Debug.Composition.pas` | Anmeldung des Moduls `atlas.debugger`, #1455 |
| `Atlas.IDE.Debug.Composition.Values` | `IDE/Debug/Atlas.IDE.Debug.Composition.Values.pas` | Teile für Werte und Ausdrücke des Moduls `atlas.debugger`, #1455 |
| `Atlas.IDE.Debug.DialogCompletion` | `IDE/Debug/Atlas.IDE.Debug.DialogCompletion.pas` | Ordner `IDE/Debug` |
| `Atlas.IDE.Debug.DisplayRules` | `IDE/Debug/Atlas.IDE.Debug.DisplayRules.pas` | Ordner `IDE/Debug` |
| `Atlas.IDE.Debug.Evaluate` | `IDE/Debug/Atlas.IDE.Debug.Evaluate.pas` | Ordner `IDE/Debug` |
| `Atlas.IDE.Debug.EvaluateHook` | `IDE/Debug/Atlas.IDE.Debug.EvaluateHook.pas` | Ordner `IDE/Debug` |
| `Atlas.IDE.Debug.EvaluateStore` | `IDE/Debug/Atlas.IDE.Debug.EvaluateStore.pas` | Ordner `IDE/Debug` |
| `Atlas.IDE.Debug.EvaluateWindow` | `IDE/Debug/Atlas.IDE.Debug.EvaluateWindow.pas` | Ordner `IDE/Debug` |
| `Atlas.IDE.Debug.Evaluator` | `IDE/Debug/Atlas.IDE.Debug.Evaluator.pas` | Ordner `IDE/Debug` |
| `Atlas.IDE.Debug.EventBreak` | `IDE/Debug/Atlas.IDE.Debug.EventBreak.pas` | Ordner `IDE/Debug` |
| `Atlas.IDE.Debug.ExceptionBar` | `IDE/Debug/Atlas.IDE.Debug.ExceptionBar.pas` | Ordner `IDE/Debug` |
| `Atlas.IDE.Debug.ExceptionDialog` | `IDE/Debug/Atlas.IDE.Debug.ExceptionDialog.pas` | Ordner `IDE/Debug` |
| `Atlas.IDE.Debug.Exceptions` | `IDE/Debug/Atlas.IDE.Debug.Exceptions.pas` | Ordner `IDE/Debug` |
| `Atlas.IDE.Debug.ExceptionsWindow` | `IDE/Debug/Atlas.IDE.Debug.ExceptionsWindow.pas` | Ordner `IDE/Debug` |
| `Atlas.IDE.Debug.InlineValues` | `IDE/Debug/Atlas.IDE.Debug.InlineValues.pas` | Ordner `IDE/Debug` |
| `Atlas.IDE.Debug.OwnCode` | `IDE/Debug/Atlas.IDE.Debug.OwnCode.pas` | Ordner `IDE/Debug` |
| `Atlas.IDE.Debug.Report` | `IDE/Debug/Atlas.IDE.Debug.Report.pas` | Bericht über die Debug-Sitzung (IAtlasDebugReportSource), #1455 |
| `Atlas.IDE.Debug.Session` | `IDE/Debug/Atlas.IDE.Debug.Session.pas` | Ordner `IDE/Debug` |
| `Atlas.IDE.Debug.Sources` | `IDE/Debug/Atlas.IDE.Debug.Sources.pas` | Ordner `IDE/Debug` |
| `Atlas.IDE.Debug.StepFilter` | `IDE/Debug/Atlas.IDE.Debug.StepFilter.pas` | Ordner `IDE/Debug` |
| `Atlas.IDE.Debug.StepFilterWindow` | `IDE/Debug/Atlas.IDE.Debug.StepFilterWindow.pas` | Ordner `IDE/Debug` |
| `Atlas.IDE.Debug.StepInto` | `IDE/Debug/Atlas.IDE.Debug.StepInto.pas` | Ordner `IDE/Debug` |
| `Atlas.IDE.Debug.Trace` | `IDE/Debug/Atlas.IDE.Debug.Trace.pas` | Ordner `IDE/Debug` |
| `Atlas.IDE.Debug.Unavailable` | `IDE/Debug/Atlas.IDE.Debug.Unavailable.pas` | Ordner `IDE/Debug` |
| `Atlas.IDE.Debug.UnavailableFixes` | `IDE/Debug/Atlas.IDE.Debug.UnavailableFixes.pas` | Ordner `IDE/Debug` |
| `Atlas.IDE.Debug.Visualizers` | `IDE/Debug/Atlas.IDE.Debug.Visualizers.pas` | Ordner `IDE/Debug` |
| `Atlas.UI.Debug.AccessViolation` | `UI/Debug/Atlas.UI.Debug.AccessViolation.pas` | Ordner `UI/Debug` |
| `Atlas.UI.Debug.EvaluateFrame` | `UI/Debug/Atlas.UI.Debug.EvaluateFrame.pas` | Ordner `UI/Debug` |
| `Atlas.UI.Debug.EvaluateTree` | `UI/Debug/Atlas.UI.Debug.EvaluateTree.pas` | Ordner `UI/Debug` |
| `Atlas.UI.Debug.EventBreak` | `UI/Debug/Atlas.UI.Debug.EventBreak.pas` | Ordner `UI/Debug` |
| `Atlas.UI.Debug.ExceptionBar` | `UI/Debug/Atlas.UI.Debug.ExceptionBar.pas` | Ordner `UI/Debug` |
| `Atlas.UI.Debug.ExceptionStack` | `UI/Debug/Atlas.UI.Debug.ExceptionStack.pas` | Ordner `UI/Debug` |
| `Atlas.UI.Debug.ExceptionsFrame` | `UI/Debug/Atlas.UI.Debug.ExceptionsFrame.pas` | Ordner `UI/Debug` |
| `Atlas.UI.Debug.SettingsSection` | `UI/Debug/Atlas.UI.Debug.SettingsSection.pas` | Ordner `UI/Debug`; Einstellungen des Moduls als Abschnitte (#1456) |
| `Atlas.UI.Debug.StepFilterFrame` | `UI/Debug/Atlas.UI.Debug.StepFilterFrame.pas` | Ordner `UI/Debug` |
| `Atlas.UI.Debug.StepInto` | `UI/Debug/Atlas.UI.Debug.StepInto.pas` | Ordner `UI/Debug` |
| `Atlas.UI.Debug.Strings` | `UI/Debug/Atlas.UI.Debug.Strings.pas` | Texte des Moduls (Debugger), Sprache von Base, #1455 |
| `Atlas.UI.Debug.Viewer` | `UI/Debug/Atlas.UI.Debug.Viewer.pas` | Ordner `UI/Debug` |

## Atlas.IDE.Tracker

| Unit | Datei | Begründung |
|---|---|---|
| `Atlas.Core.Ci.Adapters.Credentials` | `Core/Ci/Atlas.Core.Ci.Adapters.Credentials.pas` | Ordner `Core/Ci` |
| `Atlas.Core.Ci.Adapters.Http` | `Core/Ci/Atlas.Core.Ci.Adapters.Http.pas` | Ordner `Core/Ci` |
| `Atlas.Core.Ci.Contract` | `Core/Ci/Atlas.Core.Ci.Contract.pas` | Ordner `Core/Ci` |
| `Atlas.Core.Ci.Internals.Addresses` | `Core/Ci/Atlas.Core.Ci.Internals.Addresses.pas` | Ordner `Core/Ci` |
| `Atlas.Core.Ci.Providers.Jenkins` | `Core/Ci/Atlas.Core.Ci.Providers.Jenkins.pas` | Ordner `Core/Ci` |
| `Atlas.Core.Tracker.Adapters.LocalFiles` | `Core/Tracker/Atlas.Core.Tracker.Adapters.LocalFiles.pas` | Ordner `Core/Tracker`; Platte über System.IOUtils, nur in der Composition erzeugt (Paket 2d) |
| `Atlas.Core.Tracker.Adapters.Shell` | `Core/Tracker/Atlas.Core.Tracker.Adapters.Shell.pas` | Ordner `Core/Tracker`; ShellExecute, nur in der Composition erzeugt (Paket 2d) |
| `Atlas.Core.Tracker.Attach` | `Core/Tracker/Atlas.Core.Tracker.Attach.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.BlameLinks` | `Core/Tracker/Atlas.Core.Tracker.BlameLinks.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.Board` | `Core/Tracker/Atlas.Core.Tracker.Board.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.Checklist` | `Core/Tracker/Atlas.Core.Tracker.Checklist.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.CodeLinks` | `Core/Tracker/Atlas.Core.Tracker.CodeLinks.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.CommentEditor` | `Core/Tracker/Atlas.Core.Tracker.CommentEditor.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.CommitHook` | `Core/Tracker/Atlas.Core.Tracker.CommitHook.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.Connections` | `Core/Tracker/Atlas.Core.Tracker.Connections.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.Contract` | `Core/Tracker/Atlas.Core.Tracker.Contract.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.Contract.Files` | `Core/Tracker/Atlas.Core.Tracker.Contract.Files.pas` | Ordner `Core/Tracker`; Verträge für Platte und Shell des Trackers (Paket 2d) |
| `Atlas.Core.Tracker.Development` | `Core/Tracker/Atlas.Core.Tracker.Development.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.Files` | `Core/Tracker/Atlas.Core.Tracker.Files.pas` | Ordner `Core/Tracker`; Anmeldung von Platte und Shell, leere Umsetzung ohne Anmeldung (Paket 2d) |
| `Atlas.Core.Tracker.Internals.GitHubApi` | `Core/Tracker/Atlas.Core.Tracker.Internals.GitHubApi.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.Internals.GitHubJson` | `Core/Tracker/Atlas.Core.Tracker.Internals.GitHubJson.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.GitHubParse` | `Core/Tracker/Atlas.Core.Tracker.GitHubParse.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.IssueCache` | `Core/Tracker/Atlas.Core.Tracker.IssueCache.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.Links` | `Core/Tracker/Atlas.Core.Tracker.Links.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.Markdown` | `Core/Tracker/Atlas.Core.Tracker.Markdown.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.MyIssues` | `Core/Tracker/Atlas.Core.Tracker.MyIssues.pas` | Ordner `Core/Tracker`, Kachel aus der Willkommensseite, #1455 |
| `Atlas.Core.Tracker.Naming` | `Core/Tracker/Atlas.Core.Tracker.Naming.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.NewIssue` | `Core/Tracker/Atlas.Core.Tracker.NewIssue.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.Notify` | `Core/Tracker/Atlas.Core.Tracker.Notify.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.PaletteSearch` | `Core/Tracker/Atlas.Core.Tracker.PaletteSearch.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.Preview` | `Core/Tracker/Atlas.Core.Tracker.Preview.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.Projects` | `Core/Tracker/Atlas.Core.Tracker.Projects.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.Providers.GitHub` | `Core/Tracker/Atlas.Core.Tracker.Providers.GitHub.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.GitHubBoards` | `Core/Tracker/Atlas.Core.Tracker.GitHubBoards.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.Providers.YouTrack` | `Core/Tracker/Atlas.Core.Tracker.Providers.YouTrack.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.Internals.YouTrackJson` | `Core/Tracker/Atlas.Core.Tracker.Internals.YouTrackJson.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.YouTrackApi` | `Core/Tracker/Atlas.Core.Tracker.YouTrackApi.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.YouTrackParse` | `Core/Tracker/Atlas.Core.Tracker.YouTrackParse.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.YouTrackBoards` | `Core/Tracker/Atlas.Core.Tracker.YouTrackBoards.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.Queries` | `Core/Tracker/Atlas.Core.Tracker.Queries.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.QueryTest` | `Core/Tracker/Atlas.Core.Tracker.QueryTest.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.SettingsTables` | `Core/Tracker/Atlas.Core.Tracker.SettingsTables.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.Sprint` | `Core/Tracker/Atlas.Core.Tracker.Sprint.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.Templates` | `Core/Tracker/Atlas.Core.Tracker.Templates.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.TestResults` | `Core/Tracker/Atlas.Core.Tracker.TestResults.pas` | Ordner `Core/Tracker`, Kachel „Testergebnisse“ aus der Willkommensseite, #1455 |
| `Atlas.Core.Tracker.TimeClock` | `Core/Tracker/Atlas.Core.Tracker.TimeClock.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.TimeLog` | `Core/Tracker/Atlas.Core.Tracker.TimeLog.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.Workflow` | `Core/Tracker/Atlas.Core.Tracker.Workflow.pas` | Ordner `Core/Tracker` |
| `Atlas.Core.Tracker.YouTrackWorkflow` | `Core/Tracker/Atlas.Core.Tracker.YouTrackWorkflow.pas` | Ordner `Core/Tracker` |
| `Atlas.IDE.Tracker.Access` | `IDE/Tracker/Atlas.IDE.Tracker.Access.pas` | Ordner `IDE/Tracker`, Zugang zu Issue-Tracker und Build-Server aus der Kompositionswurzel, #1455 |
| `Atlas.IDE.Tracker.Attach` | `IDE/Tracker/Atlas.IDE.Tracker.Attach.pas` | Ordner `IDE/Tracker` |
| `Atlas.IDE.Tracker.BlameLinks` | `IDE/Tracker/Atlas.IDE.Tracker.BlameLinks.pas` | Ordner `IDE/Tracker` |
| `Atlas.IDE.Tracker.BlameScope` | `IDE/Tracker/Atlas.IDE.Tracker.BlameScope.pas` | Ordner `IDE/Tracker` |
| `Atlas.IDE.Tracker.Board` | `IDE/Tracker/Atlas.IDE.Tracker.Board.pas` | Ordner `IDE/Tracker` |
| `Atlas.IDE.Tracker.BoardWindow` | `IDE/Tracker/Atlas.IDE.Tracker.BoardWindow.pas` | Ordner `IDE/Tracker` |
| `Atlas.IDE.Tracker.CodeLinks` | `IDE/Tracker/Atlas.IDE.Tracker.CodeLinks.pas` | Ordner `IDE/Tracker` |
| `Atlas.IDE.Tracker.CodeLinkMarks` | `IDE/Tracker/Atlas.IDE.Tracker.CodeLinkMarks.pas` | Ordner `IDE/Tracker` |
| `Atlas.IDE.Tracker.CommentAssist` | `IDE/Tracker/Atlas.IDE.Tracker.CommentAssist.pas` | Ordner `IDE/Tracker` |
| `Atlas.IDE.Tracker.Composition` | `IDE/Tracker/Atlas.IDE.Tracker.Composition.pas` | Ordner `IDE/Tracker` |
| `Atlas.IDE.Tracker.Development` | `IDE/Tracker/Atlas.IDE.Tracker.Development.pas` | Ordner `IDE/Tracker` |
| `Atlas.IDE.Tracker.IssueContext` | `IDE/Tracker/Atlas.IDE.Tracker.IssueContext.pas` | Ordner `IDE/Tracker` |
| `Atlas.IDE.Tracker.IssueLookups` | `IDE/Tracker/Atlas.IDE.Tracker.IssueLookups.pas` | Ordner `IDE/Tracker` |
| `Atlas.IDE.Tracker.IssueChecklists` | `IDE/Tracker/Atlas.IDE.Tracker.IssueChecklists.pas` | Ordner `IDE/Tracker` |
| `Atlas.IDE.Tracker.IssueLinkWrites` | `IDE/Tracker/Atlas.IDE.Tracker.IssueLinkWrites.pas` | Ordner `IDE/Tracker` |
| `Atlas.IDE.Tracker.IssueMedia` | `IDE/Tracker/Atlas.IDE.Tracker.IssueMedia.pas` | Ordner `IDE/Tracker` |
| `Atlas.IDE.Tracker.IssueComments` | `IDE/Tracker/Atlas.IDE.Tracker.IssueComments.pas` | Ordner `IDE/Tracker` |
| `Atlas.IDE.Tracker.IssuePreview` | `IDE/Tracker/Atlas.IDE.Tracker.IssuePreview.pas` | Ordner `IDE/Tracker` |
| `Atlas.IDE.Tracker.IssueWindow` | `IDE/Tracker/Atlas.IDE.Tracker.IssueWindow.pas` | Ordner `IDE/Tracker` |
| `Atlas.IDE.Tracker.MyIssues` | `IDE/Tracker/Atlas.IDE.Tracker.MyIssues.pas` | Ordner `IDE/Tracker`, Kachel aus der Willkommensseite, #1455 |
| `Atlas.IDE.Tracker.IssuesContext` | `IDE/Tracker/Atlas.IDE.Tracker.IssuesContext.pas` | Ordner `IDE/Tracker`, gemeinsamer Stand von „Meine Issues“, #1455 |
| `Atlas.IDE.Tracker.IssuesServices` | `IDE/Tracker/Atlas.IDE.Tracker.IssuesServices.pas` | Ordner `IDE/Tracker`, Dienste von „Meine Issues“, #1455 |
| `Atlas.IDE.Tracker.IssueCommands` | `IDE/Tracker/Atlas.IDE.Tracker.IssueCommands.pas` | Ordner `IDE/Tracker`, Befehle von „Meine Issues“, #1455 |
| `Atlas.IDE.Tracker.IssuesStatus` | `IDE/Tracker/Atlas.IDE.Tracker.IssuesStatus.pas` | Ordner `IDE/Tracker`, Statusfeld und Titel von „Meine Issues“, #1455 |
| `Atlas.IDE.Tracker.IssuesQuery` | `IDE/Tracker/Atlas.IDE.Tracker.IssuesQuery.pas` | Ordner `IDE/Tracker`, Abfrage von „Meine Issues“, #1455 |
| `Atlas.IDE.Tracker.IssueStart` | `IDE/Tracker/Atlas.IDE.Tracker.IssueStart.pas` | Ordner `IDE/Tracker`, „Beginnen“ und „Beenden“, #1455 |
| `Atlas.IDE.Tracker.NewIssue` | `IDE/Tracker/Atlas.IDE.Tracker.NewIssue.pas` | Ordner `IDE/Tracker`, Kachel aus der Willkommensseite, #1455 |
| `Atlas.IDE.Tracker.NewIssuePlace` | `IDE/Tracker/Atlas.IDE.Tracker.NewIssuePlace.pas` | Ordner `IDE/Tracker`, Editorseite von „Issue anlegen“, #1455 |
| `Atlas.IDE.Tracker.Notify` | `IDE/Tracker/Atlas.IDE.Tracker.Notify.pas` | Ordner `IDE/Tracker` |
| `Atlas.IDE.Tracker.PaletteSearch` | `IDE/Tracker/Atlas.IDE.Tracker.PaletteSearch.pas` | Ordner `IDE/Tracker` |
| `Atlas.IDE.Tracker.Parts` | `IDE/Tracker/Atlas.IDE.Tracker.Parts.pas` | Teile, Befehle und Menü des Moduls; die Komposition meldet nur an und baut die Adapter, #1455 |
| `Atlas.IDE.Tracker.Settings` | `IDE/Tracker/Atlas.IDE.Tracker.Settings.pas` | Ordner `IDE/Tracker` |
| `Atlas.UI.Tracker.SettingsBranches` | `UI/Tracker/Atlas.UI.Tracker.SettingsBranches.pas` | Unterpunkt „Versionsverwaltung“ des Issue-Trackers, nur mit Versionsverwaltung (#1903) |
| `Atlas.IDE.Tracker.SprintTile` | `IDE/Tracker/Atlas.IDE.Tracker.SprintTile.pas` | Ordner `IDE/Tracker`, Kachel aus der Willkommensseite, #1455 |
| `Atlas.IDE.Tracker.TestActions` | `IDE/Tracker/Atlas.IDE.Tracker.TestActions.pas` | Aktionen der Kachel „Testergebnisse“ (Test öffnen, erneut ausführen, debuggen, Build im Browser), #1455 |
| `Atlas.IDE.Tracker.TestResults` | `IDE/Tracker/Atlas.IDE.Tracker.TestResults.pas` | Ordner `IDE/Tracker`, Kachel „Testergebnisse“ aus der Willkommensseite, #1455 |
| `Atlas.IDE.Tracker.Tiles` | `IDE/Tracker/Atlas.IDE.Tracker.Tiles.pas` | Kacheln „Meine Issues“ und „Sprint“ (`IAtlasWelcomeTile`), #1455 |
| `Atlas.IDE.Tracker.TimeTracking` | `IDE/Tracker/Atlas.IDE.Tracker.TimeTracking.pas` | Ordner `IDE/Tracker` |
| `Atlas.IDE.Tracker.WelcomeLink` | `IDE/Tracker/Atlas.IDE.Tracker.WelcomeLink.pas` | Projekte und Meldungen der Willkommensseite über `Atlas.IDE.Contracts.WelcomeTiles`, #1455 |
| `Atlas.IDE.Tracker.Workflow` | `IDE/Tracker/Atlas.IDE.Tracker.Workflow.pas` | Ordner `IDE/Tracker` |
| `Atlas.UI.Tracker.AttachDialog` | `UI/Tracker/Atlas.UI.Tracker.AttachDialog.pas` | Ordner `UI/Tracker` |
| `Atlas.UI.Tracker.BoardFrame` | `UI/Tracker/Atlas.UI.Tracker.BoardFrame.pas` | Ordner `UI/Tracker` |
| `Atlas.UI.Tracker.Capture` | `UI/Tracker/Atlas.UI.Tracker.Capture.pas` | Ordner `UI/Tracker` |
| `Atlas.UI.Tracker.CiLogin` | `UI/Tracker/Atlas.UI.Tracker.CiLogin.pas` | Ordner `UI/Tracker`, Abfrage des Zugangs zu Build-Server und Tracker, #1455 |
| `Atlas.UI.Tracker.CommentEditor` | `UI/Tracker/Atlas.UI.Tracker.CommentEditor.pas` | Ordner `UI/Tracker` |
| `Atlas.UI.Tracker.DevelopmentView` | `UI/Tracker/Atlas.UI.Tracker.DevelopmentView.pas` | Ordner `UI/Tracker` |
| `Atlas.UI.Tracker.DocBox` | `UI/Tracker/Atlas.UI.Tracker.DocBox.pas` | Ordner `UI/Tracker` |
| `Atlas.UI.Tracker.EndDialog` | `UI/Tracker/Atlas.UI.Tracker.EndDialog.pas` | Ordner `UI/Tracker` |
| `Atlas.UI.Tracker.ImageMarkup` | `UI/Tracker/Atlas.UI.Tracker.ImageMarkup.pas` | Ordner `UI/Tracker` |
| `Atlas.UI.Tracker.IssueBoxes` | `UI/Tracker/Atlas.UI.Tracker.IssueBoxes.pas` | Ordner `UI/Tracker` |
| `Atlas.UI.Tracker.IssueFrame` | `UI/Tracker/Atlas.UI.Tracker.IssueFrame.pas` | Ordner `UI/Tracker` |
| `Atlas.UI.Tracker.IssueTip` | `UI/Tracker/Atlas.UI.Tracker.IssueTip.pas` | Ordner `UI/Tracker` |
| `Atlas.UI.Tracker.LinkDialogs` | `UI/Tracker/Atlas.UI.Tracker.LinkDialogs.pas` | Ordner `UI/Tracker` |
| `Atlas.UI.Tracker.MoveDialog` | `UI/Tracker/Atlas.UI.Tracker.MoveDialog.pas` | Ordner `UI/Tracker` |
| `Atlas.UI.Tracker.MyIssues` | `UI/Tracker/Atlas.UI.Tracker.MyIssues.pas` | Ordner `UI/Tracker`, Kachel aus der Willkommensseite, #1455 |
| `Atlas.UI.Tracker.NewIssueDialog` | `UI/Tracker/Atlas.UI.Tracker.NewIssueDialog.pas` | Ordner `UI/Tracker`, Kachel aus der Willkommensseite, #1455 |
| `Atlas.UI.Tracker.Notify` | `UI/Tracker/Atlas.UI.Tracker.Notify.pas` | Ordner `UI/Tracker` |
| `Atlas.UI.Tracker.QueryDialog` | `UI/Tracker/Atlas.UI.Tracker.QueryDialog.pas` | Ordner `UI/Tracker` |
| `Atlas.UI.Tracker.SettingsConnections` | `UI/Tracker/Atlas.UI.Tracker.SettingsConnections.pas` | Ordner `UI/Tracker` |
| `Atlas.UI.Tracker.SettingsGeneral` | `UI/Tracker/Atlas.UI.Tracker.SettingsGeneral.pas` | Ordner `UI/Tracker` |
| `Atlas.UI.Tracker.SettingsProjects` | `UI/Tracker/Atlas.UI.Tracker.SettingsProjects.pas` | Ordner `UI/Tracker` |
| `Atlas.UI.Tracker.SettingsQueries` | `UI/Tracker/Atlas.UI.Tracker.SettingsQueries.pas` | Ordner `UI/Tracker` |
| `Atlas.UI.Tracker.SettingsRows` | `UI/Tracker/Atlas.UI.Tracker.SettingsRows.pas` | Ordner `UI/Tracker` |
| `Atlas.UI.Tracker.SettingsSection` | `UI/Tracker/Atlas.UI.Tracker.SettingsSection.pas` | Ordner `UI/Tracker` |
| `Atlas.UI.Tracker.SettingsSnippets` | `UI/Tracker/Atlas.UI.Tracker.SettingsSnippets.pas` | Ordner `UI/Tracker` |
| `Atlas.UI.Tracker.SettingsWorkflow` | `UI/Tracker/Atlas.UI.Tracker.SettingsWorkflow.pas` | Ordner `UI/Tracker` |
| `Atlas.UI.Tracker.SprintTile` | `UI/Tracker/Atlas.UI.Tracker.SprintTile.pas` | Ordner `UI/Tracker`, Kachel aus der Willkommensseite, #1455 |
| `Atlas.UI.Tracker.Strings` | `UI/Tracker/Atlas.UI.Tracker.Strings.pas` | Texte des Moduls (Tracker), Sprache von Base, #1455 |
| `Atlas.UI.Tracker.TestResults` | `UI/Tracker/Atlas.UI.Tracker.TestResults.pas` | Ordner `UI/Tracker`, Kachel „Testergebnisse“ aus der Willkommensseite, #1455 |
| `Atlas.UI.Tracker.TileView` | `UI/Tracker/Atlas.UI.Tracker.TileView.pas` | Grundlage der Kachel-Ansichten (`IAtlasWelcomeTileView`), #1455 |
| `Atlas.UI.Tracker.TimeDialog` | `UI/Tracker/Atlas.UI.Tracker.TimeDialog.pas` | Ordner `UI/Tracker` |
| `Atlas.UI.Tracker.TimeList` | `UI/Tracker/Atlas.UI.Tracker.TimeList.pas` | Ordner `UI/Tracker` |
| `Atlas.UI.Tracker.ValueBox` | `UI/Tracker/Atlas.UI.Tracker.ValueBox.pas` | Ordner `UI/Tracker` |

## Atlas.IDE.Welcome

| Unit | Datei | Begründung |
|---|---|---|
| `Atlas.Core.Welcome.Backup` | `Core/Welcome/Atlas.Core.Welcome.Backup.pas` | Ordner `Core/Welcome` |
| `Atlas.Core.Welcome.Continue` | `Core/Welcome/Atlas.Core.Welcome.Continue.pas` | Ordner `Core/Welcome` |
| `Atlas.Core.Welcome.Discover` | `Core/Welcome/Atlas.Core.Welcome.Discover.pas` | Ordner `Core/Welcome` |
| `Atlas.Core.Welcome.AccountName` | `Core/Welcome/Atlas.Core.Welcome.AccountName.pas` | Ordner `Core/Welcome` |
| `Atlas.Core.Welcome.Greeting` | `Core/Welcome/Atlas.Core.Welcome.Greeting.pas` | Ordner `Core/Welcome` |
| `Atlas.Core.Welcome.Help` | `Core/Welcome/Atlas.Core.Welcome.Help.pas` | Ordner `Core/Welcome` |
| `Atlas.Core.Welcome.HostLayout` | `Core/Welcome/Atlas.Core.Welcome.HostLayout.pas` | Ordner `Core/Welcome` |
| `Atlas.Core.Welcome.IndexFiles` | `Core/Welcome/Atlas.Core.Welcome.IndexFiles.pas` | Ordner `Core/Welcome` |
| `Atlas.Core.Welcome.Layout` | `Core/Welcome/Atlas.Core.Welcome.Layout.pas` | Ordner `Core/Welcome` |
| `Atlas.Core.Welcome.Layouts` | `Core/Welcome/Atlas.Core.Welcome.Layouts.pas` | Ordner `Core/Welcome` |
| `Atlas.Core.Welcome.Projects` | `Core/Welcome/Atlas.Core.Welcome.Projects.pas` | Ordner `Core/Welcome` |
| `Atlas.Core.Welcome.QuickActions` | `Core/Welcome/Atlas.Core.Welcome.QuickActions.pas` | Ordner `Core/Welcome` |
| `Atlas.Core.Welcome.Saved` | `Core/Welcome/Atlas.Core.Welcome.Saved.pas` | Ordner `Core/Welcome` |
| `Atlas.Core.Welcome.Scroll` | `Core/Welcome/Atlas.Core.Welcome.Scroll.pas` | Ordner `Core/Welcome` |
| `Atlas.Core.Welcome.Search` | `Core/Welcome/Atlas.Core.Welcome.Search.pas` | Ordner `Core/Welcome` |
| `Atlas.Core.Welcome.Sections` | `Core/Welcome/Atlas.Core.Welcome.Sections.pas` | Ordner `Core/Welcome` |
| `Atlas.Core.Welcome.Setup` | `Core/Welcome/Atlas.Core.Welcome.Setup.pas` | Ordner `Core/Welcome` |
| `Atlas.Core.Welcome.State` | `Core/Welcome/Atlas.Core.Welcome.State.pas` | Ordner `Core/Welcome` |
| `Atlas.Core.Welcome.Trends` | `Core/Welcome/Atlas.Core.Welcome.Trends.pas` | Ordner `Core/Welcome` |
| `Atlas.Core.Welcome.Unsaved` | `Core/Welcome/Atlas.Core.Welcome.Unsaved.pas` | Ordner `Core/Welcome` |
| `Atlas.Core.Welcome.WhatsNew` | `Core/Welcome/Atlas.Core.Welcome.WhatsNew.pas` | Ordner `Core/Welcome` |
| `Atlas.IDE.Welcome.Commands` | `IDE/Welcome/Atlas.IDE.Welcome.Commands.pas` | Ordner `IDE/Welcome` |
| `Atlas.IDE.Welcome.Areas` | `IDE/Welcome/Atlas.IDE.Welcome.Areas.pas` | Ordner `IDE/Welcome` |
| `Atlas.IDE.Welcome.IdeLayout` | `IDE/Welcome/Atlas.IDE.Welcome.IdeLayout.pas` | Ordner `IDE/Welcome` |
| `Atlas.IDE.Welcome.ProjectWatch` | `IDE/Welcome/Atlas.IDE.Welcome.ProjectWatch.pas` | Ordner `IDE/Welcome` |
| `Atlas.IDE.Welcome.Composition` | `IDE/Welcome/Atlas.IDE.Welcome.Composition.pas` | Anmeldung des Moduls `atlas.welcome` (Teil Welcome, Befehle, Menüeinträge), #1455 |
| `Atlas.IDE.Welcome.Continue` | `IDE/Welcome/Atlas.IDE.Welcome.Continue.pas` | Ordner `IDE/Welcome` |
| `Atlas.IDE.Welcome.Continue.Editor` | `IDE/Welcome/Atlas.IDE.Welcome.Continue.Editor.pas` | Ordner `IDE/Welcome` |
| `Atlas.IDE.Welcome.Continue.Saved` | `IDE/Welcome/Atlas.IDE.Welcome.Continue.Saved.pas` | Ordner `IDE/Welcome` |
| `Atlas.IDE.Welcome.Discover` | `IDE/Welcome/Atlas.IDE.Welcome.Discover.pas` | Ordner `IDE/Welcome` |
| `Atlas.IDE.Welcome.Help` | `IDE/Welcome/Atlas.IDE.Welcome.Help.pas` | Ordner `IDE/Welcome` |
| `Atlas.IDE.Welcome.Layouts` | `IDE/Welcome/Atlas.IDE.Welcome.Layouts.pas` | Ordner `IDE/Welcome` |
| `Atlas.IDE.Welcome.TileProjects` | `IDE/Welcome/Atlas.IDE.Welcome.TileProjects.pas` | Bereich „Projekte“ für Kacheln anderer Module (IAtlasWelcomeProjects), #1455 |
| `Atlas.IDE.Welcome.Tiles` | `IDE/Welcome/Atlas.IDE.Welcome.Tiles.pas` | Kacheln anderer Module über `Atlas.IDE.Contracts.WelcomeTiles` zeigen, Board und Projekte bereitstellen, #1455 |
| `Atlas.IDE.Welcome.Listener` | `IDE/Welcome/Atlas.IDE.Welcome.Listener.pas` | Ende von Projektaufgaben, Testläufen und Befehlsnutzung an die Seite, #1455 |
| `Atlas.IDE.Welcome.Settings` | `IDE/Welcome/Atlas.IDE.Welcome.Settings.pas` | Anbieter des Abschnitts im Optionsdialog mit seinen Haken, #1456 |
| `Atlas.IDE.Welcome.Neighbors` | `IDE/Welcome/Atlas.IDE.Welcome.Neighbors.pas` | Schnellaktionen und Einrichtung über die Verträge der Module Build-Pipeline, Tests, Build und Prüfregeln, #1455 |
| `Atlas.IDE.Welcome.Page` | `IDE/Welcome/Atlas.IDE.Welcome.Page.pas` | Ordner `IDE/Welcome` |
| `Atlas.IDE.Welcome.Projects` | `IDE/Welcome/Atlas.IDE.Welcome.Projects.pas` | Ordner `IDE/Welcome` |
| `Atlas.IDE.Welcome.QuickActions` | `IDE/Welcome/Atlas.IDE.Welcome.QuickActions.pas` | Ordner `IDE/Welcome` |
| `Atlas.IDE.Welcome.Registry` | `IDE/Welcome/Atlas.IDE.Welcome.Registry.pas` | Ordner `IDE/Welcome` |
| `Atlas.IDE.Welcome.Search` | `IDE/Welcome/Atlas.IDE.Welcome.Search.pas` | Ordner `IDE/Welcome` |
| `Atlas.IDE.Welcome.Setup` | `IDE/Welcome/Atlas.IDE.Welcome.Setup.pas` | Ordner `IDE/Welcome` |
| `Atlas.IDE.Welcome.Setup.Paths` | `IDE/Welcome/Atlas.IDE.Welcome.Setup.Paths.pas` | Ordner `IDE/Welcome` |
| `Atlas.IDE.Welcome.Setup.ProjectEvents` | `IDE/Welcome/Atlas.IDE.Welcome.Setup.ProjectEvents.pas` | Ordner `IDE/Welcome` |
| `Atlas.IDE.Welcome.Startup` | `IDE/Welcome/Atlas.IDE.Welcome.Startup.pas` | Aufbau und Abbau der Seite aus den Diensten von Base, Kacheln anderer Module, #1455 |
| `Atlas.IDE.Welcome.State` | `IDE/Welcome/Atlas.IDE.Welcome.State.pas` | Ordner `IDE/Welcome` |
| `Atlas.IDE.Welcome.Trends` | `IDE/Welcome/Atlas.IDE.Welcome.Trends.pas` | Ordner `IDE/Welcome` |
| `Atlas.IDE.Welcome.Unsaved` | `IDE/Welcome/Atlas.IDE.Welcome.Unsaved.pas` | Ordner `IDE/Welcome` |
| `Atlas.IDE.Welcome.WhatsNew` | `IDE/Welcome/Atlas.IDE.Welcome.WhatsNew.pas` | Ordner `IDE/Welcome` |
| `Atlas.IDE.Welcome.Window` | `IDE/Welcome/Atlas.IDE.Welcome.Window.pas` | Ordner `IDE/Welcome` |
| `Atlas.UI.Welcome.Arrange` | `UI/Welcome/Atlas.UI.Welcome.Arrange.pas` | Ordner `UI/Welcome` |
| `Atlas.UI.Welcome.Board` | `UI/Welcome/Atlas.UI.Welcome.Board.pas` | Ordner `UI/Welcome` |
| `Atlas.UI.Welcome.Continue` | `UI/Welcome/Atlas.UI.Welcome.Continue.pas` | Ordner `UI/Welcome` |
| `Atlas.UI.Welcome.Discover` | `UI/Welcome/Atlas.UI.Welcome.Discover.pas` | Ordner `UI/Welcome` |
| `Atlas.UI.Welcome.Frame` | `UI/Welcome/Atlas.UI.Welcome.Frame.pas` | Ordner `UI/Welcome` |
| `Atlas.UI.Welcome.Header` | `UI/Welcome/Atlas.UI.Welcome.Header.pas` | Ordner `UI/Welcome` |
| `Atlas.UI.Welcome.Help` | `UI/Welcome/Atlas.UI.Welcome.Help.pas` | Ordner `UI/Welcome` |
| `Atlas.UI.Welcome.Projects` | `UI/Welcome/Atlas.UI.Welcome.Projects.pas` | Ordner `UI/Welcome` |
| `Atlas.UI.Welcome.Push` | `UI/Welcome/Atlas.UI.Welcome.Push.pas` | Ordner `UI/Welcome` |
| `Atlas.UI.Welcome.QuickActions` | `UI/Welcome/Atlas.UI.Welcome.QuickActions.pas` | Ordner `UI/Welcome` |
| `Atlas.UI.Welcome.SettingsLayouts` | `UI/Welcome/Atlas.UI.Welcome.SettingsLayouts.pas` | Ordner `UI/Welcome` |
| `Atlas.UI.Welcome.SettingsSection` | `UI/Welcome/Atlas.UI.Welcome.SettingsSection.pas` | Ordner `UI/Welcome` |
| `Atlas.UI.Welcome.Search` | `UI/Welcome/Atlas.UI.Welcome.Search.pas` | Ordner `UI/Welcome` |
| `Atlas.UI.Welcome.Setup` | `UI/Welcome/Atlas.UI.Welcome.Setup.pas` | Ordner `UI/Welcome` |
| `Atlas.UI.Welcome.SetupPreview` | `UI/Welcome/Atlas.UI.Welcome.SetupPreview.pas` | Ordner `UI/Welcome` |
| `Atlas.UI.Welcome.State` | `UI/Welcome/Atlas.UI.Welcome.State.pas` | Ordner `UI/Welcome` |
| `Atlas.UI.Welcome.Strings` | `UI/Welcome/Atlas.UI.Welcome.Strings.pas` | Texte des Moduls (Willkommensseite), Sprache von Base, #1455 |
| `Atlas.UI.Welcome.Trends` | `UI/Welcome/Atlas.UI.Welcome.Trends.pas` | Ordner `UI/Welcome` |
| `Atlas.UI.Welcome.Unsaved` | `UI/Welcome/Atlas.UI.Welcome.Unsaved.pas` | Ordner `UI/Welcome` |
| `Atlas.UI.Welcome.WhatsNew` | `UI/Welcome/Atlas.UI.Welcome.WhatsNew.pas` | Ordner `UI/Welcome` |

## Atlas.IDE.Analysis

| Unit | Datei | Begründung |
|---|---|---|
| `Atlas.Core.Analysis.MetricsLens` | `Core/Analysis/Atlas.Core.Analysis.MetricsLens.pas` | Ordner `Core/Analysis`; Beschriftung der Metrik-Lens (#66, #1756) |
| `Atlas.Core.Architecture.Model` | `Core/Architecture/Atlas.Core.Architecture.Model.pas` | Ordner `Core/Architecture` |
| `Atlas.Core.Architecture.Commands` | `Core/Architecture/Atlas.Core.Architecture.Commands.pas` | Ordner `Core/Architecture` |
| `Atlas.Core.Architecture.RoleUnit` | `Core/Architecture/Atlas.Core.Architecture.RoleUnit.pas` | Ordner `Core/Architecture`: Unit nach Architekturrolle, #1821 |
| `Atlas.Core.Architecture.MapState` | `Core/Architecture/Atlas.Core.Architecture.MapState.pas` | Ordner `Core/Architecture` |
| `Atlas.Core.Architecture.View` | `Core/Architecture/Atlas.Core.Architecture.View.pas` | Ordner `Core/Architecture` |
| `Atlas.Core.Hotspots.Model` | `Core/Hotspots/Atlas.Core.Hotspots.Model.pas` | Ordner `Core/Hotspots` |
| `Atlas.Core.UnitRelations.InterfaceCost` | `Core/UnitRelations/Atlas.Core.UnitRelations.InterfaceCost.pas` | Ordner `Core/UnitRelations` |
| `Atlas.Core.UnitRelations.Model` | `Core/UnitRelations/Atlas.Core.UnitRelations.Model.pas` | Ordner `Core/UnitRelations` |
| `Atlas.IDE.Analysis.Composition` | `IDE/Analysis/Atlas.IDE.Analysis.Composition.pas` | Anmeldung des Moduls `atlas.analysis`, #1455 |
| `Atlas.IDE.Analysis.MetricsLens` | `IDE/Analysis/Atlas.IDE.Analysis.MetricsLens.pas` | Ordner `IDE/Analysis`; Code Lens mit Code-Metriken (#66), bis #1756 in Base |
| `Atlas.IDE.Architecture.Service` | `IDE/Architecture/Atlas.IDE.Architecture.Service.pas` | Ordner `IDE/Architecture` |
| `Atlas.IDE.Architecture.RoleUnit` | `IDE/Architecture/Atlas.IDE.Architecture.RoleUnit.pas` | Ordner `IDE/Architecture`: Unit nach Architekturrolle, #1821 |
| `Atlas.IDE.Architecture.Window` | `IDE/Architecture/Atlas.IDE.Architecture.Window.pas` | Ordner `IDE/Architecture` |
| `Atlas.IDE.Hotspots.Service` | `IDE/Hotspots/Atlas.IDE.Hotspots.Service.pas` | Ordner `IDE/Hotspots` |
| `Atlas.IDE.Hotspots.Window` | `IDE/Hotspots/Atlas.IDE.Hotspots.Window.pas` | Ordner `IDE/Hotspots` |
| `Atlas.IDE.SymbolPath.Service` | `IDE/SymbolPath/Atlas.IDE.SymbolPath.Service.pas` | Ordner `IDE/SymbolPath` |
| `Atlas.IDE.UnitRelations.Service` | `IDE/UnitRelations/Atlas.IDE.UnitRelations.Service.pas` | Ordner `IDE/UnitRelations` |
| `Atlas.IDE.UnitRelations.Window` | `IDE/UnitRelations/Atlas.IDE.UnitRelations.Window.pas` | Ordner `IDE/UnitRelations` |
| `Atlas.UI.Analysis.SettingsSection` | `UI/Analysis/Atlas.UI.Analysis.SettingsSection.pas` | Ordner `UI/Analysis`; Einstellungen des Moduls als Abschnitte (#1456) |
| `Atlas.UI.Analysis.Strings` | `UI/Analysis/Atlas.UI.Analysis.Strings.pas` | Texte des Moduls (Analyse), Sprache von Base, #1455 |
| `Atlas.UI.Architecture.Assignment` | `UI/Architecture/Atlas.UI.Architecture.Assignment.pas` | Ordner `UI/Architecture` |
| `Atlas.UI.Architecture.RoleUnitDialog` | `UI/Architecture/Atlas.UI.Architecture.RoleUnitDialog.pas` | Ordner `UI/Architecture`: Dialog Unit nach Architekturrolle, #1821 |
| `Atlas.UI.Architecture.Frame` | `UI/Architecture/Atlas.UI.Architecture.Frame.pas` | Ordner `UI/Architecture` |
| `Atlas.UI.Architecture.Map` | `UI/Architecture/Atlas.UI.Architecture.Map.pas` | Ordner `UI/Architecture` |
| `Atlas.UI.Architecture.Slider` | `UI/Architecture/Atlas.UI.Architecture.Slider.pas` | Ordner `UI/Architecture` |
| `Atlas.UI.Hotspots.Chart` | `UI/Hotspots/Atlas.UI.Hotspots.Chart.pas` | Ordner `UI/Hotspots` |
| `Atlas.UI.Hotspots.Frame` | `UI/Hotspots/Atlas.UI.Hotspots.Frame.pas` | Ordner `UI/Hotspots` |
| `Atlas.UI.SymbolPath.Dialog` | `UI/SymbolPath/Atlas.UI.SymbolPath.Dialog.pas` | Ordner `UI/SymbolPath` |
| `Atlas.UI.UnitRelations.Frame` | `UI/UnitRelations/Atlas.UI.UnitRelations.Frame.pas` | Ordner `UI/UnitRelations` |

## Atlas.IDE.Designer

| Unit | Datei | Begründung |
|---|---|---|
| `Atlas.Core.Designer.ButtonBar` | `Core/Designer/Atlas.Core.Designer.ButtonBar.pas` | Ordner `Core/Designer` |
| `Atlas.Core.Designer.Components` | `Core/Designer/Atlas.Core.Designer.Components.pas` | Ordner `Core/Designer` |
| `Atlas.Core.Designer.DuplicateRow` | `Core/Designer/Atlas.Core.Designer.DuplicateRow.pas` | Ordner `Core/Designer` |
| `Atlas.Core.Designer.FitContainer` | `Core/Designer/Atlas.Core.Designer.FitContainer.pas` | Ordner `Core/Designer` |
| `Atlas.Core.Designer.NearAlign` | `Core/Designer/Atlas.Core.Designer.NearAlign.pas` | Ordner `Core/Designer` |
| `Atlas.Core.Designer.FitText` | `Core/Designer/Atlas.Core.Designer.FitText.pas` | Ordner `Core/Designer` |
| `Atlas.Core.Designer.FormModel` | `Core/Designer/Atlas.Core.Designer.FormModel.pas` | Ordner `Core/Designer` |
| `Atlas.Core.Designer.InsertSpace` | `Core/Designer/Atlas.Core.Designer.InsertSpace.pas` | Ordner `Core/Designer` |
| `Atlas.Core.Designer.Neighbours` | `Core/Designer/Atlas.Core.Designer.Neighbours.pas` | Ordner `Core/Designer` |
| `Atlas.Core.Designer.SelectionSets` | `Core/Designer/Atlas.Core.Designer.SelectionSets.pas` | Ordner `Core/Designer` |
| `Atlas.Core.Designer.Similar` | `Core/Designer/Atlas.Core.Designer.Similar.pas` | Ordner `Core/Designer` |
| `Atlas.IDE.Designer.Access` | `IDE/Designer/Atlas.IDE.Designer.Access.pas` | Ordner `IDE/Designer` |
| `Atlas.IDE.Designer.Arrange` | `IDE/Designer/Atlas.IDE.Designer.Arrange.pas` | Ordner `IDE/Designer` |
| `Atlas.IDE.Designer.Bar` | `IDE/Designer/Atlas.IDE.Designer.Bar.pas` | Ordner `IDE/Designer` |
| `Atlas.IDE.Designer.ButtonBar` | `IDE/Designer/Atlas.IDE.Designer.ButtonBar.pas` | Ordner `IDE/Designer` |
| `Atlas.IDE.Designer.Commands` | `IDE/Designer/Atlas.IDE.Designer.Commands.pas` | Ordner `IDE/Designer` |
| `Atlas.IDE.Designer.Composition` | `IDE/Designer/Atlas.IDE.Designer.Composition.pas` | Anmeldung des Moduls `atlas.designer`, #1455 |
| `Atlas.IDE.Designer.DuplicateRow` | `IDE/Designer/Atlas.IDE.Designer.DuplicateRow.pas` | Ordner `IDE/Designer` |
| `Atlas.IDE.Designer.FitContainer` | `IDE/Designer/Atlas.IDE.Designer.FitContainer.pas` | Ordner `IDE/Designer` |
| `Atlas.IDE.Designer.NearAlign` | `IDE/Designer/Atlas.IDE.Designer.NearAlign.pas` | Ordner `IDE/Designer` |
| `Atlas.IDE.Designer.FitText` | `IDE/Designer/Atlas.IDE.Designer.FitText.pas` | Ordner `IDE/Designer` |
| `Atlas.IDE.Designer.InsertSpace` | `IDE/Designer/Atlas.IDE.Designer.InsertSpace.pas` | Ordner `IDE/Designer` |
| `Atlas.IDE.Designer.Navigate` | `IDE/Designer/Atlas.IDE.Designer.Navigate.pas` | Ordner `IDE/Designer` |
| `Atlas.IDE.Designer.SearchItems` | `IDE/Designer/Atlas.IDE.Designer.SearchItems.pas` | Ordner `IDE/Designer` |
| `Atlas.IDE.Designer.Select` | `IDE/Designer/Atlas.IDE.Designer.Select.pas` | Ordner `IDE/Designer` |
| `Atlas.IDE.Designer.SelectionSets` | `IDE/Designer/Atlas.IDE.Designer.SelectionSets.pas` | Ordner `IDE/Designer` |
| `Atlas.IDE.Designer.Snapshot` | `IDE/Designer/Atlas.IDE.Designer.Snapshot.pas` | Ordner `IDE/Designer` |
| `Atlas.UI.Designer.Bar` | `UI/Designer/Atlas.UI.Designer.Bar.pas` | Ordner `UI/Designer` |
| `Atlas.UI.Designer.DuplicateDialog` | `UI/Designer/Atlas.UI.Designer.DuplicateDialog.pas` | Ordner `UI/Designer` |
| `Atlas.UI.Designer.Flash` | `UI/Designer/Atlas.UI.Designer.Flash.pas` | Ordner `UI/Designer` |
| `Atlas.UI.Designer.Outlines` | `UI/Designer/Atlas.UI.Designer.Outlines.pas` | Ordner `UI/Designer` |
| `Atlas.UI.Designer.Search` | `UI/Designer/Atlas.UI.Designer.Search.pas` | Ordner `UI/Designer` |
| `Atlas.UI.Designer.SettingsSection` | `UI/Designer/Atlas.UI.Designer.SettingsSection.pas` | Ordner `UI/Designer`; Einstellungen des Moduls als Abschnitte (#1456) |
| `Atlas.UI.Designer.SpaceDialog` | `UI/Designer/Atlas.UI.Designer.SpaceDialog.pas` | Ordner `UI/Designer` |
| `Atlas.UI.Designer.Strings` | `UI/Designer/Atlas.UI.Designer.Strings.pas` | Texte des Moduls (Formulardesigner), Sprache von Base, #1455 |
| `Atlas.UI.Designer.TabOverlay` | `UI/Designer/Atlas.UI.Designer.TabOverlay.pas` | Ordner `UI/Designer` |

## Atlas.IDE.Help

| Unit | Datei | Begründung |
|---|---|---|
| `Atlas.Core.Help.Links` | `Core/Help/Atlas.Core.Help.Links.pas` | Ziele der F1-Hilfe (Regel, Einstellung, Fenster), online und lokal, #1886 |
| `Atlas.IDE.Help.Composition` | `IDE/Help/Atlas.IDE.Help.Composition.pas` | Anmeldung des Moduls `atlas.help`, #1886 |
| `Atlas.IDE.Help.Pages` | `IDE/Help/Atlas.IDE.Help.Pages.pas` | Ordner `IDE/Help`: öffnet die Seite im Browser |
| `Atlas.UI.Help.SettingsSection` | `UI/Help/Atlas.UI.Help.SettingsSection.pas` | Ordner `UI/Help`; Einstellungen des Moduls als Abschnitte (#1456) |
| `Atlas.UI.Help.Strings` | `UI/Help/Atlas.UI.Help.Strings.pas` | Texte des Moduls (Hilfe), Sprache von Base, #1455 |

## Atlas.IDE.Search

| Unit | Datei | Begründung |
|---|---|---|
| `Atlas.Core.Query.Model` | `Core/Query/Atlas.Core.Query.Model.pas` | Ordner `Core/Query` |
| `Atlas.Core.Search.Files` | `Core/Search/Atlas.Core.Search.Files.pas` | Ordner `Core/Search` |
| `Atlas.Core.Search.History` | `Core/Search/Atlas.Core.Search.History.pas` | Ordner `Core/Search` |
| `Atlas.Core.Search.Matching` | `Core/Search/Atlas.Core.Search.Matching.pas` | Ordner `Core/Search` |
| `Atlas.Core.Search.Replace` | `Core/Search/Atlas.Core.Search.Replace.pas` | Ordner `Core/Search` |
| `Atlas.Core.Search.ReplaceList` | `Core/Search/Atlas.Core.Search.ReplaceList.pas` | Ordner `Core/Search` |
| `Atlas.Core.Search.Results` | `Core/Search/Atlas.Core.Search.Results.pas` | Ordner `Core/Search` |
| `Atlas.Core.Search.Scopes` | `Core/Search/Atlas.Core.Search.Scopes.pas` | Ordner `Core/Search` |
| `Atlas.Core.UnitSearch.Model` | `Core/UnitSearch/Atlas.Core.UnitSearch.Model.pas` | Ordner `Core/UnitSearch` |
| `Atlas.Core.UnitSearch.Sections` | `Core/UnitSearch/Atlas.Core.UnitSearch.Sections.pas` | Ordner `Core/UnitSearch` |
| `Atlas.Core.UnitSearch.State` | `Core/UnitSearch/Atlas.Core.UnitSearch.State.pas` | Ordner `Core/UnitSearch` |
| `Atlas.Core.UnitSearch.UseUnit` | `Core/UnitSearch/Atlas.Core.UnitSearch.UseUnit.pas` | Ordner `Core/UnitSearch` |
| `Atlas.IDE.Query.Service` | `IDE/Query/Atlas.IDE.Query.Service.pas` | Ordner `IDE/Query` |
| `Atlas.IDE.Query.Window` | `IDE/Query/Atlas.IDE.Query.Window.pas` | Ordner `IDE/Query` |
| `Atlas.IDE.Search.Commands` | `IDE/Search/Atlas.IDE.Search.Commands.pas` | Ordner `IDE/Search` |
| `Atlas.IDE.Search.AcrossFiles` | `IDE/Search/Atlas.IDE.Search.AcrossFiles.pas` | Ordner `IDE/Search` |
| `Atlas.IDE.Search.Counter` | `IDE/Search/Atlas.IDE.Search.Counter.pas` | Ordner `IDE/Search` |
| `Atlas.IDE.Search.Editor` | `IDE/Search/Atlas.IDE.Search.Editor.pas` | Ordner `IDE/Search` |
| `Atlas.IDE.Search.HistoryFile` | `IDE/Search/Atlas.IDE.Search.HistoryFile.pas` | Ordner `IDE/Search` |
| `Atlas.IDE.Search.Painter` | `IDE/Search/Atlas.IDE.Search.Painter.pas` | Ordner `IDE/Search` |
| `Atlas.IDE.Search.Replacing` | `IDE/Search/Atlas.IDE.Search.Replacing.pas` | Ordner `IDE/Search` |
| `Atlas.IDE.Search.Session` | `IDE/Search/Atlas.IDE.Search.Session.pas` | Ordner `IDE/Search` |
| `Atlas.IDE.Search.Stepping` | `IDE/Search/Atlas.IDE.Search.Stepping.pas` | Ordner `IDE/Search` |
| `Atlas.IDE.Search.Composition` | `IDE/Search/Atlas.IDE.Search.Composition.pas` | Anmeldung des Moduls `atlas.search`, #1455 |
| `Atlas.IDE.Search.FileSearch` | `IDE/Search/Atlas.IDE.Search.FileSearch.pas` | Ordner `IDE/Search` |
| `Atlas.IDE.Search.MessageList` | `IDE/Search/Atlas.IDE.Search.MessageList.pas` | Ordner `IDE/Search` |
| `Atlas.IDE.Search.ReplaceWindow` | `IDE/Search/Atlas.IDE.Search.ReplaceWindow.pas` | Ordner `IDE/Search` |
| `Atlas.IDE.UnitSearch.Actions` | `IDE/UnitSearch/Atlas.IDE.UnitSearch.Actions.pas` | Ordner `IDE/UnitSearch` |
| `Atlas.IDE.UnitSearch.Commands` | `IDE/UnitSearch/Atlas.IDE.UnitSearch.Commands.pas` | Ordner `IDE/UnitSearch` |
| `Atlas.UI.Query.Frame` | `UI/Query/Atlas.UI.Query.Frame.pas` | Ordner `UI/Query` |
| `Atlas.UI.Query.Parts` | `UI/Query/Atlas.UI.Query.Parts.pas` | Ordner `UI/Query` |
| `Atlas.UI.Search.Bar` | `UI/Search/Atlas.UI.Search.Bar.pas` | Ordner `UI/Search` |
| `Atlas.UI.Search.ReplaceFrame` | `UI/Search/Atlas.UI.Search.ReplaceFrame.pas` | Ordner `UI/Search` |
| `Atlas.UI.Search.SettingsSection` | `UI/Search/Atlas.UI.Search.SettingsSection.pas` | Ordner `UI/Search`; Einstellungen des Moduls als Abschnitte (#1456) |
| `Atlas.UI.Search.Strings` | `UI/Search/Atlas.UI.Search.Strings.pas` | Texte des Moduls (Suche), Sprache von Base, #1455 |
| `Atlas.UI.UnitSearch.Data` | `UI/UnitSearch/Atlas.UI.UnitSearch.Data.pas` | Ordner `UI/UnitSearch` |
| `Atlas.UI.UnitSearch.Painter` | `UI/UnitSearch/Atlas.UI.UnitSearch.Painter.pas` | Ordner `UI/UnitSearch` |
| `Atlas.UI.UnitSearch.Window` | `UI/UnitSearch/Atlas.UI.UnitSearch.Window.pas` | Ordner `UI/UnitSearch` |

## Atlas.IDE.Rules

| Unit | Datei | Begründung |
|---|---|---|
| `Atlas.Core.Problems.BulkFix` | `Core/Problems/Atlas.Core.Problems.BulkFix.pas` | Sammelkorrektur (#1352) über `IAtlasBulkFixer`, #1455 |
| `Atlas.Core.Rules.Table` | `Core/Rules/Atlas.Core.Rules.Table.pas` | Ordner `Core/Rules`: Regeltabelle für Regel-Editor und „Regel abschalten“, #1755 |
| `Atlas.Core.Rules.CustomLayer` | `Core/Rules/Atlas.Core.Rules.CustomLayer.pas` | Ordner `Core/Rules`: Eigene Prüfregel als Schicht von forbidden-uses, #1821 |
| `Atlas.IDE.Editor.DfmPropertyRules` | `IDE/Editor/Atlas.IDE.Editor.DfmPropertyRules.pas` | Eigenschaftsregeln anwenden (#309), Schalter dfmRules.apply unter ruleChecks, #1455 |
| `Atlas.IDE.Rules.Baseline` | `IDE/Rules/Atlas.IDE.Rules.Baseline.pas` | Ordner `IDE/Rules`: Baseline aktualisieren, Compilermeldungen in die Baseline, #1455 |
| `Atlas.IDE.Rules.BulkFix` | `IDE/Rules/Atlas.IDE.Rules.BulkFix.pas` | Ordner `IDE/Rules`: Sammelkorrektur, #1455 |
| `Atlas.IDE.Rules.Composition` | `IDE/Rules/Atlas.IDE.Rules.Composition.pas` | Anmeldung des Moduls `atlas.rules`, #1455 |
| `Atlas.IDE.Rules.FindingActions` | `IDE/Rules/Atlas.IDE.Rules.FindingActions.pas` | Ordner `IDE/Rules`: Regel-Aktionen am Befund (`IAtlasRuleActions`), #1755 |
| `Atlas.IDE.Rules.Maintenance` | `IDE/Rules/Atlas.IDE.Rules.Maintenance.pas` | Ordner `IDE/Rules`: Baseline und Unterdrückungen des aktiven Projekts, #1755 |
| `Atlas.IDE.Rules.Settings` | `IDE/Rules/Atlas.IDE.Rules.Settings.pas` | Ordner `IDE/Rules`: Abschnitt „Prüfregeln“ mit seinen Hooks, #1755 |
| `Atlas.UI.Problems.BulkFix` | `UI/Problems/Atlas.UI.Problems.BulkFix.pas` | Sammelkorrektur (#1352) über `IAtlasBulkFixer`, #1455 |
| `Atlas.UI.Rules.Editor` | `UI/Rules/Atlas.UI.Rules.Editor.pas` | Ordner `UI/Rules`: Regel-Editor, #1755 |
| `Atlas.UI.Rules.SettingsDialog` | `UI/Rules/Atlas.UI.Rules.SettingsDialog.pas` | Ordner `UI/Rules`: Dialog der Einstellungsdateien mit Regel-Editor (`IAtlasSettingsDialogProvider`), #1755 |
| `Atlas.UI.Rules.SettingsSection` | `UI/Rules/Atlas.UI.Rules.SettingsSection.pas` | Ordner `UI/Rules`; Einstellungen des Moduls als Abschnitte (#1456) |
| `Atlas.UI.Rules.Strings` | `UI/Rules/Atlas.UI.Rules.Strings.pas` | Texte des Moduls (Prüfregeln), Sprache von Base, #1455 |

## Atlas.IDE.Tests

| Unit | Datei | Begründung |
|---|---|---|
| `Atlas.Core.Tests.AffectedHook` | `Core/Tests/Atlas.Core.Tests.AffectedHook.pas` | Ordner `Core/Tests` |
| `Atlas.Core.Tests.Debug` | `Core/Tests/Atlas.Core.Tests.Debug.pas` | Ordner `Core/Tests` |
| `Atlas.Core.Tests.ProjectChoice` | `Core/Tests/Atlas.Core.Tests.ProjectChoice.pas` | Ordner `Core/Tests` |
| `Atlas.Core.Tests.UnitMatch` | `Core/Tests/Atlas.Core.Tests.UnitMatch.pas` | Ordner `Core/Tests` |
| `Atlas.Core.Tests.Run` | `Core/Tests/Atlas.Core.Tests.Run.pas` | Ordner `Core/Tests` |
| `Atlas.IDE.Tests.Affected` | `IDE/Tests/Atlas.IDE.Tests.Affected.pas` | Ordner `IDE/Tests` |
| `Atlas.IDE.Tests.Debug` | `IDE/Tests/Atlas.IDE.Tests.Debug.pas` | Ordner `IDE/Tests` |
| `Atlas.IDE.Tests.Lens` | `IDE/Tests/Atlas.IDE.Tests.Lens.pas` | Ordner `IDE/Tests` |
| `Atlas.IDE.Tests.Projects` | `IDE/Tests/Atlas.IDE.Tests.Projects.pas` | Ordner `IDE/Tests` |
| `Atlas.IDE.Tests.Runner` | `IDE/Tests/Atlas.IDE.Tests.Runner.pas` | Ordner `IDE/Tests` |
| `Atlas.UI.Tests.SettingsSection` | `UI/Tests/Atlas.UI.Tests.SettingsSection.pas` | Ordner `UI/Tests`; Einstellungen des Moduls als Abschnitte (#1456) |
| `Atlas.UI.Tests.Strings` | `UI/Tests/Atlas.UI.Tests.Strings.pas` | Texte des Moduls (Tests), Sprache von Base, #1455 |
| `Atlas.IDE.Tests.Composition` | `IDE/Tests/Atlas.IDE.Tests.Composition.pas` | Anmeldung des Moduls `atlas.tests`, #1455 |
| `Atlas.IDE.Tests.Composition.Hooks` | `IDE/Tests/Atlas.IDE.Tests.Composition.Hooks.pas` | Haken des Testläufers (Build, Probleme, Zusammenfassung), von der Composition gesetzt |

## Atlas.IDE.Build

| Unit | Datei | Begründung |
|---|---|---|
| `Atlas.Core.Build.CompilerSwitches` | `Core/Build/Atlas.Core.Build.CompilerSwitches.pas` | Ordner `Core/Build` |
| `Atlas.Core.Build.OpenBuild` | `Core/Build/Atlas.Core.Build.OpenBuild.pas` | Ordner `Core/Build` |
| `Atlas.Core.Tasks.Adapters.Process` | `Core/Tasks/Atlas.Core.Tasks.Adapters.Process.pas` | Ordner `Core/Tasks` |
| `Atlas.Core.Tasks.Commands` | `Core/Tasks/Atlas.Core.Tasks.Commands.pas` | Ordner `Core/Tasks` |
| `Atlas.Core.Tasks.Definitions` | `Core/Tasks/Atlas.Core.Tasks.Definitions.pas` | Ordner `Core/Tasks` |
| `Atlas.Core.Tasks.Matchers` | `Core/Tasks/Atlas.Core.Tasks.Matchers.pas` | Ordner `Core/Tasks` |
| `Atlas.Core.Tasks.OutputGroup` | `Core/Tasks/Atlas.Core.Tasks.OutputGroup.pas` | Ordner `Core/Tasks` |
| `Atlas.Core.Tasks.PreBuild` | `Core/Tasks/Atlas.Core.Tasks.PreBuild.pas` | Ordner `Core/Tasks` |
| `Atlas.Core.Tasks.Reports` | `Core/Tasks/Atlas.Core.Tasks.Reports.pas` | Ordner `Core/Tasks` |
| `Atlas.Core.Tasks.Runs` | `Core/Tasks/Atlas.Core.Tasks.Runs.pas` | Ordner `Core/Tasks` |
| `Atlas.IDE.Build.CompilerSwitches` | `IDE/Build/Atlas.IDE.Build.CompilerSwitches.pas` | Ordner `IDE/Build` |
| `Atlas.IDE.BuildTools.Composition` | `IDE/BuildTools/Atlas.IDE.BuildTools.Composition.pas` | Anmeldung des Moduls `atlas.build`, #1455 |
| `Atlas.IDE.Build.OpenBuild` | `IDE/Build/Atlas.IDE.Build.OpenBuild.pas` | Ordner `IDE/Build` |
| `Atlas.IDE.Build.SwitchesWindow` | `IDE/Build/Atlas.IDE.Build.SwitchesWindow.pas` | Ordner `IDE/Build` |
| `Atlas.IDE.StartProfiles.Service` | `IDE/StartProfiles/Atlas.IDE.StartProfiles.Service.pas` | Ordner `IDE/StartProfiles` |
| `Atlas.IDE.Tasks.Output` | `IDE/Tasks/Atlas.IDE.Tasks.Output.pas` | Ordner `IDE/Tasks` |
| `Atlas.IDE.Tasks.Projects` | `IDE/Tasks/Atlas.IDE.Tasks.Projects.pas` | Ordner `IDE/Tasks` |
| `Atlas.IDE.Tasks.Shortcuts` | `IDE/Tasks/Atlas.IDE.Tasks.Shortcuts.pas` | Ordner `IDE/Tasks` |
| `Atlas.IDE.Tasks.Pickers` | `IDE/Tasks/Atlas.IDE.Tasks.Pickers.pas` | Ordner `IDE/Tasks` |
| `Atlas.IDE.Tasks.Runner` | `IDE/Tasks/Atlas.IDE.Tasks.Runner.pas` | Ordner `IDE/Tasks` |
| `Atlas.UI.Build.SettingsSection` | `UI/Build/Atlas.UI.Build.SettingsSection.pas` | Ordner `UI/Build`; Einstellungen des Moduls als Abschnitte (#1456) |
| `Atlas.UI.Build.Strings` | `UI/Build/Atlas.UI.Build.Strings.pas` | Texte des Moduls (Build-Werkzeuge), Sprache von Base, #1455 |
| `Atlas.UI.Build.SwitchesFrame` | `UI/Build/Atlas.UI.Build.SwitchesFrame.pas` | Ordner `UI/Build` |
| `Atlas.UI.Tasks.Texts` | `UI/Tasks/Atlas.UI.Tasks.Texts.pas` | Ordner `UI/Tasks` |

## Atlas.IDE.BuildPipeline

| Unit | Datei | Begründung |
|---|---|---|
| `Atlas.Core.BuildPipeline.Gate` | `Core/BuildPipeline/Atlas.Core.BuildPipeline.Gate.pas` | Ordner `Core/BuildPipeline` |
| `Atlas.Core.BuildPipeline.ReleaseGuard` | `Core/BuildPipeline/Atlas.Core.BuildPipeline.ReleaseGuard.pas` | Ordner `Core/BuildPipeline` |
| `Atlas.IDE.BuildPipeline.Gate` | `IDE/BuildPipeline/Atlas.IDE.BuildPipeline.Gate.pas` | Ordner `IDE/BuildPipeline` |
| `Atlas.IDE.BuildPipeline.ReleaseGuard` | `IDE/BuildPipeline/Atlas.IDE.BuildPipeline.ReleaseGuard.pas` | Ordner `IDE/BuildPipeline` |
| `Atlas.IDE.BuildPipeline.Runner` | `IDE/BuildPipeline/Atlas.IDE.BuildPipeline.Runner.pas` | Ordner `IDE/BuildPipeline` |
| `Atlas.IDE.BuildPipeline.Summary` | `IDE/BuildPipeline/Atlas.IDE.BuildPipeline.Summary.pas` | Ordner `IDE/BuildPipeline` |
| `Atlas.IDE.BuildPipeline.Composition` | `IDE/BuildPipeline/Atlas.IDE.BuildPipeline.Composition.pas` | Anmeldung des Moduls `atlas.buildpipeline`, #1455 |
| `Atlas.UI.BuildPipeline.SettingsSection` | `UI/BuildPipeline/Atlas.UI.BuildPipeline.SettingsSection.pas` | Ordner `UI/BuildPipeline`; Einstellungen des Moduls als Abschnitte (#1456) |
| `Atlas.UI.BuildPipeline.Strings` | `UI/BuildPipeline/Atlas.UI.BuildPipeline.Strings.pas` | Texte des Moduls (Build-Pipeline), Sprache von Base, #1455 |

## Atlas.IDE.Bookmarks

| Unit | Datei | Begründung |
|---|---|---|
| `Atlas.Core.Bookmarks.Quick` | `Core/Bookmarks/Atlas.Core.Bookmarks.Quick.pas` | Ordner `Core/Bookmarks` |
| `Atlas.Core.Bookmarks.SavedPlaces` | `Core/Bookmarks/Atlas.Core.Bookmarks.SavedPlaces.pas` | Notizen und Lesezeichen als gemerkte Stellen (Vertrag SavedPlaces), #1456 |
| `Atlas.Core.Bookmarks.Store` | `Core/Bookmarks/Atlas.Core.Bookmarks.Store.pas` | Ordner `Core/Bookmarks` |
| `Atlas.Core.Notes.Store` | `Core/Notes/Atlas.Core.Notes.Store.pas` | Ordner `Core/Notes` |
| `Atlas.IDE.Bookmarks.Gutter` | `IDE/Bookmarks/Atlas.IDE.Bookmarks.Gutter.pas` | Ordner `IDE/Bookmarks` |
| `Atlas.IDE.Bookmarks.Composition` | `IDE/Bookmarks/Atlas.IDE.Bookmarks.Composition.pas` | Anmeldung des Moduls `atlas.bookmarks`, #1455 |
| `Atlas.IDE.Bookmarks.Composition.Todos` | `IDE/Bookmarks/Atlas.IDE.Bookmarks.Composition.Todos.pas` | TODO-Liste des Projekts (#68), von der Composition aufgerufen |
| `Atlas.IDE.Bookmarks.QuickChord` | `IDE/Bookmarks/Atlas.IDE.Bookmarks.QuickChord.pas` | Ordner `IDE/Bookmarks` |
| `Atlas.IDE.Bookmarks.QuickColumn` | `IDE/Bookmarks/Atlas.IDE.Bookmarks.QuickColumn.pas` | Ordner `IDE/Bookmarks` |
| `Atlas.IDE.Bookmarks.QuickPopups` | `IDE/Bookmarks/Atlas.IDE.Bookmarks.QuickPopups.pas` | Ordner `IDE/Bookmarks` |
| `Atlas.IDE.Bookmarks.SavedPlaces` | `IDE/Bookmarks/Atlas.IDE.Bookmarks.SavedPlaces.pas` | IAtlasSavedPlacesSource für den Reiter „Gemerkt“ der Willkommensseite, #1456 |
| `Atlas.IDE.Bookmarks.Service` | `IDE/Bookmarks/Atlas.IDE.Bookmarks.Service.pas` | Ordner `IDE/Bookmarks` |
| `Atlas.IDE.Bookmarks.QuickService` | `IDE/Bookmarks/Atlas.IDE.Bookmarks.QuickService.pas` | Ordner `IDE/Bookmarks` |
| `Atlas.IDE.Bookmarks.Window` | `IDE/Bookmarks/Atlas.IDE.Bookmarks.Window.pas` | Ordner `IDE/Bookmarks` |
| `Atlas.IDE.Notes.Gutter` | `IDE/Notes/Atlas.IDE.Notes.Gutter.pas` | Ordner `IDE/Notes` |
| `Atlas.IDE.Notes.Service` | `IDE/Notes/Atlas.IDE.Notes.Service.pas` | Ordner `IDE/Notes` |
| `Atlas.UI.Bookmarks.Dialog` | `UI/Bookmarks/Atlas.UI.Bookmarks.Dialog.pas` | Ordner `UI/Bookmarks` |
| `Atlas.UI.Bookmarks.Frame` | `UI/Bookmarks/Atlas.UI.Bookmarks.Frame.pas` | Ordner `UI/Bookmarks` |
| `Atlas.UI.Bookmarks.SettingsSection` | `UI/Bookmarks/Atlas.UI.Bookmarks.SettingsSection.pas` | Ordner `UI/Bookmarks`; Einstellungen des Moduls als Abschnitte (#1456) |
| `Atlas.UI.Bookmarks.Strings` | `UI/Bookmarks/Atlas.UI.Bookmarks.Strings.pas` | Texte des Moduls (Lesezeichen und Notizen), Sprache von Base, #1455 |
| `Atlas.UI.Notes.Dialog` | `UI/Notes/Atlas.UI.Notes.Dialog.pas` | Ordner `UI/Notes` |
| `Atlas.UI.Notes.List` | `UI/Notes/Atlas.UI.Notes.List.pas` | Notizen als Einträge der Ergebnisliste, #1455 |
| `Atlas.UI.Todos.Dialog` | `UI/Todos/Atlas.UI.Todos.Dialog.pas` | Ordner `UI/Todos` |
