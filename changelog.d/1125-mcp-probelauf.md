### Behoben
- `"project"` aus einer `atlas.json`, die über dem geöffneten Ordner liegt, gilt jetzt relativ zum Ordner der `atlas.json`, wie dokumentiert und wie alle übrigen Pfade dort. Vorher löste der Server den Pfad gegen den geöffneten Ordner auf, fand die Projektdatei nicht und arbeitete ohne Projekt (MCP `fix_findings`: „No project loaded“).

### Tests
- `Tools/Start-McpInspector.ps1` und `Tools/Test-McpTools.ps1` nehmen Argumente auch als JSON (`-ArgumentsJson`), damit typgetreue Aufrufe mit Listen und Objekten aus bash und cmd gehen (#1125). Das Referenzprojekt hat eine eigene `atlas.json`; der MCP-Probelauf läuft dort mit allen Werkzeugen ohne Befund.
