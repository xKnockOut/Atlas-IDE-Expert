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

## Einstellungen des Repositorys

- Branch-Schutz für `main-merging`: Pflichtprüfung `check` (Workflow „Package-Abhängigkeiten“), „Require branches to be up to date before merging“ aus. Mit dieser Einstellung an verlangte GitHub nach jedem Merge von allen anderen Pull Requests einen neuen Merge und einen neuen CI-Lauf.
- „Allow auto-merge“ an (Settings › General › Pull Requests), damit Schritt 4 möglich ist.
- Eine Merge Queue gibt es auf GitHub nur für Repositorys von Organisationen; für dieses Repository übernimmt das automatische Zusammenführen ihre Rolle.
