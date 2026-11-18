### Neu
- MCP-Werkzeug `find_implementations` (#2635): Umsetzungen einer Interface- oder virtuellen Methode mit Datei:Zeile, Art (umgesetzt, überschrieben, abstrakt, reintroduce, Zuordnung, Delegation über `implements`) und Kennzeichnung von Testunits, optional mit Rumpf (höchstens 20 Zeilen), als Markdown oder JSON; bei Klassen und Interfaces die Nachfahren bzw. umsetzenden Klassen.

### Geändert
- „Gehe zu Implementierung“ und die Zahl der Umsetzungen in der Aufrufhierarchie finden auch Methodenzuordnungen (`procedure IFoo.Bar = MyBar`), Delegation über `property … implements IFoo` und Methoden, die eine Klasse für ein Interface von ihrem Vorfahren erbt; Nachfahren einer umsetzenden Klasse ohne eigene Methode zählen nicht mehr als weitere Umsetzung (#2635).
