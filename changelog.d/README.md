# Changelog-Fragmente

Ein Pull Request ändert `CHANGELOG.md` nicht. Seine Einträge kommen in eine eigene Datei in diesem Ordner, benannt nach Issue und Stichwort, etwa `changelog.d/2169-bedingungen-vorausschauen.md`. Ohne Issue genügt der Name des Branches. Parallele Pull Requests schreiben so in verschiedene Dateien und kommen sich nicht in die Quere.

Aufbau wie ein Abschnitt in `CHANGELOG.md`:

```markdown
### Neu
- Bedingungen vorausschauen (#2169, `debug.predictConditions`, Vorgabe an): …

### Behoben
- …
```

- Erlaubte Überschriften: `Neu`, `Experimentell`, `Geändert`, `Behoben`, `Entfernt`, `Tests`.
- Ein Eintrag ist eine Zeile `- …`, wie bisher mit Markierung `<!-- whatsnew … -->` am Ende, wenn er auf die Karte „Neu in Atlas“ soll. Eingerückte Folgezeilen gehören zum Eintrag davor.
- Ein Pull Request darf mehrere Fragmente anlegen und sein eigenes Fragment später ändern.

`pwsh Tools/Update-Changelog.ps1 -Check` prüft die Fragmente (läuft in der CI, dort auch mit `-Base`: neue Einträge direkt in `CHANGELOG.md` sind ein Fehler). Beim Release übernimmt `Tools/Set-Version.ps1` die Fragmente unter `## [Unveröffentlicht]` und löscht sie. Testbauten zeigen sie auf der Karte „Neu in Atlas“ schon vorher (`Tools/Update-WhatsNew.ps1 -Unreleased`).
