# Command line

Back to the [README](../../../README.md)

## Logging and diagnostics

| Parameter | Meaning |
|---|---|
| `--log <file>` | log file, appended; paths, project, unit and user names and messages are replaced by IDs (`datei#3`, `name#2`, `wert#1`, #1478) |
| `--log-names` | write the log file and `--timings` with real paths and names (local debugging only) |
| `--log-level <level>` | `debug`, `info` (default), `warning`, `error`; applies to the log file and `window/logMessage` |
| `--trace <file>` | trace of all JSON messages (`-->` received, `<--` sent) |

- Values also work with `=` (`--log=server.log`).
- `--stdio` and `--clientProcessId`, appended by editors, are ignored.

## Index cache

- `AtlasServer.exe --clear-cache` deletes all index caches under `%LOCALAPPDATA%\Atlas` that no running instance uses.
- The folder is limited to 1024 MB anyway (`index.cacheMaxMb`); the caches unused longest go first.

## Linter mode

`AtlasServer.exe --check <target>` checks without an editor.

- The target can be:
  - a `.dproj` (main file and units)
  - a folder (all `.pas`, `.dpr` and `.dpk` below)
  - or a file
- `atlas.json` in the target's folder applies as in the editor.
- If it is missing, the former `delphi-lsp.json` applies (likewise `delphi-lsp-baseline.json` for the baseline).

### Symbol index (#1112)

- The linter loads the same symbol index as the editor:
  - the target's project
  - and, with `index.projectGroup`, the other projects of the group
  - from the index cache if it is current
- Rules that need types from other units (for example ownership of fields whose type is declared elsewhere, or `case` over an enumeration from another unit) therefore report the same findings as in the IDE.
- Without a project file the check runs without the index (stderr says so).
- The MCP server checks with the same index (`get_diagnostics`, `check_code`, `explain_finding`).
  - While it is still loading, `get_diagnostics` says that findings needing the index may be missing.

### Runtime

- **One evaluation per unit (#1322):** a check run evaluates each unit once and shares the result with all rules.
  - Before, rules that ask for the type of many expressions (ownership, casts, typed expressions) extracted the whole unit again for every question, so large units took quadratic time.
  - In the IDE this cost CPU on every change as well.
- **Token search (#1323):** the token at a position is found by binary search instead of a scan from the start of the file, which large constant arrays made quadratic as well.
- Measured with the Linux build (before → #1322 → #1323), findings unchanged:

  | Project | before | #1322 | #1323 |
  |---|---|---|---|
  | SynEdit | 353 s | 135 s | 113 s |
  | VirtualTreeView | 676 s | 93 s | 78 s |
  | HtmlViewer | 987 s | 708 s | 116 s |

- **Repeated searches (#1342):** searches that a check run repeats all the time no longer start from scratch:
  - project units and type lookups through the uses units are looked up in name tables and remembered per resolver
  - yes/no questions to the symbol index stop at the first match
  - token searches jump to the start of their range by binary search
- A check over the Atlas sources themselves (1,917 units, Linux build) went from 912 s to 594 s, on one core as before and with the same findings.

### Parameters

| Parameter | Meaning |
|---|---|
| `--no-index` | check without the symbol index (faster, but rules that need other units stay silent) |
| `--index-cache <folder>` | folder for the index cache instead of `%LOCALAPPDATA%\Atlas`, e.g. a cache folder kept between CI runs |
| `--format <kind>` | `text` (default, like compiler messages), `json`, `sarif` (SARIF 2.1.0 for GitHub code scanning) |
| `--output <file>` | result into a file instead of stdout |
| `--rules <a,b>` | only these rules, e.g. `syntax` |
| `--units <a,b>` | only these units: name or glob pattern for paths |
| `--min-severity <s>` | `hint`, `info`, `warning`, `error` |
| `--locale <de\|en>` | language of the texts (#1458); without it `language` from `%APPDATA%\Atlas\settings.json`, otherwise English |
| `--fail-on <s>` | which findings make the exit code 1: `error` (default), `warning` or `never`, so warnings in legacy projects do not break a pre-commit hook |
| `--source-root <folder>` | root of the SARIF paths; defaults to the Git root above the target, otherwise the target's folder. Paths below it carry `uriBaseId` `%SRCROOT%`, files outside appear as absolute `file:` URIs |
| `--profile <name>` | rule profile (`standard`, `fast`, `strict`, `security`, `style` or one of your own from `profiles`); overrides `profile` in `atlas.json` |
| `--baseline <file>` | hide known findings; without it `atlas-baseline.json` next to `atlas.json` applies if present. The editor hides them as well |
| `--update-baseline` | rewrite the baseline from the current findings, exit code 0. stderr first lists entries without a file with their path (renamed, moved or deleted files; they drop out), then the counters: findings, files, added, removed, unchanged |
| `--changed [<base>]` | only files changed according to Git (or SVN, see below) against the merge base with `<base>` (default `main`); changed `.dfm`/`.fmx` check their unit, changed `.inc` all units including them, changed `.dproj`/`.dpk`/`.dpr`/`atlas.json` everything |
| `--diff <ref>` | like `--changed`, but directly against `<ref>` |
| `--include-uncommitted` | with `--changed`/`--diff` also index, working tree and new files |
| `--changed-lines` | only findings in changed lines; together with the baseline only new findings in changed lines |
| `--fix <rules\|all>` | bulk fix (#1352): applies the safe fixes of the rules (confidence from `fix.minConfidence`, default high; only rules marked `safeFix` in the catalog, no fix with a choice), overlapping ones back to front in up to three passes; a file that would then have more syntax errors stays unchanged. Writes all changed files or none, keeping their encoding and line endings. `--units`, `--changed`, `--diff`, `--changed-lines` (only findings in changed lines), `--baseline` (its findings stay) and `--profile` apply. Summary on stderr (fixes per rule, skipped by confidence, unsafe, conflict); exit code 1 if findings reaching `--fail-on` remain |
| `--fix-dry-run` | with `--fix`: write nothing, print the unified diff instead (stdout or `--output`) |
| `--timings [<file>]` | time profile of the run (#1356): index time, the 10 slowest units and rules (sum of ms, calls) and memory per area, as Markdown or, with the extension `.json`, as JSON; without a file on stderr. The findings on stdout or `--output` stay the same (named `--timings` because `--profile` selects the rule profile) |
| `--suppression-stats` | instead of findings: how often each rule is suppressed via `lsp-ignore` (most frequent first, including unused ones), as text or JSON; exit code 0 |
| `--metrics` | instead of findings: code metrics per method (length, nesting depth, cyclomatic and cognitive complexity, parameters, operands, local variables, exits; #66, #980) with the limits from `atlas.json` (`"max"` of the `metric-*` rules); `--format text` writes a Markdown report, `json` the metric data; exit code 0 |
| `--todos` | instead of findings: open TODO entries (#68) from `// TODO`, `// FIXME` and the IDE to-do format `{ TODO 1 -oOwner -cCategory : Text }` with priority, owner and category; more markers via the option `"keywords"` of the rule `todo-comment`; `--format text` writes a Markdown overview, `json` the data; exit code 0 |
| `--architecture <file>` | instead of findings: architecture overview (#1118) of the `--check` target (without `--check` of the current folder) as `.html` (standalone map to zoom, with tables) or `.md`: subsystems, central units, cycles with locations, cross links and outliers; scope, library units and exclusions from `architecture.*` in `atlas.json` or `settings.json`; exit code 0, 3 if the overview is switched off; `.json` saves the state for a comparison (#1121) |
| `--compare <old.json>` | with `--architecture`: compares with a saved state (#1121) and prints the sections as text (or to `--output`); exit code 1 if a kind from `--fail-on newCycle,newCrossLink,subsystemChange,centralGrowth` occurs (default `architecture.failOn`), 3 if the state cannot be read |
| `--affected-tests [<base>]` | instead of findings: tests affected by the changes against the merge base with `<base>` (Git, default `main`) or the revision (SVN, default `BASE`), with `--include-uncommitted` also index, working tree and new files (#1353). The `--check` target is the test project or project group. `--format text` (tests with reasons), `json` (like `get_affected_tests`) or `dunitx` (only the `--run:…` argument for the test exe, summary on stderr); `--output` writes to a file. Exit code 0 with a list, 2 if all tests are needed (test program changed, analysis incomplete), 3 if `tests.affected` is off |
| `--query "<query>"` | instead of findings: code query (#1351) over the `--check` target (without a project over the folder's files), also `@name` of a saved query from `queries`; `--format text` (default), `json` or `csv`, `--output`; exit code 0, 3 for an error in the query (message with column on stderr), an unknown `@name` or `query.enabled` off |
| `--fail-on-match` | with `--query`: exit code 1 as soon as the query finds something (also for `@name` with `failIfAny`) |
| `--mutate <file.pas>` | instead of the check: mutants of the unit for mutation testing (#1460), without building, like `get_mutants`; `--routine <name>` only this routine, `--operators boundary,not,…` only these operators, `--check <project.dproj>` symbols of the project for the active branches (otherwise Win32, Delphi 13); `--format text` (Markdown, default), `json` (with offsets) or `diff` (one patch per mutant), `--output`; exit code 0, 3 for a missing file, unknown format or operator |

### Exit code

- 1 if a finding reaches `--fail-on` (default: at least one error), otherwise 0
- 3 for invocation or read errors
- Findings hidden by the baseline never count.

### Baseline (#97)

- An entry in `atlas-baseline.json` records:
  - the file
  - the rule
  - the enclosing routine (fully qualified like `TFoo.Bar`, outside a routine the section such as `implementation`)
  - a fingerprint of the line without whitespace
  - a fingerprint of the code ±2 lines around it
- The same line in another routine therefore counts as new, as does a finding that moves to another routine.
- Re-indenting, moved lines and a renamed routine (same context, old name gone from the file) keep their entries.
- A renamed or moved file loses its entries: its findings show up as new until the baseline is updated.
- Older files without routines stay readable and are completed on the next update.
- Suppression comments for findings in the baseline never report `unused-suppression`.
- In editors the command `atlas.updateBaseline` (`workspace/executeCommand`, argument: URI of the project or folder) updates the baseline and answers with the counters.
  - It checks every file of the project and keeps the server busy meanwhile.
- In SARIF every result carries `partialFingerprints`:
  - `atlasBaseline/v1` from rule, routine and line
  - `atlasContext/v1` from the context
  - each with a running number `:n` for equal values in one file
- With a baseline `baselineState` is added: `new`, `unchanged` (as an external suppression) or `absent` (entry without a finding).
- Text, JSON and the exit code contain only new findings.

### SARIF messages

- In SARIF, `message.text` is the rule's English catalog name without the confidence suffix.
- The confidence is in `properties.confidence`, the finding's German message in `properties.detail`.

### Confidence

- Every rule finding has a confidence (high, medium, low).
- It caps the severity even if `rules` sets it higher:
  - medium confidence at most warning
  - low at most hint
- Findings below `minConfidence` (default `medium`) are hidden.
- The confidence is never part of the message text. It is:
  - a separate column in the text output (`[Konfidenz mittel]`)
  - `confidence` in JSON
  - `data.confidence` in LSP
  - its own line in the plugin's tooltip

### SVN with `--changed`

- In an SVN working copy:
  - `--changed` without a base compares the working copy with BASE (`svn status`)
  - `--changed <rev>` and `--diff <rev>` compare with the revision (`svn diff -r`)
  - `--include-uncommitted` adds unversioned files
- The nearest working copy above the configuration folder wins (`.git` or `.svn`), Git on a tie.
- `vcs.provider` in `%APPDATA%\Atlas\settings.json` picks the kind (`auto`, `git`, `svn`) or turns it off (`off`).
- svn must be installed as a command-line tool (TortoiseSVN with command-line tools is enough).
- `vcs.git.path` and `vcs.svn.path` pick the program (as on the *Version control* page), `vcs.timeoutSeconds` the time limit per call.
- If the file under a custom path is missing, `--changed` stops with that cause.

### Examples

- Examples for a pre-commit hook and a GitHub Action that check only changes, and a GitHub Action that runs only the affected tests (all of them at night), are in [docs/Beispiele](../../../docs/Beispiele).

### Formatting without the IDE

- The same formatter as *Format document* in the plugin (#1358) runs without the IDE, for example in a pre-commit hook, in CI or for Claude Code.
- Target and selection as with `--check` (`.dproj`, folder or file, `--units`, `--changed`/`--diff`, `--include-uncommitted`, exclusions from `atlas.json`).
- The project's formatting rules apply: `format.*` from `atlas.json` over `.editorconfig` over the defaults.
- The command line does not know the indentation from the IDE's editor options; to get the same everywhere, set `format.indentSize` and `format.useTabs`.

| Parameter | Meaning |
|---|---|
| `--format-check` | formats in memory and compares; per deviating file the first five deviations with line and kind (German text such as `Einrückung 3 statt 2` = is 3, should be 2); `--format json` lists all deviations (lines from 1, kind as an id such as `indent`), `--format diff` prints the unified diff. Exit code 1 on a deviation, a syntax error or unstable formatting, otherwise 0 |
| `--format-write` | writes the formatted files atomically (sibling file, then replace); encoding (UTF-8 with or without BOM, ANSI) and line endings stay, unless `format.endOfLine` asks for others. Exit code 1 only on syntax errors or unstable formatting, 3 if a file could not be written |
| `--changed-lines` | with `--format-check`/`--format-write`: formats only the changed lines like *Format selection* (`textDocument/rangeFormatting`); every other line stays byte for byte |

#### Behaviour

- Files with syntax errors are not formatted and are reported with line and message.
- Regions between `// atlas-format: off` and `// atlas-format: on` stay untouched including these lines, in the plugin as on the command line.
  - also as `{ … }` or `(* … *)`
  - without `on` up to the end of the file
- Every run formats the result a second time and reports files that still change.

#### Claude Code

- For Claude Code the MCP tool `format_code` formats a unit by the same rules:
  - with `text` planned code (returns the formatted text, writes nothing)
  - otherwise the file, whole or `startLine`..`endLine`
- `dryRun` (default `true`) shows the diff, `dryRun: false` writes like `apply_code_action` (files open in the IDE as one undo step).
- Switch it off via `mcp.disabledTools`.

#### Examples

- [pre-commit hook](../../../docs/Beispiele/pre-commit-formatierung.ps1) with `--format-check --changed HEAD --changed-lines --include-uncommitted` (with `ATLAS_FORMAT_WRITE=1` it formats itself)
- [GitHub Action](../../../docs/Beispiele/github-action-formatierung.yml) with the diff in the log

## Rules

- All rules are described in [docs/Regeln.md](../../../docs/Regeln.md).
- The single source is the rule catalogue `Packages/Atlas.Common/Katalog/regelkatalog.json` (English) with the translation `regelkatalog.de.json`.
- After changes run `pwsh Tools/Update-RuleCatalog.ps1`; CI checks with `-Check` that catalogue, implementation and documentation agree.
