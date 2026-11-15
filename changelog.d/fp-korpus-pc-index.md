### Behoben
- Index: Gibt es eine Unit in mehreren Ordnern, gilt wie bei dcc die zuerst gefundene (Projektdatei mit `in`-Pfad der dpr vor den Suchpfaden, diese in ihrer Reihenfolge, Bibliothek zuletzt) statt der zuletzt gelesenen; wird sie gelöscht, übernimmt die nächste. Bisher meldete Atlas z. B. in JCL (`JclContainerIntf` in common und prototypes) tausende `unresolved-*`.
- Index: Werte anonymer Aufzählungen (`set of (ufImpl, ufDLL)`, Feld oder Variable `F: (mRead, mWrite)`) sind in der Unit und über uses bekannt; bisher `unresolved-identifier` (JVCL, CnVCL, Alcinoe, DMVC).
- `unresolved-identifier`: Die Intrinsics `GetDir`, `VarClear`, `VarArrayRedim` und `AddressOfReturnAddress` sind bekannt (stehen nicht in System.pas, dcc übersetzt sie auch ohne System.Variants).
