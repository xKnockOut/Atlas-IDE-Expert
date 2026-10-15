# 0011: Atlas-Bereiche als Plugins der IDE-Willkommensseite, Layout über die Registry

- Status: Angenommen
- Datum: 2026-10-15
- Bezug: #761 Willkommensseite (Epic), #753 Rahmen und Atlas-Layout, #767 frei konfigurierbares Layout

## Kontext

Atlas soll beim Start der IDE eigene Bereiche zeigen (Zustand, Weiterarbeiten, Projekte, Neu in Atlas …), am besten auf der Willkommensseite von RAD Studio. Die Open Tools API dokumentiert die Willkommensseite kaum. Die Beispiele von Embarcadero (RADStudio12Demos, Object Pascal/ToolsAPI/WelcomePage) zeigen eine Schnittstelle in `ToolsAPI.WelcomePage`, die es in RAD Studio 12 und 13 gibt. Das Layout der Seite (welcher Bereich in welcher Zeile und Spalte steht, welche ausgeblendet sind) legt die IDE nicht über eine Schnittstelle offen, sondern speichert es in der Registry. Marcos Export aus Delphi 12 (BDS 23.0) zeigt das Format:

- `…\BDS\<Version>\WelcomePage\Layout`: `RowsCount`, `ColumnsCount`
- `…\Layout\Item <n>`: `PluginID`, `Row`, `Column`, `RowSpan`, `ColumnSpan`
- `…\WelcomePage\AvailablePlugins`: `"0"`, `"1"`, … = ausgeblendete Bereiche

## Entscheidung

- **Jeder Atlas-Bereich ist ein Inhalts-Plugin** der Willkommensseite: Er implementiert `INTAWelcomePagePlugin` und `INTAWelcomePageContentPluginCreator` und wird mit `WelcomePagePluginService.RegisterPluginCreator` angemeldet. Die IDE bekommt einen Rahmen mit Titelzeile (`CreateCaptionFrame`), in den der Atlas-Frame als Client gesetzt wird. So lassen sich Atlas-Bereiche wie die eingebauten verschieben, ein- und ausblenden. Die Kennungen sind `Atlas.Welcome.<Bereich>`.
- **Atlas-Layout als ein Bereich „Atlas“:** Mit `welcomePage.layout = atlas` meldet Atlas statt der einzelnen Bereiche einen Bereich `Atlas.Welcome.board` an (Kopf plus alle Bereiche in zwei Spalten). Atlas setzt ihn in der Registry oben über alle Spalten (zwei Zeilen hoch) und schiebt die übrigen Bereiche nach unten.
- **Sicherung vor dem ersten Eingriff:** Bevor Atlas das Layout das erste Mal ändert, sichert es den ganzen Schlüssel `WelcomePage` (alle Werte mit Typ und alle Unterschlüssel) nach `%LOCALAPPDATA%\Atlas\welcomepage-layout-backup.json`. Gab es den Schlüssel nicht, steht das in der Sicherung. „Atlas-Layout zurücksetzen“ schreibt den Stand exakt zurück (bzw. löscht den Schlüssel) und entfernt die Sicherung.
- **Marke für den nächsten Start:** Da offen ist, ob die IDE ein geändertes Layout sofort liest oder ihr Layout beim Beenden aus dem Speicher zurückschreibt, legt Atlas `%LOCALAPPDATA%\Atlas\welcomepage-layout-pending` mit dem gewünschten Stand an (`atlas` oder die wiederherzustellende Sicherung). Beim nächsten Start wiederholt Atlas den Eingriff, falls die Registry ihn nicht mehr enthält; gilt er, entfällt die Marke. Danach darf der Benutzer den Bereich „Atlas“ frei verschieben.
- **Ersatz ohne Schnittstelle:** Fehlt `WelcomePagePluginService` oder ist `welcomePage.host = dockWindow`, zeigt das andockbare Fenster „Atlas-Start“ (Ansicht › Atlas-Start) dieselben Bereiche in einer Spalte.
- **Schichten:** Bereichsregister, Layout, Grußzeile, Sicherung und Raster ohne VCL und ohne Open Tools API in `Atlas.Core.Welcome.*` (getestet), Frames in `Atlas.UI.Welcome.*`, Anbindung an die IDE in `Atlas.IDE.Welcome.*`. #753 nannte `Atlas.Common` für die Datenklassen; das Plugin-Package bindet `Atlas.Common` aber nicht ein, daher liegen sie in der VCL- und OTA-freien Schicht `Atlas.Core` des Plugins.
- **Inhalts-Plugins statt Listen-Plugins:** `INTAWelcomePageDataPluginListView` zeigt nur Listenzeilen. Da Inhalts-Plugins mit eigenem VCL-Frame in 12 und 13 gehen, nutzen alle Atlas-Bereiche Frames; Listen bleiben Bereichen vorbehalten, die nur Zeilen zeigen.

## Alternativen

- **Eigene Willkommensseite als Editor-Ansicht:** volle Kontrolle, aber eine zweite Startseite neben der der IDE; doppelt und gegen die Gewohnheit der Benutzer.
- **Nur das Fenster „Atlas-Start“:** einfach und ohne Registry, aber nicht dort, wo man beim Start hinschaut.
- **Layout über Fensterklassen der IDE suchen und umsortieren:** hängt an internen Klassen, die sich je Version ändern, und wirkt nicht über einen Neustart hinaus.
- **Layout ohne Sicherung ändern:** schneller umgesetzt, aber der Benutzer verlöre seine Anordnung ohne Weg zurück.

## Folgen

- Atlas-Bereiche verhalten sich wie eingebaute; der Benutzer ordnet sie mit den Mitteln der IDE.
- Das Registry-Format ist nicht dokumentiert. Ändert Embarcadero es, findet `TAtlasHostLayout.Read` kein Raster; Atlas geht dann von der Vorgabe der IDE aus, und „Zurücksetzen“ bringt immer den gesicherten Stand zurück.
- Spätere Bereiche (#754–#767) melden nur eine Fabrik in `TAtlasWelcomeViews` und einen Eintrag in `TAtlasWelcomeSections` an; Willkommensseite, Bereich „Atlas“ und „Atlas-Start“ nutzen sie ohne weitere Anpassung.
- Ob die IDE das geänderte Layout sofort übernimmt, prüft Marco in RAD Studio 13; die Marke deckt beide Fälle ab.
- Projektzustand (#592): Das Issue entstand vor dieser Entscheidung und nennt `INTAWelcomePageDataPluginListView`, ein eigenes Fenster „Projektzustand“ und die Seite „Allgemein“. Es lässt einen frei gezeichneten Bereich ausdrücklich zu, wenn die Listenansicht nicht reicht. Die Listenansicht kann keine farbigen Marken, keine anklickbare Fehler-Marke und kein eigenes Kontextmenü; darum ist „Projekte“ ein Inhalts-Frame wie alle Atlas-Bereiche. Der Ersatz ohne Schnittstelle (Delphi 12, Host `dockWindow`) ist das gemeinsame Fenster „Atlas-Start“ (*Ansicht › Atlas-Start*), kein zweites Fenster. Die Einstellungen `welcomePage.projectStatus`, `.maxProjects` und `.refreshVcs` stehen auf der Seite *Willkommensseite*, die #753 für alle `welcomePage.*`-Schlüssel angelegt hat. Im Atlas-Layout steht „Projekte“ im Bereich „Atlas“; außerhalb ist es ein eigener Bereich „Projekte“.
- Nicht gesichert (#762): Das Issue nennt `Atlas.Common` für die reine Auswertung; sie liegt wie bei #753 in `Atlas.Core.Welcome.Unsaved`, weil das Plugin `Atlas.Common` nicht einbindet. „Ansehen“ soll die Änderungsansicht der Versionsverwaltung öffnen; #571 hat keine, darum listet Atlas die Dateien im Fenster „Atlas-Ergebnisse“ (Doppelklick öffnet die Datei). Was #571 fehlte (Branches mit Upstream, Stashes, ausgehende Commits, Push), ergänzt eine eigene Rolle `IAtlasVcsLocalWork`, damit `IAtlasVersionControl` und seine Test-Fälschungen unverändert bleiben. „Je Projekt und Art eine Zeile“ heißt: mehrere Stashes, Branches ohne Upstream oder Branches mit Vorsprung stehen zusammengefasst in einer Zeile; repository-weite Arten erscheinen je Arbeitskopie einmal. Ein Branch ohne Upstream zählt nur, wenn er Commits hat, die auf keinem Remote liegen. Der Bereich ist nicht im Atlas-Layout verankert und steht in seiner Vorgabespalte rechts (Mockup WS9).
- Weiterarbeiten (#755): Das Issue nennt keinen Ort für „Gemerkt“; es ist ein zweiter Reiter im Bereich „Weiterarbeiten“ (linke Spalte), abschaltbar mit `welcomePage.saved`. Favoriten (#458) gehören zu keinem Projekt und keiner Datei: Sie stehen unter „alle Projekte“, der Ort ist die Unit, der Sprung sucht deren Datei im Index-Cache (Projekte und Bibliothek) und die Deklaration im Text. Ein Klick auf einen eingehenden Commit zeigt dessen Dateien im Fenster „Atlas-Ergebnisse“, weil #571 keine Commit-Ansicht hat. SVN hält keinen lokalen Stand des Servers; ohne `fetch` gäbe es nichts Neues zu zeigen, darum fehlt der Abschnitt „Neu seit …“ bei SVN wie ohne Versionsverwaltung. Der Arbeitsstand entsteht beim Schließen; ohne offene Reiter (z. B. „Alle schließen“ vor dem Projekt) bleibt der gespeicherte Stand stehen, und mit `welcomePage.continue` aus zeichnet Atlas nichts auf.
