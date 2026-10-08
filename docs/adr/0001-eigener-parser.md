# 0001: Eigener Parser statt DelphiAST

- Status: Angenommen
- Datum: 2026-10-07
- Bezug: #6 Lexer, #7 Fehlertoleranter Parser

## Kontext

Der Server braucht einen Syntaxbaum für Gliederung, Navigation, Hover, Faltbereiche und Prüfregeln. Code im Editor ist fast immer unvollständig. Positionen müssen in UTF-16-Codeeinheiten stimmen, weil LSP so zählt. Neue Sprachmerkmale (Inline-Variablen, mehrzeilige Strings, If-Ausdrücke in Delphi 13) sollen schnell nachziehbar sein.

## Entscheidung

Eigener Lexer und rekursiv absteigender Parser in `BDLsp.Common.Pascal`. Der Baum ist auch bei Syntaxfehlern vollständig: übersprungene Token stehen in `Error`-Knoten, Fehler in `Diagnostics`, der Parser setzt an Deklarations-, Mitglieds- und Anweisungsgrenzen wieder auf. Kommentare und Direktiven bleiben als Token erhalten.

## Alternativen

- DelphiAST: verbreitet, aber bricht bei fehlerhaftem Code ab, liefert Positionen nicht in UTF-16 und hinkt neuen Sprachmerkmalen hinterher. Eine fehlertolerante Erweiterung wäre ein dauerhafter Fork.
- Compiler-Ausgabe oder Embarcadero DelphiLSP: nicht als Baum verfügbar.

## Folgen

- Volle Kontrolle über Fehlertoleranz, Positionen und neue Syntax.
- Mehr eigener Code und eigene Tests für die Grammatik; Lücken fallen erst bei echten Projekten auf (Referenzprojekt #94, Robustheitstests).
