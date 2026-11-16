### Behoben
- Profiler: Endet der Atlas-Server während eines Profil-Laufs (Neustart, Einstellungen, IDE schließen), hält er die Messung als ersten Schritt an und schreibt den Lauf. Vorher konnte das harte Beenden nach der Schonfrist einen Thread des gemessenen Programms dauerhaft angehalten zurücklassen (#2057).
- AtlasMonitor zeigt in den Einzelheiten, welchen Prozess ein Server gerade mit dem Profiler misst, und warnt vor „Server beenden“ und „Alle Server beenden“ (Statusdatei: `profiledProcess`). Die Profiler-Doku nennt den Fall mit Abhilfe.
