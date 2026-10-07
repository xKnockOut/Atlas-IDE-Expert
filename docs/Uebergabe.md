# Übergabe: BetterDelphiLSP kompilieren – Stand 07.10.2026

## Kontext
- Repo: https://github.com/xKnockOut/BetterDelphiLSP.git, lokal unter `C:\Projekte\BetterDelphiLSP\repo`, Branch `claude/project-thread-mhrxdt`.
- Projektgruppe: `BetterDelphiLSP.groupproj` mit `BDLsp.Common` (Package), `BDLsp.Windows` (Package), `BetterDelphiLSP` (Anwendung), `BDLsp.Tests` (DUnitX-Konsole, nur Win64).
- Projektregeln stehen in `CLAUDE.md` (Deutsch, UTF-8 mit BOM + CRLF, Rollenkonzept in `docs/Architektur.md`).

## Wie hier kompiliert wird
- RAD Studio 13 (37.0) **Starter**: `msbuild`/`dcc` von der Kommandozeile gehen nicht.
- Kompiliert wird über das IDE-Plugin: `C:\Projekte\IDE-Plugins\Claude-Compile\cc.ps1` (Doku: `Claude_Compile.md` im selben Ordner).
- Bewährter Ablauf:
  1. `cc.ps1 start -Project C:\Projekte\BetterDelphiLSP\repo\BetterDelphiLSP.groupproj` → eigene Scratch-IDE, **pid aus der Ausgabe ablesen**
  2. `cc.ps1 group-build -Instance <pid> -Platform Win64 -Json` (bei Bedarf zusätzlich `Win32`)
  3. Tests: `Output\Win64\Debug\Bin\BDLsp.Tests.exe --exitbehavior:Continue`. **Vorher prüfen, ob die exe neu geschrieben wurde.** Sonst testet man einen alten Build.
  4. `cc.ps1 quit -Instance <pid>`. Solange die IDE noch beschäftigt ist, lehnt sie das ab, dann einfach wiederholen.
- Auf `outputWritten` achten, nicht nur auf `ok`.

## Achtung
- In der IDE des Users ist **Beryl-Components** offen, und dort arbeitet parallel ein anderer Client. **Immer `-Instance <eigene pid>` angeben.** Ohne `-Instance` landet der Auftrag in dieser IDE. Das ist einmal passiert.
- DUnitX gibt es nur für Win64. Ein Win32-Gruppen-Build scheitert deshalb erwartungsgemäß an `BDLsp.Tests` (F2613). Die übrigen 3 Projekte bauen unter Win32.
- Die IDE schreibt beim Bauen die `.dproj` um. Vor jedem `git pull` diese Änderungen stashen.

## Stand nach diesem Vorgang
- Update bis `ca9d6b7 Nebenläufigkeit: Lese-Thread, Worker-Threads und $/cancelRequest (#4)` eingespielt.
- **Compilerfehler in #4 behoben** (`BDLsp.Common.JsonRpc.Connection.pas`, `Run`): `ThreadPoolScheduler` und `CreateResponder` liefern Methodenreferenzen. Ohne `()` versuchte Delphi, die Funktion selbst zuzuweisen (E2010). Jetzt stehen dort `ThreadPoolScheduler()` und `CreateResponder()`.
- Build Win64: alle 4 Projekte ✅, 0 Fehler, 0 Warnungen. Win32: 3 von 4 ✅, nur die Tests scheitern wie erwartet. **75 von 75 Tests bestehen.**
- Erledigt aus früheren Vorgängen: W1002 (`NoErrMsg`) beseitigt, `*.res` steht in der `.gitignore`, das Testprojekt ist auf Win64 beschränkt (#159).

## Offen
- Drei Stashes mit IDE-Änderungen an den `.dproj` („IDE-Änderungen an dproj vor Update“, „… 2“, „… 3“). Dazu kommen die aktuellen, nicht committeten IDE-Änderungen an den vier `.dproj`. Nicht geprüft, vermutlich wegwerfbar. Darüber sollte der User entscheiden.
