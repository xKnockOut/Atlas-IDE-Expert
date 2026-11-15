### Behoben
- Fehlalarme aus dem Korpuslauf über fremde Delphi-Projekte (OpenDSS, PascalCoin):
  - Der Lexer liest Gleitkommazahlen ohne Nachkommastellen (`0.`, `25.`) als eine Zahl; vorher meldete die Syntaxprüfung den Punkt als Fehler. `A(.1.)` und `1.ToString` bleiben, wie sie sind.
  - `conditional-directive-unbalanced` meldet Symbole wie `DELPHI10.2_TOKYO_UP` nicht mehr als ungültig, wenn sie mit einem gültigen Bezeichner beginnen.
  - `possibly-uninitialized` kennt die Methoden eines Records aus einer anderen Unit über den Index.
  - `loop-runs-at-most-once` nimmt einen Aufruf nur noch als sicher auslösend an, wenn jede Routine dieses Namens auslöst und keine `Exit` enthält, und unterscheidet eigene Aufrufe von Methoden anderer Typen.
  - `type-mismatch` (E2009) vergleicht keine Signaturen mehr, deren Parameter unter bedingten Direktiven stehen.
  - `winapi-uses-missing` übergeht Erwähnungen in inaktiven Zweigen (`{$IFDEF MSWINDOWS}` unter Linux).
  - `constant-expression-error` rechnet typisierte Konstanten (`Starttag: Word = 0`) nicht mehr als echte Konstanten aus.
  - `property-accessor-invalid` findet den Besitzer einer Eigenschaft in einer generischen Klasse neben einer gleichnamigen nicht generischen.
