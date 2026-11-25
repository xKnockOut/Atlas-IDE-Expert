### Behoben
- Konsolenausgabe (#581): Beim Start eines Programms mit Umleitung wirft das Fokussieren des Eingabefelds nicht mehr EInvalidOperation, wenn die IDE ihr Hauptfenster gerade sperrt. Vorher schaltete die Sicherung nach drei solchen Fehlern das Debuggen ab; ab dann holte Atlas keine Ausgabe mehr ab.
