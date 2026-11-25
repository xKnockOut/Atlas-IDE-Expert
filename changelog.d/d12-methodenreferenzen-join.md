### Neu
- Prüfregeln für zwei Delphi-12-Fallen, die Free Pascal und Delphi 13 übersetzen: `type-mismatch` meldet eine Variable, einen Parameter oder ein Feld eines Methodenreferenztyps an einem anderen gleich gebauten (`TProc` an `TThreadProcedure`, wie E2010), auch ohne RTL im Index; `overload-resolution` meldet `string.Join` mit einem Char-Literal im Array-Literal (wie E2251) und bietet `TArray<string>.Create(…)` an.

### Behoben
- Delphi 12: Die KI-Brücke der IDE reicht Arbeit für den Hauptthread als `TThreadProcedure` weiter, wie `TAtlasMainThread.Queue` sie erwartet (E2010); der SmartIndent-Test übergibt `string.Join` ein `TArray<string>` (E2251).
