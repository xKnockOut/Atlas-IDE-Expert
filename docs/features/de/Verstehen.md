# Verstehen

Zurück zum [README](../../../README_DE.md)

## Im Editor

### Hover-Tooltip

**Hover-Tooltip** im Atlas-Stil statt Help Insight:

- Deklaration
- XMLDoc in auf- und zuklappbaren Abschnitten
- anklickbare Typen, Vererbungskette
- Werte von Konstanten, Mengen und Resourcestrings
- published-Mitglieder von Komponenten als Tabelle
- Symbole in `{$IFDEF}` mit ihrer Herkunft
- Aktionen (Gehe zu, Verwendungen, Deklaration kopieren, Hilfe)

**Begründungen im Hover (#1123):**

- Kommentare wie `// WHY: …`, `// HACK: …` oder `// NOTE: …` über einer Deklaration und im Rumpf der Routine stehen unter BEGRÜNDUNG.
- `ADR-0007` öffnet die Architekturentscheidung, `#312` das Issue im Tracker.

**Werte beim Debuggen:** Ist der Prozess angehalten, zeigt der Tooltip den Wert des Ausdrucks unter der Maus, ausgewertet über den Debugger der IDE ohne Nebenwirkungen.

### Marken und Hervorhebungen

- **Typmarken** hinter `var X := …` ohne Typangabe
- **Code-Metriken** als Marke (Modul Analyse, `analysis.enabled`):
  - hinter jedem Methodenkopf (Länge, Tiefe, zyklomatische und kognitive Komplexität, Parameter, Operanden der größten Bedingung, lokale Variablen, Ausstiege)
  - hinter jeder Klasse (Member, Vererbungstiefe ohne RTL und VCL)
  - hinter dem Unit-Namen (Zeilen) und dem ersten `uses` (Units)
- **Rekursion im Rand**
- **inaktive `{$IFDEF}`-Zweige** abgeschwächt mit Grund im Tooltip
- **ungenutzte uses** abgeblendet (Regel `unused-uses`: auch in `--check`, `get_diagnostics` und der Baseline; `off`, `exclude`, `lsp-ignore` und die Option `keep` gelten auch fürs Abblenden); interface-uses, die nur der implementation-Teil braucht, mit Hinweis und Korrektur „In implementation-uses verschieben“ (Regel `uses-only-in-implementation`, ebenso einstellbar)
- **Klammer- und Blockpaare** farbig nach Tiefe, mit eigenen Blocklinien; lokale Routinen wahlweise eine Stufe tiefer, in eigener Farbe mit gestrichelter Linie oder wie die äußere Routine, auf Wunsch schwach hinterlegt (`highlight.nestedRoutines`, `highlight.nestedRoutineBand`)

<a id="window-atlasarchitecture"></a>
## Architekturübersicht

Fenster *Atlas-Architektur*, *Ansicht › Atlas › Architektur*.

- Teilsysteme als Gruppen eng verbundener Units auf einer Karte zum Zoomen und Verschieben
- zentrale Units mit direkt und gesamt abhängigen Units und Rolle (Fundament, Drehscheibe)
- Zyklen mit Rundweg und den uses-Einträgen, die ihn schließen
- Querverbindungen zwischen Teilsystemen (selten oder gegen die Hauptrichtung) und Ausreißer
- Doppelklick öffnet Unit oder uses-Eintrag.
- Als HTML- oder Markdown-Bericht speicherbar, auch mit `AtlasServer --architecture` und im MCP-Werkzeug `get_architecture`.

### Architekturvergleich (#1121)

- „Stand speichern …“ schreibt einen stabil sortierten JSON-Stand für die Versionsverwaltung.
- „Vergleichen mit …“ (oder automatisch `architecture.baseline`) zeigt im Reiter *Vergleich*:
  - neue und entfernte Zyklen
  - Querverbindungen und uses-Kanten zwischen Teilsystemen
  - Teilsystemwechsel
  - gewachsene zentrale Units
  - sowie neue und entfernte Units
- Auf der Karte stehen neue Kanten grün, entfernte rot gestrichelt.
- Berichte bekommen den Abschnitt „Vergleich“, `get_architecture` den Parameter `compareWith`.
- `AtlasServer --architecture neu.json --compare alt.json --fail-on newCycle` lässt einen CI-Lauf scheitern.

### Feinheit der Teilsysteme (#1366)

- Der Regler „Feinheit“ in der Werkzeugleiste (grob … fein, 0,2 bis 5,0, Doppelklick = 1,0) stellt die Auflösung γ des Louvain-Verfahrens ein.
- Beim Loslassen rechnet der Server im Hintergrund neu, der Wert bleibt in `settings.json`, daneben steht „γ = 1,5 · 12 Teilsysteme“.
- Berichte nennen ein geändertes γ im Kopf, gespeicherte Stände merken es sich, und der Vergleich weist auf ein anderes γ hin.
- `get_architecture` und `atlas/architecture` nehmen `resolution` für einen Aufruf.

Einstellungen: `architecture.grouping.resolution`, `architecture.grouping.showResolutionSlider`

### Nachteilung (#1364)

- Ein Teilsystem mit mehr als einem Viertel aller Units oder mit geringem Zusammenhalt teilt Atlas mit einem zweiten Lauf auf seinen Units nach.
- Die Teile:
  - heißen nach dem Abschnitt, der sie unterscheidet („Lsp“, „Rules“, „Index“ statt einmal „Common“),
  - stehen als „Teil von Common“ in Tabellen, Bericht und `get_architecture`,
  - liegen auf der Karte nebeneinander in Tönen einer Farbe und in der Legende eingerückt unter ihrem Ursprung.

Einstellungen: `architecture.grouping.maxShare`, `architecture.grouping.minCohesion`

### Fundamente (#1365)

- Units wie Logging oder Json-Helfer, die von vielen Teilsystemen verwendet werden, ziehen diese nicht mehr zusammen.
- Sie stehen im eigenen Teilsystem „Fundament“ in der Mitte der Karte (neutrale Farbe, Kanten dorthin blass und ausblendbar, keine Querverbindungen, kein Zusammenhalt)
- oder kommen mit `attach` zu dem Teilsystem mit den meisten Abhängigen.

Einstellungen: `architecture.grouping.foundations`: `separate`, `attach`, `group`

### Warum eine Unit dort liegt (#1368)

- Der Hinweis über einer Unit auf der Karte und ihr Steckbrief unter der Karte zeigen ihre gewichteten Kanten je Teilsystem (`3 × interface`, `2 × impl.`, `= 8`; Kanten zum Fundament „zählen nicht“).
- Sie nennen eine knappe Zuordnung („Mit 3 weiteren Kanten zu Data läge sie dort“).
- Der Reiter *Teilsysteme* markiert knappe Units, und das Fragezeichen darüber erklärt, wie die Teilsysteme entstehen, mit den aktiven Einstellungen.
- HTML- und Markdown-Bericht sowie `get_architecture` mit `unit` zeigen dieselbe Tabelle.

Einstellungen: `architecture.explainAssignment`

### Farben und Namen bleiben (#1367)

- Nach dem Neuberechnen behalten Teilsysteme, die mit einem des vorigen Stands (gespeicherter Stand aus `architecture.baseline`, sonst der zuletzt berechnete im Cache-Ordner) mehr als die Hälfte ihrer Units teilen, dessen Farbe und Namen.
- Eine neue Unit vertauscht also keine Farben mehr und macht aus „Index“ nicht „Index 2“.
- Die Statuszeile nennt „Teilsysteme an Stand vom … angeglichen“.
- *Teilsysteme ▾ › Teilsysteme neu benennen* fängt einmal neu an.

Einstellungen: `architecture.grouping.keepPrevious`

<a id="window-atlasquery"></a>
## Code-Abfragen (#1351)

Fenster *Atlas-Abfrage*, *Ansicht › Atlas › Abfrage*.

- Fragen an den Index in einer kleinen Sprache wie `classes where inherits TForm and methods > 40 order by methods desc` oder `methods where complexity > 15 and callers = 0`
- mit Vervollständigung, sortierbaren Spalten und Sprung zur Deklaration
- gespeicherte Abfragen in `atlas.json` laufen als Regel `query:<name>` im Editor, bei `--check` und in SARIF
- dieselbe Sprache im MCP-Werkzeug `query_code` und mit `AtlasServer --query`

<a id="window-atlashotspots"></a>
## Hotspots (#1354)

Fenster *Atlas-Hotspots*, *Ansicht › Atlas › Hotspots*.

- Units und Methoden, die oft geändert werden und zugleich komplex sind
- Wert = normierte Änderungen × normierte kognitive Komplexität aus dem Git- oder SVN-Verlauf der letzten `hotspots.months` Monate (Umbenennungen verfolgt)
- mit Autoren, Zeilen, Trend der Komplexität gegenüber dem Stand vor drei Monaten und letzter Änderung
- Darstellung:
  - Blasendiagramm (x = Änderungen, y = Komplexität, Größe = Zeilen)
  - sortierbare Tabelle auf Unit- oder Methodenebene
  - Reiter *Änderungskopplung* (Dateien, die in mindestens 70 % ihrer Commits gemeinsam geändert werden, ohne uses-Kante zwischen ihnen) und *Verlauf*
- Doppelklick springt in den Code, das Kontextmenü bietet *Verlauf zeigen* und *Auswirkungen anzeigen* (#1120).
- Gerechnet wird im Hintergrund, das Ergebnis gilt bis zum nächsten Commit.
- Ohne Versionsverwaltung ein Hinweis statt Daten.
- Auch als Bericht mit `AtlasServer --hotspots <Datei.html|md|json>` (Exit-Code 3 ohne Versionsverwaltung oder ausgeschaltet) und als MCP-Werkzeug `get_hotspots`

Einstellungen: `hotspots.enabled`

## Aufrufdiagramm (#1122)

Die Aufrufhierarchie als interaktives Diagramm: Umschalter *Diagramm* im Ergebnisfenster, Befehl „Aufrufdiagramm“ in der Befehlspalette, im Menü Atlas und im Kontextmenü des Editors.

- Start links, je Ebene eine Spalte, Kästen mit Methodenname und Fundstelle
- Bedienung:
  - Klick lädt und klappt die nächste Ebene auf
  - Doppelklick springt in den Code
  - Ziehen verschiebt, Mausrad zoomt
- Aufrufe über ein Interface oder eine virtuelle Methode sind gestrichelt mit der Zahl der Umsetzungen.
- Rekursion ist ein Pfeil zurück ohne weiteres Aufklappen.
- Mehr als 8 Kinder werden zu „+ N …“.
- Ausgehend oder eingehend, Filter „Nur Projekt-Units“ (RTL/VCL ausgeblendet) und „Als HTML speichern …“ (eigenständige Datei ohne externe Verweise)

Einstellungen: `callHierarchy.diagram`

## Units und Abhängigkeiten

<a id="window-atlasunitrelations"></a>
### Unit-Beziehungen (#593)

Fenster *Unit-Beziehungen*, *Ansicht › Atlas › Unit-Beziehungen*.

- folgt dem Editor und zeigt:
  - was die Unit verwendet (in den Gruppen „Interface“ und „Implementation“, RTL/VCL abgeblendet in einer eingeklappten Gruppe)
  - und wer sie verwendet
- interface-Zyklen rot mit dem Rundweg im Tooltip
- „N Units neu übersetzen“ nach einer Änderung im interface, direkt oder alle Ebenen, Filter
- Doppelklick öffnet die Unit, Strg+Doppelklick springt zum uses-Eintrag.
- Kontextmenü verschiebt einen Eintrag zwischen interface und implementation, entfernt ungenutzte oder kopiert den Pfad.
- Strg+Doppelklick in der Architekturkarte öffnet es für diese Unit.
- abschaltbar mit `architecture.enabled`

### Kosten einer interface-Änderung (#554)

- Steht die Einfügemarke im interface-Teil einer Unit, zeigt die Statusleiste „interface-Änderung: 143 Units werden neu kompiliert“ (Tooltip: die ersten Units, Klick: Abhängigkeiten).
- Der Befehl *Abhängigkeiten dieser Unit* öffnet *Unit-Beziehungen*:
  - mit den Verwendern getrennt „über interface-uses“ und „über implementation-uses“
  - markiert interface-Einträge, die nur im implementation-Teil gebraucht werden („In implementation verschieben“ im Kontextmenü)
- *Teuerste Units bei interface-Änderungen* öffnet die Architekturübersicht auf *Zentrale Units* nach „gesamt abhängig“.

Einstellungen: `build.showInterfaceCost`

### Unit verwenden und Formulare suchen (#786)

| Taste | Wirkung |
|---|---|
| Alt+F11 | öffnet das Fenster *Units suchen* als „Unit verwenden in <Unit>“ |
| Strg+I | Umschalter interface / implementation (Vorgabe implementation) |
| Enter | fügt alle markierten Units ohne Duplikat als ein Rückgängig-Schritt ein |
| Umschalt+F12 | öffnet das Fenster gefiltert auf Formulare, Frames und Datenmodule; Enter öffnet den Designer |
| Umschalt+Klick | öffnet weiter die Dialoge der IDE, ebenso die Befehle *IDE-Dialog Unit verwenden* / *IDE-Dialog Formulare* |

- Units aus den uses ausgegraut („schon in uses“)
- „Kreis über X“ als Warnung, wenn der Compiler den Kreis im interface ablehnte (im implementation nur ein Hinweis)

Einstellungen: `unitSearch.replaceUseUnitDialog`, `unitSearch.replaceFormsDialog`

### Unit-Zyklen beim Tippen (#896)

- Beim Tippen im uses (und beim Öffnen, mit dem ungespeicherten Stand anderer offener Units) meldet Atlas einen interface-Zyklus als Fehler „Zirkuläre Unit-Referenz: uC → uA → uB → uC (wie F2047)“.
- Nur solche Zyklen nennen den Compilercode (F2092 bei einer Unit, die sich selbst nennt), Zyklen über implementation-uses nicht, weil Delphi sie übersetzt (#1383).
- Im Hover ist jede Unit ein Verweis auf ihren uses-Eintrag, dazu „Graph zeigen“ (Unit-Beziehungen).
- Korrektur „In implementation-uses verschieben“ (sortiert wie `sortUses`), wenn das interface nichts aus der Unit braucht, sonst Sprünge zu den Bezeichnern, die sie brauchen.
- Eine Unit, die sich selbst nennt, ist ein Fehler mit „Eintrag entfernen“.
- implementation-Zyklen nur mit `usesCycleImplementation` als Hinweis.
- Dieselbe Meldung in Problemliste, MCP und CLI.

Einstellungen: `diagnostics.usesCycleLive`, `diagnostics.usesCycleImplementation`

### Keine Befunde in fremdem Code

- Units der Delphi-Installation (RTL, VCL) und der Bibliothekspfade, die zu keinem Projekt gehören, prüft der Editor nicht, etwa nach Strg+Klick in `System.Classes.pas`.
- Units im Projektordner, aus DCCReference und aus den Projekt-Suchpfaden immer.
- `float-equality` schweigt in Gleichheitsvergleichern (`Equals…`, `class operator Equal`), wo der exakte Vergleich gewollt ist.

Einstellungen: `diagnostics.librarySources`

## Weg zwischen Symbolen

Aufruf: *Atlas › Weg zwischen Symbolen …*, Befehlspalette, Kontextmenü im Editor *Weg von hier nach …*.

- Wie hängt `TKundenForm` mit `TDatenbank` zusammen?
- Atlas findet die kürzeste Kette über uses, Vererbung, Interface-Umsetzungen, Felder, Parameter, Ergebnisse, Aufrufe und Mitglieder.
- Es zeichnet sie im Ergebnisfenster, je Schritt mit Kantenart und Fundstelle (erschlossene Kanten gestrichelt).
- Doppelklick springt hin, *In Architekturkarte zeigen* markiert die Units des Wegs auf der Karte.
- Dieselbe Suche wie das MCP-Werkzeug `find_path`.

Schalter: `navigation.symbolPath`
