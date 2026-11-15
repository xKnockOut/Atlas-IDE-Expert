### Neu
- Prüfregeln für Lücken der Delphi-RTL, die Free Pascal nicht hat (#2309): `winapi-declaration-missing` meldet Namen, die Delphis `Winapi.Windows` nicht deklariert (`OpenThread`, `THREAD_SUSPEND_RESUME`, `PROCESS_QUERY_LIMITED_INFORMATION`, `ERROR_NOT_FOUND` …), samt der Deklaration zum Anlegen; `winapi-uses-missing` meldet `GetTickCount64`, `GetTickCount` und `MulDiv` ohne `Winapi.Windows` in uses (Korrektur: Unit aufnehmen); `stream-write-nativeint` warnt, wenn eine Ableitung von `TStream` nur `Write(…; Count: Longint)` überschreibt und die NativeInt-Überladung von Delphi 13 fehlt (unter Win64 sonst umgangen).

### Tests
- `argument-count-mismatch` mit `IOTADebuggerServices.AttachProcess` in der Form von Delphi 13 (#2309).
- `Tools/Check-TestCoverage.ps1` meldet jede Unit des Repositorys, die das Testprojekt erreicht und die nicht in `Tests/Atlas.Tests.dpr` steht, auch Server-Units aus `Application/Source` (wie F2613, #2309).
