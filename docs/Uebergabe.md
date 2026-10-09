# Übergabe: Argus IDE Expert – Stand 09.10.2026

## Kontext
- Repo: https://github.com/xKnockOut/Argus-IDE-Expert.git, lokal unter `C:\Projekte\BetterDelphiLSP\repo`. Gearbeitet wird auf `main`.
- Projektgruppe `Argus.groupproj`: `Argus.Common`, `Argus.Windows` (Packages), `ArgusServer` (Anwendung), `Argus.IdePlugin` (Design-Time-Package, Win32, ADR 0006), `Argus.Tests` (DUnitX, nur Win64).
- Projektregeln in `CLAUDE.md`: Deutsch, UTF-8 mit BOM und CRLF, Rollenkonzept in `docs/Architektur.md`.
- Regeln des Users:
  - Hinweise und Warnungen sofort beheben. Ein Build gilt erst bei 0/0/0 als fertig.
  - Am Ende jedes Vorgangs diese Datei aktualisieren.
  - Vor öffentlichen Schritten auf GitHub (Kommentare, Issues) fragen.

## Wie hier gebaut wird
- RAD Studio 13 (37.0) ohne Kommandozeilen-Compiler. Gebaut wird über `C:\Projekte\IDE-Plugins\Claude-Compile\cc.ps1`, Doku liegt daneben.
- Pro Build eine frische IDE:
  1. `start -Project …\Argus.groupproj -TimeoutSec 180`.
  2. Die pid aus der Zeile „IDE started : pid N“ ablesen. Die Ausgabe über alle Streams lesen (`*>&1`).
  3. Gegenprobe in `%LOCALAPPDATA%\ClaudeCompile\instances\<pid>\status.json`: Dort muss `Argus.groupproj` stehen.
  4. `group-build -Instance <pid> -Platform Win64 -Json` ausführen.
  5. Tests mit `Output\Win64\Debug\Bin\Argus.Tests.exe --exitbehavior:Continue` laufen lassen.
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
  - Registry `HKCU\Software\Embarcadero\BDS\37.0\LSP\UserDefined\Argus` mit `LanguageId = Delphi`.
  - Die IDE hält die Werte im Speicher und schreibt sie beim Beenden zurück. Änderungen deshalb im Dialog *Code Insight-Manager > Bearbeiten* machen, nicht in der Registry.
  - Die exe läuft direkt aus `repo\Output\Win64\Debug\Bin\` (Wunsch des Users). Vor jedem Build muss Delphi das Projekt geschlossen haben, sonst ist die exe gesperrt. Log und Mitschnitt liegen in `C:\Temp`.
  - `Help Insight` steht wieder auf `True`.
- **Funktioniert über den eingebauten Client:** Arbeitsbereich aus der Datei abgeleitet, documentSymbol, Diagnosen als Error Insight.
- **Hover funktioniert nicht und ist nicht lösbar über diesen Weg** (Belege in ADR 0006):
  - Ein Mitschnitt des eingebauten DelphiLSP zeigt dieselben Anfragen und die Antwort `{"contents":"…"}`, und die IDE zeigt sie an.
  - ArgusServer antwortet seit `ffed3c5` genauso.
  - Auch mit den Fähigkeiten von DelphiLSP und ohne Log- und Fortschrittsnachrichten (nur getestet, nicht committet) blitzt nur „Wird berechnet …“ auf.
- **Neustarts:** Kein Absturz. Jede `bds.exe` startet einen eigenen Server, außerdem gilt „Restart server each time a project is activated“. Die IDE startet zusätzlich parallel ihren eigenen DelphiLSP.
- **Behoben:** Ausweichen beim belegten `--trace` (`7d0cfaa`), Hover-Klartext als String (`ffed3c5`).
- **Entscheidung (ADR 0006):** Ein Design-Time-Package `Argus.IdePlugin` (Win32) als Code Insight-Manager und dünner LSP-Client mit eigenem Serverprozess. Reihenfolge: Hover, Gehe zu Definition, Vervollständigung (#31), Parameterhilfe (#32), Error Insight selbst gezeichnet (`INTACodeEditorEvents`).
- **Werkzeuge der Analyse:**
  - Der Vermittler `LspProxy` liegt nur im Scratchpad, `C:\Temp\LspProxy` ist gelöscht.
  - In `bin` und `bin64` liegen noch je eine `DelphiLSP.proxy-alt.exe` (6 KB), die der User löschen kann (Administratorrechte nötig).
  - `DelphiLSP.exe` selbst ist wieder das Original.
- **Kommentar in #175** mit diesem Ergebnis ist veröffentlicht.

## IDE-Plugin `Argus.IdePlugin` (ADR 0006)
- **Stand (`c1cfae2`):** Code Insight-Manager „Argus IDE Expert“ mit Hover (`GetHintText`) und Strg+Klick (`GotoDefinition`). Dünner LSP-Client (`Lsp.Client`, `Lsp.Session`, `Lsp.Adapters.ServerProcess`), 9 DUnitX-Tests in `Tests\IdePlugin`, davon einer gegen den echten Server.
- **Projektgruppe:** Das Plugin steht seit diesem Vorgang in `Argus.groupproj` (vom User in der IDE hinzugefügt). Ein `group-build -Platform Win64` übersetzt es mit (0/0/0), installiert wird aber die Win32-BPL `Output\Win32\Debug\Bpl\Argus.IdePlugin.bpl`. Win32 einzeln: `build -Project …\Argus.IdePlugin.dproj -Platform Win32`.
- **Server:** Registry `HKCU\Software\Argus\IdePlugin\ServerPath`, sonst neben der BPL, sonst `Output\Win64\Debug\Bin\ArgusServer.exe`. Solange das Plugin aktiv ist, ist diese exe gesperrt.
- **In der IDE getestet (User, GalleryDemo):** Hover funktioniert, Strg+Klick auf Bezeichner derselben Unit springt. Strg+Klick auf `TBThemeController` findet nichts, weil der Typ in einer Include-Datei steht (`Beryl.VCL.Forms.ThemeController.intf.inc`); das löst erst `264-include-resolver` (Kette Index 77). Server direkt geprüft: liefert dort `[]`.
- **`ce3da00`:** Ohne Treffer gibt `GotoDefinition` `True` mit leerem Dateinamen und Zeile 0 zurück (mit `False` meldete die IDE „Datei "" nicht gefunden“). Diagnose: `Diagnose` = 1 (DWORD) unter `HKCU\Software\Argus\IdePlugin` schreibt `Argus.IdePlugin.log` neben die BPL (der Temp-Ordner funktionierte in der IDE des Users nicht).
- **Registry aus der Sandbox:** Werte für die IDE nur mit deaktivierter Sandbox schreiben, sonst sieht die vom User gestartete IDE sie womöglich nicht.
- **Delphi des Users** darf ich selbst schließen (`CloseMainWindow` auf `bds.exe`), wenn die Plugin-BPL oder die Server-exe gesperrt ist.
- **Offen:** Vervollständigung (`GetSymbolList`), Parameterhilfe (`GetParameterList`), Error Insight selbst gezeichnet.

## Feature-Kette (pausiert, Fortsetzung nur auf Anweisung des Users)
- 98 verkettete Branches von `14-projektmodell` bis `122-binaere-dfm`.
- **Stand:** bis Index 66 (`254-uses-befehl`) in `main`, 724 Tests. Weiter ginge es bei Index 67 (`181-dateioperationen`, wird übersprungen), dann 68 `review-befunde`.
- **Vor jedem Branch Issue prüfen (Auftrag des Users):** offen → übernehmen; geschlossen → prüfen, ob noch gebraucht. Laut Durchsicht vom 09.10.2026 (Epic #392) „nicht geplant“ und aus der Kette genommen: #86 (Index 61), #179 (65), #181 (67), #111 (94), #115 (96). `review-befunde` (68) hat kein Issue, enthält Review-Korrekturen und wird übernommen.
- **Seit #460 (Umbenennung) neues Verfahren, Skript `chainrun2.ps1` im Scratchpad:** Eigene Änderung des Branches (Basis = `merge-base` mit dem Vorgänger in der Kette, so fallen ausgelassene Branches heraus) auf beiden Ständen mit `rename-argus.ps1` umbenennen (gegen #460 geprüft) und als 3-Wege-Cherry-Pick auf `main` anwenden (Arbeitsbranch `kette-arbeit`), bauen, testen, per Fast-Forward nach `main`. Die Feature-Branches auf GitHub bleiben unverändert (kein Force-Push). Listenkonflikte in `.dpr`/`.dpk`/`.dproj` (`resolve-lists.ps1`) und reine H2443-Hinweise (`fix-h2443.ps1`) löst das Skript selbst.
- **#254 ohne #179:** `/uses` hing im onTypeFormatting-Handler aus #179. Übernommen ohne Blockabschluss (User-Entscheidung): Handler nur für `/uses`, Capability `documentOnTypeFormattingProvider`, Einstellung `usesCommand`. Achtung bei späteren Branches, die auf `completeBlocks`/`BlockCompletion` aufbauen.
- **Behoben in 55–66:** H2443 (mehrfach), Zeilentransport-Tests (Lecks, `ä`), Index-Cache-Flags ohne `GetValue<Boolean>` (Leck), E1019 in `Completion.AddFromOtherUnits`, Konflikte in VS-Code-`package.json`, `Architektur.md` (`argus.server.status` wie im Code), Editor-Dateien `betterdelphilsp` → `argus`, `bench.mjs` mit `ArgusServer.exe`.
- **Behoben in 41–54:** Merge-Konflikte (Hover-Klartext mit Wert/Deprecation, Shell.Composition mit Compiler und abgeleiteten Arbeitsbereichen, Shell.Workspace-uses, mehrfach `Argus.Tests.dpr`), `Count`/`Length` als `Integer` (E2532), `ReadTabsConfig()` (E2010), H2077, H2443, DFM-Gliederungstest.
- **Kettenskript:** Konflikte nur in `Tests/Argus.Tests.dpr` löst es selbst (beide Seiten übernehmen, Dubletten entfernen). Jeder andere Konflikt hält an.
- **Leck-Monitor (seit 177):**
  - Felder im `TearDown` freigeben.
  - Thread- und RTL-Tests bekommen `[IgnoreMemoryLeaks]` mit Begründung.
  - Bei reinen Leck-Fehlschlägen die Tests bis zu dreimal laufen lassen.
- Die IDE sortiert `DCCReference` um und fügt Leerzeilen ein. Reine Umsortierungen und Leerraum-Änderungen werden verworfen.

## Umbenennung in Argus (#403, 09.10.2026)
- **GitHub:** Das Repository heißt jetzt `xKnockOut/Argus-IDE-Expert` (vom User umbenannt, alte URLs leiten weiter). Der lokale Ordner `C:\Projekte\BetterDelphiLSP\repo` bleibt, bis der User ihn selbst umbenennt.
- **Code:** Präfix `Argus.*` statt `BDLsp.*` in Units, Ordnern, `.dpk`, `.dproj`; Projektgruppe `Argus.groupproj`; Anwendung `Application\ArgusServer.dpr` → `ArgusServer.exe`; Tests `Tests\Argus.Tests.dpr` → `Argus.Tests.exe`; Plugin `Argus.IdePlugin.bpl`, Typ `TArgusCodeInsightManager`.
- **Namen nach außen:** Code Insight-Manager „Argus IDE Expert“, `serverInfo.name`, `source` der Diagnosen und SARIF-Werkzeug „Argus“. Befehle des Servers `argus.server.compile`, `argus.server.selectBuild`, `argus.server.status`; Editor-Abschnitt `argus` (VS Code `argus.*`); Cache `%LOCALAPPDATA%\Argus`, Compiler-Ausgabe `%TEMP%\Argus\dcc-…`.
- **Abwärtskompatibel:** `argus.json` und `argus-baseline.json`; fehlen sie, gelten `delphi-lsp.json` bzw. `delphi-lsp-baseline.json` (`ExistingOrLegacyFile`, `IsConfigurationFileName`). Das Plugin liest `HKCU\Software\Argus\IdePlugin`, ersatzweise den alten Schlüssel `HKCU\Software\BetterDelphiLSP\IdePlugin`; zeigt dessen `ServerPath` auf eine fehlende exe, gelten die Vorgaben.
- **Beim User nach dem ersten Bau nötig:**
  - Altes Package `BDLsp.IdePlugin.bpl` in der IDE entfernen, `Output\Win32\Debug\Bpl\Argus.IdePlugin.bpl` installieren, im Code Insight-Manager „Argus IDE Expert“ wählen.
  - Der benutzerdefinierte LSP-Eintrag `UserDefined\BetterDelphiLSP` zeigt noch auf `BetterDelphiLSP.exe`: im Dialog auf `ArgusServer.exe` umstellen (Name `Argus`).
  - Alte Ausgaben (`BetterDelphiLSP.exe`, `BDLsp.*.bpl/.dcp`, `%LOCALAPPDATA%\BetterDelphiLSP`) können gelöscht werden.
- **Feature-Kette:** Beim Einmergen von `main` in die übrigen Branches folgen Umbenennungen von Dateien meist automatisch. Neue Units der Branches und ihre uses-Einträge danach nach denselben Regeln umbenennen: `BDLsp` → `Argus`, `bdlsp` → `argus`, `BetterDelphiLSP` → `ArgusServer` in `.dproj`/`.groupproj`/`.dpr`, sonst `Argus`; `delphi-lsp.json` → `argus.json`. Danach muss `git grep -n "BDLsp\|BetterDelphiLSP"` leer sein, außer an den Stellen für Abwärtskompatibilität.
- **Offen:** Gruppenbau und Tests in der IDE (in der Cloud nicht baubar). Schichten `Argus.Core/UI/IDE` und eigenes `Argus.Tests.dpr` für das Plugin folgen mit #406 und #415.

## Stand nach diesem Vorgang
- `main` = `ebad9ee` (Kette bis 66, nach #460), Gruppenbau `Argus.groupproj` Win64 0/0/0 (5 Projekte), 724/724 Tests.
- Kette auf Wunsch des Users nach Index 66 angehalten. Fortsetzung nur auf Anweisung: `chainrun2.ps1 -StartAt 67`.
