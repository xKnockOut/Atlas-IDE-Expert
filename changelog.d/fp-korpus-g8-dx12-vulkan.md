### Behoben
- Prüflauf hing auf großen Header-Übersetzungen (DirectX-, Vulkan-Header): `type-too-large` und die Erkennung verwalteter Typen rechneten verschachtelte Records bis zur Tiefengrenze exponentiell oft neu, `dictionary-get-without-check` durchsuchte je Indexzugriff den ganzen Baum, `magic-number` plante die Korrektur je Literal über die ganze Datei, „Felder im Destruktor freigeben“ suchte je Feld alle Typdeklarationen. Größen und Antworten je Typname werden jetzt gemerkt, Typtabellen einmal je Datei gebaut.
- `constructor-on-instance` meldete den Konstruktor eines Records oder object-Typs auf der Variablen (`Desc.Create(…)`), auch über einen Alias auf einen Record einer anderen Unit; das initialisiert die Variable an Ort und Stelle.
- Weitere Fehlalarme aus dem Korpuslauf (PasVulkan):
  - `type-mismatch` und die Namensauflösung lösen den Typ eines Felds, einer Methode oder Property zuerst über die im eigenen (oder umgebenden) Typ verschachtelten Typen auf; ein gleichnamiger Typ aus dem uses verdeckt sie nicht mehr.
  - `destructor-not-nil-safe`: Im Rumpf von `try … finally` angelegte Felder gelten nicht mehr als „nur bedingt angelegt“.
  - `use-after-free`: `while Assigned(FErster) do FErster.Free` (der Destruktor hängt das Objekt aus der Liste) bleibt still.
  - `deref-before-nil-check`: Nach `New(X)` oder `X := T.Create` auf jedem Weg ist X nie nil; die spätere Abfrage im finally ist nur Vorsicht.
  - `result-not-set`: Ergebnis über eine lokale Variable mit `absolute Result` zählt als gesetzt.
  - `ifthen-side-effect`: Typumwandlungen in den Zweigen (`TFlags(0)`, auch Typen aus anderen Units) sind keine Aufrufe.
