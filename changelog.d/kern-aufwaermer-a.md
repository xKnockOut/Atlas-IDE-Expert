### Behoben
- Plugin-Zeiten: Der gemeinsame Rekorder entsteht beim Laden des Packages statt beim ersten Messpunkt; zwei Threads können nicht mehr gleichzeitig je einen anlegen.
- Eigenschaften im Designer setzen: Unbekannte Elemente eines Mengenwerts werden vor dem Setzen erkannt, ohne eine Ausnahme der RTL abzufangen.

### Tests
- Ereignisprotokoll, Plugin-Zeiten und Eigenschaftswerte ohne eigene Aufwärmer (den ersten Regex-Fehler deckt `Atlas.Tests.FirstUse` ab): Der Rekorder liegt vor dem ersten Test bereit, und ein unbekanntes Mengenelement lädt keinen Ressourcentext der RTL mehr.
