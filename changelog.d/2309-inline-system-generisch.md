### Behoben
- inline-not-expanded meldet keine Fehlalarme mehr bei Routinen aus System und SysInit (`TMonitor.Enter`, `Pos`, `UpCase`: „System fehlt in uses“) und bei direkt gerufenen Mitgliedern generischer Typen (`FListe[I]` auf ein `TObjectList<T>`-Feld einer anderen Unit: „System.Generics.Collections fehlt in uses“). Beides bettet Delphi ohne Eintrag im uses ein (#2309).
