# Argus: Testfälle in der IDE

Manuelle Prüfung des IDE-Plugins `Argus.IDE.Expert` in RAD Studio, gegliedert nach Issues. Voraussetzung: Plugin installiert (`Output\Win32\Debug\Bpl\Argus.IDE.Expert.bpl`), Code Insight-Manager „Argus IDE Expert“ aktiv, ein Delphi-Projekt mit einer VCL-Unit geöffnet. Für Fehlersuche `Diagnose` = 1 unter `HKCU\Software\Argus\IdePlugin` setzen; das Protokoll `Argus.IDE.Expert.log` liegt neben der BPL.

Schreibweise: `|` steht für die Cursorposition.

## Einstellungen (#227, #407, #413)

| Nr. | Schritte | Erwartet |
|---|---|---|
| E1 | Tools › Optionen › Drittanbieter › Argus öffnen | Seite „Argus“ mit Schaltern, Zeilenzahl, „Verlauf zurücksetzen“, „Breiten zurücksetzen“; auch über die IDE-Suche („Argus“) erreichbar |
| E2 | „Argus aktiv“ ausschalten, OK, dann `List.` tippen | Die eingebaute Code Insight der IDE erscheint (kein Argus-Popup); ohne IDE-Neustart |
| E3 | Wieder einschalten | Argus-Popup erscheint wieder; nie zwei Popups gleichzeitig |
| E4 | Sichtbare Zeilen auf 15, OK, Popup öffnen | Liste zeigt 15 Zeilen; Bild↑/Bild↓ springt um 15 |
| E5 | IDE neu starten, Seite erneut öffnen | Werte sind erhalten (Registry `HKCU\Software\Argus\IdePlugin`) |

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
| R4 | Optionen › Argus › „Geerbte Member … gruppiert“ aus | Flache Liste ohne Überschriften, nicht abgeschwächt |
| R5 | Oben in der Liste die Chips ansehen (#422) | „Alle n“, „Methoden n“, „Eigenschaften n“ …; nur Chips mit Treffern |
| R6 | Alt+2 bzw. Klick auf „Methoden“ | Nur Methoden; Zahlen stimmen; Popup schließen und wieder öffnen → wieder „Alle“ |
| R7 | Dreimal `Lines.BeginUpdate` über die Liste übernehmen, dann `Lines.` | `BeginUpdate` steht vor `Add`, Marke „zuletzt“ |
| R8 | Einen Eintrag fünfmal übernehmen, danach einen anderen | Erster Eintrag mit Marke „häufig“ |
| R9 | Optionen › Argus › „Verlauf zurücksetzen“, OK, dann `Lines.` | Keine Marken, ursprüngliche Reihenfolge |
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
| B6 | Tools › Optionen › Argus › „Breiten zurücksetzen“, OK | Wie B5 |

## Übernehmen

| Nr. | Schritte | Erwartet |
|---|---|---|
| U1 | `myList := TStringL|ist.` (Cursor mitten im Wort), Strg+Leer, `TStringList` mit Enter | `myList := TStringList.` – kein Rest „ist“ |
| U2 | `TStringL` tippen und mit `.` übernehmen | `TStringList.` |
| U3 | `List.Ad`, `Add` mit Enter übernehmen (#430) | `List.Add(|)`, Cursor zwischen den Klammern, Parameter-Hint offen |
| U4 | `List.Cle`, `Clear` mit Enter | `List.Clear` ohne Klammern |
| U5 | Bei U3 `'x'` tippen, dann `)` | `List.Add('x')` – keine doppelte Klammer |
| U6 | `List.Add(` steht schon da, Cursor vor `(` in `Ad|(`, Strg+Leer, Enter | Keine zweite Klammer |
| U7 | Optionen › Argus › „Klammern … ergänzen“ aus | `Add` ohne Klammern |
| U8 | Optionen › Argus › „Vorschau … im Editor“ an; `List.AddS` am Zeilenende (#434) | Hinter dem Cursor kursiv und blass `trings`; folgt der Auswahl mit ↑/↓ |
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
| H1 | Maus 0,5 s über `BeginUpdate` (in `Lines.BeginUpdate`) halten | Argus-Tooltip unter dem Wort: eingefärbte Deklaration, „System.Classes“, Beschreibung (höchstens 4 Zeilen); kein zweiter IDE-Tooltip |
| H2 | Maus vom Wort in den Tooltip bewegen | Tooltip bleibt offen |
| H3 | Maus aus Wort und Tooltip heraus | Tooltip schließt nach etwa 0,3 s |
| H4 | Bei offenem Tooltip tippen, klicken oder scrollen | Tooltip schließt sofort |
| H5 | Über einer Konstante verweilen | Zusätzlich „= Wert“ |
| H6 | Optionen › Argus › „Eigener Tooltip …“ aus | Wieder der Tooltip der IDE |
| H7 | Bei offenem Tooltip mit Alt+Tab in ein anderes Programm wechseln (#414) | Tooltip verschwindet nach spätestens 0,25 s und bleibt nicht über dem anderen Programm stehen |

## Hover-Navigation (#588)

| Nr. | Schritte | Erwartet |
|---|---|---|
| HN1 | Über `TGalleryFrameClass` in `TGalleryFrameClass = class of TBFrame;` verweilen | Kurzform ohne Pfadzeile; Kopfzeile „Klassenreferenz“, rechts Datei : Zeile; `TBFrame` unterstrichen; Abschnitt „Zieltyp TBFrame“ mit der Kette von TBFrame |
| HN2 | Auf `TBFrame` klicken | Deklaration und Kette von TBFrame, Pfad „TGalleryFrameClass › TBFrame“, „angeheftet“; Maus aus dem Tooltip bewegen: er bleibt offen |
| HN3 | In der Kette auf `TFrame` klicken, dann Rücktaste (bzw. Alt+←) | Wieder TBFrame; der Zurück-Pfeil führt ebenso zurück |
| HN4 | Elfmal auf verschiedene Typen klicken | Pfad beginnt mit „…“, zehn Schritte bleiben |
| HN5 | Esc; dann erneut verweilen | Tooltip schließt; beim nächsten Verweilen wieder die Kurzform |
| HN6 | Angeheftet F12, Umschalt+F12, Strg+C, F1 | Wirken auf den angezeigten Typ: Sprung zu dessen Deklaration; Verwendungen im Meldungsfenster (Gruppe Argus) und „Verwendungen (n)“; Deklaration in der Zwischenablage; DocWiki bei RTL/VCL-Typen |
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

Vorbereitung: MCP eingerichtet (`claude mcp add delphi -- ArgusServer.exe --mcp --root <Projektordner>`); in der IDE einmal Strg+Leer, damit der Argus-Server läuft.

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
| CS6 | Optionen › Argus › „Höchstdauer der Prüfung“ auf 200 setzen, speichern | Meldung „Compilerprüfung nach dem Speichern für … abgeschaltet“; weiteres Speichern prüft nicht mehr |
| CS7 | Danach Strg+Alt+F9 bzw. Palette „Argus: Compiler prüfen“ | Prüfung läuft von Hand |
| CS8 | Optionen › Argus › „Compiler prüft nach dem Speichern“ aus | Keine Prüfung mehr |
| CS9 | Fortschrittsdialog der IDE (falls „Compilerfortschritt anzeigen“ an) | Schließt nach einer fehlgeschlagenen Prüfung von selbst; bei eigenen Builds bleibt er wie gewohnt |
| CS10 | Wächter-Protokoll bei einer langsamen Prüfung | Hänger mit „Argus: Compilerprüfung nach dem Speichern“ |

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

Vorbereitung: Diagnoseprotokoll an (`HKCU\Software\Argus\IdePlugin`, DWORD `Diagnose` = 1), IDE neu starten; Protokoll `Argus.IDE.Expert.log` neben dem Plugin.

| Nr. | Schritte | Erwartet |
|---|---|---|
| C1 | Projekt compilieren (Strg+F9) | Im Protokoll genau einmal „Compile: make App.dproj (Debug, Win32) beginnt“ und „… erfolgreich nach n ms“ |
| C2 | Projekt erzeugen (Umschalt+F9) bzw. Syntaxprüfung | Art „build“ bzw. „check“ |
| C3 | Projektgruppe: „Alle erzeugen“ | „Gruppe build beginnt“, dazwischen jedes Projekt, „Gruppe erfolgreich nach n ms; Code Insight bisher …“ |
| C4 | Fehler einbauen und compilieren | „… fehlgeschlagen nach n ms“ |
| C5 | Im Editor tippen (Code Insight kompiliert im Hintergrund) | Keine Compile-Zeilen; die Zahl „Code Insight bisher n-mal“ steigt beim nächsten Gruppenlauf |
| C6 | IDE schließen bzw. Package über Komponenten › Packages installieren aus- und wieder einschalten | Keine Zugriffsverletzung, danach keine doppelten Zeilen |

Abbruch mit Grund im Meldungsfenster („Argus“) ist im Dienst vorhanden und getestet; einen Teilnehmer, der abbricht, bringen erst #529/#530.

## Probleme im Editor (#398, #528, #548)

| Nr. | Schritte | Erwartet |
|---|---|---|
| PR1 | In einer Unit `if then` tippen und kurz warten | Nach etwa einer halben Sekunde rote Wellenlinie unter der Stelle |
| PR2 | Maus über die Wellenlinie, auch über `;` oder Leerraum | Tooltip mit roter Leiste, Meldung, darunter „Argus“; über einem Bezeichner zusätzlich der normale Hover darunter |
| PR3 | Regeltreffer (z. B. unbenutzte Variable) | Gelbe Wellenlinie, Tooltip mit Regel-ID in Klammern |
| PR4 | Oberhalb eines Problems Zeilen einfügen | Die Markierung wandert sofort mit, ohne zu flackern |
| PR5 | Strg+F9 mit einem Compilerfehler | Rote Wellenlinie an der Stelle des dcc-Fehlers, im Tooltip „Compiler“ |
| PR6 | Danach in der Zeile tippen | Compilermarkierung wird blass („seit dem letzten Prüfen geändert“), bis zum nächsten Compile |
| PR7 | Meldungsfenster, Reiter „Argus-Probleme“ | Probleme aller Projektdateien (auch nicht geöffneter), ohne Compilermeldungen; Doppelklick springt zur Stelle |
| PR8 | Problem beheben | Wellenlinie und Eintrag in der Liste verschwinden |
| PR9 | Datei im Editor schließen, außerhalb ändern | Liste zeigt den Stand der Datei auf der Platte |
| PR10 | Optionen › Argus › „Probleme im Editor unterstreichen …“ aus | Keine Wellenlinien, Liste leer, keine Probleme im Tooltip |

## Klammer- und Blockpaare (#514)

| Nr. | Schritte | Erwartet |
|---|---|---|
| KP1 | Methode mit drei verschachtelten `begin`/`end` | Drei verschiedene Farben; zusammengehörige `begin`/`end` gleich |
| KP2 | `try … finally … end`, `repeat … until` | `finally` und `end` in der Farbe ihres `try`, `until` wie `repeat` |
| KP3 | `Format('(%d', [Length(S)])` | `(` im String ungefärbt, Klammern nach Tiefe |
| KP4 | Ein `end;` löschen | Das unpaarige `begin` wird rot |
| KP5 | `TFoo = class` … `end;`, `class function`, `TBar = class;`, `procedure … of object` | Nur die Klassendeklaration mit Rumpf ist ein Paar |
| KP6 | Text markieren | Markierung wie gewohnt (Argus färbt markierten Text nicht) |
| KP7 | Helles und dunkles IDE-Thema | Farben in beiden lesbar |
| KP8 | Optionen › Argus › „Klammern und Blockpaare … färben“ aus | Normale Farben der IDE |
| KP9 | Teile des Editors neu zeichnen lassen (Tooltip, Vervollständigung schließen, scrollen) | Keine Paarfarben mitten in Bezeichnern |
| KP10 | Sechs verschachtelte `begin`/`end` | Senkrechte Linie je Block in der Farbe ihres Wortpaars, Haken an `begin` und `end` |
| KP11 | `TFoo = class` … `end;`, `if A then begin` … `end;` | Linie vor `TFoo` bzw. vor `if` |
| KP12 | Erster Start mit Blocklinien | Meldung im Meldungsfenster; ab dem nächsten Start keine Linien der IDE mehr |
| KP13 | Optionen › Argus › „Blocklinien in den Paarfarben“ aus, Delphi neu starten | Keine Argus-Linien; Strukturhervorhebung der IDE wieder an |

Blocklinien zeichnet Argus selbst (Einstellung „Blocklinien in den Paarfarben“). Solange sie an sind, ist die Strukturhervorhebung der IDE in der Registry abgeschaltet (`Editor\Highlight\Structural Highlighting`, `Enabled`). Die IDE liest das nur beim Start. Hat der User sie selbst abgeschaltet, ändert Argus nichts.

## Befehlspalette (#502)

| Nr. | Schritte | Erwartet |
|---|---|---|
| BP1 | Im Editor Strg+Umschalt+P | Palette oben mittig über dem aktiven Fenster, sofort (unter 100 ms), Eingabefeld mit „>“ |
| BP2 | `bpj` tippen bzw. `pe` (deutsche IDE) | „Projekt erzeugen“ bzw. „Build Project“ in der Liste, getroffene Zeichen hervorgehoben; Menüpfad gedimmt, Tastenkürzel rechts |
| BP3 | Enter | Befehl läuft (Projekt wird erzeugt); Palette ist zu |
| BP4 | Strg+Umschalt+P erneut, nichts tippen | Der eben ausgeführte Befehl steht oben |
| BP5 | `argus` tippen | Argus-Befehle („Argus: Protokoll öffnen“, „Argus: Verlauf … zurücksetzen“, „Argus: Wächter testen (1 s)“) gemeinsam mit IDE-Aktionen |
| BP6 | „Argus: Protokoll öffnen“ | `Argus.IDE.Expert.log` öffnet sich im Editor |
| BP7 | Esc bzw. Klick neben die Palette | Palette schließt, nichts wird ausgeführt |
| BP8 | ↑/↓, Bild↑/↓, Mausrad, Klick auf eine Zeile | Auswahl bewegt sich, Klick führt aus |
| BP9 | Rücktaste, Strg+Rücktaste | Ein Zeichen bzw. ganze Eingabe gelöscht |

Abgrenzung: IDE Insight (Strg+.) ist modal und durchsucht auch Optionen und Komponenten, kennt aber keine Argus-Befehle und keinen Verlauf. Strg+Umschalt+P ist in der IDE „Tastenmakro abspielen“; die Palette übernimmt das Kürzel. Noch offen: Strg+Enter (Kürzel zuweisen).

## Extern geänderte Dateien (#536)

| Nr. | Schritte | Erwartet |
|---|---|---|
| X1 | Mehrere Units öffnen (gespeichert), im Terminal `git checkout` eines Branches, der sie ändert; zurück in die IDE | Kein Dialog „time/date changed. Reload?“; Editor zeigt den neuen Stand; Meldungsfenster, Gruppe „Argus“: „Argus: n Dateien neu geladen“ mit den Dateinamen |
| X2 | Nach X1 im Editor | Cursor und sichtbarer Bereich wie vorher (gleiche Zeile) |
| X3 | Eine Unit mit ungespeicherten Änderungen, Datei extern ändern, zurück in die IDE | Argus fasst den Puffer nicht an; Meldung „… hat ungespeicherte Änderungen; die IDE fragt nach“; danach die Rückfrage der IDE mit Warnung |
| X4 | Offene Unit extern löschen | Meldung „… existiert nicht mehr“, Tab bleibt offen |
| X5 | Unit in der IDE speichern | Kein Neuladen, Rückgängig bleibt erhalten |
| X6 | Optionen › Argus › „Außerhalb geänderte Dateien … neu laden“ aus, X1 wiederholen | Wieder die Rückfragen der IDE |
| X7 | Formular-Unit extern ändern (`.pas` und `.dfm`, z. B. per `git checkout`) | Unit und Formular neu geladen |

Protokoll: jede erkannte Änderung als Zeile „Extern geändert: … (neu laden | ungespeicherte Änderungen, behalten | gelöscht)“.

## Einfrier-Wächter (#501)

Protokoll: `Argus.IDE.Expert.log` neben dem Plugin (Hänger stehen dort immer, auch ohne `Diagnose`).

| Nr. | Schritte | Erwartet |
|---|---|---|
| W1 | Tools › Optionen › Argus › „Wächter testen (1 s)“ | IDE steht 1 s; danach im Protokoll „Hänger ~1000 ms um …; Argus: Wächter-Test, … ms; Fenster: Optionen“, darunter Zeilen `Modul+Offset` (u. a. `Argus.IDE.Expert.bpl`, `kernel*.dll`) und „Sitzung: 1 Hänger …“ |
| W2 | Normal arbeiten ohne Hänger | Keine Hänger-Zeilen im Protokoll |
| W3 | Schwelle auf 2000 setzen, W1 wiederholen | Kein Eintrag (1 s liegt unter der Schwelle) |
| W4 | Schwelle 500, „Hinweis im Meldungsfenster …“ an; einen Hänger über 2 s erzeugen (z. B. großes Projekt öffnen) | Zeile „Argus: Die IDE hat n ms nicht reagiert“ in der Gruppe „Argus“ des Meldungsfensters, kein Dialog |
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
