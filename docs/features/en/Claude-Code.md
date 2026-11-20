# Claude Code and MCP

Back to the [README](../../../README.md)

## MCP tools

The server offers Claude Code 33 MCP tools:

### Search and understand

- find symbols
- look at memory, the slowest units and rules and the queue of the IDE's server (`get_server_status`, the same numbers as the *Atlas server* window)
- survey the project's architecture (`get_architecture`, also compared with a saved state)
- query the index in a small language (`query_code`)
- find hotspots and change coupling from Git or SVN history (`get_hotspots`)
- follow the history of a method across renames and moves, with issues (`get_symbol_history`)
- find the shortest path between two symbols or units (`find_path`)
- read declarations with their rationale comments (`get_rationale`) and type and call hierarchies
- the impact of a change (`get_impact`)
- find only the tests affected by a change (`get_affected_tests`)
- component and form info
- query diagnostics, metrics and TODOs
- find unused code (`find_unused_code`)
- read a unit's dependencies including cycles (`get_unit_dependencies`)

### Check, build, test

- check planned code with `check_code` before writing it
- explain findings (`explain_finding`): the same task as "Copy as task for an AI assistant" in the "Atlas Findings" window, with a ±8 line excerpt and a closing line telling the assistant how to verify (`check_code`, for safe fixes `fix_findings`)
- look up the Atlas documentation: rules with their severity in the project, settings with their current value, windows and shortcuts (`search_atlas_docs`)
- report findings to Claude Code hooks (`hook_check`)
- build through the IDE (`build_project`, `get_last_build`)
- read the issue started in the IDE with checklist and code references (`get_current_issue`)
- explain compiler messages at their place, with the known Delphi pitfall and a safe fix as a diff (`explain_compiler_message`)
- run DUnitX tests
- read the last test run of the IDE without running again (`get_last_tests`: red tests with file:line, expected/actual, log, newly red, flaky, leak, stale)
- see where the developer currently is in the IDE (`get_ide_context`: file, cursor, method, selection, active project, last build, tabs)

### Change

Each with preview:

- rename
- apply code actions
- format (`format_code`)
- extract method, optionally with equal places (`extract_method`)
- refactorings of the context menu with arguments instead of questions (`refactor`)
- fix all safe findings of rules at once (`fix_findings`)

### Resource

- `delphi://conventions` with the project's conventions

## AI assistants in the IDE

The AI assistants module (`assistants.enabled`) takes requests from MCP clients in the running IDE: builds through `build_project` and changes to open files, which land in the editor buffer as one undo step.

- **“AI assistant active” display** (#1906, `assistants.banner`): a field in the Atlas status field shows which project is being built for an AI assistant or which open file it changed last (for one minute).
- **Pause for AI:** a click on the field or the command “Pause AI assistants” in the palette pauses AI assistants. The IDE then refuses new builds and changes to open files with a reason, and the MCP server does not write the file itself either; a running build finishes. While paused the field stays visible, a second click ends the pause.

## Connected IDE for command line assistants (#2377)

With `assistants.link` (off by default) RAD Studio presents itself to command line assistants as a connected IDE, like editors with their own extension do. Atlas opens a WebSocket server on 127.0.0.1 only, with a random port and one token per IDE session, and puts a lock file into the configuration folder of the assistant (`%USERPROFILE%\.claude\ide\<port>.lock` or under `CLAUDE_CONFIG_DIR`); it disappears when the feature is switched off or the IDE closes. The server refuses connections without the token or from a browser.

- **Live selection** (`assistants.link.shareSelection`): the selection in the editor goes to the assistant once it rests for a moment; without a selection the line of the caret.
- **Selection to the assistant:** a command in the editor context menu and a key (`assistants.link.mentionKey`, default Ctrl+Shift+Alt+K) send file and lines of the selection as a mention.
- **Proposal as a comparison** (`assistants.link.diffPreview`): a proposal of the assistant appears as a comparison with the current state of the file. “Accept” changes the file as one undo step and saves it, “Accept and open” then shows it in the editor, “Reject” or closing leaves it unchanged. Only then does the assistant learn the decision. If the file changed in the meantime, the comparison shows the new state.
- **Tools:** open files and workspace folders, selection, open a file and select a range, check and save unsaved changes, Atlas findings and compiler messages. The assistant cannot run code in the IDE.
- **Status field “Assistant connected”** with the name of the assistant; a click offers “Disconnect”. The pause for AI applies here too: the IDE then refuses saving and proposals.

## Prompts (#1357)

Ready-made workflows that Claude Code shows as slash commands:

| Prompt | Delivers |
|---|---|
| `/mcp__delphi__unit_review UI.Order` | outline, findings, metrics above limits, unused code and conventions in one message |
| `explain_form` | component tree, event handlers with bodies, data bindings |
| `write_tests` | |
| `fix_finding` | cause first, then fix, then `check_code` |
| `prepare_commit` | new findings in changed lines only, affected tests, commit prefix of the current issue |

- With `--restricted` they offer no writing steps.
- Projects add their own in `mcp.customPrompts`.
- `mcp.prompts` switches them off.
- `mcp.promptLanguage` picks German or English.

## Resource templates

- Attach with `@`:
  - a unit (outline and interface part)
  - a form
  - the findings of a file
  - the last build
- e.g. `@delphi:delphi://unit/UI.Order`

## Instructions for AI assistants (#2615)

AI assistants read an instruction file of the project when they start. Atlas writes the rules from `atlas.json` into it as a short summary, so the assistant knows them before it writes the first line:

- Rule profile, thresholds of the active metric rules, naming (`naming-prefix`), forbidden symbols with their replacement, the rules set to error in `atlas.json`, the protected files from `assistants.protected` and the required checks from `assistants.instructions.checks`.
- The section sits between `<!-- atlas:begin … -->` and `<!-- atlas:end -->`; only it is replaced, the rest of the file stays. If it is missing, Atlas appends it; if the file is missing, Atlas creates it.
- Files: `assistants.instructions.file` (default `["AGENTS.md"]`), relative to the folder of `atlas.json`. Language follows `mcp.promptLanguage`.
- Command line: `AtlasServer --check . --write-instructions` writes, `--check-instructions` only checks and exits with code 1 when a section is out of date (for CI and pre-commit hooks).
- In the IDE: Atlas › “Update instructions for AI assistants” (also in the command palette) writes the files and shows in the message view which lines changed. After saving `atlas.json`, Atlas points out an out-of-date section; turn this off with `assistants.instructionsHint`.

## The `atlas` plugin

- Checks every Pascal file Claude changes right away with the project's check rules (hook with `hook_check`, findings go straight back to Claude)
- `/atlas:bauen` builds and tests and sums up the result against 0 errors, 0 warnings, 0 hints

Setup: [Editors/ClaudeCode](../../../Editors/ClaudeCode/README.md), tools: [docs/MCP.md](../../../docs/MCP.md).

## Developing new tools

- `pwsh Tools/Start-McpInspector.ps1` opens the [MCP Inspector](https://modelcontextprotocol.io/docs/tools/inspector) against the server (browser, terminal or command line) and shows every tool, its schema and the raw JSON-RPC messages
- `delphi://stats` shows per tool how often the AI assistant calls it, how often it fails (with the last failed call), how slow and how large its answers are, and which tools never came up in the last 30 days (#2611)
- `pwsh Tools/Test-McpTools.ps1` calls every tool once with sample arguments against the reference project and writes the raw transcript

See [docs/MCP.md](../../../docs/MCP.md#werkzeuge-entwickeln-und-prüfen).
