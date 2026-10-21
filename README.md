# Atlas IDE Expert

[![Donate with PayPal](https://img.shields.io/badge/Donate-PayPal-00457C?logo=paypal)](https://www.paypal.com/paypalme/xKnockOut288)

*Deutsche Fassung: [README_DE.md](README_DE.md). The detailed documentation in `docs/` is in German.*

An expert for RAD Studio (Delphi/Object Pascal): an IDE plugin with its own user interface and its own language server (LSP), plus an MCP interface for Claude Code. Features and roadmap are tracked in the [issues](https://github.com/xKnockOut/Atlas-IDE-Expert/issues); epics #130 to #139 describe the stages.

## Quick start

You need RAD Studio or Delphi 12 or later. Ready-made downloads are on the [releases](https://github.com/xKnockOut/Atlas-IDE-Expert/releases) page; release 1.0.0 contains the plugin for Delphi 13 only.

**Option A – with the installer:**

1. Download `atlas-ide-expert-<version>.zip` from the release and unpack it.
2. Run `AtlasSetup.exe`. It needs no administrator rights and finds the installed Delphi versions from 12 on by itself.
3. Choose "Installieren" (install), then start Delphi.

Details (German): [docs/Installation.md](docs/Installation.md).

**Option B – today: build it yourself and install the package in the IDE:**

1. Install Delphi 12 or later and clone this repository.
2. Open `Atlas.groupproj` in Delphi and build all projects for **Win64** (*Build All*). For the classic 32-bit IDE, also build `Atlas.IDE.Expert` for **Win32**.
3. In Delphi, *Component › Install Packages › Add* and select the BPL: `Output\Win32\Debug\Bpl\Atlas.IDE.Expert370.bpl` for the classic IDE (Delphi 12: `…290.bpl`), `Output\Win64\Debug\Bpl\…` for the 64-bit IDE. The plugin finds the server `Output\Win64\Debug\Bin\AtlasServer.exe` there on its own.
4. Restart Delphi once.

`AtlasSetup.exe` from your own build (`Output\Win64\Debug\Bin`) does not help here: it looks for the BPLs in `Win32` and `Win64` subfolders next to itself (the layout of the release package), while the build puts them in `Output\<platform>\Debug\Bpl`. Without a BPL it offers no IDE. More: [Installation](#installation).

## The IDE plugin

`Atlas.IDE.Expert` replaces the built-in Code Insight of RAD Studio 13 (and 12) with its own windows, filled with data by the Atlas server:

- **Code completion** with detail panel, filter chips, fuzzy matching, learning order, postfix templates, an in-editor preview, enum values first and set elements with checkboxes
- **Parameter hint** with all overloads and the active parameter
- **Hover tooltip** with declaration, documentation, clickable types, inheritance chain, history and actions (go to, usages, copy declaration, help)
- **Problems in the editor**: syntax errors, rule findings and compiler messages as squiggles, in the tooltip and as the list "Atlas-Probleme" in the message view, project-wide; marks move along while typing
- **Compiler check after saving** and the compiler messages of the "Build" tab
- **Bracket and block pairs** coloured by depth, with matching block lines
- **Results window** "Atlas Results" for references (including forms), implementations, callers, calls and inheritance; workspace symbol search; preview before renaming
- **Code actions** (Alt+Enter), expand and shrink selection (Ctrl+W, Ctrl+Shift+W), go to implementation and type definition, switch between declaration and implementation (Ctrl+Shift+↑/↓), copy qualified name; all also in the editor context menu under *Atlas*. Alt+Ins opens the **generate menu** at the cursor (constructor, properties, overridden methods, interface methods, surround, templates). Slash commands such as `/uses Unit` run after Enter, `///` above a declaration creates the documentation comment
- **Form designer**: open forms are sent to the server as the designer has them, so references, renames and checks see unsaved changes; renaming an event handler also updates its assignment in the designer
- **Command palette** (Ctrl+Shift+P), silent reload of files changed outside the IDE, hang watchdog with log
- **Editing helpers**: highlight text matching the selection (#709), toggle block comment (#703, Shift+Alt+A), new line above or below (#700, Shift+Enter, Ctrl+Alt+Enter), surround the selection while typing (#672), remove the surrounding construct (#657, Ctrl+Shift+Del) with preview, Atlas column in the gutter (#768)
- **Conditional compilation**: outline, hover, go to and checks see only the active `{$IFDEF}` branches of the project, the outline shows the branch condition (#845); `{$IF}` understands `SizeOf`, `High`, `Low`, `RTLVersion111` and `Declared`, `{$IFOPT}` follows the switches of the `.dproj` and local `{$R-}`, unknown values keep both branches active, and the hover on a condition explains its value (#847)
- **Variant records**: fields such as `TRect.Left` or `TMessage.WParam` appear in completion, hover, go to and the outline, tagged with their branch (#846)
- **Class helpers with an ancestor**: `class helper (TBaseHelper) for TFoo` is read as a helper, and `Foo.` also offers the members of the ancestor helper (#848)
- **Less common syntax**: several constraints per type parameter, named OLE arguments (`Open(FileName := 'a.docx')`), calling conventions without a semicolon, `cdecl varargs`, `assembler asm`, local routines in anonymous methods, `{$I file.inc}` as a constant value and long `else if` chains and `@@End` labels in `asm` blocks (#861), control characters such as `^C` and the brackets `(.` `.)` (#862, with an inlay hint showing the code) parse without errors; under `{$SCOPEDENUMS ON}` values need their type prefix, members from `{$I}` inside a class belong to the class (#849)
- **Defines from include files**: a `{$DEFINE}` in a file pulled in with `{$I}` counts for greying out, the outline, checks and the linter; an inlay hint behind `{$I}` lists the symbols the file defines (#860)
- **Find selection**: F3 or Shift+F3 searches a single-line selection forward or backward, otherwise the IDE's "Search Again" applies
- **Unit search** (#777): its own window instead of the IDE dialog on Ctrl+F12; the IDE dialog stays available from the menu
- **Notes** (#545) on code lines, only for you and not in the source, and **named bookmarks** (#622, Ctrl+Alt+K)
- **Favourites** in code completion (#458): Ctrl+D pins an entry to the top
- **Code metrics** as a code lens after each method header (#66) and a **TODO overview** of the project (#68)
- **Tests**: run DUnitX tests from the editor (#69) and start a single test in the debugger (#585)
- **Compiling through the IDE** (#261): Claude Code builds open projects with the IDE's compiler via the MCP tool `build_project`
- **Launch profiles** (#575) for parameters, working folder, environment and host application
- **Baseline** (#97): hide known findings, report only new ones
- **Project file `.atlas`** (#486) with team-wide settings to check in
- **Notification centre** (#601, Ctrl+Shift+Alt+N) collects messages, counter in the Atlas status field
- **Release build guard** (#533) checks the project options before a release build
- **Welcome page** with sections: continue working, projects, project history, unsaved, project setup (including "Suchpfade und Defines prüfen", check search paths and defines), test results (#763), discover Atlas, help and feedback

All settings are under *Tools › Options › Third Party › Atlas*, including the path to the server; the sections of that page are listed on the left. Next to it are the pages *Snippets*, *Tastenkonflikte* (key conflicts) and *Server*. Team-wide values live in the project file `.atlas`.

## Installation

### IDE plugin for RAD Studio 13 and 12

1. Clone the repository and open `Atlas.groupproj` in RAD Studio.
2. Build `Atlas.Text`, `Atlas.Common`, `Atlas.Windows` and `AtlasServer` for **Win64** (all four for the same platform). Result: `Output\Win64\Debug\Bin\AtlasServer.exe`. Alternatively take `AtlasServer.exe` from a [release](https://github.com/xKnockOut/Atlas-IDE-Expert/releases); the server does not depend on the Delphi version.
3. Build `Atlas.IDE.Expert` with the Delphi version the plugin is meant to run in: **Win32** for the classic IDE, **Win64** for the 64-bit IDE. Result: `Output\Win32\Debug\Bpl\Atlas.IDE.Expert370.bpl` (Delphi 13; Delphi 12: `…290.bpl`, 64-bit IDE: `Output\Win64\…`).
4. *Component › Install Packages › Add* and select the BPL.
5. If the server is neither in `Output\…\Bin` nor next to the BPL: *Tools › Options › Third Party › Atlas*, field "Atlas-Server". The page shows whether the server is found.
6. Restart Delphi once: Atlas switches off the IDE's Help Insight and structural highlighting so nothing appears twice; the IDE reads these switches only at startup.

Details and troubleshooting (German): [docs/RAD-Studio.md](docs/RAD-Studio.md).

### Supported versions

- RAD Studio or Delphi **13 Florence** and **12 Athens** (12.0 or later). The plugin is built with exactly the version it runs in; the BPL carries the package version in its name (`370` for Delphi 13, `290` for Delphi 12) so both can sit side by side.
- Classic 32-bit IDE (Win32 BPL) and the 64-bit IDE from Delphi 12.3 (Win64 BPL).
- Windows 10 and 11.

So far it is built and checked only with RAD Studio 13 in the 32-bit IDE. What remains unchecked without a Delphi 12 installation and the 64-bit IDE is listed in [docs/RAD-Studio.md](docs/RAD-Studio.md#ungeprüft).

### Claude Code and without an editor

- **Claude Code:** MCP tools and LSP as a plugin, see [Editors/ClaudeCode](Editors/ClaudeCode/README.md)
- **CI and command line:** `AtlasServer.exe --check`, see [Linter mode](#linter-mode)

More: [docs/Installation.md](docs/Installation.md).

## Documentation (German)

- [Installation](docs/Installation.md) for RAD Studio, Claude Code and the command line
- [Configuration](docs/Konfiguration.md) of `atlas.json` (generated from the JSON schema with `pwsh Tools/Update-ConfigDoc.ps1`)
- [Rules](docs/Regeln.md)
- [MCP tools](docs/MCP.md)
- [Benchmark](docs/Benchmark.md) of the performance targets

## Structure

| Project | Content |
|---|---|
| `Packages/Atlas.Text` | Package, RTL only (free of Windows and VCL); the IDE plugin includes it as source |
| `Packages/Atlas.Common` | Package, free of Windows and VCL |
| `Packages/Atlas.Windows` | Package for Windows-specific functions, free of VCL |
| `Application/AtlasServer` | The server (console program, speaks LSP over stdin/stdout) |
| `Packages/Atlas.IDE.Expert` | The IDE plugin (design-time package; Win32 for the classic IDE, Win64 for the 64-bit IDE from Delphi 12.3), layers `Atlas.Core.*`, `Atlas.UI.*`, `Atlas.IDE.*` |
| `Tests/Atlas.Tests` | DUnitX tests |

Roles, naming and import rules: [docs/Architektur.md](docs/Architektur.md).

## Requirements

- Delphi 12 Athens or newer; currently built with RAD Studio 13 (Win32 and Win64). The IDE plugin must be built with the Delphi version it runs in; the server is independent of it.
- The test project is set up for Win64 only, because DUnitX is available only as a Win64 library in the Starter edition
- DUnitX (included in RAD Studio, IDE environment variable `$(DUnitX)`)
- PowerShell for the check scripts

## Building

Open `Atlas.groupproj` in the IDE and **Build All**. The order Text → Common → Windows → server → IDE plugin → setup → tests is set in the project group. Text, Common, Windows and the server must be built for the same platform, otherwise the server does not find the package units. The IDE plugin is set up for Win32 (classic IDE) and Win64 (64-bit IDE from Delphi 12.3); which BPL is loaded depends on the IDE ([ADR 0008](docs/adr/0008-plattformen.md)).

On the command line (RAD Studio command prompt or after `rsvars.bat`):

```bat
msbuild Atlas.groupproj /t:Build /p:Config=Debug /p:Platform=Win32
```

Output goes to `Output\<platform>\<config>\` (`Bin`, `Bpl`, `Dcp`, `Dcu`).

## Testing

The DUnitX tests run without an open IDE, after building `Atlas.Tests` (Win64):

```bat
Tests\Tests.bat              :: functional tests without benchmarks
Tests\Tests.bat benchmark    :: benchmarks only (category Benchmark)
Tests\Tests.bat alle         :: both
```

Check scripts (also run as GitHub Actions):

```powershell
pwsh Tools/Check-PackageDependencies.ps1   # packages keep their dependencies
pwsh Tools/Check-ConsoleOutput.ps1         # no Write/Writeln to stdout
pwsh Tools/Check-TestCoverage.ps1          # every unit with logic has tests, every test unit runs
```

## CI

- `server.yml`: build of the project group via the IDE plugin `cc.ps1` (RAD Studio Starter has no msbuild, ADR 0007) for Win64 and Win32, including the plugin BPLs `Atlas.IDE.Expert370.bpl` for the classic and the 64-bit IDE (Win32 and Win64, kept as artifacts), and DUnitX tests (Win64 only, ADR 0008). Results as the check "DUnitX-Ergebnisse" in pull requests.
  - The job needs a self-hosted Windows runner (labels `self-hosted`, `windows`, `delphi`) on the developer's workstation. It runs in the signed-in user context, not as a service, because `cc.ps1` starts an IDE, and only while that machine is switched on. Every job starts its own scratch IDE.
  - It runs only with the repository variable `DELPHI_RUNNER=true`; otherwise the job "uebersprungen" says so in the run summary. `CC_SCRIPT` overrides the path to `cc.ps1`.
  - A new push to the same branch cancels the running build (`concurrency`).
- `package-dependencies.yml`: package dependencies, the stdout rule, Delphi 12 compatibility, rule catalog, configuration docs and no Embarcadero sources in `Tests/`.

## Command line

| Parameter | Meaning |
|---|---|
| `--log <file>` | log file, appended; paths, project, unit and user names are replaced by IDs (`datei#3`, `name#2`) |
| `--log-names` | write the log file with real paths and names (local debugging only) |
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
| `--fail-on <s>` | which findings make the exit code 1: `error` (default), `warning` or `never`, so warnings in legacy projects do not break a pre-commit hook |
| `--source-root <folder>` | root of the SARIF paths; defaults to the Git root above the target, otherwise the target's folder. Paths below it carry `uriBaseId` `%SRCROOT%`, files outside appear as absolute `file:` URIs |
| `--profile <name>` | rule profile (`standard`, `fast`, `strict`, `security`, `style` or one of your own from `profiles`); overrides `profile` in `atlas.json` |
| `--baseline <file>` | hide known findings; without it `atlas-baseline.json` next to `atlas.json` applies if present. The editor hides them as well |
| `--update-baseline` | rewrite the baseline from the current findings, exit code 0. stderr first lists entries without a file with their path (renamed, moved or deleted files; they drop out), then the counters: findings, files, added, removed, unchanged |
| `--changed [<base>]` | only files changed according to Git (or SVN, see below) against the merge base with `<base>` (default `main`); changed `.dfm`/`.fmx` check their unit, changed `.inc` all units including them, changed `.dproj`/`.dpk`/`.dpr`/`atlas.json` everything |
| `--diff <ref>` | like `--changed`, but directly against `<ref>` |
| `--include-uncommitted` | with `--changed`/`--diff` also index, working tree and new files |
| `--changed-lines` | only findings in changed lines; together with the baseline only new findings in changed lines |
| `--suppression-stats` | instead of findings: how often each rule is suppressed via `lsp-ignore` (most frequent first, including unused ones), as text or JSON; exit code 0 |
| `--metrics` | instead of findings: code metrics per method (length, nesting depth, cyclomatic and cognitive complexity, parameters; #66) with the limits from `atlas.json` (`"max"` of the `metric-*` rules); `--format text` writes a Markdown report, `json` the metric data; exit code 0 |
| `--todos` | instead of findings: open TODO entries (#68) from `// TODO`, `// FIXME` and the IDE to-do format `{ TODO 1 -oOwner -cCategory : Text }` with priority, owner and category; more markers via the option `"keywords"` of the rule `todo-comment`; `--format text` writes a Markdown overview, `json` the data; exit code 0 |

Exit code: 1 if a finding reaches `--fail-on` (default: at least one error), otherwise 0; 3 for invocation or read errors. Findings hidden by the baseline never count.

Baseline (#97): an entry in `atlas-baseline.json` records the file, the rule, the enclosing routine (fully qualified like `TFoo.Bar`, outside a routine the section such as `implementation`), a fingerprint of the line without whitespace and a fingerprint of the code ±2 lines around it. The same line in another routine therefore counts as new, as does a finding that moves to another routine. Re-indenting, moved lines and a renamed routine (same context, old name gone from the file) keep their entries. A renamed or moved file loses its entries: its findings show up as new until the baseline is updated. Older files without routines stay readable and are completed on the next update. Suppression comments for findings in the baseline never report `unused-suppression`. In editors the command `atlas.updateBaseline` (`workspace/executeCommand`, argument: URI of the project or folder) updates the baseline and answers with the counters; it checks every file of the project and keeps the server busy meanwhile. In SARIF every result carries `partialFingerprints` (`atlasBaseline/v1` from rule, routine and line, `atlasContext/v1` from the context, each with a running number `:n` for equal values in one file); with a baseline `baselineState` is added: `new`, `unchanged` (as an external suppression) or `absent` (entry without a finding). Text, JSON and the exit code contain only new findings.

In SARIF, `message.text` is the rule's English catalog name without the confidence suffix. The confidence is in `properties.confidence`, the finding's German message in `properties.detail`.

Every rule finding has a confidence (high, medium, low). It caps the severity even if `rules` sets it higher: medium confidence at most warning, low at most hint. Findings below `minConfidence` (default `medium`) are hidden. The confidence is never part of the message text; it is a separate column in the text output (`[Konfidenz mittel]`), `confidence` in JSON, `data.confidence` in LSP and its own line in the plugin's tooltip.

In an SVN working copy, `--changed` without a base compares the working copy with BASE (`svn status`), `--changed <rev>` and `--diff <rev>` with the revision (`svn diff -r`); `--include-uncommitted` adds unversioned files. The nearest working copy above the configuration folder wins (`.git` or `.svn`), Git on a tie; `vcs.provider` in `%APPDATA%\Atlas\settings.json` picks the kind (`auto`, `git`, `svn`) or turns it off (`off`). svn must be installed as a command-line tool (TortoiseSVN with command-line tools is enough).

Examples for a pre-commit hook and a GitHub Action that check only changes are in [docs/Beispiele](docs/Beispiele).

### Rules

All rules are described in [docs/Regeln.md](docs/Regeln.md). The single source is the rule catalogue `Packages/Atlas.Common/Katalog/regelkatalog.json` (English) with the translation `regelkatalog.de.json`. After changes run `pwsh Tools/Update-RuleCatalog.ps1`; CI checks with `-Check` that catalogue, implementation and documentation agree.

## Important: stdout belongs to the protocol

The server speaks LSP over stdin/stdout. Any additional output to stdout (`Writeln`, unhandled exceptions) breaks the communication with the editor. All diagnostic messages go through `ILogger` (`Atlas.Common.Logging`) to `OutputDebugString`, the log file, `window/logMessage` and, for errors, stderr. After starting, the server redirects the stdout handle and `Output` to stderr, so libraries cannot disturb the protocol either.

## Licences

Atlas is licensed under the MIT licence (`LICENSE`); third-party components with their licence texts are listed in `THIRD-PARTY-NOTICES.md` (generated by `Tools/Update-ThirdPartyNotices.ps1`).

Cache and benchmark corpus stay local, VCL sources are never checked in. The index cache lives under `%LOCALAPPDATA%\Atlas`; the server reads RTL and VCL sources only from the local Delphi installation. `Tools/Check-NoEmbarcaderoSources.ps1` checks in CI that `Tests/` contains no file with an Embarcadero copyright header.
