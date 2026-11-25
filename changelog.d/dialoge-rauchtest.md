### Behoben
- Dialog „Leckprüfung einrichten …“ (#1880): Die Varianten Einfach, FastMM4 und FastMM5 bilden eine Gruppe. Mit der Tabulatortaste erreicht man die gewählte Variante, die Pfeiltasten wechseln sie; vorher lag jede Variante in einem eigenen Feld und war mit der Tastatur nicht zu wählen.

### Tests
- Jeder Dialog des Plugins wird in einem Test gebaut: Rauchtests legen alle 88 Dialoge mit kleinster Eingabe an, geben ihnen und allen Steuerelementen ein Fenster und durchlaufen `DoShow`. `Tools/Check-DialogTests.ps1` (in der CI) lässt keinen Dialog ohne solchen Test zu. Dafür haben die Liste der gelernten Vorschläge und das vergrößerte Bild eines Issues einen eigenen Konstruktor.
