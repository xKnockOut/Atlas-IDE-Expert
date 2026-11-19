### Geändert
- JSON lesen überall über `TJsonRead`: die übrigen eigenen Leser für Zeitpunkte (ISO 8601), Listen ganzer Zahlen, Wahrheitswerte, Parameter und Werte als JSON-Text sind entfernt (#1969). Ein fehlender Wert, null oder ein falscher Typ liefern jetzt überall die Vorgabe statt je nach Stelle eine Ausnahme. Eine Prüfung im Build erkennt neue Kopien an ihrer Form statt am Namen.
