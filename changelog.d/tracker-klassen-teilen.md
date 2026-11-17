### Geändert
- Fenster „Atlas-Board“, Kommentarfeld, Dialog „An Issue anhängen“ und Ansicht „Entwicklung“ nach Zuständigkeit aufgeteilt: Anordnung des Boards und Tasten des Kommentarfelds liegen ohne VCL im Kern und haben eigene Tests, Zeichnen, Auswahl von Board und Sprint, Kontextmenü der Karten, Quellen des Anhangs, Befehle des Kommentarfelds und Klicks auf Commits sind eigene Klassen. Feste Maße sind benannt. Verhalten unverändert.
### Geändert
- Issue-Tracker intern nach Aufgaben geteilt, ohne geänderte Bedienung: Die Palettensuche (#1270) fragt den Tracker über eine eigene Klasse ab (Entprellen, eine Anfrage zur Zeit, letzte Antwort); die Zeiterfassung (#1267) legt die Zeit über `TAtlasTimeStore` im Kern ab und bucht über eine eigene Klasse.

### Tests
- Ablage der Zeiterfassung: Spannen der Uhr in `time.json`, gesperrte Datei behält die Spannen und meldet nur den ersten Fehlschlag, Abziehen und Setzen, Summe beim Wechsel.
