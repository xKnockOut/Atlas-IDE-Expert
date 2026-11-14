### Experimentell
- Stichproben-Profiler (#2057, Teil 1a): Der Server misst ein laufendes Programm (Win32 und Win64, auch während die IDE es debuggt) über kurzes Anhalten der rechnenden Threads und löst die Stapel über die Map-Datei auf (Linker-Option „Map-Datei = Detailliert“). Befehle `atlas.server.profilerStart`, `…Status` und `…Stop`; die Bedienung im Plugin folgt.
