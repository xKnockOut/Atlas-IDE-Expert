# Refactorings und Code-Aktionen

Zurück zum [README](../../../README_DE.md)

Code-Aktionen öffnet Alt+Enter; alles steht auch im Menü *Atlas* und im Kontextmenü des Editors.

## Umbenennen und Signatur

- **Umbenennen** projektweit mit Vorschau, samt `.dfm`/`.fmx` und automatisch benannter Ereignis-Handler
- **Signatur ändern** im Dialog: Parameter hinzufügen, entfernen, verschieben, umbenennen, mit Vorschau

## Umbauten im Code

### Einfache Umbauten

- **Methode extrahieren**
- **Variable einführen**
- **Bedingung in Funktion auslagern**
- **with auflösen**
- **case ergänzen**

### **if-Kette ⇄ case umwandeln**

- in beide Richtungen, auch Mengen und Bereiche, Kommentare bleiben

### **Bedingungen umformen**

- Bedingung umkehren mit lesbarer Verneinung
- frühen Ausstieg mit `Exit`/`Continue` einführen
- verschachtelte `if` zusammenfassen
- doppelte Verneinung entfernen

### **if-Anweisung ⇄ Bedingungsausdruck umwandeln**

- Delphi 13 `X := if C then A else B` für Zuweisungen, `Exit` und Aufrufe
- `else if`-Ketten als verschachtelte Ausdrücke
- Klammern nur wo der Vorrang sie verlangt
- `IfThen` ersetzen, das beide Zweige auswertet

### **lokale Routine ⇄ Methode umwandeln**

- Eine lokale Routine wird private Methode bzw. Routine der Unit:
  - Die genutzten Variablen der äußeren werden `var`/`const`-Parameter.
  - Die Aufrufe bekommen die Argumente.
- Eine private Methode oder Routine der Unit mit genau einem Aufrufer wird dessen lokale Routine, wahlweise ohne die Parameter, die nur Variablen des Aufrufers durchreichen.
- Vorher eine Vorschau mit der neuen Signatur.
- Ein Hinweis statt der Aktion, wenn sich die Bedeutung eines Namens ändern würde.

### **lokale Variable ⇄ Feld umwandeln**

- Eine lokale oder Inline-Variable einer Methode wird privates Feld hinter dem letzten Feld:
  - `LLineNo` → `FLineNo` mit änderbarem Namen
  - eine Initialisierung bleibt als Zuweisung
  - der Typ einer Inline-Variablen ohne Angabe wird abgeleitet
- Ein privates Feld, das nur eine Methode benutzt und dort auf jedem Weg zuerst schreibt, wird lokale Variable.
  - nicht für Felder hinter einer Property, published- oder Formularfelder
- Vorschau mit Warnungen, etwa zur geänderten Lebensdauer eines Objekts

### **anonyme Methode ⇄ Methode umwandeln**

- Eine anonyme Methode wird private Methode, in einer freien Routine eine Routine der Unit, mit einem Namen aus dem Zusammenhang wie `HandleClick` oder `CompareByName`.
  - Erfasste Variablen werden Parameter, und an der Stelle bleibt eine kurze anonyme Weiterleitung.
  - Auf Wunsch bei später laufenden Aufrufen Werte in Feldern.
- Eine private Methode, die genau einmal an ein `reference to` übergeben wird, wird wieder anonyme Methode.
  - nie bei `of object` oder Ereignissen der Formulardatei
- Die Vorschau erklärt die gewählte Form.

### **Methode ohne `Self` umwandeln**

- Eine Methode, die weder `Self` noch Instanzmitglieder nutzt, bekommt die Marke „braucht kein Self“; ein Klick darauf (oder Strg+. auf dem Kopf) bietet an, sie umzuwandeln in:
  - eine `class … static`-Methode,
  - eine class-Methode mit Aufrufen über die Klasse,
  - eine freie Routine
  - oder einen Record-Helper für den Typ ihres ersten Parameters,
- über alle Units mit Vorschau jedes geänderten Aufrufs
- wahlweise Hinweisregel `method-without-self`

### **Typ-Alias einführen und auflösen**

- `TList<TKunde>`, Arrays, Mengen und Methodenreferenzen bekommen einen benannten Alias vor der ersten Verwendung.
- Ersetzt wird die Stelle, jeder gleiche Ausdruck der Unit oder des Projekts, gleich nach aufgelösten Typen.
- Offene generische Parameter lehnt Atlas mit Grund ab.
- „Alias auflösen“ ersetzt `X = Y` durch `Y`, wo Delphi es annimmt, und entfernt den Alias.

### **Aufzählung mit Namenstabelle**

- `CStateNames: array[TState] of string` mit Texten aus den Elementnamen anlegen, wahlweise als resourcestring
- Kommt ein Wert dazu oder fällt einer weg, bietet jede Tabelle „Fehlenden Eintrag ergänzen“ bzw. „Überzähligen Eintrag entfernen“ an der richtigen Stelle.
- „Tabellen nachziehen“ ändert alle Tabellen über den Typ im Projekt und ergänzt `case`-Anweisungen ohne `else`, mit Vorschau.

### **Überladung anlegen**

- als Kopie direkt hinter dem Original, beide mit `overload`, danach Tab durch Parameterliste und Rumpf
- als Weiterleitung ohne den letzten Parameter, die die bestehende Überladung mit dem Standardwert seines Typs aufruft, etwa `Write(AText, llInfo)`
- `override` und `virtual` gehen nicht über, Standardparameter schreibt Atlas nie

## Löschen und Verschieben

- **Sicher löschen** (Alt+Entf):
  - Methode, Feld, Property, Typ, Konstante, Variable, Routine oder ganze Unit erst nach der Suche nach Verwendungen im Projekt, in Formularen und uses-Listen löschen
  - Überschreibungen und Freigewordenes auf Wunsch mit
- **Variable und Methode einbetten** *(experimentell)*
- **Klasse in eigene Unit verschieben** *(experimentell)*
- **uses nachziehen nach dem Umbenennen einer Unit** *(experimentell)*

## Klassen-Aktionen

- Interface implementieren
- Methoden überschreiben
- Getter, Setter und Feld erzeugen
- Property aus vorhandenen Zugriffsmethoden
- Interface aus einer Klasse herauslösen
- Basisklasse herauslösen
- Mitglied in Vorfahr oder Nachfahren verschieben
- triviale Zugriffsmethode durch Feld ersetzen (einzeln oder für Unit und Projekt)
- Methode aus einem Aufruf anlegen
- Forward-Deklaration ergänzen

## Weitere Aktionen

- **Texte:** String als `resourcestring` auslagern
- **uses:** fehlende Unit ergänzen, sortieren, ungenutzte entfernen
- **Schnellkorrekturen** zu vielen Prüfregeln, auch „Alle korrigieren“
- **Atlas-Änderungen zurücknehmen** (Strg+Alt+Z): Änderungen über mehrere Dateien als ein Schritt
