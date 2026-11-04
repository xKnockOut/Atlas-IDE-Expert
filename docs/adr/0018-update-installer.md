# 0018: Updates aus dem Plugin mit AtlasUpdate.exe

- Status: Angenommen
- Datum: 2026-11-04
- Bezug: setzt [ADR 0016](0016-kein-installer.md) fort (#1519, Variante A „beim Beenden installieren“)

## Kontext

Seit ADR 0016 sind Installation und Update Handarbeit je IDE. Die Update-Prüfung (#495) meldet eine neue Version nur und verlinkt den Download. Ein Benutzer hat nach einem Auto-Update gefragt. Zwei Hürden: Die IDE hält die BPLs geladen, solange sie läuft, und Releases enthalten nur Packages für Delphi 13 (Delphi 12 lässt sich in der Release-Kette nicht bauen).

## Entscheidung

- Neue Konsolenanwendung `AtlasUpdate.exe` (Win64) in der Projektgruppe und im Release-Paket, mit den Befehlen `prepare`, `apply` und `install`. Die Logik steht in `Atlas.Common.Updates.*` (getestet ohne Windows), die Windows-Adapter in `Atlas.Windows.Updates.Adapters.*`, die Shell in `Application/Source/Shell/Shell.Update*.pas`.
- `prepare` läuft unsichtbar aus der IDE: lädt die Versionsdatei des Kanals, das Paket für die IDE (bzw. den Quelltext und baut ihn mit MSBuild der Delphi-Installation, Delphi 12), prüft SHA-256 und Signatur und legt alles unter `%LOCALAPPDATA%\Atlas\Updates\<Version>` ab. Den Stand schreibt es in `state.json`.
- `apply` startet beim Schließen der IDE in einer sichtbaren Konsole, wartet auf das Ende der IDE und aller Prozesse, die BPLs aus dem Atlas-Ordner geladen haben, tauscht die Dateien mit Sicherung, trägt die Known Packages im Profil der IDE ein und nimmt bei einem Fehler alles zurück. Das Ergebnis (`result.json`) meldet das Plugin beim nächsten Start.
- Kein Hochstufen auf Administrator: Ein anderes Konto hätte ein anderes `HKEY_CURRENT_USER`. Ist der Atlas-Ordner nicht beschreibbar, bleibt alles unverändert, und Atlas empfiehlt `%LOCALAPPDATA%\Programs\Atlas`.
- Signatur: Ist die laufende `AtlasUpdate.exe` signiert, muss jede EXE, BPL und DLL des Updates gültig vom selben Herausgeber signiert sein; sonst prüft sie nur SHA-256.
- Nicht über das Plugin: Installation über GetIt, Atlas außerhalb eines Release-Ordners (`<Ziel>\Win32` bzw. `\Win64`) und ohne `AtlasUpdate.exe`. Dann bleibt es beim Link.
- Kanäle: stabil über `releases/latest/download/atlas-version.json`; mit Vorabversionen über den festen Vorab-Release `update-channel` (`atlas-version-beta.json`), den jeder Release ersetzt.
- Einstellungen `updates.install` (ask, auto, off), `updates.channel` (stable, prerelease), `updates.newModules` (ask, install, skip).

## Alternativen

- Sofort im laufenden Betrieb tauschen (Variante B): BPLs sind geladen, ein Tausch bräuchte einen Neustart der IDE ohnehin.
- Eigener Installer wie bis 1.1 (ADR 0009): verworfen in ADR 0016.
- Hochstufen per UAC: trifft das falsche Benutzerprofil.

## Folgen

- `release.yml` baut und signiert `AtlasUpdate.exe`, packt sie ins ZIP, legt das Quelltext-ZIP bei und schreibt Paket und Quelltext mit SHA-256 in die Versionsdatei.
- Die Installation von Hand nach ADR 0016 bleibt möglich; `AtlasUpdate install` erledigt sie im Dialog.
- Delphi 12 bekommt Updates, sofern RAD Studio mit Kommandozeilen-Compiler (MSBuild) installiert ist; ohne bleibt nur der Link.
