# Benchmark

*English version: [Benchmark.md](en/Benchmark.md)*

`Tools/Benchmark/bench.mjs` misst die Leistungs-Zielwerte (#85) am echten Server über stdio. Benötigt Node 18 oder neuer.

| Vorgang | Zielwert (p95) |
|---|---|
| Gehe zu Definition, Vorkommen hervorheben | < 50 ms |
| Hover, Vervollständigung, Parameterhilfe | < 100 ms |
| Syntaxfehler nach Tastendruck | < 200 ms |
| Start mit vorhandenem Index-Cache | < 2 s |

## Ausführen

```
node Tools/Benchmark/bench.mjs --server Output\Win64\Release\Bin\AtlasServer.exe --baseline benchmark\letzte.json
```

| Option | Bedeutung |
|---|---|
| `--server` | Server-EXE, Standard `Output\Win64\Release\Bin\AtlasServer.exe` |
| `--corpus` | Ordner mit Quelltexten, mehrfach möglich; Standard `Tests/Referenzprojekt`. Für den großen Korpus zusätzlich die VCL-Quellen, z. B. `--corpus "C:\Program Files (x86)\Embarcadero\Studio\37.0\source\vcl"`. Der erste Ordner ist die Arbeitsbereichswurzel. |
| `--samples` | Anzahl der Messpositionen (Standard 30) |
| `--completion-samples` | Anzahl der Anfragen für die Vervollständigung (Standard 100, #31) |
| `--out` | Ergebnisordner (Standard `benchmark/`, nicht versioniert) |
| `--baseline` | Frühere Messung zum Vergleich |
| `--version` | Bezeichnung im Bericht, z. B. `0.1.0` |
| `--no-fail` | Immer Exit-Code 0 |

## Ablauf

1. Start ohne Cache (wird berichtet, hat keinen Zielwert), dann dreimal Start mit Cache. Bereit ist der Server, sobald `workspace/symbol` ein Symbol aus dem Korpus findet.
2. An festen Bezeichnerpositionen aus den Implementierungsteilen: Definition, Vorkommen, Hover, Parameterhilfe.
3. Vervollständigung (#31) mit warmem Index an eigenen Positionen (Standard 100): zwei Zeichen des Bezeichners getippt, damit wie im Editor die unscharfe Auswahl (#229) und Symbole aus nicht eingebundenen Units (#180) mitlaufen; der Client meldet wie RAD Studio `documentationFormat: ["plaintext"]`.
4. Für bis zu 10 Dateien: Syntaxfehler per `didChange` einfügen und die Zeit bis zu `publishDiagnostics` messen.

## Ergebnis

Im Ergebnisordner liegen `benchmark-<Zeit>.json`, `letzte.json` und `bericht.md`. Exit-Code 1, wenn ein p95 den Zielwert überschreitet oder gegenüber `--baseline` um mehr als 20 % und mehr als 5 ms langsamer ist; Exit-Code 2 bei einem Fehler im Ablauf.

Die reinen Funktionen (Statistik, Vergleich, Positionswahl) sind mit `node --test Tools/Benchmark/lib.test.mjs` getestet.

## Zeit bis „bereit“ bei Projektgruppen (#1479)

`Tools/Benchmark/ready.mjs` misst, wie lange der Index einer Projektgruppe bis „bereit“ braucht, mit mehreren Läufen je Fassung. Der erste Lauf einer Fassung steht getrennt (Umstieg: er liest noch die Caches der vorigen), Median und Spannweite gelten für die übrigen.

Ohne IDE, mit `AtlasServer --check` über alle Projekte der `.groupproj` im Zielordner (derselbe Weg wie im Server: gemeinsamer Index, Stufen, Caches):

```
node Tools/Benchmark/ready.mjs --server vor=C:\Messung\vor\AtlasServer.exe --server nach=Output\Win64\Release\Bin\AtlasServer.exe --target C:\Projekte\Gruppe --unit Haupt.dpr --runs 6 --cache %TEMP%\atlas-ready
```

In der IDE: Diagnoselog an (`diagnostics.log`), IDE je Lauf neu starten, Gruppe öffnen, warten bis „bereit“, IDE schließen. Jeder Start schreibt eine Datei `diag-<Tag>-<Prozess>.log` (Ordner `%LOCALAPPDATA%\Atlas\Logs\Diagnose`, Vorgabe an). Die Dateien je Fassung in einen eigenen Ordner legen, dann:

```
node Tools/Benchmark/ready.mjs --logs vor=C:\Messung\vor --logs nach=C:\Messung\nach --out bereit.md
```

Gemessen wird vom ersten `index project#N start` bis zum letzten `index project#N done` (abgebrochene Aufbauten zählen nicht); die Konsole nennt zusätzlich die Zeit ab der ersten Zeile des Logs. „Speicher“ ist der größte `mem`-Wert der Index-Zeilen; Gipfel und Speicher nach dem Laden zeigt das Fenster „Atlas-Server“.

| Option | Bedeutung |
|---|---|
| `--server Name=Pfad` | Fassung und Server-EXE, mehrfach; gemessen in dieser Reihenfolge auf demselben Cache |
| `--target` | Ordner mit der `.groupproj` (Standard: aktueller Ordner) |
| `--unit` | Eine Datei für `--units`, damit nach dem Index nur wenig geprüft wird |
| `--runs` | Läufe je Fassung (Standard 6: Umstieg und fünf weitere) |
| `--cache` | Ordner des Index-Caches (`--index-cache`); ohne Angabe der des Servers |
| `--logs Name=Ordner` | Statt zu messen: Diagnoselogs je Fassung auswerten, mehrfach |
| `--out` | Tabelle zusätzlich in diese Datei schreiben |

Die Auswertung ist mit `node --test Tools/Benchmark/ready-lib.test.mjs` getestet.
