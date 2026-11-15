### Behoben
- `--check` und der MCP-Modus beantworten `Declared(X)` in `{$IF}` wie der Server über den Symbolindex (FP-Korpus JCL/Indy/ZeosLib). Bisher blieb `Declared(X)` dort unbekannt, beide Zweige galten, und Code wie `{$IF NOT DECLARED(ZEncodeBase64)} … {$ELSE} … {$IFEND}` ergab Syntaxfehler und Folgebefunde.
- `overload-directive-missing`: Eine Implementierung mit `Integer` gehört zur Deklaration mit `Int32` (ebenso `DWORD`/`Cardinal` und die übrigen eingebauten Aliase) und `Unit.Typ` zu `Typ`; bisher meldete die Regel dort ein fehlendes `overload` (Indy, JCL).
- `unreachable-code` meldet ein `repeat`, dessen Rumpf immer mit `Break` oder `raise` endet, nicht mehr als „nie ausgeführt“; unerreichbar ist dort nur `until`, das meldet `loop-runs-at-most-once` (Indy).
- `deref-before-nil-check`: `X := nil; Exit;` im `try` macht die Prüfung `if X <> nil` im `finally` zu einer gültigen Prüfung des neuen Werts (Indy).
- `invalid-var-argument`: `@P` einer Variablen prozeduralen Typs ist für dcc eine Variable und darf an einen `var`-Pointer-Parameter (`HookImport(…, @OldProc)`, JCL).
