# BetterDelphiLSP in RAD Studio 13 einbinden

RAD Studio 13 kann fremde Sprachserver (LSP) über stdio einbinden. So ersetzt BetterDelphiLSP für Delphi-Dateien den eingebauten Code Insight-Server.

## Voraussetzungen

- RAD Studio 13 (Registry-Version `37.0`)
- `BetterDelphiLSP.exe` an einem festen Ort, z. B. `C:\Tools\BetterDelphiLSP.exe`. Die Datei ist gesperrt, solange die IDE den Server laufen lässt. Für ein Update die IDE schließen oder die alte Datei umbenennen und die neue daneben legen.

## 1. Server im Code Insight-Manager anlegen

*Tools > Optionen > Editor > Sprache > Code Insight > Code Insight-Manager > Neu*

| Feld | Wert |
|---|---|
| Name | `BetterDelphiLSP` |
| Ausführbare Datei | Pfad zu `BetterDelphiLSP.exe` |
| Befehlszeilenparameter | leer, oder zur Fehlersuche `--log C:\Temp\bdlsp.log --log-level debug` |
| Sprachbezeichner | beliebig (siehe Schritt 2) |
| Timeout | `15000` |
| InitializationOptions | `{}` |

## 2. Sprache auf Delphi umstellen (Registry)

Die Sprachliste im Dialog bietet weder `delphi` noch `pascal` an. Deshalb wird der Eintrag mit einer beliebigen Sprache angelegt und die Sprache danach in der Registry geändert. Die IDE muss dabei geschlossen sein.

```
HKEY_CURRENT_USER\Software\Embarcadero\BDS\37.0\LSP\UserDefined\BetterDelphiLSP
  LanguageId = Delphi
```

Danach steht „BetterDelphiLSP“ im Code Insight-Manager für Delphi zur Auswahl. Die Auswahl landet hier:

```
HKEY_CURRENT_USER\Software\Embarcadero\BDS\37.0\Editor\Source Options\Borland.EditOptions.Pascal
  Insight Manager = BetterDelphiLSP
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
- **Sprachkennung:** In `didOpen` sendet die IDE `languageId = "pascal"`.

## Fehlersuche

- `--trace <Datei>` schreibt den JSON-RPC-Verkehr mit. Die Datei wird bei jedem Start neu angelegt. Bei mehreren gleichzeitig laufenden IDEs zählt nur die zuletzt gestartete.
- Ein Absturz erscheint im Log mit Stacktrace. Fehlt im Log nur die Zeile „Beendet mit Exit-Code“, hat die IDE den Server beendet.
