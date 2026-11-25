### Behoben
- Hover-Tooltip: Ein Klick auf einen Typ im Tooltip hielt die IDE an, bis der Server antwortete, und meldete bei beschäftigtem Server „Fehler in Tooltip: ELspTimeoutError“. Der Inhalt kommt jetzt im Hintergrund; der Tooltip bleibt angeheftet stehen, eine verspätete Antwort nach Zurück oder einem neuen Tooltip wird verworfen, und bleibt sie aus, steht nur eine Zeile im Protokoll.
