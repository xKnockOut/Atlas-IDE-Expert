# Navigieren

Zurück zum [README](../../../README_DE.md)

## Springen

| Funktion | Tastenkürzel |
|---|---|
| **Gehe zu** Definition | Strg+Klick |
| Wechsel zwischen Deklaration und Implementierung | Strg+Umschalt+↑/↓ |
| **Definition einblenden** unter der Zeile, ohne die Datei zu wechseln | Alt+F12 |
| **Datei und Symbol schnell öffnen** über Projekt, Projektgruppe und Suchpfad | Strg+P |
| **Units suchen** im eigenen Fenster mit Vorschau, Gruppen, Filtern und „In uses aufnehmen“ | Strg+F12 |

- **Gehe zu** auch Implementierung und Typdefinition
- **Sprung zum Gegenstück** (begin ⇄ end, try → finally → end, `{$IFDEF}` → `{$ENDIF}`)
- projektweite **Symbolsuche**
- **Navigationsverlauf** über Dateien hinweg

## Leisten

### Brotkrumenleiste

- über dem Editor mit Sprungmenüs zu Unit, Klasse, Methode und deren Kindern

### Editorleiste

- mit Symbolen: Sprung zum interface- bzw. implementation-Teil (und zurück mit „↩ 214“), Methode suchen, Navigationsverlauf und beliebige Palettenbefehle
- Überlaufmenü, frei belegbar, auch rechts in der Brotkrumenzeile

### Designer-Leiste

Über dem Formular-Designer statt Brotkrumen und Editorleiste:

- Fenster „Komponenten suchen“ (Alt+^, groß mit Filtern und Vorschau oder klein wie Strg+P)
- Nichtvisuelle über Strg+H der IDE ein- und ausblenden
- Elternelement auswählen
- Tab-Reihenfolge als Marken auf den Steuerelementen
- experimentell: Tab-Reihenfolge per Klick neu vergeben und Ausrichten

### Atlas-Statusleiste

Unten in jedem Editorfenster (Zustandsfarben für helles und dunkles Design eigens abgestimmt):

- Server-Status
- Meldungen dieser Unit je Art (Klick springt zum nächsten Befund, Doppelklick öffnet „Atlas-Prüfung“ für die Unit)
- Live-Prüfung („live · geprüft vor 2 s“, während der Projektprüfung „· Projekt 45 %“, danach kurz „Projekt fertig“)
- die Methode am Cursor mit Zeilen und CC (über der Grenze der Metrikregeln in Warnfarbe)
- jedes Element abschaltbar
- das Atlas-Feld verlässt die Statuszeile der IDE, solange die Leiste den Status zeigt

### Weitere Ansichten

- **Gliederung** als andockbares Fenster mit Filter
- **Übersichtsleiste** an der Scrollleiste mit Fehlern, Treffern und Änderungen
- **Minimap** *(experimentell)*
- **mitlaufender Kopf** der umgebenden Klasse, Routine und großen Blöcke, je Art abschaltbar *(experimentell)*

## Suchen und Ersetzen

**Suchleiste** unter dem Editor (Strg+F):

- **Ersetzen** (Strg+H, „Alle ersetzen“ als ein Rückgängig-Schritt)
- **regulären Ausdrücken** mit Vorschau „vorher → nachher“
- Such- und Ersetzen-**Verlauf** (Pfeil hoch/runter, über Neustarts)
- Bereiche Methode, Unit, Auswahl, **offene Dateien, Projekt und Projektgruppe**
  - Suche im Hintergrund, ungespeicherte Puffer zuerst
  - Ersetzen ausgewählter Treffer über Dateien mit Häkchen

## Projektaufgaben

Aus `atlas.json` (`tasks`):

- Skripte wie `pwsh Tools/Check-Delphi12.ps1` aus Befehlspalette, Menü Atlas, Taste je Aufgabe, Statusfeld oder Schnellaktion der Willkommensseite starten
- Ausgabe im Register „Atlas-Aufgaben“ mit grüner bzw. roter Kopfzeile
- Fundstellen (dcc, pwsh, msbuild, generic oder eigener regulärer Ausdruck) als Befunde in Problemliste und Editor
- auf Wunsch vor jedem Build (`warn` oder `block`)

## Verwendungen und Zusammenhänge

### Ergebnisfenster „Atlas-Ergebnisse“

- für Referenzen (auch in Formularen), Implementierungen, Aufrufer, Aufrufe und Vererbung
- Verwendungen getrennt in „Sicher“ und „Erschlossen · vor dem Umbenennen prüfen“ mit Grund (Interface, überschrieben, Überladung unklar, inaktiver Zweig)
- Filter „Nur sichere“

### Auswirkungen anzeigen

Aufruf: Kontextmenü des Editors, *Atlas › Suchen*, Befehlspalette. Was ist betroffen, wenn sich das Symbol am Cursor ändert?

- direkte und indirekte Aufrufer und Verweise
- Overrides, die überschriebene Basismethode, Interface-Methode und Umsetzungen
- Ereignis-Handler und Komponenten in Formularen
- als Baum nach Ursache mit Tiefe 1 bis 5
- dazu die betroffenen DUnitX-Tests und „Betroffene Tests ausführen“
- Läuft im Hintergrund und meldet erreichte Grenzen (Tiefe, Anzahl, Zeit).

Einstellungen: `navigation.impact`, `navigation.impactDepth`

### Datenfluss

„Woher kommt der Wert?“ und „Wohin geht der Wert?“ zeigen einen Baum im Ergebnisfenster:

- Zuweisungen, var-/out-Argumente
- bei einem Parameter die Argumente der Aufrufer
- bei einer Funktion `Result` und `Exit(…)`
- Setter und Getter von Properties
- jeweils mit Datei, Zeile und Quelltextzeile

Weiter:

- Gleiche Stellen werden zusammengefasst („3 Zuweisungen“).
- Tiefere Ebenen laden beim Aufklappen bis `navigation.dataFlow.maxDepth`.
- Zyklen, Konstanten und Code außerhalb des Projekts beenden den Weg.
- Unsichere Kanten (Zeiger, `absolute`, `Move`, `FillChar`, `@`) sind markiert.
- Enter oder Doppelklick springt; Filter „Nur Projektcode“ und „Tests ausblenden“.
- Abschaltbar über `navigation.dataFlow`

## Lesezeichen und Notizen

- **Benannte Lesezeichen** (Strg+Alt+K) und persönliche **Notizen** an Codezeilen, die nicht im Quelltext landen
- **Schnelle Lesezeichen** in einer Spalte links der Zeilennummern:

| Bedienung | Wirkung |
|---|---|
| Klick | setzt und entfernt |
| Strg+Umschalt+1…9 | nummeriert |
| Strg+1…9 | springt projektweit |
| Strg+Umschalt+K | unnummeriert (die Faltungsakkorde der IDE bleiben) |

- Sie wandern mit dem Code mit und übernehmen die IDE-Lesezeichen, sobald die Spalte gezeichnet ist.

## TODO-Übersicht

- **TODO-Übersicht** des Projekts aus `// TODO`, `// FIXME` und dem To-do-Format der IDE
