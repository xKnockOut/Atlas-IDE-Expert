### Behoben
- `field-not-freed`: Ein Feld, das mit einem Komponenten-Parameter der Methode als Owner erzeugt wird (`TFoo.Create(AOwner)`), gehört diesem Owner und wird nicht mehr gemeldet.
- `security-hardcoded-credential`: In einem `case`-Zweig (`xbToken: AValue := ...`) gilt die zugewiesene Variable als Ziel, nicht die Marke des Zweigs.
- `blocking-call-in-main-thread`: `WaitFor` bleibt still, wenn der Thread nachweislich fertig ist (`if not X.Finished then Exit` davor oder innerhalb von `if X.Finished then`).
- `writeln-in-gui-app`: Still in Routinen, die ohne Konsole vorher aussteigen (`if not IsConsole then Exit`), und in Programmen, die mit `AllocConsole`/`AttachConsole` selbst eine Konsole öffnen.
- `thread-loop-without-terminated`: Eine Schleife mit eigenem Ausstieg (`Break` dieser Schleife, `Exit`) wird nicht mehr gemeldet.
- `winapi-uses-missing`: Still in Quelltext, der Units nur von Free Pascal einbindet (`BaseUnix`, `Unix`, `cthreads` usw.).
- `conditional-directive-unbalanced`: Ein Programm mit `{$MODE …}` außerhalb jedes bedingten Zweigs ist Quelltext für Free Pascal; seine FPC-Direktiven gelten nicht mehr als unbekannt.
