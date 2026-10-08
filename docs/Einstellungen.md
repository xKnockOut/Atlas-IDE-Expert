# Einstellungen

<!-- Erzeugt von Tools/Update-ConfigDoc.ps1 aus Editors/VSCode/schemas/delphi-lsp.schema.json. Nicht von Hand bearbeiten. -->

Alle Einstellungen mit Seite und Bedienelement im Einstellungs-Plugin (#227). Einzelheiten zu Werten und Bedeutung stehen in [Konfiguration.md](Konfiguration.md).

| Seite | Einstellung | Standard | Quelle | Neustart | Bedienelement | Herkunft |
|---|---|---|---|---|---|---|
| Allgemein | `delphiVersion` | – | delphi-lsp.json, Editor (`betterDelphiLsp.delphiVersion`) | nein | Auswahl aus den installierten Versionen | #47, #258 |
| Allgemein | `language` | `"de"` | delphi-lsp.json, Editor (`betterDelphiLsp.language`) | nein | Auswahl | #24 |
| Projekt | `project` | – | delphi-lsp.json, Editor (`betterDelphiLsp.project`) | nein | Vorgabe: aktives IDE-Projekt | #14, #24 |
| Projekt | `config` | – | delphi-lsp.json, Editor (`betterDelphiLsp.config`) | nein | Auswahl aus der .dproj | #14, #46 |
| Projekt | `platform` | – | delphi-lsp.json, Editor (`betterDelphiLsp.platform`) | nein | Auswahl aus der .dproj | #14, #46 |
| Prüfregeln | `rules` | – | delphi-lsp.json, Editor (`betterDelphiLsp.rules`) | nein | Tabelle aus dem Regelkatalog | #41 |
| Prüfregeln | `profile` | `"standard"` | delphi-lsp.json, Editor (`betterDelphiLsp.profile`) | nein | Auswahl | #146 |
| Prüfregeln | `profiles` | – | delphi-lsp.json, Editor (`betterDelphiLsp.profiles`) | nein | Profil-Editor | #146 |
| Prüfregeln | `overrides` | – | delphi-lsp.json, Editor (`betterDelphiLsp.overrides`) | nein | Liste mit Mustern | #146 |
| Prüfregeln | `excludeTests` | `false` | delphi-lsp.json, Editor (`betterDelphiLsp.excludeTests`) | nein | Kontrollkästchen | #146 |
| Prüfregeln | `testProfile` | – | delphi-lsp.json, Editor (`betterDelphiLsp.testProfile`) | nein | Auswahl | #146 |
| Compiler | `compiler`: `onSave` | – | delphi-lsp.json, Editor (`betterDelphiLsp.compiler`) | nein | Kontrollkästchen | #40 |
| Vervollständigung | `completion`: `matching` | – | delphi-lsp.json, Editor (`betterDelphiLsp.completion`) | nein | Auswahl | #229 |
| Eingabehilfen | `completeBlocks`: `begin`, `try`, `case`, `record`, `class`, `repeat` | – | delphi-lsp.json, Editor (`betterDelphiLsp.completeBlocks`) | nein | Kontrollkästchen je Block | #179 |
| Eingabehilfen | `usesCommand` | `true` | delphi-lsp.json, Editor (`betterDelphiLsp.usesCommand`) | nein | Kontrollkästchen | #254 |
| Eingabehilfen | `sortUses` | `false` | delphi-lsp.json, Editor (`betterDelphiLsp.sortUses`) | nein | Auswahl | #182, #284 |
| Eingabehilfen | `usesKeep` | `` | delphi-lsp.json, Editor (`betterDelphiLsp.usesKeep`) | nein | Liste | #284 |
| Speicher | `memoryBudgetMb` | `0` | delphi-lsp.json, Editor (`betterDelphiLsp.memoryBudgetMb`) | nein | Zahlenfeld (MB) | #185 |
| Robustheit | `requestTimeoutMs` | `10000` | delphi-lsp.json, Editor (`betterDelphiLsp.requestTimeoutMs`) | nein | Zahlenfeld (ms) | #283 |
| Editor | `highlight`: `blockPairs`, `directives`, `exitPoints`, `exitKeywords` | – | delphi-lsp.json, Editor (`betterDelphiLsp.highlight`) | nein | Kontrollkästchen, Liste | #307 |
| Editor | `inlayHints`: `parameterNames`, `inferredTypes`, `endMarkers`, `endMarkerMinLines` | – | delphi-lsp.json, Editor (`betterDelphiLsp.inlayHints`) | nein | Kontrollkästchen, Zahlenfeld | #35 |
| Prüfregeln | `minConfidence` | `"medium"` | delphi-lsp.json, Editor (`betterDelphiLsp.minConfidence`) | nein | Auswahl | #144 |
| Projekt | `exclude` | – | delphi-lsp.json, Editor (`betterDelphiLsp.exclude`) | nein | Liste mit Hinzufügen/Entfernen | #24 |
| Formatierung | `format`: `indentSize`, `useTabs`, `keywordCase`, `trimTrailingWhitespace`, `insertFinalNewline`, `spaceAroundAssignment`, `spaceAfterComma`, `endOfLine` | – | delphi-lsp.json, Editor (`betterDelphiLsp.format`) | nein | Zahlenfeld, Kontrollkästchen, Auswahl | #43 |
| Protokoll | `logLevel` | `"info"` | delphi-lsp.json, Editor (`betterDelphiLsp.logLevel`), ``--log-level`` | ja | Auswahl | #76, #96 |
| Protokoll | `logFile` | `""` | delphi-lsp.json, Editor (`betterDelphiLsp.logFile`), ``--log`` | ja | Datei wählen | #76, #96 |
| Protokoll | `traceFile` | `""` | delphi-lsp.json, Editor (`betterDelphiLsp.traceFile`), ``--trace`` | ja | Datei wählen | #76, #96 |
| Allgemein | Pfad zu `BetterDelphiLSP.exe` | – | VS Code (`betterDelphiLsp.serverPath`) | ja | Datei wählen, Version anzeigen | #12, #49 |
| Baseline | `delphi-lsp-baseline.json` | – | Datei, `--baseline`, `--update-baseline` | nein | Anzahl Einträge, „Baseline neu erzeugen“, „Baseline löschen“ | #97 |
| Baseline | Unterdrückungen `lsp-ignore` | – | `--suppression-stats` | nein | Übersicht je Regel (nur Anzeige) | #147 |
| Speicher | Index-Cache löschen | – | `--clear-cache`, Befehl `betterdelphilsp.rebuildIndex` | nein | Knopf „Index-Cache löschen“ | #184 |
