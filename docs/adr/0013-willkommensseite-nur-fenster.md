# 0013: Atlas-Willkommensseite nur im Fenster „Atlas-Start“

- Status: Angenommen
- Datum: 2026-10-23
- Bezug: #1114, löst ADR 0011 teilweise ab (Plugins der IDE-Willkommensseite, Atlas-Layout in der Registry); #761 Willkommensseite (Epic), #879 Toolfenster

## Kontext

Seit ADR 0011 meldet Atlas seine Bereiche als Plugins der Willkommensseite von RAD Studio an, wahlweise einzeln oder als ein Bereich „Atlas“, den Atlas über die Registry oben über alle Spalten setzt. Daraus folgten:

- Eingriffe in das undokumentierte Raster `…\BDS\<Version>\WelcomePage\Layout`, mit Sicherung, Marke für den nächsten Start und Befehlen zum Anwenden und Zurücksetzen.
- Lebensdauerfragen: Die IDE gibt die Plugins beim Beenden frei, bevor Atlas entladen wird (#1091, behoben).
- Zwei Orte für dieselben Bereiche (Willkommensseite und „Atlas-Start“) mit eigener Pflege von Titeln, Thema und Anordnung; „Seite anpassen“ (#767) konnte die eingebauten Bereiche ohnehin nicht umordnen.

Marco findet die Atlas-Willkommensseite selbst besser als die der IDE und möchte sie nur sehen, wenn er sie öffnet.

Zur Zugriffsverletzung beim Beenden der IDE: Sie hat mit der Willkommensseite nichts zu tun. Der Abbau-Fehler der Willkommensseite ist seit #1091 behoben; die verbleibende Zugriffsverletzung in rtl370 fing cdb in `TEditWindow.Notification` beim Aufruf einer Komponente des entladenen Beyond-Compare-Experten. Diese Entscheidung ist deshalb keine Fehlerbehebung, sondern eine Vereinfachung.

## Entscheidung

- **Keine Plugins mehr auf der Willkommensseite der IDE.** Atlas ruft `ToolsAPI.WelcomePage` nicht mehr auf; `Atlas.IDE.Welcome.Page` entfällt. Die IDE zeigt ihre eigene Willkommensseite unverändert.
- **Die Atlas-Willkommensseite ist das andockbare Fenster „Atlas-Start“** (*Ansicht › Atlas-Start*, Befehl `Atlas.WelcomeStart`, Befehlspalette). Es öffnet sich nur auf Wunsch oder, mit `welcomePage.openOnStart` (Vorgabe aus), einmal beim Start der IDE. Ein geöffnetes Fenster stellt der Desktop der IDE wie bisher wieder her (#879).
- **Einstellungen:** `welcomePage.host` und `welcomePage.layout` entfallen; dazu `welcomePage.openOnStart` (Registry `WelcomePageOpenOnStart`). Der Hauptschalter `welcomePage.enabled` schaltet das Fenster und alle Befehle ab. „Seite anpassen“, „Neu in Atlas“ und die Suche öffnen „Atlas-Start“.
- **Einmaliges Aufräumen beim ersten Start:** Liegt eine Sicherung `%LOCALAPPDATA%\Atlas\welcomepage-layout-backup.json` aus ADR 0011 vor, schreibt Atlas sie exakt zurück. Ohne Sicherung (oder mit unlesbarer) entfernt Atlas alle `Atlas.Welcome.*`-Einträge aus Raster und `AvailablePlugins` und schließt dadurch leer gewordene Zeilen (`TAtlasHostLayout.WithoutAtlas`). Ein Layout ohne Atlas bleibt unberührt. Weil die IDE ihr Layout beim Beenden aus dem Speicher zurückschreiben kann, legt Atlas wie in ADR 0011 die Marke `welcomepage-layout-pending` mit dem bereinigten Stand an und wiederholt den Eingriff beim nächsten Start einmal; danach ist die Sicherung gelöscht.
- **Suchtaste:** Strg+E gehört Atlas nur, solange der Fokus im Fenster „Atlas-Start“ liegt, sonst bleibt die Taste die inkrementelle Suche der IDE (auch, wenn das Fenster neben dem Editor angedockt ist).

## Alternativen

- **Fenster als Vorgabe, Willkommensseite als Einstellung behalten:** weniger Code entfernt, aber zwei Orte bleiben in Pflege, und die Registry-Eingriffe blieben.
- **Erst die Gegenprobe ohne den Beyond-Compare-Experten abwarten:** klärt die Zugriffsverletzung, ändert aber nichts daran, dass Marco nur das Fenster sehen möchte.
- **Bei der Umstellung nichts aufräumen:** Nach dem Update bliebe auf der Willkommensseite der IDE ein leerer Bereich „Atlas“ bzw. ein Loch im Raster, bis der Benutzer es von Hand behebt.

## Folgen

- Atlas schreibt außer dem einmaligen Aufräumen nichts mehr unter `WelcomePage`. Sicherung, Marke und das Lesen des Rasters (`Atlas.Core.Welcome.Backup`, `Atlas.Core.Welcome.HostLayout`) bleiben nur dafür.
- Bereiche, Kopf, Suche, „Seite anpassen“ und Layouts (#753–#767) wirken unverändert, nur im Fenster. Ihre Texte in CHANGELOG und Testfällen, die von der Willkommensseite sprechen, gelten für „Atlas-Start“.
- Die Befehle *Atlas-Layout anwenden* und *Atlas-Layout zurücksetzen* sowie der Tipp „Atlas-Layout“ entfallen.
- Ein importiertes Einstellungsprofil mit `welcomePage.host` oder `welcomePage.layout` meldet diese Schlüssel als unbekannt und überspringt sie.
