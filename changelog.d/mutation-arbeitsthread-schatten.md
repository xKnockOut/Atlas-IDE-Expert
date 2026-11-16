### Behoben
- Mutationslauf (#1460): Ein Testprogramm, das sich nicht beenden lässt, hält die IDE beim Schließen oder Entladen des Testmoduls nicht mehr auf; der Lauf wartet höchstens die übliche Zeitgrenze. Units ohne Formular lassen sich wieder prüfen (fehlende .dfm/.fmx brach das Anlegen des Schattenprojekts ab).
- Mutationslauf: Das Schattenprojekt legt seine DCUs immer in seinen eigenen Ordner, auch wenn das Testprojekt keinen Ausgabeordner nennt; eine Unit aus dem Schattenprojekt selbst wird abgewiesen, statt sich selbst zu überschreiben.
