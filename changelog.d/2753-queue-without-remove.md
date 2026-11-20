### Neu
- Prüfregel `queue-without-remove` (#2753): meldet Thread-Klassen, die mit `Queue`/`ForceQueue` am eigenen Thread einreihen, ohne dass Destruktor, `DoTerminate`, ein Vorfahr oder der Besitzer die Einträge mit `RemoveQueuedEvents` entfernt. Die Korrektur ergänzt `RemoveQueuedEvents(Self)` im Destruktor bzw. legt ihn an.
