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

## Rangfolge nach Gültigkeitsbereich (#488)

| Nr. | Schritte | Erwartet |
|---|---|---|
| RB1 | In `function TKasse.Calc(ACustomer: Integer)` mit `var Total` bei `Total := |` Strg+Leer | Reihenfolge `Total` („lokal“), `ACustomer` („Parameter“), `FDiscount` („Feld“) |
| RB2 | Inline-Variable `var Unten := 1;` unterhalb des Carets | `Unten` erscheint nicht |
| RB3 | Lokale Variable `Name`, die das Feld `Name` der Klasse verdeckt | `Name` einmal mit „lokal“; das Detailpanel nennt „Verdeckt: Feld TKlasse.Name“ |
| RB4 | Methode von `Self` und Routine aus einer uses-Unit in der Liste | Tag mit der Klasse bzw. dem Namen der Unit |

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
| W1 | Tools › Optionen › Atlas › „Wächter testen (1 s)“ | IDE steht 1 s; danach im Protokoll „Hänger ~1000 ms um …; Atlas: Wächter-Test, … ms; Fenster: Optionen“, darunter Zeilen `Modul+Offset` (u. a. `Atlas.IDE.Expert370.bpl`, `kernel*.dll`) und „Sitzung: 1 Hänger …“ |
| W2 | Normal arbeiten ohne Hänger | Keine Hänger-Zeilen im Protokoll |
| W3 | Schwelle auf 2000 setzen, W1 wiederholen | Kein Eintrag (1 s liegt unter der Schwelle) |
| W4 | Schwelle 500, „Hinweis im Meldungsfenster …“ an; einen Hänger über 2 s erzeugen (z. B. großes Projekt öffnen) | Zeile „Atlas: Die IDE hat n ms nicht reagiert“ in der Gruppe „Atlas“ des Meldungsfensters, kein Dialog |
| W5 | Mit `Diagnose` = 1 IDE starten | Zeile „Start: Laden des Packages bis zur freien Nachrichtenschleife n ms“ |
| W6 | IDE schließen | Schließt ohne Verzögerung; bei Hängern in der Sitzung steht am Ende „Sitzung: n Hänger, längster …“ |

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
| PZ4 | Klick auf die Zeile (nicht auf eine Marke) | Projekt öffnet sich; solange es offen ist, steht es nicht in der Liste (die IDE führt es dann nicht unter „Closed Projects“) |
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
