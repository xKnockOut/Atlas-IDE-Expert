### Neu
- KI-Assistenten: Einfache KI-Aufgaben (eine Frage, eine Antwort, z. B. „Zusammenfassen“ im Fenster „Atlas-Issue“) können einen KI-Anbieter der IDE mitbenutzen (Smart CodeInsight, ab Delphi 12.2). `assistants.ideProvider` schaltet es ein, `assistants.ideProvider.name` wählt den Anbieter, `assistants.textSource` legt fest, ob der Anbieter der IDE oder der eigene zuerst gefragt wird. Die Seite KI-Assistenten listet die Anbieter der IDE mit Status und Funktionen und öffnet Smart CodeInsight. Dateien unter `assistants.exclude` gehen an keine Quelle (#2744).
- KI-Assistenten: Der eigene KI-Anbieter lässt sich als „Atlas (…)“ bei Smart CodeInsight der IDE anmelden (`assistants.registerInIde`): Chat und Anweisungen der IDE laufen dann über ihn, mit derselben Tagesgrenze wie der KI-Schattentext; die Seite des Eintrags zeigt Anbieter, Modell und die Anfragen von heute. Atlas wählt seinen eigenen Eintrag nie als Anbieter der IDE (#2745).

### Geändert
- KI-Schattentext und Anfragen der IDE teilen sich den Tageszähler in `%LOCALAPPDATA%\Atlas\ai-requests.json`; jede Anfrage liest ihn neu, statt ihn nur beim Start zu laden (#2745).
- Regel `ota-notifier-not-removed`: `Result := X.AddNotifier(…)` in einer eigenen Methode `AddNotifier` (Umsetzung einer Schnittstelle mit eigenem Notifier-Paar) gilt nicht mehr als Fund; den Index bekommt der Aufrufer (#2745).
