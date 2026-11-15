### Behoben
- Delphi-13-Bau von main-merging: Rückgabetyp von `TAtlasIdeDebugInlineValues.EvaluateOne` passt wieder zur Deklaration, Tracker-Einstellungen binden `Atlas.Core.Tracker.SettingsPlan` ein.
- Designer: Der Rahmen um eine Gruppe begann unter Delphi bei (0, 0), weil `TRect.Union` ein leeres Rechteck mitnimmt; er umschließt jetzt nur die Mitglieder.
- Willkommensseite: Formatversion des Index-Caches wie im Server (34); die Suche fand sonst keinen Cache.

### Tests
- Methoden-Haltepunkte: einmaliger Speicher der VCL beim ersten Dialog mit gefüllter Liste wird vorab angelegt (Leckmonitor).
