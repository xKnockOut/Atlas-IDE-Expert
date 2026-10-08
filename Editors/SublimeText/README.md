# BetterDelphiLSP in Sublime Text

1. Über Package Control das Paket **LSP** installieren. Für Pascal-Hervorhebung zusätzlich ein Pascal-Paket wie **Pascal** oder **Delphi** installieren, das `.pas`, `.dpr` und `.dpk` als `source.pascal` erkennt.
2. `LSP.sublime-settings` in die LSP-Benutzereinstellungen übernehmen.
3. `Delphi-Formular.sublime-syntax` in den Ordner `Packages/User` kopieren (Preferences > Browse Packages…). Damit erhalten `.dfm`-Dateien den Scope `source.dfm`.
4. Liegt `BetterDelphiLSP.exe` nicht im `PATH`, bei `command` den vollen Pfad eintragen.

Prüfen lässt sich die Verbindung mit „LSP: Toggle Log Panel“.
