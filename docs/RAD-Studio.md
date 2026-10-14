# Atlas IDE Expert in RAD Studio einbinden

Es gibt zwei Wege:

- **Empfohlen: das IDE-Plugin** `Atlas.IDE.Expert` (ADR 0006) für RAD Studio 13 und 12. Es meldet sich als eigener Code Insight-Manager an und bringt eigene Fenster für Vervollständigung, Parameter-Hint und Hover sowie Probleme im Editor, Klammerpaare, Befehlspalette und Compilerprüfung mit (Übersicht in der [README](../README_DE.md)).
- **Eingebauter LSP-Client** (Abschnitt unten). Damit funktionieren Gliederung und Error Insight. Den Hover fremder Server zeigt RAD Studio auf diesem Weg aber nicht an.

## IDE-Plugin

1. Das Package `Packages\Atlas.IDE.Expert\Atlas.IDE.Expert.dproj` (in der Projektgruppe enthalten) für **Win32** bauen (die IDE ist 32-Bit). Ergebnis: `Output\Win32\Debug\Bpl\Atlas.IDE.Expert.bpl`. Ist das Plugin installiert, sperrt die IDE diese BPL; zum Neubauen das Package vorher entladen.
2. In RAD Studio: *Komponente > Packages installieren > Hinzufügen*, die BPL auswählen.
3. Den Server (`AtlasServer.exe`) mit bauen: Common, Windows und Server für dieselbe Plattform (Win64 empfohlen). Der Server ist ein eigenes Programm und hängt nicht von der Delphi-Version ab.
4. Den Server findet das Plugin in dieser Reihenfolge:
   - *Tools › Optionen › Drittanbieter › Atlas*, Feld „Atlas-Server“ (Registry `HKCU\Software\Atlas\IdePlugin`, Wert `ServerPath`; optional `ServerArguments`, z. B. `--log C:\Temp\atlas.log`). Darunter zeigt die Seite, welcher Server verwendet wird und ob er gefunden wurde.
   - `AtlasServer.exe` neben der BPL
   - `..\..\..\Win64\Debug\Bin\AtlasServer.exe`, sonst `..\..\..\Win32\Debug\Bin\AtlasServer.exe`, im Repo also die Build-Ausgabe

Fehlt der Server, meldet das Plugin das im Meldungsfenster und überlässt Vervollständigung und Hinweise der eingebauten Code Insight. Stürzt der Server ab, startet es ihn bei der nächsten Anfrage neu.

Was Atlas selbst anzeigt, schaltet es in der IDE ab, damit nichts doppelt erscheint: Help Insight (solange der Atlas-Tooltip an ist) und die Strukturhervorhebung (solange die Atlas-Blocklinien an sind). Die IDE liest diese Schalter nur beim Start; beim ersten Start mit Atlas erscheint daher noch beides.

Bedienung (#399): Das Menü *Atlas* in der Menüleiste und das Untermenü *Atlas* im Kontextmenü des Editors enthalten Code-Aktionen, Auswahl erweitern/verkleinern, Gehe zu Implementierung und Typdefinition, Referenzen und „Qualifizierten Namen kopieren“. Tastenkürzel (änderbar unter *Tools › Optionen › Drittanbieter › Atlas*): Code-Aktionen Alt+Enter, Auswahl erweitern Strg+W, verkleinern Strg+Umschalt+W, Gehe zu Implementierung Strg+Alt+I, Typdefinition ohne Vorgabe. Ist eine Taste schon von der IDE oder einer anderen Erweiterung belegt, bleibt diese Belegung und das Meldungsfenster nennt den Konflikt; der Schalter „Editor-Kürzel auch belegen …“ gibt Atlas Vorrang. Schnellbefehle (`/uses Unit`, `/try` …) werden nach Enter ausgeführt, `///` über einer Deklaration erzeugt das Kommentargerüst; beides lässt sich auf derselben Seite abschalten.

Formular-Designer (#402): Ein im Designer geöffnetes Formular schickt Atlas etwa eine halbe Sekunde nach jeder Änderung an den Server, auch ungespeichert. Referenzsuche, Umbenennen und Prüfungen sehen also neue Komponenten und Ereignis-Zuordnungen sofort. Wird ein Ereignis-Handler umbenannt, ändert Atlas die Unit und setzt die Zuordnung im Designer neu; das Formular ist danach geändert und wird mit der Unit gespeichert. Andere Änderungen an einem offenen Formular (etwa eine Komponente umbenennen) lehnt Atlas mit einer Meldung ab und ändert nichts; nicht geöffnete Formulare schreibt Atlas direkt in die Datei.

Aufzählungen und Mengen (#448): Erwartet die Stelle einen Aufzählungstyp (nach `:=`, `=`, `<>` oder in einem `case`-Zweig), stehen dessen Werte oben in der Liste, bei `{$SCOPEDENUMS ON}` als `Typ.Wert`. Nach `[` an einer Mengen-Stelle öffnet sich die Liste von selbst und zeigt nur die Elemente mit Häkchen; vorhandene sind schon abgehakt. Leertaste hakt ab, Enter ersetzt die ganze Menge, Esc lässt sie unverändert.

case-Anweisungen (#449): Am Anfang eines Zweigs (nach `case Shape.Kind of` oder nach dem `;` eines Zweigs) steht oben „Alle Werte einfügen“ mit der Zahl der Werte, in einer case-Anweisung mit Zweigen „Fehlende Werte ergänzen (n)“. Atlas schreibt je fehlendem Wert eine Zeile `Wert: ;` in Deklarationsreihenfolge, ergänzt ein fehlendes `end;` und setzt den Cursor vor das `;` des ersten neuen Zweigs. Bereiche (`skCircle..skRect`) und Listen zählen als vorhanden. Ein Rückgängig entfernt alles. Mit getipptem Präfix steht der Eintrag hinter den passenden Werten.

Unbekannte Namen (#471): Kennt Atlas einen getippten Namen im Rumpf einer Routine nicht, steht am Ende der Liste die Gruppe „„Name“ ist unbekannt“ mit „Lokale Variable anlegen“ (im `var`-Abschnitt), „Inline-Variable anlegen“ (nur am Anfang einer Anweisung mit `:=` und ab Delphi 10.3), „Feld FName anlegen“ (in einer Methode; im `private`-Abschnitt, die Verwendung wird umbenannt, wenn die Felder der Klasse mit F beginnen) und „Konstante anlegen“ (wenn der Name als Wert dient; in der implementation). Den Typ leitet Atlas aus der rechten Seite der Zuweisung oder dem erwarteten Typ ab, sonst steht dort `{Typ}`. Fehlt die Unit des Typs, kommt sie ins uses. Stehen nur diese Einträge in der Liste, ist keiner gewählt: Enter macht dann eine neue Zeile, eine Pfeiltaste wählt den ersten. Der Cursor bleibt im Namen, ein Rückgängig nimmt alles zurück.

Interface implementieren (#466): Steht in der Vorfahrenliste einer Klasse ein Interface, dessen Methoden fehlen (auch die seiner Vorfahren, etwa `IFlush` bei `IExporter = interface(IFlush)`), zeigt Strg+Leer auf einer leeren Zeile der Klassendeklaration nur diese Methoden mit Kontrollkästchen, alle angehakt. Die Leertaste hakt ab, Enter legt die angehakten an: Deklarationen vor dem `end` der Klasse in einem Abschnitt nach `completion.interfaceSection` (Standard `public`; steht dieser Abschnitt schon als letzter da, kommt kein neuer), je Interface mit Kommentar `{ IExporter }`, dazu die Rümpfe hinter der letzten Methode der Klasse. Funktionen setzen `Result := Default(<Typ>)`, Prozeduren bleiben leer, ohne `inherited`. Was die Klasse oder eine Vorfahrklasse schon mit gleichem Namen und gleichen Parametertypen hat, zählt als vorhanden. Generische Interfaces wie `IComparer<TKunde>` bekommen die eingesetzten Typen (`function Compare(const Left, Right: TKunde): Integer;`). Wird in der Klasse getippt, steht oben in der Liste der Hinweis „3 Methoden von IExporter fehlen“; er ist nie vorgewählt und legt beim Übernehmen alle fehlenden Methoden dieses Interfaces an. Alles ist ein Rückgängig-Schritt.

Komponenten aus dem Formular (#455): In den Methoden einer Formular-, Frame- oder Datenmodulklasse stehen deren Komponenten als erste Gruppe „Formular frmMain“ in der Liste, rechts mit ihrem Typ. Atlas liest sie aus der Formulardatei; ist das Formular im Designer offen, gilt dessen Stand, eine neu abgelegte Komponente erscheint also ohne Speichern. Gesucht werden kann auch über den Typ: `button` findet `btnSave` (`TButton`) und `btnLoad` (`TBitBtn`, von `TButton` abgeleitet), aber nicht `chkAktiv` (`TCheckBox`); solche Treffer stehen hinter denen über den Namen. Über den Typ sucht Atlas ab zwei Zeichen: Der eigene Klassenname muss ohne „T“ damit beginnen, oder ein Vorfahr muss genau so heißen. Komponenten in eingebetteten Frames gehören zum Frame und erscheinen nicht.

Sender mit Typumwandlung (#480): Nach `Sender.` in einem Ereignis-Handler mit `Sender: TObject` schaut Atlas in der Formulardatei, welchen Komponenten der Handler zugewiesen ist, und zeigt die Member ihres gemeinsamen Vorfahren (bei zwei Buttons `TButton`, bei Button und Label `TControl`) unter der Überschrift „Sender ist TButton · btnSave, btnLoad“, jeweils mit der Marke „als TButton“. Wird einer übernommen, steht danach `(Sender as TButton).Caption`; mit `completion.senderCast` = `"cast"` steht dort `TButton(Sender).Caption`. Ist der Handler keiner Komponente zugewiesen oder bleibt als gemeinsamer Vorfahr nur `TObject`, zeigt die Liste wie bisher die Member von `TObject`.

Feld- und Parameternamen (#461): In `qryOrders.FieldByName('`, `FindField('` und `ParamByName('` öffnet sich die Liste trotz String. Sie zeigt die persistenten Felder der Datenmenge, dann die Spalten ihrer SQL-Anweisung (Aliasnamen gelten) bzw. bei `ParamByName` die `:Platzhalter` und die Einträge der Params-Sammlung, rechts mit dem Typ, sofern bekannt. Die Fußzeile nennt die Anweisung. Übernehmen ersetzt den ganzen String-Inhalt in der Schreibweise der Quelle. Atlas liest das aus der Formulardatei bzw. dem offenen Designer; eine zur Laufzeit erzeugte Datenmenge liefert keine Vorschläge, `select *` keine Spalten (die kommen erst mit dem Schema-Cache aus #462). Datenmengen eines anderen Datenmoduls (`dmMain.qryOrders`) findet Atlas über die globale Variable `dmMain` im Index und die Formulardatei ihrer Unit. Steht im String ein Name, den die Datenmenge nicht kennt, zeigt der Hover „Feld nicht gefunden in qryOrders“ (nur Hinweis).

Freigabe absichern (#489): Nach Übernahme eines Konstruktors in `List := TStringList.Create` öffnet das `;` (auch als Commit-Zeichen) oder Enter am Zeilenende ohne `;` eine kleine Liste „Mit try…finally absichern“, rechts die Freigabe (`List.Free`), Fußzeile „Enter anwenden · weitertippen verwirft“. Enter setzt `try`, eine leere Zeile mit dem Cursor, `finally`, `List.Free;` und `end;` darunter, als ein Rückgängig-Schritt; ein fehlendes `;` setzt Atlas dabei selbst und ersetzt die leere Zeile vom Enter. Folgen bis zum Ende der Routine schon Zeilen, gibt es zusätzlich „Bis Routinenende mit try…finally absichern“. Nicht angeboten wird bei Feldern, `Result`, Interface-Variablen, Records, einem Owner (`Create(Self)`, `Create(Application)`), wenn die Variable später zurückgegeben, zugewiesen, an `Add`/`Insert` übergeben oder schon freigegeben wird, und wenn danach schon `try` steht. `completion.offerTryFinally` schaltet das Angebot ab, `completion.freeStyle` = `"freeAndNil"` schreibt `FreeAndNil(List)`.

Zur Fehlersuche: Wert `Diagnose` (DWORD) = `1` unter `HKCU\Software\Atlas\IdePlugin` setzen und die IDE neu starten. Das Plugin schreibt dann jeden Aufruf der IDE (Hover, Strg+Klick, Position und Ergebnis) in `Atlas.IDE.Expert.log` neben der BPL.

Findet der Server keine Definition, passiert bei Strg+Klick nichts. Deklarationen in Include-Dateien (`{$I …}`) findet der Server erst mit dem Include-Resolver (#264).

Unter Delphi 12 schließt der Tooltip über den Tastatur-Hook von Atlas, weil der Code-Editor dort keine Tastatur-Ereignisse meldet; sonst verhält sich das Plugin wie unter Delphi 13.

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
| Befehlszeilenparameter | leer, oder zur Fehlersuche `--log C:\Temp\atlas.log --log-level debug` |
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
