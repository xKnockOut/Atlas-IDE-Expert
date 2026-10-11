# 0006: IDE-Plugin als Code Insight-Manager für RAD Studio

- Status: Angenommen
- Datum: 2026-10-09
- Bezug: #175 RAD Studio als LSP-Client, #63 Hybrid-Modus (ADR 0005)

## Kontext

RAD Studio 13 kann über den Code Insight-Manager fremde LSP-Server einbinden. Mit AtlasServer funktionieren dabei `initialize`, die Dokumentsynchronisation, `documentSymbol` und `publishDiagnostics`. Syntaxfehler erscheinen als Error Insight.

**Hover zeigt die IDE für benutzerdefinierte Server aber nicht an.** Der Tooltip blitzt mit „Wird berechnet …“ auf und verschwindet. Belegt ist das so:
- **Anfragen:** Ein Mitschnitt des Verkehrs zwischen IDE und dem eingebauten DelphiLSP (über einen Vermittler, 09.10.2026) zeigt dieselben Hover-Anfragen wie bei AtlasServer.
- **Antworten:** DelphiLSP antwortet `{"contents":"…"}`, und die IDE zeigt das an.
- **Angleichen hilft nicht:** AtlasServer liefert inzwischen genau dieselbe Form, ohne `range`. Er meldet beim Start testweise sogar nur die Fähigkeiten von DelphiLSP (`textDocumentSync: 1`) und sendet keine Log- oder Fortschrittsnachrichten. Der Tooltip erscheint trotzdem nicht.
- **Ursache:** Die IDE behandelt benutzerdefinierte Server intern anders (`TLSPUserMgr` in `idelsp370.bpl`) als ihren eigenen DelphiLSP. Dem eigenen Server übergibt sie zudem `returnHoverModel: true`.

Codevervollständigung und Parameterhilfe sollen ebenfalls aus AtlasServer kommen. Der Compiler der Community Edition ist nur aus der IDE heraus nutzbar. AtlasServer braucht ihn nicht, Parser, Index und Namensauflösung sind eigen (ADR 0001).

Die Open Tools API bietet dafür:
- **Code Insight:** `IOTACodeInsightManager` (`ToolsAPI.pas`). Die IDE ruft den Manager für Vervollständigung (`#0`, `GetSymbolList`), Parameterhilfe (`#1`, `GetParameterList`), Browse/Strg+Klick (`#2`) und Symbolhinweis (`#3`) auf, Help Insight geht über `GetHelpInsightHtml`. Mit `IOTACodeInsightSelection` erscheint er in der Auswahl unter *Tools > Optionen*.
- **Zeichnen im Editor:** `INTACodeEditorEvents` (`ToolsAPI.Editor.pas`) mit `PaintLine`, `PaintText` und `PaintGutter` für eigene Markierungen im Editor.
- **Fehler:** `IOTAModuleErrors` liefert Fehler eines Moduls, ist aber zum Abfragen gedacht, nicht zum Liefern.

## Entscheidung

Ein Design-Time-Package `Atlas.IDE.Expert` (bis #406 `Atlas.IdePlugin`; Win32, denn `bds.exe` ist 32-Bit) meldet sich als **Code Insight-Manager für Delphi** an. Es ist ein **dünner LSP-Client**:

- Es startet AtlasServer als **eigenen Prozess** und spricht mit ihm JSON-RPC über stdin/stdout. Die Protokollschicht `Atlas.Common.JsonRpc.*` wird wiederverwendet.
- Es übersetzt Editor-Ereignisse in LSP-Nachrichten (`didOpen`, `didChange`, `didClose`) und die Aufrufe der IDE in Anfragen (`hover`, `definition`, `completion`, `signatureHelp`).
- Die gesamte Sprachlogik bleibt im Server. VS Code, Claude Code, Neovim und RAD Studio bekommen dieselben Ergebnisse.
- Stürzt der Server ab oder hängt er, startet das Plugin ihn neu. Die IDE läuft weiter.

Reihenfolge der Funktionen:
1. Hover (Symbolhinweis, Help Insight)
2. Gehe zu Definition (Browse, Strg+Klick)
3. Codevervollständigung, sobald der Server sie kann (#31)
4. Parameterhilfe, sobald der Server sie kann (#32)
5. Error Insight, selbst gezeichnet über `INTACodeEditorEvents`, dazu Meldungen im Meldungsfenster

Bis Schritt 5 umgesetzt ist, liefert der eingebaute LSP-Weg die Diagnosen, sofern er parallel eingerichtet bleibt.

## Alternativen

- **Nur der eingebaute Code Insight-Manager mit AtlasServer:** Er zeigt keinen Hover an (siehe Kontext). Vervollständigung und Parameterhilfe hängen am selben Client.
- **Plugin mit eigener Logik im IDE-Prozess** (`Atlas.Common` direkt geladen): Index, Parser und Hintergrund-Threads liefen im Speicher der 32-Bit-IDE. Ein Fehler darin reißt die IDE mit, und große Projekte wie die Gallery mit über 120.000 Symbolen belasten den knappen Speicher. Geladene Packages hält die IDE fest, Änderungen erfordern einen Neustart. Und es wäre ein zweiter Integrationsweg neben dem Server.
- **Kombination aus eingebautem Client und Plugin ohne Manager-Rolle:** Dann liefen zwei AtlasServer-Prozesse mit doppeltem Index und doppeltem Speicher.

## Folgen

- **Neues Package:** Die Projektgruppe bekommt ein Design-Time-Package für Win32. Es braucht Win32-Builds der Abhängigkeiten, die es schon gibt.
- **DelphiLSP inaktiv:** Ist der Manager ausgewählt, bedient er die gesamte Code Insight für Delphi. Ob unsichere Fälle an DelphiLSP weitergereicht werden, entscheidet ADR 0005 (#63).
- **Plugin baut sich nicht selbst:** Das Build-Plugin (`cc.ps1`) kann ein geladenes Design-Package nicht neu bauen, solange die IDE es hält. Zum Bauen wird es entladen (`unload-package`) oder in einer IDE gebaut, die es nicht geladen hat.
- **Tests:** Die Übersetzung zwischen Editor und LSP wird ohne IDE getestet, mit Fakes für die Open-Tools-API-Schnittstellen. Die Anzeige in der IDE wird von Hand geprüft.

## Fortschreibung: eigene Oberfläche und Datenquelle (#404, #408, 09.10.2026)

- **Eigene Fenster:** Atlas zeigt Vervollständigung, Parameter-Hint und Hover in eigenen, nicht fokussierenden Fenstern (#410) statt in den Listen der IDE. Der Code Insight-Manager bleibt angemeldet, damit die eingebaute Completion für Delphi-Quelltext unterdrückt ist (#407); `GetSymbolList` und `GetParameterList` liefern deshalb keine Daten an die IDE.
- **Datenquelle über eine Schnittstelle:** Die Oberfläche kennt nur `IAtlasCompletionProvider` (`Atlas.Core.Completion.Contract`). Eine Quelle liefert Teilmengen an eine Senke und meldet zum Schluss genau einmal `Complete`; nach `Cancel` oder einem neuen Query erreicht nichts mehr die alte Senke. `TAtlasCompletionProviders` führt mehrere Quellen zusammen.
- **Standardquelle ist der eigene Server** (ADR 0001): `TAtlasServerCompletionProvider` gleicht den Editortext im Hauptthread ab und fragt `textDocument/completion` im Hintergrund an, damit die IDE nie wartet. DelphiLSP wäre eine weitere Quelle (#63), Snippets ebenfalls (#51). Die Abwägung DelphiLSP gegen eigenen Parser ist damit zugunsten des eigenen Parsers entschieden, bleibt aber über die Schnittstelle umkehrbar.
- **Testdaten:** `TAtlasFixedCompletionProvider` liefert feste Einträge, auf Wunsch verzögert; damit lässt sich die Oberfläche ohne Server testen (#415) und ein langsamer Provider nachstellen (#409).
