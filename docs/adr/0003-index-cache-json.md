# 0003: Symbolindex-Cache als JSON-Datei

- Status: Ersetzt durch [0010](0010-binaerer-index-cache.md)
- Datum: 2026-10-07
- Bezug: #15 Symbolindex, `docs/Architektur.md` (Cache-Format)

## Kontext

Ein vollständiger Indexaufbau mit RTL und VCL dauert spürbar. Beim nächsten Start sollen nur geänderte Dateien neu gelesen werden. Das Format soll ohne Zusatzbibliothek lesbar und bei Fehlern leicht zu untersuchen sein.

## Entscheidung

Eine JSON-Datei je Arbeitsbereich mit Formatversion, je Unit Zeitstempel und Inhalts-Hash, Symbole als Arrays mit kurzen Schlüsseln. Bei anderer Version oder kaputtem JSON wird der Cache verworfen und neu aufgebaut.

## Alternativen

- SQLite: schnelle Teilabfragen, aber Abhängigkeit (FireDAC oder DLL) und mehr Code für einen Cache, der ohnehin vollständig in den Speicher geladen wird.
- Binärformat: kleiner und schneller, aber schwer zu untersuchen und versionieren.

## Folgen

- `System.JSON` genügt; der Cache ist mit einem Texteditor prüfbar.
- Der Cache wird immer ganz gelesen und geschrieben. Wird das bei großen Projekten zu langsam, ist ein Wechsel über eine neue Formatversion möglich.

## Nachtrag (#617, 14.10.2026)

Die neue Entscheidung steht in [ADR 0010](0010-binaerer-index-cache.md).


Bei 1569 Units und rund 576.000 Symbolen kostete das Laden des JSON-Baums den größten Teil des Starts. Erst ersetzte ein Zeilenformat mit Tabulatoren das JSON (Formatversion 10), jetzt ein Binärformat mit String-Tabelle (Formatversion 11, Beschreibung in `docs/Architektur.md`, Abschnitt Cache-Format). Die Köpfe aller Units werden beim Start gelesen, die Symbole je Unit erst bei Übernahme in den Index. Zum Untersuchen dient der Index selbst (`atlas.server.status`, MCP-Werkzeuge), nicht mehr ein Texteditor.
