# Installation

Atlas ist eine einzelne Datei, `AtlasServer.exe` (Windows, Win64). Sie spricht LSP über stdio, mit `--mcp` MCP für KI-Agenten und mit `--check` prüft sie ohne Editor. Eine installierte RAD-Studio-Version braucht der Server nur für Compiler-Meldungen (`compiler.onSave`); die passende Version liest er aus der `.dproj`.

## Server besorgen

- **Release:** `AtlasServer.exe` aus dem neuesten [GitHub-Release](https://github.com/xKnockOut/Atlas-IDE-Expert/releases) laden und in einen Ordner im `PATH` legen.
- **Selbst bauen:** `Atlas.groupproj` in RAD Studio öffnen und Win64 bauen; die EXE liegt unter `Output\Win64\<Config>\Bin\`.

## RAD Studio (Release-Paket)

Das Plugin `Atlas.IDE.Expert` bindet den Server in die IDE ein: [RAD-Studio.md](RAD-Studio.md).

Für das IDE-Plugin (#495) enthält jedes Release `atlas-ide-expert-<Version>.zip`:

```
AtlasServer.exe         Server (Win64)
AtlasServer.map         Map-Datei: Stacktraces im Server-Log mit Unit, Routine und Zeile
Win32\Atlas.IDE.Expert370.bpl   Plugin für die klassische IDE
Win64\Atlas.IDE.Expert370.bpl   Plugin für die 64-Bit-IDE
Win32\Atlas.IDE.Expert370.map, Win64\…   Map-Dateien des Plugins für Stacktraces im atlas.log
LICENSE, THIRD-PARTY-NOTICES.md
EULA.txt                Lizenzvereinbarung
whatsnew.json           Neuerungen je Version für die Karte „Neu in Atlas“ (#756)
Beispiele\              Beispieldateien zu „Ausprobieren“ auf dieser Karte und auf „Atlas entdecken“
tips.json               Tipps für die Karte „Atlas entdecken“ und die Tastenkürzel-Tipps (#757)
Tipps\                  Bilder (PNG) zu diesen Tipps
Doku\                   Doku als HTML für „Atlas-Doku“ auf der Willkommensseite (#766)
Vorlagen\               Vorlagen für atlas.json („Projekt für Atlas einrichten“ auf der Willkommensseite, #759)
Profile\                Einstellungsprofile „Atlas-Standard“, „Minimal“ und „Alles an“ (#723)
```

Bis 1.1.0 lag dem Paket der Installer `AtlasSetup.exe` bei (ADR 0009). Seit 1.2.0 gibt es ihn nicht mehr; das Paket wird von Hand eingebunden:

1. Delphi schließen und das ZIP in einen festen Ordner entpacken, z. B. `%LOCALAPPDATA%\Programs\Atlas` (dort lag auch die Installation des früheren Installers). Die Ordnerstruktur beibehalten: Das Plugin sucht den Server und die Daten (`whatsnew.json`, `tips.json`, `Vorlagen` …) neben der BPL und eine Ebene darüber.
2. Delphi starten, *Komponente › Packages installieren › Hinzufügen* und `Win32\Atlas.IDE.Expert370.bpl` wählen (Delphi 12: `…290.bpl`, sofern im Paket; 64-Bit-IDE ab Delphi 12.3: `Win64\…`).
3. Delphi einmal neu starten: Atlas schaltet Help Insight und die Strukturhervorhebung der IDE ab, die IDE liest diese Schalter nur beim Start.

**Deinstallieren:** *Komponente › Packages installieren*, „Atlas IDE Expert“ wählen und „Entfernen“, danach den Ordner löschen. Einstellungen (`HKCU\Software\Atlas`, `%APPDATA%\Atlas`), Index und Protokolle (`%LOCALAPPDATA%\Atlas`) und eigene Snippets (`%APPDATA%\Atlas\Snippets`) bleiben und lassen sich von Hand löschen. Eine Installation mit dem früheren Installer entfernt weiterhin der Eintrag „Atlas IDE Expert“ unter *Einstellungen › Apps › Installierte Apps*.

**Aktualisieren:** Delphi schließen, das ZIP der neuen Version über den alten Ordner entpacken (die Ordner `Beispiele`, `Tipps`, `Doku`, `Vorlagen` und `Profile` vorher löschen) und Delphi starten. Ändert sich die Package-Version im Namen der BPL nicht, bleibt die Registrierung gültig. Einstellungen, Favoriten, `.atlas`-Dateien der Projekte und Snippets bleiben unberührt. Ändert sich das Format des Index, verwirft der Server den alten Cache und baut ihn neu auf (#492).

**Einstellungen übertragen (#723):** *Tools › Optionen › Atlas* und die Befehlspalette (*Atlas.SettingsExport*, *Atlas.SettingsImport*, *Atlas.SettingsProfile*, *Atlas.SettingsReset*) exportieren, importieren und setzen die persönlichen Einstellungen des Plugins je Bereich zurück, siehe [Einstellungen.md](Einstellungen.md#bereiche-für-export-import-und-zurücksetzen). Die Kommandozeile `AtlasSetup /exportSettings …` gibt es mit dem Installer nicht mehr.

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
