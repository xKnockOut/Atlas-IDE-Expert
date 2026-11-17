### Behoben
- Mutationslauf: Vor dem ersten Bau eines großen Projekts stand der Hauptthread unnötig lange, weil die Suche außerhalb von Kommentaren und Zeichenketten für jede Zeichenkette den Text vom Anfang an kopierte. Sie liest jetzt nur noch die Zeile der Zeichenkette; die Arbeit wächst nur noch linear mit der Länge der .dpr.
- Editor: Klammerfarben, ausgegraute Zweige und verschiebbare uses-Einträge lasen beim Zeichnen für jeden Textlauf mehrere Kopien aller Einstellungen. Die Einstellungen werden jetzt einmal je Bildaufbau gelesen.
