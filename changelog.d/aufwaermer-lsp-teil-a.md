### Behoben
- Glühbirne „Befund als Prompt kopieren“: Regelbeschreibung und Beispiele kommen in der eingestellten Sprache (vorher immer deutsch). Der Server hält dafür keinen zweiten deutschen Regelkatalog mehr (rund 850 KB).

### Tests
- Drei Aufwärmer (`[SetupFixture]`) der LSP-Tests gestrichen: Die Code-Aktionen leeren ihre Einstellungen im TearDown, die Prompt-Aktion nutzt den gemeinsamen Regelkatalog, die Architektur-Tests brauchen keinen mehr.
