unit BDLsp.Common.Rules.Catalog.Data;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog*.json.
// Nicht von Hand ändern.

interface

/// <summary>Englischer Grundkatalog als JSON.</summary>
function RuleCatalogBaseJson: string;
/// <summary>Übersetzung als JSON, '' für unbekannte Sprachen.</summary>
function RuleCatalogOverlayJson(const ALanguage: string): string;

implementation

uses
  System.SysUtils;

function RuleCatalogBaseJson: string;
begin
  Result :=
    '{' + #10 +
    '  "rules": [' + #10 +
    '    {' + #10 +
    '      "id": "syntax",' + #10 +
    '      "name": "Syntax error",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "description": "The parser could not read the source code.",' + #10 +
    '      "bad": "procedure Foo;\nbegin\n  if X then\nend;",' + #10 +
    '      "good": "procedure Foo;\nbegin\n  if X then\n    Bar;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unused-suppression",' + #10 +
    '      "name": "Unused suppression",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "description": "An lsp-ignore comment suppresses no finding and can be removed.",' + #10 +
    '      "bad": "// lsp-ignore: empty-except\nX := 1;",' + #10 +
    '      "good": "X := 1;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "bidi-control",' + #10 +
    '      "name": "Bidirectional control character",' + #10 +
    '      "category": "vulnerability",' + #10 +
    '      "severity": "error",' + #10 +
    '      "description": "Bidirectional control characters can make code display differently from how it compiles (Trojan Source).",' + #10 +
    '      "bad": "if IsAdmin then { U+202E } begin",' + #10 +
    '      "good": "if IsAdmin then begin"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "invisible-char",' + #10 +
    '      "name": "Invisible character",' + #10 +
    '      "category": "security-hotspot",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "Invisible or zero-width characters in the source code.",' + #10 +
    '      "bad": "Count{U+200B} := 0;",' + #10 +
    '      "good": "Count := 0;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "control-char",' + #10 +
    '      "name": "Control character",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "description": "NUL or control characters or invalid bytes (U+FFFD) in the source code.",' + #10 +
    '      "bad": "S := ''abc{U+0000}'';",' + #10 +
    '      "good": "S := ''abc'' + #0;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "confusable-identifier",' + #10 +
    '      "name": "Confusable identifier",' + #10 +
    '      "category": "security-hotspot",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "Identifiers that mix scripts or contain non-ASCII characters can be confused with others.",' + #10 +
    '      "bad": "var Pаssword: string; { Cyrillic ''а'' }",' + #10 +
    '      "good": "var Password: string;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unit-name-mismatch",' + #10 +
    '      "name": "Unit name does not match file name",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "The name in the unit line differs from the file name, so the compiler cannot find the unit through uses.",' + #10 +
    '      "bad": "{ Helpers.pas }\nunit Tools;",' + #10 +
    '      "good": "{ Helpers.pas }\nunit Helpers;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "forbidden-uses",' + #10 +
    '      "name": "Forbidden uses",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "error",' + #10 +
    '      "description": "A uses entry violates a layer rule configured under \"layers\" in delphi-lsp.json, e.g. *.Common.* must not use Vcl.*.",' + #10 +
    '      "bad": "unit App.Common.Model;\ninterface\nuses Vcl.Forms;",' + #10 +
    '      "good": "unit App.Common.Model;\ninterface\nuses System.Classes;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "lock-without-finally",' + #10 +
    '      "name": "Lock without try/finally",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "A lock (Enter, Acquire, BeginWrite, BeginRead, LockList, Lock, TMonitor.Enter) is not directly followed by try/finally releasing it. An exception leaves the lock held.",' + #10 +
    '      "bad": "FLock.Enter;\nDoWork;\nFLock.Leave;",' + #10 +
    '      "good": "FLock.Enter;\ntry\n  DoWork;\nfinally\n  FLock.Leave;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "thread-used-after-start",' + #10 +
    '      "name": "Thread used after start with FreeOnTerminate",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "A thread with FreeOnTerminate := True may free itself as soon as it is started; using the variable afterwards can access a freed object.",' + #10 +
    '      "bad": "T.FreeOnTerminate := True;\nT.Start;\nT.WaitFor;",' + #10 +
    '      "good": "T.FreeOnTerminate := True;\nT.Start;\nT := nil;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "synchronize-in-destructor",' + #10 +
    '      "name": "Synchronize in destructor",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "Synchronize in a destructor deadlocks when the main thread is waiting for the object to be freed.",' + #10 +
    '      "bad": "destructor TWorker.Destroy;\nbegin\n  Synchronize(Notify);\n  inherited;\nend;",' + #10 +
    '      "good": "destructor TWorker.Destroy;\nbegin\n  inherited;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "deprecated-suspend-resume",' + #10 +
    '      "name": "Deprecated TThread.Suspend/Resume",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "description": "TThread.Resume and Suspend are deprecated. Start a created thread with Start; wait with an event instead of Suspend.",' + #10 +
    '      "bad": "FWorker.Resume;",' + #10 +
    '      "good": "FWorker.Start;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "thread-free-without-waitfor",' + #10 +
    '      "name": "Thread freed without WaitFor",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "description": "A thread variable is freed without a prior WaitFor in the same routine. TThread.Destroy waits itself, but errors and the end of the thread go unnoticed. Experimental.",' + #10 +
    '      "bad": "FWorkerThread.Free;",' + #10 +
    '      "good": "FWorkerThread.Terminate;\nFWorkerThread.WaitFor;\nFWorkerThread.Free;"' + #10 +
    '    }' + #10 +
    '  ]' + #10 +
    '}' + #10 +
    '' + #10;
end;

function RuleCatalogOverlayJson(const ALanguage: string): string;
begin
  if SameText(ALanguage, 'de') then
    Exit(
    '{' + #10 +
    '  "rules": [' + #10 +
    '    {' + #10 +
    '      "id": "syntax",' + #10 +
    '      "name": "Syntaxfehler",' + #10 +
    '      "description": "Der Parser konnte den Quelltext nicht lesen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unused-suppression",' + #10 +
    '      "name": "Ungenutzte Unterdrückung",' + #10 +
    '      "description": "Ein lsp-ignore-Kommentar unterdrückt keinen Treffer und kann entfernt werden."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "bidi-control",' + #10 +
    '      "name": "Bidirektionales Steuerzeichen",' + #10 +
    '      "description": "Bidirektionale Steuerzeichen können Code anders anzeigen, als er kompiliert wird (Trojan Source)."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "invisible-char",' + #10 +
    '      "name": "Unsichtbares Zeichen",' + #10 +
    '      "description": "Unsichtbare oder Nullbreiten-Zeichen im Quelltext."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "control-char",' + #10 +
    '      "name": "Steuerzeichen",' + #10 +
    '      "description": "NUL- und Steuerzeichen oder ungültige Bytes (U+FFFD) im Quelltext."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "confusable-identifier",' + #10 +
    '      "name": "Verwechselbarer Bezeichner",' + #10 +
    '      "description": "Bezeichner mit Zeichen aus mehreren Schriften oder Nicht-ASCII-Zeichen sind mit anderen verwechselbar."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unit-name-mismatch",' + #10 +
    '      "name": "Unit-Name passt nicht zum Dateinamen",' + #10 +
    '      "description": "Der Name in der unit-Zeile weicht vom Dateinamen ab; der Compiler findet die Unit dann über uses nicht."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "forbidden-uses",' + #10 +
    '      "name": "Verbotene uses-Beziehung",' + #10 +
    '      "description": "Ein uses-Eintrag verletzt eine Schichtregel unter \"layers\" in delphi-lsp.json, z. B. darf *.Common.* nicht Vcl.* verwenden."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "lock-without-finally",' + #10 +
    '      "name": "Sperre ohne try/finally",' + #10 +
    '      "description": "Auf eine Sperre (Enter, Acquire, BeginWrite, BeginRead, LockList, Lock, TMonitor.Enter) folgt kein try/finally mit der Freigabe. Eine Ausnahme lässt die Sperre gesetzt."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "thread-used-after-start",' + #10 +
    '      "name": "Thread nach dem Start mit FreeOnTerminate benutzt",' + #10 +
    '      "description": "Ein Thread mit FreeOnTerminate := True kann sich gleich nach dem Start selbst freigeben; danach greift die Variable womöglich auf ein freigegebenes Objekt zu."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "synchronize-in-destructor",' + #10 +
    '      "name": "Synchronize im Destruktor",' + #10 +
    '      "description": "Synchronize im Destruktor verklemmt sich, wenn der Hauptthread auf die Freigabe wartet."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "deprecated-suspend-resume",' + #10 +
    '      "name": "Veraltetes TThread.Suspend/Resume",' + #10 +
    '      "description": "TThread.Resume und Suspend sind veraltet. Einen erzeugten Thread mit Start starten, statt Suspend mit einem Ereignis warten."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "thread-free-without-waitfor",' + #10 +
    '      "name": "Thread ohne WaitFor freigegeben",' + #10 +
    '      "description": "Eine Thread-Variable wird ohne vorheriges WaitFor in derselben Routine freigegeben. TThread.Destroy wartet zwar selbst, Fehler und Ende des Threads bleiben aber unbemerkt. Experi' + 'mentell."' + #10 +
    '    }' + #10 +
    '  ]' + #10 +
    '}' + #10 +
    '' + #10);
  Result := '';
end;

end.
