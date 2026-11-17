### Behoben
- Debug-Bau mit Bereichsprüfung: Ein Tag mit Vorzeichen wie `2026--1-05` im Zeitprotokoll der Issues oder ein solcher Zeitpunkt im svn-Verlauf der Hotspots löste `ERangeError` aus, statt übergangen zu werden. Zeitstempel liest jetzt überall derselbe Leser, der jede Ziffer selbst prüft.
