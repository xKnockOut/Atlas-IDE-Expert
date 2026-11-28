### Behoben

- Befunde beim Debuggen (#2962): Auch die Besitz-Marken am Zeilenende („nie freigegeben“) verschwinden, solange ein Programm im Debugger läuft (`problems.hideWhileDebugging`).
- Atlas-Aufrufstapel in schmalem Fenster: Suche, Vergleich und „Kopieren“ brechen in weitere Zeilen um, die Routinen-Spalte füllt die Breite (keine waagrechte Leiste), der Tastenhinweis unten wird mit „…“ gekürzt und zeigt den ganzen Text als Tooltip.
- Exception-Verlauf in schmalem Fenster: nur Klasse und Meldung (Zeit, Anzahl, Stelle, Thread ab 520 Pixel), keine waagrechte Leiste in Liste und Stapel, Klassenauswahl lässt dem Filter Platz, Summe mit „…“.
