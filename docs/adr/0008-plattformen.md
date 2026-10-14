# 0008: Plattformen Win32 und Win64, Tests nur Win64

- Status: Angenommen
- Datum: 2026-10-14
- Bezug: #79, #260 Build und Tests über cc.ps1, #281 Delphi 12 und 64-Bit-IDE, ADR 0002 Package-Aufteilung, ADR 0006 IDE-Plugin

## Kontext

Atlas besteht aus Packages und Anwendungen mit unterschiedlichen Anforderungen an die Plattform:

- **AtlasServer** läuft als eigener Prozess. Auf 64 Bit hat er mehr Adressraum für große Projekte (Index, Syntaxbäume).
- **Atlas.IDE.Expert** wird in die IDE geladen und muss deshalb dieselbe Plattform haben wie `bds.exe`: Win32 für die klassische IDE, Win64 für die 64-Bit-IDE, die es ab Delphi 12.3 gibt.
- **Atlas.Common** und **Atlas.Windows** werden von beiden genutzt.
- **DUnitX** liegt in der RAD-Studio-Installation nur für Win64 vor.

## Entscheidung

| Projekt | Win32 | Win64 |
|---|---|---|
| `Atlas.Common`, `Atlas.Windows` | ja | ja |
| `AtlasServer` | ja | ja, Standard |
| `Atlas.IDE.Expert` | ja, für die klassische IDE | ja, für die 64-Bit-IDE |
| `Atlas.Tests` | – | ja |
| `AtlasSetup` | ja ([ADR 0009](0009-installer.md)) | – |

- Das Plugin wird für **Win32 und Win64** gebaut (Entscheidung zu #281 vom 14.10.2026). Die BPL trägt per `{$LIBSUFFIX AUTO}` die Package-Version im Namen (`Atlas.IDE.Expert370.bpl` für Delphi 13, `…290.bpl` für Delphi 12), damit BPLs beider IDE-Versionen nebeneinander liegen.
- Der Server wird für **Win32 und Win64** gebaut. Ausgeliefert und vom Plugin gestartet wird standardmäßig die Win64-Fassung.
- Die **DUnitX-Tests laufen nur unter Win64**. Win32 wird nur übersetzt, damit Code, der nur dort bricht (Zeigergrößen, `NativeInt`, Aufrufkonventionen), auffällt.
- `Tools/Build-Test.ps1 -Win32` baut zusätzlich Win32. Dort darf nur das Testprojekt scheitern; jeder andere Fehler, Hinweis oder jede Warnung zählt.
- Das Referenz-Testprojekt (#94) wird für beide Plattformen gebaut, weil es `{$IFDEF WIN32/WIN64}`-Varianten enthält.

## Alternativen

- **Nur Win64:** Das IDE-Plugin muss Win32 sein und nutzt `Atlas.Common`; Win32 entfiele also nicht.
- **Tests auch unter Win32:** Bräuchte ein selbst übersetztes DUnitX für Win32 im Repo oder auf jedem Rechner. Der Nutzen ist klein, weil der plattformabhängige Code wenig ist und Win32 trotzdem übersetzt wird.
- **Plugin nur für Win32:** Atlas fehlte in der 64-Bit-IDE ganz. Der Plugin-Code ist ohnehin 64-Bit-fest (Wächter mit Rip/Rsp, keine Zeiger in Integer), der Mehraufwand ist ein zweiter Bau.
- **Nur Win32:** Der Server verlöre den größeren Adressraum, den große Projekte brauchen.

## Folgen

- Plattformabhängige Fehler zur Laufzeit unter Win32 fallen in Tests nicht auf, nur beim Übersetzen und im Plugin selbst. Code mit Zeigerarithmetik und Größenannahmen braucht deshalb besondere Sorgfalt.
- Der vollständige CI-Lauf baut zweimal (Win64 mit Tests, Win32 ohne).
- Der Win64-Build der Gruppe erzeugt die Plugin-BPL für die 64-Bit-IDE, der Win32-Build die für die klassische IDE; `Tools/Build-Test.ps1` prüft beide.
- Die Win64-Fassung des Plugins setzt `designide` für Win64 voraus, also eine Installation mit 64-Bit-IDE.
- Code mit fester Zeigergröße meldet `Tools/Check-Delphi12.ps1`.
