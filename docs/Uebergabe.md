# Übergabe: BetterDelphiLSP kompilieren – Stand 07.10.2026

## Kontext
- Repo: https://github.com/xKnockOut/BetterDelphiLSP.git, lokal unter `C:\Projekte\BetterDelphiLSP\repo`
- Code liegt im Branch `claude/project-thread-mhrxdt` (PR #142), **nicht** auf `main` (dort nur `LICENSE`).
- Projektgruppe: `BetterDelphiLSP.groupproj` mit `BDLsp.Common` (Package), `BDLsp.Windows` (Package), `BetterDelphiLSP` (Anwendung), `BDLsp.Tests` (DUnitX-Konsole).
- Projektregeln stehen in `repo\CLAUDE.md` (Deutsch, UTF-8 mit BOM + CRLF, Rollenkonzept in `docs/Architektur.md`).

## Wie hier kompiliert wird
- RAD Studio 13 (37.0) **Starter**: `msbuild`/`dcc` von der Kommandozeile gehen nicht.
- Kompiliert wird über das IDE-Plugin: `C:\Projekte\IDE-Plugins\Claude-Compile\cc.ps1` (Doku: `Claude_Compile.md` im selben Ordner).
- Bewährter Ablauf:
  1. `cc.ps1 start -Project C:\Projekte\BetterDelphiLSP\repo\BetterDelphiLSP.groupproj` → eigene Scratch-IDE, **pid aus der Ausgabe notieren**
  2. `cc.ps1 group-build -Instance <pid> -Platform Win64 -Json`
  3. Tests: `repo\Output\Win64\Debug\Bin\BDLsp.Tests.exe --exitbehavior:Continue`
  4. `cc.ps1 quit -Instance <pid>`
- Auf `outputWritten` achten, nicht nur auf `ok`.

## Achtung
- Die IDE des Users (pid 8412) hat **Beryl-Components** offen, und dort arbeitet parallel ein anderer Client. **Immer `-Instance <eigene pid>` angeben.** Ohne `-Instance` landet der Auftrag in dieser IDE. Das ist einmal passiert: Die Beryl-Gruppe wurde für Win64 neu gebaut und ein Win32-Build abgebrochen. Beryl Win32 sollte vom User neu gebaut werden.
- DUnitX gibt es nur für Win64 (`lib\win64\release`). `BDLsp.Tests` lässt sich für Win32 nicht bauen (F2613). Abhilfe wäre, die DUnitX-Quellen über `$(DUnitX)` einzubinden.

## Erledigt
- Commit `9099651`: `Assert.AreEqual<NativeInt>` in `Tests/Common/BDLsp.Common.Product.Version.Tests.pas`, weil der Win64-Build sonst mit E2532 abbricht. Ist gepusht.
- Update auf `f0e4d45 Protokollschicht: JSON-RPC 2.0 über stdio (#2)` per Fast-Forward eingespielt.
- Build-Ergebnis: alle 4 Projekte unter Win64 ✅. Unter Win32 sind 3 von 4 ✅, nur die Tests scheitern an DUnitX. **41 von 41 Tests bestehen.**

## Offen
- Lokal nicht committet: Die IDE hat beim Bauen alle vier `.dproj` umgeschrieben und `.res`-Dateien erzeugt. Diese Änderungen sind noch nicht geprüft. Ältere IDE-Änderungen an den `.dproj` liegen im Stash (`git stash list`: „IDE-Änderungen an dproj vor Update“). Zu klären ist, ob sie committet oder verworfen werden und ob `*.res` in die `.gitignore` gehört.
- Entscheidung zu DUnitX für Win32 steht aus.
