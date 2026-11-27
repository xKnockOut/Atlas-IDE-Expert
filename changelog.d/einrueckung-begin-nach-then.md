### Behoben
- Einrückung beim Tippen (`smartIndent.outdentClosers`): Ein begin in eigener Zeile hinter then, else oder do bleibt nicht mehr eine Ebene zu tief stehen. Nach dem Enter dahinter kommt es auf die Spalte von if, else bzw. for/while/with, der Rumpf eine Ebene tiefer, ein end direkt darunter rückt mit. Rückt die Datei solche begin sonst ein, bleibt es dabei.
