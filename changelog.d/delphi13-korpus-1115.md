### Behoben
- Delphi-Bau von main-merging: Parser bindet `Atlas.Text.Lines` ein (H2443 `Before`), Test der Rümpfe in Include-Dateien ruft `IncludeReader()` mit Klammern auf (E2010).

### Tests
- Referenzprojekt: Die Mutation für `deref-before-nil-check` holt das Formular jetzt per `FindComponent`; seit der Ausnahme für frisch erzeugte Objekte (pasvulkan) meldet die Regel `Create` davor zu Recht nicht mehr.
