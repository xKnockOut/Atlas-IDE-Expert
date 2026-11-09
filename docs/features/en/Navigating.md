# Navigating

Back to the [README](../../../README.md)

## Jumping

- **Go to** definition (Ctrl+click), implementation and type definition
- Switch between declaration and implementation (Ctrl+Shift+↑/↓)
- **Jump to the counterpart** (begin ⇄ end, try → finally → end, `{$IFDEF}` → `{$ENDIF}`)
- **Peek definition** (Alt+F12) below the line without switching files
- **Navigation history** across files

## Bars above and below the editor

### Breadcrumb bar

- Above the editor with jump menus for unit, class, method and their children
- Inside the declaration of a class, record or helper, the visibility section at the cursor (`strict private`, `private`, `protected`, `public`, `published`) as a part of its own; its menu jumps to the other sections, and before the first keyword the implicit visibility appears in italics (`editor.breadcrumbsVisibility`)
- In the menu of the visibility part, each section shows its mark and member count (“− private · 7 members · line 27”, `editor.breadcrumbsSectionCounts`), “New line at the end of private” (an empty, indented line after the last member with the cursor in it; comments at the end of the section stay below, Ctrl+Z takes it back; `editor.breadcrumbsSectionAppend`) and, for missing sections, “Create section: protected” at its place in the usual order (`editor.breadcrumbsSectionCreate`); “New line at the end of the section” is also in the command palette and on a freely assignable key (`keys.sectionAppend`, section at the cursor)
- Behind it, the block at the cursor (`const`, `type`, `class var`); its menu jumps to the blocks of the section, and an explicit `var` ends the block (`editor.breadcrumbsMemberBlocks`)
- Inside a method body, the visibility mark of its declaration in front of the method part (`−` private, `#` protected, `+` public, `◆` published); the hint names the exact visibility and the line of the declaration, such as “strict private · declared in line 42” (`editor.breadcrumbsVisibilityMark`)
- At unit level, the section and the declaration block at the cursor (`type`, `const`, `var`, `resourcestring`, `threadvar`, `label`, `exports`), such as `uKunden › interface › resourcestring › sKundeFehlt`; the block menu lists all blocks of the unit with section and line, and local blocks inside routines do not count (`editor.breadcrumbsDeclarationBlocks`)
- At the end, the conditional branch around the cursor (`{$IFDEF MSWINDOWS}`, in the other branch `{$ELSE MSWINDOWS}`, `{$ELSEIF …}`), one part per level for nested blocks, outermost first; the menu jumps to IF, ELSE and ENDIF of the block. The bar does not decide whether the branch is active (`editor.breadcrumbsConditionals`)
- Behind the unit or section, the innermost `{$REGION}` around the cursor, such as `uKunden › Database access › TKunde › Save`; its menu lists all regions of the unit with their line, nested ones indented, and a region without a name is called “Region (l. n)” (`editor.breadcrumbsRegions`)
- Optionally, inside a method body, `try`, `except`, `finally` and the case branch (`case Kind of › akCompany`), at most the innermost three; the menu jumps to the parts of the try block or to all branches of the case (`editor.breadcrumbsStatements`, off by default)
- When the bar gets too narrow, these frames go first, then the other additional parts, and only then parts at the front

### Editor toolbar

- Icons:
  - jump to the interface or implementation section (and back with "↩ 214")
  - find method
  - navigation history
  - any palette command
- Overflow menu, customizable
- Can also sit inside the breadcrumb row

### Designer bar

Above the form designer instead of breadcrumbs and editor toolbar:

- a “Find components” window (Alt+^, large with filters and preview or small like Ctrl+P)
- show and hide non-visual components via the IDE's Ctrl+H
- select parent
- tab order as badges on the controls
- experimental: renumber the tab order by clicking and align controls

### Atlas status bar

At the bottom of each editor window (state colours tuned separately for light and dark themes):

- server status
- findings of this unit per kind
  - click jumps to the next one
  - double-click opens "Atlas Findings" for the unit
- live check ("live · checked 2 s ago", during the project check "· project 45 %", then briefly "project done")
- the method at the cursor with lines and CC (warning colour above the metric limit)
- each element can be switched off
- the Atlas field leaves the IDE status line while the bar shows the status

## Finding

- **Outline** as a dockable window with filter
- **Quick open** of files and symbols (Ctrl+P) across project, project group and search path
- Project-wide **symbol search**
- **Unit search** (Ctrl+F12) in its own window with preview, groups, filters and "add to uses"
- **TODO overview** of the project from `// TODO`, `// FIXME` and the IDE's to-do format

### Search bar

Below the editor (Ctrl+F):

- **replace** (Ctrl+H, "Replace all" as one undo step)
- **regular expressions** with a "before → after" preview
- search and replace **history** (arrow up/down, kept across restarts)
- scopes: method, unit, selection, **open files, project and project group**
  - searched in the background, unsaved buffers first
  - replacing checked matches across files

## Results, impact and data flow

### Results window "Atlas Results"

- For references (including forms), implementations, callers, calls and inheritance
- Usages split into "Sure" and "Inferred · check before renaming" with a reason (interface, override, ambiguous overload, inactive branch)
- A "Sure only" filter

### Show impact

Editor context menu, *Atlas › Search*, command palette. What is affected if the symbol at the cursor changes?

- Direct and indirect callers and references
- Overrides, the overridden base method
- Interface method and implementations
- Event handlers and components in forms
- As a tree by cause with a depth of 1 to 5
- Plus the affected DUnitX tests and "Run affected tests"
- Runs in the background, reports reached limits (depth, count, time)

Settings: `navigation.impact`, `navigation.impactDepth`

### Data flow

"Where does the value come from?" and "Where does the value go?" show a tree in the results window:

- assignments
- var/out arguments
- callers' arguments for a parameter
- `Result` and `Exit(…)` of a function
- property setters and getters
- each with file, line and source line

Details:

- Equal places are grouped ("3 assignments")
- Deeper levels load when expanded up to `navigation.dataFlow.maxDepth`
- Cycles, constants and code outside the project end the path
- Unsafe edges (pointers, `absolute`, `Move`, `FillChar`, `@`) are marked
- Enter or double-click jumps
- Filters "Project code only" and "Hide tests"

Settings: `navigation.dataFlow`

## Project tasks

From `atlas.json` (`tasks`):

- run scripts such as `pwsh Tools/Check-Delphi12.ps1` from the command palette, the Atlas menu, a key per task, the status field or a welcome page quick action
- output in the "Atlas tasks" tab with a green or red header
- matches (dcc, pwsh, msbuild, generic or your own regex) as findings in the problem list and the editor
- optionally before every build (`warn` or `block`)

## Bookmarks and notes

- **Named bookmarks** (Ctrl+Alt+K) and personal **notes** on code lines that never go into the source
- **Quick bookmarks** in a column left of the line numbers:

  | Action | Key |
  |---|---|
  | set and remove | click |
  | number them | Ctrl+Shift+1…9 |
  | jump project-wide | Ctrl+1…9 |
  | unnumbered | Ctrl+Shift+K |

  - the IDE's folding chords keep working
  - they follow code changes and take over the IDE bookmarks as soon as the column is drawn

## Regions

- **Regions when a file opens** (Options › Editor): "leave unchanged" (default), "collapse all" or "expand all" `{$REGION}` blocks the first time a file is shown; the region holding the caret stays open
- **Collapse all regions** / **Expand all regions** in the Atlas menu (Navigation), the editor context menu and the command palette
- "off (no commands either)" hides the commands as well

## Scroll bar and overview

- **Overview ruler** at the scroll bar with errors, matches and changes
- **Minimap** *(experimental)*
- **Sticky scroll** of the enclosing class, routine and large blocks, each kind switchable *(experimental)*
