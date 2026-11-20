### Neu
- Prüfregel `register-does-work` (#2752): meldet `Register`-Routinen von Packages, die Arbeit starten (Timer, Threads, Formulare, `Sleep`, `WaitFor…`, `ShellExecute`, `TTask.Run`), auch über Hilfsroutinen, die nur von dort aufgerufen werden. Einstellbar mit `workCalls`, `workClasses` und `entries` (eigene Einstiegsroutinen wie `*.RegisterModule`).
