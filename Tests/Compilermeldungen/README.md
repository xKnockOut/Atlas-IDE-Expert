# Compilermeldungen: jede dcc-Meldung als eigener Fall

Dieses Testprojekt enthält zu jeder Warnung, jedem Hinweis und jedem Fehler von
dcc, der sich mit Delphi 13 unter Windows gezielt auslösen lässt, einen kleinen
Fall. Damit lässt sich prüfen, welche Compilermeldungen die Regeln von Atlas
schon beim Tippen erkennen, welche sie verpassen und wo sie mehr melden als dcc.

Die Wahrheit ist die echte Ausgabe von dcc. Die erwarteten Codes in den Fällen
sind nur das Ziel; ob ein Fall greift, zeigt erst der Bau.

## Aufbau

| Pfad | Inhalt |
|---|---|
| `Faelle/Cm.<Code>.pas` | ein Fall als Unit, z. B. `Cm.W1036.pas` |
| `Faelle/Cm<Code>.dpr`, `.dpk` | Fälle, die ein Programm oder Paket brauchen (Imagebase, exports, requires …) |
| `Faelle/Cm.Hilfe.*.pas`, `CmNs*.pas` | Hilfsunits ohne eigene Meldung |
| `ohne-fall.txt` | Codes ohne Fall, mit Grund (.NET, Umgebungsfehler, defekte Dateien) |
| `Compilermeldungen.dproj` | nur für den Symbolindex von Atlas: bindet alle Units ein; dcc übersetzt es nicht |
| `atlas.json` | Delphi 13 als Mindestversion, `unused-unit` aus |

Jeder Fall beginnt mit einem Kopf:

```pascal
unit Cm.W1036;

// W1036 Variable might not have been initialized
// Erwartet: W1036
// Plattform: Win64        (optional: nur auf dieser Plattform bauen)
// Schalter: --doc         (optional: zusätzliche dcc-Option)
```

Die Zeile, an der dcc melden soll, trägt `// <- W1036`.

## Bauen und vergleichen

```
pwsh Tools/Build-Compilermeldungen.ps1 -AtlasServer <Pfad zu AtlasServer.exe>
python3 Tools/Compare-Compilermeldungen.py
```

Das Bauskript erzeugt für jeden Fall ein eigenes Projekt unter
`Output/Compilermeldungen/Projekte`, übersetzt es in einer eigenen Scratch-IDE
über `cc.ps1` und schreibt alle dcc-Meldungen nach
`Output/Compilermeldungen/dcc.tsv`. Mit `-AtlasServer` prüft es danach die Fälle
mit `--check` in den Profilen `strict` und `standard`. Einzelne Fälle baut
`-Cases 'Cm.W1*'`, nur eine Plattform `-Platforms Win32`.

Das Vergleichsskript schreibt `vergleich.md` und `vergleich.json` in denselben
Ordner. Je Code, den dcc in der Datei eines Falls meldet, steht dort:

- **erkannt**: Eine Regel von Atlas mit diesem Code (Regelkatalog, `compilerCodes`
  oder „like Xnnnn“) meldet in derselben Datei.
- **anderer Code**: Atlas meldet in derselben Zeile, aber mit einem anderen Code.
- **verpasst**: Atlas meldet nichts dazu.

Dazu kommen Treffer von Atlas mit Compiler-Code, die dcc in dieser Datei nicht
meldet (zusätzlich), und Fälle, in denen dcc den erwarteten Code nicht meldet
(Fall greift nicht; dann den Fall anpassen).

## Neue Fälle

Eine Datei `Faelle/Cm.<Code>.pas` mit Kopf und Marke anlegen und in
`Compilermeldungen.dpr` und `Compilermeldungen.dproj` eintragen. Gibt es zu
einem Code einen Fall, gehört er nicht mehr nach `ohne-fall.txt`.
