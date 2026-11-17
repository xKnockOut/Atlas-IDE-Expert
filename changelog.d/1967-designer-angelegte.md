### Behoben
- Designer: „Label rückgängig“, „Duplizieren rückgängig“ und „Einpacken rückgängig“ löschen nur noch die Komponenten, die das Werkzeug selbst angelegt hat, auch wenn der Benutzer sie inzwischen umbenannt hat; eine neue Komponente unter einem frei gewordenen Namen bleibt stehen (#1967).

### Tests
- Designer: Anlegen und Löschen von „Label erzeugen“, „In Reihe duplizieren“ und „Einpacken in“ laufen über den Vertrag des Designers und sind gegen dessen Fälschung getestet (gelöscht, umbenannt, Container mit Kindern, anderes oder geschlossenes Formular, Löschen verweigert) (#1967).
