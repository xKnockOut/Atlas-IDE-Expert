### Geändert
- Updates: `AtlasUpdate.exe` erkennt den Herausgeber am Fingerabdruck des öffentlichen Signaturschlüssels statt am Namen; ein signiertes Paket mit gleichem Namen, aber anderem Schlüssel, und eine Signatur ohne lesbaren Herausgeber gelten als fremd bzw. unsigniert.
- Updates: Versionsdatei, Paket und Quelltext lädt `AtlasUpdate.exe` nur von `github.com`, `objects.githubusercontent.com` und `release-assets.githubusercontent.com` (Fehler „Adresse außerhalb von GitHub abgelehnt“).
- Updates: Das Bauen aus dem Quelltext (Delphi ohne fertiges Paket) beginnt nur nach Bestätigung, im Plugin über „Jetzt aktualisieren“ (Zeile „Version“: „wartet auf Bestätigung zum Bauen“), in `AtlasUpdate.exe install` mit „j“. Der Dialog sagt, dass ein so gebautes Update nicht an den Herausgeber gebunden ist; `updates.install = auto` baut nie ohne Frage.
- Packages und Programme tragen eine Versionsressource: Dateiversion (2.3.0-rc.1 = 2.3.0.3001, stabil = .9000), Produktversion als SemVer, Herausgeber und eigene ProgramID; `Tools/Set-Version.ps1` setzt sie, `Tools/Check-Version.ps1` prüft sie.

### Behoben
- Updates: Eine Statusdatei eines früheren Laufs im selben Ordner galt kurz als Ergebnis einer neuen Vorbereitung; `prepare` schreibt den Stand jetzt sofort, und das Plugin löscht den alten vor dem Start.
