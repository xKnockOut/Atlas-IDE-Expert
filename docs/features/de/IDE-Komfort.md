# IDE-Komfort

Zurück zum [README](../../../README_DE.md)

<a id="window-atlasstart"></a>
## Atlas-Willkommensseite

- auf der Willkommensseite der IDE (einzeln oder als ein Bereich „Atlas“ oben, abschaltbar mit `welcomePage.ideWelcomePage`)
- und unabhängig davon im andockbaren Fenster *Atlas-Start* (*Ansicht › Atlas-Start*, Befehlspalette)
  - öffnet sich, sobald das letzte Projekt geschlossen ist, mit `welcomePage.openOnStart` auch beim Start der IDE
- mit Bereichen: Weiterarbeiten, Projekte mit Schnellaktionen, Projektverlauf, Nicht gesichert, Projekt einrichten, Testergebnisse, Meine Issues, Neu in Atlas, Atlas entdecken, Hilfe und Rückmeldung
- Suchfeld und freies Layout

## Issue-Tracker (GitHub, YouTrack)

### Grundlagen und Verbindungen

- „Meine Issues“ auf der Willkommensseite, Issue beginnen mit Branch und Commit-Präfix
- alle Tracker-Einstellungen unter `issues.*` auf der eigenen Seite *Tools › Optionen › Atlas › Issue-Tracker* (frühere `welcomePage.issues.*`-Werte übernimmt Atlas beim ersten Start)
- mehrere Tracker-Verbindungen nebeneinander (`issues.connections`) mit Token-Zustand und „Prüfen“, das Token nur im Anmeldespeicher von Windows
- persönliche Zuordnung von Delphi-Projekten, Projektgruppen oder Ordnern zu Verbindung und Tracker-Projekt (`issues.projects`, die `.atlas` gewinnt), mit „Kein Tracker für dieses Projekt – zuordnen …“ in „Meine Issues“
- Arbeitskopien je Tracker-Projekt (`issues.projects[].paths`, Spalte „Arbeitskopien“): „Beginnen“ legt den Branch in der ersten an und öffnet danach das Projekt; „Prüfen“ zeigt Art und Branch je Ordner
- „Vorschlagen …“ findet Arbeitskopien dort, wo Atlas schon war: Arbeitskopie der Zeile, svn:externals bzw. Submodule, Projekte der Gruppe und bei GitHub die zuletzt geöffneten Projekte mit passendem origin, auch Worktrees (`issues.suggestPaths`)
- Klappliste „Projekt: … ▾“ in „Meine Issues“: „Automatisch“ (nach dem Delphi-Projekt) oder ein festes Tracker-Projekt, unabhängig vom geöffneten Ordner (`issues.projectPicker`, gemerkt in `issues.welcomeProject`)
- „Alle Tracker-Projekte“: eine Gruppe je Tracker-Projekt mit Trefferzahl, höchstens `issues.allProjects.perGroup` Zeilen, eine Abfrage für alle, Hinweis nur bei der Gruppe ohne Zugang (`issues.allProjects`)

### Abfragen

- mehrere benannte Abfragen (`issues.queries`, je Verbindung und Tracker-Projekt) mit Klappliste und Trefferzahl im Kopf von „Meine Issues“ (`issues.queryPicker`)
- die frühere einzelne Abfrage wird „Standard“
- Dialog „Abfrage bearbeiten“ mit Vorlagen (YouTrack auf Deutsch und Englisch) und „Testen“:
  - nennt die Ursache (kein Token, abgelehnt, Projekt unbekannt, Abfrage abgelehnt mit der Meldung des Trackers, Antwort nicht lesbar) samt gesendeter Abfrage
- „Prüfen“ erkennt eine deutsche YouTrack-Oberfläche, die Vorgabe-Abfrage folgt ihr

<a id="window-atlasissue"></a>
### Issue-Vorschau

- im andockbaren Fenster *Atlas-Issue* (`issues.preview`: Klick auf ein Issue in „Meine Issues“ oder *Issue anzeigen …*)
- mit Beschreibung als Markdown, Feldern, Kommentaren, Anhängen, verknüpften Issues, Zurück/Vor
- 7 Tage Zwischenspeicher ohne Netz
- Checklisten (`- [ ]`) zum Abhaken direkt in der Vorschau mit Fortschritt „3/5“ in Kopfzeile und Statusfeld (`issues.preview.checklists`, `issues.checklistStatus`)
- Abhängigkeiten und Unteraufgaben als Baum (`issues.preview.links`):
  - hängt ab von, blockiert
  - Unteraufgaben mit Fortschritt 2/3
  - Unteraufgabe anlegen und verknüpfen direkt aus der Vorschau
- Warnung beim „Beginnen“, solange ein blockierendes Issue offen ist (`issues.warnBlocked`)
- Reiter *Entwicklung* (`issues.preview.development`):
  - die Branches des Issues (Vorsprung/Rückstand, Wechseln)
  - Commits (Diff, Sprung zur Änderung)
  - Pull Requests mit CI-Ampel (GitHub) bzw. VCS-Änderungen aus YouTrack
  - die geänderten Units nach Projekt

### Issues im Code

- Issue-Kennungen wie `ATL-123` oder `#42` in Kommentaren gepunktet unterstrichen (`issues.codeLinks`):
  - mit Kurzvorschau beim Überfahren
  - Strg+Klick in die Vorschau
  - eigenes Rechtsklick-Menü
- Zeilenhistorie (`issues.blameLinks`, Git `log -L` und SVN):
  - zeigt die Kennungen der Commit-Nachricht, ihr Hover Titel und Zustand je Kennung
  - Strg+Klick öffnet die Vorschau
  - *Issues zu dieser Methode* listet alle Issues, deren Commits die Methode (bzw. Unit) am Cursor geändert haben, mit Anzahl der Commits und Unterschied

### Issue anlegen

- „Issue anlegen …“ aus dem Editor (Auswahl bzw. TODO unter dem Cursor, Fundstelle, Methode, Branch, Codeausschnitt als eigenes Häkchen) und aus Befunden der Atlas-Prüfung
- mit Vorschau vor dem Senden
- danach `// TODO ATL-130: …` im Code, Kennung in der Zwischenablage

Einstellungen: `issues.create`, `issues.create.includeCode`

### Beginnen, Beenden, Kommentieren

- mit `issues.syncState`:
  - „Beginnen“ setzt Zustand, Zuweisung und Kommentar im Tracker.
  - „Beenden“ öffnet einen Dialog mit Zielzustand, Kommentar ({branch}, {commits}, {pr}) und Übergabe.
  - Die Vorschau hat ein Kommentarfeld (Strg+Enter).
- erweiterter Kommentar-Editor (`issues.commentEditor`) in Vorschau und Beenden-Dialog:
  - `@` schlägt Tracker-Benutzer vor, `#` und `ATL-` Issues
  - Strg+B/Strg+I/Strg+Umschalt+K formatieren
  - Reiter Vorschau
  - Textbausteine mit {branch}, {commit}, {issue} und {version} (`issues.commentSnippets`)
  - Entwürfe je Issue

### Zeiterfassung

- mit `issues.timeTracking` erfasst Atlas die Arbeitszeit je Issue:
  - Statusfeld „ATL-123 · 1:25“
  - Leerlauf hält an, Pause, Korrigieren, *Offene Zeitbuchungen …*
- bietet beim Beenden an, sie in YouTrack als Work Item zu buchen (gerundet, Arbeitstyp, Text aus den Commits; GitHub als Kommentar)

<a id="window-atlasboard"></a>
### Board und Sprint

- Board im andockbaren Fenster *Atlas-Board* (`issues.board`):
  - aktueller Sprint des YouTrack-Agile-Boards bzw. des GitHub-Projekts als Spalten mit Karten
  - „Nur meine“, Suche
  - Ziehen ändert nach Rückfrage den Zustand im Tracker und folgt dem Workflow von YouTrack:
    - unter einer Zustandsmaschine löst Atlas den passenden Übergang aus wie das Board von YouTrack
    - Spalten, die der Workflow ausschließt, leuchten nicht auf
    - die Statuszeile nennt die erlaubten Übergänge
  - Klick öffnet die Vorschau, Doppelklick beginnt
- Bereich *Sprint* auf der Startseite (`welcomePage.sprint`):
  - aktueller Sprint mit Resttagen, eigenen Zahlen, „Team übrig“ und Burndown
  - Vergleich mit dem Vorsprint und Velocity der letzten drei Sprints
  - Klick auf die Zahlen filtert „Meine Issues“

<a id="window-atlasflowmap"></a>
### Ablauf-Karte

- Fenster *Atlas-Ablauf* (Ansicht › Atlas › Ablauf, Befehl *Atlas.FlowMap*, `issues.flowMap`, nur YouTrack):
  - genutzte Übergänge zwischen den Zuständen mit Anzahl, mittlere Verweildauer je Zustand, offene und eigene Issues
  - Liste „Liegt lange“: Issues, die länger als `issues.flowMap.stuckDays` Tage im selben Zustand stehen
  - Zeitraum `issues.flowMap.days` (7–365 Tage)

### Suche in der Befehlspalette

Issues in der Befehlspalette suchen (`issues.paletteSearch`: `#Text`, `#42` oder `ATL-12`). Ein leeres `#` zeigt die zuletzt geöffneten.

| Taste | Wirkung |
|---|---|
| Enter | Vorschau |
| Strg+Enter | beginnen |
| Umschalt+Enter | Browser |
| Strg+C | Kennung kopieren |

### Meldungen und Anhänge

- Meldungen zu meinen Issues (`issues.notify`):
  - neue Kommentare, Zuweisungen und Zustandswechsel in der Benachrichtigungszentrale
  - „Öffnen“ springt zum neuen Kommentar
  - Punkt in „Meine Issues“ bis zum Öffnen
- *An Issue anhängen …* (`issues.attach`: Atlas-Menü, Befehlspalette, Vorschaufenster, Statusfeld) schickt in einem Schritt:
  - Bildschirmfoto des laufenden Programms oder des Formulars im Designer (mit Rahmen, Pfeil und Schwärzen)
  - Logdatei (letzte N Zeilen)
  - Debug-Notiz und Exception-Verlauf
  - YouTrack bekommt die Dateien als Anhänge samt Kommentar, GitHub die Texte als Kommentar und die Bilder über die Zwischenablage

## Versionsverwaltung (Git, SVN)

### Seite in den Optionen

Eigene Seite *Tools › Optionen › Atlas › Versionsverwaltung* (#1285) mit:

- Art (`vcs.provider`: automatisch, Git, SVN, aus)
- eigenem Pfad zu git.exe bzw. svn.exe (`vcs.git.path`, `vcs.svn.path`, leer = PATH und übliche Ordner)
  - Ein eigener Pfad gilt allein; fehlt die Datei, sagt Atlas das statt ein anderes Programm zu nehmen.
- „Prüfen“ mit Version und Fundort
- Zeitlimit je Aufruf (`vcs.timeoutSeconds`)
- dem Stand des aktuellen Projekts (Arbeitskopie, Branch bzw. Pfad, Revision, Herkunft der Einstellung)

Die Werte gelten auch für `atlas --changed`.

### Tabelle *Projekte* (#1286, `vcs.projects`)

- legt Art und Hauptbranch je `.dproj`, `.groupproj` oder Ordner fest (z. B. eine Zeile je Paketordner aus SVN-Externals)
- Reihenfolge (dieselbe wie die Tracker-Zuordnung):
  1. der Abschnitt `vcs` der `.atlas`
  2. dann die Zeile der `.dproj`
  3. der geöffneten Projektgruppe
  4. der längste passende Ordner
- Änderungsmarken nehmen die Zeile des Ordners der Unit.
- „Beginnen“ in *Meine Issues* zweigt vom Hauptbranch ab, eingehende Commits greifen darauf zurück.

### Tabelle *Server* (#1287)

- prüft auf Klick, ob Atlas den Server ohne Rückfrage erreicht (`git ls-remote`, `svn info ^/`, 10 s): erreichbar, Anmeldung nötig, nicht erreichbar, kein Server
- *Anmelden …* öffnet eine Konsole, in der Git Credential Manager bzw. SVN fragen und die Anmeldung speichern; Atlas speichert keine Zugangsdaten.
- Abruf, Pull und Push fragen nie nach (`GIT_TERMINAL_PROMPT=0`, `GCM_INTERACTIVE=never`).
- Fehlt die Anmeldung, zeigt *Weiterarbeiten* „Anmeldung am Server nötig – prüfen …“ statt einer leeren Liste.

### *Branch anlegen …* (#1288)

Aufruf: Befehlspalette, Kontextmenü von *Projekte* und „Beginnen“ in *Meine Issues*, solange `vcs.branch.confirm` an ist. Der Dialog zeigt:

- Name
- Basis (Git: origin/main, lokales main, aktueller Branch; SVN: Hauptbranch @ HEAD mit der Revision vom Server oder die Arbeitskopie @ ihrer Revision)
- die SVN-Nachricht
- unter *Was passiert* genau die git- bzw. svn-Befehle, die Atlas danach ausführt, Schritte auf dem Server markiert
- svn:externals werden genannt

#### SVN-Branches (#1290)

- SVN-Branches liegen neben dem Trunk des Projekts (`vcs.branch.svn.location`, Vorgabe `{projektwurzel}/branches/{name}`, aus `^/Kasse/trunk` wird `^/Kasse/branches/<Name>`)
- mit Quelle (HEAD oder Arbeitskopie, Warnung bei gemischter Revision)
- „Danach“: umschalten, frisch in einen Ordner daneben auschecken, den Atlas dann zum Öffnen anbietet, oder nichts
- Commit-Nachricht (`{kennung} Branch für {titel}`)

#### Externals (#1291)

- Die Gruppe „Externals (n)“ zeigt jede Zeile aus `svn:externals` mit Ordner und Quelle und lässt sie:
  - auf die Revision ihrer Arbeitskopie festschreiben,
  - unverändert lassen
  - oder mitverzweigen (das Package wird neben seinen eigenen Trunk kopiert, z. B. `^/Packages/Drucken/branches/<Name>`, und die External-Zeile im neuen Branch über eine schlanke Arbeitskopie umgeschrieben).
- Externals mit fester Revision bleiben.
- Externals aus fremden Repositories und Datei-Externals werden nie mitverzweigt.
- Vorgaben im Unterpunkt *Externals*:
  - `vcs.externals.onBranch`: festschreiben, lassen, fragen
  - `vcs.externals.suggestBranch`: bei lokalen Änderungen, nie, immer
  - `vcs.externals.rules`: eine Regel je Quelle, die längste passende gewinnt
- Festgeschrieben wird ab svn 1.9 mit `svn copy --pin-externals`, wenn alles festgeschrieben wird.
- Nach dem Umschalten baut Atlas den Index neu auf.

#### Git-Optionen fürs Anlegen (#1289, `vcs.branch.git.*`, Gruppe *Git* auf der Seite und im Dialog)

| Option | Werte |
|---|---|
| Basis | `remote` (Vorgabe; vorher `git fetch <Remote> <Hauptbranch>`, scheitert das, fragt Atlas nach dem Dialog „Vom lokalen Stand abzweigen?“ mit dem Zustand des Servers, ohne Dialog bricht es ab), `local` oder `current` |
| Push | `later` oder `now` (`git push --set-upstream`; scheitert nur der Push, bleibt der lokale Branch und die Meldung nennt den Grund) |
| offene Änderungen | `carry`, `stash` (`git stash push --include-untracked -m "Atlas: vor <Name>"`) oder `ask` (mitnehmen, beiseitelegen, abbrechen) |
| `worktree` | legt den Branch in einem eigenen Ordner an (`git worktree add`, `worktreeFolder` mit `{repo}`, `{name}`, `{kennung}`, Vorgabe `..\{repo}-{kennung}`) und bietet danach an, dieselbe `.groupproj` bzw. `.dproj` von dort zu öffnen; einen vorhandenen Ordner lehnt Atlas ab |

Mit `local`, `later`, `carry` und ohne worktree bleibt alles wie bisher.

### „Arbeitskopien …“ (#1292)

- im Projektmenü der Willkommensseite und Atlas-Menü
- zeigt Wurzel, jedes svn-External und jedes Git-Submodul mit Pfad im Repository, Revision („· fest“ bei festgeschriebenen Externals), Änderungen und nach „Server prüfen“ die neuen Commits
- Doppelklick öffnet den Ordner.
- Das Kontextmenü aktualisiert alle, nur diese oder schreibt die Revision fest (mit Rückfrage, ohne Commit).
- „Nicht gesichert“ nennt jede Arbeitskopie mit ihren Änderungen.
- Pull bekommt ein Untermenü „mit/ohne Externals“.

Einstellungen: `vcs.externals.show`, `vcs.externals.update` (mit, ohne, fragen)

## Bedienung

| Funktion | Tastenkürzel |
|---|---|
| **Befehlspalette** für alle Atlas-Befehle | Strg+Umschalt+P |
| **Atlas-Statusfeld** mit Indexfortschritt und Schnellschaltern | Strg+Umschalt+Alt+A |
| **Benachrichtigungszentrale** sammelt Hinweise von Builds, Prüfungen und Server | Strg+Umschalt+Alt+N |
| **Markierung suchen** | F3 bzw. Umschalt+F3 |

- **Änderungsmarken** in der Rinne gegenüber Git HEAD bzw. SVN BASE
- **Stilles Neuladen** extern geänderter Dateien

<a id="window-atlasserverstatus"></a>
## Fenster „Atlas-Server“ (#1356, `server.statusWindow`)

Aufruf: *Atlas › Hilfe und Diagnose*, Befehl `Atlas.ServerStatus`, Klick auf die Zeile *Server* im Statusfenster, Doppelklick auf den Status in der Atlas-Statusleiste.

- Prozess, Version, Laufzeit, Zustand (lädt, bereit, prüft) und Neustarts der Sitzung
- Speicher je Bereich (Symbole, Verwendungen, Bibliotheks-Units, Syntaxbäume, offene Dokumente, Rest) als Balken gegen das Budget mit dem Hinweis „Verwendungen werden ausgelagert“
- die 10 langsamsten Units und Regeln des letzten Prüflaufs, die langsamsten Anfragen, Warteschlange und Cache-Treffer
- Doppelklick öffnet die Unit bzw. die Regeleinstellungen.
- Es liest den Status, den die Statuszeilen ohnehin alle 5 s holen, und nur, solange es zu sehen ist.
- *Aktualisieren* fragt sofort, *Index neu aufbauen*.
- *Diagnosepaket erstellen …* schreibt nach einer Vorschau eine ZIP-Datei mit Fehlerbericht (#108), Status, Protokoll der Sitzung und mit `--trace` dem Trace der letzten Minuten, anonymisiert wie der Fehlerbericht und nie mit Zugangsdaten.

<a id="window-atlasdiagnostics"></a>
## Zeiten des Plugins im Diagnosefenster (`diagnosticMode.pluginTimings`, `diagnosticMode.slowThresholdMs`)

Im Diagnosemodus zeigt „Atlas-Diagnose“, was in Atlas gerade langsam ist:

| Reiter | Inhalt |
|---|---|
| *Hauptthread* | wie sehr Atlas die IDE in den letzten 60 s belegt hat, eigene Zeit je Funktion (Aufrufe, Summe, Mittel, Maximum, Aufrufe ab der Schwelle, Anteil) und die letzten 200 langsamen Aufrufe mit der laufenden Atlas-Aktion; Kontextmenü *Nur X zeigen*, *bis zum Neustart ausschalten*, *Zeile kopieren* |
| *Server* | jede Anfrage mit Anzahl, Mittel, Maximum, wie oft der Hauptthread wartete und wie lange im Mittel, Zeitüberschreitungen, Abbrüchen und Fehlern |
| *Hintergrund* | Arbeitszeit jeder Quelle der Vervollständigung im Arbeitsthread und wie oft sie zu langsam war |
| *Hänger* | die Meldungen des Einfrier-Wächters der Sitzung und ob Atlas beteiligt war |
| *Vervollständigung* | das bisherige Fenster |

- *Anhalten*, *Zurücksetzen* und *Bericht kopieren* (ohne Quelltext und Dateinamen)
- Ausgeschaltet läuft kein Messpunkt

## Robustheit

- kein Fehler in Atlas erreicht die IDE
- Hänger-Wächter mit Protokoll
- Stacktraces mit Unit und Zeile für jeden abgefangenen Fehler
- Prüfregeln und Editorfunktionen vertragen beliebig tief verschachtelte Ausdrücke ohne Rekursion (eine Unit jenseits des Netzes von 100000 Ebenen bekommt den Hinweis `unit-too-deep`, statt still ihre Befunde zu verlieren)
- eine wiederholt fehlerhafte Funktion wird einzeln abgeschaltet (mit Benachrichtigung zum Wiedereinschalten), die übrigen laufen weiter
- Serverabstürze stehen mit Ursache (Exit-Code, stderr) im Protokoll, und ein Server, der zweimal gleich abstürzt, wird nicht in einer Schleife neu gestartet
- abgesicherter Start nach einem Absturz (ein langsamer Start ist keiner: Statt beim nächsten Start Funktionen abzuschalten, nennt Atlas, wie lange es den Start aufgehalten hat und welche seiner Teile am längsten brauchten; eine IDE mit `ATLAS_NO_SESSION_MARKER=1`, etwa eine per Skript gestartete Bau-IDE, zählt weder selbst als Absturz noch wertet sie Abstürze anderer aus)
- eigene Datendateien (Favoriten, Verläufe, Lesezeichen, Notizen …) werden in einem Schritt ersetzt, eine beschädigte liegt danach als `.defekt` daneben statt still überschrieben zu werden
- Fehlerbericht zum Anhängen
- Anonyme Diagnose (#1478): Protokolle von Plugin und Server, Fehlerbericht, Status, Diagnosepaket und `--timings` nennen Projekte, Units, Pfade, Benutzer und Meldungen nur als `name#N`, `datei#N`, `text#N`; Klarnamen nur nach ausdrücklicher Wahl (`diagnostics.log.names`, „Fehlerbericht anonymisieren“ aus, `--log-names`), im Paket vermerkt. Vor dem Speichern zeigt Atlas jede Datei des Pakets.
- Tastenkonflikte mit anderen Erweiterungen (GExperts, CnPack, MMX) werden erkannt
- Abstürze von Anfragen im Server:
  - jeder Absturz einer Anfrage im Server wird als nachstellbarer Fall gesichert (`%LOCALAPPDATA%\Atlas\crash`: Anfrage, letzte Nachrichten, Schnappschuss der Datei, Einstellungen ohne Zugangsdaten, Aufrufstapel, `wiederholen.cmd` für `AtlasServer --replay`; `Tools/New-CrashTest.ps1` macht daraus einen DUnitX-Test)
  - die Meldung nach dem Neustart nennt Methode, Datei, Zeile und Ausnahme mit „Fall öffnen“ und „Issue anlegen“
  - als Sicherheitsnetz überspringt der Server eine Anfrage, die an derselben unveränderten Datei zweimal abgestürzt ist, sichtbar in Statusleiste und Prüffenster

Einstellungen: `server.crashCases`, `server.crashSkip`

## Weiteres

- **Update-Prüfung** nur nach Zustimmung; **Update-Installer** (#1519): „Jetzt aktualisieren“ lädt und prüft das Update im Hintergrund, ein Konsolenfenster spielt es beim Schließen der IDE ein, mit Auswahl der Module, Rückfall und Ergebnis beim nächsten Start (`updates.install`, `updates.channel`, `updates.newModules`); Delphi 12 bekommt es aus dem Quelltext gebaut
- **Barrierefreiheit:** Listen und Tooltips für UI Automation lesbar
