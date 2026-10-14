# Einstellungen

<!-- Erzeugt von Tools/Update-ConfigDoc.ps1 aus Editors/VSCode/schemas/atlas.schema.json. Nicht von Hand bearbeiten. -->

Alle Einstellungen mit Seite und Bedienelement im Einstellungs-Plugin (#227). Einzelheiten zu Werten und Bedeutung stehen in [Konfiguration.md](Konfiguration.md).

| Seite | Einstellung | Standard | Quelle | Neustart | Bedienelement | Herkunft |
|---|---|---|---|---|---|---|
| Allgemein | `delphiVersion` | – | atlas.json, Editor (`atlas.delphiVersion`) | nein | Auswahl aus den installierten Versionen | #47, #258 |
| Allgemein | `language` | `"de"` | atlas.json, Editor (`atlas.language`) | nein | Auswahl | #24 |
| Projekt | `project` | – | atlas.json, Editor (`atlas.project`) | nein | Vorgabe: aktives IDE-Projekt | #14, #24 |
| Projekt | `config` | – | atlas.json, Editor (`atlas.config`) | nein | Auswahl aus der .dproj | #14, #46 |
| Projekt | `platform` | – | atlas.json, Editor (`atlas.platform`) | nein | Auswahl aus der .dproj | #14, #46 |
| Prüfregeln | `rules` | – | atlas.json, Editor (`atlas.rules`) | nein | Tabelle aus dem Regelkatalog | #41 |
| Prüfregeln | `profile` | `"standard"` | atlas.json, Editor (`atlas.profile`) | nein | Auswahl | #146 |
| Prüfregeln | `profiles` | – | atlas.json, Editor (`atlas.profiles`) | nein | Profil-Editor | #146 |
| Prüfregeln | `overrides` | – | atlas.json, Editor (`atlas.overrides`) | nein | Liste mit Mustern | #146 |
| Prüfregeln | `excludeTests` | `false` | atlas.json, Editor (`atlas.excludeTests`) | nein | Kontrollkästchen | #146 |
| Prüfregeln | `testProfile` | – | atlas.json, Editor (`atlas.testProfile`) | nein | Auswahl | #146 |
| Compiler | `compiler`: `onSave` | – | atlas.json, Editor (`atlas.compiler`) | nein | Kontrollkästchen | #40 |
| Vervollständigung | `completion`: `matching` | – | atlas.json, Editor (`atlas.completion`) | nein | Auswahl | #229 |
| Eingabehilfen | `usesCommand` | `true` | atlas.json, Editor (`atlas.usesCommand`) | nein | Kontrollkästchen | #254 |
| Eingabehilfen | `slashCommands`: `enabled`, `disabled`, `headerTemplate` | – | atlas.json, Editor (`atlas.slashCommands`) | nein | Kontrollkästchen, Liste | #293 |
| Eingabehilfen | `sortUses` | `false` | atlas.json, Editor (`atlas.sortUses`) | nein | Auswahl | #182, #284 |
| Eingabehilfen | `usesKeep` | `` | atlas.json, Editor (`atlas.usesKeep`) | nein | Liste | #284 |
| Prüfregeln | `dfmPropertyRules` | `` | atlas.json, Editor (`atlas.dfmPropertyRules`) | nein | Eigener Editor (Klasse und Property aus dem Index) | #309 |
| Speicher | `memoryBudgetMb` | `256` | atlas.json, Editor (`atlas.memoryBudgetMb`) | nein | Zahlenfeld (MB) | #185, #492 |
| Speicher | `index`: `projectGroup`, `searchPaths`, `libraryPaths`, `usages`, `exclude` | – | atlas.json, Editor (`atlas.index`) | nein | Kontrollkästchen, Liste mit Hinzufügen/Entfernen | #648, #492 |
| Robustheit | `requestTimeoutMs` | `10000` | atlas.json, Editor (`atlas.requestTimeoutMs`) | nein | Zahlenfeld (ms) | #283 |
| Robustheit | `diagnostics`: `log`, `logDays`, `logMapFile` | – | atlas.json, Editor (`atlas.diagnostics`) | nein | Kontrollkästchen, Zahlenfeld (Tage) | #647 |
| Editor | `highlight`: `blockPairs`, `directives`, `exitPoints`, `exitKeywords` | – | atlas.json, Editor (`atlas.highlight`) | nein | Kontrollkästchen, Liste | #307 |
| Editor | `inlayHints`: `parameterNames`, `inferredTypes`, `endMarkers`, `endMarkerMinLines` | – | atlas.json, Editor (`atlas.inlayHints`) | nein | Kontrollkästchen, Zahlenfeld | #35 |
| Hints | `hints`: `xmlDocFull`, `xmlDocMaxLines` | – | atlas.json, Editor (`atlas.hints`) | nein | Kontrollkästchen, Zahlenfeld | #654 |
| Editor | `stringLiteral`: `style`, `lineBreak`, `maxLineLength` | – | atlas.json, Editor (`atlas.stringLiteral`) | nein | Auswahl, Zahlenfeld | #312 |
| Editor | `memberOrder`: `sections`, `members`, `sortFields`, `sortPublished` | – | atlas.json, Editor (`atlas.memberOrder`) | nein | Liste, Kontrollkästchen | #89 |
| Prüfregeln | `minConfidence` | `"medium"` | atlas.json, Editor (`atlas.minConfidence`) | nein | Auswahl | #144 |
| Projekt | `exclude` | – | atlas.json, Editor (`atlas.exclude`) | nein | Liste mit Hinzufügen/Entfernen | #24 |
| MCP | `mcp`: `disabledTools` | – | atlas.json, Editor (`atlas.mcp`) | nein | Liste mit Hinzufügen/Entfernen | #99 |
| Formatierung | `format`: `indentSize`, `useTabs`, `keywordCase`, `trimTrailingWhitespace`, `insertFinalNewline`, `spaceAroundAssignment`, `spaceAfterComma`, `endOfLine` | – | atlas.json, Editor (`atlas.format`) | nein | Zahlenfeld, Kontrollkästchen, Auswahl | #43 |
| Protokoll | `logLevel` | `"info"` | atlas.json, Editor (`atlas.logLevel`), ``--log-level`` | ja | Auswahl | #76, #96 |
| Protokoll | `logFile` | `""` | atlas.json, Editor (`atlas.logFile`), ``--log`` | ja | Datei wählen | #76, #96 |
| Protokoll | `traceFile` | `""` | atlas.json, Editor (`atlas.traceFile`), ``--trace`` | ja | Datei wählen | #76, #96 |
| Allgemein | Pfad zu `AtlasServer.exe` | – | VS Code (`atlas.serverPath`) | ja | Datei wählen, Version anzeigen | #12, #49 |
| Baseline | `atlas-baseline.json` | – | Datei, `--baseline`, `--update-baseline` | nein | Anzahl Einträge, „Baseline neu erzeugen“, „Baseline löschen“ | #97 |
| Baseline | Unterdrückungen `lsp-ignore` | – | `--suppression-stats` | nein | Übersicht je Regel (nur Anzeige) | #147 |
| Speicher | Index-Cache löschen | – | `--clear-cache`, Befehl `atlas.server.clearIndex` (löschen und neu indizieren), `atlas.server.rebuildIndex` (nur neu indizieren) | nein | Knöpfe „Index löschen“ und „Index neu aufbauen“ | #184, #492 |
| Allgemein | Atlas-Feld in der Statusleiste (`statusField.enabled`), Kurztext (`statusField.showSummary`), ausgeblendete Zeilen (`statusField.hidden`) | an, an, – | Plugin (Registry `StatusField`, `StatusFieldSummary`, `StatusFieldHidden`) | nein | Kontrollkästchen, Kontrollkästchen, Textfeld mit Kennungen | #591 |
| Allgemein | Schnellschalter (#604): Fenster über dem Statusfeld (Rechtsklick) und Tastenkürzel; Schalter = jede boolesche Einstellung mit `x-quickToggle` (Plugin-Katalog und `atlas.schema.json`) | Strg+Umschalt+Alt+A | Plugin (Registry `QuickToggleKey`, `QuickToggleKeyPriority`) | nein | Taste auf der Seite „Tastenkonflikte“; „Alles aus für diese Sitzung“ ändert keine Einstellung | #604 |
