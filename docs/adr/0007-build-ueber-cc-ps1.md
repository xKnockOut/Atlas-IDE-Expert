# 0007: Bauen über das IDE-Plugin cc.ps1 statt dcc und MSBuild

- Status: Angenommen
- Datum: 2026-10-14
- Bezug: #79, #78 CI-Pipeline, #260 Build und Tests über cc.ps1, #261 Kompilieren ohne Kommandozeilen-Compiler, #94 Referenz-Testprojekt

## Kontext

Entwickelt wird mit RAD Studio 13 (37.0) in einer Ausgabe ohne Kommandozeilen-Compiler: `dcc32`, `dcc64` und `msbuild` mit den Delphi-Targets stehen nicht zur Verfügung. Übersetzen kann nur die IDE selbst.

Gebraucht wird der Build trotzdem an drei Stellen:
- **Entwicklung:** Nach jeder Änderung Projektgruppe bauen, Hinweise und Warnungen sofort beheben (0/0/0-Regel), Tests laufen lassen.
- **CI (#78):** Jeder Push und jeder PR soll gebaut und getestet werden. Delphi darf aus Lizenzgründen nicht auf gehosteten Runnern laufen.
- **Compilermeldungen in Atlas (#261, #528):** Atlas soll Compilerfehler zeigen können, ohne dass ein Kommandozeilen-Compiler da ist.

Das IDE-Plugin `cc.ps1` (Claude-Compile) startet eine IDE, lädt ein Projekt oder eine Projektgruppe, baut über die Open Tools API und liefert das Ergebnis als JSON mit `ok`, `outputWritten` und dem Pfad des Build-Logs.

## Entscheidung

Gebaut wird ausschließlich über `cc.ps1`, gekapselt in Skripten im Repo:

- `Tools/Build-Test.ps1` baut `Atlas.groupproj` für Win64 (mit `-Win32` zusätzlich Win32), prüft das Log auf Hinweise und Warnungen und führt die DUnitX-Tests aus.
- `Tools/Build-Referenzprojekt.ps1` baut das Referenz-Testprojekt (#94) für Win32 und Win64 und vergleicht die Meldungen mit der Liste der gewollten.
- Jeder Lauf startet eine **eigene Scratch-IDE** und spricht sie nur über ihre pid an (`-Instance`). Eine schon laufende IDE, etwa die des Benutzers oder eines anderen Agenten, wird nie benutzt; gehört die pid zu einem vorher laufenden Prozess, bricht das Skript ab.
- Die CI (`.github/workflows/server.yml`) ruft dieselben Skripte auf einem **selbst gehosteten Windows-Runner** im angemeldeten Benutzerkontext auf, weil `cc.ps1` eine IDE mit Oberfläche startet.
- Der Pfad zu `cc.ps1` kommt aus `-CcScript` bzw. der Umgebungsvariablen `CC_SCRIPT`.

## Alternativen

- **Kommandozeilen-Compiler einer höheren Ausgabe:** Würde den Build vereinfachen, steht aber nicht zur Verfügung und darf nicht auf gehosteten Runnern laufen.
- **Free Pascal als Ersatz-Compiler:** Hilft beim Ausführen der Tests ohne Delphi (siehe Übergabe), übersetzt aber weder VCL noch Open Tools API und weicht in Details der Sprache ab. Als Nachweis, dass Delphi den Code übersetzt, taugt es nicht.
- **Build von Hand in der IDE:** Nicht wiederholbar, keine CI.

## Folgen

- **Langsamer Build:** Jeder Lauf startet eine IDE; ein Build dauert deutlich länger als mit `dcc`.
- **CI nur selbst gehostet:** Der Job läuft nur, wenn die Repository-Variable `DELPHI_RUNNER` gesetzt ist. Ohne Runner bleibt der Build ungeprüft; PRs aus der Cloud sind dann nur mit Free Pascal getestet.
- **Fehlertexte nicht immer lesbar:** `cc.ps1` kann Fehlertexte der IDE nicht in jedem Fall auslesen; dann steht im Log nur „Misslungen“. Die Skripte werten deshalb `ok` und `outputWritten` zusätzlich zum Log aus.
- **Design-Packages:** Ein geladenes Design-Package (das IDE-Plugin, ADR 0006) kann die IDE nicht neu bauen, solange sie es hält. Gebaut wird es in der Scratch-IDE, die es nicht geladen hat.
- **Compilermeldungen für Atlas (#261, #528):** Atlas bekommt Compilermeldungen über das IDE-Plugin aus der laufenden IDE, nicht über einen eigenen Compileraufruf.
- **Delphi 12 (#281):** Für einen Build mit Delphi 12 braucht es eine Installation mit `cc.ps1`; die Skripte reichen dafür Argumente an `cc.ps1 start` durch.
