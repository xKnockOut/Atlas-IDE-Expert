# 0015: Atlas-Willkommensseite wieder auf der Willkommensseite der IDE, Fenster unabhängig

- Status: Angenommen
- Datum: 2026-10-29
- Bezug: #761 Willkommensseite (Epic), nimmt [ADR 0014](0014-willkommensseite-nur-fenster.md) (#1114) teilweise zurück, gilt mit [ADR 0011](0011-willkommensseite.md); #1233 Zugriffsverletzung beim Beenden

## Kontext

ADR 0014 hatte die Atlas-Bereiche von der Willkommensseite der IDE genommen; seitdem gab es sie nur im Fenster „Atlas-Start“. Im Hintergrund stand die Zugriffsverletzung beim Beenden der IDE. Sie ist mit #1233 behoben und hatte mit der Willkommensseite nichts zu tun: Ursache waren die über `RequestGutterColumn` angeforderten Spalten der Zeilenleiste, die beim Abbau der Editorfenster noch standen (`Atlas.IDE.Foundation.GutterColumns`).

Marco möchte die Atlas-Willkommensseite wieder auf der Willkommensseite der IDE sehen und das Fenster „Atlas-Start“ behalten. Jede sichtbare Funktion soll abschaltbar sein.

## Entscheidung

- **Plugins der Willkommensseite wie in ADR 0011:** `Atlas.IDE.Welcome.Page` meldet jeden Atlas-Bereich als Inhalts-Plugin an (plus Kopf), im Atlas-Layout (`welcomePage.layout = atlas`) ein Plugin „Atlas“ mit Kopf und allen Bereichen. Die Befehle *Atlas-Layout anwenden* und *Atlas-Layout zurücksetzen*, Sicherung und Marke kommen unverändert zurück, ebenso der Tipp „Atlas-Layout“.
- **Zwei unabhängige Orte statt `welcomePage.host`:** Neuer Schalter `welcomePage.ideWelcomePage` (Registry `WelcomePageIdePage`, Vorgabe an) für die Willkommensseite der IDE. Das Fenster „Atlas-Start“ bleibt wie in ADR 0014 (`welcomePage.openOnStart`, `welcomePage.openWhenNoProject`, Menü, Palette, Desktop). Beide können zugleich offen sein; der Hauptschalter `welcomePage.enabled` schaltet beide ab. `welcomePage.host` aus ADR 0011 kommt nicht zurück, weil ein Ort entweder-oder das Fenster an die Willkommensseite koppeln würde.
- **Aufräumen, solange Atlas nicht auf der Willkommensseite der IDE stehen soll:** Das Aufräumen aus ADR 0014 (`TAtlasWelcomeRetire`) läuft beim Start nur noch, wenn `welcomePage.ideWelcomePage` oder `welcomePage.enabled` aus ist, und beim Abschalten in den Optionen. So bleibt nach dem Abschalten kein leerer Bereich „Atlas“ und kein Loch im Raster. Beim Wiedereinschalten verwirft Atlas die Marke mit dem aufgeräumten Stand, damit der nächste Start die Atlas-Bereiche nicht erneut entfernt, und setzt im Atlas-Layout den Bereich „Atlas“ wieder oben hin. Die Schritte beim Umschalten entscheidet `TAtlasIdePageSteps` (ohne VCL, getestet).
- **Abbau beim Entladen:** Vor dem Abmelden der Plugins gibt `TAtlasIdeWelcomePage.RemoveAll` die Atlas-Inhalte in den Rahmen der IDE frei. Kein Objekt einer Atlas-Klasse soll in einem Fenster der IDE stehen bleiben, das die IDE erst nach dem Entladen von Atlas abbaut; das ist dieselbe Ursache wie bei #1233. Den Rahmen selbst gibt die IDE frei (#1091).
- **Suchtaste:** Strg+E gehört Atlas, solange der Fokus in der innersten Form des Suchfelds liegt: im Fenster „Atlas-Start“ oder im Editorfenster, das gerade die Willkommensseite der IDE zeigt.

## Alternativen

- **`welcomePage.host` zurückholen:** Das wäre ein reines Zurückdrehen, aber das Fenster „Atlas-Start“ wäre dann wieder nur ein Ersatz für die Willkommensseite und nicht unabhängig schaltbar.
- **Nur das Atlas-Layout, keine einzelnen Bereiche:** einfacher, aber die Vorgabe von ADR 0011 (Bereiche wie die eingebauten verschieben) ginge verloren.
- **Aufräumen bei jedem Start wie in ADR 0014:** Es würde die Atlas-Bereiche bei jedem Start aus dem Raster nehmen, das Raster der IDE hinge an Atlas statt am Benutzer.

## Folgen

- Mit der Vorgabe stehen die Atlas-Bereiche nach dem Update wieder auf der Willkommensseite der IDE; das Raster ordnet die IDE, bis man *Atlas-Layout anwenden* wählt.
- Wohin die IDE neu angemeldete Bereiche setzt und ob sie ein geändertes Raster sofort übernimmt, ist weiter nur in der IDE prüfbar (Handtests WP18–WP27); die Marke deckt beide Fälle ab.
- Ein eingeschaltetes `welcomePage.openWhenNoProject` öffnet „Atlas-Start“ auch dann, wenn die IDE beim Schließen des letzten Projekts ihre Willkommensseite zeigt. Wer nur die Willkommensseite der IDE möchte, schaltet es ab.
- Ein Einstellungsprofil mit `welcomePage.host` meldet den Schlüssel weiter als unbekannt.
