# 0010: Binärer Index-Cache mit String-Tabelle und Prüfsumme

- Status: Angenommen
- Datum: 2026-10-14
- Bezug: #79, #617 Startzeit großer Projekte, #492 Index-Cache und Inhalt, #184 Cache-Ordner, #616 gemeinsamer Bibliotheks-Cache, ersetzt ADR 0003

## Kontext

ADR 0003 legte den Cache als JSON-Datei fest, die immer ganz gelesen wird. Bei einem Projekt mit 1569 Units und rund 576.000 Symbolen kostete das Laden des JSON-Baums den größten Teil des Starts, und gleiche Texte (Container, Typnamen, Dateinamen) lagen tausendfach im Speicher. Mit #492 kamen je Symbol Signatur, Direktiven und XMLDoc-Kurztext dazu, je Unit die Verwendungen der Bezeichner; das hätte die Datei weiter vergrößert. Außerdem fiel eine abgeschnittene oder beschädigte Datei nicht sicher auf, und die Caches lagen ohne Ordnung nach IDE-Version in einem Ordner.

## Entscheidung

- **Binärformat** `ATLASIDX` mit Formatversion (`TIndexCache.FormatVersion` in `Atlas.Common.Index.Cache`; steigt bei jeder Formatänderung) und einer Prüfsumme (FNV-1a, 4 Byte) über alles hinter dem Kopf.
- **String-Tabelle:** Jeder Text steht einmal in der Datei; Units und Symbole verweisen per Nummer darauf. Nach dem Laden teilen sich gleiche Texte eine Instanz.
- **Zahlen als Varint** (vorzeichenbehaftete per ZigZag).
- **Blöcke je Unit mit Länge:** Beim Start liest der Server nur die Köpfe (Name, Datei, Zeitstempel, Hash, uses, Includes). Die Symbole einer Unit dekodiert er erst, wenn der Builder sie übernimmt; die Verwendungen stehen in einem eigenen Block und können bei knappem Speicher in der Datei bleiben.
- **Ablage** je IDE-Version und Projekt unter `%LOCALAPPDATA%\Atlas\Index\<IDE-Version>\<Projekt-Hash>\index-<Format>.atlasidx` (Formatversion im Namen, damit Server verschiedener Atlas-Versionen sich die Caches nicht gegenseitig überschreiben), die Bibliothek (RTL, VCL, FMX) getrennt unter `…\<IDE-Version>\Bibliothek\<Hash>\`, damit Projekte sie teilen.
- **Verwerfen statt reparieren:** Andere Version, falsche Prüfsumme, abgeschnittene Datei oder ein früheres Format verwerfen den Cache; der Grund steht im Protokoll, der Aufbau liest still neu.

Das Format beschreibt `docs/Architektur.md` (Abschnitt Cache-Format) und der Kopfkommentar von `Atlas.Common.Index.Cache`.

## Alternativen

- **JSON beibehalten (ADR 0003):** lesbar, aber zu langsam und zu groß; Teil-Laden ist mit `System.JSON` nicht möglich.
- **Zeilenformat mit Tabulatoren (Formatversion 10, Zwischenschritt in #617):** schneller als JSON, aber ohne geteilte Texte und ohne Überspringen einzelner Units.
- **SQLite:** Teilabfragen ohne eigenen Code, aber eine Abhängigkeit (FireDAC oder DLL) für einen Cache, dessen Köpfe ohnehin vollständig geladen werden.
- **Speicherabbild der Records:** am schnellsten, aber abhängig von Plattform, Compiler und Feldreihenfolge; jede Änderung an `TIndexSymbol` bräche alte Dateien unbemerkt.

## Folgen

- Der Start großer Projekte hängt vor allem an den Köpfen; Units, die das Projekt nicht braucht, kosten fast nichts.
- Mit einem Texteditor lässt sich der Cache nicht mehr prüfen. Untersucht wird über den Index selbst (`atlas.server.status`, MCP-Werkzeuge) und die Protokollzeile beim Verwerfen.
- Ändert sich `TIndexSymbol` oder die Reihenfolge der Felder, muss `FormatVersion` steigen, und `TAtlasWelcomeIndexFiles.FormatVersion` im Plugin mit (der Test `FormatVersionMatchesServer` prüft das); Tests lesen und schreiben das Format im Kreis.
- Alte Caches (`index-*.json`) räumt die Größenbegrenzung des Cache-Ordners zuerst weg.
