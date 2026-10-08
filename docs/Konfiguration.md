# Konfiguration: delphi-lsp.json

<!-- Erzeugt von Tools/Update-ConfigDoc.ps1 aus Editors/VSCode/schemas/delphi-lsp.schema.json. Nicht von Hand bearbeiten. -->

Einstellungen für BetterDelphiLSP im Projektordner.

Die Datei liegt im Projektordner. Fehlende Schlüssel nehmen den Standardwert; Editor-Einstellungen gelten nur, wo die Datei nichts sagt. Die Prüfregeln stehen in [Regeln.md](Regeln.md).

## Schlüssel

| Schlüssel | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|
| `delphiVersion` | string | – | z. B. `"37.0"`, `"23.0"` | Delphi-Version wie in der Registry, z. B. "37.0" für Delphi 13 oder "23.0" für Delphi 12. Leer: neueste installierte Version. |
| `language` | string | `"de"` | `"de"`, `"en"` | Sprache der Meldungen. |
| `project` | string | – |  | Projektdatei (.dproj) relativ zu diesem Ordner. Leer: automatisch suchen. |
| `config` | string | – | z. B. `"Debug"`, `"Release"` | Build-Konfiguration, z. B. Debug oder Release. |
| `platform` | string | – | z. B. `"Win32"`, `"Win64"` | Zielplattform. |
| `rules` | object | – |  | Prüfregeln einzeln einstellen: Regel-ID → Schweregrad oder Objekt mit "severity" und Optionen. |
| `compiler` | object | – |  | Compiler-Anbindung (dcc32/dcc64). |
| `memoryBudgetMb` | integer | `0` | 0… | Obergrenze für den Symbolindex in MB. Darüber werden zuerst Bibliotheks-Units (RTL, VCL), dann Projekt-Units kompakt gehalten (nur interface-Symbole). 0: unbegrenzt. |
| `inlayHints` | object | – |  | Inlay Hints im Editor. |
| `minConfidence` | string | `"medium"` | `"low"`, `"medium"`, `"high"` | Regeltreffer unter dieser Konfidenz ausblenden. |
| `exclude` | array<string> | – | z. B. `["ThirdParty/**","Generated/*.pas"]` | Ordner und Dateien, die nicht geprüft werden (Glob-Muster relativ zu diesem Ordner: *, **, ?). |
| `format` | object | – |  | Formatierung (Dokument und Auswahl formatieren). Gesetzte Werte haben Vorrang vor .editorconfig. |

## compiler

| Schlüssel | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|
| `compiler.onSave` | boolean | `true` |  | Nach dem Speichern einer Quelldatei das Projekt im Hintergrund kompilieren und die Meldungen anzeigen. |

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
  "$schema": "https://raw.githubusercontent.com/xKnockOut/BetterDelphiLSP/main/Editors/VSCode/schemas/delphi-lsp.schema.json",
  "project": "App.dproj",
  "config": "Debug",
  "platform": "Win64",
  "rules": { "empty-except": "error" },
  "exclude": ["ThirdParty/**"]
}
```
