# Pull Requests zusammenführen

Viele Pull Requests laufen gleichzeitig gegen den Integrationsbranch `main-merging`. Damit ein Merge die übrigen nicht jedes Mal konfliktbehaftet macht, ändert ein Pull Request die Stellen nicht mehr, die alle gemeinsam haben, und die übrigen Konflikte löst ein Skript.

## Was ein Pull Request nicht anfasst

| Stelle | Stattdessen |
|---|---|
| `CHANGELOG.md` | Eintrag als Fragment in `changelog.d/` (Aufbau in `changelog.d/README.md`). Der Release übernimmt die Fragmente. Die CI meldet neue Einträge direkt in `CHANGELOG.md` als Fehler. |
| Vertragsversion `cAtlasCoreContractVersion` | Steigt höchstens einmal je Release. Steht sie noch auf dem Wert des letzten Release-Tags und ändert sich ein Vertrag von Base, auf diesen Wert + 1 setzen, sonst stehen lassen. `Tools/Check-ContractVersion.ps1` prüft das in der CI. Keine neue Zeile in der Versionsliste im Kommentar. |
| Pakettabelle im README (Spalten Umfang und Units) | Neue Funktionen als Aufzählungspunkt unter „Features“ bzw. „Funktionen“ und auf der Funktionsseite in `docs/features`. Die Spalte Units erneuert `Tools/Set-Version.ps1` beim Release. |
| Erzeugte Dateien von Hand | Nur über ihr Werkzeug ändern: `Tools/Update-ConfigDoc.ps1` (Einstellungsdoku, `*SchemaData.pas`, `ProfileData.pas`, `ScopeData.pas`), `Tools/Update-RuleCatalog.ps1` (Regeldoku, `Atlas.Common.Rules.Catalog.Data*.pas`, Regelzahlen im README). |

Erzeugte Dateien tragen in `.gitattributes` die Markierung `linguist-generated`; GitHub klappt sie im Diff zu.

## Ablauf vor dem Push

1. Arbeit committen.
2. `python3 Tools/Merge-Integration.py` mergt `origin/main-merging` ein (flache Klone vertieft es selbst) und löst:
   - erzeugte Dateien: Stand von `main-merging`, danach neu erzeugt mit den beiden Werkzeugen oben (braucht `pwsh`; fehlt es, nennt das Skript die Befehle und endet mit Code 2),
   - reine Ergänzungen beider Seiten an derselben Stelle in `.dpr`, `.dpk`, `.dproj`, `Tools/Linux/FpcTests.txt` und Markdown (Unit-Listen, Tabellenzeilen in `docs/adr/0017-unit-zuordnung.md`, Aufzählungen): beide behalten,
   - Markdown-Zeilen, die sich nur in Zahlen unterscheiden: Stand von `main-merging`, die Regelzahlen erzeugt `Update-RuleCatalog.ps1` neu.

   Was übrig bleibt, sind echte Konflikte (beide Seiten ändern dieselbe Zeile, Quelltext, JSON). Das Skript nennt sie und lässt den Merge offen; von Hand lösen, `git add`, `git commit --no-edit`.
3. Prüfungen wie gewohnt (`pwsh Tools/Check-*.ps1`, FPC-Bau und -Tests), dann pushen.
4. Pull Request nach `main-merging` öffnen und das automatische Zusammenführen einschalten (Merge-Methode „Merge commit“). GitHub führt ihn zusammen, sobald die Pflichtprüfung grün ist. Ein Pull Request muss dafür nicht auf dem neuesten Stand von `main-merging` sein; GitHub prüft in der CI ohnehin den Stand nach dem Merge.
5. Meldet GitHub danach doch einen Konflikt, Schritt 2 wiederholen und pushen. Ein neuer CI-Lauf ist dann nur für den eigenen Pull Request nötig.

Nach jedem Merge laufen die Prüfungen und der FPC-Bau auch auf `main-merging`. Bricht dort etwas, das in beiden Pull Requests einzeln grün war (zwei Änderungen passen inhaltlich nicht zusammen), behebt das der Pull Request, der zuletzt gemergt wurde.

## Automatischer Abgleich

Der Workflow „PRs abgleichen“ (`.github/workflows/pr-abgleich.yml`, Skript `Tools/CI/Abgleich-PRs.py`) läuft nach jedem Push auf `main-merging` und alle 30 Minuten. Er sieht sich jeden offenen Pull Request nach `main-merging` von einem Branch `claude/…` an (keine Entwürfe):

- Ohne Konflikt bleibt der Pull Request unangetastet. Auto-Merge braucht keinen aktuellen Stand, und ein Push würde nur die CI neu starten.
- Hat er einen Konflikt mit `main-merging`, oder ändern beide Seiten Quellen erzeugter Dateien (`schemas/`, `Setup/Profile/`, `Packages/Atlas.Common/Katalog/`), mergt der Workflow `main-merging` mit `Tools/Merge-Integration.py` ein und pusht das Ergebnis auf den Branch. Danach laufen die Prüfungen des Pull Requests neu.
- Bleibt ein echter Konflikt, bekommt der Pull Request das Label „Konflikt mit main-merging“ und einen Kommentar mit den offenen Dateien. Den Konflikt löst der Thread wie in Schritt 2 oben. Das Label verschwindet beim nächsten Lauf ohne Konflikt.

Der Workflow pusht nie mit `--force`. Hat der Thread inzwischen selbst gepusht, versucht es der nächste Lauf erneut. Umgekehrt holt `Tools/Merge-Integration.py` vom Abgleich gepushte Commits (`origin/<eigener Branch>`) vor dem Merge von `main-merging` selbst ein, damit der nächste Push des Threads nicht als „non-fast-forward“ scheitert. Wer ohne das Skript pusht, holt den Branch vorher mit `git pull --no-rebase` ein.

## Rotes main-merging

Scheitert „Package-Abhängigkeiten“ oder „AtlasServer für Linux“ nach einem Push auf `main-merging`, legt der Job `melden` (`Tools/CI/Melde-Integrationsstand.py`) ein Issue mit Label „main-merging rot“ an und kommentiert den Pull Request, dessen Merge den Stand erzeugt hat. Weitere rote Läufe kommentieren das Issue; der erste grüne Lauf danach schließt es.

## Prüfzeit

„AtlasServer für Linux“ teilt sich in zwei parallele Jobs: `bauen` (Server übersetzen, Startprobe, Selbstprüfung je Plugin-Package, die Packages gleichzeitig) und `fpc-tests` (DUnitX-Tests unter FPC). Beide holen FPC trunk aus dem Zwischenspeicher; die Paketquellen für den Startcompiler werden bei einem Aussetzer bis zu viermal angefragt.

Der Selbsttest der Modulgrenzen (`Tools/Test-PackageDependencies.ps1`, etwa sechs Minuten) läuft in Pull Requests nur, wenn sich die Prüfung selbst, die Verträge in Base oder der Workflow ändern oder Units unter `Packages` gelöscht oder verschoben werden. Nach jedem Merge auf `main-merging` läuft er immer.

## Einstellungen des Repositorys

- Branch-Schutz für `main-merging`: Pflichtprüfungen `check` (Workflow „Package-Abhängigkeiten“) sowie `bauen` und `fpc-tests` (Workflow „AtlasServer für Linux“), „Require branches to be up to date before merging“ aus. Nur `bauen` und `fpc-tests` übersetzen den Quelltext; ohne sie als Pflicht führt Auto-Merge auch Pull Requests zusammen, die unter FPC nicht übersetzen, und `main-merging` wird rot. Mit dieser Einstellung an verlangte GitHub nach jedem Merge von allen anderen Pull Requests einen neuen Merge und einen neuen CI-Lauf.
- „Allow auto-merge“ an (Settings › General › Pull Requests), damit Schritt 4 möglich ist.
- Eine Merge Queue gibt es auf GitHub nur für Repositorys von Organisationen; für dieses Repository übernimmt das automatische Zusammenführen ihre Rolle.
- Secret `ABGLEICH_TOKEN` (empfohlen): fein granuliertes Personal Access Token nur für dieses Repository mit den Rechten Contents, Pull requests und Workflows, jeweils „Read and write“. Damit startet der Push des Abgleichs die CI wie ein normaler Push und darf auch Änderungen an `.github/workflows` mitnehmen. Ohne das Secret pusht der Workflow mit `GITHUB_TOKEN`; GitHub startet danach keine Workflows, deshalb startet der Abgleich die Prüfungen per `workflow_dispatch`, und Abgleiche, die Workflow-Dateien ändern, meldet er nur am Pull Request.
