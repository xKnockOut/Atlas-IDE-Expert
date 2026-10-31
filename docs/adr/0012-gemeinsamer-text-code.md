# 0012: Plugin ohne Atlas.Common; gemeinsamer Code in Atlas.Text

- Status: Angenommen; der Grundsatz „ein BPL“ ist ersetzt durch [ADR 0017](0017-funktions-packages.md), das Teilen über Atlas.Text bleibt
- Datum: 2026-10-15
- Bezug: ADR 0002 Package-Aufteilung, ADR 0006 IDE-Plugin, #406 Package-Struktur des Plugins, Code-Review D-01 bis D-06, D-10, K-02

## Kontext

ADR 0006 sah vor, dass das IDE-Plugin die Protokollschicht `Atlas.Common.JsonRpc.*` wiederverwendet. Tatsächlich ist das Plugin seit #406 eigenständig: ein einzelnes BPL, das die IDE ohne weitere Laufzeitpackages lädt, ohne Threads und Index des Servers im IDE-Prozess, ohne zweites BPL bei Installation und Update (die IDE hält geladene Packages fest).

Die Folge waren Kopien mit Drift. Das Code-Review zählte unter anderem:

- **D-01:** zwei UTF-8-Prüfungen im Plugin ohne die strengen Regeln des Servers (überlange Formen, Surrogate, über U+10FFFF), dazu wörtliche Kopien von `HasPrefix`, `ParseCodePage`, `IsBinaryForm` und der Codepage-Liste.
- **D-02:** die Anonymisierung des Fehlerberichts zweimal, nur in Kleinigkeiten verschieden.
- **D-03:** `LineBreakOf` neunmal wörtlich, `SplitLines` 13-mal mit sechs Bedeutungen, `IndentOf` siebenmal, `IsWordChar`/`IsIdentChar`/`IsIdentStart` 17-mal mit vier Bedeutungen, `DecodeEntities` zweimal (im Plugin nur fünf benannte Entities).
- **D-04:** URI-Umwandlung und Zeilen-/Offsetrechnung je Seite, im Plugin mit anderem Laufwerksbuchstaben und anderer Deutung eines Offsets im CRLF.
- **D-05:** Wortanfänge und Teilfolgen der Vervollständigung je Seite verschieden; der Server lieferte Einträge, die das Plugin beim Weitertippen sofort wegfilterte.
- **D-06:** Zeilenvergleich viermal (Vergleichen-Dialog, Probleme, MCP, Rückgängig).
- **D-10:** JSON mit Kommentaren je Seite (im Plugin endete `//` nur an LF) und zwei Versionsangaben.

## Entscheidung

1. Das Plugin requiret weiterhin nur `rtl`, `vcl`, `vclwinx` und `designide`. Es bindet weder `Atlas.Common` noch `Atlas.Windows` ein.
2. Code, den Server und Plugin brauchen und der nur die RTL braucht, liegt einmal im Package `Packages/Atlas.Text`: Zeilen und Positionen (`Atlas.Text.Lines`), Bezeichnerzeichen (`Chars`), Kodierungserkennung (`Encoding`), Anonymisierung (`Anonymize`), file-URIs (`Uris`), Zeilenvergleich (`Diff`), unscharfe Namensprädikate (`Fuzzy`), JSON mit Kommentaren (`Jsonc`), XML-Entities (`Entities`) und die Versionsangabe (`Product.Version`).
3. Server und Tests linken Atlas.Text statisch wie Atlas.Common (DCUs aus `Output/<Plattform>/<Konfiguration>/Dcu/Atlas.Text`); `Atlas.Common` requiret `Atlas.Text`. Das Plugin übersetzt die Units selbst mit (`contains Atlas.Text.X in '..\Atlas.Text\Source\…'`), der Installer nur `Atlas.Text.Product.Version`.
4. Bedingungen, damit eine Unit in zwei Packages stehen darf:
   - Kein Package requiret das jeweils andere, auch nicht indirekt; die IDE lädt `Atlas.Text.bpl` und `Atlas.Common.bpl` nie (beide `{$RUNONLY}`, nicht installiert).
   - Das Plugin enthält **alle** Units von `Atlas.Text.dpk` unter `contains` (sonst W1033).
   - Getrennte DCUs: Das Plugin sucht nicht in `Dcu/Atlas.Text`; Tests und Server binden Atlas.Text nicht als Quelltext ein.
   - Atlas.Text-Routinen sind zustandslos, ohne `inline` und ohne Standardparameter.
5. Die Protokollschicht wird **nicht** geteilt: Der Client im Plugin arbeitet mit einem Push-Puffer im Lese-Thread, der Server mit einem Pull-Stream; die Gemeinsamkeit wäre nur das Content-Length-Format.
6. Was je Seite bewusst verschieden bleibt:
   - ANSI-Dekodierung: Das Plugin liest ANSI ohne Vorgabe mit der Codepage des Systems wie die IDE, der Server mit eigener Windows-1252-Tabelle, damit er rechnerunabhängig ist. Gemeinsam ist die Erkennung (BOM, strenges UTF-8, Codepage-Namen, binäres Formular).
   - Punktzahlen der Vervollständigung: verschiedene Skalen (Server ordnet Tausende Symbole, das Plugin stufenweise mit Quell-Rang). Gemeinsam sind die Prädikate, ob ein Name passt.
   - Fassaden mit eigenen Typen (`TFileEncoding`, `TAtlasTextFile`, `TAtlasFileFormats`, `TLspTextChanges`) bleiben und leiten weiter.

`Tools/Check-PackageDependencies.ps1` prüft die Bedingungen aus Punkt 4 und sperrt neue Kopien der geteilten Routinen außerhalb von Atlas.Text (Kopien-Sperre mit begründeten Ausnahmen).

## Alternativen

- **Zweites BPL `Atlas.Text.bpl` für das Plugin:** verworfen. Der Installer müsste es mitliefern und registrieren, die Ladefolge wäre zu beachten, und die IDE hält es wie das Plugin fest, sodass Updates schwieriger werden.
- **Bewusste Kopien mit Gleichlauftests:** verworfen außer als Übergang; die Tests finden Drift erst hinterher, und bei 17 Fassungen von `IsWordChar` ist das nicht mehr beherrschbar.
- **Plugin requiret Atlas.Common:** verworfen aus den Gründen von ADR 0006 und #406 (Threads, Index und viele Units im IDE-Prozess, zweites BPL).

## Folgen

- Eine Quelle für Zeilen, Kodierung, URIs, Fuzzy-Regeln und Versionsangabe; Server und Plugin entscheiden gleich. Gleichlauftests (`Atlas.Core.Text.Agreement.Tests`) halten Kodierung, Vervollständigung und Anonymisierung fest.
- Sichtbare Änderungen im Plugin: strenges UTF-8, URIs mit kleinem Laufwerksbuchstaben (`file:///c%3A/…`), ein Offset zwischen CR und LF zählt zum Zeilenende, numerische Entities in Live-Templates, `//` in `settings.json` endet auch an CR, Wortanfänge auch nach „.“ und bei Kleinbuchstaben nach Ziffern.
- Die Projektgruppe baut `Atlas.Text` zuerst. Neue Units in Atlas.Text stehen in `Atlas.Text.dpk`/`.dproj` **und** in `Atlas.IDE.Expert.dpk`/`.dproj`; das Prüfskript meldet eine fehlende.
- `Atlas.Core.Vcs.*` bleibt das umgekehrte Muster (Plugin-Units, die der Server als Quelltext mitübersetzt).
