### Tests
- Willkommensseite: Die Abfrage eingehender Commits bildet ihren Schlüssel selbst aus dem Projektpfad; Schlüssel und Projekt der gezeigten Commits können nicht mehr auseinanderlaufen (roter Test `IncomingArrivedNeedsSameKey`).
- Leckmessung: Der Zwischenspeicher der Feldadressen von `TComponent` ist im Testlauf aus; er meldete je neuer Besitzerklasse benannter Komponenten 240 bis 340 Byte als Leck (`ChildrenGoWithTheirContainer`). Zwei Aufwärmer der Designer-Tests entfallen.
