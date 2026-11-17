### Tests
- `TLeakMonitorTests.FreeOnOtherThreadIsNoLeak` scheiterte unter Volllast: Der Thread entstand vor der Messung und zählte zum Anfangsstand, der Monitor hörte deshalb nach wenigen ruhigen Messungen auf zu warten. Er entsteht jetzt innerhalb der Messung wie in einem echten Test.
