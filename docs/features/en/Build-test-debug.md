# Build, test, debug

Back to the [README](../../../README.md)

## Build

### Gate for hints and warnings

- A summary after each build ("succeeded, but 2 warnings, 1 hint")
- Optionally a build with warnings or hints counts as failed
- Known legacy messages go into the baseline

Settings: `build.zeroHints`, `build.warningsAsErrors`

### Without a command-line compiler (Starter, Community)

- At startup Atlas looks for `dcc32.exe` or `dcc64.exe` in the installation folder (#1822); RAD Studio Starter and, depending on the version, Community have no command-line compiler
- the result is in the startup line of `atlas.log` ("command-line compiler: …")
- if it is missing, a notice with a *Settings* button appears once; the "Set up project for Atlas" card on the welcome page says so too
- builds for AI assistants (`build_project`) run through the IDE's compiler anyway and keep working
- project tasks that call `dcc32`, `dcc64`, another `dcc…` or `msbuild` do not start but give the reason; tasks that call the compiler through a script are not recognized

Setting: `diagnostics.editionCheck` (off = behaves as before)

### Disable a compiler warning in place

- A code action on a warning or hint of the last build:
  - wraps the line, the routine or the unit in `{$WARN SYMBOL_DEPRECATED OFF}` … `ON` (or `{$HINTS OFF}`), with an optional reason comment,
  - or turns the warning off in the project options.

Settings: `refactoring.disableWarning`

### Quick fixes for compiler messages

| Message | Quick fix |
|---|---|
| H2443 | adds the missing unit |
| E2003 | offers the units declaring the identifier |
| H2077 | removes a dead assignment (keeping a call) |
| W1035 | inserts `Result := Default(T);` |
| W1057/W1058 | add an explicit string cast |

- "Fix all in file" in one undo step

Settings: `refactoring.compilerFixes`

### Unit not found

- On F2613/F1026 Atlas searches:
  - the project folder
  - the project group
  - the other configurations
  - the libraries of other platforms
  - the index
- It offers:
  - to add the folder to the search path of this or all configurations (relative to the `.dproj`)
  - or to add the unit to the project
- Otherwise "only for Win32, Win64" or the searched places

Settings: `refactoring.missingUnit`

### Check before compiling

- The units changed since the last successful compile are checked for syntax errors and rule errors before each build
- Report or cancel the build

Settings: `build.gate`

### Release build guard

- Checks the project options before a release build (DEBUG symbol, debug information, …)

### Build once on opening

- As soon as the IDE is idle
- Optionally always with the same configuration and target platform (say Debug/Win64) whatever the project is set to
- Afterwards the project is back as it was

<a id="window-atlascompilerswitches"></a>
### Compiler switches at the cursor

- A dockable window lists the effective `R`, `Q`, `O`, `C`, `I`, `A`, `HINTS`, `WARNINGS`, disabled warnings and active symbols at the cursor position
- Each with its origin: project option, compiler default, include file or directive with line, e.g. `R−, set in line 10`
- Plus platform and configuration
- Values that differ from the .dproj are highlighted
- Double-click jumps to the directive or opens the project options
- Optionally the deviations stand in the status bar (`R− Q− HINTS OFF`)
- Command `Atlas.CompilerSwitches`

Settings: `build.compilerSwitches`, `build.showSwitchesInStatusBar`

### Build tool for Claude Code

- `build_project` builds open projects with the IDE's compiler, even in the Starter edition

## Test

### DUnitX tests

- Run from the editor
- A single test starts in the debugger (code lens on `[Test]` and `[TestFixture]`)

### Outdated test results (#1770)

- If a test was changed since its run, its code lens mark shows the old result grey and italic with “(outdated)”, e.g. “Run test · passed (outdated)”.
- Only whitespace or comments changed: not outdated. Undoing the change makes the result current again.
- The class mark is outdated as soon as one of its tests is; the count “3/4 passed” does not count outdated results as passed.
- Optionally changes in the units the test unit uses (and that belong to the test project) make the result outdated too.
- “Run outdated tests” (*Atlas* menu, command palette) runs exactly these tests.

Settings: `tests.stale`, `tests.stale.units`

### Tested by (#1778)

- Behind the header of every public method of a normal unit Atlas shows which DUnitX tests cover it, e.g. “3 tests · passed”.
- Colours as in the test code lens: green only once every one of these tests passed, yellow for a partial result (“3 tests · 1/3 passed”), red on a failure. Without a test it shows a grey “no test · create test”.
- Atlas looks for the tests in the background, backwards like “Run affected tests”: depth 1 finds only tests that call the method directly, a larger depth also goes through intermediate callers. If the search hits a limit, “(incomplete)” is added.
- A click runs exactly these tests; Ctrl+click lists them and an entry jumps to the test. Without a test the click opens or creates the test unit.
- Test units themselves get no marks; private and protected methods only on request. Hide per method or file via the “Hide” menu.

Settings: `codeLens.coveredBy`, `tests.coveredBy.depth`, `tests.coveredBy.private`

### Failure at the assert line (#1771)

- A failed test no longer sits at the method header but at the statement that failed: wavy line under the statement, followed by a grey “expected 4, got 3”.
- The line comes from the stack trace in the report (DUnitX with JclDebug or madExcept). If the test stops with an exception, it is the statement that raised it.
- Without lines in the stack trace Atlas looks for the one assert in the body whose expected value matches the report (`Assert.AreEqual(4, …)` for “Expected 4 but got 3”); if the body has only one assert, that one counts. If several match, the method header stays.
- The entry moves with inserted lines like any finding; the line in the messages view jumps to the statement.
- The short text appears like the error text at the end of the line (`editor.inlineDiagnostics`).

Settings: `tests.failureAtAssert`, `tests.failureInline`

### Compare expected and actual (#1779)

Available from the *Atlas* menu, the command palette and the context menu of a test unit (*Atlas › Tests*).

- Shows the failure of the test at the cursor (for a `[TestCase]` the first failed case), otherwise the last one reported, in two columns: expected on the left, actual on the right.
- Differing characters have a red or green background; lines that exist on one side only are marked as a whole, with a grey gap opposite.
- Line ends (`↵`, `␍↵`, `␍`), tabs (`→`) and trailing spaces (`·`) are visible, so a difference only there stands out.
- If both values are JSON or XML, Atlas indents them the same way first; the difference then sits in a line of its own.
- Values ending in “...” show “(truncated)” in the column header.
- “Copy actual” puts the actual value on the clipboard, e.g. to update the expected value in the test; Esc closes.
- Only for failures whose report names an expected and an actual value.

Settings: `tests.compare`, `tests.compare.format`

### Create a test case from the unit (#1226)

Available as a code action (Alt+Enter) on a method or routine, in its body or at its declaration; in the body also as `/test`.

- Atlas finds the test unit (pattern `testUnits.pattern`) and adds a draft test method to the test class; the tested unit goes into the uses clause.
- The draft prepares a variable with a placeholder per parameter (`0`, `''`, `False`, `nil`, `Default(T)`), calls the method on the test class's object (a field of the class type), on the class (class methods) or on a local object with `try … finally`, and checks the result and `var`/`out` parameters with placeholders that fit the type (`Assert.AreEqual`, with a tolerance for floating point, `Assert.IsTrue`, `Assert.IsNotNull`).
- An `Assert.Fail` at the end keeps the draft red until the expected values are right.
- Without a test unit, Atlas creates one like *Create DUnitX test unit* (fixture, setup/teardown, entries in `.dpr` and `.dproj`) and puts the draft in place of the empty test.
- Private, protected and implementation-only routines cannot be called from the test unit; for them you only get the test with `Assert.Fail`.

### Run affected tests (#1353)

Available from the *Atlas* menu and the command palette.

- Atlas compares the working copy with the base:
  - Git: merge base with `main`
  - SVN: `BASE`
  - uncommitted changes included
- It finds the changed routines, types and constants:
  - interface changes count for the symbol
  - uses and initialization for the whole unit
  - `.dfm` for the form class
  - `.inc` for the including units
  - comments not at all
- It follows their impact up to the depth and runs only the DUnitX tests they reach, each with its reason in the messages view.
- If more than 80 % of a fixture is affected, the whole fixture runs.
- Optionally a Git hook offers the tests before every commit.
- The same selection is available on the command line (`--affected-tests`) and for Claude Code (`get_affected_tests`).

Settings: `tests.affected`, `tests.affectedDepth`, `tests.affectedBeforeCommit`

### Launch profiles

- For parameters, working folder, environment and host application

## Debug: values and display

### Values in the hover while debugging

- See [Understanding](Understanding.md)

### Visualizers for common types

- One-line summaries instead of raw object dumps in the hover, Watches and Local Variables, e.g.:
  - `TObjectList<TKunde> · Count = 3 · [Meier, Schulz, Öztürk]`
  - `TFDQuery · dsEdit · 3/10 · Name = Meier, Ort = Berlin`
  - `clWebDodgerBlue · $1E90FF`
- The magnifier opens a viewer with a table, hex view, JSON tree, image or color swatch.
- Lists, dictionaries, datasets, bytes and streams, JSON, colors, TGUID, TPoint/TRect/TSize and bitmaps, each switchable
- Evaluation with a time limit and without side effects unless allowed (`debug.visualizers.evaluation`)

Settings: `debug.visualizers`

### Custom value display per type

- Put `// atlas-debug: '{Name}, {City} (No {No})'` or `[AtlasDebugDisplay('…')]` (bundled unit `Atlas.Debug.Attributes`) above a class
  - `TCustomer` then shows as `Miller, Berlin (No 4711)` in the hover, Watches and Local Variables
- Descendants inherit the rule.
- Third-party classes such as `TFDConnection` get one via `debugDisplayRules` in the `.atlas` project file.
- Placeholders:
  - with format (`{Amount:0.00}`)
  - `{?Field}` instead of losing the whole value when something cannot be evaluated
  - getters and calls only with `debug.displayRules.allowCalls`
- `// atlas-debug-children: Name, City` limits the children in the viewer ("All fields" stays available).
- The editor completes placeholders, rule `debug-display-placeholder` flags unknown ones.

Settings: `debug.displayRules`

### Inline values while debugging

- While the process is stopped, the values of local variables, parameters, loop variables and fields of `Self` stand dimmed at the end of the lines of the current routine (`Count = 3, Name = 'Meier'`)
- Values changed since the last step are highlighted
- `TDateTime` shows as a date
- Only plain names are evaluated, never calls or properties
- In small time slices so F8 stays fast

Settings: `debug.inlineValues`, `debug.inlineValuesPerLine`

### "No access to value" explained

- When the debugger only says "Inaccessible value" or "... inaccessible here due to optimization" for a variable, the hover and the inline values show `‹no access›`.
- The hover names the cause:
  - started in Release
  - `$D-`/`$L-`
  - `$O+` with a register
  - the variable's lifetime
  - `inline`
  - RTL/VCL without debug DCUs
- It names where the switch comes from.
- It offers fixes with a preview:
  - restart with Debug
  - `{$OPTIMIZATION OFF}`/`ON` around the routine
  - `{$O-}` at the start of the unit
  - use debug DCUs
- Without a match it lists what was checked.

Settings: `debug.explainUnavailable`

### Completion in debugger dialogs

- In Evaluate/Modify (Ctrl+F7), in a watch expression and in the condition and eval expression of a breakpoint, the Atlas popup offers names from the right scope:
  - locals, parameters, fields of `Self`
  - units and globals
  - members after `.`
- The scope is:
  - the execution point while the program is stopped
  - the breakpoint's line in the breakpoint dialog
  - otherwise the editor's cursor line
- Down in an empty field shows the last 20 expressions of the project.

Settings: `debug.completionInDialogs`

<a id="window-atlasevaluate"></a>
### Evaluate window

- A dockable window "Atlas: Evaluate" with several expressions that are evaluated again at every stop
- Values that changed since the last stop are highlighted.
- Objects, records and arrays expand into their fields (taken from the Atlas index, each evaluated on its own).
- The selected value shows as text with visible control characters, as the lines of a `TStrings`, as formatted JSON or as hex.
- While the values come in one by one the window stays responsive: the tree is only changed where something changed instead of being rebuilt every time; expanded rows, the selection and the scroll position stay put. Tree and value view fill the window at any size, the key help wraps to the width.
- "Allow side effects" (off) permits function calls and getters.

| Key / command | Action |
|---|---|
| "Modify …" | sets a new value |
| Ctrl+Enter | pins an expression for the project |
| Down in the empty field | shows the last 50 expressions |
| Ctrl+F7 | opens the window with the expression under the cursor |
| Shift+Ctrl+F7, or command "Evaluate/Modify (IDE dialog)" | opens the IDE dialog |

Settings: `debug.evaluateWindow`, `debug.evaluateWindow.replaceCtrlF7`

## Debug: stepping and breaking

### Smart step into

- Shortcut Ctrl+Alt+F7
- On `Save(Customer.Name, Format(…))` Atlas lists the calls of the paused line in execution order:
  - `1 TCustomer.GetName (Getter)`
  - `2 Format`
  - `3 Save`
- It steps straight into the one you pick by digit or Enter, without walking through the others.
- Virtual calls follow the runtime type.
- Calls without source or debug DCUs are greyed out.
- A single call acts like F7.

Settings: `debug.stepIntoTarget`

### Break on next event

Run menu and command palette. "Which code runs when I click here?"

- Pick event kinds (mouse, keyboard, timer, window, database, actions, other) and optionally one form or only the visible ones.
- Atlas sets temporary breakpoints on all matching handlers from the forms and from assignments in code (`Btn.OnClick := …`).
- It stops in the next one that runs, removes them all and shows `Stopped: btnOk.OnClick → TfrmCustomer.btnSaveClick` (shared handlers resolved via `Sender.Name`).
- "Keep watching" arms them again.
- Frequent events (`OnPaint`, `OnMouseMove`, `OnUpdate`, timers under 100 ms) only when chosen explicitly (`debug.breakOnNextEvent.excluded`).

Settings: `debug.breakOnNextEvent`

<a id="window-atlasstepfilter"></a>
### Step filters

- F7 no longer stops in:
  - one-statement property getters and setters
  - trivial routines (one assignment to Result or a field)
  - class operators or constructors that only call `inherited`
- It skips every routine that matches a pattern such as `*.Log*` or `TBaseForm.*`.
- Right-click a method and choose “Skip when stepping into” to add it.
- A breakpoint inside a skipped routine still stops; Shift+F7 steps in once anyway.
- The dockable window “Step filters” shows how many routines of the project each kind and pattern matches.

Settings: `debug.stepFilters`

## Debug: exceptions

<a id="window-atlasdebugexceptions"></a>
### Exception history

- Dockable window “Atlas: Exceptions” with every exception of the debug session:
  - time, class, message from the IDE's dialog
  - count of equal exceptions at the same place
  - location, thread
- Filter by class and text
- Enter jumps to the line
- Ctrl+C copies class, message and call stack
- “Ignore class from now on” continues silently on that class

Settings: `debug.exceptionHistory`

### Just my code

- After an exception in library code Atlas jumps to the first line of your own code in the call stack and marks it.
- F7 into code without source runs on until it returns.
- The exception history shows library frames faded and collapsed to “… 7 library frames”.
- Own code = project folders plus `debug.ownCodeFolders`

Settings: `debug.justMyCode`

### Exception bar instead of the dialog

- When the debugger stops on an exception, a bar at the top of the editor shows:
  - class, message, thread
  - how often it came at this place
  - the first line of your own code (“3 levels hidden”)
- Buttons:
  - Break (F8/Esc)
  - Continue (F9)
  - Ignore class
  - Ignore only here (class + unit + line per project, continued silently next time)
  - Copy message
- In Delphi 12 and 13 Atlas closes the IDE's dialog for it, otherwise the dialog stays and the bar follows.

Settings: `debug.exceptionBanner` (off until the study for #783 is positive)

### Access violation explained

- When the debugger stops on an access violation in your own code, Atlas splits the statements of the line into access chains (`Order.Customer.Address.City`, `List[I].Name`, `Self.FData^`) and evaluates them from the left.
- The exception bar:
  - says "`Order.Customer` is nil" with the field at the read address ("access to field `FAddress` (offset $1C)", confirmed by the debugger or estimated)
  - lists the checked links with ✓/✗
  - offers "Where is `Customer` assigned?", "Evaluate expression" and "Copy explanation"
- It also recognises:
  - freed objects (memory manager fill patterns such as `$80808080` and `$FEEEFEEE`)
  - an index outside a dynamic array
- Without a clear cause it says "Cause not clear".
- The culprit is underlined in the editor until you continue.
- Getters and function calls are not evaluated unless `debug.explainAccessViolation.allowCalls` is on.
- Without the exception bar the result goes to the messages.

Settings: `debug.explainAccessViolation`
