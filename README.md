# Atlas IDE Expert

[![Donate with PayPal](https://img.shields.io/badge/Donate-PayPal-00457C?logo=paypal)](https://www.paypal.com/paypalme/xKnockOut288)

*Deutsche Fassung: [README_DE.md](README_DE.md). The user documentation is available in English ([Documentation](#documentation)); developer documents such as the architecture and the handover notes are German.*

Atlas is an expert for RAD Studio (Delphi/Object Pascal). It replaces the built-in Code Insight with its own windows and adds code analysis with 335 check rules, refactorings, navigation, form support, testing and debugging aids and its own welcome page to the IDE. The data comes from the **Atlas server**, a language server (LSP) of its own that indexes the project and also runs without the IDE as a linter or as an MCP server for Claude Code. From 2.0 the plugin consists of the core package `Atlas.IDE.Base` and 14 module packages that you install as needed ([Structure](#structure)).

Features and roadmap are tracked in the [issues](https://github.com/xKnockOut/Atlas-IDE-Expert/issues).

## Quick start

You need RAD Studio or Delphi 12 or later. Ready-made downloads are on the [releases](https://github.com/xKnockOut/Atlas-IDE-Expert/releases) page; releases 1.0.0 to 1.2.0 contain the plugin for Delphi 13 only. What is new in each version is listed in the [changelog](CHANGELOG.md) (German); a short bilingual summary of 2.1.0 is in [docs/Release-Notizen/2.1.0.md](docs/Release-Notizen/2.1.0.md).

**Option A – add the release package by hand:**

1. Download `atlas-ide-expert-<version>.zip` from the release and unpack it into a permanent folder, e.g. `%LOCALAPPDATA%\Programs\Atlas`. Close Delphi first.
2. Start Delphi, *Component › Install Packages › Add* and select `Win32\Atlas.IDE.Base370.bpl` from that folder (64-bit IDE: `Win64\…`). The plugin finds the server `AtlasServer.exe` one level above the BPL.
3. From 2.0: add the module packages from the same folder as well (`Atlas.IDE.Debugger370.bpl`, `Atlas.IDE.Tests370.bpl` …, see [Structure](#structure)); always the core package `Atlas.IDE.Base` first. Leave out the modules you do not need.
4. Restart Delphi once.

From 2.0, `AtlasUpdate.exe install` from the package does these steps in a console dialog: choose IDE and profile, target folder and modules (#1519). Up to 1.1.0 the package contained the installer `AtlasSetup.exe`; it was removed in 1.2.0. Details: [docs/en/Installation.md](docs/en/Installation.md).

**Option B – build it yourself and install the package in the IDE:**

1. Install Delphi 12 or later and clone this repository.
2. Open `Atlas.groupproj` in Delphi and build all projects for **Win64** (*Build All*). For the classic 32-bit IDE, also build `Atlas.IDE.Base` for **Win32**.
3. In Delphi, *Component › Install Packages › Add* and select the BPL: `Output\Win32\Debug\Bpl\Atlas.IDE.Base370.bpl` for the classic IDE (Delphi 12: `…290.bpl`), `Output\Win64\Debug\Bpl\…` for the 64-bit IDE. The plugin finds the server `Output\Win64\Debug\Bin\AtlasServer.exe` there on its own. Then add the module packages from the same folder (`Atlas.IDE.Debugger370.bpl` …); always the core package `Atlas.IDE.Base` first.
4. Restart Delphi once.

More: [Installation](#installation).

## Packages of the IDE plugin

The plugin consists of the core `Atlas.IDE.Base` and 14 modules. Install Base plus only the modules you need; each module can also be switched off in the options. The number of units gives the rough size (as of 2.1).

| Package | Scope | Units | Switch |
|---|---|--:|---|
| `Atlas.IDE.Base` | Core, always needed: server session and code insight (completion, hover with parameters and unit contents, parameter hint, learned suggestions as ghost text), editor (breadcrumb bar, sticky header, minimap, inlay hints, editor bar, finding marks), navigation and result window, refactorings and light bulb, findings and the “Atlas Findings” window, compiler messages explained, options with search, command palette, diagnostic mode; registry and all contracts between the modules | 760 | – |
| `Atlas.IDE.Designer` | Designer bar: “Arrange” (width to text, button bar, form grid, duplicate in a row, insert space, fit to content, layers, wrap in container, fonts and colors, suggest anchors, format painter, groups), measure spacing and set it by handle, shared size handles, quick bar, magnifier, tab order, try sizes and scaling, meaningful names, “Atlas Structure” and “Event map” windows, data binding, extract to frame, usages in code, find components and properties, undo (experimental) | 121 | `designer.enabled` |
| `Atlas.IDE.Tracker` | Issue tracker (YouTrack, GitHub and others): “My issues” with project choice, start, finish and review along the workflow transitions, time tracking, state in the status bar, board with swimlanes, sprint tile, flow map, “Attach to issue”, issue ids in code | 143 | `issues.enabled` |
| `Atlas.IDE.Welcome` | Welcome page with projects, “Continue” with the work state per issue, “What's new in Atlas”, “Discover Atlas” and “Atlas setup” with index progress per project; “Atlas Start” | 75 | `welcomePage.enabled` |
| `Atlas.IDE.Debugger` | Debugging: values in hover and editor, evaluate window, exceptions, step filters, step into a chosen call, custom value display per type, explain access violations including the module of the fault address, what threads wait for, check breakpoints before starting, parallel stacks, breakpoint sets, threads in source | 85 | `debug.enabled` |
| `Atlas.IDE.Search` | Atlas search with replace, regex and project scope, unit search, code queries | 38 | `search.enabled` |
| `Atlas.IDE.Analysis` | Architecture, hotspots, unit relations, path between symbols, code lens with code metrics, “Unit relations” and “Dependent units” also from the project manager | 30 | `analysis.enabled` |
| `Atlas.IDE.VersionControl` | Version control: Git and SVN, change marks with inline diff, line history, branch when starting an issue, working copies, project state | 26 | `vcs.enabled` |
| `Atlas.IDE.Bookmarks` | Notes, named and quick bookmarks, TODO list | 24 | `bookmarks.enabled` |
| `Atlas.IDE.Build` | Build tools: build on open, project tasks, start profiles, compiler switches | 24 | `buildTools.enabled` |
| `Atlas.IDE.Rules` | Rule checks: rule editor, baseline and suppressions, compiler messages into the baseline, form property rules, bulk fix, IDE errors (Error Insight) next to the findings; suppress, configure and disable a rule from a finding (without the module only the findings and “Explain rule” remain) | 16 | `ruleChecks.enabled` |
| `Atlas.IDE.Tests` | DUnitX runner, test at cursor, code lens, “tested by” marks, affected tests, wizard “DUnitX test unit for unit …”, leak check setup | 30 | `tests.enabled` |
| `Atlas.IDE.BuildPipeline` | Builds on request (also for MCP), check before compiling, release guard, verdict and build summary | 9 | `buildPipeline.enabled` |
| `Atlas.IDE.Assistants` | AI assistants: builds through `build_project` and changes to open files by MCP clients, own options page | 10 | `assistants.enabled` |
| `Atlas.IDE.Help` | F1 help: rule, setting and window pages of the documentation | 5 | `help.enabled` |

## Features

Short overview; each heading links to the full description. Features marked *(experimental)* are off by default and can be switched on under *Tools › Options › Third Party › Atlas* once the master switch "Experimental" is on. What changed per version: [CHANGELOG](CHANGELOG.md) (German).

### [Writing](docs/features/en/Writing.md)
- **Code completion** in its own popup with detail panel, fuzzy matching, favourites and `+ Unit` for missing uses
- **Context-aware suggestions:** enum values, `case` values, exception classes after `raise`, anonymous method skeletons, after `if X is T then` the members of `T` with the cast, and in the footer the matches that are only missing because they are private or protected
- **Parameter hint** with overload choice and `Format` placeholder checks
- **Templates:** code, postfix and class-aware templates, your own snippets, slash commands like `/uses` and `/extract`
- **Generate menu** (Alt+Ins) and editing helpers: surround, move lines, toggle comments, tidy `var` blocks
- **Formatter** (Ctrl+Shift+Alt+L), also without the IDE
- **Class completion:** `{ TCustomer }` above the bodies (or a separator line, doc sentence, region), constructors and destructor first, then get/set pairs; new bodies prefilled with `inherited` and `Result := FName`
- **Indentation while typing:** after Enter the caret lands where the block structure puts it, `end`, `until`, `finally` and `else` move to their counterpart, and a string is split with `' +` when you break the line
- **Learned suggestions:** after `X := TFoo.Create;` or `L.BeginUpdate;` and Enter Atlas suggests as grey ghost text what usually follows in your own project (`try … finally X.Free; end;`), without AI and without network; Tab accepts, Esc discards, team house rules in `atlas.json`

### [Understanding](docs/features/en/Understanding.md)
- **Hover** with declaration, XMLDoc, inheritance, constant values and debugger values; the expanded published members of large components scroll with the mouse wheel (`hover.membersMaxLines`, default 15 rows); parameters and return value of a routine are always listed one per line below the declaration like Help Insight, also without XMLDoc (`hover.signatureParams`); over a uses entry it lists the unit's types grouped by kind and clickable, the ones used in the file first (`hints.unitContents`); below a finding, “Show example” expands the description and the wrong/right example from the rule catalog (`hover.ruleExamples`)
- **Type hints, code metrics and recursion marks** in the editor; inactive `{$IFDEF}` branches dimmed
- **Pair colours and block lines** by depth; local routines stand out (one level deeper or their own colour, optionally shaded)
- **Architecture overview:** subsystems, central units, cycles, comparison with a saved state
- **Code queries** such as `classes where inherits TForm and methods > 40`
- **Hotspots, call diagram, unit relations** and the path between two symbols

### [Navigating](docs/features/en/Navigating.md)
- **Go to** definition, implementation and counterpart; navigation history (also with the mouse back/forward buttons)
- **Breadcrumb bar, editor toolbar and Atlas status bar** above and below the editor; the breadcrumbs also show the visibility section (`private`, `public` …) and the block (`const`, `type`, `class var`) inside a class, with member counts, “New line at the end of …” and “Create section” in the section menu, a context menu on every part (copy name, with unit or signature, find references, rename, show the component in the designer), a counter for overloads (`Load (2/3)`) with a menu of all overloads and their parameters, the interface mark (`Save [ICustomer]`) on methods that implement an interface method, with a jump to its declaration, a metrics card when hovering methods and types (lines, complexity, nesting, parameters; yellow above the limit, Ctrl+I), the visibility mark (`−`, `#`, `+`, `◆`) of the method in its body, the declaration block of the unit (`type`, `const`, `var`, `resourcestring` …) the conditional branch (`{$IFDEF …}`) the region (`{$REGION}`) and, optionally, `try`/`except`/`finally` and the `case` branch in the body; the editor toolbar's “Go to uses clause” switches between the interface and implementation uses
- **Quick open** (Ctrl+P), unit search (Ctrl+F12) and a search bar with replace across files
- **Results window** for references, callers and implementations, plus impact and data flow
- **Bookmarks, notes, minimap and sticky scroll**
- **Regions:** collapse or expand all `{$REGION}` blocks when a file opens, or on demand

### [Code analysis](docs/features/en/Code-analysis.md)
- **335 check rules** while you type: 220 bugs, 104 code smells, 11 security rules; findings follow their line immediately while you edit, before the server answers (`editor.trackLines`)
- **"Compiler ahead":** dcc errors and warnings before you build, with quick fixes; Atlas finds units like dcc, including namespaces and unit aliases (`WinTypes`, `WinProcs`)
- **Window "Atlas Findings"** for file, project or group, with bulk fixes; with a group open, the scope list also offers each project of the group; optionally the IDE errors (Error Insight) appear next to them, with a "Source" column and filter (`problems.ideErrors`)
- **Compiler messages explained:** the hover shows the typical cause of a dcc or IDE message such as E2003 or W1035 below the message, with the links "Explain" (dialog with a wrong and a right example) and "DocWiki"; about 40 messages in English and German, also without dcc (`hover.explainMessages`)
- **Profiles, confidence, baseline and suppressions** for legacy projects
- **Experimental style rules with few false alarms:** `hardcoded-string` skips log, check and comparison calls, date masks and markup; `magic-number` skips the DPI base 96, full bit masks, time units and point lists; `naming-prefix` keeps the parameter names of event handlers assigned in code; `public-field` skips helper classes under `private type`
- **Types from installed packages:** the IDE tells Atlas the types of its packages (even without .pas). "Type is not declared" stays silent for them, the quick fix suggests their unit, completion offers them with a `uses` entry
- **Members of types from installed packages:** for units without source, Atlas asks the IDE for the members it knows via RTTI (properties, methods with parameter types, fields, interfaces, enum values). Hover, member completion after `.`, parameter hints and enum values for parameters then work for these types too, without "go to declaration".
- **Linter for CI** with text, JSON or SARIF output. All rules: [docs/Regeln.md](docs/Regeln.md)

### [Refactorings and code actions](docs/features/en/Refactorings.md)
- **Rename** project-wide including forms, **change signature**, **safe delete**
- **Extract method, introduce variable, convert `if` ⇄ `case`** and many more conversions; *Extract method* also replaces equal places in the unit on request, each one deselectable in the preview
- **Class actions:** implement interface, extract interface or superclass, generate properties
- **uses:** add missing units, sort, remove unused ones; a unit counts as used only when a name really resolves to it, as dcc decides (members of its classes and names shadowed later do not count; enum values, helpers, attributes and inline bodies do)
- **Quick fixes** for many rules (Alt+Enter) and **undo Atlas changes** across files

### [Forms](docs/features/en/Forms.md)
- **Designer views** with their own buttons in the designer bar: measure distances while dragging and with Alt, try form sizes, check scaling and long texts, suggest meaningful names, Atlas Structure window with links between components, data binding of the selection as a breadcrumb bar below the designer, extract the selection to a frame, event map, undo with Ctrl+Z and a step list (experimental)
- **Unsaved designer state** is seen by references, renames and checks
- **Tab order** in the designer bar: badges with jumps, gaps and duplicates, nested containers in colours, click-to-renumber, sort by reading order
- **Checks between form and code** and property rules for form files
- **Convert binary forms** to text forms
- **Show in designer** (Shift+F12): from a field or handler in the code to the component in the designer
- **Search components** in the designer fuzzily (`bspei` finds `btnSpeichern`), frames included; Enter reveals hidden tab pages, Ctrl+Enter adds to the selection
- **Usages in code** from the designer (Shift+Alt+F7): real accesses to the selected component per unit and method, classified as reads, writes, passes or event, plus a counter in the status field
- **Search properties** in the form, project or project group (`Font.Name = 'Tahoma'`, `Visible = False`, `Class = TDBGrid`), inherited values marked
- **Designer tools** in the designer bar: select similar components (class, parent, property value, handler), named selection sets per form with Ctrl+Shift+1…9, Alt+Arrow to the neighbouring control, Arrange menu (width from text, button bar, duplicate in row, insert and remove space, fit to content, near-aligned edges, default sizes per class, layers step by step, format painter, suggest anchors, all form texts as a table, label and field as a pair, arrange as a form grid, wrap in a container and dissolve it, unify fonts and colors, groups without a container), edit captions in place with F2 or a slow double click, gap handles for a row or column, shared resize handles, quick bar for a multiple selection, magnifier

### [Build, test, debug](docs/features/en/Build-test-debug.md)
- **Build gate** for hints and warnings, quick fixes for compiler messages, release build guard
- **Stop the running program before the build** instead of F2039 at the end of the build
- **Without a command-line compiler** (Starter, Community): Atlas detects it at startup, says so once, and project tasks using dcc or MSBuild give the reason instead of failing (`diagnostics.editionCheck`)
- **DUnitX tests** from the editor, including **only the tests affected** by a change; changed tests show their old result as **outdated**, methods show **which tests cover them** (“3 tests · passed”), failures sit at the **failing assert** with “expected 4, got 3” and can be **compared side by side** (JSON/XML indented; **approval files** with the helper unit `Atlas.Testing.Approval`, “Compare” right in the hover, on the test mark and on the welcome page); check rules find `[TestCase]` values that do not fit the method, test classes that are never registered or whose unit is in no test project, and asserts that hide the values or swap expected and actual; every test mark shows its **duration**, **slow tests** turn yellow, and so do tests with a **memory leak**; optionally the affected tests **run in the background on every save**
- **Slash commands for tests:** `/mock`, `/testcase`, `/dump` and `/assert` create mock classes, test cases, variable dumps and asserts that fit the type
- **Create a test case from the unit:** a code action on a method adds a draft with the call and placeholder checks to the test unit and creates the unit if needed
- **Set up leak check …** in the project context menu: shows what leak hunting still needs (FastMM4/FastMM5 found, first unit in uses, report on shutdown, defines and DLL of the Debug configuration) and sets up the chosen variant with a preview, for the Debug build only (`tests.leakSetup`)
- **Debugging:** values in the hover and inline, visualizers, evaluate window, smart step into
- **Exceptions:** history window, exception bar, just my code, access violations explained, module of the fault address (program, RTL/VCL, Windows, third-party DLL)
- **Threads:** what is waiting for what (wait point of every thread, deadlock patterns such as `WaitFor` against `Synchronize`), parallel stacks of all threads as a tree, other threads in the gutter (flag, experimental: freeze)

### [IDE comfort](docs/features/en/IDE-comfort.md)
- **Atlas welcome page** with projects, history, issues and news; "Continue" remembers the work state per issue ("Issues" tab) and resumes it with "Resume" on the branch of the issue
- **Issue tracker** (GitHub, YouTrack) and **version control** (Git, SVN) inside the IDE; "My issues" can show a fixed tracker project or all of them, with working copies per tracker project; "Start" and "Finish" follow the YouTrack state machine and offer only the transitions allowed from the current state; reopened issues get a mark with the reason and "Continue on <branch>"; "Finish" books the tracked time, sets required fields (`issues.endFields`) and writes in the order of the workflow rules (time, fields, comment, transition), with step display and resume after a rejection; the status panel shows the state of the current issue ("ATL-2052 · In Progress · 1:25") with the allowed transitions, "With comment …" and "Finish …" on click, and the command palette offers the same transitions (`issues.statusState`); if the issue is in no running sprint of the board, "Start" asks whether to add it (`issues.sprintOnStart`: ask, always, never); "Review…" checks out the branch of an issue under review, builds, runs the affected tests and verifies or hands it back, then returns to your own branch; with GitHub, "Finish" asks how to close the issue (completed, not planned, duplicate of #n or keep open) and closes it with that reason; for "not planned" and "duplicate" Atlas offers no time booking and forgets the saved work state of the issue
- **Command palette** (Ctrl+Shift+P), notification centre, server window
- **Editor context menu *Atlas*** with submenus (Navigation, Edit, Search and analyze, Findings with count, modules) and right-aligned shortcuts; shows only what fits (Debugging while debugging, Tests in test units, designer with a form), submenus can be turned off one by one (`commands.editorContextMenu.*`)
- **Atlas wizards in *File › New › Other***: *DUnitX test unit for unit…*, *Unit by architecture role…* and *Custom rule…* in the gallery category *Atlas* (`generate.galleryWizards`)
- **Project Manager submenu *Atlas***: *Check with Atlas* for units, folders and projects (multi-selection too, without opening the units), *Unit relations*, *Dependent units (n)* and *Run tests for this unit* (`commands.projectContextMenu`)
- **Robustness:** errors never reach the IDE, safe start, crash cases you can replay

### [Settings](docs/features/en/Settings.md)
- **Options page as a tree**, every feature with its own switch
- **Search settings** above the tree (Ctrl+F) and with `@` in the command palette, also by key, synonym or with a typo; Alt+Enter flips quick toggles directly
- **Module switches** for whole areas such as debugging, tests or the issue tracker; each module brings its own settings, which are absent while the module is not installed
- **F1 help** for Atlas: F1 on a finding (editor or "Atlas Findings"), on a setting or in an Atlas window opens the matching documentation page, online or from the local docs (`help.enabled`, `help.source`)
- **Export, import, profiles and reset**
- **Team-wide values** in `.atlas` and `atlas.json`
- **Language follows the IDE** (German or English), including issue tracker, welcome page and debugger; unchanged default texts such as comment snippets follow it too; messages, status lines, completion tags, code templates, server crash notes and the call diagram as well; also the notes on invalid project tasks, the answers of IDE builds for Claude Code and the questions of the pre-commit hook for affected tests; the messages and quick fixes of all rules too; and the server answers: messages, code actions, hovers, MCP answers, reports, the architecture map, the messages of `--check` and the MCP tool descriptions; without `language` in settings.json the server follows the language the IDE actually shows (its loaded resource files, then `Locales` in the registry, then Windows), and `atlas.log` names the detected language and its source

### [Claude Code and MCP](docs/features/en/Claude-Code.md)
- **33 MCP tools** to read, check, build, test, rename and fix Delphi code
- **5 prompts** as slash commands, e.g. unit review or commit preparation
- **Hook:** every Pascal file Claude changes is checked right away

### Planned

Tracked as issues, order in [docs/Roadmap-Entwurf.md](docs/Roadmap-Entwurf.md) (German):

- 2.2: debugging, testing and leaks
- 2.3: AI assistants in the debugger, team, version control and CI
- 3.0: platform, including AtlasServer on Linux
- ongoing: further check rules (sub-issues of #1086)

## Installation

### IDE plugin for RAD Studio 13 and 12

1. Clone the repository and open `Atlas.groupproj` in RAD Studio.
2. Build `Atlas.Text`, `Atlas.Common`, `Atlas.Windows`, `AtlasServer` and `AtlasUpdate` for **Win64** (all for the same platform). Result: `Output\Win64\Debug\Bin\AtlasServer.exe` and `AtlasUpdate.exe`. Alternatively take `AtlasServer.exe` from a [release](https://github.com/xKnockOut/Atlas-IDE-Expert/releases); the server does not depend on the Delphi version.
3. Build the core package `Atlas.IDE.Base` and then the module packages `Atlas.IDE.<Module>` ([Structure](#structure)) with the Delphi version the plugin is meant to run in: **Win32** for the classic IDE, **Win64** for the 64-bit IDE. Result: `Output\Win32\Debug\Bpl\Atlas.IDE.Base370.bpl`, `Atlas.IDE.Debugger370.bpl` … (Delphi 13; Delphi 12: `…290.bpl`, 64-bit IDE: `Output\Win64\…`).
4. *Component › Install Packages › Add*: first `Atlas.IDE.Base`, then each module you want. A module needs the core package and nothing else; one that is missing or switched off (`debug.enabled` …) simply takes its features with it. If modules later disappear from the IDE’s “Known Packages”, Atlas reports it at startup with “Register again” and logs every change of the list ([details](docs/en/RAD-Studio.md)).
5. If the server is neither in `Output\…\Bin` nor next to the BPL: *Tools › Options › Third Party › Atlas*, field "Atlas server". The page shows whether the server is found.
6. Restart Delphi once: Atlas switches off the IDE's Help Insight and structural highlighting so nothing appears twice; the IDE reads these switches only at startup.

Details and troubleshooting: [docs/en/RAD-Studio.md](docs/en/RAD-Studio.md).

### Supported versions

- RAD Studio or Delphi **13 Florence** and **12 Athens** (12.0 or later). The plugin is built with exactly the version it runs in; the BPL carries the package version in its name (`370` for Delphi 13, `290` for Delphi 12) so both can sit side by side.
- Classic 32-bit IDE (Win32 BPL) and the 64-bit IDE from Delphi 12.3 (Win64 BPL).
- Windows 10 and 11.

So far it is built and checked only with RAD Studio 13 in the 32-bit IDE. What remains unchecked without a Delphi 12 installation and the 64-bit IDE is listed in [docs/en/RAD-Studio.md](docs/en/RAD-Studio.md#unverified).

### Claude Code and without an editor

- **Claude Code:** MCP tools and LSP as a plugin, see [Editors/ClaudeCode](Editors/ClaudeCode/README.en.md)
- **CI and command line:** `AtlasServer.exe --check`, see [Linter mode](docs/features/en/Command-line.md#linter-mode)
- **AtlasMonitor (Windows):** standalone window with an icon in the notification area for all running Atlas servers (IDE, MCP, command line): state dot (idle, working, not responding), details, stop a server, open its log, clear the index cache, start with Windows (#1901). Every server writes `%LOCALAPPDATA%\Atlas\Status\server-<pid>.json` every 5 s (`server.statusFile`). Settings in `%APPDATA%\Atlas\monitor.json`. Tab **Check** (#1900): every CLI command without the IDE (check with all options, metrics, todos, format check/write, fix with dry run, affected tests, architecture save/compare, hotspots, query, replay) on a target list (folders, .dproj, .groupproj, files; on/off, save/load). Each target runs as a hidden child process with progress, cancel and a job that ends all runs when the monitor closes; findings with filter, double click opens the editor, export as HTML or SARIF, "Copy command". Architecture and hotspot pages show in the **Report** tab (WebView2, otherwise the default browser).
- **Claude Code in the cloud (Linux):** the environment's setup script and the SessionStart hook install the server as `AtlasServer` (and `AtlasServer.exe`) in `/usr/local/bin`, prebuilt from the `cloud-linux` pre-release or built with Free Pascal; setup in [Editors/ClaudeCode](Editors/ClaudeCode/README.md#in-cloud-sitzungen-linux) ([Building on Linux](#building-on-linux))

More: [docs/en/Installation.md](docs/en/Installation.md).

## Documentation

- [Features](#features) in detail: one page per area under [docs/features/en](docs/features/en/)
- [Installation](docs/en/Installation.md) for RAD Studio, Claude Code and the command line
- [IDE plugin](docs/en/RAD-Studio.md): every feature in detail
- [Settings](docs/en/Settings.md) of the plugin
- [Configuration](docs/en/Configuration.md) of `atlas.json` (generated from the schema's `x-description-en` with `pwsh Tools/Update-ConfigDoc.ps1`)
- [Rules](docs/en/Rules.md) (generated from the rule catalog with `pwsh Tools/Update-RuleCatalog.ps1`)
- [MCP tools](docs/en/MCP.md) and the [Claude Code plugin](Editors/ClaudeCode/README.en.md)
- [Keywords](docs/en/Keywords.md): short help in the hover for keywords and directives
- [Benchmark](docs/en/Benchmark.md) of the performance targets and of the time until a project group is ready (`Tools/Benchmark/ready.mjs`, several runs per version, median and range)
- In German only (developer documents): [architecture](docs/Architektur.md), [changelog](CHANGELOG.md)

Every English page links its German original and vice versa.

## Structure

| Project | Content |
|---|---|
| `Packages/Atlas.Text` | Package, RTL only (free of Windows and VCL); the IDE plugin includes it as source |
| `Packages/Atlas.Common` | Package, free of Windows and VCL: parser, index, check rules, LSP and MCP logic |
| `Packages/Atlas.Windows` | Package for Windows-specific functions, free of VCL |
| `Packages/Atlas.Linux` | Linux counterparts of the server's Windows adapters, source only, for the Free Pascal build |
| `Application/AtlasServer` | The server (console program, speaks LSP over stdin/stdout, MCP with `--mcp`, linter with `--check`) |
| `Application/AtlasUpdate` | Installer and updater (#1519): `install`, `prepare`, `apply` |
| `Application/AtlasMonitor` | Window and notification area icon for all running Atlas servers (#1901), checks without the IDE (#1900), VCL |
| `Packages/Atlas.IDE.*` | The IDE plugin: a core package and module packages (below) |
| `Tests/Atlas.Tests` | DUnitX tests |

### Packages of the IDE plugin in the structure

All are design-time packages, built for Win32 (classic IDE) and Win64 (64-bit IDE from Delphi 12.3), with layers `Atlas.Core.*`, `Atlas.UI.*`, `Atlas.IDE.*`. Every module requires only `Atlas.IDE.Base`, never another module; Base knows no module. Each module brings its settings in the options dialog as its own section, module switch included: with only `Atlas.IDE.Base` installed, *Tools › Options › Atlas* shows only the settings of Base.

The list of packages with scope and switch is above under [Packages of the IDE plugin](#packages-of-the-ide-plugin).

`TAtlasMainThread` tracks queued main thread entries per module: when a module unregisters or its package is unloaded, its waiting entries are dropped instead of running later in unloaded code.

The main thread does not wait for the server while you type or click: slash commands, `///` scaffolds and "Switch to test unit" (also from the code lens) ask in the background. The diagnostics window does not count open modal dialogs as main thread load, and for a slow call it names the server request the main thread waited for. In the server, reading commands (switch to test unit, interface cost, metrics, TODOs, unit relations, editor marks, unit search and others) run concurrently, so hover, completion and diagnostics no longer queue behind a long command.

How a module registers, which contracts it uses and the rules for loading and unloading: [docs/Architektur.md](docs/Architektur.md) (German, section "Module und Verträge des Plugins"); each unit's package is listed in [docs/adr/0017-unit-zuordnung.md](docs/adr/0017-unit-zuordnung.md). Roles, naming and import rules: [docs/Architektur.md](docs/Architektur.md).

## Requirements

- Delphi 12 Athens or newer; currently built with RAD Studio 13 (Win32 and Win64). The IDE plugin must be built with the Delphi version it runs in; the server is independent of it.
- The test project is set up for Win64 only, because DUnitX is available only as a Win64 library in the Starter edition
- DUnitX (included in RAD Studio, IDE environment variable `$(DUnitX)`)
- PowerShell for the check scripts

## Building

Open `Atlas.groupproj` in the IDE and **Build All**. The order Text → Common → Windows → server → AtlasUpdate → AtlasMonitor → `Atlas.IDE.Base` → module packages → tests is set in the project group. Text, Common, Windows and the server must be built for the same platform, otherwise the server does not find the package units. The plugin packages are set up for Win32 (classic IDE) and Win64 (64-bit IDE from Delphi 12.3); which BPL is loaded depends on the IDE.

On the command line (RAD Studio command prompt or after `rsvars.bat`):

```bat
msbuild Atlas.groupproj /t:Build /p:Config=Debug /p:Platform=Win32
```

Output goes to `Output\<platform>\<config>\` (`Bin`, `Bpl`, `Dcp`, `Dcu`).

### Building on Linux

Only the server, only for Claude Code sessions in the cloud and other Linux machines without Delphi:

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

Without Delphi, the platform-independent tests (Atlas.Text, Atlas.Common, the plugin core) run on Linux with Free Pascal; every pull request does this as well (`linux-server.yml`):

```bash
Tools/Linux/Test-Fpc.sh      # test units from Tools/Linux/FpcTests.txt
```

The list only contains test units that pass completely under FPC. A new test unit without Windows or VCL dependencies belongs in it. Without a Delphi runner, `server.yml` reports the Delphi run as neutral; pull requests into `main` or `release/*` then fail.

Check scripts (also run as GitHub Actions):

```powershell
pwsh Tools/Check-PackageDependencies.ps1   # packages keep their dependencies, module boundaries from docs/adr/0017-unit-zuordnung.md
pwsh Tools/Test-PackageDependencies.ps1    # self-test of the module boundaries with deliberate violations
pwsh Tools/Check-ConsoleOutput.ps1         # no Write/Writeln to stdout
pwsh Tools/Check-TestCoverage.ps1          # every unit with logic has tests, every test unit runs
pwsh Tools/Check-WindowHosts.ps1           # dock windows and editor bars use their shared hosts
pwsh Tools/Check-ProjectFiles.ps1          # project files readable by MSBuild (source build for Delphi 12)
```

`Tests/DccFaelle` holds minimal cases for the compiler rules: each one states whether dcc reports it or compiles it. `pwsh Tools/Build-DccFaelle.ps1` builds them through `Tools/Build-Ide.ps1` (Win32 and Win64) and writes the dcc messages per case to `Output/DccFaelle-Ergebnis.txt`; the rules must not be stricter than that result (#1328).

`Tests/Compilermeldungen` has one case for every dcc warning, hint and error that Delphi 13 can be made to report (471 cases; codes without a case are listed in `ohne-fall.txt`). `pwsh Tools/Build-Compilermeldungen.ps1 -IdeProfile <profile> -AtlasServer <exe>` builds each case on its own through `Tools/Build-Ide.ps1` (Win32 and Win64) and runs `AtlasServer --check` over them; `python3 Tools/Compare-Compilermeldungen.py` writes `vergleich.md` with what Atlas finds, misses or reports with another code. The results of the first Delphi 13 run are checked in under `Tests/Compilermeldungen/Ergebnisse` (Atlas finds 211 of 332 codes; the missing rules are #1369–#1383). Without an IDE, `-Dcc` builds the cases with `dcc32`/`dcc64` of the Delphi version chosen with `-BdsVersion` (`23.0` = Delphi 12), `-ResultFile` keeps that run apart (#1383). Style rules name a compiler code in their message only where dcc reports it: `unused-assignment` names H2077 only for unmanaged types, `uses-cycle` F2047 only for pure interface cycles (F2092 for a unit naming itself), `xmldoc-mismatch` W1205 to W1208 only in the interface section and only for the forms dcc rejects; the comparison counts these rules only by the code in the message. A second Delphi 13 run with variant cases (#1383) showed that dcc does not report W1009 for fields and static methods, H2367 (even with `-JPHNE`), H2440, H2444, W1071, E2373, E2121 and E2287 for the same entry twice, and accepts lines of up to 1222 characters in the IDE; the rules no longer name these codes there, `exports-invalid` leaves variables alone and names E2276 for constants and types, `inline-not-expanded` no longer reports strict private members. With the Community Edition `-Dcc` stops with exit code 3, because `dcc32` there only prints that it does not compile on the command line.

## Branches

- `main`: next version. All new work lands here.
- `release/X.Y`: bug fixes for the released version, started from its tag. Each fix is merged forward into `main`.

## CI

- `server.yml`: build of the project group through the build script in the runner's environment variable `ATLAS_DELPHI_BUILD` (same parameters and JSON as `Tools/Build-Ide.ps1`; the group contains the Atlas plugin itself, so it cannot be built through `Tools/Build-Ide.ps1`) for Win64 and Win32, including the plugin BPLs `Atlas.IDE.*370.bpl` (core and modules) for the classic and the 64-bit IDE (Win32 and Win64, kept as artifacts), and DUnitX tests (Win64 only). Results as the check "DUnitX-Ergebnisse" in pull requests.
  - The job needs a self-hosted Windows runner (labels `self-hosted`, `windows`, `delphi`) on the developer's workstation. It runs in the signed-in user context, not as a service, in case the build script starts an IDE, and only while that machine is switched on. Without `ATLAS_DELPHI_BUILD` the job fails with a clear message.
  - It runs only with the repository variable `DELPHI_RUNNER=true`; otherwise the job "uebersprungen" says so in the run summary.
  - A new push to the same branch cancels the running build (`concurrency`).
- Building without a command line compiler (Community and Starter Edition): `pwsh Tools/Build-Ide.ps1 -Project <dproj|groupproj> -Platform Win32|Win64 -Mode build|make|check -Json` builds in its own RAD Studio instance with the registry profile `AtlasBuild` and a fixed copy of the Atlas plugin (set up once with `-Setup <Bpl folder>`); your own IDE is never touched. In a running RAD Studio with Atlas, MCP clients build through the tool `build_project`.
- `release.yml`: release for the tag `v<version>`. Without the Delphi runner the release package is missing; `pwsh Tools/Publish-ReleasePackage.ps1 -Version <version>` then attaches a locally built one and enters it in the update installer's version files (#1849, [docs/Release.md](docs/Release.md), German).
- `package-dependencies.yml`: package dependencies, the stdout rule, Delphi 12 compatibility, rule catalog, configuration docs, no Embarcadero sources in `Tests/`, and Atlas windows and editor bars only through their shared hosts.

## Command line

The server also runs without an editor: linter for pre-commit hooks and CI (`--check`, text, JSON or SARIF), formatter (`--format-check`, `--format-write`), architecture report, code queries, hotspots and affected tests. All parameters: [docs/features/en/Command-line.md](docs/features/en/Command-line.md).

## Important: stdout belongs to the protocol

The server speaks LSP over stdin/stdout. Any additional output to stdout (`Writeln`, unhandled exceptions) breaks the communication with the editor. All diagnostic messages go through `ILogger` (`Atlas.Common.Logging`) to `OutputDebugString`, the log file, `window/logMessage` and, for errors, stderr. After starting, the server redirects the stdout handle and `Output` to stderr, so libraries cannot disturb the protocol either.

## Licences

Atlas is licensed under the MIT licence (`LICENSE`); the end user licence agreement is `EULA.txt` (included in the release package); third-party components with their licence texts are listed in `THIRD-PARTY-NOTICES.md` (generated by `Tools/Update-ThirdPartyNotices.ps1`).

Cache and benchmark corpus stay local, VCL sources are never checked in. The index cache lives under `%LOCALAPPDATA%\Atlas`; the server reads RTL and VCL sources only from the local Delphi installation. `Tools/Check-NoEmbarcaderoSources.ps1` checks in CI that `Tests/` contains no file with an Embarcadero copyright header.
