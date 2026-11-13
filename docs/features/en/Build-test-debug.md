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

### Stop the running program before the build

- If the exe is still running outside the debugger, Atlas asks before compiling “AtlasDemo.exe is still running. Stop it and build?” (Yes, No, Always) instead of letting the build fail with F2039 at the end
- Stops politely first, after 2 s forcibly; programs in the debugger stay untouched
- For a package, a notice names the programs that still have the BPL loaded (`build.stopRunningProgram`: ask, always, never)

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
- Colours as in the test code lens: green only once every one of these tests passed, yellow for a partial result (“3 tests · 1/3 passed”), red on a failure. If a test was changed since its run, the old result shows grey and italic with “(outdated)”. Without a test it shows a grey “no test · create test”.
- Atlas looks for the tests in the background, backwards like “Run affected tests”: depth 1 finds only tests that call the method directly, a larger depth also goes through intermediate callers. If the search hits a limit, “(incomplete)” is added.
- A click runs exactly these tests; Ctrl+click lists them and an entry jumps to the test. Without a test the click opens or creates the test unit.
- Test units themselves get no marks; private and protected methods only on request. Hide per method or file via the “Hide” menu.

Settings: `codeLens.coveredBy`, `tests.coveredBy.depth`, `tests.coveredBy.private`

### Untested methods (#1783)

- On the unit line of a normal unit with a test unit Atlas shows “7 of 12 methods tested”: how many of its methods at least one test calls (depth and private methods as for “tested by”). Below `tests.untested.warnPercent` percent (default 50) the mark is yellow, otherwise grey. Units without a test unit get no mark.
- A click shows a menu with the untested methods; an entry jumps to the method header, “Create test” opens or creates the test unit.
- It counts calls from tests and does not replace a coverage measurement; the menu says so.
- Command “Untested methods of the project” (Atlas menu and command palette, `Atlas.ListUntestedMethods`): for the project of the unit in the editor one line per unit in the message view, the unit with the most untested methods first, below one line per method that jumps there on double-click. Units without a test unit are listed with all their methods. The server limits itself to 60 s; a last line names what it did not reach.
- Hide per file via the “Hide” menu.

Settings: `codeLens.untested`, `tests.untested.warnPercent`

### Affected tests on save (#1775)

- After a unit is saved (also a form or include file) Atlas finds the tests that the changes of this file since the last commit reach and runs only those in the background. It builds as with “Build before the tests”.
- No window pops up: the Atlas status field shows “Tests: 3 affected · running …”, then “Tests: 3/3 passed” or red “Tests: 1 of 3 failed”. Clicking the line in the status window shows the output of the run in the message view.
- Code lens and Atlas problems follow the run as after “Run tests”.
- Saving during a run does not cancel it; afterwards at most one more run follows with all files saved until then.
- No run during a debug session, a build or another test run. More affected tests than `tests.onSave.max` or all tests needed: no run, only a hint in the status field.
- If a test unit belongs to several test projects, the background run takes the choice made once with “Run tests”.

Settings: `tests.onSave` (default off, quick toggle), `tests.onSave.max`

### Failure at the assert line (#1771)

- A failed test no longer sits at the method header but at the statement that failed: wavy line under the statement, followed by a grey “expected 4, got 3”.
- The line comes from the stack trace in the report (DUnitX with JclDebug or madExcept). If the test stops with an exception, it is the statement that raised it.
- Without lines in the stack trace Atlas looks for the one assert in the body whose expected value matches the report (`Assert.AreEqual(4, …)` for “Expected 4 but got 3”); if the body has only one assert, that one counts. If several match, the method header stays.
- The entry moves with inserted lines like any finding; the line in the messages view jumps to the statement.
- The short text appears like the error text at the end of the line (`editor.inlineDiagnostics`).

Settings: `tests.failureAtAssert`, `tests.failureInline`

### Compare expected and actual (#1779)

Available from the *Atlas* menu, the command palette and the context menu of a test unit (*Atlas › Tests*), and with the “Compare” button:

- in the hover over the failure (before “Explain”),
- on the test mark of a failed test (after “Debug”),
- on the “Test results” tile of the welcome page for the selected failure of the local run.

The button only appears when the failure has an expected and an actual value.

- Shows the failure of the test at the cursor (for a `[TestCase]` the first failed case), otherwise the last one reported, in two columns: expected on the left, actual on the right.
- Differing characters have a red or green background; lines that exist on one side only are marked as a whole, with a grey gap opposite.
- Line ends (`↵`, `␍↵`, `␍`), tabs (`→`) and trailing spaces (`·`) are visible, so a difference only there stands out.
- If both values are JSON or XML, Atlas indents them the same way first; the difference then sits in a line of its own.
- Values ending in “...” show “(truncated)” in the column header.
- “Copy actual” puts the actual value on the clipboard, e.g. to update the expected value in the test; Esc closes.
- Only for failures whose report names an expected and an actual value.

Settings: `tests.compare`, `tests.compare.format`

### Approval files for tests (#1881)

For exports, reports, generated code or JSON a test checks the result against a stored file instead of one assert per line (“approval”). The helper unit `Atlas.Testing.Approval` ships in `Setup\Vorlagen` (MIT licence, RTL and DUnitX only); copy it into the test project or add its folder to the search path. Example: [approval-tests.pas](../../Beispiele/approval-tests.pas).

- `TApproval.Verify(Result, 'TFixture.Method')` compares with `TFixture.Method.approved.txt`; a custom extension (`'.json'`) and a normalizer for dates or GUIDs are possible.
- Line ends (CRLF, LF, CR) are no difference; files are UTF-8.
- If the result differs, `….received.txt` is written next to it and the test fails with “Approval: difference from line 3, see …” (German by default); without an approved file with “new, please review”.
- Approving means renaming received to approved and committing the approved file; `.received.*` belongs in the ignore list.
- Folder: `tests.approvalFolder` of the nearest `atlas.json` above the test program (default `Tests\Erwartet`, relative to its folder); without `atlas.json` next to the nearest `.dproj`. `TApproval.Folder` sets it in code.
- Messages are German, English with `TApproval.English := True`.

In the IDE (Tests module, `tests.approvalFiles`):

- If a test fails with this message, its test mark shows “Difference · Compare”, without an approved file “New · Compare”. The same “Compare” button appears in the hover of the failure and on the *Test results* card.
- The comparison shows the approved file on the left and the received file on the right (lines matched as for expected and actual, #1779). *Accept as new expectation* replaces the approved file with the received file and deletes it; the next run is green. *Go to test* jumps to the method header.
- *Delete leftover .received files* (Atlas menu, command palette) looks in the approval folder of the test project that ran last (without a run, the active project), deletes all `*.received.*` there after asking and offers to add `*.received.*` to the nearest `.gitignore` if it has no line for them yet.
- `tests.approvalFiles` off: no special mark, no command; the helper unit keeps working, its failures show as ordinary failures.

Settings: `tests.approvalFolder` (atlas.json), `tests.approvalFiles` (plugin)

### Test duration and slow tests (#1772)

- After a run every mark of the test lens shows the duration: “Run test · passed · 12 ms”, from one second on in seconds with one decimal (“1.2 s”). The class mark shows the sum of its tests, a `[TestCase]` method the sum of its cases.
- If the slowest test of a mark takes longer than `tests.slowMs` (default 500 ms), “· slow” follows and the mark turns yellow, even if the test passed. Failed stays red, outdated grey.
- The *Test results* card on the welcome page lists the five slowest tests of the last run below the failures; double-click opens the test.
- *Show slowest tests* (Atlas menu, command palette): all tests of this session with their duration, slowest first (at most 50); double-click or Enter jumps to the test.
- `tests.showDuration` off: no duration, no colour, no list on the welcome page, no command.

Settings: `tests.showDuration`, `tests.slowMs`

<a id="window-atlastestsexplorer"></a>
### “Atlas Tests” window (#1776)

Open it with *View › Atlas › Atlas Tests*, the Atlas menu or the command palette. The window can be docked and comes back with the desktop.

- At the top the test project (a choice when the project group has several, the active one preselected), below it the tree of all tests: test unit › fixture › test › case. Atlas reads the test units of the test project like the test lens does, without the server; again after every run, after saving a test unit and with *Reload*.
- Every row has a dot with its state: green passed, red failed, yellow only partly run, grey not run, grey ring passed but outdated (#1770). After it the counter “passed/all” (outdated results do not count as passed) and the duration. Tests with `[Ignore]` are listed with “(ignored)” and do not count.
- *Run all* builds the test project and runs all tests. *Run selected* (Ctrl+R) runs exactly the selected rows (multiple selection with Ctrl and Shift, also whole fixtures or test units) with `--run` and their names. *Debug selected* (Ctrl+D) starts them in the debugger like “Debug test”; the one-time breakpoint at the start applies only to a single test.
- The filters *Failed*, *Not run*, *Outdated* and *Slow* (above `tests.slowMs`) apply at once, several together with “or”; the search box searches the full name (Unit.Fixture.Method.Case). The path to every match stays visible.
- Double-click or Enter goes to the test, for a case to its `[TestCase]`. Below, the selected test shows message, expected and actual value and the stack trace; lines naming a unit of the test project open on double-click.
- Results are kept for this session, per test project; changes to a test unit show up after saving.
- `tests.window` off: no menu entry, the window is not restored.

Setting: `tests.window`

### Test lists in the “Atlas Tests” window (#2167)

Open them with the tabs at the top of the “Atlas Tests” window; “+” creates a list.

- Next to “All” there is a tab per list. On a list's tab the tree shows only its tests; filters and search still apply. The header shows the rules, “12 of 340 tests” and the storage, next to it *Run list*.
- **Fixed lists** name tests, fixtures or whole test units: select them in the tree, context menu *Add to list ▸* (a fixed list or *New list …*); on the tab of a fixed list *Remove from “…”* removes the selection again.
- **Dynamic lists** consist of rules that must all apply: *category is / is not* (on the fixture or the test), *unit/fixture matches / does not match* a pattern with `*` and `?` (e.g. `*.Slow.*`), *state is / is not* failed, not run or outdated. New tests that match belong to the list without further steps.
- Right-click a tab: *Rename …*, *Edit rules …* (dynamic lists), *Duplicate*, *Delete*.
- Storage per list: **in the project** it is kept in `atlas.json` next to the .dproj under `testLists` and applies to the team (tab marked with ◆); **only for me** it is kept in `%LOCALAPPDATA%\Atlas\test-lists.json`. Atlas changes only this key in `atlas.json`; comments and order stay.
- Running: *Run list* on the tab, “Run test list: <name>” in the command palette, Ctrl+Alt+R (`tests.lists.runKey`) for the last used list. Category rules go to DUnitX as `--include`/`--exclude`, Atlas evaluates all other rules and names the tests with `--run`, combined into fixtures and namespaces where possible. If the list does not fit on one command line, the messages view says so.
- `tests.lists` off: no tabs, no context menu, no command; `testLists` in `atlas.json` is not read.

```json
"testLists": [
  {"name": "Before commit", "rules": [{"category": "Benchmark", "exclude": true}, {"unit": "*.Slow.*", "exclude": true}]},
  {"name": "Parser", "tests": ["Atlas.Common.Pascal.Tests"]}
]
```

Settings: `tests.lists`, `tests.lists.runKey`

### Test status in the status bar (#1777)
- The Atlas status bar shows “Tests 41/42” (passed/run, skipped tests do not count) with a traffic-light dot after the status, for the test project of the current file: in a test unit its test project, otherwise the active test project or the first one in the project group. During a run “Tests running …”, before the first run of the session “Tests –”. Without a test project there is no field.
- Traffic light: red with failures, yellow during a run and with outdated results (when the “Atlas Tests” window shows this test project), green when everything passed.
- Click: run the failed tests again; when all are green, all tests. Right-click: *Run all*, *Run failed again*, *Run affected*, *“Atlas Tests” window*, *Results on the welcome page*.
- Tooltip: test project, time and duration of the last run, passed, failed, skipped and outdated.
- Without the *Status* item in the bar the field appears as text in the IDE status line (without dot and right-click).
Setting: `editor.statusBar.tests`
### Log per test (#2168)
What a test writes while it runs (DUnitX `Log`/`Status`, `WriteLn` in the test class, `WriteLn` of the classes under test) appears in the “Atlas Tests” window on the *Log (n)* tab next to *Details*, for exactly the selected test.
- The DUnitX XML report holds no log lines. That is what the helper unit `Atlas.Testing.Log` in `Setup\Vorlagen` is for (MIT license, RTL and DUnitX only): add it to the test project and insert `runner.AddLogger(TAtlasTestLogger.Create);` after `TDUnitX.CreateRunner`. The logger only works in runs started by Atlas: before the start Atlas puts an empty side file next to the report; only then does the logger write to it and put marks around every test into the console output.
- Every line shows the time since the test started (`01.190`), then the text; warnings and errors with “Warning:” or “Error:”, console lines with “Console:” (without a time, at the place between the log messages where they came). Start and end of the test are listed too.
- Fixture setup and teardown belong to no test: their lines are shown on the fixture. Lines between two tests (from a thread that outlives its test, for example) go to the previous test, marked “(after the test ended)”. A test with `[TestCase]` shows the lines of all cases, each headed by the case name.
- References like `Kunden.pas:42`, `Kunden.pas(42)`, stack trace lines and `Unit.Class.Method` open on double-click or Enter when the unit belongs to the test project.
- Also available for passed tests; *Copy* or Ctrl+C puts the whole log on the clipboard.
- Without the logger the tab explains how to turn it on and shows the output of the whole run below.
- At most `tests.log.maxLines` lines per test (default 2000); the rest is cut off with a note. `tests.log` off: no tab, no side file.
Settings: `tests.log`, `tests.log.maxLines`
### Leaks per test (#1774)

- With a leak monitor in the test project (`DUnitX.MemoryLeakMonitor.FastMM4` or `FastMM5`), DUnitX reports a test that does not free memory as a failure (“40 bytes were leaked in the test method”). Atlas shows it as passed with a leak: the mark turns yellow, “Run test · passed · leak: 40 bytes”.
- *Atlas problems* gets a warning at the method header, “Test TKontoTests.Bucht does not free memory: 40 bytes (leak)”, source DUnitX.
- After the run the messages view says how many tests passed with a leak and how many bytes were not freed in total.
- A leak in setup or teardown counts for the test in which it happened.
- Leaks at program end that belong to no test (objects the test program only reports as not freed when it exits) get one line in the messages view: “Tests: Leaks at program end, not tied to a test: 3 blocks (TStringList x 2, TKonto x 1).” Atlas reads the FastMM report (`<program>_MemoryManager_EventLog.txt` next to the EXE, if the run wrote it), otherwise the program's output.
- If the test program has no leak monitor, the rule `dunitx-leak-monitor` reports a hint at the `DUnitX.TestFramework` entry of the .dpr. The quick fix adds `DUnitX.MemoryLeakMonitor.FastMM4` (it also works with the RTL memory manager, without `FastMM4.pas`), or `DUnitX.MemoryLeakMonitor.FastMM5` with FastMM5. “Set up leak check…” sets up the memory manager itself.
- `tests.leaks` off: the result stays as DUnitX reports it (failure, red), and the line about leaks at program end is left out.

Setting: `tests.leaks`

### Create a test case from the unit (#1226)

Available as a code action (Alt+Enter) on a method or routine, in its body or at its declaration; in the body also as `/test`.

- Atlas finds the test unit (pattern `testUnits.pattern`) and adds a draft test method to the test class; the tested unit goes into the uses clause.
- The draft prepares a variable with a placeholder per parameter (`0`, `''`, `False`, `nil`, `Default(T)`), calls the method on the test class's object (a field of the class type), on the class (class methods) or on a local object with `try … finally`, and checks the result and `var`/`out` parameters with placeholders that fit the type (`Assert.AreEqual`, with a tolerance for floating point, `Assert.IsTrue`, `Assert.IsNotNull`).
- An `Assert.Fail` at the end keeps the draft red until the expected values are right.
- Without a test unit, Atlas creates one like *Create DUnitX test unit* (fixture, setup/teardown, entries in `.dpr` and `.dproj`) and puts the draft in place of the empty test.
- Private, protected and implementation-only routines cannot be called from the test unit; for them you only get the test with `Assert.Fail`.

### Create a test from a debug stop (#1873)

Use: button *Create test …* in the exception bar, editor context menu › Atlas › Tests while debugging, or the command palette (*Create test from debug stop …*). Settings on the Debugging page: `tests.fromDebugStop` (default on), `tests.fromDebugStop.fields` (on), `tests.fromDebugStop.properties` (off), `tests.fromDebugStop.maxArray` (20).

- Atlas takes the frame of the stop: for an exception in the RTL or VCL the first frame in your own code, otherwise the topmost frame with source.
- If that frame is the current one, the debugger evaluates the parameters and the fields of the class (`Self.FUnit`) without side effects; getters only with `tests.fromDebugStop.properties`. In a deeper frame the parameters come from the call stack line.
- The debugger texts become Delphi literals: numbers (decimal comma becomes a point), strings with `''` and `#nn`, Boolean, enumeration values, sets and dynamic arrays up to `tests.fromDebugStop.maxArray` elements. Atlas does not guess objects, pointers, interfaces, records or anything unclear: the test gets a TODO there.
- The dialog lists the values to uncheck (unchecked ones stay placeholders; private fields and objects start unchecked), the kind (*Should work* or *Should raise EConvertError* when the program stopped at an exception), the expected result for functions and the name (`ParseWith12_5Kg`, `ParseWith12_5KgRaisesConvertError`).
- *Create test* adds the test to the test unit like *Create a test case from the unit* (creating the unit with its `.dpr`/`.dproj` entries if needed), with a comment line "From debug stop 2026-11-13 10:42, EConvertError"; an exception is checked with `Assert.WillRaise`. Without an expected result the test stays red with `Assert.Fail`. Everything is one undo step, then Atlas jumps to the test.
- Without the Debugger module the button and the command are missing.

### Slash commands for tests and debugging (#305)

Type the command on an empty line and press Enter.

- `/mock IKundenRepo` at unit level creates `TKundenRepoMock = class(TInterfacedObject, IKundenRepo)` with every method of the interface (inherited ones too): each method counts its calls (`LadenCalls`), functions return a settable field (`LadenResult`). Inside a routine of a unit that uses `Delphi.Mocks` you get a local `TMock<IKundenRepo>` variable with its `Create` instead.
- `/testcase 'a', 2, True` above a test method writes `[TestCase('Case1', 'a,2,True')]`, numbered consecutively; if a value contains a comma, `;` separates. The number of values must match the parameters of the method below.
- `/dump` inside a routine prints all parameters and local variables of simple types on one line (`OutputDebugString` or the routine from `slashCommands.logCall`).
- `/assert` below an assignment checks the assigned variable to fit its type (`Assigned`, not empty, not negative, `True`); in test units with `Assert.IsNotNull`, `Assert.AreNotEqual` and `Assert.IsTrue` from DUnitX.

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

### Why am I here?

- When stopped, the end of the header lines of the enclosing `if`, `while`, `repeat … until`, `for` and `case` shows the values of their conditions, dimmed like the inline values: `(1200 > 1000) and True → True`, `I = 3 of 7`, `Art = paRabatt → paRabatt`, in an `else` branch `(4 = 0) → False, else branch`
- Short-circuit as in the program: if `A = False` already decides `A and B`, B shows “not needed”
- Calls and getters are not evaluated on their own (`‹call›`); a click on the text of the line asks and then runs them
- Only in files with source, up to the routine, at most `debug.whyHere.depth` blocks (default 3); the values disappear with the next step

Settings: `debug.whyHere`, `debug.whyHere.depth`

### Predict upcoming conditions

- When stopped, the next `if`, `while` and `case` of the same routine (up to `debug.predictConditions.lines` lines ahead, default 20) show their predicted result, marked as a forecast: `⟨= False · FOnline⟩` (the deciding part), for `case` `⟨→ smManual⟩`
- The branch that will be skipped is drawn pale, for `case` all other branches; the text stays readable (`debug.predictConditions.dimSkipped`)
- Only what follows from the current state is predicted: no assignment to a variable involved in between (also `var`/`out` arguments, `Inc`/`Dec`), no call in between for fields and global variables, no `Exit`, `raise`, `goto`, `Break` or `Continue`
- The forecast never evaluates calls and getters in the condition; it only counts when the short-circuit decides without the call
- A click on a hint opens the menu “Turn off the forecast for this session”. Hints and dimming disappear with the next step

Settings: `debug.predictConditions`, `debug.predictConditions.dimSkipped`, `debug.predictConditions.lines`

### Change values

- The debug hover shows “Change …” below the value, for `True`/`False` also “Set to False” or “Set to True”. In the editor F2 (or “Atlas: Change value” in the context menu under Debugging) changes the identifier at the cursor; without a stopped program F2 goes to the IDE
- The input fits the type: numbers with range check (`Byte` 0..255, also `$FF`), floating point with comma or dot, characters and strings without quotes, enumerations as a list (with type prefix under `{$SCOPEDENUMS ON}`), sets with one check box per value, `TColor` with “Choose colour …” (also `#RRGGBB`). Invalid input appears in red below the field and “Change” is disabled; Enter applies, Esc cancels
- A property with a setter is changed only after confirmation (“Setter SetBetrag will be called”), by calling the setter. The dialog rejects read-only properties
- Changed values stay at the end of the line in the warning colour with the old value until the next step: `Betrag = 150 (was 125)`. “Undo (was 125)” in the hover or “Atlas: Reset changed value” sets the old value as long as the program has not continued

Settings: `debug.editValues`

### Expandable debug hover

- Objects, records and arrays show ▸ before the expression in the debug hover; a click expands them. The rows are indented as `Name = value` (fields, elements with index `[0]`); structured children and objects expand further. Each level is evaluated only when expanded; if the debugger answers late (Win64), the row says “evaluating …” until the value arrives and the IDE stays responsive
- Properties from the Atlas index show “evaluate”: getters may have side effects and run only after the click
- At most 100 children per level (`debug.hoverMaxChildren`), then “100 more …”. If an array is too long for one debugger answer, Atlas evaluates the visible elements one by one
- Values changed since the previous stop (same thread, same method) are highlighted with the old value dimmed behind: `Umsatz = 1250,00 ← 980,00`. This applies to expanded children too; the end of the debug session clears the memory
- With the mouse over the tooltip, ↑ and ↓ select a row, → expands, ← collapses. The actions below the value (Copy, with Shift `expression = value`; Pin; Change …; Watch opens “Evaluate” with the expression) apply to the selected row; a right click on a row offers them as a menu
- More than 12 rows scroll inside the tooltip

Settings: `debug.hoverExpand`, `debug.hoverMaxChildren`, `debug.hoverChanges`

### Pinned values

- The debug hover shows “Pin” below the value. From then on the expression appears at every stop as a framed field `Summe = 125 ✕` at the end of its line, after the inline values
- Values changed since the previous stop are shown in the warning colour
- Pinned expressions belong to the project and survive debug sessions; a click on ✕ unpins them for good
- Evaluation has no side effects: expressions with calls stay `?`. At most 100 per project

Setting: `debug.pinnedValues`

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

<a id="window-atlasbreakpoints"></a>
### Breakpoints window

The dockable window “Breakpoints” (Atlas menu, “Breakpoints (Atlas)”) shows the same breakpoints as the IDE’s list, plus:

- search across file name, method, condition and tag; several words must all match
- filter chips “active”, “with condition”, “never hit” (in this session) and “not effective”
- hit count of this debug session; “Reset hit counts” sets it to 0
- tags such as `Import` or `Bug 4711`, several per breakpoint, completed from the ones already used; they are personal and survive a restart
- grouping by tag, file or group, with collapsible groups
- enable, disable, tag or delete several breakpoints at once (undo with Ctrl+Z)
- columns “Set” (breakpoint sets) and “Rules” (hit condition, thread filter, dependent on another breakpoint), such as “from hit 3 · main thread”
- double-click goes to the location, Enter opens the IDE’s properties
- show and hide columns from the context menu; the window remembers width and order

Settings: `debug.breakpointsWindow`

### Breakpoints that will not be hit

Before every debug session starts, Atlas checks all active source breakpoints, open files as they are in the editor:

- line without code (comment, blank line, declaration), with the next code line of the same routine
- inactive branch of conditional compilation, with its condition (`{$IFDEF RELEASE}`)
- code without debug information (`{$D-}` in the unit or in the project options)
- unit of another project in the group, not of the one being started

If anything is found, the dialog “Breakpoints that will not be hit” lists it before the start; double-click jumps to the spot. “Move to next code line” moves the breakpoints together with condition, pass count and group and starts, “Start anyway” starts unchanged, “Cancel” does not start. The command “Check breakpoints” (Atlas menu, command palette) checks at any time. Without a server, or without an answer within 3 seconds, the IDE starts without a message.

Settings: `debug.checkBreakpoints`

### Breakpoints on methods by pattern

The command “Breakpoint on methods …” (Atlas menu, command palette, editor context menu under “Debug” and the context menu of the breakpoint list) sets breakpoints on all methods that match a name or pattern, without opening each one. The starting pattern comes from the word at the cursor: in a method header `TCustomer.Save`, on a type `TCustomer.*`, on a call `FCustomer.Save` the name `Save`; a single-line selection is taken as is. Without a word, the last pattern is shown.

- `TCustomer.Save`, `TCustomer.*` (all methods of the class), `*.Validate*` (all matching methods and routines), `Customer.Import.*` (whole unit), `IOrder.Check` (all classes implementing the interface member, also through method resolution clauses)
- with parameter types, only one overload: `TCustomer.Save(Integer)`
- “Overrides” adds the override methods of descendants, “Overloads” all overloads of a name (both on by default)

The preview lists the matches with file and line to deselect, methods without source greyed out. “Set” places the breakpoints on the first executable statement of each method, in the breakpoint group named after the pattern, optionally with a condition or “Do not break, log only”. With “Grow”, Atlas adds breakpoints for new matching methods at the next debug start and names them in the messages. “Method breakpoint groups …” enables, disables or removes the groups of the project together with their breakpoints. Atlas keeps the groups personally per project.

Settings: `debug.methodBreakpoints`

### Run to here by clicking

Editor margin while paused, context menu Atlas › Debug, command palette. Instead of placing the cursor and pressing F4, click next to the line.

- When the program is paused, a narrow column appears to the right of the line numbers; on executable lines it shows ▶ under the mouse pointer, with a tooltip.
- Clicking ▶ runs to that line (like F4); Ctrl+click does so without stopping at other breakpoints.
- Skipped breakpoints are back in their old state after the next stop, even if the program ends first. If the IDE crashes in between, Atlas restores them when the next debug session starts.
- Right-click in the margin: “Run to here”, “Run to here, skip breakpoints” (also Ctrl+F4, only while paused) and “One-time breakpoint”. The one-time breakpoint is in the group `Atlas.Einmalig` and disappears after its first stop; it can also be set while no program is running.
- Executable lines are those between `begin` and `end` of a body, without blank and comment lines and without lines that only contain `begin`, `end`, `try`, `finally`, `except` or `else`.

Settings: `debug.runToClick`

### Breakpoint only for one object

A breakpoint in `TKunde.Speichere` stops 500 times for 500 customers. While the program is paused, with the caret on the breakpoint line, the editor context menu offers under Debug:

- “Breakpoint only for this object”: Atlas evaluates `Pointer(Self)` and writes `Pointer(Self) = Pointer($0A3F1C20)` into the condition. The address is only valid in this session.
- “Breakpoint only if …”: choose one of the fields of `Self` with a simple value, such as `FNr = 4711`; the condition also holds in later sessions.

An existing condition is kept and combined with `and`. Both are available only in methods, not in plain routines or class methods. Before the next start, Atlas asks about address conditions from the last session: remove them, replace them with a field condition, or keep them.

Settings: `debug.instanceBreakpoints`
### Breakpoint sets

Atlas menu and command palette. When you work on several bugs, switch between named sets of breakpoints instead of deleting and setting them again.

- “Save breakpoints as set …” takes all source breakpoints with condition, pass count, group, actions and on/off; optionally coupled to the current branch.
- “Switch breakpoint set …” creates missing breakpoints of the set and disables the breakpoints of other sets (nothing is deleted). Breakpoints that belong to no set stay as they are.
- “Add breakpoint set …” adds the breakpoints of a set without disabling others; “Delete breakpoint set …” removes only the set.
- When loading, Atlas finds the line again by method and line text, even after lines were inserted above; breakpoints that can no longer be found are listed in the messages.
- Sets are stored per project in `.atlas/breakpoints/<Name>.json` and can be shared in the repository.
- With `debug.breakpointSetPerBranch`, a coupled set becomes active as soon as the working copy switches to its branch (Git and SVN).
- The IDE's breakpoint groups stay untouched: they switch breakpoints through actions but are tied to line numbers in the `.dsk`; a set remembers each breakpoint's group.

Settings: `debug.breakpointSetPerBranch`

## Debug: event log

<a id="window-atlasdebugeventlog"></a>
- Dockable window “Atlas: Event log” with debug output (`OutputDebugString`), breakpoint messages, modules, threads, logpoints and start and end of the session
- Columns time (relative to the start), kind, thread, text
- Filter by kind and text: words (each must occur) or `/regular expression/`; “Remember filter” keeps it per project in the list
- Colors by pattern, for example `[FEHLER]` red, `[WARN]` yellow
- Double-click or Enter jumps to `File.pas(123)`, `File.pas:123` or `Unit.Routine`
- Context menu: copy line, save as text file, clear

Settings: `debug.eventLog`, `debug.eventLogColors`

## Debug: logpoints

- Shift+F5 or “Atlas: Set logpoint” (Atlas menu, editor context menu) at the cursor line, or after a right-click in the gutter at that line
- Text with placeholders: `x={x}`, `total {Total:0.00}`; formats `d` (integer), `x` (hexadecimal), patterns with `0` or `#` (`FormatFloat`), otherwise as in `Format` (`.2f`); `{{` and `}}` are literal braces
- Condition (`{Total} > 1000`) and “only the first N hits”; the dialog shows errors in the text with their position
- An ordinary breakpoint on the line becomes a logpoint; “Remove” deletes it
- One line of kind logpoint in the event log with prefix and place, for example `[LOG] x=42 · Unit1.pas:12`; double-click jumps to the line
- Diamond in the gutter with text and condition in the tooltip
- “Disable/Enable/Delete all logpoints” only touch the breakpoint group `Atlas.Logpunkte`

Settings: `debug.logpoints`, `debug.logpointPrefix`

## Debug: no source

- When the debugger stops in a routine without source (the IDE shows the CPU window), a small window without focus appears at the top right: routine, module, address, unit and reason
- Reasons: debug DCUs off (Delphi library), unit compiled with `{$D-}`, only DCU/BPL available, source not in the search path, system code (Windows)
- Ways out depending on the reason: “Turn on debug DCUs and rebuild” (only in the Debug configuration, with confirmation; the session ends, then Atlas builds and starts), “Back to my code” (runs until it returns to own code), “Find source …” (the folder is remembered for the project, the unit opens), “Keep CPU window”
- “Do not show for this unit again” extends `debug.noSourcePage.ignoredUnits`
- With “Just my code” (`debug.justMyCode`) the window only appears for exceptions

Settings: `debug.noSourcePage`, `debug.noSourcePage.ignoredUnits`

## Debug: restart

- “Atlas: Restart” with Ctrl+Shift+F2, in the Atlas menu or in the command palette
- Steps: stop (only while the program runs), build (only when something changed since the last build), start, back to the place in the editor
- A small bar without focus at the top right shows the steps and their duration, for example “Stop 0.3 s ✓ · Build 2.1 s ✓ · Start …”
- If a step fails, the run stops and the bar names the reason
- With `debug.restart.reenableBreakpoints` Atlas turns breakpoints back on before the start that were on when the last session started

Settings: `debug.restart`, `debug.restart.reenableBreakpoints`

## Debug: leak and crash reports (#74)

- Copy a report, then Atlas > “Paste crash or leak report …” (also in the command palette): Atlas reads FastMM logs (FullDebugMode), the `ReportMemoryLeaksOnShutdown` message, reports from madExcept, EurekaLog 6/7 and JclDebug, and an exception message on its own (“Access violation at address … in module …”)
- The message view shows the call stack of the crashed thread and the other threads, or the stack of each leak group (same class, same stack); lines in the project jump to the source on double-click
- The editor shows diagnostics at the locations: a warning at the creation site of each leak group (“Leak: TStringList × 2 (40 bytes) is created here”), for a crash a warning at the crash site and hints at the other own lines of the stack; the source is the tool (FastMM, madExcept, …)
- Stack lines without debug information are resolved through the map file next to the EXE of the Debug configuration (linker option “Map file: Detailed”); if the map does not match the EXE (different entry point or code size), Atlas says so
- “Remove runtime report markers” removes the diagnostics again; a new report replaces the old one
- AI assistants get the same analysis as the MCP tools `analyze_report` and `resolve_address`

## Debug: reattach to process

- When the IDE attaches to a running process (Run › Attach to Process …), Atlas remembers path and name of the EXE for the project group
- “Reattach to <name>” in the Run menu, in the command palette and with Shift+Alt+P:
  - exactly one running process with the same path: attached at once, without a dialog
  - several, or only the same name in another place (another version): choice with PID, start time and command line
  - none: offer to wait for the start
- “Attach when started …” in the Run menu and in the command palette: choose the EXE (default: the last remembered one, otherwise the output file of the active project); Atlas polls the process list in the background and attaches as soon as it starts
- While waiting the status field shows “Waiting for … (Cancel)”; a click cancels, so does closing or switching the project group
- When an attached process ends, the status field offers to reattach on its next start
- Waiting misses the first milliseconds of the program (initialization); start it via the project's run parameters or a host application if you need them
- Local processes only; processes of other users and services need an IDE with administrator rights

Settings: `debug.reattach`, `debug.reattach.key`, `debug.reattach.waitIntervalMs`

## Debug: several programs together

- Launch groups are stored in the project file `.atlas` under `launchGroups`, paths from its folder:

```json
"launchGroups": [{"name": "Server + Client", "items": [
  {"project": "Server\\Server.dproj", "profile": "Local", "wait": "port", "value": 8080, "timeout": 20},
  {"project": "Client\\Client.dproj", "debug": false}]}]
```

- per project: launch profile (`profile`, otherwise the project's run options), with debugger (`debug`, default yes) and the wait condition before the next one (`wait`: `seconds` for `value` seconds, `port` until `localhost:value` accepts connections, `window` until the program shows a main window; at most `timeout` seconds, default 30)
- “Atlas: Launch groups …” in the Atlas menu and in the command palette shows the groups with their projects, sets the active group (per project group, personal) and starts it; “Edit in .atlas” opens the project file
- F9 without a running session starts the active group, otherwise the IDE starts as usual
- Atlas first builds the changed projects and then starts one after the other; a bar at the top right shows the run, for example “Server ✓ · Client starting …”
- If a build or start fails or a wait times out, the run halts and asks “Continue anyway” or “Stop all”
- Ctrl+F2 or “Atlas: Stop launch group” ends all programs of the group
- The status field shows “running”, “paused” or “ended” per program; a click makes the next process of the group the IDE's current one; when the debugger pauses, the message names the process
- Limits: programs started with the debugger use the parameters of the launch profile, but working folder and environment from the IDE's run options; only projects of the open project group

Settings: `debug.launchGroups`
### Breakpoints move with the code

Runs on its own; commands in the Atlas menu and the command palette. After `git pull`, a branch switch or a formatter, the IDE's breakpoints otherwise sit on wrong lines because they are tied to line numbers.

- Atlas remembers an anchor for each source breakpoint: routine, distance from the start of the routine, line text and neighbouring lines (the same search as for breakpoint sets).
- When a file changes from outside (reloaded, branch switch, different from when the IDE was last closed, or five or more lines at once as with a formatter or code action), Atlas moves each breakpoint to the matching line, with condition, pass count, group, actions and on/off. While you type, the IDE moves its breakpoints itself; Atlas only remembers the new anchor.
- A line in the messages names each move and “3 moved, 1 orphaned”.
- Breakpoints that cannot be matched stay where they are and go to the list “Orphaned breakpoints …” with a suggestion (same distance within the routine) and the buttons “Apply suggestion” and “Delete”. Nothing is deleted on its own.
- “Move breakpoints back to their old lines” undoes the last move.
- Anchors are stored in `%LOCALAPPDATA%\Atlas\breakpoint-anchors.json`.

Settings: `debug.breakpointAnchors`

### Breakpoint rules: dependent, hits, thread

Editor context menu (Atlas › Debug › “Breakpoint rules …”, also in the margin), Atlas menu, command palette; on the line of a breakpoint. A breakpoint in a busy routine otherwise stops a hundred times before you get to the place that matters.

- “Active only after”: the breakpoint is off at the start of every debug session and is switched on as soon as the chosen other breakpoint has stopped. “until the session ends” keeps it on, “only once” switches it off again after its stop until the triggering one stops again. After the session it is on again.
- “Stop”: on every hit, exactly on hit n, from hit n on or on every n-th hit; counted per session.
- “Thread”: all, name contains (from `TThread.NameThreadForDebugging`), one thread ID or the main thread only. A stop in another thread does not count as a hit.
- The IDE condition, hit condition and thread filter apply together. For hits and threads the debugger stops briefly, Atlas counts and continues right away; in hot loops this costs time.
- If the triggering breakpoint is missing at start, the dependent one stays on as usual and a line in the messages says so.
- Rules are stored in `%LOCALAPPDATA%\Atlas\breakpoint-rules.json` and move along when “Breakpoints move with the code” moves a breakpoint.

Settings: `debug.breakpointRules`

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
- After it the bar names the module of the fault address: "your program", "vcl290.bpl (RTL/VCL)", "ntdll.dll (Windows)" or "Foreign.dll (no debug information)". If the debugger did not stop in your own code, Atlas names only the module and the last place in your code from the call stack (`debug.moduleOfAddress`).
- Without the exception bar the result goes to the messages.

Settings: `debug.explainAccessViolation`, `debug.moduleOfAddress`

## Debug: threads

### What is waiting for what?

- When a program hangs, pause it (Run > Program Pause) and choose Atlas > "What is waiting for what?".
- Atlas reads the call stacks of all threads and lists per thread its id, name (`TThread.NameThreadForDebugging`), wait point and first line of your own code in the results window, for example "Thread 7 "Worker": waiting in TThread.Synchronize, at TWorker.Execute (Unit2.pas:30)".
- The wait point is the wait routine above the first line of your own code: `TThread.WaitFor`, `TThread.Synchronize`, `TMonitor.Enter`/`Wait`, critical section, event (`TEvent.WaitFor`), `Sleep` or a handle (`WaitForSingleObject`, `WaitForMultipleObjects`); the message loop counts as "waiting for messages".
- Above them are the detected patterns:
  - The main thread waits in `TThread.WaitFor` (for example in the destructor of a thread) while a thread waits in `Synchronize` for it: a deadlock, see rule `synchronize-in-destructor`.
  - A thread waits in `Synchronize` while the main thread hangs on a lock.
  - Several threads wait for a lock at the same place.
  - All threads are waiting and none is running.
- A double click switches to the thread and jumps to its first line of your own code.
- The debugger does not tell who holds a lock (`TMonitor`, critical section); Atlas names only the waiting threads.

Settings: `debug.deadlocks`

<a id="window-atlasdebugcallstack"></a>
### Atlas call stack

- Atlas > "Atlas call stack" opens a dockable window that shows the call stack of the current thread at every stop: for each frame the routine with its parameters and `Unit.pas:line`.
- Consecutive frames from the RTL, VCL and libraries are collapsed as "▸ 7 calls in VCL", with the first and last routine as a hint; a click, Enter or double click expands them.
- Parameters carry the names from the declaration (the server reads the routine at the frame's line). Atlas evaluates them and shows visualizer texts, strings in quotes and objects with class and `Name` field, for example `ACustomer = TCustomer 'Miller'`.
- The search (Ctrl+F) finds routine, unit or value, also inside collapsed groups ("▸ 7 calls in VCL · 1 matches"); matches are bold.
- A click or Enter on a frame jumps to the line.
- "Copy" (Ctrl+C) puts the stack on the clipboard as text or as a Markdown list (`` `Unit.pas:line` ``), optionally only your own code.
- "Compare with last stop" shows the stack of the last stop at the same place next to it and marks changed frames and values with "≠". Atlas remembers at most 20 places per debug session while the window is open.
- Limits: values of deeper frames are evaluated by address (objects and pointers); simple values are already in the IDE's frame text. Frames of anonymous methods and routines without a parameter list in the implementation section get no names.

Settings: `debug.callStackWindow` (off: the IDE call stack stays as it is), `debug.callStackWindow.evaluateParams`

<a id="window-atlasdebugparallelstacks"></a>
### Parallel stacks

- Atlas > "Parallel stacks" opens a dockable window that shows the call stacks of all threads as a tree at every stop, from the thread start (root) to the top frame.
- Equal frames (same routine at the same place) appear once with the number of threads, for example "TWorker.Execute (Unit2.pas:30) · 10 threads"; the tree branches where the stacks part.
- Nodes of the current thread are bold. If all threads of a node stand in a wait routine (`TMonitor.Enter`, `WaitForSingleObject`, `Sleep` …), the node says "waiting" in the warning colour; the list of routines is configurable (`debug.parallelStacks.waitRoutines`).
- The filter "Just my code" hides frames from the RTL, VCL and libraries, "Waiting" shows only waiting threads.
- Below the tree are the threads of the selected node. Enter or a double click switches to the thread (from a list if there are several) and jumps to the line.
- From `debug.parallelStacks.maxThreads` threads (default 64) Atlas reads the stacks in portions and shows the tree in between so the IDE stays responsive.

Settings: `debug.parallelStacks`, `debug.parallelStacks.waitRoutines`, `debug.parallelStacks.maxThreads`

<a id="window-atlasdebugleaks"></a>
### Atlas leaks

- When a program started in the debugger ends with memory leaks, Atlas reads the report: the message box of `ReportMemoryLeaksOnShutdown` (window text, no click) or the FastMM4/FastMM5 log file next to the EXE if it was written after the start. A log file with call stacks (FullDebugMode) wins.
- The dockable window "Atlas Leaks" (Atlas > "Atlas Leaks") shows the number of leaks per class. Classes that are new or grew since the last run of the same configuration are bold ("new", "+2 since the last run"); the state lives in `.atlas-local` next to the .dproj.
- Without call stacks, each class lists the places in the project that create it (`TClass.Create…`) with a rating: never freed, returned to the caller, passed as argument, field freed in the destructor, owner, freed locally, not in the program (test units). The most urgent come first.
- With call stacks, the creation sites from the report appear there, equal stacks grouped.
- String and unknown leaks usually follow from leaked objects with such fields; the window says so.
- "Mark as known" remembers a class, "Hide known" hides it. Enter or a double click jumps to the place.

Settings: `debug.leakReport`, `debug.leakReport.compare`, `debug.leakReport.window`

### Who frees this?

- Every line with `T.Create(…)` ends with a mark that answers it: green "freed in Destroy, line 48", "freed in finally, line 30", "owner Self", "owned by FList" (list with OwnsObjects) or "reference counted"; yellow "freed in Clear, line 70" (another method), "returned to the caller", "passed to Registry.Add" or "unclear"; red "never freed".
- Red appears only where one of the leak rules (`field-not-freed`, `create-without-assignment`, `local-object-not-freed`, `created-result-not-freed`) reports with the settings of the file, so mark and problem never disagree. With the rule off, the same place reads "unclear".
- Lists also carry "owns its elements" (`TObjectList` with OwnsObjects) or "elements owned by FList" when a second list of the same class owns the elements.
- A click on the mark jumps to the releasing line; the tooltip explains how Atlas reached the rating, for red with the message of the rule.
- The marks come from the server (`atlas.server.ownership`) and are fetched again together with the normal check of the file; only visible lines are drawn. Hide per line or per file with a right-click on the mark.

Settings: `editor.ownershipHints` (off by default, module Rule checks), `editor.ownershipHints.onlyProblems` (yellow and red marks only)

### Threads in source

- At a stop the gutter shows a mark with the count at every line where another thread stands with its topmost own frame; with eight waiting workers at the same line that is “8”. The IDE shows the current thread as before.
- The tooltip lists id, name and wait point per thread (“⚑ 4120 “Worker” · waiting in TEvent.WaitFor”); the links below switch to the thread and jump to its line.
- Right-click the gutter, then Atlas > Debugging > “Flag thread”: flagged threads carry ⚑ and come first in tooltips, pick lists and the parallel stacks (context menu “Flag thread”). The flag lasts for the session and follows the thread id. With several threads at the line you pick from a list; with none the current thread counts.
- Experimental (`debug.threadFreeze`, default off): “Freeze thread”, “Thaw thread” and “Thaw all threads”. A frozen thread does not run when you continue; its mark is gray and the Atlas status bar shows “2 threads frozen” (click thaws all). Atlas holds the thread with `SuspendThread`, which only works for programs on this computer. At the end of the session and when switched off Atlas thaws all threads.

Settings: `debug.threadsInSource`, `debug.threadFreeze`

### Origin of queued methods *(experimental)*

- When the program stops in an anonymous method started with `TThread.Queue`, `TThread.Synchronize`, `TThread.ForceQueue`, `TTask.Run`, `TTask.Create` or `TParallel.For`, the IDE call stack only shows `CheckSynchronize` or the thread pool. Atlas then shows “Queued with TThread.Queue from thread 4120” in the results window with the call stack of the place that queued it; library frames are collapsed (“5 library frames”), double click jumps to the line.
- For this Atlas sets a breakpoint of group Atlas.Herkunft on every call site in the project when the session starts. When the program stops there, Atlas records thread and stack and continues at once. A breakpoint of your own on the same line stays and stops as usual.
- Matching follows the order: a stop in the method of a call site gets the oldest open call of that site. Atlas keeps the last `debug.asyncOrigin.maxPerSite` per call site (default 20).
- Only calls with the class name (`TThread.Queue(…)`) count, a plain `Synchronize(…)` inside a thread method does not.
- Stopping at every call site slows the program down; the Atlas status bar shows “Origin: 12 call sites” in yellow while the breakpoints are set.

Settings: `debug.asyncOrigin`, `debug.asyncOrigin.maxPerSite`
