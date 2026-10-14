# Atlas IDE Expert in RAD Studio einbinden

Es gibt zwei Wege:

- **Empfohlen: das IDE-Plugin** `Atlas.IDE.Expert` (ADR 0006) für RAD Studio 13 und 12. Es meldet sich als eigener Code Insight-Manager an und bringt eigene Fenster für Vervollständigung, Parameter-Hint und Hover sowie Probleme im Editor, Klammerpaare, Befehlspalette und Compilerprüfung mit (Übersicht in der [README](../README_DE.md)).
- **Eingebauter LSP-Client** (Abschnitt unten). Damit funktionieren Gliederung und Error Insight. Den Hover fremder Server zeigt RAD Studio auf diesem Weg aber nicht an.

## IDE-Plugin

**Mit dem Installer (#495):** `atlas-ide-expert-<Version>.zip` aus dem [Release](https://github.com/xKnockOut/Atlas-IDE-Expert/releases) entpacken und `AtlasSetup.exe` starten. Er zeigt jede gefundene Delphi-Version mit 32- und 64-Bit-IDE, kopiert Plugin und Server nach `%LOCALAPPDATA%\Programs\Atlas` und trägt die BPL unter „Known Packages“ der gewählten IDEs ein. Einzelheiten in [Installation.md](Installation.md#rad-studio-installer). Die Schritte unten sind der Weg ohne Installer, etwa für einen eigenen Bau.

Von Hand:

1. Das Package `Packages\Atlas.IDE.Expert\Atlas.IDE.Expert.dproj` (in der Projektgruppe enthalten) mit der Delphi-Version bauen, in der es laufen soll: für die klassische IDE **Win32**, für die 64-Bit-IDE (ab Delphi 12.3) **Win64**. Ergebnis: `Output\Win32\Debug\Bpl\Atlas.IDE.Expert370.bpl` bzw. `Output\Win64\…`; die Zahl ist die Package-Version (`370` Delphi 13, `290` Delphi 12). Ist das Plugin installiert, sperrt die IDE diese BPL; zum Neubauen das Package vorher entladen.
2. In RAD Studio: *Komponente > Packages installieren > Hinzufügen*, die BPL auswählen.
3. Den Server (`AtlasServer.exe`) mit bauen: Common, Windows und Server für dieselbe Plattform (Win64 empfohlen). Der Server ist ein eigenes Programm und hängt nicht von der Delphi-Version ab.
4. Den Server findet das Plugin in dieser Reihenfolge:
   - *Tools › Optionen › Drittanbieter › Atlas*, Feld „Atlas-Server“ (Registry `HKCU\Software\Atlas\IdePlugin`, Wert `ServerPath`; optional `ServerArguments`, z. B. `--log C:\Temp\atlas.log`). Darunter zeigt die Seite, welcher Server verwendet wird und ob er gefunden wurde.
   - `AtlasServer.exe` neben der BPL
   - `AtlasServer.exe` eine Ebene über der BPL (Aufbau des Installers: `…\Atlas\Win32\Atlas.IDE.Expert370.bpl`, `…\Atlas\AtlasServer.exe`)
   - `..\..\..\Win64\Debug\Bin\AtlasServer.exe`, sonst `..\..\..\Win32\Debug\Bin\AtlasServer.exe`, im Repo also die Build-Ausgabe

Fehlt der Server, meldet das Plugin das im Meldungsfenster und überlässt Vervollständigung und Hinweise der eingebauten Code Insight. Stürzt der Server ab, startet es ihn bei der nächsten Anfrage neu.

Den Umfang des Index stellt *Tools › Optionen › Drittanbieter › Atlas* für alle Projekte ein (#652): alle Projekte der Projektgruppe, alle Units der Projekt-Suchpfade und alle Units der Delphi-Bibliothek. Das Plugin gibt die Werte beim Start und nach jeder Änderung an den Server weiter. Steht `index` in der `atlas.json` eines Projekts, gilt dort die Datei. RTL, VCL und FMX liest der Server einmal je Delphi-Version und Plattform, unabhängig von den Defines des Projekts.

Index und Cache (#492): Der Server legt den Index je Delphi-Version und Projekt unter `%LOCALAPPDATA%\Atlas\Index\<Version>\<Projekt-Hash>\index.atlasidx` ab, die Bibliothek getrennt unter `…\<Version>\Bibliothek\`. Die Datei trägt Formatversion und Prüfsumme; ist sie beschädigt oder veraltet, verwirft der Server sie mit einer Zeile im Protokoll und baut still neu auf. Je Deklaration speichert der Index Signatur, Direktiven (`virtual`, `overload`, `deprecated`, `platform`, …) und den XMLDoc-Kurztext, in Projekt-Units auch die Verwendungen jedes Bezeichners (abschaltbar mit „Verwendungen der Bezeichner mit indizieren“, Registry `IndexUsages`, `index.usages`). Wird die Speichergrenze (Feld „Speichergrenze des Index“, Registry `MemoryBudgetMb`, Standard 256, 0 = ohne Grenze) erreicht, lagert der Server zuerst die Verwendungen aus und lädt sie bei Bedarf aus dem Cache nach, erst danach kürzt er Units. Der Abschnitt „Symbolindex“ der Optionsseite zeigt Units, Deklarationen, Speicher, Größe auf der Platte und die letzte Aktualisierung; die Knöpfe bauen den Index neu auf oder löschen nach Rückfrage alle Caches (`atlas.server.clearIndex`), danach indiziert der Server neu. Während der Server indiziert, ist das Atlas-Feld der Statuszeile gelb („Atlas · Index n %“), und die Vervollständigung vermerkt „eingeschränkt“ in ihrer Fußzeile.

Atlas-Statusfeld (#591): Rechts in der Statusleiste jedes Editorfensters steht „Atlas“ mit einem Punkt: grün (alles in Ordnung), gelb (Index im Aufbau, Server startet oder ist langsam, gemischte Zeilenenden) oder rot (Server gestoppt, Start fehlgeschlagen). Mit „Kurztext neben „Atlas“ zeigen“ (Registry `StatusFieldSummary`) steht daneben der Kurztext der wichtigsten gelben oder roten Zeile, z. B. „Atlas · Index 45 %“. Der Tooltip listet alle Zeilen, die nicht grün sind. Ein Klick öffnet darüber ein Fenster mit je einer Zeile für Server (Zustand, mittlere Antwortzeit der letzten 50 Anfragen, Version), Index (Fortschritt bzw. Anzahl Units) und die aktive Datei (Kodierung und Zeilenende) sowie den Knöpfen „Protokoll öffnen“ und „Server neu starten“; Esc oder ein Klick daneben schließt es. Ein Klick auf die Zeile „Datei“ bietet UTF-8 mit/ohne BOM und ANSI, jeweils mit CRLF oder LF; die Wahl markiert die Datei als geändert, beim Speichern schreibt Atlas sie im gewählten Format (für den Rest der Sitzung bei jedem Speichern). Das Feld lässt sich abschalten (Registry `StatusField`), einzelne Zeilen blendet „Ausgeblendete Zeilen“ aus (Registry `StatusFieldHidden`, Kennungen `atlas.server`, `atlas.index`, `atlas.file`, durch Komma getrennt). Andere Funktionen melden ihre Zeile über `IAtlasStatusRegistry` (`Atlas.Core.Status.Contract`) an, statt eigene Felder anzulegen.

Abgesicherter Start (#722): Wurde die letzte IDE-Sitzung mit Atlas unerwartet beendet (Absturz, Taskmanager) oder lud Atlas länger als `safeMode.startupTimeoutMs` (Registry `SafeStartupTimeoutMs`, Vorgabe 10000 ms), fragt Atlas beim nächsten Start in einem kleinen Fenster unten rechts, ohne den Start aufzuhalten: „Abgesichert starten“, „Normal starten“, „Details“. Abgesichert laufen nur Serververbindung, Statusfeld, Einstellungen, Befehlspalette und Menü; alle Schnellschalter sind für diese Sitzung aus und lassen sich einzeln wieder einschalten (Vorschlag im Fenster). „Normal weiterarbeiten“ meldet alles ohne Neustart an. Nach zwei Abstürzen in 10 Minuten startet Atlas ohne Rückfrage abgesichert. Umschalt beim Laden der Packages (Registry `SafeStartupKey`: shift, ctrl, none), der Schalter `bds.exe -AtlasSafeMode` oder `ATLAS_SAFE_MODE=1` laden nur Einstellungsseite und Statusfeld. Startmarken und Zustand liegen unter `%LOCALAPPDATA%\Atlas\Session`, die gemerkten Einstellungsstände in `%APPDATA%\Atlas\settings-history.json`. Abschalten: auf der Optionsseite *Abgesicherter Start* beide Kästchen aus und Taste „keine“.

Schnellschalter (#604): Ein Rechtsklick auf das Atlas-Feld oder Strg+Umschalt+Alt+A (Registry `QuickToggleKey`, änderbar auf der Seite *Tastenkonflikte*) öffnet über dem Feld das Fenster „Atlas · Schnellschalter“. Es zeigt nach Seiten gruppiert jede boolesche Einstellung, die im Katalog `"x-quickToggle": true` trägt: die Einstellungen des Plugins (`TAtlasQuickToggles.PluginCatalog`, z. B. Klammerfarben, Blocklinien, inaktive Zweige, Probleme, Hover-Tooltip, Filter-Chips) und Schlüssel aus `atlas.schema.json` mit `x-plugin` (z. B. `hints.xmlDocFull`). Ein Klick oder die Leertaste schreibt dieselbe Einstellung wie die Optionsseite und wirkt sofort. Setzt atlas.json des aktiven Projekts den Wert, steht rechts „Projekt“, und Atlas fragt, ob die Änderung nur für diese Sitzung (dann „Sitzung“) oder im Projekt gelten soll. „Alles aus für diese Sitzung“ schaltet alle Zeichnungen im Editor ab (`x-drawing`), ohne Einstellungen zu ändern; „Alles wieder an“ stellt sie wieder her. In der Befehlspalette gibt es je Schalter „Atlas: … ein/aus“, dazu „Atlas: Alles aus für diese Sitzung“ und „Atlas: Schnellschalter öffnen“. Neue Schalter brauchen nur den Eintrag im Katalog.

Update-Prüfung (#495): Beim ersten Start fragt Atlas einige Sekunden nach dem Laden in einem kleinen Fenster unten rechts, ob es auf neue Versionen prüfen soll. Ohne Zustimmung findet keine Netzwerkabfrage statt; ohne Antwort fragt Atlas beim nächsten Start wieder. Mit „Ja, prüfen“ oder dem Kästchen „Einmal täglich nach neuen Versionen sehen“ unter *Tools › Optionen › Drittanbieter › Atlas* (Abschnitt „Updates“, Registry `UpdatesCheck`, `updates.check`, Vorgabe aus) liest Atlas höchstens einmal täglich im Hintergrund die Versionsdatei `atlas-version.json` des neuesten Releases. Übertragen werden nur Atlas- und IDE-Version (`?atlas=0.1.0&ide=37.0`), keine Projektdaten. Ist eine neuere Version da, steht in der Meldungsansicht eine Zeile mit Versionsnummer und Link zu den Änderungen; heruntergeladen oder installiert wird nichts. Der Abschnitt zeigt auch die installierte Version, der Diagnoseexport enthält sie in `atlas-info.txt`. Der Zustand (gefragt, letzte Prüfung) liegt in `%LOCALAPPDATA%\Atlas\updates.json`. Aus: kein Fenster, keine Abfrage, kein Thread.

Was Atlas selbst anzeigt, schaltet es in der IDE ab, damit nichts doppelt erscheint: Help Insight (solange der Atlas-Tooltip an ist) und die Strukturhervorhebung (solange die Atlas-Blocklinien an sind). Die IDE liest diese Schalter nur beim Start; beim ersten Start mit Atlas erscheint daher noch beides.

Bedienung (#399): Das Menü *Atlas* in der Menüleiste und das Untermenü *Atlas* im Kontextmenü des Editors enthalten Code-Aktionen, Auswahl erweitern/verkleinern, Gehe zu Implementierung und Typdefinition, Referenzen und „Qualifizierten Namen kopieren“. Tastenkürzel (änderbar unter *Tools › Optionen › Drittanbieter › Atlas*): Code-Aktionen Alt+Enter, Auswahl erweitern Strg+W, verkleinern Strg+Umschalt+W, Gehe zu Implementierung Strg+Alt+I, Typdefinition ohne Vorgabe. Ist eine Taste schon von der IDE oder einer anderen Erweiterung belegt, bleibt diese Belegung und das Meldungsfenster nennt den Konflikt; der Schalter „Editor-Kürzel auch belegen …“ gibt Atlas Vorrang. Schnellbefehle (`/uses Unit`, `/try` …) werden nach Enter ausgeführt, `///` über einer Deklaration erzeugt das Kommentargerüst; beides lässt sich auf derselben Seite abschalten.

Formular-Designer (#402): Ein im Designer geöffnetes Formular schickt Atlas etwa eine halbe Sekunde nach jeder Änderung an den Server, auch ungespeichert. Referenzsuche, Umbenennen und Prüfungen sehen also neue Komponenten und Ereignis-Zuordnungen sofort. Wird ein Ereignis-Handler umbenannt, ändert Atlas die Unit und setzt die Zuordnung im Designer neu; das Formular ist danach geändert und wird mit der Unit gespeichert. Andere Änderungen an einem offenen Formular (etwa eine Komponente umbenennen) lehnt Atlas mit einer Meldung ab und ändert nichts; nicht geöffnete Formulare schreibt Atlas direkt in die Datei.

Atlas-Änderungen zurücknehmen (#721): Was Atlas in mehreren Dateien auf einmal ändert (Umbenennen, Code-Aktionen, Slash-Befehle, Änderungen vom Server oder über MCP), nimmt Strg+Alt+Z bzw. *Atlas* › „Letzte Atlas-Änderung zurücknehmen“ als Ganzes zurück; Strg+Alt+Umschalt+Z stellt es wieder her. In offenen Dateien ist das je Datei ein Rückgängig-Schritt, Strg+Z im Editor wirkt danach wie gewohnt. *Atlas* › „Atlas-Änderungen…“ listet die letzten Sätze im Ergebnisfenster; das Kontextmenü zeigt den Unterschied und nimmt auch ältere Sätze zurück, wenn die Stellen seitdem unverändert sind. Konflikte stehen mit Dateinamen in der Meldungsansicht. Einstellungen unter *Tools › Optionen › Drittanbieter › Atlas* (Abschnitt „Atlas-Änderungen zurücknehmen“).

Kodierung (#121): Dateien, die nicht im Editor offen sind, ändert Atlas in ihrer bisherigen Kodierung und mit ihren Zeilenenden. Für Dateien ohne BOM gilt dieselbe Vorgabe wie beim Server, die Einstellung `encoding` aus der nächsten atlas.json über der Datei (etwa `"windows-1250"`). Ein binär gespeichertes Formular ändert Atlas nie; die ganze Änderung wird dann mit einer Meldung abgelehnt. Findet der Server im Projekt ANSI-Dateien neben UTF-8-Dateien (Units, Formulare und Include-Dateien), erscheint einmal je Sitzung ein Hinweis im Meldungsfenster unter „Atlas“.

Aufzählungen und Mengen (#448): Erwartet die Stelle einen Aufzählungstyp (nach `:=`, `=`, `<>` oder in einem `case`-Zweig), stehen dessen Werte oben in der Liste, bei `{$SCOPEDENUMS ON}` als `Typ.Wert`. Nach `[` an einer Mengen-Stelle öffnet sich die Liste von selbst und zeigt nur die Elemente mit Häkchen; vorhandene sind schon abgehakt. Leertaste hakt ab, Enter ersetzt die ganze Menge, Esc lässt sie unverändert.

case-Anweisungen (#449): Am Anfang eines Zweigs (nach `case Shape.Kind of` oder nach dem `;` eines Zweigs) steht oben „Alle Werte einfügen“ mit der Zahl der Werte, in einer case-Anweisung mit Zweigen „Fehlende Werte ergänzen (n)“. Atlas schreibt je fehlendem Wert eine Zeile `Wert: ;` in Deklarationsreihenfolge, ergänzt ein fehlendes `end;` und setzt den Cursor vor das `;` des ersten neuen Zweigs. Bereiche (`skCircle..skRect`) und Listen zählen als vorhanden. Ein Rückgängig entfernt alles. Mit getipptem Präfix steht der Eintrag hinter den passenden Werten.

Unbekannte Namen (#471): Kennt Atlas einen getippten Namen im Rumpf einer Routine nicht, steht am Ende der Liste die Gruppe „„Name“ ist unbekannt“ mit „Lokale Variable anlegen“ (im `var`-Abschnitt), „Inline-Variable anlegen“ (nur am Anfang einer Anweisung mit `:=` und ab Delphi 10.3), „Feld FName anlegen“ (in einer Methode; im `private`-Abschnitt, die Verwendung wird umbenannt, wenn die Felder der Klasse mit F beginnen) und „Konstante anlegen“ (wenn der Name als Wert dient; in der implementation). Den Typ leitet Atlas aus der rechten Seite der Zuweisung oder dem erwarteten Typ ab, sonst steht dort `{Typ}`. Fehlt die Unit des Typs, kommt sie ins uses. Stehen nur diese Einträge in der Liste, ist keiner gewählt: Enter macht dann eine neue Zeile, eine Pfeiltaste wählt den ersten. Der Cursor bleibt im Namen, ein Rückgängig nimmt alles zurück.

Interface implementieren (#466): Steht in der Vorfahrenliste einer Klasse ein Interface, dessen Methoden fehlen (auch die seiner Vorfahren, etwa `IFlush` bei `IExporter = interface(IFlush)`), zeigt Strg+Leer auf einer leeren Zeile der Klassendeklaration nur diese Methoden mit Kontrollkästchen, alle angehakt. Die Leertaste hakt ab, Enter legt die angehakten an: Deklarationen vor dem `end` der Klasse in einem Abschnitt nach `completion.interfaceSection` (Standard `public`; steht dieser Abschnitt schon als letzter da, kommt kein neuer), je Interface mit Kommentar `{ IExporter }`, dazu die Rümpfe hinter der letzten Methode der Klasse. Funktionen setzen `Result := Default(<Typ>)`, Prozeduren bleiben leer, ohne `inherited`. Was die Klasse oder eine Vorfahrklasse schon mit gleichem Namen und gleichen Parametertypen hat, zählt als vorhanden. Generische Interfaces wie `IComparer<TKunde>` bekommen die eingesetzten Typen (`function Compare(const Left, Right: TKunde): Integer;`). Wird in der Klasse getippt, steht oben in der Liste der Hinweis „3 Methoden von IExporter fehlen“; er ist nie vorgewählt und legt beim Übernehmen alle fehlenden Methoden dieses Interfaces an. Alles ist ein Rückgängig-Schritt.

Komponenten aus dem Formular (#455): In den Methoden einer Formular-, Frame- oder Datenmodulklasse stehen deren Komponenten als erste Gruppe „Formular frmMain“ in der Liste, rechts mit ihrem Typ. Atlas liest sie aus der Formulardatei; ist das Formular im Designer offen, gilt dessen Stand, eine neu abgelegte Komponente erscheint also ohne Speichern. Gesucht werden kann auch über den Typ: `button` findet `btnSave` (`TButton`) und `btnLoad` (`TBitBtn`, von `TButton` abgeleitet), aber nicht `chkAktiv` (`TCheckBox`); solche Treffer stehen hinter denen über den Namen. Über den Typ sucht Atlas ab zwei Zeichen: Der eigene Klassenname muss ohne „T“ damit beginnen, oder ein Vorfahr muss genau so heißen. Komponenten in eingebetteten Frames gehören zum Frame und erscheinen nicht.

Sender mit Typumwandlung (#480): Nach `Sender.` in einem Ereignis-Handler mit `Sender: TObject` schaut Atlas in der Formulardatei, welchen Komponenten der Handler zugewiesen ist, und zeigt die Member ihres gemeinsamen Vorfahren (bei zwei Buttons `TButton`, bei Button und Label `TControl`) unter der Überschrift „Sender ist TButton · btnSave, btnLoad“, jeweils mit der Marke „als TButton“. Wird einer übernommen, steht danach `(Sender as TButton).Caption`; mit `completion.senderCast` = `"cast"` steht dort `TButton(Sender).Caption`. Ist der Handler keiner Komponente zugewiesen oder bleibt als gemeinsamer Vorfahr nur `TObject`, zeigt die Liste wie bisher die Member von `TObject`.

Feld- und Parameternamen (#461): In `qryOrders.FieldByName('`, `FindField('` und `ParamByName('` öffnet sich die Liste trotz String. Sie zeigt die persistenten Felder der Datenmenge, dann die Spalten ihrer SQL-Anweisung (Aliasnamen gelten) bzw. bei `ParamByName` die `:Platzhalter` und die Einträge der Params-Sammlung, rechts mit dem Typ, sofern bekannt. Die Fußzeile nennt die Anweisung. Übernehmen ersetzt den ganzen String-Inhalt in der Schreibweise der Quelle. Atlas liest das aus der Formulardatei bzw. dem offenen Designer; eine zur Laufzeit erzeugte Datenmenge liefert keine Vorschläge, `select *` keine Spalten (die kommen erst mit dem Schema-Cache aus #462). Datenmengen eines anderen Datenmoduls (`dmMain.qryOrders`) findet Atlas über die globale Variable `dmMain` im Index und die Formulardatei ihrer Unit. Steht im String ein Name, den die Datenmenge nicht kennt, zeigt der Hover „Feld nicht gefunden in qryOrders“ (nur Hinweis).

Freigabe absichern (#489): Nach Übernahme eines Konstruktors in `List := TStringList.Create` öffnet das `;` (auch als Commit-Zeichen) oder Enter am Zeilenende ohne `;` eine kleine Liste „Mit try…finally absichern“, rechts die Freigabe (`List.Free`), Fußzeile „Enter anwenden · weitertippen verwirft“. Enter setzt `try`, eine leere Zeile mit dem Cursor, `finally`, `List.Free;` und `end;` darunter, als ein Rückgängig-Schritt; ein fehlendes `;` setzt Atlas dabei selbst und ersetzt die leere Zeile vom Enter. Folgen bis zum Ende der Routine schon Zeilen, gibt es zusätzlich „Bis Routinenende mit try…finally absichern“. Nicht angeboten wird bei Feldern, `Result`, Interface-Variablen, Records, einem Owner (`Create(Self)`, `Create(Application)`), wenn die Variable später zurückgegeben, zugewiesen, an `Add`/`Insert` übergeben oder schon freigegeben wird, und wenn danach schon `try` steht. `completion.offerTryFinally` schaltet das Angebot ab, `completion.freeStyle` = `"freeAndNil"` schreibt `FreeAndNil(List)`.

Code-Vorlagen (#51): Am Anfang einer Anweisung stehen Vorlagen mit dem Badge `sn` und der Marke „Snippet“ in der Liste: `tryf` (try…finally mit Create/Free), `trye`, `forin`, `fori`, `while`, `repeat`, `class`, `record`, `prop`, `propset` (Setter mit Prüfung auf Änderung und `Invalidate`), `comp` (Komponentengerüst) und `reg` (Register-Prozedur). Enter setzt die Vorlage mit der Einrückung der Zeile ein und markiert den ersten Platzhalter; Tippen ersetzt ihn, gleich nummerierte Platzhalter ändern sich mit. Tab springt weiter, Umschalt+Tab zurück, nach dem letzten an die Endposition; Enter springt dorthin und beendet, Esc beendet an Ort und Stelle. Der aktuelle Platzhalter ist umrahmt, verknüpfte gestrichelt, dahinter steht „Platzhalter 1 / 2 · Tab weiter · Esc fertig“. Eigene Vorlagen liegen als `*.atlas-snippet` in `%APPDATA%\Atlas\Snippets` (Atlas liest den Ordner bei Änderung neu; fehlerhafte Dateien überspringt es) und ersetzen mitgelieferte mit gleichem Kürzel:

```
name: Liste anlegen
prefix: lst
description: TStringList mit Freigabe
---
${1:Items} := TStringList.Create;
try
  $0
finally
  ${1}.Free;
end;
```

`${1:Name}` ist ein Platzhalter mit Vorgabe, `${2}` einer ohne, `$0` die Endposition; `$FF` und andere Hexzahlen bleiben Text. Abschalten unter *Tools › Optionen › Drittanbieter › Atlas* („Code-Vorlagen (Snippets) in der Liste anbieten“, Registry-Wert `Snippets`).

`$$` steht für ein `$` im Text. Einsetzen und Ausfüllen sind zusammen ein Undo-Schritt: Strg+Z nach dem Beenden nimmt die ganze Vorlage zurück.

Die Live Templates der IDE (`*.xml` unter `%APPDATA%\Embarcadero\BDS\<Version>\code_templates`) erscheinen ebenfalls in der Liste; Punkte werden zu Platzhaltern, `|end|` zur Endposition, Skripte entfallen. Abschalten mit „Live Templates der IDE als Code-Vorlagen einlesen“ (Registry-Wert `ImportIdeTemplates`). Bei gleichem Kürzel gilt: eigene Vorlage vor IDE-Vorlage vor mitgelieferter.

Eigene Vorlagen lassen sich unter *Tools › Optionen › Drittanbieter › Atlas.Snippets* bearbeiten: Die Liste zeigt alle Vorlagen mit Herkunft; „Neu“ legt eine eigene an, „Als eigene kopieren“ macht aus einer mitgelieferten oder IDE-Vorlage eine eigene, die sie ersetzt, „Löschen“ entfernt eine eigene. Kürzel müssen eindeutig sein; „OK“ speichert die Dateien in `%APPDATA%\Atlas\Snippets`.

Vom Server kommen zusätzlich Vorlagen, die die Klasse kennen. Sie erscheinen nur, wenn in der Zeile außer dem getippten Wort nichts steht:

- `prop` in einer Klassendeklaration, je Feld `FName` ohne Property: setzt `property Name: Typ read FName write SetName;` ein, deklariert `SetName` im private-Abschnitt und legt den Rumpf an.
- `changed` im leeren Rumpf eines Setters: `if FName <> Value then begin FName := Value; Invalidate; end;`.
- `create` im Konstruktor: erzeugt die noch nicht erzeugten Objektfelder (Komponenten mit `Self` als Owner), davor `inherited;`, falls es fehlt.
- `free` im Destruktor: gibt die im Konstruktor erzeugten Felder in umgekehrter Reihenfolge mit `FreeAndNil` frei.

Der Setter sieht überall gleich aus, ob er aus `prop`, `changed`, `propset`, `/prop` oder `/changed` kommt: bei Controls mit `Invalidate`, sonst mit `Changed` bzw. `DoChange`, wenn die Klasse eine davon hat. Mit „Code-Vorlagen (Snippets) in der Liste anbieten“ aus fehlen auch diese Vorlagen.

Rangfolge ohne Präfix (#488): Die Vervollständigung zeigt zuerst lokale Variablen und Konstanten (auch Inline-Variablen oberhalb des Carets), dann Parameter, Mitglieder von `Self`, Bezeichner der eigenen Unit und zuletzt die der Units aus `uses`; vorrangig bleiben Präfix-Güte und erwarteter Typ, danach zählen Bereich, Gelerntes und Alphabet. Ein Tag nennt die Herkunft („lokal“, „Parameter“, „Feld“, „Eigenschaft“, die Klasse einer Methode, „Unit“ oder den Namen der fremden Unit). Verdeckt ein Name eine gleichnamige Deklaration weiter außen, erscheint er nur einmal mit der nächsten Bedeutung, und das Detailpanel nennt die verdeckte.
Tippfehler (#485): Findet die Vervollständigung weniger als drei Treffer, zeigt sie darunter „Meintest du“ mit bis zu fünf ähnlichen Namen (`Lenght` → `Length`; vertauschte, fehlende oder zusätzliche Buchstaben, ab drei getippten Zeichen). Gibt es nur solche Vorschläge, nennt die Fußzeile „Keine Treffer für ‚Lenght‘“. Übernommen werden sie nur mit Enter oder Tab, ein `;` oder `(` fügt nur das Zeichen ein.
Inaktive `{$IFDEF}`-Zweige zeichnet Atlas abgeschwächt (#615), ganze Zeilen und Teile von Zeilen wie `{$IFDEF X} a {$ENDIF}`; die Direktiven bleiben normal. Über einem ausgegrauten Bereich nennt der Tooltip den Grund, etwa „Inaktiv: Bedingung WIN64 nicht erfüllt (Zielplattform Win32 · Debug)“. Wechselt man in der Projektverwaltung Konfiguration oder Zielplattform oder ändert die Defines in den Projektoptionen (auch ungespeichert), meldet das Plugin das dem Server (`atlas.server.selectBuild` mit `defines`); nach dem Neuladen des Projekts stimmt die Darstellung wieder. Das Abblenden hängt nicht an „Probleme anzeigen“: Es holt die Diagnosen der geöffneten Datei auch dann, ohne Wellenlinien und Meldungsliste. Abschalten unter *Tools › Optionen › Drittanbieter › Atlas* oder im Menü Atlas (Registry `InactiveDim`).
Tastenkürzel und andere Erweiterungen (#494): Bevor Atlas eine Taste belegt, prüft es, ob die IDE oder eine andere Erweiterung (GExperts, CnPack, MMX, …) sie schon nutzt. Ohne Entscheidung bleibt die fremde Belegung aktiv, und die Meldungsansicht nennt den Konflikt mit Verweis auf *Tools › Optionen › Drittanbieter › Atlas › Tastenkonflikte*. Diese Seite listet je Taste von Atlas (Befehlspalette, Syntaxprüfung, Vervollständigung, Parameter-Hint) die Taste, wer sie sonst belegt, und die Wahl „Atlas verwenden“, „anderer Belegung überlassen“ oder „andere Taste für Atlas“. Vervollständigung und Parameter-Hint laufen ohne eigene Taste über Strg+Leer bzw. Strg+Umschalt+Leer der IDE; „Atlas verwenden“ belegt diese Tasten selbst, eine andere Taste öffnet die Vervollständigung bzw. den Parameter-Hint von Atlas direkt (Registry `CompletionKey`, `SignatureKey` samt `…Priority`). Darunter stehen erkannte Erweiterungen mit eigener Vervollständigung. Nach dem Installieren oder Entfernen eines Packages prüft Atlas die Tasten erneut.
Absturzsicherheit (#493): Kein Fehler in Atlas erreicht die IDE. Tastaturbindungen, Editor- und Compile-Notifier, Zeichnen, Timer, Menü, Optionsseiten und Hintergrund-Threads laufen über einen gemeinsamen Schutz; Fehler landen ohne Dialog im Protokoll `%LOCALAPPDATA%\Atlas\Logs\atlas.log` (rotierend, 5 × 1 MB; je Zeile Atlas-Version, Feature oder Quelle, Fehlerklasse und eine gekürzte, einzeilige Meldung, mit Stack-Trace nur bei installiertem Anbieter wie JCL oder madExcept). Drei Fehler innerhalb von fünf Minuten schalten nur das betroffene Feature bzw. die betroffene Datenquelle ab (etwa „Vervollständigung (XMLDoc)“, die übrigen Quellen liefern weiter), mit einer Warnung in der Meldungsansicht. *Tools › Optionen › Drittanbieter › Atlas* zeigt unten, was abgeschaltet ist, und schaltet es einzeln oder alle wieder ein; ebenso das Menü Atlas. Datenquellen, die der Hauptthread aufruft (Vervollständigung, Parameter-Hint), haben ein hartes Zeitlimit (Standard 200 ms, Feld „Zeitlimit für Datenquellen“, Registry `ProviderTimeLimitMs`, 50 bis 5000); dauert eine länger, bricht Atlas ab und zählt es als Fehler. Fehler und Zeitlimit des Servers selbst zählen nicht, dafür gibt es Neustart und Zeitlimit des Servers. Beim Schließen der IDE und beim Entladen des Packages setzt Atlas zuerst ein gemeinsames Abbruchsignal: Laufende Anfragen an den Server, Wächter und Zeitlimit-Arbeiter hören sofort auf zu warten, der Server wird spätestens nach 400 ms beendet, und alle Threads enden innerhalb einer Sekunde; die Dauer steht im Protokoll. Editor-Puffer liest und schreibt Atlas nur im Hauptthread, Hintergrund-Threads arbeiten auf Kopien.
Liegt unter der Maus ein Problem, zeigt der Tooltip es oben an; bei Regeltreffern steht darunter die Konfidenz (hoch, mittel, niedrig) als eigene Zeile (#144).

Zur Fehlersuche: Wert `Diagnose` (DWORD) = `1` unter `HKCU\Software\Atlas\IdePlugin` setzen und die IDE neu starten. Das Plugin schreibt dann jeden Aufruf der IDE (Hover, Strg+Klick, Position und Ergebnis) in eine Datei neben der BPL, die wie sie heißt, z. B. `Atlas.IDE.Expert370.log`. Die Datei enthält keine Pfade, Datei- oder Bezeichnernamen (nur Endungen, Positionen und Längen) und darf weitergegeben werden. Für die Vervollständigung steht dort auch, wie lange der Server brauchte, ob er nicht antwortete und warum das Popup schloss.

Findet der Server keine Definition, passiert bei Strg+Klick nichts. Deklarationen in Include-Dateien (`{$I …}`) findet der Server erst mit dem Include-Resolver (#264).

Unter Delphi 12 schließt der Tooltip über den Tastatur-Hook von Atlas, weil der Code-Editor dort keine Tastatur-Ereignisse meldet; sonst verhält sich das Plugin wie unter Delphi 13.

### Ungeprüft

Gebaut und geprüft wird bisher nur mit RAD Studio 13 in der 32-Bit-IDE (#281). Ohne Delphi-12-Installation und ohne 64-Bit-IDE sind diese Punkte offen:

| Punkt | Stand |
|---|---|
| Bau mit Delphi 12 (Compilerversion 36.0, `CompilerVersion < 37.0`-Zweige) | Der Delphi-12-Zweig im Tooltip wurde nur mit umgedrehter Bedingung in Delphi 13 übersetzt |
| `.dproj` mit `ProjectVersion` 20.3 in Delphi 12 öffnen | angenommen: Delphi 12 öffnet sie und schreibt beim Speichern seine Version |
| `{$LIBSUFFIX AUTO}` ergibt `…290.bpl` unter Delphi 12 | aus der Dokumentation, nicht beobachtet |
| Registry `HKCU\Software\Embarcadero\BDS\23.0` (Code Insight-Manager, Help Insight, Strukturhervorhebung) | Das Plugin liest den Schlüssel über `GetBaseRegistryKey`, nicht fest verdrahtet |
| DUnitX-Pfad unter Delphi 12 | ungeprüft; die Tests laufen nur mit Delphi 13 |
| Win64-Bau des Plugins und Lauf in der 64-Bit-IDE | ungeprüft; braucht `designide` für Win64 |
| Installer: Liste der 64-Bit-IDE unter `…\BDS\<Version>\Known Packages x64` | angenommen nach dem Aufbau der 32-Bit-Liste; beim ersten Lauf mit der 64-Bit-IDE prüfen |
| Installer: Delphi-12-BPL im Release | der Release-Runner hat nur Delphi 13; ohne `…290.bpl` zeigt der Installer Delphi 12 als „Paket fehlt im Download“ |
| Lesen des Build-Reiters per RTTI (#528) | an IDE-Interna gebunden, meldet bei Abweichung „nicht lesbar“ |
| Windows 10 und 11 | kein dokumentierter Test auf beiden |

`pwsh Tools/Check-Delphi12.ps1` prüft automatisch Sprachmerkmale von Delphi 13, die `ProjectVersion` und Code mit fester Zeigergröße.

## Eingebauter LSP-Client

RAD Studio 13 kann fremde Sprachserver (LSP) über stdio einbinden. So ersetzt der Atlas-Server für Delphi-Dateien den eingebauten Code Insight-Server.

## Voraussetzungen

- RAD Studio 13 (Registry-Version `37.0`)
- `AtlasServer.exe` an einem festen Ort, z. B. `C:\Tools\AtlasServer.exe`. Die Datei ist gesperrt, solange die IDE den Server laufen lässt. Für ein Update die IDE schließen oder die alte Datei umbenennen und die neue daneben legen.

## 1. Server im Code Insight-Manager anlegen

*Tools > Optionen > Editor > Sprache > Code Insight > Code Insight-Manager > Neu*

| Feld | Wert |
|---|---|
| Name | `Atlas` |
| Ausführbare Datei | Pfad zu `AtlasServer.exe` |
| Befehlszeilenparameter | leer, oder zur Fehlersuche `--log C:\Temp\atlas.log --log-level debug` (anonymisiert: Pfade und Namen als `datei#N`/`name#N`; `--log-names` schreibt sie im Klartext) |
| Sprachbezeichner | beliebig (siehe Schritt 2) |
| Timeout | `15000` |
| InitializationOptions | `{}` |

## 2. Sprache auf Delphi umstellen (Registry)

Die Sprachliste im Dialog bietet weder `delphi` noch `pascal` an. Deshalb wird der Eintrag mit einer beliebigen Sprache angelegt und die Sprache danach in der Registry geändert. Die IDE muss dabei geschlossen sein.

```
HKEY_CURRENT_USER\Software\Embarcadero\BDS\37.0\LSP\UserDefined\Atlas
  LanguageId = Delphi
```

Danach steht „Atlas“ im Code Insight-Manager für Delphi zur Auswahl. Die Auswahl landet hier:

```
HKEY_CURRENT_USER\Software\Embarcadero\BDS\37.0\Editor\Source Options\Borland.EditOptions.Pascal
  Insight Manager = Atlas
```

## 3. Prüfen

1. Die IDE neu starten und eine `.pas` aus einem Projekt öffnen.
2. Im Log (mit `--log`) sollten diese Zeilen stehen:
   - `Kein Arbeitsbereichsordner gemeldet; Ordner werden aus den geöffneten Dateien abgeleitet`
   - `Arbeitsbereichsordner: <Ordner mit der .dproj>`
   - `Symbolindex für … fertig in … ms`
3. Über einem Bezeichner hovern. Der Tooltip zeigt die Deklaration.

## Verhalten des RAD-Studio-Clients

- **Kein Arbeitsbereich:** Die IDE meldet `rootUri` als `file:///` und keine `workspaceFolders`. Der Server leitet den Arbeitsbereich deshalb aus jeder geöffneten Datei ab: Er nimmt den nächsten Ordner mit `.dproj` oder `.groupproj` darüber.
- **Nur Klartext:** Die IDE kann kein Markdown (`hover.contentFormat = ["plaintext"]`). Der Server liefert Hover deshalb als Klartext.
- **Neustarts:** Jede gestartete IDE startet einen eigenen Server. Die Voreinstellung „Restart server each time a project is activated“ startet ihn zusätzlich bei jedem Projektwechsel neu. Die IDE beendet den Server hart, ohne `shutdown`/`exit`. Im Log fehlt deshalb die Zeile „Beendet mit Exit-Code“. Das ist kein Absturz.
- **Vervollständigung:** Die IDE fragt `textDocument/completion` an, auch ohne `completionProvider`. Bis zur Codevervollständigung (#31) antwortet der Server mit `MethodNotFound`.
- **Sprachkennung:** In `didOpen` sendet die IDE `languageId = "pascal"`. Der Server wertet `languageId` nicht aus, das ist also unschädlich.

## Fehlersuche

- `--trace <Datei>` schreibt den JSON-RPC-Verkehr mit. Die Datei wird bei jedem Start neu angelegt. Ist sie belegt, weil eine andere IDE schon einen Server laufen hat, schreibt der Server nach `<Datei>-<PID>.<Endung>` und nennt den Namen im Log.
- Ein Absturz erscheint im Log mit Stacktrace. Fehlt im Log nur die Zeile „Beendet mit Exit-Code“, hat die IDE den Server beendet.
