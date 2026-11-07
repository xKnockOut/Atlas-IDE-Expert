# Roadmap

Stand 07.11.2026, Aufteilung festgelegt. Grundlage sind die 494 offenen Issues; etwa 178 davon sind umgesetzt
und warten nur auf den Delphi-Build und den Handtest. Übersicht mit allen Issues je Version: `planung/roadmap-2026-11-07/`
im Projektordner. Atlas bleibt beim RAD-Studio-Plugin, andere Editoren sind nicht geplant.

## 2.0.0: Umbau abschließen

Keine neuen Funktionen mehr.

- `main-merging` mit Delphi bauen (0/0/0, Tests grün) und nach `main` bringen; Handtests.
- Vor dem Release, weil sie Namen, Einstellungen oder Module ändern: #1883 (KI-neutrale Benennung), #1891 (Modul
  Versionsverwaltung), #1888 (Modul KI-Assistenten). Optional #1885 (AtlasUpdate entfernen und reparieren).
- Fehler: #1477, #1480, #1751; Serverlast über PR #1847.
- Nach Build und Handtest schließen: #1454, #1455, #1456, #1755, #1756, #1458, #1440, #1442.

## 2.1: Editor, Navigation und Formular-Designer

- Lernende Schattentext-Vorschläge aus dem eigenen Code (#1890).
- Brotkrumen: #1759, #1760, #1763 bis #1769, #1784 bis #1787.
- Bedienung und IDE-Einbindung: #1884 (Einstellungen durchsuchen), #1889 (Maustasten Zurück/Vor), #1886 (F1-Hilfe),
  #1817, #1818, #1819, #1821, #1822.
- Formular-Designer: zuerst die Machbarkeit von Rückgängig (#1887), dann #603, #539, #606 bis #608, #729, #731, #738,
  #745, #748, #750; die übrige Designer-Reihe #726 bis #749 als zweite Welle.

## 2.2: Debuggen, Testen und Lecks

- Debuggen: #1878, #1820 und aus Epic #614 #577, #583, #584, #843, #851, #853, #863, #864, #869, #872, #895.
- Testen: #1873 (Test aus dem Debug-Halt), #1776, #1771, #1770, #1778, Prüfregeln #1780, #1781, #1882, #1879.
- Lecks: #1774, #1875, #1876, #1877, #1880.
- Zweite Welle: #1772, #1773, #1775, #1777, #1779, #1782, #1783, #1881, #1226, #275, #1460, #154, #305.

## 2.3: KI-Debugger, Team, Versionsverwaltung, CI

- KI-Assistenten debuggen in der laufenden IDE (#1874, braucht #1888).
- Versionsverwaltung: Merge-Konflikte (#1892, braucht #1891), #898, #513.
- CI: #1431 bis #1435, #107.

## 3.0: Plattform

Größere Schritte, die Schnittstellen ändern dürfen: Atlas-SDK (#1459), Komponenten-Werkbank (#1463), eigene Prüfregeln
(#73, #279, #280).

## Laufend

- Prüfregeln in jeder Version: #1345, #1126, #1112, #1136, #624, #1839, #1840, #145.
- Alles Übrige bleibt ohne Milestone und wird bei jeder Release-Planung neu gesichtet, dazu die Sammlung #1274.

## Aufräumen

- Alte Milestones v1.1.1, v1.2.0 und v1.2.1 schließen; ihre umgesetzten Issues kommen nach v2.0.0 zum Handtest.
- Label `handtest-offen` für umgesetzte Issues, die nur noch auf Build und Handtest warten.
