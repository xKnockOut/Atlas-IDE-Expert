### Behoben
- Hänger beim Bauen und beim Anmelden der Module (bis 1,5 s je Mal): Die Frage, ob ein Modul eingeschaltet ist, schrieb jedes Mal alle Einstellungen in einen Zwischenspeicher. Sie liest jetzt nur noch die Liste der ausgeschalteten Module, die bei jeder Änderung der Einstellungen neu entsteht.
- Gesperrte oder fehlende Datendateien von Atlas (z. B. während eines Builds) werden ohne Ausnahme übergangen; jede Ausnahme kostete in der IDE einige hundert Millisekunden.
