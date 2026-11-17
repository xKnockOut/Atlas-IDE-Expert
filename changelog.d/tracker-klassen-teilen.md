### Geändert
- Issue-Tracker intern nach Aufgaben geteilt, ohne geänderte Bedienung: Die Palettensuche (#1270) fragt den Tracker über eine eigene Klasse ab (Entprellen, eine Anfrage zur Zeit, letzte Antwort); die Zeiterfassung (#1267) legt die Zeit über `TAtlasTimeStore` im Kern ab und bucht über eine eigene Klasse.

### Tests
- Ablage der Zeiterfassung: Spannen der Uhr in `time.json`, gesperrte Datei behält die Spannen und meldet nur den ersten Fehlschlag, Abziehen und Setzen, Summe beim Wechsel.
