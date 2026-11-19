### Behoben
- Umbenennen und die Korrektur von `naming-prefix` ändern einen gleichnamigen Typ nicht mehr mit: `WParam: WPARAM` wird `AWParam: WPARAM`, nicht `AWParam: AWParam`. Im Kopf einer Routine sehen Typangaben die Parameter nicht mehr, daher meldet `unresolved-type` einen Parameter, der wie sein (fehlender) Typ heißt (#1896).
