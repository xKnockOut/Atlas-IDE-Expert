### Behoben
- Delphi-13-Bau von main-merging: Rückgabetyp von `TAtlasIdeDebugInlineValues.EvaluateOne` passt wieder zur Deklaration, Tracker-Einstellungen binden `Atlas.Core.Tracker.SettingsPlan` ein.
- Designer: Der Rahmen um eine Gruppe begann unter Delphi bei (0, 0), weil `TRect.Union` ein leeres Rechteck mitnimmt; er umschließt jetzt nur die Mitglieder.
- Willkommensseite: Formatversion des Index-Caches wie im Server (34); die Suche fand sonst keinen Cache.

### Tests
- Methoden-Haltepunkte, Formular-Eigenschaften und Objektzählung: einmaliger Speicher der RTL/VCL bei erster Benutzung wird in `[SetupFixture]` vorab angelegt, der Leckmonitor schrieb ihn je nach Teil des Gesamtlaufs dem ersten Test zu.
