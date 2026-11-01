# MCP mode

*Deutsche Fassung: [MCP.md](../MCP.md)*

With `--mcp`, Atlas offers the symbol index of a project folder via the
Model Context Protocol (stdio, one JSON message per line). An AI assistant
can use it to answer questions about the project without reading source files in full.

```
claude mcp add delphi -- AtlasServer.exe --mcp --root C:\Projekte\App
```

`--root` is the folder with `atlas.json` or the .dproj; if omitted, the
current directory. `--log <Datei>` writes a log; stdout belongs solely
to the protocol.

If `--root` contains exactly one `.groupproj`, the server additionally indexes all
other projects of the group into the same index (`index.projectGroup`, on by default).
This way it also finds units contained only in another project of the group when
`project` in `atlas.json` points to a single project.

Path parameters (#99): relative to `--root` or absolute; they are normalised
(`..`, junctions, symlinks, subst drives resolved) and accepted only in the working folder
and in the project's search and library paths. Anything else
results in a tool error with a reason. Writing happens only in the working folder.

## Security (#99)

- Every tool is read-only, writing, or starts a process.
- `mcp.disabledTools` in `atlas.json` switches off tools individually, e.g.
  `"mcp": { "disabledTools": ["rename_symbol", "apply_code_action"] }`. Disabled
  tools are missing from `tools/list`; a call results in a tool error with a reason.
- With `--restricted` (#186) only read-only tools are available.
- Like the LSP server, the MCP server also reads the global file `%APPDATA%\Atlas\settings.json`
  (that is where `mcp.disabledTools` normally lives, as do index and hint settings). With
  `"mcp": { "globalSettings": false }` in `atlas.json` only the project file applies (D-08).
- Writing tools have `dryRun` with default `true`: they then only return the diff.
  With `dryRun: false` they write atomically: if a file has changed since it was read
  or has unsaved changes in the IDE (the IDE plugin reports this in
  `%LOCALAPPDATA%\Atlas\editor-dirty-<pid>.json`), nothing is written; if writing
  a file fails, the files already written are restored. Encoding and line endings
  are preserved (#121).
- If a file is open in an IDE with the Atlas plugin, the MCP server does not write it itself (#397):
  it puts the change into the plugin's inbox (`%LOCALAPPDATA%\Atlas\ide-edits\<pid>\`), which applies it
  to the buffer as one undo step and saves the file. The change appears
  immediately in the editor. If the plugin does not accept the job within 3 s, the MCP server writes
  the file itself as before; the IDE's reload then picks up the file.
- Every writing call is logged with tool, parameters and changed files
  (`--log`).

## Resources

| URI | Content |
|---|---|
| `delphi://conventions` | Project conventions as Markdown (#272): rule profile, format style, naming rules and every active check rule with severity and short text from the rule catalog. Read before writing, check with `check_code` afterwards |
| `delphi://build/last` | Result and compiler messages of the last build in the IDE, like `get_last_build` (#1357, with `mcp.prompts`) |

Resource templates (#1357, `resources/templates/list`) are attached to a question in Claude Code with `@`, e.g. `@delphi:delphi://unit/UI.Auftrag`. The value in `{…}` may be %-encoded (`Source%2FA.pas`). Units and paths are treated like path parameters (#99): outside the working folder and its search and library paths, reading results in an error with a reason. The content is Markdown, at most 64 KB; beyond that it is truncated with a pointer to the tool for the full content.

| Template | Content |
|---|---|
| `delphi://unit/{name}` | Outline (`get_unit_outline`) and interface part of a unit; `name` is a unit name or a path |
| `delphi://form/{file}` | Component tree of a form (`get_dfm_info`); `file` is the .dfm/.fmx or the matching .pas |
| `delphi://findings/{file}` | Syntax errors and check rule findings of a file (`get_diagnostics`) |

## Prompts

Prompts (#1357) are ready-made workflows. Claude Code shows them after `/` as commands `/mcp__delphi__<name>` with description and arguments. `prompts/get` returns a message with instructions and the results of the required tools; Claude does not have to ask for each one first, and every workflow is equally thorough every time. The tools run with the same rules as `tools/call`: disabled ones (`mcp.disabledTools`) are missing from the text with a reason; with `--restricted` the instructions offer no writing steps (no fixes, no `run_tests`, no commit; suggestions as a diff).

| Prompt | Arguments | What the message contains |
|---|---|---|
| `unit_review` | `unit` | Outline, findings (`get_diagnostics`), metrics above the limit (`get_metrics`), unused code (`find_unused_code`), `delphi://conventions`; instructions for a review by severity with suggestions and `check_code` before every change |
| `explain_form` | `file` | Component tree (`get_dfm_info`), event handlers with bodies from the unit (shared handlers once with all components), data bindings (`DataSource`, `DataField`, `Connection`, LiveBindings …); instructions for explaining the form |
| `write_tests` | `name` | Declaration (`get_declaration`), callers (`get_call_hierarchy`), impact with the existing tests (`get_impact`), the project's DUnitX conventions (`testUnits.pattern`, `.folder`, `.project`); instructions for new test methods in the matching test unit and a run with `run_tests` |
| `fix_finding` | `file`, `line`, optional `rule` | Explanation (`explain_finding`), code snippet ±8 lines with the line marked, available fixes (`apply_code_action` without `title`); instructions: first the cause, then the fix, then `check_code` |
| `prepare_commit` | optional `base` | Changed files according to Git or SVN (without `base` the uncommitted ones against HEAD, otherwise since branching off `base`), new findings only in changed lines (like `--changed-lines`), affected tests (with `get_affected_tests` from #1353, otherwise the pointer to `get_impact`), commit prefix of the current issue (`issues.commitPattern`, from the plugin in `<gitdir>/atlas-commit-prefix`); instructions for the check and the commit message |

Examples in Claude Code:

```
/mcp__delphi__unit_review UI.Auftrag
/mcp__delphi__explain_form Source\UI.Auftrag.dfm
/mcp__delphi__write_tests TAuftrag.Speichern
/mcp__delphi__fix_finding Source\UI.Auftrag.pas 42 empty-except
/mcp__delphi__prepare_commit main
@delphi:delphi://unit/UI.Auftrag Wo wird hier die Mehrwertsteuer berechnet?
```

The instructions are in German; with `"mcp": { "promptLanguage": "en" }` in English. `"mcp": { "prompts": false }` switches off prompts and templates: `prompts/list` and `resources/templates/list` are then empty, `delphi://build/last` is missing; the tools remain. Both keys are in the global `settings.json` (page *MCP*).

The project's own prompts are in `atlas.json` under `mcp.customPrompts`. Placeholders `{argument}` in the text are replaced (unknown ones remain), `include` appends results: `outline`, `diagnostics`, `metrics`, `unused`, `todos`, `form`, `impact`, `dependencies`, `conventions`, `lastBuild`. The contents take the argument `file`, `unit` or (for `impact`) `name`; for file contents a unit is resolved as in `unit_review`. The names of the built-in prompts are taken: a custom one with the same name is missing from the list.

```json
{
  "mcp": {
    "customPrompts": [
      {
        "name": "check_unit",
        "description": "Unit vor dem Review prüfen",
        "arguments": [{ "name": "unit", "description": "Unit-Name", "required": true }],
        "text": "Prüfe {unit}: Befunde zuerst, dann Methoden über den Grenzwerten.",
        "include": ["diagnostics", "metrics"]
      }
    ]
  }
}
```

Prompts compared with the commands of the Claude Code plugin (`/atlas:bauen`): the plugin commands are workflows with hooks and tools on the machine (building, running tests); prompts are everything that gets its data from the server, and they work in every MCP program. They have no effect in the IDE plugin.

## Tools

| Tool | Parameters | Result |
|---|---|---|
| `find_symbol` | `name` | Locations with kind, type, unit, file:line; without an exact hit, substring search |
| `get_declaration` | `name` | Source text of the declaration, also from RTL/VCL; plus the section “Begründungen:” (rationale, #1123) with `// WHY:`, `// HACK:`, `// NOTE:` … above the declaration and in the body of the implementation, per entry marker, line and text (off with `hints.rationale`) |
| `get_type_hierarchy` | `name` | Ancestors up to the root, descendants recursively |
| `get_component_info` | `name` | Published properties with type and default (explicit, implicit, `nodefault`, `stored`), events with signature, ancestor chain, palette page from `RegisterComponents`, package from `contains` of the .dpk; without sources a note instead of an empty list |
| `get_unit_outline` | `unit` | uses lists and symbols of a unit with line numbers |
| `find_references` | `name` | Usages in the project with file:line and source line; first the certain ones, then “Erschlossen, vor dem Umbenennen prüfen:” (inferred, check before renaming) with reason and explanation (interface, overridden method, unclear overload, unknown type, inactive branch, text), header line “n Verwendungen …, a sicher, b erschlossen” (#1119, `references` in atlas.json) |
| `get_call_hierarchy` | `name`, `direction` | Callers (`incoming`) and callees (`outgoing`), default both; inferred callers come after the certain ones with a reason (#1119); calls via an interface or a virtual method carry “[über Interface, n Umsetzungen]” or “[virtuell, n Umsetzungen]” (#1122) |
| `get_impact` | `name`, `depth` (1–5, optional), `format` (`text` or `json`) | Impact analysis (#1120): what is affected if the symbol changes. Callers and references, overrides, overridden base method, interface method and implementations, form bindings; as a tree by level and cause, inferred hits with a reason. Then the affected DUnitX tests and a line `run_tests tests: …` with the names for `run_tests`, at the end the limits reached (depth, 1000 places, 60 s). Without `depth`, `navigation.impactDepth` applies; `json` returns the same as `atlas/impact` |
| `get_affected_tests` | `base` (Git ref or SVN revision; empty = `main` or `BASE`), `includeUncommitted` (default `true`), `depth` (1–5), `format` (`text`, `json` or `dunitx`; all optional) | Starts a process (git or svn, #1353): affected tests of a change. From the difference to the base (like `--changed`, according to `vcs.provider`) the changed routines, types and constants; changes in the interface count for the symbol, outside routines (uses, initialization) for the whole unit, `.dfm`/`.fmx` for the form class, `.inc` for the including units; empty lines and comments do not count. It traces their impact like `get_impact` up to the depth (default `tests.affectedDepth`, 3) and names the DUnitX tests as `Unit.Fixture.Methode` with a reason (changed place → path, inferred steps marked); if more than 80 % of a fixture is affected, the whole fixture. `json`: `run` fits directly into `run_tests.tests`, `all: true` with `reason` if all tests are needed (test program changed, analysis incomplete). `dunitx`: only the argument `--run:…` for the test EXE. Missing with `tests.affected = false` |
| `qualified_name` | `file`, `line`, `column`, `withParameters` (optional) | Fully qualified name of the symbol at the position, e.g. `Vcl.Controls.TControl.Paint`; with `withParameters`, for routines including parameter types |
| `get_diagnostics` | `file` (optional) | Syntax errors and rule findings of a file or of all project files |
| `hook_check` | `file`, `severity` (`error`, `warning`, `information`, `hint`; default `warning`) | For Claude Code hooks: findings from `severity` upwards of a file just edited, as the output of a PostToolUse hook (`{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"…"}}`), so that Claude sees them right after Edit/Write. Empty (no notice) for files without the extension `.pas`, `.dpr`, `.dpk`, `.inc`, outside the workspace or without findings. The plugin `atlas` calls it via `hooks/hooks.json`; switch off with `"mcp": {"disabledTools": ["hook_check"]}` |
| `get_metrics` | `file` (optional), `format` (`markdown` or `json`) | Code metrics per method (#66): length in lines of code, nesting depth, cyclomatic and cognitive complexity, parameter count; report with the methods above a limit from `atlas.json` (rules `metric-*`, option `max`) or the metric data as JSON |
| `get_todos` | `file`, `unit`, `category`, `owner`, `keyword`, `includeDone` (all optional), `format` (`markdown` or `json`) | TODO overview (#68) of all files that the project model assigns to the project: `// TODO`, `// FIXME` and the format of the IDE's To-Do List `{ TODO 1 -oPerson -cKategorie : Text }` with priority, person and category, filtered by unit, category, person or marker; completed entries (`{ DONE … }`) only with `includeDone`. More markers via the option `keywords` of the rule `todo-comment`. Markdown with counts by category and person and one table per unit, or JSON (`format` 1, lines from 1) |
| `get_rationale` | `unit` or `name` | Rationale (#1123) of a unit (comments in the interface before the first type and all symbols with a location) or of a symbol (above the declaration and in the body of the implementation), per entry marker, line from 1 and text. Markers from `hints.rationaleMarkers` (default `NOTE`, `WHY`, `HACK`, `IMPORTANT`, `RATIONALE`); markers of the TODO overview never appear. Also works with `hints.rationale` off; can be switched off via `mcp.disabledTools` |
| `get_architecture` | `section` (`overview`, `central`, `subsystems`, `cycles`, `crossLinks`; default `overview`), `unit` (optional), `compareWith` (optional, path relative to the project), `resolution` (optional, 0.2 to 5.0; granularity of the subsystems for this call, otherwise `architecture.grouping.resolution`, #1366) | Architecture overview (#1118) from the uses graph: subsystems (Louvain groups of tightly connected units, oversized and loose ones subdivided and marked as “Teil von …” (part of), #1364; cross-cutting foundation units in the subsystem “Fundament” with a rule, #1365) with names, central units, cycles and cross links between subsystems, each with file:line of the uses entries; with `unit` the profile of a unit, with `architecture.explainAssignment` (default on, #1368) including the block “Zuordnung” (assignment): edges per subsystem (interface, impl., weighted sum; edges to the foundation “zählt nicht” (does not count)) and, for a close assignment, how many edges are missing for a switch; with `compareWith` (saved state from `AtlasServer --architecture <Datei.json>` or “Save state …”, #1121) the sections of the comparison: new and removed cycles, cross links and uses edges between subsystems, subsystem changes, grown central units, new and removed units and which kinds from `architecture.failOn` occur. Colours and names of the subsystems are aligned to the previous state as in the window (#1367, `architecture.grouping.keepPrevious`; line “Teilsysteme an Stand vom … angeglichen”). Scope (`architecture.scope`), library units and exclusions from `atlas.json`; the same numbers as the “Atlas architecture” window and `--architecture`. Not offered with `architecture.enabled` = false |
| `query_code` | `query` (query or `@name`; empty = short help with all sets, fields and predicates), `format` (`markdown` or `json`), `limit` (default 200) | Code queries over the index (#1351): `<Menge> where <Bedingung> [order by <Feld> [asc\|desc]] [limit n]` over `units`, `classes`, `records`, `interfaces`, `methods`, `routines`, `fields`, `properties`, `forms`; fields such as `name`, `unit`, `visibility`, `methods`, `lines`, `complexity`, `cognitive`, `nesting`, `params`, `callers`, `callees`, `overrides`, `uses`, `usedBy`, `ancestor`, `components`; predicates `inherits` (transitive), `implements`, `uses`, `calls`, `has attribute`, comparisons, `like` with `*`/`?`, `and`, `or`, `not`, parentheses. Numbers as in `get_metrics` and `find_unused_code`; inferred calls (#1119) count and are marked. An error comes in German with column and suggestion. Saved queries from `queries` in `atlas.json` via `@name`. Read-only; missing with `query.enabled` off |
| `get_hotspots` | `level` (`unit` or `method`; default `unit`), `limit` (default 20), `months` (1–60; default `hotspots.months`), `section` (`hotspots` or `coupling`; default `hotspots`), `format` (`text`, `markdown`, `json`; default `text`) | Hotspots (#1354): units or methods that were changed often in the period and are complex at the same time (score = normalised changes × normalised cognitive complexity), with changes, authors, lines, trend of complexity compared with the state three months ago and last change from Git or SVN (`vcs.provider`, renames tracked); with `section` = `coupling` the change coupling: pairs with at least `hotspots.coupling.minCommits` shared commits and a share of at least 70 %, without a uses edge between them (without .pas/.dfm pairs, without commits with more than 50 files). Without version control a note instead of data; the same numbers as the “Atlas hotspots” window and `--hotspots`. Not offered with `hotspots.enabled` = false |
| `get_server_status` | `format` (`markdown` or `json`; default `markdown`) | Status of the Atlas server (#1356) with the same numbers as the IDE's “Atlas server” window: process, version, uptime, state (loading, ready, checking), memory per area (symbols, usages, library units, syntax trees, open documents, rest) against the budget, last check run with the 10 slowest units and rules, queue, cache hits and the slowest requests. The MCP process reads the last status of the IDE's server for the project folder from `%LOCALAPPDATA%\Atlas\Status\server-<pid>.json` (written by the server on every status query, at most 60 s old); if none is running, the status of this MCP process is returned. The first line or `source` names the source. Read-only; can be switched off via `mcp.disabledTools` |
| `find_unused_code` | `file` (optional), `format` (`markdown` or `json`) | Unused code (#64) of a file or of all project files with the index of all projects of the group, as in the editor: the findings of `unused-private-member`, `unused-public-member`, `unused-declaration` and `unused-unit` with line, column, rule and confidence, one section per file (at most 200 findings). Severity, `off`, options and `deadCode.keepAttributes`/`keepPatterns` from `atlas.json` apply. While projects are loading or the index is running, the project-wide rules stay silent; the report says so (JSON: `incomplete`) |
| `get_unit_dependencies` | `unit` (name or path), `direction` (`uses`, `usedBy`, `both`; default `both`), `transitive` (optional), `format` (`markdown` or `json`) | Dependencies of a unit from the uses graph (#64, #268): direct uses and the units that use it, each with section (`interface`/`implementation`), with `transitive` the closures in both directions, plus the cycles through the unit with the full path (pure interface cycles as compiler errors like F2047). Only units of the projects, without RTL/VCL |
| `find_path` | `from`, `to` (as for `find_symbol`: type, `TFoo.Bar`, routine, field, property or unit), `via` (optional: `uses`, `inherits`, `implements`, `hasField`, `parameter`, `result`, `calls`, `contains`, `library`; default all edge kinds, library units no pass-through), `maxSteps` (1–16, default 8), `all` (all equally short paths, at most 5) | Shortest path between two symbols or units (#1117) in one call: “Kürzester Weg (N Schritte):” (shortest path), per node symbol and file:line, per step edge kind (uses, inherits from, implements / implemented by, has field / of type, parameter of type, result of type, calls, contains) with location; only inferred edges (several implementations) carry `[erschlossen]`. Two stages: first over the index edges (bidirectional breadth-first search), call edges only for routines on candidate paths. Equally long paths sorted deterministically (ranking of edge kinds, then name). “Kein Weg in höchstens N Schritten.” (no path in at most N steps) is reliable; on time limit (`requestTimeoutMs`), cancellation (`notifications/cancelled`) or 20 000 nodes “Kein Weg gefunden in N Schritten (Suche nach X Knoten abgebrochen: Grund).”; ambiguous name: list of hits with locations. With `via: ["uses"]` the same result as the shortest path of the architecture map. Not offered with `navigation.symbolPath` = false |
| `check_code` | `file`, `text`, `startLine`/`endLine` (optional) | Checks planned code without writing: syntax errors, rule findings, unresolvable identifiers. Without a range `text` is the whole unit, otherwise the replacement for lines `startLine`..`endLine` |
| `get_dfm_info` | `file` | Component tree of a text form with properties and events |
| `get_last_build` | `project` (optional) | Last build the user started in the IDE (via the IDE plugin, #556): result, kind, time, duration, project, configuration, platform, number of errors/warnings/hints and all messages with file, line, column (1-based), code and text; messages outside `--root` are left out. Without a build: “Noch kein Build …” (no build yet). Exchange via `%LOCALAPPDATA%\Atlas\build-*.json`, written by the LSP server |
| `build_project` | `project`, `mode` (`make`, `build`, `check`; default `make`), `configuration`, `platform` (all optional) | Starts a process (#261): builds a project in the running RAD Studio IDE via the Atlas plugin (IOTAProjectBuilder), even without a command-line compiler (Starter Edition), and returns the result like `get_last_build`. The project must be open in an IDE with the Atlas plugin; without `project` the active project if it lies under `--root`. Configuration and platform apply only to this build. Exchange via `%LOCALAPPDATA%\Atlas\ide-builds\<pid>\`; if the plugin does not accept the job within 5 s (switched off via “Builds for Claude Code”, debugger or another build active), the tool reports the reason |
| `run_tests` | `project`, `tests` (list of `Unit.Fixture` or `Unit.Fixture.Methode`), `build` (default `false`), `configuration`, `platform`, `timeoutSeconds` (default 600, at most 3600; all optional) | Starts a process (#69): runs the DUnitX tests of a test project. The test project is a `.dproj` under `--root` whose main file uses `DUnitX.TestFramework`; without `project` the only such one. The platform comes from the project (the file's default, otherwise the first enabled one; a Win64-only project runs as Win64), the test EXE from `DCC_ExeOutput` and the main file. An existing EXE runs without a compiler; with `build: true` it builds beforehand in the running IDE like `build_project` (without an IDE with the Atlas plugin it reports the reason; if the build fails, no tests run). Called with `--exitbehavior:Continue --xmlfile:<temp> [--run:…]`; the test program needs DUnitX's XML logger (`TDUnitXXMLNUnitFileLogger`, as in RAD Studio's template), otherwise `result: noReport` with the last lines of output. Result as JSON: `result` (`passed`, `failed`, `noTests`, `noReport`), project, configuration, platform, EXE, exit code, counts (`total`, `passed`, `failed`, `errors`, `skipped`, `durationMs`) and per failed test (at most 100) name, message, `expected`/`actual` (from “Expected … but got …”), file and line (1-based) of the method header. Runs via MCP do not appear in the project summary of the welcome page; only runs from the IDE do |
| `explain_finding` | `file`, `line`, `rule` (optional) | Findings of a line as Markdown (#158): rule with description, code snippet with the line marked, before/after example from the rule catalog. |
| `rename_symbol` | `file`, `line`, `column`, `newName`, `dryRun` (default `true`) | Writing (#61): renames the symbol at the position project-wide, including `.dfm`/`.fmx` and automatically named event handlers; returns the diff of all files. Inferred places (via interface, overridden, unknown type, text) remain unchanged and are listed under “Nicht geändert, bitte prüfen” (not changed, please check, #1119) |
| `apply_code_action` | `file`, `line`, `title` (optional), `dryRun` (default `true`) | Writing (#61): without `title` lists the fixes of the line, with `title` (title or rule ID) applies the fix; returns the diff |
| `fix_findings` | `rules` (rule IDs or `all`), `file` (optional, otherwise all project files), `minConfidence` (`high`, `medium`; optional, never below `fix.minConfidence`), `dryRun` (default `true`) | Writing (#1352): applies all safe fixes of the rules, like `AtlasServer --check --fix`. Only findings from the confidence upwards whose fix is unambiguous and marked as safe (catalog field `safeFix`); overlapping fixes from back to front in up to 3 passes, files with new syntax errors remain unchanged. Returns a summary (fixes per rule, skipped items) and the diff; writes like `apply_code_action` (open files via the plugin, one undo step per file; files with unsaved changes are left untouched and are named) |
| `format_code` | `file`, `text` (optional), `startLine`/`endLine` (optional, from 1), `dryRun` (default `true`) | Writing (#1358): formats the unit according to the project's format rules (`format.*` in `atlas.json`, `.editorconfig`) like *Format document* in the IDE, entirely or only `startLine`..`endLine` (without `endLine` one line). With `text` (planned content of the whole unit, as for `check_code`) it returns the deviations and the formatted text and never writes; otherwise it shows the deviations (line and kind) and the diff, with `dryRun: false` it writes like `apply_code_action` (files open in the IDE via the plugin as one undo step, #397). It does not format files with syntax errors (tool error with line); `// atlas-format: off` … `on` remains unchanged. The file's line endings are kept; `format.endOfLine` is applied by `AtlasServer --check <Datei> --format-write` |

## Developing and testing tools

Test new or changed tools without Claude first (#1125). Two scripts, both under `pwsh` (Windows, Linux) and Windows PowerShell 5.1:

| Script | Purpose |
|---|---|
| `Tools/Start-McpInspector.ps1` | [MCP Inspector](https://modelcontextprotocol.io/docs/tools/inspector) against AtlasServer: tools, resources and input schemas as a client sees them, calls with your own arguments and the raw JSON-RPC messages |
| `Tools/Test-McpTools.ps1` | Trial run: every tool once with sample arguments in one server session, schema and response check, raw recording as JSON Lines |

This separates errors in the server from errors in the description or schema that merely cause Claude to call a tool incorrectly. Without `-Server`, the server is `Output\Win64\Debug\Bin\AtlasServer.exe`, under Linux `Output/Linux64/Bin/AtlasServer`, otherwise `AtlasServer` from the PATH. The Inspector needs Node.js 22.19 or later and is downloaded in a fixed version on the first call.

### MCP Inspector

```powershell
# Oberfläche im Browser: links Server verbinden, oben "Tools", rechts "Messages" mit jedem Aufruf roh
pwsh Tools/Start-McpInspector.ps1 -ProjectRoot Tests/Referenzprojekt

# Oberfläche im Terminal (SSH, Cloud-Sitzung)
pwsh Tools/Start-McpInspector.ps1 -Tui

# Kommandozeile, ein Aufruf, Ergebnis als JSON
pwsh Tools/Start-McpInspector.ps1 -Method tools/list -Strict
pwsh Tools/Start-McpInspector.ps1 -Method tools/call -Tool qualified_name -Arguments @{ file = 'Application/AtlasServer.dpr'; line = 1; column = 9; withParameters = $true }
pwsh Tools/Start-McpInspector.ps1 -Method resources/read -Uri delphi://conventions -Output konventionen.json
pwsh Tools/Start-McpInspector.ps1 -Method prompts/get -Prompt unit_review -Arguments @{ unit = 'Shell.Mcp' }
pwsh Tools/Start-McpInspector.ps1 -Method resources/read -Uri delphi://unit/Shell.Mcp
```

- `-Strict` outputs the Inspector's schema check for `tools/list` (path, problem, suggestion) and ends with exit code 6 if a schema is not portable across clients.
- `-Restricted` starts the server with `--restricted` (read-only tools only), `-Log` with `--log`.
- The server starts via a generated session configuration (`--config`); switches like `--mcp` thus reach the server, not the Inspector. The Inspector keeps secrets only in memory (`MCP_INSPECTOR_SECRET_STORE=memory`); Atlas needs none.

Without PowerShell, e.g. in a cloud session with the Linux server:

```bash
npx -y @modelcontextprotocol/inspector@2.12.0 --cli AtlasServer --mcp --root . --method tools/call \
  --tool-name hook_check --tool-arg file=Application/Source/Shell/Shell.Mcp.pas
```

### Trial run of all tools

```powershell
pwsh Tools/Test-McpTools.ps1                       # alle Werkzeuge, Ordner Tests/Referenzprojekt
pwsh Tools/Test-McpTools.ps1 -Tool find_symbol -Arguments @{ name = 'TKundenSuche' }
pwsh Tools/Test-McpTools.ps1 -Tool run_tests -WithProcessTools -Arguments @{ tests = @('Unit.Fixture') }
```

The script talks to the server directly via stdio. The index is built only once; the whole run takes a few seconds (the Inspector restarts the server for every command-line call). It checks:

- `initialize`, `tools/list`, `resources/list`, `resources/templates/list` and `prompts/list` answer without errors.
- Every tool has a description and an `inputSchema` of type `object`; every required parameter is in `properties`, every parameter has a description.
- Every tool answers its example without a JSON-RPC error, without `isError` and not empty, and the response contains the expected text.
- Every resource can be read.
- Every prompt has a description, every argument a description, and `prompts/get` with the example under `prompts` returns a non-empty message with the expected text; every template reads with the sample URI under `templates` (#1357). A prompt or template without an example makes the run fail.

The examples are in `Tools/Mcp/Werkzeug-Beispiele.json` and refer to the reference project (`Tests/Referenzprojekt`). Lines and columns are given there as placeholders (`{{zeile:procedure TRefAnzeige.SetStil}}`, `{{spalte:SetStil}}`) so that shifted lines do not break the examples. Tools with `"process": true` (`build_project`, `run_tests`) need the IDE or a test project and run only with `-WithProcessTools`. With `-Tool` and `-Arguments` the script calls one tool with your own arguments, including lists and objects, and prints the response.

The recording (`Output/Mcp/probe-<Zeit>.jsonl`) contains every message raw, one per line: `{"zeit":"…","richtung":"an Server"|"vom Server","nachricht":{…}}`. Exit code 0: everything fine, 1: findings, 3: server missing or not answering.

### Workflow for a new tool

1. Register the tool in `Shell.Mcp.pas`, logic in `Atlas.Common.Mcp.*` with DUnitX tests.
2. Add a row to the table above in the German [MCP.md](../MCP.md#werkzeuge); `TMcpShellTests.ToolsListMatchesDocumentation` checks it.
3. Enter an example in `Tools/Mcp/Werkzeug-Beispiele.json`; without an entry the trial run fails.
4. Build, then `pwsh Tools/Start-McpInspector.ps1 -Method tools/list -Strict` and `pwsh Tools/Test-McpTools.ps1`.
5. Edge cases in the Inspector by hand: missing required parameters, wrong types, unknown files, large results.

Things to watch:

- Description and parameter descriptions say when the tool helps and what it returns; Claude chooses based on these alone.
- Required parameters are listed in `required`; a missing required parameter returns an understandable error message (`EMcpToolError`), not an exception with a stack trace.
- Large results are limited (e.g. `MaxFindings`) and say how much was left out.
