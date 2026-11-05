# Atlas IDE Expert

[![Donate with PayPal](https://img.shields.io/badge/Donate-PayPal-00457C?logo=paypal)](https://www.paypal.com/paypalme/xKnockOut288)

*Deutsche Fassung: [README_DE.md](README_DE.md). The user documentation is available in English ([Documentation](#documentation)); developer documents such as the architecture and the handover notes are German.*

Atlas is an expert for RAD Studio (Delphi/Object Pascal). It replaces the built-in Code Insight with its own windows and adds code analysis with 313 check rules, refactorings, navigation, form support, testing and debugging aids and its own welcome page to the IDE. The data comes from the **Atlas server**, a language server (LSP) of its own that indexes the project and also runs without the IDE as a linter or as an MCP server for Claude Code.

Features and roadmap are tracked in the [issues](https://github.com/xKnockOut/Atlas-IDE-Expert/issues).

## Quick start

You need RAD Studio or Delphi 12 or later. Ready-made downloads are on the [releases](https://github.com/xKnockOut/Atlas-IDE-Expert/releases) page; releases 1.0.0 to 1.2.0 contain the plugin for Delphi 13 only. What is new in 1.2.0 is listed in the [changelog](CHANGELOG.md) (German).

**Option A – add the release package by hand:**

1. Download `atlas-ide-expert-<version>.zip` from the release and unpack it into a permanent folder, e.g. `%LOCALAPPDATA%\Programs\Atlas`. Close Delphi first.
2. Start Delphi, *Component › Install Packages › Add* and select `Win32\Atlas.IDE.Base370.bpl` from that folder (64-bit IDE: `Win64\…`). The plugin finds the server `AtlasServer.exe` one level above the BPL.
3. Restart Delphi once.

Up to 1.1.0 the package contained the installer `AtlasSetup.exe`; it was removed in 1.2.0. Details (German): [docs/Installation.md](docs/Installation.md).

**Option B – build it yourself and install the package in the IDE:**

1. Install Delphi 12 or later and clone this repository.
2. Open `Atlas.groupproj` in Delphi and build all projects for **Win64** (*Build All*). For the classic 32-bit IDE, also build `Atlas.IDE.Base` for **Win32**.
3. In Delphi, *Component › Install Packages › Add* and select the BPL: `Output\Win32\Debug\Bpl\Atlas.IDE.Base370.bpl` for the classic IDE (Delphi 12: `…290.bpl`), `Output\Win64\Debug\Bpl\…` for the 64-bit IDE. The plugin finds the server `Output\Win64\Debug\Bin\AtlasServer.exe` there on its own. From 2.0, then add every module package from the same folder, e.g. `Atlas.IDE.Debugger370.bpl` (#1456); always the core package `Atlas.IDE.Base` first.
4. Restart Delphi once.

More: [Installation](#installation).

## Features

Short overview; each heading links to the full description. Features marked *(experimental)* are off by default and can be switched on under *Tools › Options › Third Party › Atlas* once the master switch "Experimentell" is on. What changed per version: [CHANGELOG](CHANGELOG.md) (German).

### [Writing](docs/features/en/Writing.md)
- **Code completion** in its own popup with detail panel, fuzzy matching, favourites and `+ Unit` for missing uses
- **Context-aware suggestions:** enum values, `case` values, exception classes after `raise`, anonymous method skeletons
- **Parameter hint** with overload choice and `Format` placeholder checks
- **Templates:** code, postfix and class-aware templates, your own snippets, slash commands like `/uses` and `/extract`
- **Generate menu** (Alt+Ins) and editing helpers: surround, move lines, toggle comments, tidy `var` blocks
- **Formatter** (Ctrl+Shift+Alt+L), also without the IDE

### [Understanding](docs/features/en/Understanding.md)
- **Hover** with declaration, XMLDoc, inheritance, constant values and debugger values
- **Type hints, code metrics and recursion marks** in the editor; inactive `{$IFDEF}` branches dimmed
- **Architecture overview:** subsystems, central units, cycles, comparison with a saved state
- **Code queries** such as `classes where inherits TForm and methods > 40`
- **Hotspots, call diagram, unit relations** and the path between two symbols

### [Navigating](docs/features/en/Navigating.md)
- **Go to** definition, implementation and counterpart; navigation history
- **Breadcrumb bar, editor toolbar and Atlas status bar** above and below the editor
- **Quick open** (Ctrl+P), unit search (Ctrl+F12) and a search bar with replace across files
- **Results window** for references, callers and implementations, plus impact and data flow
- **Bookmarks, notes, minimap and sticky scroll**

### [Code analysis](docs/features/en/Code-analysis.md)
- **313 check rules** while you type: 204 bugs, 99 code smells, 10 security rules
- **"Compiler ahead":** dcc errors and warnings before you build, with quick fixes
- **Window "Atlas-Prüfung"** for file, project or group, with bulk fixes
- **Profiles, confidence, baseline and suppressions** for legacy projects
- **Linter for CI** with text, JSON or SARIF output. All rules: [docs/Regeln.md](docs/Regeln.md)

### [Refactorings and code actions](docs/features/en/Refactorings.md)
- **Rename** project-wide including forms, **change signature**, **safe delete**
- **Extract method, introduce variable, convert `if` ⇄ `case`** and many more conversions
- **Class actions:** implement interface, extract interface or superclass, generate properties
- **uses:** add missing units, sort, remove unused ones
- **Quick fixes** for many rules (Alt+Enter) and **undo Atlas changes** across files

### [Forms](docs/features/en/Forms.md)
- **Unsaved designer state** is seen by references, renames and checks
- **Checks between form and code** and property rules for form files
- **Convert binary forms** to text forms

### [Build, test, debug](docs/features/en/Build-test-debug.md)
- **Build gate** for hints and warnings, quick fixes for compiler messages, release build guard
- **DUnitX tests** from the editor, including **only the tests affected** by a change
- **Debugging:** values in the hover and inline, visualizers, evaluate window, smart step into
- **Exceptions:** history window, exception bar, just my code, access violations explained

### [IDE comfort](docs/features/en/IDE-comfort.md)
- **Atlas welcome page** with projects, history, issues and news
- **Issue tracker** (GitHub, YouTrack) and **version control** (Git, SVN) inside the IDE
- **Command palette** (Ctrl+Shift+P), notification centre, server window
- **Robustness:** errors never reach the IDE, safe start, crash cases you can replay

### [Settings](docs/features/en/Settings.md)
- **Options page as a tree**, every feature with its own switch
- **Module switches** for whole areas such as debugging, tests or the issue tracker
- **Export, import, profiles and reset**
- **Team-wide values** in `.atlas` and `atlas.json`
- **Language follows the IDE** (German or English)

### [Claude Code and MCP](docs/features/en/Claude-Code.md)
- **32 MCP tools** to read, check, build, test, rename and fix Delphi code
- **5 prompts** as slash commands, e.g. unit review or commit preparation
- **Hook:** every Pascal file Claude changes is checked right away

### Planned

Not yet in `main`, tracked as issues:

- Further check rules (sub-issues of #1086)
- Debugging (#614) and designer features for later versions
- Splitting the plugin into `Atlas.IDE.Base` and module packages (2.0, ADR 0017); the debugger, bookmarks (notes, bookmarks, TODO list), build tools (build on open, project tasks, start profiles, compiler switches), the build pipeline (builds on request, check before compiling, release guard, verdict and summary), tests (DUnitX runner, test at cursor, code lens, affected tests), the designer bar, search (Atlas search, unit search, code queries) analysis (architecture, hotspots, unit relations, symbol path), rule checks (baseline, compiler messages into the baseline, DFM property rules, bulk fix) and the issue tracker (issue keys in code, issues in the line history, tracker commands, board and attach menu entries, create issue in the editor context menu, the tiles My issues, Sprint and Test results including build server access; Base reaches create issue from findings and crash cases through a contract; files, environment and shell only through the module's adapters) and the welcome page (its settings in the options dialog are a section of the module) register as modules through the contracts (#1455, see Structure) and live in their own packages (#1456)

## Installation

### IDE plugin for RAD Studio 13 and 12

1. Clone the repository and open `Atlas.groupproj` in RAD Studio.
2. Build `Atlas.Text`, `Atlas.Common`, `Atlas.Windows` and `AtlasServer` for **Win64** (all four for the same platform). Result: `Output\Win64\Debug\Bin\AtlasServer.exe`. Alternatively take `AtlasServer.exe` from a [release](https://github.com/xKnockOut/Atlas-IDE-Expert/releases); the server does not depend on the Delphi version.
3. Build `Atlas.IDE.Base` with the Delphi version the plugin is meant to run in: **Win32** for the classic IDE, **Win64** for the 64-bit IDE. Result: `Output\Win32\Debug\Bpl\Atlas.IDE.Base370.bpl` (Delphi 13; Delphi 12: `…290.bpl`, 64-bit IDE: `Output\Win64\…`).
4. *Component › Install Packages › Add* and select the BPL. From 2.0 the contracts between modules live in the core package and every module in its own package (`Atlas.IDE.Debugger`, `.Designer`, `.Rules`, `.Tests`, `.Bookmarks`, `.Analysis`, `.Search`, `.Build`, `.BuildPipeline`, `.Tracker`, `.Welcome`, #1456), compiled against the core package: build and install them after `Atlas.IDE.Base`.
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
- **CI and command line:** `AtlasServer.exe --check`, see [Linter mode](docs/features/en/Command-line.md#linter-mode)
- **Claude Code in the cloud (Linux):** the environment's setup script and the SessionStart hook install the server as `AtlasServer` (and `AtlasServer.exe`) in `/usr/local/bin`, prebuilt from the `cloud-linux` pre-release or built with Free Pascal; setup in [Editors/ClaudeCode](Editors/ClaudeCode/README.md#in-cloud-sitzungen-linux) ([ADR 0013](docs/adr/0013-linux-bau.md), [Building on Linux](#building-on-linux))

More: [docs/Installation.md](docs/Installation.md).

## Documentation

- [Features](#features) in detail: one page per area under [docs/features/en](docs/features/en/)
- [Installation](docs/en/Installation.md) for RAD Studio, Claude Code and the command line
- [IDE plugin](docs/en/RAD-Studio.md): every feature in detail
- [Settings](docs/en/Settings.md) of the plugin
- [Configuration](docs/en/Configuration.md) of `atlas.json` (generated from the schema's `x-description-en` with `pwsh Tools/Update-ConfigDoc.ps1`)
- [Rules](docs/en/Rules.md) (generated from the rule catalog with `pwsh Tools/Update-RuleCatalog.ps1`)
- [MCP tools](docs/en/MCP.md) and the [Claude Code plugin](Editors/ClaudeCode/README.en.md)
- In German only: [Benchmark](docs/Benchmark.md) of the performance targets, [architecture](docs/Architektur.md), [test cases](docs/Atlas-Testfaelle.md)

Every English page links its German original and vice versa.

## Structure

| Project | Content |
|---|---|
| `Packages/Atlas.Text` | Package, RTL only (free of Windows and VCL); the IDE plugin includes it as source |
| `Packages/Atlas.Common` | Package, free of Windows and VCL |
| `Packages/Atlas.Windows` | Package for Windows-specific functions, free of VCL |
| `Packages/Atlas.Linux` | Linux counterparts of the server's Windows adapters, source only, for the Free Pascal build (ADR 0013) |
| `Application/AtlasServer` | The server (console program, speaks LSP over stdin/stdout) |
| `Packages/Atlas.IDE.Base` | The IDE plugin (design-time package; Win32 for the classic IDE, Win64 for the 64-bit IDE from Delphi 12.3), layers `Atlas.Core.*`, `Atlas.UI.*`, `Atlas.IDE.*` |
| `Tests/Atlas.Tests` | DUnitX tests |

Roles, naming and import rules: [docs/Architektur.md](docs/Architektur.md).

Contracts for the modules from 2.0 on (#1455, ADR 0017): `Atlas.Core.Modules.Contract` (module, scope, registry with `Provide`/`FindAll` by interface GUID, change notification, contract version), `Atlas.Core.Modules.Registry` (module list built from registrations, unregistering in reverse through the scope), `Atlas.Core.Modules.Handshake` (exported `AtlasCoreContractVersion`), `Atlas.Core.Settings.Contract` and `Atlas.Core.Settings.Parts` (settings parts of the modules, kept centrally in Base; values of missing modules are preserved). Base collects what modules contribute through `Atlas.Core.Modules.Contributions` (commands, Atlas menu and editor context menu entries, keys, settings, theme and editor view listeners, hover values, gutter layers, own bookmarks in the overview ruler); only modules that are running count (a module switched off contributes nothing). It hosts their feature parts in the feature table (`Atlas.Core.Diagnostics.ModuleHosting`); `Atlas.IDE.Foundation.Host` gives modules the server session, background server commands (answers reach a module only while it is registered, `Atlas.Core.Modules.Answer`), the message view, warnings, the log and status field items. Modules so far: the debugger (`Atlas.IDE.Debug.Composition`, id `atlas.debugger`) bookmarks (`Atlas.IDE.Bookmarks.Composition`, id `atlas.bookmarks`: notes, named and quick bookmarks, TODO list) and build tools (`Atlas.IDE.BuildTools.Composition`, id `atlas.build`; it adds compile participants it removes again on stop) and the build pipeline (`Atlas.IDE.BuildPipeline.Composition`, id `atlas.buildpipeline`, switch `buildPipeline`: builds on request with the MCP inbox, check before compiling, release guard with *Check release build*, verdict and build summary; Base hands it the compiler messages and the verdict through `Atlas.Core.Build.Pipeline`, without the module Base judges a build by the compiler alone; other modules and the welcome page build through `IAtlasBuildJobs` in `Atlas.IDE.Contracts.BuildPipeline`; compile events, compiler messages, check on save and the messages of the last build stay in Base) and tests (`Atlas.IDE.Tests.Composition`, id `atlas.tests`; they hear about evaluated builds through `IAtlasBuildVerdictListener`, Base and other modules start tests through `IAtlasTestRunner`, start options and temporary start parameters are in Base, `Atlas.IDE.Foundation.StartOptions`) the designer (`Atlas.IDE.Designer.Composition`, id `atlas.designer`: designer bar), search (`Atlas.IDE.Search.Composition`, id `atlas.search`; menu entries also under View › Atlas, IDE actions a module takes over show up in the key map through `IAtlasTakenActions`, server requests through `TAtlasIdeHost.RunRequestAsync`) and analysis (`Atlas.IDE.Analysis.Composition`, id `atlas.analysis`: architecture, hotspots, unit relations with the interface cost field, symbol path; concurrent server commands through `TAtlasIdeHost.RunServerCommandAsync`, the path view of the results window stays in Base) and rule checks (`Atlas.IDE.Rules.Composition`, id `atlas.rules`, switch `ruleChecks`: baseline commands, DFM property rules, bulk fix in the problems window through `IAtlasBulkFixer`, baseline update for the setup wizard through `IAtlasBaselineSource` in `Atlas.IDE.Contracts.Rules`; checking, the problems window and the baseline file state stay in Base; project summaries are kept by Base, `Atlas.IDE.Projects.Summaries`, also without the welcome page; the rules and tests modules write baseline and test runs there, whoever shows them listens through `IAtlasProjectSummaryListener`) and the welcome page (`Atlas.IDE.Welcome.Composition`, id `atlas.welcome`, switch `welcome`: the page with all its sections, its commands and menu entries, Atlas Start also under View › Atlas; it reaches builds, tests, start profiles, tasks and the baseline only through contracts, `Atlas.IDE.Welcome.Neighbors`, and shows tiles of other modules) and the issue tracker (`Atlas.IDE.Tracker.Composition`, id `atlas.tracker`, switch `issues`: issue keys in code, issues in the line history, tracker commands, board under View › Atlas, attach in the Atlas menu, create issue in the editor context menu and on its key; "My issues", the sprint tile and "Create issue" are tiles of the module on the welcome page and in Atlas Start (`Atlas.IDE.Tracker.Tiles`, through `IAtlasWelcomeTile`), split into context, services, commands, status field, query and start/end parts (`Atlas.IDE.Tracker.Issues*`, `Atlas.IDE.Tracker.IssueStart`); method bodies at a line and branch names are in Base, `TAtlasMethodToggle.BodyAt`, `Atlas.Core.Vcs.BranchNames`; its page in the options dialog is a settings section of the module, `Atlas.UI.Tracker.SettingsSection`, assembled from small parts with the table rules in `Atlas.Core.Tracker.SettingsTables`); menu entries may also come without a command (one per project task); the results window shows module lists with ids (`TAtlasResultsItemList`), the general tooltip is `Atlas.UI.Popup.TitledTip`; contracts between modules live in the core package under `Source/Contracts` (units `Atlas.IDE.Contracts.*`, `IAtlasDebugReportSource` for the debug note when attaching to an issue, `IAtlasBuildToolsSource` and `IAtlasTestsSource` for the welcome page).

## Requirements

- Delphi 12 Athens or newer; currently built with RAD Studio 13 (Win32 and Win64). The IDE plugin must be built with the Delphi version it runs in; the server is independent of it.
- The test project is set up for Win64 only, because DUnitX is available only as a Win64 library in the Starter edition
- DUnitX (included in RAD Studio, IDE environment variable `$(DUnitX)`)
- PowerShell for the check scripts

## Building

Open `Atlas.groupproj` in the IDE and **Build All**. The order Text → Common → Windows → server → IDE plugin → tests is set in the project group. Text, Common, Windows and the server must be built for the same platform, otherwise the server does not find the package units. The IDE plugin is set up for Win32 (classic IDE) and Win64 (64-bit IDE from Delphi 12.3); which BPL is loaded depends on the IDE ([ADR 0008](docs/adr/0008-plattformen.md)).

On the command line (RAD Studio command prompt or after `rsvars.bat`):

```bat
msbuild Atlas.groupproj /t:Build /p:Config=Debug /p:Platform=Win32
```

Output goes to `Output\<platform>\<config>\` (`Bin`, `Bpl`, `Dcp`, `Dcu`).

### Building on Linux

Only the server, only for Claude Code sessions in the cloud and other Linux machines without Delphi ([ADR 0013](docs/adr/0013-linux-bau.md)):

```bash
Tools/Linux/Build-AtlasServer.sh --install /usr/local/bin
```

The script first takes the prebuilt program from the `cloud-linux` pre-release (workflow `linux-server.yml`, state of main) if it matches the source. Otherwise it fetches Free Pascal trunk at a pinned commit from the same release or builds it once (about 10 minutes, under `~/.cache/atlas-fpc`), prepares the source with `Tools/Linux/Convert-ForFpc.py` and compiles to `Output/Linux64/Bin/AtlasServer`. If the source has not changed, it does not rebuild. Platform adapters live in `Packages/Atlas.Linux`; `Shell.Platform` picks them. The Linux build does not replace the Delphi build before a merge.

Without any Delphi installation, `AtlasServer --check X.dproj` and the editor take the Delphi version the project expects: `delphiVersion`, otherwise the one matching `<ProjectVersion>` of the .dproj, otherwise the newest known one. It sets only `CompilerVersion`, `RTLVersion` and `VERxxx` (no library paths), so `{$IF CompilerVersion >= 36}…{$ELSE}…{$ENDIF}` keeps only one branch, as in the IDE (#1321).

## Testing

The DUnitX tests run without an open IDE, after building `Atlas.Tests` (Win64):

```bat
Tests\Tests.bat              :: functional tests without benchmarks
Tests\Tests.bat benchmark    :: benchmarks only (category Benchmark)
Tests\Tests.bat alle         :: both
```

Check scripts (also run as GitHub Actions):

```powershell
pwsh Tools/Check-PackageDependencies.ps1   # packages keep their dependencies, module boundaries from ADR 0017
pwsh Tools/Test-PackageDependencies.ps1    # self-test of the module boundaries with deliberate violations
pwsh Tools/Check-ConsoleOutput.ps1         # no Write/Writeln to stdout
pwsh Tools/Check-TestCoverage.ps1          # every unit with logic has tests, every test unit runs
pwsh Tools/Check-WindowHosts.ps1           # dock windows and editor bars use their shared hosts
```

`Tests/DccFaelle` holds minimal cases for the compiler rules: each one states whether dcc reports it or compiles it. `pwsh Tools/Build-DccFaelle.ps1` builds them in a scratch IDE via `cc.ps1` (Win32 and Win64) and writes the dcc messages per case to `Output/DccFaelle-Ergebnis.txt`; the rules must not be stricter than that result (#1328).

`Tests/Compilermeldungen` has one case for every dcc warning, hint and error that Delphi 13 can be made to report (471 cases; codes without a case are listed in `ohne-fall.txt`). `pwsh Tools/Build-Compilermeldungen.ps1 -IdeProfile <profile> -AtlasServer <exe>` builds each case on its own in a scratch IDE (Win32 and Win64) and runs `AtlasServer --check` over them; `python3 Tools/Compare-Compilermeldungen.py` writes `vergleich.md` with what Atlas finds, misses or reports with another code. The results of the first Delphi 13 run are checked in under `Tests/Compilermeldungen/Ergebnisse` (Atlas finds 211 of 332 codes; the missing rules are #1369–#1383). Without an IDE, `-Dcc` builds the cases with `dcc32`/`dcc64` of the Delphi version chosen with `-BdsVersion` (`23.0` = Delphi 12), `-ResultFile` keeps that run apart (#1383). Style rules name a compiler code in their message only where dcc reports it: `unused-assignment` names H2077 only for unmanaged types, `uses-cycle` F2047 only for pure interface cycles (F2092 for a unit naming itself), `xmldoc-mismatch` W1205 to W1208 only in the interface section and only for the forms dcc rejects; the comparison counts these rules only by the code in the message. A second Delphi 13 run with variant cases (#1383) showed that dcc does not report W1009 for fields and static methods, H2367 (even with `-JPHNE`), H2440, H2444, W1071, E2373, E2121 and E2287 for the same entry twice, and accepts lines of up to 1222 characters in the IDE; the rules no longer name these codes there, `exports-invalid` leaves variables alone and names E2276 for constants and types, `inline-not-expanded` no longer reports strict private members. With the Community Edition `-Dcc` stops with exit code 3, because `dcc32` there only prints that it does not compile on the command line.

## CI

- `server.yml`: build of the project group via the IDE plugin `cc.ps1` (RAD Studio Starter has no msbuild, ADR 0007) for Win64 and Win32, including the plugin BPLs `Atlas.IDE.Base370.bpl` for the classic and the 64-bit IDE (Win32 and Win64, kept as artifacts), and DUnitX tests (Win64 only, ADR 0008). Results as the check "DUnitX-Ergebnisse" in pull requests.
  - The job needs a self-hosted Windows runner (labels `self-hosted`, `windows`, `delphi`) on the developer's workstation. It runs in the signed-in user context, not as a service, because `cc.ps1` starts an IDE, and only while that machine is switched on. Every job starts its own scratch IDE.
  - It runs only with the repository variable `DELPHI_RUNNER=true`; otherwise the job "uebersprungen" says so in the run summary. `CC_SCRIPT` overrides the path to `cc.ps1`.
  - A new push to the same branch cancels the running build (`concurrency`).
- `package-dependencies.yml`: package dependencies, the stdout rule, Delphi 12 compatibility, rule catalog, configuration docs, no Embarcadero sources in `Tests/`, and Atlas windows and editor bars only through their shared hosts.

## Command line

The server also runs without an editor: linter for pre-commit hooks and CI (`--check`, text, JSON or SARIF), formatter (`--format-check`, `--format-write`), architecture report, code queries, hotspots and affected tests. All parameters: [docs/features/en/Command-line.md](docs/features/en/Command-line.md).

## Important: stdout belongs to the protocol

The server speaks LSP over stdin/stdout. Any additional output to stdout (`Writeln`, unhandled exceptions) breaks the communication with the editor. All diagnostic messages go through `ILogger` (`Atlas.Common.Logging`) to `OutputDebugString`, the log file, `window/logMessage` and, for errors, stderr. After starting, the server redirects the stdout handle and `Output` to stderr, so libraries cannot disturb the protocol either.

## Licences

Atlas is licensed under the MIT licence (`LICENSE`); the end user licence agreement is `EULA.txt` (included in the release package); third-party components with their licence texts are listed in `THIRD-PARTY-NOTICES.md` (generated by `Tools/Update-ThirdPartyNotices.ps1`).

Cache and benchmark corpus stay local, VCL sources are never checked in. The index cache lives under `%LOCALAPPDATA%\Atlas`; the server reads RTL and VCL sources only from the local Delphi installation. `Tools/Check-NoEmbarcaderoSources.ps1` checks in CI that `Tests/` contains no file with an Embarcadero copyright header.
