### Behoben
- Architekturansicht über eine große Projektgruppe: Der erste Aufruf brach nach 10 s ab (Watchdog), weil der Uses-Graph jede Unit einzeln aufnahm und wartende Units immer wieder neu verknüpfte. Er entsteht jetzt in einem Durchgang (Atlas-Gruppe: 1,5 s statt über 10 s).
