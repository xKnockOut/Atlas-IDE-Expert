### Behoben
- Prüfregeln `declared-not-implemented`, `implemented-not-declared` und `signature-mismatch` brauchten in großen Units quadratisch viel Zeit (eine Unit mit 2500 Methoden gut 13 s je Regel). Deklarationen und Rümpfe werden jetzt einmal je Datei über Tabellen zugeordnet und von den drei Regeln geteilt; die Befunde bleiben gleich (#1477).
