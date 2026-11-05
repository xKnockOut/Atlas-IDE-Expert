# Installation

German version: [Installation.md](../Installation.md).

Atlas is a single file, `AtlasServer.exe` (Windows, Win64). It speaks LSP over stdio, MCP for AI agents with `--mcp`, and checks without an editor with `--check`. The server only needs an installed RAD Studio version for compiler messages (`compiler.onSave`); it reads the matching version from the `.dproj`.

## Language

Atlas follows the language of the IDE (#1458): with an English Delphi IDE, findings, light bulb, hover, previews and settings descriptions are English; with a German IDE everything stays German. The setting `language` (`""` = like the IDE, `"de"`, `"en"`) fixes the language. Without an IDE, `AtlasServer --check` takes `--locale de|en`; without `--locale` the `language` setting of `%APPDATA%\Atlas\settings.json` applies, otherwise English.

## Getting the server

- **Release:** download `AtlasServer.exe` from the latest [GitHub release](https://github.com/xKnockOut/Atlas-IDE-Expert/releases) and put it in a folder on the `PATH`.
- **Build it yourself:** open `Atlas.groupproj` in RAD Studio and build Win64; the EXE is under `Output\Win64\<Config>\Bin\`.

## RAD Studio (release package)

The plugin `Atlas.IDE.Base` integrates the server into the IDE: [RAD-Studio.md](RAD-Studio.md).

For the IDE plugin (#495) every release contains `atlas-ide-expert-<version>.zip`:

```
AtlasServer.exe         Server (Win64)
AtlasUpdate.exe         installation and updates (#1519): “AtlasUpdate install” adds the package to an IDE
AtlasServer.map         Map file: stack traces in the server log with unit, routine and line
Win32\Atlas.IDE.Base370.bpl   Core of the plugin for the classic IDE
Win64\Atlas.IDE.Base370.bpl   Core of the plugin for the 64-bit IDE
Win32\Atlas.IDE.<Module>370.bpl, Win64\…   from 2.0 one BPL per module (#1456): Debugger, Designer, Rules, Tests,
                        Bookmarks, Analysis, Search, Build, BuildPipeline, Tracker, Welcome
Win32\Atlas.IDE.*370.map, Win64\…   Map files of every plugin BPL for stack traces in atlas.log
LICENSE, THIRD-PARTY-NOTICES.md
EULA.txt                License agreement
whatsnew.json           News per version for the card "New in Atlas" (#756)
Beispiele\              Sample files for "Try it" on this card and on "Discover Atlas"
tips.json               Tips for the card "Discover Atlas" and the shortcut tips (#757)
Tipps\                  Images (PNG) for these tips
Doku\                   Documentation as HTML for "Atlas docs" on the welcome page (#766)
Vorlagen\               Templates for atlas.json ("Set up project for Atlas" on the welcome page, #759)
Profile\                Settings profiles "Atlas default", "Minimal" and "Everything on" (#723)
```

Up to 1.1.0 the package contained the installer `AtlasSetup.exe` (ADR 0009). Since 1.2.0 it is gone. From 2.0 on, `AtlasUpdate.exe install` does the steps below in a console dialog (#1519, ADR 0018): choose IDE and profile (also own profiles from `bds -r` and the 64-bit IDE), target folder (suggested `%LOCALAPPDATA%\Programs\Atlas`, no admin rights needed) and modules; without matching BPLs in the package (Delphi 12) it builds the plugin from the release source (needs MSBuild of the Delphi installation). By hand it still works like this:

1. Close Delphi and unpack the ZIP into a fixed folder, e.g. `%LOCALAPPDATA%\Programs\Atlas` (where the former installer also put it). Keep the folder structure: the plugin looks for the server and the data (`whatsnew.json`, `tips.json`, `Vorlagen` …) next to the BPL and one level above.
2. Start Delphi, *Component › Install Packages › Add* and pick `Win32\Atlas.IDE.Base370.bpl` (Delphi 12: `…290.bpl` if included in the package; 64-bit IDE from Delphi 12.3: `Win64\…`). From 2.0 on, then add every module package from the same folder (`Atlas.IDE.Debugger370.bpl` …): first the core (it also contains the contracts between the modules), then the modules; when uninstalling, the other way round. A module loads the core along with it, but only finds it if it is already loaded or on the PATH (ADR 0017, decision 1: placed in the Bpl folder of RAD Studio).
3. Restart Delphi once: Atlas turns off Help Insight and the structural highlighting of the IDE, which the IDE only reads at startup.

**Uninstall:** *Component › Install Packages*, select "Atlas IDE Expert" and "Remove", then delete the folder. Settings (`HKCU\Software\Atlas`, `%APPDATA%\Atlas`), index and logs (`%LOCALAPPDATA%\Atlas`) and your own snippets (`%APPDATA%\Atlas\Snippets`) stay and can be deleted by hand. An installation made with the former installer is still removed by the entry "Atlas IDE Expert" under *Settings › Apps › Installed apps*.

**Update:** close Delphi, unpack the ZIP of the new version over the old folder (delete the folders `Beispiele`, `Tipps`, `Doku`, `Vorlagen` and `Profile` first) and start Delphi. If the package version in the BPL name does not change, the registration stays valid. Settings, favorites, `.atlas` files of the projects and snippets are left untouched. If the index format changes, the server discards the old cache and rebuilds it (#492).

**Transfer settings (#723):** *Tools › Options › Atlas* and the command palette (*Atlas.SettingsExport*, *Atlas.SettingsImport*, *Atlas.SettingsProfile*, *Atlas.SettingsReset*) export, import and reset the personal settings of the plugin per area, see [Settings.md](Settings.md#areas-for-export-import-and-reset) (German). The command line `AtlasSetup /exportSettings …` is gone together with the installer.

**Updates:** after consent at the first start, the plugin checks at most once a day whether a new version is available and reports it in the message view ([RAD-Studio.md](RAD-Studio.md)). From 2.0 on it installs it itself on request (#1519, ADR 0018): “Update now” downloads and verifies the update in the background, a console window applies it when the IDE closes, and Atlas reports the result on the next start. This needs a writable Atlas folder (not below `C:\Program Files`); otherwise nothing changes. Installed via GetIt, updates come through GetIt.

### Without the plugin: Code Insight Manager (quick guide)

If you only want to use the server without the plugin, register it in the built-in LSP client of the IDE (#175, in detail in [RAD-Studio.md](RAD-Studio.md#built-in-lsp-client)):

1. *Tools › Options › Editor › Language › Code Insight › Code Insight Manager › New*: name `Atlas`, executable `AtlasServer.exe`, timeout `15000`, InitializationOptions `{}` (or `{"locale": "en"}` for English texts), any language.
2. Close the IDE and set the value `LanguageId` to `Delphi` under `HKCU\Software\Embarcadero\BDS\<Version>\LSP\UserDefined\Atlas`.
3. Start the IDE and select "Atlas" for Delphi in the Code Insight Manager.

Then syntax errors, hover (as plain text), outline and completion run through Atlas. Frequent server starts in the log are normal: the IDE restarts its server per IDE and on every project change and ends it hard; the next start reports this in the log.

## Claude Code

As an MCP server (index tools for the agent):

```
claude mcp add delphi -- AtlasServer.exe --mcp --root C:\Projects\App
```

With diagnostics and navigation as a plugin: [Editors/ClaudeCode/README.en.md](../../Editors/ClaudeCode/README.en.md). Tools: [MCP.md](MCP.md).

## Without an editor (CI)

```
AtlasServer.exe --check App.dproj --format sarif --output findings.sarif --locale en
```

More options are listed in the [README](../../README.md).

## Next

- [Configuration.md](Configuration.md): all keys of `atlas.json`
- [Rules.md](Rules.md): all check rules with examples and suppression via `// lsp-ignore: <rule>`
