# Atlas in Claude Code

## Installation

### Als Plugin aus dem Marketplace (empfohlen)

1. `AtlasServer.exe` in einen Ordner im `PATH` legen ([Server besorgen](../../docs/Installation.md#server-besorgen)).
2. In Claude Code:

   ```
   /plugin marketplace add xKnockOut/Atlas-IDE-Expert
   /plugin install atlas@atlas
   ```

Das Plugin bringt mit:

- **LSP** (`.lsp.json`): Diagnosen und Navigation für `.pas`, `.dpr`, `.dpk`, `.inc`, `.dfm` und `.fmx`
- **MCP** (`.mcp.json`): die Werkzeuge aus [docs/MCP.md](../../docs/MCP.md), die Ressource `delphi://conventions`, Ressourcen mit Vorlage (`@delphi:delphi://unit/UI.Auftrag`) und die Prompts `unit_review`, `explain_form`, `write_tests`, `fix_finding`, `prepare_commit` als Schrägstrich-Befehle (#1357; mit `claude mcp add delphi …` heißen sie `/mcp__delphi__unit_review`, über das Plugin steht der Plugin-Name davor; `/unit_review` tippen findet sie)
- **Skill** `delphi-mit-atlas`: wann welches Werkzeug hilft (z. B. `find_symbol` statt Textsuche, `rename_symbol` statt Suchen und Ersetzen)
- **Hook** (`hooks/hooks.json`): Nach jedem Edit/Write prüft das MCP-Werkzeug `hook_check` die geänderte Pascal-Datei mit den Prüfregeln des Projekts und gibt Warnungen und Fehler sofort an Claude zurück; andere Dateien übergeht es. Mit `"minDelphiVersion": "12"` in atlas.json meldet es auch Sprachmerkmale, die Delphi 12 nicht kennt (If-Ausdruck, `is not`, `not in`; Regel `language-feature`). Abschalten: `"mcp": {"disabledTools": ["hook_check"]}`
- **Befehl** `/atlas:bauen [make|build|check] [Projekt] [--ohne-tests]`: baut (eigenes `Tools/Build-Test.ps1` des Projekts oder `build_project` in der laufenden IDE), führt die Tests aus und fasst das Ergebnis nach 0 Fehlern, 0 Warnungen, 0 Hinweisen zusammen

Welcher Weg wofür: Plugin-Befehle wie `/atlas:bauen` sind Abläufe mit Hooks und Programmen auf dem Rechner (Build, Tests). Die Prompts des Servers sind alles, was seine Daten braucht (Review, Formular erklären, Tests schreiben, Befund beheben, Commit vorbereiten); sie liefern die Ergebnisse der Werkzeuge gleich in der Nachricht mit und laufen in jedem MCP-Programm. Abschalten mit `"mcp": {"prompts": false}`, eigene Prompts in `mcp.customPrompts` ([docs/MCP.md](../../docs/MCP.md#prompts)).

Ohne `PATH`: Jedes Release enthält `atlas-claude-plugin-<Version>.zip` mit der EXE unter `bin/`. Entpacken und mit `claude --plugin-dir <Ordner>/atlas` starten oder den Ordner als lokalen Marketplace eintragen.

Die Version von Plugin und Marketplace-Eintrag setzt `Tools/Set-Version.ps1` mit der Release-Version; `Tools/Check-Version.ps1` prüft sie.

### In Cloud-Sitzungen (Linux)

In Claude-Code-Sitzungen in der Cloud legt `Tools/Linux/Build-AtlasServer.sh --install /usr/local/bin` den Server als `/usr/local/bin/AtlasServer` samt Verweis `AtlasServer.exe` ab; das Plugin findet ihn dort ([ADR 0013](../../docs/adr/0013-linux-bau.md)). Das Skript lädt das fertige Programm aus dem Vorab-Release `cloud-linux` (baut der Workflow `linux-server.yml` bei jedem Push auf main), solange der Quelltext dazu passt, und baut sonst mit dem fertigen FPC aus demselben Release (etwa 2 Minuten).

Claude Code startet den MCP-Server beim Start der Sitzung und versucht es danach nicht erneut. Der Server muss deshalb schon vorher da sein. Dafür im **Setup-Skript der Cloud-Umgebung** (Projekteinstellungen › Umgebung › Zahnrad) eintragen:

```bash
#!/bin/bash
# Atlas: AtlasServer für das Claude-Code-Plugin bereitstellen (MCP und LSP)
for skript in /home/user/*/Tools/Linux/Build-AtlasServer.sh; do
  [ -x "$skript" ] && "$skript" --install /usr/local/bin && break
done
exit 0
```

Zusätzlich ruft der SessionStart-Hook dieses Repositorys (`.claude/hooks/session-start.sh`) dasselbe Skript auf; ist der Server schon da, kostet das nur den Vergleich des Fingerabdrucks. Hooks aus `.claude/settings.json` gelten in Claude-Projekten nur, wenn das Projekt genau ein Repository hat.

Prüfen: `claude mcp list` zeigt `plugin:atlas:delphi` als verbunden.

### Nur MCP-Werkzeuge (ein Befehl)

```
claude mcp add delphi -- AtlasServer.exe --mcp --root C:\Projekte\App
```

Alternativ `atlas/.mcp.json` ins Projekt kopieren (ohne `--root` gilt das Arbeitsverzeichnis). Schreibende Werkzeuge lassen sich mit `mcp.disabledTools` in `atlas.json` oder `--restricted` abschalten.

### Plugin aus dem Repository testen

```
claude plugin validate Editors/ClaudeCode/atlas
claude --plugin-dir Editors/ClaudeCode/atlas
```
