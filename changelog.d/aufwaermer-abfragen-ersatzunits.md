### Behoben
- Vervollständigung mit Ersatz-Units der IDE: Der Namensindex der Import-Vorschläge hielt nach jeder Anfrage die Units des Index fest, mit dem sie lief, bis zur nächsten Anfrage über einen anderen Index. Der Index der Ersatz-Units meldet sich jetzt beim Freigeben ab wie der gemeinsame Index.

### Tests
- Drei Fixtures ohne vorgezogenen Testlauf (`[SetupFixture]`): Abfragen über LSP, gespeicherte Abfragen als Regeln und Ersatz-Units der IDE. Die Testdateien der Abfragen liegen nicht mehr in einer Tabelle, die beim ersten Lesen entstand und erst am Programmende frei wurde.
