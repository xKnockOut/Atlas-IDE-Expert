### Behoben
- KI-Debuggen (#2895): `debug_start` hängt nicht mehr an einem Dialog. Haltepunkte, die nicht greifen werden, meldet die IDE bei einem Start durch den Assistenten in der Antwort (`breakpointWarnings`) statt im Dialog, der auf den Benutzer wartet. Jeder angenommene Debug-Auftrag bekommt eine Antwort, auch wenn der Start abgebrochen wird; danach nimmt die IDE weitere Aufträge an, ohne Neustart. Ein Auftrag, der eintrifft, während ein anderer noch baut, wird mit „beschäftigt“ beantwortet; die Meldung „nicht angenommen“ nennt einen noch offenen früheren Auftrag statt „abgeschaltet“. Bricht ein Teststart ab, gelten die vorübergehenden Startparameter nicht weiter.
- `debug_start` mit `test` ohne `project` startet das Testprojekt, das den Test enthält, statt des aktiven Projekts; `Fixture.Methode` wird zum vollen Namen `Unit.Fixture.Methode` ergänzt.

### Neu
- `debug_start` und `build_project` machen das genannte Projekt zum aktiven der Projektgruppe und öffnen ein Projekt, das in keiner IDE offen ist, nach der neuen Einstellung `mcp.openProjects` (`ask` mit Rückfrage, `always`, `never`).
