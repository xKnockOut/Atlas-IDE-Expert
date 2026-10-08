# Release

Server und VS-Code-Erweiterung tragen dieselbe [SemVer](https://semver.org/lang/de/)-Version. Quellen sind `TProductVersion.Version` (`BDLsp.Common.Product.Version.pas`) und `version` in `Editors/VSCode/package.json`; `pwsh Tools/Check-Version.ps1` prüft beide und den Abschnitt in `CHANGELOG.md`.

## Ablauf

1. Änderungen laufend unter `## [Unveröffentlicht]` in `CHANGELOG.md` eintragen.
2. `pwsh Tools/Set-Version.ps1 -Version 0.2.0` setzt die Version überall und legt den Changelog-Abschnitt an.
3. Committen, mergen, dann `git tag v0.2.0` und `git push origin v0.2.0`.
4. `.github/workflows/release.yml` prüft die Versionen, baut den Server (Win64 Release) auf dem Delphi-Runner, packt die `.vsix` mit EXE und legt das GitHub Release mit beiden Dateien und den Changelog-Notizen an. Versionen `0.x` und mit Suffix (`-beta.1`) gelten als Vorabversion.

Ohne Delphi-Runner (`DELPHI_RUNNER` nicht `true`) enthält das Release nur die `.vsix`; die EXE lässt sich dann von Hand anhängen.

## Optionale Geheimnisse

| Geheimnis | Wirkung |
|---|---|
| `SIGN_CERT_BASE64`, `SIGN_CERT_PASSWORD` | Signiert die EXE mit `signtool` (PFX als Base64), vermeidet SmartScreen-Warnungen |
| `VSCE_PAT` | Veröffentlicht die Erweiterung im VS Code Marketplace (Publisher `xknockout`) |
| `OVSX_PAT` | Veröffentlicht auf Open VSX (VSCodium, Cursor u. a.) |
