# Entscheidungsprotokoll (ADR)

Hier stehen Architekturentscheidungen mit Kontext, Entscheidung und Folgen. Eine Entscheidung wird nicht nachträglich umgeschrieben; wird sie ersetzt, bekommt sie den Status „Ersetzt durch NNNN“ und eine neue Datei erklärt die neue Entscheidung.

| Nr. | Titel | Status |
|---|---|---|
| [0001](0001-eigener-parser.md) | Eigener Parser statt DelphiAST | Angenommen |
| [0002](0002-package-aufteilung.md) | Aufteilung in Common, Windows und Anwendung | Angenommen |
| [0003](0003-index-cache-json.md) | Symbolindex-Cache als JSON-Datei | Angenommen |
| [0004](0004-nebenlaeufige-anfragen.md) | Lesende Anfragen nebenläufig auf Momentaufnahmen | Angenommen |
| [0005](0005-hybrid-modus.md) | Hybrid-Modus mit Embarcadero DelphiLSP | Offen |

## Vorlage

```markdown
# NNNN: Titel

- Status: Vorgeschlagen | Angenommen | Abgelehnt | Ersetzt durch NNNN
- Datum: JJJJ-MM-TT
- Bezug: Issues, PRs

## Kontext
Welches Problem, welche Randbedingungen?

## Entscheidung
Was wird gemacht?

## Alternativen
Was wurde verworfen und warum?

## Folgen
Was wird dadurch leichter, was schwerer?
```
