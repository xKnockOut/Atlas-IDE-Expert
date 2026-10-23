unit Atlas.Common.Rules.Catalog.Data;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog*.json.
// Nicht von Hand ändern.
// Die Beispiele "bad" zeigen absichtlich unsichere URLs (#1109).
// lsp-ignore-file: security-insecure-http

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
    '      "group": "compiler",' + #10 +
    '      "description": "The source code does not parse. The message says, like the compiler, what was expected and what was found (\"'';'' expected but ''end'' found (like E2029).\") and carries the compile' +
    'r code: missing '';'' (E2066 between statements, E2029 in declarations), '';'' before else (E2153), unterminated string (E2052) or comment with its start line (E2057), statements in the interface part (E2' +
    '050), identifier after a trailing dot (E2372), strict without private or protected (E2375), class before something other than a routine (E2357), try without except or finally (E2125), for without a va' +
    'riable (E2088). Checks on the finished tree: procedure with a result type (E2025), function declaration without one (E2023; the short form of an implementation is fine), value parameter without a type' +
    ' (E2067), initialised local variable (E2195) or several variables with one initial value (E2196), class, interface or object type in a var section (E2060, E2058) or local to a routine (E2061, E2059), ' +
    'label in the interface part (E2049) and goto to an undeclared label (E2031; a label of a surrounding routine is reported by label-misuse as E2093). After an unterminated string or comment the follow-u' +
    'p errors are dropped, as the compiler stops there. Inactive {$IFDEF} branches are not reported. Quick fixes: remove '';'' before else (safe, also on save), add '';'', close the string, close the comment a' +
    't the end of its first line.",' + #10 +
    '      "bad": "if Gueltig then\n  Speichern;\nelse\n  Verwerfen;",' + #10 +
    '      "good": "if Gueltig then\n  Speichern\nelse\n  Verwerfen;",' + #10 +
    '      "level": "A",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2023",' + #10 +
    '        "E2025",' + #10 +
    '        "E2029",' + #10 +
    '        "E2031",' + #10 +
    '        "E2049",' + #10 +
    '        "E2050",' + #10 +
    '        "E2052",' + #10 +
    '        "E2057",' + #10 +
    '        "E2058",' + #10 +
    '        "E2059",' + #10 +
    '        "E2060",' + #10 +
    '        "E2061",' + #10 +
    '        "E2066",' + #10 +
    '        "E2067",' + #10 +
    '        "E2088",' + #10 +
    '        "E2125",' + #10 +
    '        "E2153",' + #10 +
    '        "E2195",' + #10 +
    '        "E2196",' + #10 +
    '        "E2357",' + #10 +
    '        "E2372",' + #10 +
    '        "E2375"' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unused-suppression",' + #10 +
    '      "name": "Unused suppression",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "internal",' + #10 +
    '      "description": "An lsp-ignore comment suppresses no finding and can be removed.",' + #10 +
    '      "bad": "// lsp-ignore: empty-except\nX := 1;",' + #10 +
    '      "good": "X := 1;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unknown-rule-id",' + #10 +
    '      "name": "Unknown rule id",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "internal",' + #10 +
    '      "description": "An lsp-ignore comment names a rule id that does not exist, so it suppresses nothing. The message suggests the most similar known id (typo); such a comment is not also reported as' +
    ' unused-suppression.",' + #10 +
    '      "bad": "// lsp-ignore: empty-exept\ntry X; except end;",' + #10 +
    '      "good": "// lsp-ignore: empty-except\ntry X; except end;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unit-too-deep",' + #10 +
    '      "name": "Unit too deep to check",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "internal",' + #10 +
    '      "description": "The syntax tree of the unit is more than 100000 levels deep, so the rules do not run for it. Such trees only come from chains with as many terms, such as X := A - B - C - … The h' +
    'int marks the deepest point; splitting the chain into partial expressions makes the unit checkable again.",' + #10 +
    '      "bad": "X := A - B - C - D - E; // … 100000 terms",' + #10 +
    '      "good": "Part := A - B - C;\nX := Part - D - E;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "bidi-control",' + #10 +
    '      "name": "Bidirectional control character",' + #10 +
    '      "category": "vulnerability",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "security",' + #10 +
    '      "description": "Bidirectional control characters can make code display differently from how it compiles (Trojan Source); also in form files. Direction marks in RTL text only with low confidence.' +
    '",' + #10 +
    '      "bad": "if IsAdmin then { U+202E } begin",' + #10 +
    '      "good": "if IsAdmin then begin"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "invisible-char",' + #10 +
    '      "name": "Invisible character",' + #10 +
    '      "category": "security-hotspot",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "security",' + #10 +
    '      "description": "Invisible or zero-width characters in the source code and form files; medium confidence in strings and comments.",' + #10 +
    '      "bad": "Count{U+200B} := 0;",' + #10 +
    '      "good": "Count := 0;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "control-char",' + #10 +
    '      "name": "Control character",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "security",' + #10 +
    '      "description": "NUL or control characters or invalid UTF-8 bytes in the source code and the form file; invalid bytes with exact line and column.",' + #10 +
    '      "bad": "S := ''abc{U+0000}'';",' + #10 +
    '      "good": "S := ''abc'' + #0;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "confusable-identifier",' + #10 +
    '      "name": "Confusable identifier",' + #10 +
    '      "category": "security-hotspot",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "security",' + #10 +
    '      "description": "Identifiers that mix scripts or contain non-ASCII characters can be confused with others.",' + #10 +
    '      "bad": "var Pаssword: string; { Cyrillic ''а'' }",' + #10 +
    '      "good": "var Password: string;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "forbidden-uses",' + #10 +
    '      "name": "Forbidden uses",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "architecture",' + #10 +
    '      "description": "A uses entry violates a layer rule configured under \"layers\" in atlas.json, e.g. *.Common.* must not use Vcl.*.",' + #10 +
    '      "bad": "unit App.Common.Model;\ninterface\nuses Vcl.Forms;",' + #10 +
    '      "good": "unit App.Common.Model;\ninterface\nuses System.Classes;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "layers",' + #10 +
    '          "type": "json",' + #10 +
    '          "default": [],' + #10 +
    '          "description": "Layer rules: [{\"from\": glob, \"deny\": [globs], \"allow\": [globs]}]."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "architecture-role-import",' + #10 +
    '      "name": "Import violates the role matrix",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "architecture",' + #10 +
    '      "description": "A uses entry violates the import matrix of the role concept (output artefact, feature, role: Contract, Internals, Providers, Adapters, Composition, Hosting). Off by default; swit' +
    'ch it on in atlas.json with the option \"prefixes\". Approved exceptions go to \"allow\" as \"Source -> Target\" globs.",' + #10 +
    '      "bad": "unit Atlas.Common.Logging.Contract;\ninterface\nuses Atlas.Common.Logging.Providers.Logger;",' + #10 +
    '      "good": "unit Atlas.Common.Logging.Contract;\ninterface\nuses System.SysUtils;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "prefixes",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [],' + #10 +
    '          "description": "Prefixes of the output artefacts, e.g. \"Atlas.Common\"; without them the rule reports nothing."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "hostRoles",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [' + #10 +
    '            "Foundation",' + #10 +
    '            "Core",' + #10 +
    '            "Shell",' + #10 +
    '            "Adapters",' + #10 +
    '            "Platform"' + #10 +
    '          ],' + #10 +
    '          "description": "First name segments of host units without prefix."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "allow",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [],' + #10 +
    '          "description": "Approved exceptions \"Source -> Target\" (both globs)."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "architecture-contract-content",' + #10 +
    '      "name": "Class in a contract unit",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "architecture",' + #10 +
    '      "description": "A contract unit declares a class in its interface section. Contracts hold only records, interfaces, enumerations and exceptions. Off by default; switch it on in atlas.json with t' +
    'he option \"prefixes\". Approved exceptions go to \"allow\" as \"Unit.Type\" globs.",' + #10 +
    '      "bad": "unit App.Orders.Contract;\ninterface\ntype\n  TOrderList = class\n  end;",' + #10 +
    '      "good": "unit App.Orders.Contract;\ninterface\ntype\n  IOrderList = interface\n  end;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "prefixes",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [],' + #10 +
    '          "description": "Prefixes of the output artefacts, e.g. \"Atlas.Common\"."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "allow",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [],' + #10 +
    '          "description": "Approved exceptions \"Unit.Type\" as glob."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "thread-vcl-access",' + #10 +
    '      "name": "VCL access from a thread",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "threads",' + #10 +
    '      "description": "TThread.Execute, TThread.CreateAnonymousThread or TTask accesses the VCL (Application, Screen, ShowMessage, MessageDlg …) outside Synchronize or Queue. The VCL is not thread-safe' +
    '.",' + #10 +
    '      "bad": "procedure TWorker.Execute;\nbegin\n  Application.Title := ''Done'';\nend;",' + #10 +
    '      "good": "procedure TWorker.Execute;\nbegin\n  TThread.Queue(nil, procedure begin Application.Title := ''Done'' end);\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "lock-without-finally",' + #10 +
    '      "name": "Lock without try/finally",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "threads",' + #10 +
    '      "description": "A lock (TCriticalSection.Enter/Acquire, TMonitor.Enter, BeginRead/BeginWrite, TSpinLock.Enter, TMutex.Acquire, EnterCriticalSection or a pair from the lockPairs option) is not di' +
    'rectly followed by try/finally releasing it. An exception leaves the lock held.",' + #10 +
    '      "bad": "CS.Enter;\nDoWork;\nCS.Leave;",' + #10 +
    '      "good": "CS.Enter;\ntry\n  DoWork;\nfinally\n  CS.Leave;\nend;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "lockPairs",' + #10 +
    '          "type": "json",' + #10 +
    '          "default": [],' + #10 +
    '          "description": "Additional lock pairs as [[\"Lock\", \"Release\"]]."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "thread-use-after-free-on-terminate",' + #10 +
    '      "name": "Thread used after start with FreeOnTerminate",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "threads",' + #10 +
    '      "description": "A thread with FreeOnTerminate := True may free itself as soon as it is started; using the variable afterwards can access a freed object.",' + #10 +
    '      "bad": "T.FreeOnTerminate := True;\nT.Start;\nLog(T.ThreadID);",' + #10 +
    '      "good": "Log(T.ThreadID);\nT.FreeOnTerminate := True;\nT.Start;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "thread-free-with-free-on-terminate",' + #10 +
    '      "name": "Free on a thread with FreeOnTerminate",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "threads",' + #10 +
    '      "description": "Free on a thread with FreeOnTerminate := True frees it twice.",' + #10 +
    '      "bad": "T.FreeOnTerminate := True;\nT.Start;\nT.Free;",' + #10 +
    '      "good": "T.FreeOnTerminate := True;\nT.Start;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "synchronize-in-destructor",' + #10 +
    '      "name": "Synchronize in thread destructor",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "threads",' + #10 +
    '      "description": "Synchronize in the destructor of a TThread descendant (or a method it calls) deadlocks: the main thread waits in WaitFor while the thread waits for Synchronize.",' + #10 +
    '      "bad": "destructor TWorker.Destroy;\nbegin\n  Synchronize(Notify);\n  inherited;\nend;",' + #10 +
    '      "good": "destructor TWorker.Destroy;\nbegin\n  inherited;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "thread-resume-suspend",' + #10 +
    '      "name": "Deprecated TThread.Resume/Suspend",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "threads",' + #10 +
    '      "description": "TThread.Resume and Suspend are deprecated. Start a created thread with Start; Suspend has no safe replacement, wait with an event instead.",' + #10 +
    '      "bad": "FWorker.Resume;",' + #10 +
    '      "good": "FWorker.Start;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "result-not-set",' + #10 +
    '      "name": "Function result possibly not set",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "A path through the function ends without assigning Result. The caller then reads an undefined value.",' + #10 +
    '      "bad": "function Find: Integer;\nbegin\n  if Ok then\n    Result := 1;\nend;",' + #10 +
    '      "good": "function Find: Integer;\nbegin\n  Result := 0;\n  if Ok then\n    Result := 1;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "possibly-uninitialized",' + #10 +
    '      "name": "Variable possibly uninitialized",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "A local variable is read on a path where it was never assigned.",' + #10 +
    '      "bad": "var I: Integer;\nbegin\n  if Ok then\n    I := 1;\n  Writeln(I);\nend;",' + #10 +
    '      "good": "var I: Integer;\nbegin\n  I := 0;\n  if Ok then\n    I := 1;\n  Writeln(I);\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unreachable-code",' + #10 +
    '      "name": "Unreachable code",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "A statement after Exit, raise, Abort, Halt, Break, Continue or goto is never executed. Usually a leftover or a misplaced jump. Only the first statement of an unreachable section ' +
    'is reported.",' + #10 +
    '      "bad": "procedure Save;\nbegin\n  Exit;\n  Store;\nend;",' + #10 +
    '      "good": "procedure Save;\nbegin\n  if not Ready then\n    Exit;\n  Store;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unused-local",' + #10 +
    '      "name": "Unused local variable",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "A local variable is declared but never used. Like compiler hint H2164, but while typing.",' + #10 +
    '      "bad": "procedure Foo;\nvar\n  I, Count: Integer;\nbegin\n  I := 1;\n  Bar(I);\nend;",' + #10 +
    '      "good": "procedure Foo;\nvar\n  I: Integer;\nbegin\n  I := 1;\n  Bar(I);\nend;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "ignore",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [],' + #10 +
    '          "description": "Name patterns that are never reported (* and ?)."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unused-parameter",' + #10 +
    '      "name": "Unused parameter",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "A parameter is never used in the routine body. Overridden and virtual methods, event handlers, published methods, interface implementations and callbacks are exempt.",' + #10 +
    '      "bad": "function Twice(A, B: Integer): Integer;\nbegin\n  Result := 2 * A;\nend;",' + #10 +
    '      "good": "function Twice(A: Integer): Integer;\nbegin\n  Result := 2 * A;\nend;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "ignore",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [],' + #10 +
    '          "description": "Name patterns that are never reported (* and ?)."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unused-assignment",' + #10 +
    '      "name": "Value assigned is never used",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "A value assigned to a local variable is overwritten or the routine ends before it is read. Like compiler hint H2077. Variables of an interface type are exempt: assigning them hol' +
    'ds or releases a reference (scope guards, Writer := nil).",' + #10 +
    '      "bad": "procedure Foo;\nvar\n  I: Integer;\nbegin\n  I := 0;\n  I := Calc;\n  Bar(I);\nend;",' + #10 +
    '      "good": "procedure Foo;\nvar\n  I: Integer;\nbegin\n  I := Calc;\n  Bar(I);\nend;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "ignore",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [],' + #10 +
    '          "description": "Name patterns that are never reported (* and ?)."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "duplicate-assignment",' + #10 +
    '      "name": "Field or property assigned twice",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "The same field or property (Panel.Left, Self.FWert, P^.X) gets a value twice in a row without being read or anything being called in between; usually the second line should have ' +
    'a different target (Left/Top). Between the two only assignments to other objects with values that call nothing and do not name the target may stand; the second value must not read the target. Local va' +
    'riables are covered by unused-assignment, targets with an index or a call do not count. Silent for a False/True toggle (it often triggers something, like Active), for a second assignment compiled only' +
    ' under an additional condition ({$IFDEF DEBUG}), for different branches of the same {$IFDEF} and for properties from allowProperties. If the counterpart (Left/Top, Width/Height …) is missing from the ' +
    'sequence, the message suggests it. High confidence. No quick fix; jump to the first assignment.",' + #10 +
    '      "bad": "Panel.Left := 8;\nPanel.Left := 40;\nPanel.Width := 200;",' + #10 +
    '      "good": "Panel.Left := 8;\nPanel.Top := 40;\nPanel.Width := 200;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "allowProperties",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [' + #10 +
    '            "Visible",' + #10 +
    '            "Enabled"' + #10 +
    '          ],' + #10 +
    '          "description": "Properties where setting twice may be intended (setter with side effects), patterns with * and ?."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "declared-not-implemented",' + #10 +
    '      "name": "Declared but not implemented",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "A method is declared in a class, record or object but has no body in the implementation section. The compiler reports this only when compiling (E2065). A body of the same name wi' +
    'th a different header is reported by signature-mismatch instead.",' + #10 +
    '      "bad": "type\n  TFoo = class\n    procedure Run;\n  end;\n\nimplementation\n\nend.",' + #10 +
    '      "good": "type\n  TFoo = class\n    procedure Run;\n  end;\n\nimplementation\n\nprocedure TFoo.Run;\nbegin\nend;\n\nend."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "implemented-not-declared",' + #10 +
    '      "name": "Implemented but not declared",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "A method body TFoo.Bar has no declaration of that name in the type. A declaration of the same name with a different header is reported by signature-mismatch instead.",' + #10 +
    '      "bad": "type\n  TFoo = class\n  end;\n\nimplementation\n\nprocedure TFoo.Run;\nbegin\nend;",' + #10 +
    '      "good": "type\n  TFoo = class\n  private\n    procedure Run;\n  end;\n\nimplementation\n\nprocedure TFoo.Run;\nbegin\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "destroy-without-override",' + #10 +
    '      "name": "Destroy without override",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "A destructor Destroy is declared without override. Free calls TObject.Destroy, so this destructor never runs.",' + #10 +
    '      "bad": "type\n  TFoo = class\n    destructor Destroy;\n  end;",' + #10 +
    '      "good": "type\n  TFoo = class\n    destructor Destroy; override;\n  end;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "setter-recursion",' + #10 +
    '      "name": "Setter or getter calls itself",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "A setter assigns to its own property (Name := Value in SetName) or a getter reads it (Result := Name in GetName). The accessor calls itself endlessly and ends in a stack overflow' +
    ' at run time; the compiler stays silent. Quick fix: use the field instead (the field from the property declaration, otherwise F plus the name, if the class has it). Formerly recursive-property-accesso' +
    'r; settings and suppressions with the old ID still apply.",' + #10 +
    '      "bad": "procedure TKunde.SetName(const Value: string);\nbegin\n  if Name <> Value then\n    Name := Value;\nend;",' + #10 +
    '      "good": "procedure TKunde.SetName(const Value: string);\nbegin\n  if FName <> Value then\n    FName := Value;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-create-without-override",' + #10 +
    '      "name": "Component constructor without override",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "components",' + #10 +
    '      "description": "A TComponent descendant declares constructor Create(AOwner: TComponent) without override. Components created from a form file are built through the virtual constructor and skip t' +
    'his one.",' + #10 +
    '      "bad": "type\n  TMyPanel = class(TCustomPanel)\n    constructor Create(AOwner: TComponent);\n  end;",' + #10 +
    '      "good": "type\n  TMyPanel = class(TCustomPanel)\n    constructor Create(AOwner: TComponent); override;\n  end;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "hides-virtual",' + #10 +
    '      "name": "Method hides virtual method",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "A method has the same name as a virtual method of an ancestor but neither overrides nor reintroduces it (compiler warning W1010).",' + #10 +
    '      "bad": "type\n  TBase = class\n    procedure Run; virtual;\n  end;\n  TFoo = class(TBase)\n    procedure Run;\n  end;",' + #10 +
    '      "good": "type\n  TBase = class\n    procedure Run; virtual;\n  end;\n  TFoo = class(TBase)\n    procedure Run; override;\n  end;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "virtual-instead-of-override",' + #10 +
    '      "name": "virtual instead of override",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "A descendant declares a method virtual although the ancestor already has a virtual method with the same signature; this starts a new chain instead of overriding.",' + #10 +
    '      "bad": "type\n  TFoo = class(TBase)\n    procedure Run; virtual;\n  end;",' + #10 +
    '      "good": "type\n  TFoo = class(TBase)\n    procedure Run; override;\n  end;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "captured-loop-variable",' + #10 +
    '      "name": "Captured loop variable",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "An anonymous method passed to a deferred API (TThread.Queue, TTask.Run, ...) captures a variable that changes before it runs, such as a for-in loop variable. Delphi captures the ' +
    'variable, not its value.",' + #10 +
    '      "bad": "for S in List do\n  TThread.Queue(nil, procedure begin Memo1.Lines.Add(S); end);",' + #10 +
    '      "good": "function CaptureS(const AValue: string): TProc;\nbegin\n  Result := procedure begin Memo1.Lines.Add(AValue); end;\nend;\n...\nfor S in List do\n  TThread.Queue(nil, CaptureS(S));",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "deferredApis",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [],' + #10 +
    '          "description": "Additional deferred APIs (besides TThread.Queue, TTask.Run and others)."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-missing-inherited",' + #10 +
    '      "name": "Component method without inherited",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "components",' + #10 +
    '      "description": "An overridden Loaded, CreateParams, CreateWnd, Notification, SetParent, Destroy or Paint of a component does not call inherited, so the VCL skips its own work there. For Paint th' +
    'e confidence is low, because TCustomControl.Paint only draws the design-time frame.",' + #10 +
    '      "bad": "procedure TMyControl.Loaded;\nbegin\n  UpdateLayout;\nend;",' + #10 +
    '      "good": "procedure TMyControl.Loaded;\nbegin\n  inherited;\n  UpdateLayout;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-default-mismatch",' + #10 +
    '      "name": "default does not match constructor",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "components",' + #10 +
    '      "description": "A property declares a default value, but the constructor sets its field to a different literal. The streaming system does not store values equal to default, so the property is lo' +
    'aded wrongly from the DFM.",' + #10 +
    '      "bad": "property Size: Integer read FSize write FSize default 5;\n...\nFSize := 10;",' + #10 +
    '      "good": "property Size: Integer read FSize write FSize default 10;\n...\nFSize := 10;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-missing-free-notification",' + #10 +
    '      "name": "Component reference without FreeNotification",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "components",' + #10 +
    '      "description": "A component property refers to another component, but its setter does not call FreeNotification. When the other component is freed, a dangling pointer remains. Subcomponents crea' +
    'ted in the constructor are ignored.",' + #10 +
    '      "bad": "procedure TMyControl.SetLink(const Value: TControl);\nbegin\n  FLink := Value;\nend;",' + #10 +
    '      "good": "procedure TMyControl.SetLink(const Value: TControl);\nbegin\n  FLink := Value;\n  if Value <> nil then Value.FreeNotification(Self);\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-setter-without-invalidate",' + #10 +
    '      "name": "Setter without Invalidate",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "components",' + #10 +
    '      "description": "A property setter changes a field that Paint reads, but does not call Invalidate (or Repaint, Refresh, Changed). The control keeps showing the old state.",' + #10 +
    '      "bad": "procedure TMyControl.SetColor(const Value: TColor);\nbegin\n  FColor := Value;\nend;",' + #10 +
    '      "good": "procedure TMyControl.SetColor(const Value: TColor);\nbegin\n  FColor := Value;\n  Invalidate;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-fixed-pixels",' + #10 +
    '      "name": "Fixed pixel values",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "components",' + #10 +
    '      "description": "Paint or Resize uses fixed pixel values that are too small above 96 dpi. Values passed through ScaleValue or MulDiv, 0, 1 and -1, and factors of multiplications and divisions are' +
    ' not reported.",' + #10 +
    '      "bad": "Canvas.FillRect(Rect(0, 0, 16, 16));",' + #10 +
    '      "good": "Canvas.FillRect(Rect(0, 0, ScaleValue(16), ScaleValue(16)));"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-hardcoded-color",' + #10 +
    '      "name": "Hardcoded color in Paint",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "components",' + #10 +
    '      "description": "Paint uses an RGB literal, a $00BBGGRR constant or a TColor cast. Such colors ignore VCL styles; system colors like clBtnFace are fine.",' + #10 +
    '      "bad": "Canvas.Brush.Color := $00FF8000;",' + #10 +
    '      "good": "Canvas.Brush.Color := StyleServices.GetSystemColor(clHighlight);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "form-field-without-object",' + #10 +
    '      "name": "Form field without object",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "forms",' + #10 +
    '      "description": "A published component field of the form class has no object in the .dfm/.fmx next to the unit. After loading, the field stays nil. Fields outside published are not checked.",' + #10 +
    '      "bad": "Edit1: TEdit;  // object Edit1 was deleted from the form",' + #10 +
    '      "good": "// remove the field or restore the object"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "form-object-without-field",' + #10 +
    '      "name": "Form object without field",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "forms",' + #10 +
    '      "description": "An object of the form file has no field in the form class. Inherited objects, objects inside inline frames, unnamed components and collection items are skipped. The fix adds the ' +
    'field.",' + #10 +
    '      "bad": "object Button2: TButton  // no Button2 in TForm1",' + #10 +
    '      "good": "Button2: TButton;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "form-field-type-mismatch",' + #10 +
    '      "name": "Form field type differs from object",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "forms",' + #10 +
    '      "description": "The field type differs from the class of the object in the form file. Without source for the class in the form file, nothing is compared. The fix changes the field type.",' + #10 +
    '      "bad": "Edit1: TEdit;  // object Edit1: TMaskEdit",' + #10 +
    '      "good": "Edit1: TMaskEdit;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "security-command-injection",' + #10 +
    '      "name": "Command injection",' + #10 +
    '      "category": "vulnerability",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "security",' + #10 +
    '      "description": "ShellExecute, ShellExecuteEx, CreateProcess or WinExec receives an argument built with +, Format or Concat from non-constant values. Input could inject further commands. Without ' +
    'data flow analysis only this simple pattern is found (medium confidence).",' + #10 +
    '      "bad": "ShellExecute(0, ''open'', PChar(''cmd /c '' + Edit1.Text), nil, nil, SW_SHOW);",' + #10 +
    '      "good": "ShellExecute(0, ''open'', ''tool.exe'', PChar(QuotedArgument), nil, SW_SHOW);  // validated"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "security-path-traversal",' + #10 +
    '      "name": "Path traversal",' + #10 +
    '      "category": "vulnerability",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "security",' + #10 +
    '      "description": "A file access (TFileStream.Create, LoadFromFile, AssignFile, TFile.*) uses a path from input data (Text, ParamStr, Request) without TPath.GetFullPath check. Experimental until da' +
    'ta flow analysis is available.",' + #10 +
    '      "bad": "List.LoadFromFile(''C:\\Data\\'' + Edit1.Text);",' + #10 +
    '      "good": "Path := TPath.GetFullPath(TPath.Combine(Root, Edit1.Text));  // then check it starts with Root"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "security-weak-crypto",' + #10 +
    '      "name": "Weak cryptography",' + #10 +
    '      "category": "security-hotspot",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "security",' + #10 +
    '      "description": "MD5, SHA-1, DES or RC4 is used. For checksums this is fine; for passwords and signatures it is not. Low confidence, medium when the statement mentions a password, secret or signa' +
    'ture.",' + #10 +
    '      "bad": "Stored := THashSHA1.GetHashString(PasswordText);",' + #10 +
    '      "good": "Stored := THashSHA2.GetHashString(Salt + PasswordText);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "security-tls-verification-disabled",' + #10 +
    '      "name": "TLS certificate check disabled",' + #10 +
    '      "category": "vulnerability",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "security",' + #10 +
    '      "description": "Indy SSLOptions.VerifyMode := [], an OnVerifyPeer handler that always returns True, or a ValidateServerCertificate handler that sets Accepted := True without a check.",' + #10 +
    '      "bad": "IdSSL.SSLOptions.VerifyMode := [];",' + #10 +
    '      "good": "IdSSL.SSLOptions.VerifyMode := [sslvrfPeer];"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "security-insecure-http",' + #10 +
    '      "name": "Unencrypted http:// URL",' + #10 +
    '      "category": "security-hotspot",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "security",' + #10 +
    '      "description": "A string contains an http:// URL. XML namespaces and schema URIs, comments and localhost, 127.0.0.1 and [::1] are skipped. The fix replaces http:// with https://.",' + #10 +
    '      "bad": "Client.Get(''http://api.example.com/data'');",' + #10 +
    '      "good": "Client.Get(''https://api.example.com/data'');"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "security-insecure-random",' + #10 +
    '      "name": "Random for security values",' + #10 +
    '      "category": "security-hotspot",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "security",' + #10 +
    '      "description": "Random is assigned to a token, password, salt, nonce or key. Random is predictable; use a cryptographic random generator. Missing Randomize is a separate topic (#153).",' + #10 +
    '      "bad": "Token := IntToStr(Random(MaxInt));",' + #10 +
    '      "good": "Token := TNetEncoding.Base64URL.EncodeBytesToString(CryptoRandomBytes(32));"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dfm-circular-datasource",' + #10 +
    '      "name": "Circular master-detail or data source link",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "forms",' + #10 +
    '      "description": "MasterSource/DataSource links in the form file form a cycle (tblA → dsB → tblB → dsA → tblA). Opening the datasets recurses or never shows consistent data.",' + #10 +
    '      "bad": "tblA.MasterSource = dsB; tblB.MasterSource = dsA",' + #10 +
    '      "good": "tblB.MasterSource = dsA  // tblA has no master"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dfm-master-without-fields",' + #10 +
    '      "name": "Master-detail without MasterFields",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "forms",' + #10 +
    '      "description": "A dataset has MasterSource but no MasterFields. The detail is not filtered and shows all records.",' + #10 +
    '      "bad": "MasterSource = dsKunden",' + #10 +
    '      "good": "MasterSource = dsKunden; MasterFields = ''KundenID''"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dfm-required-field-without-control",' + #10 +
    '      "name": "Required field without visible input control",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "forms",' + #10 +
    '      "description": "A persistent field with Required = True is bound to no visible data-aware control (a grid without DataField counts for all fields). The user cannot fill it and posting fails.",' + #10 +
    '      "bad": "tblKundenName: Required = True, no TDBEdit for Name",' + #10 +
    '      "good": "edName: TDBEdit; DataSource = dsKunden; DataField = ''Name''"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dfm-control-field-type-mismatch",' + #10 +
    '      "name": "Data-aware control does not fit the field type",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "forms",' + #10 +
    '      "description": "The control does not suit the persistent field, e.g. TDBEdit on a TBooleanField or blob field, TDBImage on a non-graphic field.",' + #10 +
    '      "bad": "edAktiv: TDBEdit; DataField = ''Aktiv''  // TBooleanField",' + #10 +
    '      "good": "cbAktiv: TDBCheckBox; DataField = ''Aktiv''"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dfm-duplicate-binding",' + #10 +
    '      "name": "Two controls bound to the same field",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "forms",' + #10 +
    '      "description": "Two input controls use the same DataSource and DataField. Usually a copy-and-paste error. Display controls (TDBText, TDBImage) are ignored.",' + #10 +
    '      "bad": "ed1, ed2: DataSource = dsA; DataField = ''Name''",' + #10 +
    '      "good": "ed1: DataField = ''Name''; ed2: DataField = ''Vorname''"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dfm-property",' + #10 +
    '      "name": "Component property violates a property rule",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "forms",' + #10 +
    '      "description": "A component property in the form file does not meet a rule from dfmPropertyRules in atlas.json (class, property, condition, value). A property that is not stored counts with its ' +
    'default value; objects of the ancestor form are only reported where this form sets the value itself. The quick fix sets the value in the form file (fix: auto also with source.fixAll); the command \"Ap' +
    'ply property rules\" corrects one form, the project or the group with a preview.",' + #10 +
    '      "bad": "// dfmPropertyRules: TLabel.Transparent = True\nobject Label1: TLabel\n  Caption = ''Name''\nend",' + #10 +
    '      "good": "object Label1: TLabel\n  Caption = ''Name''\n  Transparent = True\nend"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "foreign-form-control-access",' + #10 +
    '      "name": "Access to controls of another form",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "forms",' + #10 +
    '      "description": "Code accesses a field of a form or frame from another unit through its global variable (Form2.Edit1.Text). This couples the units tightly; use a method or property of the form.",' + #10 +
    '      "bad": "Form2.Edit1.Text := ''x'';",' + #10 +
    '      "good": "Form2.Kundenname := ''x'';"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "security-sql-injection",' + #10 +
    '      "name": "SQL text built from values (SQL injection)",' + #10 +
    '      "category": "vulnerability",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "security",' + #10 +
    '      "description": "SQL.Text, SQL.Add, CommandText, ExecSQL or Open receives text built with + or Format from non-constant values. User input could inject SQL. Use parameters (:Name, ParamByName). C' +
    'onstants, resourcestrings, IntToStr and QuotedStr are not reported; user input (TEdit.Text, TMemo.Lines) raises the confidence to high.",' + #10 +
    '      "bad": "Q.SQL.Text := ''select * from K where N = '''''' + Edit1.Text + '''''''';",' + #10 +
    '      "good": "Q.SQL.Text := ''select * from K where N = :N'';\nQ.ParamByName(''N'').AsString := Edit1.Text;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "slash-command",' + #10 +
    '      "name": "Quick command not executed",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "internal",' + #10 +
    '      "description": "A line starting with /name was not executed and stays in the code: the command is unknown, switched off (slashCommands.disabled) or does not fit at this place. The message names ' +
    'the reason. \"/ignore rule\" is also reported when that rule finds nothing in the line below.",' + #10 +
    '      "bad": "/gibtsnicht X",' + #10 +
    '      "good": "/uses System.Classes"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "empty-except",' + #10 +
    '      "name": "Empty except block",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "exceptions",' + #10 +
    '      "description": "An except block without statements swallows every exception. A block that contains only a comment counts as deliberate and is not reported.",' + #10 +
    '      "bad": "try\n  Save;\nexcept\nend;",' + #10 +
    '      "good": "try\n  Save;\nexcept\n  on E: EInOutError do\n    Log(E.Message);\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "interface-guid",' + #10 +
    '      "name": "Interface without GUID",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "An interface declares no GUID. Supports, as and QueryInterface need one. The confidence is high when the interface is used with them in the same file, otherwise low. The quick fi' +
    'x inserts a new GUID.",' + #10 +
    '      "bad": "type\n  ISaver = interface\n    procedure Save;\n  end;",' + #10 +
    '      "good": "type\n  ISaver = interface\n    [''{6C1D2A57-0E3B-4F8A-9B2D-5A7E4C3F1D08}'']\n    procedure Save;\n  end;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "duplicate-interface-guid",' + #10 +
    '      "name": "Two interfaces with the same GUID",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "Two interfaces in the file declare the same GUID, usually after copying a declaration. Supports and as then mix them up. The quick fix generates a new GUID.",' + #10 +
    '      "bad": "ILoader = interface\n  [''{6C1D2A57-0E3B-4F8A-9B2D-5A7E4C3F1D08}'']\nend;\nISaver = interface\n  [''{6C1D2A57-0E3B-4F8A-9B2D-5A7E4C3F1D08}'']\nend;",' + #10 +
    '      "good": "ILoader = interface\n  [''{6C1D2A57-0E3B-4F8A-9B2D-5A7E4C3F1D08}'']\nend;\nISaver = interface\n  [''{0B9E4F21-7C6D-4A3E-8F15-2D9C7B6A4E31}'']\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "file-header",' + #10 +
    '      "name": "File header missing or different",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "The file does not start with the header from the rule option \"template\". Off by default; switch it on in atlas.json with a template. The quick fix inserts the header.",' + #10 +
    '      "bad": "unit Tools;",' + #10 +
    '      "good": "// Copyright (c) Example GmbH\nunit Tools;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "template",' + #10 +
    '          "type": "string",' + #10 +
    '          "default": "",' + #10 +
    '          "description": "Expected file header; placeholders as documented."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "hardcoded-string",' + #10 +
    '      "name": "Text in code instead of resourcestring",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "A string literal with words for people stands in a statement. Move it to a resourcestring so it can be translated. Off by default, low confidence.",' + #10 +
    '      "bad": "ShowMessage(''File not found'');",' + #10 +
    '      "good": "resourcestring\n  SFileNotFound = ''File not found'';\n...\nShowMessage(SFileNotFound);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "self-assignment",' + #10 +
    '      "name": "Assignment to itself",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "A variable, field or property is assigned to itself. Usually a different value was meant, for example a parameter or another field. If a parameter or local variable hides a field' +
    ' of the same name (Name := Name), Atlas offers Self.Name := Name as the fix.",' + #10 +
    '      "bad": "FName := FName;",' + #10 +
    '      "good": "FName := AName;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "for-high-to-low",' + #10 +
    '      "name": "for loop counts down with to",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "The loop starts at the upper bound (High, Count - 1) and ends at the lower one, but uses to. It never runs; downto was meant. Also reports loops with constant bounds that never r' +
    'un, such as for I := 10 to 1, with signed, hexadecimal or character literals (like H2135). Equal bounds, expressions, named constants and ascending bounds stay silent. Quick fix: replace to with downt' +
    'o.",' + #10 +
    '      "bad": "for I := 10 to 1 do\n  Countdown(I);",' + #10 +
    '      "good": "for I := 10 downto 1 do\n  Countdown(I);",' + #10 +
    '      "level": "A",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "H2135"' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "exception-not-raised",' + #10 +
    '      "name": "Exception created but not raised",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "An exception object is created as a statement on its own. Without raise nothing happens and the object leaks.",' + #10 +
    '      "bad": "if X = nil then\n  EArgumentException.Create(''X missing'');",' + #10 +
    '      "good": "if X = nil then\n  raise EArgumentException.Create(''X missing'');"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "assert-side-effect",' + #10 +
    '      "name": "Assert with side effect",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "The argument of Assert changes data (Inc, Dec, a Try… function with an out parameter or a method from the option mutatingMethods). With {$C-} the compiler removes the whole call ' +
    'including the side effect.",' + #10 +
    '      "bad": "Assert(List.Remove(X) >= 0);",' + #10 +
    '      "good": "Index := List.Remove(X);\nAssert(Index >= 0);",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "mutatingMethods",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [' + #10 +
    '            "Add",' + #10 +
    '            "Delete",' + #10 +
    '            "Remove",' + #10 +
    '            "Extract",' + #10 +
    '            "Clear",' + #10 +
    '            "Insert"' + #10 +
    '          ],' + #10 +
    '          "description": "Methods that change their object."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "ifthen-side-effect",' + #10 +
    '      "name": "IfThen evaluates both branches",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "IfThen is a function: both branches are evaluated before the call. A nil access or a function call in the branch that is not chosen still happens. High confidence when a branch d' +
    'ereferences a name checked in the condition, medium for a function call.",' + #10 +
    '      "bad": "S := IfThen(Assigned(X), X.Name, '''');",' + #10 +
    '      "good": "if Assigned(X) then S := X.Name else S := '''';"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "random-without-randomize",' + #10 +
    '      "name": "Random without Randomize",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "robustness",' + #10 +
    '      "description": "Random is used, but the unit never calls Randomize, so every start yields the same sequence. Randomize often sits in the .dpr, so the rule is off by default and has low confidenc' +
    'e.",' + #10 +
    '      "bad": "Dice := Random(6) + 1;",' + #10 +
    '      "good": "Randomize; // once at program start\n...\nDice := Random(6) + 1;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "int32-mul-overflow",' + #10 +
    '      "name": "Int32 multiplication assigned to Int64",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "Both operands have at most 32 bits, so the product is computed in 32 bits and overflows before it is assigned to the Int64 variable. Cast one operand to Int64.",' + #10 +
    '      "bad": "Total := Width * Height; // Total: Int64; Width, Height: Integer",' + #10 +
    '      "good": "Total := Int64(Width) * Height;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "sizeof-pointer",' + #10 +
    '      "name": "SizeOf of a pointer in Move or FillChar",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "SizeOf of a pointer, string or dynamic array is the size of the reference (4 or 8 bytes), not of the data. Move and FillChar then copy or clear too little.",' + #10 +
    '      "bad": "FillChar(Buffer[0], SizeOf(Buffer), 0); // Buffer: TBytes",' + #10 +
    '      "good": "FillChar(Buffer[0], Length(Buffer) * SizeOf(Buffer[0]), 0);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "char-to-pchar",' + #10 +
    '      "name": "Char cast to PChar",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "PChar(C) with a Char variable turns the character code into an address. A string was meant.",' + #10 +
    '      "bad": "ShowMessage(PChar(C)); // C: Char",' + #10 +
    '      "good": "ShowMessage(PChar(string(C)));"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "float-equality",' + #10 +
    '      "name": "Floating-point comparison with = or <>",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "Floating-point values are rarely exactly equal after calculations. Compare with SameValue from System.Math and a tolerance. Comparisons with 0 are not reported.",' + #10 +
    '      "bad": "if Total = Expected then",' + #10 +
    '      "good": "if SameValue(Total, Expected) then"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "constructor-on-instance",' + #10 +
    '      "name": "Constructor called on an instance",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "Create is called on a variable instead of the class. That does not create a new object; with an unassigned variable it crashes. Class references (class of …) are not reported.",' + #10 +
    '      "bad": "List.Create; // List: TStringList",' + #10 +
    '      "good": "List := TStringList.Create;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "format-without-settings",' + #10 +
    '      "name": "Formatting depends on the locale",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "robustness",' + #10 +
    '      "description": "Format with %f, %n, %m, %g or %e and functions like FloatToStr, StrToFloat or DateToStr without a TFormatSettings parameter use the user''s locale (decimal separator, date format)' +
    '. For files, protocols and logs pass fixed TFormatSettings. Format(''%d'', …) is not reported, nor are FormatDateTime and FormatFloat with a fixed picture without separators (: / . ,), such as ''yyyy\"-\' +
    '"mm\"-\"dd'' or ''ddddd t''.",' + #10 +
    '      "bad": "Line := Format(''%.2f'', [Amount]);",' + #10 +
    '      "good": "Line := Format(''%.2f'', [Amount], TFormatSettings.Invariant);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "generic-exception-raised",' + #10 +
    '      "name": "Generic exception raised",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "exceptions",' + #10 +
    '      "description": "Raising the base class Exception prevents callers from handling the error specifically. Declare a dedicated exception class.",' + #10 +
    '      "bad": "raise Exception.Create(''Customer missing'');",' + #10 +
    '      "good": "raise ECustomerMissing.Create(''Customer missing'');"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "catch-all-without-raise",' + #10 +
    '      "name": "Catch-all handler without re-raise",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "exceptions",' + #10 +
    '      "description": "A handler for Exception that neither re-raises nor ends the program swallows every error, including programming errors. Off by default; intended for library code.",' + #10 +
    '      "bad": "except\n  on E: Exception do\n    Log(E.Message);\nend;",' + #10 +
    '      "good": "except\n  on E: Exception do\n  begin\n    Log(E.Message);\n    raise;\n  end;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "exception-freed",' + #10 +
    '      "name": "Exception object freed manually",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "exceptions",' + #10 +
    '      "description": "The RTL frees an exception object after its handler or after raise. Freeing it manually causes a double free.",' + #10 +
    '      "bad": "on E: Exception do\n  E.Free;",' + #10 +
    '      "good": "on E: Exception do\n  Log(E.Message);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "string-concat-in-loop",' + #10 +
    '      "name": "String concatenation in a loop",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "performance",' + #10 +
    '      "description": "A string variable is extended step by step inside a loop. Delphi usually grows strings in place, so this is reported only with low confidence and is off by default; for many iter' +
    'ations TStringBuilder is faster.",' + #10 +
    '      "bad": "for I := 1 to 10000 do\n  S := S + IntToStr(I);",' + #10 +
    '      "good": "Builder := TStringBuilder.Create;\ntry\n  for I := 1 to 10000 do\n    Builder.Append(I);\n  S := Builder.ToString;\nfinally\n  Builder.Free;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "loop-invariant-call",' + #10 +
    '      "name": "Expensive call in a loop condition",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "performance",' + #10 +
    '      "description": "The condition of while and until is evaluated on every iteration. Calls like Trim, Format or FileExists and properties like Lines.Text there are recomputed each time; compute the' +
    'm once before the loop. Bounds of for loops are evaluated only once and are not reported. Off by default.",' + #10 +
    '      "bad": "while I < Length(Trim(Memo.Lines.Text)) do\n  Inc(I);",' + #10 +
    '      "good": "Text := Trim(Memo.Lines.Text);\nwhile I < Length(Text) do\n  Inc(I);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "missing-begin-update",' + #10 +
    '      "name": "Adding items in a loop without BeginUpdate",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "performance",' + #10 +
    '      "description": "Items.Add, Lines.Add and similar calls in a loop repaint the control on every call. Wrap the loop in BeginUpdate and try … finally EndUpdate. Off by default.",' + #10 +
    '      "bad": "for I := 1 to 1000 do\n  ListBox1.Items.Add(IntToStr(I));",' + #10 +
    '      "good": "ListBox1.Items.BeginUpdate;\ntry\n  for I := 1 to 1000 do\n    ListBox1.Items.Add(IntToStr(I));\nfinally\n  ListBox1.Items.EndUpdate;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "setlength-in-loop",' + #10 +
    '      "name": "Array grows by one element in a loop",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "performance",' + #10 +
    '      "description": "SetLength(A, Length(A) + 1) inside a loop copies the dynamic array on every iteration. The rule only reports when A is surely a dynamic array (array of, TArray<T>, an array type ' +
    'of the file or a known RTL type such as TBytes), never for strings. In a for loop the count is known: the message names it, and when A is a local variable not used before the loop and only written as ' +
    'A[High(A)] or A[Length(A) - 1] inside it, the quick fix sets the length once before the loop and indexes with the loop variable. Otherwise collect the values in a TList<T>.",' + #10 +
    '      "bad": "for I := 0 to Liste.Count - 1 do\nbegin\n  SetLength(Namen, Length(Namen) + 1);\n  Namen[High(Namen)] := Liste[I].Name;\nend;",' + #10 +
    '      "good": "SetLength(Namen, Liste.Count);\nfor I := 0 to Liste.Count - 1 do\n  Namen[I] := Liste[I].Name;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "managed-param-without-const",' + #10 +
    '      "name": "Managed parameter without const",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "performance",' + #10 +
    '      "description": "A value parameter of type string, interface, dynamic or open array, or a record of the file with at least minRecordSize bytes, that the routine never changes. Every call pays ref' +
    'erence counting or a copy; const avoids both. Changed means: assigned, a part assigned (characters, fields, elements), passed to var or out, @Param, a method call on a record, a for loop variable. The' +
    ' rule only reports when this is certain: calls with unknown signature (methods without the symbol index, overloads), with blocks, captures in anonymous methods, bare inherited and asm make it stay sil' +
    'ent. Virtual, dynamic, abstract and message methods, calling conventions, external and exported routines, methods of classes implementing interfaces, published methods and methods used as values (even' +
    't handlers, @Routine, form file) are skipped because their signature is given from outside; overrides only with ignoreOverrides = false and then without fix. The fix adds const in the implementation a' +
    'nd the declaration and splits parameter groups when needed. References as method pointers in other units are not visible to the rule; the compiler reports them after the fix.",' + #10 +
    '      "bad": "function Formatieren(Text: string; Kunde: TKundenDaten): string;\nbegin\n  Result := Text + Kunde.Name;\nend;",' + #10 +
    '      "good": "function Formatieren(const Text: string; const Kunde: TKundenDaten): string;\nbegin\n  Result := Text + Kunde.Name;\nend;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "minRecordSize",' + #10 +
    '          "type": "integer",' + #10 +
    '          "default": 16,' + #10 +
    '          "description": "Report record parameters from this size in bytes on."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "ignoreOverrides",' + #10 +
    '          "type": "boolean",' + #10 +
    '          "default": true,' + #10 +
    '          "description": "Do not report overrides; their signature is given by the ancestor."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "bool-compare",' + #10 +
    '      "name": "Comparison with True or False",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "Comparing a Boolean with True or False is redundant; use the expression or not directly.",' + #10 +
    '      "bad": "if Visible = True then\n  Show;",' + #10 +
    '      "good": "if Visible then\n  Show;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "redundant-assigned-free",' + #10 +
    '      "name": "Assigned check before Free",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "Free already checks for nil, so testing Assigned before Free or FreeAndNil is redundant.",' + #10 +
    '      "bad": "if Assigned(List) then\n  List.Free;",' + #10 +
    '      "good": "List.Free;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "raise-in-finally",' + #10 +
    '      "name": "raise in a finally block",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "exceptions",' + #10 +
    '      "description": "An exception raised in a finally block replaces the exception that is currently propagating, which is then lost.",' + #10 +
    '      "bad": "try\n  Work;\nfinally\n  raise Exception.Create(''Fehler'');\nend;",' + #10 +
    '      "good": "try\n  Work;\nfinally\n  Cleanup;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "redundant-parens",' + #10 +
    '      "name": "Redundant parentheses",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "Parentheses around a whole condition or a single identifier add nothing. Off by default.",' + #10 +
    '      "bad": "if (Done) then\n  Exit;",' + #10 +
    '      "good": "if Done then\n  Exit;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "redundant-begin-end",' + #10 +
    '      "name": "begin … end around a single statement",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "A begin … end block that holds exactly one statement can be removed. Off by default.",' + #10 +
    '      "bad": "if Done then\nbegin\n  Exit;\nend;",' + #10 +
    '      "good": "if Done then\n  Exit;",' + #10 +
    '      "overriddenBy": [' + #10 +
    '        "missing-begin-end"' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "with-statement",' + #10 +
    '      "name": "with statement",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "Inside a with block it is unclear which object an identifier belongs to, and a new member of the with object silently changes the meaning. Write the expression out or use a local' +
    ' variable.",' + #10 +
    '      "bad": "with Customer do\n  Name := Edit.Text;",' + #10 +
    '      "good": "Customer.Name := Edit.Text;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-method-length",' + #10 +
    '      "name": "Method too long",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "The method has more code lines than the limit (default 60). Blank lines, comments, compiler directives and local routines do not count. Split the method into smaller ones. Set th' +
    'e limit with the option max, e.g. \"rules\": {\"metric-method-length\": {\"max\": 80}}.",' + #10 +
    '      "bad": "procedure TImport.Run;\nbegin\n  // 120 lines: read, check, convert and save\nend;",' + #10 +
    '      "good": "procedure TImport.Run;\nbegin\n  Read;\n  Check;\n  Convert;\n  Save;\nend;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "max",' + #10 +
    '          "type": "integer",' + #10 +
    '          "default": 60,' + #10 +
    '          "description": "Highest allowed number of statement lines."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-nesting-depth",' + #10 +
    '      "name": "Nesting too deep",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "The method nests if, case, loops and try deeper than the limit (default 4). else if stays on the level of its if. Leave early with Exit or Continue, or move inner parts into thei' +
    'r own methods. Set the limit with the option max.",' + #10 +
    '      "bad": "for Item in Items do\n  if Item.Active then\n    for Line in Item.Lines do\n      if Line.Valid then\n        try\n          Save(Line);\n        except\n          Log;\n        end;",' + #10 +
    '      "good": "for Item in Items do\n  if Item.Active then\n    SaveLines(Item);",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "max",' + #10 +
    '          "type": "integer",' + #10 +
    '          "default": 4,' + #10 +
    '          "description": "Highest allowed nesting depth."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-cyclomatic-complexity",' + #10 +
    '      "name": "Cyclomatic complexity too high",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "The cyclomatic complexity of the method is above the limit (default 15). It starts at 1 and adds 1 for every if, while, repeat and for, every case branch without else, every and/' +
    'or in a condition and every except on; an except without on counts once. Many paths need many tests. Set the limit with the option max.",' + #10 +
    '      "bad": "case Kind of\n  1: A;\n  2: B;\n  // ... 20 branches\nend;",' + #10 +
    '      "good": "Handlers[Kind]();",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "max",' + #10 +
    '          "type": "integer",' + #10 +
    '          "default": 15,' + #10 +
    '          "description": "Highest allowed cyclomatic complexity."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-cognitive-complexity",' + #10 +
    '      "name": "Cognitive complexity too high",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "The cognitive complexity of the method is above the limit (default 15). Following SonarSource, if, case, loops and except handlers count 1 plus their nesting level; else, else if' +
    ', goto and every sequence of equal logical operators count 1. Nested code is harder to read than code in sequence. Set the limit with the option max.",' + #10 +
    '      "bad": "if A then\n  for I := 0 to N do\n    if B and C or D then\n      while E do\n        F;",' + #10 +
    '      "good": "if not A then\n  Exit;\nfor I := 0 to N do\n  ProcessItem(I);",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "max",' + #10 +
    '          "type": "integer",' + #10 +
    '          "default": 15,' + #10 +
    '          "description": "Highest allowed cognitive complexity."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-parameter-count",' + #10 +
    '      "name": "Too many parameters",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "The method has more parameters than the limit (default 6). Group related values in a record or class. Set the limit with the option max.",' + #10 +
    '      "bad": "procedure Book(const AName, AStreet, ACity, AZip: string; AAmount: Currency; ADate: TDate; ANote: string);",' + #10 +
    '      "good": "procedure Book(const AAddress: TAddress; const AOrder: TOrder);",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "max",' + #10 +
    '          "type": "integer",' + #10 +
    '          "default": 6,' + #10 +
    '          "description": "Highest allowed number of parameters."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-boolean-operands",' + #10 +
    '      "name": "Condition with too many operands",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "A condition of if, while, until or a conditional expression joins more operands with and, or and xor than the limit (default 5); parentheses and not are looked through, a compari' +
    'son or call counts as one operand. The finding sits on the condition. Quick fix: Extract condition to function (#50) turns the whole condition into a Boolean function (a method of the class or a routi' +
    'ne before the current one) with the local names it reads as const parameters. Also shown in the metrics lens.",' + #10 +
    '      "bad": "if (Kunde.Aktiv) and (Kunde.Land = ''DE'') and (Betrag > 0) and\n   (not Gesperrt) and (Datum >= Start) and (Datum <= Ende) then",' + #10 +
    '      "good": "if IstBuchbar(Kunde, Betrag, Gesperrt, Datum, Start, Ende) then",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "max",' + #10 +
    '          "type": "integer",' + #10 +
    '          "default": 5,' + #10 +
    '          "description": "Highest allowed number of operands in one condition."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-local-count",' + #10 +
    '      "name": "Too many local variables",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "The routine declares more local variables than the limit (default 12): names in its var section, inline variables and for var loops. Local routines and anonymous methods count on' +
    ' their own. Many locals usually mean the routine does several things; extract parts into own methods. Also shown in the metrics lens.",' + #10 +
    '      "bad": "procedure Abschluss;\nvar\n  Summe, Netto, Steuer, Rabatt, Skonto, Porto: Currency;\n  Kunde, Konto, Beleg, Datei, Zeile, Text, Pfad: string;",' + #10 +
    '      "good": "procedure Abschluss;\nvar\n  Beleg: TBeleg;\nbegin\n  Beleg := BerechneBeleg;\n  SchreibeBeleg(Beleg);",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "max",' + #10 +
    '          "type": "integer",' + #10 +
    '          "default": 12,' + #10 +
    '          "description": "Highest allowed number of local variables."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-exit-points",' + #10 +
    '      "name": "Too many exit points",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "The routine leaves more often through Exit and raise than the limit (default 4); Exit(Value) and a bare raise in an except block count too. Local routines and anonymous methods c' +
    'ount on their own. Many exits make the flow hard to follow; combine guard clauses or extract parts. Also shown in the metrics lens.",' + #10 +
    '      "bad": "if A = nil then Exit;\nif B = nil then Exit;\nif not Valid then raise EError.Create(''...'');\nif Done then Exit(True);\nif Cancel then Exit(False);",' + #10 +
    '      "good": "if not Ready(A, B) then\n  Exit;\nResult := Process(A, B);",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "max",' + #10 +
    '          "type": "integer",' + #10 +
    '          "default": 4,' + #10 +
    '          "description": "Highest allowed number of Exit and raise statements."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "todo-comment",' + #10 +
    '      "name": "Open TODO comment",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "A comment starts with a marker for open work: // TODO, // FIXME or the IDE to-do format { TODO 1 -oOwner -cCategory : Text }. The hint shows marker, priority, category, owner and' +
    ' text, so open work appears in the problem list. Off by default; switch it on in atlas.json, e.g. \"rules\": {\"todo-comment\": {\"severity\": \"hint\"}}. Completed entries ({ DONE … }) are never repo' +
    'rted. The option keywords sets the markers (default [\"TODO\", \"FIXME\"]); it also applies to get_todos and --todos.",' + #10 +
    '      "bad": "// TODO 1 -oMarco -cGUI : set focus\nEdit.Text := '''';",' + #10 +
    '      "good": "Edit.Text := '''';\nEdit.SetFocus;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "keywords",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [' + #10 +
    '            "TODO",' + #10 +
    '            "FIXME"' + #10 +
    '          ],' + #10 +
    '          "description": "Markers of open TODO entries (letters only)."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-palette-icon",' + #10 +
    '      "name": "Registered component without palette icon",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "components",' + #10 +
    '      "description": "Every class passed to RegisterComponents needs a bitmap named after the class in upper case in a .dcr or .res included with {$R}. From Delphi 11 the sizes 16, 24 and 32 px (NAME1' +
    '6, NAME24, NAME32) are expected as well. Silent when the unit includes no readable resource file.",' + #10 +
    '      "bad": "{$R *.dcr} // without TMYBUTTON\nRegisterComponents(''Samples'', [TMyButton]);",' + #10 +
    '      "good": "{$R *.dcr} // with TMYBUTTON16, TMYBUTTON24, TMYBUTTON32\nRegisterComponents(''Samples'', [TMyButton]);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unresolved-identifier",' + #10 +
    '      "name": "Unresolved identifier",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "An identifier in a statement is declared neither in the unit nor in the units it uses (like compiler error E2003). Checked while typing, without the compiler; with blocks, asm an' +
    'd anonymous methods are skipped.",' + #10 +
    '      "bad": "procedure Foo;\nbegin\n  Lst.Add(''x'');\nend;",' + #10 +
    '      "good": "procedure Foo;\nvar\n  Lst: TStringList;\nbegin\n  Lst := TStringList.Create;\n  Lst.Add(''x'');\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "deprecated-symbol",' + #10 +
    '      "name": "Deprecated or bound symbol",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A routine, type, constant or member marked deprecated, experimental, platform or library is used (like W1000, W1003, W1002, W1001), or a unit whose header carries one of these hi' +
    'nts is listed in uses (like W1006, W1007, W1005, W1004). Reported only when the name resolves for sure. The editor strikes deprecated names through; the message carries the reason from deprecated ''rea' +
    'son''. The declaration and the head of its implementation are not reported. Which kinds are reported is set by the option kinds (deprecated and experimental by default, as in most projects); the switch' +
    'es {$WARN SYMBOL_DEPRECATED OFF|ON|ERROR|DEFAULT}, {$WARN UNIT_PLATFORM …} and so on and {$WARNINGS OFF} apply from their position like in the compiler; a switch in an {$IF} branch that is not surely ' +
    'compiled with the position keeps it silent. Quick fix: replace with the name the reason gives (or, for IncludeTrailingBackslash and ExcludeTrailingBackslash, the platform-independent routine) when exa' +
    'ctly one name fits, is visible at that position and is of the same kind. Without a project index only the symbols of the file itself are checked.",' + #10 +
    '      "bad": "Pfad := IncludeTrailingBackslash(Basis) + Name;",' + #10 +
    '      "good": "Pfad := IncludeTrailingPathDelimiter(Basis) + Name;",' + #10 +
    '      "level": "B",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "W1000",' + #10 +
    '        "W1001",' + #10 +
    '        "W1002",' + #10 +
    '        "W1003",' + #10 +
    '        "W1004",' + #10 +
    '        "W1005",' + #10 +
    '        "W1006",' + #10 +
    '        "W1007"' + #10 +
    '      ],' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "kinds",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [' + #10 +
    '            "deprecated",' + #10 +
    '            "experimental"' + #10 +
    '          ],' + #10 +
    '          "description": "Reported kinds: deprecated, experimental, platform, library (platform and library are off by default)."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "implicit-package-import",' + #10 +
    '      "name": "Implicit package import",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "packages",' + #10 +
    '      "description": "In a package (.dpk) a unit from contains uses a unit that is neither in contains nor provided by a package in requires. The compiler pulls it in implicitly (W1033), which later c' +
    'auses duplicate units when another package also contains it. The quick fix adds the unit to contains.",' + #10 +
    '      "bad": "package Werkzeuge;\nrequires rtl;\ncontains\n  uHaupt in ''uHaupt.pas'';  // uHaupt uses uMathe\nend.",' + #10 +
    '      "good": "package Werkzeuge;\nrequires rtl;\ncontains\n  uHaupt in ''uHaupt.pas'',\n  uMathe in ''uMathe.pas'';\nend."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "type-used-before-declaration",' + #10 +
    '      "name": "Type used before its declaration",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "A class, interface, record or other type is used in a type declaration (field, parameter, result, property, generic argument, class of) but declared only further down in the same' +
    ' scope (like compiler error E2003). Ancestors, aliases and pointer types are not reported. Quick fixes: add a forward declaration at the start of the type block, merge type blocks (const, var and labe' +
    'l sections in between move in front of the first block) or move a record up in front of its first user; without a safe fix the message gives the reason.",' + #10 +
    '      "bad": "type\n  TTree = class\n    FRoot: TNode;\n  end;\n  TNode = class\n  end;",' + #10 +
    '      "good": "type\n  TNode = class;\n  TTree = class\n    FRoot: TNode;\n  end;\n  TNode = class\n  end;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unneeded-forward-declaration",' + #10 +
    '      "name": "Unneeded forward declaration",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "A forward declaration whose type is not used before its full declaration in the same type block. Quick fix: remove it.",' + #10 +
    '      "bad": "type\n  TNode = class;\n  TNode = class\n  end;",' + #10 +
    '      "good": "type\n  TNode = class\n  end;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "field-not-freed",' + #10 +
    '      "name": "Field created but never freed",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "An object field that the constructor (or a private method it calls) creates with TClass.Create is never freed in the class (no Free, FreeAndNil, Destroy or DisposeOf): a memory l' +
    'eak. Components created with an owner other than nil, interface and record fields and the classes from the option ignoreTypes are exempt; TObjectList and TObjectDictionary fields are normal fields. Me' +
    'dium confidence. Quick fixes: free the field in the destructor, or free all owned objects of the class; a missing destructor is created with override and inherited. The objects are freed before inheri' +
    'ted in reverse creation order, as Free or FreeAndNil (refactoring.freeFieldsStyle). Up to #918 the rule was called owned-field-not-freed; settings and suppressions with that id still apply.",' + #10 +
    '      "bad": "constructor TImport.Create;\nbegin\n  FZeilen := TStringList.Create;\n  FFehler := TStringList.Create;\nend;\n\ndestructor TImport.Destroy;\nbegin\n  FZeilen.Free;\n  inherited;\nend;",' + #10 +
    '      "good": "destructor TImport.Destroy;\nbegin\n  FFehler.Free;\n  FZeilen.Free;\n  inherited;\nend;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "ignoreTypes",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [],' + #10 +
    '          "description": "Classes that are freed elsewhere; generic types match without type parameters."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "owned-field-free-unclear",' + #10 +
    '      "name": "Unclear whether a created field must be freed",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "An object field created in the constructor and not freed is also returned (Result := FField, Exit(FField)), handed to a property of another object or to its Add…, Insert…, Regist' +
    'er…, Attach…, Push or Enqueue, assigned without Create or writable through a property (write FField). Whether the class still owns the object is up to the developer, so there is no quick fix.",' + #10 +
    '      "bad": "function TCache.Take: TList;\nbegin\n  Result := FList;  // created in Create, never freed\nend;",' + #10 +
    '      "good": "function TCache.Take: TList;\nbegin\n  Result := FList;\n  FList := nil;  // ownership passes to the caller\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "operator-precedence",' + #10 +
    '      "name": "Precedence of not overlooked",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "In Pascal not binds more tightly than in and comparisons: not X in Set means (not X) in Set, not A = B means (not A) = B, and on integers not works bitwise. The rule reports thes' +
    'e forms when the declared type of the operand shows that this cannot be meant (not Boolean). Quick fix: add parentheses, not (X in Set).",' + #10 +
    '      "bad": "if not Zustand in [zsOffen, zsGesperrt] then\n  Bearbeiten;",' + #10 +
    '      "good": "if not (Zustand in [zsOffen, zsGesperrt]) then\n  Bearbeiten;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "empty-statement",' + #10 +
    '      "name": "Empty statement after then, do or else",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "A semicolon right after then, do or else ends the statement: the following line always runs, or the loop spins empty. An empty begin … end after then, do or else is reported too,' +
    ' unless it contains an explanatory comment (option allowCommented). A semicolon right before end, until, except or finally changes nothing and is not reported. Quick fix: remove the semicolon.",' + #10 +
    '      "bad": "if Liste.Count = 0 then;\n  raise EKeineDaten.Create(''Keine Daten'');",' + #10 +
    '      "good": "if Liste.Count = 0 then\n  raise EKeineDaten.Create(''Keine Daten'');",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "allowCommented",' + #10 +
    '          "type": "boolean",' + #10 +
    '          "default": true,' + #10 +
    '          "description": "Do not report begin { intentionally empty } end."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "loop-off-by-one",' + #10 +
    '      "name": "Loop runs one step too far",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "for I := 0 to List.Count or to Length(A) over zero-based lists and arrays reads one element past the end when the body indexes List[I] or A[I]. With one-based strings it is the o' +
    'ther way round: S[0] and for I := 0 to Length(S) read before the first character; {$ZEROBASEDSTRINGS ON} is taken into account. Quick fix: add - 1 or use High(A); for strings Low(S) and High(S). The o' +
    'ption countNames lists the names that return a count.",' + #10 +
    '      "bad": "for I := 0 to Kunden.Count do\n  Ausgabe(Kunden[I].Name);",' + #10 +
    '      "good": "for I := 0 to Kunden.Count - 1 do\n  Ausgabe(Kunden[I].Name);",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "countNames",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [' + #10 +
    '            "Count",' + #10 +
    '            "Length"' + #10 +
    '          ],' + #10 +
    '          "description": "Names that return a count (property like Count or function like Length)."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "collection-modified-in-loop",' + #10 +
    '      "name": "List modified inside its own loop",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "Delete, Remove, Add or another method from the option mutatingMethods is called on the list that the loop is walking forwards by index or with for … in. Forwards, Delete skips th' +
    'e next element and runs past the end, Add is not visited and Insert visits the same element twice; with for … in the RTL raises an exception. A Break or Exit directly after the call ends the loop and ' +
    'stays silent, downto loops too. Quick fix for index loops: rewrite as downto; for for … in collect the elements and change the list after the loop.",' + #10 +
    '      "bad": "for I := 0 to Liste.Count - 1 do\n  if Liste[I].Erledigt then\n    Liste.Delete(I);",' + #10 +
    '      "good": "for I := Liste.Count - 1 downto 0 do\n  if Liste[I].Erledigt then\n    Liste.Delete(I);",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "mutatingMethods",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [' + #10 +
    '            "Add",' + #10 +
    '            "Insert",' + #10 +
    '            "Delete",' + #10 +
    '            "Remove",' + #10 +
    '            "Extract",' + #10 +
    '            "Clear"' + #10 +
    '          ],' + #10 +
    '          "description": "Methods that change the list."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "use-after-free",' + #10 +
    '      "name": "Object used after Free",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "After X.Free, X.Destroy, X.DisposeOf, FreeAndNil(X) or Dispose(X), X is used again without a new assignment: a method, field, index or X^, with X, and after Free also Assigned(X)' +
    ' (always True) or a second Free. The rule follows the data flow of the routine; an assignment to X, passing X to a routine, @X and after FreeAndNil a check for nil end the path, ways only through a po' +
    'ssible exception are left out. Confidence high when release and access stand one after the other in the same block, otherwise medium. No automatic fix; the action jumps to the release.",' + #10 +
    '      "bad": "Bericht.Free;\nProtokoll.Add(''Seiten: '' + IntToStr(Bericht.Seiten));",' + #10 +
    '      "good": "Protokoll.Add(''Seiten: '' + IntToStr(Bericht.Seiten));\nBericht.Free;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "deref-before-nil-check",' + #10 +
    '      "name": "Used first, checked for nil later",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "X is dereferenced (X.Field, X.Method, X^) and only afterwards checked with Assigned(X), X <> nil or X = nil. Either the check is superfluous or the access before it can crash. Re' +
    'ported only when every path to the check passes the access and X was not checked before; a new assignment, passing X to a routine and, for fields and global variables, any call in between end the path' +
    '. Medium confidence. When the check is an if without else directly after the access in the same block, the quick fix moves the access into it.",' + #10 +
    '      "bad": "Titel := Kunde.Name;\nif Assigned(Kunde) then\n  Anzeigen(Kunde);",' + #10 +
    '      "good": "if Assigned(Kunde) then\nbegin\n  Titel := Kunde.Name;\n  Anzeigen(Kunde);\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "field-free-without-nil",' + #10 +
    '      "name": "Field freed, reference stays",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "FField.Free in a method outside the destructor, and a path to the end of the method does not set the field again. A later access or a second Free hits freed memory. Setting it ag' +
    'ain means an assignment or the call of a method of the same class that assigns the field. Fields are those of the class declaration in the unit. Destructors, methods with [TearDown] or [TearDownFixtur' +
    'e], methods only called from these and the methods from the option ignoreMethods are exempt. Medium confidence. Quick fix: FreeAndNil(FField).",' + #10 +
    '      "bad": "procedure TImport.Zuruecksetzen;\nbegin\n  FCache.Free;\nend;",' + #10 +
    '      "good": "procedure TImport.Zuruecksetzen;\nbegin\n  FreeAndNil(FCache);\nend;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "ignoreMethods",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [' + #10 +
    '            "Destroy",' + #10 +
    '            "BeforeDestruction"' + #10 +
    '          ],' + #10 +
    '          "description": "Methods in which Free without nil is allowed."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "missing-inherited",' + #10 +
    '      "name": "Constructor or destructor without inherited",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "A constructor, or an override of Destroy, AfterConstruction or BeforeDestruction, does not call inherited, in any class whose ancestor is not TObject. Constructors are reported o' +
    'nly if an ancestor declares a constructor of its own (file, index or a known RTL/VCL class) and the constructor does not call another constructor of the same class. For components, Destroy is reported' +
    ' only by component-missing-inherited. High confidence. Quick fix: insert inherited; at the end of Destroy and BeforeDestruction, at the start of constructors and AfterConstruction; a constructor with ' +
    'parameters without override gets inherited Create;.",' + #10 +
    '      "bad": "destructor TExport.Destroy;\nbegin\n  FDatei.Free;\nend;",' + #10 +
    '      "good": "destructor TExport.Destroy;\nbegin\n  FDatei.Free;\n  inherited;\nend;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "methods",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [' + #10 +
    '            "Create",' + #10 +
    '            "Destroy",' + #10 +
    '            "AfterConstruction",' + #10 +
    '            "BeforeDestruction"' + #10 +
    '          ],' + #10 +
    '          "description": "Checked methods; Create stands for all constructors whose name starts with Create."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "inherited-order",' + #10 +
    '      "name": "inherited in the wrong place",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "In a destructor, inherited (inherited; or inherited Destroy) stands as a statement of the method body before a later statement frees a field of the class itself (F.Free, F.Dispos' +
    'eOf, FreeAndNil(F), also with Self.): the ancestor may still call virtual methods that need the field. Classes whose chain contains a class with Thread in its name stay silent, because TThread.Destroy' +
    ' waits for Execute and belongs at the start there. In a constructor, the statements before inherited access a field or property inherited from an ancestor (resolved through the file and the index; own' +
    ' fields, parameters and local variables do not count), while the ancestor is not set up yet. missing-inherited reports a missing inherited; this rule the order. Medium confidence. Quick fix: move inhe' +
    'rited to the end of the destructor or the start of the constructor; not when the arguments of inherited Create use local variables set before.",' + #10 +
    '      "bad": "destructor TExport.Destroy;\nbegin\n  inherited;\n  FDatei.Free;\nend;",' + #10 +
    '      "good": "destructor TExport.Destroy;\nbegin\n  FDatei.Free;\n  inherited;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "inherited-wrong-method",' + #10 +
    '      "name": "inherited calls a different method",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "In the overridden method Speichern there is inherited Laden(…) instead of inherited Speichern(…), usually after copying a method. Only calls count (inherited Name as a statement ' +
    'or with parentheses); inherited Caption without parentheses may be a property. Silent in constructors (inherited Create(nil), CreateNew), in methods without override and when the method also calls its' +
    'elf in the ancestor (inherited; or inherited Speichern), which makes the other call intentional. Pairs from the option allowed stay silent. High confidence. Quick fix: replace the name with the method' +
    '''s own, when the number of arguments matches its parameters.",' + #10 +
    '      "bad": "procedure TKundenForm.Speichern;\nbegin\n  inherited Laden;\n  Protokollieren;\nend;",' + #10 +
    '      "good": "procedure TKundenForm.Speichern;\nbegin\n  inherited Speichern;\n  Protokollieren;\nend;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "allowed",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [],' + #10 +
    '          "description": "Allowed pairs \"Method>inherited method\", patterns with * and ?, e.g. \"Speichern>Pruefen\"."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "getter-side-effect",' + #10 +
    '      "name": "Getter changes the state",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "The read method of a property assigns fields or properties of its own object (FAbrufe, Self.FWert, inherited fields as well), calls Inc/Dec/Include/Exclude on them or passes a ne' +
    'wly created object to a method of a field (FListe.Add(TEintrag.Create)). The debugger evaluates getters when displaying them and so changes the state. Lazy initialization is allowed: an enclosing if t' +
    'ests something that its branch assigns (if FListe = nil then FListe := …, if Result = nil then … FListe := Result, if not FGeladen then … FGeladen := True). Local variables with the same name as a fie' +
    'ld, Result, methods without a property and anonymous methods stay silent. One message per getter and field. Medium confidence. No quick fix.",' + #10 +
    '      "bad": "function TZaehler.GetWert: Integer;\nbegin\n  Inc(FAbrufe);\n  Result := FWert;\nend;",' + #10 +
    '      "good": "function TZaehler.GetWert: Integer;\nbegin\n  Result := FWert;\nend;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "allowLazyInit",' + #10 +
    '          "type": "boolean",' + #10 +
    '          "default": true,' + #10 +
    '          "description": "Allow lazy initialization in the getter (if FListe = nil then FListe := …)."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "equals-without-gethashcode",' + #10 +
    '      "name": "Equals without GetHashCode",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "A class overrides Equals but not GetHashCode (or the other way round). In TDictionary and THashSet with the default comparer equal objects then do not find each other. Silent whe' +
    'n an ancestor overrides the counterpart, when the ancestor chain is not known completely and for Equals without override. Also applies to records of the file with class operator Equal used as keys of ' +
    'TDictionary, TObjectDictionary, THashSet or TMultiMap without a comparer (Create without arguments or only with constants such as capacity or ownership): the default comparer compares records byte by ' +
    'byte, which is only wrong for fields of type string, Variant, floating point, interface or TArray; records with only such ordinal fields stay silent. High confidence. Quick fix for classes: declare Ge' +
    'tHashCode after Equals and implement it after the body of Equals with THashBobJenkins over the own fields that Equals compares (case-insensitively via LowerCase when Equals uses SameText), adding Syst' +
    'em.Hash to uses.",' + #10 +
    '      "bad": "  TKundenNr = class\n    function Equals(Obj: TObject): Boolean; override;\n  end;",' + #10 +
    '      "good": "  TKundenNr = class\n    function Equals(Obj: TObject): Boolean; override;\n    function GetHashCode: Integer; override;\n  end;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "destroy-called-directly",' + #10 +
    '      "name": "Destroy called instead of Free",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "Obj.Destroy is called directly as a statement. If Obj is nil, the call crashes; Free checks for nil first and is the usual way to release an object. inherited Destroy and calls o' +
    'f a destructor with arguments are exempt. High confidence. Quick fix: Destroy becomes Free.",' + #10 +
    '      "bad": "Verbindung.Destroy;",' + #10 +
    '      "good": "Verbindung.Free;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "managed-type-raw-memory",' + #10 +
    '      "name": "FillChar, Move or GetMem on managed types",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "FillChar, ZeroMemory, FillMemory, Move, CopyMemory, GetMem or FreeMem on a variable whose type contains strings, interfaces, dynamic arrays or variants (records, static arrays an' +
    'd aliases are resolved in the file and in the index). Reference counts are overwritten or skipped: leaks, double frees, access violations. Only plain variables (X, @X, P^) are checked; array elements ' +
    'such as S[1] and types that cannot be resolved stay silent. High confidence. Quick fixes: FillChar(X, SizeOf(X), 0) becomes X := Default(T), Move(A, B, SizeOf(T)) becomes B := A, GetMem(P, SizeOf(T)) ' +
    'becomes New(P) and FreeMem(P) becomes Dispose(P); otherwise Initialize and Finalize help.",' + #10 +
    '      "bad": "FillChar(Adresse, SizeOf(Adresse), 0);",' + #10 +
    '      "good": "Adresse := Default(TAdresse);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "threadvar-managed",' + #10 +
    '      "name": "threadvar with a managed type",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "threads",' + #10 +
    '      "description": "Delphi does not finalize threadvar variables. A string, interface, dynamic array or variant in a threadvar (also inside a record or static array) leaks in every thread that ends.' +
    ' Types are resolved in the file and in the index. High confidence. No quick fix: release the value at the end of the thread (for example set it to '''' or nil in TThread.Execute), or store a pointer or ' +
    'a fixed-size buffer instead.",' + #10 +
    '      "bad": "threadvar\n  LetzteMeldung: string;",' + #10 +
    '      "good": "threadvar\n  LetzteMeldung: PChar;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "pchar-of-temporary",' + #10 +
    '      "name": "PChar of a temporary string",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "PChar (PWideChar, PAnsiChar) of a temporary string, such as a concatenation with a string (S + ''.bak'') or a function result (IntToStr(N)), is stored in a variable, a field or Res' +
    'ult, or passed to PostMessage, PostThreadMessage, SendNotifyMessage or SendMessageCallback (also behind LPARAM(…)). The temporary string is released after the statement, so the pointer points to freed' +
    ' memory. Passing it to an ordinary call such as CopyFile is fine. High confidence. Quick fix for local variables: keep the intermediate result in an inline string variable.",' + #10 +
    '      "bad": "Ziel := PChar(Pfad + ''.bak'');\nCopyFile(PChar(Pfad), Ziel, False);",' + #10 +
    '      "good": "var ZielText: string := Pfad + ''.bak'';\nZiel := PChar(ZielText);\nCopyFile(PChar(Pfad), Ziel, False);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "out-param-read",' + #10 +
    '      "name": "out parameter read before it is set",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "An out parameter is read before the routine sets it on some path through the control flow. For managed types (string, interfaces, dynamic arrays, Variant) the caller has already ' +
    'cleared it, so the old value is gone; for other types the value is undefined. Usually var was meant. Uses the control flow graph cannot follow (passing the parameter to a routine, setting a field of i' +
    't, @Param) stay silent. High confidence. Quick fix: out becomes var in the implementation and in the declaration.",' + #10 +
    '      "bad": "procedure Anhaengen(out Text: string);\nbegin\n  Text := Text + sLineBreak + ''Ende'';\nend;",' + #10 +
    '      "good": "procedure Anhaengen(var Text: string);\nbegin\n  Text := Text + sLineBreak + ''Ende'';\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "stringlist-unsorted",' + #10 +
    '      "name": "Find or Duplicates on an unsorted TStringList",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "Find on a TStringList or THashedStringList that is created in the unit but never sorted: Find searches binary and returns wrong results on an unsorted list. The same holds for Du' +
    'plicates := dupIgnore or dupError, which only works on sorted lists. Sorted counts as Sorted := True (or any value other than False), Sort, CustomSort, Create(Duplicates, True, ...) and with List do. ' +
    'A list passed to a routine or assigned to another variable stays silent. Locals are tracked per routine, fields across the unit. Medium confidence. Quick fixes: Sorted := True after the creation (not ' +
    'offered when the list uses Insert, Move or Exchange, which raise on sorted lists) and, for if List.Find(S, I) then, I := List.IndexOf(S) with if I >= 0.",' + #10 +
    '      "bad": "Namen := TStringList.Create;\nNamen.LoadFromFile(Datei);\nif Namen.Find(Suche, Index) then\n  Namen.Delete(Index);",' + #10 +
    '      "good": "Namen := TStringList.Create;\nNamen.Sorted := True;\nNamen.LoadFromFile(Datei);\nif Namen.Find(Suche, Index) then\n  Namen.Delete(Index);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "writeln-in-gui-app",' + #10 +
    '      "name": "Writeln in a program without console",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "Write, Writeln, Read or Readln on standard input or output in a program without a console: at run time Writeln raises EInOutError (I/O error 105), Readln I/O error 104. The appli' +
    'cation type comes from DCC_ConsoleTarget in the .dproj and {$APPTYPE CONSOLE} in the .dpr (also inside {$IFDEF}); units are only checked when they belong to the loaded project, a .dpr without project ' +
    'on its own. Libraries and packages stay silent. Calls with a text file as first argument, calls under if IsConsole, routines of the same name declared in the unit and Read/Write inside methods (TStrea' +
    'm.Read) are exempt. High confidence. Quick fix for Write and Writeln: replace with OutputDebugString(PChar(...)) and add Winapi.Windows; numbers and Boolean go through IntToStr, FloatToStr and BoolToS' +
    'tr. Option replacement sets another target, e.g. Log.Info or Logger.Log(TLogLevel.Info, %s). No fix for width specifiers (X:5) or arguments of unknown type.",' + #10 +
    '      "bad": "procedure TfrmHaupt.btnStartClick(Sender: TObject);\nbegin\n  Writeln(''Start: '', TimeToStr(Now));\nend;",' + #10 +
    '      "good": "procedure TfrmHaupt.btnStartClick(Sender: TObject);\nbegin\n  OutputDebugString(PChar(''Start: '' + TimeToStr(Now)));\nend;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "replacement",' + #10 +
    '          "type": "string",' + #10 +
    '          "default": "OutputDebugString",' + #10 +
    '          "description": "Replacement for Write and Writeln in the quick fix; %s stands for the text."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "exception-in-destructor",' + #10 +
    '      "name": "raise in a destructor",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "exceptions",' + #10 +
    '      "description": "raise in a destructor (also class destructor) that no except inside the destructor catches. The exception aborts the destruction: inherited Destroy no longer runs, the object sta' +
    'ys half freed, and in a finally of the caller it hides the original exception. A raise in the try part of a try..except is caught; raise in the except or finally part, including a bare raise; to re-ra' +
    'ise, is reported. Nested routines and anonymous methods are exempt. Calls that raise are not followed. High confidence. No quick fix: log the state or release it without an exception.",' + #10 +
    '      "bad": "destructor TSitzung.Destroy;\nbegin\n  if FOffen then\n    raise ESitzung.Create(''Sitzung noch offen'');\n  inherited;\nend;",' + #10 +
    '      "good": "destructor TSitzung.Destroy;\nbegin\n  if FOffen then\n    Schliessen;\n  inherited;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "duplicate-condition",' + #10 +
    '      "name": "Duplicate condition or identical branches",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "The same condition twice in an if ... else if chain (the later branch is never reached), identical then and else branches, the same operand twice in an and, or or xor chain, and ' +
    'comparisons of an expression with itself (X = X, X < X). Usually a copy error. Expressions are compared by their tokens without whitespace, comments and case. Chains with calls that may change state (' +
    'anything but SameText, Length, Assigned, Pos and similar pure functions, or Read, Next, Pop, Random ...) stay silent, as do float self-comparisons (NaN check X <> X) and comparisons on class members s' +
    'uch as TFoo.Shared = TFoo.Shared. High confidence. No quick fix; the action jumps to the first occurrence.",' + #10 +
    '      "bad": "if Betrag > 1000 then\n  Stufe := 3\nelse if Betrag > 500 then\n  Stufe := 2\nelse if Betrag > 1000 then\n  Stufe := 1;",' + #10 +
    '      "good": "if Betrag > 1000 then\n  Stufe := 3\nelse if Betrag > 500 then\n  Stufe := 2\nelse if Betrag > 100 then\n  Stufe := 1;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "case-missing-enum-value",' + #10 +
    '      "name": "case over an enumeration without all values",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "A case over an enumerated type without else does not cover all values; a value added later silently falls through. The message names the missing values. The type of the selector ' +
    '(variable, parameter, field or chain A.B) comes from name resolution, the values from the index or the unit itself; aliases are followed. Ranges (bsNeu..bsBezahlt) and lists count as present. Selector' +
    's with calls, integer and unknown types stay silent. With option requireElse a case with else is reported as well. High confidence. Quick fix \"Fehlende Werte ergänzen (n)\" adds empty branches in dec' +
    'laration order before else or end, with type prefix when the labels use one ({$SCOPEDENUMS ON}).",' + #10 +
    '      "bad": "case Bestellung.Status of\n  bsNeu: Anlegen;\n  bsBezahlt: Versenden;\nend;",' + #10 +
    '      "good": "case Bestellung.Status of\n  bsNeu: Anlegen;\n  bsBezahlt: Versenden;\n  bsStorniert: ;\n  bsZurueck: ;\nend;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "requireElse",' + #10 +
    '          "type": "boolean",' + #10 +
    '          "default": false,' + #10 +
    '          "description": "Also report case statements with else when values are missing."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "pair-without-finally",' + #10 +
    '      "name": "Paired calls without try/finally",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "Generalises lock-without-finally (whose lock pairs stay there) to other pairs: DisableControls/EnableControls, BeginUpdate/EndUpdate, FindFirst/FindClose (also in if FindFirst(..' +
    '.) = 0 then begin ... end), Reset, Rewrite or Append/CloseFile, GetMem or AllocMem/FreeMem and Screen.Cursor := ... with a later Screen.Cursor := .... Reported when the closing call stands unprotected' +
    ' later in the same statement list with at least one statement in between; an exception there leaves the state hanging. Both calls must use the same receiver or argument. Overlapping pairs are reported' +
    ' together. High confidence. Quick fix: wrap the statements in between in try/finally with the closing calls, when the closing calls follow each other directly. Option pairs adds own pairs.",' + #10 +
    '      "bad": "Screen.Cursor := crHourGlass;\nTabelle.DisableControls;\nImportieren;\nTabelle.EnableControls;\nScreen.Cursor := crDefault;",' + #10 +
    '      "good": "Screen.Cursor := crHourGlass;\nTabelle.DisableControls;\ntry\n  Importieren;\nfinally\n  Tabelle.EnableControls;\n  Screen.Cursor := crDefault;\nend;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "pairs",' + #10 +
    '          "type": "json",' + #10 +
    '          "default": [],' + #10 +
    '          "description": "Additional pairs as [{\"open\": \"Freeze\", \"close\": \"Thaw\"}], optionally with openArg/closeArg."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "processmessages-in-loop",' + #10 +
    '      "name": "Application.ProcessMessages in loops",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "threads",' + #10 +
    '      "description": "Application.ProcessMessages inside a for, while or repeat loop, or directly in an event handler (a method with a Sender parameter), opens the door for re-entrancy: the user click' +
    's again, closes the form or starts the operation twice. Calls inside anonymous methods are left to thread-vcl-access; other objects'' ProcessMessages methods are ignored. Medium confidence, no quick fi' +
    'x: move the work to a thread or TTask, or disable the trigger until it is done. Option allowIn lists methods where it is allowed.",' + #10 +
    '      "bad": "while not Done do\nbegin\n  Step;\n  Application.ProcessMessages;\nend;",' + #10 +
    '      "good": "StartButton.Enabled := False;\nTTask.Run(\n  procedure\n  begin\n    while not Done do\n      Step;\n    TThread.Queue(nil, procedure begin StartButton.Enabled := True; end);\n  end);",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "allowIn",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [],' + #10 +
    '          "description": "Methods in which ProcessMessages is allowed, as Name or Class.Name."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unchecked-conversion",' + #10 +
    '      "name": "Unchecked conversion of user input",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "StrToInt, StrToInt64, StrToFloat, StrToDate, StrToDateTime or StrToCurr applied directly to user input (Edit.Text, Grid.Cells[...], Memo.Lines[...], also inside Trim) outside the' +
    ' try part of a try/except. Invalid input raises EConvertError with an English message. try/finally does not count as protection. Medium confidence. Quick fix for X := StrToInt(Edit.Text); as its own s' +
    'tatement, when X is a variable or field of the matching type: if not TryStrToInt(Edit.Text, X) then raise EConvertError.Create(''X ist keine Zahl''). format-without-settings additionally reports locale-' +
    'dependent conversions without TFormatSettings. Options functions and sources choose the checked conversions and the properties that count as input.",' + #10 +
    '      "bad": "Menge := StrToInt(edtMenge.Text);",' + #10 +
    '      "good": "if not TryStrToInt(edtMenge.Text, Menge) then\n  raise EConvertError.Create(''Menge ist keine Zahl'');",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "functions",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [' + #10 +
    '            "StrToInt",' + #10 +
    '            "StrToInt64",' + #10 +
    '            "StrToFloat",' + #10 +
    '            "StrToDate",' + #10 +
    '            "StrToDateTime",' + #10 +
    '            "StrToCurr"' + #10 +
    '          ],' + #10 +
    '          "description": "Checked conversions."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "sources",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [' + #10 +
    '            "Text",' + #10 +
    '            "Cells",' + #10 +
    '            "Lines"' + #10 +
    '          ],' + #10 +
    '          "description": "Properties that count as user input."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dictionary-get-without-check",' + #10 +
    '      "name": "Dictionary access without key check",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "Dict[Key] or Dict.Items[Key] is read on a TDictionary or TObjectDictionary (also through a type alias of the file) although neither ContainsKey nor TryGetValue checked the same k' +
    'ey earlier in the routine. The rule stays silent when the routine fills the dictionary itself beforehand (Add, AddOrSetValue, TryAdd, Dict[K] := ...) or when the key stems from Keys or the pairs (for ' +
    'K in Dict.Keys, Names := Dict.Keys.ToArray, for Pair in Dict with K := Pair.Key). A missing key raises EListError. Medium confidence. Quick fix for X := Dict[Key]; as its own statement, when X is a va' +
    'riable of the value type: if not Dict.TryGetValue(Key, X) then X := 0 (or '''', False, Default(T)).",' + #10 +
    '      "bad": "Preis := Preise[Artikel.Nummer];",' + #10 +
    '      "good": "if not Preise.TryGetValue(Artikel.Nummer, Preis) then\n  Preis := 0;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "shadowed-name",' + #10 +
    '      "name": "Local name shadows field or property",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "A parameter, local or inline variable has the same name as a field or property of the class (also inherited and visible there, resolved through the file and the symbol index) or ' +
    'as a global variable of the unit declared before the routine. Especially treacherous in form methods: Caption, Name, Tag, Left. If VCL is not in the index, the members of TComponent and TControl are k' +
    'nown when the ancestor chain ends at a VCL base class. Parameters of event handlers (with Sender) are skipped because the event type dictates the signature. High confidence. Quick fix: rename to AName' +
    ' (parameter, also in the declaration) or LName (local variable) within the routine. Option ignore lists name patterns that are never reported (default Sender, Value).",' + #10 +
    '      "bad": "procedure TfrmKunde.Laden(const Caption: string);\nbegin\n  Caption := Caption + '' (geladen)'';\nend;",' + #10 +
    '      "good": "procedure TfrmKunde.Laden(const ACaption: string);\nbegin\n  Caption := ACaption + '' (geladen)'';\nend;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "ignore",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [' + #10 +
    '            "Sender",' + #10 +
    '            "Value"' + #10 +
    '          ],' + #10 +
    '          "description": "Name patterns (* and ?) that are never reported."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "boolean-assign-if",' + #10 +
    '      "name": "if that only assigns True or False",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "if B then X := True else X := False (also with begin/end and the values swapped), if B then Exit(True) else Exit(False) and if B then Exit(True); followed by Exit(False); can be ' +
    'written directly. Complements bool-compare. High confidence. Quick fix: X := B, X := not B or Exit(B); negations are simplified (not B becomes B), compound conditions are wrapped in parentheses. Witho' +
    'ut a fix when comments stand inside the if.",' + #10 +
    '      "bad": "if Betrag > 0 then\n  Result := True\nelse\n  Result := False;",' + #10 +
    '      "good": "Result := Betrag > 0;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "case-insensitive-compare",' + #10 +
    '      "name": "Comparison through UpperCase or LowerCase",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "performance",' + #10 +
    '      "description": "UpperCase(A) = UpperCase(B), LowerCase(A) <> ''x'', AnsiUpperCase(...) or A.ToUpper = B.ToUpper creates two strings for one comparison. SameText (AnsiSameText for the Ansi function' +
    's and the Unicode string helpers) is shorter and faster. A literal is only accepted if the conversion does not change it; UpperCase(A) = LowerCase(B) and UpperCase(A) = ''ja'' are left alone because the' +
    'y are different mistakes. Does not replace the string helper modernisation of #71. High confidence. Quick fix: SameText(A, B) or not SameText(A, B).",' + #10 +
    '      "bad": "if UpperCase(Land) = UpperCase(Standard) then",' + #10 +
    '      "good": "if SameText(Land, Standard) then"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "magic-number",' + #10 +
    '      "name": "Number without a name in code",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "Number literals (decimal, $hex, floating point, with sign) in statements, outside const sections, types, array bounds and subranges. Allowed values are configurable; DFM coordina' +
    'tes and tests can be excluded through exclude. Off by default and low confidence: it shows up once the rule is switched on and minConfidence is low. Quick fix: Introduce constant (#50) in the const se' +
    'ction of the routine.",' + #10 +
    '      "bad": "if Tage > 42 then\n  Mahnen;",' + #10 +
    '      "good": "const\n  Mahnfrist = 42;\n...\nif Tage > Mahnfrist then\n  Mahnen;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "allowed",' + #10 +
    '          "type": "number-list",' + #10 +
    '          "default": [' + #10 +
    '            0,' + #10 +
    '            1,' + #10 +
    '            -1,' + #10 +
    '            2,' + #10 +
    '            10,' + #10 +
    '            100' + #10 +
    '          ],' + #10 +
    '          "description": "Numbers that are never reported."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "line-length",' + #10 +
    '      "name": "Line too long",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "Lines longer than the limit max (default 120 characters, matching the rulers from #710). Tabs count up to the next tab stop of format.indentSize. Lines that are only too long bec' +
    'ause of a string or, with ignoreComments, a comment are not reported. Lines over 1023 characters are always reported as an error regardless of max, because the compiler stops there (F2069). Off by def' +
    'ault. Quick fix: Wrap line after commas or before binary operators, where the pieces then fit.",' + #10 +
    '      "bad": "Ergebnis := Rechner.Berechne(Kunde.Rabattstufe, Bestellung.Positionen, Lager.Verfuegbarkeit(Artikel), Steuer.Satz(Land));",' + #10 +
    '      "good": "Ergebnis := Rechner.Berechne(Kunde.Rabattstufe, Bestellung.Positionen, Lager.Verfuegbarkeit(Artikel),\n  Steuer.Satz(Land));",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "F2069"' + #10 +
    '      ],' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "max",' + #10 +
    '          "type": "integer",' + #10 +
    '          "default": 120,' + #10 +
    '          "description": "Maximum line length in characters."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "ignoreStrings",' + #10 +
    '          "type": "boolean",' + #10 +
    '          "default": true,' + #10 +
    '          "description": "Do not report lines that are only too long because of a string."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "ignoreComments",' + #10 +
    '          "type": "boolean",' + #10 +
    '          "default": false,' + #10 +
    '          "description": "Do not report lines that are only too long because of a comment."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-class-size",' + #10 +
    '      "name": "Class with too many members",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "The class has more members than the limit (default 40): field names, methods, properties with their own type and class var. Properties that only raise visibility (property Align;' +
    ') and nested types do not count; a nested class is measured on its own. Also shown in the metrics lens above the class. Split the class or move parts into helper classes; Move class to own unit (#103)' +
    ' helps when the unit is crowded too.",' + #10 +
    '      "bad": "type\n  TfrmHaupt = class(TForm)\n    { 87 members }\n  end;",' + #10 +
    '      "good": "type\n  TfrmHaupt = class(TForm)\n    { 25 members; data access in TKundenDaten }\n  end;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "max",' + #10 +
    '          "type": "integer",' + #10 +
    '          "default": 40,' + #10 +
    '          "description": "Maximum number of members per class."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-unit-length",' + #10 +
    '      "name": "Unit too long",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "The unit has more lines than the limit (default 2000), counted up to the final end. Only units are measured, not programs or packages. Also shown in the metrics lens above the un' +
    'it name. Move classes into their own units with Move class to own unit (#103).",' + #10 +
    '      "bad": "unit Kasse.Haupt;  { 2140 lines }",' + #10 +
    '      "good": "unit Kasse.Haupt;  { 900 lines; TBeleg in Kasse.Beleg }",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "max",' + #10 +
    '          "type": "integer",' + #10 +
    '          "default": 2000,' + #10 +
    '          "description": "Maximum number of lines per unit."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-uses-count",' + #10 +
    '      "name": "Too many units in uses",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "The unit uses more units than the limit (default 30), interface and implementation together. The finding sits on the first uses. Programs and libraries are not checked, because t' +
    'heir uses lists the units of the project. Also shown in the metrics lens above uses. Many dependencies usually mean the unit does too much; Move class to own unit (#103) splits it.",' + #10 +
    '      "bad": "uses\n  { 34 units in interface and implementation }",' + #10 +
    '      "good": "uses\n  { 12 units; reports in Kasse.Berichte }",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "max",' + #10 +
    '          "type": "integer",' + #10 +
    '          "default": 30,' + #10 +
    '          "description": "Maximum number of units in all uses clauses."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-inheritance-depth",' + #10 +
    '      "name": "Inheritance too deep",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "The class has more ancestors of its own than the limit (default 5). Ancestors from RTL, VCL, FMX and other libraries do not count (by unit name or because the index loaded them f' +
    'rom the library path), nor does TObject. Ancestors are looked up in the file and in the symbol index. If the chain breaks at an unknown ancestor before reaching a library, the value is a lower bound a' +
    'nd the message says at least; it is only reported when that bound already exceeds the limit. Units of a library itself are not checked. The finding sits on the class name; the metrics lens shows the d' +
    'epth next to the member count.",' + #10 +
    '      "bad": "TBasis = class(TForm) ... TStufe6 = class(TStufe5)  { 6 own ancestors }",' + #10 +
    '      "good": "TStufe2 = class(TBasis)\n  FDruck: IDruck;  { composition instead of more levels }",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "max",' + #10 +
    '          "type": "integer",' + #10 +
    '          "default": 5,' + #10 +
    '          "description": "Highest allowed number of own ancestors."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "public-field",' + #10 +
    '      "name": "Public field",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "Fields in the public or published section of a class. The section without a visibility keyword only counts for classes without an ancestor or with TObject, because the form desig' +
    'ner puts its fields there. Records are excluded unless includeRecords is set; class var is not reported. Off by default. Quick fix: Encapsulate field moves the field as FName into a private section at' +
    ' the end of the class and adds property Name read FName write FName in the old section; accesses from outside stay valid.",' + #10 +
    '      "bad": "TKunde = class\npublic\n  Name: string;\nend;",' + #10 +
    '      "good": "TKunde = class\nprivate\n  FName: string;\npublic\n  property Name: string read FName write FName;\nend;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "includeRecords",' + #10 +
    '          "type": "boolean",' + #10 +
    '          "default": false,' + #10 +
    '          "description": "Also report fields of records."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "legacy-tlist",' + #10 +
    '      "name": "Non-generic list with cast",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "information",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "A non-generic TList (System.Classes) or TObjectList (System.Contnrs) whose items are read with a cast: T(List[I]), T(List.Items[I]), T(List.First), List[I] as T and so on. TList<' +
    'T> and TObjectList<T> from System.Generics.Collections check the type at compile time and need no cast. The rule reports once per list, at its declaration when it is in this file, otherwise at the fir' +
    'st cast; with several target types, all of them are named. Only when name resolution finds the list type and the target type for sure; casts to Pointer are ignored. Off by default; for code that must ' +
    'still compile with old Delphi versions, use exclude. Quick fix (#1105): converts the list to TList<T> or TObjectList<T> in one step: declaration, every Create (arguments are kept), every cast and Syst' +
    'em.Generics.Collections in the uses clause; Contnrs is removed when nothing else uses it. Only when every read has the same cast and no member without a generic counterpart is used (Sort with TListSor' +
    'tCompare, Assign with TListAssignOp, List), no Pointer or Integer values are stored, Add, Extract, Remove and IndexOf get T, and the list is not passed on. If the list is visible outside the unit, the' +
    ' fix also rewrites the other units of the project group or is not offered; \"fix all\" (source.fixAll) never applies such fixes. Otherwise the finding hover names the reason. Stacks and queues: legacy' +
    '-stack-queue.",' + #10 +
    '      "bad": "FPositionen: TList;\n...\nPos := TPosition(FPositionen[I]);",' + #10 +
    '      "good": "FPositionen: TList<TPosition>;\n...\nPos := FPositionen[I];"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "legacy-stack-queue",' + #10 +
    '      "name": "Non-generic stack or queue with cast",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "information",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "A non-generic TStack, TQueue, TObjectStack or TObjectQueue (System.Contnrs) whose items are read with a cast: T(Stack.Pop), T(Stack.Peek), Queue.Pop as T and so on. TStack<T>, TQ' +
    'ueue<T>, TObjectStack<T> and TObjectQueue<T> from System.Generics.Collections check the type at compile time and need no cast. Like legacy-tlist, the rule reports once per stack or queue, at its decla' +
    'ration when it is in this file, otherwise at the first cast; with several target types, all of them are named. Only when name resolution finds the type and the target type for sure; casts to Pointer a' +
    're ignored. Off by default; for code that must still compile with old Delphi versions, use exclude. Quick fix: converts in one step like legacy-tlist; for queues Push becomes Enqueue and Pop becomes D' +
    'equeue. TObjectStack<T> and TObjectQueue<T> own their objects, the Contnrs classes do not: the fix therefore creates them with Create(False) and reads with Extract, because Pop and Dequeue are procedu' +
    'res there that free the object. Without a Create in the unit, with different casts or with members without a generic counterpart (AtLeast) there is no fix; the finding hover names the reason.",' + #10 +
    '      "bad": "FOffen: TObjectStack;\n...\nKnoten := TKnoten(FOffen.Pop);",' + #10 +
    '      "good": "FOffen: TObjectStack<TKnoten>;\n...\nFOffen := TObjectStack<TKnoten>.Create(False);\n...\nKnoten := FOffen.Extract;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "global-variable",' + #10 +
    '      "name": "Global variable in interface",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "var or threadvar in the interface section of a unit: every unit that uses it can read and change the value. The form variable created by the designer (frmMain: TfrmMain, for clas' +
    'ses derived from TForm, TFrame, TDataModule or any class in a unit with a form file) is excluded unless includeFormVariables is set. Off by default. Move the variable into the implementation section a' +
    'nd offer a function or property instead.",' + #10 +
    '      "bad": "interface\nvar\n  AktuellerBenutzer: TBenutzer;",' + #10 +
    '      "good": "interface\nfunction AktuellerBenutzer: TBenutzer;\nimplementation\nvar\n  GBenutzer: TBenutzer;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "includeFormVariables",' + #10 +
    '          "type": "boolean",' + #10 +
    '          "default": false,' + #10 +
    '          "description": "Also report the form variables created by the designer."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "commented-out-code",' + #10 +
    '      "name": "Commented-out code",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "At least minLines consecutive comment lines (// per line or a multi-line { } comment) that parse as statements, declarations or class members. Prose at the start and end of the b' +
    'lock is ignored, and at least half the lines must look like code (;, :=, begin, end, then, do). XMLDoc (///) and comments before the first token (license headers) are never reported. Confidence medium' +
    '. Version control keeps the old code; the fix removes the lines.",' + #10 +
    '      "bad": "Speichern;\n// if Kunde.Aktiv then\n//   Kunde.Speichern;\n// Log(''gespeichert'');",' + #10 +
    '      "good": "Speichern;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "minLines",' + #10 +
    '          "type": "integer",' + #10 +
    '          "default": 3,' + #10 +
    '          "description": "Minimum number of consecutive commented-out code lines."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "default-parameter",' + #10 +
    '      "name": "Default parameter instead of overload",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "A parameter with a default value (Count: Integer = 10). For teams that prefer overloads: default values end up compiled into the caller, do not change with the library and do not' +
    ' mix well with overloads. Reported once per declaration (class member, interface section, forward or a routine only in the implementation part); the body of a declaration is not reported again. The qu' +
    'ick fix inserts one overload per omitted trailing default parameter before the declaration, each forwarding with the default value, removes the default values (also repeated ones in the body) and adds' +
    ' overload. No fix when the signature is given from outside (virtual, dynamic, abstract, override, message, external, interface types), when the name is used as a value (@Routine, method pointer), when' +
    ' an overload of the same name exists, inside conditional compilation, or when the body cannot be found unambiguously.",' + #10 +
    '      "bad": "procedure Exportieren(const Datei: string; MitKopf: Boolean = True);",' + #10 +
    '      "good": "procedure Exportieren(const Datei: string); overload;\nprocedure Exportieren(const Datei: string; MitKopf: Boolean); overload;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "empty-routine",' + #10 +
    '      "name": "Empty routine",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "A method or routine whose body has neither a statement nor a comment (nor a compiler directive). Either the content is missing or the method can go. Not reported: virtual and dyn' +
    'amic methods (a stand-in for abstract in base classes), message handlers, methods of classes that list interfaces (the compiler requires every interface method), event handlers named in the form file ' +
    '(the IDE removes empty ones when saving) and bodies with a comment, such as overrides that deliberately do nothing. Quick fixes: insert a comment between begin and end; remove the method (declaration ' +
    'with its XML doc and body) only for private methods and routines without a declaration in the interface part that occur nowhere else in the file and fulfil no signature from outside.",' + #10 +
    '      "bad": "procedure TImport.Pruefen;\nbegin\nend;",' + #10 +
    '      "good": "procedure TImport.Pruefen;\nbegin\n  // Absichtlich leer.\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "write-only-property",' + #10 +
    '      "name": "Property without read",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "A property has write but no read. It cannot be shown in the Object Inspector or read in the debugger and confuses callers. Properties without a type are skipped (they republish a' +
    'n inherited property whose read comes from the ancestor), as are properties with an attribute from allowAttributes (with or without the Attribute suffix). Quick fix: add read FName when the type decla' +
    'res a field FName of the same type. Reading such a property is reported by readonly-property-assigned.",' + #10 +
    '      "bad": "property Passwort: string write SetPasswort;",' + #10 +
    '      "good": "property Passwort: string read FPasswort write SetPasswort;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "allowAttributes",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [],' + #10 +
    '          "description": "Attributes that allow a property without read."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "xmldoc-mismatch",' + #10 +
    '      "name": "XMLDoc does not match the signature",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "A /// comment does not match its declaration or is not well-formed XML, like the compiler warnings W1201 to W1208 with XML documentation enabled. Reported: <param> for a paramete' +
    'r that does not exist; missing <param> when the block describes parameters at all (like W1208, ''but other parameters do''); with checkReturns, <returns> on a routine without a result and missing <retur' +
    'ns> on a function whose block describes parameters. <inheritdoc/> fills in what is missing. Also ''<'' and ''&'' outside tags and entities, unknown entities, attribute values without quotes, unclosed and ' +
    'stray end tags, and cref targets that do not exist (W1206, only with an index and when every unit in uses is known; generic targets, unit names and types with unknown ancestors stay silent). With requ' +
    'irePublic, public and published methods and properties of types in the interface section without a /// comment are reported too (not override, not properties without a type). Quick fixes: rename unkno' +
    'wn <param> in order to the missing ones, add the rest as empty lines in signature order, remove surplus <param> and stray <returns>; escape the character, add quotes, add or remove the end tag, write ' +
    'an unknown empty tag like TList<T> as text; set cref to the most similar symbol; generate the comment skeleton.",' + #10 +
    '      "bad": "/// <summary>Sucht einen Kunden.</summary>\n/// <param name=\"Nummer\">Kundennummer</param>\nfunction Suchen(const Id: Integer; Aktive: Boolean): TKunde;",' + #10 +
    '      "good": "/// <summary>Sucht einen Kunden.</summary>\n/// <param name=\"Id\">Kundennummer</param>\n/// <param name=\"Aktive\"></param>\nfunction Suchen(const Id: Integer; Aktive: Boolean): TKunde' +
    ';",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "W1201",' + #10 +
    '        "W1202",' + #10 +
    '        "W1203",' + #10 +
    '        "W1204",' + #10 +
    '        "W1205",' + #10 +
    '        "W1206",' + #10 +
    '        "W1207",' + #10 +
    '        "W1208"' + #10 +
    '      ],' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "requirePublic",' + #10 +
    '          "type": "boolean",' + #10 +
    '          "default": false,' + #10 +
    '          "description": "Also report public members without XMLDoc."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "checkReturns",' + #10 +
    '          "type": "boolean",' + #10 +
    '          "default": true,' + #10 +
    '          "description": "Check <returns>."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "queue-nil-in-package",' + #10 +
    '      "name": "TThread.Queue(nil, …) in a package",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "threads",' + #10 +
    '      "description": "TThread.Queue(nil, …) or TThread.ForceQueue(nil, …) in a unit of a design-time or runtime package: the entry belongs to no thread, so nobody removes it when the package is unload' +
    'ed, and CheckSynchronize may call it afterwards in memory that no longer holds the code. Package units are recognized through the .dpk or .dproj of the loaded project (a .dpk on its own without projec' +
    't). A line with the comment from okMarker (default mainthread-ok) is exempt. High confidence. Quick fix: rewrite to the wrapper from the wrapper option (default TAtlasMainThread.Queue, ForceQueue for ' +
    'ForceQueue); with a parenthesis the wrapper text is put in front of the remaining arguments. ForceQueue with a delay gets no quick fix. The command-line linter reads the .dpk files below the checked f' +
    'older. Does the same as Tools/Check-MainThreadQueue.ps1 for any plugin project; the script stays for checks without the Atlas server.",' + #10 +
    '      "bad": "TThread.Queue(nil,\n  procedure\n  begin\n    FPanel.Aktualisieren;\n  end);",' + #10 +
    '      "good": "TAtlasMainThread.Queue(\n  procedure\n  begin\n    FPanel.Aktualisieren;\n  end);",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "wrapper",' + #10 +
    '          "type": "string",' + #10 +
    '          "default": "TAtlasMainThread.Queue",' + #10 +
    '          "description": "Replacement for TThread.Queue(nil, in the quick fix."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "okMarker",' + #10 +
    '          "type": "string",' + #10 +
    '          "default": "mainthread-ok",' + #10 +
    '          "description": "Comment that exempts a line."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "ota-notifier-not-removed",' + #10 +
    '      "name": "IDE notifier without RemoveNotifier",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "packages",' + #10 +
    '      "description": "AddNotifier on IOTAServices, IOTAEditorServices, IOTAModule and so on (or another pair from registerPairs) whose index never reaches RemoveNotifier: the call is a statement witho' +
    'ut assignment, or the variable it is assigned to is never passed to RemoveNotifier in the unit (in finalization, a destructor or Destroyed). The IDE then calls the notifier after the package is unload' +
    'ed, in memory that no longer holds the code. Register… calls inside the procedure Register are exempt: the IDE removes those wizards itself. Medium confidence. Quick fix in methods: keep the index in ' +
    'a field (FNotifierIndex in the private section) and add RemoveNotifier to the destructor, which is created if missing; in procedures of the unit: a global variable initialized with -1 and RemoveNotifi' +
    'er in finalization. No quick fix when the receiver is a parameter or local variable.",' + #10 +
    '      "bad": "procedure Register;\nbegin\n  (BorlandIDEServices as IOTAServices).AddNotifier(TSpeicherNotifier.Create);\nend;",' + #10 +
    '      "good": "var\n  NotifierIndex: Integer = -1;\n\nprocedure Register;\nbegin\n  NotifierIndex := (BorlandIDEServices as IOTAServices).AddNotifier(TSpeicherNotifier.Create);\nend;\n\ninitialization' +
    '\n\nfinalization\n  if NotifierIndex >= 0 then\n    (BorlandIDEServices as IOTAServices).RemoveNotifier(NotifierIndex);",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "registerPairs",' + #10 +
    '          "type": "json",' + #10 +
    '          "default": [' + #10 +
    '            {' + #10 +
    '              "open": "AddNotifier",' + #10 +
    '              "close": "RemoveNotifier"' + #10 +
    '            },' + #10 +
    '            {' + #10 +
    '              "open": "RegisterPackageWizard",' + #10 +
    '              "close": "RemoveWizard"' + #10 +
    '            }' + #10 +
    '          ],' + #10 +
    '          "description": "Pairs of the Open Tools API as [{\"open\": \"AddNotifier\", \"close\": \"RemoveNotifier\"}]; replaces the default."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dunitx-test-without-assert",' + #10 +
    '      "name": "DUnitX test without assert",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "packages",' + #10 +
    '      "description": "A [Test] or [TestCase] method that calls no check, neither itself nor through methods of the same class or routines of the unit: it is always green. Calls matching assertPatterns' +
    ' (default Assert.*, WillRaise*, Check*), System.Assert and calls on classes with Assert in their name (TRuleAssert.Reports) count as checks. Tests with [WillRaise] or [Ignore] stay silent. High confid' +
    'ence. Quick fixes: insert Assert.Pass as a placeholder, or jump to the method.",' + #10 +
    '      "bad": "[Test]\nprocedure TImportTests.LeereDateiWirdGelesen;\nbegin\n  FImport.Laden(''leer.csv'');\nend;",' + #10 +
    '      "good": "[Test]\nprocedure TImportTests.LeereDateiWirdGelesen;\nbegin\n  FImport.Laden(''leer.csv'');\n  Assert.AreEqual(0, FImport.Anzahl);\nend;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "assertPatterns",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [' + #10 +
    '            "Assert.*",' + #10 +
    '            "WillRaise*",' + #10 +
    '            "Check*"' + #10 +
    '          ],' + #10 +
    '          "description": "Calls that count as a check, as patterns with * and ?; replaces the default."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "event-call-without-assigned",' + #10 +
    '      "name": "Event called without Assigned check",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "FOnChange(Self) or OnChange(Self) is called in a method of the class without Assigned(FOnChange) or FOnChange <> nil guarding the call: without a handler an access violation foll' +
    'ows. Events are fields and properties of the class with a method pointer or reference type (procedure ... of object, reference to ..., TNotifyEvent, TProc/TFunc, types ending in Event, procedural type' +
    's of the unit or the index). Guards: the then branch of a condition with Assigned (also while), the else branch of not Assigned, \"Assigned(F) and\" before the call, or \"if not Assigned(F) then Exit/' +
    'raise\" before it, including a flag variable or a parameterless method of the class whose Result contains Assigned(F). Fields that a constructor sets to a value (injected dependencies such as FReadTex' +
    't := AReadText), properties reading them and local names that shadow the event stay silent. High confidence. Quick fix: wrap the call in \"if Assigned(F) then\" when it is a statement of its own in a ' +
    'block.",' + #10 +
    '      "bad": "procedure TZaehler.Erhoehen;\nbegin\n  Inc(FWert);\n  FOnChange(Self);\nend;",' + #10 +
    '      "good": "procedure TZaehler.Erhoehen;\nbegin\n  Inc(FWert);\n  if Assigned(FOnChange) then\n    FOnChange(Self);\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "owned-item-freed",' + #10 +
    '      "name": "Item of an owning list freed as well",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "An item of a TObjectList/TObjectList<T> (OwnsObjects, default True) or of a TObjectDictionary with doOwnsValues is freed with Free, FreeAndNil, Destroy or DisposeOf, directly (Li' +
    'st[I].Free, List.Items[I].Free) or through a variable taken from List[I], List.First/Last or a for-in loop over the list or Dictionary.Values. The list frees the item itself on Delete, Remove, Clear, ' +
    'an assignment to List[I], or at the latest when it is freed: a double free. A list is owning when the unit creates it that way (TObjectList without False, TObjectDictionary with doOwnsValues) or decla' +
    'res it as TObjectList without creating it, and no OwnsObjects := False follows. Extract in the same routine keeps the rule silent. High confidence. Quick fixes: remove the Free (the whole loop when it' +
    ' only frees), Delete or Remove instead of Free, Extract instead of Remove.",' + #10 +
    '      "bad": "Auftraege := TObjectList<TAuftrag>.Create;\n…\nAuftraege[I].Free;\nAuftraege.Delete(I);",' + #10 +
    '      "good": "Auftraege := TObjectList<TAuftrag>.Create;\n…\nAuftraege.Delete(I);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "create-without-assignment",' + #10 +
    '      "name": "Object created and lost at once",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "TStringList.Create; as a statement of its own: the object is created but stored nowhere and never freed (memory leak). Silent for components with an owner (first argument Self, O' +
    'wner, AOwner, Application, or a TComponent descendant with an argument other than nil), threads (they free themselves with FreeOnTerminate), records, unknown classes with arguments and classes listed ' +
    'in selfRegistering. High confidence. Quick fix: assign to a new local variable and wrap the following statements of the block in try/finally with Free.",' + #10 +
    '      "bad": "procedure TImport.Starten;\nbegin\n  TImportProtokoll.Create;\n  Laden;\nend;",' + #10 +
    '      "good": "procedure TImport.Starten;\nvar\n  ImportProtokoll: TImportProtokoll;\nbegin\n  ImportProtokoll := TImportProtokoll.Create;\n  try\n    Laden;\n  finally\n    ImportProtokoll.Free;\n  e' +
    'nd;\nend;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "selfRegistering",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [],' + #10 +
    '          "description": "Classes that register themselves in their constructor, as patterns with * and ?; Create as a statement stays silent for them."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "raw-memory-leak",' + #10 +
    '      "name": "GetMem or New without release",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "A local variable receives memory from GetMem, AllocMem, ReallocMem, GetMemory, New, StrAlloc or StrNew, but the routine never releases it with FreeMem, FreeMemory, Dispose, StrDi' +
    'spose or ReallocMem(P, 0), and the pointer neither leaves the routine nor is stored: not returned (Result, Exit), not assigned to another variable or field, not passed by address (@P), not handed to a' +
    ' method that keeps it (Add, Insert, Push …), not captured by an anonymous method and not used in a local routine. Passing the pointer to read or fill it (Checksum(P, N), Stream.ReadBuffer(P^, N)) is f' +
    'ine; a routine whose name contains Free, Frei, Release, Dispose, Destroy or Dealloc counts as the release. A release without try/finally is reported by pair-without-finally. Medium confidence. Quick f' +
    'ix: wrap the following statements of the block in try … finally with the matching release.",' + #10 +
    '      "bad": "GetMem(Puffer, Groesse);\nStrom.ReadBuffer(Puffer^, Groesse);\nErgebnis := Pruefsumme(Puffer, Groesse);",' + #10 +
    '      "good": "GetMem(Puffer, Groesse);\ntry\n  Strom.ReadBuffer(Puffer^, Groesse);\n  Ergebnis := Pruefsumme(Puffer, Groesse);\nfinally\n  FreeMem(Puffer);\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "stringlist-objects-leak",' + #10 +
    '      "name": "Objects in a TStringList without ownership",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "AddObject or InsertObject puts a newly created object (T.Create(…) directly, or a local variable created that way and otherwise only read) into a TStringList (or THashedStringLis' +
    't) that the unit creates without OwnsObjects, or into the Items of a TListBox, TComboBox, TCheckListBox, TComboBoxEx or TColorListBox field; nobody frees these objects. A list is owning with TStringLi' +
    'st.Create(True) or OwnsObjects := True. Silent when a routine of the unit reads List.Objects[…] and frees something, when the list is passed on (FreeObjects(List), assigned elsewhere), when the object' +
    ' has an owner (Self, Owner, AOwner, Application or a TComponent descendant with an argument) and for lists not created in the unit. Medium confidence. Quick fix: TStringList.Create(True) (also instead' +
    ' of Create(False)), with other constructors OwnsObjects := True after the creation; none for control items.",' + #10 +
    '      "bad": "FKunden := TStringList.Create;\n…\nFKunden.AddObject(K.Name, TKunde.Create(K));",' + #10 +
    '      "good": "FKunden := TStringList.Create(True);\n…\nFKunden.AddObject(K.Name, TKunde.Create(K));"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "message-handler-without-inherited",' + #10 +
    '      "name": "Message handler without inherited",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "A method with message WM_... or CM_... calls neither inherited nor DefaultHandler (or DefWindowProc, CallWindowProc). The default handling of the VCL or Windows is lost: no reali' +
    'gnment on WM_SIZE, no closing on WM_CLOSE, no painting on WM_PAINT. The message names the consequence for common messages. Silent for classes without an ancestor, for messages listed in swallow (defau' +
    'lt WM_ERASEBKGND) and for handlers that set Msg.Result themselves (deliberate answer such as MA_NOACTIVATE). Medium confidence. Quick fix: insert inherited; at the start.",' + #10 +
    '      "bad": "procedure TfrmHaupt.WMSize(var Msg: TWMSize);\nbegin\n  AnordnungAnpassen;\nend;",' + #10 +
    '      "good": "procedure TfrmHaupt.WMSize(var Msg: TWMSize);\nbegin\n  inherited;\n  AnordnungAnpassen;\nend;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "swallow",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [' + #10 +
    '            "WM_ERASEBKGND"' + #10 +
    '          ],' + #10 +
    '          "description": "Messages that may be handled without inherited; replaces the default."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "string-index-base",' + #10 +
    '      "name": "String index from 0 or Pos result compared with -1",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "The classic string routines count from 1: Copy(S, 0, N) and Insert(T, S, 0) only work like 1 by chance, Delete(S, 0, N) deletes nothing. The string must be known: declared type i' +
    'n the file, literal, or .Text/.Caption; dynamic arrays (0-based) stay silent. Pos, PosEx and AnsiPos return 0 for no match: Pos(...) > -1, >= 0 and <> -1 are always true, = -1 and < 0 never. Conversel' +
    'y S.IndexOf(...) > 0 or >= 1 misses a match at the start, < 1 or <= 0 counts it as not found (medium confidence; LastIndexOf stays silent, where > 0 usually means \"not at the start\"). High confidenc' +
    'e for Delete and Pos. Quick fix: start value 1 or the corrected comparison (> 0, = 0, >= 0, < 0).",' + #10 +
    '      "bad": "if Pos('';'', Zeile) > -1 then\n  Felder := Copy(Zeile, 0, Pos('';'', Zeile) - 1);",' + #10 +
    '      "good": "if Pos('';'', Zeile) > 0 then\n  Felder := Copy(Zeile, 1, Pos('';'', Zeile) - 1);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "delimited-text-without-strict",' + #10 +
    '      "name": "DelimitedText without StrictDelimiter",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "List.DelimitedText := ... after List.Delimiter := ... in the same routine without StrictDelimiter being set: DelimitedText then also splits at spaces, ''Max Muster;Berlin'' becomes' +
    ' three entries instead of two. For fields, StrictDelimiter anywhere in the unit counts (often in the constructor); StrictDelimiter := False is deliberate and stays silent, as does DelimitedText withou' +
    't a Delimiter of its own. High confidence. Quick fix: insert StrictDelimiter := True; before the assignment.",' + #10 +
    '      "bad": "Teile.Delimiter := '';'';\nTeile.DelimitedText := Zeile;",' + #10 +
    '      "good": "Teile.Delimiter := '';'';\nTeile.StrictDelimiter := True;\nTeile.DelimitedText := Zeile;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "self-as-interface-in-constructor",' + #10 +
    '      "name": "Self passed as interface during construction",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "Self is passed as an interface while reference counting can already free the object. Only two real error cases are reported: (1) a class with its own reference counting (an _Rele' +
    'ase in the class chain frees the object, no class overrides NewInstance, the chain is known up to TObject) passes Self as an interface in a constructor or in AfterConstruction: the counter goes from 0' +
    ' to 1 and back to 0, the object is destroyed before construction ends. (2) A TInterfacedObject descendant passes Self as an interface in AfterConstruction after inherited: inherited AfterConstruction ' +
    'has already removed the protective count from NewInstance. In the constructor of a TInterfacedObject descendant Self is protected and the rule stays silent. Passing counts as Self as IX, IX(Self), an ' +
    'argument whose parameter is an interface in all known overloads, and an assignment to an interface variable. High confidence. Quick fix in case 2: move the statement before inherited.",' + #10 +
    '      "bad": "procedure TBeobachter.AfterConstruction;\nbegin\n  inherited;\n  FQuelle.Anmelden(Self);\nend;",' + #10 +
    '      "good": "procedure TBeobachter.AfterConstruction;\nbegin\n  FQuelle.Anmelden(Self);\n  inherited;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "null-compare",' + #10 +
    '      "name": "Comparison with Null instead of VarIsNull or IsNull",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "robustness",' + #10 +
    '      "description": "X = Null or X <> Null compares a variant with Null. The result depends on the global System.Variants.NullEqualityRule: with the default ncrLoose the comparison works as expected,' +
    ' with ncrStrict it is never true and with ncrError it raises an exception. A library, a test framework or another part of the project can change the rule. VarIsNull(X) and Field.IsNull check independe' +
    'ntly of it. Reported only where the comparison stands on its own (condition, argument, assignment); not X = Null binds as (not X) = Null and gets no quick fix. High confidence. Quick fix: Field.IsNull' +
    ' for X.Value on FieldByName, FindField, Fields[...], ParamByName, Params[...] or a field of type T...Field/T...Param, otherwise VarIsNull(X); with <> preceded by not.",' + #10 +
    '      "bad": "if qryKunde.FieldByName(''Geburtstag'').Value = Null then\n  Alter := 0;",' + #10 +
    '      "good": "if qryKunde.FieldByName(''Geburtstag'').IsNull then\n  Alter := 0;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unchecked-enum-cast",' + #10 +
    '      "name": "Number cast to enumeration without check",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "TStatus(N) with an enumeration type declared in the file or the index, where N comes from a call listed in the option sources (FieldByName, ReadInteger, AsInteger, StrToInt): dir' +
    'ectly in the argument or via a variable that is not read (checked) between its assignment and the cast. A value outside the range yields an invalid enumeration value that falls through case statements' +
    '. EnsureRange, Min or Max in the argument count as a check; constants, arithmetic and unknown types stay silent. For enumerations with explicit ordinal values the range is given as Ord(Low(T))..Ord(Hi' +
    'gh(T)). Medium confidence. Quick fix for a direct source in a statement of its own: helper variable, InRange check with raise EConvertError before it, System.Math added to uses.",' + #10 +
    '      "bad": "Status := TStatus(qry.FieldByName(''Status'').AsInteger);",' + #10 +
    '      "good": "Wert := qry.FieldByName(''Status'').AsInteger;\nif not InRange(Wert, Ord(Low(TStatus)), Ord(High(TStatus))) then\n  raise EConvertError.CreateFmt(''Ungültiger Wert %d für TStatus'', [Wert])' +
    ';\nStatus := TStatus(Wert);",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "sources",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [' + #10 +
    '            "FieldByName",' + #10 +
    '            "ReadInteger",' + #10 +
    '            "AsInteger",' + #10 +
    '            "StrToInt"' + #10 +
    '          ],' + #10 +
    '          "description": "Calls whose result counts as unchecked."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "createprocess-readonly-commandline",' + #10 +
    '      "name": "CreateProcess with a read-only command line",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "CreateProcess (CreateProcessW) and CreateProcessAsUser write into the buffer of lpCommandLine. A PChar on memory that cannot be written causes an access violation. Reported for P' +
    'Char(...)/PWideChar(...) on: a string literal or constant; a concatenation of exactly one literal and one value (if the value is empty, the RTL returns the literal itself); a local string variable who' +
    'se last assignment before the call is one of these, without UniqueString afterwards; a string parameter (medium confidence, the caller may pass a literal). Function results such as Format and concaten' +
    'ations with several parts are writable heap strings and stay silent, as does CreateProcessA, which copies the command line itself. Quick fix: copy the command line into a local variable and call Uniqu' +
    'eString; for a variable, UniqueString before the statement. No quick fix in loop conditions.",' + #10 +
    '      "bad": "CreateProcess(nil, PChar(''notepad.exe '' + Datei), nil, nil, False, 0, nil, nil, SI, PI);",' + #10 +
    '      "good": "Befehl := ''notepad.exe '' + Datei;\nUniqueString(Befehl);\nCreateProcess(nil, PChar(Befehl), nil, nil, False, 0, nil, nil, SI, PI);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "form-access-before-create",' + #10 +
    '      "name": "Access to a form that is not created yet",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "The constructor, AfterConstruction or the OnCreate handler of an automatically created form or data module uses the global variable of another form that the .dpr creates later wi' +
    'th Application.CreateForm. The variable is still nil at that point. The order comes from the .dpr of the project the unit belongs to; the OnCreate handler from the form file (FormCreate or DataModuleC' +
    'reate without one). Silent when the routine checks the variable (Assigned, comparison with nil), assigns it itself, creates it with CreateForm or declares a local name of the same name, and for forms ' +
    'that are not created automatically. Each variable is reported once per routine. Medium confidence. No quick fix: change the order in the .dpr or move the access to OnShow.",' + #10 +
    '      "bad": "procedure TfrmHaupt.FormCreate(Sender: TObject);\nbegin\n  lblNutzer.Caption := dmDaten.Benutzer;\nend;",' + #10 +
    '      "good": "// .dpr: Application.CreateForm(TdmDaten, dmDaten) before TfrmHaupt\nprocedure TfrmHaupt.FormCreate(Sender: TObject);\nbegin\n  lblNutzer.Caption := dmDaten.Benutzer;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "except-handler-order",' + #10 +
    '      "name": "General exception handler before a specific one",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "exceptions",' + #10 +
    '      "description": "In a try..except with several on handlers the first matching handler wins. A handler for a class that an earlier handler already catches is never reached: its code is dead and th' +
    'e special treatment never runs. Reported when an earlier handler names the same class, an ancestor of it, Exception (covers every exception class) or TObject. Ancestors come from the unit, the project' +
    ' index and a table of known RTL, VCL and FireDAC exception classes (for example EStreamError > EFOpenError, EIntError > ERangeError); unknown classes are only compared with Exception and TObject. Quic' +
    'k fix: move the specific handler before the general one (only when both handlers stand on their own lines). A duplicate handler for the same class is reported without a quick fix.",' + #10 +
    '      "bad": "except\n  on E: Exception do\n    Protokoll(E.Message);\n  on E: EConvertError do\n    ShowMessage(''Ungültige Zahl'');\nend;",' + #10 +
    '      "good": "except\n  on E: EConvertError do\n    ShowMessage(''Ungültige Zahl'');\n  on E: Exception do\n    Protokoll(E.Message);\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "reraise-exception-object",' + #10 +
    '      "name": "raise E instead of raise in a handler",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "exceptions",' + #10 +
    '      "description": "raise E; in an on E: … handler raises the caught exception object again as a new raise. The RTL does not free the object twice, but the exception now starts at the handler: Excep' +
    'tAddr and the call stack of tools such as madExcept or JclDebug point to the handler instead of the original fault, and the original location is lost. raise; re-raises the current exception unchanged.' +
    ' Also reported for raise E at …, then without a quick fix. Silent when the handler takes the object over with AcquireExceptionObject or assigns a new object to the variable, inside anonymous methods a' +
    'nd for handlers without a variable name. High confidence. Quick fix: raise E; → raise;.",' + #10 +
    '      "bad": "except\n  on E: EDatenbank do\n  begin\n    Protokoll(E.Message);\n    raise E;\n  end;\nend;",' + #10 +
    '      "good": "except\n  on E: EDatenbank do\n  begin\n    Protokoll(E.Message);\n    raise;\n  end;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "blocking-call-in-main-thread",' + #10 +
    '      "name": "Blocking call in the main thread",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "threads",' + #10 +
    '      "description": "Sleep, WaitFor, WaitForSingleObject, WaitForMultipleObjects or Wait in methods of forms and frames (classes that inherit from TForm, TCustomForm, TFrame or TCustomFrame) and in e' +
    'vent handlers (methods with a Sender parameter) outside thread classes. The user interface freezes while the call waits; if the other thread waits for Synchronize, the program hangs. WaitFor without a' +
    ' timeout on a variable names the risk of the Synchronize deadlock. Sleep, WaitForSingleObject and WaitForMultipleObjects count only without a receiver (or with Winapi.Windows), WaitFor and Wait only o' +
    'n a receiver. A literal timeout below maxSleepMs (Sleep(10), WaitForSingleObject(H, 0)) stays silent, except a short Sleep in a waiting loop without Application.ProcessMessages. Anonymous methods are ' +
    'skipped (TTask.Run, TThread.Queue), nested routines belong to their method. Medium confidence. No quick fix: move the work into TTask.Run and report the result with TThread.Queue.",' + #10 +
    '      "bad": "procedure TfrmHaupt.btnExportClick(Sender: TObject);\nbegin\n  FExport.Start;\n  FExport.WaitFor;\nend;",' + #10 +
    '      "good": "procedure TfrmHaupt.btnExportClick(Sender: TObject);\nbegin\n  btnExport.Enabled := False;\n  TTask.Run(\n    procedure\n    begin\n      FExport.Ausfuehren;\n      TThread.Queue(nil, p' +
    'rocedure begin btnExport.Enabled := True; end);\n    end);\nend;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "maxSleepMs",' + #10 +
    '          "type": "integer",' + #10 +
    '          "default": 50,' + #10 +
    '          "description": "Literal timeouts below this value (milliseconds) are not reported; a short Sleep in a waiting loop still is."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "calls",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [' + #10 +
    '            "Sleep",' + #10 +
    '            "WaitFor",' + #10 +
    '            "WaitForSingleObject",' + #10 +
    '            "WaitForMultipleObjects",' + #10 +
    '            "Wait"' + #10 +
    '          ],' + #10 +
    '          "description": "Calls that block. Other names are reported regardless of their arguments."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "thread-loop-without-terminated",' + #10 +
    '      "name": "Thread loop without Terminated",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "threads",' + #10 +
    '      "description": "A while or repeat loop in TThread.Execute, or in a method of the thread class that is only called from there (also through other such methods, including nested routines), does no' +
    't check Terminated. Terminate then has no effect, and WaitFor or Free hang when the program shuts down. Reported for endless loops (while True, until False) and for waiting loops with Sleep, WaitFor, ' +
    'WaitForSingleObject, WaitForMultipleObjects, MsgWaitForMultipleObjects, Wait or Yield whose condition and body never mention Terminated or CheckTerminated. Thread classes come from the unit and the in' +
    'dex. Bounded loops, for loops, anonymous methods and classes that override TerminatedSet (they end their loops another way) stay silent. High confidence. Quick fix: add Terminated to the loop conditio' +
    'n (while True → while not Terminated, otherwise and not Terminated; until False → until Terminated, otherwise or Terminated).",' + #10 +
    '      "bad": "procedure TPoller.Execute;\nbegin\n  while True do\n  begin\n    Abfragen;\n    Sleep(1000);\n  end;\nend;",' + #10 +
    '      "good": "procedure TPoller.Execute;\nbegin\n  while not Terminated do\n  begin\n    Abfragen;\n    Sleep(1000);\n  end;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "anonymous-thread-not-started",' + #10 +
    '      "name": "Anonymous thread never started",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "threads",' + #10 +
    '      "description": "TThread.CreateAnonymousThread(…) creates the thread suspended with FreeOnTerminate set. Without Start the thread never runs, and because it never terminates it is never freed eit' +
    'her. Reported for the call as a statement of its own and for a local variable (also an inline variable) that is never started with Start or Resume and not passed on (argument, assignment, Result, fiel' +
    'd). Setting properties such as FreeOnTerminate or OnTerminate does not count as passing on. High confidence. Quick fix: append .Start; for a variable, T.Start; after the last statement of the same blo' +
    'ck that mentions it.",' + #10 +
    '      "bad": "TThread.CreateAnonymousThread(\n  procedure\n  begin\n    Synchronisieren;\n  end);",' + #10 +
    '      "good": "TThread.CreateAnonymousThread(\n  procedure\n  begin\n    Synchronisieren;\n  end).Start;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "task-exception-unobserved",' + #10 +
    '      "name": "Exception in TTask gets lost",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "threads",' + #10 +
    '      "description": "TTask.Run(…) or TTask.Create(…).Start whose result is never kept or queried with Wait, Status or similar, and whose anonymous method has no try … except. An exception in the task' +
    ' disappears silently. Also reported for a local variable that is never mentioned again (for TTask.Create only in V.Start). Silent for kept results (fields, Result, any other use of the variable) and f' +
    'or method references, whose body the rule cannot see. Medium confidence. Quick fix: wrap the body in try … except and report the message on the main thread through TThread.Queue with ShowMessage (adds' +
    ' Vcl.Dialogs, or FMX.Dialogs in FireMonkey units, and System.SysUtils to the uses clause when missing); only when begin and end of the anonymous method stand on their own lines.",' + #10 +
    '      "bad": "TTask.Run(\n  procedure\n  begin\n    Importieren(Datei);\n  end);",' + #10 +
    '      "good": "TTask.Run(\n  procedure\n  begin\n    try\n      Importieren(Datei);\n    except\n      on E: Exception do\n      begin\n        var Fehler := E.Message;\n        TThread.Queue(nil,\n  ' +
    '        procedure\n          begin\n            ShowMessage(Fehler);\n          end);\n      end;\n    end;\n  end);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dataset-loop-without-next",' + #10 +
    '      "name": "Dataset loop without Next",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "database",' + #10 +
    '      "description": "while not Q.Eof do without Q.Next in the body, or with Next only on some of the paths that continue the loop (an if without else, Continue before Next). The loop spins forever on' +
    ' the same record. Delete, MoveBy, Last, Close, FindNext and Free also count as moving on; Break, Exit, Abort and raise end the loop. Nested while and for loops are not trusted to run. When Q is passed' +
    ' on in the body (argument, assignment, with), the called code may move the record pointer and the rule stays silent. High confidence when Next is missing entirely, medium when only some paths miss it.' +
    ' Quick fix: insert Q.Next; at the end of the begin … end body (only when Next is missing entirely).",' + #10 +
    '      "bad": "qryPositionen.First;\nwhile not qryPositionen.Eof do\nbegin\n  Summe := Summe + qryPositionen.FieldByName(''Betrag'').AsCurrency;\nend;",' + #10 +
    '      "good": "qryPositionen.First;\nwhile not qryPositionen.Eof do\nbegin\n  Summe := Summe + qryPositionen.FieldByName(''Betrag'').AsCurrency;\n  qryPositionen.Next;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dataset-edit-without-post",' + #10 +
    '      "name": "Edit or Append without Post",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "database",' + #10 +
    '      "description": "After Edit, Append or Insert (without arguments) on a dataset, the same routine calls neither Post nor Cancel (nor CheckBrowseMode). The change stays open and is silently lost on' +
    ' scrolling or saved unexpectedly later; on an exception in between, nothing cancels it. Silent when another routine of the unit posts or cancels the same dataset (an Edit button with a separate Save b' +
    'utton) and when the dataset is passed on after Edit (argument, assignment, with). Medium confidence. Quick fix: wrap the following statements that use the dataset in try … except, with Post at the end' +
    ' of the try part and Cancel; raise; in the except part.",' + #10 +
    '      "bad": "tblKunde.Edit;\ntblKunde.FieldByName(''Status'').AsInteger := Ord(ksAktiv);\nProtokollieren;",' + #10 +
    '      "good": "tblKunde.Edit;\ntry\n  tblKunde.FieldByName(''Status'').AsInteger := Ord(ksAktiv);\n  tblKunde.Post;\nexcept\n  tblKunde.Cancel;\n  raise;\nend;\nProtokollieren;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "transaction-without-rollback",' + #10 +
    '      "name": "Transaction without Rollback",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "database",' + #10 +
    '      "description": "StartTransaction without Rollback in the except part of the try that directly follows. On an exception the transaction stays open and holds locks. Recognized for FireDAC (TFDConn' +
    'ection, TFDTransaction), IBX and dbExpress (StartTransaction/Commit/Rollback), dbExpress from XE (BeginTransaction/CommitFreeAndNil/RollbackFreeAndNil, also as T := Conn.BeginTransaction) and ADO (Beg' +
    'inTrans/CommitTrans/RollbackTrans). The option pairs replaces these pairs with your own. The Rollback may sit in a try … except inside a try … finally that follows directly. Silent when another routin' +
    'e of the unit rolls back the same connection (transaction across several events). High confidence. Quick fix: wrap the statements up to the Commit of the same block in try … except with Rollback (with' +
    ' the arguments of the Commit) and raise; only when a Commit follows in the same block.",' + #10 +
    '      "bad": "Verbindung.StartTransaction;\nBuchen(Auftrag);\nVerbindung.Commit;",' + #10 +
    '      "good": "Verbindung.StartTransaction;\ntry\n  Buchen(Auftrag);\n  Verbindung.Commit;\nexcept\n  Verbindung.Rollback;\n  raise;\nend;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "pairs",' + #10 +
    '          "type": "json",' + #10 +
    '          "default": [' + #10 +
    '            {' + #10 +
    '              "start": "StartTransaction",' + #10 +
    '              "commit": "Commit",' + #10 +
    '              "rollback": "Rollback"' + #10 +
    '            },' + #10 +
    '            {' + #10 +
    '              "start": "BeginTransaction",' + #10 +
    '              "commit": "CommitFreeAndNil",' + #10 +
    '              "rollback": "RollbackFreeAndNil"' + #10 +
    '            },' + #10 +
    '            {' + #10 +
    '              "start": "BeginTrans",' + #10 +
    '              "commit": "CommitTrans",' + #10 +
    '              "rollback": "RollbackTrans"' + #10 +
    '            }' + #10 +
    '          ],' + #10 +
    '          "description": "Transaction methods per library as [{\"start\": …, \"commit\": …, \"rollback\": …}]; replaces the built-in pairs."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "sql-write-without-where",' + #10 +
    '      "name": "UPDATE or DELETE without WHERE",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "database",' + #10 +
    '      "description": "An UPDATE or DELETE without WHERE in a string literal, SQL.Text, SQL.Add, CommandText, the first argument of ExecSQL, ExecSQLScalar, Open, ExecuteDirect or Execute, or in SQL.Str' +
    'ings/CommandText of the form file. It affects every row of the table; usually the condition was forgotten. The rule assembles the SQL text per query within a routine (Clear and a new Text start over) ' +
    'and substitutes constants and local values. JOIN, TOP, LIMIT and ROWS restrict the rows as well; a WHERE in a subquery or comment does not count. Unknown parts behind the table name (variables, calls ' +
    'at the place of a clause) keep the statement silent; a dynamic table name reports with medium confidence. Silent when the routine passes the SQL on or another routine of the unit adds to it; form file' +
    ' SQL only counts when the unit does not change it. Literals outside SQL properties count only with DELETE or UPDATE in capitals, so message texts stay silent. High confidence, no quick fix; tables tha' +
    't are emptied on purpose go into allowTables.",' + #10 +
    '      "bad": "qry.SQL.Text := ''DELETE FROM Warenkorb'';\nqry.ExecSQL;",' + #10 +
    '      "good": "qry.SQL.Text := ''DELETE FROM Warenkorb WHERE Kunde = :Kunde'';\nqry.ParamByName(''Kunde'').AsInteger := KundeId;\nqry.ExecSQL;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "allowTables",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [],' + #10 +
    '          "description": "Tables that are deliberately emptied or changed completely, with or without schema."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "signature-mismatch",' + #10 +
    '      "name": "Implementation differs from declaration",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "The header in the implementation section has different parameters (count, name, type, const/var/out), a different result type, procedure instead of function or a different callin' +
    'g convention than the declaration in the type (like E2037). With overloads the nearest declaration is compared (parameter count, then types, names and modifiers); if that is not unique, declared-not-i' +
    'mplemented and implemented-not-declared report both sides instead. A body may omit the parameter list, the result type and the calling convention. Methods inside {$IF} blocks are skipped; with include' +
    ' files the confidence is medium. Quick fix: align the implementation header with the declaration, or, as the second action, the declaration with the implementation (default values stay in the declarat' +
    'ion). Off with refactoring.syncSignatures = false only removes the quick fixes.",' + #10 +
    '      "bad": "procedure Buchen(const Betrag: Currency; Datum: TDate);\n…\nprocedure TKonto.Buchen(Betrag: Currency; Datum: TDateTime);",' + #10 +
    '      "good": "procedure Buchen(const Betrag: Currency; Datum: TDate);\n…\nprocedure TKonto.Buchen(const Betrag: Currency; Datum: TDate);",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2037",' + #10 +
    '        "E2211",' + #10 +
    '        "E2065"' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "interface-not-implemented",' + #10 +
    '      "name": "Interface method missing in the class",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A class lists an interface but does not implement all of its methods, including those of ancestor interfaces (like E2291). A method of the class with the same name but a differen' +
    't signature is reported at that method (like E2211). Methods inherited from ancestor classes, method resolution clauses (procedure IFoo.Bar = Baz) and properties with implements count; public TObject ' +
    'methods and IInterface methods of TInterfacedObject and similar RTL bases count as well. If the chain of ancestor classes ends at an unknown class or the interface is unknown, the rule stays silent. A' +
    ' method resolution clause for an interface the class does not list is reported too (like E2265). Classes inside {$IF} blocks are skipped. Quick fix: declare the missing methods and create empty bodies' +
    ' (not offered when a header differs).",' + #10 +
    '      "bad": "TDateiLog = class(TInterfacedObject, ILogger)\npublic\n  procedure Info(const Text: string);\nend;",' + #10 +
    '      "good": "TDateiLog = class(TInterfacedObject, ILogger)\npublic\n  procedure Info(const Text: string);\n  procedure Warnung(const Text: string);\n  procedure Fehler(const Text: string);\nend;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2291",' + #10 +
    '        "E2211",' + #10 +
    '        "E2265"' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "uses-unit-not-found",' + #10 +
    '      "name": "Unit in uses not found",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A unit in uses or contains is found neither in the project nor in the folders the compiler searches: folder of the using file, project folder, search paths and DCU output folder ' +
    'of the .dproj, library paths of the installation, each as .pas or .dcu and with every unit scope name in front (SysUtils → System.SysUtils); in packages also the units of the required packages (like F' +
    '2613). Also reported: a file from in ''…'' that does not exist (F1026), a package from requires found neither as .dpk nor as .dcp (E2202), a unit that uses itself (F2092), and once a missing unit System' +
    ', i.e. a missing library path, instead of one finding per unit (F1027). Entries inside {$IF} blocks are skipped; without a known installation, with an open macro in a search path or with a required pa' +
    'ckage of unknown content the rule stays silent. The message names similar units. Quick fixes: use the unit with its namespace (Forms → Vcl.Forms) or a similarly written unit, or add the folder below t' +
    'he project that holds the unit to DCC_UnitSearchPath of the base configuration in the .dproj.",' + #10 +
    '      "bad": "uses\n  System.SysUtils, Vcl.Forms, Kunden.Daten, Rechnungs.Druck;",' + #10 +
    '      "good": "uses\n  System.SysUtils, Vcl.Forms, Kunden.Daten, Rechnung.Druck;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "F2613",' + #10 +
    '        "F1027",' + #10 +
    '        "F1026",' + #10 +
    '        "E2202",' + #10 +
    '        "F2092"' + #10 +
    '      ],' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "searchPaths",' + #10 +
    '          "type": "string",' + #10 +
    '          "default": "project",' + #10 +
    '          "description": "Where units are searched: project (like the compiler: project, search paths of the .dproj, library paths, .pas and .dcu), atlas (what Atlas knows: index and browsing paths of' +
    ' the installation) or both."' + #10 +
    '        }' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unresolved-attribute",' + #10 +
    '      "name": "Attribute not found and silently ignored",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "An attribute [Name] resolves neither to a class NameAttribute nor to Name, usually because a unit is missing in uses. Delphi only warns (W1074) and skips the attribute: DUnitX te' +
    'sts do not run, JSON or ORM mappings are missing. The message names the unit that declares the attribute in the index; a facade unit that passes the type on from another candidate (DUnitX.TestFramewor' +
    'k instead of DUnitX.Attributes) comes first, and the DUnitX attributes are known even without DUnitX in the index. Compiler attributes such as Weak, Unsafe, Ref and Volatile always count. Silent witho' +
    'ut the unit System in the index, when a unit from uses is not in the index (it could declare the attribute), inside {$IF} blocks and when an ancestor of the surrounding class is unknown; with include ' +
    'files the confidence is medium. Quick fix: add the unit to uses.",' + #10 +
    '      "bad": "uses\n  System.SysUtils;\ntype\n  [TestFixture]\n  TKundeTests = class",' + #10 +
    '      "good": "uses\n  System.SysUtils, DUnitX.TestFramework;\ntype\n  [TestFixture]\n  TKundeTests = class",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "W1074",' + #10 +
    '        "E2289"' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "comparison-as-statement",' + #10 +
    '      "name": "Comparison instead of assignment as a statement",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A comparison such as Result = 0; or FAktiv = True; stands on its own as a statement; := was meant. Delphi only reports E2014 when compiling. With = and an assignable left side (v' +
    'ariable, field, element, pointer target) the quick fix replaces = with :=. Other comparisons and expressions whose value is discarded (A <> B;, A + B;, not A;, a literal) are reported without a fix, a' +
    's is a call on the left side.",' + #10 +
    '      "bad": "Result = 0;",' + #10 +
    '      "good": "Result := 0;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2014"' + #10 +
    '      ],' + #10 +
    '      "level": "A"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "duplicate-case-label",' + #10 +
    '      "name": "Duplicate case label",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "Two labels of a case statement cover the same value (like E2030), also through ranges (1..5 and 3), constants with the same value, characters (''a'' and #97) and enumeration ranges' +
    '. The same applies to the labels of a variant record part (like E2027). Values are computed from numbers, characters, constants and enumeration values via name resolution; labels whose value is unknow' +
    'n are only compared by their text. A label is only reported when the earlier one is compiled whenever it is: different branches of the same {$IF} never clash. Quick fix: remove the duplicate value fro' +
    'm the later branch, or the whole branch when it was its only label; a partial range overlap is reported without a fix.",' + #10 +
    '      "bad": "case Status of\n  stNeu, stOffen: Bearbeiten;\n  stGeschlossen: Archivieren;\n  stOffen: Erinnern;\nend;",' + #10 +
    '      "good": "case Status of\n  stNeu, stOffen: Bearbeiten;\n  stGeschlossen: Archivieren;\nend;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2030",' + #10 +
    '        "E2027"' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "field-after-method",' + #10 +
    '      "name": "Field after methods in the same section",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "Within a visibility section of a class, object or record, a field declaration follows a method or property. Delphi requires fields first or a new section or var (E2169); FPC acce' +
    'pts it. Quick fixes: move the field with its attributes and comments to the start of the section, or put var in front of it. In records var comes first because moving changes the memory layout. A fiel' +
    'd is only reported when a method before it is compiled whenever the field is; with conditional branches in between only var is offered.",' + #10 +
    '      "bad": "TKunde = class\nprivate\n  function GetName: string;\n  FName: string;\nend;",' + #10 +
    '      "good": "TKunde = class\nprivate\n  FName: string;\n  function GetName: string;\nend;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2169"' + #10 +
    '      ],' + #10 +
    '      "level": "A"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "overload-directive-missing",' + #10 +
    '      "name": "Overload without overload or with the same signature",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "Two routines or methods of the same name in the same scope (a type, the unit across interface and implementation, the routines nested in a routine), of which at least one lacks o' +
    'verload (like E2254, or E2267 when the earlier one lacks it), or two overloads with the same parameter kinds and types (like E2252, or E2301 with the same result type as well). A body that implements ' +
    'an earlier declaration (interface, forward) does not count. Operators, method bodies and declarations in different branches of the same {$IF} are skipped. Quick fix: append overload; to every declarat' +
    'ion without it, before the other directives.",' + #10 +
    '      "bad": "procedure Laden(const Datei: string);\nprocedure Laden(Strom: TStream);",' + #10 +
    '      "good": "procedure Laden(const Datei: string); overload;\nprocedure Laden(Strom: TStream); overload;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2254",' + #10 +
    '        "E2267",' + #10 +
    '        "E2252",' + #10 +
    '        "E2301"' + #10 +
    '      ],' + #10 +
    '      "level": "A"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "duplicate-declaration",' + #10 +
    '      "name": "Identifier declared twice",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "An identifier is declared twice in the same scope (like E2004): a local variable, constant, type or label and a parameter of the routine, two fields, a field and a method or prop' +
    'erty of a type, two types, a constant and a variable of the unit across interface and implementation. Likewise a unit twice in uses or in the uses clauses of interface and implementation at once (opti' +
    'on checkUses). Overloads and bodies of routines, a forward declaration and its type, TList next to TList<T> and declarations in different branches of the same {$IF} do not count. Quick fix: remove the' +
    ' second declaration (the whole var, const, type or label section when it was its only one; for uses the duplicate entry); none for parameters, methods and properties.",' + #10 +
    '      "bad": "procedure TRechnung.Summieren(Betrag: Currency);\nvar\n  Betrag: Currency;\nbegin",' + #10 +
    '      "good": "procedure TRechnung.Summieren(Betrag: Currency);\nbegin",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2004"' + #10 +
    '      ],' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "checkUses",' + #10 +
    '          "type": "boolean",' + #10 +
    '          "default": true,' + #10 +
    '          "description": "Report duplicate entries in uses clauses."' + #10 +
    '        }' + #10 +
    '      ],' + #10 +
    '      "level": "A"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "conditional-directive-unbalanced",' + #10 +
    '      "name": "Conditional directives incomplete or unknown",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "An {$IFDEF}, {$IFNDEF}, {$IFOPT} or {$IF} that is never closed, so the rest of the file depends on its condition (like E2095, E2280 for {$IF}); {$ELSE}, {$ELSEIF}, {$ENDIF} or {$' +
    'IFEND} without a matching {$IF…}, or after {$ELSE} (like E2279); {$IFDEF}, {$IFNDEF}, {$DEFINE} or {$UNDEF} without a valid symbol (like E2173); an unknown directive or {$WARN} identifier (like W1030)' +
    ', with the closest known name as quick fix; {$POPOPT} without {$PUSHOPT} (like W1078) or {$PUSHOPT} without {$POPOPT} (like W1079); an invalid value for {$ALIGN} or {$A} (like E2573). Unknown names ar' +
    'e not checked in branches whose condition tests FPC, {$PUSHOPT}/{$POPOPT} only when none of them is inside a conditional branch. Quick fixes: add {$ENDIF} before the first blank line after the open bl' +
    'ock, remove a surplus directive, correct the typo.",' + #10 +
    '      "bad": "{$IFDEF DEBUG}\n  Protokoll.Ausfuehrlich := True;\n\nprocedure TDienst.Starten;",' + #10 +
    '      "good": "{$IFDEF DEBUG}\n  Protokoll.Ausfuehrlich := True;\n{$ENDIF}\n\nprocedure TDienst.Starten;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2095",' + #10 +
    '        "E2280",' + #10 +
    '        "E2279",' + #10 +
    '        "E2173",' + #10 +
    '        "W1030",' + #10 +
    '        "W1078",' + #10 +
    '        "W1079",' + #10 +
    '        "E2573"' + #10 +
    '      ],' + #10 +
    '      "level": "A"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "override-target-missing",' + #10 +
    '      "name": "override without a matching virtual method",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A method marked override for which no ancestor has a virtual (or dynamic, abstract) method with the same name and parameters (like E2137): often a typo (Destory) or parameters ch' +
    'anged in the ancestor. The message names the closest virtual method of the ancestor (\"there it is Ausfuehren(const Modus: TModus)\") or a similar name. Also: override on a static method (like E2170),' +
    ' on a final one (like E2352), and deriving from a sealed class (like E2353). Ancestors are looked up in the file and in the symbol index; when the chain breaks at an unknown class the rule stays silen' +
    't. Without System in the index the virtual methods of TObject count as present. Type parameters of generic ancestors, type aliases and synonyms such as Longint match. Quick fix: take over the ancestor' +
    '''s signature in the declaration and the implementation.",' + #10 +
    '      "bad": "TDienst = class\nprotected\n  procedure Ausfuehren(const Modus: TModus); virtual;\nend;\nTImportDienst = class(TDienst)\nprotected\n  procedure Ausfuehren(Modus: Integer); override;\nend' +
    ';",' + #10 +
    '      "good": "TImportDienst = class(TDienst)\nprotected\n  procedure Ausfuehren(const Modus: TModus); override;\nend;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2137",' + #10 +
    '        "E2170",' + #10 +
    '        "E2352",' + #10 +
    '        "E2353"' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "abstract-class-instantiated",' + #10 +
    '      "name": "Instance of a class with abstract methods",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "Create on a class that declares or inherits abstract methods without overriding them (like W1020), or on a class declared abstract (like E2402). Calling an abstract method raises' +
    ' EAbstractError at run time; the message names the open methods. Classes are looked up in the file and in the symbol index; overloads with the same number of parameters count as one method. Calls on c' +
    'lass references, inherited Create and constructor bodies are not checked. Quick fix for a class of this file that inherits the abstract methods: override them there (like the code action \"override\")' +
    '.",' + #10 +
    '      "bad": "Form := TForm.Create;\nGesamt := Gesamt + Form.Flaeche;",' + #10 +
    '      "good": "Form := TKreis.Create;\nGesamt := Gesamt + Form.Flaeche;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "W1020",' + #10 +
    '        "E2402"' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "property-accessor-invalid",' + #10 +
    '      "name": "Invalid property getter or setter",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "The name after read or write of a property does not fit: it is declared neither in the class nor in its ancestors, or it is a property (like E2168); the getter or setter has the ' +
    'wrong kind, parameters or types (like E2234); the setter takes a var or out parameter (like E2282); the accessor is overloaded (like E2271); a class property uses an instance member or a class method ' +
    'without static (like E2355), or an instance property uses a class member (like E2356); an array property or a property with index uses a field (like E2174); a field selector goes through a field that ' +
    'is no record (like E2459), names a member that is no field (like E2461) or a field the record lacks (like E2562). Names are looked up in the file and, for ancestors, in the symbol index; the rule stay' +
    's silent when the ancestor chain breaks, the name only exists in an inactive branch, the class cannot see it or the class includes files. Types are compared only when both are built in or declared as ' +
    'types of their own. Quick fix for a missing F<Name>, Get<Name> or Set<Name>: create it (like the completion after read/write, completion.accessorSection).",' + #10 +
    '      "bad": "TKunde = class\nprivate\n  FName: string;\npublic\n  property Name: string read FName write SetName;\nend;",' + #10 +
    '      "good": "TKunde = class\nprivate\n  FName: string;\n  procedure SetName(const Value: string);\npublic\n  property Name: string read FName write SetName;\nend;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2168",' + #10 +
    '        "E2234",' + #10 +
    '        "E2282",' + #10 +
    '        "E2271",' + #10 +
    '        "E2355",' + #10 +
    '        "E2356",' + #10 +
    '        "E2174",' + #10 +
    '        "E2459",' + #10 +
    '        "E2461",' + #10 +
    '        "E2562"' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "assign-to-property-member",' + #10 +
    '      "name": "Assignment to a field of a property record",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "Assignment to a field of a record that a property with a getter, a default or array property or a function result only delivers as a copy (like E2064): the assignment has no effe' +
    'ct. Assignments to untyped constants are reported as well. Types come from name resolution; the rule only reports when the record type is known for sure. A property that reads a field directly lets De' +
    'lphi write into that field and stays silent. Quick fix for a property with write: assign through a local variable and write it back; the variable is declared in the routine and the unit of its type is' +
    ' added to uses.",' + #10 +
    '      "bad": "Rahmen.BoundsRect.Left := 0;",' + #10 +
    '      "good": "R := Rahmen.BoundsRect;\nR.Left := 0;\nRahmen.BoundsRect := R;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2064",' + #10 +
    '        "E2453"' + #10 +
    '      ],' + #10 +
    '      "level": "T"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "readonly-property-assigned",' + #10 +
    '      "name": "Assignment to a property without write",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "Assignment to a property that has no write (like E2129), or reading a property that has no read (like E2130). The rule only reports when name resolution finds the property for su' +
    're; redeclarations without read and write (property Caption;) count as unknown. Quick fixes: Count := 0 becomes Clear when the type has Clear; inside a method of the declaring class, assign the field ' +
    'behind read; for a property declared in this file, create the setter and add write.",' + #10 +
    '      "bad": "Liste.Count := 0;",' + #10 +
    '      "good": "Liste.Clear;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2129",' + #10 +
    '        "E2130"' + #10 +
    '      ],' + #10 +
    '      "level": "T"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "sql-select-star",' + #10 +
    '      "name": "SELECT * in code",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "database",' + #10 +
    '      "description": "SELECT * or SELECT alias.* in a column list, in the same places as sql-write-without-where: string literals, SQL.Text, SQL.Add, CommandText, the first argument of ExecSQL, Open a' +
    'nd similar calls, constants, local values and SQL.Strings/CommandText of the form file. New columns silently change the dataset, persistent fields no longer match, and more data is transferred than ne' +
    'eded. Subqueries count; EXISTS (SELECT * …) and COUNT(*) stay silent, as does a column list from a variable. Literals outside SQL properties count only with SELECT in capitals and a FROM, so message t' +
    'exts stay silent. Off by default (enable in the rules settings or with the strict profile). High confidence. Quick fix: when the star stands in a single literal and the dataset has persistent fields i' +
    'n the form file, replace * with their FieldName list (without calculated and lookup fields).",' + #10 +
    '      "bad": "qry.SQL.Text := ''SELECT * FROM Kunden WHERE Ort = :Ort'';",' + #10 +
    '      "good": "qry.SQL.Text := ''SELECT Id, Name, Ort FROM Kunden WHERE Ort = :Ort'';"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "path-concat-without-delimiter",' + #10 +
    '      "name": "Path joined without delimiter",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "robustness",' + #10 +
    '      "description": "A folder without a trailing path delimiter is joined to a file or folder name with +: results of ExtractFileDir, ExcludeTrailingPathDelimiter, GetCurrentDir, GetHomePath, TPath.G' +
    'etDocumentsPath and the other TPath.Get…Path folders, TPath.GetDirectoryName, TDirectory.GetCurrentDirectory and TDirectory.GetParent, called directly or held in a local variable that the routine only' +
    ' assigns such values to. The result is C:\\Datadatei.txt instead of C:\\Data\\datei.txt. ExtractFilePath, IncludeTrailingPathDelimiter and TPath.GetTempPath end with a delimiter and stay silent, as do' +
    ' delimiters, extensions (ExtractFileExt, ''.bak'') and texts that start with a space or punctuation. A literal name reports with high confidence, an identifier with medium confidence. A local variable p' +
    'assed to a procedure other than ForceDirectories, FileExists and similar read-only calls may be changed there and stays silent. Quick fix: TPath.Combine(Folder, Name), adding System.IOUtils to uses.",' + #10 +
    '      "bad": "Ordner := TPath.GetDocumentsPath;\nDatei := Ordner + ''export.csv'';",' + #10 +
    '      "good": "Ordner := TPath.GetDocumentsPath;\nDatei := TPath.Combine(Ordner, ''export.csv'');"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "hardcoded-path",' + #10 +
    '      "name": "Hard-coded file path",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "robustness",' + #10 +
    '      "description": "A string literal with a drive letter (C:\\…, also with /) or a UNC path (\\\\server\\share\\…); paths under C:\\Users or C:\\Documents and Settings get their own message. On othe' +
    'r computers the path is missing. Drive roots such as ''C:\\'' alone and the prefixes \\\\?\\ and \\\\.\\ stay silent, as do comments, test units and units listed in allowUnits (for example a unit with t' +
    'he default paths of an installation). High confidence, no quick fix: take the path from TPath (GetDocumentsPath, GetHomePath, GetSharedDocumentsPath), the settings or an environment variable.",' + #10 +
    '      "bad": "Protokoll.SaveToFile(''C:\\Users\\marco\\Desktop\\log.txt'');",' + #10 +
    '      "good": "Protokoll.SaveToFile(TPath.Combine(TPath.GetDocumentsPath, ''log.txt''));",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "allowUnits",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [],' + #10 +
    '          "description": "Units in which hard-coded paths are allowed, by unit name; * at the end matches a prefix (App.Config*)."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "filename-compare-case",' + #10 +
    '      "name": "File names compared with =",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "robustness",' + #10 +
    '      "description": "A comparison with = or <> where one side is a file or path name: the result of ExtractFileName, ExtractFilePath, ExtractFileDir, ExtractFileExt, ExpandFileName, ChangeFileExt and' +
    ' related System.SysUtils functions, of TPath.GetFileName, GetExtension, GetDirectoryName, GetFullPath, Combine and related methods, or a variable or property whose name ends in FileName, or Applicatio' +
    'n.ExeName. On Windows Kunde.pas and kunde.PAS are the same file. Comparisons with an empty string, nil or a literal without letters stay silent, as does ExtractFileDir(X) = X (both sides come from the' +
    ' same text). Medium confidence. Quick fix: SameFileName(A, B), or not SameFileName(A, B) for <>; adds System.SysUtils to uses if needed.",' + #10 +
    '      "bad": "if ExtractFileName(Datei) = ''Config.ini'' then",' + #10 +
    '      "good": "if SameFileName(ExtractFileName(Datei), ''Config.ini'') then"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "initialization-not-finalized",' + #10 +
    '      "name": "Object created at startup is not freed",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "robustness",' + #10 +
    '      "description": "An object is created with TClass.Create in the initialization section and assigned to a unit variable, or created in a class constructor and assigned to a class var, but the unit' +
    ' never frees it (no Free, Destroy, DisposeOf, Release or FreeAndNil anywhere in the unit). FastMM reports a leak on shutdown; in packages the object stays behind on every unload. Interface and record ' +
    'types, components with an owner (Application, Self, Owner) and objects the unit hands over stay silent: every mention of the variable must be harmless (member access, comparison with nil, Assigned, a ' +
    'new Create or nil assignment); passing it as an argument, assigning it elsewhere, with, a property reading it or FreeOnTerminate silence the rule. For variables in the interface section and public cla' +
    'ss vars the rule also stays silent when another indexed unit uses the name. High confidence. Quick fix: FreeAndNil at the end of finalization or in the class destructor; a missing finalization section' +
    ' or class destructor (declaration and body) is created and System.SysUtils is added to uses when needed.",' + #10 +
    '      "bad": "initialization\n  GProtokoll := TProtokoll.Create;\nend.",' + #10 +
    '      "good": "initialization\n  GProtokoll := TProtokoll.Create;\n\nfinalization\n  FreeAndNil(GProtokoll);\nend."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "compiler-warnings-disabled",' + #10 +
    '      "name": "Compiler warnings or checks switched off up to the end of the unit",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "robustness",' + #10 +
    '      "description": "{$WARNINGS OFF}, {$HINTS OFF}, {$WARN X OFF}, {$R-}, {$Q-} (also combined as {$R-,Q-}) or the long forms {$RANGECHECKS OFF} and {$OVERFLOWCHECKS OFF} without a later restore up t' +
    'o the end of the unit. Messages and checks disappear far beyond the intended spot, and the 0/0/0 rule is bypassed. Any later ON, +, DEFAULT or ERROR for the same switch counts as a restore, also insid' +
    'e {$IFOPT}/{$IFDEF} patterns, as does a later {$POPOPT}. A switch whose counterpart stands in another branch of the same {$IF} ({$IFDEF DEBUG}{$R+}{$ELSE}{$R-}{$ENDIF}) is a deliberate setting per con' +
    'figuration and stays silent, as does a directive with no code after it; {$R *.dfm} is a resource, not a range check. Option allow lists switches that may stay off (warning names such as SYMBOL_PLATFOR' +
    'M, WARNINGS, HINTS, R or RANGECHECKS, Q or OVERFLOWCHECKS). High confidence. Quick fix: insert the restore ({$WARNINGS ON}, {$WARN X DEFAULT}, {$R+} …) after the next block; for range and overflow che' +
    'cks only individually, since {$R+} may switch on a check the project has off.",' + #10 +
    '      "bad": "{$WARNINGS OFF}\nfunction AlteBerechnung(const Wert: Integer): Integer;\nbegin\n  Result := Wert * 2;\nend;",' + #10 +
    '      "good": "{$WARNINGS OFF}\nfunction AlteBerechnung(const Wert: Integer): Integer;\nbegin\n  Result := Wert * 2;\nend;\n{$WARNINGS ON}",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "allow",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [],' + #10 +
    '          "description": "Switches that may stay off up to the end of the unit: warning names for {$WARN} (SYMBOL_PLATFORM), WARNINGS, HINTS, R or RANGECHECKS, Q or OVERFLOWCHECKS; case is ignored."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dll-export-unsafe",' + #10 +
    '      "name": "Exported routine not safe across DLL boundaries",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "robustness",' + #10 +
    '      "description": "A routine of this file listed in exports has no calling convention (stdcall, cdecl, safecall, winapi or pascal; register is the Delphi convention) or takes or returns a string (s' +
    'tring, UnicodeString, AnsiString, UTF8String, RawByteString), a dynamic array (TBytes, TArray<T>, …DynArray, array of T declared in the file), an object or an interface without GUID. Callers in other ' +
    'languages or Delphi versions crash; strings and dynamic arrays live in the memory manager of the DLL. WideString, ShortString, PChar, open array parameters and records are fine. Objects are only recog' +
    'nised for certain: classes of the file, of the index and common RTL classes; interfaces only from the file. Routines from other units and overloads that the exports entry does not pin down stay silent' +
    '. With ShareMem or SimpleShareMem in uses, strings and dynamic arrays are allowed (option allowShareMem). The finding sits on the exports entry; for strings it recommends PChar with buffer and length.' +
    ' High confidence. Quick fix: add stdcall to every header of the routine (only individually, since it changes the interface for existing callers).",' + #10 +
    '      "bad": "function KundeName(Id: Integer): string;\n…\nexports\n  KundeName;",' + #10 +
    '      "good": "function KundeName(Id: Integer; Puffer: PChar; Laenge: Integer): Integer; stdcall;\n…\nexports\n  KundeName;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "allowShareMem",' + #10 +
    '          "type": "boolean",' + #10 +
    '          "default": true,' + #10 +
    '          "description": "With ShareMem or SimpleShareMem in uses, strings and dynamic arrays are allowed in exported routines."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "destructor-not-nil-safe",' + #10 +
    '      "name": "Destructor uses fields that may be nil",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "If a constructor raises, Delphi calls the destructor right away, even though not all fields exist yet. Reported is an access in the destructor (or in a private method that only t' +
    'he destructor calls) to a field such as FLines.Clear, FFile.Position or FLines[0], when a constructor of the class creates the field (TClass.Create) only after a call that can raise or only on some pa' +
    'ths. The resulting access violation hides the original exception. Free, FreeAndNil, DisposeOf and accesses after Assigned(FField) or FField <> nil are nil-safe; BeforeDestruction does not run on this ' +
    'path. Constructors of RTL classes that raise at most EOutOfMemory (TStringList.Create, TObjectList<T>.Create(True)), inherited Create and Supports do not count as raising. High confidence. Quick fix: ' +
    'put if Assigned(FField) then in front of the statement. With onlyAfterRaisingCode off, every field created in the constructor counts.",' + #10 +
    '      "bad": "constructor TImport.Create(const Datei: string);\nbegin\n  inherited Create;\n  FStrom := TFileStream.Create(Datei, fmOpenRead);\n  FZeilen := TStringList.Create;\nend;\n\ndestructor TIm' +
    'port.Destroy;\nbegin\n  FZeilen.Clear;\n  FZeilen.Free;\n  FStrom.Free;\n  inherited;\nend;",' + #10 +
    '      "good": "destructor TImport.Destroy;\nbegin\n  if Assigned(FZeilen) then\n    FZeilen.Clear;\n  FZeilen.Free;\n  FStrom.Free;\n  inherited;\nend;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "onlyAfterRaisingCode",' + #10 +
    '          "type": "boolean",' + #10 +
    '          "default": true,' + #10 +
    '          "description": "Only report when the constructor calls something that can raise before it creates the field."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "handle-leak",' + #10 +
    '      "name": "Windows handle is not closed",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "A Windows handle in a local variable is not closed with its counterpart on some path to the end of the routine: CreateFile, CreateEvent, CreateMutex, OpenProcess, CreateProcess (' +
    'hProcess, hThread) and CreateToolhelp32Snapshot with CloseHandle, FindFirstFile with FindClose, RegOpenKeyEx/RegCreateKeyEx with RegCloseKey, LoadLibrary with FreeLibrary, GetDC with ReleaseDC, Create' +
    'Pen/CreateBrush/CreateFont/CreateBitmap with DeleteObject, CreateCompatibleDC with DeleteDC and others. Returning the handle, storing it in a field or global, passing it to an unknown routine or captu' +
    'ring it in an anonymous method counts as handing it on. Branches in which an if check says the open failed (H = 0, H = INVALID_HANDLE_VALUE, RegOpenKeyEx(...) <> ERROR_SUCCESS) and exception paths (se' +
    'e pair-without-finally) do not count. The option pairs adds your own pairs. Medium confidence. Quick fix when the handle is never closed: wrap the statements after the open in try … finally with the c' +
    'lose call, or append the close call when the open is the last statement.",' + #10 +
    '      "bad": "H := CreateFile(PChar(Datei), GENERIC_READ, 0, nil, OPEN_EXISTING, 0, 0);\nif H = INVALID_HANDLE_VALUE then\n  RaiseLastOSError;\nReadFile(H, Puffer, SizeOf(Puffer), Gelesen, nil);",' + #10 +
    '      "good": "H := CreateFile(PChar(Datei), GENERIC_READ, 0, nil, OPEN_EXISTING, 0, 0);\nif H = INVALID_HANDLE_VALUE then\n  RaiseLastOSError;\ntry\n  ReadFile(H, Puffer, SizeOf(Puffer), Gelesen, nil' +
    ');\nfinally\n  CloseHandle(H);\nend;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "pairs",' + #10 +
    '          "type": "json",' + #10 +
    '          "default": [],' + #10 +
    '          "description": "Additional open/close pairs as \"Open>Close\" or {\"open\": …, \"close\": …}; the open function returns the handle, the close procedure takes it as its only argument."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "global-formatsettings-modified",' + #10 +
    '      "name": "Global FormatSettings is modified",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "robustness",' + #10 +
    '      "description": "Assignment to the global FormatSettings or one of its fields (also to the deprecated global variables DecimalSeparator, ShortDateFormat, ThousandSeparator … of older Delphi versi' +
    'ons). This changes the formatting for the whole application, for every package in the same process (in an IDE plugin the IDE itself) and for all threads, and is not thread-safe; it is often a workarou' +
    'nd to force a dot as decimal separator. Reported only when the name is surely the variable from System.SysUtils: no local declaration, no member of the class or its ancestors (silent when the chain of' +
    ' ancestors ends at an unknown class), not inside with. Complements format-without-settings, which reports formatting calls without settings. High confidence. Quick fix when the routine changes the glo' +
    'bal settings only once and formats something afterwards: declare a local TFormatSettings (TFormatSettings.Invariant for DecimalSeparator := ''.'', otherwise a copy of FormatSettings with the changed fie' +
    'ld) and pass it to the formatting calls that follow. With allowInProgram on, assignments in the .dpr are allowed.",' + #10 +
    '      "bad": "procedure TExport.Schreiben;\nbegin\n  FormatSettings.DecimalSeparator := ''.'';\n  Zeile := FloatToStr(Betrag);\nend;",' + #10 +
    '      "good": "procedure TExport.Schreiben;\nvar\n  FS: TFormatSettings;\nbegin\n  FS := TFormatSettings.Invariant;\n  Zeile := FloatToStr(Betrag, FS);\nend;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "allowInProgram",' + #10 +
    '          "type": "boolean",' + #10 +
    '          "default": false,' + #10 +
    '          "description": "Allow the assignments in the .dpr, for example once at program start."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-interface-dangling",' + #10 +
    '      "name": "Component stored as interface stays referenced after Free",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "A descendant of TComponent (form, frame, data module, own component) implements an interface, but TComponent does not count references. Reported is storing the object as an inter' +
    'face in a field, a global variable or a list (FView as IObserver passed to Bus.Subscribe, FList.Add, Register, Anmelden …, assigned to a field or global, or added to a TList<IFoo>/TInterfaceList) when' +
    ' the same unit frees the object (Free, Release, DisposeOf, FreeAndNil) and nowhere unregisters it: FreeNotification on the object, another call on the same receiver with the object as argument (Unsubs' +
    'cribe, Remove, Abmelden …), Clear, or another assignment to the same field. After the Free the stored interface points to freed memory. Silent for classes with their own _Release and when the chain of' +
    ' ancestors ends at an unknown class. Also reported, without a quick fix: descendants of TInterfacedObject that are stored this way and additionally freed with Free; the stored interface keeps a freed ' +
    'object, and unregistering first would already free it. Medium confidence. Quick fix: insert the unregistration before the first Free (Receiver.Abmelden(…) when the receiver''s type has the counterpart,' +
    ' or Field := nil).",' + #10 +
    '      "bad": "procedure TfrmHaupt.AnsichtOeffnen;\nbegin\n  FAnsicht := TfrmKunden.Create(Self);\n  Bus.Anmelden(FAnsicht as IBeobachter);\nend;\n\nprocedure TfrmHaupt.AnsichtSchliessen;\nbegin\n  FAn' +
    'sicht.Free;\nend;",' + #10 +
    '      "good": "procedure TfrmHaupt.AnsichtOeffnen;\nbegin\n  FAnsicht := TfrmKunden.Create(Self);\n  Bus.Anmelden(FAnsicht as IBeobachter);\nend;\n\nprocedure TfrmHaupt.AnsichtSchliessen;\nbegin\n  Bu' +
    's.Abmelden(FAnsicht as IBeobachter);\n  FAnsicht.Free;\nend;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "componentClasses",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [' + #10 +
    '            "TComponent"' + #10 +
    '          ],' + #10 +
    '          "description": "Base classes without reference counting; with TComponent the known VCL and FMX classes (TForm, TFrame, TDataModule …) count as well."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unit-name-mismatch",' + #10 +
    '      "name": "Unit name does not match the file name",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "The name after unit differs from the file name, usually after renaming the file outside the IDE (like E1038, W1038). Case does not matter, dots in the name do. In a program, libr' +
    'ary or package, an entry uses X in ''File.pas'' whose file declares a different unit is reported too (like E2085); the rule reads that file. Programs, libraries and packages themselves are not compared ' +
    'with their file name, because the compiler does not either. {$WARN UNIT_NAME_MISMATCH OFF} or {$WARNINGS OFF} before the unit name silences the rule like the compiler. Quick fixes: change the unit nam' +
    'e to the file name (renaming the file is up to the IDE), or change the uses entry to the unit the file declares.",' + #10 +
    '      "bad": "// File: Kunden.Daten.pas\nunit Kunden.Model;\n\ninterface",' + #10 +
    '      "good": "// File: Kunden.Daten.pas\nunit Kunden.Daten;\n\ninterface",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E1038",' + #10 +
    '        "W1038",' + #10 +
    '        "E2085"' + #10 +
    '      ],' + #10 +
    '      "level": "A"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "text-after-final-end",' + #10 +
    '      "name": "Text after the final end.",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "Source code after the final end. of a unit, program, library or package. The compiler ignores it (like W1011); usually it is code that ended up at the end of the file while pasti' +
    'ng and is never compiled. Comments and directives are not reported (option allowComments). The rule finds the final end. behind the last section of the syntax tree and stays silent while the parser re' +
    'ports errors or when end. is inside an {$IF…} branch; {$WARNINGS OFF} before end. silences it. Quick fix: remove the text after end.",' + #10 +
    '      "bad": "end.\n\nprocedure TKunde.Speichern;\nbegin",' + #10 +
    '      "good": "end.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "allowComments",' + #10 +
    '          "type": "boolean",' + #10 +
    '          "default": true,' + #10 +
    '          "description": "Allow comments and directives after end."' + #10 +
    '        }' + #10 +
    '      ],' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "W1011"' + #10 +
    '      ],' + #10 +
    '      "level": "A"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "exports-invalid",' + #10 +
    '      "name": "Invalid exports clause",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "An exports clause inside a routine (like E2191), the export of a threadvar or of a routine declared local (like E2276), of a variable, constant or type (like E2121), or the same ' +
    'entry or export name twice (like E2287). Names are only resolved against global declarations of the file; names from other units and names with a dot stay silent, as do two entries in mutually exclusi' +
    've {$IF…} branches. Overloaded routines with different parameter lists or export names count as different entries. Complements dll-export-unsafe (#973). Quick fix: remove the duplicate entry.",' + #10 +
    '      "bad": "exports\n  Initialisieren,\n  Berechnen,\n  Initialisieren;",' + #10 +
    '      "good": "exports\n  Initialisieren,\n  Berechnen;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2191",' + #10 +
    '        "E2276",' + #10 +
    '        "E2121",' + #10 +
    '        "E2287"' + #10 +
    '      ],' + #10 +
    '      "level": "A"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unit-name-conflict",' + #10 +
    '      "name": "Unit name conflicts",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A unit is named like a unit reserved for the compiler, System or SysInit (like E2272), or {$NOINCLUDE X} names a unit the compiler does not know (like E2242); the latter needs th' +
    'e project''s unit search and stays silent when it gives no sure answer. The RTL sources (source/rtl) are not checked. Not reported: E2447, W1051 and X2421 belong to the namespaces of .NET metadata, whi' +
    'ch dcc32/dcc64 do not create; for E2399 the documentation gives no condition, and a unit Kunden next to Kunden.Daten compiles without error in Delphi (Spring.pas next to Spring.Collections.pas). Quick' +
    ' fix for {$NOINCLUDE}: use a similarly spelled known unit.",' + #10 +
    '      "bad": "unit System;\n\ninterface",' + #10 +
    '      "good": "unit Kunden.Systemdienste;\n\ninterface",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2272",' + #10 +
    '        "E2242"' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "implicit-variants-unit",' + #10 +
    '      "name": "Variant without System.Variants in uses",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "The unit uses Variant or OleVariant as a type without System.Variants in uses. The compiler then adds the unit silently (like W1040) and so changes the initialization order. The ' +
    'rule counts type references in the syntax tree (variables, fields, parameters, results, type arguments); Variants in uses also counts inside an {$IF…} branch and without namespace. Silent in System, S' +
    'ysInit and Variants themselves, when the file declares its own type Variant, and after {$WARN IMPLICIT_VARIANTS OFF}. Off by default (strict profile). Quick fix: add System.Variants to uses (Variants ' +
    'when the unit names SysUtils or Classes without namespace).",' + #10 +
    '      "bad": "uses\n  System.SysUtils;\n…\nvar Wert: Variant;",' + #10 +
    '      "good": "uses\n  System.SysUtils, System.Variants;\n…\nvar Wert: Variant;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "W1040"' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "file-encoding-unsupported",' + #10 +
    '      "name": "Encoding or character the compiler does not read",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "The file is UTF-32 encoded (like F2438; recognized by its byte order mark, no further findings then), or the code outside strings, comments and directives contains a character th' +
    'e compiler rejects (like E2038): typographic quotes copied from a web page or a word processor, the ASCII characters ! \" ? \\ ` | ~ and punctuation, symbols and emoji beyond ASCII. Letters, digits an' +
    'd connectors such as U+203F stay allowed in identifiers; asm blocks and {$IF…} branches are skipped; control, format and space characters are left to control-char and invisible-char. Quick fix: a pair' +
    ' of quotes on one line becomes a string literal; a single character with an unambiguous ASCII counterpart (– − × ÷ ≤ ≥ ≠, full-width ASCII) is replaced. A UTF-32 file has no quick fix; save it as UTF-' +
    '8 with BOM.",' + #10 +
    '      "bad": "Titel := ‚Bericht‘;",' + #10 +
    '      "good": "Titel := ''Bericht'';",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "F2438",' + #10 +
    '        "E2038"' + #10 +
    '      ],' + #10 +
    '      "level": "A"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "anonymous-capture-invalid",' + #10 +
    '      "name": "Anonymous method captures what it must not capture",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "An anonymous method uses a var, out or untyped parameter, or Result, of a surrounding routine or anonymous function (like E2555). The name is resolved from the inside out (parame' +
    'ters, var/const/type, local routines, inline variables, for var); inside with and asm the rule stays silent, and declarations in conditional branches that exclude the location do not count. Quick fix:' +
    ' copy the value into a local variable before the statement, use only that variable in the anonymous method, and write it back after the statement when the method assigns it.",' + #10 +
    '      "bad": "procedure Load(var Count: Integer);\nbegin\n  TTask.Run(procedure begin Inc(Count); end);\nend;",' + #10 +
    '      "good": "procedure Load(var Count: Integer);\nvar\n  CountCopy: Integer;\nbegin\n  CountCopy := Count;\n  TTask.Run(procedure begin Inc(CountCopy); end);\n  Count := CountCopy;\nend;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2555"' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "operator-declaration-invalid",' + #10 +
    '      "name": "Operator declared incorrectly",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A class operator in a record or class is declared in a way Delphi rejects: unknown operator name (like E2393), wrong number of parameters (E2517), own type missing from the param' +
    'eters (E2518) or from parameters and result for Implicit/Explicit (E2521), Inc/Dec with a result type other than the first parameter (E2519), comparison operator without a Boolean result (E2520), conv' +
    'ersion to or from an ancestor (E2522, chain within the file) or Assign without var before the first parameter (E2464). Types count as equal when their names match without unit prefix and type argument' +
    's; aliases of the own type declared in the file keep the rule silent, and True, False and OnesComplement are accepted. Quick fixes: nearest operator name, Boolean as result, result like the first para' +
    'meter, var before the first parameter, parameter list from the template; each in the declaration and the implementation.",' + #10 +
    '      "bad": "TGeld = record\n  class operator Equal(const A, B: TGeld): Integer;\nend;",' + #10 +
    '      "good": "TGeld = record\n  class operator Equal(const A, B: TGeld): Boolean;\nend;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2393",' + #10 +
    '        "E2464",' + #10 +
    '        "E2517",' + #10 +
    '        "E2518",' + #10 +
    '        "E2519",' + #10 +
    '        "E2520",' + #10 +
    '        "E2521",' + #10 +
    '        "E2522"' + #10 +
    '      ],' + #10 +
    '      "level": "A"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "generic-declaration-invalid",' + #10 +
    '      "name": "Generic declaration not allowed",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A generic declaration that Delphi rejects: class and record constraints together (like E2507), a constraint twice (E2603), record together with constructor (E2516), a class type ' +
    'next to class or record (E2552), two class types (E2553), a constraint type that is neither class nor interface (E2510); type parameters on an enumeration, set, subrange, pointer, class reference, ali' +
    'as or helper (E2508), on a destructor or class constructor (E2528), an operator (E2529), a global routine (E2530), a virtual, dynamic, message or override method (E2533) or an interface method (E2535)' +
    '; class of a parameterized type (E2548), a generic class derived from TCustomAttribute (E2549), a parameterized type as attribute (E2565); a type parameter that hides one of the enclosing type (H2509)' +
    '; a call with a number of type arguments no overload has (E2551, classes and records of the file with their ancestors in the file); a method of a generic type or a generic method declared in the inter' +
    'face section that uses a symbol of the implementation section (E2506; silent inside with and when the ancestor chain is not known). Types count only when they are built in or declared in the file; unk' +
    'nown types keep the rule silent. Local procedures in generic methods (E2570) are not reported until a check against Delphi 12/13 confirms that they are still rejected.",' + #10 +
    '      "bad": "procedure Swap<T>(var A, B: T);",' + #10 +
    '      "good": "type\n  TSwap = record\n    class procedure Swap<T>(var A, B: T); static;\n  end;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2506",' + #10 +
    '        "E2507",' + #10 +
    '        "E2508",' + #10 +
    '        "E2510",' + #10 +
    '        "E2516",' + #10 +
    '        "E2528",' + #10 +
    '        "E2529",' + #10 +
    '        "E2530",' + #10 +
    '        "E2533",' + #10 +
    '        "E2535",' + #10 +
    '        "E2548",' + #10 +
    '        "E2549",' + #10 +
    '        "E2551",' + #10 +
    '        "E2552",' + #10 +
    '        "E2553",' + #10 +
    '        "E2565",' + #10 +
    '        "E2603",' + #10 +
    '        "H2509"' + #10 +
    '      ],' + #10 +
    '      "level": "A"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "type-restriction-violated",' + #10 +
    '      "name": "Language rule for records, inline and helpers violated",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "Fixed language rules that only the compiler reports: virtual methods (like E2379) or other virtual directives (override, abstract, reintroduce, message, final; E2463) in records,' +
    ' parameterless constructors (E2394), constructors whose parameters all have defaults (E2471) and destructors (E2465) in records, class methods in records without static (E2398); in record helpers virt' +
    'ual methods (E2598) and the other virtual directives (E2475); fields in helpers (class var is allowed, E2599), a destructor (E2295) or class constructor (E2358) in a class helper, a helper constructor' +
    ' whose first statement is not a call without arguments (E2296), a class helper descending from a helper whose type the new target does not descend from (E2294, only with a known ancestor chain), a hel' +
    'per used as type of a declaration (E2527) or declared inside a generic type (E2589); several class constructors (E2359, exclusive conditional branches count once), class constructors with parameters (' +
    'E2360) or virtual, dynamic or message (E2534); methods, properties, class members, types and constants in local or anonymous records (E2433 to E2437); inline on virtual or dynamic methods (E2425), on ' +
    'constructors and destructors (E2442), with open array parameters (E2439), with an asm body (E2426), declared in the interface section and using a symbol of the implementation section (E2441), as local' +
    ' routine reading variables of the enclosing routine (E2449) or calling its own local routines (E2501); local, absolute or initialized threadvar (E2189, E2190, E2194). The checks apply to all supported' +
    ' Delphi versions (10 Seattle to 13). Option disabledChecks leaves out single codes. Quick fixes: remove the directive, add static.",' + #10 +
    '      "bad": "TPoint2 = record\n  X, Y: Integer;\n  function Length: Double; virtual;\nend;",' + #10 +
    '      "good": "TPoint2 = record\n  X, Y: Integer;\n  function Length: Double;\nend;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2189",' + #10 +
    '        "E2190",' + #10 +
    '        "E2194",' + #10 +
    '        "E2294",' + #10 +
    '        "E2295",' + #10 +
    '        "E2296",' + #10 +
    '        "E2358",' + #10 +
    '        "E2359",' + #10 +
    '        "E2360",' + #10 +
    '        "E2379",' + #10 +
    '        "E2394",' + #10 +
    '        "E2398",' + #10 +
    '        "E2425",' + #10 +
    '        "E2426",' + #10 +
    '        "E2433",' + #10 +
    '        "E2434",' + #10 +
    '        "E2435",' + #10 +
    '        "E2436",' + #10 +
    '        "E2437",' + #10 +
    '        "E2439",' + #10 +
    '        "E2441",' + #10 +
    '        "E2442",' + #10 +
    '        "E2449",' + #10 +
    '        "E2463",' + #10 +
    '        "E2465",' + #10 +
    '        "E2471",' + #10 +
    '        "E2475",' + #10 +
    '        "E2501",' + #10 +
    '        "E2527",' + #10 +
    '        "E2534",' + #10 +
    '        "E2589",' + #10 +
    '        "E2598",' + #10 +
    '        "E2599"' + #10 +
    '      ],' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "disabledChecks",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [],' + #10 +
    '          "description": "Compiler codes the rule does not check, e.g. [\"E2425\"]."' + #10 +
    '        }' + #10 +
    '      ],' + #10 +
    '      "level": "A"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "attribute-usage-invalid",' + #10 +
    '      "name": "Attribute used incorrectly",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A compiler attribute is used where Delphi rejects it: [Weak] on a field or variable whose type is certainly neither a class nor an interface (built-in value types, records, enume' +
    'rations, sets, arrays, pointer types of the file, aliases followed; like E2584), [Volatile] on a type, routine, method or property (E2325), Weak, Unsafe, Volatile or Ref twice on the same declaration ' +
    '(E2326; branches that exclude each other do not count), or an attribute argument that is certainly a variable or a routine of the file (E2448; visible before the attribute, not shadowed by a constant,' +
    ' type or other declaration of the same name). Custom attributes may be repeated; a type Weak or WeakAttribute declared in the file keeps the rule silent for that name. No quick fix.",' + #10 +
    '      "bad": "TCounter = class\nprivate\n  [Weak] FCount: Integer;\nend;",' + #10 +
    '      "good": "TCounter = class\nprivate\n  [Weak] FOwner: IInterface;\n  FCount: Integer;\nend;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2325",' + #10 +
    '        "E2326",' + #10 +
    '        "E2448",' + #10 +
    '        "E2584"' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "typeinfo-invalid",' + #10 +
    '      "name": "TypeInfo or Default with an invalid argument",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "TypeInfo or Default receives a variable instead of a type (like E2133, E2537: parameters, local, inline and unit variables, fields, properties, Result, for and exception variable' +
    's), TypeInfo receives a type without RTTI (enumeration with explicit values, file type, Text/TextFile; E2134), or Default receives a file type (E2538). Names are resolved from the inside out; inside w' +
    'ith, in helpers, in methods of types outside the file, for declarations in other conditional branches and when the file or the index declares its own TypeInfo or Default the rule stays silent. Quick f' +
    'ix: insert the variable''s declared type.",' + #10 +
    '      "bad": "Name := GetEnumName(TypeInfo(Status), Ord(Status));",' + #10 +
    '      "good": "Name := GetEnumName(TypeInfo(TStatus), Ord(Status));",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2133",' + #10 +
    '        "E2134",' + #10 +
    '        "E2537",' + #10 +
    '        "E2538"' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "missing-begin-end",' + #10 +
    '      "name": "Condition or loop without begin … end",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "The body of if … then, else, for, while or with is a single statement without begin … end. With the rule, conditions and loops always have a block, so a second statement added la' +
    'ter does not end up outside by accident. else if stays allowed (the inner if needs no block of its own); repeat … until, case … end, try … end and asm … end are blocks already. An empty statement (if ' +
    'X then ;) is reported by empty-statement. Bodies with {$IFDEF} are not reported. While the rule is on, redundant-begin-end reports nothing. Quick fixes: put begin … end around the statement, for the w' +
    'hole method or for the whole file, indented by the format settings; a ; before else moves into the block (no E2153); with format.elsePlacement \"sameLine\", else follows the new end on the same line (' +
    'end else).",' + #10 +
    '      "bad": "if Kunde.Gesperrt then\n  Protokoll.Warnung(''Gesperrt'')\nelse\n  Speichern(Kunde);",' + #10 +
    '      "good": "if Kunde.Gesperrt then\nbegin\n  Protokoll.Warnung(''Gesperrt'');\nend\nelse\nbegin\n  Speichern(Kunde);\nend;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "statements",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [' + #10 +
    '            "if",' + #10 +
    '            "else",' + #10 +
    '            "for",' + #10 +
    '            "while",' + #10 +
    '            "with"' + #10 +
    '          ],' + #10 +
    '          "description": "Checked statements; add case for the branches of case statements."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "allowSingleLineExit",' + #10 +
    '          "type": "boolean",' + #10 +
    '          "default": false,' + #10 +
    '          "description": "Allow Exit, Continue, Break and raise on the same line as the condition (if … then Exit;)."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "allowSameLine",' + #10 +
    '          "type": "boolean",' + #10 +
    '          "default": false,' + #10 +
    '          "description": "Allow a single statement on the same line as the condition or loop header."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "inherited-constructor-after-try",' + #10 +
    '      "name": "Inherited constructor only inside try",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A constructor enters a try block before it has called the inherited constructor (like H2505). Self is not initialised there yet; an exception in the block can hit half-created fi' +
    'elds. Calls count as the inherited constructor when they are inherited without a name, with the constructor''s own name or with a name starting with Create. Branches of {$IFDEF} are checked separately.' +
    ' Quick fix when the call is the first statement of the try block: move it before try.",' + #10 +
    '      "bad": "constructor TDienst.Create;\nbegin\n  try\n    inherited Create;\n    FListe := TList<TAuftrag>.Create;",' + #10 +
    '      "good": "constructor TDienst.Create;\nbegin\n  inherited Create;\n  try\n    FListe := TList<TAuftrag>.Create;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "H2505"' + #10 +
    '      ],' + #10 +
    '      "level": "A"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "variant-record-managed-field",' + #10 +
    '      "name": "Managed type in the variant part of a record",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "The variant part of a record (case … of) holds a string, dynamic array, interface, Variant or a record with such fields (like E2154), a custom managed record with class operator ' +
    'Initialize or Finalize (like E2418), or a type parameter without record constraint (like E2569); likewise after file of (like E2155, E2417). Types are resolved in the file and the index; unknown types' +
    ' stay silent. Quick fixes: move the field before case into the fixed part, use ShortString, or constrain the type parameter with record.",' + #10 +
    '      "bad": "TWert = record\n  case Art: TArt of\n    waZahl: (Zahl: Double);\n    waText: (Text: string);\nend;",' + #10 +
    '      "good": "TWert = record\n  Text: string;\n  case Art: TArt of\n    waZahl: (Zahl: Double);\nend;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2154",' + #10 +
    '        "E2155",' + #10 +
    '        "E2418",' + #10 +
    '        "E2417",' + #10 +
    '        "E2569"' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "guid-syntax-invalid",' + #10 +
    '      "name": "GUID with invalid syntax",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "The GUID of an interface or of a typed TGUID constant is not of the form ''{8-4-4-4-12}'' (like E2204): missing braces, wrong number or length of blocks, characters that are not he' +
    'x digits, often after editing by hand. Only single literals are checked; concatenations and constants stay silent. Quick fixes: generate a new GUID; when only the braces are missing, add them. Complem' +
    'ents interface-guid and duplicate-interface-guid.",' + #10 +
    '      "bad": "ILogger = interface\n  [''{6A1F3B2C-9D4E-4F5A-8B7C-1D2E3F4A5B6}'']",' + #10 +
    '      "good": "ILogger = interface\n  [''{6A1F3B2C-9D4E-4F5A-8B7C-1D2E3F4A5B6C}'']",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2204"' + #10 +
    '      ],' + #10 +
    '      "level": "A"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "untyped-pointer-refcount",' + #10 +
    '      "name": "Untyped pointer bypasses reference counting",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "An interface is assigned through a typecast to Pointer (Pointer(FIntf) := P, like W1070). Reference counting does not take part: the object is freed too early or never. The rule ' +
    'reports only when name resolution knows the interface type for sure; strings (string, AnsiString …) are reported as well, with the note \"dcc does not report this\", since Delphi warns about them only' +
    ' under NEXTGEN. Fields that already carry [weak] or [unsafe] stay silent. Quick fixes for an interface field of this file with Pointer(Y) or nil on the right: mark the field [weak] or [unsafe] and ass' +
    'ign without Pointer.",' + #10 +
    '      "bad": "Pointer(FBesitzer) := Pointer(Besitzer);",' + #10 +
    '      "good": "[weak] FBesitzer: IBesitzer;\n…\nFBesitzer := Besitzer;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "W1070"' + #10 +
    '      ],' + #10 +
    '      "level": "T"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "type-too-large",' + #10 +
    '      "name": "Type exceeds a size limit",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A static array or record is 2 GB or larger (like E2100), or an instance of a generic type of this file is (like E2543). Atlas computes a lower bound from the declarations: index ' +
    'ranges via constant expressions, constants and enumerations of the file, built-in types, records from the index; unknown parts count as 0, so the rule reports only for sure. Only the innermost type th' +
    'at crosses the limit is reported. E2419 (records over 1 MB) applies only to Delphi for .NET and is not reported. No quick fix; use a dynamic array or a pointer instead.",' + #10 +
    '      "bad": "type TPuffer = array[0..High(Integer)] of Int64;",' + #10 +
    '      "good": "type TPuffer = array of Int64;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2100",' + #10 +
    '        "E2543"' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "comparison-always-constant",' + #10 +
    '      "name": "Comparison always true or always false",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A comparison of a variable, field, property or function result of a built-in integer type with a constant outside or at the edge of its value range (like W1021, W1022): Cardinal ' +
    '>= 0 is always true, Byte > 255 always false. Case labels outside the range of the case expression are reported as well (like W1018). The rule only reports when the type is known for sure and its decl' +
    'aration is always compiled together with the comparison. NativeInt, LongInt and their unsigned counterparts count with the widest range of all platforms; subrange types are not reported. Length(...) <' +
    ' 0 and Length(...) >= 0 are reported as well, although dcc does not warn there; the message says so.",' + #10 +
    '      "bad": "while Rest >= 0 do  // Rest: Cardinal",' + #10 +
    '      "good": "while Rest > 0 do",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "W1021",' + #10 +
    '        "W1022",' + #10 +
    '        "W1018"' + #10 +
    '      ],' + #10 +
    '      "level": "T"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "constant-initializer-mismatch",' + #10 +
    '      "name": "Initializer of a constant does not match",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A typed constant or initialized variable of a static array type has more or fewer elements than its index range (like E2072), typically after adding a value to an enumeration (ar' +
    'ray[TStatus] of string); checked per dimension and for named array types of the file. Record constants whose fields are in a different order than declared are reported as well (like E2083). Index rang' +
    'es: subranges with constant bounds, enumerations without own values, Boolean, Byte, Char and so on. Declarations with conditional directives count as unsure. Quick fixes: add the missing entries with ' +
    'a placeholder (name of the enumeration value as a comment), put the fields in the order of the declaration.",' + #10 +
    '      "bad": "StatusText: array[TStatus] of string = (''Neu'', ''Offen'', ''Geschlossen'');  // TStatus has 4 values",' + #10 +
    '      "good": "StatusText: array[TStatus] of string = (''Neu'', ''Offen'', ''Geschlossen'', ''''{stArchiviert});",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2072",' + #10 +
    '        "E2083"' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "case-selector-not-ordinal",' + #10 +
    '      "name": "case or for without an ordinal type",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "case over an expression that is not ordinal (like E2001): strings, floating point numbers, classes and interfaces; a for loop whose counter is not ordinal (like E2032); case labe' +
    'ls and array bounds that are variables, fields, properties, parameters or typed constants instead of constants (like E2026). The rule only reports when the type is known for sure and its declaration i' +
    's always compiled together with the statement. Quick fix for strings whose labels are all string literals: case IndexStr(S, [...]) of with the positions as labels, System.StrUtils is added to uses.",' + #10 +
    '      "bad": "case Befehl of ''start'': Starten; ''stop'': Stoppen; end;  // Befehl: string",' + #10 +
    '      "good": "case IndexStr(Befehl, [''start'', ''stop'']) of 0: Starten; 1: Stoppen; end;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2001",' + #10 +
    '        "E2032",' + #10 +
    '        "E2026"' + #10 +
    '      ],' + #10 +
    '      "level": "T"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "suspicious-string-pointer-cast",' + #10 +
    '      "name": "Pointer and character width of a string do not match",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "PChar or PWideChar on an AnsiString, RawByteString or UTF8String, and PAnsiChar on a string, UnicodeString or WideString (like W1044): pointer and character width do not match, a' +
    ' typical mistake after the Unicode migration; the API then reads garbage or only the first character. The rule only reports when the type of the argument is known for sure and its declaration is alway' +
    's compiled together with the cast. string(PAnsiChar) converts correctly and a pointer to TBytes may be intended; both are not reported. Quick fixes: declare an own variable with the matching string ty' +
    'pe (PChar(Pfad) with Pfad: AnsiString becomes Pfad: string), wrap the argument in string(...) or AnsiString(...), use the matching pointer type.",' + #10 +
    '      "bad": "var Pfad: AnsiString; ... DeleteFile(PChar(Pfad));",' + #10 +
    '      "good": "var Pfad: string; ... DeleteFile(PChar(Pfad));",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "W1044",' + #10 +
    '        "W1048"' + #10 +
    '      ],' + #10 +
    '      "level": "T"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "inaccessible-member",' + #10 +
    '      "name": "Access to a member that is not visible",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "Access A.B to a member that is not visible at that point: private or strict private of another unit or class (like E2361), protected or strict protected outside the declaring uni' +
    't and its descendants (like E2362, E2389). Inside a class method or static method, an instance field, method or property of the class is not reachable (like E2124). A property that refers to a private' +
    ' member of an ancestor in the same unit is reported as a warning (like W1045). The rule only reports when name resolution knows the receiver and its type for sure and finds the member only without reg' +
    'ard to visibility; protected members stay visible through a class declared in the same unit (TAccess(Control).Click). Declarations in conditional branches, methods of helpers and nested types stay sil' +
    'ent.",' + #10 +
    '      "bad": "class function TKonfig.Standard: TKonfig;\nbegin\n  Result := TKonfig.Create;\n  Result.Pfad := FBasisPfad;\nend;",' + #10 +
    '      "good": "class function TKonfig.Standard: TKonfig;\nbegin\n  Result := TKonfig.Create;\n  Result.Pfad := Result.FBasisPfad;\nend;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2361",' + #10 +
    '        "E2362",' + #10 +
    '        "E2389",' + #10 +
    '        "E2124",' + #10 +
    '        "W1045"' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unused-private-member",' + #10 +
    '      "name": "Private member never used",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A private or strict private field, method, constant or property is never used in the unit (like H2219, which the compiler only reports for methods; fields too unless includeField' +
    's is off). Any occurrence of the name as an identifier counts as a use, also in inactive conditional branches and behind read/write; declarations and method headers do not. Exempt: methods with messag' +
    'e, virtual, dynamic, override or abstract, methods of types that implement interfaces, constructors and destructors, members with attributes (RTTI), names from the form file and units with include fil' +
    'es. Quick fix: remove the declaration (with its /// documentation) and the body of a method; not when several members share the declaration or the method is overloaded.",' + #10 +
    '      "bad": "  TImport = class\n  private\n    FAltFormat: Boolean;\n    procedure KonvertiereAlt;\n  end;",' + #10 +
    '      "good": "  TImport = class\n  private\n  end;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "H2219"' + #10 +
    '      ],' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "includeFields",' + #10 +
    '          "type": "boolean",' + #10 +
    '          "default": true,' + #10 +
    '          "description": "Also report private fields that are never used (the compiler reports only methods)."' + #10 +
    '        }' + #10 +
    '      ],' + #10 +
    '      "level": "A"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unused-public-member",' + #10 +
    '      "name": "Public member never used in the project",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "A public or published method, constant or property (optionally also protected members, fields and class variables, and unit-level routines and constants of the interface section)' +
    ' is used nowhere in the projects of the project group. The search is project-wide via the symbol index: only files whose index usages contain the name are parsed, and every occurrence is resolved by n' +
    'ame resolution; an occurrence that cannot be resolved counts as a use. Names in form files (.dfm/.fmx) and in string literals count as uses. Considered used: interface implementations and members of i' +
    'nterfaces, virtual, dynamic, override, abstract and message methods, constructors, destructors, operators, enumerators, default properties, implements, members with attributes, published members of TP' +
    'ersistent descendants (streaming), of classes registered with RegisterComponents, RegisterClass or RegisterClasses and of test fixtures, published methods while a form file cannot be read, property ac' +
    'cessors, exported routines, class helpers, members of classes with an unknown ancestor. Silent while projects are loading or the index is incomplete, when a file cannot be read, for units with include' +
    ' files and for units of packages or libraries (external users) unless projectKinds allows them. Quick fix: mark as intentionally public (lsp-ignore comment).",' + #10 +
    '      "bad": "  TExport = class\n  public\n    procedure ExportiereAlsXml;\n  end;\n// ExportiereAlsXml is called nowhere in the project group",' + #10 +
    '      "good": "  TExport = class\n  public\n    procedure ExportiereAlsJson; // called by TMainForm\n  end;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "visibilities",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [' + #10 +
    '            "public",' + #10 +
    '            "published"' + #10 +
    '          ],' + #10 +
    '          "description": "Visibilities that are checked: public, published, protected."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "memberKinds",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [' + #10 +
    '            "method",' + #10 +
    '            "constant",' + #10 +
    '            "property"' + #10 +
    '          ],' + #10 +
    '          "description": "Member kinds that are checked: method, constant, property, field, classVar."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "projectKinds",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [' + #10 +
    '            "application"' + #10 +
    '          ],' + #10 +
    '          "description": "Project kinds whose units are checked: application, package, library. Packages and libraries have users outside the project group, so they are off by default."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "unitLevel",' + #10 +
    '          "type": "boolean",' + #10 +
    '          "default": true,' + #10 +
    '          "description": "Also check routines and constants declared in the interface section of a unit."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "scope",' + #10 +
    '          "type": "string",' + #10 +
    '          "default": "projectGroup",' + #10 +
    '          "description": "Where uses are searched: projectGroup (all projects of the group) or project (only the projects of the file)."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "testsCountAsUse",' + #10 +
    '          "type": "boolean",' + #10 +
    '          "default": true,' + #10 +
    '          "description": "Uses in test projects count; when off, a member used only by tests is reported as such."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "stringLiteralsCountAsUse",' + #10 +
    '          "type": "boolean",' + #10 +
    '          "default": true,' + #10 +
    '          "description": "The name as a string literal (''Name'') counts as a use (RTTI, MethodAddress, scripts)."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "keepAttributes",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [],' + #10 +
    '          "description": "Attributes on the member or its type that mark it as used, e.g. \"Keep\" or \"Api\"."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "keepPatterns",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [],' + #10 +
    '          "description": "Name patterns (* and ?) for members that are always considered used, e.g. \"TPlugin.*\" or \"*Callback\"."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "message-method-invalid",' + #10 +
    '      "name": "Message method declared incorrectly",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A message procedure of a class does not have exactly one var parameter (like E2138; the parameter type is not checked, an untyped var parameter is fine), its message number is le' +
    'ss than 1 (like E2139), or an earlier message method of the same class already handles the same number (like E2140, usually after copying). Numbers count as equal when their values are known (numbers,' +
    ' constants from the index) or when the expressions are the same text. Methods in mutually exclusive {$IF} branches are not duplicates; the same number in a descendant overrides the handler and is fine' +
    '. Quick fix for E2138: make a single parameter var, otherwise replace the list with (var Msg: TMessage); the method body in the same file is adjusted as well.",' + #10 +
    '      "bad": "procedure WMSize(var Msg: TWMSize); message WM_SIZE;\nprocedure WMGroesse(var Msg: TWMSize); message WM_SIZE;",' + #10 +
    '      "good": "procedure WMSize(var Msg: TWMSize); message WM_SIZE;\nprocedure WMMove(var Msg: TWMMove); message WM_MOVE;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2138",' + #10 +
    '        "E2139",' + #10 +
    '        "E2140"' + #10 +
    '      ],' + #10 +
    '      "level": "A"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "interface-declaration-invalid",' + #10 +
    '      "name": "Invalid declaration in an interface",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "An interface type declares something interfaces cannot have: fields (like E2209), visibility sections or method directives such as virtual, dynamic, abstract, override, message o' +
    'r reintroduce (like E2210), the property clauses stored, nodefault or default with a value (like E2207; default; after an array property is fine), a property an ancestor interface already declares (li' +
    'ke E2206) or a property accessor that only the ancestor interface declares (like E2370). A class, record or enumeration as the ancestor of an interface or in the interface list of a class is reported ' +
    'as well (like E2205), and so is the same interface twice in that list (like E2208). Types are resolved through the uses clauses; aliases, unknown types, dispinterfaces and declarations inside conditio' +
    'nal branches stay silent.",' + #10 +
    '      "bad": "IKunde = interface\n  FName: string;\n  function GetName: string;\nend;",' + #10 +
    '      "good": "IKunde = interface\n  function GetName: string;\n  property Name: string read GetName;\nend;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2205",' + #10 +
    '        "E2206",' + #10 +
    '        "E2207",' + #10 +
    '        "E2208",' + #10 +
    '        "E2209",' + #10 +
    '        "E2210",' + #10 +
    '        "E2370"' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "implements-clause-invalid",' + #10 +
    '      "name": "Invalid implements clause",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "Delegation with implements breaks one of its fixed rules: implements only in classes (like E2258), only on properties of class or interface type (like E2259; reported for built-i' +
    'n types, records and enumerations), not together with index (like E2260), only on readable properties (like E2261), the getter without a calling convention other than register (like E2262) and not dyn' +
    'amic or message (like E2263), each interface implemented by one property only (like E2257) and no method resolution clause for an interface implemented that way (like E2264). Types are resolved throug' +
    'h the uses clauses; unknown types, aliases and properties in conditional branches stay silent.",' + #10 +
    '      "bad": "property Logger: ILogger write FLogger implements ILogger;",' + #10 +
    '      "good": "property Logger: ILogger read FLogger write FLogger implements ILogger;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2257",' + #10 +
    '        "E2258",' + #10 +
    '        "E2259",' + #10 +
    '        "E2260",' + #10 +
    '        "E2261",' + #10 +
    '        "E2262",' + #10 +
    '        "E2263",' + #10 +
    '        "E2264"' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "calling-convention-required",' + #10 +
    '      "name": "Calling convention does not fit",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "The compiler prescribes the calling convention here: constructors and destructors of a class only with register (like E2236), getters and setters of published properties as well ' +
    '(like E2270), and varargs only with cdecl (like E2277 for external routines, otherwise E2591). Explicit register is fine; class constructors, accessors outside published sections and inherited accesso' +
    'rs stay silent. Quick fix: remove the convention in the declaration and in the method body of the same file, or set cdecl for varargs.",' + #10 +
    '      "bad": "function Formatieren(Muster: PAnsiChar): Integer; stdcall; varargs; external ''msvcrt.dll'';",' + #10 +
    '      "good": "function Formatieren(Muster: PAnsiChar): Integer; cdecl; varargs; external ''msvcrt.dll'';",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2236",' + #10 +
    '        "E2270",' + #10 +
    '        "E2277",' + #10 +
    '        "E2591"' + #10 +
    '      ],' + #10 +
    '      "level": "A"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "abstract-declaration-invalid",' + #10 +
    '      "name": "abstract, final or static combined wrongly",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A method directive the compiler rejects: abstract without virtual, dynamic or override (like E2167), a body in the implementation section for an abstract method (like E2136), fin' +
    'al on a method that is not virtual (like E2351), abstract together with final (like E2371), a class declared abstract sealed (like E2383, E2540) or static on an instance method or a virtual class meth' +
    'od (like E2376). A body only counts for an abstract method when no non-abstract method of the same name in the same class is compiled with it (overloads, {$IFDEF} branches). Quick fixes: insert virtua' +
    'l; before abstract, remove the body.",' + #10 +
    '      "bad": "TForm = class\n  function Flaeche: Double; abstract;\nend;",' + #10 +
    '      "good": "TForm = class\n  function Flaeche: Double; virtual; abstract;\nend;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2167",' + #10 +
    '        "E2136",' + #10 +
    '        "E2351",' + #10 +
    '        "E2371",' + #10 +
    '        "E2383",' + #10 +
    '        "E2540",' + #10 +
    '        "E2376"' + #10 +
    '      ],' + #10 +
    '      "level": "A"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unsatisfied-forward",' + #10 +
    '      "name": "Forward declaration never satisfied",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A routine declared in the interface section or with forward has no body (like E2065), or a forward declaration TFoo = class; or IFoo = interface; is never completed in the same t' +
    'ype section (like E2086, E2420). Methods are checked by declared-not-implemented. A body fits when it has the same name; with overload the number of parameters must match too. An external declaration ' +
    'in the implementation section counts as a body. Declarations inside a {$IFDEF} branch are skipped; with include files the rule does not check routines. Quick fix: create an empty body before initializ' +
    'ation or the final end.",' + #10 +
    '      "bad": "interface\n\nfunction Pruefsumme(const Daten: TBytes): Cardinal;\n\nimplementation\n\nend.",' + #10 +
    '      "good": "interface\n\nfunction Pruefsumme(const Daten: TBytes): Cardinal;\n\nimplementation\n\nfunction Pruefsumme(const Daten: TBytes): Cardinal;\nbegin\n  Result := 0;\nend;\n\nend.",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2065",' + #10 +
    '        "E2086",' + #10 +
    '        "E2420"' + #10 +
    '      ],' + #10 +
    '      "level": "A"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "member-hides-ancestor",' + #10 +
    '      "name": "Member hides a member of the ancestor",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A property has the name of a field of an ancestor (like W1009), a field has the name of a field or property of an ancestor, or a non-virtual method has the name and parameters of' +
    ' a non-virtual method of an ancestor. Code that accesses the object through the ancestor type still sees the old member. Virtual methods are reported by hides-virtual, local names by shadowed-name. Re' +
    'published properties (property Caption;), properties with a new type over an ancestor property, overload, reintroduce, constructors and class methods are not reported. Members the descendant cannot se' +
    'e (private in another unit, strict private with ignoreStrictPrivate) are skipped; ancestors come from the file and the symbol index. Quick fix for fields and properties: rename the member in the class' +
    ' declaration and the bodies of its methods in this unit (FName becomes FKundeName).",' + #10 +
    '      "bad": "TBasis = class\n  FName: string;\nend;\nTKunde = class(TBasis)\n  FName: string;\nend;",' + #10 +
    '      "good": "TBasis = class\n  FName: string;\nend;\nTKunde = class(TBasis)\n  FKundeName: string;\nend;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "W1009"' + #10 +
    '      ],' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "ignoreStrictPrivate",' + #10 +
    '          "type": "boolean",' + #10 +
    '          "default": true,' + #10 +
    '          "description": "Do not report hidden strict private members of the ancestor."' + #10 +
    '        }' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "published-type-invalid",' + #10 +
    '      "name": "Invalid member in the published section",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A member behind an explicit published that the compiler rejects: a property of a record, array, pointer or plain procedural type (like E2188), of type Real48 (like E2186) or of a' +
    ' set larger than 4 bytes (like E2187), a field that is neither a class nor an interface (like E2217), more than one published overload (like E2266), a class property (like E2545) or a name with non-AS' +
    'CII characters (like E2452). Types are resolved through the file and the index, aliases are followed; type parameters, unknown types and sections whose published is in another conditional branch than ' +
    'the member stay silent. The section without visibility specifier is not checked, because the compiler silently demotes such members to public there. Quick fix: move the member into the public section.' +
    '",' + #10 +
    '      "bad": "TKarte = class(TCustomControl)\npublished\n  property Mitte: TPointF read FMitte write SetMitte;\nend;",' + #10 +
    '      "good": "TKarte = class(TCustomControl)\npublic\n  property Mitte: TPointF read FMitte write SetMitte;\nend;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2188",' + #10 +
    '        "E2217",' + #10 +
    '        "E2186",' + #10 +
    '        "E2187",' + #10 +
    '        "E2266",' + #10 +
    '        "E2545",' + #10 +
    '        "E2452"' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "override-case-mismatch",' + #10 +
    '      "name": "Spelling or visibility differs from the ancestor",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "An overriding method spells its name differently from the ancestor (destructor destroy, like H2365) or has a lower visibility than the overridden method (like H2269, only for cla' +
    'sses in the interface section; visibilities are compared in tiers private, protected, public), a getter or setter is named Get<Property> or Set<Property> but spelled differently (like H2367), or an in' +
    'line method accesses a member that is less visible than the method itself, so the compiler cannot expand it outside the class (like H2440). Matters for C++Builder users of the units and for consistent' +
    ' code. The docwiki lists H2269 and H2367 as X2269 and X2367 because their level can be changed; dcc reports them as hints by default. H2368 and H2369 are not covered, since it is not documented when d' +
    'cc reports them. Off by default; switch it on in atlas.json. Quick fixes: adopt the ancestor''s spelling, rename the accessor.",' + #10 +
    '      "bad": "TKunde = class\n  destructor destroy; override;\nend;",' + #10 +
    '      "good": "TKunde = class\n  destructor Destroy; override;\nend;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "H2365",' + #10 +
    '        "H2440",' + #10 +
    '        "H2269",' + #10 +
    '        "H2367"' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "default-property-invalid",' + #10 +
    '      "name": "default property declared wrongly or missing",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "default; behind a property without index parameters (like E2132), a second default property of the same class with the same index types (like E2131; overloading by index type is ' +
    'allowed), or Obj[I] on a class that has no default property in its whole ancestor chain (like E2149). The type of Obj is resolved by name resolution; unresolvable types, broken ancestor chains and cla' +
    'sses with a class helper in the unit stay silent. Property redeclarations without a type (property Items; default;) take the index from the ancestor and are not checked.",' + #10 +
    '      "bad": "TListe = class\n  property Name: string read FName; default;\nend;",' + #10 +
    '      "good": "TListe = class\n  property Items[I: Integer]: string read GetItem; default;\nend;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2131",' + #10 +
    '        "E2132",' + #10 +
    '        "E2149"' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "property-redeclaration-invalid",' + #10 +
    '      "name": "Redeclared property missing in the ancestor",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A property redeclaration without type such as property Caption; (to change the visibility or the default value) names a property that no ancestor has (like E2147), or the ancesto' +
    'r''s property is not accessible from here: strict private, or private in another unit (like E2233). Only reported when the whole ancestor chain is known; a field or method of the same name and declarat' +
    'ions in inactive conditional branches stay silent. Quick fix: use the most similar property name of the ancestors.",' + #10 +
    '      "bad": "TMeinPanel = class(TCustomPanel)\npublished\n  property Captoin;\nend;",' + #10 +
    '      "good": "TMeinPanel = class(TCustomPanel)\npublished\n  property Caption;\nend;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2147",' + #10 +
    '        "E2233"' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "inline-not-expanded",' + #10 +
    '      "name": "Inline function is not expanded",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A call of an inline routine from another unit that the compiler does not expand: its body needs a unit that is missing from uses here (like H2443, typically System.Generics.Colle' +
    'ctions for TJSONObject.Count), it accesses a strict private member and the call is not inside a method of that class (like H2444), the calling routine is inline itself and the unit of the callee is on' +
    'ly in the implementation uses (like H2445), or the unit of the callee uses this unit directly (like H2456) or through other units (like H2457). Calls, properties with an inline getter or setter and fo' +
    'r-in loops (GetEnumerator, MoveNext, Current) are checked. The index records what each inline body refers to; the rule only reports what it resolves for sure (unknown references and members inherited ' +
    'from other units stay silent). Silent with {$INLINE OFF} in the file. Quick fix: add the missing units to the uses clause of the section.",' + #10 +
    '      "bad": "uses\n  System.JSON;\n...\nfor Wert in Feld as TJSONArray do",' + #10 +
    '      "good": "uses\n  System.JSON, System.Generics.Collections;\n...\nfor Wert in Feld as TJSONArray do",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "H2443",' + #10 +
    '        "H2444",' + #10 +
    '        "H2445",' + #10 +
    '        "H2456",' + #10 +
    '        "H2457"' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "directive-typo",' + #10 +
    '      "name": "Unknown directive (typo)",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A word that is not a directive stands where a directive belongs: after the '';'' of a routine or method header (overide;, virutal;, overlaod;, stdcal;, reintroduces;) or after a pr' +
    'operty, where only default is allowed (defualt;). The compiler stops there (like E2070). The message suggests the closest directive when at most two characters differ. Silent in {$IF} branches that te' +
    'st FPC, which knows further directives such as nostackframe. Quick fix: replace with the suggested directive.",' + #10 +
    '      "bad": "procedure Paint; overide;",' + #10 +
    '      "good": "procedure Paint; override;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2070"' + #10 +
    '      ],' + #10 +
    '      "level": "A"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "ui-call-in-console-or-service",' + #10 +
    '      "name": "Dialog in a console program or service",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "robustness",' + #10 +
    '      "description": "ShowMessage, ShowMessageFmt, MessageDlg, TaskMessageDlg, InputBox, InputQuery, Application.MessageBox or TDialogService in a program with {$APPTYPE CONSOLE} (or DCC_ConsoleTarget' +
    ' in the .dproj), in a Windows service or in a DLL without forms. In a service the dialog blocks invisibly; a console program waits for a click nobody sees when it runs unattended. A service is a unit ' +
    'with a class derived from TService, or any unit of a project whose .dpr uses Vcl.SvcMgr without Vcl.Forms. A DLL without forms is a library whose .dpr lists no form and does not use Vcl.Forms; there t' +
    'he rule reports with medium confidence, because only the host decides whether there is a user interface. Units with a form file, calls under if IsConsole and routines of the same name declared in the ' +
    'unit stay silent. Counterpart of writeln-in-gui-app. High confidence. No quick fix: log the message instead of showing it.",' + #10 +
    '      "bad": "procedure TDatenDienst.ServiceExecute(Sender: TService);\nbegin\n  if not Verbinden then\n    ShowMessage(''Keine Verbindung'');\nend;",' + #10 +
    '      "good": "procedure TDatenDienst.ServiceExecute(Sender: TService);\nbegin\n  if not Verbinden then\n    LogMessage(''Keine Verbindung'', EVENTLOG_ERROR_TYPE);\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "load-without-encoding",' + #10 +
    '      "name": "Loading or saving text without an encoding",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "robustness",' + #10 +
    '      "description": "LoadFromFile, SaveToFile, LoadFromStream or SaveToStream of a TStrings (TStringList, Memo.Lines, ListBox.Items, Query.SQL) and TFile.ReadAllText or TFile.ReadAllLines without an ' +
    'encoding: a file without BOM is read with the ANSI code page of the machine, and SaveToFile writes ANSI, so umlauts get lost between machines. The receiver must be a declared string list or a Lines, I' +
    'tems, SQL or Strings property; bitmaps, streams and datasets stay silent. Also silent when the list sets DefaultEncoding anywhere in the unit or was loaded with an encoding earlier in the same routine' +
    ' (SaveToFile then keeps that encoding). TFile.WriteAllText, TStreamReader and TStreamWriter already default to UTF-8 and are not reported. Medium confidence. Quick fix: add TEncoding.UTF8 (option defa' +
    'ultEncoding) as the last argument and System.SysUtils to uses.",' + #10 +
    '      "bad": "Zeilen.LoadFromFile(Pfad);",' + #10 +
    '      "good": "Zeilen.LoadFromFile(Pfad, TEncoding.UTF8);",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "defaultEncoding",' + #10 +
    '          "type": "string",' + #10 +
    '          "default": "UTF8",' + #10 +
    '          "description": "TEncoding property the quick fix inserts: UTF8, Unicode, BigEndianUnicode, ANSI, ASCII, UTF7 or Default."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "registry-hklm-write",' + #10 +
    '      "name": "Writing to HKEY_LOCAL_MACHINE",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "robustness",' + #10 +
    '      "description": "RootKey := HKEY_LOCAL_MACHINE on a TRegistry followed in the same routine by a writing access on the same object: OpenKey(…, True), CreateKey, Write…, DeleteKey, DeleteValue, Ren' +
    'ameValue, MoveKey, SaveKey or RestoreKey. Without administrator rights this fails or silently lands in the registry virtualization. Use HKEY_CURRENT_USER for user settings; exclude installer code thro' +
    'ugh exclude. Reading (OpenKeyReadOnly, Read…, OpenKey(…, False)), another RootKey before the write and writes in the other branch of {$IFDEF} stay silent. High confidence. Quick fix: RootKey := HKEY_C' +
    'URRENT_USER.",' + #10 +
    '      "bad": "Reg.RootKey := HKEY_LOCAL_MACHINE;\nReg.OpenKey(''Software\\Firma\\Programm'', True);\nReg.WriteString(''Sprache'', Sprache);",' + #10 +
    '      "good": "Reg.RootKey := HKEY_CURRENT_USER;\nReg.OpenKey(''Software\\Firma\\Programm'', True);\nReg.WriteString(''Sprache'', Sprache);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "now-for-elapsed-time",' + #10 +
    '      "name": "Elapsed time measured with Now",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "A variable set to Now and later used in Now - Start, End - Start or MilliSecondsBetween, SecondsBetween, MinutesBetween, HoursBetween, DaysBetween or the …Span functions in the s' +
    'ame routine: it measures elapsed time with the wall clock, which is coarse and wrong across daylight saving changes or clock synchronisation. TStopwatch is precise and monotonic. Assignments in anothe' +
    'r routine (fields) and in the other branch of {$IFDEF} stay silent. High confidence. Quick fix when the variable is a local TDateTime (also var Start := Now) used only for MilliSecondsBetween, Seconds' +
    'Between or MinutesBetween with Now: TStopwatch.StartNew and ElapsedMilliseconds (div 1000 or div 60000), the variable becomes Uhr when the name is free, System.Diagnostics is added to uses.",' + #10 +
    '      "bad": "Start := Now;\nImportieren;\nLog(MilliSecondsBetween(Now, Start).ToString + '' ms'');",' + #10 +
    '      "good": "Uhr := TStopwatch.StartNew;\nImportieren;\nLog(Uhr.ElapsedMilliseconds.ToString + '' ms'');"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "money-as-float",' + #10 +
    '      "name": "Money amount as floating point",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "Field, variable, parameter or property whose name denotes a money amount (option namePatterns) with type Double, Single, Extended or Real: binary floating point rounds cent amoun' +
    'ts wrongly (0.1 + 0.2), Currency calculates them exactly. The last part of the name counts (GesamtPreis, Nettobetrag, FNetto, Preise; not NettoGewicht); rates, factors, quotas, shares (Steuersatz, Pri' +
    'ceFactor) and checksums stay silent. Ambiguous words (Amount, Summe, Sum, Total: a quantity or sum of anything) only count with a money context in the type or routine: another money name, Currency or ' +
    'words like Cent, Euro, Rabatt, Invoice, Payment, Kosten (Lighten(AColor, AAmount: Double) stays silent). Off by default and low confidence: it shows up once the rule is switched on and minConfidence i' +
    's low. Quick fix when all names of the declaration are money amounts: type Currency, for parameters also in the header of the implementation, for fields and properties also the property or the field b' +
    'ehind read and write; no fix when a getter or setter would have to change too. With checkRound the rule also reports Round with a money amount in the argument (banker''s rounding: 2.5 becomes 2).",' + #10 +
    '      "bad": "TPosition = record\n  Menge: Integer;\n  Preis: Double;\nend;",' + #10 +
    '      "good": "TPosition = record\n  Menge: Integer;\n  Preis: Currency;\nend;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "namePatterns",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [' + #10 +
    '            "Betrag",' + #10 +
    '            "Preis",' + #10 +
    '            "Summe",' + #10 +
    '            "Netto",' + #10 +
    '            "Brutto",' + #10 +
    '            "Steuer",' + #10 +
    '            "Amount",' + #10 +
    '            "Price"' + #10 +
    '          ],' + #10 +
    '          "description": "Name parts that denote a money amount; plurals included."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "checkRound",' + #10 +
    '          "type": "boolean",' + #10 +
    '          "default": false,' + #10 +
    '          "description": "Also report Round on money amounts."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "string-if-chain",' + #10 +
    '      "name": "Long if chain over the same string",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "An if … else if chain that compares the same string (identifier or A.B, no function calls) with at least min literals: S = ''x'', ''x'' = S, SameText(S, ''x''), also combined with or, ' +
    'in at least two branches (a single if with or stays silent). case IndexStr(S, [...]) of or a dictionary is shorter and faster. Only comparisons that are always compiled together with the head count ({' +
    '$IFDEF} branches inside the chain do not). Off by default, high confidence. Quick fix as in the code action if chain to case (#646): case IndexStr(…) of, IndexText(…) for SameText, comparisons joined ' +
    'with or share one label, the rest of the chain becomes else, System.StrUtils is added to uses. No fix when comments or directives sit between the branches, a literal appears twice or = and SameText ar' +
    'e mixed.",' + #10 +
    '      "bad": "if Befehl = ''neu'' then Neu\nelse if Befehl = ''oeffnen'' then Oeffnen\nelse if Befehl = ''speichern'' then Speichern\nelse if Befehl = ''beenden'' then Beenden;",' + #10 +
    '      "good": "case IndexStr(Befehl, [''neu'', ''oeffnen'', ''speichern'', ''beenden'']) of\n  0: Neu;\n  1: Oeffnen;\n  2: Speichern;\n  3: Beenden;\nend;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "min",' + #10 +
    '          "type": "integer",' + #10 +
    '          "default": 4,' + #10 +
    '          "description": "Number of comparisons of the same string from which the rule reports; at least 2."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "prefer-case",' + #10 +
    '      "name": "if chain can be written as case",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "An if … else if chain with at least min branches (the final else counts) that compares the same ordinal expression (integer, character, enumeration; no side effects, no function ' +
    'call) with constants: X = a, a = X, X in [a, b..c], (X >= a) and (X <= b), also combined with or. Labels must be literals, constant expressions, untyped constants or enumeration values, without duplic' +
    'ates or overlaps. The type comes from name resolution; chains with unknown types and chains with directives stay silent. Off by default, high confidence. Quick fix: the code action In case umwandeln (' +
    '#646, refactoring.ifCase); begin … end only where a branch has several statements, comments in the branches stay.",' + #10 +
    '      "bad": "if Kind = 1 then Neu\nelse if (Kind = 2) or (Kind = 3) then Oeffnen\nelse if (Kind >= 4) and (Kind <= 6) then Speichern\nelse Beenden;",' + #10 +
    '      "good": "case Kind of\n  1: Neu;\n  2, 3: Oeffnen;\n  4..6: Speichern;\nelse\n  Beenden;\nend;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "min",' + #10 +
    '          "type": "integer",' + #10 +
    '          "default": 4,' + #10 +
    '          "description": "Number of branches (the final else included) from which the rule reports; at least 2."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "constant-condition",' + #10 +
    '      "name": "Condition is always the same",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "The condition of if, while or until is fixed: True, False, comparisons of numbers and untyped constants of the file, also through and, or, xor and not (X or True is always true, ' +
    'X and False always false). The branch is dead code or always runs. while True do and repeat … until False count as deliberate endless loops (infinite-loop checks their exit). Constants listed in switc' +
    'hConstants, constants inside a {$IF…} branch and constants from other units count as unknown. Quick fix for if: remove the dead branch or the condition.",' + #10 +
    '      "bad": "if (Count > 0) or True then\n  Process;",' + #10 +
    '      "good": "if Count > 0 then\n  Process;",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "switchConstants",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [],' + #10 +
    '          "description": "Constants that deliberately serve as switches; conditions on them are not reported."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "infinite-loop",' + #10 +
    '      "name": "Loop without exit",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "while True do, repeat … until False or another loop whose condition never ends it, without an exit in the body: no Break (a Break in a nested loop only leaves that loop), Exit, r' +
    'aise, goto, Halt, Abort or RunError, no call of a routine of the file that raises an exception or ends the program, and no check of Terminated (thread loops are covered by thread-loop-without-terminat' +
    'ed). Anonymous methods in the body do not count. The action jumps to the loop head.",' + #10 +
    '      "bad": "while True do\nbegin\n  Line := Reader.ReadLine;\n  Process(Line);\nend;",' + #10 +
    '      "good": "while not Reader.EndOfStream do\nbegin\n  Line := Reader.ReadLine;\n  Process(Line);\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "loop-condition-unchanged",' + #10 +
    '      "name": "Loop condition never changes in the body",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "No variable of the while or until condition changes in the body: no assignment, no Inc/Dec, no argument (possibly var), no method or member access on the object of the condition,' +
    ' no for loop over it. Typically a forgotten Inc(I) or Next. The rule only reports when every variable of the condition is a local variable or value parameter of the routine and at least one appears di' +
    'rectly (not only as X.Property). Conditions with function calls, fields, global variables, var and out parameters and Terminated are not reported, nor loops with an exit (Break, Exit, raise …), waitin' +
    'g loops (Sleep, ProcessMessages …), with, calls of local routines or variables captured by an anonymous method. Changes through X[…] count only when the condition reads X[…].",' + #10 +
    '      "bad": "I := 0;\nwhile I < List.Count do\nbegin\n  Check(List[I]);\nend;",' + #10 +
    '      "good": "I := 0;\nwhile I < List.Count do\nbegin\n  Check(List[I]);\n  Inc(I);\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unconditional-recursion",' + #10 +
    '      "name": "Recursion without a stop",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "A routine calls itself on every path before it can return: there is no path without a self-call and no Exit or raise before it. The result is a stack overflow. Paths without a ca' +
    'll are: an if without else or a case without else, the body of while and for, the right side of and/or, branches of if expressions and anonymous methods. Getters and setters of their own property are ' +
    'reported by setter-recursion; overloaded routines stay silent (the call may go to another overload). The margin marker from #623 shows every recursion.",' + #10 +
    '      "bad": "function TTree.Depth(N: TNode): Integer;\nbegin\n  Result := 1 + Max(Depth(N.Left), Depth(N.Right));\nend;",' + #10 +
    '      "good": "function TTree.Depth(N: TNode): Integer;\nbegin\n  if N = nil then\n    Exit(0);\n  Result := 1 + Max(Depth(N.Left), Depth(N.Right));\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "pos-arguments-swapped",' + #10 +
    '      "name": "Arguments of Pos swapped",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "Pos(Text, '';''): Pos, PosEx, AnsiPos, StartsText, StartsStr, EndsText and EndsStr (also with Ansi prefix) expect the searched part first and the text second; ContainsText and Cont' +
    'ainsStr expect the text first. Reported when a short literal (up to maxLiteralLength characters, default 3; '''' counts as one character, #9 as well) stands where the text belongs and a certain string s' +
    'tands where the part belongs: a variable or field of a string type declared in the file, .Text or .Caption, a string function of the RTL (Trim, UpperCase, Copy-like LeftStr, Format …) or a concatenati' +
    'on with a string part. Characters stay silent, because Pos(C, '';,'') deliberately checks whether C is one of the separators; so do unknown types, two literals and methods of other objects (Liste.Pos). ' +
    'Medium confidence. Quick fix: swap the arguments in one edit; comments between them stay.",' + #10 +
    '      "bad": "if Pos(Zeile, '';'') > 0 then",' + #10 +
    '      "good": "if Pos('';'', Zeile) > 0 then",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "maxLiteralLength",' + #10 +
    '          "type": "integer",' + #10 +
    '          "default": 3,' + #10 +
    '          "description": "Longest literal in the place of the text that is still taken as swapped."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "integer-division-to-float",' + #10 +
    '      "name": "Integer division assigned to a floating-point number",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "Average := Sum div Count with Average: Double: div cuts off the fraction before the value is assigned. Also Percent := Part div Total * 100, Result of a function with a floating-' +
    'point result and var X: Double := A div B. The div is searched through parentheses, signs and + - * /, not inside calls (Round(A div B)), indexes, mod or comparisons. The target must be a variable, fi' +
    'eld (also Self.X) or Result whose type Single, Double, Extended, Real, Currency … is declared in the file. TDateTime, TDate and TTime stay silent (whole days are usually intended there), as do assignm' +
    'ents inside with and Trunc(A) div Trunc(B) (also Round, Floor, Ceil: explicitly converted, so integer division is intended). High confidence. Quick fix: replace div with / (same precedence).",' + #10 +
    '      "bad": "var Average: Double;\n…\nAverage := Sum div Count;",' + #10 +
    '      "good": "var Average: Double;\n…\nAverage := Sum / Count;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "empty-finally",' + #10 +
    '      "name": "Empty finally block",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "A finally block without statements: usually the release got lost during a rework. If the statement right before try is X := T….Create, the message names X.Free. A block with an e' +
    'xplaining comment counts as deliberate and is not reported (as with empty-except); a block with a compiler directive is skipped as well, because another branch may contain code. High confidence. Quick' +
    ' fix: remove try, finally and end and outdent the body (when try, finally and end each stand on their own line); as the only statement of an if, while, for, with or case branch with several statements' +
    ' in the body, try becomes begin.",' + #10 +
    '      "bad": "Liste := TStringList.Create;\ntry\n  Liste.LoadFromFile(Pfad);\nfinally\nend;",' + #10 +
    '      "good": "Liste := TStringList.Create;\ntry\n  Liste.LoadFromFile(Pfad);\nfinally\n  Liste.Free;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "form-resource-missing",' + #10 +
    '      "name": "Form unit without {$R *.dfm}",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "forms",' + #10 +
    '      "description": "A .dfm or .fmx lies next to the unit and the unit declares the class of its root object, but no {$R …} directive includes a form file: creating the form raises EResNotFound. Conv' +
    'ersely, a {$R *.dfm} or {$R Name.dfm} whose file does not exist next to the unit is reported (the compiler stops with F1026). A directive in any branch of conditional compilation counts as included. S' +
    'ilent when the form file''s class is not declared in the unit and when the rule cannot see files next to the unit. Quick fix: insert {$R *.dfm} (or {$R *.fmx}) after implementation.",' + #10 +
    '      "bad": "implementation\n\nprocedure TfrmKunde.FormShow(Sender: TObject);",' + #10 +
    '      "good": "implementation\n\n{$R *.dfm}\n\nprocedure TfrmKunde.FormShow(Sender: TObject);",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "F1026"' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "form-autocreate-and-manual",' + #10 +
    '      "name": "Form created automatically and by hand",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "forms",' + #10 +
    '      "description": "The .dpr creates a form with Application.CreateForm, and the code also assigns TfrmX.Create(…) to the same global variable. There are then two instances; the first one stays invi' +
    'sible in memory. The automatically created forms come from the .dpr of the project the unit belongs to; when the rule can read the .dpr, the class must match the CreateForm call. Silent when the routi' +
    'ne checks the variable (Assigned, comparison with nil) or frees it before (Free, FreeAndNil, Release), for local names and for fields of the own class with the same name, and for units without a proje' +
    'ct. High confidence. Quick fix: remove the Application.CreateForm line from the .dpr (the form is then only created by the code).",' + #10 +
    '      "bad": "// Projekt.dpr: Application.CreateForm(TfrmBericht, frmBericht);\nfrmBericht := TfrmBericht.Create(Application);\nfrmBericht.ShowModal;",' + #10 +
    '      "good": "// Projekt.dpr without CreateForm for TfrmBericht\nfrmBericht := TfrmBericht.Create(Application);\nfrmBericht.ShowModal;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "inherited-form-handler-without-inherited",' + #10 +
    '      "name": "Event handler in an inherited form without inherited",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "forms",' + #10 +
    '      "description": "With form inheritance, an ancestor form assigns a handler of the same name to the same event of the same component, but the handler in the descendant does not call inherited (any' +
    ' more). The IDE generates inherited; when the handler is created; once it is deleted, the logic of the ancestor is lost silently. The ancestor''s form file comes from the index (file of the class) or f' +
    'rom the units in the uses clause next to the unit; the chain follows inherited forms up to the first form with object. Handlers with a different name count as a deliberate replacement. Silent without ' +
    'the ancestor''s form file. High confidence. Quick fix: insert inherited; at the start.",' + #10 +
    '      "bad": "procedure TfrmKundeBearbeiten.btnSpeichernClick(Sender: TObject);\nbegin\n  FKunde.Speichern;\nend;",' + #10 +
    '      "good": "procedure TfrmKundeBearbeiten.btnSpeichernClick(Sender: TObject);\nbegin\n  inherited;\n  FKunde.Speichern;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "self-free-in-event-handler",' + #10 +
    '      "name": "Form frees itself in its own event",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "forms",' + #10 +
    '      "description": "Free, Destroy, DisposeOf or FreeAndNil on Self, or on the global variable of the form''s own class, as a statement in an event handler of the form or one of its controls. After th' +
    'e handler returns, the VCL still accesses the object: access violation. Correct is Release, or Action := caFree in OnClose. Event handlers are the methods named in the form file and methods with a Sen' +
    'der: TObject parameter; a form is the root class of the form file with ClientWidth or ClientHeight, or a class derived directly from TForm or TCustomForm (frames and data modules have no Release). Sta' +
    'tements in anonymous methods and with blocks do not count. Silent without the form file. High confidence. Quick fix: replace Free with Release; in OnClose (var Action: TCloseAction) with Action := caF' +
    'ree.",' + #10 +
    '      "bad": "procedure TfrmMeldung.btnOKClick(Sender: TObject);\nbegin\n  Free;\nend;",' + #10 +
    '      "good": "procedure TfrmMeldung.btnOKClick(Sender: TObject);\nbegin\n  Release;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "parallel-for-shared-write",' + #10 +
    '      "name": "Shared variable written in TParallel.For",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "threads",' + #10 +
    '      "description": "The body of TParallel.For, or of a TTask.Run/Create/Future started inside a loop, writes a variable from outside without a lock: Summe := Summe + …, Inc/Dec or another assignment' +
    ', or changes a collection from outside (Add, Delete, Clear, Insert, Remove …). The iterations run at the same time, so additions get lost or the list is corrupted. Outside means a local variable or pa' +
    'rameter of the enclosing routine, a field of its class or a global variable of the unit; names of unknown origin stay silent. Bodies with a lock (TMonitor, Enter, Acquire, Lock, LockList, BeginWrite, ' +
    'TInterlocked), writes through an index (Werte[I] := …) and nested anonymous methods (Synchronize, Queue) do not count. Types listed in threadSafeTypes count as thread-safe. Medium confidence. Quick fi' +
    'xes: TInterlocked.Add/Increment/Decrement for Integer, Int64 and Cardinal (adds System.SyncObjs), System.TMonitor.Enter/Exit in try … finally around the collection call.",' + #10 +
    '      "bad": "TParallel.For(0, High(Werte), procedure(I: Integer)\n  begin\n    Summe := Summe + Werte[I];\n  end);",' + #10 +
    '      "good": "TParallel.For(0, High(Werte), procedure(I: Integer)\n  begin\n    TInterlocked.Add(Summe, Werte[I]);\n  end);",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "threadSafeTypes",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [' + #10 +
    '            "TThreadList",' + #10 +
    '            "TThreadedQueue"' + #10 +
    '          ],' + #10 +
    '          "description": "Types that count as thread-safe; their collection calls stay silent."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "thread-unsafe-increment",' + #10 +
    '      "name": "Counter in a thread without TInterlocked",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "threads",' + #10 +
    '      "description": "Inc, Dec, X := X + 1 or X := X - 1 without a lock on a global variable in Execute of a TThread descendant, or on a field or global variable in the body of TTask.Run/Create/Future' +
    ' outside loops and of TThread.CreateAnonymousThread. Inc is not atomic: when several threads count at the same time, increments get lost. Thread classes come from the unit (also through intermediate c' +
    'lasses) and from the index. Own fields of the thread in Execute and captured local variables of a single task have only one writer and stay silent, as do bodies with a lock (TMonitor, Enter, Acquire, ' +
    'Lock, LockList, BeginWrite, TInterlocked) and nested anonymous methods (Synchronize, Queue). Tasks inside loops and TParallel.For are reported by parallel-for-shared-write. Medium confidence. Quick fi' +
    'x: TInterlocked.Increment/Decrement/Add for Integer, Int64 and Cardinal (adds System.SyncObjs).",' + #10 +
    '      "bad": "procedure TArbeiter.Execute;\nbegin\n  while not Terminated do\n    if Holen then Inc(GVerarbeitet);\nend;",' + #10 +
    '      "good": "procedure TArbeiter.Execute;\nbegin\n  while not Terminated do\n    if Holen then TInterlocked.Increment(GVerarbeitet);\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "constant-expression-error",' + #10 +
    '      "name": "Error in a constant expression",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A constant expression divides by zero (like E2098), overflows beyond the range of Int64 and UInt64 (like E2099), a range has its low bound above its high bound (array[5..1], like' +
    ' E2011), a constant violates an integer type of fixed size or a subrange type (like W1012, reported as a warning; assignments only from values outside 0..127) or a hex, binary or octal literal needs m' +
    'ore than 64 bits (like E2102). Atlas evaluates literals, constants (also from other units) and SizeOf/High/Low of types with a fixed size; a constant from an {$IF} branch only counts where the checked' +
    ' place is compiled together with it. Expressions with unknown parts stay silent.",' + #10 +
    '      "bad": "const\n  Seiten = 0;\n  ProSeite = 100 div Seiten;",' + #10 +
    '      "good": "const\n  Seiten = 5;\n  ProSeite = 100 div Seiten;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2098",' + #10 +
    '        "E2099",' + #10 +
    '        "E2011",' + #10 +
    '        "W1012",' + #10 +
    '        "E2102"' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "default-parameter-invalid",' + #10 +
    '      "name": "Invalid default value of a parameter",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "Default values the compiler rejects: several names sharing one default value (A, B: Integer = 0, like E2237), a parameter without a default value after one with a default value (' +
    'like E2238), var and out parameters with a default value (like E2239) records or static arrays with a default value (like E2268) and sets larger than 4 bytes with a default value (like E2146, only sma' +
    'll sets are allowed; medium confidence). Applies to routines, methods and procedural types. Quick fixes: declare the parameters one by one; move the parameters with a default value to the end, also in' +
    ' the matching declaration or implementation header of the same file (calls are not changed).",' + #10 +
    '      "bad": "procedure Senden(const Text: string = ''''; Ziel: TZiel);",' + #10 +
    '      "good": "procedure Senden(Ziel: TZiel; const Text: string = '''');",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2237",' + #10 +
    '        "E2238",' + #10 +
    '        "E2239",' + #10 +
    '        "E2268",' + #10 +
    '        "E2146"' + #10 +
    '      ],' + #10 +
    '      "level": "A"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "signed-unsigned-mix",' + #10 +
    '      "name": "Signed and unsigned mixed",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "Comparison or arithmetic (+, -, *, div, mod) with one signed and one unsigned operand whose types are known for certain (variables, fields, properties, function results, own alia' +
    'ses). With UInt64 the whole expression is computed unsigned and a negative value becomes a huge number (like W1073, comparison like W1023); with Cardinal/DWORD and a signed type up to 32 bits both ope' +
    'rands are widened to Int64 (like W1023/W1024). Silent for Byte and Word, Cardinal with Int64, literals, constants, NativeInt/NativeUInt and unknown types. Medium confidence. Quick fix: convert the uns' +
    'igned operand to Int64.",' + #10 +
    '      "bad": "if Groesse + Delta < Grenze then  // Groesse: UInt64; Delta: Int64",' + #10 +
    '      "good": "if Int64(Groesse) + Delta < Grenze then",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "W1023",' + #10 +
    '        "W1024",' + #10 +
    '        "W1073"' + #10 +
    '      ],' + #10 +
    '      "level": "T"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "narrowing-assignment",' + #10 +
    '      "name": "Assignment with possible data loss",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "An assignment or an inline variable with a value whose type is wider than the target, without an explicit conversion: Int64 to Integer, NativeInt to Integer (Win64) and, via the ' +
    'option types, e.g. Double to Single or Extended to Double. Like W1071 (integers), W1072 (floating point) and W1066 (Extended to Double); the compiler shows W1071 only when switched on. Only reported w' +
    'hen both types are known for certain (variables, fields, properties, function results, own aliases and integer arithmetic built from them); literals and explicit conversions stay silent. Off by defaul' +
    't; medium confidence. Quick fixes: convert explicitly; widen the type of the target''s declaration (single variable declared in the same file).",' + #10 +
    '      "bad": "Anzahl := Strom.Size;  // Anzahl: Integer",' + #10 +
    '      "good": "Anzahl := Integer(Strom.Size);",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "W1071",' + #10 +
    '        "W1072",' + #10 +
    '        "W1066"' + #10 +
    '      ],' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "types",' + #10 +
    '          "type": "string-list",' + #10 +
    '          "default": [' + #10 +
    '            "Int64>Integer",' + #10 +
    '            "NativeInt>Integer"' + #10 +
    '          ],' + #10 +
    '          "description": "Reported pairs source type>target type, e.g. Double>Single or Extended>Double."' + #10 +
    '        }' + #10 +
    '      ],' + #10 +
    '      "level": "T"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "typed-constant-modified",' + #10 +
    '      "name": "Typed constant modified",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A typed constant (const Counter: Integer = 0) is assigned (like W1017, also an element or a record field of it) or passed as a var or out argument, including Inc, Dec, Include, E' +
    'xclude, Delete, SetLength and the like (like W1016). Usually a variable was meant; this only compiles with {$J+}. When {$J-} or {$WRITEABLECONST OFF} is in effect before the declaration in the same fi' +
    'le, it is reported as an error (like E2064 or E2197). Also reports 0 as the value of a pointer constant or an initialised pointer variable (like W1013). Quick fixes: turn a unit-level constant into a ' +
    'variable with an initial value (the const section is split if needed; local typed constants keep their value between calls and get no fix); write nil instead of 0.",' + #10 +
    '      "bad": "const\n  Zaehler: Integer = 0;\n…\nInc(Zaehler);",' + #10 +
    '      "good": "var\n  Zaehler: Integer = 0;\n…\nInc(Zaehler);",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "W1016",' + #10 +
    '        "W1017",' + #10 +
    '        "W1013",' + #10 +
    '        "E2064",' + #10 +
    '        "E2197"' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "string-length-limit",' + #10 +
    '      "name": "String limit exceeded",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A string literal is truncated to fit a string[N] or ShortString target: assignment, typed constant or initialised variable, also via own aliases, string[Constant] and fields from' +
    ' other units (like W1014). Before Delphi 12 (delphiVersion below 23) a quoted literal may have at most 255 characters (like E2056), and a resourcestring may have at most 4096 characters, literals join' +
    'ed with + included (like E2381); both are errors. Characters are counted as written, '''' and #13 count as one. Quick fixes: declare the target as string (single variable or typed constant of the same f' +
    'ile; record fields keep their size); split the literal into pieces of 255 characters joined with +.",' + #10 +
    '      "bad": "var Kennung: string[8];\n…\nKennung := ''KUNDE-2026-0001'';",' + #10 +
    '      "good": "var Kennung: string;\n…\nKennung := ''KUNDE-2026-0001'';",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "W1014",' + #10 +
    '        "E2056",' + #10 +
    '        "E2381"' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dynamic-array-misuse",' + #10 +
    '      "name": "New, Dispose or SetLength misused on a dynamic array",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "New (like E2255) or Dispose (like E2256) on a dynamic array, SetLength without a length (like E2246), New with a length on a type that is not a dynamic array (like E2307) and New' +
    '(TArrayType) without a length (like E2308). Typical for old code that switched from pointers to dynamic arrays. The rule only reports when name resolution knows the variable or type for sure; aliases ' +
    'are followed (TValues = array of Double), TBytes and the other dynamic arrays of the RTL count even without an index; open array parameters and pointers stay silent. Quick fixes: Dispose(A) becomes A ' +
    ':= nil, New(A) becomes SetLength(A, 1).",' + #10 +
    '      "bad": "Dispose(Werte);",' + #10 +
    '      "good": "Werte := nil;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2255",' + #10 +
    '        "E2256",' + #10 +
    '        "E2246",' + #10 +
    '        "E2307",' + #10 +
    '        "E2308"' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "local-routine-as-callback",' + #10 +
    '      "name": "Local routine as procedure variable",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A local (nested) routine is assigned to a variable or passed to a parameter of a procedural type without of object (like E2094), or a typed constant of a routine takes the addres' +
    's of a local variable (like E2278). Usually an anonymous method or a routine of the unit was meant. The rule only reports when name resolution knows the target type for sure; method pointers and metho' +
    'd references stay silent because the compiler reports them with other codes, and so does @Routine (an untyped pointer). Quick fix: move the routine in front of the enclosing routine as a routine of th' +
    'e unit, if it uses nothing from it (no local names further out, no class members without a prefix).",' + #10 +
    '      "bad": "procedure TListe.Sortieren;\n  function Vergleich(A, B: Pointer): Integer;\n  begin\n    Result := 0;\n  end;\nbegin\n  FListe.Sort(Vergleich);\nend;",' + #10 +
    '      "good": "function Vergleich(A, B: Pointer): Integer;\nbegin\n  Result := 0;\nend;\n\nprocedure TListe.Sortieren;\nbegin\n  FListe.Sort(Vergleich);\nend;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2094",' + #10 +
    '        "E2278"' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "hresult-integer-mix",' + #10 +
    '      "name": "Integer and HRESULT interchanged",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A class implements an interface method with an HRESULT result through a method with an Integer (or LongInt) result, or the other way round (like X1008). Both are 32 bits wide, so' +
    ' it goes unnoticed, but the meaning of the values (S_FALSE as success) is lost; important for COM and Open Tools API code. Methods are matched by name and parameter types, including resolution clauses' +
    ' such as function IFoo.Bar = Baz; interfaces and their ancestors come from the file or the index. If variants stand in conditional branches, the rule only reports when every variant differs. Quick fix' +
    ': align the result type in declaration and implementation with the interface.",' + #10 +
    '      "bad": "IExport = interface\n  function Schreiben: HRESULT; stdcall;\nend;\n…\n  function Schreiben: Integer; stdcall;",' + #10 +
    '      "good": "IExport = interface\n  function Schreiben: HRESULT; stdcall;\nend;\n…\n  function Schreiben: HRESULT; stdcall;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "X1008"' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "invalid-var-argument",' + #10 +
    '      "name": "Invalid argument for a var or out parameter",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A var or out parameter receives something that is not a variable: a string element for a character parameter (like E2354), a constant, a const parameter, a property or a function' +
    ' result (like E2197), a constant for an open array (like E2192), Slice (like E2454) or an expression (like E2036). Reported only for routines without overloads whose header is known from the file or t' +
    'he index; built-in routines such as Inc or Move and untyped var parameters accept more and stay silent. Typed constants count as constants unless {$J+} is set. Quick fix: pass a local variable of the ' +
    'parameter type, and write it back for string elements and properties with write.",' + #10 +
    '      "bad": "procedure Erhoehen(var Zeichen: Char);\n…\nErhoehen(Zeile[1]);",' + #10 +
    '      "good": "Zeichen := Zeile[1];\nErhoehen(Zeichen);\nZeile[1] := Zeichen;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2354",' + #10 +
    '        "E2197",' + #10 +
    '        "E2192",' + #10 +
    '        "E2454",' + #10 +
    '        "E2036"' + #10 +
    '      ],' + #10 +
    '      "level": "T"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "condition-not-boolean",' + #10 +
    '      "name": "Condition is not Boolean",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "The condition of if, while, until or a conditional expression has a type that is surely not Boolean: a number, a pointer, a class, an interface, a string or a character (like E20' +
    '12). Unlike C, Delphi needs a Boolean. Reported only when the type is certain; Boolean types such as LongBool, enumerations, aliases and unknown types stay silent. Quick fix: add <> 0 (alternative > 0' +
    '), <> nil (alternative Assigned), <> '''' or <> #0.",' + #10 +
    '      "bad": "if Liste.Count then\n  Verarbeiten;",' + #10 +
    '      "good": "if Liste.Count > 0 then\n  Verarbeiten;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2012"' + #10 +
    '      ],' + #10 +
    '      "level": "T"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "for-in-not-enumerable",' + #10 +
    '      "name": "for-in over a type without enumerator",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A for-in loop runs over a type that cannot be enumerated: a number, pointer, character or Boolean, or a class, record or interface without a public GetEnumerator, also not inheri' +
    'ted or from a helper (like E2430); or the enumerator returned by GetEnumerator lacks a public MoveNext or Current (like E2431). Strings, arrays and sets are fine. Reported only when the type and all i' +
    'ts ancestors are known; generic types and unknown types stay silent. No quick fix; if the type has Count, the message suggests an indexed loop.",' + #10 +
    '      "bad": "for F in Felder.Dataset do",' + #10 +
    '      "good": "for F in Felder do",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2430",' + #10 +
    '        "E2431"' + #10 +
    '      ],' + #10 +
    '      "level": "T"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "inherited-abstract-call",' + #10 +
    '      "name": "inherited calls an abstract method",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "inherited with an explicit method name, such as inherited Zeichnen(C), although the method is abstract in the ancestor (like E2373). A bare inherited; is skipped silently by the ' +
    'compiler for abstract methods and is not reported. The method is resolved by name resolution including overloads; the rule only reports when every matching overload is abstract. Quick fix: remove the ' +
    'call when it is a statement of its own in a begin…end block.",' + #10 +
    '      "bad": "procedure TKreis.Zeichnen(C: TCanvas);\nbegin\n  inherited Zeichnen(C);\n  C.Ellipse(FRahmen);\nend;",' + #10 +
    '      "good": "procedure TKreis.Zeichnen(C: TCanvas);\nbegin\n  C.Ellipse(FRahmen);\nend;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2373"' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "generic-constraint-violated",' + #10 +
    '      "name": "Type argument violates a constraint",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A type argument does not satisfy the constraint of its type parameter: class (like E2511), record (like E2512), constructor (like E2513), an interface (like E2514) or a base clas' +
    's (like E2515). Inside methods of a generic type of this file the rule also reports T.Create without a constructor constraint (like E2568) and method calls on values of a type parameter without any co' +
    'nstraint (like E2571). The generic type is resolved by name resolution including the number of type parameters, its constraints come from its declaration in the file or in the symbol index. Arguments ' +
    'that are type parameters themselves, aliases and types whose ancestry cannot be resolved are not reported. Quick fix for a type parameter of this file that stands alone in its group: add the constrain' +
    't (T: class, constructor or T: class).",' + #10 +
    '      "bad": "  TFabrik<T: class> = class\n    function Neu: T;\n  end;\n…\n  Result := T.Create;",' + #10 +
    '      "good": "  TFabrik<T: class, constructor> = class\n    function Neu: T;\n  end;\n…\n  Result := T.Create;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2511",' + #10 +
    '        "E2512",' + #10 +
    '        "E2513",' + #10 +
    '        "E2514",' + #10 +
    '        "E2515",' + #10 +
    '        "E2568",' + #10 +
    '        "E2571"' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unresolved-type",' + #10 +
    '      "name": "Type in a declaration not found",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A type name in a declaration (field, parameter, result, ancestor, interface list, variable, type argument) is not declared (like E2003, for the target of a pointer type like E256' +
    '4) or is not a type (like E2005). Complements unresolved-identifier, which only checks statements. Same preconditions as unresolved-attribute: System in the symbol index, every unit from uses known, n' +
    'ot inside {$IF…} blocks. Type parameters, names the file declares as a type anywhere (also nested) and names the index knows as a nested type (inherited inner types) are not reported. Quick fix: add t' +
    'he unit that declares the type (with the same number of type parameters) to uses.",' + #10 +
    '      "bad": "uses\n  System.SysUtils;\ntype\n  TKunden = TObjectList<TKunde>;",' + #10 +
    '      "good": "uses\n  System.SysUtils, System.Generics.Collections;\ntype\n  TKunden = TObjectList<TKunde>;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2564",' + #10 +
    '        "E2563",' + #10 +
    '        "E2005",' + #10 +
    '        "E2003"' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "class-reference-nonvirtual-constructor",' + #10 +
    '      "name": "Constructor called through a class reference is not virtual",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "Create called through a class reference (class of TBasis) whose constructor is not virtual. On Win32 and Win64 this compiles silently but always runs the constructor of TBasis: f' +
    'ields that descendants set up in their own constructors stay empty (like E2391). The receiver may be a variable, field, parameter or function result whose type is a class reference; the constructor is' +
    ' resolved by name resolution in the nearest class that declares it, including overloads by argument count. The rule stays silent when a matching overload is virtual, dynamic, override or abstract, whe' +
    'n a declaration lies in another branch of conditional compilation, and when a type cannot be resolved. Quick fix when the constructor is declared in this file: virtual on it and override on the constr' +
    'uctors with the same signature in descendants in this file.",' + #10 +
    '      "bad": "type\n  TPluginKlasse = class of TPlugin;\n  TPlugin = class\n    constructor Create;\n  end;\n...\n  P := Klasse.Create;",' + #10 +
    '      "good": "type\n  TPluginKlasse = class of TPlugin;\n  TPlugin = class\n    constructor Create; virtual;\n  end;\n  TSpezial = class(TPlugin)\n    constructor Create; override;\n  end;\n...\n  P ' +
    ':= Klasse.Create;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2391"' + #10 +
    '      ],' + #10 +
    '      "level": "B"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "jump-outside-allowed-scope",' + #10 +
    '      "name": "Break, Continue or Exit in a place where it is not allowed",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "Break or Continue outside a loop (like E2097), or Break, Continue or Exit that leave a finally block (like E2126). Delphi only reports both when compiling; it happens often after' +
    ' moving a loop body into a method of its own. A loop that lies entirely inside the finally block may use Break and Continue. Routines and anonymous methods start afresh: a Break in an anonymous method' +
    ' does not belong to the loop around it. Only plain calls are reported (not TMonitor.Exit(FLock)), and not when the file declares a routine or variable of that name. Quick fix outside a finally block: ' +
    'replace Break with Exit.",' + #10 +
    '      "bad": "if Eintrag.Treffer then\n  Break;",' + #10 +
    '      "good": "if Eintrag.Treffer then\n  Exit;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2097",' + #10 +
    '        "E2126"' + #10 +
    '      ],' + #10 +
    '      "level": "A"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "reraise-outside-handler",' + #10 +
    '      "name": "raise without an argument outside a handler",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "raise; without an exception object is only allowed in an except block (like E2145); Delphi only reports it when compiling. It happens in a local procedure called from the handler' +
    ', in a finally block or after moving code. Routines and anonymous methods start afresh. The rule stays silent in anonymous methods inside an except block and in routines where the parser reports an er' +
    'ror. No quick fix: raise a new exception (raise EImport.Create(…)) or move the code into the handler. reraise-exception-object covers raise E; inside the handler.",' + #10 +
    '      "bad": "Protokoll.Fehler(''Import abgebrochen'');\nraise;",' + #10 +
    '      "good": "Protokoll.Fehler(''Import abgebrochen'');\nraise EImportAbgebrochen.Create(''Import abgebrochen'');",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2145"' + #10 +
    '      ],' + #10 +
    '      "level": "A"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "label-misuse",' + #10 +
    '      "name": "Label used incorrectly",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A label is set twice (like E2073), declared and jumped to but never set (E2074), set or jumped to without being declared in the current routine (E2093; a goto to a label declared' +
    ' nowhere and never set is reported by the syntax rule as E2031), or goto jumps into or out of a try block, also between the try part and its except or finally part (E2127). Delphi only reports these w' +
    'hen compiling. Labels belong to one routine or the program block; a local procedure cannot jump to a label of the routine around it. Duplicate labels in conditional branches that exclude each other st' +
    'ay silent, as do routines with an asm block, because labels inside asm are not in the syntax tree. No quick fix.",' + #10 +
    '      "bad": "label Weiter;\nbegin\n  try\n    if Fertig then goto Weiter;\n  finally\n    Aufraeumen;\n  end;\nWeiter:\nend;",' + #10 +
    '      "good": "begin\n  try\n    if Fertig then Exit;\n  finally\n    Aufraeumen;\n  end;\nend;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2073",' + #10 +
    '        "E2074",' + #10 +
    '        "E2093",' + #10 +
    '        "E2127"' + #10 +
    '      ],' + #10 +
    '      "level": "A"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "for-variable-misuse",' + #10 +
    '      "name": "Loop variable changed or not local",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "The variable of a for loop is assigned in the body or changed with Inc/Dec (like E2081), passed as a var or out parameter to a routine of this file (like W1015), or is not a simp' +
    'le local variable: a field of the own class, a global variable of the unit or a local variable of the enclosing routine (like E1019). Delphi only reports these when compiling. Parameters, unknown name' +
    's and loops inside with statements stay silent, as do anonymous methods in the body and routines with parser errors. Quick fixes: convert to a while loop (not when the body uses Continue), or use for ' +
    'var when the routine does not use the name otherwise.",' + #10 +
    '      "bad": "for I := 0 to Zeilen.Count - 1 do\nbegin\n  if Zeilen[I] = '''' then\n    Inc(I);\nend;",' + #10 +
    '      "good": "I := 0;\nwhile I <= Zeilen.Count - 1 do\nbegin\n  if Zeilen[I] = '''' then\n    Inc(I);\n  Inc(I);\nend;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2081",' + #10 +
    '        "W1015",' + #10 +
    '        "E1019"' + #10 +
    '      ],' + #10 +
    '      "level": "A"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "for-variable-after-loop",' + #10 +
    '      "name": "Loop variable read after the loop",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "After a for loop that ends normally (without Break), the loop variable is undefined. The rule reports the first read of the variable on a path from the normal loop exit, before i' +
    't is assigned again (like W1037). Only simple local variables of the routine are checked; for var loops, fields, globals, reads only inside the body, arguments of routines that might be out parameters' +
    ', and routines whose control flow is incomplete stay silent. Quick fix: convert to a while loop, where the counter has a defined value afterwards.",' + #10 +
    '      "bad": "for I := 0 to High(Werte) do\n  if Werte[I] = Gesucht then\n    Break;\nGefunden := I <= High(Werte);",' + #10 +
    '      "good": "I := 0;\nwhile I <= High(Werte) do\nbegin\n  if Werte[I] = Gesucht then\n    Break;\n  Inc(I);\nend;\nGefunden := I <= High(Werte);",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "W1037"' + #10 +
    '      ],' + #10 +
    '      "level": "A"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "argument-count-mismatch",' + #10 +
    '      "name": "Wrong number of arguments",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A call passes more arguments than the routine has parameters (like E2034) or fewer than its parameters without default value (like E2035), also as a statement without parentheses' +
    '. Checked only when the name resolves to exactly one routine: overloads, varargs, typecasts, variables of procedural type, System identifiers without source and declarations in conditional branches ar' +
    'e left to the compiler (E2250). A function called with too many arguments is only reported when its result type is known and not procedural. Quick fix: Signature help opens the parameter hint inside t' +
    'he parentheses (adds () when missing).",' + #10 +
    '      "bad": "Versenden(Kunde.Mail, ''Rechnung'');",' + #10 +
    '      "good": "Versenden(Kunde.Mail, ''Rechnung'', Text);",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2034",' + #10 +
    '        "E2035"' + #10 +
    '      ],' + #10 +
    '      "level": "T"' + #10 +
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
    '      "description": "Der Quelltext lässt sich nicht lesen. Die Meldung nennt wie der Compiler, was erwartet und was gefunden wurde („'';'' erwartet, aber ''end'' gefunden (wie E2029).“), und trägt den Co' +
    'mpilercode: fehlendes '';'' (E2066 zwischen Anweisungen, E2029 in Deklarationen), '';'' vor else (E2153), offener String (E2052) oder Kommentar mit Startzeile (E2057), Anweisungen im interface-Teil (E2050' +
    '), Bezeichner nach einem Punkt am Ende (E2372), strict ohne private oder protected (E2375), class vor etwas anderem als einer Routine (E2357), try ohne except oder finally (E2125), for ohne Variable (' +
    'E2088). Prüfungen am fertigen Baum: procedure mit Ergebnistyp (E2025), Deklaration einer function ohne Ergebnistyp (E2023; die Kurzform der Implementierung ist erlaubt), Wertparameter ohne Typ (E2067)' +
    ', lokale Variable mit Anfangswert (E2195) oder mehrere Variablen mit einem Anfangswert (E2196), Klassen-, Interface- oder Objekttyp im var-Abschnitt (E2060, E2058) oder lokal in einer Routine (E2061, ' +
    'E2059), label im interface-Teil (E2049) und goto auf eine nicht deklarierte Marke (E2031; eine Marke der umgebenden Routine meldet label-misuse als E2093). Nach einem offenen String oder Kommentar fal' +
    'len die Folgefehler weg, weil der Compiler dort abbricht. Inaktive {$IFDEF}-Zweige werden nicht gemeldet. Korrekturen: '';'' vor else entfernen (sicher, auch beim Speichern), '';'' ergänzen, String schlie' +
    'ßen, Kommentar am Ende seiner ersten Zeile schließen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unused-suppression",' + #10 +
    '      "name": "Ungenutzte Unterdrückung",' + #10 +
    '      "description": "Ein lsp-ignore-Kommentar unterdrückt keinen Treffer und kann entfernt werden."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unknown-rule-id",' + #10 +
    '      "name": "Unbekannte Regelkennung",' + #10 +
    '      "description": "Ein lsp-ignore-Kommentar nennt eine Regelkennung, die es nicht gibt, und unterdrückt deshalb nichts. Die Meldung schlägt die ähnlichste bekannte Kennung vor (Tippfehler); ein sol' +
    'cher Kommentar zählt nicht zusätzlich als unused-suppression."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unit-too-deep",' + #10 +
    '      "name": "Unit zu tief für die Prüfung",' + #10 +
    '      "description": "Der Syntaxbaum der Unit ist mehr als 100000 Ebenen tief; die Prüfregeln laufen für sie nicht. So tiefe Bäume entstehen nur aus Ketten mit ebenso vielen Gliedern wie X := A - B - ' +
    'C - … Der Hinweis markiert die tiefste Stelle; wer die Kette in Teilausdrücke aufteilt, macht die Unit wieder prüfbar."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "bidi-control",' + #10 +
    '      "name": "Bidirektionales Steuerzeichen",' + #10 +
    '      "description": "Bidirektionale Steuerzeichen können Code anders anzeigen, als er kompiliert wird (Trojan Source); auch in Formulardateien. Richtungsmarken in RTL-Text nur mit niedriger Konfidenz' +
    '."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "invisible-char",' + #10 +
    '      "name": "Unsichtbares Zeichen",' + #10 +
    '      "description": "Unsichtbare oder Nullbreiten-Zeichen im Quelltext und in Formulardateien; in Strings und Kommentaren mittlere Konfidenz."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "control-char",' + #10 +
    '      "name": "Steuerzeichen",' + #10 +
    '      "description": "NUL- und Steuerzeichen oder ungültige UTF-8-Bytes im Quelltext und in der Formulardatei; ungültige Bytes mit genauer Zeile und Spalte."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "confusable-identifier",' + #10 +
    '      "name": "Verwechselbarer Bezeichner",' + #10 +
    '      "description": "Bezeichner mit Zeichen aus mehreren Schriften oder Nicht-ASCII-Zeichen sind mit anderen verwechselbar."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "forbidden-uses",' + #10 +
    '      "name": "Verbotene uses-Beziehung",' + #10 +
    '      "description": "Ein uses-Eintrag verletzt eine Schichtregel unter \"layers\" in atlas.json, z. B. darf *.Common.* nicht Vcl.* verwenden.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "layers",' + #10 +
    '          "description": "Schichtregeln: [{\"from\": Glob, \"deny\": [Globs], \"allow\": [Globs]}]."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "architecture-role-import",' + #10 +
    '      "name": "Import verletzt die Rollenmatrix",' + #10 +
    '      "description": "Ein uses-Eintrag verletzt die Importmatrix des Rollenkonzepts (Ausgabeartefakt, Feature, Rolle: Contract, Internals, Providers, Adapters, Composition, Hosting). Standardmäßig aus' +
    '; in atlas.json mit der Option \"prefixes\" einschalten. Genehmigte Ausnahmen stehen unter \"allow\" als \"Quelle -> Ziel\"-Globs.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "prefixes",' + #10 +
    '          "description": "Präfixe der Ausgabeartefakte, z. B. \"Atlas.Common\"; ohne Angabe meldet die Regel nichts."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "hostRoles",' + #10 +
    '          "description": "Erste Namenssegmente der Host-Units ohne Präfix."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "allow",' + #10 +
    '          "description": "Genehmigte Ausnahmen \"Quelle -> Ziel\" (beide Globs)."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "architecture-contract-content",' + #10 +
    '      "name": "Klasse in einer Contract-Unit",' + #10 +
    '      "description": "Eine Contract-Unit deklariert im interface eine Klasse. Contracts enthalten nur Records, Interfaces, Aufzählungen und Ausnahmen. Standardmäßig aus; in atlas.json mit der Option \' +
    '"prefixes\" einschalten. Genehmigte Ausnahmen stehen unter \"allow\" als \"Unit.Typ\"-Globs.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "prefixes",' + #10 +
    '          "description": "Präfixe der Ausgabeartefakte, z. B. \"Atlas.Common\"."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "allow",' + #10 +
    '          "description": "Genehmigte Ausnahmen \"Unit.Typ\" als Glob."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "thread-vcl-access",' + #10 +
    '      "name": "VCL-Zugriff aus einem Thread",' + #10 +
    '      "description": "TThread.Execute, TThread.CreateAnonymousThread oder TTask greift außerhalb von Synchronize oder Queue auf die VCL zu (Application, Screen, ShowMessage, MessageDlg …). Die VCL ist' +
    ' nicht threadsicher."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "lock-without-finally",' + #10 +
    '      "name": "Sperre ohne try/finally",' + #10 +
    '      "description": "Auf eine Sperre (TCriticalSection.Enter/Acquire, TMonitor.Enter, BeginRead/BeginWrite, TSpinLock.Enter, TMutex.Acquire, EnterCriticalSection oder ein Paar aus der Option lockPair' +
    's) folgt kein try/finally mit der Freigabe. Eine Ausnahme lässt die Sperre gesetzt.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "lockPairs",' + #10 +
    '          "description": "Weitere Sperrpaare als [[\"Sperren\", \"Freigeben\"]]."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "thread-use-after-free-on-terminate",' + #10 +
    '      "name": "Thread nach dem Start mit FreeOnTerminate benutzt",' + #10 +
    '      "description": "Ein Thread mit FreeOnTerminate := True kann sich gleich nach dem Start selbst freigeben; danach greift die Variable womöglich auf ein freigegebenes Objekt zu."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "thread-free-with-free-on-terminate",' + #10 +
    '      "name": "Free auf einem Thread mit FreeOnTerminate",' + #10 +
    '      "description": "Free auf einem Thread mit FreeOnTerminate := True gibt ihn doppelt frei."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "synchronize-in-destructor",' + #10 +
    '      "name": "Synchronize im Destruktor eines Threads",' + #10 +
    '      "description": "Synchronize im Destruktor eines TThread-Nachfahren (oder in einer Methode, die er aufruft) verklemmt sich: Der Hauptthread wartet in WaitFor, der Thread auf Synchronize."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "thread-resume-suspend",' + #10 +
    '      "name": "Veraltetes TThread.Resume/Suspend",' + #10 +
    '      "description": "TThread.Resume und Suspend sind veraltet. Einen erzeugten Thread mit Start starten; Suspend hat keinen sicheren Ersatz, stattdessen mit einem Ereignis warten."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "result-not-set",' + #10 +
    '      "name": "Funktionsergebnis eventuell nicht gesetzt",' + #10 +
    '      "description": "Ein Pfad durch die Funktion endet, ohne Result zuzuweisen. Der Aufrufer liest dann einen undefinierten Wert."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "possibly-uninitialized",' + #10 +
    '      "name": "Variable eventuell nicht initialisiert",' + #10 +
    '      "description": "Eine lokale Variable wird auf einem Pfad gelesen, auf dem ihr nie ein Wert zugewiesen wurde."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unreachable-code",' + #10 +
    '      "name": "Unerreichbarer Code",' + #10 +
    '      "description": "Eine Anweisung nach Exit, raise, Abort, Halt, Break, Continue oder goto wird nie ausgeführt. Meist ein Rest oder ein falsch gesetzter Sprung. Gemeldet wird nur die erste Anweisun' +
    'g eines unerreichbaren Abschnitts."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unused-local",' + #10 +
    '      "name": "Ungenutzte lokale Variable",' + #10 +
    '      "description": "Eine lokale Variable ist deklariert, wird aber nie verwendet. Wie Compilerhinweis H2164, aber schon beim Tippen.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "ignore",' + #10 +
    '          "description": "Namensmuster, die nie gemeldet werden (* und ?)."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unused-parameter",' + #10 +
    '      "name": "Ungenutzter Parameter",' + #10 +
    '      "description": "Ein Parameter wird im Rumpf der Routine nicht verwendet. Ausgenommen sind überschriebene und virtuelle Methoden, Ereignis-Handler, published-Methoden, Interface-Implementierungen' +
    ' und Callbacks.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "ignore",' + #10 +
    '          "description": "Namensmuster, die nie gemeldet werden (* und ?)."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unused-assignment",' + #10 +
    '      "name": "Zugewiesener Wert ungenutzt",' + #10 +
    '      "description": "Ein einer lokalen Variable zugewiesener Wert wird überschrieben oder die Routine endet, bevor er gelesen wird. Wie Compilerhinweis H2077. Variablen mit Interface-Typ sind ausgeno' +
    'mmen: Die Zuweisung hält oder gibt eine Referenz frei (Bereichswächter, Writer := nil).",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "ignore",' + #10 +
    '          "description": "Namensmuster, die nie gemeldet werden (* und ?)."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "duplicate-assignment",' + #10 +
    '      "name": "Feld oder Property wird zweimal gesetzt",' + #10 +
    '      "description": "Dasselbe Feld oder dieselbe Property (Panel.Left, Self.FWert, P^.X) bekommt zweimal hintereinander einen Wert, ohne dass dazwischen gelesen oder etwas aufgerufen wird; meist soll' +
    'te die zweite Zeile ein anderes Ziel haben (Left/Top). Dazwischen dürfen nur Zuweisungen an andere Objekte stehen, deren Werte nichts aufrufen und das Ziel nicht nennen; der zweite Wert darf das Ziel ' +
    'nicht lesen. Lokale Variablen deckt unused-assignment ab, Ziele mit Index oder Aufruf zählen nicht. Still beim Wechsel False/True (stößt oft etwas an, etwa Active), bei einer zweiten Zuweisung, die nu' +
    'r unter einer weiteren Bedingung übersetzt wird ({$IFDEF DEBUG}), bei verschiedenen Zweigen desselben {$IFDEF} und bei Properties aus allowProperties. Fehlt das Gegenstück (Left/Top, Width/Height …) i' +
    'n der Folge, nennt die Meldung es als Vermutung. Konfidenz hoch. Keine Schnellkorrektur; Sprung zur ersten Zuweisung.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "allowProperties",' + #10 +
    '          "description": "Properties, bei denen doppeltes Setzen gewollt sein kann (Setter mit Nebenwirkung), Muster mit * und ?."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "declared-not-implemented",' + #10 +
    '      "name": "Deklariert, aber nicht implementiert",' + #10 +
    '      "description": "Eine Methode ist in einer Klasse, einem Record oder Objekt deklariert, hat aber keinen Rumpf im implementation-Abschnitt. Der Compiler meldet das erst beim Kompilieren (E2065). E' +
    'inen Rumpf gleichen Namens mit anderem Kopf meldet stattdessen signature-mismatch."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "implemented-not-declared",' + #10 +
    '      "name": "Implementiert, aber nicht deklariert",' + #10 +
    '      "description": "Ein Methodenrumpf TFoo.Bar hat keine Deklaration dieses Namens im Typ. Eine gleichnamige Deklaration mit anderem Kopf meldet stattdessen signature-mismatch."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "destroy-without-override",' + #10 +
    '      "name": "Destroy ohne override",' + #10 +
    '      "description": "Ein destructor Destroy ist ohne override deklariert. Free ruft TObject.Destroy auf, dieser Destruktor läuft also nie."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "setter-recursion",' + #10 +
    '      "name": "Setter oder Getter ruft sich selbst auf",' + #10 +
    '      "description": "Ein Setter weist an die eigene Property zu (Name := Value in SetName) oder ein Getter liest sie (Result := Name in GetName). Das ergibt eine Endlosrekursion und einen Stapelüberl' +
    'auf zur Laufzeit; der Compiler schweigt. Schnellkorrektur: das Feld verwenden (das Feld aus der Property-Deklaration, sonst F und der Name, wenn die Klasse es hat). Früher recursive-property-accessor;' +
    ' Einstellungen und Unterdrückungen mit der alten Kennung wirken weiter."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-create-without-override",' + #10 +
    '      "name": "Komponentenkonstruktor ohne override",' + #10 +
    '      "description": "Ein TComponent-Nachfahre deklariert constructor Create(AOwner: TComponent) ohne override. Beim Laden aus der Formulardatei wird der virtuelle Konstruktor benutzt und dieser überg' +
    'angen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "hides-virtual",' + #10 +
    '      "name": "Methode verdeckt virtuelle Methode",' + #10 +
    '      "description": "Eine Methode heißt wie eine virtuelle Methode eines Vorfahren, überschreibt sie aber weder noch führt sie sie neu ein (Compilerwarnung W1010)."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "virtual-instead-of-override",' + #10 +
    '      "name": "virtual statt override",' + #10 +
    '      "description": "Ein Nachfahre deklariert eine Methode als virtual, obwohl der Vorfahr schon eine virtuelle Methode mit derselben Signatur hat; das beginnt eine neue Kette statt zu überschreiben.' +
    '"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "captured-loop-variable",' + #10 +
    '      "name": "Erfasste Schleifenvariable",' + #10 +
    '      "description": "Eine anonyme Methode, die an eine verzögert ausführende API (TThread.Queue, TTask.Run …) geht, erfasst eine Variable, die sich vor dem Aufruf noch ändert, etwa die Variable einer' +
    ' for-in-Schleife. Delphi erfasst die Variable, nicht ihren Wert.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "deferredApis",' + #10 +
    '          "description": "Weitere verzögerte APIs (zusätzlich zu TThread.Queue, TTask.Run u. a.)."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-missing-inherited",' + #10 +
    '      "name": "Komponentenmethode ohne inherited",' + #10 +
    '      "description": "Ein überschriebenes Loaded, CreateParams, CreateWnd, Notification, SetParent, Destroy oder Paint einer Komponente ruft inherited nicht auf; die VCL überspringt dann ihre eigene A' +
    'rbeit. Bei Paint ist die Konfidenz niedrig, weil TCustomControl.Paint nur den Rahmen im Designer zeichnet."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-default-mismatch",' + #10 +
    '      "name": "default passt nicht zum Konstruktor",' + #10 +
    '      "description": "Eine Eigenschaft gibt einen default-Wert an, der Konstruktor setzt das Feld aber auf ein anderes Literal. Werte gleich default speichert die DFM nicht, deshalb wird die Eigenscha' +
    'ft falsch geladen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-missing-free-notification",' + #10 +
    '      "name": "Komponentenreferenz ohne FreeNotification",' + #10 +
    '      "description": "Eine Eigenschaft verweist auf eine andere Komponente, ihr Setter ruft aber FreeNotification nicht auf. Wird die andere Komponente freigegeben, bleibt ein ungültiger Zeiger zurück' +
    '. Im Konstruktor erzeugte Unterkomponenten sind ausgenommen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-setter-without-invalidate",' + #10 +
    '      "name": "Setter ohne Invalidate",' + #10 +
    '      "description": "Ein Setter ändert ein Feld, das Paint liest, ruft aber weder Invalidate noch Repaint, Refresh oder Changed auf. Das Steuerelement zeigt weiter den alten Zustand."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-fixed-pixels",' + #10 +
    '      "name": "Feste Pixelwerte",' + #10 +
    '      "description": "Paint oder Resize verwenden feste Pixelwerte, die über 96 dpi zu klein sind. Werte über ScaleValue oder MulDiv, 0, 1 und -1 sowie Faktoren von Multiplikationen und Divisionen wer' +
    'den nicht gemeldet."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-hardcoded-color",' + #10 +
    '      "name": "Feste Farbe in Paint",' + #10 +
    '      "description": "Paint verwendet ein RGB-Literal, eine $00BBGGRR-Konstante oder einen TColor-Cast. Solche Farben ignorieren VCL-Styles; Systemfarben wie clBtnFace sind in Ordnung."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "form-field-without-object",' + #10 +
    '      "name": "Formularfeld ohne Objekt",' + #10 +
    '      "description": "Ein published-Komponentenfeld der Formularklasse hat kein Objekt in der .dfm/.fmx neben der Unit. Nach dem Laden bleibt das Feld nil. Felder außerhalb von published werden nicht ' +
    'geprüft."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "form-object-without-field",' + #10 +
    '      "name": "Formularobjekt ohne Feld",' + #10 +
    '      "description": "Ein Objekt der Formulardatei hat kein Feld in der Formularklasse. Geerbte Objekte, Objekte in inline-Frames, namenlose Komponenten und Collection-Einträge werden übergangen. Die ' +
    'Korrektur ergänzt das Feld."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "form-field-type-mismatch",' + #10 +
    '      "name": "Feldtyp weicht vom Formularobjekt ab",' + #10 +
    '      "description": "Der Typ des Felds weicht von der Klasse des Objekts in der Formulardatei ab. Ohne Quelltext der Klasse aus der Formulardatei wird nicht verglichen. Die Korrektur ändert den Feldt' +
    'yp."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "security-command-injection",' + #10 +
    '      "name": "Befehlsinjektion",' + #10 +
    '      "description": "ShellExecute, ShellExecuteEx, CreateProcess oder WinExec erhält ein Argument, das mit +, Format oder Concat aus nicht konstanten Werten zusammengesetzt ist. Eingaben könnten weit' +
    'ere Befehle einschleusen. Ohne Datenflussanalyse wird nur dieses einfache Muster erkannt (mittlere Konfidenz)."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "security-path-traversal",' + #10 +
    '      "name": "Pfad-Traversal",' + #10 +
    '      "description": "Ein Dateizugriff (TFileStream.Create, LoadFromFile, AssignFile, TFile.*) verwendet einen Pfad aus Eingabedaten (Text, ParamStr, Request) ohne Prüfung über TPath.GetFullPath. Expe' +
    'rimentell, bis die Datenflussanalyse verfügbar ist."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "security-weak-crypto",' + #10 +
    '      "name": "Schwache Kryptografie",' + #10 +
    '      "description": "MD5, SHA-1, DES oder RC4 wird verwendet. Für Prüfsummen ist das in Ordnung, für Kennwörter und Signaturen nicht. Niedrige Konfidenz, mittlere, wenn die Anweisung ein Kennwort, Ge' +
    'heimnis oder eine Signatur nennt."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "security-tls-verification-disabled",' + #10 +
    '      "name": "TLS-Zertifikatsprüfung abgeschaltet",' + #10 +
    '      "description": "Indy SSLOptions.VerifyMode := [], ein OnVerifyPeer-Handler, der immer True liefert, oder ein ValidateServerCertificate-Handler, der Accepted := True ohne Prüfung setzt."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "security-insecure-http",' + #10 +
    '      "name": "Unverschlüsselte http://-URL",' + #10 +
    '      "description": "Ein String enthält eine http://-URL. XML-Namensräume und Schema-URIs, Kommentare sowie localhost, 127.0.0.1 und [::1] sind ausgenommen. Die Korrektur ersetzt http:// durch https:' +
    '//."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "security-insecure-random",' + #10 +
    '      "name": "Random für sicherheitsrelevante Werte",' + #10 +
    '      "description": "Random wird einem Token, Kennwort, Salt, Nonce oder Schlüssel zugewiesen. Random ist vorhersagbar; einen kryptografischen Zufallsgenerator verwenden. Fehlendes Randomize behandel' +
    't #153."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dfm-circular-datasource",' + #10 +
    '      "name": "Zirkuläre Master-Detail- bzw. DataSource-Verknüpfung",' + #10 +
    '      "description": "MasterSource/DataSource-Verknüpfungen der Formulardatei bilden einen Kreis (tblA → dsB → tblB → dsA → tblA). Das Öffnen der Datasets läuft in eine Rekursion oder zeigt keine stim' +
    'migen Daten."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dfm-master-without-fields",' + #10 +
    '      "name": "Master-Detail ohne MasterFields",' + #10 +
    '      "description": "Ein Dataset hat MasterSource, aber keine MasterFields. Das Detail wird nicht gefiltert und zeigt alle Datensätze."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dfm-required-field-without-control",' + #10 +
    '      "name": "Pflichtfeld ohne sichtbares Eingabe-Control",' + #10 +
    '      "description": "Ein persistentes Feld mit Required = True ist an kein sichtbares datensensitives Control gebunden (ein Gitter ohne DataField zählt für alle Felder). Der Anwender kann es nicht fü' +
    'llen, Post schlägt fehl."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dfm-control-field-type-mismatch",' + #10 +
    '      "name": "Datensensitives Control passt nicht zum Feldtyp",' + #10 +
    '      "description": "Das Control passt nicht zum persistenten Feld, z. B. TDBEdit an einem TBooleanField oder Blob-Feld, TDBImage an einem Feld ohne Grafik."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dfm-duplicate-binding",' + #10 +
    '      "name": "Zwei Controls an demselben Feld",' + #10 +
    '      "description": "Zwei Eingabe-Controls nutzen dieselbe DataSource und dasselbe DataField. Meist ein Kopierfehler. Anzeige-Controls (TDBText, TDBImage) zählen nicht."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dfm-property",' + #10 +
    '      "name": "Komponenten-Property verletzt eine Eigenschaftsregel",' + #10 +
    '      "description": "Eine Komponenten-Property in der Formulardatei erfüllt eine Regel aus dfmPropertyRules in atlas.json nicht (Klasse, Property, Bedingung, Wert). Nicht gespeicherte Properties zähl' +
    'en mit ihrem default-Wert; Objekte aus dem Vorfahrenformular werden nur gemeldet, wenn dieses Formular den Wert selbst setzt. Die Schnellkorrektur setzt den Wert in der Formulardatei (fix: auto auch m' +
    'it source.fixAll); der Befehl \"Eigenschaftsregeln anwenden\" korrigiert ein Formular, das Projekt oder die Gruppe mit Vorschau."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "foreign-form-control-access",' + #10 +
    '      "name": "Zugriff auf Controls eines anderen Formulars",' + #10 +
    '      "description": "Code greift über die globale Variable auf ein Feld eines Formulars oder Frames aus einer anderen Unit zu (Form2.Edit1.Text). Das koppelt die Units eng; besser eine Methode oder P' +
    'roperty des Formulars nutzen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "security-sql-injection",' + #10 +
    '      "name": "SQL-Text aus zusammengesetzten Werten (SQL-Injection)",' + #10 +
    '      "description": "SQL.Text, SQL.Add, CommandText, ExecSQL oder Open erhalten Text, der per + oder Format aus Nicht-Konstanten zusammengesetzt ist. Benutzereingaben könnten SQL einschleusen. Parame' +
    'ter verwenden (:Name, ParamByName). Konstanten, resourcestrings, IntToStr und QuotedStr zählen nicht; Benutzereingaben (TEdit.Text, TMemo.Lines) heben die Konfidenz auf hoch."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "slash-command",' + #10 +
    '      "name": "Schnellbefehl nicht ausgeführt",' + #10 +
    '      "description": "Eine Zeile, die mit /name beginnt, wurde nicht ausgeführt und steht noch im Code: Der Befehl ist unbekannt, abgeschaltet (slashCommands.disabled) oder passt an dieser Stelle nich' +
    't. Die Meldung nennt den Grund. \"/ignore regel\" meldet sie auch, wenn diese Regel in der Zeile darunter nichts findet."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "empty-except",' + #10 +
    '      "name": "Leerer except-Block",' + #10 +
    '      "description": "Ein except-Block ohne Anweisung verschluckt jede Ausnahme. Ein Block, der nur einen Kommentar enthält, gilt als begründet und wird nicht gemeldet."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "interface-guid",' + #10 +
    '      "name": "Interface ohne GUID",' + #10 +
    '      "description": "Ein Interface deklariert keine GUID. Supports, as und QueryInterface brauchen eine. Die Konfidenz ist hoch, wenn das Interface in derselben Datei damit verwendet wird, sonst nied' +
    'rig. Die Schnellkorrektur fügt eine neue GUID ein."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "duplicate-interface-guid",' + #10 +
    '      "name": "Zwei Interfaces mit derselben GUID",' + #10 +
    '      "description": "Zwei Interfaces der Datei deklarieren dieselbe GUID, meist nach dem Kopieren einer Deklaration. Supports und as verwechseln sie dann. Die Schnellkorrektur erzeugt eine neue GUID.' +
    '"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "file-header",' + #10 +
    '      "name": "Dateikopf fehlt oder weicht ab",' + #10 +
    '      "description": "Die Datei beginnt nicht mit dem Kopf aus der Regeloption \"template\". Standardmäßig aus; in atlas.json mit einer Vorlage einschalten. Die Schnellkorrektur fügt den Kopf ein.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "template",' + #10 +
    '          "description": "Erwarteter Dateikopf; Platzhalter wie dokumentiert."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "hardcoded-string",' + #10 +
    '      "name": "Text im Code statt resourcestring",' + #10 +
    '      "description": "In einer Anweisung steht ein String mit Wörtern für Menschen. In einen resourcestring auslagern, damit er übersetzt werden kann. Standardmäßig aus, niedrige Konfidenz."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "self-assignment",' + #10 +
    '      "name": "Zuweisung an sich selbst",' + #10 +
    '      "description": "Einer Variablen, einem Feld oder einer Property wird der eigene Wert zugewiesen. Gemeint ist meist ein anderer Wert, etwa ein Parameter oder ein anderes Feld. Verdeckt ein Parame' +
    'ter oder eine lokale Variable ein gleichnamiges Feld (Name := Name), bietet Atlas Self.Name := Name als Korrektur an."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "for-high-to-low",' + #10 +
    '      "name": "for-Schleife zählt mit to abwärts",' + #10 +
    '      "description": "Die Schleife beginnt beim oberen Wert (High, Count - 1) und endet beim unteren, verwendet aber to. Sie läuft nie; gemeint war downto. Ebenso Schleifen mit konstanten Grenzen, die' +
    ' nie laufen, etwa for I := 10 to 1, auch mit Vorzeichen, Hex- oder Zeichenliteralen (wie H2135). Gleiche Grenzen, Ausdrücke, benannte Konstanten und aufsteigende Grenzen bleiben still. Korrektur: to d' +
    'urch downto ersetzen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "exception-not-raised",' + #10 +
    '      "name": "Exception erzeugt, aber nicht ausgelöst",' + #10 +
    '      "description": "Ein Exception-Objekt wird als eigene Anweisung erzeugt. Ohne raise passiert nichts, und das Objekt bleibt als Speicherleck zurück."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "assert-side-effect",' + #10 +
    '      "name": "Assert mit Seiteneffekt",' + #10 +
    '      "description": "Das Argument von Assert verändert Daten (Inc, Dec, eine Try…-Funktion mit out-Parameter oder eine Methode aus der Option mutatingMethods). Mit {$C-} entfernt der Compiler den gan' +
    'zen Aufruf samt Seiteneffekt.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "mutatingMethods",' + #10 +
    '          "description": "Methoden, die ihr Objekt verändern."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "ifthen-side-effect",' + #10 +
    '      "name": "IfThen wertet beide Zweige aus",' + #10 +
    '      "description": "IfThen ist eine Funktion: Beide Zweige werden vor dem Aufruf ausgewertet. Ein Nil-Zugriff oder Funktionsaufruf im nicht gewählten Zweig passiert trotzdem. Hohe Konfidenz, wenn ei' +
    'n Zweig einen in der Bedingung geprüften Namen dereferenziert, mittlere bei einem Funktionsaufruf."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "random-without-randomize",' + #10 +
    '      "name": "Random ohne Randomize",' + #10 +
    '      "description": "Random wird verwendet, aber die Unit ruft nie Randomize auf; jeder Start liefert dieselbe Folge. Randomize steht oft in der .dpr, deshalb ist die Regel standardmäßig aus und hat ' +
    'niedrige Konfidenz."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "int32-mul-overflow",' + #10 +
    '      "name": "Int32-Multiplikation an Int64 zugewiesen",' + #10 +
    '      "description": "Beide Operanden haben höchstens 32 Bit; das Produkt wird in 32 Bit gerechnet und läuft über, bevor es der Int64-Variablen zugewiesen wird. Einen Operanden nach Int64 umwandeln."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "sizeof-pointer",' + #10 +
    '      "name": "SizeOf eines Zeigers in Move oder FillChar",' + #10 +
    '      "description": "SizeOf eines Zeigers, Strings oder dynamischen Arrays ist die Größe des Verweises (4 oder 8 Byte), nicht die der Daten. Move und FillChar kopieren bzw. löschen dann zu wenig."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "char-to-pchar",' + #10 +
    '      "name": "Char nach PChar umgewandelt",' + #10 +
    '      "description": "PChar(C) mit einer Char-Variablen macht aus dem Zeichencode eine Adresse. Gemeint war ein String."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "float-equality",' + #10 +
    '      "name": "Gleitkommavergleich mit = oder <>",' + #10 +
    '      "description": "Gleitkommawerte sind nach Berechnungen selten exakt gleich. Mit SameValue aus System.Math und einer Toleranz vergleichen. Vergleiche mit 0 werden nicht gemeldet."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "constructor-on-instance",' + #10 +
    '      "name": "Konstruktor auf einer Instanz aufgerufen",' + #10 +
    '      "description": "Create wird auf einer Variablen statt auf der Klasse aufgerufen. Das legt kein neues Objekt an; mit nicht zugewiesener Variable stürzt es ab. Klassenreferenzen (class of …) werde' +
    'n nicht gemeldet."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "format-without-settings",' + #10 +
    '      "name": "Formatierung abhängig vom Gebietsschema",' + #10 +
    '      "description": "Format mit %f, %n, %m, %g oder %e und Funktionen wie FloatToStr, StrToFloat oder DateToStr ohne TFormatSettings-Parameter verwenden das Gebietsschema des Benutzers (Dezimaltrenne' +
    'r, Datumsformat). Für Dateien, Protokolle und Logs feste TFormatSettings übergeben. Format(''%d'', …) wird nicht gemeldet, ebenso wenig FormatDateTime und FormatFloat mit festem Bild ohne Trennzeichen (' +
    ': / . ,) wie ''yyyy\"-\"mm\"-\"dd'' oder ''ddddd t''."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "generic-exception-raised",' + #10 +
    '      "name": "Allgemeine Exception ausgelöst",' + #10 +
    '      "description": "Wer die Basisklasse Exception auslöst, nimmt Aufrufern die Möglichkeit, den Fehler gezielt zu behandeln. Besser eine eigene Exception-Klasse deklarieren."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "catch-all-without-raise",' + #10 +
    '      "name": "Exception-Handler ohne erneutes raise",' + #10 +
    '      "description": "Ein Handler für Exception, der weder erneut auslöst noch das Programm beendet, verschluckt jeden Fehler, auch Programmierfehler. Standardmäßig aus; gedacht für Bibliothekscode."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "exception-freed",' + #10 +
    '      "name": "Exception-Objekt manuell freigegeben",' + #10 +
    '      "description": "Die RTL gibt ein Exception-Objekt nach seinem Handler bzw. nach raise selbst frei. Manuelles Freigeben führt zur doppelten Freigabe."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "string-concat-in-loop",' + #10 +
    '      "name": "String-Verkettung in einer Schleife",' + #10 +
    '      "description": "Eine String-Variable wird in einer Schleife schrittweise verlängert. Delphi vergrößert Strings meist an Ort und Stelle, deshalb nur mit niedriger Konfidenz und standardmäßig aus;' +
    ' bei vielen Durchläufen ist TStringBuilder schneller."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "loop-invariant-call",' + #10 +
    '      "name": "Teurer Aufruf in der Schleifenbedingung",' + #10 +
    '      "description": "Die Bedingung von while und until wird bei jedem Durchlauf ausgewertet. Aufrufe wie Trim, Format oder FileExists und Eigenschaften wie Lines.Text werden dort jedes Mal neu berech' +
    'net; besser einmal vor der Schleife. Die Grenzen von for werden nur einmal ausgewertet und nicht gemeldet. Standardmäßig aus."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "missing-begin-update",' + #10 +
    '      "name": "Hinzufügen in einer Schleife ohne BeginUpdate",' + #10 +
    '      "description": "Items.Add, Lines.Add und ähnliche Aufrufe in einer Schleife zeichnen das Steuerelement bei jedem Aufruf neu. Die Schleife mit BeginUpdate und try … finally EndUpdate umschließen.' +
    ' Standardmäßig aus."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "setlength-in-loop",' + #10 +
    '      "name": "Array wächst in der Schleife um je ein Element",' + #10 +
    '      "description": "SetLength(A, Length(A) + 1) in einer Schleife kopiert das dynamische Array bei jedem Durchlauf. Die Regel meldet nur, wenn A sicher ein dynamisches Array ist (array of, TArray<T>' +
    ', ein Array-Typ der Datei oder ein bekannter RTL-Typ wie TBytes), nie bei Strings. In einer for-Schleife ist die Anzahl bekannt: Die Meldung nennt sie, und ist A eine lokale Variable, die vor der Schl' +
    'eife nicht benutzt und darin nur als A[High(A)] bzw. A[Length(A) - 1] beschrieben wird, setzt die Schnellkorrektur die Länge einmal vor der Schleife und indiziert mit der Schleifenvariable. Sonst die ' +
    'Werte in einer TList<T> sammeln."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "managed-param-without-const",' + #10 +
    '      "name": "Verwalteter Parameter ohne const",' + #10 +
    '      "description": "Ein Wertparameter vom Typ String, Interface, dynamisches oder offenes Array oder ein Record der Datei ab minRecordSize Byte, den die Routine nie verändert. Jeder Aufruf zahlt Ref' +
    'erenzzählung bzw. Kopie; const spart beides. Verändert heißt: zugewiesen, ein Teil zugewiesen (Zeichen, Felder, Elemente), an var oder out übergeben, @Parameter, Methodenaufruf an einem Record, Laufva' +
    'riable einer for-Schleife. Die Regel meldet nur, wenn das sicher ist: Aufrufe mit unbekannter Signatur (Methoden ohne Symbolindex, Überladungen), with-Blöcke, Einfangen in anonymen Methoden, inherited' +
    ' ohne Namen und asm lassen sie schweigen. Virtuelle, dynamische, abstrakte und message-Methoden, Aufrufkonventionen, external- und exportierte Routinen, Methoden von Klassen mit Interfaces, published-' +
    'Methoden und als Wert benutzte Methoden (Ereignisse, @Routine, Formulardatei) bleiben außen vor, weil ihre Signatur von außen vorgegeben ist; Overrides nur mit ignoreOverrides = false und dann ohne Ko' +
    'rrektur. Die Korrektur ergänzt const in Rumpf und Deklaration und teilt Parametergruppen bei Bedarf. Verweise als Methodenzeiger in anderen Units sieht die Regel nicht; die meldet nach der Korrektur d' +
    'er Compiler.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "minRecordSize",' + #10 +
    '          "description": "Record-Parameter ab dieser Größe in Byte melden."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "ignoreOverrides",' + #10 +
    '          "description": "Overrides nicht melden; ihre Signatur gibt der Vorfahr vor."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "bool-compare",' + #10 +
    '      "name": "Vergleich mit True oder False",' + #10 +
    '      "description": "Ein Vergleich eines Boolean mit True oder False ist überflüssig; den Ausdruck oder not direkt verwenden."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "redundant-assigned-free",' + #10 +
    '      "name": "Assigned-Prüfung vor Free",' + #10 +
    '      "description": "Free prüft selbst auf nil, eine Assigned-Prüfung vor Free oder FreeAndNil ist überflüssig."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "raise-in-finally",' + #10 +
    '      "name": "raise in einem finally-Block",' + #10 +
    '      "description": "Eine im finally-Block ausgelöste Exception ersetzt die gerade laufende Exception, die dadurch verloren geht."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "redundant-parens",' + #10 +
    '      "name": "Überflüssige Klammern",' + #10 +
    '      "description": "Klammern um eine ganze Bedingung oder einen einzelnen Bezeichner bringen nichts. Standardmäßig aus."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "redundant-begin-end",' + #10 +
    '      "name": "begin … end um eine einzelne Anweisung",' + #10 +
    '      "description": "Ein begin … end-Block mit genau einer Anweisung kann entfallen. Standardmäßig aus."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "with-statement",' + #10 +
    '      "name": "with-Anweisung",' + #10 +
    '      "description": "In einem with-Block ist unklar, zu welchem Objekt ein Bezeichner gehört, und ein neues Mitglied des with-Objekts ändert still die Bedeutung. Den Ausdruck ausschreiben oder eine l' +
    'okale Variable verwenden."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-method-length",' + #10 +
    '      "name": "Methode zu lang",' + #10 +
    '      "description": "Die Methode hat mehr Codezeilen als der Grenzwert (Vorgabe 60). Leerzeilen, Kommentare, Compiler-Direktiven und lokale Routinen zählen nicht mit. Die Methode in kleinere aufteile' +
    'n. Den Grenzwert setzt die Option max, z. B. \"rules\": {\"metric-method-length\": {\"max\": 80}}.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "max",' + #10 +
    '          "description": "Höchstens so viele Anweisungszeilen."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-nesting-depth",' + #10 +
    '      "name": "Zu tief verschachtelt",' + #10 +
    '      "description": "Die Methode verschachtelt if, case, Schleifen und try tiefer als der Grenzwert (Vorgabe 4). else if bleibt auf der Ebene seines if. Mit Exit oder Continue früh verlassen oder inn' +
    'ere Teile in eigene Methoden auslagern. Den Grenzwert setzt die Option max.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "max",' + #10 +
    '          "description": "Höchste erlaubte Schachtelungstiefe."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-cyclomatic-complexity",' + #10 +
    '      "name": "Zyklomatische Komplexität zu hoch",' + #10 +
    '      "description": "Die zyklomatische Komplexität der Methode liegt über dem Grenzwert (Vorgabe 15). Sie beginnt bei 1 und steigt um 1 je if, while, repeat und for, je case-Zweig ohne else, je and/o' +
    'r in einer Bedingung und je except on; ein except ohne on zählt einmal. Viele Pfade brauchen viele Tests. Den Grenzwert setzt die Option max.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "max",' + #10 +
    '          "description": "Höchste erlaubte zyklomatische Komplexität."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-cognitive-complexity",' + #10 +
    '      "name": "Kognitive Komplexität zu hoch",' + #10 +
    '      "description": "Die kognitive Komplexität der Methode liegt über dem Grenzwert (Vorgabe 15). Nach SonarSource zählen if, case, Schleifen und except-Behandler 1 plus ihre Schachtelungsebene; else' +
    ', else if, goto und jede Folge gleicher logischer Operatoren zählen 1. Verschachtelter Code ist schwerer zu lesen als Code hintereinander. Den Grenzwert setzt die Option max.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "max",' + #10 +
    '          "description": "Höchste erlaubte kognitive Komplexität."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-parameter-count",' + #10 +
    '      "name": "Zu viele Parameter",' + #10 +
    '      "description": "Die Methode hat mehr Parameter als der Grenzwert (Vorgabe 6). Zusammengehörige Werte in einem Record oder einer Klasse bündeln. Den Grenzwert setzt die Option max.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "max",' + #10 +
    '          "description": "Höchstens so viele Parameter."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-boolean-operands",' + #10 +
    '      "name": "Bedingung mit zu vielen Operanden",' + #10 +
    '      "description": "Eine Bedingung von if, while, until oder einem Bedingungsausdruck verknüpft mehr Operanden mit and, or und xor als der Grenzwert (Vorgabe 5); Klammern und not zählen nicht, ein V' +
    'ergleich oder Aufruf ist ein Operand. Der Befund steht auf der Bedingung. Schnellkorrektur „Bedingung in Funktion auslagern“ (#50) macht aus der ganzen Bedingung eine Funktion mit Ergebnis Boolean (Me' +
    'thode der Klasse bzw. Routine vor der umgebenden), die gelesenen lokalen Namen werden const-Parameter. Erscheint auch in der Metrik-Linse.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "max",' + #10 +
    '          "description": "Höchstens so viele Operanden in einer Bedingung."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-local-count",' + #10 +
    '      "name": "Zu viele lokale Variablen",' + #10 +
    '      "description": "Die Routine deklariert mehr lokale Variablen als der Grenzwert (Vorgabe 12): Namen im var-Abschnitt, Inline-Variablen und for var. Lokale Routinen und anonyme Methoden zählen für' +
    ' sich. Viele lokale Variablen heißen meist, dass die Routine mehreres tut; Teile in eigene Methoden auslagern. Erscheint auch in der Metrik-Linse.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "max",' + #10 +
    '          "description": "Höchstens so viele lokale Variablen."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-exit-points",' + #10 +
    '      "name": "Zu viele Ausstiege",' + #10 +
    '      "description": "Die Routine wird öfter mit Exit und raise verlassen als der Grenzwert (Vorgabe 4); Exit(Wert) und raise; im except zählen mit. Lokale Routinen und anonyme Methoden zählen für sic' +
    'h. Viele Ausstiege machen den Ablauf schwer lesbar; Wächter zusammenfassen oder Teile auslagern. Erscheint auch in der Metrik-Linse.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "max",' + #10 +
    '          "description": "Höchstens so viele Exit und raise."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "todo-comment",' + #10 +
    '      "name": "Offener TODO-Kommentar",' + #10 +
    '      "description": "Ein Kommentar beginnt mit einer Marke für offene Arbeit: // TODO, // FIXME oder das Format der IDE-To-Do-Liste { TODO 1 -oPerson -cKategorie : Text }. Der Hinweis zeigt Marke, Pr' +
    'iorität, Kategorie, Person und Text, damit offene Arbeit in der Problemliste erscheint. In der Vorgabe aus; in atlas.json einschalten, z. B. \"rules\": {\"todo-comment\": {\"severity\": \"hint\"}}. Er' +
    'ledigte Einträge ({ DONE … }) meldet die Regel nie. Die Option keywords legt die Marken fest (Vorgabe [\"TODO\", \"FIXME\"]); sie gilt auch für get_todos und --todos.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "keywords",' + #10 +
    '          "description": "Marken offener TODO-Einträge (nur Buchstaben)."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-palette-icon",' + #10 +
    '      "name": "Registrierte Komponente ohne Palettensymbol",' + #10 +
    '      "description": "Jede an RegisterComponents übergebene Klasse braucht in einer per {$R} eingebundenen .dcr oder .res eine Bitmap mit dem Klassennamen in Großbuchstaben. Ab Delphi 11 werden zusätz' +
    'lich die Größen 16, 24 und 32 px (NAME16, NAME24, NAME32) erwartet. Ohne lesbare eingebundene Ressourcendatei schweigt die Regel."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unresolved-identifier",' + #10 +
    '      "name": "Nicht deklarierter Bezeichner",' + #10 +
    '      "description": "Ein Bezeichner in einer Anweisung ist weder in der Unit noch in den eingebundenen Units deklariert (wie Compilerfehler E2003). Geprüft beim Tippen, ohne Compiler; with-Blöcke, as' +
    'm und anonyme Methoden werden übersprungen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "deprecated-symbol",' + #10 +
    '      "name": "Veraltetes oder gebundenes Symbol",' + #10 +
    '      "description": "Eine Routine, ein Typ, eine Konstante oder ein Mitglied mit deprecated, experimental, platform oder library wird verwendet (wie W1000, W1003, W1002, W1001), oder eine Unit, deren' +
    ' Kopf einen dieser Hinweise trägt, steht in uses (wie W1006, W1007, W1005, W1004). Gemeldet wird nur, was sicher aufgelöst ist. Der Editor streicht veraltete Namen durch; die Meldung nennt den Grund a' +
    'us deprecated ''Grund''. Die Deklaration und der Kopf ihrer Implementierung werden nicht gemeldet. Welche Arten gemeldet werden, legt die Option kinds fest (Standard deprecated und experimental, wie mei' +
    'st in Projekten); die Schalter {$WARN SYMBOL_DEPRECATED OFF|ON|ERROR|DEFAULT}, {$WARN UNIT_PLATFORM …} usw. und {$WARNINGS OFF} gelten ab ihrer Stelle wie beim Compiler; ein Schalter in einem {$IF}-Zw' +
    'eig, der nicht sicher mit übersetzt wird, hält die Stelle still. Korrektur: durch den Namen aus dem Grund ersetzen (bei IncludeTrailingBackslash und ExcludeTrailingBackslash durch die plattformunabhän' +
    'gige Routine), wenn genau ein Name passt, an der Stelle sichtbar ist und dieselbe Art hat. Ohne Projektindex prüft die Regel nur die Symbole der Datei selbst.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "kinds",' + #10 +
    '          "description": "Gemeldete Arten: deprecated, experimental, platform, library (platform und library sind standardmäßig aus)."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "implicit-package-import",' + #10 +
    '      "name": "Implizit eingebundene Unit",' + #10 +
    '      "description": "In einem Package (.dpk) verwendet eine Unit aus contains eine Unit, die weder in contains steht noch von einem Package aus requires geliefert wird. Der Compiler zieht sie implizi' +
    't hinein (W1033), was später zu doppelten Units führt, wenn ein anderes Package sie ebenfalls enthält. Die Schnellkorrektur nimmt die Unit in contains auf."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "type-used-before-declaration",' + #10 +
    '      "name": "Typ vor seiner Deklaration benutzt",' + #10 +
    '      "description": "Eine Klasse, ein Interface, ein Record oder ein anderer Typ wird in einer Typdeklaration (Feld, Parameter, Ergebnis, Property, generisches Argument, class of) benutzt, ist aber e' +
    'rst weiter unten im selben Gültigkeitsbereich deklariert (wie Compilerfehler E2003). Vorfahren, Aliase und Zeigertypen werden nicht gemeldet. Schnellkorrekturen: Forward-Deklaration am Anfang des type' +
    '-Blocks ergänzen, type-Blöcke zusammenlegen (const-, var- und label-Abschnitte dazwischen wandern vor den ersten Block) oder einen Record vor seinen ersten Verwender verschieben; ohne sichere Korrektu' +
    'r nennt die Meldung den Grund."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unneeded-forward-declaration",' + #10 +
    '      "name": "Überflüssige Forward-Deklaration",' + #10 +
    '      "description": "Eine Forward-Deklaration, deren Typ im selben type-Block vor der vollständigen Deklaration nicht benutzt wird. Schnellkorrektur: entfernen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "field-not-freed",' + #10 +
    '      "name": "Feld erzeugt, aber nie freigegeben",' + #10 +
    '      "description": "Ein Objektfeld, das der Konstruktor (oder eine von ihm aufgerufene private Methode) mit TKlasse.Create erzeugt, wird in der Klasse nirgends freigegeben (kein Free, FreeAndNil, De' +
    'stroy oder DisposeOf): ein Speicherleck. Ausgenommen sind Komponenten mit einem Owner ungleich nil, Interface- und Record-Felder sowie die Klassen aus der Option ignoreTypes; TObjectList- und TObjectD' +
    'ictionary-Felder sind normale Felder. Konfidenz mittel. Schnellkorrekturen: das Feld im Destruktor freigeben oder alle eigenen Objekte der Klasse freigeben; ein fehlender Destruktor wird mit override ' +
    'und inherited angelegt. Die Freigaben stehen vor inherited in umgekehrter Erzeugungsreihenfolge, als Free oder FreeAndNil (refactoring.freeFieldsStyle). Bis #918 hieß die Regel owned-field-not-freed; ' +
    'Einstellungen und Unterdrückungen mit dieser Kennung wirken weiter.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "ignoreTypes",' + #10 +
    '          "description": "Klassen, die anderswo freigegeben werden; generische Typen treffen ohne Typparameter."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "owned-field-free-unclear",' + #10 +
    '      "name": "Unklar, ob ein erzeugtes Feld freigegeben werden muss",' + #10 +
    '      "description": "Ein im Konstruktor erzeugtes, nicht freigegebenes Objektfeld wird auch zurückgegeben (Result := FFeld, Exit(FFeld)), an eine Property eines anderen Objekts oder an dessen Add…, I' +
    'nsert…, Register…, Attach…, Push oder Enqueue übergeben, ohne Create zugewiesen oder ist über eine Property (write FFeld) schreibbar. Ob die Klasse das Objekt noch besitzt, entscheidet der Entwickler;' +
    ' deshalb gibt es keine Schnellkorrektur."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "operator-precedence",' + #10 +
    '      "name": "Vorrang von not übersehen",' + #10 +
    '      "description": "In Pascal bindet not stärker als in und Vergleiche: not X in Menge heißt (not X) in Menge, not A = B heißt (not A) = B, bei Ganzzahlen wird not bitweise. Die Regel meldet diese F' +
    'ormen, wenn der deklarierte Typ des Operanden zeigt, dass es nicht gemeint sein kann (kein Boolean). Schnellkorrektur: Klammern setzen, not (X in Menge)."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "empty-statement",' + #10 +
    '      "name": "Leere Anweisung nach then, do oder else",' + #10 +
    '      "description": "Ein Semikolon direkt nach then, do oder else beendet die Anweisung: Die folgende Zeile läuft dann immer bzw. die Schleife dreht leer. Ein leerer Block begin … end nach then, do o' +
    'der else wird ebenfalls gemeldet, außer er enthält einen erklärenden Kommentar (Option allowCommented). Ein Semikolon direkt vor end, until, except oder finally ändert nichts und bleibt unbeanstandet.' +
    ' Schnellkorrektur: Semikolon entfernen.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "allowCommented",' + #10 +
    '          "description": "begin { absichtlich leer } end nicht melden."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "loop-off-by-one",' + #10 +
    '      "name": "Schleife läuft einen Schritt zu weit",' + #10 +
    '      "description": "for I := 0 to Liste.Count oder to Length(A) über nullbasierte Listen und Arrays greift im letzten Durchlauf hinter das Ende, wenn der Rumpf Liste[I] bzw. A[I] liest. Bei einsbasi' +
    'erten Strings umgekehrt: S[0] und for I := 0 to Length(S) greifen vor das erste Zeichen; {$ZEROBASEDSTRINGS ON} wird beachtet. Schnellkorrektur: - 1 ergänzen bzw. High(A) verwenden, bei Strings Low(S)' +
    ' und High(S). Die Option countNames nennt die Namen, die eine Anzahl liefern.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "countNames",' + #10 +
    '          "description": "Namen, die eine Anzahl liefern (Property wie Count oder Funktion wie Length)."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "collection-modified-in-loop",' + #10 +
    '      "name": "Liste in der eigenen Schleife verändert",' + #10 +
    '      "description": "Delete, Remove, Add oder eine andere Methode aus der Option mutatingMethods wird auf der Liste aufgerufen, über die die Schleife gerade vorwärts per Index oder mit for … in läuft' +
    '. Vorwärts überspringt Delete das nächste Element und läuft über das Ende, Add wird nicht mehr durchlaufen und Insert liefert dasselbe Element zweimal; mit for … in wirft die RTL eine Exception. Ein B' +
    'reak oder Exit direkt nach dem Aufruf beendet die Schleife und bleibt still, downto-Schleifen ebenso. Schnellkorrektur bei Indexschleifen: rückwärts mit downto; bei for … in die Elemente sammeln und d' +
    'ie Liste nach der Schleife ändern.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "mutatingMethods",' + #10 +
    '          "description": "Methoden, die die Liste verändern."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "use-after-free",' + #10 +
    '      "name": "Objekt nach Free weiter benutzt",' + #10 +
    '      "description": "Nach X.Free, X.Destroy, X.DisposeOf, FreeAndNil(X) oder Dispose(X) wird X ohne neue Zuweisung wieder benutzt: Methode, Feld, Index oder X^, with X, nach Free auch Assigned(X) (im' +
    'mer True) oder ein zweites Free. Die Regel folgt dem Datenfluss der Routine; eine Zuweisung an X, die Übergabe von X an eine Routine, @X und nach FreeAndNil eine Abfrage auf nil beenden den Weg, Wege ' +
    'nur über eine mögliche Ausnahme bleiben aus. Konfidenz hoch, wenn Freigabe und Zugriff im selben Block nacheinander stehen, sonst mittel. Keine automatische Korrektur; die Aktion springt zur Freigabe.' +
    '"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "deref-before-nil-check",' + #10 +
    '      "name": "Erst benutzt, dann auf nil geprüft",' + #10 +
    '      "description": "X wird dereferenziert (X.Feld, X.Methode, X^) und erst danach mit Assigned(X), X <> nil oder X = nil geprüft. Entweder ist die Prüfung überflüssig oder der Zugriff davor kann kna' +
    'llen. Gemeldet wird nur, wenn jeder Weg zur Prüfung durch den Zugriff führt und X vorher nicht geprüft wurde; eine neue Zuweisung, die Übergabe von X an eine Routine und bei Feldern und globalen Varia' +
    'blen jeder Aufruf dazwischen beenden den Weg. Konfidenz mittel. Ist die Prüfung ein if ohne else direkt nach dem Zugriff im selben Block, zieht die Schnellkorrektur den Zugriff hinein."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "field-free-without-nil",' + #10 +
    '      "name": "Feld freigegeben, Verweis bleibt stehen",' + #10 +
    '      "description": "FFeld.Free in einer Methode außerhalb des Destruktors, und ein Weg zum Ende der Methode setzt das Feld nicht neu. Ein späterer Zugriff oder ein zweites Free trifft freigegebenen ' +
    'Speicher. Neu setzt eine Zuweisung oder der Aufruf einer Methode derselben Klasse, die das Feld zuweist. Felder sind die der Klassendeklaration in der Unit. Ausgenommen sind Destruktoren, Methoden mit' +
    ' [TearDown] oder [TearDownFixture], Methoden, die nur aus diesen aufgerufen werden, und die Methoden aus der Option ignoreMethods. Konfidenz mittel. Schnellkorrektur: FreeAndNil(FFeld).",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "ignoreMethods",' + #10 +
    '          "description": "Methoden, in denen Free ohne nil erlaubt ist."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "missing-inherited",' + #10 +
    '      "name": "Konstruktor oder Destruktor ohne inherited",' + #10 +
    '      "description": "Ein Konstruktor oder ein override von Destroy, AfterConstruction oder BeforeDestruction ruft inherited nicht auf, in jeder Klasse, deren Vorfahr nicht TObject ist. Konstruktoren ' +
    'werden nur gemeldet, wenn ein Vorfahr einen eigenen Konstruktor deklariert (Datei, Index oder bekannte RTL-/VCL-Klasse) und der Konstruktor keinen anderen Konstruktor derselben Klasse aufruft. Bei Kom' +
    'ponenten meldet Destroy nur component-missing-inherited. Konfidenz hoch. Schnellkorrektur: inherited; am Ende von Destroy und BeforeDestruction, am Anfang von Konstruktoren und AfterConstruction; ein ' +
    'Konstruktor mit Parametern ohne override bekommt inherited Create;.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "methods",' + #10 +
    '          "description": "Geprüfte Methoden; Create steht für alle Konstruktoren, deren Name mit Create beginnt."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "inherited-order",' + #10 +
    '      "name": "inherited an der falschen Stelle",' + #10 +
    '      "description": "Im Destruktor steht inherited (inherited; bzw. inherited Destroy) als Anweisung des Rumpfs vor einer späteren Anweisung, die ein Feld der Klasse selbst freigibt (F.Free, F.Dispos' +
    'eOf, FreeAndNil(F), auch mit Self.): Der Vorfahr kann noch virtuelle Methoden aufrufen, die das Feld brauchen. Klassen, in deren Kette eine Klasse mit Thread im Namen steht, bleiben still, denn TThrea' +
    'd.Destroy wartet auf Execute und gehört dort an den Anfang. Im Konstruktor greifen die Anweisungen vor inherited auf ein Feld oder eine Property eines Vorfahren zu (aufgelöst über Datei und Index; eig' +
    'ene Felder, Parameter und lokale Variablen zählen nicht), solange der Vorfahr noch nicht angelegt ist. missing-inherited meldet fehlendes inherited, diese Regel die Reihenfolge. Konfidenz mittel. Schn' +
    'ellkorrektur: inherited an das Ende des Destruktors bzw. den Anfang des Konstruktors verschieben; nicht, wenn die Argumente von inherited Create vorher gesetzte lokale Variablen verwenden."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "inherited-wrong-method",' + #10 +
    '      "name": "inherited ruft eine andere Methode",' + #10 +
    '      "description": "In der überschriebenen Methode Speichern steht inherited Laden(…) statt inherited Speichern(…), meist nach Kopieren einer Methode. Es zählen nur Aufrufe (inherited Name als Anwei' +
    'sung oder mit Klammern); inherited Caption ohne Klammern kann eine Property sein. Still in Konstruktoren (inherited Create(nil), CreateNew), in Methoden ohne override und wenn die Methode auch sich se' +
    'lbst im Vorfahren aufruft (inherited; bzw. inherited Speichern), denn dann ist der andere Aufruf gewollt. Paare aus der Option allowed bleiben still. Konfidenz hoch. Schnellkorrektur: den Namen durch ' +
    'den eigenen ersetzen, wenn die Zahl der Argumente zu ihren Parametern passt.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "allowed",' + #10 +
    '          "description": "Erlaubte Paare \"Methode>geerbte Methode\", Muster mit * und ?, z. B. \"Speichern>Pruefen\"."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "getter-side-effect",' + #10 +
    '      "name": "Getter verändert den Zustand",' + #10 +
    '      "description": "Die read-Methode einer Property weist Feldern oder Properties des eigenen Objekts zu (FAbrufe, Self.FWert, auch geerbte Felder), ruft Inc/Dec/Include/Exclude darauf auf oder über' +
    'gibt ein neu angelegtes Objekt an eine Methode eines Felds (FListe.Add(TEintrag.Create)). Der Debugger wertet Getter beim Anzeigen aus und ändert so den Zustand. Lazy-Initialisierung ist erlaubt: Ein ' +
    'umschließendes if prüft etwas, das sein Zweig zuweist (if FListe = nil then FListe := …, if Result = nil then … FListe := Result, if not FGeladen then … FGeladen := True). Still bei lokalen Variablen ' +
    'mit dem Namen eines Felds, Result, Methoden ohne Property und anonymen Methoden. Eine Meldung je Getter und Feld. Konfidenz mittel. Keine Schnellkorrektur.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "allowLazyInit",' + #10 +
    '          "description": "Lazy-Initialisierung im Getter erlauben (if FListe = nil then FListe := …)."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "equals-without-gethashcode",' + #10 +
    '      "name": "Equals ohne GetHashCode",' + #10 +
    '      "description": "Eine Klasse überschreibt Equals, aber nicht GetHashCode (oder umgekehrt). In TDictionary und THashSet mit Standard-Comparer finden gleiche Objekte sich dann nicht. Still, wenn ei' +
    'n Vorfahr das Gegenstück überschreibt, wenn die Vorfahrenkette nicht vollständig bekannt ist und bei Equals ohne override. Gilt ebenso für Records der Datei mit class operator Equal, die als Schlüssel' +
    ' von TDictionary, TObjectDictionary, THashSet oder TMultiMap ohne Comparer dienen (Create ohne Argumente oder nur mit Konstanten wie Kapazität oder Besitz): Der Standard-Comparer vergleicht Records By' +
    'te für Byte, was nur bei Feldern vom Typ string, Variant, Gleitkomma, Interface oder TArray falsch ist; Records mit nur ordinalen Feldern bleiben still. Konfidenz hoch. Schnellkorrektur für Klassen: G' +
    'etHashCode hinter Equals deklarieren und hinter dem Rumpf von Equals mit THashBobJenkins über die eigenen Felder umsetzen, die Equals vergleicht (ohne Groß-/Kleinschreibung über LowerCase, wenn Equals' +
    ' SameText nutzt), System.Hash in uses ergänzen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "destroy-called-directly",' + #10 +
    '      "name": "Destroy statt Free aufgerufen",' + #10 +
    '      "description": "Obj.Destroy wird direkt als Anweisung aufgerufen. Ist Obj nil, knallt der Aufruf; Free prüft vorher auf nil und ist der übliche Weg, ein Objekt freizugeben. inherited Destroy und' +
    ' Aufrufe eines Destruktors mit Argumenten sind ausgenommen. Konfidenz hoch. Schnellkorrektur: aus Destroy wird Free."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "managed-type-raw-memory",' + #10 +
    '      "name": "FillChar, Move oder GetMem auf verwaltete Typen",' + #10 +
    '      "description": "FillChar, ZeroMemory, FillMemory, Move, CopyMemory, GetMem oder FreeMem auf eine Variable, deren Typ Strings, Interfaces, dynamische Arrays oder Variants enthält (Records, statis' +
    'che Arrays und Aliasse werden in der Datei und im Index aufgelöst). Referenzzähler werden überschrieben oder übergangen: Lecks, doppelte Freigabe, Zugriffsverletzungen. Geprüft werden nur einfache Var' +
    'iablen (X, @X, P^); Array-Elemente wie S[1] und Typen, die sich nicht auflösen lassen, bleiben still. Konfidenz hoch. Schnellkorrekturen: aus FillChar(X, SizeOf(X), 0) wird X := Default(T), aus Move(A' +
    ', B, SizeOf(T)) wird B := A, aus GetMem(P, SizeOf(T)) wird New(P) und aus FreeMem(P) wird Dispose(P); sonst helfen Initialize und Finalize."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "threadvar-managed",' + #10 +
    '      "name": "threadvar mit verwaltetem Typ",' + #10 +
    '      "description": "Delphi finalisiert threadvar-Variablen nicht. Ein String, Interface, dynamisches Array oder Variant in einer threadvar (auch in einem Record oder statischen Array) leckt in jedem' +
    ' Thread, der endet. Typen werden in der Datei und im Index aufgelöst. Konfidenz hoch. Keine Schnellkorrektur: den Wert am Thread-Ende freigeben (etwa in TThread.Execute auf '''' bzw. nil setzen) oder st' +
    'attdessen einen Zeiger bzw. Puffer fester Größe ablegen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "pchar-of-temporary",' + #10 +
    '      "name": "PChar auf einen temporären String",' + #10 +
    '      "description": "PChar (PWideChar, PAnsiChar) eines temporären Strings, etwa einer Verkettung mit einem String (S + ''.bak'') oder eines Funktionsergebnisses (IntToStr(N)), wird in einer Variablen,' +
    ' einem Feld oder Result gemerkt oder an PostMessage, PostThreadMessage, SendNotifyMessage oder SendMessageCallback übergeben (auch hinter LPARAM(…)). Der temporäre String wird nach der Anweisung freig' +
    'egeben, der Zeiger zeigt dann ins Leere. Die Übergabe an einen gewöhnlichen Aufruf wie CopyFile ist in Ordnung. Konfidenz hoch. Schnellkorrektur für lokale Variablen: das Zwischenergebnis in eine Inli' +
    'ne-String-Variable legen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "out-param-read",' + #10 +
    '      "name": "out-Parameter gelesen, bevor er gesetzt ist",' + #10 +
    '      "description": "Ein out-Parameter wird auf einem Weg durch den Kontrollfluss gelesen, bevor die Routine ihn setzt. Bei verwalteten Typen (string, Interfaces, dynamische Arrays, Variant) hat der ' +
    'Aufrufer ihn schon geleert, der alte Wert ist weg; bei anderen Typen ist der Wert undefiniert. Gemeint war meist var. Verwendungen, denen der Kontrollflussgraph nicht folgen kann (Übergabe an eine Rou' +
    'tine, Setzen eines Felds, @Param), bleiben still. Konfidenz hoch. Schnellkorrektur: aus out wird var in Implementierung und Deklaration."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "stringlist-unsorted",' + #10 +
    '      "name": "Find oder Duplicates auf einer unsortierten TStringList",' + #10 +
    '      "description": "Find auf einer TStringList oder THashedStringList, die in der Unit erzeugt, aber nie sortiert wird: Find sucht binär und liefert auf einer unsortierten Liste falsche Ergebnisse. ' +
    'Ebenso wirkt Duplicates := dupIgnore oder dupError nur bei sortierten Listen. Als sortiert gelten Sorted := True (oder jeder Wert außer False), Sort, CustomSort, Create(Duplicates, True, ...) und with' +
    ' Liste do. Eine Liste, die an eine Routine übergeben oder einer anderen Variablen zugewiesen wird, bleibt still. Lokale Variablen gelten je Routine, Felder in der ganzen Unit. Konfidenz mittel. Schnel' +
    'lkorrekturen: Sorted := True nach dem Erzeugen (nicht, wenn die Liste Insert, Move oder Exchange benutzt, die bei sortierten Listen eine Ausnahme auslösen) und bei if Liste.Find(S, I) then die Form I ' +
    ':= Liste.IndexOf(S) mit if I >= 0."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "writeln-in-gui-app",' + #10 +
    '      "name": "Writeln in einem Programm ohne Konsole",' + #10 +
    '      "description": "Write, Writeln, Read oder Readln auf die Standardein- oder -ausgabe in einem Programm ohne Konsole: zur Laufzeit löst Writeln EInOutError aus (E/A-Fehler 105), Readln E/A-Fehler ' +
    '104. Die Anwendungsart kommt aus DCC_ConsoleTarget der .dproj und {$APPTYPE CONSOLE} der .dpr (auch in {$IFDEF}); Units werden nur geprüft, wenn sie zum geladenen Projekt gehören, eine .dpr ohne Proje' +
    'kt für sich. Bibliotheken und Packages bleiben still. Ausgenommen sind Aufrufe mit einer Textdatei als erstem Argument, Aufrufe unter if IsConsole, gleichnamige Routinen der Unit und Read/Write in Met' +
    'hoden (TStream.Read). Konfidenz hoch. Schnellkorrektur für Write und Writeln: Ersatz durch OutputDebugString(PChar(...)) und Winapi.Windows im uses; Zahlen und Boolean über IntToStr, FloatToStr und Bo' +
    'olToStr. Die Option replacement setzt ein anderes Ziel, z. B. Log.Info oder Logger.Log(TLogLevel.Info, %s). Keine Korrektur bei Breitenangaben (X:5) oder Argumenten unbekannten Typs.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "replacement",' + #10 +
    '          "description": "Ersatz für Write und Writeln in der Schnellkorrektur; %s steht für den Text."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "exception-in-destructor",' + #10 +
    '      "name": "raise im Destruktor",' + #10 +
    '      "description": "raise in einem Destruktor (auch class destructor), das kein except im Destruktor abfängt. Die Ausnahme bricht die Freigabe ab: inherited Destroy läuft nicht mehr, das Objekt blei' +
    'bt halb freigegeben, und in einem finally des Aufrufers überdeckt sie die ursprüngliche Ausnahme. Ein raise im try-Teil eines try..except ist abgefangen; raise im except- oder finally-Teil, auch ein e' +
    'rneutes raise;, wird gemeldet. Eingebettete Routinen und anonyme Methoden sind ausgenommen. Aufrufen, die ihrerseits auslösen, folgt die Regel nicht. Konfidenz hoch. Keine Schnellkorrektur: den Zustan' +
    'd protokollieren oder ohne Ausnahme freigeben."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "duplicate-condition",' + #10 +
    '      "name": "Doppelte Bedingung oder gleiche Zweige",' + #10 +
    '      "description": "Dieselbe Bedingung zweimal in einer if … else if-Kette (der spätere Zweig wird nie erreicht), gleiche then- und else-Zweige, derselbe Operand zweimal in einer and-, or- oder xor-' +
    'Kette und Vergleiche eines Ausdrucks mit sich selbst (X = X, X < X). Meist ein Kopierfehler. Verglichen werden die Token ohne Leerraum, Kommentare und Groß-/Kleinschreibung. Ketten mit Aufrufen, die Z' +
    'ustand ändern können (alles außer SameText, Length, Assigned, Pos und ähnlichen reinen Funktionen, dazu Read, Next, Pop, Random …), bleiben still, ebenso Gleitkomma-Vergleiche mit sich selbst (NaN-Prü' +
    'fung X <> X) und Vergleiche über Klassenmitglieder wie TFoo.Shared = TFoo.Shared. Konfidenz hoch. Keine Schnellkorrektur; die Aktion springt zum ersten Vorkommen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "case-missing-enum-value",' + #10 +
    '      "name": "case über Aufzählung ohne alle Werte",' + #10 +
    '      "description": "Ein case über einen Aufzählungstyp ohne else deckt nicht alle Werte ab; ein später ergänzter Wert fällt still durch. Die Meldung nennt die fehlenden Werte. Den Typ des Selektors ' +
    '(Variable, Parameter, Feld oder Kette A.B) liefert die Namensauflösung, die Werte der Index bzw. die Unit selbst; Aliase werden verfolgt. Bereiche (bsNeu..bsBezahlt) und Listen zählen als vorhanden. S' +
    'elektoren mit Aufrufen, Ganzzahlen und unbekannte Typen bleiben still. Mit der Option requireElse wird auch ein case mit else gemeldet. Konfidenz hoch. Schnellkorrektur „Fehlende Werte ergänzen (n)“ e' +
    'rgänzt leere Zweige in Deklarationsreihenfolge vor else bzw. end, mit Typpräfix, wenn die Marken einen tragen ({$SCOPEDENUMS ON}).",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "requireElse",' + #10 +
    '          "description": "Auch case-Anweisungen mit else melden, wenn Werte fehlen."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "pair-without-finally",' + #10 +
    '      "name": "Paarige Aufrufe ohne try/finally",' + #10 +
    '      "description": "Verallgemeinert lock-without-finally (dessen Sperrpaare dort bleiben) auf andere Paare: DisableControls/EnableControls, BeginUpdate/EndUpdate, FindFirst/FindClose (auch in if Fin' +
    'dFirst(...) = 0 then begin ... end), Reset, Rewrite oder Append/CloseFile, GetMem oder AllocMem/FreeMem und Screen.Cursor := ... mit einem späteren Screen.Cursor := .... Gemeldet wird, wenn das Schlie' +
    'ßen später ungeschützt in derselben Anweisungsliste steht und mindestens eine Anweisung dazwischen liegt; eine Exception dort lässt den Zustand hängen. Beide Aufrufe müssen denselben Empfänger bzw. da' +
    'sselbe Argument haben. Überlappende Paare meldet die Regel zusammen. Konfidenz hoch. Schnellkorrektur: die Anweisungen dazwischen in try/finally mit den schließenden Aufrufen einschließen, wenn diese ' +
    'direkt aufeinander folgen. Die Option pairs ergänzt eigene Paare.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "pairs",' + #10 +
    '          "description": "Weitere Paare als [{\"open\": \"Einfrieren\", \"close\": \"Auftauen\"}], wahlweise mit openArg/closeArg."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "processmessages-in-loop",' + #10 +
    '      "name": "Application.ProcessMessages in Schleifen",' + #10 +
    '      "description": "Application.ProcessMessages in einer for-, while- oder repeat-Schleife oder direkt in einem Ereignis-Handler (Methode mit Parameter Sender) öffnet die Tür für Wiedereintritt: Der' +
    ' Benutzer klickt erneut, schließt das Formular oder startet den Vorgang doppelt. Aufrufe in anonymen Methoden überlässt die Regel thread-vcl-access; ProcessMessages anderer Objekte zählt nicht. Konfid' +
    'enz mittel, keine Schnellkorrektur: die Arbeit in einen Thread oder TTask auslagern oder den Auslöser bis zum Ende sperren. Die Option allowIn nennt Methoden, in denen es erlaubt ist.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "allowIn",' + #10 +
    '          "description": "Methoden, in denen ProcessMessages erlaubt ist, als Name oder Klasse.Name."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unchecked-conversion",' + #10 +
    '      "name": "Umwandlung einer Benutzereingabe ohne Prüfung",' + #10 +
    '      "description": "StrToInt, StrToInt64, StrToFloat, StrToDate, StrToDateTime oder StrToCurr direkt auf einer Benutzereingabe (Edit.Text, Grid.Cells[...], Memo.Lines[...], auch in Trim) außerhalb d' +
    'es try-Teils eines try/except. Eine Fehleingabe löst EConvertError mit englischer Meldung aus. try/finally gilt nicht als Schutz. Konfidenz mittel. Schnellkorrektur für X := StrToInt(Edit.Text); als e' +
    'igene Anweisung, wenn X eine Variable oder ein Feld des passenden Typs ist: if not TryStrToInt(Edit.Text, X) then raise EConvertError.Create(''X ist keine Zahl''). format-without-settings meldet zusätzl' +
    'ich landesabhängige Umwandlungen ohne TFormatSettings. Die Optionen functions und sources wählen die geprüften Umwandlungen und die Eigenschaften, die als Eingabe gelten.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "functions",' + #10 +
    '          "description": "Geprüfte Umwandlungen."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "sources",' + #10 +
    '          "description": "Eigenschaften, die als Benutzereingabe gelten."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dictionary-get-without-check",' + #10 +
    '      "name": "Dictionary-Zugriff ohne Prüfung des Schlüssels",' + #10 +
    '      "description": "Dict[Key] bzw. Dict.Items[Key] wird auf einem TDictionary oder TObjectDictionary (auch über einen Typalias der Datei) gelesen, obwohl weder ContainsKey noch TryGetValue denselben' +
    ' Schlüssel vorher in der Routine geprüft hat. Still bleibt die Regel, wenn die Routine das Dictionary vorher selbst füllt (Add, AddOrSetValue, TryAdd, Dict[K] := ...) oder der Schlüssel aus Keys bzw. ' +
    'den Paaren stammt (for K in Dict.Keys, Namen := Dict.Keys.ToArray, for Pair in Dict mit K := Pair.Key). Fehlt der Schlüssel, folgt EListError. Konfidenz mittel. Schnellkorrektur für X := Dict[Key]; al' +
    's eigene Anweisung, wenn X eine Variable vom Wertetyp ist: if not Dict.TryGetValue(Key, X) then X := 0 (bzw. '''', False, Default(T))."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "shadowed-name",' + #10 +
    '      "name": "Lokaler Name verdeckt Feld oder Property",' + #10 +
    '      "description": "Ein Parameter, eine lokale oder Inline-Variable heißt wie ein Feld oder eine Property der Klasse (auch geerbt und dort sichtbar, aufgelöst über die Datei und den Symbolindex) ode' +
    'r wie eine globale Variable der Unit, die vor der Routine deklariert ist. In Formularmethoden besonders tückisch: Caption, Name, Tag, Left. Steht die VCL nicht im Index, kennt die Regel die Mitglieder' +
    ' von TComponent und TControl, wenn die Vorfahrenkette an einer VCL-Grundklasse endet. Parameter von Ereignis-Handlern (mit Sender) bleiben außen vor, weil der Ereignistyp die Signatur vorgibt. Konfide' +
    'nz hoch. Schnellkorrektur: in der Routine in AName (Parameter, auch in der Deklaration) bzw. LName (lokale Variable) umbenennen. Die Option ignore nennt Namensmuster, die nie gemeldet werden (Vorgabe ' +
    'Sender, Value).",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "ignore",' + #10 +
    '          "description": "Namensmuster (* und ?), die nie gemeldet werden."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "boolean-assign-if",' + #10 +
    '      "name": "if, das nur True oder False zuweist",' + #10 +
    '      "description": "if B then X := True else X := False (auch mit begin/end und vertauschten Werten), if B then Exit(True) else Exit(False) sowie if B then Exit(True); gefolgt von Exit(False); lasse' +
    'n sich direkt schreiben. Ergänzt bool-compare. Konfidenz hoch. Schnellkorrektur: X := B, X := not B bzw. Exit(B); Verneinungen werden vereinfacht (aus not B wird B), zusammengesetzte Bedingungen einge' +
    'klammert. Ohne Korrektur, wenn Kommentare im if stehen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "case-insensitive-compare",' + #10 +
    '      "name": "Vergleich über UpperCase oder LowerCase",' + #10 +
    '      "description": "UpperCase(A) = UpperCase(B), LowerCase(A) <> ''x'', AnsiUpperCase(...) oder A.ToUpper = B.ToUpper erzeugt zwei Strings für einen Vergleich. SameText (AnsiSameText bei den Ansi-Funk' +
    'tionen und den Unicode-String-Helfern) ist kürzer und schneller. Ein Literal zählt nur, wenn die Umwandlung es nicht ändert; UpperCase(A) = LowerCase(B) und UpperCase(A) = ''ja'' bleiben unberührt, weil' +
    ' das andere Fehler sind. Ersetzt nicht die String-Helper-Modernisierung aus #71. Konfidenz hoch. Schnellkorrektur: SameText(A, B) bzw. not SameText(A, B)."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "magic-number",' + #10 +
    '      "name": "Zahl ohne Namen im Code",' + #10 +
    '      "description": "Zahlenliterale (dezimal, $hex, Gleitkomma, mit Vorzeichen) in Anweisungen, außerhalb von const-Abschnitten, Typen, Array-Grenzen und Teilbereichen. Erlaubte Werte sind einstellba' +
    'r; DFM-Koordinaten und Tests lassen sich über exclude ausnehmen. Standard aus und niedrige Konfidenz: Treffer erscheinen, wenn die Regel eingeschaltet und minConfidence low ist. Schnellkorrektur: Kons' +
    'tante einführen (#50) im const-Abschnitt der Routine.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "allowed",' + #10 +
    '          "description": "Zahlen, die nie gemeldet werden."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "line-length",' + #10 +
    '      "name": "Zeile zu lang",' + #10 +
    '      "description": "Zeilen über der Grenze max (Vorgabe 120 Zeichen, passend zu den Linealen aus #710). Tabs zählen bis zur nächsten Tabstelle nach format.indentSize. Zeilen, die nur wegen eines Str' +
    'ings oder, mit ignoreComments, eines Kommentars zu lang sind, werden nicht gemeldet. Zeilen über 1023 Zeichen meldet die Regel unabhängig von max immer als Fehler, weil der Compiler dort abbricht (F20' +
    '69). Standard aus. Schnellkorrektur: Zeile umbrechen hinter Kommas bzw. vor zweistelligen Operatoren, wenn die Stücke danach passen.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "max",' + #10 +
    '          "description": "Höchstlänge einer Zeile in Zeichen."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "ignoreStrings",' + #10 +
    '          "description": "Zeilen, die nur wegen eines Strings zu lang sind, nicht melden."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "ignoreComments",' + #10 +
    '          "description": "Zeilen, die nur wegen eines Kommentars zu lang sind, nicht melden."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-class-size",' + #10 +
    '      "name": "Klasse mit zu vielen Membern",' + #10 +
    '      "description": "Die Klasse hat mehr Member als der Grenzwert (Vorgabe 40): Feldnamen, Methoden, Properties mit eigenem Typ und class var. Properties, die nur die Sichtbarkeit anheben (property A' +
    'lign;), und geschachtelte Typen zählen nicht; eine geschachtelte Klasse wird für sich gemessen. Erscheint auch in der Metrik-Linse über der Klasse. Die Klasse aufteilen oder Teile in Hilfsklassen ausl' +
    'agern; „Klasse in eigene Unit verschieben“ (#103) hilft, wenn auch die Unit voll ist.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "max",' + #10 +
    '          "description": "Höchstzahl der Member je Klasse."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-unit-length",' + #10 +
    '      "name": "Unit zu lang",' + #10 +
    '      "description": "Die Unit hat mehr Zeilen als der Grenzwert (Vorgabe 2000), gezählt bis zum abschließenden end. Gemessen werden nur Units, keine Programme oder Packages. Erscheint auch in der Met' +
    'rik-Linse über dem Unit-Namen. Klassen mit „Klasse in eigene Unit verschieben“ (#103) auslagern.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "max",' + #10 +
    '          "description": "Höchstzahl der Zeilen je Unit."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-uses-count",' + #10 +
    '      "name": "Zu viele Units im uses",' + #10 +
    '      "description": "Die Unit bindet mehr Units ein als der Grenzwert (Vorgabe 30), interface und implementation zusammen. Der Befund steht auf dem ersten uses. Programme und Bibliotheken werden nich' +
    't geprüft, weil ihr uses die Units des Projekts aufzählt. Erscheint auch in der Metrik-Linse über uses. Viele Abhängigkeiten heißen meist, dass die Unit zu viel tut; „Klasse in eigene Unit verschieben' +
    '“ (#103) teilt sie.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "max",' + #10 +
    '          "description": "Höchstzahl der Units in allen uses-Klauseln."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-inheritance-depth",' + #10 +
    '      "name": "Zu tiefe Vererbung",' + #10 +
    '      "description": "Die Klasse hat mehr eigene Vorfahren als der Grenzwert (Vorgabe 5). Vorfahren aus RTL, VCL, FMX und anderen Bibliotheken zählen nicht (am Unit-Namen oder weil der Index sie aus d' +
    'em Bibliothekspfad nachgeladen hat), TObject ebenso. Vorfahren werden in der Datei und im Symbolindex gesucht. Bricht die Kette an einem unbekannten Vorfahren ab, bevor sie eine Bibliothek erreicht, i' +
    'st der Wert eine Untergrenze und die Meldung sagt „mindestens“; gemeldet wird nur, wenn schon sie über der Grenze liegt. Units einer Bibliothek selbst werden nicht geprüft. Der Befund steht auf dem Kl' +
    'assennamen; die Metrik-Linse zeigt die Tiefe neben den Membern.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "max",' + #10 +
    '          "description": "Höchstens so viele eigene Vorfahren."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "public-field",' + #10 +
    '      "name": "Öffentliches Feld",' + #10 +
    '      "description": "Felder im public- oder published-Abschnitt einer Klasse. Der Abschnitt ohne Sichtbarkeitswort zählt nur bei Klassen ohne Vorfahren oder mit TObject, weil der Formulardesigner dor' +
    't seine Felder anlegt. Records sind ausgenommen, außer mit includeRecords; class var wird nicht gemeldet. Standard aus. Schnellkorrektur: Feld kapseln legt das Feld als FName in einen private-Abschnit' +
    't am Ende der Klasse und ergänzt im alten Abschnitt property Name read FName write FName; Zugriffe von außen bleiben gültig.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "includeRecords",' + #10 +
    '          "description": "Auch Felder von Records melden."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "legacy-tlist",' + #10 +
    '      "name": "Ungenerische Liste mit Cast",' + #10 +
    '      "description": "Eine ungenerische TList (System.Classes) oder TObjectList (System.Contnrs), deren Elemente mit Cast gelesen werden: T(Liste[I]), T(Liste.Items[I]), T(Liste.First), Liste[I] as T ' +
    'usw. TList<T> und TObjectList<T> aus System.Generics.Collections prüfen den Typ beim Übersetzen und brauchen keinen Cast. Die Regel meldet je Liste einmal, an ihrer Deklaration, wenn sie in der Datei ' +
    'steht, sonst am ersten Cast; bei mehreren Zieltypen nennt sie alle. Nur wenn die Namensauflösung Listentyp und Zieltyp sicher findet; Casts auf Pointer zählen nicht. Standard aus; für Code, der noch m' +
    'it alten Delphi-Versionen übersetzen muss, über exclude abschaltbar. Schnellkorrektur (#1105): wandelt die Liste in einem Schritt in TList<T> bzw. TObjectList<T> um: Deklaration, jedes Create (Argumen' +
    'te bleiben), jeden Cast und System.Generics.Collections im uses; Contnrs entfällt, wenn nichts anderes es braucht. Nur wenn alle Lesezugriffe denselben Cast haben, kein Mitglied ohne generisches Gegen' +
    'stück vorkommt (Sort mit TListSortCompare, Assign mit TListAssignOp, List), keine Pointer- oder Integer-Werte in der Liste stehen, Add, Extract, Remove und IndexOf T bekommen und die Liste nicht weite' +
    'rgegeben wird. Ist die Liste außerhalb der Unit sichtbar, schreibt die Korrektur die anderen Units der Projektgruppe mit um oder entfällt; solche Korrekturen wendet „Alle korrigieren“ (source.fixAll) ' +
    'nie an. Sonst nennt der Befund-Hover den Grund. Stapel und Warteschlangen: legacy-stack-queue."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "legacy-stack-queue",' + #10 +
    '      "name": "Ungenerischer Stapel oder ungenerische Warteschlange mit Cast",' + #10 +
    '      "description": "Ein ungenerischer TStack, TQueue, TObjectStack oder TObjectQueue (System.Contnrs), dessen Elemente mit Cast gelesen werden: T(Stapel.Pop), T(Stapel.Peek), Schlange.Pop as T usw. ' +
    'TStack<T>, TQueue<T>, TObjectStack<T> und TObjectQueue<T> aus System.Generics.Collections prüfen den Typ beim Übersetzen und brauchen keinen Cast. Wie legacy-tlist meldet die Regel je Stapel bzw. Wart' +
    'eschlange einmal, an der Deklaration, wenn sie in der Datei steht, sonst am ersten Cast; bei mehreren Zieltypen nennt sie alle. Nur wenn die Namensauflösung Typ und Zieltyp sicher findet; Casts auf Po' +
    'inter zählen nicht. Standard aus; für Code, der noch mit alten Delphi-Versionen übersetzen muss, über exclude abschaltbar. Schnellkorrektur: wandelt in einem Schritt um wie legacy-tlist; bei Warteschl' +
    'angen wird Push zu Enqueue und Pop zu Dequeue. TObjectStack<T> und TObjectQueue<T> besitzen ihre Objekte, die Contnrs-Klassen nicht: Die Korrektur erzeugt sie deshalb mit Create(False) und liest mit E' +
    'xtract, weil Pop und Dequeue dort Prozeduren sind, die das Objekt freigeben. Ohne Create in der Unit, mit verschiedenen Casts oder mit Mitgliedern ohne generisches Gegenstück (AtLeast) gibt es keine K' +
    'orrektur; der Befund-Hover nennt den Grund."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "global-variable",' + #10 +
    '      "name": "Globale Variable im interface",' + #10 +
    '      "description": "var oder threadvar im interface-Teil einer Unit: Jede Unit, die sie einbindet, kann den Wert lesen und ändern. Die Formularvariable des Designers (frmHaupt: TfrmHaupt, bei Nachfa' +
    'hren von TForm, TFrame, TDataModule oder jeder Klasse einer Unit mit Formulardatei) ist ausgenommen, außer mit includeFormVariables. Standard aus. Die Variable in den implementation-Teil verschieben u' +
    'nd eine Funktion oder Property anbieten.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "includeFormVariables",' + #10 +
    '          "description": "Auch die Formularvariablen des Designers melden."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "commented-out-code",' + #10 +
    '      "name": "Auskommentierter Code",' + #10 +
    '      "description": "Mindestens minLines aufeinanderfolgende Kommentarzeilen (// je Zeile oder ein mehrzeiliger { }-Kommentar), die sich als Anweisungen, Deklarationen oder Klassenmitglieder parsen l' +
    'assen. Prosa am Anfang und Ende des Blocks bleibt außen vor, mindestens die Hälfte der Zeilen muss nach Code aussehen (;, :=, begin, end, then, do). XMLDoc (///) und Kommentare vor dem ersten Token (L' +
    'izenzköpfe) meldet die Regel nie. Sicherheit mittel. Die Versionsverwaltung bewahrt den alten Code auf; die Korrektur entfernt die Zeilen.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "minLines",' + #10 +
    '          "description": "Mindestzahl aufeinanderfolgender auskommentierter Codezeilen."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "default-parameter",' + #10 +
    '      "name": "Standardparameter statt Überladung",' + #10 +
    '      "description": "Ein Parameter mit Vorgabewert (Anzahl: Integer = 10). Für Teams, die Überladungen bevorzugen: Vorgabewerte landen beim Aufrufer im Code, ändern sich nicht mit der Bibliothek und ' +
    'vertragen sich schlecht mit Überladungen. Gemeldet wird einmal je Deklaration (Klassenmitglied, interface-Teil, forward oder eine Routine nur im implementation-Teil); der Rumpf zu einer Deklaration ni' +
    'cht noch einmal. Die Schnellkorrektur fügt vor der Deklaration je weggelassenem Standardparameter am Ende eine Überladung ein, die mit dem Vorgabewert weiterreicht, entfernt die Vorgabewerte (auch im ' +
    'Rumpf wiederholte) und ergänzt overload. Keine Korrektur, wenn die Signatur von außen vorgegeben ist (virtual, dynamic, abstract, override, message, external, Interface-Typen), der Name als Wert benut' +
    'zt wird (@Routine, Methodenzeiger), es schon eine gleichnamige Überladung gibt, in bedingter Übersetzung oder wenn der Rumpf nicht eindeutig zu finden ist."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "empty-routine",' + #10 +
    '      "name": "Leere Methode",' + #10 +
    '      "description": "Eine Methode oder Routine, deren Rumpf weder eine Anweisung noch einen Kommentar (noch eine Compiler-Direktive) enthält. Entweder fehlt der Inhalt oder die Methode kann weg. Nich' +
    't gemeldet werden virtuelle und dynamische Methoden (Ersatz für abstract in Basisklassen), Nachrichten-Handler, Methoden von Klassen mit Interfaces (der Compiler verlangt jede Interface-Methode), Erei' +
    'gnis-Handler, die in der Formulardatei stehen (die IDE entfernt leere beim Speichern), und Rümpfe mit Kommentar, etwa Überschreibungen, die bewusst nichts tun. Schnellkorrekturen: Kommentar zwischen b' +
    'egin und end einfügen; Methode entfernen (Deklaration samt XML-Doku und Rumpf) nur bei privaten Methoden und Routinen ohne Deklaration im interface-Teil, die sonst nirgends in der Datei vorkommen und ' +
    'keine Signatur von außen erfüllen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "write-only-property",' + #10 +
    '      "name": "Property ohne read",' + #10 +
    '      "description": "Eine Property hat write, aber kein read. Sie lässt sich nicht im Objektinspektor anzeigen, nicht im Debugger lesen und verwirrt Aufrufer. Properties ohne Typ bleiben außen vor (s' +
    'ie veröffentlichen eine geerbte Property neu, deren read vom Vorfahren kommt), ebenso Properties mit einem Attribut aus allowAttributes (mit oder ohne Endung Attribute). Schnellkorrektur: read FName e' +
    'rgänzen, wenn der Typ ein Feld FName gleichen Typs deklariert. Das Lesen einer solchen Property meldet readonly-property-assigned.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "allowAttributes",' + #10 +
    '          "description": "Attribute, die eine Property ohne read erlauben."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "xmldoc-mismatch",' + #10 +
    '      "name": "XMLDoc passt nicht zur Signatur",' + #10 +
    '      "description": "Ein ///-Kommentar passt nicht zu seiner Deklaration oder ist kein wohlgeformtes XML, wie die Compilerwarnungen W1201 bis W1208 mit eingeschalteter XML-Dokumentation. Gemeldet wer' +
    'den: <param> zu einem Parameter, den es nicht gibt; fehlende <param>, wenn der Block überhaupt Parameter beschreibt (wie W1208, „but other parameters do“); mit checkReturns <returns> an einer Routine ' +
    'ohne Ergebnis und fehlendes <returns> an einer Funktion, deren Block Parameter beschreibt. <inheritdoc/> ergänzt, was fehlt. Außerdem ''<'' und ''&'' außerhalb von Tags und Entitäten, unbekannte Entitäten' +
    ', Attributwerte ohne Anführungszeichen, nicht geschlossene und überzählige Endtags sowie cref-Ziele, die es nicht gibt (W1206, nur mit Index und wenn jede Unit aus uses bekannt ist; generische Ziele, ' +
    'Unit-Namen und Typen mit unbekannten Vorfahren bleiben still). Mit requirePublic zusätzlich public- und published-Methoden und -Properties von Typen im interface ohne ///-Kommentar (nicht override, ni' +
    'cht Properties ohne Typ). Schnellkorrekturen: unbekannte <param> der Reihe nach auf die fehlenden umbenennen, die übrigen als leere Zeilen in Signaturreihenfolge ergänzen, überzählige <param> und <ret' +
    'urns> an Prozeduren entfernen; Zeichen maskieren, Anführungszeichen setzen, Endtag ergänzen oder entfernen, ein fremdes leeres Tag wie TList<T> als Text schreiben; cref auf das ähnlichste Symbol setze' +
    'n; Kommentargerüst erzeugen.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "requirePublic",' + #10 +
    '          "description": "Öffentliche Member ohne XMLDoc melden."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "checkReturns",' + #10 +
    '          "description": "<returns> prüfen."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "queue-nil-in-package",' + #10 +
    '      "name": "TThread.Queue(nil, …) in einem Package",' + #10 +
    '      "description": "TThread.Queue(nil, …) oder TThread.ForceQueue(nil, …) in einer Unit eines Design-Time- oder Laufzeit-Packages: Der Eintrag gehört keinem Thread, beim Entladen des Packages räumt ' +
    'ihn niemand weg, und CheckSynchronize ruft ihn womöglich danach in fremdem Speicher auf. Package-Units erkennt die Regel über die .dpk bzw. .dproj des geladenen Projekts (eine .dpk ohne Projekt für si' +
    'ch). Eine Zeile mit dem Kommentar aus okMarker (Vorgabe mainthread-ok) ist ausgenommen. Sicherheit hoch. Korrektur: auf den Wrapper aus der Option wrapper umschreiben (Vorgabe TAtlasMainThread.Queue, ' +
    'bei ForceQueue ForceQueue); mit Klammer steht der Text so vor den übrigen Argumenten. ForceQueue mit Verzögerung bekommt keine Korrektur. Der Kommandozeilen-Linter liest die .dpk-Dateien unter dem gep' +
    'rüften Ordner. Leistet für jedes Plugin-Projekt dasselbe wie Tools/Check-MainThreadQueue.ps1; das Skript bleibt für Prüfungen ohne Atlas-Server.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "wrapper",' + #10 +
    '          "description": "Ersatz für TThread.Queue(nil, in der Schnellkorrektur."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "okMarker",' + #10 +
    '          "description": "Kommentar, der eine Zeile ausnimmt."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "ota-notifier-not-removed",' + #10 +
    '      "name": "IDE-Notifier ohne RemoveNotifier",' + #10 +
    '      "description": "AddNotifier an IOTAServices, IOTAEditorServices, IOTAModule usw. (oder ein anderes Paar aus registerPairs), dessen Index nie an RemoveNotifier geht: Der Aufruf steht als Anweisun' +
    'g ohne Zuweisung, oder die Variable, der er zugewiesen wird, erhält in der Unit kein RemoveNotifier (in finalization, im Destruktor oder in Destroyed). Die IDE ruft den Notifier dann nach dem Entladen' +
    ' des Packages in fremdem Speicher auf. Register…-Aufrufe in der Prozedur Register sind ausgenommen: Diese Wizards entfernt die IDE selbst. Sicherheit mittel. Korrektur in Methoden: Index in ein Feld l' +
    'egen (FNotifierIndex im private-Abschnitt) und RemoveNotifier im Destruktor ergänzen, der bei Bedarf angelegt wird; in Prozeduren der Unit: globale Variable mit -1 und RemoveNotifier in finalization. ' +
    'Keine Korrektur, wenn der Empfänger ein Parameter oder eine lokale Variable ist.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "registerPairs",' + #10 +
    '          "description": "Paare der Open Tools API als [{\"open\": \"AddNotifier\", \"close\": \"RemoveNotifier\"}]; ersetzt die Vorgabe."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dunitx-test-without-assert",' + #10 +
    '      "name": "DUnitX-Test ohne Assert",' + #10 +
    '      "description": "Eine [Test]- oder [TestCase]-Methode, die keine Prüfung aufruft, weder selbst noch über Methoden derselben Klasse oder Routinen der Unit: Sie ist immer grün. Als Prüfung zählen A' +
    'ufrufe nach assertPatterns (Vorgabe Assert.*, WillRaise*, Check*), System.Assert und Aufrufe an Klassen mit Assert im Namen (TRuleAssert.Reports). Tests mit [WillRaise] oder [Ignore] bleiben still. Si' +
    'cherheit hoch. Korrekturen: Assert.Pass als Platzhalter einfügen oder zur Methode springen.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "assertPatterns",' + #10 +
    '          "description": "Aufrufe, die als Prüfung zählen, als Muster mit * und ?; ersetzt die Vorgabe."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "event-call-without-assigned",' + #10 +
    '      "name": "Ereignis ohne Assigned-Prüfung aufgerufen",' + #10 +
    '      "description": "FOnChange(Self) oder OnChange(Self) wird in einer Methode der Klasse aufgerufen, ohne dass Assigned(FOnChange) oder FOnChange <> nil den Aufruf schützt: Ohne Handler folgt eine Z' +
    'ugriffsverletzung. Ereignisse sind Felder und Properties der Klasse mit Methodenzeiger- oder Referenztyp (procedure … of object, reference to …, TNotifyEvent, TProc/TFunc, Typen auf Event, prozedurale' +
    ' Typen der Unit oder des Index). Schutz: der then-Zweig einer Bedingung mit Assigned (auch while), der else-Zweig von not Assigned, \"Assigned(F) and\" vor dem Aufruf oder \"if not Assigned(F) then Ex' +
    'it/raise\" davor, auch über einen Merker oder eine Methode der Klasse ohne Parameter, deren Result Assigned(F) enthält. Still bleiben Felder, die ein Konstruktor mit einem Wert belegt (eingereichte Ab' +
    'hängigkeiten wie FReadText := AReadText), Properties darauf und gleichnamige lokale Namen. Sicherheit hoch. Korrektur: den Aufruf in \"if Assigned(F) then\" einschließen, wenn er als eigene Anweisung ' +
    'in einem Block steht."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "owned-item-freed",' + #10 +
    '      "name": "Element einer besitzenden Liste zusätzlich freigegeben",' + #10 +
    '      "description": "Ein Element einer TObjectList/TObjectList<T> (OwnsObjects, Vorgabe True) oder eines TObjectDictionary mit doOwnsValues wird mit Free, FreeAndNil, Destroy oder DisposeOf freigegeb' +
    'en, direkt (Liste[I].Free, Liste.Items[I].Free) oder über eine Variable aus Liste[I], Liste.First/Last oder einer for-in-Schleife über die Liste bzw. Dictionary.Values. Die Liste gibt das Element selb' +
    'st frei: bei Delete, Remove, Clear, einer Zuweisung an Liste[I] oder spätestens beim Freigeben, also doppelt. Besitzend ist eine Liste, wenn die Unit sie so erzeugt (TObjectList ohne False, TObjectDic' +
    'tionary mit doOwnsValues) oder ohne Erzeugung als TObjectList deklariert, und kein OwnsObjects := False folgt. Extract in derselben Routine lässt die Regel schweigen. Sicherheit hoch. Korrekturen: Fre' +
    'e entfernen (die ganze Schleife, wenn sie nur freigibt), Delete bzw. Remove statt Free, Extract statt Remove."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "create-without-assignment",' + #10 +
    '      "name": "Objekt erzeugt und sofort verloren",' + #10 +
    '      "description": "TStringList.Create; als eigene Anweisung: Das Objekt wird erzeugt, aber nirgends gespeichert und nie freigegeben (Speicherleck). Still bleiben Komponenten mit Owner (erstes Argum' +
    'ent Self, Owner, AOwner, Application oder ein Nachfahr von TComponent mit einem Argument ungleich nil), Threads (geben sich mit FreeOnTerminate selbst frei), Records, unbekannte Klassen mit Argumenten' +
    ' und Klassen aus selfRegistering. Sicherheit hoch. Korrektur: Zuweisung an eine neue lokale Variable, die folgenden Anweisungen des Blocks in try/finally mit Free.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "selfRegistering",' + #10 +
    '          "description": "Klassen, die sich im Konstruktor selbst registrieren, als Muster mit * und ?; Create als Anweisung bleibt für sie still."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "raw-memory-leak",' + #10 +
    '      "name": "GetMem oder New ohne Freigabe",' + #10 +
    '      "description": "Eine lokale Variable erhält Speicher über GetMem, AllocMem, ReallocMem, GetMemory, New, StrAlloc oder StrNew, die Routine gibt ihn aber nie mit FreeMem, FreeMemory, Dispose, StrD' +
    'ispose oder ReallocMem(P, 0) frei, und der Zeiger verlässt die Routine nicht: weder zurückgegeben (Result, Exit) noch einer anderen Variablen oder einem Feld zugewiesen, nicht über seine Adresse (@P) ' +
    'weitergegeben, keiner Methode übergeben, die ihn behält (Add, Insert, Push …), nicht von einer anonymen Methode eingefangen und nicht in einer lokalen Routine benutzt. Zum Lesen oder Füllen weitergebe' +
    'n (Pruefsumme(P, N), Strom.ReadBuffer(P^, N)) ist erlaubt; eine Routine mit Free, Frei, Release, Dispose, Destroy oder Dealloc im Namen gilt als Freigabe. Eine Freigabe ohne try/finally meldet pair-wi' +
    'thout-finally. Konfidenz mittel. Schnellkorrektur: die folgenden Anweisungen des Blocks in try … finally mit der passenden Freigabe einschließen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "stringlist-objects-leak",' + #10 +
    '      "name": "Objekte in einer TStringList ohne Besitz",' + #10 +
    '      "description": "AddObject oder InsertObject legt ein neu erzeugtes Objekt (T.Create(…) direkt oder eine so erzeugte lokale Variable, die sonst nur gelesen wird) in eine TStringList (oder THashed' +
    'StringList), die die Unit ohne OwnsObjects erzeugt, oder in die Items eines Felds vom Typ TListBox, TComboBox, TCheckListBox, TComboBoxEx oder TColorListBox; niemand gibt diese Objekte frei. Besitzend' +
    ' ist eine Liste mit TStringList.Create(True) oder OwnsObjects := True. Still, wenn eine Routine der Unit Liste.Objects[…] liest und etwas freigibt, wenn die Liste weitergegeben wird (ObjekteFreigeben(' +
    'Liste), anderswo zugewiesen), wenn das Objekt einen Owner hat (Self, Owner, AOwner, Application oder ein Nachfahr von TComponent mit Argument) und bei Listen, die nicht in der Unit erzeugt werden. Kon' +
    'fidenz mittel. Schnellkorrektur: TStringList.Create(True) (auch statt Create(False)), bei anderen Konstruktoren OwnsObjects := True nach der Erzeugung; für Items von Steuerelementen keine."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "message-handler-without-inherited",' + #10 +
    '      "name": "Message-Handler ohne inherited",' + #10 +
    '      "description": "Eine Methode mit message WM_… oder CM_… ruft weder inherited noch DefaultHandler (bzw. DefWindowProc, CallWindowProc) auf. Die Standardbehandlung der VCL bzw. von Windows fällt w' +
    'eg: kein Neuausrichten bei WM_SIZE, kein Schließen bei WM_CLOSE, kein Zeichnen bei WM_PAINT. Die Meldung nennt für gängige Nachrichten die Folge. Still bleiben Klassen ohne Vorfahr, Nachrichten aus sw' +
    'allow (Vorgabe WM_ERASEBKGND) und Handler, die Msg.Result selbst setzen (bewusste Antwort wie MA_NOACTIVATE). Sicherheit mittel. Korrektur: inherited; am Anfang einfügen.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "swallow",' + #10 +
    '          "description": "Nachrichten, die ohne inherited behandelt werden dürfen; ersetzt die Vorgabe."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "string-index-base",' + #10 +
    '      "name": "String-Index ab 0 oder Pos-Ergebnis mit -1 verglichen",' + #10 +
    '      "description": "Die klassischen String-Routinen zählen ab 1: Copy(S, 0, N) und Insert(T, S, 0) wirken nur zufällig wie 1, Delete(S, 0, N) löscht nichts. Der String muss bekannt sein: deklarierte' +
    'r Typ in der Datei, Literal oder .Text/.Caption; dynamische Arrays (ab 0) bleiben still. Pos, PosEx und AnsiPos liefern 0 bei keinem Treffer: Pos(…) > -1, >= 0 und <> -1 sind immer wahr, = -1 und < 0 ' +
    'nie. Umgekehrt übersieht S.IndexOf(…) > 0 bzw. >= 1 den Treffer am Anfang, < 1 bzw. <= 0 zählt ihn als nicht gefunden (Sicherheit mittel; LastIndexOf bleibt still, dort heißt > 0 meist „nicht am Anfan' +
    'g“). Sicherheit hoch für Delete und Pos. Korrektur: Startwert 1 bzw. der richtige Vergleich (> 0, = 0, >= 0, < 0)."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "delimited-text-without-strict",' + #10 +
    '      "name": "DelimitedText ohne StrictDelimiter",' + #10 +
    '      "description": "Liste.DelimitedText := … nach Liste.Delimiter := … in derselben Routine, ohne dass StrictDelimiter gesetzt wird: DelimitedText trennt dann auch an Leerzeichen, ''Max Muster;Berlin' +
    ''' ergibt drei statt zwei Einträge. Bei Feldern zählt StrictDelimiter in der ganzen Unit (oft im Konstruktor); StrictDelimiter := False ist bewusst und bleibt still, ebenso DelimitedText ohne eigenen D' +
    'elimiter. Sicherheit hoch. Korrektur: StrictDelimiter := True; vor der Zuweisung einfügen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "self-as-interface-in-constructor",' + #10 +
    '      "name": "Self während der Konstruktion als Interface weitergegeben",' + #10 +
    '      "description": "Self wird als Interface weitergegeben, während die Referenzzählung das Objekt schon freigeben kann. Gemeldet werden nur zwei echte Fehlerfälle: (1) Eine Klasse mit eigener Refere' +
    'nzzählung (ein _Release in der Klassenkette gibt das Objekt frei, keine Klasse überschreibt NewInstance, die Kette ist bis TObject bekannt) gibt Self im Konstruktor oder in AfterConstruction als Inter' +
    'face weiter: Der Zähler steigt von 0 auf 1 und fällt wieder auf 0, das Objekt wird freigegeben, bevor die Konstruktion endet. (2) Ein Nachfahr von TInterfacedObject gibt Self in AfterConstruction nach' +
    ' inherited als Interface weiter: inherited AfterConstruction hat den Schutzzähler aus NewInstance schon abgebaut. Im Konstruktor eines TInterfacedObject-Nachfahren ist Self geschützt, die Regel bleibt' +
    ' still. Als Weitergabe zählen Self as IX, IX(Self), ein Argument, dessen Parameter in allen bekannten Überladungen ein Interface ist, und die Zuweisung an eine Interface-Variable. Sicherheit hoch. Kor' +
    'rektur in Fall 2: die Anweisung vor inherited verschieben."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "null-compare",' + #10 +
    '      "name": "Vergleich mit Null statt VarIsNull oder IsNull",' + #10 +
    '      "description": "X = Null bzw. X <> Null vergleicht einen Variant mit Null. Das Ergebnis hängt von der globalen Einstellung System.Variants.NullEqualityRule ab: Mit der Vorgabe ncrLoose vergleich' +
    't er wie erwartet, mit ncrStrict ist er nie wahr, mit ncrError löst er eine Exception aus. Eine Bibliothek, ein Testrahmen oder ein anderer Teil des Projekts kann die Einstellung ändern. VarIsNull(X) ' +
    'und Feld.IsNull prüfen unabhängig davon. Gemeldet wird nur, wo der Vergleich für sich steht (Bedingung, Argument, Zuweisung); not X = Null bindet als (not X) = Null und bekommt keine Korrektur. Sicher' +
    'heit hoch. Korrektur: Feld.IsNull bei X.Value auf FieldByName, FindField, Fields[…], ParamByName, Params[…] oder einem Feld vom Typ T…Field/T…Param, sonst VarIsNull(X); bei <> mit not davor."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unchecked-enum-cast",' + #10 +
    '      "name": "Zahl ungeprüft in Aufzählung umgewandelt",' + #10 +
    '      "description": "TStatus(N) mit einem Aufzählungstyp aus der Datei oder dem Index, wenn N aus einem Aufruf der Option sources stammt (FieldByName, ReadInteger, AsInteger, StrToInt): direkt im Arg' +
    'ument oder über eine Variable, die zwischen Zuweisung und Umwandlung nicht gelesen (geprüft) wird. Ein Wert außerhalb des Bereichs ergibt einen ungültigen Aufzählungswert, der in case durchfällt. Ensu' +
    'reRange, Min oder Max im Argument gelten als Prüfung; Konstanten, Rechnungen und unbekannte Typen bleiben still. Bei Aufzählungen mit eigenen Ordinalwerten nennt die Meldung den Bereich als Ord(Low(T)' +
    ')..Ord(High(T)). Sicherheit mittel. Korrektur bei direkter Quelle in einer eigenen Anweisung: Hilfsvariable, InRange-Prüfung mit raise EConvertError davor, System.Math in uses.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "sources",' + #10 +
    '          "description": "Aufrufe, deren Ergebnis als ungeprüft gilt."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "createprocess-readonly-commandline",' + #10 +
    '      "name": "CreateProcess mit unveränderlicher Befehlszeile",' + #10 +
    '      "description": "CreateProcess (CreateProcessW) und CreateProcessAsUser schreiben in den Puffer von lpCommandLine. Ein PChar auf Speicher, der nicht beschreibbar ist, führt zu einer Zugriffsverle' +
    'tzung. Gemeldet wird PChar(…)/PWideChar(…) auf: ein String-Literal oder eine Konstante; eine Verkettung aus genau einem Literal und einem Wert (ist der Wert leer, liefert die RTL das Literal selbst); ' +
    'eine lokale String-Variable, deren letzte Zuweisung vor dem Aufruf eines davon ist, ohne UniqueString danach; einen String-Parameter (Sicherheit mittel, der Aufrufer kann ein Literal übergeben). Funkt' +
    'ionsergebnisse wie Format und Verkettungen aus mehreren Teilen sind beschreibbare Heap-Strings und bleiben still, ebenso CreateProcessA, das die Befehlszeile selbst kopiert. Korrektur: Befehlszeile in' +
    ' eine lokale Variable kopieren und UniqueString aufrufen; bei einer Variablen UniqueString vor der Anweisung. In Schleifenbedingungen keine Korrektur."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "form-access-before-create",' + #10 +
    '      "name": "Zugriff auf ein Formular, das noch nicht erzeugt ist",' + #10 +
    '      "description": "Der Konstruktor, AfterConstruction oder der OnCreate-Handler eines automatisch erzeugten Formulars bzw. Datenmoduls benutzt die globale Variable eines anderen Formulars, das die ' +
    '.dpr erst danach mit Application.CreateForm erzeugt. Die Variable ist dort noch nil. Die Reihenfolge stammt aus der .dpr des Projekts, zu dem die Unit gehört; der OnCreate-Handler aus der Formulardate' +
    'i (ohne Eintrag FormCreate bzw. DataModuleCreate). Still, wenn die Routine die Variable prüft (Assigned, Vergleich mit nil), selbst zuweist, mit CreateForm erzeugt oder einen gleichnamigen lokalen Nam' +
    'en deklariert, und bei Formularen, die nicht automatisch erzeugt werden. Jede Variable wird je Routine einmal gemeldet. Sicherheit mittel. Keine Korrektur: die Reihenfolge in der .dpr ändern oder den ' +
    'Zugriff nach OnShow verlegen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "except-handler-order",' + #10 +
    '      "name": "Allgemeiner Exception-Handler vor speziellem",' + #10 +
    '      "description": "In einem try..except mit mehreren on-Handlern gewinnt der erste passende. Ein Handler für eine Klasse, die ein früherer Handler schon fängt, wird nie erreicht: Sein Code ist tot ' +
    'und die Sonderbehandlung läuft nie. Gemeldet, wenn ein früherer Handler dieselbe Klasse, einen Vorfahren davon, Exception (deckt jede Exception-Klasse ab) oder TObject nennt. Vorfahren kommen aus der ' +
    'Unit, dem Projektindex und einer Tabelle bekannter RTL-, VCL- und FireDAC-Exceptions (etwa EStreamError > EFOpenError, EIntError > ERangeError); unbekannte Klassen werden nur mit Exception und TObject' +
    ' verglichen. Korrektur: den speziellen Handler vor den allgemeinen verschieben (nur, wenn beide Handler auf eigenen Zeilen stehen). Ein doppelter Handler für dieselbe Klasse wird ohne Korrektur gemeld' +
    'et."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "reraise-exception-object",' + #10 +
    '      "name": "raise E statt raise im Handler",' + #10 +
    '      "description": "raise E; in einem Handler on E: … löst das gefangene Exception-Objekt als neues raise aus. Die RTL gibt das Objekt nicht doppelt frei, aber die Ausnahme beginnt jetzt im Handler:' +
    ' ExceptAddr und die Aufrufliste von Werkzeugen wie madExcept oder JclDebug zeigen auf den Handler statt auf den ursprünglichen Fehler, die Absprungstelle geht verloren. raise; wirft die aktuelle Excep' +
    'tion unverändert weiter. Auch raise E at … wird gemeldet, dann ohne Korrektur. Still, wenn der Handler das Objekt mit AcquireExceptionObject übernimmt oder der Variablen ein neues Objekt zuweist, in a' +
    'nonymen Methoden und bei Handlern ohne Variablennamen. Konfidenz hoch. Korrektur: raise E; → raise;."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "blocking-call-in-main-thread",' + #10 +
    '      "name": "Blockierender Aufruf im Hauptthread",' + #10 +
    '      "description": "Sleep, WaitFor, WaitForSingleObject, WaitForMultipleObjects oder Wait in Methoden von Formularen und Frames (Klassen, die von TForm, TCustomForm, TFrame oder TCustomFrame erben) ' +
    'und in Ereignis-Handlern (Methoden mit Parameter Sender) außerhalb von Thread-Klassen. Die Oberfläche friert ein, solange der Aufruf wartet; wartet der andere Thread auf Synchronize, hängt das Program' +
    'm. WaitFor ohne Timeout auf einer Variablen nennt die Gefahr der Synchronize-Verklemmung. Sleep, WaitForSingleObject und WaitForMultipleObjects zählen nur ohne Empfänger (oder mit Winapi.Windows), Wai' +
    'tFor und Wait nur mit Empfänger. Ein Literal-Timeout unter maxSleepMs (Sleep(10), WaitForSingleObject(H, 0)) bleibt still, außer ein kurzes Sleep in einer Warteschleife ohne Application.ProcessMessage' +
    's. Anonyme Methoden sind ausgenommen (TTask.Run, TThread.Queue), eingebettete Routinen gehören zu ihrer Methode. Konfidenz mittel. Keine Schnellkorrektur: die Arbeit in TTask.Run auslagern und das Erg' +
    'ebnis mit TThread.Queue melden.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "maxSleepMs",' + #10 +
    '          "description": "Literal-Timeouts unter diesem Wert (Millisekunden) werden nicht gemeldet; ein kurzes Sleep in einer Warteschleife schon."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "calls",' + #10 +
    '          "description": "Aufrufe, die blockieren. Andere Namen werden unabhängig von ihren Argumenten gemeldet."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "thread-loop-without-terminated",' + #10 +
    '      "name": "Thread-Schleife ohne Terminated",' + #10 +
    '      "description": "Eine while- oder repeat-Schleife in TThread.Execute oder in einer Methode der Thread-Klasse, die nur von dort aufgerufen wird (auch über andere solche Methoden, eingebettete Rout' +
    'inen eingeschlossen), prüft Terminated nicht. Terminate wirkt dann nicht, und WaitFor bzw. Free hängen beim Beenden. Gemeldet für Endlosschleifen (while True, until False) und für Warteschleifen mit S' +
    'leep, WaitFor, WaitForSingleObject, WaitForMultipleObjects, MsgWaitForMultipleObjects, Wait oder Yield, deren Bedingung und Rumpf Terminated bzw. CheckTerminated nie erwähnen. Thread-Klassen kommen au' +
    's der Unit und dem Index. Begrenzte Schleifen, for-Schleifen, anonyme Methoden und Klassen, die TerminatedSet überschreiben (sie beenden ihre Schleifen auf anderem Weg), bleiben still. Konfidenz hoch.' +
    ' Korrektur: Terminated in die Schleifenbedingung aufnehmen (while True → while not Terminated, sonst and not Terminated; until False → until Terminated, sonst or Terminated)."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "anonymous-thread-not-started",' + #10 +
    '      "name": "Anonymer Thread nie gestartet",' + #10 +
    '      "description": "TThread.CreateAnonymousThread(…) legt den Thread angehalten und mit FreeOnTerminate an. Ohne Start läuft er nie, und weil er nie endet, wird er auch nie freigegeben. Gemeldet für' +
    ' den Aufruf als eigene Anweisung und für eine lokale Variable (auch Inline-Variable), die weder mit Start oder Resume gestartet noch weitergegeben wird (Argument, Zuweisung, Result, Feld). Eigenschaft' +
    'en wie FreeOnTerminate oder OnTerminate zu setzen gilt nicht als Weitergabe. Konfidenz hoch. Korrektur: .Start anhängen; bei einer Variablen T.Start; nach der letzten Anweisung desselben Blocks, die s' +
    'ie erwähnt."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "task-exception-unobserved",' + #10 +
    '      "name": "Exception in TTask geht verloren",' + #10 +
    '      "description": "TTask.Run(…) bzw. TTask.Create(…).Start, dessen Ergebnis nicht gespeichert und nie mit Wait, Status o. ä. abgefragt wird und dessen anonyme Methode kein try … except hat. Eine Ex' +
    'ception im Task verschwindet still. Auch gemeldet für eine lokale Variable, die nie wieder vorkommt (bei TTask.Create nur in V.Start). Still bei gespeicherten Ergebnissen (Felder, Result, jede andere ' +
    'Verwendung der Variablen) und bei Methodenzeigern, deren Rumpf die Regel nicht sieht. Konfidenz mittel. Korrektur: den Rumpf in try … except einschließen und die Meldung über TThread.Queue mit ShowMes' +
    'sage im Hauptthread zeigen (ergänzt Vcl.Dialogs, in FireMonkey-Units FMX.Dialogs, und System.SysUtils im uses, wenn sie fehlen); nur, wenn begin und end der anonymen Methode auf eigenen Zeilen stehen.' +
    '"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dataset-loop-without-next",' + #10 +
    '      "name": "Datenmengen-Schleife ohne Next",' + #10 +
    '      "description": "while not Q.Eof do ohne Q.Next im Rumpf oder mit Next nur auf einem Teil der Wege, die die Schleife fortsetzen (if ohne else, Continue vor Next). Die Schleife dreht endlos auf de' +
    'mselben Datensatz. Delete, MoveBy, Last, Close, FindNext und Free zählen ebenfalls als Weiterbewegen; Break, Exit, Abort und raise beenden die Schleife. Innere while- und for-Schleifen laufen vielleic' +
    'ht nie und zählen nicht. Wird Q im Rumpf weitergegeben (Argument, Zuweisung, with), kann der Aufgerufene den Zeiger bewegen, und die Regel bleibt still. Konfidenz hoch, wenn Next ganz fehlt, mittel, w' +
    'enn nur einzelne Wege es auslassen. Korrektur: Q.Next; am Ende des begin … end-Rumpfs einfügen (nur, wenn Next ganz fehlt)."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dataset-edit-without-post",' + #10 +
    '      "name": "Edit oder Append ohne Post",' + #10 +
    '      "description": "Nach Edit, Append oder Insert (ohne Argumente) einer Datenmenge ruft dieselbe Routine weder Post noch Cancel (noch CheckBrowseMode) auf. Die Änderung bleibt offen und geht beim S' +
    'crollen still verloren oder wird später unerwartet gespeichert; bei einer Exception dazwischen bricht sie niemand ab. Still, wenn eine andere Routine der Unit dieselbe Datenmenge postet oder abbricht ' +
    '(Bearbeiten-Knopf mit eigenem Speichern-Knopf), und wenn die Datenmenge nach Edit weitergegeben wird (Argument, Zuweisung, with). Konfidenz mittel. Korrektur: die folgenden Anweisungen, die die Datenm' +
    'enge benutzen, in try … except einschließen, mit Post am Ende des try-Teils und Cancel; raise; im except-Teil."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "transaction-without-rollback",' + #10 +
    '      "name": "Transaktion ohne Rollback",' + #10 +
    '      "description": "StartTransaction ohne Rollback im except des unmittelbar folgenden try. Bei einer Exception bleibt die Transaktion offen und hält Sperren. Erkannt für FireDAC (TFDConnection, TFD' +
    'Transaction), IBX und dbExpress (StartTransaction/Commit/Rollback), dbExpress ab XE (BeginTransaction/CommitFreeAndNil/RollbackFreeAndNil, auch als T := Conn.BeginTransaction) und ADO (BeginTrans/Comm' +
    'itTrans/RollbackTrans). Die Option pairs ersetzt diese Paare durch eigene. Das Rollback darf in einem try … except innerhalb eines direkt folgenden try … finally stehen. Still, wenn eine andere Routin' +
    'e der Unit dieselbe Verbindung zurückrollt (Transaktion über mehrere Ereignisse). Konfidenz hoch. Korrektur: die Anweisungen bis zum Commit desselben Blocks in try … except mit Rollback (mit den Argum' +
    'enten des Commit) und raise; einschließen; nur, wenn im selben Block ein Commit folgt.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "pairs",' + #10 +
    '          "description": "Transaktionsmethoden je Bibliothek als [{\"start\": …, \"commit\": …, \"rollback\": …}]; ersetzt die eingebauten Paare."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "sql-write-without-where",' + #10 +
    '      "name": "UPDATE oder DELETE ohne WHERE",' + #10 +
    '      "description": "UPDATE oder DELETE ohne WHERE in einem String-Literal, in SQL.Text, SQL.Add, CommandText, im ersten Argument von ExecSQL, ExecSQLScalar, Open, ExecuteDirect oder Execute oder in ' +
    'SQL.Strings/CommandText der Formulardatei. Das betrifft alle Zeilen der Tabelle; meist ist die Bedingung vergessen. Die Regel setzt den SQL-Text je Query innerhalb einer Routine zusammen (Clear und ei' +
    'n neuer Text beginnen von vorn) und setzt Konstanten und lokale Werte ein. JOIN, TOP, LIMIT und ROWS schränken die Zeilen ebenfalls ein; ein WHERE in einer Unterabfrage oder einem Kommentar zählt nich' +
    't. Unbekannte Teile hinter dem Tabellennamen (Variablen, Aufrufe an der Stelle einer Klausel) lassen die Anweisung still; ein dynamischer Tabellenname meldet mit mittlerer Konfidenz. Still, wenn die R' +
    'outine den SQL-Text weitergibt oder eine andere Routine der Unit ihn ergänzt; SQL der Formulardatei zählt nur, solange die Unit es nicht verändert. Literale außerhalb von SQL-Eigenschaften zählen nur ' +
    'mit DELETE bzw. UPDATE in Großbuchstaben, damit Meldungstexte still bleiben. Konfidenz hoch, keine Korrektur; Tabellen, die absichtlich geleert werden, gehören in allowTables.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "allowTables",' + #10 +
    '          "description": "Tabellen, die absichtlich ganz geleert bzw. geändert werden, mit oder ohne Schema."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "signature-mismatch",' + #10 +
    '      "name": "Implementierung weicht von der Deklaration ab",' + #10 +
    '      "description": "Der Kopf im implementation-Teil hat andere Parameter (Anzahl, Name, Typ, const/var/out), einen anderen Ergebnistyp, procedure statt function oder eine andere Aufrufkonvention als' +
    ' die Deklaration im Typ (wie E2037). Bei Überladungen wird die nächstliegende Deklaration verglichen (Parameteranzahl, dann Typen, Namen und Modifizierer); ist sie nicht eindeutig, melden declared-not' +
    '-implemented und implemented-not-declared beide Seiten. Ein Rumpf darf Parameterliste, Ergebnistyp und Aufrufkonvention weglassen. Methoden in {$IF}-Blöcken werden übergangen; mit Include-Dateien ist ' +
    'die Konfidenz mittel. Korrektur: Kopf der Implementierung an die Deklaration angleichen oder als zweite Aktion die Deklaration an die Implementierung (Standardwerte bleiben in der Deklaration). refact' +
    'oring.syncSignatures = false entfernt nur die Korrekturen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "interface-not-implemented",' + #10 +
    '      "name": "Interface-Methode fehlt in der Klasse",' + #10 +
    '      "description": "Eine Klasse nennt ein Interface, implementiert aber nicht alle seine Methoden, auch die der Vorfahr-Interfaces (wie E2291). Eine gleichnamige Methode der Klasse mit anderer Signa' +
    'tur wird an dieser Methode gemeldet (wie E2211). Geerbte Methoden der Vorfahrklassen, Methodenzuordnungen (procedure IFoo.Bar = Baz) und Properties mit implements zählen; ebenso die öffentlichen Metho' +
    'den von TObject und die IInterface-Methoden von TInterfacedObject und ähnlichen RTL-Basen. Endet die Kette der Vorfahrklassen bei einer unbekannten Klasse oder ist das Interface unbekannt, bleibt die ' +
    'Regel still. Gemeldet wird auch eine Methodenzuordnung für ein Interface, das die Klasse nicht nennt (wie E2265). Klassen in {$IF}-Blöcken werden übergangen. Korrektur: fehlende Methoden deklarieren u' +
    'nd leer implementieren (nicht bei abweichendem Kopf)."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "uses-unit-not-found",' + #10 +
    '      "name": "Unit in uses nicht gefunden",' + #10 +
    '      "description": "Eine Unit aus uses oder contains liegt weder im Projekt noch in den Ordnern, die der Compiler durchsucht: Ordner der verwendenden Datei, Projektordner, Suchpfade und DCU-Ausgabeo' +
    'rdner der .dproj, Bibliothekspfade der Installation, jeweils als .pas oder .dcu und mit jedem Unit-Namespace davor (SysUtils → System.SysUtils); bei Packages zusätzlich die Units der requires-Packages' +
    ' (wie F2613). Ebenso gemeldet: eine Datei aus in ''…'', die es nicht gibt (F1026), ein Package aus requires, das weder als .dpk noch als .dcp gefunden wird (E2202), eine Unit, die sich selbst einbindet ' +
    '(F2092), und einmal eine fehlende Unit System, also ein fehlender Bibliothekspfad, statt einer Meldung je Unit (F1027). Einträge in {$IF}-Blöcken werden übergangen; ohne bekannte Installation, mit off' +
    'enem Makro in einem Suchpfad oder einem requires-Package mit unbekanntem Inhalt bleibt die Regel still. Die Meldung nennt ähnliche Units. Korrekturen: die Unit mit Namespace (Forms → Vcl.Forms) bzw. e' +
    'ine ähnlich geschriebene einsetzen oder den Ordner unter dem Projekt, in dem die Unit liegt, in DCC_UnitSearchPath der Basiskonfiguration der .dproj aufnehmen.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "searchPaths",' + #10 +
    '          "description": "Wo Units gesucht werden: project (wie der Compiler: Projekt, Suchpfade der .dproj, Bibliothekspfade, .pas und .dcu), atlas (was Atlas kennt: Index und Quellpfade der Installa' +
    'tion) oder both."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unresolved-attribute",' + #10 +
    '      "name": "Attribut nicht gefunden und still ignoriert",' + #10 +
    '      "description": "Ein Attribut [Name] lässt sich weder einer Klasse NameAttribute noch Name zuordnen, meist weil eine Unit in uses fehlt. Delphi warnt nur (W1074) und übergeht das Attribut: DUnitX' +
    '-Tests laufen dann nicht, JSON- oder ORM-Zuordnungen fehlen. Die Meldung nennt die Unit, die das Attribut im Index deklariert; eine Fassaden-Unit, die den Typ aus einer anderen Kandidatin weiterreicht' +
    ' (DUnitX.TestFramework statt DUnitX.Attributes), geht vor, und die DUnitX-Attribute sind auch ohne DUnitX im Index bekannt. Attribute des Compilers wie Weak, Unsafe, Ref und Volatile zählen immer. Sti' +
    'll ohne die Unit System im Index, wenn eine Unit aus uses nicht im Index steht (sie könnte das Attribut deklarieren), in {$IF}-Blöcken und bei unbekanntem Vorfahren der umgebenden Klasse; mit Include-' +
    'Dateien ist die Konfidenz mittel. Korrektur: Unit in uses aufnehmen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "comparison-as-statement",' + #10 +
    '      "name": "Vergleich statt Zuweisung als Anweisung",' + #10 +
    '      "description": "Ein Vergleich wie Result = 0; oder FAktiv = True; steht als eigene Anweisung; gemeint war :=. Delphi meldet E2014 erst beim Übersetzen. Bei = mit zuweisbarer linker Seite (Variab' +
    'le, Feld, Element, Ziel eines Zeigers) ersetzt die Korrektur = durch :=. Andere Vergleiche und Ausdrücke, deren Wert verfällt (A <> B;, A + B;, not A;, ein Literal), meldet die Regel ohne Korrektur, e' +
    'benso einen Aufruf links."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "duplicate-case-label",' + #10 +
    '      "name": "Doppelte case-Marke",' + #10 +
    '      "description": "Zwei Marken einer case-Anweisung decken denselben Wert ab (wie E2030), auch über Bereiche (1..5 und 3), Konstanten mit gleichem Wert, Zeichen (''a'' und #97) und Bereiche von Aufzä' +
    'hlungswerten. Gleiches gilt für die Marken eines varianten Record-Teils (wie E2027). Die Werte ergeben sich aus Zahlen, Zeichen, Konstanten und Aufzählungswerten über die Namensauflösung; Marken mit u' +
    'nbekanntem Wert vergleicht die Regel nur über den Text. Gemeldet wird eine Marke nur, wenn die frühere immer mit übersetzt wird: verschiedene Zweige desselben {$IF} stoßen nie zusammen. Korrektur: den' +
    ' doppelten Wert aus dem späteren Zweig entfernen bzw. den ganzen Zweig, wenn es seine einzige Marke war; eine teilweise Überschneidung von Bereichen meldet die Regel ohne Korrektur."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "field-after-method",' + #10 +
    '      "name": "Feld nach Methoden im selben Abschnitt",' + #10 +
    '      "description": "In einem Sichtbarkeitsabschnitt einer Klasse, eines Objekts oder Records folgt eine Felddeklaration auf eine Methode oder Property. Delphi verlangt Felder zuerst oder einen neuen' +
    ' Abschnitt bzw. var (E2169); FPC übersetzt das. Korrekturen: das Feld samt Attributen und Kommentaren an den Anfang des Abschnitts verschieben oder var davor setzen. In Records steht var vorn, weil da' +
    's Verschieben das Speicherlayout ändert. Gemeldet wird ein Feld nur, wenn eine Methode davor immer mit übersetzt wird, wenn das Feld übersetzt wird; mit bedingten Zweigen dazwischen gibt es nur var."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "overload-directive-missing",' + #10 +
    '      "name": "Überladung ohne overload oder mit gleicher Signatur",' + #10 +
    '      "description": "Zwei Routinen oder Methoden gleichen Namens im selben Gültigkeitsbereich (ein Typ, die Unit über interface und implementation, die in einer Routine verschachtelten Routinen), von' +
    ' denen mindestens eine kein overload trägt (wie E2254, bzw. E2267, wenn es der früheren fehlt), oder zwei Überladungen mit gleichen Parameterarten und -typen (wie E2252, bzw. E2301 mit auch gleichem E' +
    'rgebnistyp). Ein Rumpf zu einer früheren Deklaration (interface, forward) zählt nicht. Operatoren, Methodenrümpfe und Deklarationen in verschiedenen Zweigen desselben {$IF} bleiben außen vor. Korrektu' +
    'r: overload; an alle Deklarationen ohne anhängen, vor den übrigen Direktiven."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "duplicate-declaration",' + #10 +
    '      "name": "Bezeichner doppelt deklariert",' + #10 +
    '      "description": "Ein Bezeichner ist im selben Gültigkeitsbereich zweimal deklariert (wie E2004): lokale Variable, Konstante, Typ oder Label und ein Parameter der Routine, zwei Felder, ein Feld un' +
    'd eine Methode oder Property eines Typs, zwei Typen, Konstante und Variable der Unit über interface und implementation hinweg. Ebenso eine Unit doppelt in uses oder in den uses-Klauseln von interface ' +
    'und implementation zugleich (Option checkUses). Überladungen und Rümpfe von Routinen, eine Vorwärtsdeklaration und ihr Typ, TList neben TList<T> und Deklarationen in verschiedenen Zweigen desselben {$' +
    'IF} zählen nicht. Korrektur: zweite Deklaration entfernen (den ganzen var-, const-, type- oder label-Abschnitt, wenn sie seine einzige war; bei uses den doppelten Eintrag); keine bei Parametern, Metho' +
    'den und Properties.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "checkUses",' + #10 +
    '          "description": "Doppelte Einträge in uses-Klauseln melden."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "conditional-directive-unbalanced",' + #10 +
    '      "name": "Bedingte Direktiven unvollständig oder unbekannt",' + #10 +
    '      "description": "Ein {$IFDEF}, {$IFNDEF}, {$IFOPT} oder {$IF}, das nie geschlossen wird, sodass der Rest der Datei an seiner Bedingung hängt (wie E2095, bei {$IF} E2280); {$ELSE}, {$ELSEIF}, {$EN' +
    'DIF} oder {$IFEND} ohne passendes {$IF…} oder nach {$ELSE} (wie E2279); {$IFDEF}, {$IFNDEF}, {$DEFINE} oder {$UNDEF} ohne gültiges Symbol (wie E2173); eine unbekannte Direktive oder ein unbekannter {$' +
    'WARN}-Bezeichner (wie W1030), mit dem nächstliegenden bekannten Namen als Korrektur; {$POPOPT} ohne {$PUSHOPT} (wie W1078) oder {$PUSHOPT} ohne {$POPOPT} (wie W1079); ein ungültiger Wert für {$ALIGN} ' +
    'bzw. {$A} (wie E2573). Unbekannte Namen prüft die Regel nicht in Zweigen, deren Bedingung FPC abfragt, {$PUSHOPT}/{$POPOPT} nur, wenn keines davon in einem bedingten Zweig steht. Korrekturen: {$ENDIF}' +
    ' vor der ersten Leerzeile hinter dem offenen Block ergänzen, überzählige Direktive entfernen, Tippfehler korrigieren."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "override-target-missing",' + #10 +
    '      "name": "override ohne passende virtuelle Methode",' + #10 +
    '      "description": "Eine Methode mit override, zu der kein Vorfahr eine virtuelle (oder dynamic, abstract) Methode mit gleichem Namen und gleichen Parametern hat (wie E2137): oft ein Tippfehler (Des' +
    'tory) oder im Vorfahren geänderte Parameter. Die Meldung nennt die nächstliegende virtuelle Methode des Vorfahren („dort heißt es Ausfuehren(const Modus: TModus)“) bzw. einen ähnlichen Namen. Außerdem' +
    ': override auf eine statische Methode (wie E2170), auf eine finale (wie E2352) und Ableiten von einer sealed-Klasse (wie E2353). Vorfahren sucht die Regel in der Datei und im Symbolindex; bricht die K' +
    'ette an einer unbekannten Klasse ab, bleibt sie still. Ohne System im Index gelten die virtuellen Methoden von TObject als vorhanden. Typparameter generischer Vorfahren, Typaliase und Synonyme wie Lon' +
    'gint passen. Korrektur: Signatur des Vorfahren in Deklaration und Implementierung übernehmen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "abstract-class-instantiated",' + #10 +
    '      "name": "Instanz einer Klasse mit abstrakten Methoden",' + #10 +
    '      "description": "Create auf einer Klasse, die abstrakte Methoden deklariert oder erbt, ohne sie zu überschreiben (wie W1020), oder auf einer als abstract deklarierten Klasse (wie E2402). Der Aufr' +
    'uf einer abstrakten Methode löst zur Laufzeit EAbstractError aus; die Meldung nennt die offenen Methoden. Klassen sucht die Regel in der Datei und im Symbolindex; Überladungen mit gleicher Parameterza' +
    'hl gelten als eine Methode. Aufrufe über Klassenreferenzen, inherited Create und Konstruktor-Rümpfe prüft sie nicht. Korrektur für eine Klasse dieser Datei, die die abstrakten Methoden erbt: dort über' +
    'schreiben (wie die Code-Aktion „überschreiben“)."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "property-accessor-invalid",' + #10 +
    '      "name": "Getter oder Setter einer Property ungültig",' + #10 +
    '      "description": "Der Name hinter read oder write einer Property passt nicht: Er ist weder in der Klasse noch in ihren Vorfahren deklariert oder ist eine Property (wie E2168); Getter oder Setter h' +
    'aben die falsche Art, Parameter oder Typen (wie E2234); der Setter nimmt einen var- oder out-Parameter (wie E2282); die Zugriffsmethode ist überladen (wie E2271); eine Klassen-Property nutzt ein Insta' +
    'nzmitglied oder eine Klassenmethode ohne static (wie E2355), eine Instanz-Property ein Klassenmitglied (wie E2356); eine Array-Property oder eine Property mit index nutzt ein Feld (wie E2174); ein Fel' +
    'dselektor geht über ein Feld, das kein Record ist (wie E2459), nennt ein Mitglied, das kein Feld ist (wie E2461), oder ein Feld, das dem Record fehlt (wie E2562). Namen sucht die Regel in der Datei un' +
    'd für Vorfahren im Symbolindex; sie bleibt still, wenn die Kette der Vorfahren abbricht, der Name nur in einem inaktiven Zweig steht, die Klasse ihn nicht sieht oder Include-Dateien einbindet. Typen v' +
    'ergleicht sie nur, wenn beide eingebaut oder als eigener Typ deklariert sind. Korrektur für ein fehlendes F<Name>, Get<Name> oder Set<Name>: anlegen (wie die Vervollständigung hinter read/write, compl' +
    'etion.accessorSection)."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "assign-to-property-member",' + #10 +
    '      "name": "Zuweisung an ein Feld eines Property-Records",' + #10 +
    '      "description": "Zuweisung an ein Feld eines Records, den eine Property mit Getter, eine Default- oder Array-Property oder ein Funktionsergebnis nur als Kopie liefert (wie E2064): Die Zuweisung h' +
    'at keine Wirkung. Zuweisungen an untypisierte Konstanten meldet die Regel ebenso. Typen kommen aus der Namensauflösung; gemeldet wird nur bei sicher bekanntem Record-Typ. Liest die Property direkt ein' +
    ' Feld, schreibt Delphi in dieses Feld, und die Regel bleibt still. Korrektur bei einer Property mit write: über eine lokale Variable zuweisen und zurückschreiben; die Variable wird in der Routine dekl' +
    'ariert, die Unit ihres Typs in uses ergänzt."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "readonly-property-assigned",' + #10 +
    '      "name": "Zuweisung an eine Property ohne write",' + #10 +
    '      "description": "Zuweisung an eine Property ohne write (wie E2129) bzw. Lesen einer Property ohne read (wie E2130). Die Regel meldet nur, wenn die Namensauflösung die Property sicher findet; Neud' +
    'eklarationen ohne read und write (property Caption;) gelten als unbekannt. Korrekturen: Count := 0 wird Clear, wenn der Typ Clear hat; in einer Methode der deklarierenden Klasse das Feld hinter read z' +
    'uweisen; für eine Property dieser Datei den Setter anlegen und write ergänzen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "sql-select-star",' + #10 +
    '      "name": "SELECT * im Code",' + #10 +
    '      "description": "SELECT * oder SELECT Alias.* in einer Spaltenliste, an denselben Stellen wie bei sql-write-without-where: String-Literale, SQL.Text, SQL.Add, CommandText, das erste Argument von ' +
    'ExecSQL, Open und ähnlichen Aufrufen, Konstanten, lokale Werte und SQL.Strings/CommandText der Formulardatei. Neue Spalten ändern still die Datenmenge, persistente Felder passen nicht mehr, und es wer' +
    'den mehr Daten übertragen als nötig. Unterabfragen zählen; EXISTS (SELECT * …) und COUNT(*) bleiben still, ebenso eine Spaltenliste aus einer Variablen. Literale außerhalb von SQL-Eigenschaften zählen' +
    ' nur mit SELECT in Großbuchstaben und einem FROM, damit Meldungstexte still bleiben. Standardmäßig aus (in den Regeleinstellungen oder mit dem Profil strict einschalten). Konfidenz hoch. Schnellkorrek' +
    'tur: Steht der Stern in einem einzelnen Literal und hat die Datenmenge persistente Felder in der Formulardatei, ersetzt sie * durch deren FieldName-Liste (ohne berechnete und Nachschlagefelder)."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "path-concat-without-delimiter",' + #10 +
    '      "name": "Pfad ohne Trennzeichen zusammengesetzt",' + #10 +
    '      "description": "Ein Ordner ohne abschließendes Trennzeichen wird mit + an einen Datei- oder Ordnernamen gehängt: Ergebnisse von ExtractFileDir, ExcludeTrailingPathDelimiter, GetCurrentDir, GetHo' +
    'mePath, TPath.GetDocumentsPath und den übrigen TPath.Get…Path-Ordnern, TPath.GetDirectoryName, TDirectory.GetCurrentDirectory und TDirectory.GetParent, direkt aufgerufen oder in einer lokalen Variable' +
    'n, der die Routine nur solche Werte zuweist. Das Ergebnis ist C:\\Datendatei.txt statt C:\\Daten\\datei.txt. ExtractFilePath, IncludeTrailingPathDelimiter und TPath.GetTempPath enden mit einem Trennze' +
    'ichen und bleiben still, ebenso Trennzeichen, Endungen (ExtractFileExt, ''.bak'') und Texte, die mit Leerzeichen oder Satzzeichen beginnen. Ein Literal als Name meldet mit hoher, ein Bezeichner mit mitt' +
    'lerer Konfidenz. Geht eine lokale Variable an eine Prozedur außer ForceDirectories, FileExists und ähnlichen lesenden Aufrufen, kann sie dort geändert werden und bleibt still. Schnellkorrektur: TPath.' +
    'Combine(Ordner, Name), System.IOUtils wird in die uses eingetragen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "hardcoded-path",' + #10 +
    '      "name": "Fester Dateipfad im Code",' + #10 +
    '      "description": "Ein String-Literal mit Laufwerksbuchstaben (C:\\…, auch mit /) oder UNC-Pfad (\\\\server\\freigabe\\…); Pfade unter C:\\Users bzw. C:\\Documents and Settings bekommen eine eigene' +
    ' Meldung. Auf anderen Rechnern fehlt der Pfad. Laufwerkswurzeln wie ''C:\\'' allein und die Präfixe \\\\?\\ und \\\\.\\ bleiben still, ebenso Kommentare, Test-Units und Units aus allowUnits (z. B. eine ' +
    'Unit mit den Standardpfaden einer Installation). Konfidenz hoch, keine Korrektur: den Pfad aus TPath (GetDocumentsPath, GetHomePath, GetSharedDocumentsPath), den Einstellungen oder einer Umgebungsvari' +
    'ablen holen.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "allowUnits",' + #10 +
    '          "description": "Units, in denen feste Pfade erlaubt sind, nach Unit-Namen; * am Ende passt auf ein Präfix (App.Config*)."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "filename-compare-case",' + #10 +
    '      "name": "Dateinamen mit = verglichen",' + #10 +
    '      "description": "Ein Vergleich mit = oder <>, bei dem eine Seite ein Datei- oder Pfadname ist: das Ergebnis von ExtractFileName, ExtractFilePath, ExtractFileDir, ExtractFileExt, ExpandFileName, C' +
    'hangeFileExt und verwandten Funktionen aus System.SysUtils, von TPath.GetFileName, GetExtension, GetDirectoryName, GetFullPath, Combine und verwandten Methoden oder eine Variable bzw. Eigenschaft, der' +
    'en Name auf FileName endet, oder Application.ExeName. Unter Windows sind Kunde.pas und kunde.PAS dieselbe Datei. Vergleiche mit Leertext, nil oder einem Literal ohne Buchstaben bleiben still, ebenso E' +
    'xtractFileDir(X) = X (beide Seiten stammen aus demselben Text). Konfidenz mittel. Korrektur: SameFileName(A, B), bei <> not SameFileName(A, B); ergänzt System.SysUtils in der uses-Klausel, falls nötig' +
    '."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "initialization-not-finalized",' + #10 +
    '      "name": "Beim Start erzeugtes Objekt wird nicht freigegeben",' + #10 +
    '      "description": "Ein Objekt wird in initialization mit TKlasse.Create erzeugt und einer Unit-Variablen zugewiesen oder in einem class constructor erzeugt und einer class var zugewiesen, aber die ' +
    'Unit gibt es nirgends frei (kein Free, Destroy, DisposeOf, Release oder FreeAndNil in der ganzen Unit). FastMM meldet beim Beenden ein Leck; in Packages bleibt das Objekt bei jedem Entladen liegen. In' +
    'terface- und Record-Typen, Komponenten mit Owner (Application, Self, Owner) und Objekte, die die Unit weitergibt, bleiben still: Jede Erwähnung der Variablen muss harmlos sein (Zugriff auf ein Mitglie' +
    'd, Vergleich mit nil, Assigned, erneutes Create oder Zuweisung von nil); als Argument übergeben, anderswo zugewiesen, with, eine Property, die sie liest, oder FreeOnTerminate lassen die Regel schweige' +
    'n. Bei Variablen aus dem interface-Abschnitt und öffentlichen class vars schweigt sie auch, wenn eine andere Unit im Index den Namen verwendet. Konfidenz hoch. Korrektur: FreeAndNil am Ende von finali' +
    'zation bzw. im class destructor; fehlt der finalization-Abschnitt oder der class destructor (Deklaration und Rumpf), wird er angelegt, System.SysUtils kommt bei Bedarf in die uses-Klausel."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "compiler-warnings-disabled",' + #10 +
    '      "name": "Compiler-Warnungen oder Prüfungen bis zum Ende der Unit abgeschaltet",' + #10 +
    '      "description": "{$WARNINGS OFF}, {$HINTS OFF}, {$WARN X OFF}, {$R-}, {$Q-} (auch zusammen als {$R-,Q-}) oder die langen Formen {$RANGECHECKS OFF} und {$OVERFLOWCHECKS OFF} ohne spätere Wiederher' +
    'stellung bis zum Ende der Unit. Meldungen und Prüfungen verschwinden weit über die gemeinte Stelle hinaus, die 0/0/0-Regel wird unterlaufen. Jedes spätere ON, +, DEFAULT oder ERROR für denselben Schal' +
    'ter zählt als Wiederherstellung, auch in Mustern mit {$IFOPT}/{$IFDEF}, ebenso ein späteres {$POPOPT}. Ein Schalter, dessen Gegenstück in einem anderen Zweig desselben {$IF} steht ({$IFDEF DEBUG}{$R+}' +
    '{$ELSE}{$R-}{$ENDIF}), ist eine gewollte Einstellung je Konfiguration und bleibt still, ebenso eine Direktive ohne Code dahinter; {$R *.dfm} ist eine Ressource, keine Bereichsprüfung. Die Option allow' +
    ' nennt Schalter, die aus bleiben dürfen (Warnungsnamen wie SYMBOL_PLATFORM, WARNINGS, HINTS, R bzw. RANGECHECKS, Q bzw. OVERFLOWCHECKS). Konfidenz hoch. Korrektur: die Wiederherstellung ({$WARNINGS ON' +
    '}, {$WARN X DEFAULT}, {$R+} …) hinter dem nächsten Block einfügen; bei Bereichs- und Überlaufprüfung nur einzeln, weil {$R+} eine Prüfung einschalten kann, die das Projekt aus hat.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "allow",' + #10 +
    '          "description": "Schalter, die bis zum Ende der Unit aus bleiben dürfen: Warnungsnamen für {$WARN} (SYMBOL_PLATFORM), WARNINGS, HINTS, R bzw. RANGECHECKS, Q bzw. OVERFLOWCHECKS; ohne Groß-/Kl' +
    'einschreibung."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dll-export-unsafe",' + #10 +
    '      "name": "Exportierte Routine nicht sicher über DLL-Grenzen aufrufbar",' + #10 +
    '      "description": "Eine in exports aufgeführte Routine dieser Datei hat keine Aufrufkonvention (stdcall, cdecl, safecall, winapi oder pascal; register ist die Delphi-Konvention) oder erwartet bzw. ' +
    'liefert einen String (string, UnicodeString, AnsiString, UTF8String, RawByteString), ein dynamisches Array (TBytes, TArray<T>, …DynArray, array of T aus der Datei), ein Objekt oder ein Interface ohne ' +
    'GUID. Aufrufer aus anderen Sprachen oder Delphi-Versionen stürzen ab; Strings und dynamische Arrays liegen im Speichermanager der DLL. WideString, ShortString, PChar, offene Array-Parameter und Record' +
    's sind in Ordnung. Objekte erkennt die Regel nur sicher: Klassen der Datei, des Index und häufige RTL-Klassen; Interfaces nur aus der Datei. Routinen aus anderen Units und Überladungen, die der export' +
    's-Eintrag nicht festlegt, bleiben still. Mit ShareMem oder SimpleShareMem in der uses-Klausel sind Strings und dynamische Arrays erlaubt (Option allowShareMem). Die Meldung steht am Eintrag in exports' +
    '; bei Strings empfiehlt sie PChar mit Puffer und Länge. Konfidenz hoch. Korrektur: stdcall in jedem Kopf der Routine ergänzen (nur einzeln, weil das die Schnittstelle für vorhandene Aufrufer ändert)."' +
    ',' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "allowShareMem",' + #10 +
    '          "description": "Mit ShareMem oder SimpleShareMem in der uses-Klausel sind Strings und dynamische Arrays in exportierten Routinen erlaubt."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "destructor-not-nil-safe",' + #10 +
    '      "name": "Destruktor benutzt Felder, die nil sein können",' + #10 +
    '      "description": "Wirft ein Konstruktor, ruft Delphi sofort den Destruktor auf, obwohl noch nicht alle Felder angelegt sind. Gemeldet wird ein Zugriff im Destruktor (oder in einer privaten Methode' +
    ', die nur der Destruktor aufruft) auf ein Feld wie FZeilen.Clear, FDatei.Position oder FZeilen[0], wenn ein Konstruktor der Klasse das Feld (TKlasse.Create) erst nach einem Aufruf anlegt, der werfen k' +
    'ann, oder nur auf manchen Wegen. Die Zugriffsverletzung verdeckt dann die eigentliche Exception. Free, FreeAndNil, DisposeOf und Zugriffe nach Assigned(FFeld) bzw. FFeld <> nil sind nil-sicher; Before' +
    'Destruction läuft auf diesem Weg nicht. Konstruktoren von RTL-Klassen, die höchstens EOutOfMemory werfen (TStringList.Create, TObjectList<T>.Create(True)), inherited Create und Supports zählen nicht a' +
    'ls werfend. Konfidenz hoch. Schnellkorrektur: if Assigned(FFeld) then vor die Anweisung setzen. Mit onlyAfterRaisingCode aus zählt jedes im Konstruktor angelegte Feld.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "onlyAfterRaisingCode",' + #10 +
    '          "description": "Nur melden, wenn der Konstruktor vor dem Anlegen des Felds etwas aufruft, das eine Exception werfen kann."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "handle-leak",' + #10 +
    '      "name": "Windows-Handle wird nicht geschlossen",' + #10 +
    '      "description": "Ein Windows-Handle in einer lokalen Variablen wird auf einem Weg zum Ende der Routine nicht mit dem passenden Gegenstück geschlossen: CreateFile, CreateEvent, CreateMutex, OpenPr' +
    'ocess, CreateProcess (hProcess, hThread) und CreateToolhelp32Snapshot mit CloseHandle, FindFirstFile mit FindClose, RegOpenKeyEx/RegCreateKeyEx mit RegCloseKey, LoadLibrary mit FreeLibrary, GetDC mit ' +
    'ReleaseDC, CreatePen/CreateBrush/CreateFont/CreateBitmap mit DeleteObject, CreateCompatibleDC mit DeleteDC und weitere. Zurückgeben, Speichern in einem Feld oder einer globalen Variablen, Übergabe an ' +
    'eine unbekannte Routine und Verwenden in einer anonymen Methode gelten als Weitergabe. Zweige, in denen eine if-Prüfung sagt, dass das Öffnen misslang (H = 0, H = INVALID_HANDLE_VALUE, RegOpenKeyEx(..' +
    '.) <> ERROR_SUCCESS), und Ausnahmewege (siehe pair-without-finally) zählen nicht. Die Option pairs ergänzt eigene Paare. Konfidenz mittel. Schnellkorrektur, wenn das Handle nie geschlossen wird: die A' +
    'nweisungen nach dem Öffnen in try … finally mit dem Schließen einschließen bzw. das Schließen anhängen, wenn das Öffnen die letzte Anweisung ist.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "pairs",' + #10 +
    '          "description": "Zusätzliche Paare aus Öffnen und Schließen als \"Oeffnen>Schliessen\" oder {\"open\": …, \"close\": …}; die Öffnen-Funktion liefert das Handle, die Schließen-Prozedur bekommt' +
    ' es als einziges Argument."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "global-formatsettings-modified",' + #10 +
    '      "name": "Globale FormatSettings wird verändert",' + #10 +
    '      "description": "Zuweisung an die globale FormatSettings oder eines ihrer Felder (auch an die veralteten globalen Variablen DecimalSeparator, ShortDateFormat, ThousandSeparator … älterer Delphi-V' +
    'ersionen). Das ändert die Formatierung für die ganze Anwendung, für alle Packages im selben Prozess (im IDE-Plugin die IDE selbst) und für alle Threads und ist nicht threadsicher; häufig eine Notlösun' +
    'g, um einen Punkt als Dezimaltrenner zu erzwingen. Gemeldet wird nur, wenn der Name sicher die Variable aus System.SysUtils ist: keine lokale Deklaration, kein Mitglied der Klasse oder ihrer Vorfahren' +
    ' (still, wenn die Kette der Vorfahren an einer unbekannten Klasse endet), nicht in with. Ergänzt format-without-settings, das Formatierungsaufrufe ohne Settings meldet. Konfidenz hoch. Schnellkorrektu' +
    'r, wenn die Routine die globalen Settings nur einmal ändert und danach etwas formatiert: lokale TFormatSettings anlegen (TFormatSettings.Invariant bei DecimalSeparator := ''.'', sonst eine Kopie von For' +
    'matSettings mit dem geänderten Feld) und an die folgenden Formatierungsaufrufe übergeben. Mit allowInProgram sind die Zuweisungen in der .dpr erlaubt.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "allowInProgram",' + #10 +
    '          "description": "Zuweisungen in der .dpr erlauben, etwa einmal beim Programmstart."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-interface-dangling",' + #10 +
    '      "name": "Komponente als Interface gespeichert und freigegeben",' + #10 +
    '      "description": "Ein Nachfahr von TComponent (Formular, Frame, Datenmodul, eigene Komponente) implementiert ein Interface, aber TComponent zählt keine Referenzen. Gemeldet wird das Speichern des ' +
    'Objekts als Interface in einem Feld, einer globalen Variablen oder einer Liste (FAnsicht as IBeobachter an Bus.Anmelden, FListe.Add, Register, Subscribe …, Zuweisung an ein Feld oder eine globale Vari' +
    'able, Add in TList<IFoo>/TInterfaceList), wenn dieselbe Unit das Objekt freigibt (Free, Release, DisposeOf, FreeAndNil) und es nirgends abmeldet: FreeNotification auf dem Objekt, ein anderer Aufruf am' +
    ' selben Empfänger mit dem Objekt als Argument (Abmelden, Remove, Unsubscribe …), Clear oder eine weitere Zuweisung an dasselbe Feld. Nach der Freigabe zeigt das gespeicherte Interface ins Leere. Still' +
    ' bei Klassen mit eigenem _Release und wenn die Kette der Vorfahren an einer unbekannten Klasse endet. Ebenso gemeldet, ohne Schnellkorrektur: Nachfahren von TInterfacedObject, die so gespeichert und z' +
    'usätzlich mit Free freigegeben werden; das gespeicherte Interface hält dann ein freigegebenes Objekt, und eine Abmeldung davor gäbe es schon frei. Konfidenz mittel. Schnellkorrektur: Abmeldung vor der' +
    ' ersten Freigabe einfügen (Empfänger.Abmelden(…), wenn der Typ des Empfängers das Gegenstück hat, bzw. Feld := nil).",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "componentClasses",' + #10 +
    '          "description": "Basisklassen ohne Referenzzählung; mit TComponent zählen auch die bekannten VCL- und FMX-Klassen (TForm, TFrame, TDataModule …)."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unit-name-mismatch",' + #10 +
    '      "name": "Unit-Name passt nicht zum Dateinamen",' + #10 +
    '      "description": "Der Name hinter unit weicht vom Dateinamen ab, meist nach dem Umbenennen der Datei außerhalb der IDE (wie E1038, W1038). Groß-/Kleinschreibung zählt nicht, Punkte im Namen schon.' +
    ' In Programmen, Bibliotheken und Packages wird außerdem ein Eintrag uses X in ''Datei.pas'' gemeldet, dessen Datei eine andere Unit deklariert (wie E2085); die Regel liest dazu die Datei. Programme, Bib' +
    'liotheken und Packages selbst vergleicht sie nicht mit dem Dateinamen, weil der Compiler das auch nicht tut. {$WARN UNIT_NAME_MISMATCH OFF} oder {$WARNINGS OFF} vor dem Unit-Namen schaltet die Regel w' +
    'ie den Compiler ab. Korrekturen: Unit-Namen an den Dateinamen anpassen (die Datei umbenennen bleibt Sache der IDE) bzw. den uses-Eintrag auf die Unit der Datei ändern."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "text-after-final-end",' + #10 +
    '      "name": "Text nach dem abschließenden end.",' + #10 +
    '      "description": "Nach dem abschließenden end. einer Unit, eines Programms, einer Bibliothek oder eines Packages steht noch Quelltext. Der Compiler ignoriert ihn (wie W1011); meist ist es Code, de' +
    'r beim Einfügen ans Dateiende geraten ist und nie übersetzt wird. Kommentare und Direktiven werden nicht gemeldet (Option allowComments). Die Regel sucht das abschließende end. hinter dem letzten Absc' +
    'hnitt des Syntaxbaums und schweigt, solange der Parser Fehler meldet oder end. in einem {$IF…}-Zweig steht; {$WARNINGS OFF} vor end. schaltet sie ab. Schnellkorrektur: Text nach end. entfernen.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "allowComments",' + #10 +
    '          "description": "Kommentare und Direktiven nach end. erlauben."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "exports-invalid",' + #10 +
    '      "name": "exports-Klausel unzulässig",' + #10 +
    '      "description": "Eine exports-Klausel in einer Routine (wie E2191), der Export einer threadvar oder einer mit local deklarierten Routine (wie E2276), einer Variablen, Konstanten oder eines Typs (' +
    'wie E2121) oder derselbe Eintrag bzw. Exportname zweimal (wie E2287). Namen löst die Regel nur gegen globale Deklarationen der Datei auf; Namen aus anderen Units und Namen mit Punkt bleiben still, ebe' +
    'nso zwei Einträge in sich ausschließenden {$IF…}-Zweigen. Überladene Routinen mit verschiedenen Parameterlisten oder Exportnamen gelten als verschiedene Einträge. Ergänzt dll-export-unsafe (#973). Sch' +
    'nellkorrektur: doppelten Eintrag entfernen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unit-name-conflict",' + #10 +
    '      "name": "Unit-Name kollidiert",' + #10 +
    '      "description": "Eine Unit heißt wie eine für den Compiler reservierte Unit, System oder SysInit (wie E2272), oder {$NOINCLUDE X} nennt eine Unit, die der Compiler nicht kennt (wie E2242); dafür ' +
    'braucht die Regel die Unit-Suche des Projekts und schweigt ohne sichere Antwort. Die Quellen der RTL (source/rtl) prüft sie nicht. Nicht gemeldet: E2447, W1051 und X2421 gehören zu den Namensräumen de' +
    'r .NET-Metadaten, die dcc32/dcc64 nicht erzeugt; für E2399 nennt die Dokumentation keine Bedingung, und eine Unit Kunden neben Kunden.Daten übersetzt Delphi ohne Fehler (Spring.pas neben Spring.Collec' +
    'tions.pas). Schnellkorrektur für {$NOINCLUDE}: eine ähnlich geschriebene bekannte Unit einsetzen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "implicit-variants-unit",' + #10 +
    '      "name": "Variant ohne System.Variants in uses",' + #10 +
    '      "description": "Die Unit verwendet Variant oder OleVariant als Typ, ohne System.Variants in uses zu haben. Der Compiler bindet die Unit dann still ein (wie W1040) und ändert damit die Initialisi' +
    'erungsreihenfolge. Die Regel zählt Typangaben im Syntaxbaum (Variablen, Felder, Parameter, Ergebnisse, Typargumente); Variants in uses gilt auch in einem {$IF…}-Zweig und ohne Namespace. Still in Syst' +
    'em, SysInit und Variants selbst, wenn die Datei einen eigenen Typ Variant deklariert, und nach {$WARN IMPLICIT_VARIANTS OFF}. Standardmäßig aus (Profil strict). Schnellkorrektur: System.Variants in us' +
    'es aufnehmen (Variants, wenn die Unit SysUtils oder Classes ohne Namespace nennt)."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "file-encoding-unsupported",' + #10 +
    '      "name": "Kodierung oder Zeichen, die der Compiler nicht liest",' + #10 +
    '      "description": "Die Datei ist UTF-32 kodiert (wie F2438; erkannt an der BOM, dann keine weiteren Meldungen), oder der Code außerhalb von Strings, Kommentaren und Direktiven enthält ein Zeichen, ' +
    'das der Compiler ablehnt (wie E2038): typografische Anführungszeichen aus einer Webseite oder Textverarbeitung, die ASCII-Zeichen ! \" ? \\ ` | ~ sowie Satz- und Sonderzeichen und Emoji jenseits von A' +
    'SCII. Buchstaben, Ziffern und Verbinder wie U+203F bleiben in Bezeichnern erlaubt; asm-Blöcke und {$IF…}-Zweige werden übersprungen; Steuer-, Format- und Leerzeichen melden control-char und invisible-' +
    'char. Schnellkorrektur: ein Paar Anführungszeichen auf einer Zeile wird zum String; ein einzelnes Zeichen mit eindeutigem ASCII-Gegenstück (– − × ÷ ≤ ≥ ≠, Vollbreiten-ASCII) wird ersetzt. Eine UTF-32-' +
    'Datei hat keine Schnellkorrektur; als UTF-8 mit BOM speichern."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "anonymous-capture-invalid",' + #10 +
    '      "name": "Anonyme Methode erfasst, was sie nicht erfassen darf",' + #10 +
    '      "description": "Eine anonyme Methode greift auf einen var-, out- oder untypisierten Parameter oder auf Result einer umgebenden Routine bzw. anonymen Funktion zu (wie E2555). Der Name wird von in' +
    'nen nach außen aufgelöst (Parameter, var/const/type, lokale Routinen, Inline-Variablen, for var); in with und asm bleibt die Regel still, Deklarationen in Zweigen bedingter Übersetzung, die die Stelle' +
    ' ausschließen, zählen nicht. Korrektur: Wert vor der Anweisung in eine lokale Variable kopieren, in der anonymen Methode nur diese verwenden und nach der Anweisung zurückschreiben, wenn die Methode si' +
    'e zuweist."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "operator-declaration-invalid",' + #10 +
    '      "name": "Operator falsch deklariert",' + #10 +
    '      "description": "Ein class operator in einem Record oder einer Klasse ist so deklariert, wie Delphi es ablehnt: unbekannter Operatorname (wie E2393), falsche Parameterzahl (E2517), eigener Typ fe' +
    'hlt in den Parametern (E2518) bzw. bei Implicit/Explicit in Parametern und Ergebnis (E2521), Inc/Dec mit anderem Ergebnistyp als dem ersten Parameter (E2519), Vergleichsoperator ohne Boolean-Ergebnis ' +
    '(E2520), Umwandlung in oder aus einem Vorfahren (E2522, Kette innerhalb der Datei) oder Assign ohne var vor dem ersten Parameter (E2464). Typen gelten als gleich, wenn ihre Namen ohne Unit-Präfix und ' +
    'Typargumente übereinstimmen; Aliase des eigenen Typs in der Datei halten die Regel still, True, False und OnesComplement gelten als bekannt. Korrekturen: nächstliegender Operatorname, Boolean als Erge' +
    'bnis, Ergebnis wie der erste Parameter, var vor dem ersten Parameter, Parameterliste nach Vorlage; jeweils in Deklaration und Rumpf."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "generic-declaration-invalid",' + #10 +
    '      "name": "Generische Deklaration unzulässig",' + #10 +
    '      "description": "Eine generische Deklaration, die Delphi ablehnt: Einschränkungen class und record zugleich (wie E2507), eine Einschränkung doppelt (E2603), record zusammen mit constructor (E2516' +
    '), eine Klasse neben class bzw. record (E2552), zwei Klassen (E2553), ein Einschränkungstyp, der weder Klasse noch Interface ist (E2510); Typparameter an Aufzählung, Menge, Teilbereich, Zeiger, Klasse' +
    'nreferenz, Alias oder Helfer (E2508), an Destruktor oder Klassenkonstruktor (E2528), Operator (E2529), globaler Routine (E2530), virtueller, dynamischer, message- oder override-Methode (E2533) oder In' +
    'terface-Methode (E2535); class of eines parametrisierten Typs (E2548), generische Klasse, die von TCustomAttribute erbt (E2549), parametrisierter Typ als Attribut (E2565); ein Typparameter, der einen ' +
    'des umgebenden Typs verdeckt (H2509); ein Aufruf mit einer Zahl Typargumente, die keine Überladung hat (E2551, Klassen und Records der Datei mit Vorfahren aus der Datei); eine Methode eines generische' +
    'n Typs oder eine generische Methode aus dem interface-Teil, die ein Symbol des implementation-Teils verwendet (E2506; still in with und wenn die Vorfahrenkette nicht bekannt ist). Typen zählen nur, we' +
    'nn sie eingebaut oder in der Datei deklariert sind; unbekannte Typen halten die Regel still. Lokale Prozeduren in generischen Methoden (E2570) meldet die Regel erst, wenn der Abgleich mit Delphi 12/13' +
    ' bestätigt, dass sie noch abgelehnt werden."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "type-restriction-violated",' + #10 +
    '      "name": "Sprachregel für Records, Inline und Helfer verletzt",' + #10 +
    '      "description": "Feste Sprachregeln, die erst der Compiler meldet: virtuelle Methoden (wie E2379) oder andere virtuelle Direktiven (override, abstract, reintroduce, message, final; E2463) in Reco' +
    'rds, parameterlose Konstruktoren (E2394), Konstruktoren, deren Parameter alle Vorgabewerte haben (E2471), und Destruktoren (E2465) in Records, Klassenmethoden in Records ohne static (E2398); in Record' +
    '-Helfern virtuelle Methoden (E2598) und die übrigen virtuellen Direktiven (E2475); Felder in Helfern (class var ist erlaubt, E2599), Destruktor (E2295) oder Klassenkonstruktor (E2358) in einem Class-H' +
    'elfer, ein Helfer-Konstruktor, dessen erster Befehl kein Aufruf ohne Argumente ist (E2296), ein Class-Helfer mit Vorfahr-Helfer für einen Typ, der nicht vom Typ des Vorfahren abstammt (E2294, nur bei ' +
    'bekannter Vorfahrenkette), ein Helfer als Typ einer Deklaration (E2527) oder in einem generischen Typ (E2589); mehrere Klassenkonstruktoren (E2359, sich ausschließende bedingte Zweige zählen einmal), ' +
    'Klassenkonstruktoren mit Parametern (E2360) oder virtual, dynamic bzw. message (E2534); Methoden, Properties, Klassenmitglieder, Typen und Konstanten in lokalen oder anonymen Records (E2433 bis E2437)' +
    '; inline an virtuellen oder dynamischen Methoden (E2425), an Konstruktoren und Destruktoren (E2442), mit offenen Array-Parametern (E2439), mit asm-Rumpf (E2426), im interface-Teil deklariert mit Symbo' +
    'len des implementation-Teils (E2441), als lokale Routine mit Zugriff auf Variablen der umgebenden Routine (E2449) oder mit Aufruf eigener lokaler Routinen (E2501); lokale, absolute oder initialisierte' +
    ' threadvar (E2189, E2190, E2194). Die Prüfungen gelten für alle unterstützten Delphi-Versionen (10 Seattle bis 13). Option disabledChecks nimmt einzelne Codes aus. Korrekturen: Direktive entfernen, st' +
    'atic ergänzen.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "disabledChecks",' + #10 +
    '          "description": "Compilercodes, die die Regel nicht prüft, z. B. [\"E2425\"]."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "attribute-usage-invalid",' + #10 +
    '      "name": "Attribut falsch verwendet",' + #10 +
    '      "description": "Ein Attribut des Compilers steht dort, wo Delphi es ablehnt: [Weak] an einem Feld oder einer Variablen, deren Typ sicher weder Klasse noch Interface ist (eingebaute Werttypen, Re' +
    'cords, Aufzählungen, Mengen, Arrays, Zeigertypen der Datei, Aliase verfolgt; wie E2584), [Volatile] an Typ, Routine, Methode oder Property (E2325), Weak, Unsafe, Volatile oder Ref doppelt an derselben' +
    ' Deklaration (E2326; sich ausschließende Zweige zählen nicht) oder ein Attributargument, das sicher eine Variable oder Routine der Datei ist (E2448; vor dem Attribut sichtbar, nicht durch eine gleichn' +
    'amige Konstante, einen Typ oder eine andere Deklaration verdeckt). Eigene Attribute dürfen mehrfach stehen; ein Typ Weak bzw. WeakAttribute in der Datei macht die Regel für diesen Namen still. Keine S' +
    'chnellkorrektur."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "typeinfo-invalid",' + #10 +
    '      "name": "TypeInfo oder Default mit unzulässigem Argument",' + #10 +
    '      "description": "TypeInfo oder Default bekommt eine Variable statt eines Typs (wie E2133, E2537: Parameter, lokale, Inline- und Unit-Variablen, Felder, Properties, Result, for- und Ausnahmevariab' +
    'len), TypeInfo einen Typ ohne RTTI (Aufzählung mit festen Werten, Dateityp, Text/TextFile; E2134) oder Default einen Dateityp (E2538). Namen werden von innen nach außen aufgelöst; in with, in Helfern,' +
    ' in Methoden von Typen außerhalb der Datei, bei Deklarationen in anderen bedingten Zweigen und wenn Datei oder Index ein eigenes TypeInfo bzw. Default deklarieren, bleibt die Regel still. Korrektur: d' +
    'en deklarierten Typ der Variablen einsetzen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "missing-begin-end",' + #10 +
    '      "name": "Bedingung oder Schleife ohne begin … end",' + #10 +
    '      "description": "Der Rumpf von if … then, else, for, while oder with ist eine einzelne Anweisung ohne begin … end. Mit der Regel haben Bedingungen und Schleifen immer einen Block; eine später erg' +
    'änzte zweite Anweisung landet so nicht versehentlich außerhalb. else if bleibt erlaubt (das innere if braucht keinen eigenen Block); repeat … until, case … end, try … end und asm … end sind schon Blöc' +
    'ke. Eine leere Anweisung (if X then ;) meldet empty-statement. Rümpfe mit {$IFDEF} meldet die Regel nicht. Solange die Regel an ist, meldet redundant-begin-end nichts. Schnellkorrekturen: begin … end ' +
    'um die Anweisung setzen, für die ganze Methode oder für die ganze Datei, eingerückt nach den Formatierungseinstellungen; ein ; vor else wandert in den Block (kein E2153); mit format.elsePlacement \"sa' +
    'meLine\" steht else hinter dem neuen end (end else).",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "statements",' + #10 +
    '          "description": "Geprüfte Anweisungen; case für die Zweige von case-Anweisungen ergänzen."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "allowSingleLineExit",' + #10 +
    '          "description": "Exit, Continue, Break und raise in derselben Zeile wie die Bedingung erlauben (if … then Exit;)."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "allowSameLine",' + #10 +
    '          "description": "Eine einzelne Anweisung in derselben Zeile wie Bedingung bzw. Schleifenkopf erlauben."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "inherited-constructor-after-try",' + #10 +
    '      "name": "Geerbter Konstruktor erst im try-Block",' + #10 +
    '      "description": "Ein Konstruktor betritt einen try-Block, bevor er den geerbten Konstruktor aufgerufen hat (wie H2505). Self ist dort noch nicht initialisiert; eine Exception im Block kann auf ha' +
    'lb erzeugte Felder treffen. Als geerbter Konstruktor gilt inherited ohne Namen, mit dem Namen des Konstruktors oder mit einem Namen, der mit Create beginnt. Zweige von {$IFDEF} werden getrennt geprüft' +
    '. Korrektur, wenn der Aufruf die erste Anweisung im try-Block ist: vor try ziehen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "variant-record-managed-field",' + #10 +
    '      "name": "Verwalteter Typ im varianten Teil eines Records",' + #10 +
    '      "description": "Im varianten Teil eines Records (case … of) steht ein String, ein dynamisches Array, ein Interface, ein Variant oder ein Record mit solchen Feldern (wie E2154), ein verwalteter R' +
    'ecord mit class operator Initialize oder Finalize (wie E2418) oder ein Typparameter ohne record-Einschränkung (wie E2569); ebenso hinter file of (wie E2155, E2417). Typen werden in der Datei und im In' +
    'dex aufgelöst; unbekannte bleiben still. Korrekturen: Feld vor case in den festen Teil verschieben, ShortString verwenden oder den Typparameter mit record einschränken."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "guid-syntax-invalid",' + #10 +
    '      "name": "GUID mit falscher Schreibweise",' + #10 +
    '      "description": "Die GUID eines Interfaces oder einer typisierten TGUID-Konstante hat nicht die Form ''{8-4-4-4-12}'' (wie E2204): fehlende Klammern, falsche Zahl oder Länge der Blöcke, Zeichen, di' +
    'e keine Hexadezimalziffern sind, oft nach Hand-Bearbeitung. Geprüft werden nur einzelne Literale; Verkettungen und Konstanten bleiben still. Korrekturen: neue GUID erzeugen; fehlen nur die Klammern, s' +
    'ie ergänzen. Ergänzt interface-guid und duplicate-interface-guid."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "untyped-pointer-refcount",' + #10 +
    '      "name": "Untypisierter Zeiger umgeht die Referenzzählung",' + #10 +
    '      "description": "Ein Interface wird über eine Typumwandlung nach Pointer zugewiesen (Pointer(FIntf) := P, wie W1070). Die Referenzzählung läuft dann nicht mit: das Objekt wird zu früh freigegeben' +
    ' oder nie. Die Regel meldet nur, wenn die Namensauflösung den Interface-Typ sicher kennt; Strings (string, AnsiString …) meldet sie ebenfalls, mit dem Zusatz „dcc meldet das nicht“, weil Delphi bei ih' +
    'nen nur unter NEXTGEN warnt. Felder mit [weak] oder [unsafe] bleiben still. Korrekturen für ein Interface-Feld dieser Datei mit Pointer(Y) oder nil rechts: das Feld mit [weak] bzw. [unsafe] auszeichne' +
    'n und ohne Pointer zuweisen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "type-too-large",' + #10 +
    '      "name": "Typ überschreitet eine Größengrenze",' + #10 +
    '      "description": "Ein statisches Array oder Record ist 2 GB groß oder größer (wie E2100), ebenso eine Instanz eines generischen Typs dieser Datei (wie E2543). Atlas rechnet eine untere Grenze aus ' +
    'den Deklarationen: Indexbereiche über konstante Ausdrücke, Konstanten und Aufzählungen der Datei, eingebaute Typen, Records aus dem Index; Unbekanntes zählt 0, gemeldet wird also nur sicher. Gemeldet ' +
    'wird nur der innerste Typ, der die Grenze überschreitet. E2419 (Records über 1 MB) gilt nur für Delphi für .NET und wird nicht gemeldet. Keine Korrektur; stattdessen ein dynamisches Array oder einen Z' +
    'eiger verwenden."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "comparison-always-constant",' + #10 +
    '      "name": "Vergleich immer wahr oder immer falsch",' + #10 +
    '      "description": "Vergleich einer Variablen, eines Feldes, einer Property oder eines Funktionsergebnisses vom eingebauten Ganzzahltyp mit einer Konstanten außerhalb bzw. am Rand des Wertebereichs ' +
    '(wie W1021, W1022): Cardinal >= 0 ist immer wahr, Byte > 255 immer falsch. Ebenso case-Marken außerhalb des Bereichs des case-Ausdrucks (wie W1018). Gemeldet wird nur bei sicher bekanntem Typ, dessen ' +
    'Deklaration immer mit dem Vergleich übersetzt wird. NativeInt, LongInt und ihre vorzeichenlosen Gegenstücke gelten mit dem weitesten Bereich aller Plattformen; Teilbereichstypen meldet die Regel nicht' +
    '. Length(…) < 0 und Length(…) >= 0 meldet sie ebenfalls, obwohl dcc dort nicht warnt; die Meldung sagt das dazu."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "constant-initializer-mismatch",' + #10 +
    '      "name": "Initialisierung einer Konstanten passt nicht",' + #10 +
    '      "description": "Eine typisierte Konstante oder initialisierte Variable vom statischen Array-Typ hat mehr oder weniger Elemente als ihr Indexbereich (wie E2072), typisch nach einem neuen Wert in ' +
    'einer Aufzählung (array[TStatus] of string); geprüft je Dimension und auch für benannte Array-Typen der Datei. Ebenso Record-Konstanten, deren Felder in anderer Reihenfolge als deklariert stehen (wie ' +
    'E2083). Indexbereiche: Teilbereiche mit konstanten Grenzen, Aufzählungen ohne eigene Werte, Boolean, Byte, Char usw. Deklarationen mit bedingten Direktiven gelten als unsicher. Korrekturen: fehlende E' +
    'inträge mit Platzhalter ergänzen (Name des Aufzählungswerts als Kommentar), Felder in die Reihenfolge der Deklaration bringen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "case-selector-not-ordinal",' + #10 +
    '      "name": "case oder for ohne ordinalen Typ",' + #10 +
    '      "description": "case über einen nicht ordinalen Ausdruck (wie E2001): Strings, Gleitkommazahlen, Klassen und Interfaces; for-Schleife mit nicht ordinaler Zählvariable (wie E2032); case-Marken un' +
    'd Array-Grenzen, die Variablen, Felder, Properties, Parameter oder typisierte Konstanten statt Konstanten sind (wie E2026). Gemeldet wird nur bei sicher bekanntem Typ, dessen Deklaration immer mit der' +
    ' Anweisung übersetzt wird. Korrektur bei Strings mit lauter String-Literalen als Marken: case IndexStr(S, […]) of mit den Positionen als Marken, System.StrUtils kommt in die uses."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "suspicious-string-pointer-cast",' + #10 +
    '      "name": "Zeiger und Zeichenbreite eines Strings passen nicht zusammen",' + #10 +
    '      "description": "PChar bzw. PWideChar auf einen AnsiString, RawByteString oder UTF8String und PAnsiChar auf einen string, UnicodeString oder WideString (wie W1044): Zeiger und Zeichenbreite passe' +
    'n nicht zusammen, typisch nach der Unicode-Umstellung; die API liest dann Datenmüll bzw. nur das erste Zeichen. Gemeldet wird nur bei sicher bekanntem Typ des Arguments, dessen Deklaration immer mit d' +
    'er Umwandlung übersetzt wird. string(PAnsiChar) wandelt korrekt um, ein Zeiger auf TBytes kann gewollt sein; beides meldet die Regel nicht. Korrekturen: eigene Variable mit passendem Stringtyp deklari' +
    'eren (PChar(Pfad) mit Pfad: AnsiString wird Pfad: string), string(…) bzw. AnsiString(…) um das Argument, passenden Zeigertyp verwenden."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "inaccessible-member",' + #10 +
    '      "name": "Zugriff auf ein nicht sichtbares Mitglied",' + #10 +
    '      "description": "Zugriff A.B auf ein Mitglied, das an der Stelle nicht sichtbar ist: private bzw. strict private einer anderen Unit oder Klasse (wie E2361), protected bzw. strict protected außerh' +
    'alb der deklarierenden Unit und ihrer Nachfahren (wie E2362, E2389). In einer Klassenmethode oder statischen Methode sind Instanzfelder, -methoden und -Properties der Klasse nicht erreichbar (wie E212' +
    '4). Eine Property, die auf ein private-Mitglied eines Vorfahren derselben Unit verweist, meldet die Regel als Warnung (wie W1045). Gemeldet wird nur, wenn die Namensauflösung den Empfänger und seinen ' +
    'Typ sicher kennt und das Mitglied erst ohne Rücksicht auf die Sichtbarkeit findet; protected-Mitglieder bleiben über eine Klasse der eigenen Unit sichtbar (TZugang(Control).Click). Deklarationen in be' +
    'dingten Zweigen, Methoden von Helfern und verschachtelten Typen bleiben still."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unused-private-member",' + #10 +
    '      "name": "Privates Mitglied wird nie verwendet",' + #10 +
    '      "description": "Ein private- oder strict-private-Feld, eine Methode, Konstante oder Property kommt in der Unit nirgends vor (wie H2219, das der Compiler nur für Methoden meldet; Felder ebenso, a' +
    'ußer includeFields ist aus). Jedes Vorkommen des Namens als Bezeichner zählt als Verwendung, auch in inaktiven bedingten Zweigen und hinter read/write; Deklarationen und Methodenköpfe zählen nicht. Au' +
    'sgenommen: Methoden mit message, virtual, dynamic, override oder abstract, Methoden von Typen, die Interfaces umsetzen, Konstruktoren und Destruktoren, Mitglieder mit Attributen (RTTI), Namen aus der ' +
    'Formulardatei und Units mit Include-Dateien. Korrektur: Deklaration (samt ///-Doku) und den Rumpf einer Methode entfernen; nicht, wenn sich mehrere Mitglieder die Deklaration teilen oder die Methode ü' +
    'berladen ist.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "includeFields",' + #10 +
    '          "description": "Auch nie verwendete private Felder melden (der Compiler meldet nur Methoden)."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unused-public-member",' + #10 +
    '      "name": "Öffentliches Mitglied wird im Projekt nie verwendet",' + #10 +
    '      "description": "Eine public- oder published-Methode, -Konstante oder -Property (wahlweise auch protected-Mitglieder, Felder und Klassenvariablen sowie Routinen und Konstanten im interface-Abschn' +
    'itt einer Unit) wird in den Projekten der Projektgruppe nirgends verwendet. Die Suche läuft projektweit über den Symbolindex: Nur Dateien, deren Verwendungen im Index den Namen enthalten, werden geles' +
    'en, und jedes Vorkommen wird über die Namensauflösung zugeordnet; ein Vorkommen, das sich nicht auflösen lässt, zählt als Verwendung. Namen in Formulardateien (.dfm/.fmx) und in String-Literalen zähle' +
    'n als Verwendung. Gelten als verwendet: Interface-Umsetzungen und Mitglieder von Interfaces, Methoden mit virtual, dynamic, override, abstract oder message, Konstruktoren, Destruktoren, Operatoren, En' +
    'umeratoren, Default-Properties, implements, Mitglieder mit Attributen, published-Mitglieder von TPersistent-Nachfahren (Streaming), von Klassen aus RegisterComponents, RegisterClass oder RegisterClass' +
    'es und von Testklassen, published-Methoden, solange eine Formulardatei nicht lesbar ist, Property-Zugriffsmethoden, exportierte Routinen, Klassenhelfer und Mitglieder von Klassen mit unbekanntem Vorfa' +
    'hren. Still, solange Projekte laden oder der Index unvollständig ist, wenn eine Datei nicht lesbar ist, bei Units mit Include-Dateien und bei Units von Packages oder Bibliotheken (Nutzer außerhalb des' +
    ' Projekts), außer projectKinds lässt sie zu. Korrektur: als bewusst öffentlich markieren (lsp-ignore-Kommentar).",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "visibilities",' + #10 +
    '          "description": "Geprüfte Sichtbarkeiten: public, published, protected."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "memberKinds",' + #10 +
    '          "description": "Geprüfte Mitgliedsarten: method, constant, property, field, classVar."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "projectKinds",' + #10 +
    '          "description": "Projektarten, deren Units geprüft werden: application, package, library. Packages und Bibliotheken haben Nutzer außerhalb der Projektgruppe und sind deshalb standardmäßig aus' +
    '."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "unitLevel",' + #10 +
    '          "description": "Auch Routinen und Konstanten aus dem interface-Abschnitt einer Unit prüfen."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "scope",' + #10 +
    '          "description": "Wo nach Verwendungen gesucht wird: projectGroup (alle Projekte der Gruppe) oder project (nur die Projekte der Datei)."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "testsCountAsUse",' + #10 +
    '          "description": "Verwendungen in Testprojekten zählen; ist es aus, wird ein Mitglied, das nur Tests verwenden, als solches gemeldet."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "stringLiteralsCountAsUse",' + #10 +
    '          "description": "Der Name als String-Literal (''Name'') zählt als Verwendung (RTTI, MethodAddress, Skripte)."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "keepAttributes",' + #10 +
    '          "description": "Attribute am Mitglied oder seinem Typ, die es als verwendet markieren, z. B. \"Keep\" oder \"Api\"."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "keepPatterns",' + #10 +
    '          "description": "Namensmuster (* und ?) für Mitglieder, die immer als verwendet gelten, z. B. \"TPlugin.*\" oder \"*Callback\"."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "message-method-invalid",' + #10 +
    '      "name": "message-Methode falsch deklariert",' + #10 +
    '      "description": "Eine message-Prozedur einer Klasse hat nicht genau einen var-Parameter (wie E2138; der Typ wird nicht geprüft, ein untypisierter var-Parameter ist in Ordnung), ihre Nachrichtennu' +
    'mmer ist kleiner als 1 (wie E2139) oder eine frühere message-Methode derselben Klasse behandelt schon dieselbe Nummer (wie E2140, meist nach Kopieren). Nummern gelten als gleich, wenn ihre Werte bekan' +
    'nt sind (Zahlen, Konstanten aus dem Index) oder die Ausdrücke gleich lauten. Methoden in sich ausschließenden {$IF}-Zweigen sind nicht doppelt; dieselbe Nummer in einem Nachfahren überschreibt den Han' +
    'dler und ist erlaubt. Korrektur für E2138: einen einzelnen Parameter zu var machen, sonst die Liste durch (var Msg: TMessage) ersetzen; der Rumpf in derselben Datei wird mit angepasst."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "interface-declaration-invalid",' + #10 +
    '      "name": "Unzulässige Deklaration in einem Interface",' + #10 +
    '      "description": "Ein Interface deklariert etwas, das Interfaces nicht haben dürfen: Felder (wie E2209), Sichtbarkeitsabschnitte oder Methodendirektiven wie virtual, dynamic, abstract, override, m' +
    'essage oder reintroduce (wie E2210), die Property-Klauseln stored, nodefault oder default mit Wert (wie E2207; default; hinter einer Array-Property ist erlaubt), eine Property, die ein Vorfahr-Interfa' +
    'ce schon deklariert (wie E2206), oder einen Property-Accessor, den nur das Vorfahr-Interface deklariert (wie E2370). Ebenso gemeldet werden eine Klasse, ein Record oder eine Aufzählung als Vorfahr ein' +
    'es Interfaces oder in der Interface-Liste einer Klasse (wie E2205) und dasselbe Interface zweimal in dieser Liste (wie E2208). Typen werden über die uses-Klauseln aufgelöst; Aliase, unbekannte Typen, ' +
    'dispinterface und Deklarationen in bedingten Zweigen bleiben still."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "implements-clause-invalid",' + #10 +
    '      "name": "implements-Klausel unzulässig",' + #10 +
    '      "description": "Eine Delegation mit implements verletzt eine ihrer festen Regeln: implements nur in Klassen (wie E2258), nur an Properties mit Klassen- oder Interface-Typ (wie E2259; gemeldet fü' +
    'r eingebaute Typen, Records und Aufzählungen), nicht zusammen mit index (wie E2260), nur an lesbaren Properties (wie E2261), der Getter ohne andere Aufrufkonvention als register (wie E2262) und nicht ' +
    'dynamic oder message (wie E2263), jedes Interface nur über eine Property (wie E2257) und keine Methodenzuordnung für ein so umgesetztes Interface (wie E2264). Typen werden über die uses-Klauseln aufge' +
    'löst; unbekannte Typen, Aliase und Properties in bedingten Zweigen bleiben still."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "calling-convention-required",' + #10 +
    '      "name": "Aufrufkonvention passt nicht",' + #10 +
    '      "description": "Der Compiler schreibt hier die Aufrufkonvention vor: Konstruktoren und Destruktoren einer Klasse nur mit register (wie E2236), Getter und Setter von published-Properties ebenso (' +
    'wie E2270) und varargs nur mit cdecl (wie E2277 bei external-Routinen, sonst E2591). Ein ausdrückliches register ist in Ordnung; Klassenkonstruktoren, Accessoren außerhalb von published-Abschnitten un' +
    'd geerbte Accessoren bleiben still. Korrektur: die Konvention in der Deklaration und im Rumpf derselben Datei entfernen bzw. bei varargs cdecl setzen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "abstract-declaration-invalid",' + #10 +
    '      "name": "abstract, final oder static falsch kombiniert",' + #10 +
    '      "description": "Eine Methodendirektive, die der Compiler ablehnt: abstract ohne virtual, dynamic oder override (wie E2167), ein Rumpf im implementation-Teil zu einer abstrakten Methode (wie E213' +
    '6), final an einer nicht virtuellen Methode (wie E2351), abstract zusammen mit final (wie E2371), eine Klasse abstract sealed (wie E2383, E2540) oder static an einer Instanzmethode bzw. einer virtuell' +
    'en Klassenmethode (wie E2376). Ein Rumpf zählt nur dann als Rumpf einer abstrakten Methode, wenn keine gleichnamige nicht abstrakte Methode derselben Klasse mit ihm übersetzt wird (Überladungen, {$IFD' +
    'EF}-Zweige). Korrekturen: virtual; vor abstract einfügen, Rumpf entfernen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unsatisfied-forward",' + #10 +
    '      "name": "Vorwärtsdeklaration nie aufgelöst",' + #10 +
    '      "description": "Eine Routine aus dem interface-Teil oder mit forward hat keinen Rumpf (wie E2065), oder eine Vorwärtsdeklaration TFoo = class; bzw. IFoo = interface; wird im selben type-Abschnit' +
    't nie vollständig deklariert (wie E2086, E2420). Methoden prüft declared-not-implemented. Ein Rumpf passt, wenn er gleich heißt; bei overload muss auch die Zahl der Parameter stimmen. Ein external im ' +
    'implementation-Teil zählt als Rumpf. Deklarationen in einem {$IFDEF}-Zweig bleiben unbeachtet; mit Include-Dateien prüft die Regel keine Routinen. Korrektur: leeren Rumpf vor initialization bzw. dem a' +
    'bschließenden end. anlegen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "member-hides-ancestor",' + #10 +
    '      "name": "Member verdeckt einen Member des Vorfahren",' + #10 +
    '      "description": "Eine Property heißt wie ein Feld eines Vorfahren (wie W1009), ein Feld wie ein Feld oder eine Property eines Vorfahren oder eine nicht virtuelle Methode hat Namen und Parameter e' +
    'iner nicht virtuellen Methode eines Vorfahren. Code, der über den Vorfahrtyp zugreift, sieht weiter den alten Member. Virtuelle Methoden meldet hides-virtual, lokale Namen shadowed-name. Neu veröffent' +
    'lichte Properties (property Caption;), Properties mit neuem Typ über einer Property des Vorfahren, overload, reintroduce, Konstruktoren und Klassenmethoden bleiben unbeanstandet. Member, die der Nachf' +
    'ahre nicht sieht (private einer anderen Unit, strict private mit ignoreStrictPrivate), zählen nicht; Vorfahren kommen aus der Datei und dem Symbolindex. Korrektur für Felder und Properties: den Member' +
    ' in der Klassendeklaration und in den Rümpfen ihrer Methoden in dieser Unit umbenennen (aus FName wird FKundeName).",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "ignoreStrictPrivate",' + #10 +
    '          "description": "Verdeckte strict private Member des Vorfahren nicht melden."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "published-type-invalid",' + #10 +
    '      "name": "Unzulässiges Mitglied im published-Abschnitt",' + #10 +
    '      "description": "Ein Mitglied hinter einem ausdrücklichen published, das der Compiler ablehnt: eine Property vom Typ Record, Array, Zeiger oder Prozedurtyp ohne of object (wie E2188), vom Typ Rea' +
    'l48 (wie E2186) oder eine Menge über 4 Byte (wie E2187), ein Feld, das weder Klasse noch Interface ist (wie E2217), mehr als eine published-Überladung (wie E2266), eine Klassen-Property (wie E2545) od' +
    'er ein Name mit Zeichen außerhalb von ASCII (wie E2452). Typen löst die Regel über die Datei und den Index auf und verfolgt Aliase; Typparameter, unbekannte Typen und Abschnitte, deren published in ei' +
    'nem anderen Zweig der bedingten Übersetzung steht als das Mitglied, bleiben still. Den Abschnitt ohne Sichtbarkeitsangabe prüft sie nicht, weil der Compiler solche Mitglieder dort still zu public hera' +
    'bstuft. Korrektur: das Mitglied in den public-Abschnitt verschieben."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "override-case-mismatch",' + #10 +
    '      "name": "Schreibweise oder Sichtbarkeit weicht vom Vorfahren ab",' + #10 +
    '      "description": "Eine überschreibende Methode schreibt ihren Namen anders als der Vorfahr (destructor destroy, wie H2365) oder ist weniger sichtbar als die überschriebene Methode (wie H2269, nur ' +
    'für Klassen im interface-Teil; verglichen werden die Stufen privat, geschützt, öffentlich), ein Getter oder Setter heißt Get<Property> bzw. Set<Property>, ist aber anders geschrieben (wie H2367), oder' +
    ' eine inline-Methode greift auf ein Mitglied zu, das weniger sichtbar ist als sie selbst, sodass der Compiler sie außerhalb der Klasse nicht einsetzen kann (wie H2440). Wichtig für C++Builder-Nutzer d' +
    'er Units und für einheitlichen Code. Die Docwiki führt H2269 und H2367 als X2269 und X2367, weil sich ihre Stufe umstellen lässt; dcc meldet sie standardmäßig als Hinweis. H2368 und H2369 deckt die Re' +
    'gel nicht ab, weil nicht dokumentiert ist, wann dcc sie meldet. Standardmäßig aus; in atlas.json einschalten. Korrekturen: Schreibweise vom Vorfahr übernehmen, Zugriffsmethode umbenennen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "default-property-invalid",' + #10 +
    '      "name": "default-Property falsch deklariert oder fehlt",' + #10 +
    '      "description": "default; hinter einer Property ohne Indexparameter (wie E2132), eine zweite default-Property derselben Klasse mit denselben Indextypen (wie E2131; Überladung über den Indextyp is' +
    't erlaubt) oder Obj[I] auf einer Klasse, die in ihrer ganzen Vorfahrenkette keine default-Property hat (wie E2149). Den Typ von Obj ermittelt die Namensauflösung; nicht auflösbare Typen, abgebrochene ' +
    'Vorfahrenketten und Klassen mit einem Class-Helper in der Unit bleiben still. Neudeklarationen ohne Typ (property Items; default;) übernehmen den Index des Vorfahren und werden nicht geprüft."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "property-redeclaration-invalid",' + #10 +
    '      "name": "Neu deklarierte Property fehlt im Vorfahren",' + #10 +
    '      "description": "Eine Neudeklaration ohne Typ wie property Caption; (um Sichtbarkeit oder Standardwert zu ändern) nennt eine Property, die kein Vorfahr hat (wie E2147), oder die Property des Vorf' +
    'ahren ist von hier aus nicht erreichbar: strict private oder private in einer anderen Unit (wie E2233). Gemeldet nur, wenn die ganze Vorfahrenkette bekannt ist; ein gleichnamiges Feld oder eine Method' +
    'e und Deklarationen in inaktiven Zweigen bleiben still. Korrektur: den ähnlichsten Property-Namen der Vorfahren verwenden."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "inline-not-expanded",' + #10 +
    '      "name": "Inline-Funktion wird nicht eingebettet",' + #10 +
    '      "description": "Aufruf einer inline-Routine aus einer anderen Unit, die der Compiler nicht einbettet: Ihr Rumpf braucht eine Unit, die hier in uses fehlt (wie H2443, typisch System.Generics.Coll' +
    'ections bei TJSONObject.Count), er greift auf ein strict private-Mitglied zu und der Aufruf steht nicht in einer Methode dieser Klasse (wie H2444), die aufrufende Routine ist selbst inline und die Uni' +
    't der gerufenen steht nur im uses des implementation-Teils (wie H2445), oder die Unit der gerufenen Routine verwendet diese Unit direkt (wie H2456) bzw. über andere Units (wie H2457). Geprüft werden A' +
    'ufrufe, Properties mit inline-Getter bzw. -Setter und for-in (GetEnumerator, MoveNext, Current). Der Index merkt sich, worauf jeder inline-Rumpf verweist; die Regel meldet nur, was sie sicher auflöst ' +
    '(unbekannte Verweise und geerbte Mitglieder aus anderen Units bleiben stumm). Mit {$INLINE OFF} in der Datei schweigt sie. Korrektur: die fehlenden Units in das uses des Abschnitts aufnehmen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "directive-typo",' + #10 +
    '      "name": "Unbekannte Direktive (Tippfehler)",' + #10 +
    '      "description": "An der Stelle einer Direktive steht ein Wort, das keine ist: nach dem '';'' eines Routinen- oder Methodenkopfs (overide;, virutal;, overlaod;, stdcal;, reintroduces;) oder nach ein' +
    'er Property, wo nur default erlaubt ist (defualt;). Der Compiler bricht dort ab (wie E2070). Die Meldung schlägt die ähnlichste Direktive vor, wenn höchstens zwei Zeichen abweichen. Still in {$IF}-Zwe' +
    'igen, die FPC abfragen; FPC kennt weitere Direktiven wie nostackframe. Korrektur: durch die vorgeschlagene Direktive ersetzen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "ui-call-in-console-or-service",' + #10 +
    '      "name": "Dialog in Konsolenprogramm oder Dienst",' + #10 +
    '      "description": "ShowMessage, ShowMessageFmt, MessageDlg, TaskMessageDlg, InputBox, InputQuery, Application.MessageBox oder TDialogService in einem Programm mit {$APPTYPE CONSOLE} (oder DCC_Conso' +
    'leTarget in der .dproj), in einem Windows-Dienst oder in einer DLL ohne Formulare. Im Dienst blockiert der Dialog unsichtbar; ein Konsolenprogramm wartet auf einen Klick, den niemand sieht, wenn es un' +
    'beaufsichtigt läuft. Als Dienst gilt eine Unit mit einer Klasse, die von TService erbt, oder jede Unit eines Projekts, dessen .dpr Vcl.SvcMgr ohne Vcl.Forms einbindet. Eine DLL ohne Formulare ist eine' +
    ' library, deren .dpr kein Formular aufführt und Vcl.Forms nicht einbindet; dort meldet die Regel mit mittlerer Konfidenz, weil erst der Host entscheidet, ob es eine Oberfläche gibt. Units mit Formular' +
    'datei, Aufrufe unter if IsConsole und gleichnamige Routinen der Unit bleiben still. Gegenstück zu writeln-in-gui-app. Konfidenz hoch. Keine Schnellkorrektur: die Meldung protokollieren statt anzeigen.' +
    '"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "load-without-encoding",' + #10 +
    '      "name": "Text laden oder speichern ohne Kodierung",' + #10 +
    '      "description": "LoadFromFile, SaveToFile, LoadFromStream oder SaveToStream einer TStrings (TStringList, Memo.Lines, ListBox.Items, Query.SQL) sowie TFile.ReadAllText und TFile.ReadAllLines ohne ' +
    'Kodierung: Eine Datei ohne BOM wird mit der ANSI-Codepage des Rechners gelesen, SaveToFile schreibt ANSI, und Umlaute gehen zwischen Rechnern verloren. Der Empfänger muss eine deklarierte Stringliste ' +
    'oder eine Property Lines, Items, SQL oder Strings sein; Bilder, Streams und Datenmengen bleiben still. Ebenso still, wenn die Liste irgendwo in der Unit DefaultEncoding setzt oder in derselben Routine' +
    ' vorher mit Kodierung geladen wurde (SaveToFile behält diese Kodierung). TFile.WriteAllText, TStreamReader und TStreamWriter nehmen ohne Angabe schon UTF-8 und werden nicht gemeldet. Konfidenz mittel.' +
    ' Schnellkorrektur: TEncoding.UTF8 (Option defaultEncoding) als letztes Argument und System.SysUtils im uses ergänzen.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "defaultEncoding",' + #10 +
    '          "description": "Property von TEncoding, die die Schnellkorrektur einsetzt: UTF8, Unicode, BigEndianUnicode, ANSI, ASCII, UTF7 oder Default."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "registry-hklm-write",' + #10 +
    '      "name": "Schreiben nach HKEY_LOCAL_MACHINE",' + #10 +
    '      "description": "RootKey := HKEY_LOCAL_MACHINE auf einer TRegistry, danach in derselben Routine ein schreibender Zugriff auf dasselbe Objekt: OpenKey(…, True), CreateKey, Write…, DeleteKey, Delet' +
    'eValue, RenameValue, MoveKey, SaveKey oder RestoreKey. Ohne Administratorrechte schlägt das fehl oder landet still in der Virtualisierung der Registry. Für Benutzereinstellungen HKEY_CURRENT_USER verw' +
    'enden; Installer-Code über exclude ausnehmen. Lesen (OpenKeyReadOnly, Read…, OpenKey(…, False)), ein anderer RootKey vor dem Schreiben und Schreiben im anderen Zweig von {$IFDEF} bleiben still. Konfid' +
    'enz hoch. Schnellkorrektur: RootKey := HKEY_CURRENT_USER."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "now-for-elapsed-time",' + #10 +
    '      "name": "Laufzeit mit Now gemessen",' + #10 +
    '      "description": "Eine Variable, der Now zugewiesen wird und die in derselben Routine danach in Now - Start, Ende - Start oder MilliSecondsBetween, SecondsBetween, MinutesBetween, HoursBetween, Da' +
    'ysBetween bzw. den …Span-Funktionen vorkommt: Die Laufzeit wird mit der Uhrzeit gemessen, grob aufgelöst und falsch bei Zeitumstellung oder Uhrabgleich. TStopwatch ist genau und monoton. Zuweisungen i' +
    'n einer anderen Routine (Felder) und im anderen Zweig von {$IFDEF} bleiben still. Konfidenz hoch. Schnellkorrektur, wenn die Variable eine lokale TDateTime ist (auch var Start := Now) und nur für Mill' +
    'iSecondsBetween, SecondsBetween oder MinutesBetween mit Now dient: TStopwatch.StartNew und ElapsedMilliseconds (div 1000 bzw. div 60000), die Variable heißt danach Uhr, wenn der Name frei ist, System.' +
    'Diagnostics kommt ins uses."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "money-as-float",' + #10 +
    '      "name": "Geldbetrag als Gleitkommazahl",' + #10 +
    '      "description": "Feld, Variable, Parameter oder Property, deren Name einen Geldbetrag bezeichnet (Option namePatterns), mit dem Typ Double, Single, Extended oder Real: Binäres Gleitkomma rundet C' +
    'ent-Beträge falsch (0.1 + 0.2), Currency rechnet sie exakt. Maßgeblich ist der letzte Namensteil (GesamtPreis, Nettobetrag, FNetto, Preise; nicht NettoGewicht); Sätze, Faktoren, Quoten, Anteile (Steue' +
    'rsatz, PriceFactor) und Prüfsummen bleiben still. Mehrdeutige Wörter (Amount, Summe, Sum, Total: Menge bzw. Summe von irgendetwas) zählen nur mit Geldbezug in Typ bzw. Routine: ein anderer Geldname, C' +
    'urrency oder Wörter wie Cent, Euro, Rabatt, Rechnung, Zahlung, Kosten (Lighten(AColor, AAmount: Double) bleibt still). Standard aus und niedrige Konfidenz: Treffer erscheinen, wenn die Regel eingescha' +
    'ltet und minConfidence low ist. Schnellkorrektur, wenn alle Namen der Deklaration Geldbeträge sind: Typ Currency, bei Parametern auch im Kopf der Implementierung, bei Feldern und Properties auch die P' +
    'roperty bzw. das Feld hinter read und write; keine Korrektur, wenn ein Getter oder Setter mitwandern müsste. Mit checkRound meldet die Regel zusätzlich Round mit einem Geldbetrag im Argument (Banker''s' +
    ' Rounding: 2,5 wird 2).",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "namePatterns",' + #10 +
    '          "description": "Namensteile, die einen Geldbetrag bezeichnen; Mehrzahl eingeschlossen."' + #10 +
    '        },' + #10 +
    '        {' + #10 +
    '          "name": "checkRound",' + #10 +
    '          "description": "Zusätzlich Round auf Geldbeträgen melden."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "string-if-chain",' + #10 +
    '      "name": "Lange if-Kette über denselben String",' + #10 +
    '      "description": "Eine if … else if-Kette vergleicht denselben String (Bezeichner oder A.B, keine Funktionsaufrufe) mit mindestens min Literalen: S = ''x'', ''x'' = S, SameText(S, ''x''), auch mit or ve' +
    'rknüpft, in mindestens zwei Zweigen (ein einzelnes if mit or bleibt still). case IndexStr(S, [...]) of oder ein Dictionary ist kürzer und schneller. Es zählen nur Vergleiche, die immer zusammen mit de' +
    'm Kopf übersetzt werden ({$IFDEF}-Zweige innerhalb der Kette nicht). Standard aus, Konfidenz hoch. Schnellkorrektur wie die Code-Aktion if-Kette in case umwandeln (#646): case IndexStr(…) of, IndexTex' +
    't(…) bei SameText, mit or verknüpfte Vergleiche teilen sich eine Marke, der Rest der Kette wird zum else, System.StrUtils kommt ins uses. Keine Korrektur bei Kommentaren oder Direktiven zwischen den Z' +
    'weigen, doppelten Literalen oder gemischtem = und SameText.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "min",' + #10 +
    '          "description": "Ab so vielen Vergleichen desselben Strings meldet die Regel; mindestens 2."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "prefer-case",' + #10 +
    '      "name": "if-Kette lässt sich als case schreiben",' + #10 +
    '      "description": "Eine if … else if-Kette mit mindestens min Zweigen (das abschließende else zählt mit) vergleicht denselben ordinalen Ausdruck (Ganzzahl, Zeichen, Aufzählung; ohne Seiteneffekte, ' +
    'kein Funktionsaufruf) mit Konstanten: X = a, a = X, X in [a, b..c], (X >= a) and (X <= b), auch mit or verknüpft. Die Marken sind Literale, Konstantenausdrücke, untypisierte Konstanten oder Aufzählung' +
    'swerte, ohne Doppelte und Überlappungen. Den Typ liefert die Namensauflösung; Ketten mit unbekanntem Typ und Ketten mit Direktiven bleiben still. Standard aus, Konfidenz hoch. Schnellkorrektur: die Co' +
    'de-Aktion „In case umwandeln“ (#646, refactoring.ifCase); begin … end nur, wo ein Zweig mehrere Anweisungen hat, Kommentare in den Zweigen bleiben.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "min",' + #10 +
    '          "description": "Ab so vielen Zweigen (das abschließende else eingeschlossen) meldet die Regel; mindestens 2."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "constant-condition",' + #10 +
    '      "name": "Bedingung ist immer gleich",' + #10 +
    '      "description": "Die Bedingung von if, while oder until steht fest: True, False, Vergleiche von Zahlen und untypisierte Konstanten der Datei, auch über and, or, xor und not (X or True ist immer w' +
    'ahr, X and False immer falsch). Der Zweig ist toter Code oder läuft immer. while True do und repeat … until False gelten als gewollte Endlosschleifen (deren Ausgang prüft infinite-loop). Konstanten au' +
    's switchConstants, Konstanten in einem Zweig von {$IF…} und Konstanten aus anderen Units gelten als unbekannt. Korrektur bei if: toten Zweig bzw. die Bedingung entfernen.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "switchConstants",' + #10 +
    '          "description": "Konstanten, die bewusst als Schalter dienen; Bedingungen darauf werden nicht gemeldet."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "infinite-loop",' + #10 +
    '      "name": "Schleife ohne Ausgang",' + #10 +
    '      "description": "while True do, repeat … until False oder eine andere Schleife, deren Bedingung sie nie beendet, ohne Ausgang im Rumpf: kein Break (ein Break in einer inneren Schleife verlässt nu' +
    'r diese), Exit, raise, goto, Halt, Abort oder RunError, kein Aufruf einer Routine der Datei, die eine Ausnahme auslöst oder das Programm beendet, und keine Prüfung von Terminated (Thread-Schleifen prü' +
    'ft thread-loop-without-terminated). Anonyme Methoden im Rumpf zählen nicht. Die Aktion springt zum Schleifenkopf."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "loop-condition-unchanged",' + #10 +
    '      "name": "Schleifenbedingung ändert sich im Rumpf nie",' + #10 +
    '      "description": "Keine Variable der while- bzw. until-Bedingung ändert sich im Rumpf: keine Zuweisung, kein Inc/Dec, kein Argument (möglicherweise var), kein Methoden- oder Mitgliedszugriff auf d' +
    'as Objekt der Bedingung, keine for-Schleife darüber. Typisch ist das vergessene Inc(I) oder Next. Gemeldet wird nur, wenn jede Variable der Bedingung eine lokale Variable oder ein Wertparameter der Ro' +
    'utine ist und mindestens eine direkt (nicht nur als X.Eigenschaft) vorkommt. Still bleiben Bedingungen mit Funktionsaufrufen, Feldern, globalen Variablen, var- und out-Parametern und Terminated, außer' +
    'dem Schleifen mit Ausgang (Break, Exit, raise …), Warteschleifen (Sleep, ProcessMessages …), with, Aufrufen lokaler Routinen und Variablen, die eine anonyme Methode erfasst. Änderungen über X[…] zähle' +
    'n nur, wenn die Bedingung X[…] liest."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unconditional-recursion",' + #10 +
    '      "name": "Rekursion ohne Abbruch",' + #10 +
    '      "description": "Eine Routine ruft sich auf jedem Pfad selbst auf, bevor sie zurückkehren kann: Es gibt keinen Pfad ohne Selbstaufruf und kein Exit oder raise davor. Ergebnis ist ein Stapelüberla' +
    'uf. Pfade ohne Aufruf sind: if ohne else bzw. case ohne else, der Rumpf von while und for, die rechte Seite von and/or, Zweige von if-Ausdrücken und anonyme Methoden. Getter und Setter der eigenen Pro' +
    'perty meldet setter-recursion; überladene Routinen bleiben still (der Aufruf kann eine andere Überladung treffen). Das Randsymbol aus #623 zeigt jede Rekursion."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "pos-arguments-swapped",' + #10 +
    '      "name": "Argumente von Pos vertauscht",' + #10 +
    '      "description": "Pos(Text, '';''): Pos, PosEx, AnsiPos, StartsText, StartsStr, EndsText und EndsStr (auch mit Ansi-Präfix) erwarten zuerst den gesuchten Teil, dann den Text; ContainsText und Contai' +
    'nsStr erwarten zuerst den Text. Gemeldet, wenn an der Stelle des Textes ein kurzes Literal steht (bis maxLiteralLength Zeichen, Vorgabe 3; '''' zählt als ein Zeichen, #9 ebenso) und an der Stelle des Te' +
    'ils sicher ein String: eine Variable oder ein Feld mit in der Datei deklariertem String-Typ, .Text oder .Caption, eine String-Funktion der RTL (Trim, UpperCase, LeftStr, Format …) oder eine Verkettung' +
    ' mit einem String-Teil. Zeichen bleiben still, weil Pos(C, '';,'') bewusst prüft, ob C einer der Trenner ist; ebenso unbekannte Typen, zwei Literale und Methoden anderer Objekte (Liste.Pos). Konfidenz m' +
    'ittel. Schnellkorrektur: Argumente in einer Änderung tauschen; Kommentare dazwischen bleiben.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "maxLiteralLength",' + #10 +
    '          "description": "Längstes Literal an der Stelle des Textes, das noch als vertauscht gilt."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "integer-division-to-float",' + #10 +
    '      "name": "Ganzzahldivision an Gleitkommazahl",' + #10 +
    '      "description": "Schnitt := Summe div Anzahl mit Schnitt: Double: div schneidet die Nachkommastellen ab, bevor zugewiesen wird. Ebenso Prozent := Teil div Gesamt * 100, Result einer Funktion mit ' +
    'Gleitkommaergebnis und var X: Double := A div B. Gesucht wird durch Klammern, Vorzeichen und + - * / hindurch, nicht in Aufrufen (Round(A div B)), Indizes, mod oder Vergleichen. Das Ziel muss eine Var' +
    'iable, ein Feld (auch Self.X) oder Result sein, deren Typ Single, Double, Extended, Real, Currency … in der Datei deklariert ist. TDateTime, TDate und TTime bleiben still (ganze Tage sind dort meist g' +
    'ewollt), ebenso Zuweisungen in with und Trunc(A) div Trunc(B) (auch Round, Floor, Ceil: ausdrücklich gewandelt, also gewollt ganzzahlig). Konfidenz hoch. Schnellkorrektur: div durch / ersetzen (gleich' +
    'er Vorrang)."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "empty-finally",' + #10 +
    '      "name": "Leerer finally-Block",' + #10 +
    '      "description": "Ein finally-Block ohne Anweisung: Meist ist die Freigabe beim Umbau verloren gegangen. Steht direkt vor try X := T….Create, nennt die Meldung X.Free. Ein Block mit erklärendem Ko' +
    'mmentar gilt als bewusst und wird nicht gemeldet (wie bei empty-except); ein Block mit Compiler-Direktive ebenso nicht, weil ein anderer Zweig Code enthalten kann. Konfidenz hoch. Schnellkorrektur: tr' +
    'y, finally und end entfernen und den Rumpf ausrücken (wenn try, finally und end je allein auf ihrer Zeile stehen); als einzige Anweisung eines if-, while-, for-, with- oder case-Zweigs mit mehreren An' +
    'weisungen im Rumpf wird aus try begin."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "form-resource-missing",' + #10 +
    '      "name": "Formular-Unit ohne {$R *.dfm}",' + #10 +
    '      "description": "Neben der Unit liegt eine .dfm bzw. .fmx, die Unit deklariert die Klasse ihres Wurzelobjekts, aber keine {$R …}-Direktive bindet eine Formulardatei ein: Beim Erzeugen des Formula' +
    'rs folgt EResNotFound. Umgekehrt meldet die Regel ein {$R *.dfm} bzw. {$R Name.dfm}, dessen Datei neben der Unit fehlt (der Compiler bricht mit F1026 ab). Eine Direktive in einem beliebigen Zweig der ' +
    'bedingten Übersetzung zählt als eingebunden. Still bleibt die Regel, wenn die Klasse der Formulardatei nicht in der Unit steht und wenn sie keine Dateien neben der Unit sieht. Korrektur: {$R *.dfm} (b' +
    'zw. {$R *.fmx}) nach implementation einfügen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "form-autocreate-and-manual",' + #10 +
    '      "name": "Formular automatisch und zusätzlich von Hand erzeugt",' + #10 +
    '      "description": "Die .dpr erzeugt ein Formular mit Application.CreateForm, der Code weist derselben globalen Variablen zusätzlich TfrmX.Create(…) zu. Es gibt dann zwei Instanzen, die erste bleibt' +
    ' unsichtbar im Speicher. Die automatisch erzeugten Formulare kommen aus der .dpr des Projekts, zu dem die Unit gehört; kann die Regel die .dpr lesen, muss die Klasse zum CreateForm-Aufruf passen. Stil' +
    'l bleibt sie, wenn die Routine die Variable prüft (Assigned, Vergleich mit nil) oder vorher freigibt (Free, FreeAndNil, Release), bei lokalen Namen und gleichnamigen Feldern der eigenen Klasse und bei' +
    ' Units ohne Projekt. Sicherheit hoch. Korrektur: die Zeile mit Application.CreateForm aus der .dpr entfernen (das Formular erzeugt dann nur noch der Code)."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "inherited-form-handler-without-inherited",' + #10 +
    '      "name": "Ereignis-Handler im geerbten Formular ohne inherited",' + #10 +
    '      "description": "Bei Formularvererbung belegt ein Vorfahr-Formular dasselbe Ereignis derselben Komponente mit einem gleichnamigen Handler, der Handler im Nachfahren ruft inherited aber nicht (meh' +
    'r) auf. Die IDE erzeugt inherited; beim Anlegen; wird es gelöscht, fällt die Logik des Vorfahren still weg. Die Formulardatei des Vorfahren kommt aus dem Index (Datei der Klasse) bzw. aus den Units de' +
    'r uses-Liste neben der Unit; die Kette folgt geerbten Formularen bis zum ersten Formular mit object. Handler mit anderem Namen gelten als bewusster Ersatz. Still ohne Formulardatei des Vorfahren. Sich' +
    'erheit hoch. Korrektur: inherited; am Anfang einfügen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "self-free-in-event-handler",' + #10 +
    '      "name": "Formular gibt sich im eigenen Ereignis frei",' + #10 +
    '      "description": "Free, Destroy, DisposeOf oder FreeAndNil auf Self bzw. auf die globale Variable der eigenen Formularklasse als Anweisung in einem Ereignis-Handler des Formulars oder eines seiner' +
    ' Controls. Nach der Rückkehr greift die VCL noch auf das Objekt zu: Zugriffsverletzung. Richtig ist Release oder Action := caFree in OnClose. Ereignis-Handler sind die Methoden aus der Formulardatei u' +
    'nd Methoden mit einem Parameter Sender: TObject; ein Formular ist die Wurzelklasse der Formulardatei mit ClientWidth bzw. ClientHeight oder eine direkt von TForm bzw. TCustomForm abgeleitete Klasse (R' +
    'ahmen und Datenmodule haben kein Release). Anweisungen in anonymen Methoden und with-Blöcken zählen nicht. Still ohne Formulardatei. Sicherheit hoch. Korrektur: Free durch Release ersetzen, in OnClose' +
    ' (var Action: TCloseAction) durch Action := caFree."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "parallel-for-shared-write",' + #10 +
    '      "name": "Gemeinsame Variable in TParallel.For geschrieben",' + #10 +
    '      "description": "Der Rumpf von TParallel.For bzw. eines TTask.Run/Create/Future, der in einer Schleife entsteht, schreibt eine Variable von außerhalb ohne Sperre: Summe := Summe + …, Inc/Dec oder' +
    ' eine andere Zuweisung, oder er verändert eine Sammlung von außerhalb (Add, Delete, Clear, Insert, Remove …). Die Durchläufe laufen gleichzeitig; Additionen gehen verloren oder die Liste wird beschädi' +
    'gt. Von außerhalb heißt: lokale Variable oder Parameter der umgebenden Routine, Feld ihrer Klasse oder globale Variable der Unit; Namen unbekannter Herkunft bleiben still. Rümpfe mit Sperre (TMonitor,' +
    ' Enter, Acquire, Lock, LockList, BeginWrite, TInterlocked), Zugriffe über Index (Werte[I] := …) und verschachtelte anonyme Methoden (Synchronize, Queue) zählen nicht. Typen aus threadSafeTypes gelten ' +
    'als threadsicher. Sicherheit mittel. Korrekturen: TInterlocked.Add/Increment/Decrement bei Integer, Int64 und Cardinal (ergänzt System.SyncObjs), System.TMonitor.Enter/Exit in try … finally um den Sam' +
    'mlungsaufruf.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "threadSafeTypes",' + #10 +
    '          "description": "Typen, die als threadsicher gelten; ihre Sammlungsaufrufe bleiben still."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "thread-unsafe-increment",' + #10 +
    '      "name": "Zähler im Thread ohne TInterlocked",' + #10 +
    '      "description": "Inc, Dec, X := X + 1 oder X := X - 1 ohne Sperre auf einer globalen Variablen in Execute eines TThread-Nachfahren bzw. auf einem Feld oder einer globalen Variablen im Rumpf von T' +
    'Task.Run/Create/Future außerhalb von Schleifen und von TThread.CreateAnonymousThread. Inc ist nicht atomar: zählen mehrere Threads gleichzeitig, gehen Erhöhungen verloren. Thread-Klassen kommen aus de' +
    'r Unit (auch über Zwischenklassen) und aus dem Index. Eigene Felder des Threads in Execute und eingefangene lokale Variablen eines einzelnen Tasks haben nur einen Schreiber und bleiben still, ebenso R' +
    'ümpfe mit Sperre (TMonitor, Enter, Acquire, Lock, LockList, BeginWrite, TInterlocked) und verschachtelte anonyme Methoden (Synchronize, Queue). Tasks in Schleifen und TParallel.For meldet parallel-for' +
    '-shared-write. Sicherheit mittel. Korrektur: TInterlocked.Increment/Decrement/Add bei Integer, Int64 und Cardinal (ergänzt System.SyncObjs)."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "constant-expression-error",' + #10 +
    '      "name": "Fehler in einem konstanten Ausdruck",' + #10 +
    '      "description": "Ein konstanter Ausdruck teilt durch null (wie E2098), läuft über den Bereich von Int64 und UInt64 hinaus (wie E2099), ein Bereich hat die Untergrenze über der Obergrenze (array[5' +
    '..1], wie E2011), eine Konstante verletzt einen ganzzahligen Typ fester Größe oder einen Teilbereichstyp (wie W1012, als Warnung; bei Zuweisungen nur Werte außerhalb von 0..127) oder ein Hex-, Binär- ' +
    'oder Oktalliteral braucht mehr als 64 Bit (wie E2102). Atlas wertet Literale, Konstanten (auch aus anderen Units) und SizeOf/High/Low von Typen fester Größe aus; eine Konstante aus einem {$IF}-Zweig z' +
    'ählt nur, wo die geprüfte Stelle mit ihr zusammen übersetzt wird. Ausdrücke mit unbekannten Teilen bleiben still."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "default-parameter-invalid",' + #10 +
    '      "name": "Unzulässiger Standardwert eines Parameters",' + #10 +
    '      "description": "Standardwerte, die der Compiler ablehnt: mehrere Namen mit einem gemeinsamen Standardwert (A, B: Integer = 0, wie E2237), ein Parameter ohne Standardwert nach einem mit Standardw' +
    'ert (wie E2238), var- und out-Parameter mit Standardwert (wie E2239) Records oder statische Arrays mit Standardwert (wie E2268) sowie Mengen über 4 Byte mit Standardwert (wie E2146, erlaubt sind nur k' +
    'leine Mengen; mittlere Konfidenz). Gilt für Routinen, Methoden und Prozedurtypen. Korrekturen: Parameter einzeln deklarieren; Parameter mit Standardwert ans Ende verschieben, auch im zugehörigen Kopf ' +
    'der Deklaration bzw. Implementierung derselben Datei (Aufrufe ändert sie nicht)."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "signed-unsigned-mix",' + #10 +
    '      "name": "Vorzeichenbehaftet und vorzeichenlos gemischt",' + #10 +
    '      "description": "Vergleich oder Rechnung (+, -, *, div, mod) mit einem vorzeichenbehafteten und einem vorzeichenlosen Operanden, deren Typen sicher bekannt sind (Variablen, Felder, Properties, Fu' +
    'nktionsergebnisse, eigene Aliase). Mit UInt64 wird der ganze Ausdruck vorzeichenlos gerechnet, ein negativer Wert wird zu einer riesigen Zahl (wie W1073, beim Vergleich wie W1023); mit Cardinal/DWORD ' +
    'und einem vorzeichenbehafteten Typ bis 32 Bit werden beide Operanden auf Int64 erweitert (wie W1023/W1024). Still bei Byte und Word, Cardinal mit Int64, Literalen, Konstanten, NativeInt/NativeUInt und' +
    ' unbekannten Typen. Mittlere Konfidenz. Korrektur: den vorzeichenlosen Operanden in Int64 umwandeln."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "narrowing-assignment",' + #10 +
    '      "name": "Zuweisung mit möglichem Datenverlust",' + #10 +
    '      "description": "Eine Zuweisung oder Inline-Variable mit einem Wert, dessen Typ breiter ist als das Ziel, ohne ausdrückliche Umwandlung: Int64 an Integer, NativeInt an Integer (Win64) und über di' +
    'e Option types z. B. Double an Single oder Extended an Double. Wie W1071 (Ganzzahlen), W1072 (Gleitkomma) und W1066 (Extended an Double); der Compiler zeigt W1071 nur, wenn man es einschaltet. Gemelde' +
    't wird nur, wenn beide Typen sicher bekannt sind (Variablen, Felder, Properties, Funktionsergebnisse, eigene Aliase und ganzzahlige Rechnungen daraus); Literale und ausdrückliche Umwandlungen bleiben ' +
    'still. Standardmäßig aus; mittlere Konfidenz. Korrekturen: ausdrücklich umwandeln; den Typ der Deklaration des Ziels vergrößern (einzelne Variable aus derselben Datei).",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "types",' + #10 +
    '          "description": "Gemeldete Paare Quelltyp>Zieltyp, z. B. Double>Single oder Extended>Double."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "typed-constant-modified",' + #10 +
    '      "name": "Typisierte Konstante verändert",' + #10 +
    '      "description": "Einer typisierten Konstante (const Zaehler: Integer = 0) wird etwas zugewiesen (wie W1017, auch einem Element oder Record-Feld davon), oder sie wird als var- oder out-Argument üb' +
    'ergeben, auch an Inc, Dec, Include, Exclude, Delete, SetLength und ähnliche (wie W1016). Gemeint war meist eine Variable; übersetzbar ist das nur mit {$J+}. Gilt vor der Deklaration in derselben Datei' +
    ' {$J-} bzw. {$WRITEABLECONST OFF}, meldet Atlas einen Fehler (wie E2064 bzw. E2197). Dazu 0 als Wert einer Zeigerkonstante oder einer initialisierten Zeigervariable (wie W1013). Korrekturen: eine Kons' +
    'tante auf Unit-Ebene in eine Variable mit Initialwert umwandeln (der const-Abschnitt wird bei Bedarf geteilt; lokale typisierte Konstanten behalten ihren Wert zwischen Aufrufen und bekommen keine Korr' +
    'ektur); nil statt 0 schreiben."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "string-length-limit",' + #10 +
    '      "name": "String-Grenze überschritten",' + #10 +
    '      "description": "Ein String-Literal wird an ein Ziel vom Typ string[N] oder ShortString gekürzt: Zuweisung, typisierte Konstante oder initialisierte Variable, auch über eigene Aliase, string[Kons' +
    'tante] und Felder aus anderen Units (wie W1014). Vor Delphi 12 (delphiVersion unter 23) darf ein Literal in Anführungszeichen höchstens 255 Zeichen haben (wie E2056), und ein resourcestring höchstens ' +
    '4096 Zeichen, mit + verbundene Literale eingerechnet (wie E2381); beides sind Fehler. Gezählt wird wie geschrieben, '''' und #13 zählen als ein Zeichen. Korrekturen: das Ziel als string deklarieren (ein' +
    'zelne Variable oder typisierte Konstante derselben Datei; Record-Felder behalten ihre Größe); das Literal in Stücke zu 255 Zeichen teilen, verbunden mit +."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dynamic-array-misuse",' + #10 +
    '      "name": "New, Dispose oder SetLength falsch für dynamische Arrays",' + #10 +
    '      "description": "New (wie E2255) oder Dispose (wie E2256) auf einem dynamischen Array, SetLength ohne Länge (wie E2246), New mit Länge auf einem Typ, der kein dynamisches Array ist (wie E2307), u' +
    'nd New(TArrayTyp) ohne Länge (wie E2308). Häufig in altem Code, der von Zeigern auf dynamische Arrays umgestellt wurde. Die Regel meldet nur, wenn die Namensauflösung Variable bzw. Typ sicher kennt; A' +
    'liase werden verfolgt (TWerte = array of Double), TBytes und die übrigen dynamischen Arrays der RTL gelten auch ohne Index; offene Array-Parameter und Zeiger bleiben still. Korrekturen: Dispose(A) wir' +
    'd A := nil, New(A) wird SetLength(A, 1)."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "local-routine-as-callback",' + #10 +
    '      "name": "Lokale Routine als Prozedurvariable",' + #10 +
    '      "description": "Eine lokale (verschachtelte) Routine wird einer Variablen oder einem Parameter eines prozeduralen Typs ohne of object zugewiesen (wie E2094), oder eine typisierte Konstante einer' +
    ' Routine nimmt die Adresse einer lokalen Variablen (wie E2278). Gemeint ist meist eine anonyme Methode oder eine Routine der Unit. Die Regel meldet nur, wenn die Namensauflösung den Zieltyp sicher ken' +
    'nt; Methodenzeiger und Methodenreferenzen bleiben still, weil der Compiler sie mit anderen Codes meldet, ebenso @Routine (ein untypisierter Zeiger). Korrektur: die Routine als Routine der Unit vor die' +
    ' umgebende Routine verschieben, wenn sie nichts aus ihr nutzt (keine lokalen Namen weiter außen, keine Klassenmitglieder ohne Präfix)."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "hresult-integer-mix",' + #10 +
    '      "name": "Integer und HRESULT vertauscht",' + #10 +
    '      "description": "Eine Klasse implementiert eine Interface-Methode mit HRESULT-Ergebnis über eine Methode mit Integer- (bzw. LongInt-) Ergebnis oder umgekehrt (wie X1008). Beide sind 32 Bit groß, ' +
    'deshalb fällt es nicht auf; die Bedeutung der Werte (S_FALSE als Erfolg) geht aber verloren; wichtig für COM- und OTA-Code. Zugeordnet wird über Name und Parametertypen samt Zuordnungen wie function I' +
    'Foo.Bar = Baz; Interfaces samt ihren Vorfahren kommen aus der Datei bzw. dem Index. Stehen Varianten in bedingten Zweigen, meldet die Regel nur, wenn jede Variante abweicht. Korrektur: den Ergebnistyp' +
    ' in Deklaration und Implementierung an das Interface angleichen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "invalid-var-argument",' + #10 +
    '      "name": "Ungültiges Argument für einen var- oder out-Parameter",' + #10 +
    '      "description": "Ein var- oder out-Parameter bekommt etwas, das keine Variable ist: ein String-Element für einen Zeichen-Parameter (wie E2354), eine Konstante, einen const-Parameter, eine Propert' +
    'y oder ein Funktionsergebnis (wie E2197), eine Konstante für ein offenes Array (wie E2192), Slice (wie E2454) oder einen Ausdruck (wie E2036). Gemeldet nur für Routinen ohne Überladungen, deren Kopf a' +
    'us der Datei oder dem Index bekannt ist; eingebaute Routinen wie Inc oder Move und untypisierte var-Parameter nehmen mehr an und bleiben still. Typisierte Konstanten zählen als Konstanten, außer mit {' +
    '$J+}. Korrektur: eine lokale Variable vom Typ des Parameters übergeben, bei String-Elementen und Properties mit write mit Rückschreiben."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "condition-not-boolean",' + #10 +
    '      "name": "Bedingung ist kein Boolean",' + #10 +
    '      "description": "Die Bedingung von if, while, until oder eines bedingten Ausdrucks hat sicher einen Typ, der kein Boolean ist: Zahl, Zeiger, Klasse, Interface, String oder Zeichen (wie E2012). An' +
    'ders als C verlangt Delphi einen Boolean. Gemeldet nur bei sicher bekanntem Typ; Boolean-Typen wie LongBool, Aufzählungen, Aliase und unbekannte Typen bleiben still. Korrektur: <> 0 (Alternative > 0),' +
    ' <> nil (Alternative Assigned), <> '''' bzw. <> #0 ergänzen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "for-in-not-enumerable",' + #10 +
    '      "name": "for-in über einen Typ ohne Enumerator",' + #10 +
    '      "description": "Eine for-in-Schleife läuft über einen Typ, der sich nicht aufzählen lässt: Zahl, Zeiger, Zeichen oder Boolean, oder eine Klasse, ein Record bzw. Interface ohne öffentliches GetEn' +
    'umerator, auch nicht geerbt oder aus einem Helper (wie E2430); oder der Enumerator aus GetEnumerator hat kein öffentliches MoveNext bzw. Current (wie E2431). Strings, Arrays und Mengen gehen. Gemeldet' +
    ' nur, wenn der Typ und alle Vorfahren bekannt sind; generische und unbekannte Typen bleiben still. Keine Korrektur; hat der Typ Count, nennt die Meldung eine Schleife mit Index."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "inherited-abstract-call",' + #10 +
    '      "name": "inherited ruft eine abstrakte Methode auf",' + #10 +
    '      "description": "inherited mit ausdrücklichem Methodennamen, etwa inherited Zeichnen(C), obwohl die Methode im Vorfahren abstract ist (wie E2373). Ein bloßes inherited; übergeht der Compiler bei ' +
    'abstrakten Methoden still; das meldet die Regel nicht. Die Methode löst die Namensauflösung samt Überladungen auf; gemeldet wird nur, wenn jede passende Überladung abstrakt ist. Korrektur: den Aufruf ' +
    'entfernen, wenn er als eigene Anweisung in einem begin…end steht."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "generic-constraint-violated",' + #10 +
    '      "name": "Typargument verletzt eine Einschränkung",' + #10 +
    '      "description": "Ein Typargument erfüllt die Einschränkung seines Typparameters nicht: class (wie E2511), record (wie E2512), constructor (wie E2513), ein Interface (wie E2514) oder eine Basiskla' +
    'sse (wie E2515). In Methoden eines generischen Typs dieser Datei meldet die Regel außerdem T.Create ohne constructor-Einschränkung (wie E2568) und Methodenaufrufe auf Werten eines Typparameters ganz o' +
    'hne Einschränkung (wie E2571). Den generischen Typ löst die Namensauflösung samt Zahl der Typparameter auf, seine Einschränkungen stammen aus seiner Deklaration in der Datei oder im Symbolindex. Argum' +
    'ente, die selbst Typparameter sind, Aliase und Typen mit unvollständiger Vorfahrenkette meldet die Regel nicht. Korrektur für einen Typparameter dieser Datei, der allein in seiner Gruppe steht: die Ei' +
    'nschränkung ergänzen (T: class, constructor bzw. T: class)."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unresolved-type",' + #10 +
    '      "name": "Typ in einer Deklaration nicht gefunden",' + #10 +
    '      "description": "Ein Typname in einer Deklaration (Feld, Parameter, Ergebnis, Vorfahr, Interface-Liste, Variable, Typargument) ist nicht deklariert (wie E2003, beim Ziel eines Zeigertyps wie E256' +
    '4) oder kein Typ (wie E2005). Ergänzt unresolved-identifier, das nur Anweisungen prüft. Dieselben Vorbedingungen wie bei unresolved-attribute: System im Symbolindex, alle Units aus uses bekannt, nicht' +
    ' in {$IF…}-Blöcken. Typparameter, Namen, die die Datei irgendwo als Typ deklariert (auch verschachtelt), und Namen, die der Index als verschachtelten Typ kennt (geerbte innere Typen), meldet die Regel' +
    ' nicht. Korrektur: die Unit, die den Typ (mit gleich vielen Typparametern) deklariert, in uses aufnehmen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "class-reference-nonvirtual-constructor",' + #10 +
    '      "name": "Konstruktor über Klassenreferenz nicht virtuell",' + #10 +
    '      "description": "Create über eine Klassenreferenz (class of TBasis), deren Konstruktor nicht virtual ist. Unter Win32 und Win64 übersetzt das ohne Meldung, erzeugt aber immer über den Konstruktor' +
    ' von TBasis: Felder, die Nachfahren in ihren eigenen Konstruktoren setzen, bleiben leer (wie E2391). Der Empfänger kann eine Variable, ein Feld, ein Parameter oder ein Funktionsergebnis vom Typ einer ' +
    'Klassenreferenz sein; den Konstruktor löst die Namensauflösung in der nächsten Klasse auf, die ihn deklariert, Überladungen nach Zahl der Argumente. Still, wenn eine passende Überladung virtual, dynam' +
    'ic, override oder abstract ist, wenn eine Deklaration in einem anderen Zweig der bedingten Übersetzung steht und wenn ein Typ nicht auflösbar ist. Korrektur, wenn der Konstruktor in dieser Datei steht' +
    ': virtual an ihn und override an die gleichlautenden Konstruktoren der Nachfahren in dieser Datei."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "jump-outside-allowed-scope",' + #10 +
    '      "name": "Break, Continue oder Exit an unzulässiger Stelle",' + #10 +
    '      "description": "Break oder Continue außerhalb einer Schleife (wie E2097) bzw. Break, Continue oder Exit, die einen finally-Block verlassen (wie E2126). Delphi meldet beides erst beim Übersetzen;' +
    ' häufig nach dem Herausziehen eines Schleifenrumpfs in eine eigene Methode. Eine Schleife ganz im finally-Block darf Break und Continue verwenden. Routinen und anonyme Methoden beginnen neu: Ein Break' +
    ' in einer anonymen Methode gehört nicht zur Schleife um sie herum. Gemeldet werden nur einfache Aufrufe (nicht TMonitor.Exit(FLock)) und nicht, wenn die Datei eine Routine oder Variable dieses Namens ' +
    'deklariert. Korrektur außerhalb eines finally-Blocks: Break durch Exit ersetzen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "reraise-outside-handler",' + #10 +
    '      "name": "raise ohne Argument außerhalb eines Handlers",' + #10 +
    '      "description": "raise; ohne Exception-Objekt ist nur in einem except-Block erlaubt (wie E2145); Delphi meldet es erst beim Übersetzen. Es passiert in einer lokalen Prozedur, die aus dem Handler ' +
    'gerufen wird, in einem finally-Block oder nach dem Verschieben von Code. Routinen und anonyme Methoden beginnen neu. Still bleibt die Regel in anonymen Methoden innerhalb eines except-Blocks und in Ro' +
    'utinen, in denen der Parser einen Fehler meldet. Keine Korrektur: eine neue Exception auslösen (raise EImport.Create(…)) oder den Code in den Handler verschieben. raise E; im Handler meldet reraise-ex' +
    'ception-object."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "label-misuse",' + #10 +
    '      "name": "Sprungmarke falsch verwendet",' + #10 +
    '      "description": "Eine Marke ist doppelt gesetzt (wie E2073), deklariert und angesprungen, aber nie gesetzt (E2074), gesetzt oder angesprungen, ohne in der aktuellen Routine deklariert zu sein (E2' +
    '093; ein goto auf eine nirgends deklarierte und nie gesetzte Marke meldet die Regel syntax als E2031), oder goto springt in einen try-Block hinein oder aus ihm heraus, auch zwischen try-Teil und excep' +
    't bzw. finally (E2127). Delphi meldet das erst beim Übersetzen. Marken gehören zu einer Routine bzw. zum Programmblock; eine lokale Prozedur kann keine Marke der umgebenden Routine anspringen. Doppelt' +
    'e Marken in bedingten Zweigen, die sich ausschließen, bleiben still, ebenso Routinen mit asm-Block, weil Marken im asm nicht im Syntaxbaum stehen. Keine Korrektur."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "for-variable-misuse",' + #10 +
    '      "name": "Schleifenvariable verändert oder nicht lokal",' + #10 +
    '      "description": "Der Variablen einer for-Schleife wird im Rumpf zugewiesen oder sie wird mit Inc/Dec verändert (wie E2081), sie wird als var- bzw. out-Parameter an eine Routine dieser Datei überg' +
    'eben (wie W1015) oder sie ist keine einfache lokale Variable: Feld der eigenen Klasse, globale Variable der Unit oder lokale Variable der umgebenden Routine (wie E1019). Delphi meldet das erst beim Üb' +
    'ersetzen. Parameter, unbekannte Namen und Schleifen in with-Anweisungen bleiben still, ebenso anonyme Methoden im Rumpf und Routinen mit Parserfehlern. Korrekturen: auf eine while-Schleife umstellen (' +
    'nicht bei Continue im Rumpf) bzw. for var verwenden, wenn die Routine den Namen sonst nicht benutzt."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "for-variable-after-loop",' + #10 +
    '      "name": "Schleifenvariable nach der Schleife gelesen",' + #10 +
    '      "description": "Nach einer for-Schleife, die normal endet (ohne Break), ist die Schleifenvariable undefiniert. Die Regel meldet das erste Lesen der Variable auf einem Weg vom normalen Schleifene' +
    'nde, bevor ihr erneut zugewiesen wird (wie W1037). Geprüft werden nur einfache lokale Variablen der Routine; for var, Felder, globale Variablen, Lesen nur im Rumpf, Argumente von Routinen, die out-Par' +
    'ameter sein könnten, und Routinen mit unvollständigem Ablaufgraphen bleiben still. Korrektur: auf eine while-Schleife umstellen, deren Zähler danach einen festen Wert hat."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "argument-count-mismatch",' + #10 +
    '      "name": "Falsche Anzahl Argumente",' + #10 +
    '      "description": "Ein Aufruf übergibt mehr Argumente, als die Routine Parameter hat (wie E2034), oder weniger als Parameter ohne Standardwert (wie E2035), auch als Anweisung ohne Klammern. Geprüft' +
    ' wird nur, wenn der Name sicher genau eine Routine meint: Überladungen, varargs, Typumwandlungen, Variablen prozeduralen Typs, Bezeichner von System ohne Quelltext und Deklarationen in bedingten Zweig' +
    'en bleiben beim Compiler (E2250). Eine Funktion mit zu vielen Argumenten meldet die Regel nur bei bekanntem, nicht prozeduralem Ergebnistyp. Korrektur: Signaturhilfe öffnen setzt die Schreibmarke in d' +
    'ie Klammern und öffnet den Parameter-Hint (ergänzt () bei Bedarf)."' + #10 +
    '    }' + #10 +
    '  ]' + #10 +
    '}' + #10 +
    '' + #10);
  Result := '';
end;

end.
