### Tests
- Mehrere Einfügemarken: Der Ablauf im Puffer (Strg+D, Tippen an allen Marken als ein Schritt, Rückgängig der IDE, Änderung der IDE an der Hauptmarke nachziehen, Kopieren, Einfügen je Marke, Umschließen, Bewegen, Klick, Zeilenenden) liegt im Kern hinter demselben Vertrag für den Editorpuffer wie „Bezeichner mitziehen“ und ist gegen eine Fälschung getestet (#1967).

### Behoben
- Mehrere Einfügemarken: Tippen am Anfang einer Datei, deren alter Text ganz am Ende des neuen steht (etwa eine einzeilige Datei), las vor dem Anfang des Texts (Bereichsfehler im Debug-Build) (#1967).
