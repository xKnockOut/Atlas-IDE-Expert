### Tests
- Aufwärmer der Index-Cache-Tests ersetzt: Der Fehlergrund eines verworfenen Caches wird im TearDown freigegeben statt erst im nächsten Setup, und der Ressourcentext eines gescheiterten `TFile.Replace` (Wettlauf zweier Schreiber) ist ein benannter Schritt in `Atlas.Tests.FirstUse`.
