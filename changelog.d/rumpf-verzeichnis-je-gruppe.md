### Behoben
- Regel `duplicate-routine-body`: Das Verzeichnis der Rümpfe entsteht einmal je Projektgruppe statt für jede geprüfte Unit neu. „Projekt prüfen“ und `--check` mit eingeschalteter Regel lesen jede Datei nur noch einmal; vorher wuchs der Aufwand mit dem Quadrat der Unit-Zahl. Die Befunde bleiben dieselben, die weiteren Fassungen im Hover stehen nach Pfad sortiert.

### Geändert
- Selbstprüfung: Methodenlänge und zyklomatische Komplexität laufen auch für Atlas.Common, Atlas.Windows, Application und die Tests; die neun Routinen über den Grenzwerten sind aufgeteilt, die Baseline ist leer und darf nicht wachsen.
