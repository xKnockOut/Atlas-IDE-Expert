### Geändert

- Datenmenge als Tabelle (#3024): Steht das Programm im Bearbeiten (`dsEdit`/`dsInsert`), lässt sich der aktuelle Datensatz ändern; Atlas setzt den Wert nur im Bearbeitungspuffer, Post oder Cancel bleiben beim Programm. Andere Datensätze sind mit verständlichem Hinweis gesperrt.

### Behoben

- „Ändern fehlgeschlagen“ in der Datenmengen-Tabelle nennt jetzt den Schritt und die Antwort des Debuggers statt eines leeren Grunds.
- Wert ändern in der Datenmengen-Tabelle scheiterte, weil Delphi `AsString` (Eigenschaft mit Setter) nicht ändert; Atlas ruft dann den Setter auf.
