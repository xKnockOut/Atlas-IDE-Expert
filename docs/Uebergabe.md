# Übergabe: BetterDelphiLSP – Stand 09.10.2026

## Kontext
- Repo: https://github.com/xKnockOut/BetterDelphiLSP.git, lokal unter `C:\Projekte\BetterDelphiLSP\repo`. Gearbeitet wird auf `main`.
- Projektgruppe `BetterDelphiLSP.groupproj`: `BDLsp.Common`, `BDLsp.Windows` (Packages), `BetterDelphiLSP` (Anwendung), `BDLsp.Tests` (DUnitX, nur Win64).
- Projektregeln in `CLAUDE.md`: Deutsch, UTF-8 mit BOM und CRLF, Rollenkonzept in `docs/Architektur.md`.
- Regeln des Users:
  - Hinweise und Warnungen sofort beheben. Ein Build gilt erst bei 0/0/0 als fertig.
  - Am Ende jedes Vorgangs diese Datei aktualisieren.
  - Vor öffentlichen Schritten auf GitHub (Kommentare, Issues) fragen.

## Wie hier gebaut wird
- RAD Studio 13 (37.0) ohne Kommandozeilen-Compiler. Gebaut wird über `C:\Projekte\IDE-Plugins\Claude-Compile\cc.ps1`, Doku liegt daneben.
- Pro Build eine frische IDE:
  1. `start -Project …\BetterDelphiLSP.groupproj -TimeoutSec 180`.
  2. Die pid aus der Zeile „IDE started : pid N“ ablesen. Die Ausgabe über alle Streams lesen (`*>&1`).
  3. Gegenprobe in `%LOCALAPPDATA%\ClaudeCompile\instances\<pid>\status.json`: Dort muss `BetterDelphiLSP.groupproj` stehen.
  4. `group-build -Instance <pid> -Platform Win64 -Json` ausführen.
  5. Tests mit `Output\Win64\Debug\Bin\BDLsp.Tests.exe --exitbehavior:Continue` laufen lassen.
  6. `quit -Instance <pid>` so lange wiederholen, bis der Prozess beendet ist.
- **Niemals `quit` oder einen Build ohne geprüfte `-Instance`.** Ein Agent für XML-Inspector nutzt dasselbe Plugin und lädt seine Projekte in freie IDEs. Erkennbar an einer veränderten `.groupproj`. Dann die Änderung verwerfen und mit neuer IDE wiederholen.
- **Fehlertexte nicht lesbar:** Das Plugin kann die Fehlertexte oft nicht lesen. Dann ist `ok=False` bei 0/0/0, im Log steht nur „Misslungen“. Die Ursache im Code suchen.
- **Häufige Fehlerursachen:**
  - Eine Funktion, die eine Methodenreferenz liefert, ohne `()` zugewiesen (E2010).
  - `TXyz.Create` direkt an einen `const`-Interface-Parameter übergeben.
  - Eine Methode steht zwischen Feldern (E2169).
  - Ein Typ im Interface-Teil stammt aus einer Unit, die nur in den uses des Implementation-Teils steht (E2003).
  - `GetValue<T>` direkt als Argument von `Assert`.
  - Doppeltes BOM in einer Datei.
  - `DUnitX.ServiceLocator` statt `DUnitX.IoC`.

## RAD Studio als LSP-Client (#175) – erledigt
- Anleitung: `docs/RAD-Studio.md`. Wird mit #84 in `docs/Installation.md` verlinkt, sobald die Kette `84-benutzerdoku` nach `main` bringt.
- Checkliste als Kommentar in #175 (09.10.2026).
- **Eintrag in RAD Studio:**
  - Registry `HKCU\Software\Embarcadero\BDS\37.0\LSP\UserDefined\BetterDelphiLSP` mit `LanguageId = Delphi`.
  - Die Auswahl steht in `…\Editor\Source Options\Borland.EditOptions.Pascal`, Wert `Insight Manager`.
  - Die exe liegt unter `C:\Projekte\BetterDelphiLSP.exe`, Log und Mitschnitt in `C:\Temp`.
- **Geprüft in der IDE:**
  - Der Arbeitsbereich wird aus der Datei abgeleitet (Gallery, Index in 4,9 s).
  - Hover liefert `plaintext`.
  - documentSymbol und Diagnosen funktionieren.
- **Neustarts:** Das ist kein Absturz. Jede `bds.exe` startet einen eigenen Server, außerdem greift die Voreinstellung „Restart server each time a project is activated“. Die IDE beendet den Server hart, deshalb fehlt „Beendet mit Exit-Code“. Das ließ sich belegen: 38 von 44 Sitzungen beginnen direkt nach einem IDE-Start.
- **Behoben (7d0cfaa):** Bei belegter `--trace`-Datei weicht der Server auf `<Datei>-<PID>.<Endung>` aus. Vorher lief jeder weitere Server ohne Mitschnitt.
- **Kein Handlungsbedarf:** `languageId = "pascal"`, weil der Server `languageId` nicht auswertet.
- **Offen:** `textDocument/completion`. Die IDE fragt an, der Server antwortet `MethodNotFound`. Das wird mit `feature/31-vervollstaendigung` aus der Kette gelöst.
- **Aufräumen:** `C:\Projekte\BetterDelphiLSP.old.exe` ist eine identische Kopie, die gerade läuft. Löschen, sobald Delphi den Server beendet hat.

## Feature-Kette (pausiert, Fortsetzung nur auf Anweisung des Users)
- 98 verkettete Branches von `14-projektmodell` bis `122-binaere-dfm`. Für jeden: `main` einmergen, in frischer IDE bauen, beheben, prüfen, Branch pushen, per Fast-Forward nach `main`, `main` pushen.
- **Stand:** 38 von 98 sind in `main`. Weiter geht es bei Index 39, `feature/31-vervollstaendigung`.
- Seitdem hat `main` neue Commits bekommen (#175, die Anleitung, der Fix beim Mitschnitt). Beim nächsten Branch kommen sie über „main einmergen“ automatisch mit.
- **Leck-Monitor (seit 177):**
  - Felder im `TearDown` freigeben.
  - Thread- und RTL-Tests bekommen `[IgnoreMemoryLeaks]` mit Begründung.
  - Bei reinen Leck-Fehlschlägen die Tests bis zu dreimal laufen lassen.
- Die IDE sortiert `DCCReference` um und fügt Leerzeilen ein. Reine Umsortierungen und Leerraum-Änderungen werden verworfen.

## Stand nach diesem Vorgang
- `main` = `7d0cfaa`, Win64 0/0/0, 528/528 Tests.
