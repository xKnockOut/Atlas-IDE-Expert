# Übergabe: BetterDelphiLSP – Stand 09.10.2026

## Kontext
- Repo: https://github.com/xKnockOut/BetterDelphiLSP.git, lokal unter `C:\Projekte\BetterDelphiLSP\repo`. Gearbeitet wird auf `main`.
- Projektgruppe `BetterDelphiLSP.groupproj`: `BDLsp.Common`, `BDLsp.Windows` (Packages), `BetterDelphiLSP` (Anwendung), `BDLsp.IdePlugin` (Design-Time-Package, Win32, ADR 0006), `BDLsp.Tests` (DUnitX, nur Win64).
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

## RAD Studio als LSP-Client (#175)
- **Anleitung:** `docs/RAD-Studio.md`. Wird mit #84 in `docs/Installation.md` verlinkt.
- **Eintrag in RAD Studio:**
  - Registry `HKCU\Software\Embarcadero\BDS\37.0\LSP\UserDefined\BetterDelphiLSP` mit `LanguageId = Delphi`.
  - Die IDE hält die Werte im Speicher und schreibt sie beim Beenden zurück. Änderungen deshalb im Dialog *Code Insight-Manager > Bearbeiten* machen, nicht in der Registry.
  - Die exe läuft direkt aus `repo\Output\Win64\Debug\Bin\` (Wunsch des Users). Vor jedem Build muss Delphi das Projekt geschlossen haben, sonst ist die exe gesperrt. Log und Mitschnitt liegen in `C:\Temp`.
  - `Help Insight` steht wieder auf `True`.
- **Funktioniert über den eingebauten Client:** Arbeitsbereich aus der Datei abgeleitet, documentSymbol, Diagnosen als Error Insight.
- **Hover funktioniert nicht und ist nicht lösbar über diesen Weg** (Belege in ADR 0006):
  - Ein Mitschnitt des eingebauten DelphiLSP zeigt dieselben Anfragen und die Antwort `{"contents":"…"}`, und die IDE zeigt sie an.
  - BetterDelphiLSP antwortet seit `ffed3c5` genauso.
  - Auch mit den Fähigkeiten von DelphiLSP und ohne Log- und Fortschrittsnachrichten (nur getestet, nicht committet) blitzt nur „Wird berechnet …“ auf.
- **Neustarts:** Kein Absturz. Jede `bds.exe` startet einen eigenen Server, außerdem gilt „Restart server each time a project is activated“. Die IDE startet zusätzlich parallel ihren eigenen DelphiLSP.
- **Behoben:** Ausweichen beim belegten `--trace` (`7d0cfaa`), Hover-Klartext als String (`ffed3c5`).
- **Entscheidung (ADR 0006):** Ein Design-Time-Package `BDLsp.IdePlugin` (Win32) als Code Insight-Manager und dünner LSP-Client mit eigenem Serverprozess. Reihenfolge: Hover, Gehe zu Definition, Vervollständigung (#31), Parameterhilfe (#32), Error Insight selbst gezeichnet (`INTACodeEditorEvents`).
- **Werkzeuge der Analyse:**
  - Der Vermittler `LspProxy` liegt nur im Scratchpad, `C:\Temp\LspProxy` ist gelöscht.
  - In `bin` und `bin64` liegen noch je eine `DelphiLSP.proxy-alt.exe` (6 KB), die der User löschen kann (Administratorrechte nötig).
  - `DelphiLSP.exe` selbst ist wieder das Original.
- **Kommentar in #175** mit diesem Ergebnis ist veröffentlicht.

## IDE-Plugin `BDLsp.IdePlugin` (ADR 0006)
- **Stand (`c1cfae2`):** Code Insight-Manager „BetterDelphiLSP (Plugin)“ mit Hover (`GetHintText`) und Strg+Klick (`GotoDefinition`). Dünner LSP-Client (`Lsp.Client`, `Lsp.Session`, `Lsp.Adapters.ServerProcess`), 9 DUnitX-Tests in `Tests\IdePlugin`, davon einer gegen den echten Server.
- **Projektgruppe:** Das Plugin steht seit diesem Vorgang in `BetterDelphiLSP.groupproj` (vom User in der IDE hinzugefügt). Ein `group-build -Platform Win64` übersetzt es mit (0/0/0), installiert wird aber die Win32-BPL `Output\Win32\Debug\Bpl\BDLsp.IdePlugin.bpl`. Win32 einzeln: `build -Project …\BDLsp.IdePlugin.dproj -Platform Win32`.
- **Server:** Registry `HKCU\Software\BetterDelphiLSP\IdePlugin\ServerPath`, sonst neben der BPL, sonst `Output\Win64\Debug\Bin\BetterDelphiLSP.exe`. Solange das Plugin aktiv ist, ist diese exe gesperrt.
- **Offen:** Test in der IDE durch den User (installieren, Manager auswählen, Hover und Strg+Klick). Danach Vervollständigung (`GetSymbolList`), Parameterhilfe (`GetParameterList`), Error Insight selbst gezeichnet.

## Feature-Kette (pausiert, Fortsetzung nur auf Anweisung des Users)
- 98 verkettete Branches von `14-projektmodell` bis `122-binaere-dfm`. Für jeden: `main` einmergen, in frischer IDE bauen, beheben, prüfen, Branch pushen, per Fast-Forward nach `main`, `main` pushen.
- **Stand:** 40 von 98 sind in `main` (zuletzt 31-vervollstaendigung und 32-parameterhilfe). Weiter geht es bei Index 41, `33-hierarchien`.
- Neue Commits auf `main` (Plugin, Projektgruppe) kommen beim nächsten Branch über „main einmergen“ automatisch mit. Achtung: Die Kette nutzt `git checkout -- BetterDelphiLSP.groupproj` zum Aufräumen; ältere Branches kennen das Plugin noch nicht, der Merge bringt es mit.
- **Leck-Monitor (seit 177):**
  - Felder im `TearDown` freigeben.
  - Thread- und RTL-Tests bekommen `[IgnoreMemoryLeaks]` mit Begründung.
  - Bei reinen Leck-Fehlschlägen die Tests bis zu dreimal laufen lassen.
- Die IDE sortiert `DCCReference` um und fügt Leerzeilen ein. Reine Umsortierungen und Leerraum-Änderungen werden verworfen.

## Stand nach diesem Vorgang
- `main` enthält Plugin und Projektgruppe mit Plugin. Gruppenbau Win64 0/0/0 (5 Projekte), 550/550 Tests.
- Nächster Schritt: Rückmeldung des Users zum Plugin-Test in der IDE abwarten, dann Vervollständigung und Parameterhilfe im Plugin.
