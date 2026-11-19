### Behoben
- Versionsverwaltung im Hintergrund: Aufträge, die beim Schließen eines Fensters oder beim Abmelden eines Moduls noch laufen, werden nach ihrem Ende freigegeben, und das Modul bleibt bis dahin geladen; vorher blieben sie als Speicherrest liegen und konnten nach dem Entladen eine Zugriffsverletzung auslösen (#1961).
