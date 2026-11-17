### Geändert
- Prüfregel `metric-class-size` zählt ehrlich: Freie Routinen einer Unit, die über Parameter oder Variablen auf private oder geschützte Mitglieder einer Klasse derselben Unit zugreifen, zählen als Mitglieder dieser Klasse. Eine Klasse lässt sich so nicht mehr durch Auslagern in freie Routinen unter die Grenze drücken. Der Grenzwert bleibt unverändert.
