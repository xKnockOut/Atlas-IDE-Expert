---
name: bauen
description: Delphi-Projekt bauen und testen und das Ergebnis nach der 0/0/0-Regel zusammenfassen (0 Fehler, 0 Warnungen, 0 Hinweise, Tests grün). Verwenden bei /atlas:bauen oder wenn der Benutzer „bauen“, „kompilieren“, „Build“ oder „Tests laufen lassen“ sagt.
argument-hint: "[make|build|check] [Projekt] [--ohne-tests]"
---

# Bauen und testen

Argumente: `$ARGUMENTS` (alle optional). `make` (Vorgabe) übersetzt geänderte Units, `build` alles neu,
`check` nur die Syntax. Ein Projektname oder eine `.dproj` wählt das Projekt; `--ohne-tests` lässt die Tests weg.

## Wo gebaut wird

1. **Eigenes Bau-Skript des Projekts zuerst.** Gibt es `Tools/Build-Test.ps1` (so im Atlas-Repository), dieses
   Skript nehmen: `pwsh Tools/Build-Test.ps1` (mit `-SkipTests` bei `--ohne-tests`). Exit-Code 0 = grün,
   1 = Fehler, Warnung oder Hinweis, 2 = Tests rot, 3 = Umgebungsfehler. Es startet eine eigene IDE; nie eine
   fremde IDE beenden.
2. **Sonst über Atlas in der laufenden IDE** (auch in der Starter Edition ohne Kommandozeilen-Compiler):
   - `build_project` mit `mode` aus den Argumenten und ggf. `project`. Das Projekt muss in RAD Studio mit
     Atlas-Plugin offen sein; meldet das Werkzeug, dass keine IDE den Auftrag annimmt, den Grund wörtlich nennen
     und den Benutzer bitten, das Projekt zu öffnen.
   - Danach, wenn nicht `--ohne-tests` und der Build fehlerfrei war: `run_tests` (ohne `build`, das ist schon
     geschehen). Erst die Tests der geänderten Units (`tests`), dann alle.
3. **In einer Cloud-Sitzung (Linux)** gibt es weder Delphi noch die IDE. Das offen sagen. Im Atlas-Repository
   übersetzt `Tools/Linux/Build-AtlasServer.sh` wenigstens den Server mit Free Pascal; das ersetzt den
   Delphi-Bau nicht und ist nur ein Hinweis auf Syntaxfehler.

## Ergebnis

- Eine Zeile vorweg: **grün** nur bei 0 Fehlern, 0 Warnungen, 0 Hinweisen und allen Tests bestanden, sonst
  **rot** mit den Zahlen (z. B. „rot: 0 Fehler, 2 Warnungen, 1 Hinweis; Tests 812/814“).
- Danach jede Meldung als `Datei:Zeile: Code Text` und jeder fehlgeschlagene Test mit erwartetem und
  tatsächlichem Wert, Datei und Zeile.
- Hinweise und Warnungen gehören zum Ergebnis, nicht ins Kleingedruckte: Die Ursache im Code beheben, nicht die
  Meldung abschalten. Danach erneut bauen, bis 0/0/0 erreicht ist oder ein Punkt eine Entscheidung des Benutzers
  braucht.
