# Roadmap (Entwurf)

Stand 06.11.2026, nach Atlas 2.0.0. Entwurf zur Abstimmung: Reihenfolge und Zuschnitt sind Vorschläge, keine Zusagen.
Grundlage sind die offenen Issues (mehr als 300) und die Erfahrungen aus dem 2.0-Release. Leitlinie: Fehler und
Alltag vor neuen Funktionen, zuerst das RAD-Studio-Plugin.

## 2.0.x: Stabilisieren (laufend)

Nur Fehlerbehebungen, kurze Abstände.

- Rückmeldungen zu 2.0.0 aufnehmen, vor allem Update von 1.x und Delphi 12 aus dem Quelltext.
- Bau und Tests dauerhaft sauber: Leckmeldungen, 0/0/0 auf dem Beta-Stand.
- Inhalte aus dem früheren `main` prüfen und bei Bedarf zurückholen: Speicher bei Projektgruppen (.dcp je Prozess,
  gemeinsamer Suchpfad-Cache), Atlas-Suche unter Delphi 12, Schalter „Atlas-Probleme“, GetIt-Logo.
- Offene Fehler: #1440 (Willkommensseiten scrollen), #1477 (declared-not-implemented), #1480 (--timings),
  #1751 (TRegEx unter Linux).
- Sprache ohne `language`-Eintrag: Das Plugin soll die IDE-Sprache zuverlässig an den Server geben.
- Serverlast: lesende Befehle nebenläufig (PR #1847).

## 2.1: Prüfen und Compiler

Thema: Atlas meldet dasselbe wie Delphi, nur früher.

- Compilerregeln angleichen: #1382, #1383, #1380, #1381.
- Prüfregeln für die Klassenordnung: #1840, #1839.
- Klassenvervollständigung abrunden: #1838 (Umbenennen und Verschieben nehmen den Kommentar mit).
- Compilermeldungen, die als Prüfregel fehlen, nachziehen (z. B. E2010, H2443, E2035 durch verdeckte Windows-Funktionen).

## 2.2: Testen

Thema: Tests direkt in der IDE. Baut auf Stufe 7 auf.

- Fenster „Atlas-Tests“ (#1776), Fehler an der Assert-Zeile (#1771), veraltete Ergebnisse (#1770).
- Marke „getestet von“ (#1778), Lecks je Test (#1774).
- Prüfregeln für Tests: #1780, #1781.
- Später: betroffene Tests im Hintergrund (#1775), wackelnde Tests (#1773), Mutationstests (#1460).

## 2.3: Navigation und Editor

Thema: Brotkrumenleiste und Editorleiste ausbauen.

- Brotkrumen: #1759, #1763 bis #1769, #1784 bis #1787.
- Smarte Einrückung abschließen (#1827 ff.).
- IDE-Einbindung: #1817 (Projektverwaltung), #1818 (Marken folgen der Zeile), #1819 (Error Insight), #1821 (Objektgalerie).

## 2.4: Team und CI

Thema: Atlas außerhalb der IDE.

- GitHub Action `setup-atlas` (#1431), Ausgabe `--format github` (#1432), weitere Formate (#1433).
- Atlas prüft sich in der eigenen CI (#1434), weitere CI-Anbieter (#1435).
- Release-Ablauf: Delphi-Runner oder weiter lokales Paket; `-WhatIf` in `Publish-ReleasePackage.ps1`.

## 3.0: Plattform

Thema: Größere Schritte, die Schnittstellen ändern dürfen.

- Atlas-SDK für eigene Add-ons (#1459), aufbauend auf den Modulen aus 2.0.
- Komponenten-Werkbank (#1463).
- Andere Editoren (VS Code): erst nach Abschluss der Delphi-Schwerpunkte.

## Zu entscheiden

- Wie oft soll eine Version erscheinen, und bleibt es bei Vorabversionen vor jedem Release?
- Welches Thema zuerst: Prüfen (2.1) oder Testen (2.2)?
- Lohnt ein Delphi-Runner, damit Releases nicht mehr lokal gebaut werden müssen?
- Bereinigung der Issues: Viele sind in 2.0 erledigt, aber noch offen (z. B. #1454, #1455, #1478, #1519, #1755).
