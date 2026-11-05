# Offene Punkte für die Cloud

Stand 05.11.2026, Branch `Pilot-2.0.0-beta.1`. Reihenfolge nach Priorität. Die Delphi-IDE steht in der Cloud
nicht zur Verfügung: Änderungen sind dort nicht übersetzt. Sie brauchen danach einen Bau und Testlauf am Rechner.
Beim Bau von Pascal-Code darauf achten: Parameterlose Funktionen, die Prozedurtypen liefern, mit `()` aufrufen
(E2010), und jede verwendete Unit direkt in die uses-Liste aufnehmen. Der GitHub-Stand war deshalb nicht baubar.

## 1. Absturzzählung zählt fremde IDE-Prozesse

**Problem:** Atlas wertet jede Sitzungsmarke, deren Prozess nicht mehr lebt, als Absturz
(`TAtlasSessionFiles.TakeCrashed`). Abgewürgte Bau-IDEs und parallele Instanzen führen so zu Stufe Safe
(`Crash`, `RepeatedCrash`), obwohl nichts abgestürzt ist.

**Plan:** Prozesse mit gesetzter Umgebungsvariable (z. B. `ATLAS_NO_SESSION_MARKER=1`) schreiben keine Marke und
werten keine fremden aus. Das Skript `cc.ps1` (Claude-Compile, außerhalb des Repos) setzt `CLAUDE_COMPILE_OWNED`
beim Start der Bau-IDE; die neue Variable gehört dorthin und muss am Rechner ergänzt werden.

**Stellen:** `Atlas.IDE.Diagnostics.SafeMode.pas` (`Start`, `WriteMarker`, `ReadSessions`),
`Atlas.Core.Diagnostics.SafeMode.pas`.

**Fertig:** Test, dass eine Sitzung mit der Variable weder Marke schreibt noch den Zähler erhöht.

## 2. Verlorene Known Packages

**Problem:** Am 05.11.2026 zwischen 05:34 und 06:31 standen nur noch Base, die 11 Module fehlten unter
`HKCU:\Software\Embarcadero\BDS\37.0\Known Packages`. Ursache unbewiesen. Atlas selbst entfernt Einträge nur im
Updater (`TUpdateKnownPackages`). Verdacht: Mehrere parallele IDEs nutzen denselben Schlüssel, eine schreibt die
Liste beim Beenden zurück.

**Aufgabe:** Prüfen, ob sich das erhärten lässt; beim Start fehlende Module im Log melden und, falls vertretbar,
wiederherstellen.

## 3. Absturz 06:31:15 in `Atlas.Core.Diagnostics.MainThread`

**Problem:** Zugriffsverletzung (Zeile 129) aus einem eingereihten Eintrag, passt zu einem Modul, das entladen
wurde, während der Eintrag wartete.

**Aufgabe:** Eingereihte Einträge entladener Module verwerfen.

## 4. Leckmeldungen der Tests

**Stand:** 11282 Tests, 0 fehlgeschlagen; `TESTEXIT 1` nur durch Leckmeldungen. Vor dem Merge gab es keine. Die
meisten sind Erstbenutzung (Caches, Registry) und treffen den ersten Test einer Fixture. Zwei Aufwärmungen sind
ergänzt (`WarmUpSettingsPage`, `TRuleFindingsMemoTests.WarmUp`).

**Bekannte Meldungen vor dieser Ergänzung:** `EnglishTextsWithoutGerman` (23136 Bytes),
`TimingNamesExecutedCommand` (5016), `FailingProviderTripsOnlyItself` (208), `GuardErrorLineHidesMessage` (208),
`ExceptionCountsForFeature` (192), `SecondLockFails` (176), `FetchErrorsCountPerProvider` (168),
`ShowsAndReenablesTrippedFeatures` (88), `ServicesStartWithoutLoading` (72), `HandlerWritesInlineValues` (72).

**Aufgabe:** Je Fall klären, ob Erstbenutzung oder echtes Leck. Erstbenutzung per `[SetupFixture]` vorwegnehmen,
echte Lecks beheben. Keine Leckmeldung pauschal ignorieren.

## 5. Sprache ohne `language`-Eintrag

**Problem:** Ohne `"language"` in `settings.json` kamen die Serverbefunde auf Deutsch eingestelltem System
englisch. Der Server selbst wählt richtig (LSP-Test mit `locale` de und en). Verdacht: Das Plugin schickt beim
Start nicht `de`.

**Stellen:** `InterfaceLocale` in `Atlas.IDE.CodeInsight.Manager.Session.pas`, `TAtlasStrings.Language`,
`TLspClientLocale.FromInitialize`, `TShellSettings.SetLoose`.

**Aufgabe:** Klären, wann `TAtlasStrings.Language` gesetzt wird und ob `OpenSession` davor laufen kann.

## 6. Spitzen der Willkommensseite (zurückgestellt)

700 bis 1025 ms im Hauptthread beim Projektöffnen und Fensterwechsel, dazu Hänger mit Atlas-Beteiligung. Im
Leerlauf ist die Seite still. Aus der Diagnose: Messzeilen `Willkommensseite` und
`Willkommensseite: Aktualisieren`.

## 7. Fehlalarme der Prüfregeln

- `method-without-self` bei Interface-Methoden
- `handle-leak` über `Result`
- `field-not-freed` bei Records
- `unused-suppression`

## 8. Kleinere Reste

- `kette/release-build.ps1` auf das Modul-Layout umstellen (liegt außerhalb des Repos, am Rechner erledigen).
- Handtests zu den neuen Funktionen: `docs/Atlas-Testfaelle.md`.

## Am Rechner zu prüfen, nicht in der Cloud

- Glühbirne an `FMouseHooks` in `Core.Host.pas` (XML-Inspector): Commit `c3f1829b2`, Rückmeldung steht aus.
- `Atlas.Common.Logging.RotatingFileStream.pas`: lokale, uncommittete Änderung (entfernter `lsp-ignore`-Kommentar).
- Stashes `b61bf8b30` und `137e94fac` sichten.
