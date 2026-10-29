# 0016: Kein eigener Installer, Release-Paket von Hand einbinden

- Status: Angenommen
- Datum: 2026-10-29
- Bezug: ersetzt [ADR 0009](0009-installer.md) (#495); Zusammenführung von Prep-v1.2.0 mit main

## Kontext

Seit ADR 0009 gehörte der Installer `AtlasSetup.exe` zur Projektgruppe. Beim ersten Delphi-Bau von Prep-v1.2.0 (29.10.2026) hat Marco ihn entfernt: `Setup/AtlasSetup.*`, `Setup/Source`, `Tests/Setup`, der Eintrag in `Atlas.groupproj` und seine Regeln in `Tools/Check-PackageDependencies.ps1` sind weg. Die Daten unter `Setup` (Tipps, Vorlagen, Profile, Beispiele, `tips.json`) bleiben, sie gehören weiter ins Release-Paket.

## Entscheidung

- Atlas hat keinen eigenen Installer mehr.
- Das Release-Paket `atlas-ide-expert-<Version>.zip` behält den Aufbau des früheren Zielordners (`AtlasServer.exe`, `Win32\…bpl`, `Win64\…bpl`, Daten daneben). Es wird in einen festen Ordner entpackt und die BPL in der IDE über *Komponente › Packages installieren* eingetragen. Das Plugin findet Server und Daten weiter neben der BPL oder eine Ebene darüber.
- Einstellungen exportieren, importieren und zurücksetzen nur noch in der IDE (*Tools › Optionen › Atlas*, Befehlspalette); die Kommandozeile `AtlasSetup /exportSettings …` entfällt.

## Folgen

- `release.yml` baut und signiert keinen Installer mehr und packt das ZIP ohne `AtlasSetup.exe`.
- `docs/Installation.md`, `docs/RAD-Studio.md` und die READMEs beschreiben das Einbinden von Hand.
- Installation, Update und Deinstallation sind Handarbeit je IDE (die Alternative „Nur ZIP mit Anleitung“ aus ADR 0009). Eine Installation mit dem früheren Installer lässt sich weiter über die App-Liste von Windows entfernen.
