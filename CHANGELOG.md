# Changelog

Alle nennenswerten Änderungen an Argus (Server und VS-Code-Erweiterung).
Format nach [Keep a Changelog](https://keepachangelog.com/de/1.1.0/), Versionen nach [SemVer](https://semver.org/lang/de/).
Server und Erweiterung tragen immer dieselbe Version.

## [Unveröffentlicht]

### Neu
- Schnellbefehle für Windows-API und DLLs: `/external`, `/exports` (nur in einer library), `/oscheck` und `/olecheck` (#321).
- Schnellbefehle für Tasks: `/task` (VCL-Zeilen am Ende in TThread.Queue), `/parallel` (TParallel.For mit Prüfung auf Break, äußere Variablen und VCL), `/future` und `/atomic` (#322).
- Schnellbefehle für Records und Wertobjekte: `/record` (mit `ro` nur lesbar), `/operator` (`=` bringt `<>` mit), `/equals` (Equals und GetHashCode über dieselben Felder) und `/clone` (#323).
- Schnellbefehl `/modern`: for-in statt Indexschleife, Inline-Variablen und FreeAndNil in der umgebenden Routine, einzeln abschaltbar mit `-for`, `-inline`, `-free` (#303).
- Attribute: Gehe zu Definition und Referenzsuche lösen `[Foo]` zuerst als `FooAttribute` auf (auch qualifiziert); der Hover zeigt die passenden Konstruktoren (#119).
- Dokumentationskommentar: nach `///` über einer Deklaration entsteht das Gerüst mit `<summary>`, `<typeparam>`, `<param>` und `<returns>`; Code-Aktionen erzeugen den Kommentar bzw. passen die `<param>` an die Signatur an (#88).
- Code-Aktion „Klassenmitglieder ordnen“ nach `memberOrder` (Abschnitte, Arten, `sortFields`, `sortPublished`); Kommentare und Attribute wandern mit, packed-Klassen, Records und `{$IF}` quer zu Abschnitten bleiben unangetastet (#89).
- Stilregeln: `bool-compare`, `redundant-assigned-free`, `raise-in-finally` sowie standardmäßig aus `redundant-parens` und `redundant-begin-end` (#104).
- Regel `component-palette-icon`: registrierte Komponenten ohne Palettensymbol in der per `{$R}` eingebundenen .dcr/.res, ab Delphi 11 auch fehlende Größen 16/24/32 px (#114).
- Schnellbefehle für eigene Komponenten: `/notify OnChange`, `/changed Farbe` (Invalidate bei Controls), `/loaded` und `/notification` samt FreeNotification im Setter (#320).
- Schnellbefehle `/header` (Dateikopf aus `slashCommands.headerTemplate`, Jahr fortschreiben), `/deprecated Grund`, `/region-all` und `/bookmark Name`; die Symbolsuche findet Lesezeichen `// @bookmark Name` (#306).
- Schnellbefehle für Datenbankcode: `/sql`, `/params`, `/loop` und `/transaction`, passend zu FireDAC, ADO, dbExpress und IBX (#302).
- Schnellbefehle `/define`, `/define!`, `/searchpath` (ändern nur die betroffene Zeile der `.dproj`), `/config Release Win64` und `/dfm` (Sprung in die Formulardatei) (#301).
- Schnellbefehle `/format`, `/multiline`, `/multiline!`, `/iif` und `/inc` für Ausdrücke; Vorschläge richten sich nach `delphiVersion` (#303).
- Schnellbefehle `/fmt` (umgebende Routine formatieren) und `/measure` (Laufzeit mit TStopwatch messen) (#300).
- Linter: `--changed` und `--diff` auch in SVN-Arbeitskopien (#276).
- Linter: `--changed`, `--diff`, `--include-uncommitted` und `--changed-lines` prüfen nur, was sich laut Git geändert hat; Beispiele für Pre-Commit-Hook und GitHub Action (#157).
- Performance-Regeln, alle standardmäßig aus: `string-concat-in-loop`, `loop-invariant-call` und `missing-begin-update` (#278).
- Exception-Regeln: `generic-exception-raised`, `catch-all-without-raise` (standardmäßig aus) und `exception-freed` (#277).
- Regeln für fehleranfällige RTL-Muster, Stufe 2 (typbasiert): `int32-mul-overflow`, `sizeof-pointer`, `char-to-pchar`, `float-equality`, `constructor-on-instance`, `format-without-settings` (#153).
- Regeln für fehleranfällige RTL-Muster, Stufe 1: `self-assignment`, `for-high-to-low`, `exception-not-raised`, `assert-side-effect`, `ifthen-side-effect`, `random-without-randomize` (#153).
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
