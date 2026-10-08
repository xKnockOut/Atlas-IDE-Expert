# 0002: Aufteilung in Common, Windows und Anwendung

- Status: Angenommen
- Datum: 2026-10-07
- Bezug: #1 Projektgerüst, `docs/Architektur.md`

## Kontext

Der größte Teil des Servers ist reine Textverarbeitung. Windows-Abhängigkeiten (Registry, Pfad-API, Konsole, Debug-API) sind wenige, aber sie machen Code schwer testbar und an eine Plattform gebunden. Das Konzept „Rollenbasierte Kopplung und Kohäsion“ verlangt klare Ausgabeartefakte mit Importregeln.

## Entscheidung

- `BDLsp.Common`: frei von Windows und VCL.
- `BDLsp.Windows`: Windows-Adapter, frei von VCL.
- `BetterDelphiLSP`: Anwendung mit Komposition von Hand.

`Tools/Check-PackageDependencies.ps1` prüft die Regeln lokal und in der GitHub Action.

## Alternativen

- Ein einziges Projekt: einfacher, aber Windows-Code würde sich überall verteilen.
- Feinere Packages je Feature: mehr Verwaltung in `.dpk`/`.dproj` ohne erkennbaren Nutzen.

## Folgen

- Fachlogik ist ohne Windows testbar (auch mit FPC im Container).
- Schnittstellen für Windows-Dienste (`ILibraryPathProvider`, Pfad-Kanonisierung) müssen in Common deklariert und in der Shell verbunden werden.
