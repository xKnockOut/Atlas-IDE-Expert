### Neu
- Prüfregel `sleep-polling-loop` (#2626): meldet `while`- und `repeat`-Schleifen, die nur mit `Sleep` auf ein Feld, eine Eigenschaft oder eine globale Variable warten, und nennt den Ersatz (`TEvent.WaitFor`, `TThread.WaitFor`, `ITask.Wait`). Still, wo `thread-loop-without-terminated` oder `blocking-call-in-main-thread` die Schleife schon melden.
