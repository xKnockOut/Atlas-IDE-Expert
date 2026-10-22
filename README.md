# Atlas IDE Expert

[![Donate with PayPal](https://img.shields.io/badge/Donate-PayPal-00457C?logo=paypal)](https://www.paypal.com/paypalme/xKnockOut288)

*Deutsche Fassung: [README_DE.md](README_DE.md). The detailed documentation in `docs/` is in German.*

Atlas is an expert for RAD Studio (Delphi/Object Pascal). It replaces the built-in Code Insight with its own windows and adds code analysis with 170 check rules, refactorings, navigation, form support, testing and debugging aids and its own welcome page to the IDE. The data comes from the **Atlas server**, a language server (LSP) of its own that indexes the project and also runs without the IDE as a linter or as an MCP server for Claude Code.
Atlas is an expert for RAD Studio (Delphi/Object Pascal). It replaces the built-in Code Insight with its own windows and adds code analysis with 174 check rules, refactorings, navigation, form support, testing and debugging aids and its own welcome page to the IDE. The data comes from the **Atlas server**, a language server (LSP) of its own that indexes the project and also runs without the IDE as a linter or as an MCP server for Claude Code.
Atlas is an expert for RAD Studio (Delphi/Object Pascal). It replaces the built-in Code Insight with its own windows and adds code analysis with 173 check rules, refactorings, navigation, form support, testing and debugging aids and its own welcome page to the IDE. The data comes from the **Atlas server**, a language server (LSP) of its own that indexes the project and also runs without the IDE as a linter or as an MCP server for Claude Code.
Atlas is an expert for RAD Studio (Delphi/Object Pascal). It replaces the built-in Code Insight with its own windows and adds code analysis with 175 check rules, refactorings, navigation, form support, testing and debugging aids and its own welcome page to the IDE. The data comes from the **Atlas server**, a language server (LSP) of its own that indexes the project and also runs without the IDE as a linter or as an MCP server for Claude Code.
Atlas is an expert for RAD Studio (Delphi/Object Pascal). It replaces the built-in Code Insight with its own windows and adds code analysis with 175 check rules, refactorings, navigation, form support, testing and debugging aids and its own welcome page to the IDE. The data comes from the **Atlas server**, a language server (LSP) of its own that indexes the project and also runs without the IDE as a linter or as an MCP server for Claude Code.

Features and roadmap are tracked in the [issues](https://github.com/xKnockOut/Atlas-IDE-Expert/issues).

## At a glance

| Area | What Atlas brings |
|---|---|
| [Writing](#writing) | Completion with detail panel, parameter hint, code and postfix templates, slash commands (`/uses`, `/extract`, …), generate menu, formatter |
| [Understanding](#understanding) | Hover with docs, values, inheritance and debugger values, type hints, code metrics, inactive `{$IFDEF}` branches |
| [Navigating](#navigating) | Breadcrumb bar, outline, peek definition, quick open, unit search, results window, bookmarks and notes |
| [Code analysis](#code-analysis) | 170 check rules (bugs, code smells, security), profiles, confidence, baseline, compiler check on save, CI linter with SARIF |
| [Code analysis](#code-analysis) | 174 check rules (bugs, code smells, security), profiles, confidence, baseline, compiler check on save, CI linter with SARIF |
| [Code analysis](#code-analysis) | 173 check rules (bugs, code smells, security), profiles, confidence, baseline, compiler check on save, CI linter with SARIF |
| [Code analysis](#code-analysis) | 175 check rules (bugs, code smells, security), profiles, confidence, baseline, compiler check on save, CI linter with SARIF |
| [Code analysis](#code-analysis) | 175 check rules (bugs, code smells, security), profiles, confidence, baseline, compiler check on save, CI linter with SARIF |
| [Refactorings and code actions](#refactorings-and-code-actions) | Rename including forms, change signature, extract method, implement interface, generate properties and many quick fixes (Alt+Enter) |
| [Forms](#forms) | Sync with the designer, form components in completion, checks between form and code |
| [Build, test, debug](#build-test-debug) | Release build guard, DUnitX tests from the editor, launch profiles, values in the hover while debugging |
| [IDE comfort](#ide-comfort) | Welcome page, command palette, notifications, Git/SVN change marks, safe start |
| [Settings](#settings) | Every feature can be switched off, options page as a tree, team-wide project file `.atlas` |
| [Claude Code](#claude-code-and-mcp) | 19 MCP tools to read, check, build, test and rename |

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

## Features

Everything below is implemented in `main`. Features marked *(experimental)* are off by default and can be switched on under *Tools › Options › Third Party › Atlas* once the master switch "Experimentell" is on. The full description of each feature is in [docs/RAD-Studio.md](docs/RAD-Studio.md) and the [CHANGELOG](CHANGELOG.md) (German).

### Writing

- **Code completion** in its own popup: detail panel with coloured declaration and docs, filter chips, fuzzy matching, learning order, favourites (Ctrl+D), typo suggestions ("did you mean"), in-editor preview, `+ Unit` hint for units not yet in `uses`
- **Context-aware:** enum values first, set elements with checkboxes, `case` with all or the missing values, only types after `:`, type arguments matching constraints, full `inherited` call, field and parameter names in `FieldByName('`, the form's components, `Sender` with the matching typecast, same names from different units, helper methods, `uses` list with groups
- **Unknown names:** create a local variable, inline variable, field or method right from the list; name suggestions from the type
- **Parameter hint** with all overloads, the active parameter and overload choice by argument types
- **Templates:** code templates (`tryf`, `forin`, `prop`, …), your own `*.atlas-snippet` files, the IDE's Live Templates, class-aware templates (`prop`, `create`, `free`) and postfix templates (`List.forin`, `Obj.notnil`, `Obj.free`)
- **Slash commands** run after Enter, such as `/uses Unit`, `/extract`, `/inline`, `/fix`, `/explain`, `/case`, `/helper`, `/test`, `/component`, `/unit`, `/sortuses`, `/cleanuses`
- **Generate menu** (Alt+Ins): constructor, properties, overridden methods, interface methods, surround, templates
- **Guard the free:** after `X := TFoo.Create;` an offer for `try … finally X.Free; end;`
- **Editing helpers**: highlight text matching the selection (#709), toggle block comment (#703, Shift+Alt+A), new line above or below (#700, Shift+Enter, Ctrl+Alt+Enter), surround the selection while typing (#672), remove the surrounding construct (#657, Ctrl+Shift+Del) with preview, Atlas column in the gutter (#768)
- **Conditional compilation**: outline, hover, go to and checks see only the active `{$IFDEF}` branches of the project, the outline shows the branch condition (#845)
- **Variant records**: fields such as `TRect.Left` or `TMessage.WParam` appear in completion, hover, go to and the outline, tagged with their branch (#846)
- **Documentation comments:** `///` creates the XMLDoc skeleton with placeholders
- **Complete statement** (Ctrl+Shift+Enter), **continue patterns** as ghost text, **continue comments** on Enter
- **Formatting** by its own rules (Ctrl+Shift+Alt+L), since RAD Studio 13 no longer has a formatter
- **Move and duplicate lines** (Alt+↑/↓, Shift+Alt+↑/↓), **multiple cursors** *(experimental)*, **linked editing of identifiers** *(experimental)*, **paste with uses completion** *(experimental)*

### Understanding

- **Hover tooltip** in Atlas style instead of Help Insight: declaration, XMLDoc in collapsible sections, clickable types, inheritance chain, values of constants, sets and resource strings, published members of components as a table, symbols in `{$IFDEF}` with their origin, actions (go to, usages, copy declaration, help)
- **Values while debugging:** when the process is paused, the tooltip shows the value of the expression under the mouse, evaluated by the IDE's debugger without side effects
- **Type hints** after `var X := …` without a type
- **Code metrics** as a lens after each method header (length, depth, cyclomatic and cognitive complexity, parameters), after each class (members), the unit name (lines) and the first `uses` (units)
- **Recursion marks** in the gutter, **inactive `{$IFDEF}` branches** dimmed with the reason in the tooltip, **unused uses** dimmed
- **Bracket and block pairs** coloured by depth, with matching block lines

### Navigating

- **Go to** definition (Ctrl+click), implementation and type definition; switch between declaration and implementation (Ctrl+Shift+↑/↓); **jump to the counterpart** (begin ⇄ end, try → finally → end, `{$IFDEF}` → `{$ENDIF}`)
- **Breadcrumb bar** above the editor with jump menus for unit, class, method and their children
- **Outline** as a dockable window with filter
- **Peek definition** (Alt+F12) below the line without switching files
- **Quick open** of files and symbols (Ctrl+P) across project, project group and search path; project-wide **symbol search**
- **Unit search** (Ctrl+F12) in its own window with preview, groups, filters and "add to uses"
- **Results window** "Atlas Results" for references (including forms), implementations, callers, calls and inheritance
- **Navigation history** across files
- **Named bookmarks** (Ctrl+Alt+K) and personal **notes** on code lines that never go into the source
- **Overview ruler** at the scroll bar with errors, matches and changes; **minimap** *(experimental)*; **sticky scroll** of the enclosing class and routine *(experimental)*
- **TODO overview** of the project from `// TODO`, `// FIXME` and the IDE's to-do format

### Code analysis

The server checks every unit while you type. Findings appear as squiggles, in the tooltip, shortened at the end of the line and project-wide in the dockable window **"Atlas-Prüfung"** (Ctrl+Alt+P); marks move along while typing.

- **Window "Atlas-Prüfung":** live findings of the file, project or project group, filters per kind, category and text, grouping by file, rule or category, sortable columns; Enter jumps, Alt+Enter fixes, context menu to suppress, configure, disable and explain the rule
- **Finding hover** with severity, rule and action line "Alt+Enter: fix", "Suppress for this line", "Configure rule…"
- **Page "Prüfregeln"** in the options: per rule group a master switch and a table with severity, exclusions and options of every rule, search and catalog text with examples

- **170 check rules** in four categories: 103 bugs, 57 code smells, 5 vulnerabilities, 5 security hotspots. Among them:
- **174 check rules** in four categories: 107 bugs, 57 code smells, 5 vulnerabilities, 5 security hotspots. Among them:
- **173 check rules** in four categories: 106 bugs, 57 code smells, 5 vulnerabilities, 5 security hotspots. Among them:
- **175 check rules** in four categories: 108 bugs, 57 code smells, 5 vulnerabilities, 5 security hotspots. Among them:
- **175 check rules** in four categories: 108 bugs, 57 code smells, 5 vulnerabilities, 5 security hotspots. Among them:
  - **Correctness:** `Result` not set, possibly uninitialized variables, unreachable code, unused variables, parameters and assignments, declared but not implemented methods, missing `override`, hidden virtual methods, overflows, float comparison, `raise` in `finally`, overlooked precedence of `not` (`not X in Set`), empty statement after `then`/`do`/`else`, loops one step too far (`0 to List.Count`), lists changed inside their own loop (`Delete` in a forward loop), objects used after `Free` (with a jump to the release), access before the nil check (`X.Name` before `if Assigned(X)`), fields freed outside the destructor without `nil`, fields created in the constructor that the destructor never frees, constructors and destructors without `inherited`, `Destroy` instead of `Free`, `FillChar`/`Move`/`GetMem` on records with strings or interfaces, `PChar` of temporary strings, `out` parameters read before they are set, `Find` on unsorted `TStringList`s, `DelimitedText` without `StrictDelimiter`, `Writeln` in programs without a console, `raise` in destructors, duplicate conditions and identical branches, `case` over enumerations with missing values, `DisableControls`/`BeginUpdate`/`Screen.Cursor` without `try`/`finally`, `StrToInt` on `Edit.Text` without a check, numbers from the database, registry or text cast to an enumeration without a range check (quick fix with `InRange`), `CreateProcess` with a read-only command line such as `PChar('notepad.exe')` (quick fix with a copy and `UniqueString`), access in `OnCreate` to a form that the `.dpr` creates only later, `on E: Exception` before a more specific handler that is never reached (quick fix moves it up), `raise E;` in a handler, which loses the original fault address (quick fix `raise;`), `Dict[Key]` without `ContainsKey` or `TryGetValue`, `Copy(S, 0, N)` and `Pos(…) > -1` (strings count from 1), events like `FOnChange(Self)` called without `Assigned` (quick fix adds the check), items of an owning `TObjectList` freed by hand (double free), `TStringList.Create;` without assignment (quick fix with variable and `try`/`finally`), `Self` passed as an interface while reference counting can already free the object (own reference counting in the constructor, `TInterfacedObject` after `inherited AfterConstruction`; quick fix moves the call before `inherited`), comparisons with `Null` whose result depends on `NullEqualityRule` (quick fix `Field.IsNull` or `VarIsNull`)
  - **Threads:** VCL access from threads, locks without `finally`, `FreeOnTerminate` traps, `Synchronize` in the destructor, `threadvar` with strings, `Application.ProcessMessages` in loops and event handlers, `TThread.Queue(nil, …)` in packages (quick fix to your own wrapper), `Sleep`/`WaitFor` in forms and event handlers that freeze the user interface, loops in `Execute` that never check `Terminated` (quick fix adds it), `CreateAnonymousThread` without `Start` (quick fix appends it), `TTask.Run` without `try … except` whose exceptions get lost (quick fix wraps the body)
  - **Database:** `while not Q.Eof` loops without `Q.Next` on every path (quick fix inserts it), `Edit`/`Append` without `Post` or `Cancel` (quick fix with `try … except Cancel`), transactions without `Rollback` on exceptions (FireDAC, IBX, dbExpress, ADO; quick fix with `try … except Rollback`), `UPDATE`/`DELETE` without `WHERE` in code, constants and the form file (option `allowTables` for tables emptied on purpose)
  - **Compiler ahead:** compiler errors while typing, without a build: method headers in the implementation that differ from the declaration (parameters, `const`/`var`, result type, calling convention; like E2037, the quick fix aligns either side), interface methods missing in a class (like E2291, also with a different header or a resolution clause for an interface not listed; quick fix declares and implements them), units in `uses` the compiler cannot find in the project, search and library paths (also as `.dcu`; like F2613, with similar names, quick fixes for the namespace prefix or a missing search path in the `.dproj`), missing files from `in '…'`, packages from `requires` and units that use themselves, attributes such as `[TestFixture]` that Delphi silently ignores because their unit is missing (like W1074; quick fix adds the unit), comparisons such as `Result = 0;` standing as a statement (like E2014; quick fix replaces `=` with `:=`), duplicate `case` labels, also through ranges and constants with the same value, and in variant records (like E2030, E2027; quick fix removes the later value), fields after methods or properties in the same section, which FPC accepts but Delphi does not (like E2169; quick fixes move the field up or put `var` in front), overloads without `overload` or with identical parameters (like E2254, E2267, E2252, E2301; quick fix appends `overload;` everywhere), identifiers declared twice in the same scope and units listed twice in `uses` (like E2004; quick fix removes the second one), conditional directives left open or without counterpart, missing symbols, unknown directives and `{$WARN}` identifiers, unbalanced `{$PUSHOPT}`/`{$POPOPT}` and invalid `{$ALIGN}` values (like E2095, E2280, E2279, E2173, W1030, W1078, W1079, E2573; quick fixes add `{$ENDIF}`, remove a surplus directive or correct the typo), `override` without a matching virtual method in the ancestor, on a static or `final` method and classes derived from a `sealed` one (like E2137, E2170, E2352, E2353; quick fix takes over the ancestor's signature in declaration and implementation, also for typos such as `Destory`), `Create` on a class with abstract methods that are not overridden or on a class declared `abstract` (like W1020, E2402; the message names the open methods, quick fix overrides them in a class of the file), getters, setters and fields after `read`/`write` that are missing, overloaded, have the wrong signature or a `var` parameter, mix class and instance members or use invalid field selectors (like E2168, E2234, E2282, E2271, E2355, E2356, E2174, E2459, E2461, E2562; quick fix creates a missing `FName`, `GetName` or `SetName`), assignments to a field of a record that a property, default property or function only returns as a copy, and to constants (like E2064; quick fix assigns through a local variable and writes it back), assignments to properties without `write` and reads of properties without `read` (like E2129, E2130; quick fixes call `Clear` instead of `Count := 0`, assign the field behind `read` or create the setter), calls with too many or too few arguments for a routine without overloads (like E2034, E2035; quick fix opens the parameter hint inside the parentheses). When the next build reports the same error on the same line, Atlas shows a single entry marked “Atlas + dcc” and “confirmed by the compiler (E2035)” (setting “Confirmed compiler messages”: merge or show both); the “Compiler” column of the “Atlas Findings” window names the code. Under Rules › Compiler ahead the master switch turns off every rule of the group and “Check level T rules” only those that need expression types; the compiler code in message, column and hover can be hidden
  - **Compiler ahead:** compiler errors while typing, without a build: method headers in the implementation that differ from the declaration (parameters, `const`/`var`, result type, calling convention; like E2037, the quick fix aligns either side), interface methods missing in a class (like E2291, also with a different header or a resolution clause for an interface not listed; quick fix declares and implements them), units in `uses` the compiler cannot find in the project, search and library paths (also as `.dcu`; like F2613, with similar names, quick fixes for the namespace prefix or a missing search path in the `.dproj`), missing files from `in '…'`, packages from `requires` and units that use themselves, attributes such as `[TestFixture]` that Delphi silently ignores because their unit is missing (like W1074; quick fix adds the unit), comparisons such as `Result = 0;` standing as a statement (like E2014; quick fix replaces `=` with `:=`), duplicate `case` labels, also through ranges and constants with the same value, and in variant records (like E2030, E2027; quick fix removes the later value), fields after methods or properties in the same section, which FPC accepts but Delphi does not (like E2169; quick fixes move the field up or put `var` in front), overloads without `overload` or with identical parameters (like E2254, E2267, E2252, E2301; quick fix appends `overload;` everywhere), identifiers declared twice in the same scope and units listed twice in `uses` (like E2004; quick fix removes the second one), conditional directives left open or without counterpart, missing symbols, unknown directives and `{$WARN}` identifiers, unbalanced `{$PUSHOPT}`/`{$POPOPT}` and invalid `{$ALIGN}` values (like E2095, E2280, E2279, E2173, W1030, W1078, W1079, E2573; quick fixes add `{$ENDIF}`, remove a surplus directive or correct the typo), `override` without a matching virtual method in the ancestor, on a static or `final` method and classes derived from a `sealed` one (like E2137, E2170, E2352, E2353; quick fix takes over the ancestor's signature in declaration and implementation, also for typos such as `Destory`), `Create` on a class with abstract methods that are not overridden or on a class declared `abstract` (like W1020, E2402; the message names the open methods, quick fix overrides them in a class of the file), getters, setters and fields after `read`/`write` that are missing, overloaded, have the wrong signature or a `var` parameter, mix class and instance members or use invalid field selectors (like E2168, E2234, E2282, E2271, E2355, E2356, E2174, E2459, E2461, E2562; quick fix creates a missing `FName`, `GetName` or `SetName`), assignments to a field of a record that a property, default property or function only returns as a copy, and to constants (like E2064; quick fix assigns through a local variable and writes it back), assignments to properties without `write` and reads of properties without `read` (like E2129, E2130; quick fixes call `Clear` instead of `Count := 0`, assign the field behind `read` or create the setter), `Break` and `Continue` outside a loop, and `Break`, `Continue` and `Exit` that leave a `finally` block (like E2097, E2126; quick fix replaces `Break` with `Exit`), `raise;` without an argument outside an `except` block, for example in a local procedure called from the handler (like E2145), misused labels: set twice, never set, not declared, or a `goto` into or out of a `try` block (like E2073, E2074, E2093, E2127), loop variables that are assigned in the body, changed with `Inc`/`Dec`, passed as a `var` parameter or are not a simple local variable (like E2081, W1015, E1019; quick fixes convert to `while` or use `for var`), loop variables read after the loop ended normally (like W1037, quick fix converts to `while`), `to` loops that never run (`High … to Low`, constant bounds such as `10 to 1`; like H2135, quick fix `downto`)
  - **Compiler ahead:** compiler errors while typing, without a build: method headers in the implementation that differ from the declaration (parameters, `const`/`var`, result type, calling convention; like E2037, the quick fix aligns either side), interface methods missing in a class (like E2291, also with a different header or a resolution clause for an interface not listed; quick fix declares and implements them), units in `uses` the compiler cannot find in the project, search and library paths (also as `.dcu`; like F2613, with similar names, quick fixes for the namespace prefix or a missing search path in the `.dproj`), missing files from `in '…'`, packages from `requires` and units that use themselves, attributes such as `[TestFixture]` that Delphi silently ignores because their unit is missing (like W1074; quick fix adds the unit), comparisons such as `Result = 0;` standing as a statement (like E2014; quick fix replaces `=` with `:=`), duplicate `case` labels, also through ranges and constants with the same value, and in variant records (like E2030, E2027; quick fix removes the later value), fields after methods or properties in the same section, which FPC accepts but Delphi does not (like E2169; quick fixes move the field up or put `var` in front), overloads without `overload` or with identical parameters (like E2254, E2267, E2252, E2301; quick fix appends `overload;` everywhere), identifiers declared twice in the same scope and units listed twice in `uses` (like E2004; quick fix removes the second one), conditional directives left open or without counterpart, missing symbols, unknown directives and `{$WARN}` identifiers, unbalanced `{$PUSHOPT}`/`{$POPOPT}` and invalid `{$ALIGN}` values (like E2095, E2280, E2279, E2173, W1030, W1078, W1079, E2573; quick fixes add `{$ENDIF}`, remove a surplus directive or correct the typo), `override` without a matching virtual method in the ancestor, on a static or `final` method and classes derived from a `sealed` one (like E2137, E2170, E2352, E2353; quick fix takes over the ancestor's signature in declaration and implementation, also for typos such as `Destory`), `Create` on a class with abstract methods that are not overridden or on a class declared `abstract` (like W1020, E2402; the message names the open methods, quick fix overrides them in a class of the file), getters, setters and fields after `read`/`write` that are missing, overloaded, have the wrong signature or a `var` parameter, mix class and instance members or use invalid field selectors (like E2168, E2234, E2282, E2271, E2355, E2356, E2174, E2459, E2461, E2562; quick fix creates a missing `FName`, `GetName` or `SetName`), assignments to a field of a record that a property, default property or function only returns as a copy, and to constants (like E2064; quick fix assigns through a local variable and writes it back), assignments to properties without `write` and reads of properties without `read` (like E2129, E2130; quick fixes call `Clear` instead of `Count := 0`, assign the field behind `read` or create the setter), `inherited Name(…)` on a method that is abstract in the ancestor (like E2373; quick fix removes the call), type arguments that violate the constraint of their type parameter (`class`, `record`, `constructor`, interface or base class), `T.Create` without a `constructor` constraint and method calls on values of an unconstrained `T` (like E2511–E2515, E2568, E2571; quick fix adds the constraint), unknown type names in declarations, casts and pointer targets, and names that are not a type (like E2003, E2005, E2564; quick fix adds the declaring unit to uses), `Create` through a class reference (`class of TBase`) whose constructor is not virtual, so the base constructor always runs (like E2391; quick fix adds `virtual` and `override` in descendants)
  - **Compiler ahead:** compiler errors while typing, without a build: method headers in the implementation that differ from the declaration (parameters, `const`/`var`, result type, calling convention; like E2037, the quick fix aligns either side), interface methods missing in a class (like E2291, also with a different header or a resolution clause for an interface not listed; quick fix declares and implements them), units in `uses` the compiler cannot find in the project, search and library paths (also as `.dcu`; like F2613, with similar names, quick fixes for the namespace prefix or a missing search path in the `.dproj`), missing files from `in '…'`, packages from `requires` and units that use themselves, attributes such as `[TestFixture]` that Delphi silently ignores because their unit is missing (like W1074; quick fix adds the unit), comparisons such as `Result = 0;` standing as a statement (like E2014; quick fix replaces `=` with `:=`), duplicate `case` labels, also through ranges and constants with the same value, and in variant records (like E2030, E2027; quick fix removes the later value), fields after methods or properties in the same section, which FPC accepts but Delphi does not (like E2169; quick fixes move the field up or put `var` in front), overloads without `overload` or with identical parameters (like E2254, E2267, E2252, E2301; quick fix appends `overload;` everywhere), identifiers declared twice in the same scope and units listed twice in `uses` (like E2004; quick fix removes the second one), conditional directives left open or without counterpart, missing symbols, unknown directives and `{$WARN}` identifiers, unbalanced `{$PUSHOPT}`/`{$POPOPT}` and invalid `{$ALIGN}` values (like E2095, E2280, E2279, E2173, W1030, W1078, W1079, E2573; quick fixes add `{$ENDIF}`, remove a surplus directive or correct the typo), `override` without a matching virtual method in the ancestor, on a static or `final` method and classes derived from a `sealed` one (like E2137, E2170, E2352, E2353; quick fix takes over the ancestor's signature in declaration and implementation, also for typos such as `Destory`), `Create` on a class with abstract methods that are not overridden or on a class declared `abstract` (like W1020, E2402; the message names the open methods, quick fix overrides them in a class of the file), getters, setters and fields after `read`/`write` that are missing, overloaded, have the wrong signature or a `var` parameter, mix class and instance members or use invalid field selectors (like E2168, E2234, E2282, E2271, E2355, E2356, E2174, E2459, E2461, E2562; quick fix creates a missing `FName`, `GetName` or `SetName`), assignments to a field of a record that a property, default property or function only returns as a copy, and to constants (like E2064; quick fix assigns through a local variable and writes it back), assignments to properties without `write` and reads of properties without `read` (like E2129, E2130; quick fixes call `Clear` instead of `Count := 0`, assign the field behind `read` or create the setter), `New`, `Dispose` and `SetLength` without a length on dynamic arrays (like E2255, E2256, E2246, E2307, E2308; quick fixes `A := nil` and `SetLength(A, 1)`), local (nested) routines assigned or passed to a procedural type (like E2094, E2278; quick fix moves the routine to unit level), Integer and HRESULT interchanged between an interface method and its implementation (like X1008; quick fix aligns the result type), invalid arguments for var and out parameters: string elements, constants, properties, function results, Slice and expressions (like E2354, E2197, E2192, E2454, E2036; quick fix passes a local variable), conditions that are not Boolean in if, while and until (like E2012; quick fix adds <> 0, > 0, <> nil or Assigned), for-in over types without enumerator (like E2430, E2431)
  - **Compiler ahead:** compiler errors while typing, without a build: method headers in the implementation that differ from the declaration (parameters, `const`/`var`, result type, calling convention; like E2037, the quick fix aligns either side), interface methods missing in a class (like E2291, also with a different header or a resolution clause for an interface not listed; quick fix declares and implements them), units in `uses` the compiler cannot find in the project, search and library paths (also as `.dcu`; like F2613, with similar names, quick fixes for the namespace prefix or a missing search path in the `.dproj`), missing files from `in '…'`, packages from `requires` and units that use themselves, attributes such as `[TestFixture]` that Delphi silently ignores because their unit is missing (like W1074; quick fix adds the unit), comparisons such as `Result = 0;` standing as a statement (like E2014; quick fix replaces `=` with `:=`), duplicate `case` labels, also through ranges and constants with the same value, and in variant records (like E2030, E2027; quick fix removes the later value), fields after methods or properties in the same section, which FPC accepts but Delphi does not (like E2169; quick fixes move the field up or put `var` in front), overloads without `overload` or with identical parameters (like E2254, E2267, E2252, E2301; quick fix appends `overload;` everywhere), identifiers declared twice in the same scope and units listed twice in `uses` (like E2004; quick fix removes the second one), conditional directives left open or without counterpart, missing symbols, unknown directives and `{$WARN}` identifiers, unbalanced `{$PUSHOPT}`/`{$POPOPT}` and invalid `{$ALIGN}` values (like E2095, E2280, E2279, E2173, W1030, W1078, W1079, E2573; quick fixes add `{$ENDIF}`, remove a surplus directive or correct the typo), `override` without a matching virtual method in the ancestor, on a static or `final` method and classes derived from a `sealed` one (like E2137, E2170, E2352, E2353; quick fix takes over the ancestor's signature in declaration and implementation, also for typos such as `Destory`), `Create` on a class with abstract methods that are not overridden or on a class declared `abstract` (like W1020, E2402; the message names the open methods, quick fix overrides them in a class of the file), getters, setters and fields after `read`/`write` that are missing, overloaded, have the wrong signature or a `var` parameter, mix class and instance members or use invalid field selectors (like E2168, E2234, E2282, E2271, E2355, E2356, E2174, E2459, E2461, E2562; quick fix creates a missing `FName`, `GetName` or `SetName`), assignments to a field of a record that a property, default property or function only returns as a copy, and to constants (like E2064; quick fix assigns through a local variable and writes it back), assignments to properties without `write` and reads of properties without `read` (like E2129, E2130; quick fixes call `Clear` instead of `Count := 0`, assign the field behind `read` or create the setter), errors in constant expressions: division by zero, overflow, ranges like `array[5..1]`, values outside the type and too large hex literals (like E2098, E2099, E2011, W1012, E2102), invalid default values of parameters (several names with one default, a parameter without default after one with default, `var`/`out`, records and large sets; like E2237, E2238, E2239, E2268, E2146; quick fixes split the names or move the parameters with defaults to the end), signed and unsigned operands mixed in comparisons or arithmetic (Integer with Cardinal, anything with UInt64; like W1023, W1024, W1073; quick fix converts the unsigned operand to Int64), assignments with possible data loss, off by default (Int64 or NativeInt to Integer, configurable pairs such as Double>Single; like W1071, W1072, W1066; quick fixes convert explicitly or widen the target's type), typed constants that are modified by assignment or as var argument (like W1016, W1017; with {$J-} like E2064, E2197) and 0 instead of nil for pointer constants (like W1013); quick fixes turn the constant into an initialised variable or write nil, string limits exceeded: literals truncated to `string[N]`/ShortString (like W1014), literals over 255 characters before Delphi 12 (like E2056) and resourcestrings over 4096 characters (like E2381); quick fixes declare the target as string or split the literal
  - **Exceptions:** empty `except` blocks, catch-all without re-raise, exceptions created but not raised
  - **Components and forms:** missing `inherited`, `Notification`, wrong `default` values, fields without a form object and vice versa, data bindings and data sources in DFM files, message handlers (`message WM_SIZE`) without `inherited`, IDE notifiers without `RemoveNotifier` (quick fix keeps the index and removes it on unload), DUnitX tests without any assert
  - **Security:** SQL and command injection, path traversal, weak cryptography, disabled TLS verification, insecure HTTP and random, Trojan Source (bidi control, invisible and confusable characters)
  - **Architecture and style:** forbidden uses, role-based import rules, `with`, redundant parentheses and `begin … end`, file header, hard-coded strings, metric limits (also members per class, lines per unit, units in uses), public fields (optional, quick fix encapsulates them), global variables in the interface (optional), local names that shadow a field or property, `if` that only assigns `True` or `False`, `UpperCase(A) = UpperCase(B)` instead of `SameText`, numbers without a name, too long lines (optional; over 1023 characters always an error like F2069) and commented-out code (quick fix removes it)
- **Confidence** (high, medium, low) per finding caps the severity; **profiles** `standard`, `fast`, `strict`, `security`, `style` or your own in `atlas.json`
- **Suppress** with `// lsp-ignore: rule`, with reports of unused or misspelled suppressions
- **Baseline** for legacy projects: hide known findings, report only new ones
- **Compiler check after saving** and the messages of the "Build" tab
- **Check search paths and defines** of the active project (card on the welcome page)
- **Linter without the IDE:** `AtlasServer.exe --check` for pre-commit hooks and CI, as text, JSON or SARIF for GitHub code scanning, optionally only changed files or lines (see [Linter mode](#linter-mode))

Every rule with description and before/after example: [docs/Regeln.md](docs/Regeln.md).

### Refactorings and code actions

Alt+Enter opens the code actions; everything is also in the *Atlas* menu and the editor context menu.

- **Rename** project-wide with preview, including `.dfm`/`.fmx` and automatically named event handlers
- **Change signature** in a dialog: add, remove, move and rename parameters, with preview
- **Extract method**, **introduce variable**, **resolve `with`**, **complete `case`**
- **Inline variable and method** *(experimental)*, **move class to its own unit** *(experimental)*, **update uses after renaming a unit** *(experimental)*
- **Class actions:** implement interface, override methods, generate getter, setter and field, property from existing accessors, create method from a call, add forward declaration
- **Strings:** move a string literal to a `resourcestring`
- **uses:** add the missing unit, sort, remove unused ones
- **Quick fixes** for many check rules, also "fix all"
- **Undo Atlas changes** (Ctrl+Alt+Z): changes across several files as one step

### Forms

- Open forms are sent to the server as the designer has them: references, renames and checks also see unsaved components
- Renaming an event handler also updates its assignment in the designer
- The form's components in completion, `Sender` with the matching typecast
- Checks between form and code and **property rules** for form files with quick fix
- Convert binary forms to text forms

### Build, test, debug

- **Release build guard:** checks the project options before a release build (DEBUG symbol, debug information, …)
- **DUnitX tests** run from the editor, and a single test starts in the debugger (code lens on `[Test]` and `[TestFixture]`)
- **Launch profiles** for parameters, working folder, environment and host application
- **Values in the hover while debugging** (see [Understanding](#understanding))
- **Build tool for Claude Code:** `build_project` builds open projects with the IDE's compiler, even in the Starter edition

### IDE comfort

- **Welcome page** with sections: continue working, projects with quick actions, project history, unsaved, project setup, test results, my issues, new in Atlas, discover Atlas, help and feedback; search box and free layout
- **Command palette** (Ctrl+Shift+P) for all Atlas commands
- **Atlas status field** with index progress and quick toggles (Ctrl+Shift+Alt+A)
- **Notification centre** (Ctrl+Shift+Alt+N) collects messages from builds, checks and the server
- **Change marks** in the gutter against Git HEAD or SVN BASE
- **Find selection** with F3 or Shift+F3
- **Silent reload** of files changed outside the IDE
- **Robustness:** no error in Atlas reaches the IDE, hang watchdog with log, stack traces with unit and line for every caught error, check rules and editor features handle arbitrarily deeply nested expressions without recursion (a unit beyond the 100000-level net gets the hint `unit-too-deep` instead of silently losing its findings), a feature that keeps failing is switched off on its own (with a notification to switch it back on) while the others keep running, server crashes are logged with their cause (exit code, stderr) and a server that crashes the same way twice is not restarted in a loop, safe start after a crash (a slow IDE start is not a crash: instead of switching features off next time, Atlas names how long it held up the start and which of its parts took longest), its own data files (favorites, histories, bookmarks, notes …) are replaced in one step, and a damaged one is kept next to it as `.defekt` instead of being silently overwritten, bug report to attach, key conflicts with other extensions (GExperts, CnPack, MMX) are detected
- **Update check** only after consent
- **Accessibility:** lists and tooltips readable by UI Automation

### Settings

- *Tools › Options › Third Party › Atlas* as a tree: areas at the top, every feature with its own master switch that also disables its sub-options; next to it the pages *Snippets*, *Tastenkonflikte* (key conflicts) and *Server*
- Every visible feature can be switched off on its own; experimental features are marked
- Export, import, load profiles and reset settings
- Team-wide values in the project file `.atlas`, server and rule settings in `atlas.json` (*Atlas › Projekt-Einstellungen*), global values in `%APPDATA%\Atlas\settings.json`

All keys (German): [docs/Einstellungen.md](docs/Einstellungen.md) and [docs/Konfiguration.md](docs/Konfiguration.md).

### Claude Code and MCP

The server offers Claude Code 19 MCP tools: find symbols, read declarations and type and call hierarchies, component and form info, query diagnostics, metrics and TODOs, check planned code with `check_code` before writing it, explain findings, build through the IDE (`build_project`, `get_last_build`), run DUnitX tests, and rename or apply code actions (with preview). Plus the resource `delphi://conventions` with the project's conventions. Setup: [Editors/ClaudeCode](Editors/ClaudeCode/README.md), tools: [docs/MCP.md](docs/MCP.md).

### Planned

Not yet in `main`, tracked as issues:

- More than 100 further check rules (sub-issues of #909, #1086)
- Compiler messages as Atlas rules of their own, reported while typing instead of only when compiling (#1024)

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
- [IDE plugin](docs/RAD-Studio.md): every feature in detail
- [Settings](docs/Einstellungen.md) of the plugin
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

Atlas is licensed under the MIT licence (`LICENSE`); the end user licence agreement shown by the installer and GetIt is `EULA.txt`; third-party components with their licence texts are listed in `THIRD-PARTY-NOTICES.md` (generated by `Tools/Update-ThirdPartyNotices.ps1`).

Cache and benchmark corpus stay local, VCL sources are never checked in. The index cache lives under `%LOCALAPPDATA%\Atlas`; the server reads RTL and VCL sources only from the local Delphi installation. `Tools/Check-NoEmbarcaderoSources.ps1` checks in CI that `Tests/` contains no file with an Embarcadero copyright header.
