### Behoben
- Konsolenausgabe (#581): Atlas fokussiert das Eingabefeld erst, wenn das Programm nach dem Anhängen des Debuggers läuft und die IDE ihr Fenster wieder freigibt. Vorher geschah das sofort nach dem Start, während die IDE ihr Hauptfenster noch sperrte; das warf EInvalidOperation, und nach drei Fehlern schaltete die Sicherung das Debuggen ab, ab dann kam keine Ausgabe mehr an.
