# Code-Review: Atlas-IDE-Expert (Branch `main`)

Datum: 15. Oktober 2026 · Stand: Commit `4730b4a` („Übergabe: Branch-Kette zusammengeführt“) · Umfang: 428 Units, ≈ 151 000 Zeilen Produktivcode (ohne Tests), 254 Test-Units mit 2 263 `[Test]`-Methoden · Delphi 12 / VCL (Plugin) bzw. RTL-Konsole (Server)
Werkzeuge: nur Dateiwerkzeuge (Grep, Read, eigene Python-Skripte für Metriken und Importmatrix). Der Atlas-MCP-Server stand in dieser Sitzung nicht zur Verfügung; `get_diagnostics`, `get_last_build` und `check_code` konnten deshalb nicht genutzt werden (siehe Anhang 7.4).

Vorgehen: Das gesamte Projekt wurde strukturell erfasst (Metriken je Unit, Abhängigkeitsgraph, Importmatrix des Konzepts „Rollenbasierte Kopplung und Kohäsion“). Danach wurden die nach Größe, Kopplung und Mustertreffern auffälligen Units gelesen: Server-Kern (Completion, NameResolver, Index, Parser, References), Host und Protokollschicht (Shell, JsonRpc), Plugin-IDE-Schicht (CodeInsight, OTA-Notifier, LSP-Client, Zeitlimit), Plugin-UI-Schicht (Popups, Hover, Painter) sowie Rules/Editing und die Duplikate zwischen Server und Plugin. Jede Fundstelle im Bericht wurde gelesen; Laufzeitangaben sind Schätzungen aus dem Code, keine Messungen.

## Status (Stand 16.10.2026)

Alle Befunde sind erledigt. Commits laut `git log` (Kurz-Hash; mehrere = Schritte):

| Befunde | Status | Commit |
|---|---|---|
| P-01, P-02, P-05–P-07, P-12, P-13, P-17 | erledigt | `94bd93df` (Block C) |
| P-03, P-08, P-11 | erledigt | `50507754`, P-08/P-11 auch `94bd93df`, P-08 auch `8a4fc1a4` |
| P-04, P-09, P-10, P-15 | erledigt | `4a1cc965`, P-09 auch `667f9506` |
| P-14 / P-16 | erledigt | `a9c7f774` / `31dd64a3` |
| S-01 | erledigt | `7246fa97`, `575fa735`, `dd820036`, `170ebdc5` |
| S-02 / S-03 / S-04 | erledigt | `552e3cbb`, `777ae12f` / `daa1e03f` / `8a4fc1a4` |
| S-05 / S-06 / S-07 | erledigt | `9a957911` / `c58eea60` / `54812897`, `ab7a23e6`, `37248d3b` |
| D-01–D-06, D-10, K-02 | erledigt | `80c8a5f5`, D-04 auch `50507754`, D-10 auch `37248d3b` |
| D-07 / D-08 / D-09 | erledigt | `4a1cc965` / `777ae12f`, `8467f643` / `575fa735` |
| A-01, A-07, A-13, K-03 | erledigt | `71008a63` |
| A-02 | erledigt | `9a957911`, `2f0c0525` (Prüfskript `Tools/Check-MainThreadQueue.ps1`) u. a. |
| A-03 / A-04 / A-05 / A-06 | erledigt | `843b2aa2` / `abdba914` / `c58eea60` / `4f5fbdcc` |
| A-08 / A-09 / A-10 | erledigt | `bce17694` / `1b7cf147` u. a. / `d893a819` |
| A-11 / A-12 | erledigt | `f5473db0` / `5a2be0b1` |
| K-01 | erledigt | `57cc5b22` (Nachschlagetabellen in `SymbolIndex` tatsächlich eingeführt, Kopfkommentar stimmt jetzt) |
| K-04, K-05, K-06 | erledigt | `9e2d2187` |

---

## 1. Zusammenfassung

Atlas-IDE-Expert ist ein ungewöhnlich reifes Delphi-Projekt. Der Server ist ein vollständiger LSP-Server mit eigenem fehlertolerantem Parser, Symbolindex mit Binärcache, Namensauflösung inklusive Generics und Helpern, Kontrollflussanalyse und 79 Prüfregeln; das Plugin ist ein Design-Time-Package mit eigenem LSP-Client, fokuslosen Popups und einer durchdachten Absturzsicherung. Es gibt keine globalen Variablen, keine `with`-Blöcke, kein `Application.ProcessMessages`, keinen auskommentierten Code und keine offenen TODO-Kommentare. Alle 413 Package-Units tragen einen Kopfkommentar, der das Warum mit Issue-Nummer festhält. Konstruktor-Injektion über Interfaces ist durchgängig; Momentaufnahmen (`ITextDocument`) und ein Baum je Dokumentversion lösen das Nebenläufigkeitsproblem sauber. Das ist eine Codebasis, in der man gern arbeitet.

Die Probleme liegen nicht in der Sorgfalt, sondern im Wachstum. Vier Dinge wiegen schwer:

1. **Zwei kritische Befunde mit Absturzpotenzial.** Im Plugin startet und stoppt der Server unter bestimmten Umständen aus dem Zeitlimit-Arbeiterthread statt aus dem Hauptthread (A-01), inklusive OTA- und VCL-Aufrufen aus einem Nebenthread und einem Rennen um `FreeAndNil(FSession)`. Im Server extrahiert die Referenzsuche bei jedem Treffer-Token den kompletten Unit-Index neu (P-01) – `references`, `documentHighlight` und `rename` auf häufige Namen werden dadurch um Größenordnungen langsamer als nötig, obwohl das Gegenmittel (`PinTree`) drei Zeilen entfernt in `SemanticTokens` steht.
2. **Der heiße Pfad der Vervollständigung rechnet dasselbe fünf- bis fünfzehnmal.** `TLspCompletion.Collect` (716 Zeilen) und `Handle` extrahieren je Tastendruck mehrfach den Unit-Index, splitten den Text bis zu siebenmal in Zeilen, parsen die DFM von der Platte und kompilieren Regex-Muster neu (P-02, P-06, P-07, P-11). Dazu kommt ein systemisches Muster `Result := Result + [X]` in Schleifen – 399 Stellen in `Atlas.Common`, 243 im Plugin –, das an einem Dutzend Stellen mit großem n quadratisch wird (P-08).
3. **Die Entscheidung „Plugin ohne Atlas.Common“ hat Kopien erzeugt, die bereits auseinanderdriften.** Kodierungserkennung existiert viermal (zweimal allein im Plugin) mit unterschiedlicher UTF-8-Strenge, die Fehlerbericht-Anonymisierung ist eine 95-%-Kopie, Fuzzy-Matching hat in Server und Plugin verschiedene Regeln, und `LineBreakOf` steht siebenmal wörtlich identisch im Server (D-01 bis D-03). Diese Entscheidung ist nirgends als ADR festgehalten; ADR 0006 behauptet sogar das Gegenteil (K-02).
4. **Das Architekturkonzept wird formal eingehalten und materiell umgangen.** Die Importmatrizen sind mit 15 Verstößen bei 2 003 internen Imports fast sauber. Aber der Host besteht nur aus einer Shell; LSP-Handler, Prüfregeln, Refactoring-Befehle und Namensauflösung – rund 55 000 Zeilen Fachcode – liegen in einem „Platform-Package“, das laut Konzept nur technische Abstraktionen enthalten darf (A-08). Die Folge ist eine 2 687-Zeilen-`Shell.Composition`, die Komposition und Laufzeit-Orchestrierung vermischt (S-02), und ein 17-Feature-Zyklus in der IDE-Schicht des Plugins (A-09).

**Kernempfehlung:** Zuerst die beiden kritischen Befunde und die Quick Wins im heißen Pfad beheben (Vorschläge 4.1 und 4.2, zusammen wenige Tage, messbar in jeder Sitzung). Dann ein kleines gemeinsames Runtime-Package `Atlas.Text` einführen, das die Kopien zwischen Server und Plugin beendet (4.3). Die Regelengine bekommt einen Ableitungscache je Lauf (4.4). Erst danach lohnt der große Umbau, der den Fachcode in den Host zieht (4.5) – er ist richtig, aber nicht dringend, und er wird einfacher, wenn die Quick Wins die Hotspots vorher entflochten haben.

### Befunde nach Schweregrad und Kategorie

| Kategorie | Kritisch | Hoch | Mittel | Niedrig | Summe |
|---|:-:|:-:|:-:|:-:|:-:|
| P – Performance | 1 | 7 | 7 | 2 | 17 |
| S – Code-Smells | – | – | 5 | 2 | 7 |
| D – Duplikate | – | 3 | 5 | 2 | 10 |
| A – Architektur | 1 | 4 | 7 | 1 | 13 |
| K – Dokumentation | – | – | 3 | 3 | 6 |
| **Summe** | **2** | **14** | **27** | **10** | **53** |

Der Anhang enthält die Zählung der auffälligen Muster (7.1), die 15 Verstöße gegen die Importmatrix (7.2), die Methoden über 100 Zeilen (7.3) und die nicht geprüften Bereiche (7.4).

---

## 2. Projektübersicht

### 2.1 Ausgabeartefakte und Kennzahlen

| Ausgabeartefakt | Art | Units | Zeilen | Typen | Methoden (impl.) | Ø uses je Unit | Methoden > 60 Z. | `/// <summary>` | Tests (Units) |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| `Atlas.Common` | Runtime-Package, nur RTL | 230 | 83 235 | 486 | 3 542 | 7,3 | 164 | 2 204 | 175 |
| `Atlas.Windows` | Runtime-Package, RTL + Winapi | 11 | 1 182 | 10 | 54 | 3,3 | 2 | 25 | 5 |
| `Atlas.IDE.Expert` | Design-Time-Package (VCL, OTA) | 172 | 58 874 | 366 | 2 741 | 8,6 | 81 | 1 552 | 54 |
| `AtlasServer` (Shell) | Konsolenanwendung | 9 | 6 277 | 11 | 162 | 24,4 | 15 | – | 3 |
| `AtlasSetup` | VCL-Anwendung | 6 | 1 507 | – | – | – | – | – | 1 |

Dokumentationsquote (öffentliche Deklarationen mit direkt vorangestelltem `<summary>`): `Atlas.Common` 51 %, `Atlas.Windows` 50 %, `Atlas.IDE.Expert` 46 %. Unit-Kopfkommentar: 413 von 413 Units.

### 2.2 Die größten Units und ihre längsten Methoden

| Unit | Zeilen | Typen | Methoden | uses (intf/impl) | Längste Methode | Zeilen |
|---|--:|--:|--:|:-:|---|--:|
| `Atlas.Common.Lsp.Completion` | 4 307 | 5 | 100 | 13/32 | `TLspCompletion.Collect` | 716 |
| `Atlas.Common.Semantics.NameResolver` | 2 854 | 2 | 104 | 6/6 | `ExprSymbol` | 122 |
| `Shell.Composition` | 2 687 | 1 | 54 | 68/35 | `TServerComposition.Create` | 919 |
| `Atlas.Common.Pascal.Parser` | 2 366 | 1 | 197 | 2/4 | `ParseTypeBody` | 183 |
| `Atlas.Core.Lsp.Session` | 1 599 | 8 | 71 | 13/1 | `Initialize` | 118 |
| `Atlas.Common.Configuration.Parser` | 1 590 | 1 | 78 | 2/5 | `TValidator.Run` | 198 |
| `Atlas.Common.Index.Extractor` | 1 566 | 1 | 44 | 7/6 | `BlankInactive` | 237 |
| `Atlas.UI.Completion.Popup` | 1 486 | 1 | 68 | 18/4 | `PlaceAt` | 99 |
| `Atlas.Common.Semantics.ControlFlow` | 1 440 | 4 | 93 | 3/0 | `TFlowBuilder.Analyze` | 151 |
| `Atlas.IDE.Completion.Editor` | 1 386 | 1 | 71 | 19/27 | `Commit` | 156 |
| `Atlas.IDE.CodeInsight.Manager` | 1 350 | 1 | 76 | 15/17 | – | 75 |
| `Atlas.Common.Pascal.XmlDoc` | 1 308 | 4 | 65 | 1/2 | `TXmlDocParser.Build` | 165 |
| `Atlas.UI.Settings.Page` | 1 256 | 3 | 44 | 20/4 | `Create` | 228 |
| `Shell.Workspace` | 1 148 | 1 | 39 | 19/14 | `StartIndex` | 287 |
| `Atlas.UI.Hover.Tip` | 1 051 | 3 | 39 | 14/8 | `Render` | 557 |
| `Atlas.Core.Documentation.Layout` | 1 025 | 7 | 59 | 2/2 | `Build` | 173 |
| `Atlas.IDE.CodeInsight.Composition` | 984 | 0 | 63 | 0/54 | `RegisterFeatures` | 169 |

Sechs Units liegen über 1 500 Zeilen; 262 Methoden sind länger als 60 Zeilen (247 in den Packages, 15 in der Shell). Die vollständige Liste der Methoden über 100 Zeilen steht in Anhang 7.3.

### 2.3 Abhängigkeiten, so wie sie sind

```text
Ausgabeartefakte:
  AtlasServer (Shell) ──► Atlas.Windows ──► Atlas.Common ──► RTL
        │                                      ▲
        └──────────────────────────────────────┘
  Atlas.IDE.Expert (Plugin) ──► RTL, VCL, designide      (kein Atlas.Common – bewusst, siehe K-02)
  AtlasSetup ──► RTL, VCL (+ Versions-Unit des Plugins)

Schichten in Atlas.Common (Feature → Feature, nur nach unten, eine Ausnahme):
  Lsp (57 Units, 20 k Zeilen)  ──► Semantics, Index, Pascal, Rules, Editing, Dfm, Projects, Configuration, Documents, JsonRpc, Logging, Diagnostics
  Mcp (8)                      ──► Lsp, Rules, Editing, Index, Semantics, Dfm, Compiler
  Rules (41, 15 k)  ◄────────►  Editing (43, 16 k)      ← einziger Zyklus im Server (A-11)
  Semantics (4, 4,6 k)         ──► Index, Pascal, Documents, Diagnostics
  Index (13, 5,4 k)            ──► Pascal, Projects, Documents
  Pascal (9, 6 k)              ──► Documents
  Projects, Configuration, Documents, JsonRpc, Logging, Compiler, Dfm, Diagnostics ──► RTL

Schichten im Plugin (ADR 0006):
  Atlas.IDE.*  (OTA, 17 Features)  ──► Atlas.UI.*, Atlas.Core.*     ← alle 17 IDE-Features bilden einen Zyklus (A-09)
  Atlas.UI.*   (VCL-Fenster)       ──► Atlas.Core.*
  Atlas.Core.* (ohne VCL/OTA)      ──► RTL                           ← 5er-Zyklus Completion/Editor/Lsp/Problems/Results
```

Stark zusammenhängende Komponenten auf Feature-Ebene (Tarjan): `Atlas.Common.Editing` ⇄ `Atlas.Common.Rules`; `Atlas.Core.{Completion, Editor, Lsp, Problems, Results}`; alle 17 `Atlas.IDE.*`-Features. Außerhalb dieser drei Gruppen ist der Graph azyklisch.

### 2.4 Die Architektur, wie sie tatsächlich umgesetzt ist

Der Server ist ein Host mit genau einer Rolle: `Application/Source` enthält nur `Shell/`. `TServerComposition` (eine Klasse, 69 Felder) erzeugt alle Dienste und ≈ 40 LSP-Handler von Hand, hält jeden Handler als konkretes Feld, registriert ihn am `TJsonRpcDispatcher` und übernimmt daneben Workspace-Verwaltung, Compile-Loop, Einstellungsauflösung je URI, Bugreport und Dateibeobachtung. Es gibt keine `Foundation`, kein Host-`Core`, keine Host-`Adapters`, keine `Hosting`-Rolle in irgendeinem Feature und nur eine einzige `Composition`-Unit im gesamten Projekt (`Atlas.IDE.CodeInsight.Composition`). Das Konzept wird auf Unit-Ebene (Rollenbezeichner, Importmatrizen) diszipliniert befolgt; auf Host-Ebene ist es nicht angekommen.

Die Ablaufarchitektur ist dagegen vorbildlich dokumentiert und im Code wiederzufinden: Lese-Thread (nur Interfaces, `FreeOnTerminate`), Run-Thread für Notifications und synchrone Anfragen, `TTask`-Pool für nebenläufige Anfragen mit Abbruchtoken, Index-Thread je Workspace mit Builder-Übergabe per Nutzerzähler. Im Plugin: alles OTA/VCL im Hauptthread, Lese-Thread des Clients kennt die Sitzung nicht, Datenquellen in Arbeiterthreads mit hartem Zeitlimit, gemeinsames Abbruchsignal `TAtlasShutdown`. Genau an den Nahtstellen dieser Threads liegen die beiden kritischen Befunde.

---

## 3. Befunde

Jeder Befund trägt Kategorie, Schweregrad (Kritisch/Hoch/Mittel/Niedrig) und Aufwand (S < 1 h, M halber bis ganzer Tag, L mehrere Tage, XL Umbauprojekt). Innerhalb jeder Kategorie sind die Befunde nach Schweregrad sortiert. Zeilenangaben beziehen sich auf den Stand des geprüften Commits.

### 3.1 Performance

#### P-01 · Referenzsuche extrahiert je Treffer-Token den kompletten Unit-Index neu · Schweregrad: Kritisch · Aufwand: S
**Fundstelle:** `Packages/Atlas.Common/Source/Lsp/Atlas.Common.Lsp.References.pas`, Zeile 155–168, `TLspReferences.InTree`; gleiches Muster `Atlas.Common.Lsp.DocumentHighlights.pas` 141–147; Ursache in `Atlas.Common.Semantics.NameResolver.pas` 1942–1953 (`Prepare`) und 2317–2330 (`TreeUnit`), `Atlas.Common.Lsp.Definition.pas` 131, 138, 172–173 (`Targets`).
**Beobachtung:**
```pascal
for Token in ATree.Tokens do
begin
  if (Token.Kind <> TPascalTokenKind.Identifier) or not (SameText(CleanName(Token.Text), AName) or
    SameText(CleanName(Token.Text), AlternativeName(AName))) then
    Continue;
  if ACancellation <> nil then
    ACancellation.ThrowIfCancellationRequested;
  Candidate := TLspDefinition.Targets(AResolver, AIndex, ATree, AFileName, Token.StartPos, True);
  if (Length(Candidate) > 0) and SameTarget(Candidate[0], AWanted) then
    Result := Result + [TTextRange.Create(Token.StartPos, Token.EndPos)];
end;
```
In `TNameResolver.Prepare` (1950–1953) gilt: ist der Baum nicht gepinnt, läuft `TreeUnit` → `TIndexExtractor.Extract` über den **ganzen** Baum – alle Knoten, je Symbol Signatur per `TStringBuilder`, XmlDoc-Kurztext, Parameterinfo. `Targets` ruft `Prepare` indirekt über `Resolve`; bei Routinen extrahiert `Targets` ein zweites Mal (Definition 172–173). `InTree` wird für jede Projektdatei aufgerufen, in der der Name vorkommt.
**Warum das ein Problem ist:** Für `Create`, `Free` oder einen Feldnamen mit 100 Vorkommen in einer 3 000-Zeilen-Unit bedeutet das ≈ 200 vollständige Index-Extraktionen je Datei, über 200 Projektdateien. Betroffen sind `textDocument/references`, `documentHighlight` (bei jedem Cursorwechsel), `rename` (Rename 242/272 → Find), der Referenzzähler in `codeLens` (311) und `Hierarchies` (427). `SemanticTokens.Collect` zeigt in Zeile 263/343 bereits das Gegenmittel: `PinTree`/`UnpinTree` um die Token-Schleife.
**Empfehlung:** In `InTree`, `DocumentHighlights.Collect` und `Find` (für den geparsten Fremdbaum) `AResolver.PinTree(ATree, AFileName); try … finally AResolver.UnpinTree; end;` um die Token-Schleife legen. Mittelfristig soll `TLspDefinition.Targets` den gepinnten `TUnitIndex` des Resolvers verwenden statt selbst zu extrahieren. Ein Memo nach Baumadresse ist keine Alternative: `References` gibt Bäume frei, Adressen werden wiederverwendet.
**Konfidenz:** hoch für den Mechanismus (Code gelesen); der Faktor ist eine Schätzung.

#### P-02 · Vervollständigung: Unit-Index und Hilfsstrukturen werden je Tastendruck 5–15-mal neu berechnet · Schweregrad: Hoch · Aufwand: S (Pin) / M (Request-Kontext)
**Fundstelle:** `Atlas.Common.Lsp.Completion.pas`, `Collect` 2024–2028, `Handle` 2309–2514; `Extract`-Aufrufe 1141, 2938, 3014, 3142, 3334, 3495, 3624, 3746, 3898; `Analyze` 2007, 3298, 3434, 3719, 4282; `TextLines` 2719, 3134, 3439, 3570, 3619, 3855, 4131.
**Beobachtung:**
```pascal
if Context.Kind in [TCompletionContextKind.Member, TCompletionContextKind.Scope] then
  Expected := ExpectedType(AResolver, ATree, AFileName, APosition);
// Viele Typprüfungen auf demselben Baum: einmal auswerten.
if Expected <> '' then
  AResolver.PinTree(ATree, AFileName);
```
**Warum das ein Problem ist:** Gepinnt wird nur, wenn ein erwarteter Typ existiert. In der häufigsten Lage (freie Anweisung, Deklaration, Klassenrumpf) ist `Expected = ''`, und `Handle` arbeitet als 14-stufige `if … then Exit(ToJson(…))`-Kette, in der `EnumItems`, `ComponentItems`, `InterfaceItems`, `MemberCandidates`, `AddPostfix` und `DeclareItems` jeweils den Unit-Index neu extrahieren, das Dokument bis zu siebenmal in Zeilen splitten (jede Zeile wird kopiert) und `Analyze` fünfmal ausführen – obwohl `Handle` in Zeile 2348 das `ITextDocument` mit fertigem Zeilenindex in der Hand hat und nur `Document.Text` weiterreicht.
**Empfehlung:** In `Handle` direkt nach `Resolver := TNameResolver.Create` ein `Resolver.PinTree(Tree, Path)` mit `UnpinTree` im `finally`; die Bedingung in `Collect` entfällt dann. Zweiter Schritt (siehe Vorschlag 4.2): ein `TCompletionRequest`-Record (Baum, Pfad, Position, Kontext, `ITextDocument`, lazy `UnitIndex`, lazy `LineBreak`) an alle `*Items`-Methoden reichen.
**Konfidenz:** hoch (Aufrufpfade gelesen); Ersparnis je Extraktion einige Millisekunden bei großen Units (Annahme).

#### P-03 · Prüfregeln: jede Regel baut dieselben Vorbereitungsdaten neu, 79 Regeln laufen 79 eigene Baumdurchläufe · Schweregrad: Hoch · Aufwand: M
**Fundstelle:** `Atlas.Common.Rules.Builtin.Components.pas` `Prepare` 439–445 → `TComponentModel.Create` 157–169 (in 6 Regeln: 466, 556, 621, 680, 788, 860); `Builtin.Inheritance.pas` `TAncestry.Create` 132–137 → `TIndexExtractor.Extract` (in 4 Regeln, 386–394); `Builtin.DfmProperties.pas` 400; `TFlowSignatures.FromTree` in `Capture` 463, `Flow` 203/287/426, `Unused` 808; `TControlFlowGraph.Build` in `Capture` 499, `Flow` 214/318/429, `Unused` 777; `Unused.pas` `CollectRoutines` 480, 635, 806; `Concurrency.pas` `ThreadClasses` 401 und 796. Engine: `Atlas.Common.Rules.Engine.pas` 262–283.
**Beobachtung:** Der Baum selbst wird korrekt einmal geparst und über `TRuleContext.Tree` an alle Regeln gereicht. Aber `TSyntaxNode` bietet nur `ChildCount`/`FindChild` (`Pascal.SyntaxTree.pas` 65–77) – es gibt keinen Visitor. In 12 Builtin-Units stehen 47 rekursive `for … ANode.ChildCount - 1`-Schleifen; 35 Stellen starten bei `AContext.Tree.Root`.
**Warum das ein Problem ist:** Pro geprüfter Datei entstehen mindestens 11 vollständige `TUnitIndex`-Extraktionen, 5 Signaturtabellen, 6 Komponentenmodelle, 2 Thread-Klassenlisten und je Routine bis zu 4 Kontrollflussgraphen – alle aus demselben unveränderlichen Baum. Die Diagnose läuft bei jedem Tastendruck (Pull-Diagnostics mit Debouncing) und bei `workspace/diagnostic` über alle Projektdateien; die Kosten skalieren mit Regelanzahl × Dateigröße statt mit Dateigröße.
**Empfehlung:** `TRuleContext` um einen Ableitungscache ergänzen – das Muster existiert bereits als `ITextDocument.Derived` in `Documents.TextDocument.pas` 188–205 – und `UnitIndex`, `Routines`, `FlowSignatures`, `ComponentModel`, `ThreadClasses`, `CodeTokens` einmal je Lauf erzeugen. Dazu ein Visitor `TSyntaxNode.Walk(const AVisit: TFunc<TSyntaxNode, Boolean>)`, damit Regeln sich einen Durchlauf teilen können (Vorschlag 4.4).
**Konfidenz:** hoch.

#### P-04 · Zwei Timer lesen den gesamten Editorpuffer ≈ 11-mal pro Sekunde, auch ohne Tastendruck · Schweregrad: Hoch · Aufwand: M
**Fundstelle:** `Packages/Atlas.IDE.Expert/Source/IDE/Problems/Atlas.IDE.Problems.Controller.pas` 377–380 (Intervall 250 ms), 547–558 (`Tick`); `IDE/InlayHints/Atlas.IDE.InlayHints.Editor.pas` 109 (Intervall 150 ms), 168–180 (`Tick`); `IDE/Editor/Atlas.IDE.Editor.Buffer.pas` 35–57 (`Text`).
**Beobachtung:**
```pascal
if (View <> nil) and (View.Buffer <> nil) and IsSource(View.Buffer.FileName) then
begin
  FileName := View.Buffer.FileName;
  Key := TAtlasProblemStore.Key(FileName);
  Text := TAtlasEditorBuffer.Text(View.Buffer);
  // Markierungen wandern mit, bevor neue Diagnosen da sind.
  if not FTexts.TryGetValue(Key, Known) or (Known <> Text) then
```
`TAtlasEditorBuffer.Text` liest den Puffer über `IOTAEditReader` in 64-KB-Stücken mit `SetLength(Bytes, Length(Bytes) + Count)` je Stück (das Kopieren wächst quadratisch mit der Dateigröße), dekodiert UTF-8 und vergleicht anschließend die ganze Zeichenkette.
**Warum das ein Problem ist:** Das geschieht im Hauptthread, unabhängig von Tipp- oder Fokusaktivität, solange ein `.pas` vorn liegt – auch bei inaktiver IDE. Bei Units von 1–2 MB (in Altprojekten üblich) sind das pro Sekunde zweistellige Megabyte Kopier- und Dekodierarbeit im UI-Thread, die der Einfrier-Wächter mitmisst. Die Inlay-Hints sind standardmäßig aus, der Probleme-Timer nicht.
**Empfehlung:** Einen gemeinsamen Puffer-Snapshot (Datei, Text, Stand) einführen, der höchstens einmal je Tick-Zyklus und nur bei gesetztem Dirty-Flag gelesen wird; das Flag setzt der bereits abonnierte `INTAEditServicesNotifier.EditorViewModified` (`Completion.Editor` 370–389). `Bytes` vorab auf die Puffergröße dimensionieren oder in einen `TBytesStream` schreiben. Bei `Application.Active = False` Timer aussetzen.
**Konfidenz:** hoch für das Verhalten; die Kostenangabe ist eine Schätzung.

#### P-05 · Namensauflösung: jeder Lookup ist ein linearer Scan über alle Symbole einer Unit, je Vorfahrenstufe · Schweregrad: Hoch · Aufwand: M–L
**Fundstelle:** `Atlas.Common.Semantics.NameResolver.pas` 773–804 `LookupInUnit`, 806–818 `LookupGlobal`, 1110–1161 `FindMembers`, 2062–2097 `CollectMembers`, 1055–1108 `HelperFor`, 2383–2407 `DeclaredMember`; `Atlas.Common.Index.SymbolIndex.pas` 29–31 (nur `FFiles`, `FUnitFiles`).
**Beobachtung:**
```pascal
for Symbol in OwnerUnit.Symbols do
  if SameText(Symbol.Container, TypeName) and SameText(Symbol.Name, AName) then
  begin
    if Hidden or not IsVisible(Symbol, OwnerUnit, Current) then
    ...
if not AncestorOf(Current, Ancestor) then
  Exit;
Current := Ancestor;
```
**Warum das ein Problem ist:** `TUnitIndex.Symbols` ist ein flaches Array ohne Namens- oder Container-Verzeichnis; `for … in` kopiert zudem jedes `TIndexSymbol`-Record mit ≈ 12 verwalteten Feldern. Ein Mitgliederlookup auf einem `TForm`-Nachfahren durchläuft neun Vorfahrenstufen (`Vcl.Forms`, `Vcl.Controls`, `System.Classes`, `System` …) mit je `SameText` über tausende Symbole. `LookupGlobal` für einen nicht-lokalen Namen scannt alle uses-Units (≈ 30 × mehrere tausend Symbole) plus je Unit ein `FIndex.FindUnit` unter Lock. Jeder `Resolve` – Hover, Definition, `semanticTokens/full` mit tausenden Bezeichnern, Completion-Scope – zahlt das.
**Empfehlung:** Je Unit ein verzögert aufgebautes Verzeichnis `TDictionary<string, TArray<Integer>>` (Schlüssel `UpperCase(Container + '.' + Name)`, Werte Positionen in `Symbols`) als Teil des unveränderlichen Snapshots; `LookupInUnit`/`FindMembers`/`CollectMembers` greifen darüber zu. Kleinerer erster Schritt: ein Memo je Resolver-Instanz (der Resolver lebt nur eine Anfrage) und Index-Zugriff statt `for … in`, wie `TSymbolIndex.Locations` (243) es bereits begründet.
**Konfidenz:** hoch (Struktur); Kostenschätzung Annahme.

#### P-06 · `ComponentItems` liest und parst die .dfm bei jedem Scope-Tastendruck in einer Formular-Unit · Schweregrad: Hoch · Aufwand: S–M
**Fundstelle:** `Atlas.Common.Lsp.Completion.pas` 3296–3311, 3319–3331, 3371 (`ComponentItems`), Aufruf aus `Handle` 2430; `SenderItems` 3464–3472 wiederholt den Block; `Shell.Composition.pas` 1711–1726 (`ReadSourceText`).
**Beobachtung:**
```pascal
Document := nil;
for FormFile in TFormFiles.FormFiles(AFileName, AText) do
  if AReadText(FormFile, FormText) then
  begin
    Document := TDfmParser.Parse(FormText);
    if Document.Root <> nil then
      Break;
    FreeAndNil(Document);
  end;
```
**Warum das ein Problem ist:** `AReadText` lädt eine nicht geöffnete `.dfm` von der Platte (`TFileEncoding.LoadFromFile`) und parst sie vollständig – DFMs mit eingebetteten Bildern sind oft hunderte Kilobyte – bei jedem Tastendruck ohne Punkt, **bevor** geprüft ist, ob der Cursor überhaupt in einer Methode der Formularklasse steht. Dazu bis zu drei `ResolveChain`-Proben (je Extraktion, P-02) und `AItems := AItems + [Item]` über alle Komponenten (`TCompletionItem` hat 22 verwaltete Felder).
**Empfehlung:** DFM-Dokument je (Dateiname, Zeitstempel bzw. Dokumentversion) in `TLspCompletion` cachen – `ReadCached` 624–655 und `FCacheLock` existieren bereits. Reihenfolge drehen: erst über den gepinnten Unit-Index prüfen, ob `Context.Offset` in einer Formularmethode liegt, dann laden. `SetLength(AItems, Length(Components))` mit Zähler statt Append.
**Konfidenz:** hoch.

#### P-07 · `OverrideItems` liest die Quelldatei des Vorfahren je Kandidat erneut und splittet sie je Kandidat in Zeilen · Schweregrad: Hoch · Aufwand: S
**Fundstelle:** `Atlas.Common.Lsp.Completion.pas` 3022–3028 (`OverrideItems`); Gegenstück richtig gelöst in `InterfaceItems` 3180–3190.
**Beobachtung:**
```pascal
for Candidate in AResolver.OverridableMembers(UnitIndex, TypeName) do
begin
  if SameText(Candidate.FileName, AFileName) then
    Source := AText
  else if not (Assigned(AReadText) and AReadText(Candidate.FileName, Source)) then
    Continue;
  Declaration := DeclarationOf(TextLines(Source), Candidate.Range);
```
**Warum das ein Problem ist:** Für `TForm`-Nachfahren liefert `OverridableMembers` 100–150 Methoden aus `Vcl.Forms`, `Vcl.Controls`, `System.Classes`. Je Kandidat wird die Datei von der Platte geladen und mit `TextLines` komplett zerlegt (`Vcl.Controls.pas` ≈ 20 000 Zeilen) – hundertmal dieselbe Datei, bei jedem Zeichen, das der Benutzer hinter `procedure ` tippt. `InterfaceItems` daneben lädt nur bei Dateiwechsel.
**Empfehlung:** Wie in `InterfaceItems` nur bei Wechsel von `Candidate.FileName` neu lesen und splitten; besser `TIndexSymbol.Signature` (im Index vorhanden, Extractor 283) über `TResolvedSymbol` durchreichen – dann entfällt das Lesen ganz. Beide Methoden auf eine gemeinsame Hilfsfunktion `DeclarationFor(Candidate, Cache)` zusammenziehen.
**Konfidenz:** hoch.

#### P-08 · `Result := Result + [X]` in Schleifen – die Stellen, an denen n groß wird · Schweregrad: Mittel · Aufwand: S
**Fundstelle:** Muster projektweit: 399 Stellen in `Atlas.Common`, 243 im Plugin (Anhang 7.1). Mit großem n: `Atlas.Common.Lsp.References.pas` 181–186 (`Find.Add`: Referenzen projektweit, 10 000+), 208–212 (`Searched + [FileName]` plus `IndexText` = O(Dateien²)), 235–240 (`Filtered`); `Atlas.Common.Lsp.Completion.pas` 2273–2281 (`WithoutKeywords`, bis 1 000 Items à 22 verwaltete Felder je Tastendruck); `NameResolver.pas` 2326–2328 (`TreeUnit`, Include-Symbole), 2437–2439, 2459–2485; `Rules.Builtin.Security.pas` 90–101 (`CodeTokens`: alle Tokens der Datei, siebenmal je Prüfung); `Rules.Builtin.Unused.pas` 179; `Lsp.Hierarchies.pas` 375/385; `Lsp.DocumentHighlights.pas` 162/206; `Semantics.ControlFlow.pas` 309/1321/1350.
**Beobachtung:**
```pascal
for Range in ARanges do
begin
  Location.FileName := AFile;
  Location.Range := Range;
  Result := Result + [Location];
end;
```
**Warum das ein Problem ist:** Jede Konkatenation legt ein neues Array an und kopiert alle bisherigen Elemente inklusive Refcount-Inc/Dec je verwaltetem Feld. Bei 10 000 Referenzen sind das ≈ 50 Mio. Record-Kopien; bei `CodeTokens` mit 50 000 Tokens ≈ 1,25 Mrd. Element-Kopien je Security-Regel. Zusammen mit P-01 macht das `references`/`rename` auf häufige Namen unbrauchbar langsam. `WithoutNames` direkt unter `WithoutKeywords` (2283–2307) zeigt das richtige Muster mit `SetLength` vorab.
**Empfehlung:** `TList<T>` mit `ToArray` am Ende oder `SetLength` mit Zähler; `Searched` als `TDictionary<string, Boolean>`. Harmlos und nicht anzufassen sind die Stellen mit n < 50 (Keywords, Overloads, Vorfahrenketten, Editing-Befehle, die einmal je Benutzeraktion laufen).
**Konfidenz:** hoch.

#### P-09 · Hover-Tooltip: Layout und Zeichnen in einer 557-Zeilen-Methode, je Repaint wird die Deklaration neu tokenisiert und umbrochen · Schweregrad: Hoch · Aufwand: M
**Fundstelle:** `Packages/Atlas.IDE.Expert/Source/UI/Hover/Atlas.UI.Hover.Tip.pas`, `TAtlasHoverTip.Render` 318–873 (Deklaration 794–797, `Band` 598–620), `FitHeight` 200–212, `Paint` 1040–1048; `UI/Popup/Atlas.UI.Popup.Styled.pas` `WrapAtSpaces` 218–248, `Pieces` 71–120.
**Beobachtung:**
```pascal
Canvas.Font := Font;
LineHeight := Canvas.TextHeight('Wg') + Scale(2);
Declaration := TAtlasStyledText.Create(Data.Declaration);
Lines := Declaration.WrapAtSpaces(Canvas, Right - Left, Scale(16));
```
und in `Band`:
```pascal
if Drawing then
begin
  Saved := Length(FHits);
  Drawing := False;
  BandContent(AKind);
  SetLength(FHits, Saved);
  Drawing := True;
```
**Warum das ein Problem ist:** `Render` misst und zeichnet in einem Durchlauf; ein Layout als Datenstruktur existiert nicht. `ShowContent` führt `Render(False)` ein- bis zweimal (`FitHeight`) und `Paint` ein weiteres Mal aus; `Band` lässt `BandContent` beim Zeichnen zusätzlich doppelt laufen – je Öffnen drei bis vier vollständige Layouts. Jeder `Invalidate` bei Hot-Wechsel (`MouseMove` 967–972) wiederholt alles: Tokenisierung, `WrapAtSpaces` (je Umbruchkandidat `Width` → `Pieces` mit `TArray.Sort` und Array-Konkatenation je Token, also quadratisch viele `GetTextExtentPoint32`-Aufrufe), Link-Suche, Neuaufbau von `FHits`. Das widerspricht der eigenen Architektur: Für die XMLDoc existiert mit `Atlas.Core.Documentation.Layout` bereits ein VCL-freies Layout mit Mess-Callback.
**Empfehlung:** `Render` in ein `TAtlasHoverLayout`-Record (Zeilen mit Pieces und Breiten, Link-Rechtecke, Bänder, Hits), das in `ShowContent`/`UpdateContent` einmal über einen Mess-Callback gebaut wird – testbar ohne VCL –, und ein `Paint`, das nur noch daraus zeichnet. `TAtlasStyledText` soll seine `Pieces`-Zerlegung cachen und `WrapAtSpaces` mit kumulierten Breiten arbeiten.
**Konfidenz:** hoch (Ablauf belegt; Millisekunden nicht gemessen).

#### P-10 · Inlay-Hints `PaintLine`: drei VCL-Objekte, sechs `Assign`, `GetPixel` und eine Settings-Kopie je gezeichneter Zeile · Schweregrad: Mittel · Aufwand: S
**Fundstelle:** `IDE/InlayHints/Atlas.IDE.InlayHints.Editor.pas`, `PaintLine` 250, 273–291, 304–311; gleiches Settings-Muster `IDE/Problems/Atlas.IDE.Problems.Painter.pas` 151.
**Beobachtung:**
```pascal
Sample := GetPixel(Canvas.Handle, X, Rect.Top + 1);
...
OldFont := TFont.Create;
OldBrush := TBrush.Create;
OldPen := TPen.Create;
try
  OldFont.Assign(Canvas.Font);
  OldBrush.Assign(Canvas.Brush);
  OldPen.Assign(Canvas.Pen);
  Canvas.Font.Size := Max(6, Canvas.Font.Size - 1);
```
**Warum das ein Problem ist:** Der Handler läuft bei jedem Editor-Repaint für jede sichtbare Zeile. Jedes `Assign` löst `Changed` und ein erneutes `SelectObject` aus, `Font.Size` fordert eine neue HFONT aus dem Ressourcencache an, `GetPixel` auf dem Bildschirm-DC erzwingt einen GDI-Flush. Zeile 250 kopiert bei **jeder** Zeile – auch ohne Hinweise – den 80-Felder-Record `TAtlasPluginSettings` mit acht verwalteten Feldern. Kein Leck (try/finally korrekt), aber unnötige Arbeit im heißesten Pfad des Plugins. `Problems.Painter` zeigt daneben das leichtere Muster (`SaveDC`/`RestoreDC`).
**Empfehlung:** `SaveDC`/`RestoreDC` plus `Canvas.Refresh` statt Objektsicherung (wie `Atlas.UI.Documentation.View.Paint` 357–405); eine vorbereitete Hinweis-`TFont` und berechnete Farben als Felder, nur bei Schrift-/PPI-/Hintergrundwechsel neu; `Enabled`/`InlayHints` als zwei Booleans abfragen statt den Record zu kopieren.
**Konfidenz:** hoch (Struktur); mittel für die `GetPixel`-Kosten.

#### P-11 · Regex-Kompilierung in Schleifen und je Anfrage · Schweregrad: Mittel · Aufwand: S
**Fundstelle:** `Atlas.Common.Lsp.Completion.pas` 3441–3451 (`SenderItems`, Schleife bis 2 000 Zeilen rückwärts), 2934, 2996/3008, 3131/3156, 3710, 2579, 2622; `Rules.Builtin.DfmProperties.pas` 216 (in `for Member in Members(…)` 207) und 254; `Atlas.Common.Diagnostics.Anonymizer.pas` 323, 333, 432, 441, 498–520 (sechs Muster je Logzeile).
**Beobachtung:**
```pascal
for Line := Min(APosition.Line - 1, High(Lines)) downto Max(0, APosition.Line - MaxHeaderDistance) do
begin
  Match := TRegEx.Match(Lines[Line], '^\s*(class\s+)?(procedure|function)\s+[\w.]+\.(\w+)\s*[(;:]',
    [roIgnoreCase]);
  if Match.Success then
```
**Warum das ein Problem ist:** `TRegEx.Match` als Klassenfunktion erzeugt bei jedem Aufruf ein `TRegEx` und kompiliert das Muster (PCRE); Delphi hat keinen Pattern-Cache. In `SenderItems` sind das bis zu 2 000 Kompilierungen je „Sender.“-Anfrage; vier bis sechs weitere konstante Muster werden bei jedem Tastendruck neu kompiliert; im Anonymizer je geschriebener Logzeile.
**Empfehlung:** Muster einmal als `TRegEx`-Instanz anlegen (Feld, `class var` mit `initialization`, `roCompiled`) und `Instance.Match(Line)` verwenden. In `SenderItems` den Methodenkopf über den Syntaxbaum (`EnclosingRoutines`) statt per Zeilen-Regex suchen – der Baum ist ohnehin da.
**Konfidenz:** hoch (Mechanismus); Kosten je Kompilierung 10–50 µs (Annahme).

#### P-12 · `FindSymbols` ist ein Vollscan über alle Symbole des Index und wird für eingebaute Typen bei jedem Tastendruck ausgelöst · Schweregrad: Mittel · Aufwand: S (Builtin-Prüfung) / M (Namensverzeichnis)
**Fundstelle:** `Atlas.Common.Lsp.Completion.pas` 3905–3920 (`TypeAt`, Aufrufe 4254, 4261, 4288 aus `EnumItems`), 4065–4083; `Atlas.Common.Index.SymbolIndex.pas` 262–273 (`FindSymbols`), 233–260 (`Locations`); Kopfkommentar 3–5 (siehe K-01).
**Beobachtung:**
```pascal
Result := AResolver.ResolveChain(ATree, AFileName, ATypeName.Split(['.']), AOffset);
if (Result.Found and Result.IsType) or (AIndex = nil) or (Pos('.', ATypeName) > 0) then
  Exit;
// Typ einer Eigenschaft aus einer Unit, die hier nicht eingebunden ist (TAnchors aus Vcl.Controls).
for Location in AIndex.FindSymbols(ATypeName) do
```
**Warum das ein Problem ist:** `Expected` ist sehr oft `Integer`, `string` oder `Boolean` (`I := |`). `ResolveChain` findet eingebaute Typen nicht (sie stehen nicht im Index), also `FindSymbols('Integer')` → Snapshot aller Units (P-13) plus Scan über bis zu 500 000 Symbole – bei jedem Tastendruck. `FindSymbols` wird an 28 weiteren Stellen (Rules, Editing, MCP) benutzt.
**Empfehlung:** In `TypeAt` vorab `TNameResolver.IsBuiltinTypeName(ATypeName)` → `Exit` (eine Zeile). Im `TSymbolIndex` ein echtes Namensverzeichnis `TDictionary<string, TArray<TSymbolLocation>>` in `AddLocked`/`RemoveFileLocked` pflegen; `Descendants` analog über den letzten Teil des Vorfahrennamens.
**Konfidenz:** hoch (Pfad); Häufigkeit der Builtin-Fälle Annahme.

#### P-13 · `ISymbolIndex.Units` kopiert alle Unit-Records unter dem globalen Lock; `AddUnit` hält den Lock während `InternUnit` · Schweregrad: Mittel · Aufwand: M
**Fundstelle:** `Atlas.Common.Index.SymbolIndex.pas` 292–300 (`Units`), 179–199 (`AddUnit`); Aufrufer je Tastendruck: `Completion.pas` 1664, 1947, 2036; `SemanticTokens.pas` 270; `NameIndex.pas` 110.
**Beobachtung:**
```pascal
FLock.Enter;
try
  Pooled.InterfaceUses := Copy(AUnit.InterfaceUses);
  ...
  FPool.InternUnit(Pooled);
  RemoveFileLocked(Key);
  AddLocked(Key, Pooled);
  ShrinkLocked;
```
**Warum das ein Problem ist:** `TUnitIndex` hat zehn verwaltete Felder; 5 000 Units → 50 000 Refcount-Operationen unter dem Lock, den gleichzeitig jeder `FindUnit` jedes Resolvers braucht. `AddUnavailable`/`AddUnavailableMembers` holen diesen Snapshot bei jedem Scope- bzw. Member-Tastendruck, nur um die wenigen Units mit `Unavailable`-Einträgen zu finden. `InternUnit` hasht alle Strings aller Symbole einer Unit (`System.pas`: 10 000 Symbole × 8 Strings) unter demselben Lock – während des Indexaufbaus stottern Worker-Anfragen bei jedem `FindUnit`.
**Empfehlung:** Snapshot-Array je `FGeneration` cachen (copy-on-write: `AddLocked` setzt es auf nil); `InternUnit` vor `FLock.Enter` ausführen (Pool mit eigenem kurzem Lock); für `Unavailable` eine kleine separate Liste betroffener Unit-Schlüssel pflegen.
**Konfidenz:** hoch (Struktur), Kosten Annahme.

#### P-14 · Long-Polling von `workspace/diagnostic` (10 s) kollidiert mit dem Watchdog-Standard (10 s); zweiter Wartender pollt mit `Sleep(100)` · Schweregrad: Mittel · Aufwand: S
**Fundstelle:** `Atlas.Common.Lsp.PullDiagnostics.pas` 57 (`DefaultWaitMs = 10000`), 260–273 (`WaitForChange`), 411–426 (`WorkspaceReport`), 143 (Auto-Reset-Event); `Shell.Composition.pas` 249 (`RequestTimeoutMs = 10000`); `Atlas.Common.JsonRpc.Watchdog.pas` 114.
**Beobachtung:**
```pascal
while (Waited < FWaitMs) and (FGeneration = Generation) and (FWorkspaceActive <> 0) and
  not ACancellation.IsCancellationRequested do
begin
  Sleep(100);
  Inc(Waited, 100);
end;
```
**Warum das ein Problem ist:** Ohne Änderungen wartet der Handler ≥ 10 000 ms; der Watchdog ist beim Start auf +10 000 ms gestellt und feuert meist zuerst. Ergebnis: je Long-Poll eine Warnung „nach 10000 ms abgebrochen (Zeitlimit)“ im Server-Log und ein gezählter Timeout in Statistik und Diagnoselog, obwohl das Verhalten gewollt ist. Zwei Mechanismen für dieselbe Wartebedingung (Auto-Reset-Event weckt nur einen Wartenden, deshalb vermutlich der `Sleep`); beide blockieren je einen Thread des Standard-`TThreadPool`, in dem auch die Vervollständigung läuft.
**Empfehlung:** `WaitMs` an das Zeitlimit koppeln (`Max(1000, Timeout - 2000)`) oder Long-Poll-Methoden vom Watchdog ausnehmen; `WaitForChange` auf Manual-Reset-Event plus Generation oder `TMonitor.Wait/PulseAll` umstellen.
**Konfidenz:** mittel (Zeitablauf aus Konstanten plausibel, nicht gemessen).

#### P-15 · Completion-Popup: Metriken, Deklarations-Layout und Doku-Parsen je Aufruf statt je Änderung · Schweregrad: Niedrig · Aufwand: S
**Fundstelle:** `Atlas.UI.Completion.Popup.pas` `RowHeight` 600–604, `ChipsHeight` 392–399, `FooterHeight` 606–611, `RowRect` 628–634; `Atlas.UI.Completion.Details.pas` `Render` 294–299, 322, `DocOf` 108–136.
**Beobachtung:**
```pascal
function TAtlasCompletionPopup.RowHeight: Integer;
begin
  Canvas.Font := Font;
  Result := Max(Canvas.TextHeight('Wg') + Scale(9), Scale(24));
end;
```
**Warum das ein Problem ist:** `RowRect` ruft `RowHeight` und `ListTop → ChipsHeight`; je gezeichneter Zeile drei `Canvas.Font :=`-Zuweisungen (jede löst `TFont.Changed` und Neu-Selektieren aus) und zwei `TextHeight`-Messungen – rund 40 Font-Wechsel je Repaint, zusätzlich in `RowAt` bei jedem `MouseMove`. Nicht dramatisch (Millisekunden), aber bei jedem Pfeiltastendruck doppelt.
**Empfehlung:** Zeilen-/Chip-/Fußzeilenhöhe als Felder, nur in `CMFontChanged`/`SetScaling` neu messen; in `SetDetails` `Doc`, `TAtlasStyledText` und Umbruchzeilen ablegen.
**Konfidenz:** hoch.

#### P-16 · `Sleep(20)`-Polling im MCP-Werkzeugaufruf blockiert die Nachrichtenschleife bis 33 s · Schweregrad: Niedrig · Aufwand: S
**Fundstelle:** `Application/Source/Shell/Shell.Mcp.pas` 185–210 (`WriteSourceText`); `Atlas.Common.Mcp.IdeEdits.pas` 26–27 (`AnswerMs = 3000`, `TakenMs = 30000`); `Atlas.Common.Mcp.Server.pas` 267 (`tools/call` synchron).
**Beobachtung:**
```pascal
case TMcpIdeEdits.Send(TMcpIdeEdits.InboxOf(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), Pid),
  AFileName, Expected, AText,
  procedure
  begin
    Sleep(20);
  end,
```
**Warum das ein Problem ist:** Die Datei-Handshake-Schleife pollt alle 20 ms per `FileExists` im Thread der Nachrichtenschleife; währenddessen antwortet der MCP-Server auf nichts, auch nicht auf `ping`, und `$/cancelRequest` wirkt nicht. Positiv: `Sleep` und Uhr sind injiziert, `Atlas.Common` bleibt testbar.
**Empfehlung:** Intervall 50–100 ms; `tools/call` als nebenläufigen Handler registrieren, damit `ping`/`cancel` durchkommen; alternativ `ReadDirectoryChangesW` auf den Inbox-Ordner im Windows-Adapter.
**Konfidenz:** hoch.

#### P-17 · `ResolveTypeFrom` leert den Helper-Cache; `ScopeUnits` allokiert je Lookup · Schweregrad: Mittel · Aufwand: S
**Fundstelle:** `Atlas.Common.Semantics.NameResolver.pas` 2357–2368 (`ResolveTypeFrom`), 1073–1108 (`HelperFor`), 683–702 (`ScopeUnits`, Aufrufer 647, 814, 1083, 1467, 2254, 2277).
**Beobachtung:**
```pascal
FTree := nil;
FOffset := 0;
FCurrent := AFromUnit;
FInImplementation := True;
FClassState := 0;
FHelperTree := nil;
FHelpers.Clear;
Result := ResolveTypeName(ATypeName, AFromUnit, True, AResult);
```
**Warum das ein Problem ist:** Die Vervollständigung ruft `ResolveTypeFrom` häufig (`TypeAt` 3918, `TypeChain` 3397 je Komponente, `ComponentItems` 3349, `EnumOf` 3959/3962). Jeder Aufruf verwirft `FHelpers`; der nächste `Prepare` leert ihn erneut, und `HelperFor` baut ihn durch Scan aller Symbole aller uses-Units wieder auf. `ScopeUnits` erzeugt bei jedem Aufruf `TList` plus Array, obwohl sich `FCurrent`/`FInImplementation` nur in `Prepare` ändern.
**Empfehlung:** Helper-Cache nach (Unit-Datei, `InImplementation`) statt nach Baum schlüsseln; `ScopeUnits` in `Prepare` einmal berechnen; `HelperFor` nur Symbole mit `Kind = HelperType` betrachten – ideal über das Verzeichnis aus P-05.
**Konfidenz:** hoch.

### 3.2 Code-Smells

Geprüft und ohne wesentlichen Befund: `with`-Blöcke (0), `Application.ProcessMessages` (0), globale Variablen im Interface-Abschnitt (0 in `Atlas.Common`), `Variant`-Nutzung (11 Treffer, alle in OTA- oder JSON-Zugriffen begründet), ungeprüfte Typecasts auf `Sender` (keine gefunden; die Popups verwenden Methodenzeiger statt `Sender`-Weichen), Compiler-Warnungen per Direktive unterdrückt (3 × `SYMBOL_PLATFORM`, alle begründet), `except end;` (16 Stellen, alle kommentiert und auf Protokollierungs- bzw. Beendigungspfade beschränkt – gerechtfertigt).

#### S-01 · `TLspCompletion.Collect` (716 Zeilen) und `Handle` (207): versteckte Parameter, if-Kaskade, Datenklumpen · Schweregrad: Mittel · Aufwand: L
**Fundstelle:** `Atlas.Common.Lsp.Completion.pas` 1401–2115 (`Collect` mit 12 verschachtelten Routinen und ≈ 20 geteilten Variablen), `Add` 1528–1592, `AddCandidates` 1977–1999, `Handle` 2309–2514, `ToJson` 2124–2269 (40 `if`-Zweige für `data`); Parameterlisten: `EnumItems` 4228–4230 (10 Parameter), `SenderItems` 3408–3410 (10), `Collect` 1401–1403 (9), `InterfaceItems` 3082–3084 (9), `DeclareItems` 4085–4087 (9).
**Beobachtung:**
```pascal
SourceFile := Candidate.FileName;
SourcePosition := Candidate.SelectionRange.StartPos;
Member := Candidate;
if Candidate.TypeName <> '' then
  Add(Candidate.Name, Candidate.TypeName, KindOf(Candidate.SymbolKind))
```
**Warum das ein Problem ist:** `Add` liest `Member`, `SourceFile`, `SourcePosition` aus dem äußeren Scope; jeder Aufrufer muss sie vorher setzen und hinterher zurücksetzen (`AddKeywords` 1919–1921, `AddUnavailable` 1696–1697, `AddFromOtherUnits` 1760–1765 mit Kommentar, warum). Das ist genau die Fehlerklasse, die der Kommentar 1538–1539 („sonst blieben … Datenmüll“) schon einmal gekostet hat. Die immer gleichen 8–10 Parameter (`AResolver, AIndex, ATree, AText, AFileName, APosition, AReadText, AMatching`) sind ein Datenklumpen, der jede neue Completion-Art teurer macht; die Unit ist mit 4 307 Zeilen und sieben Anliegen (Sichtbarkeit, Snippets, Enum-Werte, Set-Modus, Sender-Cast, Feldnamen, Postfix) der größte Wartungsrisikofaktor des Servers.
**Empfehlung:** `TCompletionCollector`-Klasse mit Feldern statt Closure-Variablen und `Add(const ASymbol: TResolvedSymbol; AKind, APenalty)`; `TCompletionRequest`-Record als gemeinsamer Parameter; die Spezialfälle als Liste von Providern `function(const R: TCompletionRequest; out Items): Boolean`, die `Handle` iteriert; `ToJson` tabellengesteuert. Siehe Vorschlag 4.2.
**Konfidenz:** hoch.

#### S-02 · `TServerComposition.Create` (919 Zeilen) vermischt Verdrahtung, Fachlogik und 23 überflüssige Wrapper-Closures; Fallback-Logik je Workspace ist inkonsistent · Schweregrad: Mittel · Aufwand: M
**Fundstelle:** `Application/Source/Shell/Shell.Composition.pas` 333–1250. Zahlen: 29 `.Attach(`, 12 `FCommands.Register(`, 77 anonyme Methoden, davon 10 identische `ReadSourceText`- und 13 identische `EnsureUnit`-Wrapper; 18 × das Muster „`WorkspaceOf` + Fallback `FWorkspaces.Count = 1`“, unit-weit 47 × `TMonitor.Enter(FWorkspacesLock)`. Fachlogik in Handlern: Formular-Konvertierung 872–905, `selectBuild` 1021–1090, `clearIndex` 990–1020, Build-Datei 1129–1157. `StartIndex` in `Shell.Workspace.pas` 287 Zeilen, `TCommandLineOptions.Parse` 199 Zeilen.
**Beobachtung:**
```pascal
FDefinition := TLspDefinition.Create(FDocuments, FIndex,
  function(const AUnitName: string): Boolean
  begin
    Result := EnsureUnit(AUnitName);
  end);
FDefinition.ReadText :=
  function(const AFileName: string; out AText: string): Boolean
  begin
    Result := ReadSourceText(AFileName, AText);
  end;
```
Dieselbe Unit zeigt, dass es ohne Wrapper geht: Zeile 436–437 `FFormatting.SlashCommandsFor := SlashCommandsFor;`.
**Warum das ein Problem ist:** Alle Delegattypen sind `reference to function`; Methoden lassen sich direkt zuweisen – die 23 Wrapper sind Lärm. Schwerer wiegt die Inkonsistenz: `DelphiVersionFor`/`CompletionSettingsFor` fallen bei genau einem Ordner auf diesen zurück, `IncludePathsProvider` (520–534), `DocumentLinks` (853–867) und `RuleContextFor` (2062–2083) nie, `DefinesFor` (1690–1691) auf `FWorkspaces[0]` auch bei mehreren Ordnern. Eine Datei außerhalb aller Ordner bekommt Hover-Einstellungen aus dem Ordner, aber Regel-Defaults und Includes aus dem Nichts.
**Empfehlung:** Wrapper entfernen; `WorkspaceFor(const AUri; AFallback): TShellWorkspace` plus `SettingsFor(const AUri): TServerSettings` (eine Sperre, ein Fallback), dann werden alle `*SettingsFor` Einzeiler; `Create` in `WireProtocol`, `WireDocuments`, `WireNavigation`, `WireCommands`, `WireWorkspaceLifecycle`, `WireCompiler` teilen; Fachlogik der Befehle nach `Shell.Commands.*` bzw. (nach Vorschlag 4.5) in Host-Core. `Parse` tabellengesteuert (Name → Setter, „braucht Wert“).
**Konfidenz:** hoch.

#### S-03 · `Apply` (435 Zeilen), `Initialize` (118), `RegisterFeatures` (169), `RegisterPalette` (151) vermischen Planen, Entscheiden und Ausführen · Schweregrad: Mittel · Aufwand: L
**Fundstelle:** `IDE/Editor/Atlas.IDE.Editor.WorkspaceEdit.pas` 275–707; `Core/Lsp/Atlas.Core.Lsp.Session.pas` 473–589; `IDE/CodeInsight/Atlas.IDE.CodeInsight.Composition.pas` 633–799 und 237–385.
**Beobachtung:** `Apply` hat 12 lokale Routinen (297–468), die 20 gemeinsame Variablen teilen, Verschachtelungstiefe bis 6 (534–618), `Result.Error := …; Exit` an zehn Stellen, `Remember` in fünf Fehlerpfaden und den Boolean-Parameter `AOpenUnopened`. Phase 1 (Planen, 481–618) ist reine Logik ohne OTA bis auf `BufferOf`/`IsOpen`; Phase 2 (620–699) ist IDE-Ausführung. `Initialize` baut Capability-JSON (485–530), verdrahtet Lese-Thread-Callbacks (531–577) und sendet (580–588) in einer Methode. `RegisterFeatures` ist eine Kette `if (X = nil) and (Full or …) then X := …` mit zwei Booleans `Full`/`Basic`, deren Reihenfolge `Unregister` von Hand spiegeln muss; `RegisterPalette` wiederholt 25-mal dieselbe `RegisterCommand`-Closure.
**Warum das ein Problem ist:** Die Planung von `Apply` ist so nicht per DUnitX testbar (CLAUDE.md verlangt Tests je Kernfunktion); Fehler in der Reihenfolge Anmelden/Abmelden fallen erst in der IDE auf; eine neue Dateioperation berührt eine 435-Zeilen-Funktion.
**Empfehlung:** `Apply` in `TAtlasEditPlanner` (Core, liefert `TAtlasEditPlan` mit `Creates/Removes/Files/Error`) und `TAtlasIdeWorkspaceEdit.Execute(Plan)` trennen; `AOpenUnopened` → `TAtlasUnopenedPolicy = (OpenInEditor, WriteToDisk)`. `Initialize` in `class function InitializeParams(…): TJSONObject` (testbar) + `AttachClientHandlers` + `Initialize`. `RegisterFeatures` tabellengesteuert (Stufe, Bedingung, Create, Free), `Unregister` iteriert rückwärts; `RegisterPalette` aus einer Tabelle (Id, TextId, Proc).
**Konfidenz:** hoch.

#### S-04 · `TMemberOrder.Sort` (179 Zeilen) monolithisch · Schweregrad: Mittel · Aufwand: M
**Fundstelle:** `Atlas.Common.Editing.MemberOrder.pas` 179–357, Variablenblock 181–191 (über 20 lokale Variablen, keine lokalen Routinen).
**Beobachtung:** Eine Methode erledigt Vorprüfung (`{$A-}` 189–192), Abschnittserkennung, Mitgliedersammlung, Sortierbarkeitsregeln (Nested/Directives/Fields) und Textausgabe. Zum Vergleich ist `TUnusedAssignmentRule.Check` (`Builtin.Unused.pas` 702–842) durch vier lokale Routinen gegliedert und bleibt im Hauptrumpf bei 42 Zeilen.
**Warum das ein Problem ist:** Die vielen Sortier-Ausschlussregeln (Kopf 3–15) lassen sich in dieser Form nicht einzeln testen oder erweitern.
**Empfehlung:** In `CollectSections`, `ClassifyMembers`, `CanSort(Sections, Settings)`, `Emit` zerlegen; `TSection`/`TItem` bleiben.
**Konfidenz:** hoch.

#### S-05 · Nachgelagerte Einstiegspunkte im Plugin ohne `TAtlasGuard` · Schweregrad: Mittel · Aufwand: S
**Fundstelle:** `IDE/Completion/Atlas.IDE.Completion.Editor.pas` 902–911 (`EditorModified`, `ForceQueue` → `Invoke`), 935–952 (`SkipAutoParen`), 1279–1284, 1295–1300; `Core/Completion/Providers/Atlas.Core.Completion.Providers.Server.pas` 509–515 (`Resolve`-Rückruf → `ShowDetails`); `IDE/CodeInsight/Atlas.IDE.CodeInsight.Manager.pas` 661–673 (`AReply` außerhalb des `try`), 886–918 (`GetHintText`), 920–974 (`GotoDefinition`), 1225–1285 (`except … ReportError` statt `TAtlasGuard.Report`).
**Beobachtung:**
```pascal
TThread.ForceQueue(nil,
  procedure
  begin
    if (View.Buffer <> nil) and not FController.Active then
    begin
      FGuardNewLine := True;
      if not Invoke(View, True) then
        FGuardNewLine := False;
    end;
  end);
```
Der Notifier-Aufruf selbst ist abgesichert (`EditorViewModified` 381–389), die später über `CheckSynchronize` ausgeführte Closure nicht.
**Warum das ein Problem ist:** Eine Exception in einer eingereihten Closure landet in `TApplication.HandleException` – der Fehlerdialog der IDE, den #493 ausschließt – und zählt nicht gegen die Sicherung. Die fünf Manager-Methoden mit `ReportError` schreiben nur ins Meldungsfenster; ein dauerhaft werfender Hover schaltet nie ab.
**Empfehlung:** Jede `ForceQueue`/`Queue`-Closure in `TAtlasGuard.Run(TAtlasFeature.…, …)` hüllen (Muster `TAtlasIdeKeys.TPackageWatch` 188–193); in `GetHintText`/`GotoDefinition`/`Invoke*`/`Open*` zusätzlich `TAtlasGuard.Report`; `AReply` in `AcceptApplyEdit` in den `try` nehmen.
**Konfidenz:** hoch.

#### S-06 · Compile-Thread: Ausnahme außerhalb des inneren `except` friert `FCompiling` ein; Exceptions anonymer Threads verschwinden · Schweregrad: Niedrig · Aufwand: S
**Fundstelle:** `Shell.Composition.pas` 2306–2312 (`CreateAnonymousThread`), 2315–2394 (`CompileLoop`), 2371–2377.
**Beobachtung:**
```pascal
except
  on E: Exception do
  begin
    CompilerUnavailable(E.Message);
    FCompileProgress.Finish('Fehlgeschlagen');
  end;
end;
```
**Warum das ein Problem ist:** Wirft `FCompileProgress.Finish` im Except-Zweig (Transportfehler) oder `FCompileProgress.Start` (2329, außerhalb des inneren `try`), verlässt die Ausnahme `CompileLoop`; ein anonymer `TThread` legt sie in `FatalException` ab, niemand liest sie, `FCompiling` bleibt True – kein Kompilieren mehr nach dem Speichern, ohne Logzeile.
**Empfehlung:** `CompileLoop` vollständig in `try … except on E: Exception do FLogger.Error(DescribeFailure(E)); end` hüllen, `FCompiling := False` im `finally` unter `FCompileLock`; Hilfsfunktion `RunLoggedThread(const AName: string; const AWork: TProc)` mit `NameThreadForDebugging` für alle anonymen Threads.
**Konfidenz:** hoch (Mechanismus), Eintrittswahrscheinlichkeit gering.

#### S-07 · Kleinkram: magische Strafpunkte, `{$WARN … ON}` statt `DEFAULT`, Test-Knopf im Produktivdialog, Mitschnitt schluckt dauerhaft, zwei kleine Lecks · Schweregrad: Niedrig · Aufwand: S
**Fundstelle:** `Atlas.Common.Lsp.Completion.pas` 1632, 1684, 1768/1770, 1923, 1960 (`Dec(Scored.Score, 500)` usw.); `Shell.Composition.pas` 1702–1705 (`{$WARN SYMBOL_PLATFORM ON}`; `Atlas.Windows.Console.StdStreams.pas` 92–94 macht es mit `DEFAULT` richtig); `Atlas.UI.Settings.Page.pas` 1236–1243 (`HangTestClick` mit `Sleep(1000)`) und `Atlas.IDE.CodeInsight.Composition.pas` 377–384 („Wächter-Test“ als Palettenbefehl); `Atlas.Common.JsonRpc.TracingTransport.pas` 61–77 (nach Schreibfehler weiter versuchen, nie melden); `Atlas.IDE.CodeInsight.Manager.pas` 653–655 (`AId` bei verworfenem applyEdit nicht freigegeben); `Atlas.Core.Lsp.Adapters.ServerProcess.pas` 194–197 (zweite `CreatePipe` schlägt fehl → `InputRead` bleibt offen).
**Warum das ein Problem ist:** Die Strafpunkte 50/100/200/500 definieren die Gruppenreihenfolge der Vervollständigung (Schlüsselwörter, Projekt-Import, Bibliotheks-Import, nicht verfügbar), sind aber nirgends benannt. `ON` erzwingt die Warnung unabhängig von der Projekteinstellung. Der Test-Knopf friert die IDE absichtlich eine Sekunde ein und erzeugt einen Wächter-Eintrag; er steht gleichberechtigt neben den regulären Einstellungen und in der Befehlssuche. Die Lecks sind klein, nach Serverneustarts aber kumulativ.
**Empfehlung:** `const PenaltyKeyword = 50; PenaltyProjectImport = 100; PenaltyLibraryImport = 200; PenaltyUnavailable = 500;`; `{$WARN SYMBOL_PLATFORM DEFAULT}`; Test-Knopf und Palettenbefehl nur mit `Diagnose = 1`; im `TracingTransport` nach dem ersten Fehler `FTrace := nil` und einmalig melden; im Exit-Pfad `AReply(False, 'Sitzung beendet')`; `InputRead` im `finally` des Konstruktors schließen.
**Konfidenz:** hoch.

### 3.3 Duplikate

Hintergrund: `Atlas.IDE.Expert.dpk` 43–47 verlangt nur `rtl, vcl, vclwinx, designide`; `Tools/Check-PackageDependencies.ps1` 72 erlaubt dem Plugin nichts anderes. Die Kopfkommentare der Plugin-Units nennen die Kopie ausdrücklich (`Atlas.Core.Diagnostics.BugReport.pas` 10–11, `Atlas.Core.Files.TextFile.pas` 97, `Atlas.Core.Product.Version.pas` 3–6). Die Entscheidung ist also bewusst – aber sie ist nicht als ADR dokumentiert (K-02), und die Kopien driften bereits.

#### D-01 · Kodierungs-, BOM- und Zeilenende-Erkennung viermal, mit unterschiedlicher UTF-8-Strenge · Schweregrad: Hoch · Aufwand: M
**Fundstellen:** `Atlas.Core.Files.Format.pas` (295 Zeilen), `Atlas.Core.Files.TextFile.pas` (277), `Atlas.Core.Files.EncodingDefault.pas` (73) vs. `Atlas.Common.Documents.FileEncoding.pas` (743).
**Beobachtung:** Wörtlich identisch Plugin ↔ Server: `HasPrefix` (TextFile 102–112 = FileEncoding 268–278), `SingleByteCodePages` (98–100 = 131–133), `ParseCodePage` (162–187 = 570–595, 26 Zeilen), `IsBinaryForm` (157–160 = 597–600), `LineBreakOf` (Format 135–151 = `DetectLineBreak` 490–506). Strukturell gleich, semantisch abweichend: `IsUtf8` existiert **zweimal im Plugin** (Format 98–125, TextFile 62–94) und akzeptiert jede Folge mit gültigen Folgebytes; `CheckUtf8` im Server (216–266) prüft strikt (überlange Formen, Surrogate, > U+10FFFF). Reines ASCII: Server nimmt `ADefault`, Plugin immer UTF-8. ANSI: Server dekodiert über eine eigene CP1252-Tabelle (Kopf 14–15: „damit das Ergebnis nicht von der Codepage des Systems abhängt“), Plugin über `TEncoding.ANSI`.
**Warum das ein Problem ist:** Dieselbe Datei kann von Server und Plugin unterschiedlich klassifiziert werden – das Plugin schreibt Dateien (`TextFile.Save` 257–275), der Server liest sie; Umlaute können kippen. Vier Pflegestellen für eine Regel; kein Test vergleicht beide Seiten, obwohl `Tests/Atlas.Tests.dpr` beide Pakete einbindet.
**Empfehlung:** Gemeinsame Unit `Atlas.Text.Encoding` (nur RTL) mit der strikten Server-Fassung; `TFileEncoding` und `TAtlasTextFile` werden dünne Fassaden; `Format` und `TextFile` im Plugin auf eine Erkennung zusammenführen. Ablage siehe Vorschlag 4.3.
**Konfidenz:** hoch (Diffs gemessen).

#### D-02 · Fehlerbericht-Anonymisierung ist eine 95-%-Kopie · Schweregrad: Hoch · Aufwand: S
**Fundstellen:** `Atlas.Core.Diagnostics.BugReport.pas` 69–235 vs. `Atlas.Common.Diagnostics.BugReport.pas` 59–230 (`IsWordChar`, `IsPathEnd`, `TrimDelimiters`, `PathLengthAt`, `ReplaceAbsolutePaths`, `ReplaceQuoted`, `AnonymizePaths`, `AnonymizeLogLine`); `Atlas.Common.Diagnostics.Anonymizer.pas` 254–257 (dritte `IsWordChar`-Variante ohne `Ord(C) > 127`).
**Beobachtung:** 167 vs. 172 Zeilen; nach Normalisierung der Klassennamen nur 17 abweichende Zeilen, alle kosmetisch (`PathEnd`-Konstante statt Inline-Set, Kommentare, Variablenreihenfolge). `Build` (Core 255–309, Common 232–297) teilt Kopf, Datumsformat und das Entschärfen von ```.
**Warum das ein Problem ist:** Sicherheitsrelevante Logik (was im Bericht geschwärzt wird) zweimal; eine Korrektur muss zweimal erfolgen. `Tests/IDE.Expert/Atlas.Core.Diagnostics.BugReport.Tests.pas` testet nur die Plugin-Seite.
**Empfehlung:** Die acht Funktionen nach `Atlas.Text.Anonymize` (RTL); beide `TBugReport` rufen sie. Falls die Kopie bleiben soll: Sync-Test, der beide `AnonymizeLogLine` über eine Tabelle von Eingaben vergleicht.
**Konfidenz:** hoch.

#### D-03 · Kleinhelfer vielfach kopiert, teils mit abweichender Semantik: `LineBreakOf` 7×, `SplitLines` 11×, `IndentOf` 5×, `IsWordChar` 8× · Schweregrad: Hoch · Aufwand: M
**Fundstellen (alle `Atlas.Common`, sofern nicht anders):** `LineBreakOf` wörtlich identisch in `Editing.CodeActions` 134, `Editing.ClassCompletion` 86, `Editing.DocComments` 70, `Editing.GuardFree` 94, `Rules.Builtin.Capture` 362, `Rules.Builtin.General` 109, `Projects.DprojEditor` 87; dazu `DetectLineBreak` (`Editing.Formatter` 62), `LineBreakIn` (`Mcp.CodeTools` 338), sechs Inline-Varianten in `Lsp.Completion` (1473, 3018, 3168, 3520, 4019, 3755) und 19 weitere Inline-Vorkommen `if Pos(#13#10, …) > 0`. `SplitLines` mit vier Semantiken: Replace-Kette (`Formatter` 57, `ClassCompletion` 81, `GoldenCorpus` 87, Plugin `Forms.Changes` 40), nur `#10` + separates `StripCr` (`CodeActions` 111/126, `AssignmentSwap` 67/221, `StringLiterals` 55), `Split([#10])` mit Nachbearbeitung (`GuardFree` 84), `out ALineBreak` (`SlashCommands` 167), eigene Schleife (`Lsp.SignatureHelp` 110). `IndentOf` mit drei Signaturen (`Modernizer` 39 → Integer; `CodeActions` 142, `ClassCompletion` 292, `DocComments` 87 → string; `CaseCompletion` 104). `IsWordChar` 8 Definitionen, `IsIdentChar` 6, `DecodeEntities` 2 (`Pascal.XmlDoc` 211 vollständig vs. Plugin `LiveTemplates` 122 nur fünf benannte Entities). Gleicher Name, andere Semantik: `ReplaceCommand` in `Editing.DatabaseCommands` 87–96 (ohne Einrückung) vs. `Editing.MaintenanceCommands` 33–42 (mit `ASource.Indent`).
**Warum das ein Problem ist:** Sieben identische Kopien eines Fünfzeilers sind das klarste Signal für eine fehlende Basis-Unit; die vier `SplitLines`-Semantiken sind ein stiller Fehlerherd (CR-only-Dateien, abschließendes `#13`). Zwei gleichnamige Funktionen mit unterschiedlichem Verhalten sind beim Verschieben eines Befehls zwischen Units ein unsichtbarer Fehler.
**Empfehlung:** `Atlas.Text.Lines` (`SplitLines(const AText; out ALineBreak)`, `LineBreakOf`, `IndentOf`, `JoinLines`) und `Atlas.Text.Chars` (`IsWordChar`, `IsIdentStart/Char`); `ReplaceCommand`, `JoinLines`, `IndentedBlock` in `TCommandSource` aufnehmen (das ist bereits die richtige Heimat, 20–63). Danach eine Prüfung „keine lokale Definition dieser Namen“ in `Tools/Check-*.ps1` oder als Atlas-Regel.
**Konfidenz:** hoch.

#### D-04 · URI↔Pfad und Position↔Offset zweimal mit Drift; `PositionAt` zusätzlich in Regeln nachgebaut · Schweregrad: Mittel · Aufwand: S
**Fundstellen:** `Atlas.Core.Lsp.Session.pas` `PathToUri` 347–372, `UriToPath` 374–417 vs. `Atlas.Common.Documents.Uris.pas` `FromPath` 127–137, `ToPath` 106–125, `PercentDecode` 45–77; `Atlas.Core.Lsp.TextChanges.pas` `PositionOf` 106–131, `OffsetOf` 133–158 vs. `Atlas.Common.Documents.TextDocument.pas` `PositionAt` 161–180, `OffsetAt` 149–159; innerhalb des Servers `PositionAt` in `Rules.Builtin.Unused.pas` 196–209 und `Rules.Builtin.Capture.pas` 347–360 (wörtlich gleich, zählt nur `#10`), `OffsetOf` in `Lsp.Completion.pas` 3864, `Lsp.PublishedMembers.pas` 288, `Mcp.EditTools.pas` 110.
**Beobachtung:** `UriToPath` 384–405 ist wörtlich `PercentDecode` 55–76 (gleiche Variablennamen). Abweichungen: Server normalisiert (`NormalizePath`, Laufwerksbuchstabe klein, 135), Plugin nicht; Plugin wandelt `/` immer in `\`, Server nur bei Windows-Pfaden. Positionen: gleiche Semantik, Plugin linear O(n) je Aufruf, Server binär über `FLineStarts`.
**Warum das ein Problem ist:** Server-Schlüssel und Plugin-URI können für dieselbe Datei verschieden ausfallen; die Positionsrechnung ist viermal mit drei Verhaltensweisen vorhanden, obwohl `ITextDocument.OffsetAt/PositionAt` existieren.
**Empfehlung:** `Atlas.Text.Uris` und `Atlas.Text.Lines` (Zeilenstart-Tabelle + `PositionAt/OffsetAt`) im gemeinsamen Package; Regeln in `Common` auf `ITextDocument`/Zeilentabelle statt eigener `PositionAt`.
**Konfidenz:** hoch für die Kopie, mittel für die praktische Auswirkung der URI-Drift.

#### D-05 · Fuzzy-Matching: Server filtert mit anderen Regeln als das Plugin nachfiltert · Schweregrad: Mittel · Aufwand: M
**Fundstellen:** `Atlas.Core.Completion.Matching.pas` `IsWordStart` 51–68, `MatchesSubsequence` 83–114, `Score` 177–197 vs. `Atlas.Common.Lsp.FuzzyMatch.pas` `IsWordStart` 35–44, `SubsequenceScoreOf` 48–91, `Score` 95–124; dritter `IsWordStart`-Wrapper in `Atlas.Core.Completion.Presentation.pas` 85–88.
**Beobachtung:** Plugin-Wortanfang = Großbuchstabe nur nach Klein/Ziffer oder vor Klein (64–66), Server = jeder Großbuchstabe oder nach `_`/`.` (39–42). Plugin verlangt bei Teilfolgen Wortgrenzen (89–91), Server erlaubt die „Plain“-Teilfolge (119). Stufen 1000/900/800/600/400/200 vs. 4000/3000/2000/1000.
**Warum das ein Problem ist:** Ein Eintrag, den der Server als Treffer liefert, kann beim Weitertippen im Plugin verschwinden (Kopf Matching 3–5: das Popup filtert lokal statt neu zu fragen). Das ist Drift, nicht nur Doppelung.
**Empfehlung:** `IsWordStart` und die Teilfolgen-Prüfung teilen (`Atlas.Text.Fuzzy`), Score-Stufen als Konstanten dort; das Tippfehler-Ranking (Damerau-Levenshtein, 118–144) bleibt im Plugin.
**Konfidenz:** mittel (Drift-Szenario abgeleitet, nicht ausgeführt).

#### D-06 · Prefix/Suffix-Zeilendiff viermal (drei davon zeichengleich) · Schweregrad: Mittel · Aufwand: S
**Fundstellen:** `Atlas.Core.Files.TextDiff.pas` 39–49; `Atlas.Core.Problems.Store.pas` 229–237; `Atlas.Common.Mcp.EditTools.pas` 154–162 (dazu 165–175 dieselbe Ausgabe „Zeile %d: / - / +“ wie TextDiff 50–58); `Atlas.Core.Undo.LinePatch.pas` `Hunks` 109–115 (+ LCS 131–164). `Atlas.Core.Forms.Changes.pas` ist kein Diff (Zeile-für-Zeile bei gleicher Zeilenzahl), aber `SplitLines` 40–43 ist wörtlich `Atlas.Common.Editing.Formatter.pas` 57–60 und `ClassCompletion.pas` 81–84.
**Warum das ein Problem ist:** Vier Stellen für dieselbe Diff-Vorstufe; `LinePatch` hat den vollwertigen Algorithmus (LCS, Hunks), den die anderen nicht nutzen.
**Empfehlung:** `Atlas.Text.Diff` mit `CommonPrefixSuffix` + `Hunks` aus `LinePatch`; TextDiff, Problems.Store und Mcp.EditTools darauf umstellen.
**Konfidenz:** hoch.

#### D-07 · Zeichenbausteine der Plugin-UI vier- bis fünffach, mit bereits abweichenden Werten · Schweregrad: Mittel · Aufwand: M
**Fundstellen:** `Atlas.UI.Hover.Tip.pas` `SeverityColor` 337–351, `Block` 395–412, Badge 759–772, `Chip` 462–498, `DocLabels` 175–181; `Atlas.UI.Completion.Details.pas` `Block` 189–208, Tags 262–292, `DocLabels` 156–162; `Atlas.UI.Completion.Popup.pas` `DrawBadge` 885–905, `DrawTag` 959–985, `DrawChips` 421–465, `DrawScrollBar` 1089–1104; `Atlas.UI.Documentation.View.pas` 407–415; `Atlas.IDE.Problems.Painter.pas` `SeverityColor` 113–127; `ToColor` in `Popup.Window` 125 und `Status.Window` 86.
**Beobachtung:** Hover-Tip mischt blasse Probleme mit `Mix(Result, Colors.Surface, 0.5)`, der Editor-Painter mit `0.55` – zwei Farben für denselben Zustand. Textblock mit `DT_CALCRECT`/Maximalzeilen/Ellipse in Hover und Details wortgleich; Badge 24×17 mit `-Round(Box.Height * 0.62)`-Schrift in Hover und Popup identisch; Chips in vier Varianten mit Padding 10/12/14 und Rundung 3/4/9; Scroll-Daumen mit Mischfaktor 0.45/0.5/0.6.
**Warum das ein Problem ist:** Jede Entwurfsänderung (#411) muss an vier bis fünf Stellen nachgezogen werden, und die Drift hat bereits begonnen.
**Empfehlung:** Helferunit `Atlas.UI.Popup.Draw` (`DrawBlock`, `DrawBadge`, `DrawTagFrame`, `DrawThumb`, `DrawSeparator`); `SeverityColor` VCL-frei nach `Atlas.Core.Problems` mit DUnitX-Test; Mischfaktoren als benannte Konstanten in `Atlas.Core.Style.Palette`; `DocLabels` nach `Atlas.UI.Strings`.
**Konfidenz:** hoch.

#### D-08 · Dreifache Verdrahtung von Logger, Transport, Projektgruppe und Workspace in Composition, Mcp und Linter – mit abweichender Semantik · Schweregrad: Mittel · Aufwand: M
**Fundstellen:** `Shell.Mcp.pas` 540–550 vs. `Shell.Composition.pas` 2527–2544 (Logger); Mcp 560 vs. Composition 2547 (Transport); Mcp 494–512 `GroupProjects` vs. Composition 1327–1367 `ProjectsOf`; `ReadSourceText` viermal (Mcp 219–228, `Shell.Workspace.pas` 310–319, Composition 397–415 und 1711–1726); Mcp 561–569/694–699 vs. Composition 374–378, 1415–1424; `Shell.Linter.pas` 94–108 `LoadSettings`.
**Warum das ein Problem ist:** Die Kopien driften bereits: Der LSP-Server schichtet `%APPDATA%\Atlas\settings.json` unter die `atlas.json` (`SetGlobalSettings`, Composition 1447); MCP (568, 694) und Linter (104) kennen die globale Datei nicht, obwohl der Linter-Kopf verspricht „atlas.json … gilt wie im Editor“. Jede neue Log-Senke muss dreimal eingebaut werden.
**Empfehlung:** `Shell.Bootstrap` mit `CreateLogger(AOptions, AStderrLevel; out AAnonymizer)`, `CreateStdioTransport(AFraming)`, `CreateWorkspace(ARoot, AProjectFile, …)` samt globaler Einstellungen; `TFileEncoding.TryLoadFromFile` in `Atlas.Common`. Entscheiden und dokumentieren, ob Linter und MCP die globale Benutzerdatei berücksichtigen (CI eher nein, MCP eher ja).
**Konfidenz:** hoch für die Duplikate; Absicht der fehlenden globalen Datei Annahme.

#### D-09 · Duplikate innerhalb `Lsp.Completion` und eigene Zeilenhelfer statt des Dokument-Zeilenindex · Schweregrad: Niedrig · Aufwand: M
**Fundstellen:** `Atlas.Common.Lsp.Completion.pas`: DFM laden 3301–3309 = 3464–3472; innerste Klasse/Methode um eine Zeile 2895–2917, 3145–3152, 3748–3751; Vorfahrenkette `TypeChain` 3391–3406 = 3349–3356; `CollectComponents` 3240–3253 ≈ `CollectObjects` 3381–3388; `TCompletionItem` aus `TResolvedSymbol` befüllen 2963–2975, 3054–3063, 3775–3782, 1540–1552; Zeilenhelfer `LineBefore` 464–479, `LineOf` 1169, `TextLines` 2530–2538, `OffsetOf` 3864–3877, `RangeText` 3849–3861 – obwohl `ITextDocument` (`LineText` O(1), `OffsetAt`, `PositionAt` binär) in `Handle` 2348 vorliegt; `MaxDepth = 32` aus `TNameResolver` (319) in 3350/3399 wiederholt.
**Empfehlung:** `LineBreakOf` einmal je Anfrage im Request-Record, `ItemFrom(const ACandidate: TResolvedSymbol)`, `LoadFormDocument(…)`, `EnclosingTypeAt(…)`; `ITextDocument` statt `string` durch die `*Items`-Methoden reichen. Gehört zu Vorschlag 4.2.
**Konfidenz:** hoch.

#### D-10 · Geringe Duplikate: JSONC-Skipper, Versionskonstante, Content-Length-Rahmung · Schweregrad: Niedrig · Aufwand: S
**Fundstellen:** `Atlas.Core.Settings.JsonText.pas` `SkipSpace` 60–81, `StripComments` 266–312 vs. `Atlas.Common.Configuration.Internals.JsonTree.pas` `SkipSpace` 148–171 (Server meldet „Kommentar nicht abgeschlossen“ und beendet `//` an `#10` oder `#13`; Plugin läuft stumm bis Dateiende und beendet nur an `#10`); `Atlas.Core.Product.Version.pas` 11–14 vs. `Atlas.Common.Product.Version.pas` 10–14 (per `Tools/Check-Version.ps1` synchron gehalten); `Atlas.Core.Lsp.Client.pas` `Frame` 159–167, `TakeMessage` 435–467 vs. `Atlas.Common.JsonRpc.StreamTransport.pas` 125–152, 199 – kein echtes Duplikat (Push-Puffer vs. Pull-Stream), aber der Client prüft nur `BodyLength < 0` (456) und hat keine Obergrenze wie der Transport (`MaxContentLength = 256 MB`).
**Empfehlung:** JSONC-Skipper (≈ 25 Zeilen) teilen oder Plugin an Server angleichen (`#13`); Version als `{$I Atlas.Version.inc}`; im Client eine Längenobergrenze einziehen.
**Konfidenz:** hoch.

### 3.4 Architektur

Geprüft und ohne wesentlichen Befund: Objekt- vs. Interface-Referenz auf dasselbe Objekt (`FDiagnostics`/`FDiagnosticsRef`, `FLogImpl`/`FLog`, `FIde`/`FIdeRef` sind überall korrekt gepaart und kommentiert); `TObjectList.OwnsObjects` (`FWorkspaces` mit `Extract`, `FRetiredResolvers`, MCP `Others` – alle passend); Lock-Reihenfolge im Server (`FWorkspacesLock` → `Workspace.FLock`, Gegenrichtung kommt nicht vor; `FCompileLock` nie geschachtelt); Content-Length-Rahmung (Bytezählung nach UTF-8, Header+Body in einem `WriteBuffer` unter Sperre, Obergrenzen 8 KB/256 MB); OTA-Notifier-Bilanz im Plugin: 28 `Add`, 28 `Remove`, Reihenfolge „abmelden vor freigeben“ in allen Destruktoren, `FOwner := nil` vor `RemoveNotifier`, `FreeNotification` für Dock-Fenster und Statusleisten vorhanden; GDI-Handles im Plugin (Regionen, Pens, DIB-Sections, WIC-Bilder) ohne Leck je Öffnen/Schließen.

#### A-01 · Serverstart und -stopp laufen im Zeitlimit-Arbeiter statt im Hauptthread · Schweregrad: Kritisch · Aufwand: M
**Fundstelle:** `Core/Completion/Atlas.Core.Completion.Composite.pas` 228–232 (`QueryOne`: `Provider.Query` in `TAtlasTimeLimit.Run`, also im `TWorker`-Thread aus `Atlas.Core.Diagnostics.TimeLimit.pas` 31/88–132); `Core/Completion/Internals/Atlas.Core.Completion.Internals.Async.pas` 209–215 (`Query` → `Prepare`); `Core/Completion/Providers/Atlas.Core.Completion.Providers.Server.pas` 316–334 (`Prepare` → `FSession()`); `IDE/CodeInsight/Atlas.IDE.CodeInsight.Manager.pas` 863–871 (Closure liefert `SessionOrNil`), 789–795 (`SessionOrNil` → `EnsureSession`), 535–608 (`EnsureSession`), 431–451 (`StopSession`); gleicher Weg beim Parameter-Hint `Core/Signature/Atlas.Core.Signature.Providers.Server.pas` 227–234.
**Beobachtung:**
```pascal
if Assigned(FSession) then
  Session := FSession();
Result := (Session <> nil) and (AContext.FileName <> '');
...
// Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
Session.Sync(AContext.FileName, AContext.Text);
AData := Session;
```
Die Aufrufkette lautet `TAtlasTimeLimit.Run` → `Provider.Query` → `Prepare` → `FSession()` → `SessionOrNil` → `EnsureSession`. Läuft die Sitzung bereits, greifen die `MainThreadID`-Wächter in `RefreshContexts`/`RefreshProjects`/`FlushFileChanges` (713, 731, 764) und alles ist unkritisch. Läuft sie **nicht** – erster Aufruf vor dem Probleme-Timer, nach Serverabsturz, nach `SetEnabled(False)`, nach `RestartServer` –, führt der Arbeiterthread `StopSession` aus (553; darin `FCompletion.Shutdown` → `Close` → Popup, Timer, Tastatur-Hook = VCL aus dem Nebenthread), `GroupProjects` (576; `IOTAModuleServices` ohne Thread-Wächter), `ReportError` (558; `IOTAMessageServices`) und `TLspSession.Initialize` (590; blockiert bis 15 s). Der Hauptthread wartet nur 200 ms, gibt den Arbeiter dann auf (`FAbandoned := True`, TimeLimit 229) – der Arbeiter läuft weiter. Tippt der Nutzer in dieser Sekunde, kommt über `Recheck → Requery` ein zweiter Arbeiter, sieht `FSession <> nil`, aber nicht `Initialized`, und ruft erneut `StopSession` → `FreeAndNil(FSession)`/`FreeAndNil(FServer)` (449–450), während der erste noch in `FSession.Initialize` → `FClient.Request` → `TMonitor.Enter(FLock)` steckt. Dasselbe Rennen entsteht gegen den Probleme-Timer im Hauptthread (`Problems.Controller.pas` 559 → `EnsureSession`). Die Kommentare „Prepare im aufrufenden Thread (dem Hauptthread der IDE)“ (Async.pas 4) und „Im Hauptthread“ (Providers.Server.pas 331) sind seit #493 falsch.
**Warum das ein Problem ist:** Zugriff auf freigegebene `TLspSession`/`TLspClient` aus dem Arbeiter (Heap-Beschädigung im IDE-Prozess – die `except`-Klausel in `TWorker.Execute` fängt die AV, nicht die Korruption), OTA- und VCL-Aufrufe aus einem Nebenthread, und jeder Kaltstart über Vervollständigung oder Parameter-Hint zählt als „Zeitlimit überschritten“ gegen die Quelle (Composite 250, Signature 236–239) – drei Starts in fünf Minuten schalten die Server-Quelle ab.
**Empfehlung:** Die an Provider gereichte `TAtlasSessionFunc` darf nie starten: in `Completion`/`Signature` (Manager 847–851, 867–871) `RunningSession` statt `SessionOrNil` übergeben. Den Start explizit im Hauptthread anstoßen, bevor der Controller fragt (`InvokeCodeCompletion`/`OpenCompletion`/`InvokeParameterCodeInsight`/`OpenSignature` rufen zuerst `EnsureSession`; bei Bedarf asynchron mit Phase `Starting` und Popup „Server startet“). Schutz in `EnsureSession` und `StopSession`: `if GetCurrentThreadId <> MainThreadID then Exit(RunningSession <> nil);`. Kommentare korrigieren. DUnitX-Test, der `TAtlasAsyncCompletionProvider.Query` mit einem `Prepare` aufruft, das die Thread-ID protokolliert. Siehe Vorschlag 4.1.
**Konfidenz:** hoch für den Mechanismus (Aufrufkette am Code nachvollzogen); Häufigkeit hängt davon ab, wie oft der Server beim Tippen nicht läuft.

#### A-02 · `TThread.Queue(nil, …)` aus Arbeiterthreads: eingereihte Closures überleben das Entladen des Packages · Schweregrad: Hoch · Aufwand: S
**Fundstelle:** 31 Stellen `TThread.Queue(nil, …)`/`ForceQueue(nil, …)` im Plugin, darunter aus Arbeiterthreads: `IDE/Hover/Atlas.IDE.Hover.Editor.pas` 554–566; `Core/Completion/Providers/Atlas.Core.Completion.Providers.Server.pas` 509–515; `Core/Signature/Atlas.Core.Signature.Providers.Server.pas` 274–284; `Core/Completion/Atlas.Core.Completion.Controller.pas` 231, 254, 277; `IDE/CodeInsight/Atlas.IDE.CodeInsight.Manager.pas` 648, 689 (aus dem Lese-Thread). Gegenbeispiel im selben Repo: `IDE/Problems/Atlas.IDE.Problems.Controller.pas` 218–231 (`Queue` am eigenen Thread) + 414–418 (`RemoveQueuedEvents(Thread)`); `IDE/Updates/Atlas.IDE.Updates.Check.pas` 228–232 (`TThread.Queue(TThread.Current, …)`).
**Beobachtung:**
```pascal
Show :=
  procedure
  begin
    if not Alive.Alive or (AliveRef = nil) or (Owner.FRequest <> Request) or (Owner.FKey <> Key) then
      Exit;
    TAtlasGuard.Run(TAtlasFeature.Hover,
      procedure
      begin
        Owner.ShowData(Data);
      end);
  end;
TThread.Queue(nil, Show);
```
**Warum das ein Problem ist:** Die Alive-Token schützen vor dem freigegebenen Zielobjekt, nicht vor dem entladenen Code. Ein mit `nil` eingereihter Eintrag gehört keinem Thread; `TThread.Destroy` (→ `RemoveQueuedEvents(Self)`) in `ReapWorkers(True)`/`Shutdown` räumt ihn nicht weg. Reiht ein Worker kurz vor `Unregister` ein und das `WM_NULL` ist noch nicht verarbeitet, ruft `CheckSynchronize` nach dem Entladen der BPL einen Closure-Rumpf in nicht mehr gemappten Speicher – Zugriffsverletzung beim Entladen oder Schließen der IDE, nicht abfangbar, nicht reproduzierbar.
**Empfehlung:** In allen Worker-Threads `TThread.Queue(TThread.Current, …)` verwenden (anonyme Threads sind `TThread`-Instanzen; ihre `Destroy` räumt die Einträge ab). Für den LSP-Lese-Thread dasselbe (`TThread.Current` ist dort `TReaderThread`, der in `TLspServerProcess.Destroy` 267–271 vor `FClient.Free` freigegeben wird). `RemoveQueuedEvents(nil)` ist keine Option (entfernt Einträge aller Threads im IDE-Prozess). Das Muster aus `Problems.Controller`/`Updates.Check` in `docs/Architektur.md` festhalten.
**Konfidenz:** hoch für den Mechanismus; mittel für die Trefferwahrscheinlichkeit (Millisekundenfenster).

#### A-03 · Indexaufbau wird aus Worker- und Lese-Thread neu gestartet (Schnellbefehle `/config`, `/define`, `/searchpath`); Namespaces-Arrays ohne Sperre ersetzt · Schweregrad: Hoch · Aufwand: M
**Fundstelle:** `Atlas.Common.Lsp.Formatting.pas` 97 (`RegisterConcurrentRequest(OnTypeMethod, …)`), 145–147 (`AfterEnter(… FSlashHost)`); `Atlas.Common.Editing.ProjectCommands.pas` 77–81, 160–164; `Shell.SlashHost.pas` 109–125 (`WriteThroughClient`: laut eigenem Kommentar im Lese-Thread), 160–171, 178–186; `Shell.Workspace.pas` 419–423 (`Reload`), 571–577, 1051–1061 (`StartIndex`); `Shell.Composition.pas` 2146–2157 (`ProjectLoaded`); gleiches Muster `Atlas.Common.Lsp.Completion.pas` 219/362/2372 (`FNamespaces`), `References.pas` 45/289, SemanticTokens, Hover.
**Beobachtung:** (`Shell.Workspace.pas` 1051–1061, ohne Sperre)
```pascal
if State = FSignature then
  Exit;
FSignature := State;
FIndexService.Stop;
Resolver := TUnitResolver.Create(Project, LibraryPaths, FileExistsFunc);
...
if FUnitResolver <> nil then
  FRetiredResolvers.Add(FUnitResolver);
FUnitResolver := Resolver;
```
und (`Shell.Composition.pas` 2146–2151)
```pascal
FDefinition.Namespaces := Namespaces;
FHover.Namespaces := Namespaces;
FDocumentHighlights.Namespaces := Namespaces;
FReferences.Namespaces := Namespaces;
FRename.Namespaces := Namespaces;
FCompletion.Namespaces := Namespaces;
```
Aufrufkette: `textDocument/onTypeFormatting` ist ein nebenläufiger Handler → `TSlashCommandRegistry.AfterEnter` → `Context.Actions.Run` → `ISlashHost.SelectBuild`/`WriteProject` → `TShellWorkspace.Reload` → `StartIndex` – im Thread-Pool-Thread.
**Warum das ein Problem ist:** `StartIndex` setzt voraus, nur im Thread der Nachrichtenschleife zu laufen (`FSignature`, `FUnitResolver`, `FRetiredResolvers`, `FIndexService.Stop/Start` mit `FreeAndNil(FThread)` – alles ohne Sperre). Läuft parallel ein `StartIndex` aus der Schleife (Dateibeobachter, `didChangeConfiguration`), drohen Doppel-Free des Index-Threads und kaputte Listen. `ProjectLoaded` ersetzt zudem dynamische Arrays, während Worker sie in `Resolver.Namespaces := FNamespaces` kopieren – die Zuweisung eines `TArray<string>` ist nicht atomar (Refcount-Dec des alten, Inc des neuen Arrays): echtes Race mit möglichem Absturz in allen zwölf Features. Selten (nur per Schnellbefehl bzw. Projektwechsel), aber real.
**Empfehlung:** Reload/SelectBuild aus dem Slash-Host nicht direkt ausführen, sondern wie der Dateibeobachter in die Schleife stellen (`FConnection.Post(TJsonRpcMessages.Notification('atlas/reloadWorkspace', …))` mit internem Handler). Namespaces als unveränderliches Objekt hinter einer Interface-Referenz übergeben und per `TInterlocked.Exchange` oder unter dem bestehenden `FCacheLock` setzen; alternativ lesen die Features die Namespaces je Anfrage über `NamespacesFor(Uri)` wie `MatchingFor`. Invariante „StartIndex nur im Schleifen-Thread“ als Test (Aufruf aus `TTask`) absichern.
**Konfidenz:** hoch (Pfad vollständig im Code nachvollzogen).

#### A-04 · Ausnahme im Index-Thread lässt `FProjectPending` und den Fortschritt dauerhaft hängen · Schweregrad: Hoch · Aufwand: S
**Fundstelle:** `Atlas.Common.Index.Service.pas` 290–340 (`Run`), 336–340; `Shell.Workspace.pas` 337–351 (`OnProjectReady`/`OnFinished`), 1141–1142; `Shell.Composition.pas` 1660–1677; `Lsp.PullDiagnostics.pas` 404–409.
**Beobachtung:**
```pascal
if not BuildResult.Cancelled then
  WriteCaches(ARequest, Cached, LibraryCached, BuildResult.Parsed - WrittenParsed);
if Assigned(FOnFinished) then
  FOnFinished(BuildResult, Watch.ElapsedMilliseconds);
except
  on E: Exception do
    if Assigned(FOnError) then
      FOnError(E);
end;
```
`FProjectPending := True` wird nur in `OnProjectReady`/`OnFinished` zurückgesetzt; ist `FOnError` nicht zugewiesen, verschwindet die Ausnahme ohne Spur.
**Warum das ein Problem ist:** Wirft `WriteCaches` (Platte voll, Virenscanner sperrt die Cache-Datei), `ReadCache` oder `Builder.Build`, bleibt `FProjectPending` True → `workspace/diagnostic` meldet bis zum nächsten Reload nur `indexLoading` (Problemansicht bleibt leer), `IndexFinished` ruft `RefreshLater` nie, `$/progress` endet nie. Der Server wirkt dauerhaft „beschäftigt“.
**Empfehlung:** Im `except` von `TIndexService.Run` ein Abschlussereignis auslösen (`FOnFinished` mit `Cancelled := True` oder neues Feld `Failed`); in `TShellWorkspace` dort `FProjectPending := False` und `FProgress.Finish('Fehlgeschlagen')`. Test: Builder-Dateisystem, dessen `WriteBytes` wirft → `ProjectPending` muss False werden.
**Konfidenz:** hoch für `FProjectPending`; Fortschritts-„end“ Annahme.

#### A-05 · `Shell.Composition.Destroy`: Diagnoselog wird freigegeben, bevor die Index-Threads stehen; Destruktor nicht nil-sicher; dcc32 wartet ohne Abbruch · Schweregrad: Mittel · Aufwand: S
**Fundstelle:** `Shell.Composition.pas` 1252–1325 (`Destroy`), 1263–1274; `Shell.Workspace.pas` 346–354 (`OnFinished` ruft `IndexEvent` auch bei `Cancelled`); `Atlas.Windows.Compiler.Adapters.ProcessRunner.pas` (`WaitForSingleObject(…, INFINITE)`).
**Beobachtung:**
```pascal
FDispatcher.Observer := nil;
FDiagnostics := nil;
FDiagnosticsRef := nil;
// Laufenden Compilerlauf abwarten: Er meldet über die Syntaxprüfung.
if FCompileThread <> nil then
begin
  FCompileThread.WaitFor;
  FreeAndNil(FCompileThread);
end;
// Index-Threads vor der Syntaxprüfung anhalten: Ein fertiger Aufbau meldet sich dort (IndexFinished).
for Workspace in FWorkspaces do
  Workspace.Stop;
```
**Warum das ein Problem ist:** `FDiagnostics := nil` plus `FDiagnosticsRef := nil` gibt das Objekt frei (Refcount 2 → 0); erst danach stoppt `Workspace.Stop` die Index-Threads. Der Abbruch führt deterministisch zu `OnFinished` → `IndexEvent(… cancelled)` → `FDiagnostics.Log.LogEvent` mit `FDiagnostics = nil` → Zugriffsverletzung im Index-Thread, die `TIndexService.Run` fängt und als „Fehler beim Aufbau des Symbolindex“ protokolliert – bei jedem Beenden während eines Aufbaus ein falscher Fehlereintrag. Fliegt in `Create` vor Zeile 483 eine Ausnahme, laufen `FDispatcher.Observer := nil` (1263), `for Workspace in FWorkspaces` (1273) und `FDispatcher.Watchdog := nil` (1320) auf nil-Felder. `FCompileThread.WaitFor` wartet unbegrenzt auf dcc32.
**Empfehlung:** Reihenfolge: erst `Workspace.Stop` und Compile-Thread, dann `Observer := nil`/`FDiagnostics := nil`. Destruktor nil-sicher (`if FDispatcher <> nil then …`). Für dcc32 ein Stop-Ereignis an `ICompilerProcess.Run` (`WaitForMultipleObjects` wie im `ParentWatcher`) und `TerminateProcess` beim Beenden.
**Konfidenz:** hoch.

#### A-06 · Watchdog bricht nicht ab: kein Fehler an den Client, Handler ohne Token-Prüfung belegen den Pool, Use-after-free beim sauberen `exit` möglich · Schweregrad: Mittel · Aufwand: M
**Fundstelle:** `Atlas.Common.JsonRpc.Watchdog.pas` 163–172 (`Expire`); `Atlas.Common.JsonRpc.Dispatcher.pas` 419–432 (Watch auch für synchrone Handler ohne Token-Parameter); `Atlas.Common.Lsp.Formatting.pas` 245–255 (Token ungenutzt, 0 Treffer auf `Cancellation` in der Unit); `Shell.Composition.pas` 341–345, 1590–1631 (`EnsureUnit` ohne Token); `Atlas.Common.JsonRpc.Connection.pas` 492–494 (`WaitForWork(5000)`).
**Beobachtung:**
```pascal
procedure TJsonRpcWatchdog.Expire(const AEntry: TEntry);
begin
  try
    FPending.Cancel(AEntry.Id);
    if Assigned(FOnTimeout) then
      FOnTimeout(AEntry.Method, Timeout);
  finally
    AEntry.Id.Free;
  end;
end;
```
**Warum das ein Problem ist:** Der Watchdog setzt nur das Token. Synchrone Handler (`initialize`, `workspace/executeCommand`, alle MCP-Werkzeuge) bekommen gar kein Token; das Log meldet trotzdem „abgebrochen (Zeitlimit)“. Formatting und alle Pfade über `EnsureUnit` (Parsen einer Bibliotheks-Unit) prüfen kein Token; der Worker bleibt belegt, der Client wartet weiter, es gibt keine Fehlerantwort. Nach `WaitForWork(5000)` gibt `Destroy` die Feature-Objekte frei, während ein nicht kooperierender Worker noch darauf arbeitet.
**Empfehlung:** Beim Ablauf sofort `RequestCancelled` antworten und die späte Antwort verwerfen (`Release` liefert False, wenn bereits beantwortet; `Responder` nur bei True); `TEnsureUnitFunc` um das Token erweitern bzw. `EnsureUnit` vor dem Parsen `ThrowIfCancellationRequested` aufrufen lassen; Formatting-Handler das Token an `TSyntaxTreeCache.Get` durchreichen (wie References/Rename). Logtext in „Abbruch angefordert“ ändern, solange nicht wirklich abgebrochen wird. Eigener `TThreadPool` mit `MaxWorkerThreads` statt `TThreadPool.Default`.
**Konfidenz:** hoch für Token und Use-after-free; Pool-Verhalten Annahme.

#### A-07 · `StopSession` wartet nicht auf laufende Hover-Anfragen · Schweregrad: Mittel · Aufwand: S
**Fundstelle:** `Atlas.IDE.CodeInsight.Manager.pas` 431–451 (`StopSession`), 483–489 (`RestartServer`), 1026–1032 (`SetEnabled`); `Atlas.IDE.Hover.Editor.pas` 541–570 (Worker hält `Session` als rohen Zeiger), 269–296 (`Destroy` wartet mit `ReapWorkers(True)`).
**Beobachtung:**
```pascal
procedure TAtlasCodeInsightManager.StopSession;
begin
  // Laufende Anfragen der Vervollständigung nutzen die Sitzung noch.
  if FCompletion <> nil then
    FCompletion.Shutdown;
  if FSignature <> nil then
    FSignature.Shutdown;
  ...
  FQueryIdle.WaitFor(5000);
  FreeAndNil(FSession);
  FreeAndNil(FServer);
end;
```
**Warum das ein Problem ist:** Vervollständigung, Parameter-Hint, Probleme und Statusabfrage werden abgewartet, `FHover` nicht. Beim Entladen ist das unkritisch (Destroy gibt `FHover` vor `StopSession` frei), bei Neustart über das Statusfeld, `SetEnabled(False)` und dem Neustart in `EnsureSession` (553) nicht: Ein Hover-Worker in `Session.HoverDataAt` (3 s Zeitlimit) räumt nach `Client.Close` noch `FPending`/`FLock` des `TLspClient` auf, während `FreeAndNil(FSession)` und `FClient.Free` laufen.
**Empfehlung:** `TAtlasEditorHover.Shutdown` (nur `ReapWorkers(True)`) einführen und in `StopSession` vor `FServer.Client.Close` aufrufen – Reihenfolge wie `FCompletion.Shutdown`.
**Konfidenz:** hoch, dass nicht gewartet wird; mittel für die praktische Trefferwahrscheinlichkeit.

#### A-08 · Der Host ist leer; der Fachcode liegt im Platform-Package · Schweregrad: Hoch · Aufwand: XL
**Fundstelle:** `Application/Source` enthält nur `Shell/` (9 Units). `Packages/Atlas.Common/Source/Lsp` (57 Units, 20 096 Zeilen), `Rules` (41, 14 908), `Editing` (43, 16 141), `Semantics` (4, 4 560), `Mcp` (8, 2 300). Konzept 6.2: Ein Platform-Package „enthält ausschließlich Platform-Features“; 6.1: Platform-Features „stellen technische Abstraktionen und Implementierungen bereit“. Die eigene `docs/Architektur.md` (Zeile 285) ordnete LSP-Methoden ursprünglich `AtlasServer, Hosted-Features` zu und nennt Rules und Semantics in Zeile 117–118 selbst „Fachlogik“.
**Beobachtung:** Ein Hover-Handler, eine SQL-Injection-Regel oder ein `/prop`-Refactoring sind keine technischen Abstraktionen; sie sind das Produkt. Rund 58 000 Zeilen Fachcode liegen in einem Package, das sich „Platform“ nennt, und der Host hat weder `Foundation`, `Core`, `Adapters` noch ein einziges Hosted-Feature.
**Warum das ein Problem ist:** Drei konkrete Folgen: (1) `TServerComposition` muss alles selbst zusammenstecken und ist deshalb 2 687 Zeilen groß (S-02); es gibt keine Feature-eigene `Composition`, die die Shell als Default aufrufen könnte. (2) Die Feature-Matrix 8.2 würde `Rules` ⇄ `Editing` verbieten – als Platform-Features dürfen sie sich gegenseitig importieren, und genau so entstand der einzige Zyklus im Server (A-11). (3) Konzeptziel „Modularität“: Ein Fachcode-Package (`ASAG`-Beispiel des Konzepts) für einen zweiten Host ist heute nicht abspaltbar, weil Fach- und Technikcode im selben Artefakt liegen. Die Importmatrix an sich ist mit 15 Verstößen bei 2 003 Imports fast sauber (Anhang 7.2); das Problem ist der Zuschnitt, nicht die Disziplin.
**Empfehlung:** `Lsp`, `Rules`, `Semantics`, `Editing`, `Mcp` als Hosted-Features nach `Application/Source/Features/<Name>/` mit eigener `Composition`; `Atlas.Common` behält Pascal, Documents, JsonRpc, Logging, Projects, Configuration, Dfm, Index, Compiler, Diagnostics. Laufzeit-Orchestrierung (`TShellWorkspace`, Compile-Loop, Settings je URI) nach Host-`Core`. Vorschlag 4.5 beschreibt den Weg in kompilierbaren Schritten.
**Konfidenz:** hoch (Zuordnung aus dem Konzepttext); der Aufwand ist eine Schätzung.

#### A-09 · Das Plugin umgeht das Namensschema; alle 17 `Atlas.IDE.*`-Features bilden einen Zyklus · Schweregrad: Mittel · Aufwand: L
**Fundstelle:** `Packages/Atlas.IDE.Expert/Source/{Core,UI,IDE}`; `docs/Architektur.md` Zeile 73 („Ausnahme Plugin (#406)“); Tarjan-Analyse der Feature-Abhängigkeiten (Abschnitt 2.3): `Atlas.IDE.{Build, CodeInsight, Commands, Completion, Diagnostics, Editor, Files, Hover, InlayHints, Problems, Results, Settings, Signature, Status, Style, Undo, Updates}` und `Atlas.Core.{Completion, Editor, Lsp, Problems, Results}`; Analyzer-Ergebnis: 9 der 15 Importverstöße sind `Atlas.IDE.*` → `Atlas.Core.*.Providers/Adapters`.
**Beobachtung:** `Atlas.Core.Completion.Providers.Server` ist nach Konzept 6.3 nicht parsebar: Das Ausgabeartefakt müsste `Atlas.IDE.Expert` heißen; `Core` ist eine reservierte Host-Rolle mit anderer Bedeutung. Die IDE-Schicht importiert Provider und Adapter der Core-Schicht direkt – sie verhält sich wie eine Host-Shell, ist aber als Feature benannt. Innerhalb der IDE-Schicht hängt jedes Feature an jedem anderen (z. B. `Editor` → `Undo` → `Results` → `Hover` → `Editor`). Gleiches beim Installer: `Setup.Core.Contract` kombiniert Host-Rolle und Feature-Rolle.
**Warum das ein Problem ist:** Die Schichten Core/UI/IDE sind sinnvoll und per Skript geprüft, aber der 17er-Zyklus bedeutet, dass kein IDE-Feature isoliert gebaut oder getestet werden kann; die Architekturdoku nennt als Ziel, Core und UI später „ohne Codeänderung in ein Runtime-Package auszulagern“ – das Namensschema verhindert den Zyklus dort nicht.
**Empfehlung:** Schichten als Ausgabeartefakte modellieren (`Atlas.IDE.Expert.Core.*`, `.UI.*`, `.IDE.*`) oder ehrlicher drei Packages (`Atlas.Plugin.Core` als Runtime-Package, `Atlas.Plugin.UI`, `Atlas.IDE.Expert` als Design-Time-Host mit Rollen `Shell`/`Core`/`Adapters`). Den Zyklus über eine Host-`Foundation` auflösen: die Interfaces, die alle IDE-Features gemeinsam brauchen (`TAtlasIdeSettings.Current`, Diagnose, Style, Strings), dorthin ziehen.
**Konfidenz:** hoch (Graph berechnet).

#### A-10 · 15 Verstöße gegen die Importmatrix; vier Contract-Units mit Implementierung; `Rules.Contract` koppelt an den `NameResolver` · Schweregrad: Mittel · Aufwand: S
**Fundstelle:** Vollständige Liste in Anhang 7.2. Contract-Verstöße gegen 7.1: `Atlas.Common.Dfm.Contract.pas` 30 (`TDfmObject = class`), 54 (`TDfmDocument = class`); `Atlas.Common.Index.Contract.pas` 208 (`TIndexFiles = class`); `Atlas.Core.Undo.Contract.pas` 122 (`TAtlasUndoNames = class` mit 11 Routinen); `Atlas.Common.Rules.Contract.pas` 10–16 (`uses … Atlas.Common.Pascal.SyntaxTree, Atlas.Common.Semantics.NameResolver`); `Atlas.Core.Undo.Contract` → `Atlas.Core.Files.TextFile`; `Atlas.Common.Logging.Providers.StreamSink` → `Providers.RotatingFileStream`; `Atlas.Core.Signature.Providers.Server` → `Atlas.Core.Completion.Providers.Server`; `Atlas.IDE.CodeInsight.Composition` → `Atlas.Core.Updates.Adapters.HttpSource`.
**Warum das ein Problem ist:** Konzept 7.1 lässt im Contract nur Value-Typen, Interfaces, Exceptions, Enums und RTL-Typen zu. Jeder Konsument von `Rules.Contract` zieht 2 854 Zeilen Namensauflösung mit – auch der, der nur `TRuleDescriptor` braucht. `Providers → Providers` ist in jeder Matrix verboten; `RotatingFileStream` gehört nach `Internals` oder als Sub-Struktur unter `StreamSink` (7.4).
**Empfehlung:** `TDfmObject`/`TDfmDocument`/`TIndexFiles`/`TAtlasUndoNames` hinter Interfaces oder nach Root; `IRuleContext`-Interface statt der konkreten Resolver-Klasse im `Rules.Contract`; `RotatingFileStream` nach `Logging.Internals`; die neun Plugin-Verstöße lösen sich mit A-09.
**Konfidenz:** hoch (mechanisch geprüft, Script in Anhang 7.4).

#### A-11 · `Atlas.Common.Editing` ⇄ `Atlas.Common.Rules` – der einzige Zyklus im Server · Schweregrad: Mittel · Aufwand: M
**Fundstelle:** `Editing.CollectionCommands`, `Editing.UsesCommand`, `Editing.ProjectCommands` → `Rules.Contract`; `Rules.Profiles` → `Editing.UsesClause`; `Rules.Builtin.SlashCommands` → `Editing.SlashCommands`; `Rules.Builtin.Architecture` → `Editing.UsesClause`.
**Warum das ein Problem ist:** Die Grenze zwischen „Text verändern“ und „Text prüfen“ ist nicht fachlich gezogen; `Editing` ist mit 43 Units ein Sammelordner für alles, was Text schreibt. Keines der beiden Features ist ohne das andere übersetzbar.
**Empfehlung:** `UsesClause` (Parsen/Schreiben der uses-Klausel) und `SlashCommands`-Registry sind Infrastruktur beider Seiten → eigenes kleines Feature `Atlas.Common.Uses` bzw. `Atlas.Common.Commands.Contract`; die drei Editing-Befehle, die `Rules.Contract` brauchen, nehmen `TRuleDescriptor` über ein Interface entgegen.
**Konfidenz:** hoch.

#### A-12 · Die Rollenmatrix wird nicht automatisiert geprüft – ausgerechnet vom Linter-Projekt · Schweregrad: Mittel · Aufwand: S
**Fundstelle:** `Tools/Check-PackageDependencies.ps1` (186 Zeilen; prüft nur Package-Grenzen: kein Windows in Common, keine VCL in Windows, Schichten Core/UI/IDE); `Atlas.Common.Rules.Builtin.Architecture.pas` (prüft andere Regeln); Konzept Ziel 2 „Code-Analyse ohne manuelles Review“.
**Warum das ein Problem ist:** Das Projekt hat Parser, Symbolindex und uses-Auswertung; eine Regel `architecture-role-import` mit Whitelist der Präfixe wäre ein Nachmittag und würde Ziel 2 des Konzepts erfüllen. Die 15 Verstöße in Anhang 7.2 sind über Monate unbemerkt entstanden.
**Empfehlung:** Das Python-Skript aus diesem Review (Anhang 7.4) als Vorlage für eine Atlas-Regel in `Builtin.Architecture` nehmen und in `Check-PackageDependencies.ps1` aufrufen. Siehe Vorschlag 4.6.
**Konfidenz:** hoch.

#### A-13 · Zeitlimit-Arbeiter: nach Ablauf oder Abbruch arbeitet der Arbeiter voll weiter; beim Entladen bleibt er mit `FreeOnTerminate` sich selbst überlassen · Schweregrad: Niedrig · Aufwand: S
**Fundstelle:** `Atlas.Core.Diagnostics.TimeLimit.pas` 203–240 (`Run`), 252–282 (`StopAll`, 275–281); `Atlas.Core.Completion.Internals.Async.pas` 209–261 (`Query` prüft nach `Prepare` die Generation nicht); `Atlas.Core.Diagnostics.Shutdown.pas` 107–122 (`WaitForThreads` pollt mit `Sleep(5)`).
**Beobachtung:**
```pascal
Result := TAtlasShutdown.WaitForThreads(Threads, AMs);
for Worker in Workers do
  if Worker.Finished then
    Worker.Free
  else
    // Hängt im Aufruf einer Quelle: gibt sich selbst frei, sobald er zurückkehrt.
    Worker.FreeOnTerminate := True;
```
**Warum das ein Problem ist:** Verschwendete Serverlast beim schnellen Tippen (jede Neuabfrage nach Zeitlimit löst eine Vollanfrage `textDocument/completion` aus, `$/cancelRequest` geht nicht raus); theoretischer Absturz beim Entladen, falls ein Arbeiter länger als 1 s in nicht abbrechbarem Code steckt – sein `Execute`/`Destroy` liegt dann in der entladenen BPL.
**Empfehlung:** In `Query` nach `Prepare`: `if not IsCurrent(Generation) then begin ASink.Complete; Exit; end;`; in `StopAll` mit `WaitForMultipleObjects` nachwarten und hängende Arbeiter protokollieren statt `FreeOnTerminate`.
**Konfidenz:** hoch (gelesen); Entlade-Fall Annahme gering.

### 3.5 Dokumentation

Zahlen: `/// <summary>` an öffentlichen Deklarationen – `Atlas.Common` 51 %, `Atlas.Windows` 50 %, `Atlas.IDE.Expert` 46 %. Unit-Kopfkommentar in 413 von 413 Units. Auskommentierter Code: keiner. Offene `TODO`/`FIXME`/`HACK`: keine (die 15 Grep-Treffer sind generierter Text der Refactoring-Befehle und der `/todo`-Befehl). Stichprobe von fünf Units (`Configuration.Internals.JsonTree`, `JsonRpc.Messages`, `Pascal.SyntaxTree`, `Core.Completion.Providers.XmlDoc`, `IDE.Completion.History`): Die Kopfkommentare erklären durchweg das Warum und tragen Issue-Nummern; Rauschkommentare sind selten. README und README_DE enthalten Installationsanleitung (Schritte 1–6), Feature-Liste, Aufbau-Tabelle und Linter-Beispiele; `docs/adr/README.md` ist konsistent, 0003 → 0010 korrekt als „ersetzt“ mit Nachtrag. Das ist eine überdurchschnittliche Dokumentationskultur; die folgenden Befunde sind Abweichungen davon.

#### K-01 · Kopfkommentar von `SymbolIndex` verspricht Nachschlagetabellen für Symbolnamen, die es nicht gibt · Schweregrad: Mittel · Aufwand: S
**Fundstelle:** `Atlas.Common.Index.SymbolIndex.pas` Zeile 3–5 („Symbolnamen und Vorfahren werden beim Hinzufügen einer Unit in Nachschlagetabellen eingetragen“) vs. `AddLocked` 130–141 (füllt nur `FFiles` und `FUnitFiles`), `FindSymbols` 262–273 und `Descendants` 275–287 (linear über alle Symbole aller Units, Kommentar 241–242 nennt „über 500.000“).
**Warum das ein Problem ist:** Wer den Kopf liest, erwartet O(1)-Suche und nutzt `FindSymbols` in Regeln und Vervollständigung entsprechend (P-12, P-03) – an 28 Stellen.
**Empfehlung:** Entweder den Kopf korrigieren („lineare Suche auf Schnappschuss; Namensindex nur für Importe in `NameIndex`“) oder – besser – die versprochene Tabelle tatsächlich pflegen (P-12).
**Konfidenz:** hoch.

#### K-02 · ADR 0006 widerspricht dem Code; der Code zitiert ADR 0006 für das Gegenteil · Schweregrad: Mittel · Aufwand: S
**Fundstelle:** `docs/adr/0006-ide-plugin.md` Zeile 28 („Die Protokollschicht `Atlas.Common.JsonRpc.*` wird wiederverwendet“); `Packages/Atlas.IDE.Expert/Atlas.IDE.Expert.dpk` 43–47 (kein `Atlas.Common`); eigener Client `Atlas.Core.Lsp.Client.pas`; `Atlas.Core.Diagnostics.BugReport.pas` 10–11 („das Plugin bindet Atlas.Common nicht ein, ADR 0006“); `docs/Architektur.md` Zeile 17 („eigenständig, damit die IDE nur ein BPL laden muss“); die Fortschreibung in 0006 Zeile 56–62 erwähnt die Entscheidung nicht.
**Warum das ein Problem ist:** Genau diese Entscheidung ist die Ursache aller Duplikate aus 3.3; sie ist nirgends als ADR festgehalten, nur als Nebensatz in `Architektur.md`, und das zitierte ADR sagt das Gegenteil.
**Empfehlung:** Nachtrag in ADR 0006 oder neues ADR 0011 „Plugin ohne Atlas.Common; gemeinsamer Code in Atlas.Text“ mit Status, Grund („ein BPL“) und der gewählten Teilungsstrategie (Vorschlag 4.3).
**Konfidenz:** hoch.

#### K-03 · Kommentare behaupten „im Hauptthread“, wo seit #493 ein Arbeiterthread läuft · Schweregrad: Mittel · Aufwand: S
**Fundstelle:** `Atlas.Core.Completion.Internals.Async.pas` Zeile 4 („Prepare im aufrufenden Thread (dem Hauptthread der IDE)“); `Atlas.Core.Completion.Providers.Server.pas` 331 („Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.“).
**Warum das ein Problem ist:** Beide Kommentare haben die Fehlerursache von A-01 unsichtbar gemacht: Wer `Prepare` liest, verlässt sich auf die Zusicherung und prüft die Aufrufkette nicht.
**Empfehlung:** Mit A-01 zusammen korrigieren; die Thread-Zusicherung in einen Laufzeit-Check (`Assert(GetCurrentThreadId = MainThreadID)` im Debug-Build) überführen, dann kann der Kommentar nicht mehr lügen.
**Konfidenz:** hoch.

#### K-04 · Verwaiste und doppelte `/// <summary>` an neun Stellen · Schweregrad: Niedrig · Aufwand: S
**Fundstelle:** `Rules.Contract.pas` 64–65 (Summary „Alles, was eine Regel … wissen darf“ hängt an `TRuleFileReader`, `TRuleContext` 68 bleibt ohne Doku) und 95–96; `Rules.Engine.pas` 45–46 (Summary von `IsExceptedByOptions` steht über `CapSeverity`); `Index.Extractor.pas` 91–93 (drei Summaries hintereinander); `Lsp.Completion.pas` 985–986 (verwaiste „Punktzahl von AName“ über `PlainType`), 2271; `Lsp.CodeActions.pas` 31–32; `IDE.CodeInsight.Composition.pas` 208.
**Warum das ein Problem ist:** Help Insight und der eigene XmlDoc-Hover zeigen falsche Texte; Zeichen für Umbauten ohne Kommentarpflege.
**Empfehlung:** Bereinigen; eine Atlas-Regel „zwei `<summary>` ohne Deklaration dazwischen“ wäre ein Fünfzeiler auf dem eigenen Parser.
**Konfidenz:** hoch.

#### K-05 · Cache-Formatversion in ADR 0010 und `Architektur.md` veraltet · Schweregrad: Niedrig · Aufwand: S
**Fundstelle:** `docs/adr/0010-binaerer-index-cache.md` Zeile 13 („derzeit 12“); `docs/Architektur.md` 257 („Formatversion 12“); Code `Atlas.Common.Index.Cache.pas` 73 `FormatVersion = 15`.
**Empfehlung:** Zahl streichen („siehe `TIndexCache.FormatVersion`“) oder per Skript erzeugen wie `Update-ConfigDoc.ps1`.
**Konfidenz:** hoch.

#### K-06 · README/README_DE widersprechen sich zur Plattform des Plugins · Schweregrad: Niedrig · Aufwand: S
**Fundstelle:** `README_DE.md` Zeile 67 („Designtime-Package, Win32“) und 81 („nur für Win32 eingerichtet (die IDE ist 32-Bit)“) vs. Zeile 30/40 derselben Datei (Win32 und Win64), `docs/adr/0008-plattformen.md` 12/22/26, `docs/Architektur.md` 17; `README.md` analog 67/82.
**Empfehlung:** Beide Stellen auf „Win32 (klassische IDE) / Win64 (64-Bit-IDE ab 12.3)“ angleichen.
**Konfidenz:** hoch.

---

## 4. Verbesserungsvorschläge mit Konzept

Aus den 53 Befunden sind sechs Maßnahmen ausgewählt, die zusammen den größten Teil der Wirkung tragen. Die Codeskizzen sind in Object Pascal für Delphi 12 geschrieben (keine `if`-Ausdrücke, kein `is not`, kein `not in`); sie konnten in dieser Sitzung nicht mit `check_code` geprüft werden und sind als Gerüst zu lesen, nicht als fertige Units.

### 4.1 Plugin-Stabilität: Serverstart nur im Hauptthread, Queue-Einträge an den eigenen Thread binden  (Nutzen: sehr hoch · Aufwand: M)

**Ziel.** Kein OTA-/VCL-Aufruf und kein `FreeAndNil(FSession)` außerhalb des Hauptthreads; keine eingereihte Closure überlebt das Entladen des Packages. Erfolg ist erkennbar, wenn ein DUnitX-Test die Thread-ID in `Prepare` prüft und die IDE auch dann sauber entlädt, wenn ein Worker Millisekunden vorher eingereiht hat.

**Ist.** A-01 (Serverstart im Zeitlimit-Arbeiter), A-02 (31 × `TThread.Queue(nil, …)`), A-07 (Hover nicht abgewartet), S-05 (Closures ohne Guard), K-03 (irreführende Kommentare).

**Soll.** Provider erhalten eine Sitzungsfunktion, die nur noch liefert, nie startet; der Start ist ein expliziter Hauptthread-Schritt vor dem Controller; Worker reihen an sich selbst ein.

```pascal
// Atlas.IDE.CodeInsight.Manager
function TAtlasCodeInsightManager.RunningSession: TLspSession;
begin
  if (FServer <> nil) and FServer.Running and (FSession <> nil) and FSession.Initialized then
    Result := FSession
  else
    Result := nil;
end;

function TAtlasCodeInsightManager.EnsureSession: Boolean;
begin
  // Start und Stopp gehören dem Hauptthread; Arbeiter bekommen nur, was läuft.
  if GetCurrentThreadId <> MainThreadID then
    Exit(RunningSession <> nil);
  ...
end;

function TAtlasCodeInsightManager.Completion: TAtlasEditorCompletion;
begin
  if FCompletion = nil then
    FCompletion := TAtlasEditorCompletion.Create(RunningSession, Diagnose);  // Methodenzeiger statt Closure
  Result := FCompletion;
end;

// Einstiegspunkt im Hauptthread, bevor der Controller fragt:
procedure TAtlasCodeInsightManager.InvokeCodeCompletion(...);
begin
  if not EnsureSession then
  begin
    SetPhase(TAtlasServerPhase.Starting, 'Server startet …');
    Exit;
  end;
  Completion.Invoke(View, False);
end;

// Alle Worker: an den eigenen Thread binden, damit TThread.Destroy aufräumt.
TThread.Queue(TThread.Current, Show);
```

**Schritte.**
1. `RunningSession` einführen, in `Completion`/`Signature` übergeben; `EnsureSession`/`StopSession` mit Thread-Wächter. Kompiliert, Verhalten: Kaltstart über Tippen liefert vorübergehend leere Listen.
2. `EnsureSession` in `InvokeCodeCompletion`/`OpenCompletion`/`InvokeParameterCodeInsight`/`OpenSignature` vorziehen (Hauptthread).
3. `TThread.Queue(nil, …)` → `TThread.Queue(TThread.Current, …)` in `Hover.Editor`, `Completion.Providers.Server`, `Signature.Providers.Server`, `Completion.Controller`, `CodeInsight.Manager` (Lese-Thread).
4. `TAtlasEditorHover.Shutdown` und Aufruf in `StopSession` vor `Client.Close`.
5. `ForceQueue`-Closures in `Completion.Editor` und den `Resolve`-Rückruf in `TAtlasGuard.Run` hüllen; `TAtlasGuard.Report` in den fünf Manager-Methoden.
6. Kommentare in `Async.pas` 4 und `Providers.Server.pas` 331 ersetzen durch `Assert(GetCurrentThreadId = MainThreadID)` im Debug-Build.
7. Tests: `Atlas.Core.Completion.Composite.Tests` mit einem Provider, dessen `Prepare` die Thread-ID aufzeichnet; Entlade-Test manuell (Package entladen während Hover-Worker läuft).

**Aufwand.** M (ein Tag inklusive Tests). **Risiken.** Schritt 1 ändert sichtbares Verhalten (Kaltstart liefert erst beim zweiten Tastendruck); Schritt 2 kompensiert das. Nachtesten: Serverneustart über Statusfeld, `SetEnabled`, Absturz des Servers während Tippen, Entladen mit offenem Hover. **Alternativen.** Den Start innerhalb des Arbeiters per `TThread.Synchronize` in den Hauptthread marshallen – würde den Hauptthread bis zu 15 s blockieren (`Initialize`), deshalb verworfen. `RemoveQueuedEvents(nil)` beim Entladen – entfernt Einträge aller Threads des IDE-Prozesses, verworfen.

### 4.2 Heißer Pfad des Servers: Pinning, Request-Kontext, O(n²) beseitigen  (Nutzen: sehr hoch · Aufwand: S + M)

**Ziel.** `references`/`rename` auf häufige Namen in Sekunden statt Minuten; Vervollständigung je Tastendruck mit einer Index-Extraktion statt bis zu 15; die 4 307-Zeilen-Unit wird erweiterbar, ohne dass jeder neue Fall acht Parameter durchreicht. Erfolg: ein Benchmark in `Tools/Benchmark` (existiert bereits, `bench.mjs`) misst `references` auf `Create` und `completion` in einer Formular-Unit vor und nach.

**Ist.** P-01, P-02, P-06, P-07, P-08, P-11, P-12, P-17, S-01, D-09.

**Soll.** Erstens drei Zeilen Pinning; zweitens ein Request-Record, der alles trägt, was die Spezialfälle heute einzeln berechnen; drittens ein Collector mit Feldern statt Closure-Variablen.

```pascal
// Schritt 1 – References.InTree, DocumentHighlights.Collect, Completion.Handle:
AResolver.PinTree(ATree, AFileName);
try
  for Token in ATree.Tokens do
    ...
finally
  AResolver.UnpinTree;
end;

// Schritt 2 – Atlas.Common.Lsp.Completion:
type
  TCompletionRequest = record
  private
    FUnitIndex: TUnitIndex;
    FUnitIndexReady: Boolean;
    FLineBreak: string;
  public
    Tree: TSyntaxTree;
    FileName: string;
    Document: ITextDocument;        // statt Text: string – LineText, OffsetAt, PositionAt sind O(1) bzw. O(log n)
    Position: TTextPosition;
    Context: TCompletionContext;
    Resolver: TNameResolver;        // gepinnt für die ganze Anfrage
    Index: ISymbolIndex;
    ReadText: TReadTextFunc;
    function UnitIndex: TUnitIndex; // einmal extrahieren, dann aus dem Feld
    function LineBreak: string;
  end;

  TCompletionCase = reference to function(const ARequest: TCompletionRequest;
    out AItems: TArray<TCompletionItem>): Boolean;

// Handle wird zur Schleife über FCases (EnumItems, ComponentItems, InterfaceItems, …):
for CaseFunc in FCases do
  if CaseFunc(Request, Items) then
    Exit(ToJson(Items, Request));

// Schritt 3 – Collector statt Closure-Variablen:
type
  TCompletionCollector = class
  private
    FRequest: TCompletionRequest;
    FMatching: TMatchingOptions;
    FItems: TList<TScoredItem>;
    FSeen: TDictionary<string, Integer>;
  public
    procedure Add(const ASymbol: TResolvedSymbol; AKind: TCompletionKind; APenalty: Integer);
    procedure AddKeyword(const AName: string);
    function ToArray: TArray<TScoredItem>;
  end;

const
  PenaltyKeyword = 50;
  PenaltyProjectImport = 100;
  PenaltyLibraryImport = 200;
  PenaltyUnavailable = 500;
```

**Schritte.**
1. Pinning in `References.InTree`, `DocumentHighlights.Collect`, `Completion.Handle` (P-01, P-02). Je drei Zeilen; danach `TLspDefinition.Targets` auf den gepinnten Index umstellen.
2. `TList<T>`/`SetLength` an den Stellen mit großem n: `References.Find/Searched/Filtered`, `WithoutKeywords`, `TreeUnit`, `Security.CodeTokens` (P-08).
3. `IsBuiltinTypeName`-Prüfung in `TypeAt` (P-12); konstante `TRegEx`-Instanzen (P-11); DFM-Cache und Reihenfolge in `ComponentItems` (P-06); Datei-Cache in `OverrideItems` (P-07).
4. `TCompletionRequest` einführen und die `*Items`-Methoden nacheinander umstellen (jede einzeln kompilierbar, da der Record die alten Parameter kapselt).
5. `Handle` zur Case-Liste; `Collect` auf `TCompletionCollector`; Strafpunkte als Konstanten.
6. `Lsp.Completion` in Units je Anliegen teilen (`Completion.Scope`, `.Members`, `.Enums`, `.Forms`, `.Interfaces`, `.Postfix`, `.Declare`), die jeweils einen `TCompletionCase` registrieren.

**Aufwand.** Schritte 1–3: S (ein halber Tag, größte Wirkung). Schritte 4–6: M–L (zwei bis drei Tage). **Risiken.** `PinTree` setzt voraus, dass der Baum während der Anfrage unverändert bleibt – gegeben (Momentaufnahme). Die Umstellung auf `ITextDocument` ändert Zeilenende-Semantik an den Stellen, die heute eigene `LineBreakOf`-Varianten haben (D-09) – Protokolltests in `Tests/Data/Protocol` sind die Absicherung. **Alternativen.** Memoisierung von `Extract` nach Baumadresse – unsicher, weil Bäume freigegeben und Adressen wiederverwendet werden; explizites Pinning ist deshalb vorzuziehen.

### 4.3 Gemeinsames Runtime-Package `Atlas.Text` für Server und Plugin  (Nutzen: hoch · Aufwand: M)

**Ziel.** Eine Implementierung für Kodierung, Zeilen, URIs, Anonymisierung, Fuzzy-Grundregeln, Diff-Vorstufe und JSONC-Skipper; Drift zwischen Server und Plugin ist strukturell ausgeschlossen. Erfolg: `Atlas.Core.Files.Format`, `Atlas.Core.Files.TextFile`, die Anonymisierungsroutinen in `Atlas.Core.Diagnostics.BugReport` und sieben `LineBreakOf`-Kopien sind gelöscht; `Check-PackageDependencies.ps1` kennt `Atlas.Text` als erlaubte Abhängigkeit beider Seiten.

**Ist.** D-01 bis D-06, D-10, K-02.

**Soll.**

```text
Packages/Atlas.Text/
  Atlas.Text.dpk                      requires rtl;   (kein Windows, keine VCL)
  Source/
    Encoding/ Atlas.Text.Encoding.pas  CheckUtf8 (strikt), DetectBom, ParseCodePage, IsBinaryForm, Cp1252-Tabelle
    Lines/    Atlas.Text.Lines.pas     TLineTable (Zeilenstarts, PositionAt/OffsetAt binär), SplitLines(out ALineBreak), LineBreakOf, IndentOf, JoinLines
    Chars/    Atlas.Text.Chars.pas     IsWordChar, IsIdentStart, IsIdentChar
    Uris/     Atlas.Text.Uris.pas      FromPath, ToPath, PercentEncode/Decode, Normalisierung
    Anonymize/Atlas.Text.Anonymize.pas AnonymizePaths, AnonymizeLogLine, ReplaceQuoted …
    Fuzzy/    Atlas.Text.Fuzzy.pas     IsWordStart, SubsequenceScore, Score-Stufen als Konstanten
    Diff/     Atlas.Text.Diff.pas      CommonPrefixSuffix, Hunks (aus LinePatch)
    Jsonc/    Atlas.Text.Jsonc.pas     SkipSpace, StripComments
```

```pascal
unit Atlas.Text.Lines;

interface

type
  TLineBreak = (Crlf, Lf, Cr, Mixed, None);

  TLineTable = record
  private
    FStarts: TArray<Integer>;
  public
    class function Build(const AText: string): TLineTable; static;
    function PositionAt(AOffset: Integer): TTextPosition;
    function OffsetAt(const APosition: TTextPosition): Integer;
    function LineText(const AText: string; ALine: Integer): string;
  end;

function LineBreakOf(const AText: string): string;
function DetectLineBreak(const AText: string; out AMixed: Boolean): TLineBreak;
function SplitLines(const AText: string; out ALineBreak: string): TArray<string>;
function IndentOf(const ALine: string): string;
```

**Schritte.**
1. Package anlegen, `Atlas.groupproj` (Build-Reihenfolge: Text, Common, Windows, …), `Check-PackageDependencies.ps1` Zeile 62/72 um `Atlas.Text` erweitern, ADR 0011 schreiben (K-02).
2. `Atlas.Text.Encoding` aus `Atlas.Common.Documents.FileEncoding` (strikte Fassung) extrahieren; `TFileEncoding` wird Fassade; Server-Tests laufen weiter.
3. Plugin: `Atlas.Core.Files.Format`/`TextFile`/`EncodingDefault` auf `Atlas.Text.Encoding` umstellen, zwei `IsUtf8`-Kopien löschen; Plugin-Tests laufen weiter.
4. `Atlas.Text.Lines` + `Chars`: die elf `SplitLines`, sieben `LineBreakOf`, fünf `IndentOf`, acht `IsWordChar` ersetzen – je Unit ein Commit, nach jedem kompiliert alles.
5. `Anonymize`, `Uris`, `Fuzzy`, `Diff`, `Jsonc` analog.
6. Atlas-Regel oder Check-Skript: „keine lokale Definition von `LineBreakOf`/`SplitLines`/`IsWordChar`/`IndentOf`“.

**Aufwand.** M (zwei Tage), gut parallelisierbar je Unit. **Risiken.** Die IDE lädt ein zweites BPL (`Atlas.Text.bpl`) – das widerspricht dem Grund „nur ein BPL“ in `Architektur.md` 17. Es ist ein winziges, VCL- und Windows-freies Package; die Installation (`AtlasSetup`) muss es mit ausliefern und registrieren. Verhaltensänderung im Plugin: strikte UTF-8-Prüfung klassifiziert bisher „UTF-8“ erkannte Dateien mit ungültigen Sequenzen als ANSI – gewollt, aber im CHANGELOG zu nennen. **Alternativen.** (a) Dieselben Units in beide `.dpk` unter `contains` aufnehmen (gemeinsamer Quellordner, zweimal übersetzt, kein Laufzeitkonflikt, da getrennte Prozesse) – hält „ein BPL“, verliert aber die Garantie gegen Drift nur, wenn jemand eine Kopie anlegt; Check-Skript kann das verhindern. Gangbar, wenn das zweite BPL politisch nicht gewollt ist. (b) Bewusste Kopie mit Sync-Test – nur für `Version` sinnvoll (`{$I Atlas.Version.inc}`).

### 4.4 Regelengine: Ableitungscache je Lauf und gemeinsamer Baumdurchlauf  (Nutzen: hoch · Aufwand: M)

**Ziel.** Die Diagnosekosten je Datei skalieren mit der Dateigröße, nicht mit Regelanzahl × Dateigröße. Erfolg: `workspace/diagnostic` über ein 2 000-Dateien-Projekt messbar schneller; `TIndexExtractor.Extract` läuft je Datei genau einmal.

**Ist.** P-03, P-08 (`CodeTokens`), P-11 (`DfmProperties`), D-04 (`PositionAt` in Regeln).

**Soll.** `TRuleContext` bekommt denselben `Derived`-Mechanismus, den `ITextDocument` bereits hat, und `TSyntaxNode` einen Visitor.

```pascal
// Atlas.Common.Rules.Contract
type
  TRuleContext = record
  private
    FDerived: IDerivedCache;   // Besitz je Lauf; TRuleEngine.Run legt ihn an
  public
    Tree: TSyntaxTree;
    Document: ITextDocument;
    ...
    // Einmal je Lauf berechnet, von allen Regeln geteilt:
    function UnitIndex: TUnitIndex;
    function Routines: TArray<TSyntaxNode>;
    function FlowSignatures: TFlowSignatures;
    function ComponentModel: TComponentModel;
    function CodeTokens: TArray<TPascalToken>;
    function Derived<T: class>(const AKey: string; const AFactory: TFunc<T>): T;
  end;

// Atlas.Common.Pascal.SyntaxTree
type
  TNodeVisit = reference to function(ANode: TSyntaxNode): Boolean;  // False = nicht absteigen

procedure TSyntaxNode.Walk(const AVisit: TNodeVisit);
var
  Index: Integer;
begin
  if not AVisit(Self) then
    Exit;
  for Index := 0 to ChildCount - 1 do
    Children[Index].Walk(AVisit);
end;
```

**Schritte.**
1. `Derived<T>` in `TRuleContext` mit `TObjectDictionary<string, TObject>`, angelegt in `TRuleEngine.Run` vor der Regelschleife (262), freigegeben danach.
2. `UnitIndex` darüber; die elf `TIndexExtractor.Extract`-Aufrufe in `Inheritance`, `Components`, `DfmProperties` ersetzen.
3. `Routines`, `FlowSignatures`, `ComponentModel`, `ThreadClasses`, `CodeTokens` analog; `CodeTokens` mit `SetLength` vorab.
4. `Walk` einführen; die 47 rekursiven Schleifen nach und nach umstellen (keine Verhaltensänderung, jede Regel einzeln testbar).
5. Kontrollflussgraphen je Routine über `Derived('flow:' + RoutineKey, …)`.
6. `PositionAt` in `Unused`/`Capture` durch `Document.PositionAt` ersetzen.

**Aufwand.** M (ein bis zwei Tage). **Risiken.** `TRuleContext` wird kopiert (Record) – der Cache muss eine Interface-Referenz sein, damit alle Kopien denselben Speicher sehen. Regeln, die den Baum verändern (keine gefunden), würden den Cache ungültig machen. **Alternativen.** Ein einziger Visitor-Lauf mit Regel-Registrierung je Knotentyp (echtes Visitor-Pattern) – größerer Umbau aller 79 Regeln; der Cache bringt 80 % des Nutzens bei 20 % des Aufwands und bereitet den Visitor vor.

### 4.5 Fachcode in den Host: Hosted-Features mit eigener Composition  (Nutzen: hoch, langfristig · Aufwand: XL)

**Ziel.** `Atlas.Common` enthält nur noch technische Basis; `AtlasServer` besitzt seine Features und komponiert sie über deren eigene `Composition`-Units; `Shell.Composition` schrumpft auf wenige hundert Zeilen; `Rules` ⇄ `Editing` ist durch die Feature-Matrix verboten und aufgelöst. Erfolg: `Application/Source/Features/` existiert, `TServerComposition` hat keine `TLsp*`-Felder mehr, der Rollen-Checker (4.6) meldet null Verstöße.

**Ist.** A-08, A-11, S-02, D-08.

**Soll.**

```text
Application/Source/
  Foundation/   Foundation.Workspace.pas        (IWorkspaceLookup, ISettingsProvider, IEnsureUnit – was alle Features brauchen)
  Core/         Core.Workspaces.pas             (TShellWorkspace, Reload, StartIndex)
                Core.Compile.pas                (Compile-Loop)
                Core.Settings.pas               (SettingsFor(Uri) mit einem Fallback)
  Adapters/     Adapters.Index.CacheDirectory.pas …
  Features/
    Navigation/ Navigation.Contract.pas, Navigation.Providers.Definition.pas, .Hover, .References, Navigation.Composition.pas
    Completion/ Completion.Contract.pas, Completion.Providers.*.pas, Completion.Composition.pas
    Rules/      (bisher Atlas.Common.Rules)   Rules.Contract, Rules.Providers.Engine, Rules.Composition
    Editing/    (bisher Atlas.Common.Editing) Editing.Contract, Editing.Providers.*, Editing.Composition
    Mcp/        …
  Shell/        Shell.Composition.pas (ruft Feature-Compositions), Shell.Application, Shell.CommandLine
```

```pascal
// Features/Navigation/Navigation.Composition.pas  – manuelle DI-Strategie, deshalb ohne Suffix (Architektur.md)
unit Navigation.Composition;

interface

uses
  Foundation.Workspace, Navigation.Contract, Atlas.Common.JsonRpc.Contract;

type
  TNavigationComposition = class
  public
    class procedure Register(const AHost: IFeatureHost; const ADispatcher: IJsonRpcHandlerRegistry);
  end;

implementation

uses
  Navigation.Providers.Definition, Navigation.Providers.Hover, Navigation.Providers.References;

class procedure TNavigationComposition.Register(const AHost: IFeatureHost; const ADispatcher: IJsonRpcHandlerRegistry);
begin
  // Einziger Ort, an dem Konstruktoren der Injectables dieses Features aufgerufen werden (Konzept 7.6).
  ADispatcher.RegisterConcurrent('textDocument/definition',
    TLspDefinition.Create(AHost.Documents, AHost.Index, AHost.EnsureUnit, AHost.ReadText));
  ADispatcher.RegisterConcurrent('textDocument/hover',
    TLspHover.Create(AHost.Documents, AHost.Index, AHost.ReadText, AHost.EnsureUnit));
  ...
end;
```

**Schritte** (jeder lässt das Projekt kompilieren und die Protokolltests laufen):
1. `Foundation.Workspace` mit den Interfaces, die heute als Closures durchgereicht werden (`IEnsureUnit`, `IReadText`, `ISettingsProvider`); `TServerComposition` implementiert sie zunächst selbst.
2. `Core.Settings`/`Core.Workspaces`/`Core.Compile` aus `Shell.Composition` und `Shell.Workspace` herauslösen (S-02 nebenbei erledigt).
3. `Atlas.Common.Lsp` als erstes Feature verschieben – zunächst **im selben Package**, nur mit neuem Namenspräfix und `Composition`-Unit; die Shell ruft die Composition. Der Rollen-Checker prüft ab hier mit Matrix 8.2.
4. `Rules` und `Editing` folgen; dabei den Zyklus über `Atlas.Common.Uses`/`Commands.Contract` auflösen (A-11).
5. `Semantics` und `Mcp`.
6. Erst jetzt die Features physisch nach `Application/Source/Features` verschieben (Versionskontrolle: ein Commit je Feature, `git mv`).
7. `Atlas.Common.dpk` schrumpft entsprechend; `Check-PackageDependencies.ps1` anpassen.

**Aufwand.** XL (zwei bis vier Wochen, verteilbar). **Risiken.** Tests in `Tests/Common` müssen mitwandern; MCP-Server (`Shell.Mcp`) und Linter (`Shell.Linter`) sind zweite Hosts desselben Fachcodes – sie werden mit Schritt 1–2 zu Nutzern derselben Feature-Compositions (löst D-08), brauchen aber vorher `Shell.Bootstrap`. Die `Tests/Referenzprojekt` und Benchmarks sind die Regression. **Alternativen.** Den Zustand belassen und `Atlas.Common` als „Fachcode-Package“ umdeklarieren – das würde die Konzeptwidersprüche beseitigen, aber nicht die 2 687-Zeilen-Shell und nicht den Zyklus; es ist der ehrlichere Zwischenschritt, falls der Umbau nicht ansteht, und sollte dann in `Architektur.md` so benannt werden.

### 4.6 Rollen-Checker als Atlas-Regel  (Nutzen: mittel, sichert alles andere · Aufwand: S)

**Ziel.** Konzeptziel 2 ist erfüllt: Verstöße gegen Benennung (6.3), Importmatrizen (8.1–8.3) und Contract-Inhalt (7.1) erscheinen als Diagnose im Editor und im CI, ohne Review.

**Ist.** A-10, A-12; das Python-Skript dieses Reviews (Anhang 7.4) fand die 15 Verstöße in Sekunden.

**Soll.**

```pascal
// Atlas.Common.Rules.Builtin.Architecture – neue Regel
type
  TRoleImportRule = class(TInterfacedObject, IRule)
  private
    FPrefixes: TArray<string>;   // Whitelist der Ausgabeartefakte aus atlas.json: "architecture.prefixes"
    function Classify(const AUnitName: string; out AArtefact, AFeature, ARole: string): Boolean;
    function Allowed(const AFrom, ATo: TUnitRole): Boolean;   // Matrix 8.1/8.2/8.3 als Konstanten-Tabelle
  public
    function Descriptor: TRuleDescriptor;        // 'architecture-role-import', Warning
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;
```

Die Regel liest beide `uses`-Klauseln aus dem Baum (`TRuleContext.UnitIndex.InterfaceUses/ImplementationUses` existieren bereits), klassifiziert Quelle und Ziel nach Präfix-Whitelist, Feature und Rollenbezeichner, und meldet je verbotenem Import ein Finding an der Position des uses-Eintrags – mit Fix „Import entfernen“. Eine zweite Regel `architecture-contract-content` meldet `class`-Deklarationen mit Implementierungsteil in `*.Contract`-Units.

**Schritte.** 1. Matrix als Konstanten; 2. Regel mit Tests (`Tests/Common/Rules/…`, je Matrixzelle ein Fall); 3. Einstellung `architecture.prefixes` im Schema (`Update-ConfigDoc.ps1`); 4. Aufruf in `Check-PackageDependencies.ps1` über den Linter; 5. die 15 bestehenden Verstöße beheben oder als genehmigte Ausnahme mit Kommentar eintragen (Konzept 7.1 erlaubt das nur für Framework-Importe des Contract).

**Aufwand.** S–M (ein halber bis ganzer Tag). **Risiken.** Keine für den Produktcode. **Alternativen.** PowerShell wie bisher – funktioniert, aber die Regel im Linter liefert Diagnosen im Editor und ist dieselbe Infrastruktur, die das Produkt Kunden verkauft.

---

## 5. Empfohlener Fahrplan

**Sofort (diese Woche, zusammen unter einem Tag):**
- 4.1 Schritte 1–4 (A-01, A-02, A-07) – die beiden kritischen Plugin-Befunde.
- 4.2 Schritte 1–3 (P-01, P-02, P-06, P-07, P-08, P-11, P-12) – der heiße Pfad des Servers.
- Quick Wins, jeder unter einer Stunde: A-04 (`FProjectPending` im Fehlerfall), A-05 (Reihenfolge in `Destroy`), S-06 (`CompileLoop` absichern), S-07 (Konstanten, `WARN DEFAULT`, Test-Knopf hinter `Diagnose`), K-01, K-03, K-05, K-06, P-14 (`WaitMs` an Timeout koppeln), P-16 (Intervall), P-15, P-10.

**Nächstes Release (ein bis zwei Wochen):**
- 4.3 `Atlas.Text` (D-01 bis D-06, D-10) mit ADR 0011 (K-02).
- 4.4 Regelcache (P-03).
- 4.6 Rollen-Checker (A-10, A-12) – er sichert die folgenden Umbauten ab.
- A-03 (Reload in die Schleife posten, Namespaces-Race), A-06 (Watchdog-Antwort), P-09 (Hover-Layout), P-04 (Puffer-Snapshot), P-13, P-17, S-05, D-07, D-08.

**Langfristig (nächstes Quartal, in Etappen):**
- 4.5 Fachcode in den Host (A-08, A-11, S-02) – erst nach 4.6, damit jede Etappe geprüft ist.
- A-09 (Plugin-Schichten als Artefakte, 17er-Zyklus), S-01/4.2 Schritte 4–6 (Completion-Umbau), S-03 (`Apply`/`Initialize`/`RegisterFeatures`), S-04, P-05 (Verzeichnis im Index).

Was zusammen erledigt werden sollte: 4.2 Schritt 4 (Request-Record) und D-09 (Zeilenhelfer in Completion) sind dieselbe Änderung; 4.3 und 4.4 berühren beide `PositionAt` (D-04) und sollten die Reihenfolge Text → Rules einhalten; 4.5 Schritt 2 erledigt S-02 und D-08 nebenbei.

---

## 6. Was gut ist

Diese Punkte sind keine Höflichkeit, sondern Muster, die beibehalten und auf die Befunde oben übertragen werden sollten.

1. **Snapshot statt Scan unter Sperre** – `Atlas.Common.Index.SymbolIndex.pas` 233–260 (`Locations`): Kopie der Unit-Liste unter dem Lock, Durchlauf ohne Lock, Index-Zugriff statt `for … in`, Begründung (#647) im Kommentar. Genau das richtige Muster; es muss nur noch auf `Units` selbst (P-13) angewendet werden.
2. **Ein Baum je Dokumentversion mit Abbruch veralteter Parses** – `Atlas.Common.Pascal.TreeCache.pas` 119–156 (`ParseShared`) und `Atlas.Common.Documents.TextDocument.pas` 188–205 (`Derived`): unveränderliche Momentaufnahme, Interlocked-Abbruchsignal, Fallback-Parse für veraltete Anfragen; `Parser.pas` 318–321 prüft den Abbruch nur alle 4 096 Tokens. Das `Derived`-Muster ist zugleich die fertige Lösung für 4.4.
3. **Import-Namensindex mit Zeichenmaske** – `Atlas.Common.Index.NameIndex.pas` 78–135, 144–164: `SetLength` vorab, Projekt vor Bibliothek, gedrosselter Neuaufbau nach Generation; Nutzung in `Completion.pas` 1731–1737 mit `UnitState`-Byte-Array. Das ist der Grund, warum Importvorschläge trotz 500 000 Symbolen schnell sind.
4. **Builder-Übergabe mit Nutzerzähler statt globaler Sperre** – `Atlas.Common.Index.Service.pas` 385–425 (`AcquireBuilder`/`ReleaseBuilder`/`ReplaceBuilder` mit `TMonitor.Wait/PulseAll`, `Old.Free` außerhalb des Locks) und `Shell.Composition.pas` 1590–1631 (`EnsureUnit` ohne `FWorkspacesLock`). Konsequente Lösung des #647-Hover-Problems.
5. **Lese-Thread ohne Objektbesitz** – `Atlas.Common.JsonRpc.Connection.pas` 266–337, 499 (Server) und `Atlas.Core.Lsp.Session.pas` 531–577 (Plugin: „Der Lese-Thread kann die Sitzung überleben“): Der Reader hält nur Interfaces; `$/cancelRequest` und `didChange → ContentModified` wirken, bevor die Nachricht in die Warteschlange geht (`PendingRequests.pas` 171–230).
6. **Schutz von stdout** – `Atlas.Windows.Console.StdStreams.pas` 81–95 (`ReserveOutputForProtocol`): biegt Win32-Standardhandle, RTL-`Output` und `NoErrMsg` auf stderr; versehentliche `Writeln` aus Bibliotheken können das Protokoll nicht zerstören.
7. **Absturzsicherung je Feature und je Quelle** – `Atlas.Core.Diagnostics.Guard.pas` 523–539, 444–461, 227–240: drei Fehler in fünf Minuten schalten nur das betroffene Feature ab, nie einen Dialog; Protokoll gekürzt ohne Quelltext. `TAtlasShutdown` als gemeinsames Abbruchsignal mit 20-ms-Scheiben und die gestufte Prozessbeendigung in `ServerProcess.pas` 229–276.
8. **Notifier-Entkopplung** – `Atlas.IDE.Build.Notifier.pas` 218–236 (`FOwner := nil` vor `RemoveNotifier`), identisch in `Forms.Designer` und `Commands.Keys`; `TAtlasStatusField.Unhook` setzt nur eigene Handler zurück; 28 `Add`, 28 `Remove`, alle in der richtigen Reihenfolge.
9. **VCL-freies Layout mit Mess-Callback** – `Atlas.Core.Documentation.Layout.pas` und `Atlas.UI.Documentation.View.Paint` 357–405 (`SaveDC`/`IntersectClipRect`/`RestoreDC` + `Canvas.Refresh`, Schriftcache): das Muster, das 4.2 für den Hover-Tooltip (P-09) empfiehlt. Ebenso `Atlas.UI.Completion.Popup.ShowList` 744–756 (`SameList` per Pointer-Vergleich verhindert das erneute Messen bei Pfeiltasten).
10. **Kodierungsbehandlung im Server** – `Atlas.Common.Documents.FileEncoding.pas`: eigene CP1252-Tabelle mit Begründung, strikte UTF-8-Prüfung, threadsichere Vorgabe je Ordner, Schutz binärer Formulare. Das ist die Referenzfassung für `Atlas.Text.Encoding`.
11. **Dokumentationskultur** – 100 % Unit-Köpfe mit Warum und Issue-Nummer; `LinePatch` (Dreiwege-Rebase mit Konfliktregel) und `TextChanges` (CRLF-/Surrogat-Grenzen) sind Beispiele, wo Kommentar und Code eine nachprüfbare Spezifikation bilden; der ADR-Prozess wird gelebt (0003 → 0010 mit Nachtrag statt Umschreiben).
12. **Kein DI-Container, trotzdem konsequente Konstruktor-Injektion** über Interfaces; keine globalen Variablen in `Atlas.Common`; Konstruktoren der Provider (`TLogger`, `TDocumentStore`, `TIndexService`) werden außerhalb der Shell nur in Tests aufgerufen (Konzept 7.6 eingehalten).

---

## 7. Anhang

### 7.1 Musterzählung (Grep über `Packages` und `Application`, ohne Tests)

| Muster | Treffer | Bewertung |
|---|--:|---|
| `X := X + [...]` bzw. `S := S + ...` in `for`/`while`-Schleifen (heuristisch) | 367 Kandidaten; 93 davon in heißen Pfaden (Lsp, Semantics, Index, Rules) | P-08: nur die Stellen mit großem n sind relevant; die übrigen laufen einmal je Benutzeraktion |
| `Result := Result + [` / `A := A + [` gesamt | 399 (`Atlas.Common`), 243 (Plugin) | systemisches Idiom, siehe P-08 |
| `with` … `do` | 0 | – |
| `Application.ProcessMessages` | 0 | – |
| `except` … `end;` ohne Behandlung | 16 Stellen in 10 Units | alle kommentiert, auf Protokollierung/Beendigung beschränkt – gerechtfertigt |
| `except Exit;` | 1 | `Atlas.IDE.Commands.Palette.pas` 268 (Verlauf kaputt → leer anfangen) |
| `Sleep(` | 8 | P-14, P-16, S-07, A-13; `Index.Service` 359 (Startpolling auf Sperrdatei, vertretbar) |
| `{$WARN … OFF}` | 3 (alle `SYMBOL_PLATFORM`) | begründet; S-07 zu `ON` vs. `DEFAULT` |
| `TThread.Queue(nil` / `ForceQueue(nil` | 31 | A-02 |
| `TThread.Synchronize` | 0 | – (gut: nur `Queue`) |
| `ShowMessage` | 1 | Installer, legitim |
| `TODO` / `FIXME` / `HACK` / `XXX` | 15 Treffer, 0 offene | alle sind generierter Text oder der `/todo`-Befehl |
| Globale `var` im Interface-Abschnitt (`Atlas.Common`) | 0 | – |
| `class var` (`Atlas.Common`) | 1 | – |
| `Variant` / `OleVariant` | 11 | OTA/JSON-Zugriffe, begründet |
| Units > 1 500 Zeilen | 6 | Abschnitt 2.2 |
| Methoden > 60 Zeilen | 262 in 152 Units | 7.3 |

### 7.2 Verstöße gegen die Importmatrix des Konzepts (15 von 2 003 internen Imports)

Prüfung: eigenes Skript, das jede Unit nach `Ausgabeartefakt.Feature.Rolle.Sache` klassifiziert (Whitelist `Atlas.Common`, `Atlas.Windows`, `Atlas.Core`, `Atlas.UI`, `Atlas.IDE`, `Setup`; Anwendung ohne Präfix) und beide `uses`-Klauseln gegen die Matrizen 8.1 (Shell) und 8.3 (Platform-Feature, eigen/fremd) prüft. Verschachtelung (7.4) wurde als „Sache“ behandelt, was zugunsten des Codes wirkt.

| Importierende Unit | importiert | Verstoß |
|---|---|---|
| `Atlas.Common.Logging.Providers.StreamSink` | `Atlas.Common.Logging.Providers.RotatingFileStream` | eigene Providers aus Providers |
| `Atlas.Common.Rules.Contract` | `Atlas.Common.Pascal.SyntaxTree` | fremdes Root aus Contract |
| `Atlas.Common.Rules.Contract` | `Atlas.Common.Semantics.NameResolver` | fremdes Root aus Contract |
| `Atlas.Core.Undo.Contract` | `Atlas.Core.Files.TextFile` | fremdes Root aus Contract |
| `Atlas.Core.Signature.Providers.Server` | `Atlas.Core.Completion.Providers.Server` | fremde Providers aus Providers |
| `Atlas.IDE.CodeInsight.Composition` | `Atlas.Core.Updates.Adapters.HttpSource` | fremde Adapters aus Composition |
| `Atlas.IDE.CodeInsight.Manager` | `Atlas.Core.Lsp.Adapters.ServerProcess` | fremde Adapters aus Root |
| `Atlas.IDE.CodeInsight.Manager` | `Atlas.Core.Files.Adapters.FolderWatcher` | fremde Adapters aus Root |
| `Atlas.IDE.Completion.Editor` | `Atlas.Core.Completion.Providers.Server` | fremde Providers aus Root |
| `Atlas.IDE.Completion.Editor` | `Atlas.Core.Completion.Providers.Snippets` | fremde Providers aus Root |
| `Atlas.IDE.Completion.Editor` | `Atlas.Core.Completion.Providers.XmlDoc` | fremde Providers aus Root |
| `Atlas.IDE.Signature.Editor` | `Atlas.Core.Signature.Providers.Server` | fremde Providers aus Root |
| `Atlas.IDE.Signature.Editor` | `Atlas.Core.Completion.Providers.Server` | fremde Providers aus Root |
| `Atlas.IDE.Undo.Changes` | `Atlas.Core.Undo.Adapters.FileStore` | fremde Adapters aus Root |
| `Atlas.IDE.Undo.Target` | `Atlas.Core.Undo.Adapters.DiskTarget` | fremde Adapters aus Root |

Ergänzend gegen 7.1 (Contract-Inhalt): `Atlas.Common.Dfm.Contract` (2 Klassen), `Atlas.Common.Index.Contract` (`TIndexFiles`), `Atlas.Core.Undo.Contract` (`TAtlasUndoNames`). Die Shell (`Shell.*`) und der Installer (`Setup.*`) sind frei von Verstößen. Nicht genutzte Rollen: `Hosting` (0 Units), `Composition` (1 Unit), Host-Rollen `Foundation`/`Core`/`Adapters` (0 Units).

### 7.3 Methoden über 100 Zeilen (Auszug, absteigend)

| Zeilen | Methode |
|--:|---|
| 919 | `Shell.Composition.TServerComposition.Create` |
| 716 | `Atlas.Common.Lsp.Completion.TLspCompletion.Collect` |
| 557 | `Atlas.UI.Hover.Tip.TAtlasHoverTip.Render` |
| 435 | `Atlas.IDE.Editor.WorkspaceEdit.TAtlasIdeWorkspaceEdit.Apply` |
| 312 | `Atlas.Core.Editor.Pairs.TAtlasPairs.Analyze` |
| 287 | `Shell.Workspace.TShellWorkspace.StartIndex` |
| 237 | `Atlas.Common.Index.Extractor.TIndexExtractor.BlankInactive` |
| 236 | `Shell.Mcp.RegisterTools` |
| 228 | `Atlas.UI.Settings.Page.TAtlasSettingsPage.Create` |
| 213 | `Shell.Mcp.TMcpShell.Run` |
| 207 | `Atlas.Common.Lsp.Completion.TLspCompletion.Handle` |
| 201 | `Atlas.UI.Settings.ProjectDialog.TAtlasProjectSettingsDialog.ShowPage` |
| 199 | `Shell.CommandLine.TCommandLineOptions.Parse`, `Atlas.UI.Completion.Details.TAtlasDetailView.Render` |
| 198 | `Atlas.Common.Configuration.Parser.TValidator.Run` |
| 186 | `Atlas.Common.Pascal.Preprocessor.TPreprocessorRun.ProcessText` |
| 184 | `Atlas.Common.Lsp.Hover.TLspHover.InfoAt` |
| 183 | `Atlas.Common.Pascal.Parser.TParser.ParseTypeBody` |
| 179 | `Atlas.Common.Editing.MemberOrder.TMemberOrder.Sort` |
| 177 | `Shell.Linter.TLinterShell.Run` |
| 173 | `Atlas.Core.Documentation.Layout.TAtlasDocLayout.Build` |
| 169 | `Atlas.IDE.CodeInsight.Composition.RegisterFeatures` |
| 165 | `Atlas.Common.Pascal.XmlDoc.TXmlDocParser.Build` |
| 159 | `Atlas.Common.Lsp.Completion.TLspCompletion.EventItems`, `Atlas.Common.Dfm.BinaryForm.TConverter.ConvertValue` |
| 158 | `Atlas.Common.Lsp.Completion.TLspCompletion.InterfaceItems` |
| 156 | `Atlas.IDE.Completion.Editor.TAtlasEditorCompletion.Commit` |
| 151 | `Atlas.Common.Semantics.ControlFlow.TFlowBuilder.Analyze`, `Atlas.IDE.CodeInsight.Composition.RegisterPalette` |
| 150 | `Atlas.Core.Completion.Ranking.TAtlasRanking.Order` |
| 149 | `Atlas.Common.Lsp.Completion.TLspCompletion.ToJson` |

Parser- und Preprocessor-Methoden (`ParseTypeBody`, `ProcessText`, `ConvertValue`) sind in dieser Länge bei rekursiv absteigenden Parsern üblich und werden nicht als Befund geführt.

### 7.4 Nicht geprüft und warum

- **Atlas-MCP-Werkzeuge** (`get_diagnostics`, `get_last_build`, `check_code`, `rename_symbol`): In dieser Sitzung nicht erreichbar. Compiler-Warnungen des letzten Builds und die Befunde der eigenen 79 Regeln über den eigenen Code fehlen deshalb; die Codeskizzen in Abschnitt 4 sind nicht syntaxgeprüft.
- **Laufzeitmessungen**: Alle Performance-Aussagen sind aus dem Code abgeleitet (Aufrufhäufigkeit × Kosten je Aufruf). `Tools/Benchmark/bench.mjs` existiert und sollte für P-01/P-02 vor und nach der Änderung laufen.
- **`Tests/`** (254 Units, 64 153 Zeilen): nur Abdeckung gezählt, nicht inhaltlich geprüft. Auffällig: `Tests/Application` hat 3 Units für 6 277 Zeilen Shell – `TServerComposition`, `TShellWorkspace` und `CompileLoop` sind praktisch ungetestet.
- **`Setup/`** (Installer, 6 Units) und `Atlas.Windows` (11 Units): nur Struktur und Importe geprüft, keine Lesung der Logik (Registry-Zugriffe, Prozessstart).
- **`.dfm`-Dateien** (5 im Plugin): nicht geprüft; die meisten Fenster entstehen per `CreateNew` ohne DFM (P-09/D-07 nennen die DPI-Folgen).
- **Rules/Builtin** jenseits der genannten Units (Unicode, Flow, Declarations, Style, RtlPatterns, PaletteIcons, Performance): nicht gelesen; die strukturellen Befunde P-03/B gelten vermutlich gleichermaßen (Annahme).
- **PowerShell-Tools** (`Tools/*.ps1`) und GitHub-Workflows: nur `Check-PackageDependencies.ps1` gelesen.
- **Werkzeuge dieses Reviews**: Die Skripte für Importmatrix (`check_roles.py`) und Metriken (`metrics.py`) liegen im Scratchpad der Sitzung unter `/tmp/claude-0/-home-claude-atlas-ide-expert/8c584b58-9f83-52be-b907-36388650a51f/scratchpad/` und können als Vorlage für Vorschlag 4.6 dienen; im Repository wurde nichts geändert außer dieser Berichtsdatei.
