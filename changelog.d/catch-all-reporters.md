### Geändert
- Prüfregel `catch-all-without-raise`: neue Option `reporters` (Aufrufe, die eine Ausnahme melden, z. B. `TAtlasGuard.*` oder `*Logger.Error`; ein Block mit einem davon gilt als behandelt) und `allowExceptionUse` (ein Handler, der seine Ausnahme weiterreicht, gilt als behandelt); `AcquireExceptionObject` zählt wie `raise`. Die Regel meldet jetzt auch einen `except`-Teil ohne `on`, der weder auslöst noch meldet. In Atlas selbst gilt sie damit auch für das Plugin und die Anwendungen.

### Behoben
- Zeiterfassung im Tracker: Ohne Schreibrecht im Ordner der Sperrdatei wartet das Speichern nicht mehr bei jedem Takt zwei Sekunden im Hauptthread, sondern meldet den Fehlschlag sofort; gewartet wird nur noch, solange eine andere IDE die Sperre hält.
