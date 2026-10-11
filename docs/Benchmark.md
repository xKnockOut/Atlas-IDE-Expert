# Benchmark

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
| `--out` | Ergebnisordner (Standard `benchmark/`, nicht versioniert) |
| `--baseline` | Frühere Messung zum Vergleich |
| `--version` | Bezeichnung im Bericht, z. B. `0.1.0` |
| `--no-fail` | Immer Exit-Code 0 |

## Ablauf

1. Start ohne Cache (wird berichtet, hat keinen Zielwert), dann dreimal Start mit Cache. Bereit ist der Server, sobald `workspace/symbol` ein Symbol aus dem Korpus findet.
2. An festen Bezeichnerpositionen aus den Implementierungsteilen: Definition, Vorkommen, Hover, Vervollständigung, Parameterhilfe.
3. Für bis zu 10 Dateien: Syntaxfehler per `didChange` einfügen und die Zeit bis zu `publishDiagnostics` messen.

## Ergebnis

Im Ergebnisordner liegen `benchmark-<Zeit>.json`, `letzte.json` und `bericht.md`. Exit-Code 1, wenn ein p95 den Zielwert überschreitet oder gegenüber `--baseline` um mehr als 20 % und mehr als 5 ms langsamer ist; Exit-Code 2 bei einem Fehler im Ablauf.

Die reinen Funktionen (Statistik, Vergleich, Positionswahl) sind mit `node --test Tools/Benchmark/lib.test.mjs` getestet.
