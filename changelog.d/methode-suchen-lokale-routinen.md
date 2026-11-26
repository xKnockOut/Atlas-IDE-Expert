### Behoben
- „Methode suchen“ der Editorleiste findet jetzt auch lokale (verschachtelte) Prozeduren und Funktionen in Methoden und Routinen, angezeigt als „TFoo.Bar › Lokal“ direkt hinter ihrer Methode; vorgewählt ist die innerste Routine am Cursor.
- Gliederung und projektweite Symbolsuche („#“ in Datei oder Symbol öffnen, workspace/symbol) zeigen lokale Prozeduren und Funktionen jetzt ebenso: in der Gliederung unter ihrer Methode (der Cursor markiert die lokale Routine), in der Symbolsuche mit Unit und umgebender Routine. Der Index-Cache wird dafür einmal neu aufgebaut.
