### Behoben
- Fehlalarme aus dem Korpuslauf über fremde Delphi-Projekte (OpenDSS, PascalCoin):
  - Der Lexer liest Gleitkommazahlen ohne Nachkommastellen (`0.`, `25.`) als eine Zahl; vorher meldete die Syntaxprüfung den Punkt als Fehler. `A(.1.)` und `1.ToString` bleiben, wie sie sind.
  - `conditional-directive-unbalanced` nimmt Symbole wie dcc: Es zählt der Anfang aus Bezeichnerzeichen, auch mit Ziffer vorn (`DELPHI10.2_TOKYO_UP`, `32Bit`, `USE_PDFALEVEL]`).
  - `possibly-uninitialized` kennt die Methoden eines Records aus einer anderen Unit über den Index und Methodenaufrufe auf Record-Feldern (`Container.Bag.AddObject`).
  - `loop-runs-at-most-once` nimmt eine Routine nicht mehr als immer auslösend, wenn ihr Rumpf irgendwo über `Exit` normal zurückkehrt (`repeat … if … then Exit; until …; raise`).
  - `type-mismatch` (E2009) vergleicht keine Signaturen mehr, deren Parameter unter bedingten Direktiven stehen.
  - `winapi-uses-missing` übergeht Erwähnungen in inaktiven Zweigen (`GetTickCount64` im Zweig `{$IFDEF FPC}`).
  - `constant-expression-error` rechnet typisierte Konstanten (`Starttag: Word = 0`) nicht mehr als echte Konstanten aus.
  - `property-accessor-invalid` findet den Besitzer einer Eigenschaft in einer generischen Klasse neben einer gleichnamigen nicht generischen.
