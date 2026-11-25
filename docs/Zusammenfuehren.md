# Pull Requests zusammenführen

Viele Pull Requests laufen gleichzeitig gegen den Integrationsbranch `main-merging`. Damit ein Merge die übrigen nicht jedes Mal konfliktbehaftet macht, ändert ein Pull Request die Stellen nicht mehr, die alle gemeinsam haben, und die übrigen Konflikte löst ein Skript.

## Was ein Pull Request nicht anfasst

| Stelle | Stattdessen |
|---|---|
| `CHANGELOG.md` | Eintrag als Fragment in `changelog.d/` (Aufbau in `changelog.d/README.md`). Der Release übernimmt die Fragmente. Die CI meldet neue Einträge direkt in `CHANGELOG.md` als Fehler. |
| Vertragsversion `cAtlasCoreContractVersion` | Steigt höchstens einmal je Release. Steht sie noch auf dem Wert des letzten Release-Tags und ändert sich ein Vertrag von Base, auf diesen Wert + 1 setzen, sonst stehen lassen. `Tools/Check-ContractVersion.ps1` prüft das in der CI. Keine neue Zeile in der Versionsliste im Kommentar. |
| Pakettabelle im README (Spalten Umfang und Units) | Neue Funktionen als Aufzählungspunkt unter „Features“ bzw. „Funktionen“ und auf der Funktionsseite in `docs/features`. Die Spalte Units erneuert `Tools/Set-Version.ps1` beim Release. |
| Erzeugte Dateien von Hand | Nur über ihr Werkzeug ändern: `Tools/Update-ConfigDoc.ps1` (Einstellungsdoku, `*SchemaData.pas`, `ProfileData.pas`, `ScopeData.pas`), `Tools/Update-RuleCatalog.ps1` (Regeldoku, `Rules.Catalog.Data*.pas`, Regelzahlen im README). |

Erzeugte Dateien tragen in `.gitattributes` die Markierung `linguist-generated`; GitHub klappt sie im Diff zu.

## Ablauf vor dem Push

1. Arbeit committen.
2. `python3 Tools/Merge-Integration.py` mergt `origin/main-merging` ein (flache Klone vertieft es selbst) und löst:
   - erzeugte Dateien: Stand von `main-merging`, danach neu erzeugt mit den beiden Werkzeugen oben (braucht `pwsh`; fehlt es, nennt das Skript die Befehle und endet mit Code 2),
   - reine Ergänzungen beider Seiten an derselben Stelle in `.dpr`, `.dpk`, `.dproj`, `Tools/Linux/FpcTests.txt`, der Unit-Zuordnung `Tools/UnitAssignment*.tsv` (danach wieder nach Package und Unit sortiert) und Markdown (Unit-Listen, Tabellenzeilen, Aufzählungen): beide behalten,
   - Markdown-Zeilen, die sich nur in Zahlen unterscheiden: Stand von `main-merging`, die Regelzahlen erzeugt `Update-RuleCatalog.ps1` neu,
   - die Baseline wortgleicher Rümpfe `atlas-duplicates.json`: Stand von `main-merging`, danach neu geschrieben mit `AtlasServer --check . --check-duplicates --update-baseline` (gebauter Server unter `Output/` oder im PATH; fehlt er, nennt das Skript den Befehl und endet mit Code 2).
   - die Liste der Aufwärm-Routinen `Tools/TestWarmUps.baseline.json`: Stand von `main-merging`, danach neu geschrieben mit `pwsh Tools/Check-TestWarmUps.ps1 -Update`.

   Wer Kopien zusammenlegt, schreibt die Baseline mit demselben Befehl neu und checkt sie mit ein; sonst scheitert der Schritt „Wortgleiche Rümpfe“ der CI an den toten Einträgen. Neue Kopien gehören nicht in die Baseline: `Tools/Check-Baselines.ps1` vergleicht sie je Gruppe mit `main-merging` und meldet jede neue Gruppe und jede Gruppe mit mehr Fassungen, auch wenn die Summe sinkt. Das Merge-Skript nennt solche Gruppen schon beim Neuschreiben. Gibt es einen Grund, eine Kopie zu behalten, steht er in der Beschreibung des Pull Requests in einer Zeile `Neue Kopien: <Grund>`; danach den Lauf der Prüfung neu starten, die Befunde werden dann zu Warnungen.

   Dasselbe gilt für die Klassengröße (`metric-class-size`, Grenzwert 40). Muss eine Korrektur einer vollen Klasse ein Mitglied hinzufügen, etwa kurz vor einem Release, ist ein Umbau an Ort und Stelle der falsche Zeitpunkt. Dann darf der Pull Request die Klasse in die Baseline ihres Packages aufnehmen (`AtlasServer --check Packages/<Package>/<Package>.dproj --update-baseline`, im Diff nur diesen Eintrag behalten) und trägt je Klasse eine Zeile in der Beschreibung:

   ```
   Größere Klasse: TAtlasStructureFrame – Korrektur des Takts vor dem Release, Teilung im nächsten Meilenstein
   ```

   `Tools/Check-Baselines.ps1` lässt die Summe der Einträge zu `metric-class-size` dann je begründeter Klasse um einen steigen und nennt Name und Grund als Warnung; die Klasse muss in einer Datei mit einem solchen Eintrag deklariert sein, Zeilen ohne Grund und doppelte Namen zählen nicht. Die Ausnahme ist befristet: Für die Teilung gibt es ein Issue im nächsten Meilenstein, und sie entfernt den Eintrag wieder; die Baseline darf wie jede andere nur schrumpfen. Häufen sich solche Einträge bei einer Art von Klasse, ist der Grenzwert für diese Art falsch, nicht die Klasse. Einen Record nur zum Senken der Zahl einzuführen, ist kein Ausweg (`docs/Regeln.md`, `metric-class-size`).

   Was übrig bleibt, sind echte Konflikte (beide Seiten ändern dieselbe Zeile, Quelltext, JSON). Das Skript nennt sie und lässt den Merge offen; von Hand lösen, `git add`, `git commit --no-edit`.
3. Prüfungen wie gewohnt (`pwsh Tools/Check-*.ps1`, FPC-Bau und -Tests), dann pushen.
4. Pull Request nach `main-merging` öffnen und das automatische Zusammenführen einschalten (Merge-Methode „Merge commit“). GitHub führt ihn zusammen, sobald die Pflichtprüfung grün ist. Ein Pull Request muss dafür nicht auf dem neuesten Stand von `main-merging` sein; GitHub prüft in der CI ohnehin den Stand nach dem Merge.
5. Meldet GitHub danach doch einen Konflikt, Schritt 2 wiederholen und pushen. Ein neuer CI-Lauf ist dann nur für den eigenen Pull Request nötig.

Nach jedem Merge laufen die Prüfungen und der FPC-Bau auch auf `main-merging`. Bricht dort etwas, das in beiden Pull Requests einzeln grün war (zwei Änderungen passen inhaltlich nicht zusammen), behebt das der Pull Request, der zuletzt gemergt wurde.

## Automatischer Abgleich

Der Workflow „PRs abgleichen“ (`.github/workflows/pr-abgleich.yml`, Skript `Tools/CI/Abgleich-PRs.py`) läuft nach jedem Push auf `main-merging` und alle 30 Minuten. Er sieht sich jeden offenen Pull Request nach `main-merging` von einem Branch `claude/…` an (keine Entwürfe):

- Ohne Konflikt bleibt der Pull Request unangetastet. Auto-Merge braucht keinen aktuellen Stand, und ein Push würde nur die CI neu starten.
- Hat er einen Konflikt mit `main-merging`, oder ändern beide Seiten Quellen erzeugter Dateien (`schemas/`, `Setup/Profile/`, `Packages/Atlas.Common/Katalog/`), mergt der Workflow `main-merging` mit `Tools/Merge-Integration.py` ein und pusht das Ergebnis auf den Branch (nur mit dem Secret `ABGLEICH_TOKEN`, siehe unten). Danach laufen die Prüfungen des Pull Requests neu. Ohne das Secret bekommt der Pull Request stattdessen Label und Kommentar, und der Thread gleicht selbst ab.
- Bleibt ein echter Konflikt, bekommt der Pull Request das Label „Konflikt mit main-merging“ und einen Kommentar mit den offenen Dateien. Den Konflikt löst der Thread wie in Schritt 2 oben. Das Label verschwindet beim nächsten Lauf ohne Konflikt.

Der Workflow pusht nie mit `--force`. Hat der Thread inzwischen selbst gepusht, versucht es der nächste Lauf erneut. Umgekehrt holt `Tools/Merge-Integration.py` vom Abgleich gepushte Commits (`origin/<eigener Branch>`) vor dem Merge von `main-merging` selbst ein, damit der nächste Push des Threads nicht als „non-fast-forward“ scheitert. Wer ohne das Skript pusht, holt den Branch vorher mit `git pull --no-rebase` ein.

## Rotes main-merging

Scheitert „Package-Abhängigkeiten“ oder „AtlasServer für Linux“ nach einem Push auf `main-merging`, legt der Job `melden` (`Tools/CI/Melde-Integrationsstand.py`) ein Issue mit Label „main-merging rot“ an und kommentiert den Pull Request, dessen Merge den Stand erzeugt hat. Weitere rote Läufe kommentieren das Issue; der erste grüne Lauf danach schließt es.

## Units umbenennen

Units umbenennen oder verschieben nur mit `python3 Tools/Rename-Units.py <Tabelle.tsv>` (je Zeile `alt<TAB>neu[<TAB>Zielordner]`, `--dry-run` zeigt nur). Das Skript verschiebt Unit, Formular und Testunits (`alt.Tests` → `neu.Tests`) mit `git mv` und zieht Namen und Pfade in allen versionierten Textdateien nach: uses-Klauseln, qualifizierte Bezeichner, `.dpk`, `.dpr`, `.dproj`, `atlas.json`, Baselines, Skripte, Doku und die Unit-Zuordnung `Tools/UnitAssignment*.tsv` (danach wieder sortiert). `CHANGELOG.md`, Release-Notizen und die übrigen ADRs bleiben, wie sie sind. Ein Pfad wird nur ersetzt, wenn er auf die verschobene Datei zeigt; was sich nicht zuordnen lässt, meldet es als Warnung. Danach `pwsh Tools/Check-PackageDependencies.ps1`, bei geänderten Fingerabdrücken die Baselines neu schreiben (`--update-baseline`), und mit Delphi bauen: FPC übersetzt die IDE-Packages nicht.

## Konstante Arrays

`Tools/Check-ConstArrays.py` (in `check`) vergleicht die Elemente jeder Konstante `array[<Aufzählung oder Bereich>] of …` mit der Aufzählung. Delphi bricht bei einer Abweichung ab (E2072); FPC übersetzt Plugin-Units mit VCL nicht und merkt es dort nicht. Wer einer Aufzählung einen Wert hinzufügt, ergänzt alle Namenslisten dazu.

## Prüfzeit

Die drei Pflichtprüfungen `check`, `bauen` und `fpc-tests` sammeln nur Ergebnisse oder laufen selbst kurz; die eigentliche Arbeit verteilt sich auf gleichzeitige Jobs. So bestimmt der längste Teil die Dauer, nicht die Summe, und die Namen im Branch-Schutz bleiben gleich.

- „Package-Abhängigkeiten“: `pruefungen` (alle Check-Skripte nacheinander, etwa acht Minuten) und `modulgrenzen` (Selbsttest der Modulgrenzen `Tools/Test-PackageDependencies.ps1`, fünf Teile über `-Shard`/`-Shards`). `check` ist grün, wenn beide grün sind. Der Selbsttest ruft je Fall die ganze Prüfung auf (etwa zwei Minuten je Fall, nacheinander über 40 Minuten). Im Pull Request läuft er nur, wenn sich die Prüfung selbst, die Verträge in Base oder der Workflow ändern oder Units unter `Packages` gelöscht oder verschoben werden. Nach jedem Merge auf `main-merging` läuft er immer.
- „AtlasServer für Linux“: `server` übersetzt den Server (etwa sechs Minuten) und reicht ihn als Artefakt weiter. `pruefen` prüft damit in vier Jobs: drei Teile der Plugin-Packages (`ATLAS_SHARD` in `Tools/Linux/Check-PluginPackages.sh`, verteilt nach Zahl der Units; Base ist allein ein Teil) und ein Teil mit Metriken, Kopien und Regex-Probe. `bauen` ist grün, wenn Bau und alle Teile grün sind, und ersetzt auf `main` danach das Release `cloud-linux`. Parallel laufen die DUnitX-Tests unter FPC in `fpc-tests`.
- Ändert ein Pull Request nur Module (`Packages/Atlas.IDE.<Modul>`, nicht Base) und daneben nur Doku, Changelog-Fragmente, Workflows oder Prüfskripte unter `Tools/` (außer `Tools/Linux`), prüft `pruefen` nur diese Module (`--seit` in `Check-PluginPackages.sh`). Module verwenden nur Base und Base kein Modul; deshalb ändern sich die Befunde anderer Packages dabei nicht. Nach dem Merge auf `main-merging` prüft der Lauf alle Packages.
- Beide Workflows halten je Branch einen laufenden und höchstens einen wartenden Lauf. Folgen mehrere Merges auf `main-merging` kurz hintereinander, prüft der Lauf danach den letzten Stand; ein rotes Ergebnis meldet `Tools/CI/Melde-Integrationsstand.py` am zuletzt gemergten Pull Request.
- FPC trunk kommt aus dem Zwischenspeicher; die Paketquellen werden bei einem Aussetzer bis zu viermal angefragt.

## Einstellungen des Repositorys

- Branch-Schutz für `main-merging`: Pflichtprüfungen `check` (Workflow „Package-Abhängigkeiten“) sowie `bauen` und `fpc-tests` (Workflow „AtlasServer für Linux“), „Require branches to be up to date before merging“ aus. Nur `bauen` und `fpc-tests` übersetzen den Quelltext; ohne sie als Pflicht führt Auto-Merge auch Pull Requests zusammen, die unter FPC nicht übersetzen, und `main-merging` wird rot. Mit dieser Einstellung an verlangte GitHub nach jedem Merge von allen anderen Pull Requests einen neuen Merge und einen neuen CI-Lauf.
- „Allow auto-merge“ an (Settings › General › Pull Requests), damit Schritt 4 möglich ist.
- Eine Merge Queue gibt es auf GitHub nur für Repositorys von Organisationen; für dieses Repository übernimmt das automatische Zusammenführen ihre Rolle. Beide Pflicht-Workflows hören schon auf `merge_group` und prüfen dort wie nach einem Merge alles. Liegt das Repository einmal in einer Organisation, genügt die Einstellung „Require merge queue“ im Branch-Schutz von `main-merging` (Merge-Methode „Merge commit“, Pflichtprüfungen wie oben); `Tools/Merge-Integration.py` bleibt für Konflikte nötig, denn die Queue löst keine.
- Secret `ABGLEICH_TOKEN` (Settings › Secrets and variables › Actions): fein granuliertes Personal Access Token nur für dieses Repository mit den Rechten Contents, Pull requests und Workflows, jeweils „Read and write“. Nur damit pusht der Abgleich. Pushes mit `GITHUB_TOKEN` taugen nicht: Die Pull-Request-Läufe danach warten auf Freigabe, per `workflow_dispatch` nachgestartete Prüfungen zählen für Auto-Merge nicht (der Pull Request bleibt „blocked“, obwohl alle Pflichtprüfungen grün sind), und Änderungen an `.github/workflows` darf `GITHUB_TOKEN` nicht pushen.
