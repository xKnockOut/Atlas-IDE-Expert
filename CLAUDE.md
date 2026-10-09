# Hinweise für Claude Code

- Sprache: Kommentare, Doku, Issues und Commit-Nachrichten auf Deutsch.
- Architektur nach dem Konzept „Rollenbasierte Kopplung und Kohäsion“, angewendet in `docs/Architektur.md`. Vor neuen Units dort Benennung (`Ausgabeartefakt.Feature.Rolle.Sache`) und Importregeln prüfen.
- `Argus.Common` ist frei von Windows und VCL, `Argus.Windows` frei von VCL. Nach Änderungen an uses- oder requires-Klauseln `pwsh Tools/Check-PackageDependencies.ps1` ausführen.
- Neue Units immer auch in `.dpk`/`.dpr` und `.dproj` (`DCCReference`) eintragen.
- Delphi-Quelltexte als UTF-8 mit BOM und CRLF speichern.
- Niemals auf stdout schreiben außer über die Protokollschicht. Diagnose über `ILogger`; `pwsh Tools/Check-ConsoleOutput.ps1` prüft das.
- Jede Prüfregel und jede Kernfunktion bekommt DUnitX-Tests in `Tests/`.
