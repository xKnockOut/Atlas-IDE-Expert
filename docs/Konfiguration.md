# Konfiguration: atlas.json

<!-- Erzeugt von Tools/Update-ConfigDoc.ps1 aus schemas/atlas.schema.json. Nicht von Hand bearbeiten. -->

Einstellungen für Atlas. Jeder Schlüssel hat genau einen Ort (x-scope): "project" in atlas.json im Projektordner (Atlas › Projekt-Einstellungen), "global" in %APPDATA%\Atlas\settings.json für alle Projekte (Tools › Optionen › Atlas). Ein Schlüssel am falschen Ort wird ignoriert und gemeldet.

Jeder Schlüssel hat genau einen Ort (Spalte „Ort“): Projekt-Schlüssel stehen in `atlas.json` im Projektordner (im Plugin *Atlas › Projekt-Einstellungen*), globale in `%APPDATA%\Atlas\settings.json` für alle Projekte (im Plugin *Tools › Optionen › Atlas*). Ein Schlüssel am falschen Ort wird ignoriert und als Warnung gemeldet. Fehlende Schlüssel nehmen den Standardwert. In der IDE bestimmt die laufende IDE die Delphi-Version (`delphiVersion` gilt dort nicht). Die Prüfregeln stehen in [Regeln.md](Regeln.md).

## Schlüssel

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `delphiVersion` | global (settings.json) | string | – | z. B. `"37.0"`, `"23.0"` | Delphi-Version als Produktnummer ("13", "12", "10.4") oder wie in der Registry ("37.0" für Delphi 13, "23.0" für Delphi 12). Leer: neueste installierte Version. |
| `language` | global (settings.json) | string | `"de"` | `"de"`, `"en"` | Sprache der Meldungen. |
| `encoding` | Projekt (atlas.json) | string | `"utf-8"` | z. B. `"utf-8"`, `"windows-1252"`, `"windows-1250"` | Vorgabe-Kodierung für Dateien ohne BOM, wenn die Erkennung nicht entscheidet (reines ASCII, ungültiges UTF-8): "utf-8" oder eine ANSI-Codepage wie "windows-1250". Binäre Formulare werden nie geändert. |
| `project` | Projekt (atlas.json) | string | – |  | Projektdatei (.dproj) relativ zu diesem Ordner. Leer: automatisch suchen. |
| `config` | Projekt (atlas.json) | string | – | z. B. `"Debug"`, `"Release"` | Build-Konfiguration, z. B. Debug oder Release. |
| `platform` | Projekt (atlas.json) | string | – | z. B. `"Win32"`, `"Win64"` | Zielplattform. |
| `rules` | Projekt (atlas.json) | object | – |  | Prüfregeln einzeln einstellen: Regel-ID → Schweregrad oder Objekt mit "severity" und Optionen. Die Konfidenz eines Treffers begrenzt den Schweregrad auch hier: Bei mittlerer Konfidenz bleibt ein Treffer höchstens eine Warnung, bei niedriger höchstens ein Hinweis, auch mit "error". |
| `profile` | Projekt (atlas.json) |  | `"standard"` | z. B. `"fast"`, `"strict"` | Regelprofil: standard, fast (nur Bugs und Schwachstellen), strict (experimentelle Regeln an, minConfidence low), security, style oder ein eigenes aus "profiles". Als Objekt getrennt für Editor und Kommandozeile. |
| `profiles` | Projekt (atlas.json) | object | – |  | Eigene Regelprofile: Name → { "extends": eingebautes oder eigenes Profil, "categories": nur diese Kategorien, "rules": Regel-ID → Schweregrad }. |
| `overrides` | Projekt (atlas.json) | array<object> | – |  | Pfadregeln: Schweregrade für Dateien, die eines der Glob-Muster treffen, z. B. Tests oder generierten Code herabstufen. Regel-ID "*" steht für alle Regeln; spätere Einträge haben Vorrang. |
| `excludeTests` | Projekt (atlas.json) | boolean | `false` |  | Test-Units und Testprojekte (uses DUnitX.TestFramework, TestFramework oder TestInsight.*) nicht prüfen. |
| `testProfile` | Projekt (atlas.json) | string | – | z. B. `"fast"` | Regelprofil für Test-Units und Testprojekte; leer: wie "profile". |
| `compiler` | global (settings.json) | object | – |  | Compiler-Anbindung (dcc32/dcc64). |
| `vcs` | global (settings.json) | object | – |  | Versionsverwaltung (Git, SVN) für geänderte Dateien, Branch und Revision. |
| `completion` | gemischt, siehe unten | object | – |  | Code-Vervollständigung. |
| `refactoring` | Projekt (atlas.json) | object | – |  | Code, den Atlas erzeugt. |
| `usesCommand` | global (settings.json) | boolean | `true` |  | Eine Zeile "/uses Unit1, Unit2" wird nach Enter gelöscht und die Units kommen ins passende uses. |
| `slashCommands` | global (settings.json) | object | – |  | Schnellbefehle: Eine Zeile, die mit /name beginnt, wird nach Enter ausgeführt und verschwindet. Nach / schlägt die Vervollständigung alle Befehle vor. |
| `sortUses` | Projekt (atlas.json) | boolean string | `false` | `true`, `false`, `"alphabetic"`, `"namespace"` | "uses aufräumen" (source.organizeImports, z. B. beim Speichern) sortiert die uses: true oder "alphabetic" alphabetisch, "namespace" nach Namespace gruppiert (System, Vcl, ... und Units ohne Namespace zuletzt). Achtung: Die Reihenfolge bestimmt die Initialisierung der Units. |
| `usesKeep` | Projekt (atlas.json) | array<string> | `` |  | Units, die "ungenutzte uses entfernen" nie entfernt, zusätzlich zu allen Units mit initialization-Abschnitt. |
| `dfmPropertyRules` | Projekt (atlas.json) | array<object> | `` |  | Eigenschaftsregeln für Formulardateien: Vorgaben für Komponenten-Properties, gemeldet als dfm-property am Feld der Komponente in der Unit. Nicht gespeicherte Properties gelten mit ihrem default-Wert. |
| `memoryBudgetMb` | global (settings.json) | integer | `768` | 0… | Obergrenze für den Symbolindex im Arbeitsspeicher in MB. Darüber werden zuerst die Verwendungen ausgelagert (sie bleiben im Cache auf der Platte), dann Bibliotheks-Units (RTL, VCL) und zuletzt Projekt-Units kompakt gehalten (nur interface-Symbole). 0: unbegrenzt. |
| `index` | gemischt, siehe unten | object | – |  | Umfang des Symbolindex. Standard: alle Projekte der Projektgruppe, alle Units der Projekt-Suchpfade und alle Units der Bibliotheks- und Suchpfade der Delphi-Installation, auch wenn keine Unit sie einbindet. Reihenfolge: aktives Projekt, übrige Projekte, Suchpfade, Bibliothek; alles im Hintergrund, die Bibliothek aus dem gemeinsamen Cache. |
| `requestTimeoutMs` | global (settings.json) | integer | `10000` | 1000… | Zeitlimit für Anfragen in Millisekunden. Länger laufende Anfragen werden abgebrochen und im Log gemeldet. |
| `diagnostics` | global (settings.json) | object | – |  | Anonymisiertes Diagnoselog des Servers (je Anfrage Dauer, Ergebnis und Grundcode, je Lauf Start und Ende mit Grund). Es enthält keine Pfade, keine Projekt-, Unit- oder Bezeichnernamen und keinen Quelltext und lässt sich über „Diagnoselog exportieren“ weitergeben. |
| `highlight` | global (settings.json) | object | – |  | Zusammengehörige Schlüsselwörter hervorheben, wenn der Cursor auf einem steht. |
| `inlayHints` | global (settings.json) | object | – |  | Inlay Hints im Editor. |
| `codeLens` | global (settings.json) | object | – |  | Code Lens im Editor. |
| `hints` | global (settings.json) | object | – |  | Anzeige von XMLDoc-Kommentaren (///) im Hover-Tooltip und im Detailpanel der Vervollständigung des IDE-Plugins. Der Server bereitet die Doku immer vollständig auf; die Werte steuern nur die Anzeige. Ohne Angabe gelten die Werte aus Tools › Optionen › Drittanbieter › Atlas. |
| `stringLiteral` | Projekt (atlas.json) | object | – |  | Code-Aktionen „Als String-Literal“ und „Als Klartext kopieren“. |
| `memberOrder` | Projekt (atlas.json) | object | – |  | Code-Aktion „Klassenmitglieder ordnen“: Reihenfolge der Sichtbarkeitsabschnitte und der Mitglieder darin. |
| `testUnits` | Projekt (atlas.json) | object | – |  | Testunits anlegen und zwischen Unit und Testunit wechseln: Namensmuster, Ordner neuer Testunits und Testprojekt. |
| `minConfidence` | Projekt (atlas.json) | string | `"medium"` | `"low"`, `"medium"`, `"high"` | Regeltreffer unter dieser Konfidenz ausblenden. |
| `exclude` | Projekt (atlas.json) | array<string> | – | z. B. `["ThirdParty/**","Generated/*.pas"]` | Ordner und Dateien, die nicht geprüft werden (Glob-Muster relativ zu diesem Ordner: *, **, ?). |
| `mcp` | gemischt, siehe unten | object | – | z. B. `{"disabledTools":["rename_symbol","apply_code_action"]}`, `{"globalSettings":false}` | MCP-Modus (--mcp) für KI-Assistenten. |
| `format` | Projekt (atlas.json) | object | – |  | Formatierung (Dokument und Auswahl formatieren). Gesetzte Werte haben Vorrang vor .editorconfig. |
| `logLevel` | global (settings.json) | string | `"info"` | `"debug"`, `"info"`, `"warning"`, `"error"` | Mindeststufe der Meldungen im Ausgabefenster und in der Logdatei. Gilt ab dem nächsten Start; die Kommandozeilenoption --log-level hat Vorrang. |
| `logFile` | global (settings.json) | string | `""` |  | Optionale Logdatei des Servers (Rotation bei 10 MB). Gilt ab dem nächsten Start; --log hat Vorrang. |
| `traceFile` | global (settings.json) | string | `""` |  | Optionaler Mitschnitt aller JSON-Nachrichten zur Fehlersuche. Gilt ab dem nächsten Start; --trace hat Vorrang. |

## compiler

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `compiler.onSave` | global (settings.json) | boolean | `false` |  | Nach dem Speichern einer Quelldatei das Projekt im Hintergrund kompilieren und die Meldungen anzeigen. |

## vcs

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `vcs.provider` | global (settings.json) | string | `"auto"` | `"auto"`, `"git"`, `"svn"`, `"off"` | auto: nach gefundener Arbeitskopie (.git oder .svn, die nächstliegende gilt, bei Gleichstand Git). git bzw. svn: nur diese Art. off: ohne Versionsverwaltung. Git und SVN über die Kommandozeile (git bzw. svn, TortoiseSVN mit Kommandozeilenwerkzeugen genügt); fehlt das Programm, meldet Atlas das einmal und arbeitet ohne Versionsangaben weiter. |

## completion

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `completion.matching` | global (settings.json) | string | `"fuzzy"` | `"fuzzy"`, `"prefix"` | Auswahl der Vorschläge: unscharf (Teilfolgen, Kürzel wie TSL für TStringList) oder nur nach Präfix, falls ein Editor nachträglich strikt filtert. |
| `completion.interfaceSection` | Projekt (atlas.json) | string | `"public"` | `"private"`, `"protected"`, `"public"` | Abschnitt der Klasse, in den „Interface implementieren“ die Deklarationen fehlender Interface-Methoden schreibt. |
| `completion.senderCast` | Projekt (atlas.json) | string | `"as"` | `"as"`, `"cast"` | Form der Typumwandlung, wenn nach Sender. ein Member der zugewiesenen Komponenten gewählt wird: "as" schreibt (Sender as TButton), "cast" schreibt TButton(Sender). |
| `completion.offerTryFinally` | global (settings.json) | boolean | `true` |  | Nach Übernahme eines Konstruktors in "Liste := TStringList.Create;" anbieten, den folgenden Code in try…finally mit Freigabe einzuschließen. |
| `completion.freeStyle` | Projekt (atlas.json) | string | `"free"` | `"free"`, `"freeAndNil"` | Freigabe im finally von „Freigabe absichern“: "free" schreibt Liste.Free, "freeAndNil" schreibt FreeAndNil(Liste). |
| `completion.keywords` | global (settings.json) | boolean | `true` |  | Schlüsselwörter passend zur Stelle vorschlagen (in Anweisungen begin, try …, im Klassenrumpf property, private …, nach ":" string, array …), sobald ein Zeichen getippt ist. |
| `completion.postfixTemplates` | global (settings.json) | boolean | `true` |  | Postfix-Vorlagen hinter einem Ausdruck anbieten: Liste.for wird zu for var Item in Liste do, FKunde.notnil zu if Assigned(FKunde) then, dazu tryf, ifa, fmt, nil, not, if, forin, free, try, var, exit und eigene Vorlagen mit "postfix: true". |

## refactoring

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `refactoring.inlineVar` | Projekt (atlas.json) | boolean | `true` |  | Inline-Variablen (for var Item in …, var Name := …) erzeugen, wenn die Delphi-Version sie kennt (ab 10.3). Aus: Atlas trägt die Variable in den var-Abschnitt der Routine ein. |

## slashCommands

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `slashCommands.enabled` | global (settings.json) | boolean | `true` |  | Schnellbefehle auswerten. |
| `slashCommands.disabled` | global (settings.json) | array<string> | `` |  | Abgeschaltete Befehle ohne /, z. B. ["uses"]. usesCommand: false wirkt wie "uses" in dieser Liste. |
| `slashCommands.headerTemplate` | global (settings.json) | string | `""` |  | Vorlage für /header mit den Platzhaltern {unit}, {jahr} und {autor}. Leer: die Vorlage der Regel file-header, sonst ein einfacher Kopf. |

## index

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `index.projectGroup` | global (settings.json) | boolean | `true` |  | Alle Projekte der Projektgruppe indizieren; aus = nur das Projekt der geöffneten Datei. |
| `index.searchPaths` | global (settings.json) | boolean | `true` |  | Alle Units der Projekt-Suchpfade indizieren; aus = nur über uses erreichbare. |
| `index.libraryPaths` | global (settings.json) | boolean | `false` |  | Alle Units der Bibliotheks- und Suchpfade der Installation indizieren (RTL, VCL, Komponenten); aus = nur über uses erreichbare. |
| `index.usages` | global (settings.json) | boolean | `true` |  | Verwendungen der Bezeichner in Projekt-Units mit indizieren (Verwendungsbeispiele); aus = nur Deklarationen, kleinerer Index. |
| `index.exclude` | Projekt (atlas.json) | array<string> | `` | z. B. `["**/Demos/**","**/Samples/**"]` | Ordner oder Dateien, die nicht indiziert werden (Glob-Muster gegen den vollen Pfad: *, **, ?). |

## diagnostics

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `diagnostics.log` | global (settings.json) | boolean | `true` |  | Anonymisiertes Diagnoselog schreiben (%LOCALAPPDATA%\Atlas\Logs\Diagnose). |
| `diagnostics.logDays` | global (settings.json) | integer | `7` | 1…365 | Aufbewahrung des Diagnoselogs in Tagen. |
| `diagnostics.logMapFile` | global (settings.json) | boolean | `false` |  | Zuordnung Kurz-ID (doc#4) → Pfad lokal speichern, nur für die eigene Analyse. Der Export nimmt sie nie mit. |

## highlight

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `highlight.blockPairs` | global (settings.json) | boolean | `true` |  | Blockpaare (begin/end, try/finally/except/end, case/of/end, repeat/until, if/then/else, Typen) und Routinen hervorheben. |
| `highlight.directives` | global (settings.json) | boolean | `true` |  | Zusammengehörige {$IF…}/{$ELSE}/{$ENDIF} sowie {$REGION}/{$ENDREGION} hervorheben. |
| `highlight.exitPoints` | global (settings.json) | boolean | `true` |  | Ausstiegspunkte der Routine sowie Kopf und Ende der Schleife bei Break/Continue hervorheben. |
| `highlight.exitKeywords` | global (settings.json) | array<string> | `["Exit","raise","Abort","Halt"]` |  | Was als Ausstiegspunkt gilt; eigene Routinen, die immer eine Exception auslösen, lassen sich ergänzen. |

## inlayHints

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `inlayHints.parameterNames` | global (settings.json) | boolean | `true` |  | Parameternamen vor den Argumenten eines Aufrufs. |
| `inlayHints.inferredTypes` | global (settings.json) | boolean | `true` |  | Abgeleiteter Typ hinter var X := …. |
| `inlayHints.endMarkers` | global (settings.json) | boolean | `true` |  | Hinter dem end langer Blöcke anzeigen, was dort endet. |
| `inlayHints.endMarkerMinLines` | global (settings.json) | integer | `20` | 1… | Mindestlänge eines Blocks in Zeilen für eine Endmarkierung. |

## codeLens

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `codeLens.metrics` | global (settings.json) | boolean | `true` |  | Kennzahlen über jeder Methode: Länge in Codezeilen, Verschachtelungstiefe, zyklomatische und kognitive Komplexität, Parameteranzahl. Die Grenzwerte stehen bei den Regeln metric-* unter "max". |

## hints

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `hints.xmlDocFull` | global (settings.json) | boolean | `true` |  | XMLDoc vollständig und formatiert zeigen (alle Abschnitte, Verweise, Listen, Code). false: Kurzform wie bisher (Beschreibung auf 4 Zeilen, Bemerkungen auf 3 Zeilen gekürzt). |
| `hints.xmlDocMaxLines` | global (settings.json) | integer | `0` | 0…50 | Höchstzahl der Doku-Zeilen, bevor der Inhalt mit dem Mausrad scrollt (0 = unbegrenzt, nur durch Bildschirm bzw. Popup begrenzt). |

## stringLiteral

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `stringLiteral.style` | Projekt (atlas.json) | string | `"auto"` | `"auto"`, `"multiline"`, `"concat"` | auto: mehrzeiliger String mit ''', wenn die Delphi-Version ihn kennt (ab Delphi 12), sonst Verkettung. |
| `stringLiteral.lineBreak` | Projekt (atlas.json) | string | `"sLineBreak"` | `"sLineBreak"`, `"#13#10"`, `"#10"`, `"space"`, `"none"` | Was bei Verkettung zwischen den Zeilen steht; space z. B. für SQL, das einzeilig ankommen soll. |
| `stringLiteral.maxLineLength` | Projekt (atlas.json) | integer | `0` | 0… | Bei Verkettung lange Zeilen zusätzlich umbrechen (0 = nicht umbrechen). |

## memberOrder

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `memberOrder.sections` | Projekt (atlas.json) | array<string> | `["strict private","private","strict protected","protected","public","published"]` |  | Zielreihenfolge der Sichtbarkeitsabschnitte; nicht genannte kommen ans Ende. |
| `memberOrder.members` | Projekt (atlas.json) | array<string> | `["field","constructor","destructor","method","property"]` |  | Zielreihenfolge der Mitglieder in einem Abschnitt; innerhalb einer Art bleibt die Reihenfolge. |
| `memberOrder.sortFields` | Projekt (atlas.json) | boolean | `false` |  | Abschnitte mit Feldern auch dann verschieben, wenn sich dadurch die Reihenfolge der Felder (Speicherlayout) ändert. |
| `memberOrder.sortPublished` | Projekt (atlas.json) | boolean | `false` |  | Auch published-Abschnitte umsortieren; ihre Reihenfolge bestimmt Streaming und Objektinspektor. |

## testUnits

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `testUnits.pattern` | Projekt (atlas.json) | string | `"{unit}.Tests"` |  | Name der Testunit; {unit} steht für den Namen der getesteten Unit, z. B. "{unit}.Tests" oder "Test.{unit}". |
| `testUnits.folder` | Projekt (atlas.json) | string | `""` |  | Ordner für neue Testunits relativ zur Wurzel; leer: Ordner des Testprojekts. |
| `testUnits.project` | Projekt (atlas.json) | string | `""` |  | Testprojekt (.dproj oder .dpr) relativ zur Wurzel; leer: das Projekt im Arbeitsbereich, dessen .dpr DUnitX oder DUnit verwendet. |

## mcp

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `mcp.disabledTools` | global (settings.json) | array<string> | `` |  | Werkzeuge, die der MCP-Server nicht anbietet, z. B. rename_symbol oder apply_code_action. Im eingeschränkten Modus (--restricted) sind schreibende Werkzeuge immer aus. |
| `mcp.globalSettings` | Projekt (atlas.json) | boolean | `true` |  | Der MCP-Server liest wie der LSP-Server und der Linter die globale Datei %APPDATA%\Atlas\settings.json (z. B. mcp.disabledTools, Index, Hints). false: nur atlas.json, etwa für reproduzierbare Ergebnisse im Team. |

## format

| Schlüssel | Ort | Typ | Standard | Werte | Bedeutung |
|---|---|---|---|---|---|
| `format.indentSize` | Projekt (atlas.json) | integer | `2` | 1…16 | Breite einer Einrückungsebene. |
| `format.useTabs` | Projekt (atlas.json) | boolean | `false` |  | Mit Tabs statt Leerzeichen einrücken. |
| `format.keywordCase` | Projekt (atlas.json) | string | `"preserve"` | `"preserve"`, `"lower"`, `"upper"` | Schreibweise reservierter Wörter. |
| `format.trimTrailingWhitespace` | Projekt (atlas.json) | boolean | `true` |  | Leerzeichen am Zeilenende entfernen. |
| `format.insertFinalNewline` | Projekt (atlas.json) | boolean | `false` |  | Datei mit einem Zeilenende abschließen. |
| `format.spaceAroundAssignment` | Projekt (atlas.json) | boolean | `true` |  | Genau ein Leerzeichen vor und nach :=. |
| `format.spaceAfterComma` | Projekt (atlas.json) | boolean | `true` |  | Genau ein Leerzeichen nach Kommas. |
| `format.endOfLine` | Projekt (atlas.json) | string | – | `"lf"`, `"crlf"` | Zeilenenden vereinheitlichen; ohne Angabe bleiben sie. |

## Beispiel

```json
{
  "$schema": "https://raw.githubusercontent.com/xKnockOut/Atlas/main/schemas/atlas.schema.json",
  "project": "App.dproj",
  "config": "Debug",
  "platform": "Win64",
  "rules": { "empty-except": "error" },
  "exclude": ["ThirdParty/**"]
}
```
