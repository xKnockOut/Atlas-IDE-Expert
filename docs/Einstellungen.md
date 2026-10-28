# Einstellungen

<!-- Erzeugt von Tools/Update-ConfigDoc.ps1 aus schemas/atlas.schema.json. Nicht von Hand bearbeiten. -->

Alle Einstellungen mit Seite und Bedienelement im Einstellungs-Plugin (#227). Einzelheiten zu Werten und Bedeutung stehen in [Konfiguration.md](Konfiguration.md).

| Seite | Einstellung | Standard | Quelle | Neustart | Bedienelement | Herkunft |
|---|---|---|---|---|---|---|
| Allgemein | `delphiVersion` | – | settings.json (Tools › Optionen › Atlas) | nein | Auswahl aus den installierten Versionen | #47, #258 |
| Projekt | `minDelphiVersion` | – | atlas.json (Atlas › Projekt-Einstellungen) | nein | Auswahl aller bekannten Delphi-Versionen | #1126 |
| Allgemein | `language` | `"de"` | settings.json (Tools › Optionen › Atlas) | nein | Auswahl | #24 |
| Allgemein | `encoding` | `"utf-8"` | atlas.json (Atlas › Projekt-Einstellungen) | nein | Auswahl | #121 |
| Projekt | `project` | – | atlas.json (Atlas › Projekt-Einstellungen) | nein | Vorgabe: aktives IDE-Projekt | #14, #24 |
| Projekt | `config` | – | atlas.json (Atlas › Projekt-Einstellungen) | nein | Auswahl aus der .dproj | #14, #46 |
| Projekt | `platform` | – | atlas.json (Atlas › Projekt-Einstellungen) | nein | Auswahl aus der .dproj | #14, #46 |
| Prüfregeln | `rules` | – | settings.json (Tools › Optionen › Atlas) und atlas.json (Atlas › Projekt-Einstellungen) | nein | Tabelle aus dem Regelkatalog | #41 |
| Prüfregeln | `profile` | `"standard"` | atlas.json (Atlas › Projekt-Einstellungen) | nein | Auswahl | #146 |
| Prüfregeln | `profiles` | – | atlas.json (Atlas › Projekt-Einstellungen) | nein | Profil-Editor | #146 |
| Prüfregeln | `overrides` | – | atlas.json (Atlas › Projekt-Einstellungen) | nein | Liste mit Mustern | #146 |
| Prüfregeln | `excludeTests` | `false` | atlas.json (Atlas › Projekt-Einstellungen) | nein | Kontrollkästchen | #146 |
| Prüfregeln | `testProfile` | – | atlas.json (Atlas › Projekt-Einstellungen) | nein | Auswahl | #146 |
| Compiler | `compiler`: `onSave`, `backend`, `ideCommand` | – | settings.json (Tools › Optionen › Atlas) | nein | Kontrollkästchen, Auswahl, Datei wählen | #40, #261 |
| Allgemein | `vcs`: `provider` | – | settings.json (Tools › Optionen › Atlas) | nein | Auswahl | #571 |
| Vervollständigung | `completion`: `matching`, `interfaceSection`, `senderCast`, `offerTryFinally`, `freeStyle`, `keywords`, `postfixTemplates`, `genericConstraints`, `createAccessors`, `accessorSection`, `resourceStrings`, `resourceStringUnit`, `typeConversion` (experimentell), `assignAllFields` (experimentell), `usesDetails`, `inheritedCall`, `attributes`, `anonymousMethods`, `withOrigin`, `exceptionClasses`, `syntaxNotice`, `sameNameVariants`, `sameNameInsert`, `showFmxUnits`, `nameSuggestions` | – | settings.json (Tools › Optionen › Atlas); `interfaceSection`, `senderCast`, `freeStyle`, `createAccessors`, `accessorSection`, `resourceStringUnit` in atlas.json | nein | Auswahl | #31, #188, #229, #450, #452, #466, #467, #469, #473, #475, #480, #482, #489, #490 |
| Vervollständigung | `refactoring`: `inlineVar`, `changeSignature`, `newParameter`, `virtualOverload`, `syncSignatures`, `forwardDeclaration`, `propertyFromAccessors`, `propertyFromAccessorsPrefixes`, `propertyFromAccessorsReplaceCalls`, `propertyFromAccessorsSection`, `propertyFromAccessorsHideAccessors`, `freeFields`, `freeFieldsStyle`, `suggestConst`, `invertBoolean`, `invertBooleanAntonyms`, `invertBooleanFallbackPrefix`, `invertBooleanIncludeDfm`, `ifCase`, `conditions`, `conditionalExpression`, `nestedRoutine`, `promoteVariable`, `anonymousMethod`, `anonymousMethodDeferredCapture`, `methodKind`, `methodKindMarker`, `methodKindStatic`, `typeAlias`, `typeAliasScope`, `enumTables`, `enumTablesResourceStrings`, `varBlock`, `varBlockMerge`, `varBlockSort`, `extractInterface`, `extractSuperclass`, `extractSuperclassTarget`, `extractSuperclassNameSuffix`, `extractSuperclassMethodMode`, `extractSuperclassRaiseVisibility`, `moveMember`, `inlineAccessor`, `inlineAccessorEqualityCheck`, `inlineAccessorBulk`, `inlineAccessorDiagnostic`, `safeDelete`, `safeDeletePreviewWhenUnused`, `safeDeleteCascade`, `safeDeleteIncludeOverrides`, `tryFinally`, `classActions`, `explicitType`, `compilerFixes`, `missingUnit`, `disableWarning`, `disableWarningReason`, `extract`, `completeCase`, `resolveWith`, `inline` (experimentell), `moveClass` (experimentell), `unitRenameFollowUp` (experimentell), `createMethod`, `createMethodSection`, `createMethodCaret`, `constParameters` | – | atlas.json (Atlas › Projekt-Einstellungen) | nein | Kontrollkästchen | #42, #50, #100, #188, #453, #472, #646, #656, #666, #682, #684, #685, #715 |
| Eingabehilfen | `usesCommand` | `true` | settings.json (Tools › Optionen › Atlas) | nein | Kontrollkästchen | #254 |
| Eingabehilfen | `completeBlocks`: `docComment` | – | settings.json (Tools › Optionen › Atlas) | nein | Kontrollkästchen | #88 |
| Editor | `metrics` | `true` | settings.json (Tools › Optionen › Atlas) | nein | Kontrollkästchen | #66 |
| Allgemein | `experimental`: `enabled` | – | settings.json (Tools › Optionen › Atlas) | nein | Kontrollkästchen „Experimentelle Funktionen erlauben“ | #834 |
| Eingabehilfen | `slashCommands`: `enabled`, `disabled`, `headerTemplate`, `logCall`, `componentPalette`, `todoOwner`, `todoCategory`, `sortUsesRemoveUnused`, `enumHelper`, `setHelper` | – | settings.json (Tools › Optionen › Atlas) | nein | Kontrollkästchen, Liste | #293 |
| Eingabehilfen | `sortUses` | `false` | atlas.json (Atlas › Projekt-Einstellungen) | nein | Auswahl | #182, #284 |
| Eingabehilfen | `usesKeep` | `` | atlas.json (Atlas › Projekt-Einstellungen) | nein | Liste | #284 |
| Prüfregeln | `deadCode`: `keepAttributes`, `keepPatterns` | – | atlas.json (Atlas › Projekt-Einstellungen) | nein | Liste mit Hinzufügen/Entfernen | #64 |
| Prüfregeln | `dfmPropertyRules` | `` | atlas.json (Atlas › Projekt-Einstellungen) | nein | Eigener Editor (Klasse und Property aus dem Index) | #309 |
| Speicher | `memoryBudgetMb` | `768` | settings.json (Tools › Optionen › Atlas) | nein | Zahlenfeld (MB) | #185, #492 |
| Speicher | `index`: `projectGroup`, `searchPaths`, `libraryPaths`, `usages`, `removeOrphans`, `cacheMaxAgeDays`, `cacheMaxMb`, `exclude` | – | settings.json (Tools › Optionen › Atlas); `exclude` in atlas.json | nein | Kontrollkästchen, Liste mit Hinzufügen/Entfernen | #648, #492, #905 |
| Architektur | `architecture`: `enabled`, `scope`, `includeLibraryUnits`, `centralUnits`, `exclude`, `baseline`, `failOn` | – | settings.json (Tools › Optionen › Atlas); `exclude`, `baseline`, `failOn` in atlas.json | nein | Kontrollkästchen, Auswahl, Kontrollkästchen, Zahl (5–100); exclude: Liste mit Hinzufügen/Entfernen in den Projekt-Einstellungen; baseline: Datei wählen, failOn: Liste (Projekt-Einstellungen, #1121) | #1118 |
| Robustheit | `requestTimeoutMs` | `10000` | settings.json (Tools › Optionen › Atlas) | nein | Zahlenfeld (ms) | #283 |
| Robustheit | `diagnostics`: `log`, `logDays`, `logMapFile`, `usesCycleLive`, `usesCycleImplementation` | – | settings.json (Tools › Optionen › Atlas); `usesCycleLive`, `usesCycleImplementation` in atlas.json | nein | Kontrollkästchen, Zahlenfeld (Tage) | #647 |
| Editor | `highlight`: `blockPairs`, `directives`, `exitPoints`, `exitKeywords` | – | settings.json (Tools › Optionen › Atlas) | nein | Kontrollkästchen, Liste | #307 |
| Editor | `inlayHints`: `parameterNames`, `inferredTypes`, `endMarkers`, `endMarkerMinLines`, `includeDefines`, `controlChars` | – | settings.json (Tools › Optionen › Atlas) | nein | Kontrollkästchen, Zahlenfeld | #35, #453, #860, #862 |
| Editor | `codeLens`: `metrics` | – | settings.json (Tools › Optionen › Atlas) | nein | Kontrollkästchen | #66 |
| Befehle | `references`: `inferred`, `textMatches` | – | settings.json (Tools › Optionen › Atlas) | nein | Kontrollkästchen | #1119 |
| Befehle | `navigation`: `symbolPath`, `impact`, `impactDepth` | – | settings.json (Tools › Optionen › Atlas) | nein | Kontrollkästchen, Zahlenfeld | #1117, #1120 |
| Hints | `hints`: `xmlDocExpand`, `xmlDocFull`, `xmlDocMaxLines`, `publishedMembers`, `rationale`, `rationaleMarkers`, `adrFolder` | – | settings.json (Tools › Optionen › Atlas) | nein | Kontrollkästchen, Zahlenfeld | #654 |
| Editor | `directives`: `completion`, `hover` | – | settings.json (Tools › Optionen › Atlas) | nein | Kontrollkästchen | #102 |
| Editor | `stringLiteral`: `style`, `lineBreak`, `maxLineLength` | – | atlas.json (Atlas › Projekt-Einstellungen) | nein | Auswahl, Zahlenfeld | #312 |
| Editor | `memberOrder`: `sections`, `members`, `sortFields`, `sortPublished` | – | atlas.json (Atlas › Projekt-Einstellungen) | nein | Liste, Kontrollkästchen | #89 |
| Projekt | `testUnits`: `pattern`, `folder`, `project` | – | atlas.json (Atlas › Projekt-Einstellungen) | nein | Textfeld, Dateiauswahl | #274 |
| Prüfregeln | `minConfidence` | `"medium"` | atlas.json (Atlas › Projekt-Einstellungen) | nein | Auswahl | #144 |
| Projekt | `exclude` | – | atlas.json (Atlas › Projekt-Einstellungen) | nein | Liste mit Hinzufügen/Entfernen | #24 |
| MCP | `mcp`: `disabledTools`, `globalSettings` | – | settings.json (Tools › Optionen › Atlas); `globalSettings` in atlas.json | nein | Liste mit Hinzufügen/Entfernen; globalSettings: Kontrollkästchen | #99 |
| Formatierung | `format`: `indentSize`, `useTabs`, `keywordCase`, `trimTrailingWhitespace`, `insertFinalNewline`, `spaceAroundAssignment`, `spaceAfterComma`, `endOfLine`, `reindent`, `beginPlacement`, `elsePlacement`, `maxLineLength`, `alignAssignments`, `alignDeclarations`, `alignComments` | – | atlas.json (Atlas › Projekt-Einstellungen) | nein | Zahlenfeld, Kontrollkästchen, Auswahl | #43 |
| Projekt | `tasks` | – | settings.json (Tools › Optionen › Atlas) und atlas.json (Atlas › Projekt-Einstellungen) | nein | JSON in atlas.json bzw. settings.json (Liste der Aufgaben) | #900 |
| Issue-Tracker | `issues`: `connections`, `projects` | – | settings.json (Tools › Optionen › Atlas) | nein | Tabellen Verbindungen und Projekte | #1260, #1261 |
| Protokoll | `logLevel` | `"info"` | settings.json (Tools › Optionen › Atlas), ``--log-level`` | ja | Auswahl | #76, #96 |
| Protokoll | `logFile` | `""` | settings.json (Tools › Optionen › Atlas), ``--log`` | ja | Datei wählen | #76, #96 |
| Protokoll | `traceFile` | `""` | settings.json (Tools › Optionen › Atlas), ``--trace`` | ja | Datei wählen | #76, #96 |
| Allgemein | Pfad zu `AtlasServer.exe` | – | Plugin (Registry `ServerPath`) | ja | Datei wählen, Version anzeigen | #12 |
| Prüfregeln | Unit-Zyklen beim Tippen (`diagnostics.usesCycleLive`): Regel `uses-cycle` im Editor mit kürzestem Pfad am auslösenden uses-Eintrag, Fehler, wenn jede Kante im interface liegt (F2047); jede Unit im Hover springt an ihren uses-Eintrag, „Graph zeigen“ öffnet die Unit-Beziehungen; Schnellkorrektur „In implementation-uses verschieben“ (sortiert mit `sortUses`), wenn kein Bezeichner der Unit im interface-Teil gebraucht wird, sonst Sprünge zu diesen Bezeichnern; auch Zyklen mit implementation-Kante als Hinweis (`diagnostics.usesCycleImplementation`); aus = keine Meldung im Editor, die projektweite Prüfung (#64) bleibt | an, aus | atlas.json (Atlas › Projekt-Einstellungen, Seite Prüfregeln) | nein | Kontrollkästchen, Kontrollkästchen | #896 |
| Compiler | Builds für Claude Code (`compiler.mcpBuild`, Schnellschalter): Das MCP-Werkzeug `build_project` darf offene Projekte in dieser IDE über IOTAProjectBuilder bauen (make, build, check; Konfiguration und Plattform nur für diesen Build) und bekommt Ergebnis und Compilermeldungen, auch in der Starter Edition ohne Kommandozeilen-Compiler. Abgelehnt mit Grund, solange der Debugger, ein anderer Build oder die Compilerprüfung läuft; aus = die IDE nimmt keine Aufträge an | an | Plugin (Registry `McpBuild`) | nein | Kontrollkästchen | #261 |
| Compiler | DUnitX-Tests ausführen (#69, `tests.run`, Schnellschalter): Befehle „Tests ausführen“ (*Atlas.RunTests*) und „Fehlgeschlagene Tests erneut ausführen“ (*Atlas.RunFailedTests*) in der Befehlspalette; Testprojekt ist das aktive bzw. eines der Projektgruppe, dessen Hauptdatei `DUnitX.TestFramework` verwendet (für einen Test das Testprojekt, das seine Testunit enthält); bei mehreren fragt Atlas einmal und merkt sich die Wahl für genau diese Kandidaten (#585, lokal in `%LOCALAPPDATA%\Atlas\test-projects.json`); Plattform und Konfiguration aus dem Testprojekt; Ergebnis über den XML-Logger von DUnitX, fehlgeschlagene Tests als Probleme an der Testmethode (Quelle `DUnitX`, erwarteter und tatsächlicher Wert) und in der Meldungsansicht; aus = Befehle, Code Lens und Lauf nach dem Build verschwinden | an | Plugin (Registry `TestRun`) | nein | Kontrollkästchen | #69 |
| Compiler | Vor den Tests bauen (`tests.buildFirst`): „Tests ausführen“ baut das Testprojekt vorher (make) wie `build_project`; aus = die vorhandene Test-EXE läuft ohne Compiler | an | Plugin (Registry `TestsBuildFirst`) | nein | Kontrollkästchen | #69 |
| Compiler | Tests nach dem Build (`tests.afterBuild`, Schnellschalter): nach jedem erfolgreichen Build eines DUnitX-Testprojekts durch den Benutzer laufen dessen Tests (Compile-Ereignisse #527); nicht nach der Hintergrundprüfung und nicht nach Builds für Claude Code | aus | Plugin (Registry `TestsAfterBuild`) | nein | Kontrollkästchen | #69 |
| Compiler | Build nur ohne Warnungen und Hinweise erfolgreich (`build.zeroHints`): ein Build mit gezählten Warnungen oder Hinweisen gilt als gescheitert (rote Zusammenfassung, roter Eintrag in der Benachrichtigungszentrale, keine Tests nach dem Build); Meldungen in der Basislinie zählen nicht | aus | Plugin (Registry `BuildZeroHints`) | nein | Kontrollkästchen | #530 |
| Compiler | Kosten einer interface-Änderung in der Statusleiste (#554, `build.showInterfaceCost`): Steht die Einfügemarke im interface-Teil einer Unit, zeigt das Zusatzfeld „interface-Änderung: N Units werden neu kompiliert“ (Hinweis: die ersten Units; Klick: „Abhängigkeiten dieser Unit“); im implementation-Teil, bei 0 Units und ohne Server kein Feld; braucht `architecture.enabled` (derselbe Uses-Graph); aus = kein Feld, die Befehle „Abhängigkeiten dieser Unit“ und „Teuerste Units bei interface-Änderungen“ bleiben | an | Plugin (Registry `ShowInterfaceCost`) | nein | Kontrollkästchen | #554 |
| Compiler | Zusammenfassung nach jedem Build (`build.summary`) in der Atlas-Gruppe des Meldungsfensters, z. B. „Build Kasse erfolgreich, aber 2 Warnungen, 1 Hinweis“, mit der ersten Meldung zum Anspringen; einen Build, den `build.zeroHints` oder `build.warningsAsErrors` scheitern lassen, meldet Atlas auch ohne sie | an | Plugin (Registry `BuildSummary`) | nein | Kontrollkästchen | #530 |
| Compiler | Codes, die als Fehler zählen (`build.warningsAsErrors`): Warnungen und Hinweise wie `W1035, H2164`; enthält ein Build eine davon (außerhalb der Basislinie), gilt er als gescheitert | leer | Plugin (Registry `BuildWarningsAsErrors`) | nein | Textfeld | #530 |
| Compiler | Prüfung vor dem Compile (`build.gate`: off, warn, block): Vor jedem make und build, den der Benutzer startet (nicht Code Insight, Hintergrundprüfung, Syntaxprüfung oder Aufträge von Claude Code), prüft Atlas die seit dem letzten erfolgreichen Compile geänderten Units mit den Puffern der IDE (auch ungespeichert) auf Syntaxfehler und Regeltreffer mit Schweregrad Fehler; die Treffer stehen in der Atlas-Gruppe des Meldungsfensters (Doppelklick springt hin). off = keine Prüfung, warn = melden, block = Compile abbrechen; ein zweiter Compile ohne Änderung binnen 10 s läuft trotzdem (bewusst übergehen). Gilt ebenso für den Release-Build-Wächter (#533), bei dem off und warn nur melden | off | Plugin (Registry `BuildGate`) | nein | Auswahl | #529, #533 |
| Compiler | Zeitlimit der Prüfung vor dem Compile (`build.gateTimeoutMs`, 50 bis 10000 ms): dauert die Prüfung länger, läuft der Compile ungeprüft, und Atlas meldet das einmal je Sitzung | 300 | Plugin (Registry `BuildGateTimeoutMs`) | nein | Zahl | #529 |
| Compiler | Fenster „Compiler-Schalter“ (`build.compilerSwitches`, Schnellschalter): Andockbares Fenster mit den wirksamen Compiler-Schaltern an der Cursorposition: `R`, `Q`, `O`, `C`, `I`, `A`, `HINTS`, `WARNINGS`, abgeschaltete bzw. als Fehler gemeldete Warnungen (`{$WARN … OFF}`), aktive Symbole sowie Plattform und Konfiguration. Je Wert die Herkunft: Projektoption (Eigenschaft der .dproj), Compiler-Vorgabe, Include-Datei oder Direktive mit Zeile (`R−, gesetzt in Zeile 10`). Abweichungen von der .dproj sind hervorgehoben. Berechnet vom Server über den Präprozessor bis zur Cursorzeile (`atlas/compilerSwitches`), 150 ms nach der letzten Cursorbewegung. Doppelklick oder Enter springt zur Direktive bzw. öffnet die Projektoptionen. Befehl `Atlas.CompilerSwitches` | an | Plugin (Registry `BuildCompilerSwitches`) | nein | Kontrollkästchen | #558 |
| Compiler | Abweichende Compiler-Schalter in der Statusleiste (`build.showSwitchesInStatusBar`): Zusatzfeld in der Statusleiste des Editors mit den Schaltern, die an der Cursorposition von der .dproj abweichen, etwa `R− Q− HINTS OFF` oder `WARN SYMBOL_PLATFORM OFF`; ohne Abweichung erscheint kein Feld. Der Tooltip nennt die Herkunft, ein Klick öffnet das Fenster „Compiler-Schalter“. Wirkt nur mit `build.compilerSwitches` | aus | Plugin (Registry `BuildSwitchesInStatusBar`) | nein | Kontrollkästchen | #558 |
| Compiler | Startprofile (#575, `startProfiles.enabled`, Schnellschalter): Befehl „Startprofil: …“ (*Atlas.StartProfile*, Befehlspalette) und Klick auf das Feld in der Statusleiste wählen für das aktive Projekt ein Profil aus `startProfiles` der Projektdatei `.atlas` (gemeinsam, braucht `teamFile.enabled`) oder ein persönliches; Atlas setzt Parameter, Arbeitsordner, Host-Anwendung und Umgebungsvariablen der aktiven Konfiguration und Plattform (wie *Start › Parameter*), *Start* und *Ohne Debugger starten* nutzen sie dann; das aktive Profil gilt je Projekt und wird bei Wechsel von Projekt, Konfiguration oder Plattform wieder gesetzt; „Kein Startprofil“ stellt die Startoptionen von vor dem ersten Profil wieder her; „Aktuelle Startoptionen als persönliches Profil speichern …“; Feld „Startprofil: <Name>“ in der Statusleiste, sobald das Projekt Profile hat (`startProfiles.statusField`, Schnellschalter); aus = Befehl, Feld und Tipp verschwinden, die Startoptionen bleiben, wie sie sind | an, an | Plugin (Registry `StartProfiles`, `StartProfilesStatusField`); persönliche Profile, aktives Profil und die Startoptionen von vorher je Projekt nur lokal in `%LOCALAPPDATA%\Atlas\startprofiles\<Schlüssel>.json`; gemeinsame in `.atlas` | nein | Kontrollkästchen, Kontrollkästchen | #575 |
| Compiler | Beim Öffnen einmal bauen (`build.onOpen`, Schnellschalter; Art `build.onOpenKind`: `check` Syntaxprüfung, `make` Compilieren, `build` Erzeugen): Wird ein Projekt oder eine Projektgruppe geöffnet (auch das beim Start der IDE geladene), baut Atlas es einmal über den Compiler der IDE, sobald die IDE ruhig ist (keine Eingabe seit `build.onOpenDelayMs`, kein Build, kein Debugger, keine Compilerprüfung); mit eingeschalteter Hintergrundcompilierung der IDE ohne zu blockieren, sonst mit ihrem Fortschrittsdialog. Einmal je Öffnen; Tests nach dem Build laufen nicht, der Release-Wächter prüft wie bei jedem Build. Ergebnis je Projekt in der Benachrichtigungszentrale, bei mehreren Projekten zusätzlich eine Zusammenfassung (Quelle `openBuild`); aus = kein Bau beim Öffnen | aus, make | Plugin (Registry `BuildOnOpen`, `BuildOnOpenKind`) | nein | Auswahl „nicht bauen / Syntaxprüfung / Compilieren / Erzeugen“ |  |
| Compiler | Umfang in einer Projektgruppe (`build.onOpenScope`: `all` alle Projekte in der Reihenfolge der Gruppe, `active` nur das aktive Projekt) | all | Plugin (Registry `BuildOnOpenScope`) | nein | Auswahl |  |
| Compiler | Wartezeit beim Öffnen (`build.onOpenDelayMs`, 500 bis 60000 ms): so lange nach dem letzten Öffnen und nach der letzten Eingabe, bevor Atlas baut | 3000 | Plugin (Registry `BuildOnOpenDelayMs`) | nein | Zahl |  |
| Compiler | Beim Öffnen nicht bauen (`build.onOpenExclude`, Projektnamen ohne Endung, durch Komma getrennt), z. B. ein in dieser IDE installiertes Package | – | Plugin (Registry `BuildOnOpenExclude`) | nein | Textfeld |  |
| Release-Build | Release-Build-Wächter (`build.releaseGuard`, Schnellschalter): vor make und build in einer Release-Konfiguration prüft Atlas die Projektoptionen, wie die laufende IDE sie für den Build verwendet (mit geerbten Werten, auch ungespeichert; nicht die .dproj auf der Platte), nach `build.releaseChecks`. Verstöße stehen in der Atlas-Gruppe des Meldungsfensters mit Regel-ID und Hinweis, wo die Option zu ändern ist. Gilt auch für Builds über den Läufer (Claude Code `build_project`, „Öffnen und bauen“ #764), nie für Debug-Konfigurationen, die Hintergrundprüfung, Syntaxprüfung, Clean oder Code Insight. Befehl „Release-Build prüfen“ (*Atlas.CheckRelease*, Befehlspalette) prüft das aktive Projekt ohne Build. Ergebnis und Version jedes erfolgreichen Release-Builds stehen im Abschnitt `release` der Projekt-Zusammenfassung; aus = keine Prüfung und kein Befehl | an | Plugin (Registry `ReleaseGuard`) | nein | Kontrollkästchen | #533 |
| Release-Build | Release-Konfigurationen (`build.releaseConfigs`, durch Komma getrennt; „Release“ gilt immer, Groß-/Kleinschreibung egal) | Release | Plugin (Registry `ReleaseConfigs`) | nein | Textfeld | #533 |
| Release-Build | Prüfungen des Wächters (`build.releaseChecks`, durch Komma getrennt; `-name` schaltet eine ab): `debugDefine` (Symbol DEBUG), `debugInfo` (Debug-Informationen; mit Sollwert aus auch „Mit Debug-Informationen linken“), `stackFrames`, `assertions`, `rangeChecks`, `overflowChecks` (je mit Sollwert `=off` oder `=on`; fehlt die Option, gilt die Vorgabe des Compilers), `memoryLeaks` (`ReportMemoryLeaksOnShutdown := True` im Projektquelltext außerhalb von `{$IFDEF DEBUG}`), `versionInfo` (keine Versionsinformationen oder dieselbe Version wie beim letzten erfolgreichen Release-Build derselben Konfiguration und Plattform; nicht mit automatisch erhöhter Build-Nummer), `outputFolder` (Ausgabeordner gleich dem der Konfiguration Debug). Packages ohne `memoryLeaks` und `outputFolder`. Regel-IDs `release-debug-define` bis `release-output-folder` | alle an, Sollwerte aus | Plugin (Registry `ReleaseChecks`) | nein | Kontrollkästchen bzw. Auswahl je Prüfung | #533 |
| Debuggen | Einzelnen Test debuggen (#585, `tests.debug`, Schnellschalter): Befehle „Test am Cursor debuggen“ (*Atlas.DebugTest*) und „Test am Cursor ausführen“ (*Atlas.RunTest*, mit `tests.run`) in der Befehlspalette, Einträge „Test debuggen“/„Test ausführen“ im Kontextmenü des Editors und Marke „Debuggen“ der Code Lens an `[TestFixture]`, `[Test]` und je `[TestCase]`; Atlas baut das Testprojekt (wie „Tests ausführen“), setzt über die Startprofile (#575) vorübergehend die Startparameter `--run:<Unit.Fixture.Methode[.Fall]>` (vorhandene Parameter bleiben, `--run`, `--include`, `--exclude`, `--xmlfile` und `--exitbehavior` weichen) und startet es im Debugger; danach gelten aktives Projekt und Startparameter wie vorher (auch nach einem Absturz beim nächsten Start), das Ergebnis erscheint wie bei „Tests ausführen“. Braucht „Tests ausführen“ und `codeLens.tests`; aus = Befehl, Eintrag, Marke und Tipp verschwinden | an | Plugin (Registry `TestDebug`) | nein | Kontrollkästchen | #585 |
| Debuggen | Beim Test-Debuggen am Anfang der Methode anhalten (`debug.testBreakAtStart`): einmaliger Haltepunkt auf der ersten Anweisung der Testmethode, den Atlas nach dem ersten Halt wieder entfernt (ein eigener Haltepunkt dort bleibt unberührt); nicht beim Debuggen einer ganzen Fixture | an | Plugin (Registry `TestBreakAtStart`) | nein | Kontrollkästchen | #585 |
| Debuggen | Variablenwerte im Hover (`debug.hoverValues`, Schnellschalter): Ist der Prozess angehalten, wertet Atlas den Ausdruck unter der Maus (Bezeichner samt Qualifizierern links davon, z. B. `FList.Count`; nichts in Strings, Kommentaren und mit Aufrufen) über den Debugger der IDE ohne Nebenwirkungen aus und zeigt den Wert oben im Atlas-Tooltip; antwortet der Debugger verzögert (Win64), steht dort „wird ausgewertet …“; mit eigenem Tooltip aus liefert Atlas den Wert an den Tooltip der IDE | an | Plugin (Registry `DebugHoverValues`) | nein | Kontrollkästchen | #891 |
| Debuggen | „kein Zugriff“ beim Debuggen erklären (`debug.explainUnavailable`, Schnellschalter): Scheitert die Auswertung eines Werts im Hover oder in den Werten im Editor mit einem bekannten Text der IDE (deutsch und englisch, etwa „Inaccessible value“ oder „… wegen der Optimierung nicht …“; eigene Ergänzungen in `%LOCALAPPDATA%\Atlas\debug-unavailable.txt`), steht dort `‹kein Zugriff›`. Der Hover nennt die Ursache in fester Reihenfolge: Start in einer Konfiguration ohne Debug-Informationen, `$D-`/`$L-` an der Stelle, `$O+` (Variable im Register), Lebensdauer überschritten oder noch nicht begonnen (Näherung), Routine `inline`, Bibliotheksrahmen ohne Debug-DCUs; dazu die Herkunft des Schalters und Korrekturen mit Vorschau: Mit Debug neu starten, `{$OPTIMIZATION OFF}`/`ON` um die Routine, `{$O-}` am Unit-Anfang, Debug-DCUs verwenden, zur Direktive. Ohne Treffer „Ursache unbekannt“ mit den geprüften Punkten | an | Plugin (Registry `DebugExplainUnavailable`) | nein | Kontrollkästchen | #840 |
| Debuggen | Vervollständigung in Debugger-Dialogen (`debug.completionInDialogs`, Schnellschalter): In „Auswerten/Ändern“ (Strg+F7), im Ausdruck einer Überwachung und in Bedingung und „Ausdruck auswerten“ eines Haltepunkts öffnet Atlas das eigene Popup mit Bezeichnern aus dem Gültigkeitsbereich: lokale Variablen, Parameter, Felder von `Self`, Units und globale Namen, nach `.` die Elemente. Gültigkeitsbereich ist bei angehaltenem Programm der Ausführungspunkt, im Haltepunktdialog dessen Zeile, sonst die Cursorzeile im Editor. Die Liste geht beim ersten Buchstaben eines Worts und nach `.` auf, Strg+Leer öffnet sie von Hand. Pfeil nach unten im leeren Feld zeigt die letzten 20 Ausdrücke des Projekts (`%LOCALAPPDATA%\Atlas\debug-expressions.json`) | an | Plugin (Registry `DebugCompletionInDialogs`) | nein | Kontrollkästchen | #538 |
| Debuggen | Fenster „Auswerten“ (`debug.evaluateWindow`, Schnellschalter): Andockbares Fenster „Atlas: Auswerten“ (Befehl `Atlas.DebugEvaluate`): Enter fügt einen Ausdruck an, Entf entfernt ihn; bei jedem Halt wertet Atlas alle Zeilen in Zeitscheiben neu aus und markiert Werte, die sich seit dem letzten Halt geändert haben. Objekte, Records und Arrays klappen auf, die Felder kommen aus dem Atlas-Index (ohne Server aus dem Ergebnis-String) und werden einzeln ausgewertet. Unten der gewählte Wert als Text (Steuerzeichen sichtbar), Zeilen (`Ausdruck.Text`), JSON oder Hex; „Ändern …“ (F2) setzt einen neuen Wert. Strg+Enter heftet einen Ausdruck fest (`%LOCALAPPDATA%\Atlas\debug-evaluate-pinned.json`, je Projekt); Pfeil nach unten im leeren Feld zeigt die letzten 50 Ausdrücke (`debug-evaluate-history.json`). „Nebenwirkungen erlauben“ (aus) lässt Funktionsaufrufe und Getter zu | an | Plugin (Registry `DebugEvaluateWindow`) | nein | Kontrollkästchen | #784 |
| Debuggen | Strg+F7 öffnet das Atlas-Fenster (`debug.evaluateWindow.replaceCtrlF7`): Atlas hängt sich in die IDE-Aktion „Auswerten/Ändern“: Strg+F7 öffnet das Fenster „Auswerten“ mit der einzeiligen Markierung bzw. dem Ausdruck unter dem Cursor (`Kunde.Adresse.Ort`) im Eingabefeld. Mit gedrückter Umschalttaste (auch beim Klick im Menü „Start“) und mit dem Befehl `Atlas.DebugEvaluateIdeDialog` öffnet die IDE ihren Dialog. Aus = Strg+F7 bleibt unverändert | an | Plugin (Registry `DebugEvaluateReplaceCtrlF7`) | nein | Kontrollkästchen | #784 |
| Debuggen | Zugriffsverletzungen erklären (`debug.explainAccessViolation`, Schnellschalter): Beim Halt wegen einer Zugriffsverletzung in eigenem Code wertet Atlas die Zugriffsketten der Zeile von links aus und nennt in der Exception-Leiste (sonst in den Meldungen) das nil-Glied mit Feld und Versatz, freigegebene Objekte (Füllmuster) und Indizes außerhalb eines dynamischen Arrays; das nil-Glied wird im Editor unterstrichen | an | Plugin (Registry `DebugExplainAccessViolation`) | nein | Kontrollkästchen | #865 |
| Debuggen | Getter und Funktionsaufrufe erlauben (`debug.explainAccessViolation.allowCalls`): Glieder mit Getter, Funktionsaufruf oder Default-Property wertet Atlas nur damit aus (der Debugger ruft dann Code im Prozess auf); aus stehen sie als „nicht ausgewertet“ in der Liste | aus | Plugin (Registry `DebugExplainAccessViolationAllowCalls`) | nein | Kontrollkästchen | #865 |
| Debuggen | Schrittfilter beim Hineinspringen (`debug.stepFilters`, Schnellschalter): F7 überspringt eigene Routinen der gewählten Arten (Getter und Setter mit einer Anweisung, triviale Routinen, Klassen-Operatoren, Konstruktoren und Destruktoren, die nur inherited aufrufen) und Methoden nach Muster: Atlas läuft die Routine bis zur Rückkehr durch und springt dann in den nächsten Aufruf derselben Anweisung bzw. auf die nächste Zeile. Umschalt+F7 (und „Trotzdem hineinspringen“ in der Befehlspalette) ignoriert die Filter für einen Schritt; Haltepunkte in übersprungenen Routinen greifen. Kontextmenü „Beim Hineinspringen überspringen“ / „Nicht mehr überspringen“, Fenster „Schrittfilter“ mit Treffern aus dem Index | an | Plugin (Registry `DebugStepFilters`) | nein | Kontrollkästchen | #850 |
| Debuggen | Exception-Verlauf beim Debuggen (`debug.exceptionHistory`, Schnellschalter): Jeder Halt wegen einer Exception landet im dockbaren Fenster „Atlas: Exceptions“ (Befehl `Atlas.DebugExceptions`) mit Zeit, Klasse, Meldung (aus dem Exception-Dialog der IDE), Anzahl, Ort (erster Rahmen mit Quelltext) und Thread; gleiche Exceptions am selben Ort werden gezählt; Filter nach Klasse und Text, Enter springt an den Ort, Strg+C kopiert Klasse, Meldung und Aufrufstapel; „Klasse künftig ignorieren“ (Liste `%LOCALAPPDATA%\Atlas\debug-ignore.json`) setzt bei dieser Klasse still über den Dialog fort; höchstens 1000 Einträge je Sitzung | an | Plugin (Registry `DebugExceptionHistory`) | nein | Kontrollkästchen | #517 |
| Debuggen | Nur eigener Code beim Debuggen (`debug.justMyCode`, Schnellschalter): Eigener Code sind Units unter den Projektordnern der Projektgruppe und unter `debug.ownCodeFolders`. Nach einer Exception in Bibliothekscode (RTL, VCL, Komponenten) springt Atlas nach dem Schließen des Exception-Dialogs zur ersten eigenen Zeile im Aufrufstapel und markiert sie; landet F7 (Einzelne Anweisung) in Code ohne Quelltext, setzt Atlas „Bis zur Rückkehr ausführen“ fort, bis wieder Quelltext erreicht ist (höchstens 16-mal); im Fenster „Atlas: Exceptions“ ist der Ort der erste eigene Rahmen, der Aufrufstapel zeigt Bibliotheksrahmen abgeschwächt und fasst zwei und mehr zu „… n Bibliotheksrahmen“ zusammen; Befehl `Atlas.DebugJustMyCode` schaltet um | an | Plugin (Registry `DebugJustMyCode`) | nein | Kontrollkästchen | #578 |
| Debuggen | Exception-Leiste statt Dialog (`debug.exceptionBanner`, Schnellschalter): Baut auf `debug.exceptionHistory` auf. Hält der Debugger wegen einer Exception, steht oben im Editor eine Leiste: Klasse, Meldung, Thread, wie oft die Klasse an dieser Stelle kam, Aufrufstapel gekürzt auf die erste eigene Zeile („n Ebenen ausgeblendet“, die Zeile ist markiert), Knöpfe Anhalten (F8/Esc), Fortsetzen (F9), Klasse ignorieren, Nur an dieser Stelle ignorieren, Meldung kopieren. In Delphi 12 und 13 schließt Atlas den Exception-Dialog der IDE über „Anhalten“; in anderen Versionen oder mit dem Befehl `Atlas.DebugExceptionIdeDialog` bleibt der Dialog, und die Leiste erscheint nach ihm (Hinweis im Statusfeld). Vorgabe aus, bis die Studie (docs/Studie-Exception-Dialog.md) positiv ist | aus | Plugin (Registry `DebugExceptionBanner`) | nein | Kontrollkästchen | #783 |
| Debuggen | Nur an dieser Stelle ignorieren (`debug.exceptionBanner.ignoreAtLocation`): Knopf der Exception-Leiste: merkt Klasse + Unit + Zeile je Projekt in `%LOCALAPPDATA%\Atlas\debug-ignore.json`; kommt dieselbe Kombination wieder, setzt Atlas still fort und zählt nur im Exception-Verlauf. An einer anderen Zeile hält der Debugger weiter. Aus = kein Knopf, gemerkte Orte wirken nicht | an | Plugin (Registry `DebugExceptionBannerIgnoreAtLocation`) | nein | Kontrollkästchen | #783 |
| Debuggen | Werte im Editor beim Debuggen (`debug.inlineValues`, Schnellschalter): Steht der Prozess (Haltepunkt, Einzelschritt, Pause), nennt der Server die lokalen Variablen, Parameter, Schleifenvariablen und Felder von `Self` der Routine mit dem Ausführungspunkt, vom Routinenanfang bis zur aktuellen Zeile (`textDocument/inlineValue`); Atlas wertet sie ohne Nebenwirkungen über den Debugger der IDE aus (nie Aufrufe, Eigenschaften oder Felder in `with`) und schreibt sie gedimmt hinter das Zeilenende: `Count = 3, Name = 'Meier'`. Seit dem letzten Halt geänderte Werte sind hervorgehoben, lange Werte gekürzt, `TDateTime`/`TDate`/`TTime` als Datum bzw. Uhrzeit. Ausgewertet wird in Zeitscheiben von höchstens 30 ms, damit F8 nicht spürbar langsamer wird; beim Fortsetzen verschwinden die Werte | an | Plugin (Registry `DebugInlineValues`) | nein | Kontrollkästchen | #508 |
| Debuggen | Weitere Ordner mit eigenem Code (`debug.ownCodeFolders`, durch „;“ getrennt, Groß-/Kleinschreibung egal; die Ordner der Projekte der Gruppe gelten immer, Unterordner zählen mit) | leer | Plugin (Registry `DebugOwnCodeFolders`) | nein | Textfeld | #578 |
| Baseline | `atlas-baseline.json` | – | Datei, `--baseline`, `--update-baseline` | nein | Anzahl Einträge, „Baseline neu erzeugen“, „Baseline löschen“ | #97 |
| Projektdatei | Projektdatei `.atlas` (#486) lesen (`teamFile.enabled`, Schnellschalter): Einstellungen des Plugins für alle im Team, im Ordner der .dproj, sonst in der Wurzel des Repositorys (nächster Ordner mit `.git`); JSON mit Kommentaren und `version` (1) mit `naming` (Präfixe `field`, `parameter`, `local`, #452, und `constant` für die Prüfregel naming-prefix, #1111), `snippets` (Ordner mit Projekt-Vorlagen, #51), `formatFunctions` (`name`, `formatIndex`, #451), `sqlTargets` (#462), `fileMethods` (#478), `mainThreadExceptions` (#484), `startProfiles` (`name`, `parameters`, `workingDir`, `host`, `environment`, #575), `ci` (`provider` jenkins, `url`, `job`, `multibranch`, #763) `tracker` (`provider` github oder youtrack, `url`, `project`, #765), `hidden` (am Element ausgeblendete Stellen: `setting` = Schlüssel der Einstellung des Elements, `file` relativ zur `.atlas`, `anchor` = Methode, Zeilentext o. Ä., ohne `anchor` gilt es für die ganze Datei; schreibt „Nur hier/In dieser Datei ausblenden“, #628) und `debugDisplayRules` (`debug.displayRules.project`: Typname → Vorlage oder `{template, children}`, Wertdarstellung beim Debuggen für fremde Klassen, #854). Werte aus `.atlas` haben Vorrang vor den persönlichen (Listen ergänzen sich), der Reiter *Projektdatei* zeigt jeden mit „aus .atlas“. Zugangsdaten, absolute Pfade und Pfade außerhalb des Repositorys werden ignoriert (ein Startprofil damit ganz), fehlerhafte Dateien und ignorierte Einträge in der Meldungsansicht gemeldet; dann gelten die persönlichen Einstellungen. Befehl *Projektdatei .atlas öffnen* (*Atlas.TeamFile*, Befehlspalette, Knopf auf dem Reiter) legt die Datei mit Gerüst an und öffnet sie | an | Plugin (Registry `TeamFile`); Datei `.atlas` im Repository | nein | Kontrollkästchen, Werte „aus .atlas“, Knopf „Projektdatei öffnen“ | #486 |
| Baseline | Unterdrückungen `lsp-ignore` | – | `--suppression-stats` | nein | Übersicht je Regel (nur Anzeige) | #147 |
| Speicher | Index-Cache löschen | – | `--clear-cache`, Befehl `atlas.server.clearIndex` (löschen und neu indizieren), `atlas.server.rebuildIndex` (nur neu indizieren) | nein | Knöpfe „Index löschen“ und „Index neu aufbauen“ | #184, #492 |
| Allgemein | Atlas-Feld in der Statusleiste (`statusField.enabled`), Kurztext (`statusField.showSummary`), Schnellschalter öffnen mit (`statusField.openToggles`: both, rightClick, doubleClick), ausgeblendete Zeilen (`statusField.hidden`) | an, an, both, – | Plugin (Registry `StatusField`, `StatusFieldSummary`, `StatusFieldToggles`, `StatusFieldHidden`) | nein | Kontrollkästchen, Kontrollkästchen, Auswahl, Textfeld mit Kennungen | #591 |
| Allgemein | Fortschritt beim Aufbau des Symbol-Index (`statusField.indexProgress`: statusField, menu, off); mit abgeschaltetem Statusfeld steht er im Menütitel | statusField | Plugin (Registry `IndexProgressPlace`) | nein | Auswahl | #492, #591 |
| Allgemein | Schnellschalter (#604): Fenster über dem Statusfeld (Rechtsklick oder Doppelklick) und Tastenkürzel; Schalter = jede boolesche Einstellung mit `x-quickToggle` (Plugin-Katalog und `atlas.schema.json`) | Strg+Umschalt+Alt+A | Plugin (Registry `QuickToggleKey`, `QuickToggleKeyPriority`) | nein | Taste auf der Seite „Tastenkonflikte“; „Alles aus für diese Sitzung“ ändert keine Einstellung | #604 |
| Allgemein | Diagnosemodus (`diagnosticMode.enabled`, Schnellschalter): andockbares Fenster „Atlas-Diagnose“ mit der Dauer jedes Schritts der letzten Abfrage (Kontext, je Quelle mit Namen, Filtern und Sortieren, Zeichnen, bis zur Liste, Anzahl der Einträge) sowie Mittelwert und Maximum der letzten 50 Abfragen; Überschreitungen des Budgets aus #409 in Warnfarbe; „Bericht kopieren“ ohne Quelltext, Dateinamen nur mit Häkchen; gelbe Zeile im Statusfeld; Tastenkürzel (Strg+Alt+Umschalt+A gehört den Schnellschaltern) | aus, Strg+Umschalt+Alt+D | Plugin (Registry `DiagnosticMode`, `DiagnosticModeKey`, `DiagnosticModeKeyPriority`); letzte Diagnosedaten in `%LOCALAPPDATA%\Atlas\Logs\Diagnose\atlas-diagnosemodus.txt` | nein | Kontrollkästchen; Taste auf der Seite „Tastenkonflikte“ | #479 |
| Allgemein | Architekturübersicht (`architecture.enabled`, Schnellschalter; Unterpunkt „Architektur“): andockbares Fenster „Atlas-Architektur“ (*Ansicht › Atlas › Architektur*, Befehlspalette *Atlas.Architecture*) mit Karte der Teilsysteme, zentralen Units, Teilsystemen mit Ausreißern, Zyklen und Querverbindungen, Doppelklick springt zur Unit bzw. zum uses-Eintrag; „Bericht speichern …“ als HTML-Seite oder Markdown; Umfang (`architecture.scope`: projectGroup, project), Bibliotheks-Units mitzählen (`architecture.includeLibraryUnits`), Zahl der zentralen Units (`architecture.centralUnits`, 5–100); das Fenster legt sich beim ersten Öffnen einmal rechts neben die Projektverwaltung (Zustand `ui.architectureWindowPlaced`), danach gilt die Lage aus dem Desktop; dieselben Werte nutzen `--architecture` und das MCP-Werkzeug `get_architecture`; am selben Schalter hängt das Fenster „Unit-Beziehungen“ (*Ansicht › Atlas › Unit-Beziehungen*, Befehlspalette *Atlas.UnitRelations*; Zustand `ui.unitRelationsWindowPlaced`), dazu *Atlas.UnitDependencies* („Abhängigkeiten dieser Unit“) und *Atlas.InterfaceCostRanking* („Teuerste Units bei interface-Änderungen“, Reiter „Zentrale Units“ nach gesamt abhängig, #554); aus = kein Menüeintrag, kein Fenster, keine Befehle, kein Feld in der Statusleiste, kein MCP-Werkzeug | an, projectGroup, aus, 15 | `%APPDATA%\Atlas\settings.json` (`architecture.*`, wie der Server) | nein | Kontrollkästchen, Auswahl, Kontrollkästchen, Zahl | #1118, #593, #554 |
| Allgemein | Einrichtung mit Prüfliste (`ui.setupChecklist`): Fenster „Atlas-Einrichtung“ beim IDE-Start zeigen, solange nicht alles grün ist (beim ersten Start immer); prüft Server (gefunden, gestartet, Version passend), Delphi-Version und Plattform, Index der Projektgruppe je Projekt, Bibliotheks-Cache, Error Insight gegen doppelte Meldungen und Tastenkonflikte, jeder gelbe oder rote Punkt mit Knopf; aus = nur auf Abruf (*Atlas › Einrichtung prüfen …*, Befehlspalette, Zeile „Einrichtung“ im Statusfeld) | an | Plugin (Registry `SetupChecklist`; schon einmal gezeigt in `SetupChecklistSeen`) | nein | Kontrollkästchen, auch im Fenster selbst | #625 |
| Tastenkonflikte | Tastenkürzel-Übersicht (#520): Menüeintrag *Atlas › Tastenkürzel-Übersicht…* und Befehl der Befehlspalette (`keys.overview`) mit allen Kürzeln aus IDE, Atlas und anderen Erweiterungen, Konflikten in Rot und HTML-Export; beim Start die Atlas-Tasten prüfen und jeden Konflikt einmal in der Meldungsansicht melden (`keys.startupCheck`) | an, an | Plugin (Registry `KeyOverview`, `KeyStartupCheck`); Export in `%LOCALAPPDATA%\Atlas\Tastenkuerzel.html` | nein | Kontrollkästchen, Kontrollkästchen | #520 |
| Allgemein | Tastenkürzel-Tipps (`shortcutTips.enabled`, Schnellschalter): wer eine IDE- oder Atlas-Aktion mit Kürzel per Maus (Hauptmenü, Kontextmenü, Werkzeugleiste, Befehlspalette) aufruft, sieht 4 s lang unten rechts im Editor das Kürzel mit Tastenkappen, „Nicht mehr zeigen“ und „Alle Kürzel“; höchstens ein Tipp je Aktion und Tag, keiner nach dreimaliger Nutzung des Kürzels, nicht bei angehaltener Debug-Sitzung oder offenem modalem Dialog, höchstens alle 30 s; für welche Befehle (`shortcutTips.scope`: atlas = nur Atlas-Befehle, all = auch die der IDE); Zählung je Befehl auch für die Spalte „Selten per Tastatur“ der Tastenkürzel-Übersicht und die Karte „Atlas entdecken“ (#757); Titel des Tipps aus `tips.json`, wenn es dort einen Tipp zum Befehl gibt | an, all | Plugin (Registry `ShortcutTips`, `ShortcutTipsScope`); Zählung je Befehl nur lokal in `%LOCALAPPDATA%\Atlas\usage.json` (#757), letzter Tipp und „Nicht mehr zeigen“ je Befehl in `%LOCALAPPDATA%\Atlas\shortcut-tips.json` | nein | Kontrollkästchen, Auswahl | #600 |
| Allgemein | Benachrichtigungszentrale (`notifications.enabled`, Schnellschalter): Build fertig, Hintergrundprüfung, neu geladene Dateien, Server-Neustarts und -Meldungen sowie Tastenkürzel-Tipps landen als Einträge in einer Liste über dem Atlas-Statusfeld (Klick auf die Zahl im Feld, Befehl *Atlas.Notifications*, Tastenkürzel); neueste zuerst mit Symbol nach Schwere, Titel, Text, Quelle und Uhrzeit, ungelesene hinterlegt, Aktionen wie „Zum Fehler“, „Vergleichen“, „Protokoll öffnen“ als Knöpfe; „Alle gelesen“, „Liste leeren“, Filter nach Quelle; gleichartige Hinweise innerhalb von 10 s werden zusammengefasst („3 × Server neu gestartet“); die Zahl im Statusfeld zählt die ungelesenen in der Farbe des schwersten; gilt für die IDE-Sitzung; aus: jede Funktion zeigt ihre Hinweise wie bisher, nichts wird gesammelt | an | Plugin (Registry `Notifications`) | nein | Kontrollkästchen | #601 |
| Allgemein | Verhalten je Quelle (`notifications.sources`): `quelle=verhalten`, kommagetrennt; Quellen build, check, reload, server, buildServer (Build-Server rot geworden, #763), shortcutTips, openBuild (Zusammenfassung „Beim Öffnen gebaut“, `build.onOpen`), hidden (Hinweis „Ausgeblendet · Rückgängig“ und Ablehnungen beim Ausblenden am Element, #628), unitRename (Hinweis „N Units verwenden noch …“ nach dem Umbenennen einer Unit, #512); Verhalten show = einblenden und sammeln, collect = nur sammeln (keine eigene Einblendung bzw. keine Zeile im Meldungsfenster), off = weder noch; auch im Kontextmenü eines Eintrags; „Build fertig“ hat noch keine eigene Einblendung (#535), dort wirken show und collect gleich | leer (alle show) | Plugin (Registry `NotificationsSources`) | nein | Auswahl (Quelle, Verhalten) | #601, #763, #628, #512 |
| Allgemein | Höchstzahl der Einträge in der Liste der Benachrichtigungen (`notifications.maxEntries`, 10–1000); ältere fallen weg | 200 | Plugin (Registry `NotificationsMaxEntries`) | nein | Zahl | #601 |
| Allgemein | Abgesicherter Start nach einem Absturz: Rückfrage (`safeMode.askAfterCrash`), ohne Rückfrage nach zwei Abstürzen (`safeMode.autoAfterRepeatedCrash`), Taste beim Laden (`safeMode.startupKey`: shift, ctrl, none), langsamer Start ab (`safeMode.startupTimeoutMs`; Atlas nennt dann seine Startanteile im Meldungsfenster, abschaltbar mit `robustness.hangHint`, und im Protokoll; kein Absturz, Bericht N4), gemerkte Einstellungsstände (`safeMode.keepSettingsHistory`) | an, an, shift, 30000, 5 | Plugin (Registry `SafeAskAfterCrash`, `SafeAutoAfterRepeatedCrash`, `SafeStartupKey`, `SafeStartupTimeoutMs`, `SafeKeepSettingsHistory`); Kommandozeile `-AtlasSafeMode`, Umgebungsvariable `ATLAS_SAFE_MODE=1` | nein | Kontrollkästchen, Kontrollkästchen, Auswahl, Zahl (1000–120000), Zahl (0–50) | #722 |
| Allgemein | Atlas-Änderungen über mehrere Dateien zurücknehmen: an/aus (`undo.multiFile`), Anzahl Sätze (`undo.multiFile.depth`), über Neustarts sichern (`undo.multiFile.persist`) bis höchstens MB (`undo.multiFile.maxSizeMb`), bei Konflikten (`undo.multiFile.onConflict`: partial, abort), neu angelegte Dateien (`undo.multiFile.newFiles`: recycleBin, delete, keep), Tasten Zurücknehmen und Wiederherstellen | an, 20, an, 50, partial, recycleBin, Strg+Alt+Z, Strg+Alt+Umschalt+Z | Plugin (Registry `UndoMultiFile`, `UndoMultiFileDepth`, `UndoMultiFilePersist`, `UndoMultiFileMaxSizeMb`, `UndoMultiFileOnConflict`, `UndoMultiFileNewFiles`, `UndoKey`, `RedoKey`); Sicherung in `%LOCALAPPDATA%\Atlas\undo` | nein | Kontrollkästchen, Zahl (1–200), Kontrollkästchen, Zahl (1–1024), Auswahl, Auswahl, Tastenkürzel, Tastenkürzel | #721 |
| Allgemein | Nach Zustimmung beim ersten Start höchstens einmal täglich auf eine neue Atlas-Version prüfen (`updates.check`); übertragen werden nur Atlas- und IDE-Version, ein Hinweis erscheint in der Meldungsansicht und als gelbe Zeile „Version“ im Statusfeld und in der Zustandskachel | aus | Plugin (Registry `UpdatesCheck`); Zustand (auch die gefundene neue Version) in `%LOCALAPPDATA%\Atlas\updates.json` | nein | Kontrollkästchen | #495 |
| Allgemein | Fehlerbericht (*Atlas › Fehlerbericht erstellen…*) anonymisieren: Pfade unter dem Projekt zu `<ws>`, andere Pfade zu `<pfad>`, Benutzername und Bezeichner im Protokoll ersetzen (`diagnostics.bugReport.anonymize`) | an | Plugin (Registry `BugReportAnonymize`) | nein | Kontrollkästchen | #108 |
| Allgemein | Einstellungen exportieren, importieren und zurücksetzen (`settings.exportImport`, Schnellschalter): Knöpfe unten auf *Tools › Optionen › Atlas* und Befehle *Atlas.SettingsExport*, *Atlas.SettingsImport*, *Atlas.SettingsProfile*, *Atlas.SettingsReset* (Befehlspalette) sowie `AtlasSetup.exe /exportSettings`, `/importSettings`, `/resetSettings`; geänderte Werte mit Punkt am Feld (`settings.markModified`), Sicherung in `%APPDATA%\Atlas\Backups` vor jedem Import (`settings.backupBeforeImport`), Zugangsdaten auslassen oder als Platzhalter (`settings.exportSecrets`: omit, placeholder); Bereiche siehe unten | an, an, an, omit | Plugin (Registry `SettingsExportImport`, `SettingsMarkModified`, `SettingsBackupBeforeImport`, `SettingsExportSecrets`) | nein | Kontrollkästchen, Auswahl, Knöpfe „Exportieren…“, „Importieren…“, „Profil laden…“, „Seite zurücksetzen“, „Alles zurücksetzen…“, Kontextmenü „Auf Standard zurücksetzen“ | #723 |
| Vervollständigung | Favoriten anheften (`completion.favorites`, Schnellschalter): Strg+D in der offenen Liste oder Klick auf den Stern, der beim Überfahren einer Zeile erscheint, heftet den Eintrag an bzw. löst ihn; angeheftete Einträge stehen mit Stern links vor allen anderen Gruppen, unabhängig von Lernen und Rangfolge, aber nur, wenn sie zum getippten Präfix passen; je Paar (Typ, Member) wie die lernende Gewichtung, höchstens 5 je Typ (ein sechster ersetzt nichts, die Fußzeile nennt den Grund); Liste mit „Entfernen“ und „Alle entfernen“ auf der Optionsseite | an | Plugin (Registry `Favorites`); Favoriten in `%APPDATA%\Atlas\favorites.json` (Typ, Member, Art, Unit, Signatur, Zeitpunkt; lesbar ohne Server) | nein | Kontrollkästchen, Liste mit Knöpfen | #458 |
| Editor | Zwischen Unit und Testunit wechseln: Code Lens über der Zeile `unit …;` (`codeLens.testUnit`) und Tastenkürzel (Befehl auch im Atlas-Menü, Kontextmenü und in der Befehlspalette) | an, keins | Plugin (Registry `CodeLensTestUnit`, `TestUnitKey`) | nein | Kontrollkästchen, Tastenkürzel | #189 |
| Editor | Code Lens „Test ausführen“ (`codeLens.tests`, Schnellschalter; gemeinsamer Schlüssel mit „Test debuggen“ #585): hinter `[TestFixture]` und `[Test]`/`[TestCase]` (bzw. der Deklaration registrierter Fixtures und published-Methoden) eine Marke mit dem Ergebnis des letzten Laufs (bestanden grün, fehlgeschlagen rot, während eines Laufs „Tests laufen …“); Klick startet den Test bzw. alle Tests der Fixture; ein `[TestCase]` in eigener Zeile hat eine eigene Marke „Fall ausführen“ (#585); daneben „Debuggen“, wenn „Test debuggen“ an ist. Braucht „Tests ausführen“; aus = keine Marken und auch kein „Test am Cursor debuggen/ausführen“ über Befehl oder Kontextmenü (#585) | an | Plugin (Registry `CodeLensTests`) | nein | Kontrollkästchen | #69 |
| Editor | Code-Metriken (#66): Code Lens hinter dem Kopf jeder implementierten Methode mit Länge, Verschachtelungstiefe, zyklomatischer und kognitiver Komplexität und Parameteranzahl, Werte über dem Grenzwert markiert (`codeLens.metrics`, Schnellschalter; Grenzwerte als `max` der Regeln `metric-*` in atlas.json); Befehl „Metrikbericht des Projekts“ (*Atlas.MetricsReport*, Befehlspalette, abschaltbar mit `metrics.report`, Schnellschalter; aus = der Befehl verschwindet) schreibt den Markdown-Bericht des aktiven Projekts nach `%LOCALAPPDATA%\Atlas\Berichte\Metriken-<Projekt>.md` und öffnet ihn; nach jedem Build (nicht nach einer Hintergrundprüfung) legt das Plugin die Zusammenfassung im Abschnitt `metrics` der Projekt-Zusammenfassung ab (Projektverlauf #758) | an, an | Plugin (Registry `CodeLensMetrics`, umgeleitet nach settings.json `codeLens.metrics`; Registry `MetricsReport`); Zusammenfassung in `%LOCALAPPDATA%\Atlas\projects\<Schlüssel>.json` | nein | Kontrollkästchen, Kontrollkästchen | #66 |
| Editor | TODO-Übersicht (#68): Befehle „TODOs des Projekts“ (*Atlas.TodoList*) und „TODOs des Projekts filtern …“ (*Atlas.TodoListFilter*, Kategorie, Person, Unit, Marke, Erledigte) in der Befehlspalette (`todos.list`, Schnellschalter; aus = beide Befehle verschwinden) listen die offenen `// TODO`, `// FIXME` und `{ TODO … }` des aktiven Projekts nach Unit im Ergebnisfenster; Marken als `keywords` der Regel `todo-comment` in atlas.json (Vorgabe `TODO`, `FIXME`), Hinweise im Editor nur mit eingeschalteter Regel; nach jedem Build legt das Plugin die Zählung im Abschnitt `todos` der Projekt-Zusammenfassung ab (Projektverlauf #758) | an, Hinweise aus | Plugin (Registry `TodoList`); Server (atlas.json `rules.todo-comment`: Schweregrad und `keywords`); Zusammenfassung in `%LOCALAPPDATA%\Atlas\projects\<Schlüssel>.json` | nein | Kontrollkästchen; Regel und Marken nur in atlas.json | #68 |
| Editor | Baseline für Altprojekte (#97): Befehl „Baseline des Projekts aktualisieren“ (*Atlas.UpdateBaseline*, Befehlspalette, abschaltbar mit `baseline.update`, Schnellschalter; aus = der Befehl verschwindet, die Baseline wirkt weiter) lässt den Server (`atlas.updateBaseline`) alle Dateien des aktiven Projekts prüfen und `atlas-baseline.json` im Arbeitsbereich neu schreiben; vorher nennt er Einträge, deren Datei es nicht mehr gibt, und fragt nach, danach stehen die Zähler (neu, entfernt, unverändert) im Meldungsfenster; nach jedem Build und nach dem Aktualisieren legt das Plugin den Stand der Baseline im Abschnitt `baseline` der Projekt-Zusammenfassung ab (Projektverlauf #758, Einrichtung #759) | an | Plugin (Registry `BaselineUpdate`); Zusammenfassung in `%LOCALAPPDATA%\Atlas\projects\<Schlüssel>.json` | nein | Kontrollkästchen | #97 |
| Editor | Eigenschaftsregeln für Formulare (#309): Befehle „Eigenschaftsregeln anwenden: Formular“, „…: Projekt“ und „…: Projektgruppe“ (*Atlas.ApplyDfmRulesForm*, *Atlas.ApplyDfmRulesProject*, *Atlas.ApplyDfmRulesGroup*, Befehlspalette, abschaltbar mit `dfmRules.apply`, Schnellschalter; aus = die Befehle verschwinden, Regel `dfm-property` und Schnellkorrektur bleiben) lassen den Server (`atlas.server.applyDfmPropertyRules`) die Korrekturen aller Regeln aus `dfmPropertyRules` in den Formulardateien sammeln; eine Vorschau zeigt jede geänderte Zeile vorher und nachher, erst „Anwenden“ übernimmt sie (offene Formulare im Designer, die übrigen auf der Platte) | an | Plugin (Registry `DfmPropertyRules`) | nein | Kontrollkästchen | #309 |
| Editor | Persönliche Notizen an Codezeilen (`notes.enabled`, Schnellschalter): *Atlas › Notiz an dieser Zeile…* (Befehlspalette, Atlas-Untermenü im Editor-Kontextmenü; nach Rechtsklick in die Rinne für die angeklickte Zeile) legt eine ein- oder mehrzeilige Notiz an, ein Symbol in der Rinne zeigt sie, Überfahren zeigt den Text; *Atlas › Notizen des Projekts* listet alle im Ergebnisfenster (Datei, Zeile, Text, Doppelklick springt, verwaiste Notizen gesondert); die Notiz folgt ihrer Zeile über Inhalt und je zwei Nachbarzeilen | an | Plugin (Registry `Notes`); Notizen je Projekt in `%LOCALAPPDATA%\Atlas\Notes\<Schlüssel>.json`, nie im Repository | nein | Kontrollkästchen | #545 |
| Editor | Benannte Lesezeichen (`bookmarks.named`, Schnellschalter): *Atlas › Lesezeichen setzen…* (Strg+Alt+K, Befehlspalette, Atlas-Untermenü im Editor-Kontextmenü; nach Rechtsklick in die Rinne für die angeklickte Zeile) fragt nach dem Namen und schlägt Methode und Zeilenbeginn vor; ein Band in der Rinne zeigt das Lesezeichen, Überfahren zeigt den Namen; *Atlas › Gehe zu Lesezeichen…* sucht unscharf über Name, Datei und Methode; das Seitenfenster *Atlas › Lesezeichen-Fenster* listet Name, Datei, Methode und Zeilenvorschau mit Filter (Klick oder Enter springt, F2 benennt um, Entf löscht, Ziehen sortiert); das Lesezeichen sucht zuerst seine Methode und dann den Zeilentext darin, fehlt beides, steht es als „nicht gefunden“ in der Liste; aus: alles ruht, die IDE-Lesezeichen bleiben unberührt | an | Plugin (Registry `BookmarksNamed`) | nein | Kontrollkästchen | #622 |
| Editor | Lesezeichen im Repository für das Team (`bookmarks.shared`): `atlas-bookmarks.json` neben der .dproj zum Einchecken statt der persönlichen `.atlas-bookmarks.json` (die Atlas lokal in `.git/info/exclude` einträgt); gibt es die Team-Datei noch nicht, gelten zunächst die persönlichen Lesezeichen | aus | Plugin (Registry `BookmarksShared`) | nein | Kontrollkästchen | #622 |
| Editor | Tastenkürzel für „Lesezeichen setzen…“ (`bookmarks.key`, Reiter *Befehle*; leer = keins) | Strg+Alt+K | Plugin (Registry `BookmarkKey`) | nein | Tastenkürzel | #622 |
| Editor | Beschriftung hinter dem `end` langer Blöcke (`editor.blockEndLabels`, Schnellschalter): „// TKunde.Speichern“ bzw. „// if Kunde.Aktiv“ als leiser Text hinter dem `end` von Methoden und Blöcken ab einer Länge, die der Server meldet (Inlay-Hints vom Server, #401); läuft auch bei ausgeschalteten Inlay-Hints | an | Plugin (Registry `BlockEndLabels`) | nein | Kontrollkästchen | #620, #628 |
| Editor | Fehlertext am Zeilenende (`editor.inlineDiagnostics`: `off`, `errors`, `errorsAndWarnings`, `all`): hinter dem letzten Zeichen steht gekürzt der Text der schwersten Diagnose der Zeile in ihrer Farbe, gedimmt; weitere als „(+2)“; in der Cursorzeile erst nach 1 s Tipp-Pause; teilt den Platz mit Inlay-Hints und Blockende-Beschriftungen; nur mit `problems.enabled` | errors | Plugin (Registry `InlineDiagnostics`) | nein | Auswahl | #509 |
| Compiler | Zähler „Fehler/Warnungen/Hinweise“ in der Statusleiste (`problems.statusCounter`): zählt wie die Liste „Atlas-Probleme“ (ohne Compilermeldungen); ein Klick öffnet die Liste; ausgeblendet, solange die Atlas-Statusleiste am Editor ihre Befundzähler zeigt (#1155) | an | Plugin (Registry `ProblemsStatusCounter`) | nein | Kontrollkästchen | #509 |
| Befehle | Nächster bzw. vorheriger Befund in der Datei (`keys.nextProblem`, `keys.previousProblem`; leer = keins; auch Befehlspalette *Atlas.NextProblem*/*Atlas.PreviousProblem* und Atlas-Untermenü im Editor-Kontextmenü): springt über alle Atlas-Diagnosen der Datei, am Ende wieder von vorn | Strg+Alt+F8, Strg+Alt+Umschalt+F8 | Plugin (Registry `NextProblemKey`, `PreviousProblemKey`) | nein | Tastenkürzel | #509 |
| Editor | Ausblenden direkt am Element (#628): Rechtsklick auf Code Lens, Blockende-Beschriftung oder Inlay-Hint, für Unterstreichungen, Randsymbole (Notizen, Lesezeichen), Klammerfarben, Blocklinien, Abblendungen und die Vorschau der Vervollständigung der Eintrag „Element ausblenden …“ im Editor-Kontextmenü (gilt für die Stelle des Rechtsklicks) oder Strg+. (an der Cursorzeile) bietet „Nur hier ausblenden“ (bei Befunden mit Regel ein Unterdrückungskommentar `// lsp-ignore: <Regel>` über der Zeile, #147; sonst ein Eintrag im Abschnitt `hidden` der Projektdatei `.atlas`), „In dieser Datei ausblenden“ (`// lsp-ignore-file: <Regel>` am Dateianfang bzw. Eintrag ohne `anchor`; Elemente, die nur ganze Dateien kennen, bieten nur diesen und „überall“), „… überall ausblenden“ (schaltet die Einstellung des Elements aus, alle verschwinden sofort) und „Einstellungen dazu …“ (öffnet *Tools › Optionen › Atlas* mit der Zeile hervorgehoben); danach kurz „Ausgeblendet · Rückgängig“ (Benachrichtigungsquelle `hidden`); Befehl *Atlas.HideElement* in der Befehlspalette; Taste (`keys.hideElement`, Reiter *Befehle*; leer = keins; Vorrang wie die Editorbefehle, sonst bleibt Strg+. bei der IDE) | Strg+. | Plugin (Registry `HideElementKey`); „Nur hier“ und „In dieser Datei“ ohne Regel in `.atlas` (braucht `teamFile.enabled`) | nein | Tastenkürzel | #628 |
| Befehle | Erzeugen-Menü (`keys.generateMenu`, Schnellschalter): Alt+Einfg, *Atlas › Erzeugen…*, Atlas-Untermenü im Editor-Kontextmenü und Befehlspalette (*Atlas.GenerateMenu*) öffnen am Cursor ein Menü mit den Gruppen Erzeugen (Schnellbefehle mit Ortsregel aus #293, „Interface implementieren“, Code-Aktionen der Art refactor), Umschließen (nur mit Markierung) und Vorlagen (Code-Vorlagen mit passendem `context:`); jede Zeile mit Ziffer 1–9 und `/name`, Tippen filtert unscharf, zuletzt gewählte stehen oben, Einträge mit Auswahl (Felder, Methoden) öffnen sie; Entf blendet einen Eintrag aus; aus: die Funktion ruht, Alt+Einfg bleibt frei | an | Plugin (Registry `GenerateMenu`); zuletzt gewählte in `%APPDATA%\Atlas\generate-recent.txt` | nein | Kontrollkästchen | #719 |
| Befehle | Tastenkürzel des Erzeugen-Menüs (`keys.generateMenu.key`; leer = keins) | Alt+Einfg | Plugin (Registry `GenerateMenuKey`) | nein | Tastenkürzel | #719 |
| Befehle | Gruppen des Erzeugen-Menüs in ihrer Reihenfolge (`keys.generateMenu.groups`: generate, surround, templates; fehlt eine, fehlt sie im Menü) | generate,surround,templates | Plugin (Registry `GenerateMenuGroups`) | nein | Textfeld | #719 |
| Befehle | Ausgeblendete Einträge des Erzeugen-Menüs (`keys.generateMenu.hidden`): Kennungen wie `slash:json`, `snippet:tryf`, `action:Titel` oder Namen wie `/json`, `tryf`, kommagetrennt; Entf im Menü ergänzt die Liste | leer | Plugin (Registry `GenerateMenuHidden`) | nein | Textfeld | #719 |
| Befehle | Zuletzt gewählte Einträge oben im Erzeugen-Menü, höchstens drei (`keys.generateMenu.recentFirst`) | an | Plugin (Registry `GenerateMenuRecentFirst`) | nein | Kontrollkästchen | #719 |
| Befehle | Befehlsnamen (`/ctor`, Kürzel der Vorlage) rechts in den Zeilen des Erzeugen-Menüs (`keys.generateMenu.showCommandNames`) | an | Plugin (Registry `GenerateMenuShowCommandNames`) | nein | Kontrollkästchen | #719 |
| Befehle | Tastenkürzel der Liste der Benachrichtigungen (`notifications.key`; leer = keins; Vorrang wie die Editorbefehle) | Strg+Umschalt+Alt+N | Plugin (Registry `NotificationsKey`) | nein | Tastenkürzel | #601 |
| Befehle | Treffersicherheit der Verwendungen (#1119): Verwendungen, Aufrufhierarchie, Einblenden und Umbenennen zeigen neben den sicheren Stellen erschlossene mit Grund (Interface, überschriebene Methode, unklare Überladung, unbekannter Typ, inaktiver Zweig; `references.inferred`, Schnellschalter); das Ergebnisfenster trennt „Sicher“ und „Erschlossen · vor dem Umbenennen prüfen“ und filtert mit „Nur sichere“, Umbenennen ändert nur sichere Stellen und listet die übrigen; Namen in String-Literalen als erschlossene Treffer (`references.textMatches`) | an, aus | Plugin (Registry `ReferencesInferred`, `ReferencesTextMatches`, umgeleitet nach settings.json `references.inferred`, `references.textMatches`) | nein | Kontrollkästchen, Kontrollkästchen | #1119 |
| Units suchen | Fenster „Units suchen“ von Atlas (`unitSearch.enabled`); aus: Strg+F12 bleibt beim IDE-Dialog | an | Plugin (Registry `UnitSearchEnabled`) | nein | Kontrollkästchen | #777 |
| Units suchen | Strg+F12 und *Ansicht › Units* öffnen das Atlas-Fenster; mit Umschalt bzw. Befehl *IDE-Dialog Units suchen* der IDE-Dialog (`unitSearch.replaceIdeDialog`) | an | Plugin (Registry `UnitSearchReplaceIdeDialog`) | nein | Kontrollkästchen | #777 |
| Units suchen | Alt+F11 und *Datei › Unit verwenden* öffnen das Atlas-Fenster im Modus „Unit verwenden in <Unit>“ (`unitSearch.replaceUseUnitDialog`): Umschalter interface / implementation (Strg+I, Vorgabe implementation), Units aus den uses ausgegraut mit „schon in uses“, „Kreis über X“ als Warnung, wenn der Compiler den Kreis im interface ablehnt, sonst als Hinweis (Uses-Graph, braucht `architecture.enabled`); Enter fügt die markierten Units ohne Duplikat als ein Rückgängig-Schritt ein; mit Umschalt bzw. Befehl *IDE-Dialog Unit verwenden* der IDE-Dialog | an | Plugin (Registry `UnitSearchReplaceUseUnitDialog`) | nein | Kontrollkästchen | #786 |
| Units suchen | Umschalt+F12 und *Ansicht › Formulare* öffnen das Atlas-Fenster „Formulare suchen“ mit Filter `t:form\|frame\|dm` (Formulare, Frames, Datenmodule); Enter öffnet den Designer, Umschalt+Enter den Quelltext; mit Umschalt bzw. Befehl *IDE-Dialog Formulare* der IDE-Dialog (`unitSearch.replaceFormsDialog`) | an | Plugin (Registry `UnitSearchReplaceFormsDialog`) | nein | Kontrollkästchen | #786 |
| Units suchen | Eigenes Tastenkürzel für das Fenster (`unitSearch.key`) | keins | Plugin (Registry `UnitSearchKey`) | nein | Tastenkürzel | #777 |
| Units suchen | Pfadanzeige: relativ zur Projektgruppe, in der Mitte gekürzt oder absolut (`unitSearch.pathStyle`) | relative | Plugin (Registry `UnitSearchPathStyle`) | nein | Auswahlliste | #777 |
| Units suchen | Gruppierung: Projekt, Ordner oder flach (`unitSearch.groupBy`) | project | Plugin (Registry `UnitSearchGroupBy`) | nein | Auswahlliste | #777 |
| Units suchen | Eingeklappte Gruppen je Projektgruppe merken (`unitSearch.rememberCollapsed`) | an | Plugin (Registry `UnitSearchRememberCollapsed`) | nein | Kontrollkästchen | #777 |
| Units suchen | Chipzeile Herkunft und Art (`unitSearch.filters`) | an | Plugin (Registry `UnitSearchFilters`) | nein | Kontrollkästchen | #777 |
| Units suchen | Vorgewählte Herkunft ohne gemerkte Wahl: Projektgruppe, aktives Projekt, Suchpfad, Bibliothek (`unitSearch.defaultScope`) | group | Plugin (Registry `UnitSearchDefaultScope`) | nein | Auswahlliste | #777 |
| Units suchen | Tippsyntax `p:` und `t:` im Suchfeld (`unitSearch.filterSyntax`) | an | Plugin (Registry `UnitSearchFilterSyntax`) | nein | Kontrollkästchen | #777 |
| Units suchen | Vorschau rechts, F4 schaltet um (`unitSearch.preview`) | an | Plugin (Registry `UnitSearchPreview`) | nein | Kontrollkästchen | #777 |
| Units suchen | Formularskizze in der Vorschau (`unitSearch.preview.form`) | an | Plugin (Registry `UnitSearchPreviewForm`) | nein | Kontrollkästchen | #777 |
| Units suchen | „Verwendet von“ in der Vorschau (`unitSearch.preview.usedBy`) | an | Plugin (Registry `UnitSearchPreviewUsedBy`) | nein | Kontrollkästchen | #777 |
| Units suchen | Abschnitte der Vorschau einklappen, wenn sie nicht passen (`unitSearch.preview.autoCollapse`) | an | Plugin (Registry `UnitSearchPreviewAutoCollapse`) | nein | Kontrollkästchen | #876 |
| Units suchen | Häkchen und Mehrfachauswahl (`unitSearch.multiSelect`) | an | Plugin (Registry `UnitSearchMultiSelect`) | nein | Kontrollkästchen | #777 |
| Units suchen | Aktionsleiste (`unitSearch.actions`) | an | Plugin (Registry `UnitSearchActions`) | nein | Kontrollkästchen | #777 |
| Units suchen | Aktion „In uses aufnehmen“ (`unitSearch.actions.addUses`) | an | Plugin (Registry `UnitSearchActionsAddUses`) | nein | Kontrollkästchen | #777 |
| Willkommensseite | Atlas-Willkommensseite als andockbares Fenster „Atlas-Start“ (*Ansicht › Atlas-Start*, Atlas-Menü, *Atlas.WelcomeStart* in der Palette; der Desktop der IDE stellt es wieder her; seit #1114 keine Atlas-Bereiche mehr auf der Willkommensseite der IDE) (`welcomePage.enabled`, Schnellschalter), beim Start der IDE öffnen (`welcomePage.openOnStart`), öffnen, sobald das letzte Projekt bzw. die Projektgruppe geschlossen ist (`welcomePage.openWhenNoProject`; nicht beim Beenden der IDE), Kopf mit Symbol und Version (`welcomePage.header`), Grußzeile (`welcomePage.greeting`), Suchfeld im Kopf (`welcomePage.search`), Gruppe „Symbole“ darin (`welcomePage.search.symbols`, braucht laufenden Server), Taste für das Suchfeld (`welcomePage.search.key`, nur im Fenster „Atlas-Start“), Karte „Neu in Atlas“ (`welcomePage.whatsNew`: off = nie, afterUpdate = einmalig nach einem Update, always = immer), Bereich „Weiterarbeiten“ mit den letzten Arbeitsständen (Reiter, zuletzt bearbeitete Datei und Methode, „Fortsetzen“ öffnet Projekt und Reiter und setzt den Cursor an die letzte Änderung; *Atlas.Continue* in der Palette) (`welcomePage.continue`; aus = kein Bereich, nichts wird mitgeschrieben), höchstens so viele Arbeitsstände (`welcomePage.continue.count`, 1–20), „Neu seit deinem letzten Öffnen“ mit eingehenden Commits zu den eigenen Dateien aus dem lokalen Stand der Remote-Branches (`welcomePage.continue.incoming`), vorher abrufen (`welcomePage.continue.fetch`: fetch im Hintergrund, 5 s, ohne Rückfrage nach Zugangsdaten), Reiter „Gemerkt“ mit Notizen, Lesezeichen und Favoriten aller Projekte (`welcomePage.saved`), Bereich „Projekte“ mit Zustand je Projekt (`welcomePage.projectStatus`), höchstens so viele Projekte (`welcomePage.maxProjects`, 1–30), Branch und Änderungen frisch abfragen (`welcomePage.refreshVcs`), Bereich „Projektverlauf“ mit einer Linie je Reihe über die letzten Builds des in „Projekte“ gewählten (sonst obersten) Projekts, letzter Wert, Vorwert, Lücke für unbekannte Werte, Klick auf einen Punkt zeigt Build, Datum, Branch und Commit; Klick auf eine Projektzeile wählt sie dann, Doppelklick öffnet (`welcomePage.trends`; aus = kein Bereich, keine neuen Messpunkte, Klick öffnet wieder), gespeicherte und gezeigte Builds je Projekt (`welcomePage.trends.points`, 2–100), gezeigte Reihen (`welcomePage.trends.series`: Liste aus warnings, ruleHits, todos, duration, methodLength), Bereich „Nicht gesichert“ mit nicht Committetem, nicht Gepushtem und Stashes je Projekt (`welcomePage.unsaved`), erst ab so vielen Stunden zeigen (`welcomePage.unsaved.minAgeHours`, 0–8760), gelb ab (`welcomePage.unsaved.warnHours`, 0–8760), rot ab (`welcomePage.unsaved.alertHours`, 0–8760, nie unter warnHours), Bereich ausblenden, wenn alles gesichert ist (`welcomePage.unsaved.hideWhenClean`; sonst Zeile „Alles gesichert“), Zustandskachel „Atlas“ mit Server, Version, Index, Einrichtung und Diagnosemodus (`welcomePage.statusTile`), Kachel nur bei einer gelben oder roten Zeile (`welcomePage.statusTile.onlyProblems`), Karte „Atlas entdecken“ mit einem Tipp je Start aus `tips.json` der Installation, Bild, tatsächlichem Kürzel und „Noch nie benutzt“/„Zuletzt vor 3 Wochen“, Knöpfe „Ausprobieren“, „Nächster Tipp“, „Nicht mehr zeigen“ (`welcomePage.discover`; zuerst eingeschaltete, nie benutzte Funktionen, dann lange nicht benutzte; abgeschaltete nie), Nutzung je Befehl lokal zählen (`tips.usageTracking`; aus = Tipps der Reihe nach, es wird nichts gezählt), Knöpfe „Zählung zurücksetzen“ und „Gesperrte Tipps wieder zeigen“, Bereich „Hilfe und Rückmeldung“ mit „Atlas-Doku“ (lokale HTML-Doku `Doku\index.html` der Installation, sonst die Doku-Seite des Repositorys), „Tastenkürzel“ (Übersicht aus #520, ausgegraut mit `keys.overview` aus) und „Problem melden …“ (Dialog: Kurzbeschreibung, Häkchen für Logs, Versionen, Einstellungen ohne Pfade und letzte Diagnosedaten, Vorschau jeder Datei, „ZIP anlegen“ schreibt `Atlas-Diagnose-<Datum>.zip` und zeigt sie im Explorer, „Issue-Seite öffnen“ legt die Vorlage in die Zwischenablage und öffnet die Seite im Browser; Atlas sendet nichts) (`welcomePage.help`), Ziel für „Issue-Seite öffnen“ (`welcomePage.help.reportUrl`, nur http:// oder https://, sonst die Vorgabe), Ordner für das Diagnosepaket (`welcomePage.help.reportFolder`, leer = Desktop), Karte „<Projekt> für Atlas einrichten“ für das aktive bzw. zuletzt geöffnete Projekt mit den Schritten atlas.json anlegen (Vorlage „Bestehendes Projekt“, „Neues Projekt, streng“ oder „Altprojekt mit Baseline“ aus dem Ordner `Vorlagen` der Installation, vorher gegen das Schema geprüft und gezeigt), Baseline erzeugen (#97) und Suchpfade und Defines prüfen (fehlende Units aus uses, Defines ohne Quelle; Klick öffnet die Projektoptionen), jeder Schritt nur auf Klick, „Für dieses Projekt nicht mehr fragen“ dauerhaft, *Atlas.ProjectSetup* in der Palette fragt wieder (`welcomePage.projectSetup`, Schnellschalter; aus = keine Karte, keine Knöpfe, kein Befehl), Knöpfe „Neu mit Atlas“ (Unit, Formular, Testklasse) öffnen das Erzeugen-Menü mit den Dateivorlagen und legen die Datei im aktuellen Projekt an (`welcomePage.newFromTemplate`), Bereich „Testergebnisse“ mit einer Zeile je Projekt aus dem letzten DUnitX-Lauf in der IDE (#69: Ampel, Marke „2 fehlgeschlagen“ bzw. „alle 57 ok“, bestanden, übersprungen, Dauer, Zeit), darunter die fehlgeschlagenen Tests des gewählten Projekts mit Meldung und Datei:Zeile, Doppelklick öffnet Projekt und Test, „Fehlgeschlagene erneut ausführen“ startet genau diese Tests, „Im Debugger“ den gewählten (#585) (`welcomePage.tests`), höchstens so viele Fehlschläge (`welcomePage.tests.maxFailures`, 1–50), Ergebnisse vom Build-Server (`welcomePage.tests.ci`; Server, Job und Multibranch aus dem Abschnitt `ci` der `.atlas`, bei Multibranch der Job des aktuellen Branches; REST `…/lastCompletedBuild/api/json` und `…/testReport/api/json`; zweite Zeile „Jenkins #482 · 2 fehlgeschlagen · vor 40 Min. · main“, Server-Fehlschläge in derselben Liste mit Marke „Server“, „lokal grün, Server rot“ hervorgehoben, „Im Browser“ öffnet die Seite des Builds; abgefragt beim Anzeigen im Hintergrund mit 5 s Zeitgrenze; nicht erreichbar = letzter Stand mit „Stand vom …“, kein Dialog; aus = kein Netzzugriff, `.atlas` wird dafür nicht gelesen), Anbieter, wenn die `.atlas` keinen nennt (`welcomePage.tests.ci.provider`: jenkins), höchstens alle so viele Minuten je Job (`welcomePage.tests.ci.intervalMinutes`, 1–1440, auch nach einem Fehler und über einen Neustart hinweg), Hinweis in der Benachrichtigungszentrale, wenn ein neuer Build rot wird (`welcomePage.tests.ci.notify`, Quelle `buildServer`, mit „Im Browser“), Befehl „Zugang zum Build-Server hinterlegen …“ (*Atlas.CiLogin*, Schnellschalter; auch im Kontextmenü des Bereichs): Benutzer und API-Token für den Server aus der `.atlas` des aktiven Projekts im Anmeldespeicher von Windows (Ziel `Atlas:ci:<Server>`), das Token verdeckt eingegeben, beide Felder leer entfernt den Zugang; angemeldet wird nur über https und nur beim eingetragenen Server, Weiterleitungen nur auf denselben Rechner; Adresse, Job, Benutzer und Token kommen nie ins Protokoll, Schnellaktionen je Projekt in „Projekte“ und „Weiterarbeiten“: Knöpfe in der Zeile unter der Maus bzw. der Tastatur „Öffnen und bauen ▾“ (öffnet Projekt bzw. Gruppe wie die IDE und baut mit der zuletzt benutzten oder gewählten Konfiguration und Plattform, Release-Wächter #533 gilt), „Tests“ (baut das zugehörige DUnitX-Testprojekt und führt es aus, #69; Ergebnis auch in „Testergebnisse“), „Startprofil ▾“ (#575), „Pull“ bzw. bei SVN „Aktualisieren“ (nur vorwärts, gesperrt bei lokalen Änderungen: „Erst lokale Änderungen sichern“), „Ordner“ (Explorer) und „Konsole“; Fortschritt „baut … 12 s“ in der Zeile, Ergebnis als Marke; ohne Maus über Pfeiltasten, Enter, Alt+↓ und Kontextmenütaste (`welcomePage.quickActions`, Schnellschalter; aus = keine Knöpfe, die Tasten bleiben bei der IDE), gezeigte Knöpfe (`welcomePage.quickActions.items`: Liste aus build, tests, run, pull, folder, console), Programm für „Konsole“ im Projektordner (`welcomePage.quickActions.console`; ohne Windows-Terminal cmd.exe), Taste für „Öffnen und bauen“ (`welcomePage.quickActions.buildKey`) und für „Tests“ (`welcomePage.quickActions.testKey`), beide nur in einer Zeile mit Fokus, Bereich „Meine Issues · <Projekt>“ mit den mir zugewiesenen offenen Issues aus dem Tracker der `.atlas` des in „Projekte“ gewählten, sonst des aktiven Projekts (Abschnitt `tracker`; GitHub: Vorgabe-Abfrage `assignee:@me state:open`, Kennung `#123`, Labels und verknüpfter Pull Request mit CI-Ampel; YouTrack: Vorgabe `for: me #Unresolved`, Kennung `ATL-123`, Zustand, Priorität und Sprint), Klick auf die Kennung öffnet das Issue im Browser, abgefragt beim Anzeigen höchstens alle 10 Minuten im Hintergrund mit 5 s Zeitgrenze, nicht erreichbar = letzter Stand mit „Stand vom …“, kein Dialog; „Beginnen“ legt unter Git den Branch nach Muster von der Basis an und checkt ihn aus (vorhandener Branch: nur auschecken; bei lokalen Änderungen fragt Atlas vorher), unter SVN `svn copy ^/trunk ^/branches/<Name>` und `svn switch`, und öffnet danach das Projekt; das aktuelle Issue steht im Atlas-Statusfeld (Zeile `atlas.issue`, Klick beendet es nach Rückfrage) (`welcomePage.issues`, Schnellschalter; aus = kein Bereich, kein Netzzugriff); Tracker, Abfrage, Muster und Zugang stehen seit #1280 auf der Seite Issue-Tracker („Tracker-Einstellungen …“), frei anordnen mit „Seite anpassen“ (Leiste unter dem Kopf, Kontextmenü der Bereiche, *Atlas.WelcomeCustomize* in der Palette): Griff zum Ziehen und Strg+Pfeiltasten, Breite und Auge je Bereich, „Bereich hinzufügen“, „Zurücksetzen“, Leiste „Ausgeblendet“, benannte Layouts mit Umschalter im Kopf; Ausblenden schaltet die Einstellung des Bereichs (`welcomePage.customLayout`, Schnellschalter; aus = kein Bearbeitungsmodus, festes Atlas-Layout), Spalten der Seite (`welcomePage.columns`, 1–3), aktives Layout (`welcomePage.activeLayout`, leer = Standard), Layouts mit Plätzen, Breiten, Spalten und Sichtbarkeit (`welcomePage.layouts`, JSON, leer = ein Layout „Standard“ wie das Atlas-Layout); Bereich „Sprint“ (`welcomePage.sprint`, #1277): aktueller Sprint des Boards aus #1272 (YouTrack-Agile-Board bzw. GitHub-Projekt mit Iterationen) mit Name, Zeitraum und „noch n Tage“ (Arbeitstage laut YouTrack, sonst Montag bis Freitag), „meine offen“, „meine erledigt“ und „Team übrig“ (Punkte des Schätzfeldes, sonst Anzahl) und Burndown; Klick auf „meine offen“/„meine erledigt“ filtert „Meine Issues“ („Gefiltert: … · alle zeigen“), „Team übrig“ und Diagramm öffnen das Board, der Titel das Board im Browser; ohne Tracker „Kein Board für dieses Projekt – zuordnen …“; lädt beim Anzeigen und mit „Meine Issues“ höchstens alle 10 Minuten, letzter Stand in `%LOCALAPPDATA%\Atlas\issues\<Tracker>-sprint.json` mit „Stand vom …“ ohne Netz | an, aus, an, an, an, an, an, Strg+E, afterUpdate, an, 5, an, aus, an, an, 8, an, an, 30, alle fünf, an, 0, 24, 72, aus, an, aus, an, an, an, Issue-Seite des Atlas-Repositorys, Desktop, an, an, an, 5, aus, jenkins, 10, an, an, an, alle sechs, wt.exe, Strg+B, Strg+T, aus, an, 2, Standard, leer, an | Plugin (Registry `WelcomePage`, `WelcomePageOpenOnStart`, `WelcomePageOpenWhenNoProject`, `WelcomePageHeader`, `WelcomePageGreeting`, `WelcomePageSearch`, `WelcomePageSearchSymbols`, `WelcomePageSearchKey`, `WelcomePageWhatsNew`, `WelcomePageContinue`, `WelcomePageContinueCount`, `WelcomePageContinueIncoming`, `WelcomePageContinueFetch`, `WelcomePageSaved`, `WelcomePageProjectStatus`, `WelcomePageMaxProjects`, `WelcomePageRefreshVcs`, `WelcomePageTrends`, `WelcomePageTrendsPoints`, `WelcomePageTrendsSeries`, `WelcomePageUnsaved`, `WelcomePageUnsavedMinAgeHours`, `WelcomePageUnsavedWarnHours`, `WelcomePageUnsavedAlertHours`, `WelcomePageUnsavedHideWhenClean`, `WelcomePageStatusTile`, `WelcomePageStatusTileOnlyProblems`, `WelcomePageDiscover`, `TipsUsageTracking`, `WelcomePageHelp`, `WelcomePageHelpReportUrl`, `WelcomePageHelpReportFolder`, `WelcomePageProjectSetup`, `WelcomePageNewFromTemplate`, `WelcomePageTests`, `WelcomePageTestsMaxFailures`, `WelcomePageTestsCi`, `WelcomePageTestsCiProvider`, `WelcomePageTestsCiIntervalMinutes`, `WelcomePageTestsCiNotify`, `CiLogin`, `WelcomePageQuickActions`, `WelcomePageQuickActionsItems`, `WelcomePageQuickActionsConsole`, `WelcomePageQuickActionsBuildKey`, `WelcomePageQuickActionsTestKey`, `WelcomePageIssues`, `WelcomePageSprint`, `WelcomePageCustomLayout`, `WelcomePageColumns`, `WelcomePageActiveLayout`, `WelcomePageLayouts`; gesehene Version in `WhatsNewSeen`); Zählung je Befehl (nur Kennung, Zähler, Datum, nichts wird versendet) in `%LOCALAPPDATA%\Atlas\usage.json`, gesperrte und zuletzt gezeigter Tipp im Abschnitt `discover` von `%LOCALAPPDATA%\Atlas\shortcut-tips.json`; eine Sicherung `%LOCALAPPDATA%\Atlas\welcomepage-layout-backup.json` früherer Fassungen schreibt Atlas beim Start einmal zurück und löscht sie, sonst nimmt es seine Bereiche aus dem Layout der IDE (Marke `welcomepage-layout-pending`, bis die IDE den Stand übernommen hat), Projektzustand (auch Abschnitte `unsaved`, `continue`, `trends`, `setup`, `tests`, `ci` und `issues`, die beiden letzten mit letztem Stand, Zeit des letzten Versuchs und Fehlerart, ohne Zugang; `issues` auch mit aktuellem Issue und Zustimmung zum Git-Hook) in `%LOCALAPPDATA%\Atlas\projects\<Schlüssel>.json`, letzter Index-Stand der Kachel („Stand vom …“) in `%LOCALAPPDATA%\Atlas\index-state.json` | nein | Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Tastenfeld, Auswahl, Kontrollkästchen, Zahl (1–20), Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Zahl (1–30), Kontrollkästchen, Kontrollkästchen, Zahl (2–100), fünf Kontrollkästchen, Kontrollkästchen, Zahl (0–8760), Zahl (0–8760), Zahl (0–8760), Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Knopf, Knopf, Kontrollkästchen, Textfeld, Textfeld mit „…“, Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Zahl (1–50), Kontrollkästchen, Auswahl, Zahl (1–1440), Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, sechs Kontrollkästchen, Textfeld, Tastenfeld, Tastenfeld, Kontrollkästchen, Kontrollkästchen, Zahl (1–3), Auswahl mit „Neu …“, „Umbenennen …“ und „Löschen“, Bearbeitungsmodus der Seite, Kontrollkästchen | #753, #1114, #760, #756, #755, #592, #758, #762, #754, #757, #766, #759, #763, #764, #765, #767, #1277 |
| Issue-Tracker | Anbieter (`issues.tracker`: leer = aus der `.atlas`, github, youtrack), Abfrage (`issues.query`, leer = Vorgabe des Anbieters), „Beginnen“ (`issues.start`: branch, remember = nur Kennung merken), Branch-Muster (`issues.branchPattern` mit `{kennung}`, `{nummer}` und `{kurztitel}` = erste drei Wörter, klein, Umlaute ersetzt, mit Bindestrichen; leer = `feature/{kennung}-{kurztitel}`, unter SVN `{kennung}-{kurztitel}`), Basis (`issues.branchBase`, leer = main, sonst master; SVN trunk), Präfix für Commit-Nachrichten, solange ein Issue aktuell ist (`issues.commitPattern`, leer = aus; im Commit-Dialog der IDE und nach einmaliger Zustimmung je Projekt über den Git-Hook `prepare-commit-msg`, der den Präfix aus `.git/atlas-commit-prefix` liest; einen fremden Hook ändert Atlas nie), Befehl „Zugang zum Issue-Tracker hinterlegen …“ (`issues.login`, *Atlas.TrackerLogin*, Schnellschalter; auch im Kontextmenü des Bereichs): Token für den Tracker aus der `.atlas` des aktiven Projekts im Anmeldespeicher von Windows (Ziel `Atlas:tracker:<Server>`), verdeckt eingegeben, leer entfernt es; gesendet als „Authorization: Bearer“ nur über https an den Tracker; Adresse, Projekt, Kennungen, Titel und Token kommen nie ins Protokoll; Tabelle „Verbindungen“ (`issues.connections`, #1260): mehrere persönliche Tracker je Name, Anbieter und https-Adresse in settings.json, Token je Server im Anmeldespeicher mit Zustand (fehlt, gespeichert, geprüft, abgelehnt, nicht erreichbar) und „Prüfen“ gegen den angemeldeten Benutzer; Verbindungen aus der `.atlas` erscheinen schreibgeschützt; Tabelle „Projekte“ (`issues.projects`, #1261): Delphi-Projekte ohne `tracker` in der `.atlas` persönlich einem Tracker-Projekt zuordnen („Gilt für“ = `.dproj`, `.groupproj` oder Ordner, Verbindung, Tracker-Projekt); es gilt die `.atlas`, sonst die Zeile für genau diese `.dproj`, sonst die für die geöffnete `.groupproj`, sonst der längste passende Ordner (Pfade ohne Groß-/Kleinschreibung, auch UNC); „Aktuelles Projekt hinzufügen“, „Hinzufügen …“, Entfernen; ohne Zuordnung bietet „Meine Issues“ „zuordnen …“ an; Einstellungen unter `issues.*` (bis #1280 `welcomePage.issues.*`; gespeicherte Werte übernimmt Atlas beim ersten Start, eine Zeile je Übernahme im Protokoll); Issue-Vorschau (`issues.preview`, #1264, Schnellschalter): Klick auf ein Issue in „Meine Issues“ bzw. Befehl *Atlas.IssueShow* zeigt es im Dockfenster „Atlas-Issue“ mit Beschreibung (Markdown wie im Hover), Feldern, Anhängen, verknüpften Issues und Verlauf, Strg+Klick öffnet den Browser; Bilder und Anhänge nur vom Server des Tokens, Zwischenspeicher 7 Tage in `%LOCALAPPDATA%\Atlas\issues`; Kommentare laden (`issues.preview.comments`); Checklisten in der Vorschau (`issues.preview.checklists`, #1273): Aufgabenlisten der Beschreibung (`- [ ]`, `* [x]`, `1. [ ]`, auch eingerückt, nicht in Codeblöcken) als Häkchen mit „3/5“ im Kopf; Abhaken lädt die aktuelle Beschreibung, prüft die Zeile (Text und Position), ändert nur `[ ]`/`[x]` und schreibt zurück (YouTrack `POST /api/issues/<Kennung>`, GitHub `PATCH …/issues/<n>`), wurde sie inzwischen geändert, schreibt Atlas nichts und lädt neu; „Punkt hinzufügen …“ hängt `- [ ] Text` an; ohne Schreibrecht nur lesend, Checklisten in Kommentaren nur lesend; aus = Liste als Text; Fortschritt des aktuellen Issues im Statusfeld (`issues.checklistStatus`, Zeile `atlas.issue.checklist` „ATL-131 · 3/5“, Klick öffnet die Vorschau an der Liste, ohne Checkliste keine Zeile); Verknüpfungen als Baum (`issues.preview.links`, #1279): hängt ab von, blockiert, Unteraufgaben mit Fortschritt (2/3), übergeordnet, Duplikate, „bezieht sich auf“ und Erwähnungen eingeklappt, je Zeile Symbol (offen, erledigt, blockiert), Kennung, Titel und Zustand, dazu „Unteraufgabe anlegen …“ und „Verknüpfen …“ (YouTrack und GitHub; aus: flache Liste); Warnung beim „Beginnen“, solange ein „hängt ab von“-Issue offen ist (`issues.warnBlocked`); Tracker beim Beginnen und Beenden nachführen (`issues.syncState`, #1266, Schnellschalter; aus = „Beginnen“ und „Beenden“ ändern im Tracker nichts): „Beginnen“ setzt nach dem Branch den Zustand (`issues.startState`, leer = nicht ändern; GitHub: Label), weist mir zu (`issues.assignOnStart`) und kommentiert (`issues.startComment`, leer = kein Kommentar), Ergebnis als Zeile in der Meldungsansicht, ein Fehler lässt den Branch stehen; „Beenden“ (Statusfeld, Kontextmenü, Knopf der Vorschau) zeigt den Dialog „ATL-123 beenden“ mit Zielzustand aus `issues.endStates` und „Zustand nicht ändern“, Kommentar aus `issues.endComment` mit `{branch}`, `{commits}`, `{pr}`, `{time}`, `{kennung}` (`\n` = neue Zeile) und „Zuständigkeit übergeben an …“; ohne „Senden“ wird nichts geschrieben, Fehler (403, 400) zeigt der Dialog mit dem Text des Trackers; in der Vorschau „Kommentar schreiben …“ (Markdown, Strg+Enter sendet); YouTrack über `POST /api/commands` mit Zustandsfeld (`issues.stateField`) und Benutzerfeld (`issues.assigneeField`), GitHub über Kommentar und PATCH (Labels, Zuständige, „Erledigt“ schließt); Zustandsfeld, Benutzerfeld, Zustand beim Beginnen und Zielzustände je Verbindung in `issues.connections` (`stateField`, `assigneeField`, `startState`, `endStates`), sonst die globalen Werte; Klapplisten „Werte vom Tracker laden“; Board (`issues.board`, #1272, *Atlas.Board*, Ansicht › Atlas › Board): Dockfenster „Atlas-Board“ mit den Spalten des Agile-Boards (YouTrack, Board und Sprint wählbar, „aktueller Sprint“ vorgewählt) bzw. des GitHub-Projekts (Status-Feld, Iterationen als Sprints; ohne Projekt oder ohne Berechtigung `read:project` Offen/Geschlossen mit Hinweis), Karten mit Kennung, Titel, Kürzel des Zuständigen, Prioritätsstreifen, Checklisten-Fortschritt und Schloss; „Nur meine“/„Alle“ (`issues.board.onlyMine` = Filter beim Öffnen), Suche, Aktualisieren; Ziehen in eine andere Spalte fragt nach (`issues.board.confirmMove`, „Nicht mehr fragen“ schaltet ab) mit optionalem Kommentar und schreibt über dieselben Wege wie „Beenden“ (YouTrack `POST /api/commands`, GitHub `updateProjectV2ItemFieldValue` bzw. Schließen/Öffnen), bei Fehler springt die Karte zurück; Doppelklick öffnet die Vorschau, Kontextmenü Beginnen, Im Browser öffnen, Mir zuweisen; das aktuelle Issue ist hervorgehoben; schmal (unter 360 Pixel) als Liste nach Spalten gruppiert; letzter Stand in `%LOCALAPPDATA%\Atlas\issues\<Tracker>-board.json`, offline mit Hinweis; Sprint-Kachel (#1277): Burndown mit Ist-Linie, gestrichelter Ideallinie, Marke „heute“ und Tooltip je Tag (`issues.sprint.burndown`), Vergleich mit dem vorherigen Sprint (blasse Linie auf Sprinttage normiert, „erledigt 5 · Vorsprint 4 am selben Tag ▲1“) und Velocity der letzten drei Sprints als Balken (`issues.sprint.compare`; aus = kein früherer Sprint wird gefragt; abgeschlossene Sprints einmal gefragt und als `<Tracker>-sprint-<Board>-<Sprint>.json` zwischengespeichert) | leer, leer, branch, leer, leer, `{kennung} `, an, keine, keine, an, an, an, an, an, an, an, State, Assignee, leer, aus, leer, leer, `Erledigt in {branch}.\n{commits}`, an, an, an, an, an | Plugin (Registry `IssuesTracker`, `IssuesQuery`, `IssuesStart`, `IssuesBranchPattern`, `IssuesBranchBase`, `IssuesCommitPattern`, `TrackerLogin`, `IssuesPreview`, `IssuesPreviewComments`, `IssuesPreviewLinks`, `IssuesWarnBlocked`, `IssuesPreviewChecklists`, `IssuesChecklistStatus`, `IssuesSyncState`, `IssuesStateField`, `IssuesAssigneeField`, `IssuesStartState`, `IssuesAssignOnStart`, `IssuesStartComment`, `IssuesEndStates`, `IssuesEndComment`, `IssuesBoard`, `IssuesBoardConfirmMove`, `IssuesBoardOnlyMine`, `IssuesSprintBurndown`, `IssuesSprintCompare`; `issues.connections` und `issues.projects` in settings.json) | nein | Auswahl, Textfeld, Auswahl, Textfeld, Textfeld, Textfeld, Kontrollkästchen, Tabelle, Tabelle, Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Klappliste, Klappliste, Klappliste, Kontrollkästchen, Textfeld, Textfeld, Textfeld, Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Kontrollkästchen, Kontrollkästchen | #765, #1280, #1260, #1261, #1264, #1273, #1279, #1266, #1272, #1277 |

## Bereiche für Export, Import und Zurücksetzen

*Tools › Optionen › Atlas*, die Befehlspalette und `AtlasSetup.exe` exportieren, importieren und setzen Einstellungen je Bereich zurück (#723, abschaltbar mit `settings.exportImport`). Den Bereich bestimmt `x-area` im Schema: je Plugin-Einstellung im Katalog `schemas/atlas-plugin.schema.json`, je globalem Schlüssel in `atlas.schema.json`. Neue Einstellungen gehören damit ohne weitere Liste dazu. Die Exportdatei `atlas-settings.json` enthält nur geänderte Werte, keine Zugangsdaten (`settings.exportSecrets`: auslassen oder Platzhalter) und keine Pfade mit Benutzernamen (Benutzerordner werden zu `$(APPDATA)`, `$(LOCALAPPDATA)`, `$(USERPROFILE)`). Projekt- und Teamwerte (`atlas.json`, `.atlas`) werden weder exportiert noch beim Import überschrieben.

| Bereich | Schlüssel |
|---|---|
| Editor (`editor`) | `editor.dimUnusedUses`, `editor.recursionMarkers`, `editor.recursionMarkers.depth`, `problems.enabled`, `inlayHints.parameterNames`, `inlayHints.inferredTypes`, `inlayHints.includeDefines`, `inlayHints.controlChars`, `refactoring.methodKindMarker`, `editor.blockEndLabels`, `editor.blockEndLabels.minLines`, `notes.enabled`, `codeLens.metrics`, `metrics`, `codeLens.tests`, `todos.list`, `baseline.update`, `metrics.report`, `dfmRules.apply`, `editor.hoverTooltip`, `editor.reloadExternal`, `editor.openForEdits`, `search.replaceIdeSearch`, `search.resultsInMessages`, `search.replace`, `search.regex`, `search.history`, `search.multiFile`, `problems.list`, `problems.statusCounter`, `hover.problemActions`, `editor.inlineDiagnostics`, `editor.continueComments`, `editor.continueComments.lineComments`, `editor.continueComments.lists`, `editor.completeStatement`, `editor.completeStatement.beginEnd`, `editor.completeStatement.tryKind`, `editor.completeStatement.methodBody`, `editor.format`, `editor.continuePattern`, `editor.continuePattern.minLines`, `editor.multiCursor`, `editor.linkedEditing`, `editor.smartPaste`, `editor.multiCursorModifier`, `editor.continueComments.blockPrefix`, `editor.wrapSelection`, `editor.wrapSelection.chars`, `codeLens.testUnit`, `hints.xmlDocExpand`, `hints.xmlDocMaxLines`, `undo.multiFile`, `undo.multiFile.depth`, `undo.multiFile.persist`, `undo.multiFile.maxSizeMb`, `undo.multiFile.onConflict`, `undo.multiFile.newFiles`, `unitSearch.enabled`, `unitSearch.replaceIdeDialog`, `unitSearch.replaceUseUnitDialog`, `unitSearch.replaceFormsDialog`, `unitSearch.rememberCollapsed`, `unitSearch.filters`, `unitSearch.filterSyntax`, `unitSearch.preview`, `unitSearch.preview.form`, `unitSearch.preview.usedBy`, `unitSearch.preview.autoCollapse`, `unitSearch.multiSelect`, `unitSearch.actions`, `unitSearch.actions.addUses`, `unitSearch.pathStyle`, `unitSearch.groupBy`, `unitSearch.defaultScope`, `quickOpen.enabled`, `quickOpen.librarySources`, `navHistory.enabled`, `peek.enabled`, `references.inferred`, `references.textMatches`, `callHierarchy.diagram`, `navigation.impact`, `navigation.impactDepth`, `peek.heightLines`, `peek.showImplementation`, `navigation.dataFlow`, `navigation.dataFlow.maxDepth`, `navigation.dataFlow.excludeTests`, `outline.enabled`, `navigation.symbolPath`, `outline.alphabetical`, `outline.followCursor`, `outline.conditions`, `editor.breadcrumbs`, `editor.breadcrumbsShowUnit`, `editor.breadcrumbsIdeColors`, `editor.breadcrumbsHideIdeToolbar`, `editor.toolbar`, `editor.toolbar.position`, `editor.toolbar.items`, `editor.toolbar.returnButton`, `editor.toolbar.labels`, `editor.statusBar`, `editor.statusBar.items`, `editor.stickyScroll`, `editor.stickyScrollMaxLines`, `editor.minimap`, `editor.minimap.render`, `editor.minimap.width`, `editor.minimap.scale`, `editor.minimap.maxColumn`, `editor.minimap.side`, `editor.minimap.showSlider`, `editor.minimap.sectionHeaders`, `editor.minimap.highlightMethod`, `editor.minimap.markers`, `editor.minimap.clickJumps`, `editor.gitGutter`, `editor.gitBlame`, `editor.gutterColumn`, `editor.gutterColumn.problems`, `editor.gutterColumn.codeActions`, `editor.gutterColumn.overrides`, `hints.expressionType`, `hints.expressionType.conversions`, `hints.expressionType.constValue`, `editor.methodPlacement`, `editor.overviewRuler`, `editor.overviewRulerKinds`, `inlayHints.endMarkers`, `inlayHints.endMarkerMinLines`, `hints.xmlDocFull`, `hints.publishedMembers`, `hints.rationale`, `hints.rationaleMarkers`, `hints.adrFolder`, `directives.completion`, `directives.hover` |
| Vervollständigung (`completion`) | `completion.enabled`, `completion.filterChips`, `completion.preview`, `completion.groupInherited`, `completion.variantBranch`, `completion.listMode`, `completion.listMode.scope`, `completion.learning`, `completion.favorites`, `completion.visibleRows`, `completion.panelCollapsed`, `completion.selectionMarker`, `completion.autoParentheses`, `completion.fixCase`, `completion.commitCharacters`, `completion.autoUses`, `completion.parameterHints`, `completion.formatPlaceholders`, `completion.openDelayMs`, `completion.matching`, `completion.offerTryFinally`, `completion.keywords`, `completion.genericConstraints`, `completion.resourceStrings`, `completion.typeConversion`, `completion.assignAllFields`, `completion.usesDetails`, `completion.inheritedCall`, `completion.attributes`, `completion.anonymousMethods`, `completion.withOrigin`, `completion.exceptionClasses`, `completion.syntaxNotice`, `completion.sameNameVariants`, `completion.sameNameInsert`, `completion.showFmxUnits`, `completion.nameSuggestions` |
| Hervorhebung (`highlighting`) | `highlight.pairColors`, `highlight.pairGuides`, `highlight.pairOwners`, `highlight.inactiveDim`, `highlight.pairGuideWidth`, `highlight.pairGuideOpacity`, `highlight.pairColorsLight`, `highlight.pairColorsDark`, `highlight.selectionMatches`, `highlight.selectionMatches.minLength`, `highlight.selectionMatches.caseSensitive`, `highlight.selectionMatches.wholeWord`, `highlight.selectionMatches.navigateF3`, `highlight.selectionMatches.maxMatches`, `editor.exitPoints`, `editor.exitPoints.exceptions`, `editor.exitPoints.loops`, `editor.exitPoints.badge`, `highlight.reassigned`, `highlight.reassigned.targets`, `highlight.reassigned.style`, `highlight.reassigned.color`, `highlight.blockPairs`, `highlight.directives`, `highlight.exitPoints`, `highlight.exitKeywords` |
| Tastenkürzel (`keys`) | `keys.palette`, `keys.check`, `keys.palettePriority`, `keys.checkPriority`, `keys.completion`, `keys.signature`, `keys.completionPriority`, `keys.signaturePriority`, `bookmarks.key`, `bookmarks.quick.keyPriority`, `bookmarks.quick.setKey`, `bookmarks.quick.setKeyPriority`, `bookmarks.quick.jumpKey`, `bookmarks.quick.jumpKeyPriority`, `keys.nextBookmark`, `keys.previousBookmark`, `keys.hideElement`, `keys.nextProblem`, `keys.previousProblem`, `keys.searchReplace`, `keys.search`, `keys.searchNext`, `keys.searchPrevious`, `keys.searchInMethod`, `keys.problemsWindow`, `keys.gotoInterface`, `keys.gotoImplementation`, `keys.codeActions`, `keys.expandSelection`, `keys.shrinkSelection`, `keys.implementations`, `keys.typeDefinition`, `keys.methodToggleUp`, `keys.methodToggleDown`, `keys.jumpToMatch`, `keys.jumpToMatchShortcut`, `keys.jumpToMatchSelect`, `keys.moveLines`, `keys.moveLinesUp`, `keys.moveLinesDown`, `keys.duplicateLinesUp`, `keys.duplicateLinesDown`, `keys.toggleBlockComment`, `keys.toggleBlockComment.key`, `keys.toggleBlockComment.style`, `keys.toggleBlockComment.fallback`, `keys.toggleBlockComment.ownLines`, `keys.toggleBlockComment.withoutSelection`, `keys.newLineAround`, `keys.newLineAround.belowKey`, `keys.newLineAround.aboveKey`, `keys.newLineAround.statementAware`, `keys.unwrap`, `keys.unwrap.key`, `keys.safeDelete`, `keys.safeDelete.key`, `keys.completeStatement`, `keys.format`, `keys.multiCursor.next`, `keys.multiCursor.skip`, `keys.multiCursor.lineEnds`, `keys.multiCursor.above`, `keys.multiCursor.below`, `keys.testUnit`, `keys.editorPriority`, `keys.generateMenu.key`, `keys.quickToggles`, `keys.quickTogglesPriority`, `keys.diagnosticMode`, `keys.diagnosticModePriority`, `keys.overview`, `keys.startupCheck`, `keys.undoChange`, `keys.redoChange`, `unitSearch.key`, `keys.quickOpen`, `keys.navBack`, `keys.navForward`, `keys.lastEdit`, `keys.peekDefinition`, `keys.peekReferences`, `keys.breadcrumbs`, `keys.expressionType`, `keys.nextChange`, `keys.previousChange`, `welcomePage.search.key`, `welcomePage.quickActions.buildKey`, `welcomePage.quickActions.testKey`, `notifications.key` |
| Code-Aktionen (`codeActions`) | `keys.generateMenu`, `codeActions.methodToggle`, `slashCommands.enabled`, `keys.generateMenu.groups`, `keys.generateMenu.hidden`, `keys.generateMenu.recentFirst`, `keys.generateMenu.showCommandNames`, `usesCommand`, `completeBlocks.docComment`, `slashCommands.disabled`, `slashCommands.headerTemplate`, `slashCommands.logCall`, `slashCommands.componentPalette`, `slashCommands.todoOwner`, `slashCommands.todoCategory`, `slashCommands.sortUsesRemoveUnused`, `slashCommands.enumHelper`, `slashCommands.setHelper` |
| Prüfregeln (`rules`) | `problems.window`, `problems.window.scope`, `problems.window.groupBy`, `problems.window.columns`, `problems.window.compiler`, `problems.window.followCursor`, `problems.window.openFirst`, `problems.window.closedUnits`, `problems.window.showCleanActive`, `problems.compilerMerge`, `problems.showCompilerCode`, `problems.live`, `rules` |
| Build (`build`) | `build.checkOnSave`, `compiler.mcpBuild`, `build.onOpen`, `tests.run`, `tests.afterBuild`, `tests.buildFirst`, `build.releaseGuard`, `build.zeroHints`, `build.showInterfaceCost`, `tasks.enabled`, `tasks.problemsFromOutput`, `tasks.beforeBuild`, `tasks.saveBeforeRun`, `tasks.runChecksParallel`, `tasks.onlyFindings`, `build.summary`, `build.warningsAsErrors`, `build.compilerSwitches`, `build.showSwitchesInStatusBar`, `build.checkOnSaveDelayMs`, `build.checkOnSaveMaxMs`, `build.onOpenKind`, `build.onOpenScope`, `build.onOpenDelayMs`, `build.onOpenExclude`, `compiler.onSave`, `build.gate`, `build.gateTimeoutMs`, `build.releaseConfigs`, `build.releaseChecks`, `compiler.backend`, `compiler.ideCommand`, `mcp.disabledTools`, `tasks` |
| Debug (`debug`) | `startProfiles.enabled`, `startProfiles.statusField`, `tests.debug`, `debug.testBreakAtStart`, `debug.hoverValues`, `debug.explainUnavailable`, `debug.completionInDialogs`, `debug.evaluateWindow`, `debug.evaluateWindow.replaceCtrlF7`, `debug.explainAccessViolation`, `debug.explainAccessViolation.allowCalls`, `debug.exceptionHistory`, `debug.justMyCode`, `debug.exceptionBanner`, `debug.exceptionBanner.ignoreAtLocation`, `debug.inlineValues`, `debug.inlineValuesPerLine`, `debug.ownCodeFolders`, `debug.visualizers`, `debug.visualizers.types`, `debug.visualizers.nameFields`, `debug.visualizers.maxLength`, `debug.visualizers.timeoutMs`, `debug.visualizers.maxImagePixels`, `debug.visualizers.evaluation`, `debug.displayRules`, `debug.displayRules.allowCalls`, `debug.stepIntoTarget`, `debug.stepFilters`, `debug.stepFilters.kinds`, `debug.stepFilters.patterns`, `debug.stepIntoTarget.key`, `debug.breakOnNextEvent`, `debug.breakOnNextEvent.excluded` |
| Vorlagen/Snippets (`snippets`) | `snippets.enabled`, `snippets.importIdeTemplates`, `completion.postfixTemplates` |
| Lesezeichen (`bookmarks`) | `bookmarks.named`, `bookmarks.shared`, `bookmarks.quick`, `bookmarks.quick.gutter`, `bookmarks.quick.gutterClick`, `bookmarks.quick.numberedKeys`, `bookmarks.quick.key`, `bookmarks.quick.chordWait`, `bookmarks.quick.scope`, `bookmarks.quick.importIde` |
| Willkommensseite (`welcome`) | `welcomePage.enabled`, `welcomePage.projectSetup`, `welcomePage.tests.ci.login`, `welcomePage.quickActions`, `welcomePage.openOnStart`, `welcomePage.openWhenNoProject`, `welcomePage.header`, `welcomePage.greeting`, `welcomePage.search`, `welcomePage.search.symbols`, `welcomePage.whatsNew`, `welcomePage.projectStatus`, `welcomePage.maxProjects`, `welcomePage.refreshVcs`, `welcomePage.unsaved`, `welcomePage.unsaved.minAgeHours`, `welcomePage.unsaved.warnHours`, `welcomePage.unsaved.alertHours`, `welcomePage.unsaved.hideWhenClean`, `welcomePage.statusTile`, `welcomePage.statusTile.onlyProblems`, `welcomePage.discover`, `tips.usageTracking`, `welcomePage.help`, `welcomePage.help.reportUrl`, `welcomePage.help.reportFolder`, `welcomePage.newFromTemplate`, `welcomePage.continue`, `welcomePage.continue.count`, `welcomePage.continue.incoming`, `welcomePage.continue.fetch`, `welcomePage.saved`, `welcomePage.trends`, `welcomePage.trends.points`, `welcomePage.trends.series`, `welcomePage.tests`, `welcomePage.tests.maxFailures`, `welcomePage.tests.ci`, `welcomePage.tests.ci.provider`, `welcomePage.tests.ci.intervalMinutes`, `welcomePage.tests.ci.notify`, `welcomePage.quickActions.items`, `welcomePage.quickActions.console`, `welcomePage.issues`, `welcomePage.sprint`, `welcomePage.customLayout`, `welcomePage.columns`, `welcomePage.layouts`, `welcomePage.activeLayout` |
| Issue-Tracker (`issues`) | `issues.tracker`, `issues.query`, `issues.start`, `issues.branchPattern`, `issues.branchBase`, `issues.commitPattern`, `issues.login`, `issues.connections`, `issues.preview`, `issues.preview.comments`, `issues.syncState`, `issues.stateField`, `issues.assigneeField`, `issues.startState`, `issues.assignOnStart`, `issues.startComment`, `issues.endStates`, `issues.endComment`, `issues.projects`, `issues.preview.links`, `issues.warnBlocked`, `issues.preview.checklists`, `issues.checklistStatus`, `issues.board`, `issues.board.confirmMove`, `issues.board.onlyMine`, `issues.sprint.burndown`, `issues.sprint.compare` |
| Allgemein (`general`) | `diagnosticMode.enabled`, `diagnostics.processes`, `architecture.enabled`, `architecture.scope`, `architecture.includeLibraryUnits`, `architecture.centralUnits`, `experimental.enabled`, `teamFile.enabled`, `settings.exportImport`, `shortcutTips.enabled`, `notifications.enabled`, `statusField.showSummary`, `robustness.hangThresholdMs`, `robustness.providerTimeLimitMs`, `robustness.hangHint`, `index.projectGroup`, `index.searchPaths`, `index.libraryPaths`, `index.usages`, `memoryBudgetMb`, `statusField.enabled`, `statusField.hidden`, `statusField.openToggles`, `statusField.indexProgress`, `ui.setupChecklist`, `shortcutTips.scope`, `safeMode.askAfterCrash`, `safeMode.autoAfterRepeatedCrash`, `safeMode.startupKey`, `safeMode.startupTimeoutMs`, `safeMode.keepSettingsHistory`, `updates.check`, `diagnostics.bugReport.anonymize`, `notifications.sources`, `notifications.maxEntries`, `settings.markModified`, `settings.backupBeforeImport`, `settings.exportSecrets`, `language`, `vcs.provider`, `index.removeOrphans`, `index.cacheMaxAgeDays`, `index.cacheMaxMb`, `requestTimeoutMs`, `diagnostics.log`, `diagnostics.logDays`, `diagnostics.logMapFile`, `logLevel`, `logFile`, `traceFile` |
| nicht exportiert (Zustand, nur dieser Rechner) | `ui.architectureWindowPlaced`, `ui.unitRelationsWindowPlaced`, `completion.listWidth`, `completion.panelWidth`, `server.path`, `ui.setupChecklistSeen`, `editor.minimap.noticeShown`, `welcomePage.whatsNewSeen`, `delphiVersion` |

## Experimentelle Funktionen

Riskante oder unreife Funktionen kommen als **experimentell** (#834): Sie haben einen eigenen Schalter, sind auf der Optionsseite und im Schnellschalter (#604) mit „Experimentell“ gekennzeichnet und nach der Installation aus. Der Hauptschalter `experimental.enabled` (*Tools › Optionen › Atlas › Allgemein*, Schnellschalter „Experimentelle Funktionen erlauben“, Vorgabe aus) gibt sie frei: Ist er aus, wirkt keine experimentelle Funktion, auch wenn ihr Schalter an ist; die Schalter behalten ihren Wert. Das Profil „Alles an“ (#723) schaltet sie nicht ein, dafür gibt es „Alles an, auch experimentell“. Statusfeld (Tooltip), Fehlerbericht und Diagnoselog nennen die wirksamen experimentellen Schalter (nur Schlüssel). Wird eine Funktion stabil, fällt `x-experimental` weg; ein gespeicherter Wert bleibt.

| Schlüssel | Ort | Seite | Herkunft |
|---|---|---|---|
| `editor.multiCursor` | Plugin (Registry `MultiCursor`) | Editor | #589 |
| `editor.linkedEditing` | Plugin (Registry `LinkedEditing`) | Editor | #658 |
| `editor.smartPaste` | Plugin (Registry `SmartPaste`) | Editor | #515 |
| `editor.stickyScroll` | Plugin (Registry `StickyScroll`) | Editor | #506 |
| `editor.minimap` | Plugin (Registry `Minimap`) | Editor | #873 |
| `completion.typeConversion` | global (settings.json) | Vervollständigung | #490 |
| `completion.assignAllFields` | global (settings.json) | Vervollständigung | #491 |
| `refactoring.inline` | Projekt (atlas.json) | Vervollständigung | #103 |
| `refactoring.moveClass` | Projekt (atlas.json) | Vervollständigung | #103 |
| `refactoring.unitRenameFollowUp` | Projekt (atlas.json) | Vervollständigung | #512 |

## Optionsseite: Unterpunkte und Hauptschalter

*Tools › Optionen › Atlas* zeigt links einen Baum (#890): oben die Bereiche, darunter die Unterpunkte je Funktion. Der Hauptknoten eines Bereichs trägt dessen allgemeine Optionen und eine Übersicht aller Hauptschalter seiner Unterpunkte (mit „Details“). Jede Funktion mit Hauptschalter steht in einem eigenen Rahmen, der Schalter oben, die Unteroptionen eingerückt darunter. Ist ein Hauptschalter aus, sind alle Bedienelemente seiner Gruppe gesperrt (auch verschachtelte Gruppen); die Werte bleiben erhalten und werden mit gespeichert. Experimentelle Funktionen samt Hauptschalter sind gesperrt, solange `experimental.enabled` aus ist. Den Hauptschalter bestimmt `x-parent` im Plugin-Katalog, sonst die Präfixregel (längstes Präfix `P` mit boolescher Einstellung `P` oder `P.enabled`); den Unterpunkt `x-node` (Kennungen in `x-nodes`), sonst der Unterpunkt des Hauptschalters. Gliederung nach Seite (`x-page`) und Unterpunkt; eingerückt = Unteroption des Schalters darüber.

### Allgemein

- **Hauptknoten**
  - `completion.enabled`
    - `teamFile.enabled`
  - `diagnosticMode.enabled`
  - `diagnostics.processes`
  - `experimental.enabled`
  - `editor.reloadExternal`
  - `editor.openForEdits`
  - `server.path`
  - `ui.setupChecklist`
  - `settings.markModified`

- **Statusfeld** (`general.statusField`)
  - `statusField.enabled`
    - `statusField.showSummary`
    - `statusField.hidden`
    - `statusField.openToggles`
    - `statusField.indexProgress`

- **Tastenkürzel-Tipps** (`general.shortcutTips`)
  - `shortcutTips.enabled`
    - `shortcutTips.scope`

- **Benachrichtigungen** (`general.notifications`)
  - `notifications.enabled`
    - `notifications.sources`
    - `notifications.maxEntries`

- **Einstellungen übertragen** (`general.transfer`)
  - `settings.exportImport`
    - `settings.backupBeforeImport`
    - `settings.exportSecrets`

- **Architektur** (`general.architecture`)
  - `architecture.enabled`
    - `architecture.scope`
    - `architecture.includeLibraryUnits`
    - `architecture.centralUnits`

### Editor

- **Hauptknoten**
  - `highlight.inactiveDim` – hängt an `completion.enabled`
  - `editor.dimUnusedUses` – hängt an `completion.enabled`
  - `editor.recursionMarkers`
    - `editor.recursionMarkers.depth`
  - `inlayHints.parameterNames`
  - `inlayHints.inferredTypes`
  - `inlayHints.includeDefines`
  - `inlayHints.controlChars`
  - `refactoring.methodKindMarker`
  - `editor.blockEndLabels`
    - `editor.blockEndLabels.minLines`
  - `editor.inlineDiagnostics`
  - `editor.continuePattern` – hängt an `completion.enabled`
    - `editor.continuePattern.minLines`
  - `editor.linkedEditing` (experimentell) – hängt an `completion.enabled`
  - `editor.smartPaste` (experimentell) – hängt an `completion.enabled`
  - `hints.xmlDocExpand`
  - `hints.xmlDocMaxLines`
  - `callHierarchy.diagram`
  - `editor.breadcrumbsIdeColors`
  - `editor.breadcrumbsHideIdeToolbar`
  - `editor.methodPlacement`

- **Paarfärbung** (`editor.pairs`)
  - `highlight.pairColors` – hängt an `completion.enabled`
    - `highlight.pairGuides`
    - `highlight.pairOwners`
    - `highlight.pairGuideWidth`
    - `highlight.pairGuideOpacity`

- **Brotkrumenleiste** (`editor.breadcrumbs`)
  - `editor.breadcrumbs`
    - `editor.breadcrumbsShowUnit`
    - `keys.breadcrumbs`

- **Editorleiste** (`editor.toolbar`)
  - `editor.toolbar`
    - `editor.toolbar.position`
    - `editor.toolbar.items`
    - `editor.toolbar.returnButton`
    - `editor.toolbar.labels`

- **Atlas-Statusleiste** (`editor.statusBar`)
  - `editor.statusBar`
    - `editor.statusBar.items`

- **Mitlaufender Kopf** (`editor.stickyScroll`)
  - `editor.stickyScroll` (experimentell) – hängt an `completion.enabled`
    - `editor.stickyScrollMaxLines`

- **Minimap** (`editor.minimap`)
  - `editor.minimap` (experimentell)
    - `editor.minimap.render`
    - `editor.minimap.width`
    - `editor.minimap.scale`
    - `editor.minimap.maxColumn`
    - `editor.minimap.side`
    - `editor.minimap.showSlider`
    - `editor.minimap.sectionHeaders`
    - `editor.minimap.highlightMethod`
    - `editor.minimap.markers`
    - `editor.minimap.clickJumps`

- **Änderungsmarken** (`editor.gitGutter`)
  - `editor.gitGutter`
    - `keys.nextChange`
    - `keys.previousChange`
  - `editor.gitBlame`

- **Atlas-Spalte** (`editor.gutterColumn`)
  - `editor.gutterColumn`
    - `editor.gutterColumn.problems`
    - `editor.gutterColumn.codeActions`
    - `editor.gutterColumn.overrides`

- **Gleichen Text hervorheben** (`editor.selectionMatches`)
  - `highlight.selectionMatches`
    - `highlight.selectionMatches.minLength`
    - `highlight.selectionMatches.caseSensitive`
    - `highlight.selectionMatches.wholeWord`
    - `highlight.selectionMatches.navigateF3`
    - `highlight.selectionMatches.maxMatches`

- **Austrittspunkte** (`editor.exitPoints`)
  - `editor.exitPoints`
    - `editor.exitPoints.exceptions`
    - `editor.exitPoints.loops`
    - `editor.exitPoints.badge`

- **Neu zugewiesene Variablen** (`highlight.reassigned`)
  - `highlight.reassigned`
    - `highlight.reassigned.targets`
    - `highlight.reassigned.style`
    - `highlight.reassigned.color`

- **Typ des Ausdrucks** (`hints.expressionType`)
  - `hints.expressionType`
    - `hints.expressionType.conversions`
    - `hints.expressionType.constValue`
    - `keys.expressionType`

- **Übersichtsleiste** (`editor.overviewRuler`)
  - `editor.overviewRuler`
    - `editor.overviewRulerKinds`

- **Kommentare fortsetzen** (`editor.continueComments`)
  - `editor.continueComments` – hängt an `completion.enabled`
    - `editor.continueComments.lineComments`
    - `editor.continueComments.lists`
    - `editor.continueComments.blockPrefix`

- **Markierung umschließen** (`editor.wrapSelection`)
  - `editor.wrapSelection`
    - `editor.wrapSelection.chars`

- **Anweisung vervollständigen** (`editor.completeStatement`)
  - `editor.completeStatement`
    - `keys.completeStatement`
    - `editor.completeStatement.beginEnd`
    - `editor.completeStatement.tryKind`
    - `editor.completeStatement.methodBody`

- **Formatieren** (`editor.format`)
  - `editor.format`
    - `keys.format`

- **Mehrere Einfügemarken** (`editor.multiCursor`)
  - `editor.multiCursor` (experimentell) – hängt an `completion.enabled`
    - `editor.multiCursorModifier`
    - `keys.multiCursor.next`
    - `keys.multiCursor.skip`
    - `keys.multiCursor.lineEnds`
    - `keys.multiCursor.above`
    - `keys.multiCursor.below`

- **Notizen und Lesezeichen** (`editor.notes`)
  - `notes.enabled`
  - `bookmarks.named`
    - `bookmarks.shared`

- **Schnelle Lesezeichen** (`editor.quickBookmarks`)
  - `bookmarks.quick`
    - `bookmarks.quick.gutter`
      - `bookmarks.quick.gutterClick`
    - `bookmarks.quick.numberedKeys`
    - `bookmarks.quick.key`
    - `bookmarks.quick.chordWait`
    - `bookmarks.quick.scope`
    - `bookmarks.quick.importIde`

- **Code Lens und Kennzahlen** (`editor.codeLens`)
  - `metrics` – hängt an `completion.enabled`
    - `codeLens.metrics`
  - `codeLens.tests` – hängt an `tests.run`
  - `todos.list`
  - `baseline.update`
  - `metrics.report`
  - `dfmRules.apply`
  - `codeLens.testUnit` – hängt an `completion.enabled`

### Compiler

- **Hauptknoten**
  - `compiler.mcpBuild`
  - `build.zeroHints`
  - `build.showInterfaceCost`
  - `build.summary`
  - `build.warningsAsErrors`
  - `build.compilerSwitches`
    - `build.showSwitchesInStatusBar`
  - `build.gate`
  - `build.gateTimeoutMs`

- **Probleme** (`compiler.problems`)
  - `problems.enabled` – hängt an `completion.enabled`
    - `problems.list`
    - `problems.statusCounter`

- **Nach dem Speichern** (`compiler.afterSave`)
  - `build.checkOnSave`
    - `build.checkOnSaveDelayMs`
    - `build.checkOnSaveMaxMs`
  - `compiler.onSave`

- **Tests** (`compiler.tests`)
  - `tests.run` – hängt an `completion.enabled`
    - `tests.afterBuild`
    - `tests.buildFirst`

- **Startprofile** (`compiler.startProfiles`)
  - `startProfiles.enabled`
    - `startProfiles.statusField`

- **Beim Öffnen bauen** (`compiler.openBuild`)
  - `build.onOpen`
    - `build.onOpenKind`
    - `build.onOpenScope`
    - `build.onOpenDelayMs`
    - `build.onOpenExclude`

- **Projektaufgaben** (`compiler.tasks`)
  - `tasks.enabled`
    - `tasks.problemsFromOutput`
    - `tasks.beforeBuild`
    - `tasks.saveBeforeRun`
    - `tasks.runChecksParallel`
    - `tasks.onlyFindings`

### Befehle

- **Hauptknoten**
  - `bookmarks.key` – hängt an `bookmarks.named`
  - `keys.nextBookmark` – hängt an `bookmarks.quick`
  - `keys.previousBookmark` – hängt an `bookmarks.quick`
  - `keys.hideElement`
  - `keys.nextProblem`
  - `keys.previousProblem`
  - `keys.searchReplace`
  - `keys.search`
  - `keys.searchNext`
  - `keys.searchPrevious`
  - `keys.searchInMethod`
  - `keys.problemsWindow`
  - `keys.gotoInterface`
  - `keys.gotoImplementation`
  - `keys.codeActions`
  - `keys.expandSelection`
  - `keys.shrinkSelection`
  - `keys.implementations`
  - `keys.typeDefinition`
  - `keys.testUnit`
  - `keys.editorPriority`
  - `slashCommands.enabled` – hängt an `completion.enabled`
  - `keys.undoChange`
  - `keys.redoChange`
  - `notifications.key` – hängt an `notifications.enabled`

- **Deklaration ⇄ Implementierung** (`commands.methodToggle`)
  - `codeActions.methodToggle`
    - `keys.methodToggleUp`
    - `keys.methodToggleDown`

- **Sprung zum Gegenstück** (`commands.jumpToMatch`)
  - `keys.jumpToMatch`
    - `keys.jumpToMatchShortcut`
    - `keys.jumpToMatchSelect`

- **Blockkommentar umschalten** (`commands.toggleBlockComment`)
  - `keys.toggleBlockComment`
    - `keys.toggleBlockComment.key`
    - `keys.toggleBlockComment.style`
    - `keys.toggleBlockComment.fallback`
    - `keys.toggleBlockComment.ownLines`
    - `keys.toggleBlockComment.withoutSelection`

- **Neue Zeile ober-/unterhalb** (`commands.newLineAround`)
  - `keys.newLineAround`
    - `keys.newLineAround.belowKey`
    - `keys.newLineAround.aboveKey`
    - `keys.newLineAround.statementAware`

- **Umschließung entfernen** (`commands.unwrap`)
  - `keys.unwrap`
    - `keys.unwrap.key`

- **Sicher löschen** (`commands.safeDelete`)
  - `keys.safeDelete`
    - `keys.safeDelete.key`

- **Zeilen verschieben** (`commands.moveLines`)
  - `keys.moveLines`
    - `keys.moveLinesUp`
    - `keys.moveLinesDown`
    - `keys.duplicateLinesUp`
    - `keys.duplicateLinesDown`

- **Navigationsverlauf** (`commands.navHistory`)
  - `navHistory.enabled`
    - `keys.navBack`
    - `keys.navForward`
    - `keys.lastEdit`

- **Einblenden** (`commands.peek`)
  - `peek.enabled`
    - `peek.heightLines`
    - `peek.showImplementation`
    - `keys.peekDefinition`
    - `keys.peekReferences`

- **Verwendungen** (`commands.references`)
  - `references.inferred`
    - `references.textMatches`

- **Auswirkungen** (`commands.impact`)
  - `navigation.impact`
    - `navigation.impactDepth`

- **Datenfluss** (`commands.dataFlow`)
  - `navigation.dataFlow`
    - `navigation.dataFlow.maxDepth`
    - `navigation.dataFlow.excludeTests`

- **Gliederung** (`commands.outline`)
  - `outline.enabled`
    - `outline.alphabetical`
    - `outline.followCursor`
    - `outline.conditions`

- **Weg zwischen Symbolen** (`commands.symbolPath`)
  - `navigation.symbolPath`

- **Erzeugen-Menü** (`commands.generateMenu`)
  - `keys.generateMenu`
    - `keys.generateMenu.key`
    - `keys.generateMenu.groups`
    - `keys.generateMenu.hidden`
    - `keys.generateMenu.recentFirst`
    - `keys.generateMenu.showCommandNames`

### Hints

- **Hauptknoten**
  - `editor.hoverTooltip` – hängt an `completion.enabled`
    - `hover.problemActions`

### Vervollständigung

- **Hauptknoten**
  - `completion.filterChips` – hängt an `completion.enabled`
  - `completion.preview` – hängt an `completion.enabled`
  - `completion.groupInherited` – hängt an `completion.enabled`
  - `completion.variantBranch` – hängt an `completion.enabled`
  - `completion.listMode` – hängt an `completion.enabled`
  - `completion.listMode.scope` – hängt an `completion.enabled`
  - `completion.learning` – hängt an `completion.enabled`
  - `completion.favorites` – hängt an `completion.enabled`
  - `completion.visibleRows` – hängt an `completion.enabled`
  - `completion.panelCollapsed` – hängt an `completion.enabled`
  - `completion.selectionMarker` – hängt an `completion.enabled`
  - `completion.openDelayMs` – hängt an `completion.enabled`

### Debuggen

- **Hauptknoten**
  - `tests.debug`
    - `debug.testBreakAtStart`
  - `debug.hoverValues`
  - `debug.explainUnavailable`
  - `debug.completionInDialogs`
  - `debug.evaluateWindow`
    - `debug.evaluateWindow.replaceCtrlF7`
  - `debug.explainAccessViolation`
    - `debug.explainAccessViolation.allowCalls`
  - `debug.exceptionHistory`
    - `debug.exceptionBanner`
      - `debug.exceptionBanner.ignoreAtLocation`
  - `debug.justMyCode`
    - `debug.ownCodeFolders`
  - `debug.inlineValues`
    - `debug.inlineValuesPerLine`
  - `debug.visualizers`
    - `debug.visualizers.types`
    - `debug.visualizers.nameFields`
    - `debug.visualizers.maxLength`
    - `debug.visualizers.timeoutMs`
    - `debug.visualizers.maxImagePixels`
    - `debug.visualizers.evaluation`
  - `debug.displayRules`
    - `debug.displayRules.allowCalls`
  - `debug.stepIntoTarget`
    - `debug.stepIntoTarget.key`
  - `debug.stepFilters`
    - `debug.stepFilters.kinds`
    - `debug.stepFilters.patterns`
  - `debug.breakOnNextEvent`
    - `debug.breakOnNextEvent.excluded`

### Release-Build

- **Hauptknoten**
  - `build.releaseGuard` – hängt an `completion.enabled`
    - `build.releaseConfigs`
    - `build.releaseChecks`

### Willkommensseite

- **Hauptknoten**
  - `welcomePage.enabled`
    - `welcomePage.openOnStart`
    - `welcomePage.openWhenNoProject`
    - `welcomePage.whatsNew`

- **Kopf** (`welcome.header`)
  - `welcomePage.header` – hängt an `welcomePage.enabled`
  - `welcomePage.greeting` – hängt an `welcomePage.enabled`

- **Suche** (`welcome.search`)
  - `welcomePage.search` – hängt an `welcomePage.enabled`
    - `welcomePage.search.symbols`
    - `welcomePage.search.key`

- **Weiterarbeiten** (`welcome.continue`)
  - `welcomePage.continue` – hängt an `welcomePage.enabled`
    - `welcomePage.continue.count`
    - `welcomePage.continue.incoming`
    - `welcomePage.continue.fetch`
  - `welcomePage.saved` – hängt an `welcomePage.enabled`

- **Projekte** (`welcome.projects`)
  - `welcomePage.projectStatus` – hängt an `welcomePage.enabled`
    - `welcomePage.maxProjects`
    - `welcomePage.refreshVcs`

- **Projektverlauf** (`welcome.trends`)
  - `welcomePage.trends` – hängt an `welcomePage.enabled`
    - `welcomePage.trends.points`
    - `welcomePage.trends.series`

- **Testergebnisse** (`welcome.tests`)
  - `welcomePage.tests` – hängt an `welcomePage.enabled`
    - `welcomePage.tests.maxFailures`
    - `welcomePage.tests.ci`
      - `welcomePage.tests.ci.login`
      - `welcomePage.tests.ci.provider`
      - `welcomePage.tests.ci.intervalMinutes`
      - `welcomePage.tests.ci.notify`

- **Meine Issues** (`welcome.issues`)
  - `welcomePage.issues` – hängt an `welcomePage.enabled`

- **Sprint** (`welcome.sprint`)
  - `welcomePage.sprint` – hängt an `welcomePage.enabled`

- **Schnellaktionen** (`welcome.quickActions`)
  - `welcomePage.quickActions` – hängt an `welcomePage.enabled`
    - `welcomePage.quickActions.items`
    - `welcomePage.quickActions.console`
    - `welcomePage.quickActions.buildKey`
    - `welcomePage.quickActions.testKey`

- **Nicht gesichert** (`welcome.unsaved`)
  - `welcomePage.unsaved` – hängt an `welcomePage.enabled`
    - `welcomePage.unsaved.minAgeHours`
    - `welcomePage.unsaved.warnHours`
    - `welcomePage.unsaved.alertHours`
    - `welcomePage.unsaved.hideWhenClean`

- **Zustandskachel** (`welcome.statusTile`)
  - `welcomePage.statusTile` – hängt an `welcomePage.enabled`
    - `welcomePage.statusTile.onlyProblems`

- **Atlas entdecken** (`welcome.discover`)
  - `welcomePage.discover` – hängt an `welcomePage.enabled`
    - `tips.usageTracking`

- **Hilfe und Rückmeldung** (`welcome.help`)
  - `welcomePage.help` – hängt an `welcomePage.enabled`
    - `welcomePage.help.reportUrl`
    - `welcomePage.help.reportFolder`

- **Projekt einrichten** (`welcome.projectSetup`)
  - `welcomePage.projectSetup` – hängt an `welcomePage.enabled`
  - `welcomePage.newFromTemplate` – hängt an `welcomePage.enabled`

- **Freies Layout** (`welcome.customLayout`)
  - `welcomePage.customLayout` – hängt an `welcomePage.enabled`
    - `welcomePage.columns`
    - `welcomePage.layouts`
    - `welcomePage.activeLayout`

### Einfügen

- **Hauptknoten**
  - `completion.autoParentheses` – hängt an `completion.enabled`
  - `completion.fixCase` – hängt an `completion.enabled`
  - `completion.commitCharacters` – hängt an `completion.enabled`
  - `completion.autoUses` – hängt an `completion.enabled`
  - `completion.parameterHints` – hängt an `completion.enabled`
    - `completion.formatPlaceholders`
  - `snippets.enabled`
    - `snippets.importIdeTemplates`

### Tastenkonflikte

- **Hauptknoten**
  - `keys.palette`
  - `keys.check`
  - `keys.palettePriority`
  - `keys.checkPriority`
  - `keys.completion`
  - `keys.signature`
  - `keys.completionPriority`
  - `keys.signaturePriority`
  - `bookmarks.quick.keyPriority`
  - `bookmarks.quick.setKey`
  - `bookmarks.quick.setKeyPriority`
  - `bookmarks.quick.jumpKey`
  - `bookmarks.quick.jumpKeyPriority`
  - `keys.quickToggles`
  - `keys.quickTogglesPriority`
  - `keys.diagnosticMode`
  - `keys.diagnosticModePriority`
  - `keys.overview`
  - `keys.startupCheck`

### Robustheit

- **Hauptknoten**
  - `robustness.hangThresholdMs`
  - `robustness.providerTimeLimitMs`
  - `robustness.hangHint`

### Units suchen

- **Hauptknoten**
  - `search.replaceIdeSearch`
  - `search.resultsInMessages`
  - `search.replace`
  - `search.regex`
  - `search.history`
  - `search.multiFile`
  - `unitSearch.enabled`
    - `unitSearch.replaceIdeDialog`
    - `unitSearch.replaceUseUnitDialog`
    - `unitSearch.replaceFormsDialog`
    - `unitSearch.rememberCollapsed`
    - `unitSearch.filters`
    - `unitSearch.filterSyntax`
    - `unitSearch.preview`
      - `unitSearch.preview.form`
      - `unitSearch.preview.usedBy`
      - `unitSearch.preview.autoCollapse`
    - `unitSearch.multiSelect`
    - `unitSearch.actions`
      - `unitSearch.actions.addUses`
    - `unitSearch.pathStyle`
    - `unitSearch.groupBy`
    - `unitSearch.defaultScope`
    - `unitSearch.key`

- **Schnell öffnen** (`unitSearch.quickOpen`)
  - `quickOpen.enabled`
    - `quickOpen.librarySources`
    - `keys.quickOpen`

### Farben

- **Hauptknoten**
  - `highlight.pairColorsLight` – hängt an `highlight.pairColors`
  - `highlight.pairColorsDark` – hängt an `highlight.pairColors`

### Prüfregeln

- **Prüffenster** (`rules.window`)
  - `problems.window` – hängt an `problems.enabled`
    - `problems.window.scope`
    - `problems.window.groupBy`
    - `problems.window.columns`
    - `problems.window.compiler`
    - `problems.window.followCursor`
    - `problems.window.openFirst`
      - `problems.window.closedUnits`
      - `problems.window.showCleanActive`
  - `problems.live` – hängt an `problems.enabled`

- **Compiler vorab** (`rules.group.compiler`)
  - `problems.compilerMerge` – hängt an `problems.enabled`
  - `problems.showCompilerCode` – hängt an `problems.enabled`

### Index

- **Hauptknoten**
  - `index.projectGroup`
  - `index.searchPaths`
  - `index.libraryPaths`
  - `index.usages`
  - `memoryBudgetMb`

### Start und Updates

- **Hauptknoten**
  - `safeMode.askAfterCrash`
  - `safeMode.autoAfterRepeatedCrash`
  - `safeMode.startupKey`
  - `safeMode.startupTimeoutMs`
  - `safeMode.keepSettingsHistory`
  - `updates.check`
  - `diagnostics.bugReport.anonymize`

### Rückgängig

- **Hauptknoten**
  - `undo.multiFile`
    - `undo.multiFile.depth`
    - `undo.multiFile.persist`
    - `undo.multiFile.maxSizeMb`
    - `undo.multiFile.onConflict`
    - `undo.multiFile.newFiles`

### Issue-Tracker

- **Hauptknoten**
  - `issues.tracker`
  - `issues.query`
  - `issues.start`
  - `issues.branchPattern`
  - `issues.branchBase`
  - `issues.commitPattern`
  - `issues.login`
  - `issues.connections`
  - `issues.preview`
    - `issues.preview.comments`
    - `issues.preview.links`
    - `issues.preview.checklists`
  - `issues.syncState`
  - `issues.stateField`
  - `issues.assigneeField`
  - `issues.startState`
  - `issues.assignOnStart`
  - `issues.startComment`
  - `issues.endStates`
  - `issues.endComment`
  - `issues.projects`
  - `issues.warnBlocked`
  - `issues.checklistStatus`
  - `issues.board`
    - `issues.board.confirmMove`
    - `issues.board.onlyMine`
  - `issues.sprint.burndown`
  - `issues.sprint.compare`
