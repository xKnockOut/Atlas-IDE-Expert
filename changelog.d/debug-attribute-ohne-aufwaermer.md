### Tests
- Test der Debug-Attribute ohne Aufwärmer: Er liest die Attribute nicht mehr über `TRttiContext`, dessen Zwischenspeicher bis zum Beenden lebt, sondern prüft eigene Instanzen; die Anwendung auf einen Typ prüft weiter der Compiler.
