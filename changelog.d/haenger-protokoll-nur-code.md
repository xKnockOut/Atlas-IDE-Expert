### Behoben
- Hängerprotokoll (atlas.log): „Atlas im Aufrufstapel“ zählt nur noch Adressen im Code eines Atlas-Moduls. Bisher reichte ein Zeiger in die Daten von Atlas auf dem Stapel, etwa während die IDE übersetzt. Rahmen der Module (Willkommensseite, Prüfregeln …) bekommen jetzt Unit, Routine und Zeile aus ihrer Map-Datei, nicht nur Rahmen von Atlas.IDE.Base.
