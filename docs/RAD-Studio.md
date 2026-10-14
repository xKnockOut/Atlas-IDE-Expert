# Atlas IDE Expert in RAD Studio einbinden

Es gibt zwei Wege:

- **Empfohlen: das IDE-Plugin** `Atlas.IDE.Expert` (ADR 0006) für RAD Studio 13 und 12. Es meldet sich als eigener Code Insight-Manager an und bringt eigene Fenster für Vervollständigung, Parameter-Hint und Hover sowie Probleme im Editor, Klammerpaare, Befehlspalette und Compilerprüfung mit (Übersicht in der [README](../README_DE.md)).
- **Eingebauter LSP-Client** (Abschnitt unten). Damit funktionieren Gliederung und Error Insight. Den Hover fremder Server zeigt RAD Studio auf diesem Weg aber nicht an.

## IDE-Plugin

1. Das Package `Packages\Atlas.IDE.Expert\Atlas.IDE.Expert.dproj` (in der Projektgruppe enthalten) mit der Delphi-Version bauen, in der es laufen soll: für die klassische IDE **Win32**, für die 64-Bit-IDE (ab Delphi 12.3) **Win64**. Ergebnis: `Output\Win32\Debug\Bpl\Atlas.IDE.Expert370.bpl` bzw. `Output\Win64\…`; die Zahl ist die Package-Version (`370` Delphi 13, `290` Delphi 12). Ist das Plugin installiert, sperrt die IDE diese BPL; zum Neubauen das Package vorher entladen.
2. In RAD Studio: *Komponente > Packages installieren > Hinzufügen*, die BPL auswählen.
3. Den Server (`AtlasServer.exe`) mit bauen: Common, Windows und Server für dieselbe Plattform (Win64 empfohlen). Der Server ist ein eigenes Programm und hängt nicht von der Delphi-Version ab.
4. Den Server findet das Plugin in dieser Reihenfolge:
   - *Tools › Optionen › Drittanbieter › Atlas*, Feld „Atlas-Server“ (Registry `HKCU\Software\Atlas\IdePlugin`, Wert `ServerPath`; optional `ServerArguments`, z. B. `--log C:\Temp\atlas.log`). Darunter zeigt die Seite, welcher Server verwendet wird und ob er gefunden wurde.
   - `AtlasServer.exe` neben der BPL
   - `..\..\..\Win64\Debug\Bin\AtlasServer.exe`, sonst `..\..\..\Win32\Debug\Bin\AtlasServer.exe`, im Repo also die Build-Ausgabe

Fehlt der Server, meldet das Plugin das im Meldungsfenster und überlässt Vervollständigung und Hinweise der eingebauten Code Insight. Stürzt der Server ab, startet es ihn bei der nächsten Anfrage neu.

Den Umfang des Index stellt *Tools › Optionen › Drittanbieter › Atlas* für alle Projekte ein (#652): alle Projekte der Projektgruppe, alle Units der Projekt-Suchpfade und alle Units der Delphi-Bibliothek. Das Plugin gibt die Werte beim Start und nach jeder Änderung an den Server weiter. Steht `index` in der `atlas.json` eines Projekts, gilt dort die Datei. RTL, VCL und FMX liest der Server einmal je Delphi-Version und Plattform, unabhängig von den Defines des Projekts.

Was Atlas selbst anzeigt, schaltet es in der IDE ab, damit nichts doppelt erscheint: Help Insight (solange der Atlas-Tooltip an ist) und die Strukturhervorhebung (solange die Atlas-Blocklinien an sind). Die IDE liest diese Schalter nur beim Start; beim ersten Start mit Atlas erscheint daher noch beides.

XMLDoc-Kommentare (`///`) zeigen Tooltip und Detailpanel der Vervollständigung vollständig und formatiert (#654): Beschreibung, Parameter, Typparameter, Rückgabe, Wert, Exceptions, Bemerkungen, Beispiel mit Code, Listen, Tabellen und „Siehe auch“. Ist die Doku höher als der Bildschirm (bzw. das Panel höher als das Popup), scrollt nur sie mit dem Mausrad; Deklaration und Aktionsleiste bleiben stehen. Verweise (`cref`) sind unterstrichen: Klick zeigt den Typ im Tooltip, Strg+Klick springt zur Deklaration (im Detailpanel nur Strg+Klick); Links (`href`) öffnen den Browser. Doku-Text lässt sich mit der Maus markieren, Strg+C kopiert dann die Markierung statt der Deklaration. *Tools › Optionen › Drittanbieter › Atlas* schaltet die volle Anzeige ab (Registry `XmlDocFull`, aus = Kurzform: Beschreibung vier, Bemerkungen drei Zeilen) und begrenzt die Höhe (`XmlDocMaxLines`, 0 bis 50, 0 = bis zur Bildschirmhöhe). Steht `hints` in der `atlas.json` eines Projekts, gilt dort die Datei. Das Mausrad erreicht den Tooltip, solange Windows inaktive Fenster unter der Maus scrollt (Vorgabe von Windows 10 und 11).

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
