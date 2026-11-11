# Einstellungen

Zurück zum [README](../../../README_DE.md)

- *Tools › Optionen › Drittanbieter › Atlas* als Baum: Bereiche oben, jede Funktion mit eigenem Hauptschalter, der ihre Unteroptionen mit abschaltet; daneben die Seiten *Snippets*, *Tastenkonflikte* und *Server*
- Jede sichtbare Funktion lässt sich einzeln abschalten; experimentelle Funktionen sind gekennzeichnet
- **Einstellungen suchen** (#1884, `settings.search`): Über dem Baum jedes Knotens und auf der Übersicht „Atlas“ steht ein Suchfeld (Strg+F oder Strg+E). Gesucht wird in Beschriftung, Beschreibung, Schlüssel (`hover.signatureParams`, auch Teile wie „signature“), Bereich und Unterpunkt sowie in Synonymen (`x-keywords` im Schema, etwa „tooltip“ für Hover, „lint“ für Prüfregeln); deutsche Begriffe treffen auch in der englischen IDE. Ein Tippfehler je Wort ist erlaubt („minimpa“). Jede Zeile nennt Weg und Zustand: geändert, experimentell, gesperrt mit Grund, Modul aus, im Projekt festlegbar; Treffer anderer Knoten tragen „in <Package>“. Enter öffnet den ersten Treffer, ↓ geht in die Liste, Esc leert das Feld. Einstellungen nicht installierter Module erscheinen nicht.
- **Einstellungen in der Befehlspalette** (#1884, `palette.settingsPrefix`): `@` vor dem Suchtext zeigt nur Einstellungen mit Weg, Taste und Zustand. Enter öffnet *Tools › Optionen* an der Einstellung, Alt+Enter schaltet einen Schnellschalter direkt um.
- **F1-Hilfe** (#1886, Modul `Atlas.IDE.Help`, `help.enabled`): F1 auf einer Einstellung öffnet ihren Eintrag in der [Einstellungsdoku](../../Einstellungen.md), F1 auf einem Atlas-Befund (Editor, „Atlas-Prüfung“) die Seite der Regel, F1 in einem Atlas-Fenster dessen Funktionsseite. `help.source` wählt die Doku auf GitHub zur installierten Version (`online`) oder die lokale HTML-Doku neben dem Plugin (`local`, Ordner `Doku`; fehlt sie, gilt einmalig mit Hinweis die Online-Seite). Compilermeldungen haben keine Atlas-Seite; ohne Modul oder ohne Seite geht F1 wie bisher an die IDE.
- **Modulschalter** für ganze Bereiche (`debug.enabled` … `search.enabled`, `ruleChecks.enabled`, `welcomePage.enabled`):
  - Debuggen, Issue-Tracker, Analyse, Tests, Build-Werkzeuge, Build-Pipeline, Lesezeichen, Designer, Prüfregeln, Suche und Willkommensseite
  - Ein ausgeschaltetes Modul schaltet seine Funktionen und Befehle ohne Neustart ab, die gespeicherten Werte bleiben.
  - Das Profil *Nur Code Insight* lässt nur den Kern an.
  - Jedes Modul-Package bringt seine Einstellungen als eigenen Abschnitt im Optionsdialog mit; ist nur `Atlas.IDE.Base` installiert, erscheinen nur die Einstellungen von Base.
  - Legt die `atlas.json` eines Projekts Prüfregeln fest, während das Modul Prüfregeln aus ist, weist Atlas einmal darauf hin.
- Einstellungen exportieren, importieren, Profile laden und zurücksetzen
- Teamweite Werte in der Projektdatei `.atlas` (neben der .dproj, in einem Ordner darüber bis zur Wurzel von Git oder SVN oder neben der .groupproj), Server- und Regeleinstellungen in `atlas.json` (*Atlas › Projekt-Einstellungen*), globale Werte in `%APPDATA%\Atlas\settings.json`

- Sprache wie die IDE (#1458): Mit englischer Delphi-IDE sind Beschreibungen der Einstellungen, „Neu in Atlas“ und die ersten Servertexte (Regelerklärungen, unbekannte Regel-IDs, überflüssige Unterdrückungen) englisch, mit deutscher IDE bleibt alles deutsch; `language` (`""` wie die IDE, `"de"`, `"en"`) legt sie fest, `AtlasServer --check` nimmt `--locale de|en`. Die Servertexte wandern gruppenweise in Texttabellen (`TAtlasText`); `Tools/Check-GermanText.ps1` hält neue deutsche Literale fern

Alle Schlüssel: [docs/Einstellungen.md](../../../docs/Einstellungen.md) und [docs/Konfiguration.md](../../../docs/Konfiguration.md), englisch [docs/en/Configuration.md](../../../docs/en/Configuration.md).
