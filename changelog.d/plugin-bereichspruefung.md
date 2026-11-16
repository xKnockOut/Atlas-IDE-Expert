### Geändert
- Plugin-Packages, Atlas.WinBase, AtlasMonitor und AtlasUpdate übersetzen im Debug-Build mit Bereichs- und Überlaufprüfung wie schon Server, Atlas.Common und die Tests. `Tools/Check-RuntimeChecks.ps1` (in der CI) lehnt Projekte ohne diese Prüfungen ab; ausgenommen sind nur die Prüflinge unter `Tests/DccFaelle`, `Tests/Compilermeldungen` und `Tests/Referenzprojekt`.
