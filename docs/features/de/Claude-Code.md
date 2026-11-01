# Claude Code und MCP

Zurück zum [README](../../../README_DE.md)

## MCP-Werkzeuge

Der Server bietet Claude Code 32 MCP-Werkzeuge, jeweils mit Vorschau:

- **Code verstehen:**
  - Symbole suchen
  - Speicher, langsamste Units und Regeln und Warteschlange des Servers der IDE ansehen (`get_server_status`, dieselben Zahlen wie das Fenster „Atlas-Server“)
  - die Architektur des Projekts überblicken (`get_architecture`, auch im Vergleich mit einem gespeicherten Stand)
  - den Index in einer kleinen Sprache abfragen (`query_code`)
  - Hotspots und Änderungskopplung aus dem Git- oder SVN-Verlauf finden (`get_hotspots`)
  - den kürzesten Weg zwischen zwei Symbolen oder Units finden (`find_path`)
  - Deklarationen samt Begründungskommentaren (`get_rationale`) und Typ- und Aufrufhierarchien lesen
  - die Auswirkungen einer Änderung ermitteln (`get_impact`)
  - nur die von einer Änderung betroffenen Tests ermitteln (`get_affected_tests`)
  - Komponenten- und Formularinfos, Diagnosen, Metriken und TODOs abfragen
  - ungenutzten Code finden (`find_unused_code`)
  - die Abhängigkeiten einer Unit samt Zyklen lesen (`get_unit_dependencies`)
- **Prüfen:**
  - geplanten Code mit `check_code` vor dem Schreiben prüfen
  - Treffer erklären
  - Befunde an Hooks von Claude Code melden (`hook_check`)
- **Bauen und Testen:**
  - über die IDE bauen (`build_project`, `get_last_build`)
  - DUnitX-Tests ausführen
- **Ändern:**
  - schreibend umbenennen
  - Code-Aktionen anwenden
  - formatieren (`format_code`)
  - oder alle sicheren Treffer von Regeln auf einmal korrigieren (`fix_findings`)

Dazu die Ressource `delphi://conventions` mit den Konventionen des Projekts.

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

## Plugin `atlas`

- Das Plugin `atlas` prüft außerdem jede Pascal-Datei, die Claude ändert, sofort mit den Prüfregeln des Projekts (Hook mit `hook_check`, Befunde gehen direkt an Claude zurück).
- `/atlas:bauen` baut und testet und fasst das Ergebnis nach 0 Fehlern, 0 Warnungen, 0 Hinweisen zusammen.

Einrichtung: [Editors/ClaudeCode](../../../Editors/ClaudeCode/README.md), Werkzeuge: [docs/MCP.md](../../../docs/MCP.md).

## Neue Werkzeuge entwickeln

- `pwsh Tools/Start-McpInspector.ps1` öffnet den [MCP Inspector](https://modelcontextprotocol.io/docs/tools/inspector) gegen den Server (Browser, Terminal oder Kommandozeile) und zeigt jedes Werkzeug, sein Schema und die rohen JSON-RPC-Nachrichten.
- `pwsh Tools/Test-McpTools.ps1` ruft jedes Werkzeug einmal mit Beispielargumenten gegen das Referenzprojekt auf und schreibt den rohen Mitschnitt.

Siehe [docs/MCP.md](../../../docs/MCP.md#werkzeuge-entwickeln-und-prüfen).
