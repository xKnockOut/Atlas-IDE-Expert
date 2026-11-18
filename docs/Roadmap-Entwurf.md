# Roadmap

Stand 18.11.2026. Je Version ein Meilenstein auf GitHub; die Zuordnung der Issues steht dort. Patch-Versionen
(2.x.y) enthalten nur Fehlerbehebungen. Ungeplante Ideen tragen das Label `backlog`, Vorschläge ohne Issue stehen in
#1274. Atlas bleibt beim RAD-Studio-Plugin, andere Editoren sind nicht geplant.

## 2.3.0: Fundament und KI-Assistent

- Fehler, offene Review-Befunde und Prüfregeln (#1345, #1126, #1112, #1895, #1896, #1477, #2425 und weitere).
- KI-Assistenten debuggen in der laufenden IDE (#1874 zuerst), MCP-Werkzeuge und Kontext für Assistenten
  (#2049 bis #2051, #2376, #2409, #2603, #2621, #2635, #2638, #2641 und weitere).
- Rest des Debugger-Epics #614 und neue Haltepunkt-Arten (#2548 bis #2550, #2552).

## 2.4.0: Team

- Tracker und YouTrack (#2434 bis #2457, #2461, #2643 bis #2646).
- Versionsverwaltung: Merge-Konflikte (#1892), Vergleich nach Klassen (#2055), Prüfung vor dem Commit (#2585) und
  weitere.
- CI: #1431 bis #1435, #107, #1902, „Nur neuer Code“ (#2374).

## 2.5.0: Tests und Build

- Tests: Zeitgrenzen, Mutationslauf, Zweigabdeckung, eigenschaftsbasierte Tests (#2397 bis #2408, #2617 bis #2629).
- Build, Build-Pipeline und Release-Wächter (#2297 bis #2303, #2618, #2624, #2631, #2634 bis #2642, #2659, #2661).
- Befunde im Alltag: Baseline-Ansicht, Fehlalarm melden, Vorschau vor dem Einschalten (#2569 bis #2614).

## 2.6.0: Editor, Navigation, Suche, Refactoring

- Editor und Navigation (#2558 bis #2564, #2654 bis #2656), Gliederung, Hover und Vervollständigung.
- Suche (#2284 bis #2294, #2607, #2610, #2613).
- Refactoring und XMLDoc (#2151 bis #2154, #2424, #2426 bis #2430).

## 2.7.0: Designer, Architektur, Bedienung und Hilfe

- Formular-Designer und Objektinspektor (#2410 bis #2415, #2554 bis #2568, #2575, #2660).
- Architektur und Analyse: Abhängigkeitsmatrix, Modulverträge, Package-Zuschnitt (#2567, #2572, #2599 bis #2601).
- Einstellungen, Befehlspalette und Hilfe (#2590 bis #2597, #2647 bis #2650, #2657).

## 3.0: Plattform

Größere Schritte, die Schnittstellen ändern dürfen: Atlas-SDK (#1459), Komponenten-Werkbank (#1463), eigene Prüfregeln
(#73, #279, #280). Dazu AtlasUpdate: Atlas entfernen und reparieren (#1885, erster Stand auf Branch `uninstall-1885`).

AtlasServer unter Linux als unterstützte Plattform (#2070): Release-Datei für Linux x86_64 (#2071), DUnitX-Tests
unter FPC/Linux in der CI (#2072), Doku zu Installation und Grenzen (#2073). Das IDE-Plugin bleibt Windows-only.

## Erschienen

- 2.0.0: Umbau auf Base und Module. 2.0.1: Optionen je Package.
- 2.1.0: Editor, Navigation und Formular-Designer.
- 2.2.0: Debuggen, Testen und Lecks (Release in Vorbereitung).
