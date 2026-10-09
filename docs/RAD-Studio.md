# Argus IDE Expert in RAD Studio 13 einbinden

Es gibt zwei Wege:

- **Empfohlen: das IDE-Plugin** `Argus.IdePlugin` (ADR 0006). Es meldet sich als eigener Code Insight-Manager an und zeigt Hover und Gehe zu Definition an.
- **Eingebauter LSP-Client** (Abschnitt unten). Damit funktionieren Gliederung und Error Insight. Den Hover fremder Server zeigt RAD Studio auf diesem Weg aber nicht an.

## IDE-Plugin

1. Das Package `Packages\Argus.IdePlugin\Argus.IdePlugin.dproj` (in der Projektgruppe enthalten) für **Win32** bauen (die IDE ist 32-Bit). Ergebnis: `Output\Win32\Debug\Bpl\Argus.IdePlugin.bpl`. Ist das Plugin installiert, sperrt die IDE diese BPL; zum Neubauen das Package vorher entladen.
2. In RAD Studio: *Komponente > Packages installieren > Hinzufügen*, die BPL auswählen.
3. *Tools > Optionen > Editor > Sprache > Code Insight*: im Code Insight-Manager **„Argus IDE Expert“** wählen.
4. Den Server findet das Plugin in dieser Reihenfolge:
   - Registry `HKCU\Software\Argus\IdePlugin` (fehlt er, der frühere Schlüssel `HKCU\Software\ArgusServer\IdePlugin`), Wert `ServerPath` (optional `ServerArguments`, z. B. `--log C:\Temp\argus.log`)
   - `ArgusServer.exe` neben der BPL
   - `..\..\..\Win64\Debug\Bin\ArgusServer.exe`, im Repo also die Win64-Build-Ausgabe

Fehler beim Start meldet das Plugin einmalig im Meldungsfenster. Stürzt der Server ab, startet es ihn bei der nächsten Anfrage neu.

Zur Fehlersuche: Wert `Diagnose` (DWORD) = `1` unter `HKCU\Software\Argus\IdePlugin` setzen und die IDE neu starten. Das Plugin schreibt dann jeden Aufruf der IDE (Hover, Strg+Klick, Position und Ergebnis) in `Argus.IdePlugin.log` neben der BPL.

Findet der Server keine Definition, passiert bei Strg+Klick nichts. Deklarationen in Include-Dateien (`{$I …}`) findet der Server erst mit dem Include-Resolver (#264).

Umgesetzt sind Symbolhinweis (Hover) und Strg+Klick (Gehe zu Definition). Vervollständigung, Parameterhilfe und Error Insight folgen.

## Eingebauter LSP-Client

RAD Studio 13 kann fremde Sprachserver (LSP) über stdio einbinden. So ersetzt der Argus-Server für Delphi-Dateien den eingebauten Code Insight-Server.

## Voraussetzungen

- RAD Studio 13 (Registry-Version `37.0`)
- `ArgusServer.exe` an einem festen Ort, z. B. `C:\Tools\ArgusServer.exe`. Die Datei ist gesperrt, solange die IDE den Server laufen lässt. Für ein Update die IDE schließen oder die alte Datei umbenennen und die neue daneben legen.

## 1. Server im Code Insight-Manager anlegen

*Tools > Optionen > Editor > Sprache > Code Insight > Code Insight-Manager > Neu*

| Feld | Wert |
|---|---|
| Name | `Argus` |
| Ausführbare Datei | Pfad zu `ArgusServer.exe` |
| Befehlszeilenparameter | leer, oder zur Fehlersuche `--log C:\Temp\argus.log --log-level debug` |
| Sprachbezeichner | beliebig (siehe Schritt 2) |
| Timeout | `15000` |
| InitializationOptions | `{}` |

## 2. Sprache auf Delphi umstellen (Registry)

Die Sprachliste im Dialog bietet weder `delphi` noch `pascal` an. Deshalb wird der Eintrag mit einer beliebigen Sprache angelegt und die Sprache danach in der Registry geändert. Die IDE muss dabei geschlossen sein.

```
HKEY_CURRENT_USER\Software\Embarcadero\BDS\37.0\LSP\UserDefined\Argus
  LanguageId = Delphi
```

Danach steht „Argus“ im Code Insight-Manager für Delphi zur Auswahl. Die Auswahl landet hier:

```
HKEY_CURRENT_USER\Software\Embarcadero\BDS\37.0\Editor\Source Options\Borland.EditOptions.Pascal
  Insight Manager = Argus
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
