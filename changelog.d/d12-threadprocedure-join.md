### Behoben
- Delphi 12: Die KI-Brücke der IDE reicht Arbeit für den Hauptthread als `TThreadProcedure` weiter, wie `TAtlasMainThread.Queue` sie erwartet (E2010 `TThreadProcedure` und `TProc`); ein Test übergibt `string.Join` ein Array aus Strings statt eines Array-Literals mit Char-Literalen (E2251).
