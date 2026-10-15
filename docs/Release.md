# Release

Server und Claude-Code-Plugin tragen dieselbe [SemVer](https://semver.org/lang/de/)-Version. Quellen sind `TProductVersion.Version` (`Atlas.Common.Product.Version.pas`) und `version` in `Editors/ClaudeCode/atlas/.claude-plugin/plugin.json` und `.claude-plugin/marketplace.json`; `pwsh Tools/Check-Version.ps1` prüft beide und den Abschnitt in `CHANGELOG.md`.

## Ablauf

1. Änderungen laufend unter `## [Unveröffentlicht]` in `CHANGELOG.md` eintragen. Einträge für die Karte „Neu in Atlas“ (#756) bekommen am Zeilenende eine Markierung `<!-- whatsnew … -->` (Felder `title`, `text`, `setting`, `key`, `command`, `sample`, `line`; siehe `Tools/Update-WhatsNew.ps1`); Beispieldateien liegen in `Setup/Beispiele`. Der Release erzeugt daraus `whatsnew.json` im Installationspaket, die Release-Notizen enthalten die Markierungen nicht. Die Tipps der Karte „Atlas entdecken“ (#757) stehen in `Setup/tips.json` mit Bildern in `Setup/Tipps`; `Tools/Check-Tips.ps1` prüft sie (Befehle, Einstellungen, Bilder samt Größe und `@2x`-Datei, Vorlagen, Stellen in den Beispielen), der Release kopiert beide unverändert ins Paket. Neuer Befehl oder neue Funktion: Tipp in `Setup/tips.json` ergänzen (siehe Abschnitt „Bilder der Tipps“). Die lokale HTML-Doku für „Atlas-Doku“ (#766) erzeugt `Tools/Build-Docs.ps1` aus `README_DE.md`, den Seiten unter `docs/` und `CHANGELOG.md` in den Ordner `Doku` des Pakets; Verweise auf andere Dateien zeigen ins Repository auf GitHub.
2. `pwsh Tools/Set-Version.ps1 -Version 0.2.0` setzt die Version überall und legt den Changelog-Abschnitt an.
3. Committen, mergen, dann `git tag v0.2.0` und `git push origin v0.2.0`.
4. `.github/workflows/release.yml` prüft die Versionen, baut den Server (Win64 Release) auf dem Delphi-Runner, packt das Claude-Code-Plugin mit EXE und legt das GitHub Release mit EXE, Map-Datei, Plugin und den Changelog-Notizen an. Versionen `0.x` und mit Suffix (`-beta.1`) gelten als Vorabversion.

Mit Delphi-Runner baut der Workflow außerdem Plugin (Win32 und Win64) und Installer (#495) und hängt `atlas-ide-expert-<Version>.zip` an (Aufbau in [Installation.md](Installation.md#rad-studio-installer)). Dazu kommt immer `atlas-version.json` (`{"version": "…", "changes": "<Link zum Release>"}`): Die Update-Prüfung des Plugins liest sie über `releases/latest/download/atlas-version.json`. GitHub zählt Vorabversionen dabei nicht als „latest“; Versionen `0.x` melden sich also nicht als Update.

Ohne Delphi-Runner (`DELPHI_RUNNER` nicht `true`) enthält das Release nur die Changelog-Notizen; die EXE lässt sich dann von Hand anhängen.

## Bilder der Tipps

Die Bilder der Karte „Atlas entdecken“ entstehen reproduzierbar aus HTML-Vorlagen: je Tipp `Tools/Tipps/Vorlagen/<name>.html` (ein HTML-Ausschnitt), gemeinsamer Rahmen und Bausteine in `Tools/Tipps/tipps.css`. `Tools/Tipps/Render-Tips.mjs` fotografiert jede Vorlage mit Chromium (Playwright) zweimal: `Setup/Tipps/<name>.png` mit 320 × 180 Pixeln (Anzeige auf der Karte bei 100 %, Pixel für Pixel) und `<name>@2x.png` mit 640 × 360 (ab 125 % Skalierung; Atlas rechnet beide bei abweichender Größe glatt um). Ein Bild gilt für helles und dunkles Thema: Es bringt seinen dunklen Editor-Grund und einen grauen Rand mit.

1. Vorlage anlegen oder ändern; Texte mindestens 11 px, nichts ragt über 320 × 180 hinaus.
2. `npm install --no-save playwright` und `npx playwright install chromium` (einmalig; oder eine vorhandene Installation über `NODE_PATH` bzw. `PLAYWRIGHT_BROWSERS_PATH`).
3. `node Tools/Tipps/Render-Tips.mjs` (alle) bzw. `node Tools/Tipps/Render-Tips.mjs referenzen` (einzelne).
4. Tipp in `Setup/tips.json` mit `"image": "Tipps\\<name>.png"` eintragen, dann `pwsh Tools/Check-Tips.ps1`.

Die Bilder im Repository sind mit den Schriften DejaVu Sans und DejaVu Sans Mono gerendert; unter Windows nimmt die Vorlage Segoe UI und Consolas, die Abstände weichen dann leicht ab.

## Optionale Geheimnisse

| Geheimnis | Wirkung |
|---|---|
| `SIGN_CERT_BASE64`, `SIGN_CERT_PASSWORD` | Signiert die EXE mit `signtool` (PFX als Base64), vermeidet SmartScreen-Warnungen |
