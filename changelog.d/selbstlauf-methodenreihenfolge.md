### Behoben
- Korrektur von `method-order` und Ordnen der Methodenrümpfe: Rückt ein Rumpf über eine freie Routine oder eine Deklaration (const, var, type) nach vorn, die er braucht, wandert sie jetzt mit vor den ersten Rumpf. Vorher übersetzte das Ergebnis nicht (unbekannter Bezeichner).
