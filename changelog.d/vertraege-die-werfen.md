### Behoben
- Aufgaben: Scheitert der Start eines Prozesses, endet der Lauf als „nicht gestartet“ mit der Fehlermeldung im Ausgabefenster, statt als laufend hängen zu bleiben; ein Build, der auf die Aufgabe wartet, wird gesperrt.
- Mutationstests: Wirft das Öffnen, Schreiben, Bauen oder Ausführen einer Mutante, endet der Lauf mit der Meldung; die bisherigen Ergebnisse bleiben.
- Verknüpftes Umbenennen und Mehrfach-Cursor enden, wenn der Editorpuffer beim Schreiben eine Ausnahme wirft, statt in einem unbekannten Zustand weiterzulaufen.
- Ausdrücke im Debugger: Wirft die Auswertung eines Ausdrucks, zeigt nur dessen Zeile den Fehler; die übrigen Zeilen werden weiter ausgewertet.
- Formulardesigner: Scheitert beim Rückgängigmachen das Löschen einer Komponente, vergisst Atlas die restlichen trotzdem.
- Versionsverwaltung und Tracker: Ein Fehler beim Anzeigen eines Ergebnisses aus dem Hintergrund zählt für das Feature und erreicht die IDE nicht.
- Help Insight der IDE neben dem Atlas-Tooltip: Entschieden wird nach dem Editor unter der Maus, nicht nach dem obersten; scheitert der Wächter, steht das im Protokoll.
- Mausrad auf der Willkommensseite und im Kommentareditor des Trackers im Win64-Debug-Build ohne Bereichsfehler.
- Listen in Dialogen (Einstellungen, Debugger, Tracker, Tests, Suche) flackern im IDE-Stil nicht mehr.
