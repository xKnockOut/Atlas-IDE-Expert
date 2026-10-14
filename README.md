# Atlas IDE Expert

*Deutsche Fassung: [README_DE.md](README_DE.md). The detailed documentation in `docs/` is in German.*

An expert for RAD Studio (Delphi/Object Pascal): an IDE plugin with its own user interface and its own language server (LSP), plus an MCP interface for Claude Code. Features and roadmap are tracked in the [issues](https://github.com/xKnockOut/Atlas-IDE-Expert/issues); epics #130 to #139 describe the stages.

## The IDE plugin

`Atlas.IDE.Expert` replaces the built-in Code Insight of RAD Studio 13 (and 12) with its own windows, filled with data by the Atlas server:

- **Code completion** with detail panel, filter chips, fuzzy matching, learning order, postfix templates and an in-editor preview
- **Parameter hint** with all overloads and the active parameter
- **Hover tooltip** with declaration, documentation, clickable types, inheritance chain, history and actions (go to, usages, copy declaration, help)
- **Problems in the editor**: syntax errors, rule findings and compiler messages as squiggles, in the tooltip and as the list "Atlas-Probleme" in the message view, project-wide; marks move along while typing
- **Compiler check after saving** and the compiler messages of the "Build" tab
- **Bracket and block pairs** coloured by depth, with matching block lines
- **Results window** "Atlas Results" for references (including forms), implementations, callers, calls and inheritance; workspace symbol search; preview before renaming
- **Code actions** (Alt+Enter), expand and shrink selection (Ctrl+W, Ctrl+Shift+W), go to implementation and type definition, copy qualified name; all also in the editor context menu under *Atlas*. Slash commands such as `/uses Unit` run after Enter, `///` above a declaration creates the documentation comment
- **Form designer**: open forms are sent to the server as the designer has them, so references, renames and checks see unsaved changes; renaming an event handler also updates its assignment in the designer
- **Command palette** (Ctrl+Shift+P), silent reload of files changed outside the IDE, hang watchdog with log

All settings are under *Tools › Options › Third Party › Atlas*, including the path to the server.

## Installation

### IDE plugin for RAD Studio 13 and 12

1. Clone the repository and open `Atlas.groupproj` in RAD Studio.
2. Build `Atlas.Common`, `Atlas.Windows` and `AtlasServer` for **Win64** (all three for the same platform). Result: `Output\Win64\Debug\Bin\AtlasServer.exe`. Alternatively take `AtlasServer.exe` from a [release](https://github.com/xKnockOut/Atlas-IDE-Expert/releases); the server does not depend on the Delphi version.
3. Build `Atlas.IDE.Expert` for **Win32**, with the Delphi version the plugin is meant to run in. Result: `Output\Win32\Debug\Bpl\Atlas.IDE.Expert.bpl`.
4. *Component › Install Packages › Add* and select the BPL.
5. If the server is neither in `Output\…\Bin` nor next to the BPL: *Tools › Options › Third Party › Atlas*, field "Atlas-Server". The page shows whether the server is found.
6. Restart Delphi once: Atlas switches off the IDE's Help Insight and structural highlighting so nothing appears twice; the IDE reads these switches only at startup.

Details and troubleshooting (German): [docs/RAD-Studio.md](docs/RAD-Studio.md).

### Other editors and without an editor

- **VS Code:** extension `atlas-<version>.vsix` (contains the server), see [Editors/VSCode](Editors/VSCode/README.md)
- **Claude Code:** MCP tools and LSP as a plugin, see [Editors/ClaudeCode](Editors/ClaudeCode/README.md)
- **Neovim:** see [Editors/Neovim](Editors/Neovim/README.md)
- **CI and command line:** `AtlasServer.exe --check`, see [Linter mode](#linter-mode)

More: [docs/Installation.md](docs/Installation.md).

## Documentation (German)

- [Installation](docs/Installation.md) for VS Code, Claude Code, Neovim and other editors
- [Configuration](docs/Konfiguration.md) of `atlas.json` (generated from the JSON schema with `pwsh Tools/Update-ConfigDoc.ps1`)
- [Rules](docs/Regeln.md)
- [MCP tools](docs/MCP.md)
- [Benchmark](docs/Benchmark.md) of the performance targets

## Structure

| Project | Content |
|---|---|
| `Packages/Atlas.Common` | Package, free of Windows and VCL |
| `Packages/Atlas.Windows` | Package for Windows-specific functions, free of VCL |
| `Application/AtlasServer` | The server (console program, speaks LSP over stdin/stdout) |
| `Packages/Atlas.IDE.Expert` | The IDE plugin (design-time package, Win32), layers `Atlas.Core.*`, `Atlas.UI.*`, `Atlas.IDE.*` |
| `Tests/Atlas.Tests` | DUnitX tests |

Roles, naming and import rules: [docs/Architektur.md](docs/Architektur.md).

## Requirements

- Delphi 12 Athens or newer; currently built with RAD Studio 13 (Win32 and Win64). The IDE plugin must be built with the Delphi version it runs in; the server is independent of it.
- The test project is set up for Win64 only, because DUnitX is available only as a Win64 library in the Starter edition
- DUnitX (included in RAD Studio, IDE environment variable `$(DUnitX)`)
- PowerShell for the check scripts

## Building

Open `Atlas.groupproj` in the IDE and **Build All**. The order Common → Windows → server → IDE plugin → tests is set in the project group. Common, Windows and the server must be built for the same platform, otherwise the server does not find the package units. The IDE plugin is set up for Win32 only (the IDE is 32-bit); a group build for Win64 still compiles it and thus checks the code.

On the command line (RAD Studio command prompt or after `rsvars.bat`):

```bat
msbuild Atlas.groupproj /t:Build /p:Config=Debug /p:Platform=Win32
```

Output goes to `Output\<platform>\<config>\` (`Bin`, `Bpl`, `Dcp`, `Dcu`).

## Testing

```bat
Output\Win64\Debug\Bin\Atlas.Tests.exe --exit:Continue
```

Check scripts (also run as GitHub Actions):

```powershell
pwsh Tools/Check-PackageDependencies.ps1   # packages keep their dependencies
pwsh Tools/Check-ConsoleOutput.ps1         # no Write/Writeln to stdout
```

## CI

- `vscode-erweiterung.yml`: type check, build and `.vsix` as artifact on a hosted Ubuntu runner.
- `server.yml`: build of the project group via the IDE plugin `cc.ps1` (RAD Studio Starter has no msbuild) and DUnitX tests on a self-hosted Windows runner (labels `self-hosted`, `windows`, `delphi`, in the signed-in user context). Runs only with the repository variable `DELPHI_RUNNER=true`; `CC_SCRIPT` overrides the path to `cc.ps1`. Results as the check "DUnitX-Ergebnisse" in pull requests.
- `package-dependencies.yml`: package dependencies and the stdout rule.

## Command line

| Parameter | Meaning |
|---|---|
| `--log <file>` | log file, appended |
| `--log-level <level>` | `debug`, `info` (default), `warning`, `error`; applies to the log file and `window/logMessage` |
| `--trace <file>` | trace of all JSON messages (`-->` received, `<--` sent) |

Values also work with `=` (`--log=server.log`). `--stdio` and `--clientProcessId`, appended by editors, are ignored.

`AtlasServer.exe --clear-cache` deletes all index caches under `%LOCALAPPDATA%\Atlas` that no running instance uses. The folder is limited to 256 MB anyway; older caches go first.

### Linter mode

`AtlasServer.exe --check <target>` checks without an editor. The target can be a `.dproj` (main file and units), a folder (all `.pas`, `.dpr` and `.dpk` below) or a file. `atlas.json` in the target's folder applies as in the editor. If it is missing, the former `delphi-lsp.json` applies (likewise `delphi-lsp-baseline.json` for the baseline).

| Parameter | Meaning |
|---|---|
| `--format <kind>` | `text` (default, like compiler messages), `json`, `sarif` (SARIF 2.1.0 for GitHub code scanning) |
| `--output <file>` | result into a file instead of stdout |
| `--rules <a,b>` | only these rules, e.g. `syntax` |
| `--units <a,b>` | only these units: name or glob pattern for paths |
| `--min-severity <s>` | `hint`, `info`, `warning`, `error` |
| `--profile <name>` | rule profile (`standard`, `fast`, `strict`, `security`, `style` or one of your own from `profiles`); overrides `profile` in `atlas.json` |
| `--baseline <file>` | hide known findings; without it `atlas-baseline.json` next to `atlas.json` applies if present. The editor hides them as well |
| `--update-baseline` | rewrite the baseline from the current findings (vanished entries drop out), exit code 0 |
| `--changed [<base>]` | only files changed according to Git (or SVN, see below) against the merge base with `<base>` (default `main`); changed `.dfm`/`.fmx` check their unit, changed `.inc` all units including them, changed `.dproj`/`.dpk`/`.dpr`/`atlas.json` everything |
| `--diff <ref>` | like `--changed`, but directly against `<ref>` |
| `--include-uncommitted` | with `--changed`/`--diff` also index, working tree and new files |
| `--changed-lines` | only findings in changed lines; together with the baseline only new findings in changed lines |
| `--suppression-stats` | instead of findings: how often each rule is suppressed via `lsp-ignore` (most frequent first, including unused ones), as text or JSON; exit code 0 |

Exit code: 0 without warnings and errors, 1 with warnings, 2 with errors, 3 for invocation or read errors.

In an SVN working copy, `--changed` without a base compares the working copy with BASE (`svn status`), `--changed <rev>` and `--diff <rev>` with the revision (`svn diff -r`); `--include-uncommitted` adds unversioned files. Git takes precedence if both are present.

Examples for a pre-commit hook and a GitHub Action that check only changes are in [docs/Beispiele](docs/Beispiele).

### Rules

All rules are described in [docs/Regeln.md](docs/Regeln.md). The single source is the rule catalogue `Packages/Atlas.Common/Katalog/regelkatalog.json` (English) with the translation `regelkatalog.de.json`. After changes run `pwsh Tools/Update-RuleCatalog.ps1`; CI checks with `-Check` that catalogue, implementation and documentation agree.

## Important: stdout belongs to the protocol

The server speaks LSP over stdin/stdout. Any additional output to stdout (`Writeln`, unhandled exceptions) breaks the communication with the editor. All diagnostic messages go through `ILogger` (`Atlas.Common.Logging`) to `OutputDebugString`, the log file, `window/logMessage` and, for errors, stderr. After starting, the server redirects the stdout handle and `Output` to stderr, so libraries cannot disturb the protocol either.

## Licences

Atlas is licensed under the MIT licence (`LICENSE`); third-party components with their licence texts are listed in `THIRD-PARTY-NOTICES.md` (generated by `Tools/Update-ThirdPartyNotices.ps1`).

Cache and benchmark corpus stay local, VCL sources are never checked in. The index cache lives under `%LOCALAPPDATA%\Atlas`; the server reads RTL and VCL sources only from the local Delphi installation. `Tools/Check-NoEmbarcaderoSources.ps1` checks in CI that `Tests/` and the `.vsix` contain no file with an Embarcadero copyright header.
