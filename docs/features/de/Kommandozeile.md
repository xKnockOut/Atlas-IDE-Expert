# Kommandozeile

Zurück zum [README](../../../README_DE.md)

| Parameter | Bedeutung |
|---|---|
| `--log <Datei>` | Logdatei, wird fortgeschrieben |
| `--log-level <Stufe>` | `debug`, `info` (Standard), `warning`, `error`; gilt für Logdatei und `window/logMessage` |
| `--trace <Datei>` | Mitschnitt aller JSON-Nachrichten (`-->` empfangen, `<--` gesendet) |

Werte gehen auch mit `=` (`--log=server.log`). `--stdio` und `--clientProcessId`, die Editoren anhängen, werden ignoriert.

`AtlasServer.exe --clear-cache` löscht alle Index-Caches unter `%LOCALAPPDATA%\Atlas`, die keine laufende Instanz nutzt. Der Ordner wird ohnehin auf 1024 MB begrenzt (`index.cacheMaxMb`), die am längsten nicht benutzten Caches gehen zuerst.

## Linter-Modus

`AtlasServer.exe --check <Ziel>` prüft ohne Editor. Das Ziel kann eine `.dproj` (Hauptdatei und Units), ein Ordner (alle `.pas`, `.dpr` und `.dpk` darunter) oder eine Datei sein. `atlas.json` im Ordner des Ziels gilt wie im Editor. Fehlt sie, gilt die frühere `delphi-lsp.json` (ebenso `delphi-lsp-baseline.json` für die Baseline).

Der Linter lädt denselben Symbolindex wie der Editor (#1112): das Projekt des Ziels und mit `index.projectGroup` die übrigen Projekte der Gruppe, aus dem Index-Cache, wenn er aktuell ist. Regeln, die Typen aus anderen Units brauchen (etwa der Besitz von Feldern, deren Typ anderswo deklariert ist, oder `case` über eine Aufzählung aus einer anderen Unit), melden darum dasselbe wie in der IDE. Ohne Projektdatei prüft er ohne Index (Hinweis auf stderr). Der MCP-Server prüft mit demselben Index (`get_diagnostics`, `check_code`, `explain_finding`); solange er noch lädt, sagt `get_diagnostics`, dass Befunde, die den Index brauchen, noch fehlen können.

### Laufzeit

- Ein Prüflauf wertet jede Unit einmal aus und teilt das Ergebnis mit allen Regeln (#1322).
  - Vorher extrahierten Regeln, die für viele Ausdrücke den Typ erfragen (Besitz, Typumwandlungen, typisierte Ausdrücke), die ganze Unit bei jeder Frage neu, und große Units brauchten quadratisch lange.
  - In der IDE kostete das bei jeder Änderung ebenfalls CPU.
- Das Token an einer Position sucht Atlas binär statt ab Dateianfang (#1323); auch das machte große Konstanten-Arrays quadratisch.
- Suchen, die ein Prüflauf ständig wiederholt, beginnen nicht mehr von vorn (#1342):
  - Projekt-Units und die Typsuche über die uses-Units laufen über Namenstabellen und werden je Resolver gemerkt.
  - Ja/Nein-Fragen an den Symbolindex enden beim ersten Treffer.
  - Token-Suchen springen binär an den Anfang ihres Bereichs.

Gemessen mit dem Linux-Bau (vorher → #1322 → #1323), Befunde unverändert:

| Projekt | vorher | #1322 | #1323 |
|---|---|---|---|
| SynEdit | 353 s | 135 s | 113 s |
| VirtualTreeView | 676 s | 93 s | 78 s |
| HtmlViewer | 987 s | 708 s | 116 s |

Ein Prüflauf über die Atlas-Quellen selbst (1.917 Units, Linux-Bau) brauchte 912 s und braucht jetzt 594 s, weiter auf einem Kern und mit denselben Befunden.

### Parameter

| Parameter | Bedeutung |
|---|---|
| `--no-index` | ohne Symbolindex prüfen (schneller, aber Regeln, die andere Units brauchen, schweigen) |
| `--index-cache <Ordner>` | Ordner für den Index-Cache statt `%LOCALAPPDATA%\Atlas`, z. B. ein Cache-Ordner, der zwischen CI-Läufen erhalten bleibt |
| `--format <Art>` | `text` (Standard, wie Compilermeldungen), `json`, `sarif` (SARIF 2.1.0 für GitHub Code Scanning) |
| `--output <Datei>` | Ergebnis in eine Datei statt auf stdout |
| `--rules <a,b>` | nur diese Regeln, z. B. `syntax` |
| `--units <a,b>` | nur diese Units: Name oder Glob-Muster für Pfade |
| `--min-severity <S>` | `hint`, `info`, `warning`, `error` |
| `--locale <de\|en>` | Sprache der Texte (#1458); ohne Angabe `language` aus `%APPDATA%\Atlas\settings.json`, sonst Englisch |
| `--fail-on <S>` | ab welchem Treffer der Exit-Code 1 ist: `error` (Standard), `warning` oder `never`. So brechen Warnungen in Altprojekten keinen Pre-Commit-Hook ab |
| `--source-root <Ordner>` | Wurzel der SARIF-Pfade; Standard ist die Git-Wurzel über dem Ziel, sonst der Ordner des Ziels. Pfade darunter tragen `uriBaseId` `%SRCROOT%`, Dateien außerhalb erscheinen als absoluter `file:`-URI |
| `--profile <Name>` | Regelprofil (`standard`, `fast`, `strict`, `security`, `style` oder eigenes aus `profiles`); geht `profile` in `atlas.json` vor |
| `--baseline <Datei>` | bekannte Treffer ausblenden; ohne Angabe gilt `atlas-baseline.json` neben `atlas.json`, falls vorhanden. Der Editor blendet sie ebenso aus |
| `--update-baseline` | Baseline aus den aktuellen Treffern neu schreiben, Exit-Code 0. Auf stderr stehen zuerst die Einträge ohne Datei mit Pfad (umbenannte, verschobene oder gelöschte Dateien; sie fallen heraus), dann die Zähler: Treffer, Dateien, neu, entfernt, unverändert |
| `--changed [<Basis>]` | nur Dateien, die sich laut Git (bzw. SVN, siehe unten) gegenüber der Merge-Base mit `<Basis>` (Standard `main`) geändert haben; geänderte `.dfm`/`.fmx` prüfen ihre Unit, geänderte `.inc` alle Units, die sie einbinden, geänderte `.dproj`/`.dpk`/`.dpr`/`atlas.json` alles |
| `--diff <Ref>` | wie `--changed`, aber direkt gegenüber `<Ref>` |
| `--include-uncommitted` | mit `--changed`/`--diff` auch Index, Arbeitsverzeichnis und neue Dateien |
| `--changed-lines` | nur Treffer in geänderten Zeilen; zusammen mit der Baseline nur neue Treffer in geänderten Zeilen |
| `--fix <Regeln\|all>` | Sammelkorrektur (#1352): wendet die sicheren Korrekturen der Regeln an (Konfidenz ab `fix.minConfidence`, Vorgabe hoch; nur Regeln mit `safeFix` im Katalog, keine Korrektur mit Auswahl), überlappende von hinten nach vorn in bis zu drei Durchgängen; eine Datei, die danach mehr Syntaxfehler hätte, bleibt unverändert. Schreibt alle geänderten Dateien oder keine, in ihrer Kodierung und mit ihren Zeilenenden. Es gelten `--units`, `--changed`, `--diff`, `--changed-lines` (nur Treffer in geänderten Zeilen), `--baseline` (deren Treffer bleiben) und `--profile`. Zusammenfassung auf stderr (Korrekturen je Regel, übersprungen nach Konfidenz, unsicher, Konflikt); Exit-Code 1, wenn danach noch Treffer `--fail-on` erreichen |
| `--fix-dry-run` | mit `--fix`: nichts schreiben, nur den vereinigten Diff ausgeben (stdout oder `--output`) |
| `--timings [<Datei>]` | Zeitprofil des Laufs (#1356): Indexzeit, die 10 langsamsten Units und Regeln (Summe ms, Aufrufe) und Speicher je Bereich, als Markdown bzw. mit Endung `.json` als JSON; ohne Datei auf stderr. Die Treffer auf stdout bzw. `--output` bleiben dieselben (heißt `--timings`, weil `--profile` das Regelprofil wählt) |
| `--suppression-stats` | statt der Treffer: wie oft jede Regel per `lsp-ignore` unterdrückt wird (häufigste zuerst, mit ungenutzten), als Text oder JSON; Exit-Code 0 |
| `--metrics` | statt der Treffer: Code-Metriken je Methode (Länge, Verschachtelungstiefe, zyklomatische und kognitive Komplexität, Parameter, Operanden, lokale Variablen, Ausstiege; #66, #980) mit den Grenzwerten aus `atlas.json` (`"max"` der Regeln `metric-*`); `--format text` schreibt einen Markdown-Bericht, `json` die Metrikdaten; Exit-Code 0 |
| `--todos` | statt der Treffer: offene TODO-Einträge (#68) aus `// TODO`, `// FIXME` und dem Format der IDE-To-Do-Liste `{ TODO 1 -oPerson -cKategorie : Text }` mit Priorität, Person und Kategorie; weitere Marken über die Option `"keywords"` der Regel `todo-comment`; `--format text` schreibt eine Markdown-Übersicht, `json` die Daten; Exit-Code 0 |
| `--architecture <Datei>` | statt der Treffer: Architekturübersicht (#1118) des Ziels aus `--check` (ohne `--check` des aktuellen Ordners) als `.html` (eigenständige Karte zum Zoomen mit Tabellen) oder `.md`: Teilsysteme, zentrale Units, Zyklen mit Fundstellen, Querverbindungen und Ausreißer; Umfang, Bibliotheks-Units und Ausschlüsse aus `architecture.*` in `atlas.json` bzw. `settings.json`; Exit-Code 0, 3 bei ausgeschalteter Übersicht; `.json` speichert den Stand für einen Vergleich (#1121) |
| `--compare <alt.json>` | mit `--architecture`: vergleicht mit einem gespeicherten Stand (#1121) und gibt die Abschnitte als Text aus (oder nach `--output`); Exit-Code 1, wenn eine Art aus `--fail-on newCycle,newCrossLink,subsystemChange,centralGrowth` vorkommt (Vorgabe `architecture.failOn`), 3 bei unlesbarem Stand |
| `--affected-tests [<Basis>]` | statt der Treffer: betroffene Tests der Änderungen gegenüber der Merge-Base mit `<Basis>` (Git, Standard `main`) bzw. der Revision (SVN, Standard `BASE`), mit `--include-uncommitted` samt Index, Arbeitsverzeichnis und neuen Dateien (#1353). Ziel aus `--check` ist das Testprojekt bzw. die Projektgruppe. `--format text` (Tests mit Gründen), `json` (wie `get_affected_tests`) oder `dunitx` (nur das Argument `--run:…` für die Test-EXE, Zusammenfassung auf stderr); `--output` schreibt in eine Datei. Exit-Code 0 mit Liste, 2 wenn alle Tests nötig sind (Testprogramm geändert, Analyse unvollständig), 3 wenn `tests.affected` aus ist |
| `--query "<Abfrage>"` | statt der Treffer: Code-Abfrage (#1351) über das Ziel aus `--check` (ohne Projekt über die Dateien des Ordners), auch `@name` einer gespeicherten Abfrage aus `queries`; `--format text` (Standard), `json` oder `csv`, `--output`; Exit-Code 0, 3 bei einem Fehler in der Abfrage (Meldung mit Spalte auf stderr), unbekanntem `@name` oder `query.enabled` aus |
| `--fail-on-match` | mit `--query`: Exit-Code 1, sobald die Abfrage etwas findet (gilt auch für `@name` mit `failIfAny`) |

Exit-Code: 1, wenn ein Treffer `--fail-on` erreicht (Standard: mindestens ein Fehler), sonst 0; 3 bei Aufruf- oder Lesefehlern. Treffer aus der Baseline zählen nie.

### Baseline (#97)

- Ein Eintrag in `atlas-baseline.json` merkt sich:
  - Datei, Regel
  - die umgebende Routine (voll qualifiziert wie `TFoo.Bar`, außerhalb einer Routine der Abschnitt wie `implementation`)
  - einen Fingerabdruck der Zeile ohne Leerraum
  - einen Fingerabdruck des Codes ±2 Zeilen darum
- Dieselbe Zeile in einer anderen Routine gilt deshalb als neu, ebenso ein Treffer, der in eine andere Routine wandert.
- Neu Einrücken, verschobene Zeilen und eine umbenannte Routine (Kontext gleich, alter Name nicht mehr in der Datei) überstehen die Baseline.
- Eine umbenannte oder verschobene Datei verliert ihre Einträge: Ihre Treffer erscheinen als neu, bis die Baseline aktualisiert ist.
- Ältere Dateien ohne Routine bleiben lesbar und werden beim nächsten Aktualisieren ergänzt.
- Unterdrückungskommentare für Treffer aus der Baseline melden kein `unused-suppression`.
- In Editoren aktualisiert der Befehl `atlas.updateBaseline` (`workspace/executeCommand`, Argument: URI des Projekts oder Ordners) die Baseline und antwortet mit den Zählern; er prüft dafür alle Dateien des Projekts und hält den Server so lange auf.
- In SARIF trägt jedes Ergebnis `partialFingerprints` (`atlasBaseline/v1` aus Regel, Routine und Zeile, `atlasContext/v1` aus dem Kontext, je mit laufender Nummer `:n` bei gleichen Werten in einer Datei).
  - Mit Baseline kommt `baselineState` hinzu: `new`, `unchanged` (als externe Unterdrückung) oder `absent` (Eintrag ohne Treffer).
- Text, JSON und Exit-Code enthalten nur die neuen Treffer.

### SARIF und Konfidenz

In SARIF steht als `message.text` der englische Name der Regel aus dem Katalog, ohne Konfidenz-Zusatz. Die Konfidenz steht in `properties.confidence`, die deutsche Meldung des Treffers in `properties.detail`.

Jeder Regeltreffer hat eine Konfidenz (hoch, mittel, niedrig). Sie begrenzt den Schweregrad, auch wenn `rules` ihn höher einstellt: mittlere Konfidenz höchstens Warnung, niedrige höchstens Hinweis. Treffer unter `minConfidence` (Standard `medium`) bleiben aus. Die Konfidenz steht nie im Meldungstext, sondern als eigene Spalte in der Textausgabe (`[Konfidenz mittel]`), in JSON als `confidence`, im LSP als `data.confidence` und im Tooltip des Plugins als eigene Zeile.

### SVN

- In einer SVN-Arbeitskopie vergleicht `--changed` ohne Basis die Arbeitskopie mit BASE (`svn status`), `--changed <Rev>` und `--diff <Rev>` mit der Revision (`svn diff -r`).
- `--include-uncommitted` nimmt unversionierte Dateien dazu.
- Es gilt die nächstliegende Arbeitskopie über dem Ordner der Konfiguration (`.git` oder `.svn`), bei Gleichstand Git.
- `vcs.provider` in `%APPDATA%\Atlas\settings.json` legt die Art fest (`auto`, `git`, `svn`) oder schaltet ab (`off`).
- svn muss als Kommandozeilenwerkzeug installiert sein (TortoiseSVN mit Kommandozeilenwerkzeugen genügt).
- `vcs.git.path` und `vcs.svn.path` legen das Programm fest (wie auf der Seite *Versionsverwaltung*), `vcs.timeoutSeconds` das Zeitlimit je Aufruf.
- Fehlt die Datei unter einem eigenen Pfad, bricht `--changed` mit dieser Ursache ab.

### Beispiele

Beispiele für einen Pre-Commit-Hook und eine GitHub Action, die nur Geändertes prüfen, und eine GitHub Action, die nur die betroffenen Tests ausführt (nachts alle), liegen in [docs/Beispiele](../../../docs/Beispiele).

### Formatieren ohne IDE

Derselbe Formatierer wie *Dokument formatieren* im Plugin (#1358) läuft ohne IDE, etwa im Pre-Commit-Hook, in der CI oder für Claude Code. Ziel und Auswahl wie bei `--check` (`.dproj`, Ordner oder Datei, `--units`, `--changed`/`--diff`, `--include-uncommitted`, Ausschlüsse aus `atlas.json`). Es gelten die Formatregeln des Projekts: `format.*` aus `atlas.json` über `.editorconfig` über den Vorgaben. Die Einrückung aus den Editor-Optionen der IDE kennt die Kommandozeile nicht; wer sie überall gleich haben will, setzt `format.indentSize` und `format.useTabs`.

| Parameter | Bedeutung |
|---|---|
| `--format-check` | formatiert im Speicher und vergleicht; je abweichende Datei die ersten fünf Abweichungen mit Zeile und Art (`Einrückung 3 statt 2` = ist 3, soll 2; `Leerzeichen vor := fehlt`; ``Schreibweise `Begin` ``; `Leerzeichen am Zeilenende`; `Zeilenumbruch`; `Zeilenenden LF statt CRLF`); mit `--format json` alle Abweichungen (Zeilen ab 1, Art als Kennung wie `indent`), mit `--format diff` der vereinigte Diff. Exit-Code 1 bei einer Abweichung, einem Syntaxfehler oder instabiler Formatierung, sonst 0 |
| `--format-write` | schreibt die formatierten Dateien atomar (Nachbardatei, dann ersetzen); Kodierung (UTF-8 mit oder ohne BOM, ANSI) und Zeilenenden bleiben, außer `format.endOfLine` verlangt andere. Exit-Code 1 nur bei Syntaxfehlern oder instabiler Formatierung, 3, wenn eine Datei nicht geschrieben werden konnte |
| `--changed-lines` | mit `--format-check`/`--format-write`: nur die geänderten Zeilen formatieren wie *Auswahl formatieren* (`textDocument/rangeFormatting`); alle anderen Zeilen bleiben Byte für Byte gleich |

Dateien mit Syntaxfehlern werden nicht formatiert und mit Zeile und Meldung genannt. Bereiche zwischen `// atlas-format: off` und `// atlas-format: on` (auch als `{ … }` oder `(* … *)`, ohne `on` bis zum Dateiende) bleiben samt dieser Zeilen unverändert, im Plugin wie auf der Kommandozeile. Jeder Lauf formatiert das Ergebnis ein zweites Mal und meldet Dateien, bei denen sich dabei noch etwas ändert.

Für Claude Code formatiert das MCP-Werkzeug `format_code` eine Unit nach denselben Regeln: mit `text` geplanten Code (liefert den formatierten Text, schreibt nichts), sonst die Datei, ganz oder `startLine`..`endLine`; `dryRun` (Vorgabe `true`) zeigt den Diff, `dryRun: false` schreibt wie `apply_code_action` (in der IDE offene Dateien als ein Rückgängig-Schritt). Abschalten über `mcp.disabledTools`.

Beispiele: [Pre-Commit-Hook](../../../docs/Beispiele/pre-commit-formatierung.ps1) mit `--format-check --changed HEAD --changed-lines --include-uncommitted` (mit `ATLAS_FORMAT_WRITE=1` formatiert er selbst) und [GitHub Action](../../../docs/Beispiele/github-action-formatierung.yml) mit dem Diff im Protokoll.

## Prüfregeln

Alle Regeln sind in [docs/Regeln.md](../../../docs/Regeln.md) beschrieben. Einzige Quelle ist der Regelkatalog `Packages/Atlas.Common/Katalog/regelkatalog.json` (englisch) mit der Übersetzung `regelkatalog.de.json`. Nach Änderungen `pwsh Tools/Update-RuleCatalog.ps1` ausführen; die CI prüft mit `-Check`, dass Katalog, Implementierung und Dokumentation übereinstimmen.
