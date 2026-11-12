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
- explain findings
- report findings to Claude Code hooks (`hook_check`)
- build through the IDE (`build_project`, `get_last_build`)
- run DUnitX tests

### Change

Each with preview:

- rename
- apply code actions
- format (`format_code`)
- extract method, optionally with equal places (`extract_method`)
- fix all safe findings of rules at once (`fix_findings`)

### Resource

- `delphi://conventions` with the project's conventions

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

## The `atlas` plugin

- Checks every Pascal file Claude changes right away with the project's check rules (hook with `hook_check`, findings go straight back to Claude)
- `/atlas:bauen` builds and tests and sums up the result against 0 errors, 0 warnings, 0 hints

Setup: [Editors/ClaudeCode](../../../Editors/ClaudeCode/README.md), tools: [docs/MCP.md](../../../docs/MCP.md).

## Developing new tools

- `pwsh Tools/Start-McpInspector.ps1` opens the [MCP Inspector](https://modelcontextprotocol.io/docs/tools/inspector) against the server (browser, terminal or command line) and shows every tool, its schema and the raw JSON-RPC messages
- `pwsh Tools/Test-McpTools.ps1` calls every tool once with sample arguments against the reference project and writes the raw transcript

See [docs/MCP.md](../../../docs/MCP.md#werkzeuge-entwickeln-und-prüfen).
