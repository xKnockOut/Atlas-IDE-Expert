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
- im Deklarationsteil einer Klasse, eines Records oder Helfers der Sichtbarkeitsabschnitt am Cursor (`strict private`, `private`, `protected`, `public`, `published`) als eigenes Glied; sein Menü springt zu den anderen Abschnitten, vor dem ersten Schlüsselwort steht die implizite Sichtbarkeit kursiv (`editor.breadcrumbsVisibility`)
- im Menü des Sichtbarkeitsglieds je Abschnitt Marke und Mitgliederzahl („− private · 7 Mitglieder · Zeile 27“, `editor.breadcrumbsSectionCounts`), „Neue Zeile am Ende von private“ (leere, eingerückte Zeile hinter dem letzten Mitglied, Cursor darin, Kommentare am Abschnittsende bleiben darunter, Strg+Z nimmt sie zurück; `editor.breadcrumbsSectionAppend`) und für fehlende Abschnitte „Abschnitt anlegen: protected“ an der Stelle der üblichen Reihenfolge (`editor.breadcrumbsSectionCreate`); „Neue Zeile am Ende des Abschnitts“ gibt es auch in der Befehlspalette und auf einer frei belegbaren Taste (`keys.sectionAppend`, Abschnitt am Cursor)
- Rechtsklick, Menütaste oder Umschalt+F10 auf ein Glied öffnet ein Kontextmenü: „Namen kopieren“ (`TKunde.Laden`), „Mit Unit kopieren“ (`uKunden.TKunde.Laden`), bei Routinen „Mit Signatur kopieren“ (Kopf mit Parametern), „Pfad der Leiste kopieren“, „Verwendungen suchen“ (Ergebnisfenster), „Umbenennen …“ (wie „Symbol umbenennen“) und für Komponentenfelder und Ereignisbehandler „Komponente im Designer zeigen“; am Unit-Glied „Unit-Namen kopieren“ und „Dateipfad kopieren“. Abschaltbar mit `editor.breadcrumbsContextMenu`.
- Hat eine Routine Überladungen im selben Typ bzw. in derselben Unit, trägt ihr Glied einen Zähler in Quelltextreihenfolge, etwa „Laden (2/3)“. Klick auf den Zähler (oder Umschalt+↓ mit Fokus) öffnet „Überladungen von Laden“ mit allen Überladungen samt Parametern und Zeile; Enter springt zur Implementierung, Umschalt+Enter zur Deklaration. Im Geschwistermenü stehen Überladungen ebenfalls mit Parametern, lange Listen gekürzt mit „…“; der Hinweis über der Zeile zeigt die volle Liste. Abschaltbar mit `editor.breadcrumbsOverloads`.
- Erfüllt eine Methode Interface-Methoden, trägt ihr Glied ganz rechts die Marke `[IKunde]`, bei mehreren `[IKunde +1]`. Der Hinweis nennt je Interface-Methode Unit und Zeile („Erfüllt IKunde.Speichern (KundenApi.pas, Z. 31)“); Klick auf die Marke (oder Alt+↓ mit Fokus) öffnet „Erfüllt“, Enter springt zur Deklaration im Interface, auch in anderen Units. Zuordnungen (`procedure IKunde.Speichern = Sichern;`) und vererbte Interfaces zählen mit, Interfaces einer Vorfahrklasse nur bei `override`. Die Angaben kommen mit der Gliederung nach einer Tipppause, nie bei Caret-Bewegung. Abschaltbar mit `editor.breadcrumbsInterfaces`.
- Liegt die Maus die Tooltip-Verzögerung lang auf einem Methoden- oder Typglied, zeigt eine Karte Kopfzeile und Kennzahlen: bei Methoden Zeilen, zyklomatische Komplexität, Verschachtelungstiefe und Parameter, bei Typen Zeilen, Mitglieder und Vererbungstiefe. Werte über der Grenze aus `atlas.json` stehen gelb mit der Grenze („86 (Grenze 60)“); Strg+I mit Fokus zeigt dieselbe Karte. Fehlen die Metriken noch, steht nur die Kopfzeile und „Kennzahlen noch nicht verfügbar“ (`editor.breadcrumbsMetrics`).
- dahinter der Unterblock am Cursor (`const`, `type`, `class var`); sein Menü springt zu den Unterblöcken des Abschnitts, ein ausdrückliches `var` beendet ihn (`editor.breadcrumbsMemberBlocks`)
- im Rumpf einer Methode die Sichtbarkeitsmarke der Deklaration vor dem Methodenglied (`−` private, `#` protected, `+` public, `◆` published); der Hinweis nennt die genaue Sichtbarkeit und die Zeile der Deklaration, etwa „strict private · deklariert in Zeile 42“ (`editor.breadcrumbsVisibilityMark`)
- auf Unit-Ebene Teil und Deklarationsblock am Cursor (`type`, `const`, `var`, `resourcestring`, `threadvar`, `label`, `exports`), etwa `uKunden › interface › resourcestring › sKundeFehlt`; das Menü des Blocks listet alle Blöcke der Unit mit Teil und Zeile, lokale Blöcke in Routinen zählen nicht (`editor.breadcrumbsDeclarationBlocks`)
- am Ende der Bedingungszweig um den Cursor (`{$IFDEF MSWINDOWS}`, im Gegenzweig `{$ELSE MSWINDOWS}`, `{$ELSEIF …}`), bei verschachtelten Blöcken einer je Ebene, außen zuerst; das Menü springt zu IF, ELSE und ENDIF des Blocks. Ob der Zweig aktiv ist, entscheidet die Leiste nicht (`editor.breadcrumbsConditionals`)
- hinter Unit bzw. Abschnitt die innerste `{$REGION}` um den Cursor, etwa `uKunden › Datenbankzugriff › TKunde › Speichern`; ihr Menü listet alle Regionen der Unit mit Zeile, verschachtelte eingerückt, eine Region ohne Namen heißt „Region (Z. n)“ (`editor.breadcrumbsRegions`)
- auf Wunsch im Methodenrumpf `try`, `except`, `finally` und der case-Zweig (`case Art of › akFirma`), höchstens die innersten drei; das Menü springt zu den Teilen des try-Blocks bzw. zu allen Zweigen des case (`editor.breadcrumbsStatements`, Vorgabe aus)
- wird die Leiste zu schmal, fallen zuerst diese Rahmen weg, dann die übrigen zusätzlichen Glieder, erst danach Glieder vorn

### Editorleiste

- mit Symbolen: Sprung zum interface- bzw. implementation-Teil (und zurück mit „↩ 214“), Methode suchen, Navigationsverlauf und beliebige Palettenbefehle
- „Zur uses-Klausel“ wechselt aus einer uses-Klausel zur anderen (interface ↔ implementation); fehlt sie, springt der Knopf zum Schlüsselwort `implementation` bzw. `interface`, ein weiterer Klick führt zurück. Der Tooltip nennt das Ziel, der Rücksprung führt zur Zeile vor dem ersten Klick
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

## Regionen

- **Regionen beim Öffnen** (Optionen › Editor): `{$REGION}`-Blöcke beim ersten Anzeigen einer Datei „unverändert lassen“ (Vorgabe), „alle zuklappen“ oder „alle aufklappen“; die Region mit der Schreibmarke bleibt offen
- **Alle Regionen zuklappen** / **Alle Regionen aufklappen** im Menü Atlas (Navigation), im Kontextmenü des Editors und in der Befehlspalette
- „aus (auch keine Befehle)“ blendet auch die Befehle aus

## TODO-Übersicht

- **TODO-Übersicht** des Projekts aus `// TODO`, `// FIXME` und dem To-do-Format der IDE
