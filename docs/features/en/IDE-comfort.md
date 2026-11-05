# IDE comfort

Back to the [README](../../../README.md)

## Atlas welcome page

- Shown:
  - on the IDE welcome page (as single sections or as one “Atlas” section on top, switchable with `welcomePage.ideWelcomePage`)
  - and, independently, in the dockable window *Atlas Start* (*View › Atlas Start*, command palette; opens when the last project is closed and, with `welcomePage.openOnStart`, on IDE start)
- Sections:
  - continue working
  - projects with quick actions
  - project history
  - unsaved
  - project setup
  - test results
  - my issues
  - new in Atlas
  - discover Atlas
  - help and feedback
- Search box and free layout

## Issue tracker (GitHub, YouTrack)

### Basics

- "My issues" on the welcome page
- Start an issue with branch and commit prefix

### Settings and connections

- All tracker settings live under `issues.*` on their own page *Tools › Options › Atlas › Issue tracker*
  - earlier `welcomePage.issues.*` values are taken over on first start
- Several tracker connections side by side (`issues.connections`)
  - with token state and "Check"
  - the token only in the Windows credential store
- "Check" detects a German YouTrack interface and the default query follows it.
- Personal assignment of Delphi projects, project groups or folders to a connection and tracker project (`issues.projects`, the `.atlas` wins)
  - with "No tracker for this project – assign …" in "My issues"

### Queries

- Several named queries (`issues.queries`, per connection and tracker project)
  - with a picker and hit counts in the "My issues" header (`issues.queryPicker`)
  - the earlier single query becomes "Standard"
- "Edit query" dialog with templates (YouTrack in German and English) and "Test"
  - "Test" names the cause (no token, rejected, unknown project, query rejected with the tracker's message, unreadable answer) and the query actually sent

### Issue preview

- In the dockable window *Atlas Issue* (`issues.preview`): click an issue in "My issues" or run *Show issue…*
- Shows:
  - description as Markdown
  - fields, comments, attachments, linked issues
  - back/forward
  - a 7-day offline cache
- Checklists (`- [ ]`) can be ticked right in the preview, with progress "3/5" in the header and the status field (`issues.preview.checklists`, `issues.checklistStatus`)
- Dependencies and subtasks as a tree (`issues.preview.links`):
  - depends on, blocks, subtasks with progress 2/3
  - create a subtask or add a link right from the preview
  - a warning on "Start" while a blocking issue is still open (`issues.warnBlocked`)
- A *Development* tab (`issues.preview.development`) with:
  - the issue's branches (ahead/behind, switch)
  - commits (diff, jump to the change)
  - pull requests with CI light (GitHub) or YouTrack VCS changes
  - the changed units grouped by project

### Issues in the code

- Issue keys such as `ATL-123` or `#42` in comments (`issues.codeLinks`):
  - get a dotted underline
  - a short preview on hover
  - Ctrl+click into the preview
  - their own right-click menu
- Line history (`issues.blameLinks`, Git `log -L` and SVN):
  - shows the issue keys of the commit message
  - its hover adds title and state per key
  - Ctrl+click opens the preview
  - *Issues for this method* lists every issue whose commits changed the method (or unit) at the cursor, with commit count and diff

### Create, start, finish

- "Create issue …" (`issues.create`, `issues.create.includeCode`):
  - from the editor (selection or TODO under the cursor, location, method, branch, code snippet as its own checkbox)
  - and from findings of the Atlas check
  - with a preview before sending
  - afterwards `// TODO ATL-130: …` in the code and the key on the clipboard
- With `issues.syncState`:
  - "Start" sets state, assignee and a comment in the tracker
  - "Finish" opens a dialog with target state, comment ({branch}, {commits}, {pr}) and hand-over
  - the preview gets a comment box (Ctrl+Enter)
- With `issues.timeTracking` Atlas tracks working time per issue:
  - status field "ATL-123 · 1:25"
  - idle time stops the clock
  - pause, correct, *Open time bookings…*
  - offers to book it as a YouTrack work item when finishing (rounded, work type, text from the commits; GitHub as a comment)

### Board and sprint

- A board in the dockable window *Atlas Board* (`issues.board`):
  - the current sprint of the YouTrack agile board or the GitHub project as columns with cards
  - "Only mine", search
  - dragging changes the state in the tracker after a confirmation and follows the YouTrack workflow:
    - under a state machine Atlas fires the matching transition like YouTrack's own board
    - columns the workflow rules out are not highlighted
    - the status line names the allowed transitions
  - click opens the preview, double-click starts the issue
- A *Sprint* section on the start page (`welcomePage.sprint`):
  - current sprint with days left, own numbers, "team left" and a burndown
  - compared with the previous sprint plus the velocity of the last three sprints
  - clicking the numbers filters "My issues"

### Search from the command palette

`issues.paletteSearch`: `#text`, `#42` or `ATL-12`

| Key | Action |
|---|---|
| Enter | preview |
| Ctrl+Enter | start |
| Shift+Enter | browser |
| Ctrl+C | copy key |

- An empty `#` lists recently opened issues.

### Comment editor

A richer comment editor (`issues.commentEditor`) in the preview and the finish dialog:

- `@` suggests tracker users
- `#` and `ATL-` suggest issues
- Ctrl+B/Ctrl+I/Ctrl+Shift+K format
- a preview tab
- text snippets with {branch}, {commit}, {issue} and {version} (`issues.commentSnippets`)
- drafts kept per issue

### Notifications

Notifications about my issues (`issues.notify`):

- new comments, assignments and state changes in the notification center
- "Open" jumps to the new comment
- a dot in "My issues" until opened

### Attach to issue

*Attach to issue…* (`issues.attach`: Atlas menu, command palette, preview window, status field) sends in one step:

- a screenshot of the running program or of the form in the designer (with rectangle, arrow and blacken)
- a log file (last N lines)
- a debug note
- the exception history

YouTrack gets the files as attachments plus a comment, GitHub gets texts as a comment and images via the clipboard.

## Version control (Git, SVN)

### Options page (#1285)

Own page *Tools › Options › Atlas › Version control* with:

- the kind (`vcs.provider`: automatic, Git, SVN, off)
- a custom path to git.exe or svn.exe (`vcs.git.path`, `vcs.svn.path`)
  - empty = PATH and the usual folders
  - a custom path is used alone, and if the file is missing Atlas says so instead of taking another program
- "Check" with version and location
- a time limit per call (`vcs.timeoutSeconds`)
- the state of the current project (working copy, branch or path, revision, where the setting comes from)

The values also apply to `atlas --changed`.

### Table *Projects* (#1286, `vcs.projects`)

- Sets kind and main branch per `.dproj`, `.groupproj` or folder (e.g. one row per package folder from SVN externals)
- Order (the same order as the tracker assignment):
  1. the `vcs` section of the `.atlas` wins,
  2. then the row for the `.dproj`,
  3. the open project group,
  4. the longest matching folder
- Change markers use the row of the unit's folder.
- "Start" in *My issues* branches from the main branch and incoming commits fall back to it.

### Table *Servers* (#1287)

- Checks on click whether Atlas reaches the server without prompting (`git ls-remote`, `svn info ^/`, 10 s)
  - results: reachable, sign-in needed, not reachable, no server
- *Sign in …* opens a console where Git Credential Manager or SVN ask and store the sign-in; Atlas stores no credentials.
- Fetch, pull and push never prompt (`GIT_TERMINAL_PROMPT=0`, `GCM_INTERACTIVE=never`).
- A missing sign-in shows up in *Continue working* as "Server sign-in needed – check …" instead of an empty list.

### Create branch (#1288)

*Create branch …* (command palette, context menu of *Projects*, and "Start" in *My issues* while `vcs.branch.confirm` is on) shows:

- name
- base:
  - Git: origin/main, local main, current branch
  - SVN: main branch @ HEAD with the revision from the server, or the working copy @ its revision
- the SVN commit message
- under *What happens* the exact git/svn commands Atlas then runs, steps that change the server marked
- svn:externals are pointed out

#### SVN branches (#1290)

- SVN branches go next to the project's trunk (`vcs.branch.svn.location`, default `{projektwurzel}/branches/{name}`, so `^/Kasse/trunk` gets `^/Kasse/branches/<name>`)
- with source (HEAD or the working copy, warning for a mixed revision)
- what happens next: switch, fresh checkout into a folder next to it (which Atlas then offers to open), or nothing
- the commit message (`{kennung} Branch für {titel}`)

#### Externals (#1291)

- The group "Externals (n)" lists every `svn:externals` line with folder and source and lets you:
  - pin it to the revision of its working copy,
  - leave it unchanged,
  - or branch it along (the package is copied next to its own trunk, e.g. `^/Packages/Drucken/branches/<name>`, and the external line in the new branch is rewritten through a slim checkout)
- Externals with a fixed revision stay; externals from other repositories and file externals are never branched along.
- Defaults on the *Externals* node:
  - `vcs.externals.onBranch`: pin, keep, ask
  - `vcs.externals.suggestBranch`: with local changes, never, always
  - `vcs.externals.rules`: one rule per source, the longest match wins
- Pinning uses `svn copy --pin-externals` from svn 1.9 when everything is pinned.
- After switching Atlas rebuilds the index.

#### Git options (#1289)

Git options for creating branches (`vcs.branch.git.*`, group *Git* on the page and in the dialog):

- base:
  - `remote` (default; `git fetch <remote> <main>` first; if that fails Atlas asks after the dialog "Branch from the local state?" with the server state, without the dialog it stops)
  - `local`
  - `current`
- `push`:
  - `later`
  - `now` (`git push --set-upstream`; if only the push fails the local branch stays and the message names the reason)
- uncommitted changes:
  - `carry`
  - `stash` (`git stash push --include-untracked -m "Atlas: vor <name>"`)
  - `ask` (carry over, stash, cancel)
- `worktree` creates the branch in its own folder:
  - `git worktree add`
  - `worktreeFolder` with `{repo}`, `{name}`, `{kennung}`, default `..\{repo}-{kennung}`
  - then offers to open the same `.groupproj`/`.dproj` from there
  - an existing folder is refused
- With `local`, `later`, `carry` and no worktree everything works as before.

### Working copies (#1292)

"Working copies …" (project menu of the welcome page and the Atlas menu):

- shows the root, every svn external and every git submodule with:
  - path in the repository
  - revision ("· fixed" for pinned externals)
  - changes
  - and, on "Check server", the new commits
- double-click opens the folder
- the context menu updates all, only this one or pins the revision (asks first, no commit)
- "Unsaved" names each working copy with its changes
- Pull gets a submenu "with/without externals"

Settings: `vcs.externals.show`, `vcs.externals.update` (with, without, ask)

### Change marks

- **Change marks** in the gutter against Git HEAD or SVN BASE

## Commands, status and notifications

| Feature | Shortcut |
|---|---|
| **Command palette** for all Atlas commands | Ctrl+Shift+P |
| **Atlas status field** with index progress and quick switches | Ctrl+Shift+Alt+A |
| **Notification centre**: collects messages from builds, checks and the server | Ctrl+Shift+Alt+N |
| **Find selection** | F3 or Shift+F3 |

### Atlas server window (#1356, `server.statusWindow`)

- Opened via *Atlas › Help and diagnostics*, command `Atlas.ServerStatus`, click on the *Server* line of the status window, double-click on the status in the Atlas status bar
- Shows:
  - process, version, uptime, state (loading, ready, checking) and restarts of the session
  - memory per area (symbols, usages, library units, syntax trees, open documents, rest) as bars against the budget with the hint “usages are being offloaded”
  - the 10 slowest units and rules of the last check run
  - the slowest requests, queue and cache hits
- Double-click opens the unit or the rule settings.
- It reads the status the status lines fetch every 5 s anyway and only while visible.
- Buttons:
  - *Refresh* asks at once
  - *Rebuild index*
  - *Create diagnostic package …* writes a ZIP with the bug report (#108), status, the session log and, with `--trace`, the trace of the last minutes, anonymised like the bug report and never with credentials, after a preview

### Plugin timings in the diagnostic window (`diagnosticMode.pluginTimings`, `diagnosticMode.slowThresholdMs`)

With the diagnostic mode on, *Atlas diagnostics* shows what in Atlas is slow right now:

| Tab | Content |
|---|---|
| *Main thread* | how busy Atlas kept the IDE over the last 60 s, own time per feature (calls, total, mean, max, calls above the threshold, share) and the last 200 slow calls with the Atlas action that ran; context menu *Show only X*, *Switch off until restart*, *Copy row* |
| *Server* | each request with count, mean, max, how long the main thread waited, timeouts, cancellations and errors |
| *Background* | working time of every completion source in the worker thread and how often it was too slow |
| *Hangs* | the freeze watchdog's reports of the session and whether Atlas was involved |
| *Completion* | the previous window |

- *Pause*, *Reset* and *Copy report* (without source code and file names)
- Switched off, no measuring point runs

## Files

- **Silent reload** of files changed outside the IDE

## Robustness

- No error in Atlas reaches the IDE
- Hang watchdog with log
- Stack traces with unit and line for every caught error
- Check rules and editor features handle arbitrarily deeply nested expressions without recursion
  - a unit beyond the 100000-level net gets the hint `unit-too-deep` instead of silently losing its findings
- A feature that keeps failing is switched off on its own (with a notification to switch it back on) while the others keep running
- Server crashes are logged with their cause (exit code, stderr); a server that crashes the same way twice is not restarted in a loop
- Safe start after a crash
  - a slow IDE start is not a crash: instead of switching features off next time, Atlas names how long it held up the start and which of its parts took longest
  - an IDE started with `ATLAS_NO_SESSION_MARKER=1`, such as a build IDE a script starts, neither counts as a crash itself nor evaluates crashes of other IDEs
- Its own data files (favorites, histories, bookmarks, notes …) are replaced in one step, and a damaged one is kept next to it as `.defekt` instead of being silently overwritten
- Bug report to attach
- Anonymous diagnostics (#1478): plugin and server logs, bug report, status, diagnostic package and `--timings` name projects, units, paths, users and messages only as `name#N`, `datei#N`, `text#N`; real names only by explicit choice (`diagnostics.log.names`, “Anonymize bug reports” off, `--log-names`), noted in the package. Before saving, Atlas shows every file of the package.
- Key conflicts with other extensions (GExperts, CnPack, MMX) are detected
- Every crash of a request in the server is saved as a reproducible case (`%LOCALAPPDATA%\Atlas\crash`):
  - request, recent messages, snapshot of the file, settings without credentials, call stack
  - `wiederholen.cmd` for `AtlasServer --replay`
  - `Tools/New-CrashTest.ps1` turns it into a DUnitX test
- The notice after the restart names method, file, line and exception with “Open case” and “Create issue”
- As a safety net the server skips a request that crashed twice on the same unchanged file, visible in the status bar and the problems window

Settings: `server.crashCases`, `server.crashSkip`

## Other

- **Update check** only after consent; **update installer** (#1519): “Update now” downloads and verifies the update in the background and a console window applies it when the IDE closes, with module selection, rollback and the result on the next start (`updates.install`, `updates.channel`, `updates.newModules`); Delphi 12 gets it built from source
- **Accessibility:** lists and tooltips readable by UI Automation
