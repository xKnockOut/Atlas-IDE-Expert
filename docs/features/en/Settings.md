# Settings

Back to the [README](../../../README.md)

- *Tools › Options › Third Party › Atlas* as a tree: areas at the top, every feature with its own master switch that also disables its sub-options; next to it the pages *Snippets*, *Tastenkonflikte* (key conflicts) and *Server*
- Every visible feature can be switched off on its own; experimental features are marked
- Export, import, load profiles and reset settings
- Team-wide values in the project file `.atlas` (next to the .dproj, in a folder above it up to the Git or SVN root, or next to the .groupproj), server and rule settings in `atlas.json` (*Atlas › Projekt-Einstellungen*), global values in `%APPDATA%\Atlas\settings.json`

- Language follows the IDE (#1458): with an English Delphi IDE, settings descriptions, "New in Atlas" and the first server texts (rule explanations, unknown rule ids, unused suppressions) are English, with a German IDE everything stays German; `language` (`""` like the IDE, `"de"`, `"en"`) fixes it, `AtlasServer --check` takes `--locale de|en`. Server texts move to text tables (`TAtlasText`) group by group; `Tools/Check-GermanText.ps1` keeps new German literals out

All keys: [docs/en/Configuration.md](../../../docs/en/Configuration.md) (English), [docs/Einstellungen.md](../../../docs/Einstellungen.md) and [docs/Konfiguration.md](../../../docs/Konfiguration.md) (German).
