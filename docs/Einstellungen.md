# Einstellungen

<!-- Erzeugt von Tools/Update-ConfigDoc.ps1 aus Editors/VSCode/schemas/argus.schema.json. Nicht von Hand bearbeiten. -->

Alle Einstellungen mit Seite und Bedienelement im Einstellungs-Plugin (#227). Einzelheiten zu Werten und Bedeutung stehen in [Konfiguration.md](Konfiguration.md).

| Seite | Einstellung | Standard | Quelle | Neustart | Bedienelement | Herkunft |
|---|---|---|---|---|---|---|
| Allgemein | `delphiVersion` | – | argus.json, Editor (`argus.delphiVersion`) | nein | Auswahl aus den installierten Versionen | #47, #258 |
| Allgemein | `language` | `"de"` | argus.json, Editor (`argus.language`) | nein | Auswahl | #24 |
| Projekt | `project` | – | argus.json, Editor (`argus.project`) | nein | Vorgabe: aktives IDE-Projekt | #14, #24 |
| Projekt | `config` | – | argus.json, Editor (`argus.config`) | nein | Auswahl aus der .dproj | #14, #46 |
| Projekt | `platform` | – | argus.json, Editor (`argus.platform`) | nein | Auswahl aus der .dproj | #14, #46 |
| Prüfregeln | `rules` | – | argus.json, Editor (`argus.rules`) | nein | Tabelle aus dem Regelkatalog | #41 |
| Prüfregeln | `profile` | `"standard"` | argus.json, Editor (`argus.profile`) | nein | Auswahl | #146 |
| Prüfregeln | `profiles` | – | argus.json, Editor (`argus.profiles`) | nein | Profil-Editor | #146 |
| Prüfregeln | `overrides` | – | argus.json, Editor (`argus.overrides`) | nein | Liste mit Mustern | #146 |
| Prüfregeln | `excludeTests` | `false` | argus.json, Editor (`argus.excludeTests`) | nein | Kontrollkästchen | #146 |
| Prüfregeln | `testProfile` | – | argus.json, Editor (`argus.testProfile`) | nein | Auswahl | #146 |
| Compiler | `compiler`: `onSave` | – | argus.json, Editor (`argus.compiler`) | nein | Kontrollkästchen | #40 |
| Vervollständigung | `completion`: `matching` | – | argus.json, Editor (`argus.completion`) | nein | Auswahl | #229 |
| Eingabehilfen | `usesCommand` | `true` | argus.json, Editor (`argus.usesCommand`) | nein | Kontrollkästchen | #254 |
| Eingabehilfen | `slashCommands`: `enabled`, `disabled`, `headerTemplate` | – | argus.json, Editor (`argus.slashCommands`) | nein | Kontrollkästchen, Liste | #293 |
| Eingabehilfen | `sortUses` | `false` | argus.json, Editor (`argus.sortUses`) | nein | Auswahl | #182, #284 |
| Eingabehilfen | `usesKeep` | `` | argus.json, Editor (`argus.usesKeep`) | nein | Liste | #284 |
| Speicher | `memoryBudgetMb` | `0` | argus.json, Editor (`argus.memoryBudgetMb`) | nein | Zahlenfeld (MB) | #185 |
| Robustheit | `requestTimeoutMs` | `10000` | argus.json, Editor (`argus.requestTimeoutMs`) | nein | Zahlenfeld (ms) | #283 |
| Editor | `highlight`: `blockPairs`, `directives`, `exitPoints`, `exitKeywords` | – | argus.json, Editor (`argus.highlight`) | nein | Kontrollkästchen, Liste | #307 |
| Editor | `inlayHints`: `parameterNames`, `inferredTypes`, `endMarkers`, `endMarkerMinLines` | – | argus.json, Editor (`argus.inlayHints`) | nein | Kontrollkästchen, Zahlenfeld | #35 |
| Editor | `stringLiteral`: `style`, `lineBreak`, `maxLineLength` | – | argus.json, Editor (`argus.stringLiteral`) | nein | Auswahl, Zahlenfeld | #312 |
| Editor | `memberOrder`: `sections`, `members`, `sortFields`, `sortPublished` | – | argus.json, Editor (`argus.memberOrder`) | nein | Liste, Kontrollkästchen | #89 |
| Prüfregeln | `minConfidence` | `"medium"` | argus.json, Editor (`argus.minConfidence`) | nein | Auswahl | #144 |
| Projekt | `exclude` | – | argus.json, Editor (`argus.exclude`) | nein | Liste mit Hinzufügen/Entfernen | #24 |
| Formatierung | `format`: `indentSize`, `useTabs`, `keywordCase`, `trimTrailingWhitespace`, `insertFinalNewline`, `spaceAroundAssignment`, `spaceAfterComma`, `endOfLine` | – | argus.json, Editor (`argus.format`) | nein | Zahlenfeld, Kontrollkästchen, Auswahl | #43 |
| Protokoll | `logLevel` | `"info"` | argus.json, Editor (`argus.logLevel`), ``--log-level`` | ja | Auswahl | #76, #96 |
| Protokoll | `logFile` | `""` | argus.json, Editor (`argus.logFile`), ``--log`` | ja | Datei wählen | #76, #96 |
| Protokoll | `traceFile` | `""` | argus.json, Editor (`argus.traceFile`), ``--trace`` | ja | Datei wählen | #76, #96 |
| Allgemein | Pfad zu `ArgusServer.exe` | – | VS Code (`argus.serverPath`) | ja | Datei wählen, Version anzeigen | #12, #49 |
| Baseline | `argus-baseline.json` | – | Datei, `--baseline`, `--update-baseline` | nein | Anzahl Einträge, „Baseline neu erzeugen“, „Baseline löschen“ | #97 |
| Baseline | Unterdrückungen `lsp-ignore` | – | `--suppression-stats` | nein | Übersicht je Regel (nur Anzeige) | #147 |
| Speicher | Index-Cache löschen | – | `--clear-cache`, Befehl `argus.server.rebuildIndex` | nein | Knopf „Index-Cache löschen“ | #184 |
