# Atlas: Testfälle in der IDE

Bei Delphi 12 heißen BPL und Protokoll `…290.bpl` und `…290.log` statt `…370`.

Manuelle Prüfung des IDE-Plugins `Atlas.IDE.Expert` in RAD Studio, gegliedert nach Issues. Voraussetzung: Plugin installiert (`Output\Win32\Debug\Bpl\Atlas.IDE.Expert370.bpl`), Code Insight-Manager „Atlas IDE Expert“ aktiv, ein Delphi-Projekt mit einer VCL-Unit geöffnet. Für Fehlersuche `Diagnose` = 1 unter `HKCU\Software\Atlas\IdePlugin` setzen; das Protokoll `Atlas.IDE.Expert370.log` liegt neben der BPL.

Schreibweise: `|` steht für die Cursorposition.

## Einstellungen (#227, #407, #413)

| Nr. | Schritte | Erwartet |
|---|---|---|
| E1 | Tools › Optionen › Drittanbieter › Atlas öffnen | Seite „Atlas“ mit Schaltern, Zeilenzahl, „Verlauf zurücksetzen“, „Breiten zurücksetzen“; auch über die IDE-Suche („Atlas“) erreichbar |
| E2 | „Atlas aktiv“ ausschalten, OK, dann `List.` tippen | Die eingebaute Code Insight der IDE erscheint (kein Atlas-Popup); ohne IDE-Neustart |
| E3 | Wieder einschalten | Atlas-Popup erscheint wieder; nie zwei Popups gleichzeitig |
| E4 | Sichtbare Zeilen auf 15, OK, Popup öffnen | Liste zeigt 15 Zeilen; Bild↑/Bild↓ springt um 15 |
| E5 | IDE neu starten, Seite erneut öffnen | Werte sind erhalten (Registry `HKCU\Software\Atlas\IdePlugin`) |

## Sprache (#446)

| Nr. | Schritte | Erwartet |
|---|---|---|
| S1 | Deutsche IDE, Popup öffnen | „Enter übernehmen · Esc schließen“, „n von m“, Chips „Alle/Methoden …“ |
| S2 | IDE mit BDSSetLang auf Englisch umstellen, IDE neu starten | „Enter to accept · Esc to close“, „n of m“, „All/Methods …“; Optionsseite englisch; Bezeichner und Signaturen unverändert |

## Aussehen (#411, #420, #421)

| Nr. | Schritte | Erwartet |
|---|---|---|
| A1 | `List.` tippen (List: TStringList) | Popup mit blauem Rahmen, runden Ecken und Schatten; jede Zeile mit farbigem Badge (`fn`, `pr`, `pp`, `ev`, `fd` …), Name links, Typ/Signatur grau rechtsbündig |
| A2 | Danach `Ad` tippen | Die getippten Buchstaben sind im Namen blau und fett hervorgehoben |
| A3 | Fußzeile ansehen | Links „Enter übernehmen · Esc schließen“, rechts „n von m“ |
| A4 | Eintrag aus nicht eingebundener Unit (z. B. `TStringList` in einer Unit ohne `System.Classes`) | Grüne Marke „+ System.Classes“ statt grauem Text |
| A5 | IDE-Thema auf Dunkel umstellen (Tools › Optionen › Thema), Popup erneut öffnen | Dunkle Farben, heller Akzent; ohne IDE-Neustart |
| A6 | Sehr langen Namen bzw. lange Signatur in der Liste | Erst die Signatur, dann der Name mit „…“ gekürzt; Badges bleiben in einer Spalte |
| A7 | Bei A6 die Maus 1 s über die gekürzte Zeile halten (#420) | Kleiner Tooltip unter der Zeile mit vollem Namen, Signatur und Marken; verschwindet beim Verlassen der Zeile |
| A8 | `showmessage` klein tippen, Strg+Leer, Enter (#433) | `ShowMessage` in deklarierter Schreibweise |

## Rangfolge, Chips, Lernen (#418, #419, #422)

| Nr. | Schritte | Erwartet |
|---|---|---|
| R1 | In einer Methode `List.` (List: TStringList) ohne weiteres Zeichen | Zuerst die Member von TStringList, dann Überschrift „Geerbt von TStrings“, dann „Geerbt von TPersistent“ usw.; geerbte Zeilen blasser, rechts die Herkunftsklasse |
| R2 | Danach `Ass` tippen | `Assign` steht oben, keine Überschriften |
| R3 | Mit ↓/↑ über eine Überschrift navigieren | Die Auswahl springt über die Überschrift hinweg |
| R4 | Optionen › Atlas › „Geerbte Member … gruppiert“ aus | Flache Liste ohne Überschriften, nicht abgeschwächt |
| R5 | Oben in der Liste die Chips ansehen (#422) | „Alle n“, „Methoden n“, „Eigenschaften n“ …; nur Chips mit Treffern |
| R6 | Alt+2 bzw. Klick auf „Methoden“ | Nur Methoden; Zahlen stimmen; Popup schließen und wieder öffnen → wieder „Alle“ |
| R7 | Dreimal `Lines.BeginUpdate` über die Liste übernehmen, dann `Lines.` | `BeginUpdate` steht vor `Add`, Marke „zuletzt“ |
| R8 | Einen Eintrag fünfmal übernehmen, danach einen anderen | Erster Eintrag mit Marke „häufig“ |
| R9 | Optionen › Atlas › „Verlauf zurücksetzen“, OK, dann `Lines.` | Keine Marken, ursprüngliche Reihenfolge |
| R10 | Überladene Methode in der Liste (z. B. `Format`) | Ein Eintrag mit Marke „+1“ (bzw. Anzahl weiterer Überladungen) |

## Kontextregeln (#435)

| Nr. | Schritte | Erwartet |
|---|---|---|
| K1 | `S := 'Text.` (Punkt in einem String) | Kein Popup |
| K2 | `// Kommentar.` | Kein Popup |
| K3 | Über einer Methode `function CalcDiscount(const Customer: TCustomer; Rate: Double): Currency;` eine Zeile `/// <` tippen | Popup mit `xd`-Einträgen: summary, param name="Customer", param name="Rate", returns, remarks … |
| K4 | `param name="Rate"` übernehmen | `/// <param name="Rate">|</param>`, Cursor zwischen den Tags |
| K5 | In normalem Code `if A < B` | Kein Popup nach `<` |
| K6 | `{$IFDEF D` und Strg+Leer | Vorschläge aus den definierten Symbolen (z. B. DEBUG) |

## Detailpanel (#424, #426, #427)

| Nr. | Schritte | Erwartet |
|---|---|---|
| D1 | `List.` tippen, `Add` wählen und kurz warten | Rechts im **selben Fenster**, durch eine Linie getrennt: Marken (z. B. `public`), eingefärbte Deklaration, „System.Classes · TStrings“ |
| D2 | Mit ↑/↓ blättern | Panel folgt der Auswahl; Fenster wird nicht schmaler oder niedriger |
| D3 | Eigene Methode mit `///`-XMLDoc (`<summary>`, `<param>`, `<returns>`, `<exception>`) wählen | Beschreibung, Parameter (Name blau), „→“ Rückgabe, „!“ Exceptions (rot) |
| D4 | Schlüsselwort oder Eintrag ohne Details wählen, nachdem das Panel schon offen war | Panel bleibt mit „Keine Details zu diesem Eintrag“ |
| D5 | Popup nahe am rechten Bildschirmrand öffnen | Panel steht links der Liste |
| D6 | Bei offenem Panel Strg+Q (#428) | Panel klappt auf eine schmale Leiste mit „›“ zusammen; erneut Strg+Q oder Klick auf die Leiste klappt es auf |
| D7 | Eingeklappt lassen, Popup schließen, wieder öffnen; IDE neu starten | Panel bleibt eingeklappt |
| D8 | Sehr breites Popup so öffnen, dass das Panel weder rechts noch links passt | Panel ist automatisch eingeklappt |
| D9 | Eigene Klasse mit drei überladenen Methoden (`procedure Schreibe; overload;` usw.), Instanz + `.`, die Methode wählen (#425) | Liste: ein Eintrag mit „+2“; Panel oben „Überladung ‹ 1 / 3 ›“ |
| D10 | Alt+↓ bzw. Klick auf „›“ | „2 / 3“, Deklaration der zweiten Überladung; nach „3 / 3“ wieder „1 / 3“ |
| D11 | Bei „2 / 3“ mit Enter übernehmen, dann `(` tippen | Parameter-Hint wählt die zweite Überladung vor |

## Breite (#416)

| Nr. | Schritte | Erwartet |
|---|---|---|
| B1 | `A` tippen, dann `Add` | Liste wird beim Filtern nicht schmaler |
| B2 | Maus auf die Trennlinie zwischen Liste und Panel | Mauszeiger ↔ (Splitter); Ziehen ändert die Breite der Liste, das Panel wandert mit |
| B3 | Maus an den rechten Rand bzw. auf das Punktmuster unten rechts | Mauszeiger ↔; Ziehen ändert die Breite des Panels (ohne Panel: der Liste); der Editor behält den Fokus (Caret blinkt weiter) |
| B4 | Popup schließen und erneut öffnen; IDE neu starten | Gezogene Breiten bleiben |
| B5 | Doppelklick auf das Punktmuster | Automatische Breite der Liste, Panel wieder 320 px |
| B6 | Tools › Optionen › Atlas › „Breiten zurücksetzen“, OK | Wie B5 |

## Code Insight-Manager (#175)

| Nr. | Schritte | Erwartet |
|---|---|---|
| CI1 | Kurzanleitung aus `docs/Installation.md` befolgen (ohne Plugin), IDE starten, `.pas` eines Projekts öffnen | Syntaxfehler unterstrichen, Hover zeigt Klartext ohne Markdown-Zeichen, Gliederung gefüllt |
| CI2 | Strg+Leer in einer Methode, Eintrag wählen | Liste kommt, Doku im Klartext, kein `MethodNotFound` im Log |
| CI3 | Mit `--log` zweimal das Projekt wechseln, Log ansehen | Je Wechsel ein neuer Start; ab dem zweiten Start „N frühere Serverläufe ohne Endzeile (von der IDE beendet oder abgestürzt)“, kein „Server abgebrochen“ |
| CI4 | IDE schließen, Log ansehen | Endet mit „Verbindung beendet: …“ und „Beendet mit Exit-Code“ oder ohne Endzeile; dann meldet der nächste Start den Lauf |

## Vervollständigung: Kontexte (#31)

| Nr. | Schritte | Erwartet |
|---|---|---|
| VK1 | In einer Methode von `TForm1` `inherited ` tippen, Strg+Leer | Nur Methoden der Vorfahren (z. B. `FormCreate` nicht, `Loaded`, `Create` ja), keine lokalen Variablen |
| VK2 | In einer Routine ohne Klasse `inherited `, Strg+Leer | Leere Liste |
| VK3 | `TNeu = class(` und Strg+Leer | Nur Typen; keine Routinen, Variablen oder Schlüsselwörter |
| VK4 | Im var-Abschnitt `Liste: Str` | `string` und Typen wie `TStringList`, keine Variablen |
| VK5 | `if Sender is not ` (Delphi 13) | Nur Typen; `if 1 not in ` zeigt dagegen Variablen und Konstanten |
| VK6 | `property Wert: Integer read ` im Klassenrumpf | Nur Integer-Felder und Funktionen mit Ergebnis Integer; bei `write ` nur Prozeduren mit einem Integer-Parameter |
| VK7 | `override ` am Zeilenanfang im Klassenrumpf, Eintrag wählen | Zeile wird zu `procedure Name; override;`, Rumpf mit `inherited` steht im implementation-Teil |
| VK8 | In einer Anweisung `beg`, im Klassenrumpf `prop`, im Deklarationsteil `proc` | `begin` bzw. `property` bzw. `procedure` in der Liste; `try` erscheint im Klassenrumpf nicht |
| VK9 | `"completion": {"keywords": false}` in atlas.json, erneut `beg` | Kein `begin` mehr |
| VK10 | Variable einer Klasse aus einer anderen Unit, `Variable.` | Keine `private`- und `strict private`-Mitglieder, `protected` nur in Methoden von Nachfahren |
| VK11 | In einem mehrzeiligen String `'''` (Delphi 12) Strg+Leer | Kein Popup |
| VK12 | Benchmark: `node Tools/Benchmark/bench.mjs --corpus Tests/Referenzprojekt` | Zeile „completion“ mit n ≥ 100 und p95 unter 100 ms |

## Übernehmen

| Nr. | Schritte | Erwartet |
|---|---|---|
| U1 | `myList := TStringL|ist.` (Cursor mitten im Wort), Strg+Leer, `TStringList` mit Enter | `myList := TStringList.` – kein Rest „ist“ |
| U2 | `TStringL` tippen und mit `.` übernehmen | `TStringList.` |
| U3 | `List.Ad`, `Add` mit Enter übernehmen (#430) | `List.Add(|)`, Cursor zwischen den Klammern, Parameter-Hint offen |
| U4 | `List.Cle`, `Clear` mit Enter | `List.Clear` ohne Klammern |
| U5 | Bei U3 `'x'` tippen, dann `)` | `List.Add('x')` – keine doppelte Klammer |
| U6 | `List.Add(` steht schon da, Cursor vor `(` in `Ad|(`, Strg+Leer, Enter | Keine zweite Klammer |
| U7 | Optionen › Atlas › „Klammern … ergänzen“ aus | `Add` ohne Klammern |
| U8 | Optionen › Atlas › „Vorschau … im Editor“ an; `List.AddS` am Zeilenende (#434) | Hinter dem Cursor kursiv und blass `trings`; folgt der Auswahl mit ↑/↓ |
| U9 | Popup mit Esc schließen bzw. übernehmen | Vorschau verschwindet; Datei unverändert, Rückgängig enthält nichts von der Vorschau |
| U10 | Hinter dem Cursor steht noch Text (z. B. `)`) | Keine Vorschau |

## Parameter-Hint (#436, #437, #438, #439, #440)

| Nr. | Schritte | Erwartet |
|---|---|---|
| P1 | `Format(` tippen | Hint mit allen Überladungen; gewählte mit blauem Balken; Signaturen eingefärbt (Schlüsselwörter blau) |
| P2 | `'%d', ` weitertippen | Aktiver Parameter `Args` auf hellblauer Fläche; unten Name und Beschreibung des Parameters, falls dokumentiert |
| P3 | `StrToInt(Edit1.Text, 10` | Roter Rahmen, unten „Keine Überladung mit 2 Parametern.“ |
| P4 | `myList := TStringList.Create(True)` tippen, dann `)` mit Rücktaste löschen | Hint erscheint wieder, `True` hervorgehoben |
| P5 | Hint mit Esc schließen, `)` tippen und wieder löschen | Hint bleibt zu (mit Esc geschlossen) |
| P6 | `ShowMessage(Format('%d', [` | Oben Pfadzeile „ShowMessage › Format“, darunter die Signaturen von `Format` |
| P7 | In P6 `N])` tippen, sodass `Format` geschlossen ist | Hint zeigt `ShowMessage` ohne Pfadzeile |
| P9 | `Pos(Sub, S, ` (#441) | Aktiver Parameter `Offset: Integer` auf der Pille, ` = 1` gedämpft dahinter; unten „optional, Standard 1“ |
| P10 | Methode mit Standardwert im Detailpanel ansehen | ` = Wert` in der Deklaration gedämpft |
| P8 | Während der Hint offen ist, `.` tippen, sodass die Vervollständigung aufgeht | Hint steht über der Zeile, Liste darunter |

## Hover-Tooltip (#442)

| Nr. | Schritte | Erwartet |
|---|---|---|
| H1 | Maus 0,5 s über `BeginUpdate` (in `Lines.BeginUpdate`) halten | Atlas-Tooltip unter dem Wort: eingefärbte Deklaration, „System.Classes“, Beschreibung (höchstens 4 Zeilen); kein zweiter IDE-Tooltip |
| H2 | Maus vom Wort in den Tooltip bewegen | Tooltip bleibt offen |
| H3 | Maus aus Wort und Tooltip heraus | Tooltip schließt nach etwa 0,3 s |
| H4 | Bei offenem Tooltip tippen, klicken oder scrollen | Tooltip schließt sofort |
| H5 | Über einer Konstante verweilen | Zusätzlich „= Wert“ |
| H6 | Optionen › Atlas › „Eigener Tooltip …“ aus | Wieder der Tooltip der IDE |
| H7 | Bei offenem Tooltip mit Alt+Tab in ein anderes Programm wechseln (#414) | Tooltip verschwindet nach spätestens 0,25 s und bleibt nicht über dem anderen Programm stehen |

## Hover-Navigation (#588)

| Nr. | Schritte | Erwartet |
|---|---|---|
| HN1 | Über `TGalleryFrameClass` in `TGalleryFrameClass = class of TBFrame;` verweilen | Kurzform ohne Pfadzeile; Kopfzeile „Klassenreferenz“, rechts Datei : Zeile; `TBFrame` unterstrichen; Abschnitt „Zieltyp TBFrame“ mit der Kette von TBFrame |
| HN2 | Auf `TBFrame` klicken | Deklaration und Kette von TBFrame, Pfad „TGalleryFrameClass › TBFrame“, „angeheftet“; Maus aus dem Tooltip bewegen: er bleibt offen |
| HN3 | In der Kette auf `TFrame` klicken, dann Rücktaste (bzw. Alt+←) | Wieder TBFrame; der Zurück-Pfeil führt ebenso zurück |
| HN4 | Elfmal auf verschiedene Typen klicken | Pfad beginnt mit „…“, zehn Schritte bleiben |
| HN5 | Esc; dann erneut verweilen | Tooltip schließt; beim nächsten Verweilen wieder die Kurzform |
| HN6 | Angeheftet F12, Umschalt+F12, Strg+C, F1 | Wirken auf den angezeigten Typ: Sprung zu dessen Deklaration; Verwendungen im Meldungsfenster (Gruppe Atlas) und „Verwendungen (n)“; Deklaration in der Zwischenablage; DocWiki bei RTL/VCL-Typen |
| HN7 | Inhalt mehrmals wechseln | Position bleibt, das Fenster wird höchstens größer |
| HN8 | Strg+Klick auf einen Typ im Tooltip | Sprung zur Deklaration, Tooltip schließt |
| HN9 | Strg drücken, während der Tooltip offen ist | Tooltip bleibt offen (nur Umschalt, Strg, Alt allein) |

## Postfix-Vorlagen (#188)

| Nr. | Schritte | Erwartet |
|---|---|---|
| PF1 | In einer Routine `Liste.` tippen (Liste: TStringList), `for` wählen | Zeile wird zu `for var Item in Liste do` (bzw. mit Element-Typ), Cursor eingerückt in der nächsten Zeile; ein Undo-Schritt |
| PF2 | `Obj.tryf` bei einem Objekt | `try … finally Obj.Free; end;` um die Folgezeile |
| PF3 | `X.ifa` bei einer Objekt- oder Zeigervariable | `if Assigned(X) then` |
| PF4 | `S.fmt` bei einem String | `Format(S, [])` |
| PF5 | `Zahl.` (Integer) | keine Postfix-Einträge (Typ passt nicht) |
| PF6 | Projekt mit `delphiVersion` vor 10.3, `Liste.for` | klassische Schleife, `Item` im `var`-Abschnitt der Routine |
| PF7 | `FKunde.notnil` + Enter | `if Assigned(FKunde) then`, Cursor eingerückt in der nächsten Zeile |
| PF8 | `FKunde.nil`, `FKunde.free` | `if not Assigned(FKunde) then` bzw. `FreeAndNil(FKunde);` |
| PF9 | `Fertig.not` rechts von `:=`, `Fertig.if` am Zeilenanfang (Boolean) | `not Fertig` bzw. `if Fertig then` |
| PF10 | `TStringList.Create.try` | `var StringList := TStringList.Create; try … finally StringList.Free; end;`, Name als Platzhalter markiert; Umbenennen ändert auch `.Free` |
| PF11 | `Liste.var`, in einer Funktion `Wert.exit` | `var StringList := Liste;` bzw. `Exit(Wert);`; in einer Prozedur kein `exit` |
| PF12 | `GetKunde(1).notnil`, `TKunde(Obj).free` | Ausdruck samt Aufruf bzw. Typumwandlung wird umschlossen |
| PF13 | `FKunde.nn` tippen | `notnil` in der Liste (Filter über das Kürzel), Marke „Postfix“, hinter allen Mitgliedern |
| PF14 | Eigene Vorlage mit `postfix: true` und `type: TKunde` anlegen, `FKunde.` und `Liste.` | Vorlage nur bei `FKunde` (auch bei Nachfahren von TKunde), `$expr` durch den Ausdruck ersetzt |
| PF15 | `"refactoring": {"inlineVar": false}` in der `atlas.json`, `Liste.var` | `StringList := Liste;` und `StringList: TStringList;` im `var`-Abschnitt |
| PF16 | `"completion": {"postfixTemplates": false}` | keine Postfix-Einträge; mit Snippets aus, aber Postfix an, erscheinen sie weiter |

## Methoden überschreiben (#443)

| Nr. | Schritte | Erwartet |
|---|---|---|
| O1 | In `TLogList = class(TStringList)` im Abschnitt `protected` eine Zeile `procedure ` tippen, Strg+Leer | Liste mit überschreibbaren Methoden von `TStringList` und Vorfahren (z. B. `Changed`, `Put`), Badge Methode |
| O2 | `Changed` übernehmen | Zeile wird `procedure Changed; override;`; im implementation-Teil entsteht `procedure TLogList.Changed; begin inherited; end;` |
| O3 | `function ` tippen, `Get` übernehmen | `function Get(Index: Integer): string; override;`, Rumpf mit `Result := inherited Get(Index);` |
| O4 | Abstrakte Methode des Vorfahren übernehmen | Rumpf ohne `inherited` |
| O5 | Bereits überschriebene Methode | Erscheint nicht noch einmal in der Liste |
| O6 | Liste aus O1 ansehen | Kein „+Unit“-Tag an den Einträgen |

## Letzter Build für Claude Code (#556)

Vorbereitung: MCP eingerichtet (`claude mcp add delphi -- AtlasServer.exe --mcp --root <Projektordner>`); in der IDE einmal Strg+Leer, damit der Atlas-Server läuft.

| Nr. | Schritte | Erwartet |
|---|---|---|
| LB1 | Ohne bisherigen Build `get_last_build` aufrufen | „Noch kein Build aus der IDE für … bekannt …“ statt eines Fehlers |
| LB2 | In der IDE ein Projekt mit Fehler erzeugen (Umschalt+F9), dann `get_last_build` | `result: failed`, Art `build`, Projekt, Konfiguration, Plattform, Dauer, Fehlerzahl und die Meldungen mit Datei, Zeile, Spalte, Code und Text |
| LB3 | Mit `project` = anderer Projektname | „Der letzte Build betraf …, nicht …“ |
| LB4 | Nach dem Speichern (Hintergrundprüfung #548) erneut abfragen | Weiterhin der letzte Build des Benutzers, nicht die Prüfung |
| LB5 | Meldung in einer Bibliotheks-Unit außerhalb des Projektordners | Nicht in `messages`, gezählt in `omittedOutsideWorkspace` |

Rauchtest im MCP-Modus: `tools/list` enthält `get_last_build`, ohne Build die Antwort aus LB1.

## Globale Einstellungen im MCP-Modus (D-08)

Vorbereitung: MCP eingerichtet wie oben; in `%APPDATA%\Atlas\settings.json` steht `"mcp": { "disabledTools": ["rename_symbol"] }`.

| Nr. | Schritte | Erwartet |
|---|---|---|
| MG1 | Claude Code neu starten, `tools/list` | `rename_symbol` fehlt; im Log (`--log`) keine Warnung zur globalen Datei |
| MG2 | In `atlas.json` des Projekts `"mcp": { "globalSettings": false }`, Claude Code neu starten | `rename_symbol` ist wieder da; im Log „Globale Einstellungen ausgeschaltet (mcp.globalSettings)“ |
| MG3 | In `settings.json` zusätzlich `"index": { "libraryPaths": true }`, Claude Code neu starten, `find_symbol` nach einem Typ aus den Bibliothekspfaden | Typ wird gefunden (vorher galt die Vorgabe `false`) |

## Datei außerhalb des einzigen Ordners (S-02)

| Nr. | Schritte | Erwartet |
|---|---|---|
| SO1 | Ein Projektordner offen; eine .pas außerhalb (z. B. aus einem Nachbarordner) öffnen, die eine Include-Datei des Projekts einbindet | Keine Meldung „Include-Datei nicht gefunden“, Dokumentlink auf die .inc funktioniert |
| SO2 | Dieselbe Datei: Prüfregeln | Regeln mit dem Profil aus `atlas.json` des Ordners |
| SO3 | Zwei Ordner offen, Datei außerhalb beider | Hover, Vervollständigung, Hints nach den globalen Einstellungen; inaktive Zweige wie im aktiven Projekt (#615) |

## Compilerprüfung nach dem Speichern (#548)

Vorab gemessen (RAD Studio 13, Mini-Projekt): Syntaxprüfung 0,6–0,9 s, schreibt keine `.exe`/`.dcu` (nur `.res`). In der echten IDE geprüft: Speichern → nach 2 s Prüfung (640 ms) → 2 Meldungen gelesen.

| Nr. | Schritte | Erwartet |
|---|---|---|
| CS1 | In einer Unit des aktiven Projekts `I := 'Text';` (I: Integer) schreiben, speichern | Nach ca. 2 s läuft die Syntaxprüfung; Protokoll „Compilerprüfung nach dem Speichern: Projekt.dproj, n ms“ und „Meldungsfenster: … Meldungen“; im Reiter „Build“ E2010 an der richtigen Zeile |
| CS2 | Mehrmals kurz hintereinander speichern | Nur eine Prüfung, 2 s nach dem letzten Speichern |
| CS3 | Fehler beheben, speichern | Neue Prüfung, keine Meldung mehr |
| CS4 | Während eines eigenen Builds speichern | Keine Prüfung während des Builds |
| CS5 | Im Debugger laufend speichern | Keine Prüfung |
| CS6 | Optionen › Atlas › „Höchstdauer der Prüfung“ auf 200 setzen, speichern | Meldung „Compilerprüfung nach dem Speichern für … abgeschaltet“; weiteres Speichern prüft nicht mehr |
| CS7 | Danach Strg+Alt+F9 bzw. Palette „Atlas: Compiler prüfen“ | Prüfung läuft von Hand |
| CS8 | Optionen › Atlas › „Compiler prüft nach dem Speichern“ aus | Keine Prüfung mehr |
| CS9 | Fortschrittsdialog der IDE (falls „Compilerfortschritt anzeigen“ an) | Schließt nach einer fehlgeschlagenen Prüfung von selbst; bei eigenen Builds bleibt er wie gewohnt |
| CS10 | Wächter-Protokoll bei einer langsamen Prüfung | Hänger mit „Atlas: Compilerprüfung nach dem Speichern“ |

Abweichung vom Issue: Einstellungen in den Plugin-Optionen (Registry) statt `build.checkOnSave*` im Server-Schema; Statusleiste noch offen.

## Compilermeldungen aus der IDE (#528)

Leseweg (Spike 10.10.2026, RAD Studio 13): Reiter „Build“ des Meldungsfensters per RTTI, Objekte `TCompilerMsgLine` mit Kind, Message, FileName, Line, Column – ohne Zwischenablage. Probe mit einem Projekt mit `I := 'Text'` (E2010) und `Writeln(Gibtsnicht)` (E2003): beide Meldungen mit Datei, Zeile und Spalte erkannt.

| Nr. | Schritte | Erwartet |
|---|---|---|
| CM1 | Projekt mit einem Fehler compilieren | Im Protokoll „Meldungsfenster: n Knoten, m Meldungen“ mit m = Zahl der Fehler/Warnungen/Hinweise im Reiter „Build“ |
| CM2 | Fehler beheben, erneut compilieren | „… 0 Meldungen“ (bzw. nur noch Hinweise) |
| CM3 | IDE auf Englisch | Gleiche Zahlen; Codes (E2003 …) unabhängig von der Sprache |
| CM4 | Vorher einmal Strg+Leer (Server läuft), dann compilieren | Im Server-Log „Compilermeldungen aus der IDE: m“ |

Noch offen: Anzeige in Error Insight und in einer projektweiten Liste (#398), Mitwandern der Markierungen bei Änderungen.

## Compile-Ereignisse (#527)

Vorbereitung: Diagnoseprotokoll an (`HKCU\Software\Atlas\IdePlugin`, DWORD `Diagnose` = 1), IDE neu starten; Protokoll `Atlas.IDE.Expert370.log` neben dem Plugin.

| Nr. | Schritte | Erwartet |
|---|---|---|
| C1 | Projekt compilieren (Strg+F9) | Im Protokoll genau einmal „Compile: make App.dproj (Debug, Win32) beginnt“ und „… erfolgreich nach n ms“ |
| C2 | Projekt erzeugen (Umschalt+F9) bzw. Syntaxprüfung | Art „build“ bzw. „check“ |
| C3 | Projektgruppe: „Alle erzeugen“ | „Gruppe build beginnt“, dazwischen jedes Projekt, „Gruppe erfolgreich nach n ms; Code Insight bisher …“ |
| C4 | Fehler einbauen und compilieren | „… fehlgeschlagen nach n ms“ |
| C5 | Im Editor tippen (Code Insight kompiliert im Hintergrund) | Keine Compile-Zeilen; die Zahl „Code Insight bisher n-mal“ steigt beim nächsten Gruppenlauf |
| C6 | IDE schließen bzw. Package über Komponenten › Packages installieren aus- und wieder einschalten | Keine Zugriffsverletzung, danach keine doppelten Zeilen |

Abbruch mit Grund im Meldungsfenster („Atlas“) ist im Dienst vorhanden und getestet; einen Teilnehmer, der abbricht, bringen erst #529/#530.

## Kompilieren ohne Kommandozeilen-Compiler (#261)

Vorbereitung: RAD Studio in einer Ausgabe ohne `dcc32`/`dcc64` (Starter) oder eine, deren `dcc32` nur den Lizenztext ausgibt. Den Text vorher einmal aufzeichnen: `dcc32 > dcc32-starter.txt` im Ordner `bin` und mit `Tests/Data/Compiler/dcc32-starter.txt` vergleichen; weicht er ab, die Kennzeichen in `Atlas.Common.Compiler.Edition` anpassen. Gemerkte Ergebnisse stehen in `%LOCALAPPDATA%\Atlas\compiler-editions.json`; zum Wiederholen löschen. Für den Weg über die IDE in der globalen `settings.json` `"compiler": {"ideCommand": "C:\\…\\cc.ps1"}` setzen.

| Nr. | Schritte | Erwartet |
|---|---|---|
| SE1 | Starter, ohne `compiler.ideCommand`: in VS Code „Atlas: Projekt kompilieren“ (`atlas.server.compile`) | Genau eine Meldung „Atlas kann nicht kompilieren: kein Kommandozeilen-Compiler (Starter Edition: …). In RAD Studio mit dem Atlas-Plugin kompilieren … oder in settings.json "compiler.ideCommand" auf cc.ps1 setzen …“; der Befehl antwortet mit demselben Text als Fehler |
| SE2 | Befehl zweimal wiederholen, Datei speichern | Keine weitere Meldung; der Befehl antwortet jedes Mal mit dem Fehlertext; beim Speichern kein Compileraufruf |
| SE3 | `atlas.server.status` bzw. Statusanzeige des Servers | Zeile „Compiler: nicht verfügbar (Starter Edition)“ |
| SE4 | `compiler-editions.json` ansehen | Eintrag mit BDS-Wurzel, Version und `"edition": "noCommandLine"` (Lizenztext) bzw. `"missing"` (keine dcc32/dcc64); nach einem Serverneustart kein neuer Probelauf |
| SE5 | `compiler.ideCommand` auf `cc.ps1` setzen, Befehl erneut | Status „Compiler: IDE über cc.ps1 (nur auf den Befehl …)“; eine zweite, eigene IDE (Scratch-IDE) startet; Fortschritt „Projekt über eine eigene IDE kompilieren“; danach Fehler und Warnungen des Projekts als Diagnosen an den richtigen Zeilen (Abgleich mit `Tests/Data/Compiler/cc-build.log`) |
| SE6 | Befehl noch einmal | Dieselbe Scratch-IDE wird wiederverwendet (keine zweite neue `bds.exe` im Task-Manager) |
| SE7 | Während SE5 läuft eine IDE des Benutzers mit demselben Projekt | Die IDE des Benutzers baut nicht, ihr Meldungsfenster bleibt unverändert; der Server spricht nur die eigene pid an |
| SE8 | VS Code schließen (Server endet) | Die Scratch-IDE schließt sich (`cc.ps1 quit`); die IDE des Benutzers bleibt offen |
| SE9 | `"compiler": {"backend": "off"}` | Keine Meldung; Status „Compiler: nicht verfügbar (abgeschaltet)“; der Befehl antwortet mit dem Fehlertext |
| SE10 | `"backend": "dcc"` auf der Starter | Wie SE1, aber kein Weg über die IDE, auch wenn `ideCommand` gesetzt ist |
| SE11 | Ausgabe mit Kommandozeilen-Compiler, `"backend": "auto"` | Status „Compiler: dcc (Kommandozeile)“; Bauen wie bisher (#40), kein Start einer IDE |
| SE12 | `compiler.ideCommand` zeigt auf eine fehlende Datei | Meldung nennt Starter Edition und „"compiler.ideCommand" zeigt auf keine vorhandene Datei“ |

### Builds für Claude Code (`build_project`)

Vorbereitung: RAD Studio mit Atlas-Plugin, Projekt offen; Claude Code mit dem Atlas-MCP-Server im Projektordner.

| Nr. | Schritte | Erwartet |
|---|---|---|
| MB1 | Claude Code: „Baue das Projekt über build_project“ | Meldungsansicht „Claude Code baut App.dproj in der IDE …“, die IDE baut (Fortschrittsdialog schließt sich selbst), danach „Build für Claude Code beendet: App.dproj, n Fehler“; das Werkzeug liefert Erfolg, Dauer und die Meldungen mit Datei, Zeile und Spalte wie `get_last_build` |
| MB2 | Mit `mode: "build"`, `configuration: "Release"`, `platform: "Win64"` | Gebaut wird Release/Win64; danach stehen Konfiguration und Plattform in der IDE wieder wie vorher |
| MB3 | Unbekannte Konfiguration bzw. Plattform | Ablehnung mit Grund im Werkzeug und „Build für Claude Code abgelehnt: …“ in der Meldungsansicht |
| MB4 | Während der Debugger läuft | Ablehnung „… Debugger …“; nichts wird gebaut |
| MB5 | Während ein Build von Hand läuft (Strg+F9) | Ablehnung; der laufende Build wird nicht gestört |
| MB6 | Optionen › Atlas › Compiler › „Builds für Claude Code“ aus (oder Schnellschalter) | Das Werkzeug meldet nach kurzer Frist „nicht angenommen“, die IDE baut nicht |
| MB7 | Projekt in keiner IDE offen | Werkzeug antwortet sofort „Keine RAD-Studio-IDE mit …“ |
| MB8 | `get_last_build` nach MB1 | Derselbe Build mit `requestedBy: "mcp"` |

## Probleme im Editor (#398, #528, #548)

| Nr. | Schritte | Erwartet |
|---|---|---|
| PR1 | In einer Unit `if then` tippen und kurz warten | Nach etwa einer halben Sekunde rote Wellenlinie unter der Stelle |
| PR2 | Maus über die Wellenlinie, auch über `;` oder Leerraum | Tooltip mit roter Leiste, Meldung, darunter „Atlas“; über einem Bezeichner zusätzlich der normale Hover darunter |
| PR3 | Regeltreffer (z. B. unbenutzte Variable) | Gelbe Wellenlinie, Tooltip mit Regel-ID in Klammern |
| PR4 | Oberhalb eines Problems Zeilen einfügen | Die Markierung wandert sofort mit, ohne zu flackern |
| PR5 | Strg+F9 mit einem Compilerfehler | Rote Wellenlinie an der Stelle des dcc-Fehlers, im Tooltip „Compiler“ |
| PR6 | Danach in der Zeile tippen | Compilermarkierung wird blass („seit dem letzten Prüfen geändert“), bis zum nächsten Compile |
| PR7 | Meldungsfenster, Reiter „Atlas-Probleme“ | Probleme aller Projektdateien (auch nicht geöffneter), ohne Compilermeldungen; Doppelklick springt zur Stelle |
| PR8 | Problem beheben | Wellenlinie und Eintrag in der Liste verschwinden |
| PR9 | Datei im Editor schließen, außerhalb ändern | Liste zeigt den Stand der Datei auf der Platte |
| PR10 | Optionen › Atlas › „Probleme im Editor unterstreichen …“ aus | Keine Wellenlinien, Liste leer, keine Probleme im Tooltip |

## Klammer- und Blockpaare (#514)

| Nr. | Schritte | Erwartet |
|---|---|---|
| KP1 | Methode mit drei verschachtelten `begin`/`end` | Drei verschiedene Farben; zusammengehörige `begin`/`end` gleich |
| KP2 | `try … finally … end`, `repeat … until` | `finally` und `end` in der Farbe ihres `try`, `until` wie `repeat` |
| KP3 | `Format('(%d', [Length(S)])` | `(` im String ungefärbt, Klammern nach Tiefe |
| KP4 | Ein `end;` löschen | Das unpaarige `begin` wird rot |
| KP5 | `TFoo = class` … `end;`, `class function`, `TBar = class;`, `procedure … of object` | Nur die Klassendeklaration mit Rumpf ist ein Paar |
| KP6 | Text markieren | Markierung wie gewohnt (Atlas färbt markierten Text nicht) |
| KP7 | Helles und dunkles IDE-Thema | Farben in beiden lesbar |
| KP8 | Optionen › Atlas › „Klammern und Blockpaare … färben“ aus | Normale Farben der IDE |
| KP9 | Teile des Editors neu zeichnen lassen (Tooltip, Vervollständigung schließen, scrollen) | Keine Paarfarben mitten in Bezeichnern |
| KP10 | Sechs verschachtelte `begin`/`end` | Senkrechte Linie je Block in der Farbe ihres Wortpaars, Haken an `begin` und `end` |
| KP11 | `TFoo = class` … `end;`, `if A then begin` … `end;` | Linie vor `TFoo` bzw. vor `if` |
| KP12 | Erster Start mit Blocklinien | Meldung im Meldungsfenster; ab dem nächsten Start keine Linien der IDE mehr |
| KP13 | Optionen › Atlas › „Blocklinien in den Paarfarben“ aus, Delphi neu starten | Keine Atlas-Linien; Strukturhervorhebung der IDE wieder an |

Help Insight der IDE (#442): Solange der Atlas-Tooltip an ist, schaltet Atlas Help Insight in der Registry ab (`Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal`, `Help Insight`), ab dem nächsten Start zeigt die IDE keinen zweiten Tooltip; mit Atlas-Tooltip aus wieder an (nur wenn Atlas abgeschaltet hatte).

| Nr. | Schritt | Erwartet |
|---|---|---|
| HI1 | Atlas-Tooltip an, Maus auf einem Typ (z. B. `TMyClass = class`) | Nur der Atlas-Tooltip, kein Help Insight der IDE darüber, auch in der ersten Sitzung |
| HI2 | Tools › Optionen › OK (beliebige Seite), Delphi neu starten, wie HI1 | Weiterhin nur der Atlas-Tooltip; Registry `Help Insight` = `False` |
| HI3 | Diagnose = 1, wie HI1 | Im Log `GetHelpInsightHtml aufgerufen` |
| HI4 | Atlas › Hauptschalter aus, Maus auf einem Typ | Nur der Tooltip der IDE, kein Atlas-Tooltip |
| HI5 | Atlas-Tooltip aus | Symbolhinweis der IDE mit dem Text von Atlas; Help Insight nach dem nächsten Start wieder wie vorher |
| HI6 | Maus auf `TDataSource` in `Data.DB.pas` (vorwärts deklariert in Zeile 29, voll in Zeile 1988) | Fundort `Data.DB.pas : 1988`, Vererbung `TDataSource › TComponent › TPersistent › TObject` (erster Start baut den Index neu, Cache-Format 12) |

Blocklinien zeichnet Atlas selbst (Einstellung „Blocklinien in den Paarfarben“). Solange sie an sind, ist die Strukturhervorhebung der IDE in der Registry abgeschaltet (`Editor\Highlight\Structural Highlighting`, `Enabled`). Die IDE liest das nur beim Start. Hat der User sie selbst abgeschaltet, ändert Atlas nichts.

## Befehlspalette (#502)

| Nr. | Schritte | Erwartet |
|---|---|---|
| BP1 | Im Editor Strg+Umschalt+P | Palette oben mittig über dem aktiven Fenster, sofort (unter 100 ms), Eingabefeld mit „>“ |
| BP2 | `bpj` tippen bzw. `pe` (deutsche IDE) | „Projekt erzeugen“ bzw. „Build Project“ in der Liste, getroffene Zeichen hervorgehoben; Menüpfad gedimmt, Tastenkürzel rechts |
| BP3 | Enter | Befehl läuft (Projekt wird erzeugt); Palette ist zu |
| BP4 | Strg+Umschalt+P erneut, nichts tippen | Der eben ausgeführte Befehl steht oben |
| BP5 | `atlas` tippen | Atlas-Befehle („Atlas: Protokoll öffnen“, „Atlas: Verlauf … zurücksetzen“, „Atlas: Wächter testen (1 s)“) gemeinsam mit IDE-Aktionen |
| BP6 | „Atlas: Protokoll öffnen“ | `Atlas.IDE.Expert370.log` öffnet sich im Editor |
| BP7 | Esc bzw. Klick neben die Palette | Palette schließt, nichts wird ausgeführt |
| BP8 | ↑/↓, Bild↑/↓, Mausrad, Klick auf eine Zeile | Auswahl bewegt sich, Klick führt aus |
| BP9 | Rücktaste, Strg+Rücktaste | Ein Zeichen bzw. ganze Eingabe gelöscht |

Abgrenzung: IDE Insight (Strg+.) ist modal und durchsucht auch Optionen und Komponenten, kennt aber keine Atlas-Befehle und keinen Verlauf. Strg+Umschalt+P ist in der IDE „Tastenmakro abspielen“; die Palette übernimmt das Kürzel. Noch offen: Strg+Enter (Kürzel zuweisen).

## Code Insight aus dem Server (#394)

| Nr. | Schritte | Erwartet |
|---|---|---|
| CI1 | *Tools › Optionen › Editor › Sprache › Code Insight*: Manager „Atlas IDE Expert“ für Delphi aktiv; IDE neu starten | Meldungsansicht ohne Fehler; Protokoll nennt den gestarteten `AtlasServer.exe` |
| CI2 | Maus über einen Bezeichner aus der eigenen Unit und einen aus der RTL (`TStringList`) | Atlas-Tooltip mit Deklaration, Unit und XMLDoc; kein Help-Insight-Fenster der IDE daneben |
| CI3 | In einer Methode Strg+Leer ohne Präfix | Atlas-Popup mit lokalen Namen, Parametern, Feldern, Unit- und uses-Bezeichnern; die eingebaute Liste der IDE erscheint nicht |
| CI4 | `TStringList` in einer Unit ohne `System.Classes` tippen, Strg+Leer, Enter | Eintrag mit Tag „+ System.Classes“; nach Enter steht `System.Classes` in der uses-Liste, ein Rückgängig nimmt beides zurück |
| CI5 | `Format(` tippen | Atlas-Parameter-Hint mit aktivem ersten Parameter; nach `, ` wechselt der aktive Parameter |
| CI6 | Überladene Routine (`IntToStr(`) | Hint zeigt die Zahl der Überladungen; ↑/↓ blättert durch sie |
| CI7 | `AtlasServer.exe` umbenennen, IDE neu starten, Strg+Leer | Meldungsfenster nennt den nicht gefundenen Server; Vervollständigung und Hinweise der eingebauten Code Insight funktionieren |
| CI8 | Server im Task-Manager beenden, danach Strg+Leer | Atlas startet den Server neu, die Liste erscheint (ggf. „eingeschränkt“, solange er indiziert) |
| CI9 | Server im Task-Manager beenden, sofort in einer Methode `Self.` tippen (automatische Liste), dann Strg+Leer | Kein Fehlerdialog, keine Zugriffsverletzung; die automatische Liste kommt ohne Server-Einträge, Strg+Leer startet den Server und zeigt sie; im Protokoll kein „Zeitlimit … überschritten“ für die Server-Quelle (Code-Review A-01) |
| CI10 | CI9 dreimal innerhalb von fünf Minuten | Die Quelle „Server“ bleibt eingeschaltet (*Optionen › Atlas › Robustheit* ohne Eintrag) |
| CI11 | Maus auf einem Bezeichner halten, bis der Tooltip lädt; währenddessen Statusfeld › Server neu starten | Kein Absturz, kein Tooltip aus der alten Sitzung; Neustart wie gewohnt (A-07) |
| CI12 | Hover über einem Bezeichner auslösen und sofort *Komponenten › Packages installieren* › Atlas abwählen (Package entladen); danach weiterarbeiten | Kein Absturz beim Entladen und danach; Protokoll „Atlas entladen in … ms; Hintergrund-Threads beendet: True“ (A-02) |
| CI13 | Server einen `workspace/applyEdit` schicken lassen (z. B. Code-Aktion „uses ergänzen“) und die Datei vorher schreibgeschützt setzen | Kein Fehlerdialog der IDE; der Server bekommt genau eine Antwort (`applied: false` mit Grund), mit `Diagnose` = 1 steht „workspace/applyEdit: …“ im Protokoll (S-05) |

## Symbolindex (#492)

| Nr. | Schritte | Erwartet |
|---|---|---|
| SX1 | Projekt öffnen, das noch nie indiziert war | Das Atlas-Feld der Statuszeile ist gelb mit „Atlas · Index n %“ (#591), die Vervollständigung vermerkt „eingeschränkt“; nach dem Aufbau wird das Feld grün |
| SX2 | IDE schließen und wieder öffnen | Index kommt aus dem Cache (Protokoll: „aus dem Cache“), bei 1000 Units in unter 3 s |
| SX3 | `%LOCALAPPDATA%\Atlas\Index\<Version>\<Hash>\index.atlasidx` mit einem Hex-Editor verändern, IDE neu starten | Kein Fehlerdialog; Server-Protokoll „Index-Cache verworfen (Prüfsumme stimmt nicht)“, der Index wird neu aufgebaut |
| SX4 | Neue Funktion im interface einer Unit deklarieren, speichern, in einer anderen Unit Strg+Leer | Die Funktion ist nach höchstens 1 s in der Liste |
| SX5 | *Tools › Optionen › Drittanbieter › Atlas*, Abschnitt „Symbolindex“ | Units, Deklarationen, Speicher von Grenze, Größe auf der Platte, letzte Aktualisierung |
| SX6 | „Index löschen“, Rückfrage mit Nein, dann mit Ja | Nein: nichts passiert; Ja: Meldung „Index gelöscht: n Caches, … frei“, danach SX1 |
| SX7 | „Speichergrenze des Index“ auf 32 MB, großes Projekt öffnen | Kennzahlen: „Verwendungen von n Units ausgelagert“; Vervollständigung funktioniert weiter |
| SX8 | Cache-Datei des Projekts von einem anderen Programm exklusiv geöffnet halten bzw. den Cache-Ordner schreibschützen, dann „Index neu aufbauen“ | Server-Log „Fehler beim Aufbau des Symbolindex …“; Fortschritt endet mit „Fehlgeschlagen“; die Problemansicht füllt sich danach, kein dauerhaftes „Index lädt“ |

## Rangfolge nach Gültigkeitsbereich (#488)

| Nr. | Schritte | Erwartet |
|---|---|---|
| RB1 | In `function TKasse.Calc(ACustomer: Integer)` mit `var Total` bei `Total := |` Strg+Leer | Reihenfolge `Total` („lokal“), `ACustomer` („Parameter“), `FDiscount` („Feld“) |
| RB2 | Inline-Variable `var Unten := 1;` unterhalb des Carets | `Unten` erscheint nicht |
| RB3 | Lokale Variable `Name`, die das Feld `Name` der Klasse verdeckt | `Name` einmal mit „lokal“; das Detailpanel nennt „Verdeckt: Feld TKlasse.Name“ |
| RB4 | Methode von `Self` und Routine aus einer uses-Unit in der Liste | Tag mit der Klasse bzw. dem Namen der Unit |

## Favoriten anheften (#458)

| Nr. | Schritte | Erwartet |
|---|---|---|
| FA1 | In einer Methode mit `qry: TFDQuery` hinter `qry.` Strg+Leer, `Open` wählen, Strg+D | Fußzeile „Open angeheftet · Strg+D löst“; `Open` steht mit gefülltem Stern links ganz oben, die Auswahl bleibt auf `Open`; der Editor formatiert nichts |
| FA2 | Mit der Maus über `ParamByName` fahren, auf den leeren Stern links klicken | Stern gefüllt, `ParamByName` steht oben (zusammen mit `Open`); die Auswahl ändert sich nicht |
| FA3 | Andere Query `qry2.` Strg+Leer, ohne Präfix, dann `P`, dann `Op`, dann `Cl` | Ohne Präfix beide Favoriten oben; mit `P` nur `ParamByName` oben; mit `Op` nur `Open`; mit `Cl` keiner (sie passen nicht) |
| FA4 | Viele Male `Close` übernehmen (lernende Gewichtung), dann `qry.` Strg+Leer | `Open` und `ParamByName` stehen trotzdem vor `Close` |
| FA5 | Bei `TDataSet` fünf Member anheften, einen sechsten mit Strg+D | Fußzeile „Schon 5 Favoriten bei TDataSet – erst einen lösen“; nichts ändert sich; Sprachausgabe liest den Hinweis |
| FA6 | IDE beenden und neu starten, `qry.` Strg+Leer | Favoriten aus FA1/FA2 stehen weiter oben; `%APPDATA%\Atlas\favorites.json` enthält sie |
| FA7 | *Tools › Optionen › Drittanbieter › Atlas*, Reiter Vervollständigung: Liste „Angeheftete Favoriten“, `TDataSet.Open` wählen, „Entfernen“ | Eintrag verschwindet sofort; beim nächsten `qry.` steht `Open` wieder an seinem Platz |
| FA8 | „Alle entfernen“ | Liste zeigt „Keine Favoriten angeheftet.“, Knöpfe ausgegraut |
| FA9 | Häkchen „Favoriten anheften“ aus (oder Schnellschalter), `qry.` Strg+Leer, Strg+D | Keine Sternspalte, keine Sonderstellung; Strg+D geht an den Editor |
| FA10 | Auf „Neue Methode …“ bzw. „Alle Werte einfügen“ Strg+D | Fußzeile „Dieser Eintrag lässt sich nicht anheften“ |
| FA11 | Popup bei 150 % und 200 % Skalierung, hell und dunkel | Stern scharf und mittig, Badge rückt um die Sternspalte nach rechts, nichts abgeschnitten |

## Persönliche Notizen (#545)

Ablage: `%LOCALAPPDATA%\Atlas\Notes\<Schlüssel>.json` je Projekt (Schlüssel wie die Projekt-Zusammenfassung aus #592), JSON mit `format` 1, `project` und `notes` (je Notiz `id`, `file`, `line` 1-basiert, `text`, `lineText`, `before`, `after`, `created`, `changed` in UTC, bei Bedarf `orphaned`). Nie im Projekt- oder Repository-Ordner.

| Nr. | Schritte | Erwartet |
|---|---|---|
| NO1 | Projekt in einem Git-Repository öffnen, Cursor in eine Methode, *Atlas › Notiz an dieser Zeile…*, zwei Zeilen Text, Strg+Enter | Dialog „Notiz – Kunde.pas, Zeile 42“ mit Hinweis; nach Strg+Enter links in der Rinne ein kleines Notizblatt an der Zeile |
| NO2 | `git status` im Repository | Keine Änderung, keine neue Datei; die Notiz steht in `%LOCALAPPDATA%\Atlas\Notes\` |
| NO3 | Maus über das Notizblatt in der Rinne halten | Nach etwa 0,3 s Tooltip „Notiz vom 15.10.2026“ mit beiden Zeilen; Maus weg schließt ihn |
| NO4 | Oberhalb der Zeile drei Zeilen einfügen, kurz warten | Das Symbol wandert mit seiner Codezeile nach unten (Akzeptanzkriterium) |
| NO5 | Die Codezeile der Notiz leicht ändern (z. B. Parameter umbenennen) | Symbol verschwindet kurz und steht nach der Tipp-Pause wieder an derselben Zeile |
| NO6 | Rechtsklick in die Rinne einer anderen Zeile, Kontextmenü › *Atlas › Notiz an dieser Zeile…* | Dialog nennt die angeklickte Zeile, nicht die Cursorzeile |
| NO7 | *Atlas › Notizen des Projekts* | Ergebnisfenster „Notizen in Projekt.dproj: n, davon 0 verwaist“, je Datei eine Gruppe mit „Zeile: erste Textzeile“; alle Notizen des Projekts (Akzeptanzkriterium) |
| NO8 | Doppelklick bzw. Enter auf einen Eintrag | Editor springt zur Zeile |
| NO9 | Kontextmenü eines Eintrags › „Notiz bearbeiten…“, Text ändern, speichern | Liste zeigt den neuen Text, Eintrag bleibt gewählt |
| NO10 | Die Codezeile samt Nachbarn löschen, Liste neu öffnen | Notiz unter „Verwaist (1)“ mit Datei und letzter Zeile; kein Symbol in der Rinne |
| NO11 | Eintrag wählen, Entf, Rückfrage mit Ja | Notiz verschwindet aus Liste und Rinne |
| NO12 | Datei mit Notizen außerhalb der IDE löschen oder umbenennen, Liste öffnen | Ihre Notizen stehen unter „Verwaist“ |
| NO13 | Dialog einer vorhandenen Notiz, Text ganz löschen, Speichern | Notiz gelöscht; bei einer neuen Notiz ohne Text wird nichts angelegt |
| NO14 | IDE neu starten, Datei öffnen | Symbole und Liste wie vorher |
| NO15 | Einstellung „Persönliche Notizen…“ (Reiter Editor) aus bzw. Schnellschalter „Notizen“ | Keine Symbole; Einträge im Menü *Atlas* und in der Befehlspalette verschwinden; das Kontextmenü meldet „Persönliche Notizen sind ausgeschaltet …“ in der Meldungsansicht |
| NO16 | Rinne bei 100 %, 150 % und 200 %, hell und dunkel, mit Haltepunkt und Lesezeichen an derselben Zeile | Symbol sichtbar und nicht abgeschnitten; prüfen, ob es Haltepunkt- oder Lesezeichen-Symbol überdeckt (Lage links in der Rinne ist ungeprüft) |
| NO17 | Rinnen-API: Delphi 12 und 13, Symbol erscheint überhaupt (`cevPaintGutterEvents`, letzte Stufe von `TPaintGutterStage`) und Maus-Ereignisse kommen in der Rinne an (Tooltip, Rechtsklick) | Funktioniert in beiden Versionen; sonst Rückmeldung mit Version |
| NO18 | Ohne geöffnetes Projekt eine einzelne Datei öffnen, Notiz anlegen | Meldung „Notizen gehören zu einem Projekt …“ |

## Benannte Lesezeichen (#622)

Ablage je Projekt neben der .dproj (Projekte im selben Ordner teilen sich die Datei): lokal `.atlas-bookmarks.json`, die Atlas beim Speichern in `.git/info/exclude` des Repositorys einträgt (nur lokal, nichts Eingechecktes ändert sich); mit „Lesezeichen im Repository für das Team speichern“ (`bookmarks.shared`) `atlas-bookmarks.json` zum Einchecken. Gibt es die Team-Datei noch nicht, gelten zunächst die lokalen Lesezeichen, das nächste Speichern legt die Team-Datei an. JSON UTF-8 ohne BOM mit `format` 1, `project` und `bookmarks` in Listenreihenfolge (je Lesezeichen `id`, `name`, `file` relativ mit „/“, `method`, `signature`, `offset`, `line` 1-basiert, `lineText`, `before`, `after`, `created` in UTC, bei Bedarf `lost`). Eine leere Liste löscht die Datei.

| Nr. | Schritte | Erwartet |
|---|---|---|
| BM1 | Projekt in einem Git-Repository öffnen, Cursor in eine Methode `TKunde.Runde`, Strg+Alt+K | Kleines Fenster „Lesezeichen – Kunde.pas, Zeile 42“, Vorschlag „Runde: Result := Round(…“ ist markiert; Enter setzt, links in der Rinne ein gelbes Lesezeichenband |
| BM2 | Maus über das Band halten | Tooltip „Lesezeichen“ mit dem Namen; zwei Lesezeichen an derselben Zeile: „2 Lesezeichen an dieser Zeile“ und beide Namen |
| BM3 | `git status` | Keine neue Datei: `.atlas-bookmarks.json` liegt neben der .dproj, steht aber in `.git/info/exclude` |
| BM4 | *Atlas › Lesezeichen-Fenster* | Andockbares Fenster „Atlas-Lesezeichen“ mit Filterfeld, Spalten Name, Datei (mit Zeile), Methode, Zeilenvorschau; unten „Lesezeichen in Projekt.dproj: 3, davon 0 nicht gefunden · Lokal in .atlas-bookmarks.json …“; andocken wie andere IDE-Fenster |
| BM5 | Im Fenster Filter „kunde rund“, ↓, Enter; dann Klick auf einen anderen Eintrag | Liste zeigt nur passende Einträge; Enter bzw. Klick springt im Editor zur Zeile |
| BM6 | Eintrag wählen, F2, neuen Namen, Enter; dann Entf und Rückfrage mit Ja | Name geändert (leerer Name bleibt beim alten); gelöschter Eintrag verschwindet aus Liste und Rinne |
| BM7 | Eintrag per Maus nach oben ziehen; Strg+↓ auf einem Eintrag | Reihenfolge ändert sich und bleibt nach Neustart erhalten (auch in „Gehe zu Lesezeichen…“) |
| BM8 | Methode mit Lesezeichen um 50 Zeilen nach unten verschieben (z. B. 50 Zeilen davor einfügen oder ausschneiden und weiter unten einfügen), kurz warten | Band wandert mit; Liste zeigt die neue Zeile (Akzeptanzkriterium) |
| BM9 | IDE neu starten, Projekt öffnen, Fenster bzw. *Gehe zu Lesezeichen…* | Lesezeichen vorhanden und an der richtigen Zeile (Akzeptanzkriterium) |
| BM10 | Datei außerhalb der IDE durch eine Fassung ohne die Methode ersetzen, IDE fragt nach Neuladen → Ja; Fenster öffnen | Lesezeichen steht grau mit „nicht gefunden · …“ in der Liste, kein Band in der Rinne (Akzeptanzkriterium); Sprung zeigt die letzte bekannte Stelle mit Meldung |
| BM11 | Datei wiederherstellen (Methode wieder da) | Lesezeichen gilt wieder, Band erscheint |
| BM12 | *Atlas › Gehe zu Lesezeichen…* (auch Befehlspalette), „rp“ bzw. Dateiname tippen | Fenster wie die Befehlspalette mit allen Lesezeichen in Listenreihenfolge, Ort „Kunde.pas:42 › TKunde.Runde“ grau daneben; unscharfe Suche über Name, Datei und Methode; Enter springt |
| BM13 | Rechtsklick in die Rinne einer anderen Zeile, Kontextmenü › *Atlas › Lesezeichen setzen…* | Dialog nennt die angeklickte Zeile |
| BM14 | „Lesezeichen im Repository für das Team speichern“ einschalten, ein Lesezeichen umbenennen | `atlas-bookmarks.json` (ohne Punkt) entsteht neben der .dproj mit allen bisherigen Lesezeichen und erscheint in `git status`; die lokale Datei bleibt unverändert |
| BM15 | Einstellung „Benannte Lesezeichen“ (Reiter Editor) aus bzw. Schnellschalter | Keine Bänder, Fenster schließt, Einträge im Menü *Atlas* und in der Befehlspalette verschwinden, Strg+Alt+K tut nichts mehr; das Kontextmenü meldet „Benannte Lesezeichen sind ausgeschaltet …“; die nummerierten IDE-Lesezeichen (Strg+Umschalt+0…9, Strg+0…9) funktionieren unverändert (Akzeptanzkriterium) |
| BM16 | Strg+Alt+K in der Tastenkürzel-Übersicht (#520) und auf *Tools › Optionen › Atlas*, Reiter Befehle | Eintrag „Lesezeichen setzen“; Konflikt mit einer anderen Belegung wird gemeldet; leeres Tastenfeld = keine Taste |
| BM17 | Rinne bei 100 %, 150 % und 200 %, hell und dunkel, mit Notiz und IDE-Lesezeichen an derselben Zeile | Notizblatt und Band nebeneinander, nichts abgeschnitten; prüfen, ob sie IDE-Symbole überdecken |
| BM18 | Ohne geöffnetes Projekt eine einzelne Datei öffnen, Strg+Alt+K | Meldung „Lesezeichen gehören zu einem Projekt …“ |

## Tippfehler (#485)

| Nr. | Schritte | Erwartet |
|---|---|---|
| TF1 | `Lenght|` und Strg+Leer | „Meintest du“ mit `Length`; Fußzeile „Keine Treffer für ‚Lenght‘“ |
| TF2 | Wie TF1, dann `;` | Nur `;` wird eingefügt, nichts übernommen |
| TF3 | Wie TF1, dann Enter | `Length` wird übernommen |

## Atlas-Statusfeld (#591)

| Nr. | Schritte | Erwartet |
|---|---|---|
| SF1 | IDE starten, Projekt öffnen, Unit öffnen | Rechts in der Statusleiste des Editors „Atlas“ mit Punkt; gelb mit „Atlas · Index n %“, solange der Index aufgebaut wird, danach grün |
| SF2 | Maus über das Feld | Tooltip mit den Zeilen, die nicht grün sind; alles grün: „Atlas: alles in Ordnung“ |
| SF3 | Klick auf das Feld | Fenster über dem Feld mit „Server: läuft, n ms im Mittel der letzten 50 Anfragen, Version …“, „Index: n Units“, „Datei X.pas: …“ und den Knöpfen „Protokoll öffnen“, „Server neu starten“; Esc oder Klick daneben schließt |
| SF4 | `AtlasServer.exe` im Task-Manager beenden | Feld innerhalb von 2 s rot („Atlas · Server gestoppt“) |
| SF5 | Feld anklicken, „Server neu starten“ | Feld erst gelb, dann grün |
| SF6 | Datei mit UTF-8 ohne BOM und LF öffnen, Feld anklicken | Zeile „Datei …: UTF-8 ohne BOM, LF“ |
| SF7 | Zeile „Datei“ anklicken, „UTF-8 mit BOM, CRLF“ wählen, speichern | Datei ist als geändert markiert; nach dem Speichern hat sie BOM und CRLF (Hex-Editor), die IDE fragt nicht nach Neuladen, Meldung „… gespeichert als UTF-8 mit BOM, CRLF“ |
| SF8 | Optionen: „Atlas-Feld in der Statusleiste“ aus, dann an | Feld verschwindet sofort und erscheint wieder |
| SF9 | Optionen: „Kurztext neben „Atlas“ zeigen“ aus; „Ausgeblendete Zeilen“ = `atlas.file` | Feld zeigt nur „Atlas“; im Fenster fehlt die Zeile „Datei“ |
| SF10 | Zweites Editorfenster öffnen (Ansicht › Neues Editorfenster) | Auch dort ein Atlas-Feld |
| SF11 | Package entladen | Felder verschwinden, die Statusleisten verhalten sich wie ohne Atlas |
| SF12 | Index neu aufbauen (Menü *Atlas*), während der Server langsam ist | Statusfeld zeigt „Atlas · Server langsam · Index NN %“, der Menütitel bleibt „Atlas“; nach dem Aufbau verschwindet der Fortschritt |
| SF13 | „Fortschritt des Symbol-Index“ = Im Menütitel, dann Index neu aufbauen | Menütitel „Atlas – …“ mit Fortschritt, im Statusfeld nur noch als Kurztext, wenn der Index die wichtigste Zeile ist; „Nicht anzeigen“: nirgends |

## Schnellschalter (#604)

| Nr. | Schritte | Erwartet |
|---|---|---|
| QS1 | Rechtsklick auf das Atlas-Feld in der Statusleiste | Fenster „Atlas · Schnellschalter“ über dem Feld, Schalter nach Seiten gruppiert (Allgemein, Editor, Hints, Vervollständigung, Compiler), u. a. „Klammerfarben“, „Blocklinien“, „XMLDoc vollständig“ |
| QS2 | Strg+Umschalt+Alt+A im Editor | Dasselbe Fenster; zweimal drücken schließt es; Esc oder ein Klick daneben schließt es ebenfalls |
| QS3 | Tools › Optionen › Atlas › Tastenkonflikte: Taste „Schnellschalter“ auf Strg+Umschalt+Q ändern | Neue Taste öffnet das Fenster sofort, die alte nicht mehr |
| QS4 | Im Fenster „Klammerfarben“ anklicken | Farbige Klammerpaare verschwinden sofort, das Fenster bleibt offen und zeigt das Kästchen leer; Tools › Optionen › Atlas zeigt „Klammerfarben“ aus |
| QS5 | IDE neu starten | Klammerfarben bleiben aus; erneut anklicken schaltet sie wieder an |
| QS6 | „Blocklinien“ mit ↑/↓ wählen, Leertaste | Blocklinien aus bzw. an, Strukturhervorhebung der IDE entsprechend an bzw. aus |
| QS7 | „Alles aus für diese Sitzung“ | Klammerfarben, Blocklinien, ausgegraute {$IFDEF}-Zweige und Unterstreichungen verschwinden; Kopf zeigt „Zeichnungen für diese Sitzung aus“, Knopf heißt „Alles wieder an“; Tools › Optionen › Atlas zeigt unverändert die alten Werte |
| QS8 | „Alles wieder an“ | Alle Zeichnungen wie vorher; nach einem IDE-Neustart ohne erneuten Klick ist ohnehin alles wieder an |
| QS9 | atlas.json mit `"hints": { "xmlDocFull": false }`, Fenster öffnen | „XMLDoc vollständig“ ist aus und trägt rechts „Projekt“ |
| QS10 | „XMLDoc vollständig“ anklicken, „Nur für diese Sitzung“ | Tooltip und Detailpanel zeigen die volle Doku; der Schalter trägt „Sitzung“; atlas.json und Optionen unverändert |
| QS11 | Schalter erneut anklicken, dann wie QS9 mit „Im Projekt (atlas.json)“ | atlas.json enthält `"xmlDocFull": true`, Kommentare und Reihenfolge bleiben; Optionsseite unverändert |
| QS12 | Befehlspalette: „Atlas: Klammerfarben ein/aus“, „Atlas: Alles aus für diese Sitzung“, „Atlas: Schnellschalter öffnen“ | Wie die Klicks im Fenster bzw. Fenster öffnet unten links im aktiven Fenster, wenn kein Statusfeld da ist |
| QS13 | Menü Atlas › „Klammerfarben“ | Häkchen wie im Fenster; Umschalten wirkt wie dort |
| QS14 | Doppelklick auf das Atlas-Feld in der Statusleiste | Fenster „Atlas · Schnellschalter“ über dem Feld; das Statusfenster des ersten Klicks schließt sich, beim Loslassen öffnet es nicht erneut |
| QS15 | Tools › Optionen › Atlas › Allgemein: „Schnellschalter öffnen mit“ = Rechtsklick, dann Doppelklick auf das Feld | Kein Schnellschalter-Fenster; der Doppelklick wirkt wie zwei einfache Klicks (Statusfenster öffnet und schließt); Rechtsklick öffnet die Schnellschalter |
| QS16 | „Schnellschalter öffnen mit“ = Doppelklick, dann Rechtsklick auf das Feld | Kein Schnellschalter-Fenster, der Rechtsklick geht an die IDE; Doppelklick öffnet die Schnellschalter |

## Abgesicherter Start (#722)

| Nr. | Schritte | Erwartet |
|---|---|---|
| AS1 | IDE mit Atlas starten, `%LOCALAPPDATA%\Atlas\Session` öffnen | Datei `session-<Prozessnummer>.json` mit Version, Startzeit, `loaded: true`, Ladezeit und aktiven Funktionen |
| AS2 | IDE normal beenden | Die Marke ist weg; `safemode.json` hat `crashCount: 0` |
| AS3 | IDE starten, im Taskmanager `bds.exe` beenden, IDE neu starten | Unten rechts das Fenster „Atlas: abgesicherter Start“ mit „Die letzte Sitzung wurde unerwartet beendet…“ und den Knöpfen „Abgesichert starten“, „Normal starten“, „Details“; die IDE ist währenddessen bedienbar; im Atlas-Feld eine gelbe Zeile „Abgesichert gestartet“ |
| AS4 | Bei AS3 „Details“ | Version, Start, Ladezeit, aktive Funktionen und Fehler der abgestürzten Sitzung, darunter ihr Protokoll ohne Pfade und Namen; „Diagnoselog exportieren…“ öffnet die Vorschau aus #647 |
| AS5 | Bei AS3 „Abgesichert starten“ | Fenster wechselt auf „Atlas läuft abgesichert…“ mit „Normal weiterarbeiten“, „Schnellschalter…“; keine Klammerfarben, Blocklinien, Unterstreichungen; Vervollständigung kommt von der IDE; Tools › Optionen › Atlas zeigt die gespeicherten Werte unverändert |
| AS6 | Bei AS5 „Schnellschalter…“, „Klammerfarben“ anklicken | Klammerfarben erscheinen sofort, der Rest bleibt aus |
| AS7 | Bei AS5 „Normal weiterarbeiten“ | Meldung „Atlas: abgesicherter Start beendet, alle Funktionen wieder an.“; alles wie im normalen Betrieb ohne Neustart, gelbe Zeile weg |
| AS8 | Bei AS3 „Normal starten“ | Wie AS7 |
| AS9 | Zweimal hintereinander (innerhalb von 10 Minuten) wie AS3 abbrechen | Beim dritten Start keine Rückfrage, Fenster „Die IDE ist zweimal kurz hintereinander abgestürzt…“, Atlas läuft abgesichert |
| AS10 | Eine Einstellung ändern (z. B. Blocklinien aus), danach wie AS3 abbrechen, „Abgesichert starten“ | Vorschlag nennt „Blocklinien“ zuerst; Knopf „Einstellungen auf den Stand vor … zurücksetzen“ stellt den alten Wert wieder her und meldet es |
| AS11 | Umschalt beim Start der IDE gedrückt halten, bis die Packages geladen sind | Fenster „Atlas wurde abgesichert gestartet (Taste beim Laden)…“; nur Optionsseite und Atlas-Feld, kein Menü Atlas, keine Palette, keine Vervollständigung von Atlas |
| AS12 | `bds.exe -AtlasSafeMode` bzw. `set ATLAS_SAFE_MODE=1` und IDE starten | Wie AS11 mit „Kommandozeile bzw. ATLAS_SAFE_MODE“ |
| AS13 | Optionen › Abgesicherter Start: Taste „Strg“; Umschalt bzw. Strg beim Start | Umschalt tut nichts, Strg wirkt wie AS11 |
| AS14 | Optionen: Längste Ladezeit 1000, IDE mit großem Projekt neu starten (Laden dauert länger), dann noch einmal neu starten | Beim zweiten Start Rückfrage mit „Der letzte Start von Atlas dauerte länger als 1000 ms.“ |
| AS15 | Optionen: beide Kästchen aus, Taste „keine“; AS3, AS9, AS11 wiederholen | Nie eine Rückfrage, Atlas startet immer normal |
| AS16 | Zwei IDEs gleichzeitig starten, eine normal beenden, die andere offen lassen; dritte IDE starten | Keine Rückfrage: die laufende IDE gilt nicht als Absturz |

## Atlas-Änderungen zurücknehmen (#721)

| Nr. | Schritte | Erwartet |
|---|---|---|
| UR1 | Eine Methode umbenennen, die in drei Units und einem Ereignis-Handler im DFM vorkommt (Vorschau „Umbenennen“) | Alle vier Dateien geändert; Strg+Alt+Z nimmt alles zurück; Meldung „Atlas-Änderung zurückgenommen: Umbenennen: … (4 Dateien)“ |
| UR2 | Nach UR1 in jeder der drei Units Strg+Z bzw. Strg+Umschalt+Z | Jeder Puffer kennt die Rücknahme als einen Schritt; Strg+Umschalt+Z stellt dort den umbenannten Stand wieder her |
| UR3 | Nach UR1 Strg+Alt+Umschalt+Z | Umbenennung wieder in allen Dateien; Meldung „wiederhergestellt“ |
| UR4 | Umbenennen, eine der Units nicht geöffnet, IDE neu starten, *Atlas* › „Atlas-Änderungen…“ | Der Satz steht in der Liste (Sicherung in `%LOCALAPPDATA%\Atlas\undo`); „Zurücknehmen“ im Kontextmenü stellt die geschlossene Unit in ihrer Kodierung wieder her |
| UR5 | Zwei Umbenennungen nacheinander; in einer Datei der ersten eine der umbenannten Zeilen von Hand ändern; die erste in der Liste zurücknehmen | Andere Dateien zurückgenommen, die Datei mit der Handänderung bleibt; Meldungsansicht nennt sie als Konflikt; Satz zeigt „teilweise zurückgenommen“ |
| UR6 | Optionen: Bei Konflikten „nichts zurücknehmen“, UR5 wiederholen | Nichts geändert, Meldung „abgebrochen“ mit Anzahl Konflikte |
| UR7 | In der Liste Doppelklick auf eine Datei bzw. Kontextmenü „Unterschied“ am Satz | Fenster mit `-`/`+`-Zeilen der Datei bzw. aller Dateien mit Überschriften; Esc schließt |
| UR8 | Aktion, deren Workspace-Edit eine Unit anlegt (`create` in `documentChanges`, etwa eine Code-Aktion oder `workspace/applyEdit`), dann Strg+Alt+Z | Unit aus dem Projekt ausgetragen, geschlossen und im Papierkorb; Strg+Alt+Umschalt+Z legt sie wieder an und trägt sie ein |
| UR9 | Optionen: „Atlas-Änderungen über mehrere Dateien zurücknehmen“ aus, umbenennen, Strg+Alt+Z | Umbenennen wie bisher; Meldung „ausgeschaltet“; Liste leer; mit „Sicherung“ aus ist der Ordner `undo` leer |
| UR10 | Optionen › Tastenkonflikte: Tasten für Zurücknehmen und Wiederherstellen ändern | Neue Tasten wirken sofort, die alten nicht mehr |
| UR11 | Umbenennen nur in einer Datei, Strg+Alt+Z | Kein Satz (eine Datei nimmt Strg+Z zurück); Meldung „nichts zurückzunehmen“ |

## Installation und Updates (#495)

| Nr. | Schritte | Erwartet |
|---|---|---|
| IN1 | Delphi 12 installiert, `atlas-ide-expert-<Version>.zip` mit `Win32\Atlas.IDE.Expert290.bpl` entpacken, `AtlasSetup.exe` starten | Liste zeigt „Delphi 12 Athens (Win32)“ angehakt, ältere Versionen ausgegraut mit „nicht unterstützt“; kein UAC-Dialog |
| IN2 | Nach IN1 „Installieren“, Delphi 12 starten | Protokoll: kopierte Dateien, „Registriert in Delphi 12 Athens (Win32)“, Eintrag in „Apps und Features“; Atlas ist in der IDE aktiv und findet den Server unter `%LOCALAPPDATA%\Programs\Atlas` |
| IN3 | Delphi 13 offen lassen, installieren | Rückfrage „Bitte zuerst diese IDE schließen“ mit Wiederholen und Abbrechen; nach dem Schließen läuft die Installation durch |
| IN4 | 64-Bit-IDE (Delphi 12.3 oder 13) vorhanden, installieren | Eigene Zeile „(Win64)“; BPL aus `Win64\` unter `Known Packages x64`; die 64-Bit-IDE lädt Atlas |
| IN5 | Alte Hand-Installation (BPL aus dem Repo unter „Known Packages“, auch unter dem Namen Argus) vorhanden, installieren | Genau ein Atlas-Eintrag unter „Known Packages“, der auf den Programmordner zeigt |
| IN6 | Einstellungen und Favoriten ändern, Installer einer neueren Version ausführen („Aktualisieren“) | Einstellungen, Favoriten, Snippets und `.atlas`-Dateien unverändert; der Index wird nur bei geändertem Format neu aufgebaut |
| IN7 | „Apps und Features“ › Atlas IDE Expert › Deinstallieren, kein Kästchen | Unter `HKCU\Software\Embarcadero\BDS\*\Known Packages` (und `x64`) kein Atlas-Eintrag; Programmordner weg; `HKCU\Software\Atlas\IdePlugin`, `%APPDATA%\Atlas`, `%LOCALAPPDATA%\Atlas` bleiben |
| IN8 | Deinstallieren mit allen drei Kästchen | Zusätzlich `HKCU\Software\Atlas`, `%APPDATA%\Atlas` (mit Snippets) und `%LOCALAPPDATA%\Atlas` entfernt |
| UP1 | Erster Start nach der Installation, IDE ruhig lassen | Nach einigen Sekunden unten rechts das Fenster „Atlas: Updates“; bis zur Antwort keine Netzwerkverbindung (z. B. im Ressourcenmonitor) |
| UP2 | In UP1 „Nein“, IDE neu starten | Keine Frage mehr, keine Abfrage; Optionen: „Einmal täglich nach neuen Versionen sehen“ aus |
| UP3 | In UP1 „Ja, prüfen“ bei einer veralteten Version | Kästchen in den Optionen an; Meldungsansicht „Atlas X ist verfügbar (installiert: Y). Änderungen: <Link>“; die Abfrage enthält nur `atlas=` und `ide=` |
| UP4 | Nach UP3 IDE am selben Tag neu starten | Keine erneute Abfrage (`%LOCALAPPDATA%\Atlas\updates.json`, `lastCheck`) |
| UP5 | Optionen: „Einmal täglich nach neuen Versionen sehen“ aus, IDE neu starten | Kein Fenster, keine Abfrage, keine Meldung; Atlas verhält sich wie ohne die Funktion |
| UP6 | Optionen › Abschnitt „Updates“; Diagnoseexport erstellen | Abschnitt zeigt „Installiert: Atlas <Version> (IDE <Version>)“; ZIP enthält `atlas-info.txt` mit Atlas-, IDE-Version und Plattform |

## Fehlerbericht (#108)

| Nr. | Schritte | Erwartet |
|---|---|---|
| BR1 | Projekt offen, *Atlas › Fehlerbericht erstellen…* | Vorschau mit Abschnitten Plugin, Version, Wirksame Konfiguration, Letzte Anfragen, Protokoll; nach OK und Speicherort `.md`-Datei mit genau diesem Text, Meldungsansicht nennt Datei und Issue-Link |
| BR2 | Bericht mit Anonymisierung (Vorgabe) | Kein Projektpfad, kein Benutzername; stattdessen `<ws>`, `<pfad>`, `<benutzer>`; Zeichenketten im Protokoll als `<wert>` |
| BR3 | Optionen › Abschnitt „Fehlerbericht“: „Fehlerbericht anonymisieren …“ aus, erneut erstellen | Pfade erscheinen im Klartext |
| BR4 | Datei mit Text öffnen und ändern, Bericht erstellen | Kein Quelltext der Datei im Bericht; Tabelle „Letzte Anfragen“ nennt nur Methoden wie `textDocument/didChange` mit Dauer |
| BR5 | Server über das Statusfeld stoppen, Bericht erstellen | Plugin-Teil vollständig, Abschnitt „Server“ meldet, dass der Server nicht lief |
| BR6 | Befehlspalette „Atlas: Fehlerbericht erstellen“; Fenster des abgesicherten Starts › „Fehlerbericht…“ | Derselbe Ablauf wie BR1 |
| BR7 | Auf GitHub „New issue“ | Auswahl „Fehler“, „Fehlalarm einer Regel“, „Funktionswunsch“; leeres Issue nicht möglich |
| BR8 | „Fehlalarm einer Regel“ ohne Regel-ID absenden | GitHub verlangt Regel-ID, Konfidenz, Codeausschnitt und Erwartung |

## Schließen der Atlas-Fenster (#414)

| Nr. | Schritte | Erwartet |
|---|---|---|
| SL1 | Popup und Parameter-Hint offen (z. B. `Foo(` und Strg+Leer), Esc | Erst schließt das Popup, beim zweiten Esc der Hint |
| SL2 | Popup mit Esc schließen, im selben Wort weitertippen (auch mit automatischer Vervollständigung der IDE) | Popup bleibt zu; Strg+Leer öffnet es wieder; im nächsten Wort (nach `.`) öffnet es wieder automatisch |
| SL3 | Popup offen, mit dem Mausrad scrollen | Popup schließt |
| SL4 | Parameter-Hint offen, ein paar Zeilen scrollen | Hint wandert mit der Zeile; scrollt die Zeile aus dem Bild, schließt er |
| SL5 | Popup, Hint bzw. Tooltip offen, Editor in der Größe ändern (Fenster, Splitter, angedockte Fenster) | Fenster schließt |
| SL6 | Popup, Hint oder Tooltip offen, anderen Editor-Tab wählen | Fenster schließt |
| SL7 | Tooltip offen, in den Objektinspektor oder die Projektverwaltung klicken | Tooltip schließt (angeheftet bleibt er, bis Esc oder Klick in den Editor) |
| SL8 | Popup, Hint oder Tooltip offen, Alt+Tab in ein anderes Programm | Kein Atlas-Fenster mehr sichtbar |
| SL9 | Maus vom Bezeichner wegbewegen (nicht in den Tooltip) | Tooltip schließt nach etwa 300 ms; in den Tooltip hinein bleibt er |
| SL10 | Popup offen, Cursor mit ← vor den Wortanfang, mit ↑ in eine andere Zeile, oder ein Leerzeichen tippen | Popup schließt jeweils (`(`, `;`, `.` bei klarem Treffer übernehmen stattdessen) |
| SL11 | Parameter-Hint offen, `)` tippen oder hinter die Klammer klicken | Hint schließt |
| SL12 | Popup bzw. Hint offen, in den Objektinspektor oder die Projektverwaltung klicken | Fenster schließt |
| SL13 | Tooltip (nicht angeheftet) offen, Esc | Tooltip schließt, Esc erreicht den Editor nicht |
| SL14 | Mehrzeiliger Aufruf `Foo(` in Zeile 1, Argumente bis Zeile 5, Hint offen; so scrollen, dass Zeile 1 aus dem Bild ist, der Caret aber nicht | Hint schließt (er hängt an der Klammerzeile); solange diese sichtbar ist, wandert er mit |

Automatisch geprüft: `Atlas.Core.Editor.CloseRules.Tests` (jede Zeile der Tabelle für Popup, Hint und Tooltip) und `EscapeBlocksAutomaticReopenInSameWord` in `Atlas.Core.Completion.Controller.Tests`.

## Extern geänderte Dateien (#536)

| Nr. | Schritte | Erwartet |
|---|---|---|
| X1 | Mehrere Units öffnen (gespeichert), im Terminal `git checkout` eines Branches, der sie ändert; zurück in die IDE | Kein Dialog „time/date changed. Reload?“; Editor zeigt den neuen Stand; Meldungsfenster, Gruppe „Atlas“: „Atlas: n Dateien neu geladen“ mit den Dateinamen |
| X2 | Nach X1 im Editor | Cursor und sichtbarer Bereich wie vorher (gleiche Zeile) |
| X3 | Eine Unit mit ungespeicherten Änderungen, Datei extern ändern, zurück in die IDE | Atlas fasst den Puffer nicht an; im Meldungsfenster „… hat ungespeicherte Änderungen; die IDE fragt nach“ und „Atlas: Unterschied in … (- Editor, + Platte)“ mit den geänderten Zeilen; danach die Rückfrage der IDE (mit „Alle Ja/Alle Nein“) |
| X4 | Offene Unit extern löschen | Meldung „… existiert nicht mehr“, Tab bleibt offen |
| X5 | Unit in der IDE speichern | Kein Neuladen, Rückgängig bleibt erhalten |
| X6 | Optionen › Atlas › „Außerhalb geänderte Dateien … neu laden“ aus, X1 wiederholen | Wieder die Rückfragen der IDE |
| X7 | Formular-Unit extern ändern (`.pas` und `.dfm`, z. B. per `git checkout`) | Unit und Formular neu geladen |

Protokoll: jede erkannte Änderung als Zeile „Extern geändert: … (neu laden | ungespeicherte Änderungen, behalten | gelöscht)“.

## Einfrier-Wächter (#501)

Protokoll: `Atlas.IDE.Expert370.log` neben dem Plugin (Hänger stehen dort immer, auch ohne `Diagnose`).

| Nr. | Schritte | Erwartet |
|---|---|---|
| W1 | Diagnosemodus an (*Optionen › Atlas › Allgemein*), dann Tools › Optionen › Atlas › Robustheit › „Wächter testen (1 s)“ | IDE steht 1 s; danach im Protokoll „Hänger ~1000 ms um …; Atlas: Wächter-Test, … ms; Fenster: Optionen“, darunter Zeilen `Modul+Offset` (u. a. `Atlas.IDE.Expert370.bpl`, `kernel*.dll`) und „Sitzung: 1 Hänger …“ |
| W2 | Normal arbeiten ohne Hänger | Keine Hänger-Zeilen im Protokoll |
| W3 | Schwelle auf 2000 setzen, W1 wiederholen | Kein Eintrag (1 s liegt unter der Schwelle) |
| W4 | Schwelle 500, „Hinweis im Meldungsfenster …“ an; einen Hänger über 2 s erzeugen (z. B. großes Projekt öffnen) | Zeile „Atlas: Die IDE hat n ms nicht reagiert“ in der Gruppe „Atlas“ des Meldungsfensters, kein Dialog |
| W5 | Mit `Diagnose` = 1 IDE starten | Zeile „Start: Laden des Packages bis zur freien Nachrichtenschleife n ms“ |
| W6 | IDE schließen | Schließt ohne Verzögerung; bei Hängern in der Sitzung steht am Ende „Sitzung: n Hänger, längster …“ |
| W7 | Diagnosemodus aus; Reiter *Robustheit* ansehen und in der Befehlspalette „Wächter“ suchen | Kein Knopf „Wächter testen“, kein Palettenbefehl; nach dem Einschalten des Diagnosemodus erscheint der Knopf sofort, der Befehl beim nächsten Öffnen der Palette (Code-Review S-07) |

## Include-Dateien (#500)

Vorbereitung: `Tests\Referenzprojekt\RefGruppe.groupproj` öffnen; `Ref.Daten.Auftraege.pas` bindet `Ref.Daten.Auftraege.inc` (Typen) und `Ref.Daten.Auftraege.Rumpf.inc` (Rümpfe) ein.

| Nr. | Schritte | Erwartet |
|---|---|---|
| I1 | In `Ref.Daten.Verwendung.pas` Strg+Klick auf `TAuftrag` | Öffnet `Ref.Daten.Auftraege.inc` an der Deklaration |
| I2 | Maus über `TAuftrag` bzw. `Mehrwertsteuer` | Tooltip mit Deklaration, Beschreibung aus der `.inc` und „Ref.Daten.Auftraege (Ref.Daten.Auftraege.inc)“; bei `Mehrwertsteuer` „= 19“ |
| I3 | In `NeuerAuftrag` `Result.` tippen | `Nummer`, `Betrag`, `Brutto` in der Liste; Detailpanel zeigt die Deklaration aus der `.inc` |
| I4 | Neue Zeile `var X: TAuf` im interface-Teil, Strg+Leer | `TAuftrag` wird angeboten |
| I5 | In der `.inc` eine Eigenschaft `property Kunde: string read FKunde;` ergänzen, speichern, in `Verwendung` `Result.` tippen | `Kunde` erscheint ohne Neustart |
| I6 | In der `.inc` `{$I Ref.Daten.Auftraege.inc}` einfügen (Zyklus), speichern | Warnung an der Direktive, die IDE hängt nicht; danach wieder entfernen |

## Erwarteter Typ (#417)

Vorbereitung: in einer Methode `var I: Integer; S: string; Obj: TPersistent;` und ein Memo `memLog`.

| Nr. | Schritte | Erwartet |
|---|---|---|
| T1 | `I := memLog.Lines.` | Oben Überschrift „Passt zu Integer“ mit `Count`, `Add`, `IndexOf` …, darunter „Weitere“; Fußzeile „n passend · m gesamt“ |
| T2 | In T1 `Cle` weitertippen | Nur „Weitere“ mit `Clear` (passt nicht zu Integer) |
| T3 | `S := memLog.` | „Passt zu string“ mit `Text`, `Name` … |
| T4 | `Obj := memLog.` | Unter „Passt zu TPersistent“ u. a. `Lines`, `Font` (Nachfahren) |
| T5 | `ShowMessage(memLog.` | „Passt zu string“ (Parametertyp) |
| T6 | In einer Funktion mit Ergebnis Integer: `Result := memLog.Lines.` | Wie T1 |
| T7 | `memLog.` als eigene Anweisung | Keine Überschriften, Fußzeile „n von m“ – wie bisher |
| T8 | IDE auf Englisch | „Matches Integer“, „Other“, „n matching · m total“ |

## Ereignis-Zuweisung (#444)

Vorbereitung: Formular mit Button `btnSave` und den Methoden `FormCreate(Sender: TObject)` und `FormCloseQuery(Sender: TObject; var CanClose: Boolean)`.

| Nr. | Schritte | Erwartet |
|---|---|---|
| V1 | In `FormCreate` `btnSave.OnClick := ` tippen, Strg+Leer | Überschrift „Passt zu TNotifyEvent“, darunter nur Methoden mit `(Sender: TObject)` (also `FormCreate`, nicht `FormCloseQuery`); zuletzt „Neue Methode btnSaveClick …“ in Akzentfarbe |
| V2 | Vorhandene Methode übernehmen | `btnSave.OnClick := FormCreate` – ohne Klammern |
| V3 | „Neue Methode btnSaveClick …“ übernehmen | Zuweisung `btnSave.OnClick := btnSaveClick`; im `private`-Abschnitt `procedure btnSaveClick(Sender: TObject);`; hinter der aktuellen Methode ein leerer Rumpf `procedure TForm1.btnSaveClick(Sender: TObject); begin end;`; ein Rückgängig nimmt alles zurück |
| V4 | V3 wiederholen (Name ist jetzt vergeben) | Vorschlag „Neue Methode btnSaveClick2 …“ |
| V5 | `btnSave.OnClick := Fo` | Gefiltert auf `FormCreate`; „Neue Methode …“ bleibt sichtbar |
| V6 | `X := ` mit einer Integer-Variablen | Normale Vervollständigung, keine Überschrift |

## Monitor und Zoom (#412, #445)

| Nr. | Schritte | Erwartet |
|---|---|---|
| Z1 | Editor mit Strg+Mausrad vergrößern (z. B. 150 %), Popup öffnen | Schrift, Zeilenhöhe, Badges und Abstände wachsen mit; das Popup beginnt genau am Wortanfang |
| Z2 | Editor wieder auf 100 % | Normale Größe |
| Z3 | Mit zwei Monitoren unterschiedlicher Skalierung: IDE auf den anderen Monitor ziehen, Popup öffnen | Scharf und in passender Größe |
| Z4 | Im Diagnoseprotokoll nach Z1 | Zeile „Darstellung: … Zoom 1,50“ (Wert ungefähr) |

## Projekt-Einstellungen (#227)

| Nr. | Schritte | Erwartet |
|---|---|---|
| PE1 | Projekt öffnen, *Atlas > Projekt-Einstellungen (atlas.json)…* | Dialog mit Seiten links (Allgemein, Projekt, Prüfregeln …); Menü „Atlas“ steht hinter „Tools“ |
| PE2 | Ohne `atlas.json`: Seite Protokoll, `logLevel` auf `debug`, OK | `atlas.json` entsteht neben der .dproj mit `"logLevel": "debug"` |
| PE3 | `atlas.json` mit Kommentaren und unbekanntem Schlüssel; `format.indentSize` auf 4 setzen | Nur der Wert kommt dazu bzw. ändert sich; Kommentare, Reihenfolge, unbekannter Schlüssel bleiben |
| PE4 | Bei einem gesetzten Wert „Zurücksetzen“, OK | Schlüssel samt Komma entfernt; Zustand zeigt „Standard: …“ |
| PE5 | `rules` mit Einträgen | Tabelle mit allen Regeln; ohne Änderung bleibt `rules` unverändert |
| PE6 | Zahlenfeld mit „abc“, OK | Hinweis „keine ganze Zahl“, Dialog bleibt offen |
| PE7 | „atlas.json öffnen“ | Dialog schließt, Datei öffnet sich im Editor |
| PE8 | Befehlspalette: „Atlas: Atlas-Einstellungen des Projekts“ | Öffnet denselben Dialog |
| PE9 | Menü *Atlas* öffnen | Häkchen bei den fünf Schaltern entsprechen Tools > Optionen > Atlas |
| PE10 | *Atlas > Klammerpaare färben* abschalten, Menü erneut öffnen | Häkchen weg, Paare ungefärbt; in Tools > Optionen > Atlas ebenfalls aus |
| PE11 | *Atlas > Optionen…* | Tools > Optionen öffnet direkt auf der Seite Atlas |
| PE12 | *Atlas > Globale Einstellungen…*, `logLevel` auf `debug`, OK | `%APPDATA%\Atlas\settings.json` entsteht mit `"logLevel": "debug"`; Titel nennt „global“ |
| PE13 | Danach Projekt-Einstellungen, Seite Protokoll | Zustand „global: debug“; Wert im Projekt ändern, dann „Auf global zurücksetzen“ entfernt den Schlüssel aus atlas.json |
| PE14 | Feld `delphiVersion` | Auswahlliste der installierten Versionen („Delphi 13 (37.0)“); `config` und `platform` aus der .dproj |
| PE15 | Seite Prüfregeln, eine Regel auf „error“, OK | Nur `"<Regel>": "error"` kommt in `rules`; bei einer Regel mit Optionen bleibt das Objekt, nur `severity` ändert sich |
| PE16 | Unbekannte Regel in atlas.json eintragen, Dialog öffnen | Regel steht in der Tabelle; OK zeigt die Warnung des Servers und fragt nach |
| PE17 | Server beenden, Dialog öffnen, ungültiges JSON in einem Objektfeld | Feld rot; Hinweis „nur Syntax geprüft“; OK verhindert Speichern |
| PE18 | atlas.json in ANSI mit LF speichern, einen Wert ändern | Datei bleibt ANSI mit LF |
| PE19 | *Tools > Optionen > Atlas > Server* | Baseline-Anzahl; „Aktualisieren“ schreibt `atlas-baseline.json`; „Löschen“ fragt und löscht |
| PE20 | Dort „Auswerten“ | Je Regel Anzahl, ungenutzte und Dateien der Unterdrückungen |
| PE21 | Dort „Index-Cache löschen“ | Rückfrage, danach Meldung; der Server baut den Index neu |
| PE22 | Hauptseite: Verzögerung 1000 ms, `List.` tippen und warten | Liste öffnet nach etwa 1 s; `List.` und sofort Leerzeichen: keine Liste |
| PE23 | „Commit-Zeichen“, „uses ergänzen“, „Parameter-Hints“ je aus | `;` übernimmt nicht; keine uses-Ergänzung; kein Hint bei `(` |
| PE24 | „Listenbreite automatisch“ an | Liste passt sich der Breite der Einträge an |

## Willkommensseite (#753)

| Nr. | Schritte | Erwartet |
|---|---|---|
| WP1 | RAD Studio 13 (und 12) mit Atlas starten, Willkommensseite ansehen | Bereich „Atlas“ mit Symbol, „Guten Morgen/Tag/Abend, <Vorname>“, „Atlas <Version> · Server startet mit dem ersten Projekt“; die Willkommensseite startet keinen Server |
| WP2 | Projekt öffnen, Index aufbauen lassen, zur Willkommensseite wechseln | Kurzstatus „Server läuft · Index wird aufgebaut (n %)“, danach „Server läuft · 1.284 Units im Index“; ändert sich mit dem Statusfeld |
| WP3 | Atlas-Bereiche der Willkommensseite (Kopf) über *Layout bearbeiten* verschieben, ausblenden, wieder einblenden | verhalten sich wie eingebaute Bereiche; Titel im Rahmen der IDE |
| WP4 | *Atlas › Atlas-Layout anwenden*; IDE neu starten | Meldung „Atlas-Layout angewendet …“; `%LOCALAPPDATA%\Atlas\welcomepage-layout-backup.json` existiert; „Atlas“ steht oben über alle Spalten (zwei Zeilen), die übrigen Bereiche darunter in alter Anordnung; einzelne Atlas-Bereiche fehlen |
| WP5 | Nach WP4: Wird das Layout sofort übernommen oder erst nach dem Neustart? | Ergebnis notieren (ADR 0011); nach dem Neustart gilt es in jedem Fall, die Datei `welcomepage-layout-pending` ist danach weg |
| WP6 | „Atlas“ nach WP4 von Hand nach unten verschieben, IDE neu starten | bleibt, wo es ist |
| WP7 | *Atlas › Atlas-Layout zurücksetzen*; IDE neu starten | Meldung „Das vorige Layout … wiederhergestellt“; Registry `…\BDS\<Version>\WelcomePage` wie vor WP4 (Export vergleichen), Sicherung gelöscht |
| WP8 | Zurücksetzen ohne Sicherung | „Keine Sicherung des Layouts gefunden …“, nichts ändert sich |
| WP9 | *Tools › Optionen › Atlas › Willkommensseite*: „Atlas-Layout verwenden“ an bzw. aus | wie WP4 bzw. WP7, ohne Meldung |
| WP10 | Optionen: „Anzeigen in“ = Fenster „Atlas-Start“ | Willkommensseite ohne Atlas-Bereiche, Fenster „Atlas-Start“ öffnet sich (eine Spalte, andockbar); *Ansicht › Atlas-Start* öffnet es wieder |
| WP11 | Optionen: Kopf aus, dann Grußzeile aus | Kopf verschwindet; ohne Grußzeile steht „Atlas“ statt des Grußes |
| WP12 | Schnellschalter „Atlas auf der Willkommensseite“ aus | alle Atlas-Bereiche und „Atlas-Start“ weg, Menüeinträge ausgeblendet |
| WP13 | IDE-Stil hell/dunkel wechseln | Atlas-Bereiche und „Atlas-Start“ folgen dem Thema, Symbol in passender Variante |
| WP14 | IDE ohne Schnittstelle der Willkommensseite (`WelcomePagePluginService` = nil), z. B. Willkommensseite abgeschaltet | „Atlas-Start“ ersetzt die Willkommensseite |

### Suchfeld (#760)

| Nr. | Schritte | Erwartet |
|---|---|---|
| WS1 | Willkommensseite ohne geöffnetes Projekt, Strg+E, „wel“ tippen | Fokus im Suchfeld rechts im Kopf; Liste darunter mit Gruppen: Dateien mit `…WelcomePage.pas` (sofern ein Projekt mit dieser Unit schon einmal indiziert wurde), Symbole mit „Symbole nach dem Öffnen eines Projekts“, Befehle mit „Atlas-Layout anwenden“; je Gruppe höchstens 4, darunter „n weitere“ |
| WS2 | „Wlecome“ tippen | dieselbe Datei wie WS1 (Tippfehler-Toleranz) |
| WS3 | Pfeiltasten, Enter auf eine Datei eines nicht geöffneten Projekts | Projekt öffnet sich, danach die Datei; Suchfeld leer, Liste weg |
| WS4 | Projekt öffnen, Server läuft, zurück zur Willkommensseite, Klassennamen suchen | Gruppe „Symbole“ zeigt Treffer; Enter springt an die Deklaration |
| WS5 | Ohne laufenden Server suchen | Gruppe „Symbole“ nur mit Hinweis; im Statusfeld startet kein Server |
| WS6 | Projekt aus *Datei › Wieder öffnen* suchen und mit Enter öffnen | Gruppe „Projekte“ zeigt es (Name, Ordner); Enter öffnet es. Wenn die Gruppe leer bleibt: Export von `HKCU\Software\Embarcadero\BDS\<Version>\Closed Projects` an Marco/Claude (Format angenommen) |
| WS7 | Esc im Suchfeld; Klick in die IDE daneben | Esc leert das Feld und schließt die Liste; Klick daneben schließt die Liste |
| WS8 | Editor aktiv, Strg+E | inkrementelle Suche der IDE wie bisher (Atlas greift nur auf der Willkommensseite) |
| WS9 | Optionen: Taste des Suchfelds auf Strg+Umschalt+F; dann „Gruppe Symbole“ aus; dann „Suchfeld zeigen“ aus | neue Taste wirkt; Gruppe „Symbole“ fehlt ganz; Suchfeld verschwindet, die Taste tut auf der Willkommensseite nichts |
| WS10 | Fenster „Atlas-Start“ (WP10) | Suchfeld oben im Kopf, verhält sich wie auf der Willkommensseite |

### Neu in Atlas (#756)

Vorbereitung: Paket mit `whatsnew.json` (Release oder `pwsh Tools/Update-WhatsNew.ps1 -Unreleased 1.1.0 -OutFile <BPL-Ordner>\..\whatsnew.json`, dazu `Setup\Beispiele` als `Beispiele` daneben). Die gesehene Version steht in `HKCU\Software\Atlas\IdePlugin`, Wert `WhatsNewSeen`.

| Nr. | Schritte | Erwartet |
|---|---|---|
| NA1 | Erste Installation (`WhatsNewSeen` fehlt), IDE starten | keine Karte; danach steht `WhatsNewSeen` auf der Plugin-Version |
| NA2 | `WhatsNewSeen` = 1.0.0, Plugin 1.1.0, IDE starten | Karte „Neu in Atlas 1.1.0“ oben in der ersten Spalte (Atlas-Layout, „Atlas-Start“) bzw. als eigener Bereich; Zeilen mit Titel, Satz, Tastenkürzel (Suchfeld: tatsächliche Belegung aus WS9), Schalter, „Ausprobieren“ |
| NA3 | Schalter „Suchfeld“ aus; *Tools › Optionen › Atlas › Willkommensseite* öffnen | Suchfeld verschwindet sofort; „Suchfeld zeigen“ ist aus; wieder an: Suchfeld zurück |
| NA4 | „Ausprobieren“ beim Suchfeld; bei „Postfix-Vorlagen“ | Fenster „Atlas-Start“ öffnet sich; `Beispiele\Postfix.pas` öffnet sich mit dem Cursor in Zeile 23 |
| NA5 | „Gelesen“, IDE neu starten | Karte weg, auch nach dem Neustart; `WhatsNewSeen` = 1.1.0 |
| NA6 | `WhatsNewSeen` = 1.0.0, Plugin 1.2.0 mit Einträgen für 1.1.0 und 1.2.0 | Karte „Neu in Atlas“ mit Überschriften „Version 1.2.0“ und „Version 1.1.0“, je mit ihren Zeilen |
| NA7 | Rechtsklick in die Atlas-Bereiche bzw. den Kopf: „Alle Versionen“; Überschrift einer älteren Version anklicken | Karte mit allen Versionen, nur die neueste aufgeklappt; Klick klappt auf und zu; „Schließen“ blendet sie aus |
| NA8 | Rechtsklick: „Neuigkeiten dieser Version zeigen“; Befehlspalette „Neu in Atlas: alle Versionen“ | Karte der aktuellen Version bzw. aller Versionen; mit Host „Atlas-Start“ öffnet sich das Fenster |
| NA9 | Optionen: Karte „Neu in Atlas“ = nie; dann = immer | keine Karte, kein Eintrag im Kontextmenü; mit „immer“ bleibt die Karte der aktuellen Version auch nach „Gelesen“ und Neustart stehen |
| NA10 | `whatsnew.json` löschen, „Alle Versionen“ wählen | Meldung „Neu in Atlas: keine Neuigkeiten gefunden …“, keine Karte |

### Projekte mit Zustand (#592)

Abweichungen vom Issue (begründet in ADR 0011): Bereich als Inhalts-Frame statt `INTAWelcomePageDataPluginListView`, Ersatzfenster „Atlas-Start“ statt „Projektzustand“, Einstellungen auf der Seite *Willkommensseite* statt *Allgemein*. Neue Regeltreffer zählt Atlas aus den Problemen, die das Plugin vom Server hat (Baseline schon abgezogen), also nur in geprüften Dateien.

Vorbereitung: zwei Projekte in Git (eins auf `main`, eins auf einem Feature-Branch mit ungespeicherten Änderungen), ein Projekt ohne Versionsverwaltung, eine Projektgruppe. Je Projekt einmal öffnen und wieder schließen. Die Zusammenfassungen stehen in `%LOCALAPPDATA%\Atlas\projects\*.json`.

| Nr. | Schritte | Erwartet |
|---|---|---|
| PZ1 | Willkommensseite (bzw. Fenster „Atlas-Start“) öffnen | Bereich „Projekte“ mit den zuletzt geschlossenen Projekten der IDE, höchstens 8; je Zeile Name, gekürzter Pfad, Branch bzw. SVN-Pfad und Marken |
| PZ2 | Projekt auf `main` fehlerfrei bauen (Strg+F9), schließen | grüne Marke „Build 0/0/0“, Branch `main`, keine Marke „geändert“ |
| PZ3 | Im Feature-Projekt zwei Fehler einbauen, bauen, schließen; auf der Willkommensseite die rote Marke „2 Fehler“ anklicken | Zeile zeigt rote Marke „2 Fehler“; Klick öffnet das Projekt und die Unit mit dem Cursor an der ersten Fehlerstelle |
| PZ4 | Projektverlauf aus (`welcomePage.trends`, #758); Klick auf die Zeile (nicht auf eine Marke) | Projekt öffnet sich; solange es offen ist, steht es nicht in der Liste (die IDE führt es dann nicht unter „Closed Projects“). Mit Projektverlauf an wählt der Klick die Zeile, siehe PV2 |
| PZ5 | Feature-Projekt: Datei ändern und speichern (ohne Commit), Projekt schließen; Branch mit Upstream und einem lokalen Commit | gelbe Marke „n geändert“; neutrale Marke „↑1 ↓0“ |
| PZ6 | Projekt ohne Versionsverwaltung | kein Branch, keine Marken „geändert“/„↑↓“, keine Fehlermeldung |
| PZ7 | Prüfung beim Speichern an (#548), im geschlossenen Zustand zuletzt einen Syntaxfehler gespeichert | Marke „Prüfung: 1 Fehler“, nur wenn die Prüfung neuer als der letzte Build ist; Klick springt zur Stelle |
| PZ8 | Maus über eine Zeile halten | Tooltip mit letztem Build (Zeit, Art, Konfiguration, Plattform, Zahlen), erster Meldung, Hintergrundprüfung, Branch/Revision, Änderungen und Hinweis zum Klick |
| PZ9 | Netzlaufwerk trennen bzw. git aus dem PATH nehmen, Willkommensseite öffnen | Seite erscheint sofort; Branch und Marken aus der gespeicherten Zusammenfassung mit „Stand vom …“; kurz „wird abgefragt …“ |
| PZ10 | Acht Projekte in der Liste, IDE neu starten | Willkommensseite ohne spürbare Verzögerung (< 200 ms für den Bereich); kein Server-Start; Branch-Abfrage läuft im Hintergrund |
| PZ11 | Rechtsklick auf eine Zeile: „Ordner öffnen“; dann „Aus Liste entfernen“ | Explorer mit markierter Projektdatei; Zeile verschwindet und bleibt nach Neustart weg, bis das Projekt wieder geöffnet wird |
| PZ12 | Projektgruppe bauen (Alle erzeugen), Gruppe schließen | Gruppe in der Liste mit dem Ergebnis des letzten Builds |
| PZ13 | *Tools › Optionen › Atlas › Willkommensseite*: „Bereich ‚Projekte‘ …“ aus; Anzahl auf 3; „Branch und Änderungen … frisch abfragen“ aus | Bereich verschwindet bzw. zeigt drei Projekte; ohne frische Abfrage nur der gespeicherte Stand („Stand vom …“); 99 eingegeben wird als 30 gespeichert |
| PZ14 | Dunkles und helles IDE-Thema, 150 % Skalierung | Text, Marken und Tooltip gut lesbar; Marken nicht abgeschnitten |
| PZ15 | Delphi 12 bzw. Host „Atlas-Start“ | Bereich erscheint im Fenster „Atlas-Start“ mit demselben Inhalt |
| PZ16 | Neu in Atlas: Schalter „Projekte mit Zustand“ aus und wieder an | Bereich verschwindet sofort und kommt zurück; Optionsseite zeigt denselben Wert |
| PZ17 | Probleme an (#398), Baseline mit bekannten Treffern; im Projekt zwei neue `with`-Anweisungen einbauen, speichern, warten bis die Probleme da sind, Projekt schließen | gelbe Marke „2 neue Treffer“; Tooltip „2 neue Regeltreffer gegenüber der Baseline (geprüfte Dateien)“; Treffer aus der Baseline zählen nicht. Mit ausgeschalteten Problemen bleibt der alte Stand |
| PZ18 | Eine Git-Arbeitskopie mit zwei Projekten in Unterordnern; nur im ersten eine Datei ändern, beide schließen | „1 geändert“ nur beim ersten Projekt, das zweite ohne Marke |
| PZ19 | git so umbenennen, dass der Aufruf hängt bzw. fehlt; Willkommensseite öffnen, 10 s warten, Bereich neu zeichnen lassen (Fenster wechseln) | „wird abgefragt …“ verschwindet spätestens nach 5 s; danach gespeicherter Stand mit „Stand vom …“ |

### Projektverlauf (#758)

Abweichungen vom Issue: Ein Klick auf eine Zeile in „Projekte“ wählt sie bei eingeschaltetem Projektverlauf (wie im Mockup); geöffnet wird dann mit Doppelklick oder Kontextmenü „Öffnen“ (bei ausgeschaltetem Verlauf öffnet der Klick wie in #592). Die Auswahl gilt für die Sitzung. Messpunkte entstehen nur nach Builds des Benutzers, nicht nach der Hintergrundprüfung; bei einer Projektgruppe auch für die Gruppe (dort ohne Metriken und TODOs, die gibt es nur je Projekt). Branch und Commit des Punkts stammen aus der Abfrage nach dem Build (`welcomePage.refreshVcs`), sonst aus dem zuletzt bekannten Stand.

Vorbereitung: Git-Projekt mit Baseline (#97), Probleme an (#398), Server läuft; zweites Projekt ohne Baseline. Die Zusammenfassungen stehen in `%LOCALAPPDATA%\Atlas\projects\*.json`, Abschnitt `trends`.

| Nr. | Schritte | Erwartet |
|---|---|---|
| PV1 | Willkommensseite bzw. „Atlas-Start“ öffnen, noch kein Build mit dieser Version | Bereich „Projektverlauf“ unter „Projekte“, Kopf „<Name> · letzte 30 Builds“ und „<Name>: noch keine Builds aufgezeichnet …“; ohne Projekt in der Liste „Noch kein Projekt …“ |
| PV2 | Klick auf die zweite Zeile in „Projekte“; Doppelklick auf eine Zeile; Rechtsklick › „Öffnen“; Klick auf eine rote Marke | Erster Klick: Zeile links markiert, Kopf und Kacheln wechseln auf dieses Projekt, nichts öffnet sich. Doppelklick und „Öffnen“ öffnen das Projekt; die rote Marke springt wie in PZ3 |
| PV3 | Im Projekt fünfmal bauen (Strg+F9) mit 12, 9, 6, 3 und 0 Hinweisen | Kachel „Warnungen + Hinweise“: „0“, daneben „vorher 3“, fallende Linie mit Fläche, letzter Punkt hervorgehoben, Nulllinie gestrichelt sichtbar |
| PV4 | Auf einen Punkt der Linie klicken (nach PV8, also 30 gezeigte Punkte) | Darunter „Build i von 30 · Nr. n · <Datum Uhrzeit> · <Branch> · <Commit, 7 Zeichen> · Warnungen + Hinweise: <Wert>“ (i = Position in der Linie, n = laufende Nummer des Builds, nur wenn sie von i abweicht; bei zu schmaler Spalte ohne „Nr. n“), der Punkt hat einen Ring; Klick auf einen Punkt einer anderen Kachel zeigt deren Wert |
| PV5 | Kacheln „Offene TODOs“, „Build-Dauer“ und „Mittl. Methodenlänge“ nach PV3 ansehen | Werte erscheinen wenige Sekunden nach dem Build (Hintergrundlauf); Build-Dauer in s mit einer Nachkommastelle, Methodenlänge in Zeilen |
| PV6 | Zweites Projekt ohne Baseline bauen und wählen | Kachel „Regeltreffer seit Baseline“: „kein Wert“, Linie mit Lücke statt 0; im JSON fehlt `ruleHits` in diesem Punkt |
| PV7 | Mit Baseline: zwei neue Treffer einbauen, speichern, Probleme abwarten, bauen | Regeltreffer steigen um 2; nach dem Löschen der Baseline und einem Build: Lücke |
| PV8 | 31 Mal bauen (z. B. Strg+F9 wiederholt) | Genau 30 Punkte im Abschnitt `trends.points`, `builds` 31, der älteste Punkt fiel weg |
| PV9 | *Tools › Optionen › Atlas › Willkommensseite*: „Bereich ‚Projektverlauf‘ …“ aus; bauen | Bereich verschwindet ohne Neustart, kein neuer Punkt in der Datei; Klick in „Projekte“ öffnet wieder |
| PV10 | Gespeicherte Builds auf 10 stellen; nur „Reihe … Warnungen + Hinweise“ und „Offene TODOs“ anhaken; 1 und 500 eingeben | Kopf „letzte 10 Builds“, nur zwei Kacheln; nach dem nächsten Build höchstens 10 Punkte in der Datei. 1 wird als 2 gespeichert, 500 als 100; keine Reihe angehakt: „Keine Reihe gewählt …“ |
| PV11 | Breite der Spalte ändern (Fenster „Atlas-Start“ schmal ziehen) | Kacheln brechen um (mindestens etwa 150 px je Kachel), der Bereich wird höher, nichts ist abgeschnitten |
| PV12 | Dunkles und helles IDE-Thema, 150 % Skalierung | Linien, Flächen, Texte und Ring gut lesbar |
| PV13 | Projektgruppe bauen (Alle erzeugen), Gruppe in „Projekte“ wählen | Verlauf der Gruppe: Warnungen + Hinweise aller Projekte, Dauer des ganzen Laufs; TODOs und Methodenlänge als Lücke |
| PV14 | Datei der Zusammenfassung von Hand um ein Feld `"x": 1` in einem Punkt und in `trends` ergänzen, bauen | Beide Felder bleiben erhalten, bis der Punkt aus dem Ringpuffer fällt |
| PV15 | Baseline aktualisieren (BL1) bei einem Projekt, das der Server noch nicht als Arbeitsbereich kennt (etwa direkt nach dem Hinzufügen zur Gruppe) | Schreibt der Server in einen anderen Ordner, meldet das Meldungsfenster „Atlas: Der Server hat die Baseline in <Ordner> geschrieben, nicht im Projektordner …“; Verlauf und Abschnitt `baseline` lesen weiter den Projektordner |

### Testergebnisse (#763)

Abweichungen vom Issue: „Fehlgeschlagene erneut ausführen“ startet die lokalen Fehlschläge und die vom Server (sofern der Stand zum Job passt), jeden Test einmal. Ein Hinweis „rot geworden“ kommt nur beim Wechsel auf einen neuen roten Build, nicht beim ersten Abruf. Der Zugang wird über „Zugang zum Build-Server hinterlegen …“ (Befehlspalette, Kontextmenü des Bereichs) eingegeben; beide Felder leer entfernt ihn. Angemeldet wird nur über https; über http fragt Atlas ohne Anmeldung (offene Server). Der Bereich steht im Atlas-Layout nicht im Mockup-Raster, sondern als eigener Bereich in der linken Spalte nach „Projektverlauf“.

Vorbereitung: Testprojekt `Atlas.Tests` mit zwei fehlschlagenden und drei übersprungenen Tests, zweites Testprojekt `Kasse.Tests` (alle grün); beide einmal mit „Tests ausführen“ (#69) laufen lassen und schließen. Für die Jenkins-Fälle: Jenkins mit Job `atlas` (oder Multibranch-Job mit Branch `main`), Benutzer mit API-Token; im Projektordner `.atlas` mit `"ci": { "url": "https://ci.firma.de", "job": "atlas", "multibranch": true }`. Die Zusammenfassungen stehen in `%LOCALAPPDATA%\Atlas\projects\*.json`, Abschnitte `tests` und `ci`.

| Nr. | Schritte | Erwartet |
|---|---|---|
| TE1 | Willkommensseite bzw. „Atlas-Start“ öffnen | Bereich „Testergebnisse“ in der linken Spalte nach „Projektverlauf“: je Projekt eine Zeile mit rotem bzw. grünem Punkt, fettem Namen, Marke „2 fehlgeschlagen“ bzw. „alle 57 ok“ und grauem Text in Festbreitenschrift „412 ok · 3 übersprungen · 18,4 s · 19:41“ (Mockup #ws11) (**Abnahme**) |
| TE2 | Zeile `Atlas.Tests` wählen | Darunter höchstens 5 Fehlschläge mit roter Leiste links: voller Name, darunter Meldung und `Datei.pas:Zeile`; Knöpfe „Fehlgeschlagene erneut ausführen“ (blau) und „Im Debugger“ |
| TE3 | Doppelklick auf einen Fehlschlag (Projekt geschlossen) | Projekt öffnet sich, der Editor steht auf der Testmethode (**Abnahme**) |
| TE4 | „Fehlgeschlagene erneut ausführen“ | Genau die zwei Tests laufen (Meldungsansicht wie #69 mit `--run`), danach zeigt der Bereich den neuen Lauf ohne Neustart (**Abnahme**) |
| TE5 | Einen Fehlschlag anklicken, „Im Debugger“ | Nur dieser Test startet im Debugger und hält in seiner ersten Zeile (#585) |
| TE6 | `welcomePage.tests.maxFailures` auf 1, dann auf 99 | Nur ein Fehlschlag und „… 1 weitere“; 99 wird als 50 gespeichert |
| TE7 | `welcomePage.tests` aus | Bereich verschwindet ohne Neustart, Befehle der Tests (#69) bleiben |
| TE8 | `welcomePage.tests.ci` an, `.atlas` wie oben; Seite anzeigen | Unter `Atlas.Tests` die Zeile „Jenkins #482 · 2 fehlgeschlagen · vor 40 Min. · main“ mit eigener Ampel; Server-Fehlschläge in derselben Liste mit Marke „Server“; Knopf „Im Browser“ (**Abnahme**) |
| TE9 | Lokal alles grün, auf dem Server ein Test rot | Hinweis „lokal grün, Server rot“ in Warnfarbe hinter der Server-Zeile (**Abnahme**) |
| TE10 | Doppelklick auf einen Fehlschlag mit Marke „Server“; „Im Browser“ | Projekt öffnet sich, der Test wird in der Testunit gefunden und angesprungen (sonst Meldung „Test nicht gefunden“); „Im Browser“ öffnet die Seite des Builds im Standardbrowser |
| TE11 | Netzwerk trennen (oder falsche `url`), Seite anzeigen | Kein Dialog, keine Fehlermeldung; die Server-Zeile zeigt den letzten Stand mit „Stand vom …“ bzw. ohne früheren Abruf „nicht erreichbar“; die Seite wartet nicht (Abfrage im Hintergrund, 5 s) (**Abnahme**) |
| TE12 | Seite mehrmals öffnen und schließen, IDE neu starten | Der Server wird je Job höchstens alle 10 Minuten gefragt (`ci.attempt` in der Zusammenfassung), auch nach dem Neustart; Kontextmenü „Build-Server jetzt abfragen“ fragt sofort |
| TE13 | Jenkins mit Anmeldung, noch kein Zugang hinterlegt | Server-Zeile „Anmeldung abgelehnt (Zugang hinterlegen)“ |
| TE14 | Befehlspalette „Zugang zum Build-Server hinterlegen …“ (aktives Projekt mit `.atlas`); Benutzer und API-Token eingeben | Dialog „Build-Server https://ci.firma.de“, Token verdeckt; danach Meldung „Zugang … gespeichert“, die Seite fragt sofort neu; in der Windows-Anmeldeinformationsverwaltung steht `Atlas:ci:https://ci.firma.de` (**Abnahme**) |
| TE15 | Denselben Befehl, beide Felder leer, OK | Eintrag in der Anmeldeinformationsverwaltung verschwindet, Meldung „Zugang … entfernt“ |
| TE16 | `.atlas` ohne `ci` bzw. `ci.url` über http | Befehl meldet „… nennt in seiner .atlas keinen Server …“; über http fragt Atlas ohne Anmeldung, das Token geht nie über http |
| TE17 | Neuer Build auf dem Server wird rot (vorher grün), Seite anzeigen | Eintrag in der Benachrichtigungszentrale „Jenkins #483 rot: Atlas.Tests“ mit „Im Browser“, Quelle „Build-Server“; mit `notifications.sources` `buildServer=off` kein Eintrag; mit `welcomePage.tests.ci.notify` aus kein Eintrag (**Abnahme**) |
| TE18 | Multibranch: Branch in Git auf `develop` wechseln, Seite anzeigen | Abgefragt wird der Job von `develop`; der Stand von `main` wird nicht als `develop` gezeigt |
| TE19 | Protokoll (`%LOCALAPPDATA%\Atlas\Logs`) nach TE8–TE17; Zusammenfassung und Registry ansehen | Nur „Testergebnisse: jenkins-Build …“ bzw. „nicht abgefragt (network)“; weder Adresse, Job, Benutzer noch Token; kein Token in Dateien oder Registry |
| TE20 | Schnellschalter „Zugang zum Build-Server“ aus | Befehl fehlt in der Palette, Kontextmenü ohne den Eintrag; die Abfrage mit schon hinterlegtem Zugang läuft weiter |
| TE21 | IDE-Thema hell ↔ dunkel, 150 % Skalierung | Punkte, Marken, rote Leiste, Marke „Server“ und Knöpfe gut lesbar, nichts abgeschnitten |
| TE22 | IDE während einer laufenden Abfrage schließen (Server antwortet langsam) | IDE schließt ohne Hänger (Abbruch spätestens nach der Wartezeit des Entladens) |

### Nicht gesichert (#762)

Abweichungen vom Issue: Die Auswertung liegt in `Atlas.Core.Welcome.Unsaved` statt in `Atlas.Common`, weil das Plugin `Atlas.Common` nicht einbindet (ADR 0011). „Ansehen“ öffnet das Projekt und listet die Dateien im Fenster „Atlas-Ergebnisse“, weil #571 keine eigene Änderungsansicht hat. Gleichartiges wird je Projekt zu einer Zeile zusammengefasst (z. B. „2 Stashes, ältester …“); repository-weite Arten (Commits, Branches ohne Upstream, Stashes) erscheinen je Arbeitskopie nur einmal.

Vorbereitung: Git-Projekt `GitDemo` mit Remote `origin` (z. B. ein lokales Bare-Repository), Branch `main` mit Upstream; SVN-Projekt `SvnDemo`; ein Projekt ohne Versionsverwaltung. Alle drei einmal öffnen und schließen.

| Nr. | Schritte | Erwartet |
|---|---|---|
| NG1 | `GitDemo`: 3 Commits ohne Push, eine Änderung mit `git stash push -m Versuch` sichern, dann 4 Dateien ändern bzw. anlegen bzw. löschen; Projekt schließen, Willkommensseite öffnen | Bereich „Nicht gesichert“ in der rechten Spalte mit 3 Zeilen „**GitDemo** · main“: „4 Dateien: … · seit …“ mit „Ansehen“, „3 Commits nicht gepusht (main) · seit …“ mit „Push …“, „Stash „Versuch“ vom … · seit …“ mit „Ansehen“; älteste zuerst |
| NG2 | `SvnDemo`: 2 Dateien ändern, Projekt schließen | eine Zeile „2 Dateien geändert · seit …“, keine Push- und keine Stash-Zeile |
| NG3 | SVN-Datei mit Konflikt (zwei Arbeitskopien, beide ändern, `svn update`) | Zeile „1 Dateien im Konflikt“ bzw. „n Dateien im Konflikt“ mit „Ansehen“ |
| NG4 | Projekt ohne Versionsverwaltung | erscheint nicht; keine Meldung, kein Eintrag im Protokoll als Fehler |
| NG5 | Datei vor über 72 Stunden geändert (Änderungszeit setzen, z. B. `(Get-Item X.pas).LastWriteTime = (Get-Date).AddDays(-4)`) | Punkt rot; zwischen 24 und 72 Stunden gelb; jünger grün |
| NG6 | „Push …“ in der Commit-Zeile | Dialog „Push – GitDemo“ mit Ziel `main → origin/main (3 Commits)` und den Commits (Kurz-Hash, Zeit, Betreff); Enter und Esc brechen ab, nichts wird gepusht |
| NG7 | NG6, dann „Pushen“ | Push läuft im Hintergrund; Meldungsansicht „GitDemo: main nach origin/main gepusht.“; Zeile verschwindet nach der neuen Abfrage |
| NG8 | Branch `feature/x` ohne Upstream mit einem Commit, „Push …“ | Zeile „Branch feature/x ohne Upstream, 1 Commits nur lokal“; Dialog nennt „feature/x → origin/feature/x (neu auf dem Server, wird verfolgter Branch; …)“; nach „Pushen“ hat der Branch einen Upstream |
| NG9 | Push mit neueren Commits auf dem Server (Push abgelehnt) bzw. Remote nicht erreichbar | Meldung „Push von … fehlgeschlagen (…). Hat der Server neuere Commits, erst Pull.“; kein Hängen der IDE; nach spätestens 2 Minuten Zeitlimit |
| NG10 | „Ansehen“ in der Änderungszeile bzw. in der Stash-Zeile | Projekt öffnet sich (falls noch nicht offen); Fenster „Atlas-Ergebnisse“ listet die Dateien mit Art („geändert“, „neu“, „gelöscht“) bzw. „Stash „Versuch“: geändert“; Doppelklick öffnet die Datei |
| NG11 | Rechtsklick auf eine Zeile: „Ordner öffnen“; dann „Ignorieren bis morgen“ | Explorer mit markierter Projektdatei; Zeile verschwindet und kommt am nächsten Tag (nach Mitternacht Ortszeit) bzw. nach IDE-Neustart am selben Tag nicht wieder |
| NG12 | Alles committen, pushen, Stash verwerfen; Willkommensseite neu öffnen | Zeile „Alles gesichert“; mit „Bereich ausblenden, wenn alles gesichert ist“ verschwindet der Bereich ganz und kommt bei neuer Arbeit wieder |
| NG13 | *Tools › Optionen › Atlas › Willkommensseite*: „Bereich ‚Nicht gesichert‘ …“ aus | Bereich verschwindet sofort, keine git- bzw. svn-Aufrufe mehr (Prozess-Monitor) |
| NG14 | Mindestalter 48 eingeben | Zeilen jünger als 48 Stunden fehlen; „Nichts zu zeigen (n Einträge jünger als die Mindestzeit …)“; Gelb 48 und Rot 12 eingeben speichert Rot = 48 |
| NG15 | Netzlaufwerk trennen bzw. git aus dem PATH nehmen; Willkommensseite öffnen | Seite sofort da; gespeicherter Stand aus der Projekt-Zusammenfassung; kein `git fetch`, kein Netzzugriff (Prozess-Monitor: nur lokale git-Aufrufe), je Projekt höchstens 2 s |
| NG16 | Acht Projekte in der Liste, IDE neu starten | Bereich ohne spürbare Verzögerung; Abfrage im Hintergrund, höchstens einmal je Minute und Projekt; beim Schließen eines Projekts sofort neu |
| NG17 | Dunkles und helles Thema, 150 % Skalierung, Delphi 12 bzw. Host „Atlas-Start“ | Punkt, Name, Branch, Detailzeile und Schaltfläche lesbar und nicht abgeschnitten; Tooltip mit Pfad, Branches und ältestem Stand; im Fenster „Atlas-Start“ derselbe Inhalt |

### Zustandskachel „Atlas“ (#754)

Abweichungen vom Issue: „Jetzt aktualisieren“ führt den Ablauf aus #495 aus, also die Seite mit Änderungen und Download des neuen Releases im Browser; Atlas lädt und installiert nichts selbst (#495 schließt das aus). Der Index-Stand ohne laufenden Server kommt aus der neuen Datei `%LOCALAPPDATA%\Atlas\index-state.json`; der Zeitpunkt der letzten vollständigen Indizierung ist das Ende des letzten Indexlaufs, den Atlas gesehen hat. Die Texte der Statusfeld-Zeilen Server, Index und Version sind wie die übrigen Zeilen aus #591 deutsch.

Vorbereitung: Plugin (Win32 und Win64) gebaut und installiert, Willkommensseite (bzw. Fenster *Atlas-Start*) mit Atlas-Bereichen, ein Projekt mit einigen Units.

| Nr. | Schritte | Erwartet |
|---|---|---|
| ZK1 | `Atlas.Tests` bauen und ausführen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TAtlasWelcomeStateTests`, `TAtlasStateLinesTests`, `TAtlasIndexStoreTests`, `TAtlasStateUpdateTests` und `TAtlasWelcomeStateFrameTests` grün |
| ZK2 | IDE starten, Projekt öffnen, Server läuft, Indizierung fertig; Willkommensseite | Kachel „Atlas“ in der rechten Spalte mit fünf Zeilen: grün „Server läuft“ mit „seit hh:mm“ rechts, „Atlas <Version>“ (grün „aktuell“ mit eingeschalteter Update-Prüfung, sonst grau), grün „Index: n Units“ mit „indiziert hh:mm“, „Einrichtung: …“, grau „Diagnosemodus aus“; darunter „Server neu starten“, „Einstellungen“, „Log-Ordner öffnen“; kein „Jetzt aktualisieren“ |
| ZK3 | Während der Indizierung (z. B. Index neu aufbauen) | Index-Zeile gelb „Index wird aufgebaut“ mit Prozent rechts (z. B. „45 %“), ändert sich ohne Klick; danach grün mit „indiziert <Uhrzeit des Endes>“ |
| ZK4 | `AtlasServer.exe` im Task-Manager beenden | Zeile „Server abgestürzt“ rot mit „um hh:mm“; Statusfeld zeigt im selben Moment dieselbe Ampel (rot) und im Tooltip „Server: abgestürzt um …“ |
| ZK5 | ZK4, dann „Server neu starten“ | Server startet; Zeile wird gelb („startet“) und dann grün „Server läuft“ mit neuem „seit“; kein Zwischenstand „beendet“ als rot |
| ZK6 | *Atlas › Server neu starten* bzw. Server über die Optionen beenden | kurz „Server beendet“ grau (nicht rot), danach wie ZK5 |
| ZK7 | Server läuft nicht (Serverpfad ungültig), IDE nach einer Sitzung mit indiziertem Projekt neu starten | Index-Zeile grau „Index: n Units“ mit „Stand vom TT.MM. hh:mm“ (bzw. nur Uhrzeit am selben Tag); Tooltip „… (Server läuft nicht)“. Ohne je gespeicherten Stand: „Index: Server läuft nicht“ |
| ZK8 | Update-Prüfung an, in `%LOCALAPPDATA%\Atlas\updates.json` `"lastCheck"` auf ein altes Datum und eine ältere installierte Version (bzw. neues Release vorhanden); IDE starten | Nach der Prüfung Zeile gelb „Update x.y.z bereit“ mit „installiert a.b.c“; Knopf „Jetzt aktualisieren“ erscheint; Statusfeld zeigt dieselbe gelbe Zeile „Version: Atlas a.b.c, Update x.y.z bereit“ |
| ZK9 | ZK8: „Jetzt aktualisieren“ bzw. Klick auf die Versionszeile | Browser öffnet die Release-Seite des Updates (https); kein Download durch die IDE; Plugin-Protokoll „Update x.y.z: Änderungen im Browser geöffnet“ ohne Adresse |
| ZK10 | ZK8, IDE neu starten (Prüfung heute schon gelaufen) | Gelbe Zeile und Knopf bleiben (gefundene Version in `updates.json`, Feld `available`); nach Installation der neuen Version grün „aktuell“ |
| ZK11 | Einrichtung mit einem gelben Punkt (z. B. Error Insight an) | Zeile „Einrichtung: 5 von 6 erledigt“ gelb, unterstrichen; Klick öffnet die Prüfliste (#625) |
| ZK12 | Diagnosemodus einschalten (Strg+Umschalt+Alt+D) | Zeile gelb „Diagnosemodus an“ mit „Logs wachsen“ rechts, unterstrichen; Klick öffnet „Atlas-Diagnose“; ausschalten: grau „Diagnosemodus aus“ |
| ZK13 | „Einstellungen“ | *Tools › Optionen › Drittanbieter › Atlas* öffnet (wie Menü *Atlas › Optionen…*) |
| ZK14 | „Log-Ordner öffnen“ | Explorer mit `%LOCALAPPDATA%\Atlas\Logs` |
| ZK15 | Für jede Zeile Kachel und Statusfeld vergleichen (Tooltip bzw. Fenster des Statusfelds) | Gleiche Ampel je Zeile; Tooltip der Kachelzeile = Text der Statusfeld-Zeile |
| ZK16 | *Tools › Optionen › Atlas › Willkommensseite*: „Zustandskachel nur zeigen, wenn eine Zeile gelb oder rot ist“; alles grün bzw. grau | Kachel verschwindet sofort; Diagnosemodus einschalten bzw. Server beenden: Kachel erscheint ohne Neuladen der Seite, nach dem Ausschalten verschwindet sie wieder |
| ZK17 | „Zustandskachel „Atlas“ …“ aus | Kachel verschwindet sofort; im Kontextmenü bzw. Atlas-Layout kein Bereich „Atlas“ mehr; an: kommt zurück |
| ZK18 | Im Leerlauf 5 Minuten beobachten (Prozess-Monitor, Profiler) | Kein Zeitgeber der Kachel; gezeichnet wird nur bei einer Änderung (Server-Abfrage alle 5 s ändert nur bei neuen Werten etwas) |
| ZK19 | Schmale Spalte bzw. Fenster *Atlas-Start* schmal ziehen; dunkles und helles Thema, 150 % Skalierung | Knöpfe brechen in eine zweite Reihe um, die Kachel wird höher, nichts abgeschnitten; lange Texte enden mit „…“, Zusatz rechts bleibt sichtbar; Punkte und Texte lesbar; Themenwechsel ohne Neustart |
| ZK20 | Abgesicherter Start | Kachel zeigt, was es gibt; fehlende Zeilen grau (z. B. „Einrichtung noch nicht geprüft“); kein Fehler im Protokoll |

### Atlas entdecken (#757)

Entscheidung zur Ablage: Die Zählung je Befehl steht (wie im Issue verlangt) in `%LOCALAPPDATA%\Atlas\usage.json` und enthält nur Befehlskennung, Zähler (`mouse`, `keyboard`) und `lastUsed`. Zustand der Tipps (letzter Tastenkürzel-Tipp, „Nicht mehr zeigen“ aus #600) und der Abschnitt `discover` der Karte (gesperrte Tipps, zuletzt gezeigter) stehen in `%LOCALAPPDATA%\Atlas\shortcut-tips.json`. Gezählt wird über die Beobachtung der Tastenkürzel-Tipps (#600); sie läuft, solange `shortcutTips.enabled` oder (Willkommensseite, Karte und `tips.usageTracking` an) gilt. Im abgesicherten Start (#722) zeigt die Karte Tipps, zählt aber nichts.

Vorbereitung: Paket mit `tips.json`, `Tipps\` und `Beispiele\` neben den BPL-Ordnern (Installer bzw. `Setup\tips.json`, `Setup\Tipps` und `Setup\Beispiele` von Hand dorthin kopieren). `%LOCALAPPDATA%\Atlas\usage.json` und `shortcut-tips.json` gelöscht. Willkommensseite (bzw. Fenster *Atlas-Start*) mit Atlas-Bereichen.

| Nr. | Schritte | Erwartet |
|---|---|---|
| AE1 | `Atlas.Tests` bauen und ausführen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TAtlasTipCatalogTests` (auch `HighDpiImageWhenScaledAndPresent`), `TAtlasDiscoverTests` (auch `SettingOnReadsSwitchesAndChoices`), `TAtlasShortcutTipsTests.KeyOnlyFunctionsHaveNoPaletteCommand`, `TAtlasCommandUsageTests`, `TAtlasWelcomeDiscoverFrameTests` (auch `ImageFitsColumn`), `TAtlasSettingsPageTests.WelcomeSettingsRoundTrip`, `TAtlasSettingsPageTests.UsageButtonsCallBack` und `TSetupInstallerTests` grün |
| AE2 | IDE starten | Karte „Atlas entdecken“ in der rechten Spalte unter „Neu in Atlas“ (Atlas-Layout) bzw. als eigener Bereich: Bild (320 × 180, in schmaler Spalte oben, ab etwa 560 Pixeln Spaltenbreite links neben dem Text), fetter Titel „Befehlspalette“ mit dem tatsächlichen Kürzel („Strg+Umschalt+P“ bzw. „Ctrl+Shift+P“) daneben, ein bis zwei Sätze, grau „Noch nie benutzt“ und rechts „Tipp 1 von n“ (n bis 28, je nach eingeschalteten Funktionen); darunter „Ausprobieren“, „Nächster Tipp“, „Nicht mehr zeigen“ (**Abnahme**) |
| AE3 | „Nächster Tipp“ bis „Code-Aktionen“, dort „Ausprobieren“ | `Beispiele\Entdecken.pas` öffnet sich, der Cursor steht auf `Rabatt` (Zeile 77); Meldungsansicht „Atlas entdecken: Beispiel geöffnet – jetzt … drücken.“; das Kürzel zeigt die Code-Aktionen |
| AE4 | AE3, dann das Kürzel drücken; IDE neu starten | `usage.json` enthält `Atlas.CodeActions` mit `keyboard` ≥ 1 und `lastUsed` von heute (spätestens 5 s nach dem Aufruf bzw. beim Beenden gespeichert); nach dem Neustart kommt zuerst ein anderer, noch nie benutzter Tipp; „Code-Aktionen“ erscheint erst nach allen nie benutzten und zeigt dann „Zuletzt heute benutzt“ (**Abnahme**) |
| AE5 | „Nächster Tipp“ mehrmals | Tipp für Tipp in der festen Reihenfolge des Starts, „Tipp n von m“ zählt mit, nach dem letzten wieder der erste; IDE neu starten: die Karte beginnt nach dem zuletzt gezeigten Tipp |
| AE6 | Bei „Umbenennen im ganzen Projekt“ „Nicht mehr zeigen“; IDE neu starten, alle Tipps durchblättern | Die Karte springt sofort zum nächsten Tipp; `shortcut-tips.json` enthält `"discover": {"blocked": ["rename"], …}`; auch nach dem Neustart kommt der Tipp nie wieder, „von m“ ist um eins kleiner (**Abnahme**) |
| AE7 | *Tools › Optionen › Atlas › Willkommensseite* „Gesperrte Tipps wieder zeigen“ | Knopf wird grau; der gesperrte Tipp erscheint beim Durchblättern wieder (hinten in der Reihenfolge) |
| AE8 | Seite *Rückgängig über mehrere Dateien*: `undo.multiFile` aus; Tastenkürzel-Übersicht (*Tastenkonflikte*) aus; `welcomePage.whatsNew` = `off`; dann alle Tipps durchblättern, IDE neu starten | „Änderungen über mehrere Dateien zurücknehmen“, „Tastenkürzel-Übersicht“ und „Neu in Atlas“ erscheinen nie (auch nicht über „Nächster Tipp“); wieder an bzw. `afterUpdate`: sie kommen ohne Neustart zurück. Mit dem Hauptschalter (Atlas aus) fehlen „Vervollständigung von Atlas“ und „Parameter-Hint“ (**Abnahme**) |
| AE9 | `welcomePage.discover` aus | Karte verschwindet sofort, im Kontextmenü bzw. Atlas-Layout kein Bereich „Atlas entdecken“; mit `shortcutTips.enabled` aus wird nichts mehr gezählt (Protokoll „Beobachtung False“) (**Abnahme**) |
| AE10 | `tips.usageTracking` aus, einige Atlas-Befehle per Menü und Kürzel aufrufen, IDE neu starten | `usage.json` ändert sich nicht (Zeitstempel und Inhalt); die Karte zeigt keinen Hinweis „Noch nie benutzt“/„Zuletzt …“ und die Tipps kommen der Reihe nach, je Start nach dem zuletzt gezeigten (**Abnahme**) |
| AE11 | „Zählung zurücksetzen“ | Knopf wird grau; `usage.json` enthält keine Zähler mehr (`"commands": {}`); die Karte zeigt sofort „Noch nie benutzt“; `shortcut-tips.json` (gesperrte Tipps, „Nicht mehr zeigen“ aus #600) bleibt |
| AE12 | `usage.json` in einem Editor ansehen | Nur `format` und je Befehl `mouse`, `keyboard`, `lastUsed`; keine Dateinamen, kein Quelltext, keine Projektnamen (**Abnahme**) |
| AE13 | Alte `shortcut-tips.json` aus #600 mit Zählern (`mouse`/`keyboard`/`lastUsed` je Befehl), `usage.json` fehlt; IDE starten, einen Befehl aufrufen, 5 s warten | `usage.json` entsteht mit den alten Zählern plus dem neuen Aufruf; `shortcut-tips.json` enthält danach nur noch `lastTip`/`never` und `discover` |
| AE14 | Über die Befehlspalette (oder das Menü *Atlas*) „Symbolsuche“ ausführen, die Karte bei „Symbolsuche“ „Ausprobieren“ | Ohne Beispieldatei führt „Ausprobieren“ den Befehl aus; danach gilt er beim nächsten Start nicht mehr als nie benutzt |
| AE15 | Mit `shortcutTips.enabled` an eine Atlas-Aktion per Menü aufrufen, die in `tips.json` steht (z. B. *Atlas › Auswahl erweitern*) | Der Tastenkürzel-Tipp (#600) zeigt den Titel aus `tips.json` („Auswahl erweitern“) |
| AE16 | `tips.json` löschen bzw. alle Tipps sperren | Kein Bereich „Atlas entdecken“; kein Fehler im Protokoll. Bild löschen: Karte ohne Bild, Text rückt nach links. `Beispiele\Entdecken.pas` löschen: „Ausprobieren“ meldet „Die Beispieldatei … fehlt in der Installation.“ |
| AE17 | Dunkles und helles Thema, 100 %, 125 %, 150 %, 200 % Skalierung (Monitor wechseln); Spalte bzw. Fenster *Atlas-Start* schmal und breit ziehen | Bild in beiden Themen gut abgegrenzt (grauer Rand) und der Text im Bild bei 100 % ohne Lupe lesbar (320 × 180, Pixel für Pixel scharf); bei 200 % aus der `@2x`-Datei Pixel für Pixel, bei 125 % und 150 % aus ihr glatt verkleinert (helle Schrift bleibt erhalten), nie verzerrt; nach dem Monitorwechsel passt das Bild ohne Neustart. Schmale Spalte: Bild oben, kleiner mit gleichem Seitenverhältnis, Text darunter; breite Spalte: Text neben dem Bild. Text bricht um, Knöpfe brechen in eine zweite Reihe um, die Karte wird höher, nichts abgeschnitten (**Abnahme**) |
| AE18 | Protokoll (`%LOCALAPPDATA%\Atlas\Logs`) nach AE2–AE11 | Nur Zahlen („n von m Tipps in Frage“, „Tipps (#757): 28 aus tips.json“) und „Tipp gesperrt“/„Sperren aufgehoben“/„Nutzungszählung zurückgesetzt“; keine Befehle, Pfade oder Benutzernamen |
| AE19 | Installer: Paket aus dem Release installieren, dann über eine Version mit anderem Tipp-Bild aktualisieren | `tips.json` und `Tipps\*.png` (je Tipp `<name>.png` und `<name>@2x.png`) im Installationsordner; alte Bilder sind nach dem Update weg; Deinstallation mit „Daten löschen“ entfernt `usage.json` und `shortcut-tips.json` |
| AE20 | Tipp „Befehlspalette“: „Ausprobieren“; dann *Tastenkonflikte* die Taste der Palette ändern und die Willkommensseite neu zeigen | Die Befehlspalette öffnet sich über dem aktiven Fenster; die Karte zeigt danach die neue Taste |
| AE21 | Alle Tipps mit Beispielstelle nacheinander „Ausprobieren“ und das genannte Kürzel drücken (bzw. den Befehl aus dem Menü *Atlas* aufrufen, wenn kein Kürzel belegt ist) | Cursor in `Entdecken.pas` (Zeile:Spalte) und Ergebnis: Code-Aktionen 77:27 auf `Rabatt` (Liste der Aktionen); Auswahl erweitern 76:32 auf `Preis` (wächst schrittweise); Umbenennen 28:3 auf `TKunde`; Referenzen 33:14 auf `Name` (Fundstellen in Zeile 33 und 82); Implementierungen 25:14 auf `IPreisliste.Preis` (TStandardpreise.Preis, TStaffelpreise.Preis); Typdefinition 82:13 auf `AKunde` (springt zu `TKunde`, Zeile 28); Aufrufer 70:10 auf `Gesamtpreis` (Beschriftung); Aufrufe 80:10 auf `Beschriftung` (Gesamtpreis, TStaffelpreise.Create, CurrToStr); Vorfahren 41:3 auf `TStaffelpreise` (TStandardpreise, TInterfacedObject, IPreisliste); Nachfahren 36:3 auf `TStandardpreise` (TStaffelpreise); Vervollständigung 82:20 hinter `AKunde.` (Strg+Leer: Mitglieder von TKunde mit `Name`); Parameter-Hint 82:64 im Aufruf von `Gesamtpreis` (Strg+Umschalt+Leer: zweiter Parameter `APreise` hervorgehoben); Qualifizierter Name 65:25 auf `Preis` (Zwischenablage `Entdecken.TStaffelpreise.Preis`) (**Abnahme**) |
| AE22 | Tipps ohne Beispielstelle „Ausprobieren“: Symbolsuche, Ergebnisfenster, Compiler prüfen, Schnellschalter, Tastenkürzel-Übersicht, Projekt-Einstellungen, Einrichtung prüfen, Atlas-Layout anwenden, Atlas-Start, Neu in Atlas, Fehlerbericht erstellen, Diagnoselog exportieren | Jeweils derselbe Befehl wie in der Befehlspalette (Fenster bzw. Dialog öffnet sich, Syntaxprüfung des aktiven Projekts läuft, Layout wird angewendet); „Änderungen über mehrere Dateien zurücknehmen“ öffnet nur die Liste „Atlas-Änderungen“ und nimmt nichts zurück; „Alles aus für diese Sitzung“ öffnet nur die Schnellschalter |
| AE23 | Vervollständigung und Parameter-Hint ohne eigene Taste (Seite *Tastenkonflikte*: keine) bzw. mit eigener Taste | Die Karte nennt Strg+Leer bzw. Strg+Umschalt+Leer der IDE; mit eigener Taste diese |

### Hilfe und Rückmeldung (#766)

Entscheidungen: Die Kurzbeschreibung kommt nur in die Issue-Vorlage, nicht in die ZIP (sie ist freier Text des Nutzers und wird ohnehin im Issue sichtbar). Die Versionen stehen in der Vorlage nur, wenn das Häkchen „Version von Atlas, RAD Studio und Windows“ gesetzt ist; sonst „(nicht angegeben)“. Die letzten Diagnosedaten (#479) sind nicht vorausgewählt. Die Ziel-URL muss mit http:// oder https:// beginnen (Einstellung und Dialog prüfen beide), sonst gilt die Issue-Seite des Atlas-Repositorys; so startet „Issue-Seite öffnen“ nie ein Programm.

Vorbereitung: Paket aus dem Release bzw. `pwsh Tools/Build-Docs.ps1 -OutDir <Installationsordner>\Doku`. Ein Projekt unter einem Pfad mit dem eigenen Benutzernamen (z. B. `C:\Users\<Name>\Projekte\Kunde`) einmal geöffnet, damit `atlas.log` Projektpfade enthält. Diagnosemodus (#479) einmal an und eine Vervollständigung ausgelöst, damit `Logs\Diagnose\atlas-diagnosemodus.txt` existiert.

| Nr. | Schritte | Erwartet |
|---|---|---|
| HR1 | `Atlas.Tests` bauen und ausführen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TAtlasDiagnosticPackageTests`, `TAtlasReportDialogTests`, `TAtlasWelcomeHelpFrameTests`, `TAtlasWelcomeSettingsTests`, `TAtlasSettingsPageTests.WelcomeSettingsRoundTrip` und `TSetupInstallerTests` grün |
| HR2 | IDE starten | Bereich „Hilfe und Rückmeldung“ unten in der rechten Spalte mit „Atlas-Doku“, „Tastenkürzel“, „Problem melden …“ und darunter grau „Nichts wird automatisch gesendet.“ (**Abnahme**) |
| HR3 | „Atlas-Doku“ mit installierter Doku | Der Standardbrowser öffnet `…\Atlas\Doku\index.html`: Inhaltsverzeichnis mit Überblick, Installation, RAD Studio, Einstellungen, Konfiguration, Regeln, Schlüsselwörter, MCP und Änderungen; Verweise zwischen den Seiten gehen lokal, andere ins Repository; helles und dunkles Systemthema lesbar (**Abnahme**) |
| HR4 | Ordner `Doku` umbenennen, „Atlas-Doku“ | Der Browser öffnet `https://github.com/xKnockOut/Atlas-IDE-Expert/tree/main/docs` |
| HR5 | „Tastenkürzel“ | Die Tastenkürzel-Übersicht aus #520 mit allen Kürzeln öffnet sich (**Abnahme**) |
| HR6 | *Tastenkonflikte*: `keys.overview` aus | „Tastenkürzel“ ist sofort ausgegraut; wieder an: klickbar |
| HR7 | „Problem melden …“ | Dialog „Problem melden“: Hinweis, Kurzbeschreibung, Häkchen Logs, Versionen, Einstellungen (gesetzt) und „Letzte Diagnosedaten“ (nicht gesetzt); Vorschau mit `atlas-info.txt`, `einstellungen.json`, `plugin/atlas.log`, `server/diag-*.log` und Größen; Summe „n Dateien, zusammen … KB“; Ordner = Desktop (**Abnahme**) |
| HR8 | Häkchen einzeln ab- und anwählen, „Letzte Diagnosedaten“ setzen | Die Vorschau folgt sofort; mit Diagnosedaten kommt `atlas-diagnosemodus.txt` dazu; ohne Datei ist das Häkchen grau mit „(keine vorhanden)“; alles ab: „Nichts ausgewählt.“, „ZIP anlegen“ grau |
| HR9 | Jede Datei per Doppelklick bzw. „Ansehen“ öffnen | Fenster „Inhalt von …“ zeigt den Text; weder Benutzername noch Rechnername noch Projektpfade, Pfade als `<pfad>`/`<ws>`, Namen als `<benutzer>`; `einstellungen.json` ohne Pfadwerte (`"<pfad>"`) (**Abnahme**) |
| HR10 | „ZIP anlegen“ | `Atlas-Diagnose-<heute>.zip` auf dem Desktop, der Explorer zeigt sie markiert; Statuszeile „Angelegt: …“; ein zweites Mal: `…-2.zip`, die erste bleibt; ZIP enthält genau die Dateien der Vorschau (**Abnahme**) |
| HR11 | ZIP entpacken und durchsuchen (`findstr /s /i "<Benutzername> <Rechnername> Projekte\Kunde" *`) | Keine Treffer (**Abnahme**) |
| HR12 | „Ordner …“, anderen Ordner wählen, „ZIP anlegen“ | ZIP im gewählten Ordner; `welcomePage.help.reportFolder` = `D:\Ablage` in den Optionen: der Dialog beginnt dort, ein fehlender Ordner wird angelegt |
| HR13 | Kurzbeschreibung eintragen, „ZIP anlegen“, dann „Issue-Seite öffnen“; in ein Textfeld einfügen | Browser öffnet `https://github.com/xKnockOut/Atlas-IDE-Expert/issues/new`; die Zwischenablage enthält Markdown mit „## Beschreibung“ (der Text), „## Versionen“ (Atlas, RAD Studio mit Plattform, Windows), „## Diagnosepaket“ mit dem ZIP-Namen; Pfade in der Beschreibung anonymisiert; Atlas hat keine Verbindung aufgebaut (Ressourcenmonitor bzw. Fiddler: keine Verbindung von `bds.exe`) (**Abnahme**) |
| HR14 | „Versionen“ abwählen, „Issue-Seite öffnen“ ohne ZIP | Vorlage mit „(nicht angegeben)“ und „Kein Diagnosepaket angelegt.“ |
| HR15 | `welcomePage.help.reportUrl` auf `https://example.org/neu` bzw. `cmd.exe` | Erst öffnet der Browser example.org; `cmd.exe` speichert die Optionsseite als Vorgabe-URL zurück, es startet kein Programm |
| HR16 | `welcomePage.help` aus | Bereich verschwindet sofort; wieder an: erscheint ohne Neustart (**Abnahme**) |
| HR17 | Englische IDE | „Help and feedback“, „Atlas docs“, „Shortcuts“, „Report a problem …“; Dialog und Vorlage englisch („## Description“) |
| HR18 | Schmale Spalte bzw. Fenster *Atlas-Start*, 100 %, 150 %, 200 % Skalierung | Knöpfe brechen in weitere Reihen um, der Bereich wird höher, nichts abgeschnitten; Dialog mit Fuß lesbar und in der Größe änderbar |
| HR19 | *Atlas › Diagnoselog exportieren…* (#647) mit vorhandener Diagnosemodus-Datei | Vorschau und ZIP enthalten zusätzlich `atlas-diagnosemodus.txt` |
| HR20 | Installer: Paket aus dem Release installieren, dann aktualisieren | `Doku\index.html` und die übrigen Seiten im Installationsordner; Seiten, die es im neuen Paket nicht mehr gibt, sind weg |
| HR21 | Protokoll (`%LOCALAPPDATA%\Atlas\Logs\atlas.log`) nach HR7–HR15 | Nur „Problem melden (#766): Dialog geöffnet“; keine Pfade, Adressen oder Texte aus dem Dialog |

### Projekt für Atlas einrichten (#759)

Entscheidungen: Ziel ist das aktive Projekt, ohne offenes Projekt das oberste nicht ausgeblendete der Liste „Wieder öffnen“ (das auch eine Projektgruppe sein kann; atlas.json kommt dann neben die `.groupproj`). „Baseline erzeugen“ und „Suchpfade prüfen“ brauchen das geöffnete Projekt; ohne heißen beide Knöpfe „Projekt öffnen“. Die Prüfung gilt für die aktive Konfiguration und Plattform; Units in Zweigen, deren Bedingung sich nicht auswerten lässt (`CompilerVersion`, `Declared`, `$IFOPT`), zählen nicht. Defines aus `{$IFDEF}` in eingebundenen Dateien zählen nicht als Abfrage (Bibliotheken wie `jedi.inc`), ihre `{$DEFINE}` aber als Quelle. „Neu mit Atlas“ steht auch ohne Karte da (Titel „Neu mit Atlas“), solange ein Projekt offen ist.

Vorbereitung: Projekt `XmlInspector` (VCL, Git egal) ohne `atlas.json` und ohne Baseline, mit `uses Xml.Helpers;` in `Main.pas` (Zeile 12) ohne passende Datei und `{$IFDEF USE_XML}` ohne Define; ein zweites Projekt `Fertig` mit atlas.json, Baseline und sauberen Pfaden.

| Nr. | Schritte | Erwartet |
|---|---|---|
| PE1 | `Atlas.Tests` bauen und ausführen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TAtlasProjectSetupTests` (Vorlagen gegen das Schema, Erkennung offener Schritte), `TAtlasSchemaCheckTests`, `TAtlasPathCheckTests`, `TAtlasWelcomeSetupTests`, `TAtlasWelcomeSetupFrameTests`, `TAtlasFileTemplatesTests`, `TTextDefinesTests` und `TSetupInstallerTests` grün |
| PE2 | `XmlInspector` öffnen, Willkommensseite bzw. *Atlas-Start* | Karte „XmlInspector für Atlas einrichten“: ✓ grün „Projekt gefunden, keine atlas.json“, darunter „atlas.json anlegen“ mit Auswahl „Bestehendes Projekt“ und „Anlegen …“, „Baseline erzeugen“ [Starten], „Suchpfade und Defines prüfen“ [Prüfen], Link „Für dieses Projekt nicht mehr fragen“, Reihe „Neu mit Atlas:“ [Unit] [Formular] [Testklasse] (Mockup #ws7) |
| PE3 | Vorlage „Altprojekt mit Baseline“ wählen, „Anlegen …“ | Dialog „atlas.json anlegen“ mit Ziel, Vorlage und Inhalt (`"minConfidence": "high"`, `overrides` für `Generated/**`); Abbrechen bzw. Esc: keine Datei |
| PE4 | „Anlegen …“, im Dialog „Anlegen“ | `atlas.json` liegt neben `XmlInspector.dproj` (UTF-8 ohne BOM, CRLF), Meldungsansicht „Projekt einrichten: … angelegt.“; Schritt 2 sofort grün mit ✓ „atlas.json vorhanden“, Auswahl und Knopf weg (**Abnahme**) |
| PE5 | Datei im Explorer löschen und eine eigene `atlas.json` von Hand anlegen, dann (vor dem Aktualisieren der Karte) „Anlegen …“ | Meldung „… gibt es schon; Atlas überschreibt sie nicht.“, die Datei bleibt unverändert |
| PE6 | Installationsordner: `Vorlagen\atlas-existing.json` mit ungültigem Wert (`"minConfidence": "sehr"`) speichern, „Anlegen …“ | Der Dialog zeigt die eingebaute Fassung (`"minConfidence": "medium"`); Protokoll „Vorlage existing passt nicht zum Schema, eingebaute Fassung“ |
| PE7 | „Starten“ bei Baseline | Text „Baseline wird erzeugt … 3 s“ zählt hoch, Knopf ausgegraut; danach ✓ „Baseline vorhanden“ und „Baseline mit 412 Treffern in 87 Dateien; neue Treffer: 0“; Meldungsansicht wie *Baseline des Projekts aktualisieren*; im Bereich „Projekte“ „0 neu“ (**Abnahme**) |
| PE8 | Server beenden (Atlas aus), „Starten“ | Unter dem Schritt der Grund („Der Atlas-Server hat keine Baseline geschrieben …“), Knopf wieder klickbar |
| PE9 | „Prüfen“ | „Suchpfade und Defines werden geprüft … n s“, danach „1 Units nicht gefunden, 1 Defines ohne Quelle (n Dateien geprüft)“ und die Zeilen „Unit „Xml.Helpers“ nicht gefunden – Main.pas, Zeile 12“ und „Define „USE_XML“ ohne Quelle – …“ (**Abnahme**) |
| PE10 | Auf eine Fundzeile klicken bzw. „Projektoptionen …“ | Dialog *Projektoptionen* der IDE öffnet sich |
| PE11 | Suchpfad auf den Ordner von `Xml.Helpers.pas` ergänzen (auch mit `$(Platform)` bzw. `$(BDS)`), `USE_XML` unter Bedingungen eintragen, „Prüfen“ | Schritt 4 grün; alle vier Schritte erledigt: Die Karte verschwindet; „Neu mit Atlas“ bleibt mit Titel „Neu mit Atlas“ (**Abnahme**) |
| PE12 | Projekt `Fertig` öffnen, dann mit `welcomePage.newFromTemplate` aus | Keine Karte; mit Schalter aus erscheint gar kein Bereich (**Abnahme**) |
| PE13 | `XmlInspector` erneut ohne atlas.json, „Für dieses Projekt nicht mehr fragen“, IDE neu starten | Die Karte bleibt weg, auch nach dem Neustart; `setup.dismissed` in `%LOCALAPPDATA%\Atlas\projects\<Schlüssel>.json` (**Abnahme**) |
| PE14 | Befehlspalette: *Projekt für Atlas einrichten* | Fenster *Atlas-Start* mit der Karte für das aktive Projekt; „nicht mehr fragen“ ist aufgehoben |
| PE15 | Alle Projekte schließen | Karte für das oberste Projekt der Liste „Wieder öffnen“; „Starten“ und „Prüfen“ heißen „Projekt öffnen“ und öffnen es; keine Knöpfe „Neu mit Atlas“ |
| PE16 | „Unit“, „Formular“, „Testklasse“ | Das Erzeugen-Menü über dem Hauptfenster zeigt nur „Vorlagen“: leere Unit und Unit mit Klasse bzw. VCL-Formular bzw. DUnitX-Testklasse; Enter legt eine neue, unbenannte Datei im Projekt an (Unit2 …; Formular mit Designer und `.dfm`, Klasse `TForm2`; Testklasse `TUnit3Tests` mit `RegisterTestFixture`) |
| PE17 | Eigene Code-Vorlage `%APPDATA%\Atlas\Snippets\dm.atlas-snippet` mit `file: unit` und `%Unit%`/`%Name%` im Text | Erscheint unter „Unit“, nicht in der Vervollständigung und nicht im Erzeugen-Menü am Cursor; die neue Datei trägt den Unit-Namen der IDE |
| PE18 | `welcomePage.projectSetup` aus (Optionen oder Schnellschalter) | Bereich weg, Befehl *Projekt für Atlas einrichten* und Tipp „Projekt für Atlas einrichten“ verschwinden; wieder an: ohne Neustart zurück (**Abnahme**) |
| PE19 | `welcomePage.newFromTemplate` aus | Nur die Reihe „Neu mit Atlas“ verschwindet, die Karte bleibt (**Abnahme**) |
| PE20 | Englische IDE; schmale Spalte; 100 %, 150 %, 200 % | „Set up XmlInspector for Atlas“, „Create …“, „Start“, „Check“, „Don’t ask again for this project“, „New with Atlas:“; Knöpfe brechen um, nichts abgeschnitten, Grün in hellem und dunklem Thema lesbar |
| PE21 | Installer: Paket aus dem Release installieren | Ordner `Vorlagen` mit `atlas-existing.json`, `atlas-strict.json`, `atlas-legacy.json` im Installationsordner |
| PE22 | Protokoll (`atlas.log`) nach PE3–PE16 | Nur Zahlen und Kennungen („atlas.json angelegt (Vorlage legacy)“, „1 Projekte, 12 Dateien geprüft, 1 Units fehlen …, 0 davon unsicher“); keine Pfade, keine Unit-, Define- oder Makronamen |
| PE23 | Suchpfad `$(BDSLIB)\$(Platform)\release;$(ProjectDir)\Lib;$(MEINLIB)\src` mit `MEINLIB` unter *Tools › Optionen › Umgebungsvariablen* (Benutzer-Überschreibung), Unit nur in `<MEINLIB>\src` | „Prüfen“: kein Fund; die drei Makros sind aufgelöst (IDE-Variablen und Projektordner vor den Umgebungsvariablen des Prozesses) |
| PE24 | Wie PE23, aber `MEINLIB` gelöscht (weder in der IDE noch im System) | Fund „Unit „…“ nicht gefunden (unsicher, Suchpfad mit unbekanntem Makro $(MEINLIB) übersprungen) – …“ und darunter „Davon unsicher: 1 (…$(MEINLIB)…)“; Schritt 4 grün, wenn es nur unsichere Funde gibt; eine Unit mit `in 'Pfad'` bleibt ein sicherer Fund |
| PE25 | Umgebungsvariable `MEINLIB` nur im System (nicht in der IDE), IDE danach neu gestartet | Wie PE23: Makro über die Umgebung des Prozesses aufgelöst |
| PE26 | Projektgruppe mit drei Projekten öffnen (eines mit fehlender Unit), „Prüfen“ | Alle drei Projekte werden nacheinander geprüft (laufende Sekunden); die Karte zeigt die Summe („1 Units nicht gefunden …, n Dateien geprüft“) und die Funde mit Projekt vorn („App: Unit „…“ nicht gefunden – App\Main.pas, Zeile 3“); jede Projekt-Zusammenfassung (`%LOCALAPPDATA%\Atlas\projects`) enthält nur ihre eigenen Funde |
| PE27 | Wie PE26, danach ein weiteres Projekt zur Gruppe hinzufügen | Karte: „3 von 4 Projekten der Gruppe geprüft“, Schritt 4 offen, Funde der geprüften bleiben sichtbar; nach „Prüfen“ alle vier |
| PE28 | Alle Projekte schließen, oberstes in „Wieder öffnen“ ist die `.groupproj` aus PE26 | Karte der Gruppe mit der Zusammenfassung aus PE26; „Prüfen“ öffnet die Gruppe |

### Weiterarbeiten (#755)

Abweichungen vom Issue: „Gemerkt“ ist ein zweiter Reiter im Bereich „Weiterarbeiten“. Favoriten (#458) haben weder Projekt noch Datei: Sie stehen unter „alle Projekte“, der Ort ist die Unit, der Sprung sucht die Datei im Index-Cache (Projekte und Bibliothek). Ein Klick auf einen eingehenden Commit listet dessen Dateien im Fenster „Atlas-Ergebnisse“, weil #571 keine Commit-Ansicht hat. Bei SVN fehlt der Abschnitt „Neu seit …“ (kein lokaler Stand des Servers). Ohne offene Reiter beim Schließen bleibt der gespeicherte Arbeitsstand stehen; mit `welcomePage.continue` aus zeichnet Atlas nichts auf.

Vorbereitung: Git-Projekt `GitDemo` (mindestens 8 Units) mit Remote `origin` (z. B. ein lokales Bare-Repository `Demo.git`) und Branch `main` mit Upstream; ein zweiter Klon `Kollege` desselben Remotes; ein SVN-Projekt `SvnDemo`; ein Projekt `OhneVcs` ohne Versionsverwaltung; eine Projektgruppe `Gruppe.groupproj` mit zwei Projekten. In zwei Projekten je eine Notiz (#545) und ein benanntes Lesezeichen (#622), dazu ein angehefteter Favorit (#458), z. B. `TStringList.Add`.

| Nr. | Schritte | Erwartet |
|---|---|---|
| WA1 | `Atlas.Tests` bauen und ausführen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TAtlasWelcomeContinueTests`, `TAtlasWelcomeSavedTests`, `TAtlasWelcomeContinueFrameTests`, `TAtlasVcsTests`, `TAtlasVcsIntegrationTests.GitIncomingCommitsOnEditedFiles`, `TAtlasWelcomeSettingsTests` und `TAtlasSettingsPageTests.WelcomeSettingsRoundTrip` grün |
| WA2 | `GitDemo` öffnen, 7 Units in einer bestimmten Reihenfolge öffnen, Reiter per Ziehen umsortieren, in drei Units an verschiedenen Stellen tippen (zuletzt in `Kunde.pas` in `TKunde.Laden`), eine andere Unit aktivieren, Projekt schließen | Willkommensseite: Bereich „Weiterarbeiten“, Reiter „Zuletzt“ mit „**GitDemo** · 7 Reiter“, „gerade eben“ und „Kunde.pas › TKunde.Laden“; Tooltip mit Pfad, Zeitpunkt und „Zuletzt bearbeitet: …\Kunde.pas:<Zeile> › TKunde.Laden“ (**Abnahme**) |
| WA3 | WA2, dann „Fortsetzen“ | Projekt öffnet sich; die 7 Reiter in der Reihenfolge von vorher, in jeder geänderten Unit steht der Cursor an der letzten Änderung, in den übrigen an der Cursorstelle beim Schließen; aktiv ist der zuletzt aktive Reiter (**Abnahme**) |
| WA4 | Wie WA2 mit Projektgruppe `Gruppe.groupproj` (Units aus beiden Projekten), Gruppe schließen | Ein Eintrag „Gruppe · n Reiter“; „Fortsetzen“ öffnet die Gruppe und die Reiter |
| WA5 | WA2, dann eine der 7 Units im Explorer löschen; „Fortsetzen“ | 6 Reiter öffnen sich; unter der Liste und in der Meldungsansicht „Weiterarbeiten: nicht mehr vorhanden, übersprungen: <Datei>“; kein Fehlerdialog (**Abnahme**) |
| WA6 | IDE mit offenem `GitDemo` und Reitern über *Datei › Beenden* schließen, neu starten | Arbeitsstand von `GitDemo` steht oben mit den Reitern vom Beenden |
| WA7 | Alle Reiter schließen, dann das Projekt | Der vorherige Arbeitsstand bleibt unverändert stehen (kein Eintrag „0 Reiter“) |
| WA8 | Im Klon `Kollege` einen Commit „Kunde: Prüfung“ an `Kunde.pas` und einen Commit an einer Datei, die in `GitDemo` nicht offen und nicht geändert war, pushen; in `GitDemo` `git fetch`; Willkommensseite öffnen | Abschnitt „Neu seit deinem letzten Öffnen (origin/main)“ mit genau einer Zeile „<Hash>  Kunde: Prüfung — <Autor> · Kunde.pas“; der zweite Commit fehlt (**Abnahme**) |
| WA9 | Klick auf die Commit-Zeile | Fenster „Atlas-Ergebnisse“ mit „Commit <Hash> – Kunde: Prüfung (<Autor>): n Dateien“, die eigenen Dateien zuerst; Doppelklick öffnet die Datei |
| WA10 | WA8 ohne `git fetch`, `welcomePage.continue.fetch` aus | „Keine neuen Commits zu deinen Dateien.“; kein Netzzugriff (Prozess-Monitor: kein `git fetch`) |
| WA11 | `welcomePage.continue.fetch` an, Remote erreichbar; dann Remote unerreichbar bzw. SSH-Remote ohne Schlüssel | Commit erscheint ohne manuellen Abruf; unerreichbar: Hinweis „Abruf (fetch) fehlgeschlagen, Stand des letzten Abrufs.“, kein Anmeldedialog, die Seite hängt nicht (höchstens 5 s im Hintergrund) |
| WA12 | `SvnDemo` und `OhneVcs` öffnen, Reiter öffnen, schließen | Einträge erscheinen; kein Abschnitt „Neu seit …“, keine Meldung, kein Fehler im Protokoll (**Abnahme**) |
| WA13 | Reiter „Gemerkt“ | Liste mit Notizen und Lesezeichen aus beiden Projekten (Art, Text, Datei:Zeile, Projekt) und dem Favoriten („Favorit“, `TStringList.Add`, Unit, „alle Projekte“); Filter „kunde“ grenzt ein (**Abnahme**) |
| WA14 | Doppelklick bzw. Enter auf eine Notiz, ein Lesezeichen und den Favoriten | Projekt öffnet sich bei Bedarf, die Datei an der Zeile; Lesezeichen über ihren Anker (auch nach verschobenem Code); Favorit springt zur Deklaration in der Unit (Bibliothek aus dem Index-Cache); ohne Cache Meldung „Favorit …: Unit … nicht im Index-Cache gefunden.“ (**Abnahme**) |
| WA15 | Befehlspalette „Letzten Arbeitsstand fortsetzen“ | Wie „Fortsetzen“ für den obersten Eintrag; ohne Arbeitsstand Meldung „Es gibt noch keinen gespeicherten Arbeitsstand.“ |
| WA16 | *Tools › Optionen › Atlas › Willkommensseite*: jeden der fünf Schalter einzeln umstellen (`welcomePage.continue`, `.count` = 2, `.incoming`, `.fetch`, `welcomePage.saved`) | Bereich verschwindet bzw. kommt; 2 Einträge; Abschnitt „Neu seit …“ verschwindet; fetch wie WA11; Reiter „Gemerkt“ verschwindet, „Zuletzt“ bleibt; jeder wirkt ohne Neustart und nur auf seinen Teil (**Abnahme**) |
| WA17 | `welcomePage.continue` aus, Projekt mit Reitern schließen, wieder an | Kein neuer Arbeitsstand für dieses Schließen |
| WA18 | Englische IDE; dunkles und helles Thema; 150 % Skalierung; Fenster *Atlas-Start* | „Continue working“, „Recent“, „Saved“, „7 tabs“, „5 min ago“, „Resume“; Texte und Schaltfläche lesbar und nicht abgeschnitten; im Fenster derselbe Inhalt |
| WA19 | Protokoll (`%LOCALAPPDATA%\Atlas\Logs\atlas.log`) nach WA2–WA16 | Nur Meldungen wie in der Meldungsansicht, ohne Pfade (Dateinamen ohne Ordner); kein Quelltext, keine Betreffzeilen von Commits |

### Schnellaktionen je Projekt (#764)

Abweichungen vom Issue: Die Knopfleiste erscheint wie im Issue-Text nur in der Zeile unter der Maus bzw. mit dem Tastaturfokus (das Mockup #ws10 zeigt sie zur Erklärung dauerhaft in der ersten Zeile). Kein eigener Platz im Atlas-Layout: Die Knöpfe gehören zu den Bereichen „Projekte“ und „Weiterarbeiten“. „Startprofil ▾“ startet immer mit Debugger. Das Ergebnis eines Builds zeigt die vorhandene Marke „Build 0/0/0“ der Zeile, keine zweite Marke.

Vorbereitung: Git-Projekt `GitDemo` (Debug und Release, Win32 und Win64) mit Upstream und Testprojekt `Tests\GitDemo.Tests.dproj` (DUnitX, ein fehlschlagender Test), SVN-Projekt `SvnDemo`, Projekt `OhneVcs` ohne Arbeitskopie, Projektgruppe `Gruppe.groupproj` mit zwei Projekten; alle einmal geöffnet und gebaut, Windows Terminal installiert

| Nr. | Schritte | Erwartet |
|---|---|---|
| SA1 | `Atlas.Tests` bauen und ausführen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TAtlasWelcomeQuickActionsTests`, `TAtlasQuickActionsBarTests`, `TAtlasWelcomeProjectsFrameTests.QuickActionsInRows`, `TAtlasWelcomeContinueFrameTests.QuickActionsInRecent` und die Tests von Einstellungen, Tastenbelegung und Schnellschaltern grün |
| SA2 | Willkommensseite, Maus über die Zeile `GitDemo` in „Projekte“ | Zeile hinterlegt, rechts die Knöpfe „Öffnen und bauen ▾“ (gefüllt), „Tests“, „Startprofil ▾“, „Pull“, „Ordner“, „Konsole“; bei schmaler Spalte in zwei Reihen; die Marken der Zeile bleiben lesbar; Maus weg = Knöpfe weg |
| SA3 | ▾ an „Öffnen und bauen“: „Debug · Win64“ wählen | Projekt öffnet sich (andere Gruppe offen und geändert: Rückfrage der IDE zum Speichern), Knopf zeigt „baut … 1 s“, „… 2 s“ usw.; danach Marke „Build 0/0/0“ in der Zeile; Meldungsansicht wie bei einem Build über das Menü (**Abnahme**) |
| SA4 | SA3, dann „Öffnen und bauen“ ohne ▾ | Baut wieder Debug · Win64 (zuletzt benutzt, in der Auswahl als „(zuletzt)“ fett) |
| SA5 | ▾ „Release · Win32“ mit eingeschaltetem Release-Wächter (#533) und `build.gate = block`, Projekt mit DEBUG in Release | Marke „nicht gebaut“; Tooltip und Meldungsansicht nennen den Grund des Wächters |
| SA6 | „Tests“ an `GitDemo` | Projekt öffnet sich, `GitDemo.Tests` kommt in die Gruppe, wird gebaut und ausgeführt; Knopf „testet … n s“, danach Marke „Tests: 1 fehlgeschlagen“ in der Zeile und Eintrag unter „Testergebnisse“ (#763) (**Abnahme**) |
| SA7 | „Tests“ an einem Projekt ohne Testprojekt; dann mit zwei passenden Testprojekten (`Tests\X.Tests.dproj`, `Test\XTest.dproj`) | Ohne: Marke „Tests nicht gelaufen“, Meldungsansicht nennt die gesuchten Orte und Namen; mit zwei: Auswahl „Testprojekt“ mit beiden |
| SA8 | „Startprofil ▾“ an einem Projekt mit Profilen (#575) | Auswahl mit Überschrift „Startprofil“, aktives Profil „(aktiv)“ fett, „Ohne Startprofil“ zuletzt; Wahl öffnet das Projekt und startet es im Debugger mit dem Profil |
| SA9 | `GitDemo` mit einer geänderten Datei: Maus über „Pull“ | „Pull“ ausgegraut, Tooltip „Erst lokale Änderungen sichern“, Klick tut nichts (**Abnahme**) |
| SA10 | Änderung sichern bzw. verwerfen, Remote hat einen neuen Commit; „Pull“ | Knopf „holt … n s“, danach Marke „aktualisiert“, Branch und ↑/↓ in der Zeile neu; ohne neuen Commit „aktuell“; bei abweichendem Branch „Pull fehlgeschlagen“ und Meldung „Ein abweichender Branch wird nicht zusammengeführt“ (**Abnahme**) |
| SA11 | `SvnDemo`: Knopf heißt „Aktualisieren“; klicken | „aktualisiert … n s“, danach „aktualisiert“ bzw. „aktuell“; `OhneVcs`: Knopf ausgegraut, Tooltip „Keine Arbeitskopie (Git oder SVN)“ |
| SA12 | „Ordner“ und „Konsole“ | Explorer im Projektordner; Windows Terminal im Projektordner; ohne Windows Terminal (bzw. `welcomePage.quickActions.console` leer und `wt.exe` fehlt) `cmd.exe`; `pwsh.exe` eingetragen: PowerShell im Projektordner |
| SA13 | Gruppe `Gruppe.groupproj`: „Öffnen und bauen“ | Gruppe öffnet sich, beide Projekte bauen nacheinander; Marke „Build …“ der Gruppe |
| SA14 | Ohne Maus: Tab bis in „Projekte“, ↓/↑, →/←, Enter, Alt+↓, Esc, Pos1, Kontextmenütaste | Fokusrahmen um Zeile bzw. Knopf; ↓/↑ wählen die Zeile, →/← den Knopf (gesperrte übersprungen), Enter führt aus bzw. öffnet die Zeile ohne Knopf, Alt+↓ öffnet die Auswahl, Esc geht vom Knopf zurück zur Zeile, Kontextmenütaste zeigt das Kontextmenü mit „Öffnen und bauen“, „Bauen mit“, „Tests“, „Starten mit“, „Pull“, „Konsole öffnen“ (**Abnahme**) |
| SA15 | Fokus auf einer Zeile: Strg+B, Strg+T; dann Fokus im Editor: Strg+B, Strg+T | Auf der Willkommensseite baut bzw. testet die gewählte Zeile; im Editor gelten die Tasten der IDE bzw. anderer Experten wie vorher |
| SA16 | *Tools › Optionen › Atlas › Willkommensseite*: Taste „Schnellaktion „Öffnen und bauen““ auf Strg+Umschalt+B; einer Funktion im Editor Strg+B geben | Keine Konfliktmeldung mit Funktionen außerhalb der Willkommensseite (#399); die neue Taste wirkt; die Tastenkürzel-Übersicht (#520) nennt beide Schnellaktionen; Tooltip des Knopfs nennt die Taste |
| SA17 | „Weiterarbeiten“, Reiter „Zuletzt“: Maus über einen Arbeitsstand | Knöpfe links neben „Fortsetzen“, Alter ausgeblendet; Strg+B und „Pull“ wie in „Projekte“; Enter ohne Knopf setzt fort; Reiter „Gemerkt“ hat keine Knöpfe |
| SA18 | *Optionen › Willkommensseite*: „Konsole“ abhaken (`welcomePage.quickActions.items` ohne `console`) | Nur der Knopf „Konsole“ fehlt (auch im Kontextmenü), alle anderen bleiben (**Abnahme**) |
| SA19 | Schalter „Schnellaktionen je Projekt“ aus (auch über die Schnellschalter) | Keine Knöpfe, keine Hinterlegung, kein Tastaturfokus; Strg+B und Strg+T gehören der IDE; Klick in die Zeile wirkt wie vor #764 (**Abnahme**) |
| SA20 | Während „baut …“ an `GitDemo` die Knöpfe einer anderen Zeile ansehen | „Öffnen und bauen“, „Tests“, „Startprofil ▾“ ausgegraut mit „In der IDE läuft schon eine Schnellaktion“; „Pull“, „Ordner“, „Konsole“ gehen |
| SA21 | Englische IDE; dunkles und helles Thema; 150 % Skalierung; Fenster *Atlas-Start* | „Open and build“, „Tests“, „Start profile“, „Pull“/„Update“, „Folder“, „Console“, „building … 12 s“; Knöpfe skaliert, lesbar in beiden Themen |
| SA22 | Karte „Atlas entdecken“ und „Neu in Atlas“ | Tipp „Schnellaktionen je Projekt“ mit Bild und Strg+B; „Neu in Atlas“ nennt die Funktion mit Schalter |
| SA23 | Protokoll (`%LOCALAPPDATA%\Atlas\Logs\atlas.log`) nach SA3–SA20 | Keine Pfade, keine Projektnamen, kein Quelltext; Meldungen mit Pfaden nur in der Meldungsansicht |

## Atlas-Symbol (#751)

| Nr. | Schritte | Erwartet |
|---|---|---|
| SY1 | RAD Studio 12 und 13 starten | Startbildschirm zeigt „Atlas IDE Expert <Version>“ mit Symbol |
| SY2 | *Hilfe › Info* | Atlas mit Symbol, Version und Beschreibung |
| SY3 | Menü *Atlas* öffnen | Symbol an „Projekt-Einstellungen“, „Globale Einstellungen“ und „Optionen…“ |
| SY4 | Statusfeld, Optionsseite *Atlas*, Ergebnisfenster (abgedockt), Fenster der Update-Prüfung | Symbol jeweils vorhanden |
| SY5 | SY3/SY4 bei 100, 150 und 200 % Skalierung (Monitor wechseln) | Symbol scharf und in passender Größe |
| SY6 | *Tools › Optionen › Benutzeroberfläche › IDE-Stil* zwischen hell und dunkel wechseln | Menü, Statusfeld, Optionsseite und Ergebnisfenster wechseln ohne Neustart die Variante |
| SY7 | Explorer: `AtlasServer.exe` und `AtlasSetup.exe`; „Apps und Features“ nach der Installation | Symbol bei beiden Dateien und beim Eintrag „Atlas“ |

## Verdeckte Felder (Feld und lokaler Name gleich)

| Nr. | Schritte | Erwartet |
|---|---|---|
| VF1 | `procedure TKunde.SetzeName(const Name: string)` mit Feld `Name`; Hover und Strg+Klick auf `Name` in `Self.Name := Name` (links und rechts) | Links das Feld `TKunde.Name`, rechts der Parameter |
| VF2 | In einer Methode `P := procedure(Wert: Integer) begin Anzahl := Wert; end;` bei Feldern `Wert` und `Anzahl`: Hover auf `Wert` und `Anzahl` | `Wert` ist der Parameter der anonymen Methode, `Anzahl` das Feld; Strg+Leer zeigt `Wert` als Parameter mit „Verdeckt: Feld TKunde.Wert“ |
| VF3 | Wie VF2 mit `var Anzahl: Integer;` in der anonymen Methode; Verwendungen von `Anzahl` darin suchen | Nur die lokale Variable der anonymen Methode, nicht das Feld |
| VF4 | Parameter `AName` einer Methode in `Name` umbenennen, die auch `Name := 'x'` (Feld) enthält | Abbruch mit „Umbenennen in "Name" würde die Bedeutung ändern: … meinte "Name" danach Parameter Name statt Feld TKunde.Name“; nichts geändert |
| VF5 | Feld `Wert` in `Anzahl` umbenennen, wenn eine Methode eine lokale Variable `Anzahl` hat und dort `Wert` ohne `Self.` verwendet | Abbruch mit Hinweis auf die lokale Variable und die Zeile |
| VF6 | `Name := Name;` in VF1 statt `Self.Name := Name;` | Warnung self-assignment „… Parameter Name verdeckt Feld TKunde.Name …“; erste Korrektur „Self. ergänzen“ ergibt `Self.Name := Name;` |
## Deklaration und Implementierung wechseln (#775)

| Nr. | Schritte | Erwartet |
|---|---|---|
| DI1 | Cursor auf `procedure Run;` im Klassenrumpf, Strg+Umschalt+↓ | Cursor steht auf `Run` in `procedure TFoo.Run;` der Implementierung |
| DI2 | Cursor irgendwo im Rumpf von `TFoo.Run` (auch in einer lokalen Routine), Strg+Umschalt+↑ | Cursor steht auf `Run` in der Deklaration |
| DI3 | Überladene Methode (`Add(Integer)`, `Add(string)`) aus beiden Richtungen | Jeweils die passende Überladung |
| DI4 | Verschachtelte Klasse, generische Klasse, `class operator`, Routine aus dem interface-Teil | Sprung wie bei DI1/DI2 |
| DI5 | Cursor außerhalb einer Methode (z. B. auf einem Feld oder einer Leerzeile), Strg+Umschalt+↑ | Verhalten wie ohne Atlas (Klassennavigation der IDE) |
| DI6 | Optionen › Atlas › Befehle: „Zwischen Deklaration und Implementierung wechseln“ aus, OK | Strg+Umschalt+↑/↓ macht wieder die IDE; Menü *Atlas* › „Deklaration/Implementierung wechseln“ geht weiter |
| DI7 | Taste 1 auf Strg+Alt+D ändern, Taste 2 leeren, OK | Strg+Alt+D wechselt; Strg+Umschalt+↑ macht die IDE, Strg+Umschalt+↓ ebenso |
| DI8 | Menü *Atlas*, Kontextmenü *Atlas* und Befehlspalette „Deklaration/Implementierung wechseln“ | Sprung wie DI1; außerhalb einer Methode Zeile „Am Cursor steht keine Methode …“ in der Meldungsansicht |
## DUnitX-Tests ausführen (#69)

Vorbereitung: RAD Studio mit Atlas-Plugin; Projektgruppe mit einer Anwendung und einem DUnitX-Testprojekt aus der Vorlage von RAD Studio (Hauptdatei mit `DUnitX.TestFramework` und `TDUnitXXMLNUnitFileLogger`), darin eine Fixture mit einem bestehenden Test, einem Test `Assert.AreEqual(0, 1)` und einem `[TestCase]`. Meldungsansicht, Reiter „Atlas“.

| Nr. | Schritte | Erwartet |
|---|---|---|
| TR1 | Testunit öffnen | Hinter `[TestFixture]` die Marke „Tests der Klasse ausführen“, hinter jedem `[Test]`/`[TestCase]` „Test ausführen“; bei einer Fixture ohne Attribut, die `RegisterTestFixture` meldet, hinter der Klassen- bzw. Methodendeklaration |
| TR2 | Klick auf „Test ausführen“ am bestehenden Test (Testprojekt ungebaut, „Vor den Tests bauen“ an) | Das Testprojekt wird gebaut (make), danach „Tests von … laufen (Debug, Win32) …“ und „Tests …: 1 bestanden, 0 fehlgeschlagen …“; kein Konsolenfenster; die Marke zeigt „Test ausführen · bestanden“ in Grün |
| TR3 | Befehlspalette › „Tests ausführen“ | Alle Tests laufen; Zusammenfassung mit Zahlen und Dauer; je Fehlschlag eine Zeile „Test TFixture.Methode fehlgeschlagen: erwartet 0, erhalten 1“, Doppelklick springt zum Methodenkopf im implementation-Teil |
| TR4 | Im Editor auf die Testmethode sehen | Rote Wellenlinie am Methodenkopf, Tooltip mit erwartetem und erhaltenem Wert und Quelle „DUnitX“; Reiter „Atlas-Probleme“ listet den Fehlschlag; die Marke am Test „fehlgeschlagen“ in Rot, an der Fixture ebenso |
| TR5 | Oberhalb der Testmethode Zeilen einfügen | Die Wellenlinie wandert mit; ein Server-Abgleich der Datei lässt sie stehen |
| TR6 | Befehlspalette › „Fehlgeschlagene Tests erneut ausführen“ | Nur der fehlgeschlagene Test läuft (Zusammenfassung „0 bestanden, 1 fehlgeschlagen“); die Ergebnisse der übrigen Tests (Marken) bleiben |
| TR7 | Test reparieren, TR6 wiederholen | Bestanden; Wellenlinie und Eintrag verschwinden; ein weiteres TR6 meldet „Keine fehlgeschlagenen Tests von … bekannt“ |
| TR8 | IDE neu starten, mit einem fehlgeschlagenen Test vorher, dann TR6 | Es läuft genau der zuletzt fehlgeschlagene Test (aus der Projekt-Zusammenfassung) |
| TR9 | `%LOCALAPPDATA%\Atlas\projects\<Schlüssel>.json` des Testprojekts und der Projektgruppe ansehen | Abschnitt `tests` mit `passed`, `failed`, `errors`, `skipped`, `durationMs`, `at` (UTC), Konfiguration, Plattform und `failures` mit Test, Meldung, Datei und Zeile (1-basiert) |
| TR10 | Optionen › Atlas › Compiler › „Vor den Tests bauen“ aus, Test-EXE vorhanden | Kein Build; die vorhandene EXE läuft sofort |
| TR11 | Wie TR10, aber Test-EXE gelöscht | Meldung „Test-EXE von … fehlt (…)“, nichts läuft |
| TR12 | Testprojekt nur mit Plattform Win64 (Win32 entfernt), „Tests ausführen“ | Gebaut und gestartet wird Win64; Meldung nennt Win64 |
| TR13 | Aktive Plattform Linux64 bzw. Android | Meldung „… ist für Linux64 eingestellt; Atlas startet nur Windows-Tests …“, nichts läuft |
| TR14 | „Tests nach erfolgreichem Build automatisch ausführen“ an, Testprojekt mit Strg+F9 bauen | Nach dem Build laufen die Tests ohne erneuten Build; nach einer Hintergrundprüfung (#548) und nach `build_project` nicht |
| TR15 | Wie TR14 mit „Build nur ohne Warnungen und Hinweise …“ an und einer Warnung im Testprojekt | Keine Tests nach dem Build; ohne Warnung laufen sie |
| TR16 | Projektgruppe mit zwei Testprojekten, aktiv ist die Anwendung, Palette › „Tests ausführen“ | Auswahl „Testprojekt wählen“ mit A und B; nach der Wahl laufen dessen Tests; beim nächsten Mal ohne Frage (#585); mit aktivem Testprojekt läuft dieses |
| TR17 | Projektgruppe ohne Testprojekt | Meldung „Kein DUnitX-Testprojekt in der Projektgruppe …“ |
| TR18 | Während eines Laufs noch einmal „Tests ausführen“ | Meldung „Es läuft schon ein Testlauf.“; die Marken zeigen „Tests laufen …“ |
| TR19 | Testprogramm ohne XML-Logger (Logger-Zeile auskommentiert) | Meldung „… lieferte keinen Bericht (Exitcode …). Letzte Ausgabe:“ mit den letzten Zeilen der Konsolenausgabe |
| TR20 | Test mit `Sleep` über das Zeitlimit (600 s) bzw. IDE während eines Laufs schließen | Abbruch mit „nach 600 s abgebrochen“; beim Schließen endet die Test-EXE mit, die IDE hängt nicht |
| TR21 | Schnellschalter „Code Lens „Test ausführen““ aus | Marken verschwinden (auch „Debuggen“, #585); Befehle bleiben |
| TR22 | Schnellschalter „DUnitX-Tests ausführen“ aus | Marken und beide Befehle verschwinden, kein Lauf nach dem Build |
| TR23 | Claude Code: „Führe die Tests über run_tests aus“ (vorhandene EXE) | JSON mit `result` `failed`, Zahlen und je Fehlschlag Name, `expected`/`actual`, Datei und Zeile; kein Compiler läuft; die Projekt-Zusammenfassung ändert sich nicht |
| TR24 | `run_tests` mit `build: true` ohne laufende IDE bzw. mit `tests: ["Unit.TFixture.Methode"]` | Ohne IDE der Grund wie bei `build_project`, keine Tests; mit Filter nur dieser Test |

## Einzelnen Test debuggen (#585)

Vorbereitung: wie bei #69, Projektgruppe mit der Anwendung (aktiv) und dem Testprojekt `Rechner.Tests`; in `Rechner.Tests.dproj` unter *Start › Parameter* den Parameter `-cfg test.ini` eintragen. Testunit mit `[Test] Addiert` (erste Anweisung in einer Zeile nach `var`-Abschnitt und lokaler Funktion), `[Test]` mit zwei `[TestCase('Klein', …)]`/`[TestCase('Gross', …)]` in eigenen Zeilen und einem Test mit `Assert.AreEqual(0, 1)`. Meldungsansicht, Reiter „Atlas“. Optionen › Atlas › Debuggen: beide Schalter an.

| Nr. | Schritte | Erwartet |
|---|---|---|
| TD1 | Testunit öffnen | Hinter `[TestFixture]` und jedem `[Test]` neben „Test ausführen“ die Marke „Debuggen“; hinter jedem `[TestCase]` in eigener Zeile „Fall ausführen“ und „Debuggen“, die Marke des Tests mit den Fällen steht dann hinter `procedure` |
| TD2 | Klick auf „Debuggen“ an `Addiert` | Testprojekt wird gebaut; Meldungen „Einmaliger Haltepunkt in Zeile …“ und „Rechner.Tests startet TRechnerTests.Addiert im Debugger (Debug, Win32)“; das Testprojekt wird aktiv; der Debugger hält auf der ersten Anweisung von `Addiert` (nicht in der lokalen Funktion); der Haltepunkt ist nach dem Halt verschwunden (Akzeptanz: startet nur diesen Test und hält in der ersten Zeile) |
| TD3 | F9 bis zum Ende | Programm endet ohne „Press Enter“; Meldung „Debuggen von Rechner.Tests beendet; aktives Projekt und Startparameter wie vorher“; die Anwendung ist wieder aktives Projekt, *Start › Parameter* von `Rechner.Tests` zeigt wieder `-cfg test.ini`; die Marke an `Addiert` zeigt „bestanden“, die übrigen Marken bleiben, wie sie waren (Akzeptanz: Projekt und Parameter wiederhergestellt) |
| TD4 | Während TD2 hält: *Start › Parameter* ansehen | `-cfg test.ini "--run:Rechner.Tests.TRechnerTests.Addiert" …` bzw. ohne Anführungszeichen, dazu `--exitbehavior:Continue` und `--xmlfile:…atlas-debug-….xml` |
| TD5 | „Debuggen“ am Test mit den Fällen (Marke hinter `procedure`) | Beide Fälle laufen (`--run:…Summe.Klein,…Summe.Gross`), Halt in der ersten Zeile beim ersten Fall; nach F9 hält er nicht noch einmal (Akzeptanz: [TestCase] führt alle Fälle aus) |
| TD6 | „Debuggen“ bzw. „Fall ausführen“ an `[TestCase('Gross', …)]` | Nur dieser Fall läuft (Meldung nennt `TRechnerTests.Summe.Gross`; Zusammenfassung 1 Test) (Akzeptanz: einzelne Fälle wählbar) |
| TD7 | „Debuggen“ an `[TestFixture]` | Alle Tests der Fixture laufen im Debugger; kein Haltepunkt |
| TD8 | Cursor in den Rumpf des fehlschlagenden Tests, Befehlspalette › „Test am Cursor debuggen“ | Wie TD2 für diesen Test; nach dem Ende rote Wellenlinie und „fehlgeschlagen“ an der Marke |
| TD9 | Rechtsklick in der Testmethode › „Test ausführen“ | Läuft ohne Debugger wie die Code Lens (#69), Ergebnis in Meldungsansicht und an der Marke |
| TD10 | Cursor außerhalb eines Tests (z. B. in `[Setup]`), „Test am Cursor debuggen“ | Meldung „Am Cursor steht kein DUnitX-Test …“, nichts startet |
| TD11 | Optionen › Atlas › Debuggen › „Beim Test-Debuggen am Anfang der Methode anhalten“ aus, TD2 | Kein Haltepunkt, das Programm läuft durch; Ergebnis wie TD3 |
| TD12 | Eigenen Haltepunkt auf die erste Anweisung von `Addiert` setzen, TD2 | Atlas setzt keinen zweiten; nach dem Lauf steht der eigene Haltepunkt noch da |
| TD13 | Während des Haltens in TD2 *Start › Parameter* von `Rechner.Tests` auf `-anders` ändern, dann F9 | Meldung „… Startparameter wurden während des Laufs geändert und bleiben“; *Start › Parameter* zeigt `-anders` |
| TD14 | Während des Haltens in TD2 die IDE beenden (Programm zurücksetzen, ohne Speichern schließen), neu starten, `Rechner.Tests` aktiv machen | Meldung „Vorübergehende Startparameter von Rechner.Tests.dproj zurückgestellt“; *Start › Parameter* wieder `-cfg test.ini` (bei ausgeschalteten Startprofilen erst beim nächsten Test-Debuggen) |
| TD15 | Startprofil „Demo“ (#575) für `Rechner.Tests` aktiv, TD2 und TD3 | Während des Laufs Arbeitsordner und Umgebung des Profils, Parameter vorübergehend; danach wieder die des Profils, Statusfeld unverändert |
| TD16 | Zweites Testprojekt `Rechner.Tests2` in der Gruppe, das dieselbe Testunit enthält; TD2 | Auswahl „Testprojekt wählen“ mit beiden; nach der Wahl läuft es; ein zweites TD2 fragt nicht; nach Entfernen oder Hinzufügen eines Testprojekts fragt Atlas wieder |
| TD17 | Während TD2 noch einmal „Debuggen“ bzw. „Tests ausführen“ | Meldung „Es läuft schon ein Test im Debugger.“ bzw. „Es läuft schon ein Testlauf.“; die Marke „Debuggen“ ist während des Laufs ausgeblendet |
| TD18 | Anwendung läuft im Debugger, „Debuggen“ an einem Test | Meldung „Der Debugger läuft schon; erst beenden.“; nichts ändert sich |
| TD19 | Fehler im Testprojekt einbauen, TD2 | Meldung, dass der Build fehlschlug; aktives Projekt und Startparameter unverändert, keine Datei `atlas-debug-*.xml` im Temp-Ordner |
| TD20 | Schnellschalter „Test debuggen“ aus | Ohne Neustart: Marken „Debuggen“, Befehl „Test am Cursor debuggen“, Eintrag im Kontextmenü (meldet „ausgeschaltet“) und Tipp „Einzelnen Test debuggen“ verschwinden; „Test ausführen“ bleibt |
| TD21 | „Code Lens „Test ausführen““ (`codeLens.tests`) aus | Keine Marken, weder „Test ausführen“ noch „Debuggen“ (Akzeptanz: mit codeLens.tests aus ist die Funktion in der Code Lens aus); Befehle und Kontextmenü gelten weiter nach „Test debuggen“ |
| TD22 | „DUnitX-Tests ausführen“ aus | Auch „Test debuggen“ ist aus: keine Marken, keine Befehle, Kontextmenü meldet „ausgeschaltet“ |
| TD23 | Testprojekt nur für Win64, aktive Plattform der Anwendung Win32, TD2 | Gebaut und gestartet wird Win64 des Testprojekts |

## DUnitX-Testgerüst (#274)

Voraussetzung: Projektgruppe mit einem DUnitX-Testprojekt (`.dpr` mit `uses DUnitX.TestFramework`).

| Nr. | Schritte | Erwartet |
|---|---|---|
| TG1 | Cursor auf `TKunde = class` in `Kunden.pas`, Code-Aktionen (Strg+.) | Eintrag „DUnitX-Testunit für TKunde anlegen“ |
| TG2 | Eintrag wählen | `Kunden.Tests.pas` im Ordner des Testprojekts angelegt und geöffnet; `[TestFixture] TKundeTests` mit `FSubject`, `[Setup]`, `[TearDown]` und einem `[Test]` je public-Methode (überladene als `TestX2`), jeder Test mit `Assert.Fail` |
| TG3 | Testprojekt ist geladen: Projektverwaltung und `.dpr` ansehen | Neue Unit steht im Testprojekt (nicht im aktiven Projekt), `uses` der `.dpr` enthält sie |
| TG4 | Testprojekt ist nicht geladen: `.dpr` und `.dproj` im Editor ansehen | `Kunden.Tests in 'Kunden.Tests.pas'` in der `.dpr`, `DCCReference` in der `.dproj`; keine `.dpr` wurde im Editor geöffnet |
| TG5 | Testprojekt übersetzen | Übersetzt ohne Fehler, Warnungen und Hinweise; die Tests schlagen mit „Test für … fehlt noch“ fehl |
| TG6 | Klasse mit `constructor Create(AName: string)` | Setup enthält nur den Kommentar „braucht Argumente im Konstruktor“ |
| TG7 | atlas.json `"testUnits": {"pattern": "Test.{unit}", "folder": "Tests/Unit"}`, TG1 | Neue Unit `Test.Kunden.pas` unter `Tests\Unit`, relativer Pfad in `.dpr` und `.dproj` |
| TG8 | Projektgruppe ohne Testprojekt, TG1 | Kein Eintrag zum Anlegen |
| TG9 | Testunit existiert schon, Code-Aktionen auf der Klasse | „Zur Testunit Kunden.Tests wechseln“ öffnet sie |

## Zwischen Unit und Testunit wechseln (#189)

Voraussetzung wie bei #274; Server läuft.

| Nr. | Schritte | Erwartet |
|---|---|---|
| TU1 | `Kunden.pas` öffnen, Testunit fehlt | Hinter `unit Kunden;` steht die Marke „+ Testunit Kunden.Tests anlegen“ |
| TU2 | Marke anklicken | Testunit wie TG2 angelegt, in `.dpr`/`.dproj` (bzw. im geladenen Testprojekt) eingetragen und geöffnet |
| TU3 | Zurück zu `Kunden.pas` | Marke zeigt nach kurzer Zeit „→ Testunit Kunden.Tests“; Klick öffnet sie |
| TU4 | In `Kunden.Tests.pas` | Marke „→ Unit Kunden“; Klick öffnet `Kunden.pas` |
| TU5 | *Atlas › Zwischen Unit und Testunit wechseln*, Kontextmenü *Atlas*, Befehlspalette „Zwischen Unit und Testunit wechseln“ und eingestelltes Tastenkürzel | Gleicher Wechsel wie per Marke; ohne Testprojekt Meldung „Keine Testunit: …“ |
| TU6 | Optionen › Atlas: „Code Lens „zur Testunit““ aus | Marke verschwindet ohne Neustart; Befehl, Menü und Taste wechseln weiter |
| TU7 | Programmdatei (`.dpr`) oder Datei mit Kommentar vor `unit` | Keine Marke in der `.dpr`; bei Kommentarkopf steht sie hinter der Zeile `unit …;` |
| TU8 | Kein Compiler, kein Build: TU2–TU4 direkt nach dem Öffnen des Projekts | Wechsel funktioniert in beide Richtungen |

## Code-Metriken (#66)

Voraussetzung: Server läuft, Beispielprojekt mit `Setup\Beispiele\Entdecken.pas` bzw. eigenes Projekt geöffnet.

| Nr. | Schritte | Erwartet |
|---|---|---|
| MX1 | `Entdecken.pas` öffnen, kurz warten | Hinter `function Gesamtpreis(…): Currency;` steht die Marke „9 Zeilen · Tiefe 1 · zyklomatisch 2 · kognitiv 1 · 3 Parameter“, hinter jedem anderen Methodenkopf eine eigene Marke; keine Marke im `interface`-Teil |
| MX2 | Im Rumpf von `Gesamtpreis` ein `if A then if B then X;` ergänzen, eine Sekunde warten | Marke zeigt nach der Tipp-Pause die neuen Werte; während des Tippens bleibt sie an ihrem Kopf (keine Marke an fremden Zeilen) |
| MX3 | Methode mit acht Parametern schreiben | Marke gelb, „8 Parameter (> 6)“; im Editor ein Hinweis `metric-parameter-count` am Methodennamen |
| MX4 | Zeile `// lsp-ignore: metric-parameter-count` über den Kopf aus MX3 | Hinweis verschwindet; die Marke bleibt (Information) |
| MX5 | atlas.json: `"rules": {"metric-parameter-count": {"max": 10}}` speichern | Nach höchstens 30 s ist die Marke aus MX3 nicht mehr gelb, der Hinweis bleibt weg auch ohne Kommentar |
| MX6 | atlas.json: `"metric-parameter-count": {"max": 0}` | Problem in atlas.json: „"max" muss eine ganze Zahl ab 1 sein“; es gilt die Vorgabe 6 |
| MX7 | Optionen › Atlas › Editor: „Code Lens mit Code-Metriken hinter dem Methodenkopf“ aus | Marken verschwinden ohne Neustart; Hinweise `metric-*` bleiben (Regeln einzeln abschaltbar) |
| MX8 | Schnellschalter „Code-Metriken“ bzw. „Alles aus für diese Sitzung“ | Marken verschwinden; „Alles wieder an“ bringt sie zurück |
| MX9 | Befehlspalette „Metrikbericht des Projekts“ | Meldung „Metrikbericht wird erstellt …“, danach öffnet `%LOCALAPPDATA%\Atlas\Berichte\Metriken-<Projekt>.md` mit Überschrift „# Code-Metriken: <Projekt>“, Tabelle der Kennzahlen, „Über einem Grenzwert“, „Komplexeste Methoden“ und „Dateien“ |
| MX10 | MX9 ohne geöffnetes Projekt | Meldung „Metrikbericht: kein aktives Projekt.“ |
| MX11 | Projekt bauen (Strg+F9), danach `%LOCALAPPDATA%\Atlas\projects\<Schlüssel>.json` ansehen | Abschnitt `metrics` mit `at` (Zeitpunkt des Builds), `files`, `methods`, `overLimits`, `average`, `maximum`, `exceeded`; nach einer Hintergrundprüfung (#548) ändert er sich nicht |
| MX12 | Großes Projekt (mehrere hundert Units): erster Build, sofort danach tippen | Editor bleibt flüssig; Code Lens kann bis zum Ende der Zusammenfassung ausbleiben und erscheint danach |
| MX13 | `AtlasServer --check <Projekt> --metrics` und `--metrics --format json` | Markdown bzw. JSON mit `"format": 1`, `limits`, `summary`, `files`; Exitcode 0; `--format sarif` mit `--metrics` endet mit Fehler |
| MX14 | Claude Code: Werkzeug `get_metrics` ohne und mit `file` | Bericht des Projekts bzw. Werte der Datei, Grenzwerte aus atlas.json |
| MX15 | Optionen › Atlas › Editor: „Befehl „Metrikbericht des Projekts“ in der Befehlspalette“ aus (oder Schnellschalter „Metrikbericht“) | Befehl verschwindet ohne Neustart aus der Befehlspalette, der Tipp „Metrikbericht des Projekts“ erscheint nicht mehr; nach einem Build steht der Abschnitt `metrics` weiter in der Projekt-Zusammenfassung; wieder an: Befehl ist zurück |

## TODO-Übersicht (#68)

Voraussetzung: Server läuft, eigenes Projekt geöffnet. In einer Unit des Projekts stehen `// TODO 2 -oMarco -cGUI : Fokus setzen`, `{ TODO 1 -cExport : CSV mit BOM }`, `// FIXME Rabatt`, `{ DONE -oAnna : Index }` und `s := '// TODO kein Kommentar';`; eine Unit im Projektordner, die nicht zum Projekt gehört, enthält `// TODO fremd`.

| Nr. | Schritte | Erwartet |
|---|---|---|
| TD1 | Befehlspalette „TODOs des Projekts“ | Ergebnisfenster „TODOs in <Projekt>: 3“, nach Unit gruppiert: „TODO 2 [GUI, Marco]: Fokus setzen“, „TODO 1 [Export]: CSV mit BOM“, „FIXME: Rabatt“; kein DONE-Eintrag, nichts aus der Zeichenkette, nichts aus der fremden Unit |
| TD2 | Doppelklick auf einen Eintrag aus TD1 | Editor öffnet die Unit an der Zeile und Spalte des Kommentars |
| TD3 | TD1 in einem Projekt ohne TODO-Kommentare | Meldung „Keine offenen TODOs in <Projekt>.“ |
| TD4 | TD1 ohne geöffnetes Projekt | Meldung „TODOs des Projekts: kein aktives Projekt.“ |
| TD5 | Projekt bauen und sofort TD1 | Entweder die Liste oder „… Der Atlas-Server ist gerade beschäftigt …“; ein zweiter Versuch nach kurzer Zeit zeigt die Liste |
| TD6 | atlas.json: `"rules": {"todo-comment": "hint"}` speichern | Nach höchstens 30 s Hinweise `todo-comment` an den drei offenen Kommentaren mit demselben Text wie in TD1; keiner am DONE-Eintrag |
| TD7 | Zeile `// lsp-ignore: todo-comment` über einen der Kommentare aus TD6 | Dieser Hinweis verschwindet; die Liste aus TD1 zeigt den Eintrag weiter |
| TD8 | atlas.json: `"todo-comment": {"severity": "off", "keywords": ["TODO", "FIXME", "HACK"]}`, ein `// HACK Umweg` ergänzen, TD1 | Liste enthält „HACK: Umweg“; keine Hinweise im Editor |
| TD9 | atlas.json: `"todo-comment": {"keywords": ["TO-DO", "DONE"]}` | Probleme in atlas.json: „Eine Marke besteht nur aus Buchstaben und ist nicht DONE, z. B. "HACK"“; es gelten die übrigen bzw. die Vorgabe-Marken |
| TD10 | Projekt bauen (Strg+F9), danach `%LOCALAPPDATA%\Atlas\projects\<Schlüssel>.json` ansehen | Neben `metrics` ein Abschnitt `todos` mit `at` (Zeitpunkt des Builds), `files`, `open` (3), `done` (1) und `keywords` mit den offenen Einträgen je Marke (`{"FIXME": 1, "TODO": 2}`) |
| TD11 | `AtlasServer --check <Projekt> --todos` und `--todos --format json` | Markdown „# TODOs: <Projekt>“ mit „Nach Kategorie“, „Nach Person“ und einer Tabelle je Unit bzw. JSON mit `"format": 1`, `summary`, `files`; Exitcode 0; `--format sarif` oder `--metrics` zusammen mit `--todos` endet mit Fehler |
| TD12 | Claude Code: Werkzeug `get_todos` ohne Argumente, mit `owner: "Marco"`, mit `includeDone: true`, mit `file` | Markdown über das Projekt; nur Marcos Einträge; zusätzlich der DONE-Eintrag als erledigt; nur die Einträge der Datei |
| TD13 | Befehlspalette „TODOs des Projekts filtern …“ nach TD1 | Dialog „TODOs filtern“ mit Kategorie (-c), Person (-o), Unit und Marke; die Auswahllisten enthalten GUI und Export, Marco, die Units mit Einträgen bzw. FIXME und TODO; „Erledigte zeigen (DONE)“ aus |
| TD14 | In TD13 Kategorie „GUI“ wählen, Enter | Ergebnisfenster „TODOs in <Projekt> (-cGUI): 1“ mit „TODO 2 [GUI, Marco]: Fokus setzen“ |
| TD15 | TD13 erneut öffnen: Kategorie steht noch auf „GUI“ (Filter der Sitzung); Kategorie leeren, Person „marco“ (klein) tippen, „Anzeigen“ | Titel „TODOs in <Projekt> (-omarco): 1“; Groß-/Kleinschreibung egal |
| TD16 | TD13 mit „Erledigte zeigen (DONE)“ und Person „Anna“ | Liste enthält „DONE [Anna]: Index“ |
| TD17 | TD13 mit Unit, die es nicht gibt (z. B. „Gibtsnicht“) | Meldung „Keine TODOs in <Projekt> passen zum Filter (Gibtsnicht).“ |
| TD18 | TD13, „Zurücksetzen“, „Anzeigen“ | Alle Felder leer; Liste wie TD1 mit Titel ohne Klammer |
| TD19 | Optionen › Atlas › Editor: „Befehl „TODOs des Projekts“ in der Befehlspalette“ aus (oder Schnellschalter „TODO-Liste“) | Beide Befehle aus TD1 und TD13 verschwinden ohne Neustart aus der Befehlspalette, die Tipps „TODOs des Projekts“ und „TODOs filtern“ erscheinen nicht mehr; Hinweise der Regel `todo-comment`, `get_todos` und der Abschnitt `todos` nach einem Build (TD10) bleiben; „Alles aus für diese Sitzung“ lässt die Befehle stehen |

## Baseline für Altprojekte (#97)

Voraussetzung: Server läuft, eigenes Projekt geöffnet, die Regel `empty-except` (oder eine andere, die im Projekt Treffer hat) ist an. In `Kasse.pas` steht in `TKasse.Buchen` und in `TKasse.Storno` je dieselbe Zeile mit einem Treffer (z. B. `except end;`).

| Nr. | Schritte | Erwartet |
|---|---|---|
| BL1 | Befehlspalette „Baseline des Projekts aktualisieren“ ohne vorhandene Baseline | Meldung „Baseline wird aktualisiert …“, danach im Meldungsfenster „Baseline geschrieben: <Ordner>\atlas-baseline.json (n Treffer in m Dateien; n neu, 0 entfernt, 0 unverändert)“; die Treffer im Editor verschwinden nach kurzer Zeit |
| BL2 | `atlas-baseline.json` ansehen | Je Eintrag `path`, `rule`, `fingerprint`, `count`, `routine` (z. B. `TKasse.Buchen`; außerhalb einer Routine `implementation` o. ä.) und `context` |
| BL3 | Die Zeile in `TKasse.Buchen` neu einrücken und eine Leerzeile darüber einfügen | Kein Treffer erscheint |
| BL4 | `TKasse.Buchen` in `TKasse.Verbuchen` umbenennen (Deklaration und Rumpf) | Kein Treffer erscheint |
| BL5 | Dieselbe Zeile ein drittes Mal in eine neue Methode `TKasse.Neu` kopieren | Nur dieser Treffer erscheint (gleiche Zeile in anderer Routine ist neu) |
| BL6 | Die Zeile aus `TKasse.Storno` in eine andere Methode verschieben | Der verschobene Treffer erscheint |
| BL7 | Eine Unit mit Treffern aus der Baseline umbenennen (Datei und Projekt), BL1 | Vorher Rückfrage „Die Baseline enthält n Einträge ohne Datei …“ mit dem alten Pfad und der Trefferzahl; „Nein“ bricht ab, nichts wird geschrieben. Mit „Ja“: Meldungsfenster nennt zuerst „Baseline: n Einträge ohne Datei entfernt …“ mit dem Pfad, dann die Zähler |
| BL8 | Eine Baseline einer älteren Atlas-Fassung (Einträge ohne `routine`) ins Projekt legen | Die bekannten Treffer bleiben ausgeblendet. BL1: zusätzlich „Baseline: n Einträge der älteren Baseline um die Routine ergänzt.“; die Datei hat danach `routine` und `context` |
| BL9 | `// lsp-ignore: empty-except` über eine Zeile, deren Treffer in der Baseline steht | Kein `unused-suppression` an diesem Kommentar |
| BL10 | `AtlasServer --check <Projekt> --update-baseline` nach BL7 (ohne Plugin) | stderr: zuerst „n Einträge ohne Datei werden entfernt …“ mit Pfaden, dann „Baseline geschrieben: … (… neu, … entfernt, … unverändert)“; Exitcode 0 |
| BL11 | `AtlasServer --check <Projekt> --format sarif` mit Baseline und einem neuen Treffer | Jedes Ergebnis hat `partialFingerprints` mit `atlasBaseline/v1` und `atlasContext/v1`; der neue Treffer `baselineState` `new`, bekannte `unchanged` mit `suppressions` (`external`); ein Eintrag ohne Treffer `absent`; Exitcode zählt nur den neuen Treffer |
| BL12 | BL11 ohne Baseline | `partialFingerprints` vorhanden, kein `baselineState`, keine `suppressions` |
| BL13 | Projekt bauen (Strg+F9), danach `%LOCALAPPDATA%\Atlas\projects\<Schlüssel>.json` ansehen | Abschnitt `baseline` mit `at`, `exists` true, `valid` true, `entries`, `hits`, `orphaned`; nach BL1 zusätzlich `updated`, `added`, `removed`. Baseline löschen und bauen: `exists` false, `updated` bleibt |
| BL14 | BL1 ohne geöffnetes Projekt bzw. direkt nach einem Build | „Baseline aktualisieren: kein aktives Projekt.“ bzw. ggf. „… Der Atlas-Server ist gerade beschäftigt …“ |
| BL15 | VS Code oder anderer Editor: `workspace/executeCommand` `atlas.updateBaseline` mit der URI des Projekts | Antwort mit `file`, `total`, `files`, `added`, `removed`, `unchanged`, `completed`, `orphaned`; der Befehl steht in `executeCommandProvider` |
| BL16 | Optionen › Atlas › Editor: „Befehl „Baseline des Projekts aktualisieren“ in der Befehlspalette“ aus (oder Schnellschalter „Baseline aktualisieren“) | Der Befehl und sein Tipp verschwinden ohne Neustart; die Baseline blendet weiter aus, BL13 schreibt weiter; „Alles aus für diese Sitzung“ lässt den Befehl stehen |

## Projektdatei .atlas (#486)

Voraussetzung: Git-Projekt `C:\Repo\App\Kasse.dproj` (Repository-Wurzel `C:\Repo`), Server läuft. Persönliche Code-Vorlagen in `%APPDATA%\Atlas\Snippets` mit einer Vorlage `try`.

| Nr. | Schritte | Erwartet |
|---|---|---|
| PD1 | Befehlspalette „Projektdatei .atlas öffnen“ ohne vorhandene Datei | `C:\Repo\App\.atlas` entsteht (UTF-8 ohne BOM) mit `"version": 1`, leeren Abschnitten und Beispielen als Kommentar und ist im Editor offen; Meldungsansicht „Projektdatei .atlas angelegt …“; keine weitere Meldung |
| PD2 | In `.atlas` `"naming": {"field": "F"}` und `"snippets": "..\\Vorlagen"` eintragen, speichern; in `C:\Repo\Vorlagen` eine Vorlage `try` mit anderem Text ablegen | Nach höchstens 2 s gilt die Datei; *Tools › Optionen › Atlas › Projektdatei* zeigt „naming.field: "F" (aus .atlas)“ und „snippets: ..\Vorlagen (aus .atlas)“, der Reiter *Einfügen* „Code-Vorlagen des Projekts: ..\Vorlagen (aus .atlas, …)“; die Vervollständigung bietet für `try` die Vorlage des Projekts an |
| PD3 | `.atlas` löschen, im Ordner `C:\Repo` neu anlegen (gleicher Inhalt) | Gilt weiter (Wurzel des Repositorys); `"snippets": "..\\Vorlagen"` wird jetzt als „führt aus dem Projekt heraus“ gemeldet und ignoriert |
| PD4 | In `.atlas` eine schließende Klammer löschen, speichern | Meldungsansicht einmal „Projektdatei .atlas ist fehlerhaft …; Atlas nutzt die persönlichen Einstellungen.“, kein Dialog, kein Absturz; der Reiter zeigt „Die Datei ist fehlerhaft …“; Projekt-Vorlagen fallen weg. Nach dem Reparieren gilt die Datei wieder ohne Meldung |
| PD5 | `"token": "abc"`, `"ci": {"url": "https://marco:pw@ci.firma.de", "job": "kasse"}` und ein Startprofil mit `"environment": {"DB_PASSWORD": "x"}` eintragen | Je eine Meldung „… sieht nach Zugangsdaten aus und wird ignoriert …“ (`token`, `ci.url`, `startProfiles[…].environment.DB_PASSWORD`); das Startprofil fehlt ganz, der Reiter nennt „3 Einträge werden ignoriert“ |
| PD6 | `"snippets": "C:\\Vorlagen"` und ein Startprofil mit `"host": "C:\\Tools\\host.exe"` bzw. `"parameters": "-db D:\\Daten\\x.fdb"` | Meldungen „… enthält einen absoluten Pfad …“; Werte ignoriert |
| PD7 | Unbekannter Schlüssel `"nameing": {}` und `"sqlTargets": "TQuery.SQL"` | Meldungen „Unbekannter Eintrag "nameing" …“ und „"sqlTargets" hat den falschen Typ …“; übrige Werte gelten |
| PD8 | Zwei Projekte einer Gruppe, nur eines mit `.atlas`; aktives Projekt wechseln | Der Reiter *Projektdatei* zeigt nach dem Wechsel die Datei des aktiven Projekts bzw. „Das aktive Projekt hat keine .atlas …“ |
| PD9 | Optionen › Atlas › Projektdatei: Schalter aus (oder Schnellschalter „Projektdatei .atlas“) | Ohne Neustart: Befehl und Tipp verschwinden, die Projekt-Vorlagen fallen weg, der Reiter zeigt „Ausgeschaltet …“; keine Meldungen mehr zu `.atlas`. Wieder an: Datei gilt, Meldungen erscheinen einmal neu |
| PD10 | `atlas.json` im Projekt mit `"token": "x"`, `"exclude": ["C:\\Fremd\\**", "/Generated/**"]` und `"testUnits": {"folder": "..\\Tests"}` | Warnungen in `atlas.json` an `token` und am absoluten Ausschluss („… gilt für alle im Team …“); `/Generated/**` und `..\Tests` gelten ohne Meldung |
| PD11 | Dasselbe in `%APPDATA%\Atlas\settings.json` (global) mit einem absoluten `exclude` | Keine Warnung: die globale Datei ist persönlich |
| PD12 | Abgesichert starten (wie AS5), dann Schnellschalter „Projektdatei .atlas“ an | Zuerst ist der Schalter wie alle aus (keine Meldungen zu `.atlas`, Befehl fehlt); danach gilt die Datei ohne Neustart, Befehl wieder in der Palette |

## Startprofile (#575)

Voraussetzung: Git-Projekt `C:\Repo\App\Zeige.dproj` (Konsolenprogramm, schreibt `ParamStr(1)`, `GetCurrentDir` und `GetEnvironmentVariable('MODUS')` in `C:\Temp\zeige.txt`), Projektdatei `.atlas` an, Startprofile und „Startprofil in der Statusleiste“ an. In `C:\Repo\App\.atlas`:

```jsonc
"startProfiles": [
  {"name": "Demo", "parameters": "-demo", "workingDir": "Daten", "environment": {"MODUS": "demo"}},
  {"name": "Kunde", "parameters": "-kunde 7"}
]
```

| Nr. | Schritte | Erwartet |
|---|---|---|
| SP1 | Befehlspalette „Startprofil: …“ | Auswahl mit „Demo“ und „Kunde“ (Pfad „Team (.atlas)“, Beschreibung mit Parametern, Arbeitsordner und Umgebung), darunter „Aktuelle Startoptionen als persönliches Profil speichern …“, „Persönliche Startprofile bearbeiten“, „Gemeinsame Startprofile in .atlas bearbeiten“; kein „Kein Startprofil“, solange keines aktiv ist |
| SP2 | „Demo“ wählen, dann F9 | Meldungsansicht „Atlas: Startprofil „Demo“ gesetzt (…)“; *Start › Parameter* zeigt `-demo`, Arbeitsordner `C:\Repo\App\Daten` und die Variable `MODUS=demo`; `zeige.txt` enthält `-demo`, `C:\Repo\App\Daten` und `demo`; Statusleiste „Startprofil: Demo“ |
| SP3 | Klick auf „Startprofil: Demo“ in der Statusleiste, „Kunde“ wählen, *Start › Ohne Debugger starten* | Feld zeigt „Startprofil: Kunde“; `zeige.txt` enthält `-kunde`; `MODUS` ist leer und der Arbeitsordner wieder der vorherige, weil „Kunde“ beides nicht setzt (Akzeptanz: zwei Profile, je eigene Parameter) |
| SP4 | Tooltip über dem Feld | Parameter, Arbeitsordner, Host und Umgebung des aktiven Profils, darunter „Klick: Startprofil wählen“ |
| SP5 | Vor SP2 eigene Parameter `-alt` in *Start › Parameter* eintragen; nach SP3 „Kein Startprofil (Startoptionen von vorher)“ | Meldung „Kein Startprofil; die Startoptionen von vorher gelten wieder.“; *Start › Parameter* zeigt wieder `-alt`; Feld „Startprofil: –“ |
| SP6 | Repository auf einem zweiten Rechner (oder in einen anderen Ordner) klonen, `Zeige.dproj` öffnen | „Demo“ und „Kunde“ stehen in der Auswahl, ohne etwas einzurichten; noch kein Profil aktiv (Akzeptanz: gemeinsames Profil nach dem Klonen da) |
| SP7 | „Kunde“ wählen, IDE schließen (Projekt speichern), neu starten, Projekt öffnen | Feld zeigt wieder „Startprofil: Kunde“; Parameter `-kunde 7` |
| SP8 | „Aktuelle Startoptionen als persönliches Profil speichern …“, Name „Lokal“ | Meldung „Persönliches Startprofil „Lokal“ gespeichert.“; „Lokal“ ist aktiv, Pfad „Persönlich“; Datei `%LOCALAPPDATA%\Atlas\startprofiles\<Schlüssel>.json` enthält das Profil, `.atlas` ist unverändert |
| SP9 | „Persönliche Startprofile bearbeiten“, in der Datei `"host": "C:\\Tools\\Host.exe"` bei „Lokal“ ergänzen, speichern | Nach höchstens 1 s setzt Atlas die Host-Anwendung neu (*Start › Parameter*); absolute Pfade sind in persönlichen Profilen erlaubt |
| SP10 | In `.atlas` „Kunde“ löschen, während „Kunde“ aktiv ist | Feld „Startprofil: Kunde (fehlt)“, Tooltip „Das Profil „Kunde“ gibt es nicht mehr …“; die Startoptionen bleiben, wie sie sind |
| SP11 | Konfiguration Debug → Release bzw. Plattform Win32 → Win64 wechseln | Das aktive Profil gilt auch dort (*Start › Parameter* der neuen Konfiguration zeigt es); das Projekt gilt nur als geändert, wenn sich ein Wert wirklich ändert |
| SP12 | Projekt ohne `startProfiles` und ohne persönliche Datei aktiv | Kein Feld in der Statusleiste; der Befehl zeigt nur die Aktionen |
| SP13 | Schalter „Startprofil in der Statusleiste“ aus (Optionen › Atlas › Compiler oder Schnellschalter) | Feld verschwindet ohne Neustart, der Befehl bleibt; wieder an: Feld da |
| SP14 | Schalter „Startprofile“ aus | Ohne Neustart: Befehl, Feld und Tipp „Startprofile wechseln“ verschwinden; Startoptionen bleiben, wie sie zuletzt gesetzt waren; wieder an: alles zurück, das gemerkte Profil gilt |
| SP15 | „Atlas-Feld in der Statusleiste“ aus, Startprofil-Feld an | Das Startprofil-Feld bleibt allein sichtbar und klickbar; kein leerer Platz für das Atlas-Feld |
| SP16 | Projektdatei `.atlas` aus | Nur persönliche Profile; „Gemeinsame Startprofile in .atlas bearbeiten“ meldet, dass die Projektdatei aus ist |
| SP17 | Während eine Debug-Sitzung läuft, ein Profil wählen | Startoptionen werden gesetzt, gelten ab dem nächsten Start; kein Absturz, kein Dialog |

## Release-Build-Wächter (#533)

Voraussetzung: VCL-Projekt `Kasse.dproj` mit den Konfigurationen Debug und Release (Win32 und Win64), Release-Build-Wächter an (Optionen › Atlas › *Release-Build*), `build.gate` = off, alle Prüfungen an, Sollwerte aus. In Release: DEBUG nicht definiert, Debug-Informationen, Assertions, Stack-Frames, Bereichs- und Überlaufprüfung aus, Versionsinformationen 1.0.0.0, Ausgabeordner `.\$(Platform)\$(Config)`. In `Kasse.dpr` steht `ReportMemoryLeaksOnShutdown := True;` innerhalb von `{$IFDEF DEBUG}`.

| Nr. | Schritte | Erwartet |
|---|---|---|
| RW1 | Release aktiv, *Projekt › Erzeugen* | Keine Meldung des Wächters; der Build läuft |
| RW2 | In Release unter *Bedingte Definitionen* `DEBUG` eintragen (nicht speichern), *Erzeugen* | Atlas-Gruppe des Meldungsfensters: „Release-Wächter: 1 Befund(e) in Kasse.dproj (Release, Win32):“ und „[release-debug-define] Symbol DEBUG ist definiert. Ändern: Projekt › Optionen › … Bedingte Definitionen (Release, Win32).“; der Build läuft (Akzeptanz: Release mit DEBUG gibt eine Meldung; Optionen aus der IDE, nicht aus der gespeicherten .dproj) |
| RW3 | Wie RW2 mit `build.gate` = block | Der Build startet nicht; Atlas-Gruppe mit dem Befund, „Build abgebrochen (build.gate = block) …“ und „Atlas: Compile abgebrochen – 1 Befund(e) des Release-Wächters: release-debug-define“ (Akzeptanz: mit block startet der Build nicht) |
| RW4 | Nach RW3 binnen 10 s noch einmal *Erzeugen* | Der Build läuft; Meldung „bewusst übergangen …“; nach mehr als 10 s wieder Abbruch |
| RW5 | Debug aktiv (mit DEBUG), *Erzeugen*, auch mit block | Keine Meldung des Wächters, der Build läuft (Akzeptanz: Debug-Build wird nicht geprüft) |
| RW6 | Wie RW2, auf dem Reiter *Release-Build* „Symbol DEBUG definiert“ abhaken, *Erzeugen* | Kein Befund (Akzeptanz: eine abgeschaltete Prüfung meldet nichts) |
| RW7 | Release: Bereichsprüfung, Überlaufprüfung, Assertions und Stack-Frames an, Debug-Informationen auf „Begrenzt“ | Je ein Befund mit „ist an (Soll: aus)“ und dem Weg zur Option; „Bereichsprüfung“ auf „prüfen, Soll: an“ gestellt: dieser Befund entfällt |
| RW8 | In `Kasse.dpr` die Zeile `ReportMemoryLeaksOnShutdown := True;` aus dem `{$IFDEF DEBUG}`-Block nehmen (ungespeichert), Release erzeugen | Befund „[release-memory-leaks] …“ als Zeile mit Datei und Zeile; Doppelklick springt in die .dpr; in `{$IF DEFINED(DEBUG)}` oder im `{$ELSE}`-Zweig von `{$IFNDEF DEBUG}` kein Befund, in einem Kommentar auch nicht |
| RW9 | *Versionsinformationen in Projekt aufnehmen* in Release abschalten | Befund „[release-version-info] Keine Versionsinformationen …“ |
| RW10 | Versionsinformationen an (1.0.0.0), Release erfolgreich erzeugen, dann noch einmal erzeugen | Beim zweiten Build „Version 1.0.0.0 wie beim letzten Release-Build …“; nach Erhöhen auf 1.0.1.0 kein Befund; mit „Build-Nummer automatisch erhöhen“ nie; nach Neustart der IDE gilt die gemerkte Version weiter (Abschnitt `release` in `%LOCALAPPDATA%\Atlas\projects\<Schlüssel>.json`) |
| RW11 | Ausgabeordner von Release auf `.\Bin` stellen, Debug ebenfalls `.\Bin` | Befund „[release-output-folder] Ausgabeordner Bin wie in Debug …“; mit `.\$(Platform)\$(Config)` in beiden kein Befund |
| RW12 | Konfiguration „Ship“ anlegen, DEBUG darin, `build.releaseConfigs` = `Release, Ship`, Ship erzeugen | Befund wie RW2 mit (Ship, Win32); ohne „Ship“ in der Liste keine Prüfung |
| RW13 | Package-Projekt (.dpk) in Release mit gleichem Ausgabeordner wie Debug und `ReportMemoryLeaksOnShutdown` im Quelltext | Keine Befunde zu Leckbericht und Ausgabeordner; DEBUG und Compileroptionen werden geprüft |
| RW14 | Mit block und DEBUG in Release: Claude Code `build_project` mit `configuration: "Release"` | Antwort „nicht angenommen“ bzw. Fehler mit „1 Befund(e) des Release-Wächters: release-debug-define“, kein Build; Konfiguration und Plattform danach wie vorher (für #764 „Öffnen und bauen“) |
| RW15 | Befehlspalette „Release-Build prüfen“ mit Debug aktiv | Prüft Release ohne Build: Befunde wie RW2 oder „Release-Wächter: Kasse.dproj (Release, Win32) ohne Befund.“; Projekt ohne Release-Konfiguration: „… hat keine Release-Konfiguration …“; kein Projekt offen: „Kein Projekt geöffnet.“ |
| RW16 | Release-Build-Wächter aus (Optionen oder Schnellschalter) | Keine Prüfung bei Release-Builds; Befehl und Tipp „Release-Build prüfen“ verschwinden ohne Neustart |
| RW17 | Hintergrundprüfung nach dem Speichern (#548) und Syntaxprüfung in Release mit DEBUG | Keine Meldung des Wächters, kein Abbruch |
| RW18 | Projektgruppe mit zwei Release-Projekten, eines mit DEBUG, *Alle erzeugen* mit block | Das Projekt mit DEBUG wird abgebrochen, die Meldung nennt dessen Namen; das andere prüft der Wächter ohne Befund (ob die IDE danach weiterbaut, entscheidet sie) |

## Units suchen (#777)

Voraussetzung: Projektgruppe mit mehreren Projekten, darunter ein DUnitX-Testprojekt; Server läuft; Einstellungen auf Vorgabe.

| Nr. | Schritte | Erwartet |
|---|---|---|
| US1 | Strg+F12 | Atlas-Fenster „Units suchen“ statt des IDE-Dialogs; erst „Units werden geladen …“, dann Gruppen je Projekt mit Trefferzahl, aktives Projekt zuerst |
| US2 | *Ansicht › Units* mit gedrückter Umschalttaste; Befehlspalette „IDE-Dialog Units suchen“ | Der Dialog der IDE |
| US3 | Optionen › Atlas › Units suchen: „Strg+F12 … öffnen das Atlas-Fenster“ aus, Strg+F12 | IDE-Dialog ohne Neustart; *Atlas › Units suchen (Atlas)…* öffnet weiter das Atlas-Fenster |
| US4 | `sett` tippen | Units mit „sett“ im Namen, bester Treffer oben, Treffer hervorgehoben, Fußzeile „n von m“ |
| US5 | `-t:test sett` und `p:ide t:form` | Erst ohne Testunits; dann nur Formulare aus Projekten mit „ide“ im Namen; die Filter erscheinen als Chips, Rücktaste im leeren Feld entfernt den letzten |
| US6 | Chips Herkunft und Art umschalten, Fenster schließen und wieder öffnen | Wahl und eingeklappte Gruppen sind je Projektgruppe gemerkt, ebenso Lage, Größe und Vorschaubreite |
| US7 | Strg+G | Gruppierung Projekt → Ordner → Flach; Strg+←/→ klappt die Gruppe zu bzw. auf |
| US8 | Eine Formular-Unit wählen, F4 | Vorschau mit Kopfkommentar, Zeilen, Änderungsdatum, Git-Zustand, Typen, „Verwendet von (n)“ und Formularskizze; F4 blendet sie aus und ein |
| US9 | Leertaste auf drei Units, „In uses aufnehmen“ | Units stehen im passenden uses der Unit, die vor dem Öffnen oben im Editor war (interface, wenn ein Bezeichner des interface-Teils aus ihnen stammt); Meldung „3 Units in uses von … aufgenommen“; Alt+Enter macht dasselbe für die gewählte Unit |
| US10 | Umschalt+Enter bzw. „Formular öffnen“ auf einer Formular-Unit | Formular im Designer; bei einer Unit ohne Formular Meldung „… hat kein Formular“ |
| US11 | „Testunits öffnen“ (Strg+T) auf `Kunden` | `Kunden.Tests.pas` geöffnet; ohne Testunit Meldung „Keine Testunit zu Kunden“ |
| US12 | „Pfade kopieren“ (Strg+C), „Im Explorer zeigen“, „Im Projektmanager zeigen“ | Pfade in der Zwischenablage; Explorer mit markierter Datei; Projektmanager offen, Meldung „Kunden gehört zu …“ |
| US13 | Jede Einstellung der Seite einzeln aus | Vorschau, Formularskizze, „Verwendet von“, Chips, Tippsyntax, Häkchen, Aktionsleiste, „In uses aufnehmen“ fehlen jeweils; Pfadanzeige und Vorgewählte Herkunft wirken beim nächsten Öffnen |
| US14 | Server beenden, Strg+F12 | Meldung „Der Atlas-Server läuft nicht“ und der IDE-Dialog |
## Erzeugen-Menü (#719)

Voraussetzung: Server läuft; Einstellungen auf Vorgabe; Unit mit `TKunde = class` (Felder `FName: string; FListe: TStrings;`), einer Klasse `TStaffelpreise = class(TStandardpreise)` mit virtueller Methode im Vorfahren und einer Klasse `TDienst = class(TInterfacedObject, IDienst)`, der Methoden von `IDienst` fehlen.

| Nr. | Schritte | Erwartet |
|---|---|---|
| EM1 | Cursor in `TKunde` hinter `public`, Alt+Einfg | Popup am Cursor mit Kopf „Erzeugen“ und den Zeilen 1 Konstruktor aus Feldern, 2 Destruktor mit Freigabe, 3 Property mit Feld, 4 Methoden überschreiben…, 5 Interface implementieren… (nur in `TDienst`), 6 Equals / GetHashCode; rechts gedimmt `/ctor`, `/dtor` …; darunter weitere Einträge und die Gruppe Vorlagen |
| EM2 | Taste 1 | Zweiter Schritt „Konstruktor aus Feldern“ mit `FName` und `FListe`, beide gewählt; Enter legt Konstruktor mit beiden Parametern an, ein Strg+Z nimmt alles zurück |
| EM3 | Alt+Einfg, `ctor`, Leertaste auf `FListe`, Enter | Konstruktor nur mit `FName` |
| EM4 | In `TStaffelpreise` Alt+Einfg, 4 | Auswahl der überschreibbaren Methoden der Vorfahren; Enter legt Deklaration und Rumpf mit `inherited` an |
| EM5 | In `TDienst` Alt+Einfg, „Interface implementieren…“, Enter | Alle fehlenden Methoden von `IDienst` als Deklaration und Rumpf; mit nur einer gewählten Methode nur diese |
| EM6 | In einer Methode zwei Anweisungen markieren, Alt+Einfg | Gruppe Umschließen (try … finally Free, Sperren, Im Hauptthread, {$IFDEF}…) und nur Anweisungs-Vorlagen; „try … finally Free“ umschließt genau die markierten Zeilen |
| EM7 | Ohne Markierung in einer Methode Alt+Einfg | Keine Gruppe Umschließen; Lokale Variable…, Protokollzeile …; Vorlagen wie `tryf`, keine Deklarations-Vorlagen wie `class` |
| EM8 | Im Kommentar bzw. String Alt+Einfg | „Hier gibt es nichts zu erzeugen“ |
| EM9 | Menü offen, `eqh` tippen | Unscharfer Filter, „Equals / GetHashCode“ oben, Treffer hervorgehoben, Fußzeile „Filter: eqh“; Rücktaste nimmt Zeichen zurück |
| EM10 | Einen Eintrag ausführen, Menü erneut öffnen | Eintrag steht oben unter „Zuletzt gewählt“ und nicht noch einmal in seiner Gruppe; nach IDE-Neustart weiter oben |
| EM11 | Auf einem Eintrag Entf | Eintrag verschwindet, Meldung „… ausgeblendet“; unter Optionen › Atlas › Befehle steht er in „Ausgeblendete Einträge“ |
| EM12 | Optionen: Gruppen `templates,generate`, „Zuletzt gewählte Einträge oben“ und „Befehlsnamen anzeigen“ aus | Vorlagen zuerst, keine Gruppe Umschließen, kein „Zuletzt gewählt“, keine `/name` rechts |
| EM13 | Rechtsklick im Editor › Atlas › Erzeugen…; Befehlspalette „Erzeugen…“; *Atlas › Erzeugen…* | Dasselbe Menü am Cursor |
| EM14 | Schnellschalter „Erzeugen-Menü“ aus, Alt+Einfg | Alt+Einfg geht an die IDE (bzw. eine andere Belegung); Befehl fehlt in Palette und Atlas-Menü, Tipp „Erzeugen-Menü“ erscheint nicht in „Atlas entdecken“; Kontextmenü meldet „abgeschaltet“ |
| EM15 | `slashCommands` in atlas.json aus, Alt+Einfg | Keine Schnellbefehle, Vorlagen und Code-Aktionen bleiben |
| EM16 | Eigene Vorlage mit `context: declaration` in `%APPDATA%\Atlas\Snippets` | Erscheint auf Unit-Ebene unter Vorlagen, nicht in einer Methode; Enter setzt sie mit Platzhaltern ein |
| EM17 | `/override` mit Pflicht-Argument ohne Auswahl, Enter im leeren Feld | Kein Ausführen, Signalton, Zeile „Beispiel: /override …“ bleibt |

## Diagnosemodus (#479)

Vorbereitung: Plugin (Win32 und Win64) gebaut und installiert, ein Projekt mit einigen Units geöffnet, Server läuft.

| Nr. | Schritte | Erwartet |
|---|---|---|
| DM1 | `Atlas.Tests` bauen und ausführen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TAtlasTimingTests`, `TAtlasCompletionTimingTests` und `TAtlasTimingFrameTests` grün |
| DM2 | Frisch installiert: *Tools › Optionen › Atlas*, Seite *Allgemein* | Kontrollkästchen „Diagnosemodus …“ aus; kein Fenster „Atlas-Diagnose“, keine Zeile „Diagnosemodus“ im Statusfeld |
| DM3 | Kontrollkästchen setzen, OK | Andockbares Fenster „Atlas-Diagnose“ öffnet (klein, lässt sich wie das Ergebnisfenster andocken); Hinweis „Noch keine Abfrage gemessen …“; gelbe Zeile „Diagnosemodus: an“ im Atlas-Statusfeld, Klick darauf zeigt das Fenster |
| DM4 | Im Editor Strg+Leer, dann weitertippen | Titel „Letzte Abfrage: Bezeichner, Strg+Leer, <Uhrzeit>“; Zeilen Kontext, „Quelle: Server“, „Quelle: XMLDoc“ bzw. „Quelle: Code-Vorlagen“ (je Quelle mit Namen), Filtern und Sortieren, Zeichnen, Bis zur Liste, Einträge; Spalten Letzte, Mittel (n), Maximum, Budget (8, 50, 12, 10, 50 ms) |
| DM5 | Server mit künstlicher Verzögerung (Index neu aufbauen lassen und sofort Strg+Leer; oder `ProviderTimeLimitMs` hoch und den Server im Debugger anhalten) | Zeit der Quelle „Server“ fett in Warnfarbe auf abgesetzter Fläche; Popup trotzdem mit den übrigen Einträgen |
| DM6 | 60 Mal die Vervollständigung öffnen | Spaltenkopf „Mittel (50)“; Mittelwert und Maximum über höchstens 50 Abfragen |
| DM7 | „Bericht kopieren“, in einen Editor einfügen | Atlas-, IDE-Version und Plattform, Budgets, Tabelle, Abfragen (neueste zuerst), Einstellungen; kein Quelltext, keine Präfixe, kein Dateiname; Serverpfad als `<pfad>`, Benutzername als `<benutzer>`; Hinweis „Bericht in der Zwischenablage (ohne Quelltext).“ |
| DM8 | „Dateinamen in den Bericht“ anhaken, erneut kopieren | Wie DM7, zusätzlich der Dateiname (ohne Ordner) je Abfrage |
| DM9 | Strg+Alt+Umschalt+D | Diagnosemodus aus: Fenster zu, Statuszeile weg, Optionsseite zeigt aus; erneut: wieder an. Strg+Alt+Umschalt+A öffnet weiterhin die Schnellschalter, die dort auch „Diagnosemodus“ (Seite Allgemein) zeigen |
| DM10 | Befehlspalette „Atlas: Diagnosemodus ein/aus“ und „Atlas: Diagnosefenster zeigen“ | Schalten bzw. zeigen das Fenster (bei ausgeschaltetem Modus schaltet „zeigen“ ihn ein) |
| DM11 | Seite *Tastenkonflikte* | Zeile „Diagnosemodus ein/aus“ mit Strg+Umschalt+Alt+D; andere Taste eintragen wirkt nach OK sofort |
| DM12 | Diagnosemodus aus, 30 Mal Vervollständigung | Verhalten wie ohne die Funktion; im Wächter- bzw. Profiler-Protokoll keine zusätzliche Zeit; `%LOCALAPPDATA%\Atlas\Logs\Diagnose\atlas-diagnosemodus.txt` unverändert |
| DM13 | Diagnosemodus an, einige Abfragen, dann aus (oder IDE schließen) | `atlas-diagnosemodus.txt` enthält den Bericht ohne Dateinamen; während der Modus an ist, höchstens alle 30 s aktualisiert |
| DM14 | Dunkles und helles Thema, 150 % Skalierung | Tabelle lesbar, Warnfarbe deutlich, nichts abgeschnitten; Themenwechsel ohne Neustart |
| DM15 | Diagnosemodus an, IDE neu starten | Fenster öffnet nach dem Laden wieder, Statuszeile gelb |

## Einrichtung mit Prüfliste (#625)

Vorbereitung: Plugin (Win32 und Win64) gebaut und installiert. Für den „ersten Start“ unter `HKCU\Software\Atlas\IdePlugin` den Wert `SetupChecklistSeen` löschen.

| Nr. | Schritte | Erwartet |
|---|---|---|
| EP1 | `Atlas.Tests` bauen und ausführen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TAtlasSetupChecklistTests`, `TAtlasSetupControllerTests` und `TAtlasSetupWindowTests` grün |
| EP2 | Erster Start (ohne `SetupChecklistSeen`) mit einer Projektgruppe | Nach dem Laden öffnet das nicht modale Fenster „Atlas-Einrichtung“; die IDE bleibt bedienbar; sechs Zeilen mit Punkt: Server, Delphi 13 (37.0) bzw. Delphi 12 (23.0) mit Plattform, Projektgruppe mit Unterzeile je Projekt, Bibliotheks-Cache, Error Insight, Tastenkürzel; unten „Probier es aus: **Strg+Leer** in einer Methode“ (bzw. die eigene Taste aus *Tastenkonflikte*) |
| EP3 | Während der Server startet bzw. indiziert, Fenster offen lassen | Punkte gelb mit „Server wird gestartet…“ bzw. „wird indiziert: n von m Projekten fertig“; aktualisiert sich alle 2 s ohne Klick; Projektzeilen wechseln von „wird aufgebaut“ auf „fertig“ |
| EP4 | Serverpfad in *Tools › Optionen › Atlas* auf eine nicht vorhandene Datei, IDE neu starten | Prüfliste öffnet von selbst; Server rot „AtlasServer.exe nicht gefunden“, Knopf „Server-Pfad wählen…“; Datei wählen → Pfad steht danach auf der Optionsseite, der Server startet, Punkt wird grün |
| EP5 | Server einer anderen Version eintragen | Gelb „Server x passt nicht zum Plugin y“ mit „Server-Pfad wählen…“ |
| EP6 | **Error-Insight-Ort bestätigen**: *Tools › Optionen › Editor › Sprache › Code Insight* Error Insight an; IDE neu starten | Zeile „Error Insight der IDE ist noch an (doppelte Meldungen)“, Knopf „Error Insight abschalten“. Klick: Zeile „Error Insight umgeschaltet, wirkt nach dem Neustart der IDE“; in der Registry unter `<BDS-Schlüssel>\Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal` steht `Error Insight = False`. Nach Neustart ist Error Insight in den IDE-Optionen aus und die Zeile grün. Stimmt der Ort nicht (Optionen zeigen weiter an), bitte den richtigen Schlüssel melden |
| EP7 | Atlas-Probleme aus (*Atlas*-Seite), Error Insight aus | Gelb „Weder Error Insight noch Atlas zeigen Fehler im Editor“ mit „Error Insight einschalten“ |
| EP8 | Taste von Atlas mit einer fremden Erweiterung belegen (z. B. CnPack auf Strg+Leer) | Gelb „1 Tastenkürzel anders belegt, z. B. …“; „Tastenkonflikte öffnen“ öffnet *Tools › Optionen › Drittanbieter › Atlas › Tastenkonflikte* (**Seite prüfen**); nach Ändern und „Erneut prüfen“ grün |
| EP9 | Bibliotheks-Cache löschen (`%LOCALAPPDATA%\Atlas\Index\<Version>\…\Bibliothek` bzw. „Index löschen“), Server neu starten | Gelb „Bibliotheks-Cache fehlt, erster Start dauert länger“ bzw. „entsteht beim ersten Indexlauf“, Knopf „Jetzt aufbauen“ baut den Index neu |
| EP10 | Ein Projekt der Gruppe nicht indizierbar (Projekt hinzufügen, Server noch ohne Workspace) | Gelb „Projektgruppe: 1 von n Projekten nicht im Index (Name)“; Knopf „Index neu aufbauen“ |
| EP11 | „Warum?“ an einem gelben Punkt (z. B. ohne Projekt bei Delphi) | Erklärung erscheint unter den Zeilen im Fenster, kein weiterer Dialog |
| EP12 | „Bericht kopieren“, in einen Editor einfügen | Titel, „n von 6 erledigt“, Atlas-, IDE-Version und Plattform, Zeilen mit `[ok]`/`[!]`/`[x]`; kein Pfad, Benutzer- oder Rechnername steht als `<benutzer>`; Hinweis „Bericht in der Zwischenablage (ohne Pfade und Namen).“ |
| EP13 | Alles grün, IDE neu starten | Prüfliste öffnet **nicht** von selbst; Zeile „Einrichtung: vollständig (6 von 6)“ grün im Statusfeld |
| EP14 | Ein Punkt fest gelb (z. B. Error Insight an), `ui.setupChecklist` aus (Kontrollkästchen im Fenster oder Seite *Allgemein*), IDE neu starten | Prüfliste öffnet nicht von selbst; *Atlas › Einrichtung prüfen…*, Befehlspalette „Einrichtung prüfen…“ und Klick auf die gelbe Zeile „Einrichtung: 5 von 6 erledigt“ im Statusfeld öffnen sie |
| EP15 | Projekt öffnen, während der Server noch startet; IDE neu starten | Fenster wartet; wird alles grün, öffnet es nicht; bleibt etwas nach 2 Minuten im Gange, öffnet es ebenfalls nicht |
| EP16 | Dunkles und helles Thema, 150 % Skalierung, Thema wechseln bei offenem Fenster | Zeilen, Punkte und Knöpfe lesbar, nichts abgeschnitten; Farben folgen ohne Neustart |
| EP17 | Abgesicherter Start (Umschalt beim Laden, Stufe minimal) | Keine Prüfliste, kein Menüeintrag; abgesichert (nicht minimal) wie normal, nur auf Abruf und beim Start |

## Tastenkürzel-Übersicht (#520)

Vorbereitung: Plugin (Win32 und Win64) gebaut und installiert; für TK5/TK6 eine Erweiterung mit eigener Tastaturbelegung (z. B. CnPack oder GExperts).

| Nr. | Schritte | Erwartet |
|---|---|---|
| TK1 | `Atlas.Tests` bauen und ausführen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TAtlasKeyMapTests` (auch der Wächter `EveryKeySettingIsInOverview`: jede Tasten-Einstellung steht in der Übersicht), `TAtlasKeyMapWindowTests`, `TAtlasKeysPageTests`, `TAtlasShortcutTipsTests` und `TAtlasSetupChecklistTests` grün |
| TK2 | *Atlas › Tastenkürzel-Übersicht…* bzw. Befehlspalette „Tastenkürzel-Übersicht“ | Nicht modales Fenster „Atlas – Tastenkürzel“ mit Spalten Taste, Befehl, Herkunft, Kontext, Hinweis; Zeile „Strg+Umschalt+P · Befehlspalette · Atlas · global“ (**Abnahme**); Aktionen der IDE (z. B. Strg+S „Speichern“) mit Herkunft IDE; unten rechts „n Kürzel, m Konflikte“ |
| TK3 | *Tastenkonflikte*: „Auswahl erweitern“ absichtlich auf Strg+Umschalt+P legen, OK, Übersicht „Aktualisieren“ | Beide Zeilen rot (**Abnahme**); Hinweis bei der einen „gewinnt …“, bei der anderen „unterliegt „…“ (Atlas): …“ mit Grund; beim nächsten IDE-Start einmal eine Meldung im Meldungsfenster „Atlas: Strg+Umschalt+P ist doppelt belegt – … (Atlas) und …; es gewinnt …“ mit Verweis auf die Übersicht und *Tools › Optionen › Atlas › Tastenkonflikte*; kein zweites Mal in derselben Sitzung |
| TK4 | Suchfeld: „Strg+Umschalt+P“, „Ctrl+Shift+P“, „palette“, „IDE“; „Nur Konflikte“ an | Jeweils nur passende Zeilen; Zusammenfassung „x von n Kürzeln“; „Nur Konflikte“ zeigt nur rote Zeilen; „Aktualisieren“ behält Suche und Filter |
| TK5 | Erweiterung mit eigener Editor-Belegung auf eine Atlas-Taste (z. B. Strg+Leer) | Zeile „Tastaturbelegung des Editors“ mit Herkunft „Erweiterung <Paket>“, Kontext Editor, rot; Hinweis nennt den Gewinner (**prüfen, ob die IDE das bestätigt**: Taste im Editor drücken) |
| TK6 | Fremde Aktion mit Kürzel (z. B. GExperts-Menüeintrag) | Herkunft „Erweiterung <Paket>“ statt IDE (**Herkunft prüfen**; bei falscher Zuordnung Paket und Aktion melden) |
| TK7 | „Als HTML exportieren“ | Browser öffnet `%LOCALAPPDATA%\Atlas\Tastenkuerzel.html` mit Titel, Stand, Filter (falls gesetzt) und nur den gezeigten Zeilen, Konflikte rot; „Drucken“ bzw. Strg+P: Druckvorschau ohne Knopf, Tabelle vollständig, Kopfzeile wiederholt sich (**Abnahme**) |
| TK8 | „Tastenkonflikte…“ im Fenster | Öffnet *Tools › Optionen › Drittanbieter › Atlas › Tastenkonflikte* |
| TK9 | *Tastenkonflikte*: „Menüeintrag und Befehl „Tastenkürzel-Übersicht““ aus | Menüeintrag und Befehl verschwinden sofort; offenes Fenster bleibt bedienbar |
| TK10 | *Tastenkonflikte*: „Beim Start die Atlas-Tasten prüfen …“ aus, Konflikt aus TK3 lassen, IDE neu starten | Keine Meldung beim Start; Übersicht zeigt den Konflikt weiter rot |
| TK11 | Einrichtung (#625) mit dem Konflikt aus TK3 bzw. TK5 | Zeile „Tastenkürzel“ gelb, nennt dieselbe Taste wie die Übersicht |
| TK12 | Dunkles und helles Thema, 150 % Skalierung, Thema wechseln bei offenem Fenster; Esc | Liste, rote Zeilen und Knöpfe lesbar, Farben folgen ohne Neustart; Esc schließt das Fenster |
| TK13 | Protokoll (`%LOCALAPPDATA%\Atlas\Logs`) nach TK3 | Nur Anzahlen (Kürzel, Konflikte), keine Pfade oder Benutzernamen |
| TK14 | Übersicht öffnen (Vorgaben: Deklaration ⇄ Implementierung an, „Units suchen“ an, Übernahme von Strg+F12 an); in *Optionen › Atlas › Befehle* eine Taste für „Zwischen Unit und Testunit wechseln“ und unter *Units suchen* ein eigenes Kürzel setzen, „Aktualisieren“ | Zeilen „Strg+Umschalt+↑ · Deklaration/Implementierung wechseln · Atlas · Editor“ und „Strg+Umschalt+↓ · Deklaration/Implementierung wechseln (Taste 2)“ (Tastentext so, wie die IDE ihn schreibt), „Zwischen Unit und Testunit wechseln“, „Units suchen“ (eigene Taste) und „Strg+F12 · Units suchen über Strg+F12 (statt IDE-Dialog) · Atlas · global“; keine zweite Zeile „Units…“ mit Herkunft IDE für Strg+F12 (**Abnahme**) |
| TK15 | „Deklaration/Implementierung wechseln“ ausschalten; *Units suchen* ganz aus; dann nur „Strg+F12 und Ansicht › Units öffnen das Atlas-Fenster“ aus; jeweils „Aktualisieren“ | Ausgeschaltet verschwinden die Zeilen der beiden Wechsel-Tasten bzw. der eigenen Units-Taste; Strg+F12 steht ohne Übernahme als „Units…“ mit Herkunft IDE; nichts davon rot und keine Meldung beim nächsten Start (**Abnahme**) |
| TK16 | Eigene Taste für Unit ⇄ Testunit absichtlich auf Strg+W (Auswahl erweitern) legen, IDE neu starten | Beide Zeilen rot; beim Start eine Meldung im Meldungsfenster für die doppelte Belegung; Einrichtung (#625): Zeile „Tastenkürzel“ gelb mit derselben Taste |
| TK17 | Erweiterung, die Strg+Umschalt+↑ oder Strg+F12 selbst belegt (z. B. CnPack/GExperts), dann Übersicht und IDE-Neustart | Atlas-Zeile rot, Hinweis nennt die Erweiterung als Gewinner; Startmeldung erscheint (**prüfen, ob die IDE das bestätigt**: Taste im Editor drücken) |
| TK18 | Befehlspalette: „Units suchen“ und „Deklaration/Implementierung wechseln“ suchen | „Units suchen“ zeigt Strg+F12 (bzw. die eigene Taste, wenn gesetzt), „Deklaration/Implementierung wechseln“ Strg+Umschalt+↑; mit abgeschalteter Übernahme bzw. abgeschaltetem Wechsel keine Taste |
| TK19 | Tastenkürzel-Tipps (#600) an; „Units suchen“ zweimal über das Menü *Atlas* aufrufen | Tipp nennt Strg+F12; nach Strg+F12 zählt die Spalte „Selten per Tastatur“ den Aufruf als Tastatur |

## Tastenkürzel-Tipps (#600)

Vorbereitung: Plugin (Win32 und Win64) gebaut und installiert; `shortcutTips.enabled` an, `shortcutTips.scope` = `all`; `%LOCALAPPDATA%\Atlas\shortcut-tips.json` und `%LOCALAPPDATA%\Atlas\usage.json` gelöscht (seit #757 steht die Zählung in `usage.json`, der Zustand der Tipps in `shortcut-tips.json`). Ein Projekt mit einer Klasse, deren Methoden noch nicht implementiert sind. Zwischen zwei Tipps 30 s warten (Mindestabstand), sofern ein Fall nichts anderes sagt.

| Nr. | Schritte | Erwartet |
|---|---|---|
| TT1 | `Atlas.Tests` bauen und ausführen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TAtlasShortcutTipsTests`, `TAtlasCommandUsageTests`, `TAtlasShortcutTipWindowTests`, `TAtlasKeyMapWindowTests` (Spalte „Selten per Tastatur“), `TAtlasSettingsPageTests.ShortcutTipsRoundTrip` und `TAtlasQuickTogglesTests` grün |
| TT2 | Im Editor auf der Klasse Rechtsklick › „Klasse beim Cursor vervollständigen“ | Die Klasse wird vervollständigt; unten rechts im Editorfenster erscheint ohne Fokuswechsel „Tipp: [Strg]+[Umschalt]+[C] für „Klasse beim Cursor vervollständigen““ mit Tastenkappen, darunter „Nicht mehr zeigen · Alle Kürzel“ (**Abnahme**). Der Caret bleibt im Editor, Tippen geht weiter in den Quelltext |
| TT3 | Nach TT2 nichts tun | Der Tipp verschwindet nach 4 s; steht die Maus über dem Tipp, bleibt er, bis sie ihn verlässt |
| TT4 | TT2 wiederholen und sofort eine beliebige Taste drücken | Der Tipp verschwindet mit der Taste; die Taste wirkt normal im Editor |
| TT5 | Nach TT2 am selben Tag (nach mehr als 30 s) erneut über das Kontextmenü „Klasse beim Cursor vervollständigen“ | Kein Tipp (höchstens einer je Aktion und Tag, **Abnahme**) |
| TT6 | Am nächsten Tag (oder `lastTip` des Befehls in `shortcut-tips.json` auf gestern setzen, IDE neu starten) TT2 wiederholen, im Tipp „Nicht mehr zeigen“ klicken; IDE neu starten, an einem weiteren Tag erneut TT2 | Nach dem Klick verschwindet der Tipp; `shortcut-tips.json` enthält für den Befehl `"never": true`; auch nach dem Neustart und an späteren Tagen kein Tipp für diesen Befehl, Tipps für andere Befehle erscheinen weiter (**Abnahme**) |
| TT7 | Strg+Umschalt+C dreimal im Editor drücken, dann (anderer Tag) über das Kontextmenü aufrufen | `keyboard` des Befehls in `usage.json` steht auf 3 (nach höchstens 5 s gespeichert); kein Tipp mehr |
| TT8 | Eine Aktion per Tastatur auslösen, z. B. Strg+Umschalt+C oder F9 | Kein Tipp (**Abnahme**); `usage.json` zählt `keyboard`, nicht `mouse` |
| TT9 | Über das Hauptmenü eine Aktion ohne Kürzel aufrufen (z. B. *Projekt › Optionen…* ohne Belegung oder *Atlas › Fehlerbericht erstellen…*) | Kein Tipp (**Abnahme**); `mouse` wird trotzdem gezählt |
| TT10 | Über die Werkzeugleiste „Speichern“ klicken, dann über das Hauptmenü *Atlas › Auswahl erweitern* | Je ein Tipp mit „[Strg]+[S]“ bzw. der Atlas-Taste für „Auswahl erweitern“ (mit 30 s Abstand) |
| TT11 | Befehlspalette (Strg+Umschalt+P), dort „Speichern“ bzw. einen Atlas-Befehl mit Taste wählen | Tipp mit dem Kürzel des gewählten Befehls (die Palette zählt als Aufruf ohne Kürzel) |
| TT12 | Unter *Tools › Optionen › Atlas › Tastenkonflikte* die Taste für „Auswahl erweitern“ ändern, speichern, dann *Atlas › Auswahl erweitern* über das Menü (anderer Befehl oder neuer Tag) | Der Tipp zeigt sofort die neue Taste, ohne IDE-Neustart (**Abnahme**) |
| TT13 | Haltepunkt setzen, Programm starten, am Haltepunkt anhalten, dann über das Kontextmenü eine Aktion mit Kürzel aufrufen | Kein Tipp während der angehaltenen Debug-Sitzung |
| TT14 | Eine Aktion mit Kürzel aufrufen, die einen modalen Dialog öffnet (z. B. *Suchen › Ersetzen…* über das Menü); bzw. bei offenem modalem Dialog eine Aktion auslösen | Kein Tipp, solange ein modaler Dialog offen ist |
| TT15 | Zwei verschiedene Aktionen mit Kürzel kurz nacheinander (unter 30 s) per Maus | Nur für die erste ein Tipp |
| TT16 | Eine Aktion mit einem Kürzel aus zwei Schritten per Menü aufrufen (z. B. in der IDE-Belegung ein Eintrag mit „Strg+K, Strg+D“ hinter dem Tab bzw. Strg+K-Belegungen der Klassischen Belegung) | Der Tipp zeigt beide Schritte: „[Strg]+[K] , [Strg]+[D]“; Sprachausgabe (Narrator) liest „Tipp: Strg+K, Strg+D für …“ |
| TT17 | Im Tipp auf „Alle Kürzel“ klicken | Das Fenster „Atlas – Tastenkürzel“ (#520) öffnet mit leerer Suche; mit `keys.overview` aus fehlt der Link |
| TT18 | Nach TT2–TT11 die Tastenkürzel-Übersicht öffnen | Spalte „Selten per Tastatur“ zwischen Kontext und Hinweis; bei Befehlen mit mindestens drei Aufrufen, davon weniger als ein Viertel per Kürzel, steht z. B. „3× Maus, 0× Tastatur“; der HTML-Export enthält die Spalte |
| TT19 | `shortcutTips.scope` auf „Nur Atlas-Befehle“, dann TT10 | Kein Tipp für „Speichern“, aber für den Atlas-Befehl |
| TT20 | `shortcutTips.enabled` aus (Seite *Allgemein* oder Schnellschalter), dann TT2 | Kein Tipp; Protokoll „Beobachtung False“ (nur, wenn auch `welcomePage.discover` oder `tips.usageTracking` aus ist, sonst zählt Atlas für „Atlas entdecken“ weiter); `shortcut-tips.json` ändert sich nicht mehr |
| TT21 | IDE-Thema hell ↔ dunkel wechseln, während ein Tipp sichtbar ist; dann erneut einen Tipp auslösen | Tipp in den Farben des Themas, Tastenkappen abgesetzt, Links in Akzentfarbe; 100 %, 150 %, 200 % Skalierung scharf und nicht abgeschnitten |
| TT22 | `%APPDATA%\Atlas\usage.json` (Vervollständigung) vor und nach TT2–TT11 vergleichen | Unverändert durch die Tipps; die Zählung steht nur in `%LOCALAPPDATA%\Atlas\usage.json` (#757) |
| TT23 | Protokoll (`%LOCALAPPDATA%\Atlas\Logs`) nach TT2 | Nur „Tastenkürzel-Tipp gezeigt (#600)“ bzw. „Beobachtung True/False“, keine Befehlsnamen, Pfade oder Benutzernamen |
| TT24 | Abgesicherter Start (#722) | Keine Tipps und keine Zählung; Menü und Palette funktionieren unverändert |

## Benachrichtigungszentrale (#601)

Vorbereitung: Plugin (Win32 und Win64) gebaut und installiert; Atlas-Statusfeld (`statusField.enabled`) an; `notifications.enabled` an, `notifications.sources` leer (alle Quellen „einblenden“), `notifications.maxEntries` = 200. Ein Projekt, das sich übersetzen lässt, und eine Unit, in die sich Fehler einbauen lassen. Die Liste gilt für die IDE-Sitzung; für jeden Fall, der eine leere Liste voraussetzt, vorher „Liste leeren“.

| Nr. | Schritte | Erwartet |
|---|---|---|
| BZ1 | `Atlas.Tests` bauen und ausführen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TAtlasNotificationCenterTests`, `TAtlasNotificationSourcesTests`, `TAtlasBuildNoticeTests`, `TAtlasNotificationsWindowTests`, `TAtlasPluginSettingsTests.NotificationOptions`, `TAtlasSettingsPageTests.NotificationsRoundTrip`, `TAtlasQuickTogglesTests`, `TAtlasKeyMapTests` und `TAtlasKeyMapWindowTests` grün |
| BZ2 | Zwei Fehler in die Unit einbauen, Projekt mit Strg+F9 übersetzen | Rechts im Atlas-Statusfeld steht eine rote Plakette „1“; Tooltip des Felds mit „1 ungelesene Benachrichtigungen; ein Klick auf die Zahl öffnet die Liste.“ Klick auf die Plakette öffnet über dem Statusfeld die Liste mit dem Eintrag „Build fertig: 2 Fehler“, Text „Projekt: 2 Fehler, 0 Warnungen, 0 Hinweise · Datei(Zeile): Meldung“, Quelle „Build fertig“, Uhrzeit, hinterlegt (ungelesen), Knopf „Zum Fehler“ (**Abnahme**) |
| BZ3 | In BZ2 auf „Zum Fehler“ klicken | Die Liste schließt, der Editor springt auf Datei, Zeile und Spalte des ersten Fehlers; die Plakette verschwindet (Eintrag gelesen, **Abnahme**) |
| BZ4 | Fehler beheben, erneut übersetzen; dann eine Warnung einbauen und übersetzen | Neue Einträge „Build fertig“ (Info, neutrale Plakette) bzw. „Build fertig: 1 Warnungen“ (gelbe Plakette mit schwarzer Zahl); die Plakette zählt die ungelesenen in der Farbe des schwersten |
| BZ5 | Compilerprüfung nach dem Speichern (#548, Registry `CheckOnSave`) an, Fehler einbauen, speichern; Fehler beheben, speichern | Ein Eintrag „Prüfung: 1 Fehler“ (Quelle „Prüfung im Hintergrund“); nach dem Beheben einmal „Prüfung: wieder fehlerfrei“, danach bei weiteren fehlerfreien Prüfungen keine Einträge mehr |
| BZ6 | Im Kontextmenü eines Eintrags der Quelle „Tastenkürzel-Tipps“ bzw. unter *Tools › Optionen › Atlas › Allgemein* unter „Verhalten je Quelle“ die Quelle „Tastenkürzel-Tipps“ auf „Nur sammeln“; dann eine Aktion mit Kürzel per Menü aufrufen (siehe TT2) | Kein Tipp-Fenster, aber ein Eintrag „Tastenkürzel: …“ mit Knöpfen „Alle Kürzel“ und „Nicht mehr zeigen“; Zähler und Tagessperre des Tipps gelten wie bei einem gezeigten Tipp (**Abnahme**) |
| BZ7 | Den Server dreimal innerhalb von 10 s neu starten (z. B. *Atlas › Server neu starten* oder Prozess `atlas-lsp.exe` beenden) | Ein einziger Eintrag „3 × Server neu gestartet“ (nach dem Beenden des Prozesses als Warnung mit „Der Server war beendet und läuft wieder.“), Knopf „Protokoll öffnen“ öffnet das Protokoll (**Abnahme**); der erste Start einer Sitzung erzeugt keinen Eintrag |
| BZ8 | Eine offene, ungeänderte Datei extern ändern (z. B. `git checkout`), zur IDE wechseln; dann eine Datei mit eigenen Änderungen extern ändern; dann eine offene Datei extern löschen | Einträge „Dateien neu geladen: 1“, „Eigene Änderungen behalten: Datei“ mit Knopf „Vergleichen“ (öffnet den Unterschied) und „Datei gelöscht: Datei“ (Quelle „Dateien neu geladen“) |
| BZ9 | Verhalten der Quelle „Dateien neu geladen“ auf „Nur sammeln“, BZ8 wiederholen | Einträge wie in BZ8, aber keine Zeilen im Meldungsfenster und kein Unterschied ohne Klick auf „Vergleichen“ |
| BZ10 | Verhalten einer Quelle auf „Aus“, deren Ereignis auslösen (z. B. Server: Server neu starten) | Kein Eintrag; die Funktion meldet sich auch nicht selbst (keine Zeile im Meldungsfenster) |
| BZ11 | Liste mit Einträgen aus mehreren Quellen öffnen; Filter auf „Build fertig“; „Alle gelesen“; „Liste leeren“ | Filter zeigt nur Einträge der Quelle; „Alle gelesen“ lässt die Einträge stehen, nimmt die Hinterlegung weg, Plakette verschwindet; „Liste leeren“ leert die Liste, Text „Keine Benachrichtigungen“, beide Knöpfe deaktiviert |
| BZ12 | Liste mit Strg+Umschalt+Alt+N öffnen; Pfeiltasten, Eingabe, Entf, Esc; Mausrad bei mehr Einträgen als Platz | Taste öffnet die Liste (auch über die Befehlspalette „Benachrichtigungen“); Pfeile wählen, Eingabe führt die erste Aktion aus (ohne Aktion: als gelesen markieren), Entf markiert als gelesen, Esc schließt; ein Klick außerhalb schließt; Mausrad blättert, Bildlaufleiste in den Farben des Themas |
| BZ13 | Rechtsklick auf einen Eintrag | Menü „Als gelesen markieren“, Trennlinie, „Hinweise von „Quelle““ (grau), drei Einträge „Einblenden und sammeln“ / „Nur sammeln“ / „Aus“ mit Häkchen beim aktuellen; die Wahl steht danach unter *Tools › Optionen › Atlas › Allgemein* und in der Registry `NotificationsSources` |
| BZ14 | `notifications.maxEntries` auf 10, mehr als 10 Ereignisse auslösen | Höchstens 10 Einträge, die ältesten fallen weg |
| BZ15 | Unter *Tools › Optionen › Atlas › Tastenkonflikte* die Taste der Benachrichtigungen ändern bzw. leeren | Neue Taste wirkt sofort; leer = keine Taste, Befehl in der Palette bleibt |
| BZ16 | `notifications.enabled` aus (Seite *Allgemein* oder Schnellschalter), dann BZ2, BZ6, BZ8 | Keine Plakette, keine Liste, Befehl fehlt in der Palette, Taste ohne Wirkung; Tipps, Meldungsfenster und Unterschiede erscheinen wie vor #601, unabhängig von `notifications.sources` (**Abnahme**) |
| BZ17 | IDE-Thema hell ↔ dunkel, 100 %, 150 %, 200 % Skalierung | Liste und Plakette in den Farben des Themas, Symbole nach Schwere (Fehler rot, Warnung gelb, Info Akzent), Chips der Aktionen lesbar, nichts abgeschnitten |
| BZ18 | Registry `NotificationsSources` auf `server=off,buildServer=collect,tracker=off` setzen, IDE starten, Einstellungen öffnen und speichern | Quelle „Build-Server“ (#763) steht in der Auswahl mit „Nur sammeln“; `tracker=off` (unbekannte Quelle) bleibt erhalten; unbekannte Verhalten werden übergangen (Quelle wieder „Einblenden und sammeln“) |
| BZ19 | Protokoll (`%LOCALAPPDATA%\Atlas\Logs`) nach BZ2–BZ8 | Keine Titel, Texte, Pfade oder Benutzernamen aus den Einträgen |
| BZ20 | Abgesicherter Start (#722) | Die Zentrale ist wie alle Schnellschalter für die Sitzung aus: keine Plakette, Hinweise wie vor #601; im Schnellschalter-Fenster „Benachrichtigungszentrale“ einschalten, dann sammelt sie ohne Neustart |

## Versionsverwaltung (#571)

Vorbereitung: Git für Windows und TortoiseSVN mit Kommandozeilenwerkzeugen (`svn.exe`, `svnadmin.exe`) installiert. Die Schnittstelle hat noch keine sichtbaren Nutzer in der IDE (folgen mit #592, #762, #755, #764, #765); geprüft wird über die Tests, den Einstellungsdialog und die Kommandozeile.

| Nr. | Schritte | Erwartet |
|---|---|---|
| VC1 | `Atlas.Tests` (Win32 und Win64) bauen und ausführen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TAtlasVcsTests` und `TAtlasVcsIntegrationTests` grün; kein Konsolenfenster blitzt auf, während die Git- und SVN-Fixtures angelegt werden |
| VC2 | VC1 mit `svn.exe` aus PATH und TortoiseSVN-Ordner entfernt (umbenennen) | SVN-Test „übersprungen“ (svn nicht installiert), alle übrigen grün |
| VC3 | Plugin (Win32 und Win64) bauen, IDE starten und wieder schließen | 0/0/0; keine Meldung zur Versionsverwaltung; Protokoll ohne Fehler, Entladen weiterhin unter einer Sekunde |
| VC4 | *Atlas › Globale Einstellungen*, Seite *Allgemein* | Feld `vcs.provider` als Auswahl `auto`, `git`, `svn`, `off`, Vorgabe `auto`; „svn“ speichern schreibt `"vcs": {"provider": "svn"}` in `%APPDATA%\Atlas\settings.json` |
| VC5 | SVN-Arbeitskopie: `AtlasServer --check <Ordner> --changed`, eine Datei ändern, eine neue anlegen; dann mit `--include-uncommitted` | wie bisher: „SVN: n von m Dateien geändert“, die geänderte Datei geprüft; mit `--include-uncommitted` auch die neue |
| VC6 | VC5 mit `"vcs": {"provider": "off"}` bzw. `"git"` in settings.json | Meldung „Versionsverwaltung abgeschaltet (vcs.provider = off)“ bzw. „… liegt in keiner Arbeitskopie für vcs.provider = git“, Exit-Code 3 |
| VC7 | SVN-Arbeitskopie innerhalb eines Git-Repositorys (z. B. Fremdcode unter `lib`): `--changed` im SVN-Ordner | SVN wird verwendet (nächstliegende Arbeitskopie), nicht mehr Git |
| VC8 | VC5 mit `svn.exe` aus PATH entfernt | Meldung „… liegt in einer SVN-Arbeitskopie, aber svn ist nicht installiert …“ statt eines Absturzes |

## Robustheit des Servers (Code-Review)

Vorbereitung: Plugin installiert, Projekt geöffnet, Server-Log über `--log` aktiv.

| Nr. | Schritte | Erwartet |
|---|---|---|
| RS1 | Während der Index aufgebaut wird: in einer Unit `/config Release Win64` + Enter, sofort danach die `.dproj` in der IDE speichern | Kein Fehler und keine Zugriffsverletzung im Server-Log; Log „Konfiguration Release, Plattform Win64 gewählt“; Index baut neu auf |
| RS2 | `/define TEST` dreimal schnell hintereinander | `.dproj` enthält TEST einmal; je Änderung ein Neuaufbau; kein Fehler im Log |
| RS3 | IDE schließen, während der Index aufgebaut wird | Server-Log ohne „Fehler beim Aufbau des Symbolindex“; Diagnoselog mit Endzeile |
| RS4 | Großes Projekt, „Atlas: Compiler prüfen“, sofort die IDE schließen | AtlasServer und dcc32 sind nach höchstens 2 s aus dem Task-Manager verschwunden |
| RS5 | `"requestTimeoutMs": 1000` in `atlas.json`, Hover bzw. Strg+Klick auf ein Symbol einer großen, noch nicht indizierten Bibliotheks-Unit | Antwort nach höchstens etwa 1 s; Server-Log „… mit RequestCancelled beantwortet (Zeitlimit)“ genau einmal; der Mitschnitt (`--trace`) zeigt genau eine Antwort auf die id |
| RS6 | Problemansicht aktiv, 2 min nichts ändern | Keine Zeitlimit-Warnung für `workspace/diagnostic`; Antworten im Mitschnitt im Abstand von etwa 8 s |
| RS7 | Server mit `--trace` auf einen USB-Stick, Stick abziehen | Genau eine Warnung „Mitschnitt abgebrochen …“; die Editorfunktionen laufen weiter |
| RS8 | Claude Code: eine in der IDE offene Datei per MCP-Werkzeug ändern | Die Änderung erscheint wie bisher im Editorpuffer |

## Leistung der Prüfregeln (Code-Review P-03, P-08, P-11, D-04)

Vorbereitung: Projekt mit Formularen und einer Unit mit Threads, Diagnosemodus an, Atlas-Problemliste vor der Änderung als Vergleich notiert.

| Nr. | Schritte | Erwartet |
|---|---|---|
| PRL1 | Projekt öffnen, `workspace/diagnostic` abwarten, Diagnoselog öffnen | `slowRule` für `component-*`, `flow-*`, `security-*` nicht mehr unter den langsamsten Regeln |
| PRL2 | Atlas-Problemliste mit dem Vergleich abgleichen (Stichprobe: drei Units mit Formular, eine mit Threads) | Anzahl und Text der Probleme unverändert |
| PRL3 | In einer Datei mit CRLF-Zeilenenden die Korrektur „Variable … entfernen“ und „Variable … je Durchlauf kopieren“ anwenden | Ersetzt genau die erwarteten Zeilen; Code übersetzt danach |
| PRL4 | Formular-Eigenschaftsregel (`dfmPropertyRules`) mit nicht gespeicherter Property auslösen | Meldung wie bisher, mit dem default-Wert aus der Klassendeklaration |

## Leistung des Plugins (Code-Review P-04, P-09, P-10, P-15, D-07)

Vorbereitung: Plugin installiert, Probleme und Inlay-Hints an, Projekt geöffnet.

| Nr. | Schritte | Erwartet |
|---|---|---|
| PP1 | Große Unit (> 1 MB) vorn, IDE 1 min im Leerlauf, Zeitmessung (Diagnosemodus) offen | Keine Last durch die Zeitgeber von Problemen und Inlay-Hints |
| PP2 | In der Unit tippen | Problemmarken wandern wie bisher mit, neue Diagnosen nach der Tipp-Pause |
| PP3 | Strg+Z / Umschalt+Strg+Z | Marken und Inlay-Hints folgen dem Text |
| PP4 | Im Formular-Designer eine Komponente einfügen | Das neue Feld ist in den Problemen spätestens nach 2 s berücksichtigt |
| PP5 | Offene Datei extern ändern, neu laden | Diagnosen passen zum neuen Text |
| PP6 | IDE in den Hintergrund, nach einer Minute zurück | Sofort aktuell |
| PP7 | Inlay-Hints an; helles und dunkles Editorthema; Strg+Mausrad; Schriftgröße in den Editoroptionen ändern | Marken gleich aussehend wie vorher; der Editortext danach unverändert (keine kleinere Schrift „hängengeblieben“) |
| PP8 | Vervollständigung öffnen, Monitor mit anderer DPI, Editorzoom ändern | Zeilen-, Chip- und Fußzeilenhöhe passen sofort |
| PP9 | Detailpanel mit langer Deklaration, Panel breiter und schmaler ziehen | Umbruch wie bisher, folgt der Breite |
| PP10 | Hover über einer Zeile mit blasser Warnung | Farbe so blass wie die Wellenlinie im Editor |
| PP11 | Chips im Hover (Vererbung), Tags in Vervollständigung und Detailpanel | Gleicher Innenabstand und gleiche Rundung; Scroll-Daumen in Liste und Doku gleich grau |

## Gemeinsamer Code Atlas.Text (ADR 0012, Code-Review D-01 bis D-06, D-10)

Vorbereitung: Projektgruppe neu gebaut, Plugin installiert, Diagnosemodus an.

| Nr. | Schritte | Erwartet |
|---|---|---|
| TX1 | Plugin Win32 und Win64 bauen (Delphi 12 und 13), IDE starten | 0 Fehler, 0 Warnungen, 0 Hinweise (kein W1033); unter *Komponenten › Packages installieren* nur `Atlas.IDE.Expert…bpl`, kein `Atlas.Text` oder `Atlas.Common`; Plugin lädt und entlädt wie bisher |
| TX2 | Gesamte Projektgruppe `Atlas.groupproj` neu erzeugen (Win32, Win64) | Reihenfolge Text → Common → Windows → Server/Tests; 0/0/0; `Atlas.Tests` grün |
| TX3 | ANSI-Datei mit Umlauten (CP1252) und eine Datei mit den Bytes `ED A0 80` ohne BOM über eine Server-Code-Aktion ändern, ohne sie im Editor zu öffnen; danach öffnen | Umlaute unverändert; Statusfeld „Datei“ zeigt bei beiden ANSI; Server und Plugin melden dieselbe Kodierung |
| TX4 | *Atlas › Fehlerbericht* mit Projekt unter `C:\Users\<Name>\…` | Pfade `<ws>\…` bzw. `<pfad>`, Benutzer `<benutzer>`, Text in Anführungszeichen `<wert>`; Plugin- und Serverteil gleich |
| TX5 | Vervollständigung: `stl` in einer Unit mit `TStringList`, dann `myLis` bei `ERROR_TOO_MANY_LINKS` (Windows-Units im Suchpfad), weitertippen | `TStringList` bleibt in der Liste; `ERROR_TOO_MANY_LINKS` erscheint nicht, auch nicht kurz |
| TX6 | Datei auf Laufwerk `C:` öffnen, Hover, Strg+Klick, Umbenennen über zwei Dateien | funktioniert wie vorher; das Protokoll im Diagnosemodus zeigt URIs mit `file:///c%3A/…` |
| TX7 | `settings.json` mit `// Kommentar` und CR-only-Zeilenenden speichern, Optionen öffnen | Einstellungen werden gelesen, keine Fehlermeldung |
| TX8 | Info-Dialog und Startbildschirm, `AtlasServer --version`, Titel des Installers | überall dieselbe Version |

## Vervollständigung nach Umbau (Code-Review S-01)

Vorbereitung: Projektgruppe neu gebaut (Delphi 12 und 13), Plugin installiert. Der Umbau soll nichts Sichtbares ändern; jeder Fall verhält sich wie vor dem Umbau.

| Nr. | Schritte | Erwartet |
|---|---|---|
| CU1 | In einer Methode `Sel` tippen, dann `Self.` | sichtbare Namen bzw. Mitglieder samt geerbter wie bisher, unscharfe Auswahl |
| CU2 | Name aus einer nicht eingebundenen Unit wählen (LF- und CRLF-Datei) | uses-Eintrag wird ergänzt |
| CU3 | `{$` und `{$WARN ` tippen | Direktiven bzw. Warnungsbezeichner |
| CU4 | `X := ` bei Aufzählungstyp, `case`-Zweig, Menge `[…]` | Aufzählungswerte, „Alle Werte einfügen“, Häkchen bei vorhandenen |
| CU5 | Unbekannten Namen im Rumpf tippen | Angebote zum Anlegen von Variable, Feld, Konstante |
| CU6 | Klasse mit Interface ohne Methoden, in der Deklaration vervollständigen | fehlende Interface-Methoden |
| CU7 | In Formularmethode Komponentennamen, `Sender.` im Ereignis-Handler, `FieldByName('` | Komponenten, Member des gemeinsamen Vorfahren, Feldnamen |
| CU8 | `TStringList.Create;` mit `;` abschließen | nur „Mit try…finally absichern“ |
| CU9 | `Ausdruck.` mit Postfix-Vorlage, `/prop` am Zeilenanfang | Vorlagen wie bisher, `completionItem/resolve` liefert Details |

## Rollenmatrix (Code-Review A-10, A-12)

Vorbereitung: Repository-Ordner als Projekt geöffnet (die `atlas.json` im Wurzelordner schaltet beide Regeln mit `prefixes` ein).

| Nr. | Schritte | Erwartet |
|---|---|---|
| AR1 | In `Atlas.Common.Logging.Contract` `uses Atlas.Common.Logging.Providers.Logger` eintragen | Warnung `architecture-role-import` am uses-Eintrag: „… (eigene Providers aus Contract)“ |
| AR2 | In `atlas.json` die Regel auf `"severity": "off"` setzen | Warnung verschwindet |
| AR3 | In eine `*.Contract`-Unit `TFoo = class end;` im interface schreiben | Warnung `architecture-contract-content` am Typnamen; `EFoo = class(Exception);` bleibt ohne Meldung |
| AR4 | Ein Projekt ohne `prefixes` in `atlas.json` öffnen, Profil `strict` | Keine Meldung der beiden Regeln |
| AR5 | Undo-Einstellungen unter *Optionen › Atlas* ändern, speichern, wieder öffnen; Atlas-Änderung über zwei Dateien zurücknehmen | Werte bleiben erhalten; Zurücknehmen wie bisher |
| AR6 | Server-Protokoll mit Mitschnitt (`--trace`), Parameter-Hint und Hover in einer Unit mit `{$I}`-Datei | Mitschnitt rotiert wie bisher; Hint und Hover funktionieren auch in der Include-Datei |

## Plugin-Struktur: Laden, Entladen, Workspace-Edits (Code-Review S-03, A-09)

| Nr. | Schritte | Erwartet |
|---|---|---|
| PS1 | IDE mit Atlas starten, *Komponenten › Packages installieren* › Atlas abwählen, wieder anwählen | Keine Zugriffsverletzung; Protokoll „Atlas entladen in … ms; Hintergrund-Threads beendet: True“; nach dem Wiederladen Menü, Palette, Statusfeld, Vervollständigung, Parameter-Hint und Willkommensseite wie zuvor |
| PS2 | Abgesichert starten (Stufe „abgesichert“, wie AS5) | Server, Statusfeld, Palette, Menü, Ergebnisfenster, Änderungsprotokoll, Notizen und Lesezeichen (Befehle), Willkommensseite da; keine Klammerfarben, keine Rinne, kein Designer-Notifier, kein Wächter, keine Tastenkürzel-Tipps |
| PS3 | Mit Umschalt starten (Stufe „minimal“, wie AS11) | Nur Optionsseite, Statusfeld und Schnellschalter; Entladen danach ohne Fehler |
| PS4 | Bei PS2 „Schnellschalter…“, „Klammerfarben“ und „Prüfung beim Speichern“ einschalten | Klammerfarben sofort; nach dem nächsten Speichern prüft Atlas (Compiler-Ereignisse werden nachgemeldet) |
| PS5 | IDE mit offener Willkommensseite, sichtbaren Tastenkürzel-Tipps und offener Befehlspalette schließen | Kein Fehler beim Beenden; Zählung der Befehle gespeichert (beim nächsten Start „Atlas entdecken“ unverändert) |
| PS6 | Umbenennen über drei Units, eine davon nicht geöffnet (Workspace-Edit mit Änderungen in offenen und geschlossenen Dateien) | Offene Puffer geändert (je ein Strg+Z-Schritt), die geschlossene Unit auf der Platte in ihrer Kodierung; ein Satz im Änderungsprotokoll |
| PS7 | Code-Aktion, die eine Unit anlegt und eine bestehende ändert; danach Strg+Alt+Z | Neue Unit im Projekt und im Editor; Zurücknehmen trägt sie aus und legt sie in den Papierkorb |
| PS8 | Workspace-Edit auf eine schreibgeschützte Datei | Meldung mit dem Dateinamen, keine der übrigen Dateien halb geändert |
| PS9 | Versionsverwaltung: Willkommensseite mit Git-Projekt öffnen, dann git aus `PATH` nehmen und IDE neu starten | Erst Branch und Zustand; danach einmal „git nicht gefunden“ in der Meldungsansicht, Atlas arbeitet weiter |

## Bauen beim Öffnen (`build.onOpen`)

Vorbereitung: Plugin (Win32 und Win64) gebaut und installiert; unter *Tools › Optionen › Atlas › Compiler* „Einmal bauen:“ auf „Compilieren (Make)“, „In einer Projektgruppe:“ auf „alle Projekte“, Wartezeit 3000 ms; Benachrichtigungszentrale an. Für die Fälle mit „Hintergrund“ in den IDE-Optionen die Hintergrundcompilierung einschalten (*Tools › Optionen › IDE › Compilieren und Ausführen*), sonst aus.

| Nr. | Schritte | Erwartet |
|---|---|---|
| OB1 | `Atlas.Tests` bauen und ausführen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TAtlasOpenBuildTests`, `BuildOnOpenOptions`, `OpenBuildRoundTrip` grün |
| OB2 | Standardeinstellungen, Projekt öffnen | Nichts wird gebaut (standardmäßig aus) |
| OB3 | Einzelprojekt öffnen und 3 s nichts tun | Das Projekt wird einmal compiliert (Fortschrittsdialog der IDE bzw. Statusleiste); Eintrag „Build fertig“ in der Benachrichtigungszentrale; keine Zusammenfassung |
| OB4 | Projektgruppe mit drei Projekten öffnen | Alle drei werden in der Reihenfolge der Gruppe in einem Lauf compiliert; dazu ein Eintrag „Beim Öffnen gebaut: 3 von 3 erfolgreich“ (Quelle „Bauen beim Öffnen“) |
| OB5 | Gleich nach dem Öffnen weiter tippen bzw. klicken | Der Bau beginnt erst, wenn 3 s keine Eingabe kam |
| OB6 | Nach OB4 ein Projekt der Gruppe in der Projektverwaltung aktivieren, eine Datei speichern, dann ein weiteres Projekt zur Gruppe hinzufügen | Nur das neue Projekt wird gebaut, die übrigen nicht noch einmal (einmal je Öffnen) |
| OB7 | Gruppe schließen und wieder öffnen | Alle Projekte werden wieder gebaut |
| OB8 | „In einer Projektgruppe:“ auf „nur das aktive Projekt“, Gruppe öffnen | Nur das aktive Projekt wird gebaut |
| OB9 | Ein Projekt mit Compilerfehler in der Gruppe | Fortschrittsdialog schließt ohne Klick; Eintrag „Build fertig: 1 Fehler“ mit „Zum Fehler“ und Zusammenfassung „Beim Öffnen gebaut: 2 von 3 erfolgreich“ mit „Fehlgeschlagen: <Name>“ (Fehler-Plakette) |
| OB10 | Hintergrundcompilierung der IDE an, Gruppe öffnen | Die IDE bleibt während des Baus bedienbar; die Zusammenfassung kommt nach dem Ende des Laufs |
| OB11 | „Nicht bauen“ auf den Namen eines Projekts der Gruppe (z. B. `Atlas.IDE.Expert`), Gruppe öffnen | Dieses Projekt wird ausgelassen, die übrigen gebaut |
| OB12 | „Einmal bauen:“ auf „Syntaxprüfung“ bzw. „Erzeugen (Build)“ | Die Gruppe wird geprüft (keine .exe/.dcu neu) bzw. vollständig neu erzeugt |
| OB13 | Projekt öffnen und sofort mit F9 starten bzw. Strg+F9 drücken | Atlas wartet, bis Debugger bzw. Build des Benutzers beendet sind, und baut danach einmal |
| OB14 | DUnitX-Testprojekt mit „Tests nach dem Build“ (#69) an öffnen | Das Testprojekt wird gebaut, die Tests laufen nicht (kein Build des Benutzers) |
| OB15 | Release-Konfiguration mit Befund und `build.gate = block` (#533) aktiv, Projekt öffnen | Der Release-Wächter meldet die Befunde; Zusammenfassung „Nicht gebaut: <Name>“ mit Grund |
| OB16 | IDE mit „Projekt beim Start laden“ starten | Das geladene Projekt bzw. die Gruppe wird nach dem Laden einmal gebaut |
| OB17 | Schnellschalter „Beim Öffnen einmal bauen“ aus, Projekt öffnen; Quelle „Bauen beim Öffnen“ auf „Aus“ | Kein Bau; bei aus geschalteter Quelle keine Zusammenfassung, die Einträge „Build fertig“ bleiben |
| OB18 | Abgesicherter Start (#722) | Kein Bau beim Öffnen |

## Einstellungen exportieren, importieren und zurücksetzen (#723)

Vorbereitung: Plugin (Win32 und Win64) gebaut und installiert; `settings.exportImport`, `settings.markModified` und `settings.backupBeforeImport` an, `settings.exportSecrets` = `omit`. Einige Einstellungen geändert (z. B. *Editor* „Notizen“ aus, *Vervollständigung* „Sichtbare Zeilen“ 12, *Compiler* „Tests nach dem Build“ an). Ein Projekt mit `atlas.json`, das `tests.afterBuild` setzt. Ordner `%APPDATA%\Atlas\Backups` vorher leeren.

| Nr. | Schritte | Erwartet |
|---|---|---|
| EI1 | `Atlas.Tests` bauen und ausführen | 0 Fehler, 0 Warnungen, 0 Hinweise; `TAtlasSettingsCatalogTests`, `TAtlasSettingsTransferTests`, `TAtlasSettingsTransferUiTests`, `TSetupSettingsCommandTests`, `TSetupInstallerTests` und `TAtlasQuickTogglesTests` grün |
| EI2 | *Tools › Optionen › Atlas* öffnen | Unten die Knöpfe „Exportieren…“, „Importieren…“, „Profil laden…“ und darunter „Seite zurücksetzen“, „Alles zurücksetzen…“ auf jeder Seite; vor „Notizen“, „Sichtbare Zeilen“ und „Tests nach dem Build“ ein Punkt „●“, Tooltip „Vom Standard geändert; Rechtsklick setzt zurück.“ (**Abnahme**) |
| EI3 | Auf der Seite *Allgemein* „Export, Import und Zurücksetzen“ ausschalten | Die Knopfleiste verschwindet sofort; nach OK fehlen die vier Befehle „Einstellungen …“ in der Befehlspalette; wieder an: Knöpfe und Befehle zurück (**Abnahme**) |
| EI4 | „Geänderte Werte markieren“ ausschalten bzw. wieder an | Alle Punkte verschwinden bzw. erscheinen wieder; ein Kästchen auf seinen Standard zurückklicken nimmt seinen Punkt sofort weg |
| EI5 | Rechtsklick auf „Notizen“ (Kästchen) bzw. auf die Beschriftung „Sichtbare Zeilen“ › „Auf Standard zurücksetzen“ | Wert auf Standard, Punkt weg; „Abbrechen“ verwirft, „OK“ speichert (**Abnahme**) |
| EI6 | Seite *Vervollständigung*: „Seite zurücksetzen“ bzw. Rechtsklick › „Ganze Seite auf Standard zurücksetzen“ | Nur die Werte dieser Seite gehen auf den Standard, „Notizen“ (Seite *Editor*) behält den Punkt (**Abnahme**) |
| EI7 | „Exportieren…“, alle Bereiche, „Speichern…“ nach `D:\Temp\atlas-settings.json` | Meldung „N Werte nach … exportiert.“; die Datei (UTF-8, CRLF) enthält `format`, `formatVersion`, `schemaVersion`, `atlasVersion`, `areas` und unter `settings` nur die geänderten Schlüssel (`notes.enabled`, `completion.visibleRows`, `tests.afterBuild` …), keine Fensterbreiten, keinen Serverpfad, keinen Pfad mit dem Benutzernamen |
| EI8 | In EI7 nur „Editor“ wählen | Nur Schlüssel des Bereichs Editor in der Datei |
| EI9 | Unter *Willkommensseite* „Adresse für Fehlerberichte“ auf `https://name:geheim@example.org/issues` setzen, exportieren; dann „Zugangsdaten beim Export“ auf „Platzhalter“, erneut exportieren | Erst fehlt der Schlüssel, die Meldung nennt ihn unter „Ausgelassen (Zugangsdaten oder Benutzerpfad)“; dann steht `"<secret>"` darin; das Passwort steht in keiner Datei und nicht im Protokoll |
| EI10 | Einstellungen zurück auf Standard, „Importieren…“ mit der Datei aus EI7 | Vorschau mit Spalten Einstellung, Bereich, Aktuell, Neu, Hinweis; geänderte Werte angehakt; Tastenkürzel als Text (z. B. „Strg+Umschalt+P“); bei `tests.afterBuild` der Hinweis „im Projekt überdeckt: atlas.json: tests.afterBuild = …“; „2 von 3 Werten gewählt“ nach Abwahl einer Zeile (**Abnahme**) |
| EI11 | In EI10 eine Zeile abwählen, „Übernehmen“ | Meldung „N Werte übernommen.“ und „Sicherung: …\Backups\atlas-settings-JJJJMMTT-HHMMSS.json“; die Seite zeigt sofort die neuen Werte mit Punkten, die abgewählte Zeile bleibt unverändert; die Sicherung enthält den alten Stand (**Abnahme**) |
| EI12 | Datei aus EI7 mit Texteditor um `"gibt.esNicht": 1` und `"completion.visibleRows": "viele"` ergänzen, importieren | Beide Zeilen ohne Kästchen, Hinweis „unbekannt, übersprungen“ bzw. „ungültig, übersprungen: …“; der Rest lässt sich übernehmen |
| EI13 | Alte Datei ohne `schemaVersion` mit Registry-Namen (`{"format":"atlas-settings","formatVersion":1,"settings":{"Notes":0}}`) importieren | Zeile `notes.enabled`, neu `false`, Hinweis „umgerechnet aus Notes“ |
| EI14 | Import mit „Ersetzen“ und nur Bereich „Editor“ | Alle Editor-Werte, die in der Datei fehlen, gehen auf den Standard („(Standard)“ in Spalte Neu); andere Bereiche bleiben |
| EI15 | „Profil laden…“ › „Minimal“, dann „Alles an“, dann „Atlas-Standard“ | Liste mit Beschreibung; Doppelklick lädt; jede Vorschau zeigt die Änderungen; „Atlas-Standard“ setzt alles zurück (Modus Ersetzen); Projektwerte bleiben (**Abnahme**) |
| EI16 | „Alles zurücksetzen…“ › „Nein“, dann › „Ja“ | „Nein“ ändert nichts; „Ja“ sichert, setzt alle persönlichen Einstellungen auf den Standard, keine Punkte mehr; Fensterbreiten und Serverpfad bleiben (**Abnahme**) |
| EI17 | `settings.backupBeforeImport` aus, importieren | Keine neue Datei unter `Backups`; mehr als zehn Importe mit Sicherung: nur die zehn neuesten bleiben |
| EI18 | Befehlspalette: „Einstellungen exportieren…“, „Einstellungen importieren…“, „Einstellungsprofil laden…“, „Alle Einstellungen zurücksetzen…“ | Dieselben Dialoge mit den gespeicherten Werten; nach Import bzw. Zurücksetzen wirken die Werte sofort |
| EI19 | IDE schließen; `AtlasSetup /exportSettings D:\Temp\a.json`, dann `/importSettings minimal /quiet`, `echo %ERRORLEVEL%`, `/resetSettings /areas:build`, `/importSettings D:\Temp\fehlt.json`, `/bunt` mit `/resetSettings` | Meldungen „exportiert“, keine Meldung und 0, „zurückgesetzt“ samt Sicherung, „Datei nicht gefunden“ (Exit-Code 2), Aufrufhilfe (Exit-Code 1); IDE starten: Werte aus „Minimal“ bzw. zurückgesetzter Bereich Build (**Abnahme**) |
| EI20 | Neu installieren | Ordner `Profile` mit `alles-an.json`, `atlas-standard.json`, `minimal.json` im Installationsordner |
| EI21 | Seite *Tastenkonflikte* und *Projektdatei* | Keine Punkte (Deutung siehe PR), Knopfleiste vorhanden; Projektwerte (Reiter *Projektdatei*) werden weder exportiert noch überschrieben |
| EI22 | IDE-Thema hell ↔ dunkel, 100 %, 150 %, 200 % | Dialoge und Knopfleiste lesbar, nichts abgeschnitten; Punkte gut sichtbar |
| EI23 | Protokoll (`%LOCALAPPDATA%\Atlas\Logs`) nach EI7–EI19 | Keine Dateipfade, Werte oder Benutzernamen aus Export und Import |
| EI24 | Tipps „Einstellungen exportieren“, „… importieren“, „Einstellungsprofil laden“, „… zurücksetzen“ auf „Atlas entdecken“ | Bild und Text passend; mit `settings.exportImport` aus erscheinen sie nicht |
