### Behoben
- Absturz der IDE nach dem Entladen von Atlas (beim Beenden oder beim Neuinstallieren), Zugriffsverletzung in einem „unbekannten Modul“: Hielt die IDE den Code-Insight-Manager von Atlas nach dem Abmelden noch, gab sie ihn später frei, als der Code von `Atlas.IDE.Base` schon entladen war. Base bleibt in diesem Fall jetzt bis zum Ende der IDE im Speicher (#2372).
