### Behoben
- Entladen bei laufender IDE: Hängt eine Quelle der Vervollständigung beim Entladen noch, hält Atlas das Package ihres Codes (auch eines einzeln entladenen Moduls) im Speicher, bis sie zurückkehrt, statt später in nicht mehr geladenen Code zu springen. Ebenso der Besitzer der Hauptthread-Einträge.
- Debugger: Endet der Prozess während einer Auswertung, meldet Atlas den Notifier am schon abgebauten Thread nicht mehr ab.
