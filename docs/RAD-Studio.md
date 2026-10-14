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

Den Umfang des Index stellt *Tools › Optionen › Drittanbieter › Atlas* für alle Projekte ein (#652): alle Projekte der Projektgruppe, alle Units der Projekt-Suchpfade und alle Units der Delphi-Bibliothek. Das Plugin gibt die Werte beim Start und nach jeder Änderung an den Server weiter. Steht `index` in der `atlas.json` eines Projekts, gilt dort die Datei. RTL, VCL und FMX liest der Server einmal je Delphi-Version und Plattform, unabhängig von den Defines des Projekts.

Was Atlas selbst anzeigt, schaltet es in der IDE ab, damit nichts doppelt erscheint: Help Insight (solange der Atlas-Tooltip an ist) und die Strukturhervorhebung (solange die Atlas-Blocklinien an sind). Die IDE liest diese Schalter nur beim Start; beim ersten Start mit Atlas erscheint daher noch beides.

Zur Fehlersuche: Wert `Diagnose` (DWORD) = `1` unter `HKCU\Software\Atlas\IdePlugin` setzen und die IDE neu starten. Das Plugin schreibt dann jeden Aufruf der IDE (Hover, Strg+Klick, Position und Ergebnis) in `Atlas.IDE.Expert.log` neben der BPL. Die Datei enthält keine Pfade, Datei- oder Bezeichnernamen (nur Endungen, Positionen und Längen) und darf weitergegeben werden. Für die Vervollständigung steht dort auch, wie lange der Server brauchte, ob er nicht antwortete und warum das Popup schloss.

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
