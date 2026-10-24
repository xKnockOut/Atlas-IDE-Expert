# Hinweise für Claude Code

- Sprache: Kommentare, Doku, Issues und Commit-Nachrichten auf Deutsch.
- Architektur nach dem Konzept „Rollenbasierte Kopplung und Kohäsion“, angewendet in `docs/Architektur.md`. Vor neuen Units dort Benennung (`Ausgabeartefakt.Feature.Rolle.Sache`) und Importregeln prüfen.
- `Atlas.Common` ist frei von Windows und VCL, `Atlas.Windows` frei von VCL. Nach Änderungen an uses- oder requires-Klauseln `pwsh Tools/Check-PackageDependencies.ps1` ausführen.
- Neue Units immer auch in `.dpk`/`.dpr` und `.dproj` (`DCCReference`) eintragen.
- Delphi-Quelltexte als UTF-8 mit BOM und CRLF speichern.
- Niemals auf stdout schreiben außer über die Protokollschicht. Diagnose über `ILogger`; `pwsh Tools/Check-ConsoleOutput.ps1` prüft das.
- Der Quelltext muss auch mit Delphi 12 übersetzen: kein Bedingungsausdruck `if … then … else`, kein `is not`, kein `not in`. `pwsh Tools/Check-Delphi12.ps1` prüft das.
- Jede Prüfregel und jede Kernfunktion bekommt DUnitX-Tests in `Tests/`; Zeitmessungen mit `[Category('Benchmark')]`. `pwsh Tools/Check-TestCoverage.ps1` prüft, dass jede Unit mit Logik eine Testunit hat und jede Testunit in `Atlas.Tests.dpr` steht.
- Neue Einstellung: Schema `schemas/atlas.schema.json` (mit `x-page`, `x-control`, `x-issue`), Parser, Test; dann `pwsh Tools/Update-ConfigDoc.ps1` ausführen. Es erzeugt Konfiguration.md, Einstellungen.md und die Schema-Unit des Plugins und prüft den Parser.
- Im IDE-Plugin nur über `TAtlasMainThread` in den Hauptthread einreihen, nie `TThread.Queue(nil, …)`/`ForceQueue(nil, …)` (sonst laufen Einträge nach dem Entladen in fremdem Speicher). `pwsh Tools/Check-MainThreadQueue.ps1` prüft das; Ausnahme je Zeile mit `// mainthread-ok` oder `// lsp-ignore: forbidden-symbol` (dieselben Verbote stehen als Regel `forbidden-symbol` in `atlas.json`).

## Mit Delphi bauen vor dem Merge

- Vor jedem Merge nach `main` mit Delphi übersetzen (Win64-Gruppe und Win32-Plugin), Tests grün, 0 Fehler, 0 Warnungen, 0 Hinweise. FPC-Läufe ersetzen das nicht.
- Typische Fallen, die unter FPC durchgehen:
  - `Exit([...])` mit Array-Literal: erst `Result` zuweisen, dann `Exit`.
  - Anonyme Methode als Argument bei Überladungen: typisierte Variable oder eigener Methodenname.
  - Funktion, die eine Methodenreferenz liefert, ohne `()` aufgerufen (E2010).
  - `TMonitor` wird durch `Vcl.Forms` verdeckt: `System.TMonitor` schreiben.
  - `Assert.AreEqual` mit `Length`/`High`: `Integer(...)` darum.
  - DUnitX `Contains`/`DoesNotContain` ignorieren Groß-/Kleinschreibung.
  - `TCaption` hat keine String-Helfer.
  - Controls, die ein Fenster brauchen (`TTabControl.Tabs`, `TListBox.Items`, Text messen), nicht im Konstruktor füllen, sondern in `CreateWnd` bzw. erst mit Fenster.
  - Konstanten, die in Delphis `Winapi.Windows` fehlen (z. B. `ERROR_NOT_FOUND`), selbst deklarieren.
  - Felder nach Methoden im selben Klassenabschnitt (E2169).
  - Fehlende Units für Inline-Funktionen (H2443): `System.Generics.Collections` bei `TJSONArray`/`TJSONObject`, `Winapi.Windows` bei `RenameFile`.
  - Tests: string- und Array-Felder im `TearDown` leeren, sonst meldet der Leckmonitor.
  - Methode direkt auf `TXyz.Create` eines `TInterfacedObject` (`TRegel.Create.Descriptor`): Das Objekt wird nie freigegeben. `(TRegel.Create as IRule).Descriptor` schreiben.
  - Array-Literal vorn in einem Ausdruck ohne Typkontext (`Lines(['a'] + Body)`) liest Delphi als Menge: `TArray<string>.Create('a') + Body`.
  - Zeilen über 1023 Zeichen (F2069), auch in erzeugten Units: lange Literale umbrechen.
  - Zwei öffentliche Typen gleichen Namens in einem Package verdecken sich je nach uses-Reihenfolge.
  - `TArray.Sort`/`TList.Sort` sind nicht stabil: bei Gleichstand eindeutig weitersortieren.
  - Gleitkomma an Int64-Grenzen: Double hat 53 Bit Mantisse (FPC rechnet unter x86 mit Extended).
  - Referenzprojekt und Mutationen: `{$IFDEF WIN32}`/`WIN64`-Zweige sind unter Windows anders aktiv als unter Linux.
  - Anonyme Methode in einer lokalen Variablen, die andere anonyme Methoden derselben Routine einfangen: Der gemeinsame Rahmen hält sich selbst fest (Leck). Die Methodenreferenz in einer eigenen Routine bauen.
  - Zeilenenden CRLF.
