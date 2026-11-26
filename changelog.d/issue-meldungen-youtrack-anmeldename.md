### Behoben
- Meldungen zu meinen Issues (YouTrack): Auch mit 2.2.4 lehnte ein YouTrack mit deutscher Systemsprache die Abfrage ab („Can't parse search query“, HTTP 400). Atlas fragt jetzt mit dem eigenen Anmeldenamen statt „me“/„meine“ und verbindet Umfang und Zeitraum ausdrücklich mit AND; scheitert die Abfrage, steht sie (ohne Anmeldenamen) im Protokoll.
