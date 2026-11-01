# Atlas in Claude Code

*Deutsche Fassung: [README.md](README.md)*

## Installation

### As a plugin from the marketplace (recommended)

1. Put `AtlasServer.exe` into a folder on the `PATH` ([getting the server](../../docs/en/Installation.md#getting-the-server)).
2. In Claude Code:

   ```
   /plugin marketplace add xKnockOut/Atlas-IDE-Expert
   /plugin install atlas@atlas
   ```

The plugin brings:

- **LSP** (`.lsp.json`): diagnostics and navigation for `.pas`, `.dpr`, `.dpk`, `.inc`, `.dfm` and `.fmx`
- **MCP** (`.mcp.json`): the tools from [docs/en/MCP.md](../../docs/en/MCP.md), the resource `delphi://conventions`, resource templates (`@delphi:delphi://unit/UI.Auftrag`) and the prompts `unit_review`, `explain_form`, `write_tests`, `fix_finding`, `prepare_commit` as slash commands (#1357; with `claude mcp add delphi …` they are called `/mcp__delphi__unit_review`, via the plugin the plugin name comes first; typing `/unit_review` finds them)
- **Skill** `delphi-mit-atlas`: which tool helps when (e.g. `find_symbol` instead of text search, `rename_symbol` instead of search and replace)
- **Hook** (`hooks/hooks.json`): after every Edit/Write the MCP tool `hook_check` checks the changed Pascal file with the project's check rules and returns warnings and errors to Claude immediately; it skips other files. With `"minDelphiVersion": "12"` in atlas.json it also reports language features that Delphi 12 does not know (if expression, `is not`, `not in`; rule `language-feature`). Switch off: `"mcp": {"disabledTools": ["hook_check"]}`
- **Command** `/atlas:bauen [make|build|check] [Projekt] [--ohne-tests]`: builds (the project's own `Tools/Build-Test.ps1` or `build_project` in the running IDE), runs the tests and summarises the result against 0 errors, 0 warnings, 0 hints

Which route for what: plugin commands like `/atlas:bauen` are workflows with hooks and programs on the machine (build, tests). The server's prompts are everything that needs its data (review, explain form, write tests, fix finding, prepare commit); they deliver the results of the tools right in the message and run in every MCP program. Switch off with `"mcp": {"prompts": false}`, custom prompts in `mcp.customPrompts` ([docs/en/MCP.md](../../docs/en/MCP.md#prompts)).

Without `PATH`: every release contains `atlas-claude-plugin-<Version>.zip` with the EXE under `bin/`. Extract it and start with `claude --plugin-dir <Ordner>/atlas` or register the folder as a local marketplace.

The version of the plugin and the marketplace entry is set by `Tools/Set-Version.ps1` with the release version; `Tools/Check-Version.ps1` checks it.

### In cloud sessions (Linux)

In Claude Code sessions in the cloud, `Tools/Linux/Build-AtlasServer.sh --install /usr/local/bin` installs the server as `/usr/local/bin/AtlasServer` together with a link `AtlasServer.exe`; the plugin finds it there ([ADR 0013](../../docs/adr/0013-linux-bau.md), German). The script downloads the finished program from the pre-release `cloud-linux` (built by the workflow `linux-server.yml` on every push to main) as long as the source matches, and otherwise builds with the prebuilt FPC from the same release (about 2 minutes).

Claude Code starts the MCP server when the session starts and does not try again afterwards. The server must therefore be there beforehand. For this, enter in the **setup script of the cloud environment** (project settings › environment › gear icon):

```bash
#!/bin/bash
# Atlas: AtlasServer für das Claude-Code-Plugin bereitstellen (MCP und LSP)
for skript in /home/user/*/Tools/Linux/Build-AtlasServer.sh; do
  [ -x "$skript" ] && "$skript" --install /usr/local/bin && break
done
exit 0
```

In addition, the SessionStart hook of this repository (`.claude/hooks/session-start.sh`) calls the same script; if the server is already there, this only costs the fingerprint comparison. Hooks from `.claude/settings.json` apply in Claude projects only if the project has exactly one repository.

Check: `claude mcp list` shows `plugin:atlas:delphi` as connected.

### MCP tools only (one command)

```
claude mcp add delphi -- AtlasServer.exe --mcp --root C:\Projekte\App
```

Alternatively copy `atlas/.mcp.json` into the project (without `--root` the working directory applies). Writing tools can be switched off with `mcp.disabledTools` in `atlas.json` or `--restricted`.

### Testing the plugin from the repository

```
claude plugin validate Editors/ClaudeCode/atlas
claude --plugin-dir Editors/ClaudeCode/atlas
```
