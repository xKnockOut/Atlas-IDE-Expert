# Changelog

Alle nennenswerten Änderungen an Argus (Server und VS-Code-Erweiterung).
Format nach [Keep a Changelog](https://keepachangelog.com/de/1.1.0/), Versionen nach [SemVer](https://semver.org/lang/de/).
Server und Erweiterung tragen immer dieselbe Version.

## [Unveröffentlicht]

### Neu
- Hover über seltenen Schlüsselwörtern und Direktiven mit Kurztext und DocWiki-Link, Hinweis auf Delphi-13-Elemente (#187).
- Klartext und String-Literal umwandeln: Code-Aktionen „Als String-Literal“ und „Als Klartext kopieren“, Befehle zum Kopieren und Einfügen, Einstellung `stringLiteral` (#312).
- Code-Aktion „Zuweisungen umkehren“ für markierte Zeilen (#313).
- Hover verlinkt bei Windows-API-Funktionen die Microsoft-Dokumentation (#120).
- Qualifizierten Namen des Symbols unter dem Cursor kopieren: Befehl `argus.server.qualifiedName`, VS-Code-Befehl und MCP-Werkzeug `qualified_name` (#128).
- Release-Prozess mit GitHub Releases, optionaler Code-Signierung und Marketplace/Open VSX (#83).
- Pull-Diagnosen und projektweite Diagnosen (#82).
- VS-Code-Erweiterung als `.vsix`, Konfiguration für Claude Code und Neovim (#49).
- MCP-Modus mit lesenden Werkzeugen (#48).
- Delphi-Version je Projekt aus der ProjectVersion (#47).

## [0.1.0] - 2026-10-08

### Neu
- Erste Fassung: Language Server mit Navigation, Prüfregeln, Formatierung, Umbenennen, Compiler-Anbindung und minimaler VS-Code-Erweiterung.
