# 0013: AtlasServer unter Linux mit Free Pascal für Cloud-Sitzungen

- Status: Angenommen
- Datum: 2026-10-23
- Bezug: #1109, ADR 0002 Package-Aufteilung, ADR 0008 Plattformen

## Kontext

Claude Code läuft in Cloud-Sitzungen in einem Linux-Container. Das Atlas-Plugin für Claude Code (`Editors/ClaudeCode/atlas`) startet dort den Befehl `AtlasServer.exe`; den gab es nur als Windows-Programm, also scheiterte der MCP-Server mit „Executable not found in $PATH“ und Claude arbeitete in Cloud-Sitzungen ohne Atlas.

Delphi selbst übersetzt in der Starter-Edition nur für Windows. Free Pascal (FPC) kann Delphi-Quelltext im Modus `delphi` übersetzen; erst die Entwicklungsfassung (trunk, 3.3.1) kennt Methodenreferenzen und anonyme Methoden, die der Server überall nutzt.

## Entscheidung

- **Linux-Bau mit FPC trunk** in einem festen Stand (`FPC_COMMIT` in `Tools/Linux/Build-AtlasServer.sh`). Das Skript baut FPC einmalig (Startcompiler FPC 3.2.2 aus `fp-compiler`), bereitet den Quelltext mit `Tools/Linux/Convert-ForFpc.py` auf und übersetzt nach `Output/Linux64/Bin/AtlasServer`. Ein Fingerabdruck des Quelltexts verhindert unnötige Neubauten.
- **Die Aufbereitung ist rein mechanisch** (Unitnamen, Kopfzeile mit Modeswitches, Schreibweisen, die FPC anders liest); sie ändert keine Logik. Was FPC fehlt, steht in `Tools/Linux/Compat` (`DelphiCompat`, `AtlasIOUtils`). Der Quelltext im Repository bleibt Delphi-Quelltext.
- **Platform-Package `Atlas.Linux`** (nur Quelltext, kein `.dpk`): Gegenstücke zu den Adaptern aus `Atlas.Windows`, die der Server braucht (Konsole, Elternprozess, Prozessliste, Dateibeobachtung, kanonische Pfade, Compileraufruf, Diagnose, Delphi-Installation als „keine“).
- **`Shell.Platform`** im Server wählt an einer Stelle zwischen `Atlas.Windows.*` und `Atlas.Linux.*` (`{$IFDEF MSWINDOWS}`), über gleichnamige Typen und `TShellPlatform`. Die übrigen Shell-Units kennen keine Plattform-Units mehr.
- **Cloud-Sitzungen**: Der SessionStart-Hook `.claude/hooks/session-start.sh` ruft das Bau-Skript mit `--install /usr/local/bin` auf (nur bei `CLAUDE_CODE_REMOTE=true`). Es legt `AtlasServer` und den Verweis `AtlasServer.exe` ab, sodass das Plugin ohne Änderung startet.
- Fehler, die FPC trunk bei Methodenreferenzen intern abbrechen lässt (internal error 2022110601), werden im Quelltext umgangen: Methodenreferenz auf eine Methode eines anderen Objekts oder von `Self` innerhalb einer anonymen Methode als eigene anonyme Methode bzw. lokale Variable schreiben.

## Alternativen

- **Windows-Programm unter Wine**: Wine ist im Container nicht vorhanden, das Programm müsste aus einem Release geladen werden und passte nie zum Stand des Branches.
- **Befehl im Plugin auf `AtlasServer` ändern**: Unter Windows hängt der Start dann davon ab, dass Claude Code `PATHEXT` auswertet; der Verweis `AtlasServer.exe` unter Linux vermeidet jedes Risiko für Windows.
- **Aufbereiteten Quelltext einchecken**: doppelte Pflege; die Umwandlung läuft in etwa einer Sekunde.
- **FPC 3.2.2 aus dem Paket**: kennt keine Methodenreferenzen.

## Folgen

- Claude hat in Cloud-Sitzungen die Atlas-Werkzeuge (MCP und LSP) für den Stand des Branches.
- Der erste Start eines Containers dauert einmalig länger (FPC-Bau etwa 10 Minuten, Server etwa 2 Minuten); danach ist der Stand im Container zwischengespeichert.
- Linux ist keine ausgelieferte Plattform: kein Delphi-Bau, keine Installation, keine Release-Datei. Was nur unter Windows geht (Delphi-Installation, Bauen mit dcc, IDE), meldet unter Linux „nicht verfügbar“.
- Neue Plattform-Units des Servers brauchen ein Gegenstück in `Atlas.Linux` und einen Eintrag in `Shell.Platform`, sonst bricht der Linux-Bau.
