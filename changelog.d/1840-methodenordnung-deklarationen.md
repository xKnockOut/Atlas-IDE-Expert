### Behoben
- Methodenrümpfe ordnen (Befehl und Korrektur der Regel `method-order`, #1840) schob einen Rumpf über einen Typ, eine Konstante oder eine freie Routine des implementation-Teils, die er braucht; die Unit übersetzte danach nicht mehr. Ein Rumpf rückt jetzt nur so weit vor, wie alles, was er nennt, schon deklariert ist.
