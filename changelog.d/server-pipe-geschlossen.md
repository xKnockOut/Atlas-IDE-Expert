### Behoben
- Sprachserver: Endet die IDE, während der Server noch Anfragen wie workspace/diagnostic bearbeitet, meldet das Protokoll keinen Fehler „Stream-Schreibfehler: Die Pipe wird gerade geschlossen“ mehr. Der Server erkennt die geschlossene Pipe als Ende der Verbindung, verwirft die offenen Antworten und beendet sich wie bei geschlossener Eingabe.
