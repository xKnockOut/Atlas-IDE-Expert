### Neu
- KI-Assistenten debuggen in der laufenden IDE, Teil 1 (#1874): MCP-Werkzeuge `debug_start`, `debug_stop`, `set_breakpoint`, `remove_breakpoint`, `debug_continue`, `debug_step`, `debug_state` und `debug_evaluate` im Server. Sie prüfen die Argumente und legen Aufträge in `%LOCALAPPDATA%\Atlas\ide-debug\<pid>\` ab; bis das Plugin sie annimmt, melden sie „nicht angenommen“ mit Grund.
