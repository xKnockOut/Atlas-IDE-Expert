# Einstellungen

Zurück zum [README](../../../README_DE.md)

- *Tools › Optionen › Drittanbieter › Atlas* als Baum: Bereiche oben, jede Funktion mit eigenem Hauptschalter, der ihre Unteroptionen mit abschaltet; daneben die Seiten *Snippets*, *Tastenkonflikte* und *Server*
- Jede sichtbare Funktion lässt sich einzeln abschalten; experimentelle Funktionen sind gekennzeichnet
- Einstellungen exportieren, importieren, Profile laden und zurücksetzen
- Teamweite Werte in der Projektdatei `.atlas` (neben der .dproj, in einem Ordner darüber bis zur Wurzel von Git oder SVN oder neben der .groupproj), Server- und Regeleinstellungen in `atlas.json` (*Atlas › Projekt-Einstellungen*), globale Werte in `%APPDATA%\Atlas\settings.json`

- Sprache wie die IDE (#1458): Mit englischer Delphi-IDE sind Beschreibungen der Einstellungen, „Neu in Atlas“ und die ersten Servertexte (Regelerklärungen, unbekannte Regel-IDs, überflüssige Unterdrückungen) englisch, mit deutscher IDE bleibt alles deutsch; `language` (`""` wie die IDE, `"de"`, `"en"`) legt sie fest, `AtlasServer --check` nimmt `--locale de|en`. Die Servertexte wandern gruppenweise in Texttabellen (`TAtlasText`); `Tools/Check-GermanText.ps1` hält neue deutsche Literale fern

Alle Schlüssel: [docs/Einstellungen.md](../../../docs/Einstellungen.md) und [docs/Konfiguration.md](../../../docs/Konfiguration.md), englisch [docs/en/Configuration.md](../../../docs/en/Configuration.md).
