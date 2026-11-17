### Tests
- Tests, die den Fundort von git oder svn vorgeben, stellen den echten danach wieder her (`TAtlasVcsTools.Remember`), statt ihn zu vergessen; der nächste Test, der git sucht, legt ihn so nicht neu an. Die Tabelle der gehaltenen Index-Cache-Sperren gibt ihre Plätze frei, sobald keine Sperre mehr gehalten wird. Die Aufwärmer der Shell-Tests für Hotspots, Linter und Replay entfallen.
