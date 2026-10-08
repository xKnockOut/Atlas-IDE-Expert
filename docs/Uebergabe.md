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
- Den ganzen Ablauf samt 0/0/0-Prüfung und Tests erledigt `pwsh Tools/Build-Test.ps1` (Optionen: `-Win32`, `-SkipTests`, `-CcScript`). Exit-Code 0 = grün, 1 = Build-Fehler/Hinweis/Warnung, 2 = Tests rot, 3 = Umgebungsfehler. Der CI-Job in `.github/workflows/server.yml` ruft dasselbe Skript auf.

## Achtung
- In der IDE des Users ist **Beryl-Components** offen, und dort arbeitet parallel ein anderer Client. **Immer `-Instance <eigene pid>` angeben.** Ohne `-Instance` landet der Auftrag in dieser IDE. Das ist einmal passiert.
- DUnitX gibt es nur für Win64. Ein Win32-Gruppen-Build scheitert deshalb erwartungsgemäß an `BDLsp.Tests` (F2613). Die übrigen 3 Projekte bauen unter Win32.
- Der Remote-Branch wird von außen umgeschrieben (Force-Push, Squash-Merges). Ein `git pull --ff-only` kann deshalb scheitern. Dann mit `git diff --stat HEAD origin/...` prüfen, ob der lokale Stand im Remote enthalten ist, und erst danach `git reset --hard origin/claude/project-thread-mhrxdt` ausführen. Vorher sicherheitshalber einen Backup-Branch anlegen.
- **Regel:** Hinweise und Warnungen werden sofort behoben. Ein Build gilt erst bei 0 Fehlern, 0 Warnungen und 0 Hinweisen als fertig. Dafür zusätzlich das `logFile` auf `[dcc… Hinweis|Warnung]` prüfen.
- Ändert die IDE beim Bauen die `.dproj`, werden diese Änderungen mitcommittet (Wunsch des Users).

## Stand nach diesem Vorgang
- Remote war erneut umgeschrieben: #5 ist jetzt als `f17253e (#161)` enthalten, inhaltlich identisch mit dem lokalen Stand. Lokal wurde auf den Remote-Stand zurückgesetzt. Der vorherige Stand liegt im Backup-Branch `backup/vor-reset-1685582` (nur lokal).
- Update bis `1987033 Lexer für Object Pascal (#6)` eingespielt.
- Build Win64: alle 4 Projekte ✅, 0 Fehler, 0 Warnungen, 0 Hinweise. Win32: 3 von 4 ✅, nur die Tests scheitern wie erwartet an DUnitX. **118 von 118 Tests bestehen.**
- Kein Code-Fix nötig. Die IDE hat keine `.dproj` geändert.

## Offen
- Backup-Branch `backup/vor-reset-1685582` (nur lokal) kann gelöscht werden.
- Diese Übergabe-Datei ist committet, aber noch nicht gepusht.