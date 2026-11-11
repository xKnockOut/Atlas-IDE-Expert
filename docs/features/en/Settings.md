# Settings

Back to the [README](../../../README.md)

- *Tools › Options › Third Party › Atlas* as a tree: areas at the top, every feature with its own master switch that also disables its sub-options; next to it the pages *Snippets*, *Key conflicts* and *Server*
- Every visible feature can be switched off on its own; experimental features are marked
- **Search settings** (#1884, `settings.search`): a search field sits above the tree of every node and on the overview "Atlas" (Ctrl+F or Ctrl+E). It searches caption, description, key (`hover.signatureParams`, also parts such as "signature"), area and sub-item, and synonyms (`x-keywords` in the schema, e.g. "tooltip" for hover, "lint" for rule checks); German terms also match in the English IDE. One typo per word is allowed ("minimpa"). Each row shows the path and state: modified, experimental, locked with reason, module off, can be set per project; hits in other nodes carry "in <package>". Enter opens the first hit, Down moves into the list, Esc clears the field. Settings of modules that are not installed do not appear.
- **Settings in the command palette** (#1884, `palette.settingsPrefix`): `@` before the query shows only settings with path, key and state. Enter opens *Tools › Options* at the setting, Alt+Enter flips a quick toggle directly.
- **Module switches** for whole areas (`debug.enabled` … `search.enabled`, `ruleChecks.enabled`, `welcomePage.enabled`):
  - debugging, issue tracker, analysis, tests, build tools, build pipeline, bookmarks, designer, rule checks, search and welcome page
  - a module that is off turns off its features and commands without a restart; stored values stay
  - the profile *Nur Code Insight* (code insight only) keeps just the core
  - every module package brings its settings as its own section of the options dialog; with only `Atlas.IDE.Base` installed, only the settings of Base appear
  - if a project's `atlas.json` sets rules while the rule checks module is off, Atlas points this out once
- Export, import, load profiles and reset settings
- Team-wide values in the project file `.atlas` (next to the .dproj, in a folder above it up to the Git or SVN root, or next to the .groupproj), server and rule settings in `atlas.json` (*Atlas › Project settings (atlas.json)…*), global values in `%APPDATA%\Atlas\settings.json`

## Language

- Language follows the IDE (#1458):
  - with an English Delphi IDE, settings descriptions, "New in Atlas" and the first server texts (rule explanations, unknown rule ids, unused suppressions) are English
  - with a German IDE everything stays German
- `language` (`""` like the IDE, `"de"`, `"en"`) fixes it
- `AtlasServer --check` takes `--locale de|en`
- Server texts move to text tables (`TAtlasText`) group by group; `Tools/Check-GermanText.ps1` keeps new German literals out

All keys: [docs/en/Configuration.md](../../../docs/en/Configuration.md) (English), [docs/Einstellungen.md](../../../docs/Einstellungen.md) and [docs/Konfiguration.md](../../../docs/Konfiguration.md) (German).
