# Claude Code und MCP

Zurück zum [README](../../../README_DE.md)

## MCP-Werkzeuge

Der Server bietet Claude Code 33 MCP-Werkzeuge, jeweils mit Vorschau:

- **Code verstehen:**
  - Symbole suchen
  - Speicher, langsamste Units und Regeln und Warteschlange des Servers der IDE ansehen (`get_server_status`, dieselben Zahlen wie das Fenster „Atlas-Server“)
  - die Architektur des Projekts überblicken (`get_architecture`, auch im Vergleich mit einem gespeicherten Stand)
  - den Index in einer kleinen Sprache abfragen (`query_code`)
  - Hotspots und Änderungskopplung aus dem Git- oder SVN-Verlauf finden (`get_hotspots`)
  - Geschichte einer Methode über Umbenennen und Verschieben verfolgen, mit Issues (`get_symbol_history`)
  - den kürzesten Weg zwischen zwei Symbolen oder Units finden (`find_path`)
  - Deklarationen samt Begründungskommentaren (`get_rationale`) und Typ- und Aufrufhierarchien lesen
  - die Auswirkungen einer Änderung ermitteln (`get_impact`)
  - nur die von einer Änderung betroffenen Tests ermitteln (`get_affected_tests`)
  - Komponenten- und Formularinfos, Diagnosen, Metriken und TODOs abfragen
  - ungenutzten Code finden (`find_unused_code`)
  - die Abhängigkeiten einer Unit samt Zyklen lesen (`get_unit_dependencies`)
- **Prüfen:**
  - geplanten Code mit `check_code` vor dem Schreiben prüfen
  - Treffer erklären (`explain_finding`): derselbe Auftrag wie „Als Auftrag für KI-Assistenten kopieren“ im Fenster „Atlas-Prüfung“, mit Ausschnitt ±8 Zeilen und der Schlusszeile, womit der Assistent nachprüft (`check_code`, bei sicheren Korrekturen `fix_findings`)
  - in der Doku von Atlas nachschlagen: Regeln mit Schweregrad im Projekt, Einstellungen mit aktuellem Wert, Fenster und Tastenkürzel (`search_atlas_docs`)
  - Befunde an Hooks von Claude Code melden (`hook_check`)
- **Bauen und Testen:**
  - über die IDE bauen (`build_project`, `get_last_build`)
  - das in der IDE begonnene Issue mit Checkliste und Codeverweisen lesen (`get_current_issue`)
  - Compilermeldungen an ihrer Stelle erklären, mit der bekannten Delphi-Falle und einer sicheren Korrektur als Diff (`explain_compiler_message`)
  - DUnitX-Tests ausführen
  - den letzten Testlauf der IDE lesen, ohne neu zu laufen (`get_last_tests`: rote Tests mit Datei:Zeile, erwartet/erhalten, Protokoll, neu rot, wackelig, Leck, veraltet)
  - sehen, wo der Entwickler in der IDE gerade ist (`get_ide_context`: Datei, Cursor, Methode, Auswahl, aktives Projekt, letzter Build, Reiter)
- **Ändern:**
  - schreibend umbenennen
  - Code-Aktionen anwenden
  - formatieren (`format_code`)
  - Methode extrahieren, auf Wunsch samt gleicher Stellen (`extract_method`)
  - Refactorings des Kontextmenüs mit Argumenten statt Rückfragen (`refactor`)
  - oder alle sicheren Treffer von Regeln auf einmal korrigieren (`fix_findings`)

Dazu die Ressource `delphi://conventions` mit den Konventionen des Projekts.

## KI-Assistenten in der IDE

Das Modul KI-Assistenten (`assistants.enabled`) nimmt Aufträge von MCP-Clients in der laufenden IDE an: Builds über `build_project` und Änderungen an offenen Dateien, die als ein Rückgängig-Schritt im Editorpuffer landen.

- **Anzeige „KI-Assistent aktiv“** (#1906, `assistants.banner`): Ein Feld im Atlas-Statusfeld zeigt, welches Projekt gerade für einen KI-Assistenten gebaut wird oder welche offene Datei er zuletzt geändert hat (eine Minute lang).
- **Pause für KI:** Ein Klick auf das Feld oder der Befehl „Pause für KI-Assistenten“ in der Palette hält KI-Assistenten an. Neue Builds und Änderungen an offenen Dateien lehnt die IDE dann mit Grund ab, der MCP-Server schreibt die Datei auch nicht selbst; ein laufender Build läuft zu Ende. Während der Pause bleibt das Feld stehen, ein zweiter Klick hebt sie auf.

## Verbundene IDE für Kommandozeilen-Assistenten (#2377)

Mit `assistants.link` (Vorgabe aus) meldet sich RAD Studio bei Kommandozeilen-Assistenten als verbundene IDE, wie es Editoren mit eigener Erweiterung tun. Atlas öffnet dafür einen WebSocket-Server nur auf 127.0.0.1 mit zufälligem Port und einem Token je IDE-Sitzung und legt eine Lock-Datei in den Konfigurationsordner des Assistenten (`%USERPROFILE%\.claude\ide\<Port>.lock` bzw. unter `CLAUDE_CONFIG_DIR`); beim Abschalten oder Beenden verschwindet sie wieder. Verbindungen ohne Token oder aus einem Browser lehnt der Server ab.

- **Auswahl live** (`assistants.link.shareSelection`): Die Auswahl im Editor geht an den Assistenten, sobald sie kurz ruht; ohne Auswahl die Zeile der Schreibmarke.
- **Auswahl an den Assistenten:** Befehl im Kontextmenü des Editors und Taste (`assistants.link.mentionKey`, Vorgabe Strg+Umschalt+Alt+K) schicken Datei und Zeilen der Auswahl als Erwähnung.
- **Vorschlag als Vergleich** (`assistants.link.diffPreview`): Ein Vorschlag des Assistenten erscheint als Vergleich mit dem jetzigen Stand der Datei. „Annehmen“ ändert die Datei als ein Rückgängig-Schritt und speichert sie, „Annehmen und öffnen“ zeigt sie danach im Editor, „Ablehnen“ oder Schließen lässt sie unverändert. Erst dann erfährt der Assistent die Entscheidung. Hat sich die Datei inzwischen geändert, zeigt der Vergleich den neuen Stand.
- **Werkzeuge:** offene Dateien und Arbeitsordner, Auswahl, Datei öffnen und einen Bereich markieren, ungespeicherte Änderungen prüfen und speichern, Befunde von Atlas und Compilermeldungen. Code in der IDE ausführen kann der Assistent nicht.
- **Statusfeld „Assistent verbunden“** mit dem Namen des Assistenten; ein Klick bietet „Trennen“. Die Pause für KI gilt auch hier: Speichern und Vorschläge lehnt die IDE dann ab.

## Prompts (#1357)

**Prompts** sind fertige Arbeitsabläufe, die Claude Code als Schrägstrich-Befehle zeigt:

| Prompt | Inhalt |
|---|---|
| `/mcp__delphi__unit_review UI.Auftrag` | Gliederung, Befunde, Metriken über Grenzwert, ungenutzten Code und Konventionen in einer Nachricht |
| `explain_form` | Komponentenbaum, Ereignis-Handler mit Rümpfen, Datenbindungen |
| `write_tests` | |
| `fix_finding` | erst die Ursache, dann die Korrektur, dann `check_code` |
| `prepare_commit` | neue Befunde nur in geänderten Zeilen, betroffene Tests, Commit-Präfix des aktuellen Issues |

- Mit `--restricted` bieten sie keine schreibenden Schritte an.
- Eigene Prompts stehen in `mcp.customPrompts`, `mcp.prompts` schaltet sie ab, `mcp.promptLanguage` wählt Deutsch oder Englisch.

## Ressourcen mit Vorlage

**Ressourcen mit Vorlage** hängen eine Unit (Gliederung und interface-Teil), ein Formular, die Befunde einer Datei oder den letzten Build mit `@` an, z. B. `@delphi:delphi://unit/UI.Auftrag`.

## Anweisungen für KI-Assistenten (#2615)

KI-Assistenten lesen beim Start eine Anweisungsdatei des Projekts. Atlas schreibt die Regeln aus `atlas.json` als Kurzfassung hinein, damit der Assistent sie kennt, bevor er die erste Zeile schreibt:

- Regelprofil, Grenzwerte der aktiven Metrik-Regeln, Benennung (`naming-prefix`), verbotene Symbole mit Ersatz, die in `atlas.json` auf Fehler gestellten Regeln, die geschützten Dateien aus `assistants.protected` und die Pflichtprüfungen aus `assistants.instructions.checks`.
- Der Abschnitt steht zwischen `<!-- atlas:begin … -->` und `<!-- atlas:end -->`; nur er wird ersetzt, der übrige Text der Datei bleibt. Fehlt er, hängt Atlas ihn an; fehlt die Datei, legt Atlas sie an.
- Dateien: `assistants.instructions.file` (Vorgabe `["AGENTS.md"]`), relativ zum Ordner von `atlas.json`. Sprache wie `mcp.promptLanguage`.
- Kommandozeile: `AtlasServer --check . --write-instructions` schreibt, `--check-instructions` prüft nur und endet mit Exit-Code 1, wenn ein Abschnitt veraltet ist (für CI und Pre-Commit-Hooks).
- In der IDE: Atlas › „Anweisungen für KI-Assistenten aktualisieren“ (auch in der Befehlspalette) schreibt die Dateien und zeigt im Meldungsfenster, welche Zeilen sich geändert haben. Nach dem Speichern von `atlas.json` weist Atlas auf einen veralteten Abschnitt hin; abschaltbar mit `assistants.instructionsHint`.

## Plugin `atlas`

- Das Plugin `atlas` prüft außerdem jede Pascal-Datei, die Claude ändert, sofort mit den Prüfregeln des Projekts (Hook mit `hook_check`, Befunde gehen direkt an Claude zurück).
- `/atlas:bauen` baut und testet und fasst das Ergebnis nach 0 Fehlern, 0 Warnungen, 0 Hinweisen zusammen.

Einrichtung: [Editors/ClaudeCode](../../../Editors/ClaudeCode/README.md), Werkzeuge: [docs/MCP.md](../../../docs/MCP.md).

## Neue Werkzeuge entwickeln

- `pwsh Tools/Start-McpInspector.ps1` öffnet den [MCP Inspector](https://modelcontextprotocol.io/docs/tools/inspector) gegen den Server (Browser, Terminal oder Kommandozeile) und zeigt jedes Werkzeug, sein Schema und die rohen JSON-RPC-Nachrichten.
- `delphi://stats` zeigt je Werkzeug, wie oft der KI-Assistent es aufruft, wie oft es scheitert (mit dem letzten fehlgeschlagenen Aufruf), wie langsam und groß seine Antworten sind und welche Werkzeuge in den letzten 30 Tagen nie vorkamen (#2611).
- `pwsh Tools/Test-McpTools.ps1` ruft jedes Werkzeug einmal mit Beispielargumenten gegen das Referenzprojekt auf und schreibt den rohen Mitschnitt.

Siehe [docs/MCP.md](../../../docs/MCP.md#werkzeuge-entwickeln-und-prüfen).
