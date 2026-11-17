### Behoben
- Stapel in Absturz- und Fehlerberichten: Routinen ohne eigene Zeilenangaben (RTL, Generika) bekamen die Datei und Zeile einer anderen Unit angehängt. Sie erscheinen jetzt ohne Zeile.

### Tests
- Leckbericht mit `ATLAS_LEAK_TRACE=1`: Blöcke, die vor dem Test angelegt wurden und im Test wachsen (Listen, Dictionaries, Zwischenspeicher), erscheinen als „vergrößert“ mit Stapel. Stapel mit einem Rahmen aus Atlas stehen vorn, Stapel nur aus RTL, VCL und DUnitX werden gezählt. Die Map-Datei der Test-EXE wird einmal in `Atlas.Tests.FirstUse` gelesen. Der Stapelbericht wird am Ende des Tests festgehalten; bisher las DUnitX ihn erst ab, als die Aufzeichnung schon dem nächsten Test gehörte, und er blieb leer.
- Leckbericht mit `ATLAS_LEAK_TRACE=1`: Zähler der Haken seit Teststart (Belegungen, Freigaben, Größenänderungen, davon ältere Blöcke) und ob der Haken noch aktiv ist; Belegungen außerhalb des Hauptthreads nennen den Thread.
