### Behoben
- `AtlasServer --check <Projekt>.dproj` prüft wie die IDE mit geöffneter Projektgruppe (#1895, #1112): Liegt die `.groupproj` über dem Ordner des Projekts (etwa `Application/AtlasServer.dproj` unter `Atlas.groupproj`), stehen die übrigen Projekte der Gruppe jetzt im Symbolindex, und Units, die ein anderes Projekt der Gruppe in einen Suchpfad übersetzt, gelten auch vor dem ersten Bau als vorhanden. Bisher fehlten sie (bei `AtlasServer.dproj` 146 statt 4497 Units im Index): Regeln, die Typen anderer Units brauchen, schwiegen, und ohne gebaute DCUs meldete `uses-unit-not-found` die Units der Packages als fehlend. `index.projectGroup` (Vorgabe an) schaltet das wie im Server ab.

### Tests
- `get_diagnostics` mit und ohne geladenen Symbolindex, `--check` mit warmem Index-Cache als Benchmark (#1112).
