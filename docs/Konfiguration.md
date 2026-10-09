# Konfiguration: argus.json

<!-- Erzeugt von Tools/Update-ConfigDoc.ps1 aus Editors/VSCode/schemas/argus.schema.json. Nicht von Hand bearbeiten. -->

Einstellungen für Argus im Projektordner.

Die Datei liegt im Projektordner. Fehlende Schlüssel nehmen den Standardwert; Editor-Einstellungen gelten nur, wo die Datei nichts sagt. Die Prüfregeln stehen in [Regeln.md](Regeln.md).

## Schlüssel

| Schlüssel | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|
| `delphiVersion` | string | – | z. B. `"37.0"`, `"23.0"` | Delphi-Version als Produktnummer ("13", "12", "10.4") oder wie in der Registry ("37.0" für Delphi 13, "23.0" für Delphi 12). Leer: neueste installierte Version. |
| `language` | string | `"de"` | `"de"`, `"en"` | Sprache der Meldungen. |
| `project` | string | – |  | Projektdatei (.dproj) relativ zu diesem Ordner. Leer: automatisch suchen. |
| `config` | string | – | z. B. `"Debug"`, `"Release"` | Build-Konfiguration, z. B. Debug oder Release. |
| `platform` | string | – | z. B. `"Win32"`, `"Win64"` | Zielplattform. |
| `rules` | object | – |  | Prüfregeln einzeln einstellen: Regel-ID → Schweregrad oder Objekt mit "severity" und Optionen. |
| `profile` |  | `"standard"` | z. B. `"fast"`, `"strict"` | Regelprofil: standard, fast (nur Bugs und Schwachstellen), strict (experimentelle Regeln an, minConfidence low), security, style oder ein eigenes aus "profiles". Als Objekt getrennt für Editor und Kommandozeile. |
| `profiles` | object | – |  | Eigene Regelprofile: Name → { "extends": eingebautes oder eigenes Profil, "categories": nur diese Kategorien, "rules": Regel-ID → Schweregrad }. |
| `overrides` | array<object> | – |  | Pfadregeln: Schweregrade für Dateien, die eines der Glob-Muster treffen, z. B. Tests oder generierten Code herabstufen. Regel-ID "*" steht für alle Regeln; spätere Einträge haben Vorrang. |
| `excludeTests` | boolean | `false` |  | Test-Units und Testprojekte (uses DUnitX.TestFramework, TestFramework oder TestInsight.*) nicht prüfen. |
| `testProfile` | string | – | z. B. `"fast"` | Regelprofil für Test-Units und Testprojekte; leer: wie "profile". |
| `compiler` | object | – |  | Compiler-Anbindung (dcc32/dcc64). |
| `completion` | object | – |  | Code-Vervollständigung. |
| `usesCommand` | boolean | `true` |  | Eine Zeile "/uses Unit1, Unit2" wird nach Enter gelöscht und die Units kommen ins passende uses. |
| `sortUses` | boolean string | `false` | `true`, `false`, `"alphabetic"`, `"namespace"` | "uses aufräumen" (source.organizeImports, z. B. beim Speichern) sortiert die uses: true oder "alphabetic" alphabetisch, "namespace" nach Namespace gruppiert (System, Vcl, ... und Units ohne Namespace zuletzt). Achtung: Die Reihenfolge bestimmt die Initialisierung der Units. |
| `usesKeep` | array<string> | `` |  | Units, die "ungenutzte uses entfernen" nie entfernt, zusätzlich zu allen Units mit initialization-Abschnitt. |
| `memoryBudgetMb` | integer | `0` | 0… | Obergrenze für den Symbolindex in MB. Darüber werden zuerst Bibliotheks-Units (RTL, VCL), dann Projekt-Units kompakt gehalten (nur interface-Symbole). 0: unbegrenzt. |
| `requestTimeoutMs` | integer | `10000` | 1000… | Zeitlimit für Anfragen in Millisekunden. Länger laufende Anfragen werden abgebrochen und im Log gemeldet. |
| `highlight` | object | – |  | Zusammengehörige Schlüsselwörter hervorheben, wenn der Cursor auf einem steht. |
| `inlayHints` | object | – |  | Inlay Hints im Editor. |
| `minConfidence` | string | `"medium"` | `"low"`, `"medium"`, `"high"` | Regeltreffer unter dieser Konfidenz ausblenden. |
| `exclude` | array<string> | – | z. B. `["ThirdParty/**","Generated/*.pas"]` | Ordner und Dateien, die nicht geprüft werden (Glob-Muster relativ zu diesem Ordner: *, **, ?). |
| `format` | object | – |  | Formatierung (Dokument und Auswahl formatieren). Gesetzte Werte haben Vorrang vor .editorconfig. |
| `logLevel` | string | `"info"` | `"debug"`, `"info"`, `"warning"`, `"error"` | Mindeststufe der Meldungen im Ausgabefenster und in der Logdatei. Gilt ab dem nächsten Start; die Kommandozeilenoption --log-level hat Vorrang. |
| `logFile` | string | `""` |  | Optionale Logdatei des Servers (Rotation bei 10 MB). Gilt ab dem nächsten Start; --log hat Vorrang. |
| `traceFile` | string | `""` |  | Optionaler Mitschnitt aller JSON-Nachrichten zur Fehlersuche. Gilt ab dem nächsten Start; --trace hat Vorrang. |

## compiler

| Schlüssel | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|
| `compiler.onSave` | boolean | `true` |  | Nach dem Speichern einer Quelldatei das Projekt im Hintergrund kompilieren und die Meldungen anzeigen. |

## completion

| Schlüssel | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|
| `completion.matching` | string | `"fuzzy"` | `"fuzzy"`, `"prefix"` | Auswahl der Vorschläge: unscharf (Teilfolgen, Kürzel wie TSL für TStringList) oder nur nach Präfix, falls ein Editor nachträglich strikt filtert. |

## highlight

| Schlüssel | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|
| `highlight.blockPairs` | boolean | `true` |  | Blockpaare (begin/end, try/finally/except/end, case/of/end, repeat/until, if/then/else, Typen) und Routinen hervorheben. |
| `highlight.directives` | boolean | `true` |  | Zusammengehörige {$IF…}/{$ELSE}/{$ENDIF} sowie {$REGION}/{$ENDREGION} hervorheben. |
| `highlight.exitPoints` | boolean | `true` |  | Ausstiegspunkte der Routine sowie Kopf und Ende der Schleife bei Break/Continue hervorheben. |
| `highlight.exitKeywords` | array<string> | `["Exit","raise","Abort","Halt"]` |  | Was als Ausstiegspunkt gilt; eigene Routinen, die immer eine Exception auslösen, lassen sich ergänzen. |

## inlayHints

| Schlüssel | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|
| `inlayHints.parameterNames` | boolean | `true` |  | Parameternamen vor den Argumenten eines Aufrufs. |
| `inlayHints.inferredTypes` | boolean | `true` |  | Abgeleiteter Typ hinter var X := …. |
| `inlayHints.endMarkers` | boolean | `true` |  | Hinter dem end langer Blöcke anzeigen, was dort endet. |
| `inlayHints.endMarkerMinLines` | integer | `20` | 1… | Mindestlänge eines Blocks in Zeilen für eine Endmarkierung. |

## format

| Schlüssel | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|
| `format.indentSize` | integer | `2` | 1…16 | Breite einer Einrückungsebene. |
| `format.useTabs` | boolean | `false` |  | Mit Tabs statt Leerzeichen einrücken. |
| `format.keywordCase` | string | `"preserve"` | `"preserve"`, `"lower"`, `"upper"` | Schreibweise reservierter Wörter. |
| `format.trimTrailingWhitespace` | boolean | `true` |  | Leerzeichen am Zeilenende entfernen. |
| `format.insertFinalNewline` | boolean | `false` |  | Datei mit einem Zeilenende abschließen. |
| `format.spaceAroundAssignment` | boolean | `true` |  | Genau ein Leerzeichen vor und nach :=. |
| `format.spaceAfterComma` | boolean | `true` |  | Genau ein Leerzeichen nach Kommas. |
| `format.endOfLine` | string | – | `"lf"`, `"crlf"` | Zeilenenden vereinheitlichen; ohne Angabe bleiben sie. |

## Beispiel

```json
{
  "$schema": "https://raw.githubusercontent.com/xKnockOut/Argus/main/Editors/VSCode/schemas/argus.schema.json",
  "project": "App.dproj",
  "config": "Debug",
  "platform": "Win64",
  "rules": { "empty-except": "error" },
  "exclude": ["ThirdParty/**"]
}
```
