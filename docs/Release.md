# Release

Server und Claude-Code-Plugin tragen dieselbe [SemVer](https://semver.org/lang/de/)-Version. Quellen sind `TProductVersion.Version` (`Atlas.Common.Product.Version.pas`) und `version` in `Editors/ClaudeCode/atlas/.claude-plugin/plugin.json` und `.claude-plugin/marketplace.json`; `pwsh Tools/Check-Version.ps1` prüft beide und den Abschnitt in `CHANGELOG.md`.

## Ablauf

1. Änderungen laufend unter `## [Unveröffentlicht]` in `CHANGELOG.md` eintragen.
2. `pwsh Tools/Set-Version.ps1 -Version 0.2.0` setzt die Version überall und legt den Changelog-Abschnitt an.
3. Committen, mergen, dann `git tag v0.2.0` und `git push origin v0.2.0`.
4. `.github/workflows/release.yml` prüft die Versionen, baut den Server (Win64 Release) auf dem Delphi-Runner, packt das Claude-Code-Plugin mit EXE und legt das GitHub Release mit EXE, Map-Datei, Plugin und den Changelog-Notizen an. Versionen `0.x` und mit Suffix (`-beta.1`) gelten als Vorabversion.

Mit Delphi-Runner baut der Workflow außerdem Plugin (Win32 und Win64) und Installer (#495) und hängt `atlas-ide-expert-<Version>.zip` an (Aufbau in [Installation.md](Installation.md#rad-studio-installer)). Dazu kommt immer `atlas-version.json` (`{"version": "…", "changes": "<Link zum Release>"}`): Die Update-Prüfung des Plugins liest sie über `releases/latest/download/atlas-version.json`. GitHub zählt Vorabversionen dabei nicht als „latest“; Versionen `0.x` melden sich also nicht als Update.

Ohne Delphi-Runner (`DELPHI_RUNNER` nicht `true`) enthält das Release nur die Changelog-Notizen; die EXE lässt sich dann von Hand anhängen.

## Optionale Geheimnisse

| Geheimnis | Wirkung |
|---|---|
| `SIGN_CERT_BASE64`, `SIGN_CERT_PASSWORD` | Signiert die EXE mit `signtool` (PFX als Base64), vermeidet SmartScreen-Warnungen |
