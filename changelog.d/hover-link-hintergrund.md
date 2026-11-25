### Behoben
- Hover-Tooltip: Ein Klick auf einen Typ im Tooltip hielt die IDE an, bis der Server antwortete, und meldete bei beschäftigtem Server „Fehler in Tooltip: ELspTimeoutError“. Der Inhalt kommt jetzt im Hintergrund; der Tooltip bleibt angeheftet stehen, eine verspätete Antwort nach Zurück oder einem neuen Tooltip wird verworfen, und bleibt sie aus, steht nur eine Zeile im Protokoll.
- Referenzen („Verwendungen“ im Tooltip, Brotkrumen, Befehl „Referenzen suchen“): Die Suche über das Projekt hielt die IDE bis zur Antwort an. Sie läuft jetzt im Hintergrund, das Ergebnisfenster füllt sich, sobald die Antwort da ist; eine neue Suche währenddessen ersetzt die laufende.
- Ergebnisfenster: Implementierungen, Aufrufer/Aufrufe, Vorfahren/Nachfahren, Datenfluss und das Aufklappen von Hierarchie, Aufrufdiagramm und Datenfluss hielten die IDE bis zur Antwort des Servers an. Sie laufen jetzt im Hintergrund; ein Knoten zeigt „…“, bis seine Ebene da ist, und von mehreren Befehlen kurz hintereinander zählt der letzte.

### Geändert
- Fehlerantworten des Servers, die auf einen Fehler im Server deuten (etwa ein interner Fehler), stehen bei Hintergrundanfragen jetzt im Fehlerprotokoll statt nur im Protokoll. Still bleiben Zeitlimit, Abbruch, veralteter Stand, begründete Ablehnung und eine beendete Verbindung.
