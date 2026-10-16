# Installation

Atlas ist eine einzelne Datei, `AtlasServer.exe` (Windows, Win64). Sie spricht LSP über stdio, mit `--mcp` MCP für KI-Agenten und mit `--check` prüft sie ohne Editor. Eine installierte RAD-Studio-Version braucht der Server nur für Compiler-Meldungen (`compiler.onSave`); die passende Version liest er aus der `.dproj`.

## Server besorgen

- **Release:** `AtlasServer.exe` aus dem neuesten [GitHub-Release](https://github.com/xKnockOut/Atlas-IDE-Expert/releases) laden und in einen Ordner im `PATH` legen.
- **Selbst bauen:** `Atlas.groupproj` in RAD Studio öffnen und Win64 bauen; die EXE liegt unter `Output\Win64\<Config>\Bin\`.

## RAD Studio (Installer)

Das Plugin `Atlas.IDE.Expert` bindet den Server in die IDE ein: [RAD-Studio.md](RAD-Studio.md).

Für das IDE-Plugin (#495) enthält jedes Release `atlas-ide-expert-<Version>.zip`:

```
AtlasSetup.exe          Installer
AtlasServer.exe         Server (Win64)
Win32\Atlas.IDE.Expert370.bpl   Plugin für die klassische IDE
Win64\Atlas.IDE.Expert370.bpl   Plugin für die 64-Bit-IDE
LICENSE, THIRD-PARTY-NOTICES.md
whatsnew.json           Neuerungen je Version für die Karte „Neu in Atlas“ (#756)
Beispiele\              Beispieldateien zu „Ausprobieren“ auf dieser Karte und auf „Atlas entdecken“
tips.json               Tipps für die Karte „Atlas entdecken“ und die Tastenkürzel-Tipps (#757)
Tipps\                  Bilder (PNG) zu diesen Tipps
Doku\                   Doku als HTML für „Atlas-Doku“ auf der Willkommensseite (#766)
Vorlagen\               Vorlagen für atlas.json („Projekt für Atlas einrichten“ auf der Willkommensseite, #759)
Profile\                Einstellungsprofile „Atlas-Standard“, „Minimal“ und „Alles an“ (#723)
```

1. ZIP entpacken und `AtlasSetup.exe` starten. Administratorrechte braucht er nicht, er schreibt nur unter dem eigenen Benutzer.
2. Er findet die installierten Delphi-Versionen über die Registry (`HKCU` und `HKLM` unter `Software\Embarcadero\BDS\<Version>`, Wert `RootDir`) und zeigt je Version die 32-Bit-IDE (`bin\bds.exe`) und, falls vorhanden, die 64-Bit-IDE (`bin64\bds.exe`). Nicht unterstützte Versionen (vor Delphi 12) und IDEs, für die das ZIP keine BPL enthält, stehen ausgegraut in der Liste.
3. „Installieren“ (bei vorhandener Installation „Aktualisieren“) prüft zuerst, ob eine der gewählten IDEs läuft, und bittet, sie zu schließen („Wiederholen“, „Abbrechen“). Dann kopiert er alle Dateien nach `%LOCALAPPDATA%\Programs\Atlas` (die Ordner `Beispiele`, `Tipps`, `Doku`, `Vorlagen` und `Profile` ersetzt er ganz) und trägt je IDE die BPL unter `HKCU\Software\Embarcadero\BDS\<Version>\Known Packages` (64-Bit-IDE: `Known Packages x64`) ein. Ältere Einträge von Atlas, auch unter früheren Namen (Argus, BetterDelphiLSP), und eine Abschaltung unter „Disabled Packages“ entfernt er vorher.
4. Beim nächsten Start der IDE ist Atlas aktiv. Den Server findet das Plugin eine Ebene über der BPL.

Jeder Schritt steht im Protokollfeld des Installers. Ist eine Datei gesperrt (IDE doch noch offen), bricht er vor der Registrierung ab und nennt die Ursache.

**Deinstallieren:** unter *Einstellungen › Apps › Installierte Apps* „Atlas IDE Expert“ wählen (ruft `AtlasSetup.exe /uninstall`). Entfernt werden die Einträge unter „Known Packages“ und „Disabled Packages“ (auch `x64`) in allen Delphi-Versionen, der Programmordner und der Eintrag in der App-Liste. Einstellungen (`HKCU\Software\Atlas`, `%APPDATA%\Atlas`), Index und Protokolle (`%LOCALAPPDATA%\Atlas`) und eigene Snippets (`%APPDATA%\Atlas\Snippets`) bleiben, außer ihr Kästchen wird angehakt.

**Aktualisieren:** den Installer der neuen Version starten. Einstellungen, Favoriten, `.atlas`-Dateien der Projekte und Snippets berührt er nicht. Ändert sich das Format des Index, verwirft der Server den alten Cache und baut ihn neu auf (#492).

**Einstellungen übertragen (#723):** Ohne Fenster exportiert, importiert oder setzt `AtlasSetup.exe` die persönlichen Einstellungen des Plugins zurück (Registry `HKCU\Software\Atlas\IdePlugin` und `%APPDATA%\Atlas\settings.json`), z. B. für neue Rechner im Team oder ein Skript:

```
AtlasSetup /exportSettings <Datei> [/areas:editor,build] [/secrets:placeholder]
AtlasSetup /importSettings <Datei|minimal|atlas-standard|alles-an> [/replace|/merge] [/areas:…]
AtlasSetup /resetSettings [/areas:…]
```

Bereiche: `editor`, `completion`, `highlighting`, `keys`, `codeActions`, `rules`, `build`, `debug`, `snippets`, `bookmarks`, `welcome`, `general`; ohne `/areas:` alle bzw. die der Datei. Es gelten dieselben Regeln wie unter *Tools › Optionen › Atlas*: nur geänderte Werte, keine Zugangsdaten und Benutzerpfade, unbekannte Schlüssel werden übersprungen, Projekt- und Teamwerte bleiben, vor Import und Zurücksetzen eine Sicherung unter `%APPDATA%\Atlas\Backups` (abschaltbar mit `settings.backupBeforeImport`). Das Ergebnis zeigt eine Meldung (mit `/quiet` keine); Exit-Code 0 = erledigt oder nichts zu tun, 1 = Aufruf falsch, 2 = Datei fehlt oder ist keine Einstellungsdatei, 3 = Schreiben gescheitert. Eine laufende IDE übernimmt die Werte erst beim nächsten Start; speichert sie vorher ihre Optionen, gelten wieder deren Werte.

**Updates:** Nach Zustimmung beim ersten Start prüft das Plugin höchstens einmal täglich, ob eine neue Version vorliegt, und meldet sie in der Meldungsansicht ([RAD-Studio.md](RAD-Studio.md)). Es lädt nichts herunter.

### Ohne Plugin: Code Insight-Manager (Kurzanleitung)

Wer nur den Server ohne Plugin nutzen will, trägt ihn im eingebauten LSP-Client der IDE ein (#175, ausführlich in [RAD-Studio.md](RAD-Studio.md#eingebauter-lsp-client)):

1. *Tools › Optionen › Editor › Sprache › Code Insight › Code Insight-Manager › Neu*: Name `Atlas`, ausführbare Datei `AtlasServer.exe`, Timeout `15000`, InitializationOptions `{}`, Sprache beliebig.
2. IDE schließen und unter `HKCU\Software\Embarcadero\BDS\<Version>\LSP\UserDefined\Atlas` den Wert `LanguageId` auf `Delphi` setzen.
3. IDE starten und im Code Insight-Manager für Delphi „Atlas“ wählen.

Dann laufen Syntaxfehler, Hover (als Klartext), Gliederung und Vervollständigung über Atlas. Häufige Serverstarts im Log sind normal: Die IDE startet ihren Server je IDE und bei jedem Projektwechsel neu und beendet ihn hart; der nächste Start meldet das im Log.

## Claude Code

Als MCP-Server (Index-Werkzeuge für den Agenten):

```
claude mcp add delphi -- AtlasServer.exe --mcp --root C:\Projekte\App
```

Mit Diagnosen und Navigation als Plugin: [Editors/ClaudeCode/README.md](../Editors/ClaudeCode/README.md). Werkzeuge: [MCP.md](MCP.md).

## Ohne Editor (CI)

```
AtlasServer.exe --check App.dproj --format sarif --output befunde.sarif
```

Weitere Optionen stehen in der [README](../README_DE.md).

## Weiter

- [Konfiguration.md](Konfiguration.md): alle Schlüssel von `atlas.json`
- [Regeln.md](Regeln.md): alle Prüfregeln mit Beispielen und Unterdrückung per `// lsp-ignore: <regel>`
