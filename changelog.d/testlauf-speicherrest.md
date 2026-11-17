### Tests
- Speicherrest beim Beenden ist ein Kriterium des Testlaufs: Im Debug-Build scheitert Atlas.Tests, wenn am Ende mehr belegt ist als erlaubt (`TShutdownLeaks.Expect`, ausgewertet auch von `Tools/Build-Test.ps1`). Bekannte Einmal-Belegungen stehen mit ihrem Besitzer in `Atlas.Tests.FirstUse`; neue `[SetupFixture]`-Aufwärmer verhindert `Tools/Check-TestWarmUps.ps1`.
