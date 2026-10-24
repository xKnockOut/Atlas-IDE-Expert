---
name: delphi-mit-atlas
description: Delphi/Object Pascal mit den Atlas-Werkzeugen bearbeiten. Verwenden, sobald es um .pas-, .dpr-, .dpk-, .dfm- oder .fmx-Dateien, Delphi-Typen, Units, Formulare oder Prüfregeln geht.
---

# Delphi mit Atlas

Atlas kennt das Projekt über seinen Symbolindex. Die Werkzeuge des MCP-Servers `delphi`
sind schneller und genauer als Textsuche und das Lesen ganzer Dateien.

## Vor dem Schreiben

1. Die Ressource `delphi://conventions` lesen: Regelprofil, Formatstil, Benennungsregeln
   und aktive Prüfregeln des Projekts. Neuen Code danach ausrichten.
2. Typen und Aufrufe nachschlagen statt zu suchen:
   - `find_symbol` statt Textsuche nach einem Namen
   - `get_declaration` für die Deklaration, auch aus RTL/VCL, samt Begründungen (`// WHY:`, `// HACK:` …)
   - `get_rationale` vor einem Umbau: warum eine Unit oder ein Symbol so gebaut ist (Begründungskommentare mit Zeile)
   - `get_type_hierarchy` für Vorfahren und Nachfahren
   - `find_references` bzw. `get_call_hierarchy` für Verwendungen und Aufrufe
   - `get_impact` vor einer Änderung an einer Methode oder einem Typ: betroffene Stellen über mehrere Ebenen und die Tests, die danach mit `run_tests` laufen sollten
   - `get_unit_outline` statt eine ganze Unit zu lesen
   - `get_dfm_info` bzw. `get_component_info` für Formulare und Komponenten

## Nach dem Schreiben

- Geplanten Code mit `check_code` prüfen, bevor er in die Datei geht
  (Syntax, Prüfregeln, nicht auflösbare Bezeichner).
- `get_diagnostics` für den Stand einer Datei oder des Projekts.
- `find_unused_code` vor dem Aufräumen: ungenutzte Member, Deklarationen und Units des Projekts; `get_unit_dependencies` für uses, Nutzer und Zyklen einer Unit, bevor sie verschoben oder aufgeteilt wird.
- `get_metrics` vor und nach einem Umbau: welche Methoden zu lang, zu tief verschachtelt oder zu komplex sind (Grenzwerte aus `atlas.json`).
- `get_todos` vor einer Aufgabe oder einem Release: offene `TODO`/`FIXME` des Projekts, gefiltert nach Kategorie (`category`), Person (`owner`), Unit oder Marke; `includeDone` zeigt erledigte.
- `get_architecture` vor Umbauten oder in fremdem Code: Teilsysteme, zentrale Units, Zyklen und Querverbindungen des Projekts; mit `unit` der Steckbrief einer Unit (wovon sie abhängt, wer sie braucht, ob sie ins Teilsystem passt); mit `compareWith` (gespeicherter Stand, etwa `architektur.json`) nach einem Umbau prüfen, ob neue Zyklen oder Querverbindungen entstanden sind.
- `find_path` bei „Wie hängt X mit Y zusammen?“ oder „Warum zieht diese Unit jene herein?“: ein Aufruf liefert die kürzeste Kette mit Kantenart und Datei:Zeile je Schritt, statt sich über `find_references` und `get_call_hierarchy` zu hangeln. „Kein Weg“ ist verlässlich; `[erschlossen]` heißt: über eine von mehreren Umsetzungen.
- Befunde mit `explain_finding` erklären lassen (Regel, Ausschnitt, Vorher/Nachher).
- `get_last_build` zeigt den letzten Build aus der IDE samt Compilermeldungen.
- `build_project` baut das Projekt in der laufenden IDE (auch in der Starter Edition ohne
  Kommandozeilen-Compiler) und liefert die Compilermeldungen; das Projekt muss dort offen sein.
- `run_tests` führt die DUnitX-Tests aus (vorhandene Test-EXE, mit `build: true` vorher in der IDE
  bauen) und liefert fehlgeschlagene Tests mit erwartetem und tatsächlichem Wert, Datei und Zeile;
  `tests` schränkt auf `Unit.Fixture` oder `Unit.Fixture.Methode` ein. Nach einer Änderung erst die
  betroffenen Tests, dann alle.

## Ändern

- Symbole nie per Suchen und Ersetzen umbenennen, sondern mit `rename_symbol`:
  Es ändert auch .dfm/.fmx und automatisch benannte Ereignis-Handler.
  Erst mit `dryRun: true` (Vorgabe) den Diff ansehen, dann mit `dryRun: false` schreiben.
- Korrekturen von Prüfregeln mit `apply_code_action`: ohne `title` auflisten, dann anwenden.
- Ist eine Datei in der IDE ungespeichert geändert, schreibt Atlas nicht; erst speichern lassen.
