# Understanding

Back to the [README](../../../README.md)

## In the editor

### Hover tooltip

In Atlas style instead of Help Insight:

- declaration
- XMLDoc in collapsible sections
- clickable types, inheritance chain
- values of constants, sets and resource strings
- published members of components as a table
- symbols in `{$IFDEF}` with their origin
- actions (go to, usages, copy declaration, help)

### Rationale in the hover (#1123)

- Comments such as `// WHY: …`, `// HACK: …` or `// NOTE: …` above a declaration and inside the routine body appear under RATIONALE
- `ADR-0007` opens the decision record
- `#312` opens the issue in your tracker

### Values while debugging

- When the process is paused, the tooltip shows the value of the expression under the mouse
- Evaluated by the IDE's debugger without side effects

### Hints and marks

- **Type hints** after `var X := …` without a type
- **Code metrics** as a lens (Analysis module, `analysis.enabled`):
  - after each method header: length, depth, cyclomatic and cognitive complexity, parameters, operands of the largest condition, local variables, exits
  - after each class: members, inheritance depth without RTL and VCL
  - the unit name: lines
  - the first `uses`: units
- **Recursion marks** in the gutter
- **Inactive `{$IFDEF}` branches** dimmed with the reason in the tooltip
- **Unused uses** dimmed (rule `unused-uses`: also in `--check`, `get_diagnostics` and the baseline; `off`, `exclude`, `lsp-ignore` and the `keep` option apply to the dimming as well); interface uses only needed by the implementation part get a hint and the fix "Move to implementation uses" (rule `uses-only-in-implementation`, configurable the same way)
- **Bracket and block pairs** coloured by depth, with matching block lines; local routines either one level deeper, in their own colour with a dashed line or like the outer routine, optionally shaded (`highlight.nestedRoutines`, `highlight.nestedRoutineBand`)

### No findings in foreign code (`diagnostics.librarySources`)

- Units of the Delphi installation (RTL, VCL) and of the library paths that belong to no project are not checked in the editor, e.g. after Ctrl+click into `System.Classes.pas`
- Units in the project folder, from DCCReference and from the project search paths always are
- `float-equality` stays silent in equality comparers (`Equals…`, `class operator Equal`), where the exact comparison is intended

<a id="window-atlasarchitecture"></a>
## Architecture overview

Window *Atlas Architecture*, *View › Atlas › Architecture*.

### Map

- Subsystems as groups of closely connected units on a map you can zoom and pan
- Central units with direct and total dependents and role (foundation, hub)
- Cycles with their round trip and the uses entries that close it
- Cross links between subsystems (rare or against the main direction) and outliers
- Double-click opens the unit or the uses entry
- Can be saved as an HTML or Markdown report, also with `AtlasServer --architecture` and in the MCP tool `get_architecture`

### Architecture comparison (#1121)

- *Save state …* writes a stably sorted JSON state for version control
- *Compare with …* (or automatically `architecture.baseline`) shows in the *Comparison* tab:
  - new and removed cycles
  - cross links and uses edges between subsystems
  - units that changed subsystem
  - grown central units
  - new or removed units
- On the map new edges are green and removed ones red dashed
- Reports get a *Comparison* section
- `get_architecture` takes `compareWith`
- `AtlasServer --architecture new.json --compare old.json --fail-on newCycle` breaks a CI run

### Subsystem granularity (#1366)

Settings: `architecture.grouping.resolution`, `architecture.grouping.showResolutionSlider`

- The *Granularity* slider in the toolbar (coarse … fine, 0.2 to 5.0, double-click = 1.0) sets the resolution γ of the Louvain method
- On release the server recomputes in the background
- The value is kept in `settings.json`; next to it you see “γ = 1.5 · 12 subsystems”
- Reports name a changed γ in the header, saved states remember it, and the comparison points out a different γ
- `get_architecture` and `atlas/architecture` take `resolution` for one call

### Splitting (#1364)

Settings: `architecture.grouping.maxShare`, `architecture.grouping.minCohesion`

- A subsystem holding more than a quarter of all units or with low cohesion is split by a second run on its own units
- The parts:
  - are named after the section that sets them apart (“Lsp”, “Rules”, “Index” instead of one “Common”)
  - appear as “part of Common” in tables, report and `get_architecture`
  - sit side by side on the map in shades of one colour
  - are indented under their origin in the legend

### Foundations (#1365)

Setting `architecture.grouping.foundations`: `separate`, `attach`, `group`

- Units such as logging or JSON helpers used by many subsystems no longer pull them together
- They sit in a subsystem of their own, “Fundament”, in the middle of the map
  - neutral colour, faint edges you can hide, no cross links, no cohesion
- Or with `attach` they join the subsystem with most dependents

### Why a unit is where it is (#1368)

Setting `architecture.explainAssignment`

- Hovering a unit on the map and its profile below the map show its weighted edges per subsystem
  - `3 × interface`, `2 × impl.`, `= 8`
  - edges to the foundation “do not count”
- They say when the assignment is close (“with 3 more edges to Data it would lie there”)
- The *Subsystems* tab marks close units
- The question mark next to it explains how the subsystems are formed with the active settings
- The HTML and Markdown reports and `get_architecture` with `unit` show the same table

### Stable colours and names (#1367)

Setting `architecture.grouping.keepPrevious`

- After recomputing, subsystems that share more than half of their units with one from the previous state keep its colour and name
  - previous state: the saved baseline, otherwise the last computed state in the cache folder
- So a new unit no longer swaps colours or turns “Index” into “Index 2”
- The status line says “Subsystems matched to the state of …”
- *Subsystems ▾ › Rename subsystems* starts over once

<a id="window-atlasquery"></a>
## Code queries (#1351)

Window *Atlas Query*, *View › Atlas › Query*.

- Questions to the index in a small language, such as:
  - `classes where inherits TForm and methods > 40 order by methods desc`
  - `methods where complexity > 15 and callers = 0`
- With completion, sortable columns and a jump to the declaration
- Saved queries in `atlas.json` run as rule `query:<name>` in the editor, in `--check` and in SARIF
- The same language in the MCP tool `query_code` and with `AtlasServer --query`

<a id="window-atlashotspots"></a>
## Hotspots (#1354)

Window *Atlas Hotspots*, *View › Atlas › Hotspots*, `hotspots.enabled`.

- Units and methods that change often and are complex at the same time
- Score = normalized changes × normalized cognitive complexity from the Git or SVN history of the last `hotspots.months` months (renames followed)
- With authors, lines, complexity trend against three months ago and last change
- Views:
  - bubble chart (x = changes, y = complexity, size = lines)
  - sortable table on unit or method level
  - *Change coupling* tab: files changed together in at least 70 % of their commits without a uses edge between them
  - *History* tab
- Double-click jumps to the code; the context menu offers *Show history* and *Show impact* (#1120)
- Computed in the background and cached until the next commit
- Without version control a hint instead of data
- Also as a report with `AtlasServer --hotspots <file.html|md|json>` (exit code 3 without version control or when switched off) and as the MCP tool `get_hotspots`

## Call diagram (#1122, `callHierarchy.diagram`)

- The call hierarchy as an interactive diagram
- Switch *Diagram* in the results window, command *Call diagram* in the palette, the Atlas menu and the editor context menu
- Layout:
  - start on the left, one column per level
  - boxes with method name and location
- Mouse:
  - click loads and expands the next level
  - double-click jumps to the code
  - drag pans, mouse wheel zooms
- Calls through an interface or a virtual method are dashed with the number of implementations
- Recursion is an arrow back without further expanding
- More than 8 children collapse into "+ N …"
- Outgoing or incoming
- Filter *Project units only* (RTL/VCL hidden)
- *Save as HTML …* (standalone file without external references)

## Units and dependencies

<a id="window-atlasunitrelations"></a>
### Unit relations (#593)

Window *Unit relations*, *View › Atlas › Unit relations*; switched with `architecture.enabled`.

- Follows the editor and shows:
  - what the unit uses (in the groups “Interface” and “Implementation”, RTL/VCL dimmed in a collapsed group)
  - who uses it
  - interface cycles in red with the path in the tooltip
  - "N units to recompile" after an interface change
- Direct or all levels, filter
- Double-click opens the unit, Ctrl+double-click jumps to the uses entry
- Context menu moves an entry between interface and implementation, removes unused ones or copies the path
- Ctrl+double-click in the architecture map opens it for that unit

### Cost of an interface change (#554, `build.showInterfaceCost`)

- While the caret is in the interface part of a unit, the status bar shows "interface change: 143 units will be recompiled"
  - tooltip: the first units
  - click: dependencies
- Command *Dependencies of this unit* opens *Unit relations*:
  - with the users split into "via interface uses" and "via implementation uses"
  - marks interface entries that are only needed in the implementation ("move to implementation" in the context menu)
- *Most expensive units for interface changes* opens the architecture overview on *Central units* sorted by "total dependent"

### Use unit and Find forms (#786)

Settings: `unitSearch.replaceUseUnitDialog`, `unitSearch.replaceFormsDialog`

- Alt+F11 opens the *Search units* window as "Use unit in <unit>":
  - with an interface / implementation switch (Ctrl+I, default implementation)
  - units already in uses greyed out ("already in uses")
  - "Cycle via X" as a warning when the compiler would reject the cycle in the interface (only a hint in the implementation)
  - Enter adds all marked units without duplicates as one undo step
- Shift+F12 opens the window filtered to forms, frames and data modules; Enter opens the designer
- Shift+click and the commands *IDE dialog Use Unit* / *IDE dialog Forms* still open the IDE dialogs

### Live uses cycles (#896)

Settings: `diagnostics.usesCycleLive`, `diagnostics.usesCycleImplementation`

- While typing in a uses clause (and on open, using the unsaved state of other open units) an interface cycle is reported as an error "Zirkuläre Unit-Referenz: uC → uA → uB → uC (wie F2047)"
- Only such cycles name the compiler code (F2092 for a unit naming itself)
  - cycles through implementation uses do not, because Delphi compiles them (#1383)
- Each unit in the hover is a link to its uses entry, plus "Show graph" (Unit relations)
- Quick fix "Move to implementation uses" (sorted like `sortUses`) when the interface needs nothing from the unit
  - otherwise jumps to the identifiers that need it
- A unit naming itself is an error with "Remove entry"
- Implementation cycles only as a hint with `usesCycleImplementation`
- Same message in the problem list, MCP and CLI

## Path between symbols

*Atlas › Path between symbols …*, command palette, editor context menu *Path from here to …*; switch: `navigation.symbolPath`.

- How is `TCustomerForm` connected to `TDatabase`?
- Atlas finds the shortest chain over uses, inheritance, interface implementations, fields, parameters, results, calls and members
- It draws it in the results window, each step with its kind and location (inferred edges dashed)
- Double-click jumps there
- *Show on architecture map* marks the units of the path on the map
- Same search as the MCP tool `find_path`
