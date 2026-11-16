### Geändert
- JSON-Ausgaben maskieren Strings überall nach derselben Regel (`TJsonText.Quote`): Umlaute bleiben lesbar und `/` wird nicht mehr als `\/` geschrieben, auch in gespeicherten Einstellungen (Tracker-Verbindungen und -Abfragen, Versionsverwaltung, TODO-Marken, Startprofile, Testlisten), im MCP-Schema und im Protokoll der letzten Nachrichten. Listen von Strings baut überall `TJsonBuild.Strings`; eine Prüfung im Build erkennt neue Kopien an ihrer Form statt am Namen.

### Behoben
- Experimentelle Einstellungen: Das Lesen eines Textwerts gab ein JSON-Objekt nicht frei (Leck).
