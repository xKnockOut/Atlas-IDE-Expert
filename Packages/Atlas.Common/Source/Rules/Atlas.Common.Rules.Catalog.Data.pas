unit Atlas.Common.Rules.Catalog.Data;

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
    '      "group": "find-bugs",' + #10 +
    '      "description": "The parser could not read the source code.",' + #10 +
    '      "bad": "procedure Foo;\nbegin\n  if X then\nend;",' + #10 +
    '      "good": "procedure Foo;\nbegin\n  if X then\n    Bar;\nend;"' + #10 +
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
    '      "description": "An lsp-ignore comment names a rule id that does not exist, so it suppresses nothing. The message suggests the most similar known id (typo); such a comment is not also reported as' + ' unused-suppression.",' + #10 +
    '      "bad": "// lsp-ignore: empty-exept\ntry X; except end;",' + #10 +
    '      "good": "// lsp-ignore: empty-except\ntry X; except end;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "bidi-control",' + #10 +
    '      "name": "Bidirectional control character",' + #10 +
    '      "category": "vulnerability",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "security",' + #10 +
    '      "description": "Bidirectional control characters can make code display differently from how it compiles (Trojan Source); also in form files. Direction marks in RTL text only with low confidence.' + '",' + #10 +
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
    '      "description": "A uses entry violates the import matrix of the role concept (output artefact, feature, role: Contract, Internals, Providers, Adapters, Composition, Hosting). Off by default; swit' + 'ch it on in atlas.json with the option \"prefixes\". Approved exceptions go to \"allow\" as \"Source -> Target\" globs.",' + #10 +
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
    '      "description": "A contract unit declares a class in its interface section. Contracts hold only records, interfaces, enumerations and exceptions. Off by default; switch it on in atlas.json with t' + 'he option \"prefixes\". Approved exceptions go to \"allow\" as \"Unit.Type\" globs.",' + #10 +
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
    '      "description": "TThread.Execute, TThread.CreateAnonymousThread or TTask accesses the VCL (Application, Screen, ShowMessage, MessageDlg …) outside Synchronize or Queue. The VCL is not thread-safe' + '.",' + #10 +
    '      "bad": "procedure TWorker.Execute;\nbegin\n  Application.Title := ''Done'';\nend;",' + #10 +
    '      "good": "procedure TWorker.Execute;\nbegin\n  TThread.Queue(nil, procedure begin Application.Title := ''Done'' end);\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "lock-without-finally",' + #10 +
    '      "name": "Lock without try/finally",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "threads",' + #10 +
    '      "description": "A lock (TCriticalSection.Enter/Acquire, TMonitor.Enter, BeginRead/BeginWrite, TSpinLock.Enter, TMutex.Acquire, EnterCriticalSection or a pair from the lockPairs option) is not di' + 'rectly followed by try/finally releasing it. An exception leaves the lock held.",' + #10 +
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
    '      "description": "A statement after Exit, raise, Abort, Halt, Break, Continue or goto is never executed. Usually a leftover or a misplaced jump. Only the first statement of an unreachable section ' + 'is reported.",' + #10 +
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
    '      "description": "A value assigned to a local variable is overwritten or the routine ends before it is read. Like compiler hint H2077.",' + #10 +
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
    '      "id": "declared-not-implemented",' + #10 +
    '      "name": "Declared but not implemented",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "A method is declared in a class, record or object but has no body in the implementation section. The compiler reports this only when compiling (E2065). A body of the same name wi' + 'th a different header is reported by signature-mismatch instead.",' + #10 +
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
    '      "description": "A setter assigns to its own property (Name := Value in SetName) or a getter reads it (Result := Name in GetName). The accessor calls itself endlessly and ends in a stack overflow' + ' at run time; the compiler stays silent. Quick fix: use the field instead (the field from the property declaration, otherwise F plus the name, if the class has it). Formerly recursive-property-accesso' + 'r; settings and suppressions with the old ID still apply.",' + #10 +
    '      "bad": "procedure TKunde.SetName(const Value: string);\nbegin\n  if Name <> Value then\n    Name := Value;\nend;",' + #10 +
    '      "good": "procedure TKunde.SetName(const Value: string);\nbegin\n  if FName <> Value then\n    FName := Value;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-create-without-override",' + #10 +
    '      "name": "Component constructor without override",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "components",' + #10 +
    '      "description": "A TComponent descendant declares constructor Create(AOwner: TComponent) without override. Components created from a form file are built through the virtual constructor and skip t' + 'his one.",' + #10 +
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
    '      "description": "An anonymous method passed to a deferred API (TThread.Queue, TTask.Run, ...) captures a variable that changes before it runs, such as a for-in loop variable. Delphi captures the ' + 'variable, not its value.",' + #10 +
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
    '      "description": "An overridden Loaded, CreateParams, CreateWnd, Notification, SetParent, Destroy or Paint of a component does not call inherited, so the VCL skips its own work there. For Paint th' + 'e confidence is low, because TCustomControl.Paint only draws the design-time frame.",' + #10 +
    '      "bad": "procedure TMyControl.Loaded;\nbegin\n  UpdateLayout;\nend;",' + #10 +
    '      "good": "procedure TMyControl.Loaded;\nbegin\n  inherited;\n  UpdateLayout;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-default-mismatch",' + #10 +
    '      "name": "default does not match constructor",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "components",' + #10 +
    '      "description": "A property declares a default value, but the constructor sets its field to a different literal. The streaming system does not store values equal to default, so the property is lo' + 'aded wrongly from the DFM.",' + #10 +
    '      "bad": "property Size: Integer read FSize write FSize default 5;\n...\nFSize := 10;",' + #10 +
    '      "good": "property Size: Integer read FSize write FSize default 10;\n...\nFSize := 10;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-missing-free-notification",' + #10 +
    '      "name": "Component reference without FreeNotification",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "components",' + #10 +
    '      "description": "A component property refers to another component, but its setter does not call FreeNotification. When the other component is freed, a dangling pointer remains. Subcomponents crea' + 'ted in the constructor are ignored.",' + #10 +
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
    '      "description": "Paint or Resize uses fixed pixel values that are too small above 96 dpi. Values passed through ScaleValue or MulDiv, 0, 1 and -1, and factors of multiplications and divisions are' + ' not reported.",' + #10 +
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
    '      "description": "An object of the form file has no field in the form class. Inherited objects, objects inside inline frames, unnamed components and collection items are skipped. The fix adds the ' + 'field.",' + #10 +
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
    '      "description": "ShellExecute, ShellExecuteEx, CreateProcess or WinExec receives an argument built with +, Format or Concat from non-constant values. Input could inject further commands. Without ' + 'data flow analysis only this simple pattern is found (medium confidence).",' + #10 +
    '      "bad": "ShellExecute(0, ''open'', PChar(''cmd /c '' + Edit1.Text), nil, nil, SW_SHOW);",' + #10 +
    '      "good": "ShellExecute(0, ''open'', ''tool.exe'', PChar(QuotedArgument), nil, SW_SHOW);  // validated"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "security-path-traversal",' + #10 +
    '      "name": "Path traversal",' + #10 +
    '      "category": "vulnerability",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "security",' + #10 +
    '      "description": "A file access (TFileStream.Create, LoadFromFile, AssignFile, TFile.*) uses a path from input data (Text, ParamStr, Request) without TPath.GetFullPath check. Experimental until da' + 'ta flow analysis is available.",' + #10 +
    '      "bad": "List.LoadFromFile(''C:\\Data\\'' + Edit1.Text);",' + #10 +
    '      "good": "Path := TPath.GetFullPath(TPath.Combine(Root, Edit1.Text));  // then check it starts with Root"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "security-weak-crypto",' + #10 +
    '      "name": "Weak cryptography",' + #10 +
    '      "category": "security-hotspot",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "security",' + #10 +
    '      "description": "MD5, SHA-1, DES or RC4 is used. For checksums this is fine; for passwords and signatures it is not. Low confidence, medium when the statement mentions a password, secret or signa' + 'ture.",' + #10 +
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
    '      "description": "A component property in the form file does not meet a rule from dfmPropertyRules in atlas.json (class, property, condition, value). A property that is not stored counts with its ' + 'default value; objects of the ancestor form are only reported where this form sets the value itself. The quick fix sets the value in the form file (fix: auto also with source.fixAll); the command \"Ap' + 'ply property rules\" corrects one form, the project or the group with a preview.",' + #10 +
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
    '      "description": "SQL.Text, SQL.Add, CommandText, ExecSQL or Open receives text built with + or Format from non-constant values. User input could inject SQL. Use parameters (:Name, ParamByName). C' + 'onstants, resourcestrings, IntToStr and QuotedStr are not reported; user input (TEdit.Text, TMemo.Lines) raises the confidence to high.",' + #10 +
    '      "bad": "Q.SQL.Text := ''select * from K where N = '''''' + Edit1.Text + '''''''';",' + #10 +
    '      "good": "Q.SQL.Text := ''select * from K where N = :N'';\nQ.ParamByName(''N'').AsString := Edit1.Text;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "slash-command",' + #10 +
    '      "name": "Quick command not executed",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "internal",' + #10 +
    '      "description": "A line starting with /name was not executed and stays in the code: the command is unknown, switched off (slashCommands.disabled) or does not fit at this place. The message names ' + 'the reason. \"/ignore rule\" is also reported when that rule finds nothing in the line below.",' + #10 +
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
    '      "description": "An interface declares no GUID. Supports, as and QueryInterface need one. The confidence is high when the interface is used with them in the same file, otherwise low. The quick fi' + 'x inserts a new GUID.",' + #10 +
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
    '      "description": "A variable, field or property is assigned to itself. Usually a different value was meant, for example a parameter or another field. If a parameter or local variable hides a field' + ' of the same name (Name := Name), Atlas offers Self.Name := Name as the fix.",' + #10 +
    '      "bad": "FName := FName;",' + #10 +
    '      "good": "FName := AName;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "for-high-to-low",' + #10 +
    '      "name": "for loop counts down with to",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "The loop starts at the upper bound (High, Count - 1) and ends at the lower one, but uses to. It never runs; downto was meant.",' + #10 +
    '      "bad": "for I := High(A) to Low(A) do\n  Save(A[I]);",' + #10 +
    '      "good": "for I := High(A) downto Low(A) do\n  Save(A[I]);"' + #10 +
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
    '      "description": "The argument of Assert changes data (Inc, Dec, a Try… function with an out parameter or a method from the option mutatingMethods). With {$C-} the compiler removes the whole call ' + 'including the side effect.",' + #10 +
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
    '      "description": "IfThen is a function: both branches are evaluated before the call. A nil access or a function call in the branch that is not chosen still happens. High confidence when a branch d' + 'ereferences a name checked in the condition, medium for a function call.",' + #10 +
    '      "bad": "S := IfThen(Assigned(X), X.Name, '''');",' + #10 +
    '      "good": "if Assigned(X) then S := X.Name else S := '''';"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "random-without-randomize",' + #10 +
    '      "name": "Random without Randomize",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "robustness",' + #10 +
    '      "description": "Random is used, but the unit never calls Randomize, so every start yields the same sequence. Randomize often sits in the .dpr, so the rule is off by default and has low confidenc' + 'e.",' + #10 +
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
    '      "description": "Format with %f, %n, %m, %g or %e and functions like FloatToStr, StrToFloat or DateToStr without a TFormatSettings parameter use the user''s locale (decimal separator, date format)' + '. For files, protocols and logs pass fixed TFormatSettings. Format(''%d'', …) is not reported.",' + #10 +
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
    '      "description": "A string variable is extended step by step inside a loop. Delphi usually grows strings in place, so this is reported only with low confidence and is off by default; for many iter' + 'ations TStringBuilder is faster.",' + #10 +
    '      "bad": "for I := 1 to 10000 do\n  S := S + IntToStr(I);",' + #10 +
    '      "good": "Builder := TStringBuilder.Create;\ntry\n  for I := 1 to 10000 do\n    Builder.Append(I);\n  S := Builder.ToString;\nfinally\n  Builder.Free;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "loop-invariant-call",' + #10 +
    '      "name": "Expensive call in a loop condition",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "performance",' + #10 +
    '      "description": "The condition of while and until is evaluated on every iteration. Calls like Trim, Format or FileExists and properties like Lines.Text there are recomputed each time; compute the' + 'm once before the loop. Bounds of for loops are evaluated only once and are not reported. Off by default.",' + #10 +
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
    '      "good": "if Done then\n  Exit;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "with-statement",' + #10 +
    '      "name": "with statement",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "Inside a with block it is unclear which object an identifier belongs to, and a new member of the with object silently changes the meaning. Write the expression out or use a local' + ' variable.",' + #10 +
    '      "bad": "with Customer do\n  Name := Edit.Text;",' + #10 +
    '      "good": "Customer.Name := Edit.Text;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-method-length",' + #10 +
    '      "name": "Method too long",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "The method has more code lines than the limit (default 60). Blank lines, comments, compiler directives and local routines do not count. Split the method into smaller ones. Set th' + 'e limit with the option max, e.g. \"rules\": {\"metric-method-length\": {\"max\": 80}}.",' + #10 +
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
    '      "description": "The method nests if, case, loops and try deeper than the limit (default 4). else if stays on the level of its if. Leave early with Exit or Continue, or move inner parts into thei' + 'r own methods. Set the limit with the option max.",' + #10 +
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
    '      "description": "The cyclomatic complexity of the method is above the limit (default 15). It starts at 1 and adds 1 for every if, while, repeat and for, every case branch without else, every and/' + 'or in a condition and every except on; an except without on counts once. Many paths need many tests. Set the limit with the option max.",' + #10 +
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
    '      "description": "The cognitive complexity of the method is above the limit (default 15). Following SonarSource, if, case, loops and except handlers count 1 plus their nesting level; else, else if' + ', goto and every sequence of equal logical operators count 1. Nested code is harder to read than code in sequence. Set the limit with the option max.",' + #10 +
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
    '      "id": "todo-comment",' + #10 +
    '      "name": "Open TODO comment",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "A comment starts with a marker for open work: // TODO, // FIXME or the IDE to-do format { TODO 1 -oOwner -cCategory : Text }. The hint shows marker, priority, category, owner and' + ' text, so open work appears in the problem list. Off by default; switch it on in atlas.json, e.g. \"rules\": {\"todo-comment\": {\"severity\": \"hint\"}}. Completed entries ({ DONE … }) are never repo' + 'rted. The option keywords sets the markers (default [\"TODO\", \"FIXME\"]); it also applies to get_todos and --todos.",' + #10 +
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
    '      "description": "Every class passed to RegisterComponents needs a bitmap named after the class in upper case in a .dcr or .res included with {$R}. From Delphi 11 the sizes 16, 24 and 32 px (NAME1' + '6, NAME24, NAME32) are expected as well. Silent when the unit includes no readable resource file.",' + #10 +
    '      "bad": "{$R *.dcr} // without TMYBUTTON\nRegisterComponents(''Samples'', [TMyButton]);",' + #10 +
    '      "good": "{$R *.dcr} // with TMYBUTTON16, TMYBUTTON24, TMYBUTTON32\nRegisterComponents(''Samples'', [TMyButton]);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unresolved-identifier",' + #10 +
    '      "name": "Unresolved identifier",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "An identifier in a statement is declared neither in the unit nor in the units it uses (like compiler error E2003). Checked while typing, without the compiler; with blocks, asm an' + 'd anonymous methods are skipped.",' + #10 +
    '      "bad": "procedure Foo;\nbegin\n  Lst.Add(''x'');\nend;",' + #10 +
    '      "good": "procedure Foo;\nvar\n  Lst: TStringList;\nbegin\n  Lst := TStringList.Create;\n  Lst.Add(''x'');\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "deprecated-symbol",' + #10 +
    '      "name": "Deprecated symbol",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "A routine, type, constant or member marked deprecated, platform or experimental is used (like compiler warnings W1000, W1002 and W1003). The editor strikes the name through; the ' + 'message carries the reason from deprecated ''reason''. The declaration and the head of its implementation are not reported.",' + #10 +
    '      "bad": "procedure Old; deprecated ''Use New'';\n...\nOld;",' + #10 +
    '      "good": "procedure New;\n...\nNew;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "implicit-package-import",' + #10 +
    '      "name": "Implicit package import",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "packages",' + #10 +
    '      "description": "In a package (.dpk) a unit from contains uses a unit that is neither in contains nor provided by a package in requires. The compiler pulls it in implicitly (W1033), which later c' + 'auses duplicate units when another package also contains it. The quick fix adds the unit to contains.",' + #10 +
    '      "bad": "package Werkzeuge;\nrequires rtl;\ncontains\n  uHaupt in ''uHaupt.pas'';  // uHaupt uses uMathe\nend.",' + #10 +
    '      "good": "package Werkzeuge;\nrequires rtl;\ncontains\n  uHaupt in ''uHaupt.pas'',\n  uMathe in ''uMathe.pas'';\nend."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "type-used-before-declaration",' + #10 +
    '      "name": "Type used before its declaration",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "A class, interface, record or other type is used in a type declaration (field, parameter, result, property, generic argument, class of) but declared only further down in the same' + ' scope (like compiler error E2003). Ancestors, aliases and pointer types are not reported. Quick fixes: add a forward declaration at the start of the type block, merge type blocks (const, var and labe' + 'l sections in between move in front of the first block) or move a record up in front of its first user; without a safe fix the message gives the reason.",' + #10 +
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
    '      "description": "An object field that the constructor (or a private method it calls) creates with TClass.Create is never freed in the class (no Free, FreeAndNil, Destroy or DisposeOf): a memory l' + 'eak. Components created with an owner other than nil, interface and record fields and the classes from the option ignoreTypes are exempt; TObjectList and TObjectDictionary fields are normal fields. Me' + 'dium confidence. Quick fixes: free the field in the destructor, or free all owned objects of the class; a missing destructor is created with override and inherited. The objects are freed before inheri' + 'ted in reverse creation order, as Free or FreeAndNil (refactoring.freeFieldsStyle). Up to #918 the rule was called owned-field-not-freed; settings and suppressions with that id still apply.",' + #10 +
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
    '      "description": "An object field created in the constructor and not freed is also returned (Result := FField, Exit(FField)), handed to a property of another object or to its Add…, Insert…, Regist' + 'er…, Attach…, Push or Enqueue, assigned without Create or writable through a property (write FField). Whether the class still owns the object is up to the developer, so there is no quick fix.",' + #10 +
    '      "bad": "function TCache.Take: TList;\nbegin\n  Result := FList;  // created in Create, never freed\nend;",' + #10 +
    '      "good": "function TCache.Take: TList;\nbegin\n  Result := FList;\n  FList := nil;  // ownership passes to the caller\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "operator-precedence",' + #10 +
    '      "name": "Precedence of not overlooked",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "In Pascal not binds more tightly than in and comparisons: not X in Set means (not X) in Set, not A = B means (not A) = B, and on integers not works bitwise. The rule reports thes' + 'e forms when the declared type of the operand shows that this cannot be meant (not Boolean). Quick fix: add parentheses, not (X in Set).",' + #10 +
    '      "bad": "if not Zustand in [zsOffen, zsGesperrt] then\n  Bearbeiten;",' + #10 +
    '      "good": "if not (Zustand in [zsOffen, zsGesperrt]) then\n  Bearbeiten;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "empty-statement",' + #10 +
    '      "name": "Empty statement after then, do or else",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "A semicolon right after then, do or else ends the statement: the following line always runs, or the loop spins empty. An empty begin … end after then, do or else is reported too,' + ' unless it contains an explanatory comment (option allowCommented). A semicolon right before end, until, except or finally changes nothing and is not reported. Quick fix: remove the semicolon.",' + #10 +
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
    '      "description": "for I := 0 to List.Count or to Length(A) over zero-based lists and arrays reads one element past the end when the body indexes List[I] or A[I]. With one-based strings it is the o' + 'ther way round: S[0] and for I := 0 to Length(S) read before the first character; {$ZEROBASEDSTRINGS ON} is taken into account. Quick fix: add - 1 or use High(A); for strings Low(S) and High(S). The o' + 'ption countNames lists the names that return a count.",' + #10 +
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
    '      "description": "Delete, Remove, Add or another method from the option mutatingMethods is called on the list that the loop is walking forwards by index or with for … in. Forwards, Delete skips th' + 'e next element and runs past the end, Add is not visited and Insert visits the same element twice; with for … in the RTL raises an exception. A Break or Exit directly after the call ends the loop and ' + 'stays silent, downto loops too. Quick fix for index loops: rewrite as downto; for for … in collect the elements and change the list after the loop.",' + #10 +
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
    '      "description": "After X.Free, X.Destroy, X.DisposeOf, FreeAndNil(X) or Dispose(X), X is used again without a new assignment: a method, field, index or X^, with X, and after Free also Assigned(X)' + ' (always True) or a second Free. The rule follows the data flow of the routine; an assignment to X, passing X to a routine, @X and after FreeAndNil a check for nil end the path, ways only through a po' + 'ssible exception are left out. Confidence high when release and access stand one after the other in the same block, otherwise medium. No automatic fix; the action jumps to the release.",' + #10 +
    '      "bad": "Bericht.Free;\nProtokoll.Add(''Seiten: '' + IntToStr(Bericht.Seiten));",' + #10 +
    '      "good": "Protokoll.Add(''Seiten: '' + IntToStr(Bericht.Seiten));\nBericht.Free;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "deref-before-nil-check",' + #10 +
    '      "name": "Used first, checked for nil later",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "X is dereferenced (X.Field, X.Method, X^) and only afterwards checked with Assigned(X), X <> nil or X = nil. Either the check is superfluous or the access before it can crash. Re' + 'ported only when every path to the check passes the access and X was not checked before; a new assignment, passing X to a routine and, for fields and global variables, any call in between end the path' + '. Medium confidence. When the check is an if without else directly after the access in the same block, the quick fix moves the access into it.",' + #10 +
    '      "bad": "Titel := Kunde.Name;\nif Assigned(Kunde) then\n  Anzeigen(Kunde);",' + #10 +
    '      "good": "if Assigned(Kunde) then\nbegin\n  Titel := Kunde.Name;\n  Anzeigen(Kunde);\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "field-free-without-nil",' + #10 +
    '      "name": "Field freed, reference stays",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "FField.Free in a method outside the destructor, and a path to the end of the method does not set the field again. A later access or a second Free hits freed memory. Setting it ag' + 'ain means an assignment or the call of a method of the same class that assigns the field. Fields are those of the class declaration in the unit. Destructors, methods with [TearDown] or [TearDownFixtur' + 'e], methods only called from these and the methods from the option ignoreMethods are exempt. Medium confidence. Quick fix: FreeAndNil(FField).",' + #10 +
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
    '      "description": "A constructor, or an override of Destroy, AfterConstruction or BeforeDestruction, does not call inherited, in any class whose ancestor is not TObject. Constructors are reported o' + 'nly if an ancestor declares a constructor of its own (file, index or a known RTL/VCL class) and the constructor does not call another constructor of the same class. For components, Destroy is reported' + ' only by component-missing-inherited. High confidence. Quick fix: insert inherited; at the end of Destroy and BeforeDestruction, at the start of constructors and AfterConstruction; a constructor with ' + 'parameters without override gets inherited Create;.",' + #10 +
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
    '      "id": "destroy-called-directly",' + #10 +
    '      "name": "Destroy called instead of Free",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "Obj.Destroy is called directly as a statement. If Obj is nil, the call crashes; Free checks for nil first and is the usual way to release an object. inherited Destroy and calls o' + 'f a destructor with arguments are exempt. High confidence. Quick fix: Destroy becomes Free.",' + #10 +
    '      "bad": "Verbindung.Destroy;",' + #10 +
    '      "good": "Verbindung.Free;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "managed-type-raw-memory",' + #10 +
    '      "name": "FillChar, Move or GetMem on managed types",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "FillChar, ZeroMemory, FillMemory, Move, CopyMemory, GetMem or FreeMem on a variable whose type contains strings, interfaces, dynamic arrays or variants (records, static arrays an' + 'd aliases are resolved in the file and in the index). Reference counts are overwritten or skipped: leaks, double frees, access violations. Only plain variables (X, @X, P^) are checked; array elements ' + 'such as S[1] and types that cannot be resolved stay silent. High confidence. Quick fixes: FillChar(X, SizeOf(X), 0) becomes X := Default(T), Move(A, B, SizeOf(T)) becomes B := A, GetMem(P, SizeOf(T)) ' + 'becomes New(P) and FreeMem(P) becomes Dispose(P); otherwise Initialize and Finalize help.",' + #10 +
    '      "bad": "FillChar(Adresse, SizeOf(Adresse), 0);",' + #10 +
    '      "good": "Adresse := Default(TAdresse);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "threadvar-managed",' + #10 +
    '      "name": "threadvar with a managed type",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "threads",' + #10 +
    '      "description": "Delphi does not finalize threadvar variables. A string, interface, dynamic array or variant in a threadvar (also inside a record or static array) leaks in every thread that ends.' + ' Types are resolved in the file and in the index. High confidence. No quick fix: release the value at the end of the thread (for example set it to '''' or nil in TThread.Execute), or store a pointer or ' + 'a fixed-size buffer instead.",' + #10 +
    '      "bad": "threadvar\n  LetzteMeldung: string;",' + #10 +
    '      "good": "threadvar\n  LetzteMeldung: PChar;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "pchar-of-temporary",' + #10 +
    '      "name": "PChar of a temporary string",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "PChar (PWideChar, PAnsiChar) of a temporary string, such as a concatenation with a string (S + ''.bak'') or a function result (IntToStr(N)), is stored in a variable, a field or Res' + 'ult, or passed to PostMessage, PostThreadMessage, SendNotifyMessage or SendMessageCallback (also behind LPARAM(…)). The temporary string is released after the statement, so the pointer points to freed' + ' memory. Passing it to an ordinary call such as CopyFile is fine. High confidence. Quick fix for local variables: keep the intermediate result in an inline string variable.",' + #10 +
    '      "bad": "Ziel := PChar(Pfad + ''.bak'');\nCopyFile(PChar(Pfad), Ziel, False);",' + #10 +
    '      "good": "var ZielText: string := Pfad + ''.bak'';\nZiel := PChar(ZielText);\nCopyFile(PChar(Pfad), Ziel, False);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "out-param-read",' + #10 +
    '      "name": "out parameter read before it is set",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "An out parameter is read before the routine sets it on some path through the control flow. For managed types (string, interfaces, dynamic arrays, Variant) the caller has already ' + 'cleared it, so the old value is gone; for other types the value is undefined. Usually var was meant. Uses the control flow graph cannot follow (passing the parameter to a routine, setting a field of i' + 't, @Param) stay silent. High confidence. Quick fix: out becomes var in the implementation and in the declaration.",' + #10 +
    '      "bad": "procedure Anhaengen(out Text: string);\nbegin\n  Text := Text + sLineBreak + ''Ende'';\nend;",' + #10 +
    '      "good": "procedure Anhaengen(var Text: string);\nbegin\n  Text := Text + sLineBreak + ''Ende'';\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "stringlist-unsorted",' + #10 +
    '      "name": "Find or Duplicates on an unsorted TStringList",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "Find on a TStringList or THashedStringList that is created in the unit but never sorted: Find searches binary and returns wrong results on an unsorted list. The same holds for Du' + 'plicates := dupIgnore or dupError, which only works on sorted lists. Sorted counts as Sorted := True (or any value other than False), Sort, CustomSort, Create(Duplicates, True, ...) and with List do. ' + 'A list passed to a routine or assigned to another variable stays silent. Locals are tracked per routine, fields across the unit. Medium confidence. Quick fixes: Sorted := True after the creation (not ' + 'offered when the list uses Insert, Move or Exchange, which raise on sorted lists) and, for if List.Find(S, I) then, I := List.IndexOf(S) with if I >= 0.",' + #10 +
    '      "bad": "Namen := TStringList.Create;\nNamen.LoadFromFile(Datei);\nif Namen.Find(Suche, Index) then\n  Namen.Delete(Index);",' + #10 +
    '      "good": "Namen := TStringList.Create;\nNamen.Sorted := True;\nNamen.LoadFromFile(Datei);\nif Namen.Find(Suche, Index) then\n  Namen.Delete(Index);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "writeln-in-gui-app",' + #10 +
    '      "name": "Writeln in a program without console",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "Write, Writeln, Read or Readln on standard input or output in a program without a console: at run time Writeln raises EInOutError (I/O error 105), Readln I/O error 104. The appli' + 'cation type comes from DCC_ConsoleTarget in the .dproj and {$APPTYPE CONSOLE} in the .dpr (also inside {$IFDEF}); units are only checked when they belong to the loaded project, a .dpr without project ' + 'on its own. Libraries and packages stay silent. Calls with a text file as first argument, calls under if IsConsole, routines of the same name declared in the unit and Read/Write inside methods (TStrea' + 'm.Read) are exempt. High confidence. Quick fix for Write and Writeln: replace with OutputDebugString(PChar(...)) and add Winapi.Windows; numbers and Boolean go through IntToStr, FloatToStr and BoolToS' + 'tr. Option replacement sets another target, e.g. Log.Info or Logger.Log(TLogLevel.Info, %s). No fix for width specifiers (X:5) or arguments of unknown type.",' + #10 +
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
    '      "description": "raise in a destructor (also class destructor) that no except inside the destructor catches. The exception aborts the destruction: inherited Destroy no longer runs, the object sta' + 'ys half freed, and in a finally of the caller it hides the original exception. A raise in the try part of a try..except is caught; raise in the except or finally part, including a bare raise; to re-ra' + 'ise, is reported. Nested routines and anonymous methods are exempt. Calls that raise are not followed. High confidence. No quick fix: log the state or release it without an exception.",' + #10 +
    '      "bad": "destructor TSitzung.Destroy;\nbegin\n  if FOffen then\n    raise ESitzung.Create(''Sitzung noch offen'');\n  inherited;\nend;",' + #10 +
    '      "good": "destructor TSitzung.Destroy;\nbegin\n  if FOffen then\n    Schliessen;\n  inherited;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "duplicate-condition",' + #10 +
    '      "name": "Duplicate condition or identical branches",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "The same condition twice in an if ... else if chain (the later branch is never reached), identical then and else branches, the same operand twice in an and, or or xor chain, and ' + 'comparisons of an expression with itself (X = X, X < X). Usually a copy error. Expressions are compared by their tokens without whitespace, comments and case. Chains with calls that may change state (' + 'anything but SameText, Length, Assigned, Pos and similar pure functions, or Read, Next, Pop, Random ...) stay silent, as do float self-comparisons (NaN check X <> X) and comparisons on class members s' + 'uch as TFoo.Shared = TFoo.Shared. High confidence. No quick fix; the action jumps to the first occurrence.",' + #10 +
    '      "bad": "if Betrag > 1000 then\n  Stufe := 3\nelse if Betrag > 500 then\n  Stufe := 2\nelse if Betrag > 1000 then\n  Stufe := 1;",' + #10 +
    '      "good": "if Betrag > 1000 then\n  Stufe := 3\nelse if Betrag > 500 then\n  Stufe := 2\nelse if Betrag > 100 then\n  Stufe := 1;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "case-missing-enum-value",' + #10 +
    '      "name": "case over an enumeration without all values",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "A case over an enumerated type without else does not cover all values; a value added later silently falls through. The message names the missing values. The type of the selector ' + '(variable, parameter, field or chain A.B) comes from name resolution, the values from the index or the unit itself; aliases are followed. Ranges (bsNeu..bsBezahlt) and lists count as present. Selector' + 's with calls, integer and unknown types stay silent. With option requireElse a case with else is reported as well. High confidence. Quick fix \"Fehlende Werte ergänzen (n)\" adds empty branches in dec' + 'laration order before else or end, with type prefix when the labels use one ({$SCOPEDENUMS ON}).",' + #10 +
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
    '      "description": "Generalises lock-without-finally (whose lock pairs stay there) to other pairs: DisableControls/EnableControls, BeginUpdate/EndUpdate, FindFirst/FindClose (also in if FindFirst(..' + '.) = 0 then begin ... end), Reset, Rewrite or Append/CloseFile, GetMem or AllocMem/FreeMem and Screen.Cursor := ... with a later Screen.Cursor := .... Reported when the closing call stands unprotected' + ' later in the same statement list with at least one statement in between; an exception there leaves the state hanging. Both calls must use the same receiver or argument. Overlapping pairs are reported' + ' together. High confidence. Quick fix: wrap the statements in between in try/finally with the closing calls, when the closing calls follow each other directly. Option pairs adds own pairs.",' + #10 +
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
    '      "description": "Application.ProcessMessages inside a for, while or repeat loop, or directly in an event handler (a method with a Sender parameter), opens the door for re-entrancy: the user click' + 's again, closes the form or starts the operation twice. Calls inside anonymous methods are left to thread-vcl-access; other objects'' ProcessMessages methods are ignored. Medium confidence, no quick fi' + 'x: move the work to a thread or TTask, or disable the trigger until it is done. Option allowIn lists methods where it is allowed.",' + #10 +
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
    '      "description": "StrToInt, StrToInt64, StrToFloat, StrToDate, StrToDateTime or StrToCurr applied directly to user input (Edit.Text, Grid.Cells[...], Memo.Lines[...], also inside Trim) outside the' + ' try part of a try/except. Invalid input raises EConvertError with an English message. try/finally does not count as protection. Medium confidence. Quick fix for X := StrToInt(Edit.Text); as its own s' + 'tatement, when X is a variable or field of the matching type: if not TryStrToInt(Edit.Text, X) then raise EConvertError.Create(''X ist keine Zahl''). format-without-settings additionally reports locale-' + 'dependent conversions without TFormatSettings. Options functions and sources choose the checked conversions and the properties that count as input.",' + #10 +
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
    '      "description": "Dict[Key] or Dict.Items[Key] is read on a TDictionary or TObjectDictionary (also through a type alias of the file) although neither ContainsKey nor TryGetValue checked the same k' + 'ey earlier in the routine. The rule stays silent when the routine fills the dictionary itself beforehand (Add, AddOrSetValue, TryAdd, Dict[K] := ...) or when the key stems from Keys or the pairs (for ' + 'K in Dict.Keys, Names := Dict.Keys.ToArray, for Pair in Dict with K := Pair.Key). A missing key raises EListError. Medium confidence. Quick fix for X := Dict[Key]; as its own statement, when X is a va' + 'riable of the value type: if not Dict.TryGetValue(Key, X) then X := 0 (or '''', False, Default(T)).",' + #10 +
    '      "bad": "Preis := Preise[Artikel.Nummer];",' + #10 +
    '      "good": "if not Preise.TryGetValue(Artikel.Nummer, Preis) then\n  Preis := 0;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "shadowed-name",' + #10 +
    '      "name": "Local name shadows field or property",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "A parameter, local or inline variable has the same name as a field or property of the class (also inherited and visible there, resolved through the file and the symbol index) or ' + 'as a global variable of the unit declared before the routine. Especially treacherous in form methods: Caption, Name, Tag, Left. If VCL is not in the index, the members of TComponent and TControl are k' + 'nown when the ancestor chain ends at a VCL base class. Parameters of event handlers (with Sender) are skipped because the event type dictates the signature. High confidence. Quick fix: rename to AName' + ' (parameter, also in the declaration) or LName (local variable) within the routine. Option ignore lists name patterns that are never reported (default Sender, Value).",' + #10 +
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
    '      "description": "if B then X := True else X := False (also with begin/end and the values swapped), if B then Exit(True) else Exit(False) and if B then Exit(True); followed by Exit(False); can be ' + 'written directly. Complements bool-compare. High confidence. Quick fix: X := B, X := not B or Exit(B); negations are simplified (not B becomes B), compound conditions are wrapped in parentheses. Witho' + 'ut a fix when comments stand inside the if.",' + #10 +
    '      "bad": "if Betrag > 0 then\n  Result := True\nelse\n  Result := False;",' + #10 +
    '      "good": "Result := Betrag > 0;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "case-insensitive-compare",' + #10 +
    '      "name": "Comparison through UpperCase or LowerCase",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "performance",' + #10 +
    '      "description": "UpperCase(A) = UpperCase(B), LowerCase(A) <> ''x'', AnsiUpperCase(...) or A.ToUpper = B.ToUpper creates two strings for one comparison. SameText (AnsiSameText for the Ansi function' + 's and the Unicode string helpers) is shorter and faster. A literal is only accepted if the conversion does not change it; UpperCase(A) = LowerCase(B) and UpperCase(A) = ''ja'' are left alone because the' + 'y are different mistakes. Does not replace the string helper modernisation of #71. High confidence. Quick fix: SameText(A, B) or not SameText(A, B).",' + #10 +
    '      "bad": "if UpperCase(Land) = UpperCase(Standard) then",' + #10 +
    '      "good": "if SameText(Land, Standard) then"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "magic-number",' + #10 +
    '      "name": "Number without a name in code",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "Number literals (decimal, $hex, floating point, with sign) in statements, outside const sections, types, array bounds and subranges. Allowed values are configurable; DFM coordina' + 'tes and tests can be excluded through exclude. Off by default and low confidence: it shows up once the rule is switched on and minConfidence is low. Quick fix: Introduce constant (#50) in the const se' + 'ction of the routine.",' + #10 +
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
    '      "description": "Lines longer than the limit max (default 120 characters, matching the rulers from #710). Tabs count up to the next tab stop of format.indentSize. Lines that are only too long bec' + 'ause of a string or, with ignoreComments, a comment are not reported. Lines over 1023 characters are always reported as an error regardless of max, because the compiler stops there (F2069). Off by def' + 'ault. Quick fix: Wrap line after commas or before binary operators, where the pieces then fit.",' + #10 +
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
    '      "description": "The class has more members than the limit (default 40): field names, methods, properties with their own type and class var. Properties that only raise visibility (property Align;' + ') and nested types do not count; a nested class is measured on its own. Also shown in the metrics lens above the class. Split the class or move parts into helper classes; Move class to own unit (#103)' + ' helps when the unit is crowded too.",' + #10 +
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
    '      "description": "The unit has more lines than the limit (default 2000), counted up to the final end. Only units are measured, not programs or packages. Also shown in the metrics lens above the un' + 'it name. Move classes into their own units with Move class to own unit (#103).",' + #10 +
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
    '      "description": "The unit uses more units than the limit (default 30), interface and implementation together. The finding sits on the first uses. Programs and libraries are not checked, because t' + 'heir uses lists the units of the project. Also shown in the metrics lens above uses. Many dependencies usually mean the unit does too much; Move class to own unit (#103) splits it.",' + #10 +
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
    '      "id": "public-field",' + #10 +
    '      "name": "Public field",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "Fields in the public or published section of a class. The section without a visibility keyword only counts for classes without an ancestor or with TObject, because the form desig' + 'ner puts its fields there. Records are excluded unless includeRecords is set; class var is not reported. Off by default. Quick fix: Encapsulate field moves the field as FName into a private section at' + ' the end of the class and adds property Name read FName write FName in the old section; accesses from outside stay valid.",' + #10 +
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
    '      "id": "global-variable",' + #10 +
    '      "name": "Global variable in interface",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "style",' + #10 +
    '      "description": "var or threadvar in the interface section of a unit: every unit that uses it can read and change the value. The form variable created by the designer (frmMain: TfrmMain, for clas' + 'ses derived from TForm, TFrame, TDataModule or any class in a unit with a form file) is excluded unless includeFormVariables is set. Off by default. Move the variable into the implementation section a' + 'nd offer a function or property instead.",' + #10 +
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
    '      "description": "At least minLines consecutive comment lines (// per line or a multi-line { } comment) that parse as statements, declarations or class members. Prose at the start and end of the b' + 'lock is ignored, and at least half the lines must look like code (;, :=, begin, end, then, do). XMLDoc (///) and comments before the first token (license headers) are never reported. Confidence medium' + '. Version control keeps the old code; the fix removes the lines.",' + #10 +
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
    '      "id": "queue-nil-in-package",' + #10 +
    '      "name": "TThread.Queue(nil, …) in a package",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "threads",' + #10 +
    '      "description": "TThread.Queue(nil, …) or TThread.ForceQueue(nil, …) in a unit of a design-time or runtime package: the entry belongs to no thread, so nobody removes it when the package is unload' + 'ed, and CheckSynchronize may call it afterwards in memory that no longer holds the code. Package units are recognized through the .dpk or .dproj of the loaded project (a .dpk on its own without projec' + 't). A line with the comment from okMarker (default mainthread-ok) is exempt. High confidence. Quick fix: rewrite to the wrapper from the wrapper option (default TAtlasMainThread.Queue, ForceQueue for ' + 'ForceQueue); with a parenthesis the wrapper text is put in front of the remaining arguments. ForceQueue with a delay gets no quick fix. The command-line linter reads the .dpk files below the checked f' + 'older. Does the same as Tools/Check-MainThreadQueue.ps1 for any plugin project; the script stays for checks without the Atlas server.",' + #10 +
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
    '      "description": "AddNotifier on IOTAServices, IOTAEditorServices, IOTAModule and so on (or another pair from registerPairs) whose index never reaches RemoveNotifier: the call is a statement witho' + 'ut assignment, or the variable it is assigned to is never passed to RemoveNotifier in the unit (in finalization, a destructor or Destroyed). The IDE then calls the notifier after the package is unload' + 'ed, in memory that no longer holds the code. Register… calls inside the procedure Register are exempt: the IDE removes those wizards itself. Medium confidence. Quick fix in methods: keep the index in ' + 'a field (FNotifierIndex in the private section) and add RemoveNotifier to the destructor, which is created if missing; in procedures of the unit: a global variable initialized with -1 and RemoveNotifi' + 'er in finalization. No quick fix when the receiver is a parameter or local variable.",' + #10 +
    '      "bad": "procedure Register;\nbegin\n  (BorlandIDEServices as IOTAServices).AddNotifier(TSpeicherNotifier.Create);\nend;",' + #10 +
    '      "good": "var\n  NotifierIndex: Integer = -1;\n\nprocedure Register;\nbegin\n  NotifierIndex := (BorlandIDEServices as IOTAServices).AddNotifier(TSpeicherNotifier.Create);\nend;\n\ninitialization' + '\n\nfinalization\n  if NotifierIndex >= 0 then\n    (BorlandIDEServices as IOTAServices).RemoveNotifier(NotifierIndex);",' + #10 +
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
    '      "description": "A [Test] or [TestCase] method that calls no check, neither itself nor through methods of the same class or routines of the unit: it is always green. Calls matching assertPatterns' + ' (default Assert.*, WillRaise*, Check*), System.Assert and calls on classes with Assert in their name (TRuleAssert.Reports) count as checks. Tests with [WillRaise] or [Ignore] stay silent. High confid' + 'ence. Quick fixes: insert Assert.Pass as a placeholder, or jump to the method.",' + #10 +
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
    '      "description": "FOnChange(Self) or OnChange(Self) is called in a method of the class without Assigned(FOnChange) or FOnChange <> nil guarding the call: without a handler an access violation foll' + 'ows. Events are fields and properties of the class with a method pointer or reference type (procedure ... of object, reference to ..., TNotifyEvent, TProc/TFunc, types ending in Event, procedural type' + 's of the unit or the index). Guards: the then branch of a condition with Assigned (also while), the else branch of not Assigned, \"Assigned(F) and\" before the call, or \"if not Assigned(F) then Exit/' + 'raise\" before it, including a flag variable or a parameterless method of the class whose Result contains Assigned(F). Fields that a constructor sets to a value (injected dependencies such as FReadTex' + 't := AReadText), properties reading them and local names that shadow the event stay silent. High confidence. Quick fix: wrap the call in \"if Assigned(F) then\" when it is a statement of its own in a ' + 'block.",' + #10 +
    '      "bad": "procedure TZaehler.Erhoehen;\nbegin\n  Inc(FWert);\n  FOnChange(Self);\nend;",' + #10 +
    '      "good": "procedure TZaehler.Erhoehen;\nbegin\n  Inc(FWert);\n  if Assigned(FOnChange) then\n    FOnChange(Self);\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "owned-item-freed",' + #10 +
    '      "name": "Item of an owning list freed as well",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "An item of a TObjectList/TObjectList<T> (OwnsObjects, default True) or of a TObjectDictionary with doOwnsValues is freed with Free, FreeAndNil, Destroy or DisposeOf, directly (Li' + 'st[I].Free, List.Items[I].Free) or through a variable taken from List[I], List.First/Last or a for-in loop over the list or Dictionary.Values. The list frees the item itself on Delete, Remove, Clear, ' + 'an assignment to List[I], or at the latest when it is freed: a double free. A list is owning when the unit creates it that way (TObjectList without False, TObjectDictionary with doOwnsValues) or decla' + 'res it as TObjectList without creating it, and no OwnsObjects := False follows. Extract in the same routine keeps the rule silent. High confidence. Quick fixes: remove the Free (the whole loop when it' + ' only frees), Delete or Remove instead of Free, Extract instead of Remove.",' + #10 +
    '      "bad": "Auftraege := TObjectList<TAuftrag>.Create;\n…\nAuftraege[I].Free;\nAuftraege.Delete(I);",' + #10 +
    '      "good": "Auftraege := TObjectList<TAuftrag>.Create;\n…\nAuftraege.Delete(I);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "create-without-assignment",' + #10 +
    '      "name": "Object created and lost at once",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "TStringList.Create; as a statement of its own: the object is created but stored nowhere and never freed (memory leak). Silent for components with an owner (first argument Self, O' + 'wner, AOwner, Application, or a TComponent descendant with an argument other than nil), threads (they free themselves with FreeOnTerminate), records, unknown classes with arguments and classes listed ' + 'in selfRegistering. High confidence. Quick fix: assign to a new local variable and wrap the following statements of the block in try/finally with Free.",' + #10 +
    '      "bad": "procedure TImport.Starten;\nbegin\n  TImportProtokoll.Create;\n  Laden;\nend;",' + #10 +
    '      "good": "procedure TImport.Starten;\nvar\n  ImportProtokoll: TImportProtokoll;\nbegin\n  ImportProtokoll := TImportProtokoll.Create;\n  try\n    Laden;\n  finally\n    ImportProtokoll.Free;\n  e' + 'nd;\nend;",' + #10 +
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
    '      "id": "message-handler-without-inherited",' + #10 +
    '      "name": "Message handler without inherited",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "A method with message WM_... or CM_... calls neither inherited nor DefaultHandler (or DefWindowProc, CallWindowProc). The default handling of the VCL or Windows is lost: no reali' + 'gnment on WM_SIZE, no closing on WM_CLOSE, no painting on WM_PAINT. The message names the consequence for common messages. Silent for classes without an ancestor, for messages listed in swallow (defau' + 'lt WM_ERASEBKGND) and for handlers that set Msg.Result themselves (deliberate answer such as MA_NOACTIVATE). Medium confidence. Quick fix: insert inherited; at the start.",' + #10 +
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
    '      "description": "The classic string routines count from 1: Copy(S, 0, N) and Insert(T, S, 0) only work like 1 by chance, Delete(S, 0, N) deletes nothing. The string must be known: declared type i' + 'n the file, literal, or .Text/.Caption; dynamic arrays (0-based) stay silent. Pos, PosEx and AnsiPos return 0 for no match: Pos(...) > -1, >= 0 and <> -1 are always true, = -1 and < 0 never. Conversel' + 'y S.IndexOf(...) > 0 or >= 1 misses a match at the start, < 1 or <= 0 counts it as not found (medium confidence; LastIndexOf stays silent, where > 0 usually means \"not at the start\"). High confidenc' + 'e for Delete and Pos. Quick fix: start value 1 or the corrected comparison (> 0, = 0, >= 0, < 0).",' + #10 +
    '      "bad": "if Pos('';'', Zeile) > -1 then\n  Felder := Copy(Zeile, 0, Pos('';'', Zeile) - 1);",' + #10 +
    '      "good": "if Pos('';'', Zeile) > 0 then\n  Felder := Copy(Zeile, 1, Pos('';'', Zeile) - 1);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "delimited-text-without-strict",' + #10 +
    '      "name": "DelimitedText without StrictDelimiter",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "List.DelimitedText := ... after List.Delimiter := ... in the same routine without StrictDelimiter being set: DelimitedText then also splits at spaces, ''Max Muster;Berlin'' becomes' + ' three entries instead of two. For fields, StrictDelimiter anywhere in the unit counts (often in the constructor); StrictDelimiter := False is deliberate and stays silent, as does DelimitedText withou' + 't a Delimiter of its own. High confidence. Quick fix: insert StrictDelimiter := True; before the assignment.",' + #10 +
    '      "bad": "Teile.Delimiter := '';'';\nTeile.DelimitedText := Zeile;",' + #10 +
    '      "good": "Teile.Delimiter := '';'';\nTeile.StrictDelimiter := True;\nTeile.DelimitedText := Zeile;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "self-as-interface-in-constructor",' + #10 +
    '      "name": "Self passed as interface during construction",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "Self is passed as an interface while reference counting can already free the object. Only two real error cases are reported: (1) a class with its own reference counting (an _Rele' + 'ase in the class chain frees the object, no class overrides NewInstance, the chain is known up to TObject) passes Self as an interface in a constructor or in AfterConstruction: the counter goes from 0' + ' to 1 and back to 0, the object is destroyed before construction ends. (2) A TInterfacedObject descendant passes Self as an interface in AfterConstruction after inherited: inherited AfterConstruction ' + 'has already removed the protective count from NewInstance. In the constructor of a TInterfacedObject descendant Self is protected and the rule stays silent. Passing counts as Self as IX, IX(Self), an ' + 'argument whose parameter is an interface in all known overloads, and an assignment to an interface variable. High confidence. Quick fix in case 2: move the statement before inherited.",' + #10 +
    '      "bad": "procedure TBeobachter.AfterConstruction;\nbegin\n  inherited;\n  FQuelle.Anmelden(Self);\nend;",' + #10 +
    '      "good": "procedure TBeobachter.AfterConstruction;\nbegin\n  FQuelle.Anmelden(Self);\n  inherited;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "null-compare",' + #10 +
    '      "name": "Comparison with Null instead of VarIsNull or IsNull",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "robustness",' + #10 +
    '      "description": "X = Null or X <> Null compares a variant with Null. The result depends on the global System.Variants.NullEqualityRule: with the default ncrLoose the comparison works as expected,' + ' with ncrStrict it is never true and with ncrError it raises an exception. A library, a test framework or another part of the project can change the rule. VarIsNull(X) and Field.IsNull check independe' + 'ntly of it. Reported only where the comparison stands on its own (condition, argument, assignment); not X = Null binds as (not X) = Null and gets no quick fix. High confidence. Quick fix: Field.IsNull' + ' for X.Value on FieldByName, FindField, Fields[...], ParamByName, Params[...] or a field of type T...Field/T...Param, otherwise VarIsNull(X); with <> preceded by not.",' + #10 +
    '      "bad": "if qryKunde.FieldByName(''Geburtstag'').Value = Null then\n  Alter := 0;",' + #10 +
    '      "good": "if qryKunde.FieldByName(''Geburtstag'').IsNull then\n  Alter := 0;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unchecked-enum-cast",' + #10 +
    '      "name": "Number cast to enumeration without check",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "TStatus(N) with an enumeration type declared in the file or the index, where N comes from a call listed in the option sources (FieldByName, ReadInteger, AsInteger, StrToInt): dir' + 'ectly in the argument or via a variable that is not read (checked) between its assignment and the cast. A value outside the range yields an invalid enumeration value that falls through case statements' + '. EnsureRange, Min or Max in the argument count as a check; constants, arithmetic and unknown types stay silent. For enumerations with explicit ordinal values the range is given as Ord(Low(T))..Ord(Hi' + 'gh(T)). Medium confidence. Quick fix for a direct source in a statement of its own: helper variable, InRange check with raise EConvertError before it, System.Math added to uses.",' + #10 +
    '      "bad": "Status := TStatus(qry.FieldByName(''Status'').AsInteger);",' + #10 +
    '      "good": "Wert := qry.FieldByName(''Status'').AsInteger;\nif not InRange(Wert, Ord(Low(TStatus)), Ord(High(TStatus))) then\n  raise EConvertError.CreateFmt(''Ungültiger Wert %d für TStatus'', [Wert])' + ';\nStatus := TStatus(Wert);",' + #10 +
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
    '      "description": "CreateProcess (CreateProcessW) and CreateProcessAsUser write into the buffer of lpCommandLine. A PChar on memory that cannot be written causes an access violation. Reported for P' + 'Char(...)/PWideChar(...) on: a string literal or constant; a concatenation of exactly one literal and one value (if the value is empty, the RTL returns the literal itself); a local string variable who' + 'se last assignment before the call is one of these, without UniqueString afterwards; a string parameter (medium confidence, the caller may pass a literal). Function results such as Format and concaten' + 'ations with several parts are writable heap strings and stay silent, as does CreateProcessA, which copies the command line itself. Quick fix: copy the command line into a local variable and call Uniqu' + 'eString; for a variable, UniqueString before the statement. No quick fix in loop conditions.",' + #10 +
    '      "bad": "CreateProcess(nil, PChar(''notepad.exe '' + Datei), nil, nil, False, 0, nil, nil, SI, PI);",' + #10 +
    '      "good": "Befehl := ''notepad.exe '' + Datei;\nUniqueString(Befehl);\nCreateProcess(nil, PChar(Befehl), nil, nil, False, 0, nil, nil, SI, PI);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "form-access-before-create",' + #10 +
    '      "name": "Access to a form that is not created yet",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "find-bugs",' + #10 +
    '      "description": "The constructor, AfterConstruction or the OnCreate handler of an automatically created form or data module uses the global variable of another form that the .dpr creates later wi' + 'th Application.CreateForm. The variable is still nil at that point. The order comes from the .dpr of the project the unit belongs to; the OnCreate handler from the form file (FormCreate or DataModuleC' + 'reate without one). Silent when the routine checks the variable (Assigned, comparison with nil), assigns it itself, creates it with CreateForm or declares a local name of the same name, and for forms ' + 'that are not created automatically. Each variable is reported once per routine. Medium confidence. No quick fix: change the order in the .dpr or move the access to OnShow.",' + #10 +
    '      "bad": "procedure TfrmHaupt.FormCreate(Sender: TObject);\nbegin\n  lblNutzer.Caption := dmDaten.Benutzer;\nend;",' + #10 +
    '      "good": "// .dpr: Application.CreateForm(TdmDaten, dmDaten) before TfrmHaupt\nprocedure TfrmHaupt.FormCreate(Sender: TObject);\nbegin\n  lblNutzer.Caption := dmDaten.Benutzer;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "except-handler-order",' + #10 +
    '      "name": "General exception handler before a specific one",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "exceptions",' + #10 +
    '      "description": "In a try..except with several on handlers the first matching handler wins. A handler for a class that an earlier handler already catches is never reached: its code is dead and th' + 'e special treatment never runs. Reported when an earlier handler names the same class, an ancestor of it, Exception (covers every exception class) or TObject. Ancestors come from the unit, the project' + ' index and a table of known RTL, VCL and FireDAC exception classes (for example EStreamError > EFOpenError, EIntError > ERangeError); unknown classes are only compared with Exception and TObject. Quic' + 'k fix: move the specific handler before the general one (only when both handlers stand on their own lines). A duplicate handler for the same class is reported without a quick fix.",' + #10 +
    '      "bad": "except\n  on E: Exception do\n    Protokoll(E.Message);\n  on E: EConvertError do\n    ShowMessage(''Ungültige Zahl'');\nend;",' + #10 +
    '      "good": "except\n  on E: EConvertError do\n    ShowMessage(''Ungültige Zahl'');\n  on E: Exception do\n    Protokoll(E.Message);\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "reraise-exception-object",' + #10 +
    '      "name": "raise E instead of raise in a handler",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "exceptions",' + #10 +
    '      "description": "raise E; in an on E: … handler raises the caught exception object again as a new raise. The RTL does not free the object twice, but the exception now starts at the handler: Excep' + 'tAddr and the call stack of tools such as madExcept or JclDebug point to the handler instead of the original fault, and the original location is lost. raise; re-raises the current exception unchanged.' + ' Also reported for raise E at …, then without a quick fix. Silent when the handler takes the object over with AcquireExceptionObject or assigns a new object to the variable, inside anonymous methods a' + 'nd for handlers without a variable name. High confidence. Quick fix: raise E; → raise;.",' + #10 +
    '      "bad": "except\n  on E: EDatenbank do\n  begin\n    Protokoll(E.Message);\n    raise E;\n  end;\nend;",' + #10 +
    '      "good": "except\n  on E: EDatenbank do\n  begin\n    Protokoll(E.Message);\n    raise;\n  end;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "blocking-call-in-main-thread",' + #10 +
    '      "name": "Blocking call in the main thread",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "threads",' + #10 +
    '      "description": "Sleep, WaitFor, WaitForSingleObject, WaitForMultipleObjects or Wait in methods of forms and frames (classes that inherit from TForm, TCustomForm, TFrame or TCustomFrame) and in e' + 'vent handlers (methods with a Sender parameter) outside thread classes. The user interface freezes while the call waits; if the other thread waits for Synchronize, the program hangs. WaitFor without a' + ' timeout on a variable names the risk of the Synchronize deadlock. Sleep, WaitForSingleObject and WaitForMultipleObjects count only without a receiver (or with Winapi.Windows), WaitFor and Wait only o' + 'n a receiver. A literal timeout below maxSleepMs (Sleep(10), WaitForSingleObject(H, 0)) stays silent, except a short Sleep in a waiting loop without Application.ProcessMessages. Anonymous methods are ' + 'skipped (TTask.Run, TThread.Queue), nested routines belong to their method. Medium confidence. No quick fix: move the work into TTask.Run and report the result with TThread.Queue.",' + #10 +
    '      "bad": "procedure TfrmHaupt.btnExportClick(Sender: TObject);\nbegin\n  FExport.Start;\n  FExport.WaitFor;\nend;",' + #10 +
    '      "good": "procedure TfrmHaupt.btnExportClick(Sender: TObject);\nbegin\n  btnExport.Enabled := False;\n  TTask.Run(\n    procedure\n    begin\n      FExport.Ausfuehren;\n      TThread.Queue(nil, p' + 'rocedure begin btnExport.Enabled := True; end);\n    end);\nend;",' + #10 +
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
    '      "description": "A while or repeat loop in TThread.Execute, or in a method of the thread class that is only called from there (also through other such methods, including nested routines), does no' + 't check Terminated. Terminate then has no effect, and WaitFor or Free hang when the program shuts down. Reported for endless loops (while True, until False) and for waiting loops with Sleep, WaitFor, ' + 'WaitForSingleObject, WaitForMultipleObjects, MsgWaitForMultipleObjects, Wait or Yield whose condition and body never mention Terminated or CheckTerminated. Thread classes come from the unit and the in' + 'dex. Bounded loops, for loops, anonymous methods and classes that override TerminatedSet (they end their loops another way) stay silent. High confidence. Quick fix: add Terminated to the loop conditio' + 'n (while True → while not Terminated, otherwise and not Terminated; until False → until Terminated, otherwise or Terminated).",' + #10 +
    '      "bad": "procedure TPoller.Execute;\nbegin\n  while True do\n  begin\n    Abfragen;\n    Sleep(1000);\n  end;\nend;",' + #10 +
    '      "good": "procedure TPoller.Execute;\nbegin\n  while not Terminated do\n  begin\n    Abfragen;\n    Sleep(1000);\n  end;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "anonymous-thread-not-started",' + #10 +
    '      "name": "Anonymous thread never started",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "threads",' + #10 +
    '      "description": "TThread.CreateAnonymousThread(…) creates the thread suspended with FreeOnTerminate set. Without Start the thread never runs, and because it never terminates it is never freed eit' + 'her. Reported for the call as a statement of its own and for a local variable (also an inline variable) that is never started with Start or Resume and not passed on (argument, assignment, Result, fiel' + 'd). Setting properties such as FreeOnTerminate or OnTerminate does not count as passing on. High confidence. Quick fix: append .Start; for a variable, T.Start; after the last statement of the same blo' + 'ck that mentions it.",' + #10 +
    '      "bad": "TThread.CreateAnonymousThread(\n  procedure\n  begin\n    Synchronisieren;\n  end);",' + #10 +
    '      "good": "TThread.CreateAnonymousThread(\n  procedure\n  begin\n    Synchronisieren;\n  end).Start;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "task-exception-unobserved",' + #10 +
    '      "name": "Exception in TTask gets lost",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "threads",' + #10 +
    '      "description": "TTask.Run(…) or TTask.Create(…).Start whose result is never kept or queried with Wait, Status or similar, and whose anonymous method has no try … except. An exception in the task' + ' disappears silently. Also reported for a local variable that is never mentioned again (for TTask.Create only in V.Start). Silent for kept results (fields, Result, any other use of the variable) and f' + 'or method references, whose body the rule cannot see. Medium confidence. Quick fix: wrap the body in try … except and report the message on the main thread through TThread.Queue with ShowMessage (adds' + ' Vcl.Dialogs, or FMX.Dialogs in FireMonkey units, and System.SysUtils to the uses clause when missing); only when begin and end of the anonymous method stand on their own lines.",' + #10 +
    '      "bad": "TTask.Run(\n  procedure\n  begin\n    Importieren(Datei);\n  end);",' + #10 +
    '      "good": "TTask.Run(\n  procedure\n  begin\n    try\n      Importieren(Datei);\n    except\n      on E: Exception do\n      begin\n        var Fehler := E.Message;\n        TThread.Queue(nil,\n  ' + '        procedure\n          begin\n            ShowMessage(Fehler);\n          end);\n      end;\n    end;\n  end);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dataset-loop-without-next",' + #10 +
    '      "name": "Dataset loop without Next",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "database",' + #10 +
    '      "description": "while not Q.Eof do without Q.Next in the body, or with Next only on some of the paths that continue the loop (an if without else, Continue before Next). The loop spins forever on' + ' the same record. Delete, MoveBy, Last, Close, FindNext and Free also count as moving on; Break, Exit, Abort and raise end the loop. Nested while and for loops are not trusted to run. When Q is passed' + ' on in the body (argument, assignment, with), the called code may move the record pointer and the rule stays silent. High confidence when Next is missing entirely, medium when only some paths miss it.' + ' Quick fix: insert Q.Next; at the end of the begin … end body (only when Next is missing entirely).",' + #10 +
    '      "bad": "qryPositionen.First;\nwhile not qryPositionen.Eof do\nbegin\n  Summe := Summe + qryPositionen.FieldByName(''Betrag'').AsCurrency;\nend;",' + #10 +
    '      "good": "qryPositionen.First;\nwhile not qryPositionen.Eof do\nbegin\n  Summe := Summe + qryPositionen.FieldByName(''Betrag'').AsCurrency;\n  qryPositionen.Next;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dataset-edit-without-post",' + #10 +
    '      "name": "Edit or Append without Post",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "database",' + #10 +
    '      "description": "After Edit, Append or Insert (without arguments) on a dataset, the same routine calls neither Post nor Cancel (nor CheckBrowseMode). The change stays open and is silently lost on' + ' scrolling or saved unexpectedly later; on an exception in between, nothing cancels it. Silent when another routine of the unit posts or cancels the same dataset (an Edit button with a separate Save b' + 'utton) and when the dataset is passed on after Edit (argument, assignment, with). Medium confidence. Quick fix: wrap the following statements that use the dataset in try … except, with Post at the end' + ' of the try part and Cancel; raise; in the except part.",' + #10 +
    '      "bad": "tblKunde.Edit;\ntblKunde.FieldByName(''Status'').AsInteger := Ord(ksAktiv);\nProtokollieren;",' + #10 +
    '      "good": "tblKunde.Edit;\ntry\n  tblKunde.FieldByName(''Status'').AsInteger := Ord(ksAktiv);\n  tblKunde.Post;\nexcept\n  tblKunde.Cancel;\n  raise;\nend;\nProtokollieren;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "transaction-without-rollback",' + #10 +
    '      "name": "Transaction without Rollback",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "database",' + #10 +
    '      "description": "StartTransaction without Rollback in the except part of the try that directly follows. On an exception the transaction stays open and holds locks. Recognized for FireDAC (TFDConn' + 'ection, TFDTransaction), IBX and dbExpress (StartTransaction/Commit/Rollback), dbExpress from XE (BeginTransaction/CommitFreeAndNil/RollbackFreeAndNil, also as T := Conn.BeginTransaction) and ADO (Beg' + 'inTrans/CommitTrans/RollbackTrans). The option pairs replaces these pairs with your own. The Rollback may sit in a try … except inside a try … finally that follows directly. Silent when another routin' + 'e of the unit rolls back the same connection (transaction across several events). High confidence. Quick fix: wrap the statements up to the Commit of the same block in try … except with Rollback (with' + ' the arguments of the Commit) and raise; only when a Commit follows in the same block.",' + #10 +
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
    '      "description": "An UPDATE or DELETE without WHERE in a string literal, SQL.Text, SQL.Add, CommandText, the first argument of ExecSQL, ExecSQLScalar, Open, ExecuteDirect or Execute, or in SQL.Str' + 'ings/CommandText of the form file. It affects every row of the table; usually the condition was forgotten. The rule assembles the SQL text per query within a routine (Clear and a new Text start over) ' + 'and substitutes constants and local values. JOIN, TOP, LIMIT and ROWS restrict the rows as well; a WHERE in a subquery or comment does not count. Unknown parts behind the table name (variables, calls ' + 'at the place of a clause) keep the statement silent; a dynamic table name reports with medium confidence. Silent when the routine passes the SQL on or another routine of the unit adds to it; form file' + ' SQL only counts when the unit does not change it. Literals outside SQL properties count only with DELETE or UPDATE in capitals, so message texts stay silent. High confidence, no quick fix; tables tha' + 't are emptied on purpose go into allowTables.",' + #10 +
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
    '      "description": "The header in the implementation section has different parameters (count, name, type, const/var/out), a different result type, procedure instead of function or a different callin' + 'g convention than the declaration in the type (like E2037). With overloads the nearest declaration is compared (parameter count, then types, names and modifiers); if that is not unique, declared-not-i' + 'mplemented and implemented-not-declared report both sides instead. A body may omit the parameter list, the result type and the calling convention. Methods inside {$IF} blocks are skipped; with include' + ' files the confidence is medium. Quick fix: align the implementation header with the declaration, or, as the second action, the declaration with the implementation (default values stay in the declarat' + 'ion). Off with refactoring.syncSignatures = false only removes the quick fixes.",' + #10 +
    '      "bad": "procedure Buchen(const Betrag: Currency; Datum: TDate);\n…\nprocedure TKonto.Buchen(Betrag: Currency; Datum: TDateTime);",' + #10 +
    '      "good": "procedure Buchen(const Betrag: Currency; Datum: TDate);\n…\nprocedure TKonto.Buchen(const Betrag: Currency; Datum: TDate);",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2037",' + #10 +
    '        "E2211",' + #10 +
    '        "E2065"' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "interface-not-implemented",' + #10 +
    '      "name": "Interface method missing in the class",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A class lists an interface but does not implement all of its methods, including those of ancestor interfaces (like E2291). A method of the class with the same name but a differen' + 't signature is reported at that method (like E2211). Methods inherited from ancestor classes, method resolution clauses (procedure IFoo.Bar = Baz) and properties with implements count; public TObject ' + 'methods and IInterface methods of TInterfacedObject and similar RTL bases count as well. If the chain of ancestor classes ends at an unknown class or the interface is unknown, the rule stays silent. A' + ' method resolution clause for an interface the class does not list is reported too (like E2265). Classes inside {$IF} blocks are skipped. Quick fix: declare the missing methods and create empty bodies' + ' (not offered when a header differs).",' + #10 +
    '      "bad": "TDateiLog = class(TInterfacedObject, ILogger)\npublic\n  procedure Info(const Text: string);\nend;",' + #10 +
    '      "good": "TDateiLog = class(TInterfacedObject, ILogger)\npublic\n  procedure Info(const Text: string);\n  procedure Warnung(const Text: string);\n  procedure Fehler(const Text: string);\nend;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2291",' + #10 +
    '        "E2211",' + #10 +
    '        "E2265"' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "uses-unit-not-found",' + #10 +
    '      "name": "Unit in uses not found",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A unit in uses or contains is found neither in the project nor in the folders the compiler searches: folder of the using file, project folder, search paths and DCU output folder ' + 'of the .dproj, library paths of the installation, each as .pas or .dcu and with every unit scope name in front (SysUtils → System.SysUtils); in packages also the units of the required packages (like F' + '2613). Also reported: a file from in ''…'' that does not exist (F1026), a package from requires found neither as .dpk nor as .dcp (E2202), a unit that uses itself (F2092), and once a missing unit System' + ', i.e. a missing library path, instead of one finding per unit (F1027). Entries inside {$IF} blocks are skipped; without a known installation, with an open macro in a search path or with a required pa' + 'ckage of unknown content the rule stays silent. The message names similar units. Quick fixes: use the unit with its namespace (Forms → Vcl.Forms) or a similarly written unit, or add the folder below t' + 'he project that holds the unit to DCC_UnitSearchPath of the base configuration in the .dproj.",' + #10 +
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
    '          "description": "Where units are searched: project (like the compiler: project, search paths of the .dproj, library paths, .pas and .dcu), atlas (what Atlas knows: index and browsing paths of' + ' the installation) or both."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unresolved-attribute",' + #10 +
    '      "name": "Attribute not found and silently ignored",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "An attribute [Name] resolves neither to a class NameAttribute nor to Name, usually because a unit is missing in uses. Delphi only warns (W1074) and skips the attribute: DUnitX te' + 'sts do not run, JSON or ORM mappings are missing. The message names the unit that declares the attribute in the index; a facade unit that passes the type on from another candidate (DUnitX.TestFramewor' + 'k instead of DUnitX.Attributes) comes first, and the DUnitX attributes are known even without DUnitX in the index. Compiler attributes such as Weak, Unsafe, Ref and Volatile always count. Silent witho' + 'ut the unit System in the index, when a unit from uses is not in the index (it could declare the attribute), inside {$IF} blocks and when an ancestor of the surrounding class is unknown; with include ' + 'files the confidence is medium. Quick fix: add the unit to uses.",' + #10 +
    '      "bad": "uses\n  System.SysUtils;\ntype\n  [TestFixture]\n  TKundeTests = class",' + #10 +
    '      "good": "uses\n  System.SysUtils, DUnitX.TestFramework;\ntype\n  [TestFixture]\n  TKundeTests = class",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "W1074",' + #10 +
    '        "E2289"' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "comparison-as-statement",' + #10 +
    '      "name": "Comparison instead of assignment as a statement",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A comparison such as Result = 0; or FAktiv = True; stands on its own as a statement; := was meant. Delphi only reports E2014 when compiling. With = and an assignable left side (v' + 'ariable, field, element, pointer target) the quick fix replaces = with :=. Other comparisons and expressions whose value is discarded (A <> B;, A + B;, not A;, a literal) are reported without a fix, a' + 's is a call on the left side.",' + #10 +
    '      "bad": "Result = 0;",' + #10 +
    '      "good": "Result := 0;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2014"' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "duplicate-case-label",' + #10 +
    '      "name": "Duplicate case label",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "Two labels of a case statement cover the same value (like E2030), also through ranges (1..5 and 3), constants with the same value, characters (''a'' and #97) and enumeration ranges' + '. The same applies to the labels of a variant record part (like E2027). Values are computed from numbers, characters, constants and enumeration values via name resolution; labels whose value is unknow' + 'n are only compared by their text. A label is only reported when the earlier one is compiled whenever it is: different branches of the same {$IF} never clash. Quick fix: remove the duplicate value fro' + 'm the later branch, or the whole branch when it was its only label; a partial range overlap is reported without a fix.",' + #10 +
    '      "bad": "case Status of\n  stNeu, stOffen: Bearbeiten;\n  stGeschlossen: Archivieren;\n  stOffen: Erinnern;\nend;",' + #10 +
    '      "good": "case Status of\n  stNeu, stOffen: Bearbeiten;\n  stGeschlossen: Archivieren;\nend;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2030",' + #10 +
    '        "E2027"' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "field-after-method",' + #10 +
    '      "name": "Field after methods in the same section",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "Within a visibility section of a class, object or record, a field declaration follows a method or property. Delphi requires fields first or a new section or var (E2169); FPC acce' + 'pts it. Quick fixes: move the field with its attributes and comments to the start of the section, or put var in front of it. In records var comes first because moving changes the memory layout. A fiel' + 'd is only reported when a method before it is compiled whenever the field is; with conditional branches in between only var is offered.",' + #10 +
    '      "bad": "TKunde = class\nprivate\n  function GetName: string;\n  FName: string;\nend;",' + #10 +
    '      "good": "TKunde = class\nprivate\n  FName: string;\n  function GetName: string;\nend;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2169"' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "overload-directive-missing",' + #10 +
    '      "name": "Overload without overload or with the same signature",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "Two routines or methods of the same name in the same scope (a type, the unit across interface and implementation, the routines nested in a routine), of which at least one lacks o' + 'verload (like E2254, or E2267 when the earlier one lacks it), or two overloads with the same parameter kinds and types (like E2252, or E2301 with the same result type as well). A body that implements ' + 'an earlier declaration (interface, forward) does not count. Operators, method bodies and declarations in different branches of the same {$IF} are skipped. Quick fix: append overload; to every declarat' + 'ion without it, before the other directives.",' + #10 +
    '      "bad": "procedure Laden(const Datei: string);\nprocedure Laden(Strom: TStream);",' + #10 +
    '      "good": "procedure Laden(const Datei: string); overload;\nprocedure Laden(Strom: TStream); overload;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2254",' + #10 +
    '        "E2267",' + #10 +
    '        "E2252",' + #10 +
    '        "E2301"' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "duplicate-declaration",' + #10 +
    '      "name": "Identifier declared twice",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "An identifier is declared twice in the same scope (like E2004): a local variable, constant, type or label and a parameter of the routine, two fields, a field and a method or prop' + 'erty of a type, two types, a constant and a variable of the unit across interface and implementation. Likewise a unit twice in uses or in the uses clauses of interface and implementation at once (opti' + 'on checkUses). Overloads and bodies of routines, a forward declaration and its type, TList next to TList<T> and declarations in different branches of the same {$IF} do not count. Quick fix: remove the' + ' second declaration (the whole var, const, type or label section when it was its only one; for uses the duplicate entry); none for parameters, methods and properties.",' + #10 +
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
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "conditional-directive-unbalanced",' + #10 +
    '      "name": "Conditional directives incomplete or unknown",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "An {$IFDEF}, {$IFNDEF}, {$IFOPT} or {$IF} that is never closed, so the rest of the file depends on its condition (like E2095, E2280 for {$IF}); {$ELSE}, {$ELSEIF}, {$ENDIF} or {$' + 'IFEND} without a matching {$IF…}, or after {$ELSE} (like E2279); {$IFDEF}, {$IFNDEF}, {$DEFINE} or {$UNDEF} without a valid symbol (like E2173); an unknown directive or {$WARN} identifier (like W1030)' + ', with the closest known name as quick fix; {$POPOPT} without {$PUSHOPT} (like W1078) or {$PUSHOPT} without {$POPOPT} (like W1079); an invalid value for {$ALIGN} or {$A} (like E2573). Unknown names ar' + 'e not checked in branches whose condition tests FPC, {$PUSHOPT}/{$POPOPT} only when none of them is inside a conditional branch. Quick fixes: add {$ENDIF} before the first blank line after the open bl' + 'ock, remove a surplus directive, correct the typo.",' + #10 +
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
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "override-target-missing",' + #10 +
    '      "name": "override without a matching virtual method",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "A method marked override for which no ancestor has a virtual (or dynamic, abstract) method with the same name and parameters (like E2137): often a typo (Destory) or parameters ch' + 'anged in the ancestor. The message names the closest virtual method of the ancestor (\"there it is Ausfuehren(const Modus: TModus)\") or a similar name. Also: override on a static method (like E2170),' + ' on a final one (like E2352), and deriving from a sealed class (like E2353). Ancestors are looked up in the file and in the symbol index; when the chain breaks at an unknown class the rule stays silen' + 't. Without System in the index the virtual methods of TObject count as present. Type parameters of generic ancestors, type aliases and synonyms such as Longint match. Quick fix: take over the ancestor' + '''s signature in the declaration and the implementation.",' + #10 +
    '      "bad": "TDienst = class\nprotected\n  procedure Ausfuehren(const Modus: TModus); virtual;\nend;\nTImportDienst = class(TDienst)\nprotected\n  procedure Ausfuehren(Modus: Integer); override;\nend' + ';",' + #10 +
    '      "good": "TImportDienst = class(TDienst)\nprotected\n  procedure Ausfuehren(const Modus: TModus); override;\nend;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2137",' + #10 +
    '        "E2170",' + #10 +
    '        "E2352",' + #10 +
    '        "E2353"' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "abstract-class-instantiated",' + #10 +
    '      "name": "Instance of a class with abstract methods",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "Create on a class that declares or inherits abstract methods without overriding them (like W1020), or on a class declared abstract (like E2402). Calling an abstract method raises' + ' EAbstractError at run time; the message names the open methods. Classes are looked up in the file and in the symbol index; overloads with the same number of parameters count as one method. Calls on c' + 'lass references, inherited Create and constructor bodies are not checked. Quick fix for a class of this file that inherits the abstract methods: override them there (like the code action \"override\")' + '.",' + #10 +
    '      "bad": "Form := TForm.Create;\nGesamt := Gesamt + Form.Flaeche;",' + #10 +
    '      "good": "Form := TKreis.Create;\nGesamt := Gesamt + Form.Flaeche;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "W1020",' + #10 +
    '        "E2402"' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "property-accessor-invalid",' + #10 +
    '      "name": "Invalid property getter or setter",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "The name after read or write of a property does not fit: it is declared neither in the class nor in its ancestors, or it is a property (like E2168); the getter or setter has the ' + 'wrong kind, parameters or types (like E2234); the setter takes a var or out parameter (like E2282); the accessor is overloaded (like E2271); a class property uses an instance member or a class method ' + 'without static (like E2355), or an instance property uses a class member (like E2356); an array property or a property with index uses a field (like E2174); a field selector goes through a field that ' + 'is no record (like E2459), names a member that is no field (like E2461) or a field the record lacks (like E2562). Names are looked up in the file and, for ancestors, in the symbol index; the rule stay' + 's silent when the ancestor chain breaks, the name only exists in an inactive branch, the class cannot see it or the class includes files. Types are compared only when both are built in or declared as ' + 'types of their own. Quick fix for a missing F<Name>, Get<Name> or Set<Name>: create it (like the completion after read/write, completion.accessorSection).",' + #10 +
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
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "assign-to-property-member",' + #10 +
    '      "name": "Assignment to a field of a property record",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "Assignment to a field of a record that a property with a getter, a default or array property or a function result only delivers as a copy (like E2064): the assignment has no effe' + 'ct. Assignments to untyped constants are reported as well. Types come from name resolution; the rule only reports when the record type is known for sure. A property that reads a field directly lets De' + 'lphi write into that field and stays silent. Quick fix for a property with write: assign through a local variable and write it back; the variable is declared in the routine and the unit of its type is' + ' added to uses.",' + #10 +
    '      "bad": "Rahmen.BoundsRect.Left := 0;",' + #10 +
    '      "good": "R := Rahmen.BoundsRect;\nR.Left := 0;\nRahmen.BoundsRect := R;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2064",' + #10 +
    '        "E2453"' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "readonly-property-assigned",' + #10 +
    '      "name": "Assignment to a property without write",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "group": "compiler",' + #10 +
    '      "description": "Assignment to a property that has no write (like E2129), or reading a property that has no read (like E2130). The rule only reports when name resolution finds the property for su' + 're; redeclarations without read and write (property Caption;) count as unknown. Quick fixes: Count := 0 becomes Clear when the type has Clear; inside a method of the declaring class, assign the field ' + 'behind read; for a property declared in this file, create the setter and add write.",' + #10 +
    '      "bad": "Liste.Count := 0;",' + #10 +
    '      "good": "Liste.Clear;",' + #10 +
    '      "compilerCodes": [' + #10 +
    '        "E2129",' + #10 +
    '        "E2130"' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "sql-select-star",' + #10 +
    '      "name": "SELECT * in code",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "database",' + #10 +
    '      "description": "SELECT * or SELECT alias.* in a column list, in the same places as sql-write-without-where: string literals, SQL.Text, SQL.Add, CommandText, the first argument of ExecSQL, Open a' + 'nd similar calls, constants, local values and SQL.Strings/CommandText of the form file. New columns silently change the dataset, persistent fields no longer match, and more data is transferred than ne' + 'eded. Subqueries count; EXISTS (SELECT * …) and COUNT(*) stay silent, as does a column list from a variable. Literals outside SQL properties count only with SELECT in capitals and a FROM, so message t' + 'exts stay silent. Off by default (enable in the rules settings or with the strict profile). High confidence. Quick fix: when the star stands in a single literal and the dataset has persistent fields i' + 'n the form file, replace * with their FieldName list (without calculated and lookup fields).",' + #10 +
    '      "bad": "qry.SQL.Text := ''SELECT * FROM Kunden WHERE Ort = :Ort'';",' + #10 +
    '      "good": "qry.SQL.Text := ''SELECT Id, Name, Ort FROM Kunden WHERE Ort = :Ort'';"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "path-concat-without-delimiter",' + #10 +
    '      "name": "Path joined without delimiter",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "group": "robustness",' + #10 +
    '      "description": "A folder without a trailing path delimiter is joined to a file or folder name with +: results of ExtractFileDir, ExcludeTrailingPathDelimiter, GetCurrentDir, GetHomePath, TPath.G' + 'etDocumentsPath and the other TPath.Get…Path folders, TPath.GetDirectoryName, TDirectory.GetCurrentDirectory and TDirectory.GetParent, called directly or held in a local variable that the routine only' + ' assigns such values to. The result is C:\\Datadatei.txt instead of C:\\Data\\datei.txt. ExtractFilePath, IncludeTrailingPathDelimiter and TPath.GetTempPath end with a delimiter and stay silent, as do' + ' delimiters, extensions (ExtractFileExt, ''.bak'') and texts that start with a space or punctuation. A literal name reports with high confidence, an identifier with medium confidence. A local variable p' + 'assed to a procedure other than ForceDirectories, FileExists and similar read-only calls may be changed there and stays silent. Quick fix: TPath.Combine(Folder, Name), adding System.IOUtils to uses.",' + #10 +
    '      "bad": "Ordner := TPath.GetDocumentsPath;\nDatei := Ordner + ''export.csv'';",' + #10 +
    '      "good": "Ordner := TPath.GetDocumentsPath;\nDatei := TPath.Combine(Ordner, ''export.csv'');"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "hardcoded-path",' + #10 +
    '      "name": "Hard-coded file path",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "group": "robustness",' + #10 +
    '      "description": "A string literal with a drive letter (C:\\…, also with /) or a UNC path (\\\\server\\share\\…); paths under C:\\Users or C:\\Documents and Settings get their own message. On othe' + 'r computers the path is missing. Drive roots such as ''C:\\'' alone and the prefixes \\\\?\\ and \\\\.\\ stay silent, as do comments, test units and units listed in allowUnits (for example a unit with t' + 'he default paths of an installation). High confidence, no quick fix: take the path from TPath (GetDocumentsPath, GetHomePath, GetSharedDocumentsPath), the settings or an environment variable.",' + #10 +
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
    '      "id": "unknown-rule-id",' + #10 +
    '      "name": "Unbekannte Regelkennung",' + #10 +
    '      "description": "Ein lsp-ignore-Kommentar nennt eine Regelkennung, die es nicht gibt, und unterdrückt deshalb nichts. Die Meldung schlägt die ähnlichste bekannte Kennung vor (Tippfehler); ein sol' + 'cher Kommentar zählt nicht zusätzlich als unused-suppression."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "bidi-control",' + #10 +
    '      "name": "Bidirektionales Steuerzeichen",' + #10 +
    '      "description": "Bidirektionale Steuerzeichen können Code anders anzeigen, als er kompiliert wird (Trojan Source); auch in Formulardateien. Richtungsmarken in RTL-Text nur mit niedriger Konfidenz' + '."' + #10 +
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
    '      "description": "Ein uses-Eintrag verletzt die Importmatrix des Rollenkonzepts (Ausgabeartefakt, Feature, Rolle: Contract, Internals, Providers, Adapters, Composition, Hosting). Standardmäßig aus' + '; in atlas.json mit der Option \"prefixes\" einschalten. Genehmigte Ausnahmen stehen unter \"allow\" als \"Quelle -> Ziel\"-Globs.",' + #10 +
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
    '      "description": "Eine Contract-Unit deklariert im interface eine Klasse. Contracts enthalten nur Records, Interfaces, Aufzählungen und Ausnahmen. Standardmäßig aus; in atlas.json mit der Option \' + '"prefixes\" einschalten. Genehmigte Ausnahmen stehen unter \"allow\" als \"Unit.Typ\"-Globs.",' + #10 +
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
    '      "description": "TThread.Execute, TThread.CreateAnonymousThread oder TTask greift außerhalb von Synchronize oder Queue auf die VCL zu (Application, Screen, ShowMessage, MessageDlg …). Die VCL ist' + ' nicht threadsicher."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "lock-without-finally",' + #10 +
    '      "name": "Sperre ohne try/finally",' + #10 +
    '      "description": "Auf eine Sperre (TCriticalSection.Enter/Acquire, TMonitor.Enter, BeginRead/BeginWrite, TSpinLock.Enter, TMutex.Acquire, EnterCriticalSection oder ein Paar aus der Option lockPair' + 's) folgt kein try/finally mit der Freigabe. Eine Ausnahme lässt die Sperre gesetzt.",' + #10 +
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
    '      "description": "Eine Anweisung nach Exit, raise, Abort, Halt, Break, Continue oder goto wird nie ausgeführt. Meist ein Rest oder ein falsch gesetzter Sprung. Gemeldet wird nur die erste Anweisun' + 'g eines unerreichbaren Abschnitts."' + #10 +
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
    '      "description": "Ein Parameter wird im Rumpf der Routine nicht verwendet. Ausgenommen sind überschriebene und virtuelle Methoden, Ereignis-Handler, published-Methoden, Interface-Implementierungen' + ' und Callbacks.",' + #10 +
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
    '      "description": "Ein einer lokalen Variable zugewiesener Wert wird überschrieben oder die Routine endet, bevor er gelesen wird. Wie Compilerhinweis H2077.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "ignore",' + #10 +
    '          "description": "Namensmuster, die nie gemeldet werden (* und ?)."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "declared-not-implemented",' + #10 +
    '      "name": "Deklariert, aber nicht implementiert",' + #10 +
    '      "description": "Eine Methode ist in einer Klasse, einem Record oder Objekt deklariert, hat aber keinen Rumpf im implementation-Abschnitt. Der Compiler meldet das erst beim Kompilieren (E2065). E' + 'inen Rumpf gleichen Namens mit anderem Kopf meldet stattdessen signature-mismatch."' + #10 +
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
    '      "description": "Ein Setter weist an die eigene Property zu (Name := Value in SetName) oder ein Getter liest sie (Result := Name in GetName). Das ergibt eine Endlosrekursion und einen Stapelüberl' + 'auf zur Laufzeit; der Compiler schweigt. Schnellkorrektur: das Feld verwenden (das Feld aus der Property-Deklaration, sonst F und der Name, wenn die Klasse es hat). Früher recursive-property-accessor;' + ' Einstellungen und Unterdrückungen mit der alten Kennung wirken weiter."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-create-without-override",' + #10 +
    '      "name": "Komponentenkonstruktor ohne override",' + #10 +
    '      "description": "Ein TComponent-Nachfahre deklariert constructor Create(AOwner: TComponent) ohne override. Beim Laden aus der Formulardatei wird der virtuelle Konstruktor benutzt und dieser überg' + 'angen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "hides-virtual",' + #10 +
    '      "name": "Methode verdeckt virtuelle Methode",' + #10 +
    '      "description": "Eine Methode heißt wie eine virtuelle Methode eines Vorfahren, überschreibt sie aber weder noch führt sie sie neu ein (Compilerwarnung W1010)."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "virtual-instead-of-override",' + #10 +
    '      "name": "virtual statt override",' + #10 +
    '      "description": "Ein Nachfahre deklariert eine Methode als virtual, obwohl der Vorfahr schon eine virtuelle Methode mit derselben Signatur hat; das beginnt eine neue Kette statt zu überschreiben.' + '"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "captured-loop-variable",' + #10 +
    '      "name": "Erfasste Schleifenvariable",' + #10 +
    '      "description": "Eine anonyme Methode, die an eine verzögert ausführende API (TThread.Queue, TTask.Run …) geht, erfasst eine Variable, die sich vor dem Aufruf noch ändert, etwa die Variable einer' + ' for-in-Schleife. Delphi erfasst die Variable, nicht ihren Wert.",' + #10 +
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
    '      "description": "Ein überschriebenes Loaded, CreateParams, CreateWnd, Notification, SetParent, Destroy oder Paint einer Komponente ruft inherited nicht auf; die VCL überspringt dann ihre eigene A' + 'rbeit. Bei Paint ist die Konfidenz niedrig, weil TCustomControl.Paint nur den Rahmen im Designer zeichnet."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-default-mismatch",' + #10 +
    '      "name": "default passt nicht zum Konstruktor",' + #10 +
    '      "description": "Eine Eigenschaft gibt einen default-Wert an, der Konstruktor setzt das Feld aber auf ein anderes Literal. Werte gleich default speichert die DFM nicht, deshalb wird die Eigenscha' + 'ft falsch geladen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-missing-free-notification",' + #10 +
    '      "name": "Komponentenreferenz ohne FreeNotification",' + #10 +
    '      "description": "Eine Eigenschaft verweist auf eine andere Komponente, ihr Setter ruft aber FreeNotification nicht auf. Wird die andere Komponente freigegeben, bleibt ein ungültiger Zeiger zurück' + '. Im Konstruktor erzeugte Unterkomponenten sind ausgenommen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-setter-without-invalidate",' + #10 +
    '      "name": "Setter ohne Invalidate",' + #10 +
    '      "description": "Ein Setter ändert ein Feld, das Paint liest, ruft aber weder Invalidate noch Repaint, Refresh oder Changed auf. Das Steuerelement zeigt weiter den alten Zustand."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-fixed-pixels",' + #10 +
    '      "name": "Feste Pixelwerte",' + #10 +
    '      "description": "Paint oder Resize verwenden feste Pixelwerte, die über 96 dpi zu klein sind. Werte über ScaleValue oder MulDiv, 0, 1 und -1 sowie Faktoren von Multiplikationen und Divisionen wer' + 'den nicht gemeldet."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-hardcoded-color",' + #10 +
    '      "name": "Feste Farbe in Paint",' + #10 +
    '      "description": "Paint verwendet ein RGB-Literal, eine $00BBGGRR-Konstante oder einen TColor-Cast. Solche Farben ignorieren VCL-Styles; Systemfarben wie clBtnFace sind in Ordnung."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "form-field-without-object",' + #10 +
    '      "name": "Formularfeld ohne Objekt",' + #10 +
    '      "description": "Ein published-Komponentenfeld der Formularklasse hat kein Objekt in der .dfm/.fmx neben der Unit. Nach dem Laden bleibt das Feld nil. Felder außerhalb von published werden nicht ' + 'geprüft."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "form-object-without-field",' + #10 +
    '      "name": "Formularobjekt ohne Feld",' + #10 +
    '      "description": "Ein Objekt der Formulardatei hat kein Feld in der Formularklasse. Geerbte Objekte, Objekte in inline-Frames, namenlose Komponenten und Collection-Einträge werden übergangen. Die ' + 'Korrektur ergänzt das Feld."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "form-field-type-mismatch",' + #10 +
    '      "name": "Feldtyp weicht vom Formularobjekt ab",' + #10 +
    '      "description": "Der Typ des Felds weicht von der Klasse des Objekts in der Formulardatei ab. Ohne Quelltext der Klasse aus der Formulardatei wird nicht verglichen. Die Korrektur ändert den Feldt' + 'yp."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "security-command-injection",' + #10 +
    '      "name": "Befehlsinjektion",' + #10 +
    '      "description": "ShellExecute, ShellExecuteEx, CreateProcess oder WinExec erhält ein Argument, das mit +, Format oder Concat aus nicht konstanten Werten zusammengesetzt ist. Eingaben könnten weit' + 'ere Befehle einschleusen. Ohne Datenflussanalyse wird nur dieses einfache Muster erkannt (mittlere Konfidenz)."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "security-path-traversal",' + #10 +
    '      "name": "Pfad-Traversal",' + #10 +
    '      "description": "Ein Dateizugriff (TFileStream.Create, LoadFromFile, AssignFile, TFile.*) verwendet einen Pfad aus Eingabedaten (Text, ParamStr, Request) ohne Prüfung über TPath.GetFullPath. Expe' + 'rimentell, bis die Datenflussanalyse verfügbar ist."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "security-weak-crypto",' + #10 +
    '      "name": "Schwache Kryptografie",' + #10 +
    '      "description": "MD5, SHA-1, DES oder RC4 wird verwendet. Für Prüfsummen ist das in Ordnung, für Kennwörter und Signaturen nicht. Niedrige Konfidenz, mittlere, wenn die Anweisung ein Kennwort, Ge' + 'heimnis oder eine Signatur nennt."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "security-tls-verification-disabled",' + #10 +
    '      "name": "TLS-Zertifikatsprüfung abgeschaltet",' + #10 +
    '      "description": "Indy SSLOptions.VerifyMode := [], ein OnVerifyPeer-Handler, der immer True liefert, oder ein ValidateServerCertificate-Handler, der Accepted := True ohne Prüfung setzt."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "security-insecure-http",' + #10 +
    '      "name": "Unverschlüsselte http://-URL",' + #10 +
    '      "description": "Ein String enthält eine http://-URL. XML-Namensräume und Schema-URIs, Kommentare sowie localhost, 127.0.0.1 und [::1] sind ausgenommen. Die Korrektur ersetzt http:// durch https:' + '//."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "security-insecure-random",' + #10 +
    '      "name": "Random für sicherheitsrelevante Werte",' + #10 +
    '      "description": "Random wird einem Token, Kennwort, Salt, Nonce oder Schlüssel zugewiesen. Random ist vorhersagbar; einen kryptografischen Zufallsgenerator verwenden. Fehlendes Randomize behandel' + 't #153."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dfm-circular-datasource",' + #10 +
    '      "name": "Zirkuläre Master-Detail- bzw. DataSource-Verknüpfung",' + #10 +
    '      "description": "MasterSource/DataSource-Verknüpfungen der Formulardatei bilden einen Kreis (tblA → dsB → tblB → dsA → tblA). Das Öffnen der Datasets läuft in eine Rekursion oder zeigt keine stim' + 'migen Daten."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dfm-master-without-fields",' + #10 +
    '      "name": "Master-Detail ohne MasterFields",' + #10 +
    '      "description": "Ein Dataset hat MasterSource, aber keine MasterFields. Das Detail wird nicht gefiltert und zeigt alle Datensätze."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dfm-required-field-without-control",' + #10 +
    '      "name": "Pflichtfeld ohne sichtbares Eingabe-Control",' + #10 +
    '      "description": "Ein persistentes Feld mit Required = True ist an kein sichtbares datensensitives Control gebunden (ein Gitter ohne DataField zählt für alle Felder). Der Anwender kann es nicht fü' + 'llen, Post schlägt fehl."' + #10 +
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
    '      "description": "Eine Komponenten-Property in der Formulardatei erfüllt eine Regel aus dfmPropertyRules in atlas.json nicht (Klasse, Property, Bedingung, Wert). Nicht gespeicherte Properties zähl' + 'en mit ihrem default-Wert; Objekte aus dem Vorfahrenformular werden nur gemeldet, wenn dieses Formular den Wert selbst setzt. Die Schnellkorrektur setzt den Wert in der Formulardatei (fix: auto auch m' + 'it source.fixAll); der Befehl \"Eigenschaftsregeln anwenden\" korrigiert ein Formular, das Projekt oder die Gruppe mit Vorschau."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "foreign-form-control-access",' + #10 +
    '      "name": "Zugriff auf Controls eines anderen Formulars",' + #10 +
    '      "description": "Code greift über die globale Variable auf ein Feld eines Formulars oder Frames aus einer anderen Unit zu (Form2.Edit1.Text). Das koppelt die Units eng; besser eine Methode oder P' + 'roperty des Formulars nutzen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "security-sql-injection",' + #10 +
    '      "name": "SQL-Text aus zusammengesetzten Werten (SQL-Injection)",' + #10 +
    '      "description": "SQL.Text, SQL.Add, CommandText, ExecSQL oder Open erhalten Text, der per + oder Format aus Nicht-Konstanten zusammengesetzt ist. Benutzereingaben könnten SQL einschleusen. Parame' + 'ter verwenden (:Name, ParamByName). Konstanten, resourcestrings, IntToStr und QuotedStr zählen nicht; Benutzereingaben (TEdit.Text, TMemo.Lines) heben die Konfidenz auf hoch."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "slash-command",' + #10 +
    '      "name": "Schnellbefehl nicht ausgeführt",' + #10 +
    '      "description": "Eine Zeile, die mit /name beginnt, wurde nicht ausgeführt und steht noch im Code: Der Befehl ist unbekannt, abgeschaltet (slashCommands.disabled) oder passt an dieser Stelle nich' + 't. Die Meldung nennt den Grund. \"/ignore regel\" meldet sie auch, wenn diese Regel in der Zeile darunter nichts findet."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "empty-except",' + #10 +
    '      "name": "Leerer except-Block",' + #10 +
    '      "description": "Ein except-Block ohne Anweisung verschluckt jede Ausnahme. Ein Block, der nur einen Kommentar enthält, gilt als begründet und wird nicht gemeldet."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "interface-guid",' + #10 +
    '      "name": "Interface ohne GUID",' + #10 +
    '      "description": "Ein Interface deklariert keine GUID. Supports, as und QueryInterface brauchen eine. Die Konfidenz ist hoch, wenn das Interface in derselben Datei damit verwendet wird, sonst nied' + 'rig. Die Schnellkorrektur fügt eine neue GUID ein."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "duplicate-interface-guid",' + #10 +
    '      "name": "Zwei Interfaces mit derselben GUID",' + #10 +
    '      "description": "Zwei Interfaces der Datei deklarieren dieselbe GUID, meist nach dem Kopieren einer Deklaration. Supports und as verwechseln sie dann. Die Schnellkorrektur erzeugt eine neue GUID.' + '"' + #10 +
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
    '      "description": "Einer Variablen, einem Feld oder einer Property wird der eigene Wert zugewiesen. Gemeint ist meist ein anderer Wert, etwa ein Parameter oder ein anderes Feld. Verdeckt ein Parame' + 'ter oder eine lokale Variable ein gleichnamiges Feld (Name := Name), bietet Atlas Self.Name := Name als Korrektur an."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "for-high-to-low",' + #10 +
    '      "name": "for-Schleife zählt mit to abwärts",' + #10 +
    '      "description": "Die Schleife beginnt beim oberen Wert (High, Count - 1) und endet beim unteren, verwendet aber to. Sie läuft nie; gemeint war downto."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "exception-not-raised",' + #10 +
    '      "name": "Exception erzeugt, aber nicht ausgelöst",' + #10 +
    '      "description": "Ein Exception-Objekt wird als eigene Anweisung erzeugt. Ohne raise passiert nichts, und das Objekt bleibt als Speicherleck zurück."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "assert-side-effect",' + #10 +
    '      "name": "Assert mit Seiteneffekt",' + #10 +
    '      "description": "Das Argument von Assert verändert Daten (Inc, Dec, eine Try…-Funktion mit out-Parameter oder eine Methode aus der Option mutatingMethods). Mit {$C-} entfernt der Compiler den gan' + 'zen Aufruf samt Seiteneffekt.",' + #10 +
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
    '      "description": "IfThen ist eine Funktion: Beide Zweige werden vor dem Aufruf ausgewertet. Ein Nil-Zugriff oder Funktionsaufruf im nicht gewählten Zweig passiert trotzdem. Hohe Konfidenz, wenn ei' + 'n Zweig einen in der Bedingung geprüften Namen dereferenziert, mittlere bei einem Funktionsaufruf."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "random-without-randomize",' + #10 +
    '      "name": "Random ohne Randomize",' + #10 +
    '      "description": "Random wird verwendet, aber die Unit ruft nie Randomize auf; jeder Start liefert dieselbe Folge. Randomize steht oft in der .dpr, deshalb ist die Regel standardmäßig aus und hat ' + 'niedrige Konfidenz."' + #10 +
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
    '      "description": "Create wird auf einer Variablen statt auf der Klasse aufgerufen. Das legt kein neues Objekt an; mit nicht zugewiesener Variable stürzt es ab. Klassenreferenzen (class of …) werde' + 'n nicht gemeldet."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "format-without-settings",' + #10 +
    '      "name": "Formatierung abhängig vom Gebietsschema",' + #10 +
    '      "description": "Format mit %f, %n, %m, %g oder %e und Funktionen wie FloatToStr, StrToFloat oder DateToStr ohne TFormatSettings-Parameter verwenden das Gebietsschema des Benutzers (Dezimaltrenne' + 'r, Datumsformat). Für Dateien, Protokolle und Logs feste TFormatSettings übergeben. Format(''%d'', …) wird nicht gemeldet."' + #10 +
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
    '      "description": "Eine String-Variable wird in einer Schleife schrittweise verlängert. Delphi vergrößert Strings meist an Ort und Stelle, deshalb nur mit niedriger Konfidenz und standardmäßig aus;' + ' bei vielen Durchläufen ist TStringBuilder schneller."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "loop-invariant-call",' + #10 +
    '      "name": "Teurer Aufruf in der Schleifenbedingung",' + #10 +
    '      "description": "Die Bedingung von while und until wird bei jedem Durchlauf ausgewertet. Aufrufe wie Trim, Format oder FileExists und Eigenschaften wie Lines.Text werden dort jedes Mal neu berech' + 'net; besser einmal vor der Schleife. Die Grenzen von for werden nur einmal ausgewertet und nicht gemeldet. Standardmäßig aus."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "missing-begin-update",' + #10 +
    '      "name": "Hinzufügen in einer Schleife ohne BeginUpdate",' + #10 +
    '      "description": "Items.Add, Lines.Add und ähnliche Aufrufe in einer Schleife zeichnen das Steuerelement bei jedem Aufruf neu. Die Schleife mit BeginUpdate und try … finally EndUpdate umschließen.' + ' Standardmäßig aus."' + #10 +
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
    '      "description": "In einem with-Block ist unklar, zu welchem Objekt ein Bezeichner gehört, und ein neues Mitglied des with-Objekts ändert still die Bedeutung. Den Ausdruck ausschreiben oder eine l' + 'okale Variable verwenden."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-method-length",' + #10 +
    '      "name": "Methode zu lang",' + #10 +
    '      "description": "Die Methode hat mehr Codezeilen als der Grenzwert (Vorgabe 60). Leerzeilen, Kommentare, Compiler-Direktiven und lokale Routinen zählen nicht mit. Die Methode in kleinere aufteile' + 'n. Den Grenzwert setzt die Option max, z. B. \"rules\": {\"metric-method-length\": {\"max\": 80}}.",' + #10 +
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
    '      "description": "Die Methode verschachtelt if, case, Schleifen und try tiefer als der Grenzwert (Vorgabe 4). else if bleibt auf der Ebene seines if. Mit Exit oder Continue früh verlassen oder inn' + 'ere Teile in eigene Methoden auslagern. Den Grenzwert setzt die Option max.",' + #10 +
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
    '      "description": "Die zyklomatische Komplexität der Methode liegt über dem Grenzwert (Vorgabe 15). Sie beginnt bei 1 und steigt um 1 je if, while, repeat und for, je case-Zweig ohne else, je and/o' + 'r in einer Bedingung und je except on; ein except ohne on zählt einmal. Viele Pfade brauchen viele Tests. Den Grenzwert setzt die Option max.",' + #10 +
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
    '      "description": "Die kognitive Komplexität der Methode liegt über dem Grenzwert (Vorgabe 15). Nach SonarSource zählen if, case, Schleifen und except-Behandler 1 plus ihre Schachtelungsebene; else' + ', else if, goto und jede Folge gleicher logischer Operatoren zählen 1. Verschachtelter Code ist schwerer zu lesen als Code hintereinander. Den Grenzwert setzt die Option max.",' + #10 +
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
    '      "id": "todo-comment",' + #10 +
    '      "name": "Offener TODO-Kommentar",' + #10 +
    '      "description": "Ein Kommentar beginnt mit einer Marke für offene Arbeit: // TODO, // FIXME oder das Format der IDE-To-Do-Liste { TODO 1 -oPerson -cKategorie : Text }. Der Hinweis zeigt Marke, Pr' + 'iorität, Kategorie, Person und Text, damit offene Arbeit in der Problemliste erscheint. In der Vorgabe aus; in atlas.json einschalten, z. B. \"rules\": {\"todo-comment\": {\"severity\": \"hint\"}}. Er' + 'ledigte Einträge ({ DONE … }) meldet die Regel nie. Die Option keywords legt die Marken fest (Vorgabe [\"TODO\", \"FIXME\"]); sie gilt auch für get_todos und --todos.",' + #10 +
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
    '      "description": "Jede an RegisterComponents übergebene Klasse braucht in einer per {$R} eingebundenen .dcr oder .res eine Bitmap mit dem Klassennamen in Großbuchstaben. Ab Delphi 11 werden zusätz' + 'lich die Größen 16, 24 und 32 px (NAME16, NAME24, NAME32) erwartet. Ohne lesbare eingebundene Ressourcendatei schweigt die Regel."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unresolved-identifier",' + #10 +
    '      "name": "Nicht deklarierter Bezeichner",' + #10 +
    '      "description": "Ein Bezeichner in einer Anweisung ist weder in der Unit noch in den eingebundenen Units deklariert (wie Compilerfehler E2003). Geprüft beim Tippen, ohne Compiler; with-Blöcke, as' + 'm und anonyme Methoden werden übersprungen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "deprecated-symbol",' + #10 +
    '      "name": "Veraltetes Symbol",' + #10 +
    '      "description": "Eine Routine, ein Typ, eine Konstante oder ein Mitglied mit deprecated, platform oder experimental wird verwendet (wie Compilerwarnungen W1000, W1002 und W1003). Der Editor strei' + 'cht den Namen durch; die Meldung nennt den Grund aus deprecated ''Grund''. Die Deklaration und der Kopf ihrer Implementierung werden nicht gemeldet."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "implicit-package-import",' + #10 +
    '      "name": "Implizit eingebundene Unit",' + #10 +
    '      "description": "In einem Package (.dpk) verwendet eine Unit aus contains eine Unit, die weder in contains steht noch von einem Package aus requires geliefert wird. Der Compiler zieht sie implizi' + 't hinein (W1033), was später zu doppelten Units führt, wenn ein anderes Package sie ebenfalls enthält. Die Schnellkorrektur nimmt die Unit in contains auf."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "type-used-before-declaration",' + #10 +
    '      "name": "Typ vor seiner Deklaration benutzt",' + #10 +
    '      "description": "Eine Klasse, ein Interface, ein Record oder ein anderer Typ wird in einer Typdeklaration (Feld, Parameter, Ergebnis, Property, generisches Argument, class of) benutzt, ist aber e' + 'rst weiter unten im selben Gültigkeitsbereich deklariert (wie Compilerfehler E2003). Vorfahren, Aliase und Zeigertypen werden nicht gemeldet. Schnellkorrekturen: Forward-Deklaration am Anfang des type' + '-Blocks ergänzen, type-Blöcke zusammenlegen (const-, var- und label-Abschnitte dazwischen wandern vor den ersten Block) oder einen Record vor seinen ersten Verwender verschieben; ohne sichere Korrektu' + 'r nennt die Meldung den Grund."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unneeded-forward-declaration",' + #10 +
    '      "name": "Überflüssige Forward-Deklaration",' + #10 +
    '      "description": "Eine Forward-Deklaration, deren Typ im selben type-Block vor der vollständigen Deklaration nicht benutzt wird. Schnellkorrektur: entfernen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "field-not-freed",' + #10 +
    '      "name": "Feld erzeugt, aber nie freigegeben",' + #10 +
    '      "description": "Ein Objektfeld, das der Konstruktor (oder eine von ihm aufgerufene private Methode) mit TKlasse.Create erzeugt, wird in der Klasse nirgends freigegeben (kein Free, FreeAndNil, De' + 'stroy oder DisposeOf): ein Speicherleck. Ausgenommen sind Komponenten mit einem Owner ungleich nil, Interface- und Record-Felder sowie die Klassen aus der Option ignoreTypes; TObjectList- und TObjectD' + 'ictionary-Felder sind normale Felder. Konfidenz mittel. Schnellkorrekturen: das Feld im Destruktor freigeben oder alle eigenen Objekte der Klasse freigeben; ein fehlender Destruktor wird mit override ' + 'und inherited angelegt. Die Freigaben stehen vor inherited in umgekehrter Erzeugungsreihenfolge, als Free oder FreeAndNil (refactoring.freeFieldsStyle). Bis #918 hieß die Regel owned-field-not-freed; ' + 'Einstellungen und Unterdrückungen mit dieser Kennung wirken weiter.",' + #10 +
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
    '      "description": "Ein im Konstruktor erzeugtes, nicht freigegebenes Objektfeld wird auch zurückgegeben (Result := FFeld, Exit(FFeld)), an eine Property eines anderen Objekts oder an dessen Add…, I' + 'nsert…, Register…, Attach…, Push oder Enqueue übergeben, ohne Create zugewiesen oder ist über eine Property (write FFeld) schreibbar. Ob die Klasse das Objekt noch besitzt, entscheidet der Entwickler;' + ' deshalb gibt es keine Schnellkorrektur."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "operator-precedence",' + #10 +
    '      "name": "Vorrang von not übersehen",' + #10 +
    '      "description": "In Pascal bindet not stärker als in und Vergleiche: not X in Menge heißt (not X) in Menge, not A = B heißt (not A) = B, bei Ganzzahlen wird not bitweise. Die Regel meldet diese F' + 'ormen, wenn der deklarierte Typ des Operanden zeigt, dass es nicht gemeint sein kann (kein Boolean). Schnellkorrektur: Klammern setzen, not (X in Menge)."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "empty-statement",' + #10 +
    '      "name": "Leere Anweisung nach then, do oder else",' + #10 +
    '      "description": "Ein Semikolon direkt nach then, do oder else beendet die Anweisung: Die folgende Zeile läuft dann immer bzw. die Schleife dreht leer. Ein leerer Block begin … end nach then, do o' + 'der else wird ebenfalls gemeldet, außer er enthält einen erklärenden Kommentar (Option allowCommented). Ein Semikolon direkt vor end, until, except oder finally ändert nichts und bleibt unbeanstandet.' + ' Schnellkorrektur: Semikolon entfernen.",' + #10 +
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
    '      "description": "for I := 0 to Liste.Count oder to Length(A) über nullbasierte Listen und Arrays greift im letzten Durchlauf hinter das Ende, wenn der Rumpf Liste[I] bzw. A[I] liest. Bei einsbasi' + 'erten Strings umgekehrt: S[0] und for I := 0 to Length(S) greifen vor das erste Zeichen; {$ZEROBASEDSTRINGS ON} wird beachtet. Schnellkorrektur: - 1 ergänzen bzw. High(A) verwenden, bei Strings Low(S)' + ' und High(S). Die Option countNames nennt die Namen, die eine Anzahl liefern.",' + #10 +
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
    '      "description": "Delete, Remove, Add oder eine andere Methode aus der Option mutatingMethods wird auf der Liste aufgerufen, über die die Schleife gerade vorwärts per Index oder mit for … in läuft' + '. Vorwärts überspringt Delete das nächste Element und läuft über das Ende, Add wird nicht mehr durchlaufen und Insert liefert dasselbe Element zweimal; mit for … in wirft die RTL eine Exception. Ein B' + 'reak oder Exit direkt nach dem Aufruf beendet die Schleife und bleibt still, downto-Schleifen ebenso. Schnellkorrektur bei Indexschleifen: rückwärts mit downto; bei for … in die Elemente sammeln und d' + 'ie Liste nach der Schleife ändern.",' + #10 +
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
    '      "description": "Nach X.Free, X.Destroy, X.DisposeOf, FreeAndNil(X) oder Dispose(X) wird X ohne neue Zuweisung wieder benutzt: Methode, Feld, Index oder X^, with X, nach Free auch Assigned(X) (im' + 'mer True) oder ein zweites Free. Die Regel folgt dem Datenfluss der Routine; eine Zuweisung an X, die Übergabe von X an eine Routine, @X und nach FreeAndNil eine Abfrage auf nil beenden den Weg, Wege ' + 'nur über eine mögliche Ausnahme bleiben aus. Konfidenz hoch, wenn Freigabe und Zugriff im selben Block nacheinander stehen, sonst mittel. Keine automatische Korrektur; die Aktion springt zur Freigabe.' + '"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "deref-before-nil-check",' + #10 +
    '      "name": "Erst benutzt, dann auf nil geprüft",' + #10 +
    '      "description": "X wird dereferenziert (X.Feld, X.Methode, X^) und erst danach mit Assigned(X), X <> nil oder X = nil geprüft. Entweder ist die Prüfung überflüssig oder der Zugriff davor kann kna' + 'llen. Gemeldet wird nur, wenn jeder Weg zur Prüfung durch den Zugriff führt und X vorher nicht geprüft wurde; eine neue Zuweisung, die Übergabe von X an eine Routine und bei Feldern und globalen Varia' + 'blen jeder Aufruf dazwischen beenden den Weg. Konfidenz mittel. Ist die Prüfung ein if ohne else direkt nach dem Zugriff im selben Block, zieht die Schnellkorrektur den Zugriff hinein."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "field-free-without-nil",' + #10 +
    '      "name": "Feld freigegeben, Verweis bleibt stehen",' + #10 +
    '      "description": "FFeld.Free in einer Methode außerhalb des Destruktors, und ein Weg zum Ende der Methode setzt das Feld nicht neu. Ein späterer Zugriff oder ein zweites Free trifft freigegebenen ' + 'Speicher. Neu setzt eine Zuweisung oder der Aufruf einer Methode derselben Klasse, die das Feld zuweist. Felder sind die der Klassendeklaration in der Unit. Ausgenommen sind Destruktoren, Methoden mit' + ' [TearDown] oder [TearDownFixture], Methoden, die nur aus diesen aufgerufen werden, und die Methoden aus der Option ignoreMethods. Konfidenz mittel. Schnellkorrektur: FreeAndNil(FFeld).",' + #10 +
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
    '      "description": "Ein Konstruktor oder ein override von Destroy, AfterConstruction oder BeforeDestruction ruft inherited nicht auf, in jeder Klasse, deren Vorfahr nicht TObject ist. Konstruktoren ' + 'werden nur gemeldet, wenn ein Vorfahr einen eigenen Konstruktor deklariert (Datei, Index oder bekannte RTL-/VCL-Klasse) und der Konstruktor keinen anderen Konstruktor derselben Klasse aufruft. Bei Kom' + 'ponenten meldet Destroy nur component-missing-inherited. Konfidenz hoch. Schnellkorrektur: inherited; am Ende von Destroy und BeforeDestruction, am Anfang von Konstruktoren und AfterConstruction; ein ' + 'Konstruktor mit Parametern ohne override bekommt inherited Create;.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "methods",' + #10 +
    '          "description": "Geprüfte Methoden; Create steht für alle Konstruktoren, deren Name mit Create beginnt."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "destroy-called-directly",' + #10 +
    '      "name": "Destroy statt Free aufgerufen",' + #10 +
    '      "description": "Obj.Destroy wird direkt als Anweisung aufgerufen. Ist Obj nil, knallt der Aufruf; Free prüft vorher auf nil und ist der übliche Weg, ein Objekt freizugeben. inherited Destroy und' + ' Aufrufe eines Destruktors mit Argumenten sind ausgenommen. Konfidenz hoch. Schnellkorrektur: aus Destroy wird Free."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "managed-type-raw-memory",' + #10 +
    '      "name": "FillChar, Move oder GetMem auf verwaltete Typen",' + #10 +
    '      "description": "FillChar, ZeroMemory, FillMemory, Move, CopyMemory, GetMem oder FreeMem auf eine Variable, deren Typ Strings, Interfaces, dynamische Arrays oder Variants enthält (Records, statis' + 'che Arrays und Aliasse werden in der Datei und im Index aufgelöst). Referenzzähler werden überschrieben oder übergangen: Lecks, doppelte Freigabe, Zugriffsverletzungen. Geprüft werden nur einfache Var' + 'iablen (X, @X, P^); Array-Elemente wie S[1] und Typen, die sich nicht auflösen lassen, bleiben still. Konfidenz hoch. Schnellkorrekturen: aus FillChar(X, SizeOf(X), 0) wird X := Default(T), aus Move(A' + ', B, SizeOf(T)) wird B := A, aus GetMem(P, SizeOf(T)) wird New(P) und aus FreeMem(P) wird Dispose(P); sonst helfen Initialize und Finalize."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "threadvar-managed",' + #10 +
    '      "name": "threadvar mit verwaltetem Typ",' + #10 +
    '      "description": "Delphi finalisiert threadvar-Variablen nicht. Ein String, Interface, dynamisches Array oder Variant in einer threadvar (auch in einem Record oder statischen Array) leckt in jedem' + ' Thread, der endet. Typen werden in der Datei und im Index aufgelöst. Konfidenz hoch. Keine Schnellkorrektur: den Wert am Thread-Ende freigeben (etwa in TThread.Execute auf '''' bzw. nil setzen) oder st' + 'attdessen einen Zeiger bzw. Puffer fester Größe ablegen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "pchar-of-temporary",' + #10 +
    '      "name": "PChar auf einen temporären String",' + #10 +
    '      "description": "PChar (PWideChar, PAnsiChar) eines temporären Strings, etwa einer Verkettung mit einem String (S + ''.bak'') oder eines Funktionsergebnisses (IntToStr(N)), wird in einer Variablen,' + ' einem Feld oder Result gemerkt oder an PostMessage, PostThreadMessage, SendNotifyMessage oder SendMessageCallback übergeben (auch hinter LPARAM(…)). Der temporäre String wird nach der Anweisung freig' + 'egeben, der Zeiger zeigt dann ins Leere. Die Übergabe an einen gewöhnlichen Aufruf wie CopyFile ist in Ordnung. Konfidenz hoch. Schnellkorrektur für lokale Variablen: das Zwischenergebnis in eine Inli' + 'ne-String-Variable legen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "out-param-read",' + #10 +
    '      "name": "out-Parameter gelesen, bevor er gesetzt ist",' + #10 +
    '      "description": "Ein out-Parameter wird auf einem Weg durch den Kontrollfluss gelesen, bevor die Routine ihn setzt. Bei verwalteten Typen (string, Interfaces, dynamische Arrays, Variant) hat der ' + 'Aufrufer ihn schon geleert, der alte Wert ist weg; bei anderen Typen ist der Wert undefiniert. Gemeint war meist var. Verwendungen, denen der Kontrollflussgraph nicht folgen kann (Übergabe an eine Rou' + 'tine, Setzen eines Felds, @Param), bleiben still. Konfidenz hoch. Schnellkorrektur: aus out wird var in Implementierung und Deklaration."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "stringlist-unsorted",' + #10 +
    '      "name": "Find oder Duplicates auf einer unsortierten TStringList",' + #10 +
    '      "description": "Find auf einer TStringList oder THashedStringList, die in der Unit erzeugt, aber nie sortiert wird: Find sucht binär und liefert auf einer unsortierten Liste falsche Ergebnisse. ' + 'Ebenso wirkt Duplicates := dupIgnore oder dupError nur bei sortierten Listen. Als sortiert gelten Sorted := True (oder jeder Wert außer False), Sort, CustomSort, Create(Duplicates, True, ...) und with' + ' Liste do. Eine Liste, die an eine Routine übergeben oder einer anderen Variablen zugewiesen wird, bleibt still. Lokale Variablen gelten je Routine, Felder in der ganzen Unit. Konfidenz mittel. Schnel' + 'lkorrekturen: Sorted := True nach dem Erzeugen (nicht, wenn die Liste Insert, Move oder Exchange benutzt, die bei sortierten Listen eine Ausnahme auslösen) und bei if Liste.Find(S, I) then die Form I ' + ':= Liste.IndexOf(S) mit if I >= 0."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "writeln-in-gui-app",' + #10 +
    '      "name": "Writeln in einem Programm ohne Konsole",' + #10 +
    '      "description": "Write, Writeln, Read oder Readln auf die Standardein- oder -ausgabe in einem Programm ohne Konsole: zur Laufzeit löst Writeln EInOutError aus (E/A-Fehler 105), Readln E/A-Fehler ' + '104. Die Anwendungsart kommt aus DCC_ConsoleTarget der .dproj und {$APPTYPE CONSOLE} der .dpr (auch in {$IFDEF}); Units werden nur geprüft, wenn sie zum geladenen Projekt gehören, eine .dpr ohne Proje' + 'kt für sich. Bibliotheken und Packages bleiben still. Ausgenommen sind Aufrufe mit einer Textdatei als erstem Argument, Aufrufe unter if IsConsole, gleichnamige Routinen der Unit und Read/Write in Met' + 'hoden (TStream.Read). Konfidenz hoch. Schnellkorrektur für Write und Writeln: Ersatz durch OutputDebugString(PChar(...)) und Winapi.Windows im uses; Zahlen und Boolean über IntToStr, FloatToStr und Bo' + 'olToStr. Die Option replacement setzt ein anderes Ziel, z. B. Log.Info oder Logger.Log(TLogLevel.Info, %s). Keine Korrektur bei Breitenangaben (X:5) oder Argumenten unbekannten Typs.",' + #10 +
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
    '      "description": "raise in einem Destruktor (auch class destructor), das kein except im Destruktor abfängt. Die Ausnahme bricht die Freigabe ab: inherited Destroy läuft nicht mehr, das Objekt blei' + 'bt halb freigegeben, und in einem finally des Aufrufers überdeckt sie die ursprüngliche Ausnahme. Ein raise im try-Teil eines try..except ist abgefangen; raise im except- oder finally-Teil, auch ein e' + 'rneutes raise;, wird gemeldet. Eingebettete Routinen und anonyme Methoden sind ausgenommen. Aufrufen, die ihrerseits auslösen, folgt die Regel nicht. Konfidenz hoch. Keine Schnellkorrektur: den Zustan' + 'd protokollieren oder ohne Ausnahme freigeben."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "duplicate-condition",' + #10 +
    '      "name": "Doppelte Bedingung oder gleiche Zweige",' + #10 +
    '      "description": "Dieselbe Bedingung zweimal in einer if … else if-Kette (der spätere Zweig wird nie erreicht), gleiche then- und else-Zweige, derselbe Operand zweimal in einer and-, or- oder xor-' + 'Kette und Vergleiche eines Ausdrucks mit sich selbst (X = X, X < X). Meist ein Kopierfehler. Verglichen werden die Token ohne Leerraum, Kommentare und Groß-/Kleinschreibung. Ketten mit Aufrufen, die Z' + 'ustand ändern können (alles außer SameText, Length, Assigned, Pos und ähnlichen reinen Funktionen, dazu Read, Next, Pop, Random …), bleiben still, ebenso Gleitkomma-Vergleiche mit sich selbst (NaN-Prü' + 'fung X <> X) und Vergleiche über Klassenmitglieder wie TFoo.Shared = TFoo.Shared. Konfidenz hoch. Keine Schnellkorrektur; die Aktion springt zum ersten Vorkommen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "case-missing-enum-value",' + #10 +
    '      "name": "case über Aufzählung ohne alle Werte",' + #10 +
    '      "description": "Ein case über einen Aufzählungstyp ohne else deckt nicht alle Werte ab; ein später ergänzter Wert fällt still durch. Die Meldung nennt die fehlenden Werte. Den Typ des Selektors ' + '(Variable, Parameter, Feld oder Kette A.B) liefert die Namensauflösung, die Werte der Index bzw. die Unit selbst; Aliase werden verfolgt. Bereiche (bsNeu..bsBezahlt) und Listen zählen als vorhanden. S' + 'elektoren mit Aufrufen, Ganzzahlen und unbekannte Typen bleiben still. Mit der Option requireElse wird auch ein case mit else gemeldet. Konfidenz hoch. Schnellkorrektur „Fehlende Werte ergänzen (n)“ e' + 'rgänzt leere Zweige in Deklarationsreihenfolge vor else bzw. end, mit Typpräfix, wenn die Marken einen tragen ({$SCOPEDENUMS ON}).",' + #10 +
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
    '      "description": "Verallgemeinert lock-without-finally (dessen Sperrpaare dort bleiben) auf andere Paare: DisableControls/EnableControls, BeginUpdate/EndUpdate, FindFirst/FindClose (auch in if Fin' + 'dFirst(...) = 0 then begin ... end), Reset, Rewrite oder Append/CloseFile, GetMem oder AllocMem/FreeMem und Screen.Cursor := ... mit einem späteren Screen.Cursor := .... Gemeldet wird, wenn das Schlie' + 'ßen später ungeschützt in derselben Anweisungsliste steht und mindestens eine Anweisung dazwischen liegt; eine Exception dort lässt den Zustand hängen. Beide Aufrufe müssen denselben Empfänger bzw. da' + 'sselbe Argument haben. Überlappende Paare meldet die Regel zusammen. Konfidenz hoch. Schnellkorrektur: die Anweisungen dazwischen in try/finally mit den schließenden Aufrufen einschließen, wenn diese ' + 'direkt aufeinander folgen. Die Option pairs ergänzt eigene Paare.",' + #10 +
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
    '      "description": "Application.ProcessMessages in einer for-, while- oder repeat-Schleife oder direkt in einem Ereignis-Handler (Methode mit Parameter Sender) öffnet die Tür für Wiedereintritt: Der' + ' Benutzer klickt erneut, schließt das Formular oder startet den Vorgang doppelt. Aufrufe in anonymen Methoden überlässt die Regel thread-vcl-access; ProcessMessages anderer Objekte zählt nicht. Konfid' + 'enz mittel, keine Schnellkorrektur: die Arbeit in einen Thread oder TTask auslagern oder den Auslöser bis zum Ende sperren. Die Option allowIn nennt Methoden, in denen es erlaubt ist.",' + #10 +
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
    '      "description": "StrToInt, StrToInt64, StrToFloat, StrToDate, StrToDateTime oder StrToCurr direkt auf einer Benutzereingabe (Edit.Text, Grid.Cells[...], Memo.Lines[...], auch in Trim) außerhalb d' + 'es try-Teils eines try/except. Eine Fehleingabe löst EConvertError mit englischer Meldung aus. try/finally gilt nicht als Schutz. Konfidenz mittel. Schnellkorrektur für X := StrToInt(Edit.Text); als e' + 'igene Anweisung, wenn X eine Variable oder ein Feld des passenden Typs ist: if not TryStrToInt(Edit.Text, X) then raise EConvertError.Create(''X ist keine Zahl''). format-without-settings meldet zusätzl' + 'ich landesabhängige Umwandlungen ohne TFormatSettings. Die Optionen functions und sources wählen die geprüften Umwandlungen und die Eigenschaften, die als Eingabe gelten.",' + #10 +
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
    '      "description": "Dict[Key] bzw. Dict.Items[Key] wird auf einem TDictionary oder TObjectDictionary (auch über einen Typalias der Datei) gelesen, obwohl weder ContainsKey noch TryGetValue denselben' + ' Schlüssel vorher in der Routine geprüft hat. Still bleibt die Regel, wenn die Routine das Dictionary vorher selbst füllt (Add, AddOrSetValue, TryAdd, Dict[K] := ...) oder der Schlüssel aus Keys bzw. ' + 'den Paaren stammt (for K in Dict.Keys, Namen := Dict.Keys.ToArray, for Pair in Dict mit K := Pair.Key). Fehlt der Schlüssel, folgt EListError. Konfidenz mittel. Schnellkorrektur für X := Dict[Key]; al' + 's eigene Anweisung, wenn X eine Variable vom Wertetyp ist: if not Dict.TryGetValue(Key, X) then X := 0 (bzw. '''', False, Default(T))."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "shadowed-name",' + #10 +
    '      "name": "Lokaler Name verdeckt Feld oder Property",' + #10 +
    '      "description": "Ein Parameter, eine lokale oder Inline-Variable heißt wie ein Feld oder eine Property der Klasse (auch geerbt und dort sichtbar, aufgelöst über die Datei und den Symbolindex) ode' + 'r wie eine globale Variable der Unit, die vor der Routine deklariert ist. In Formularmethoden besonders tückisch: Caption, Name, Tag, Left. Steht die VCL nicht im Index, kennt die Regel die Mitglieder' + ' von TComponent und TControl, wenn die Vorfahrenkette an einer VCL-Grundklasse endet. Parameter von Ereignis-Handlern (mit Sender) bleiben außen vor, weil der Ereignistyp die Signatur vorgibt. Konfide' + 'nz hoch. Schnellkorrektur: in der Routine in AName (Parameter, auch in der Deklaration) bzw. LName (lokale Variable) umbenennen. Die Option ignore nennt Namensmuster, die nie gemeldet werden (Vorgabe ' + 'Sender, Value).",' + #10 +
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
    '      "description": "if B then X := True else X := False (auch mit begin/end und vertauschten Werten), if B then Exit(True) else Exit(False) sowie if B then Exit(True); gefolgt von Exit(False); lasse' + 'n sich direkt schreiben. Ergänzt bool-compare. Konfidenz hoch. Schnellkorrektur: X := B, X := not B bzw. Exit(B); Verneinungen werden vereinfacht (aus not B wird B), zusammengesetzte Bedingungen einge' + 'klammert. Ohne Korrektur, wenn Kommentare im if stehen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "case-insensitive-compare",' + #10 +
    '      "name": "Vergleich über UpperCase oder LowerCase",' + #10 +
    '      "description": "UpperCase(A) = UpperCase(B), LowerCase(A) <> ''x'', AnsiUpperCase(...) oder A.ToUpper = B.ToUpper erzeugt zwei Strings für einen Vergleich. SameText (AnsiSameText bei den Ansi-Funk' + 'tionen und den Unicode-String-Helfern) ist kürzer und schneller. Ein Literal zählt nur, wenn die Umwandlung es nicht ändert; UpperCase(A) = LowerCase(B) und UpperCase(A) = ''ja'' bleiben unberührt, weil' + ' das andere Fehler sind. Ersetzt nicht die String-Helper-Modernisierung aus #71. Konfidenz hoch. Schnellkorrektur: SameText(A, B) bzw. not SameText(A, B)."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "magic-number",' + #10 +
    '      "name": "Zahl ohne Namen im Code",' + #10 +
    '      "description": "Zahlenliterale (dezimal, $hex, Gleitkomma, mit Vorzeichen) in Anweisungen, außerhalb von const-Abschnitten, Typen, Array-Grenzen und Teilbereichen. Erlaubte Werte sind einstellba' + 'r; DFM-Koordinaten und Tests lassen sich über exclude ausnehmen. Standard aus und niedrige Konfidenz: Treffer erscheinen, wenn die Regel eingeschaltet und minConfidence low ist. Schnellkorrektur: Kons' + 'tante einführen (#50) im const-Abschnitt der Routine.",' + #10 +
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
    '      "description": "Zeilen über der Grenze max (Vorgabe 120 Zeichen, passend zu den Linealen aus #710). Tabs zählen bis zur nächsten Tabstelle nach format.indentSize. Zeilen, die nur wegen eines Str' + 'ings oder, mit ignoreComments, eines Kommentars zu lang sind, werden nicht gemeldet. Zeilen über 1023 Zeichen meldet die Regel unabhängig von max immer als Fehler, weil der Compiler dort abbricht (F20' + '69). Standard aus. Schnellkorrektur: Zeile umbrechen hinter Kommas bzw. vor zweistelligen Operatoren, wenn die Stücke danach passen.",' + #10 +
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
    '      "description": "Die Klasse hat mehr Member als der Grenzwert (Vorgabe 40): Feldnamen, Methoden, Properties mit eigenem Typ und class var. Properties, die nur die Sichtbarkeit anheben (property A' + 'lign;), und geschachtelte Typen zählen nicht; eine geschachtelte Klasse wird für sich gemessen. Erscheint auch in der Metrik-Linse über der Klasse. Die Klasse aufteilen oder Teile in Hilfsklassen ausl' + 'agern; „Klasse in eigene Unit verschieben“ (#103) hilft, wenn auch die Unit voll ist.",' + #10 +
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
    '      "description": "Die Unit hat mehr Zeilen als der Grenzwert (Vorgabe 2000), gezählt bis zum abschließenden end. Gemessen werden nur Units, keine Programme oder Packages. Erscheint auch in der Met' + 'rik-Linse über dem Unit-Namen. Klassen mit „Klasse in eigene Unit verschieben“ (#103) auslagern.",' + #10 +
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
    '      "description": "Die Unit bindet mehr Units ein als der Grenzwert (Vorgabe 30), interface und implementation zusammen. Der Befund steht auf dem ersten uses. Programme und Bibliotheken werden nich' + 't geprüft, weil ihr uses die Units des Projekts aufzählt. Erscheint auch in der Metrik-Linse über uses. Viele Abhängigkeiten heißen meist, dass die Unit zu viel tut; „Klasse in eigene Unit verschieben' + '“ (#103) teilt sie.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "max",' + #10 +
    '          "description": "Höchstzahl der Units in allen uses-Klauseln."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "public-field",' + #10 +
    '      "name": "Öffentliches Feld",' + #10 +
    '      "description": "Felder im public- oder published-Abschnitt einer Klasse. Der Abschnitt ohne Sichtbarkeitswort zählt nur bei Klassen ohne Vorfahren oder mit TObject, weil der Formulardesigner dor' + 't seine Felder anlegt. Records sind ausgenommen, außer mit includeRecords; class var wird nicht gemeldet. Standard aus. Schnellkorrektur: Feld kapseln legt das Feld als FName in einen private-Abschnit' + 't am Ende der Klasse und ergänzt im alten Abschnitt property Name read FName write FName; Zugriffe von außen bleiben gültig.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "includeRecords",' + #10 +
    '          "description": "Auch Felder von Records melden."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "global-variable",' + #10 +
    '      "name": "Globale Variable im interface",' + #10 +
    '      "description": "var oder threadvar im interface-Teil einer Unit: Jede Unit, die sie einbindet, kann den Wert lesen und ändern. Die Formularvariable des Designers (frmHaupt: TfrmHaupt, bei Nachfa' + 'hren von TForm, TFrame, TDataModule oder jeder Klasse einer Unit mit Formulardatei) ist ausgenommen, außer mit includeFormVariables. Standard aus. Die Variable in den implementation-Teil verschieben u' + 'nd eine Funktion oder Property anbieten.",' + #10 +
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
    '      "description": "Mindestens minLines aufeinanderfolgende Kommentarzeilen (// je Zeile oder ein mehrzeiliger { }-Kommentar), die sich als Anweisungen, Deklarationen oder Klassenmitglieder parsen l' + 'assen. Prosa am Anfang und Ende des Blocks bleibt außen vor, mindestens die Hälfte der Zeilen muss nach Code aussehen (;, :=, begin, end, then, do). XMLDoc (///) und Kommentare vor dem ersten Token (L' + 'izenzköpfe) meldet die Regel nie. Sicherheit mittel. Die Versionsverwaltung bewahrt den alten Code auf; die Korrektur entfernt die Zeilen.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "minLines",' + #10 +
    '          "description": "Mindestzahl aufeinanderfolgender auskommentierter Codezeilen."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "queue-nil-in-package",' + #10 +
    '      "name": "TThread.Queue(nil, …) in einem Package",' + #10 +
    '      "description": "TThread.Queue(nil, …) oder TThread.ForceQueue(nil, …) in einer Unit eines Design-Time- oder Laufzeit-Packages: Der Eintrag gehört keinem Thread, beim Entladen des Packages räumt ' + 'ihn niemand weg, und CheckSynchronize ruft ihn womöglich danach in fremdem Speicher auf. Package-Units erkennt die Regel über die .dpk bzw. .dproj des geladenen Projekts (eine .dpk ohne Projekt für si' + 'ch). Eine Zeile mit dem Kommentar aus okMarker (Vorgabe mainthread-ok) ist ausgenommen. Sicherheit hoch. Korrektur: auf den Wrapper aus der Option wrapper umschreiben (Vorgabe TAtlasMainThread.Queue, ' + 'bei ForceQueue ForceQueue); mit Klammer steht der Text so vor den übrigen Argumenten. ForceQueue mit Verzögerung bekommt keine Korrektur. Der Kommandozeilen-Linter liest die .dpk-Dateien unter dem gep' + 'rüften Ordner. Leistet für jedes Plugin-Projekt dasselbe wie Tools/Check-MainThreadQueue.ps1; das Skript bleibt für Prüfungen ohne Atlas-Server.",' + #10 +
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
    '      "description": "AddNotifier an IOTAServices, IOTAEditorServices, IOTAModule usw. (oder ein anderes Paar aus registerPairs), dessen Index nie an RemoveNotifier geht: Der Aufruf steht als Anweisun' + 'g ohne Zuweisung, oder die Variable, der er zugewiesen wird, erhält in der Unit kein RemoveNotifier (in finalization, im Destruktor oder in Destroyed). Die IDE ruft den Notifier dann nach dem Entladen' + ' des Packages in fremdem Speicher auf. Register…-Aufrufe in der Prozedur Register sind ausgenommen: Diese Wizards entfernt die IDE selbst. Sicherheit mittel. Korrektur in Methoden: Index in ein Feld l' + 'egen (FNotifierIndex im private-Abschnitt) und RemoveNotifier im Destruktor ergänzen, der bei Bedarf angelegt wird; in Prozeduren der Unit: globale Variable mit -1 und RemoveNotifier in finalization. ' + 'Keine Korrektur, wenn der Empfänger ein Parameter oder eine lokale Variable ist.",' + #10 +
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
    '      "description": "Eine [Test]- oder [TestCase]-Methode, die keine Prüfung aufruft, weder selbst noch über Methoden derselben Klasse oder Routinen der Unit: Sie ist immer grün. Als Prüfung zählen A' + 'ufrufe nach assertPatterns (Vorgabe Assert.*, WillRaise*, Check*), System.Assert und Aufrufe an Klassen mit Assert im Namen (TRuleAssert.Reports). Tests mit [WillRaise] oder [Ignore] bleiben still. Si' + 'cherheit hoch. Korrekturen: Assert.Pass als Platzhalter einfügen oder zur Methode springen.",' + #10 +
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
    '      "description": "FOnChange(Self) oder OnChange(Self) wird in einer Methode der Klasse aufgerufen, ohne dass Assigned(FOnChange) oder FOnChange <> nil den Aufruf schützt: Ohne Handler folgt eine Z' + 'ugriffsverletzung. Ereignisse sind Felder und Properties der Klasse mit Methodenzeiger- oder Referenztyp (procedure … of object, reference to …, TNotifyEvent, TProc/TFunc, Typen auf Event, prozedurale' + ' Typen der Unit oder des Index). Schutz: der then-Zweig einer Bedingung mit Assigned (auch while), der else-Zweig von not Assigned, \"Assigned(F) and\" vor dem Aufruf oder \"if not Assigned(F) then Ex' + 'it/raise\" davor, auch über einen Merker oder eine Methode der Klasse ohne Parameter, deren Result Assigned(F) enthält. Still bleiben Felder, die ein Konstruktor mit einem Wert belegt (eingereichte Ab' + 'hängigkeiten wie FReadText := AReadText), Properties darauf und gleichnamige lokale Namen. Sicherheit hoch. Korrektur: den Aufruf in \"if Assigned(F) then\" einschließen, wenn er als eigene Anweisung ' + 'in einem Block steht."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "owned-item-freed",' + #10 +
    '      "name": "Element einer besitzenden Liste zusätzlich freigegeben",' + #10 +
    '      "description": "Ein Element einer TObjectList/TObjectList<T> (OwnsObjects, Vorgabe True) oder eines TObjectDictionary mit doOwnsValues wird mit Free, FreeAndNil, Destroy oder DisposeOf freigegeb' + 'en, direkt (Liste[I].Free, Liste.Items[I].Free) oder über eine Variable aus Liste[I], Liste.First/Last oder einer for-in-Schleife über die Liste bzw. Dictionary.Values. Die Liste gibt das Element selb' + 'st frei: bei Delete, Remove, Clear, einer Zuweisung an Liste[I] oder spätestens beim Freigeben, also doppelt. Besitzend ist eine Liste, wenn die Unit sie so erzeugt (TObjectList ohne False, TObjectDic' + 'tionary mit doOwnsValues) oder ohne Erzeugung als TObjectList deklariert, und kein OwnsObjects := False folgt. Extract in derselben Routine lässt die Regel schweigen. Sicherheit hoch. Korrekturen: Fre' + 'e entfernen (die ganze Schleife, wenn sie nur freigibt), Delete bzw. Remove statt Free, Extract statt Remove."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "create-without-assignment",' + #10 +
    '      "name": "Objekt erzeugt und sofort verloren",' + #10 +
    '      "description": "TStringList.Create; als eigene Anweisung: Das Objekt wird erzeugt, aber nirgends gespeichert und nie freigegeben (Speicherleck). Still bleiben Komponenten mit Owner (erstes Argum' + 'ent Self, Owner, AOwner, Application oder ein Nachfahr von TComponent mit einem Argument ungleich nil), Threads (geben sich mit FreeOnTerminate selbst frei), Records, unbekannte Klassen mit Argumenten' + ' und Klassen aus selfRegistering. Sicherheit hoch. Korrektur: Zuweisung an eine neue lokale Variable, die folgenden Anweisungen des Blocks in try/finally mit Free.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "selfRegistering",' + #10 +
    '          "description": "Klassen, die sich im Konstruktor selbst registrieren, als Muster mit * und ?; Create als Anweisung bleibt für sie still."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "message-handler-without-inherited",' + #10 +
    '      "name": "Message-Handler ohne inherited",' + #10 +
    '      "description": "Eine Methode mit message WM_… oder CM_… ruft weder inherited noch DefaultHandler (bzw. DefWindowProc, CallWindowProc) auf. Die Standardbehandlung der VCL bzw. von Windows fällt w' + 'eg: kein Neuausrichten bei WM_SIZE, kein Schließen bei WM_CLOSE, kein Zeichnen bei WM_PAINT. Die Meldung nennt für gängige Nachrichten die Folge. Still bleiben Klassen ohne Vorfahr, Nachrichten aus sw' + 'allow (Vorgabe WM_ERASEBKGND) und Handler, die Msg.Result selbst setzen (bewusste Antwort wie MA_NOACTIVATE). Sicherheit mittel. Korrektur: inherited; am Anfang einfügen.",' + #10 +
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
    '      "description": "Die klassischen String-Routinen zählen ab 1: Copy(S, 0, N) und Insert(T, S, 0) wirken nur zufällig wie 1, Delete(S, 0, N) löscht nichts. Der String muss bekannt sein: deklarierte' + 'r Typ in der Datei, Literal oder .Text/.Caption; dynamische Arrays (ab 0) bleiben still. Pos, PosEx und AnsiPos liefern 0 bei keinem Treffer: Pos(…) > -1, >= 0 und <> -1 sind immer wahr, = -1 und < 0 ' + 'nie. Umgekehrt übersieht S.IndexOf(…) > 0 bzw. >= 1 den Treffer am Anfang, < 1 bzw. <= 0 zählt ihn als nicht gefunden (Sicherheit mittel; LastIndexOf bleibt still, dort heißt > 0 meist „nicht am Anfan' + 'g“). Sicherheit hoch für Delete und Pos. Korrektur: Startwert 1 bzw. der richtige Vergleich (> 0, = 0, >= 0, < 0)."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "delimited-text-without-strict",' + #10 +
    '      "name": "DelimitedText ohne StrictDelimiter",' + #10 +
    '      "description": "Liste.DelimitedText := … nach Liste.Delimiter := … in derselben Routine, ohne dass StrictDelimiter gesetzt wird: DelimitedText trennt dann auch an Leerzeichen, ''Max Muster;Berlin' + ''' ergibt drei statt zwei Einträge. Bei Feldern zählt StrictDelimiter in der ganzen Unit (oft im Konstruktor); StrictDelimiter := False ist bewusst und bleibt still, ebenso DelimitedText ohne eigenen D' + 'elimiter. Sicherheit hoch. Korrektur: StrictDelimiter := True; vor der Zuweisung einfügen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "self-as-interface-in-constructor",' + #10 +
    '      "name": "Self während der Konstruktion als Interface weitergegeben",' + #10 +
    '      "description": "Self wird als Interface weitergegeben, während die Referenzzählung das Objekt schon freigeben kann. Gemeldet werden nur zwei echte Fehlerfälle: (1) Eine Klasse mit eigener Refere' + 'nzzählung (ein _Release in der Klassenkette gibt das Objekt frei, keine Klasse überschreibt NewInstance, die Kette ist bis TObject bekannt) gibt Self im Konstruktor oder in AfterConstruction als Inter' + 'face weiter: Der Zähler steigt von 0 auf 1 und fällt wieder auf 0, das Objekt wird freigegeben, bevor die Konstruktion endet. (2) Ein Nachfahr von TInterfacedObject gibt Self in AfterConstruction nach' + ' inherited als Interface weiter: inherited AfterConstruction hat den Schutzzähler aus NewInstance schon abgebaut. Im Konstruktor eines TInterfacedObject-Nachfahren ist Self geschützt, die Regel bleibt' + ' still. Als Weitergabe zählen Self as IX, IX(Self), ein Argument, dessen Parameter in allen bekannten Überladungen ein Interface ist, und die Zuweisung an eine Interface-Variable. Sicherheit hoch. Kor' + 'rektur in Fall 2: die Anweisung vor inherited verschieben."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "null-compare",' + #10 +
    '      "name": "Vergleich mit Null statt VarIsNull oder IsNull",' + #10 +
    '      "description": "X = Null bzw. X <> Null vergleicht einen Variant mit Null. Das Ergebnis hängt von der globalen Einstellung System.Variants.NullEqualityRule ab: Mit der Vorgabe ncrLoose vergleich' + 't er wie erwartet, mit ncrStrict ist er nie wahr, mit ncrError löst er eine Exception aus. Eine Bibliothek, ein Testrahmen oder ein anderer Teil des Projekts kann die Einstellung ändern. VarIsNull(X) ' + 'und Feld.IsNull prüfen unabhängig davon. Gemeldet wird nur, wo der Vergleich für sich steht (Bedingung, Argument, Zuweisung); not X = Null bindet als (not X) = Null und bekommt keine Korrektur. Sicher' + 'heit hoch. Korrektur: Feld.IsNull bei X.Value auf FieldByName, FindField, Fields[…], ParamByName, Params[…] oder einem Feld vom Typ T…Field/T…Param, sonst VarIsNull(X); bei <> mit not davor."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unchecked-enum-cast",' + #10 +
    '      "name": "Zahl ungeprüft in Aufzählung umgewandelt",' + #10 +
    '      "description": "TStatus(N) mit einem Aufzählungstyp aus der Datei oder dem Index, wenn N aus einem Aufruf der Option sources stammt (FieldByName, ReadInteger, AsInteger, StrToInt): direkt im Arg' + 'ument oder über eine Variable, die zwischen Zuweisung und Umwandlung nicht gelesen (geprüft) wird. Ein Wert außerhalb des Bereichs ergibt einen ungültigen Aufzählungswert, der in case durchfällt. Ensu' + 'reRange, Min oder Max im Argument gelten als Prüfung; Konstanten, Rechnungen und unbekannte Typen bleiben still. Bei Aufzählungen mit eigenen Ordinalwerten nennt die Meldung den Bereich als Ord(Low(T)' + ')..Ord(High(T)). Sicherheit mittel. Korrektur bei direkter Quelle in einer eigenen Anweisung: Hilfsvariable, InRange-Prüfung mit raise EConvertError davor, System.Math in uses.",' + #10 +
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
    '      "description": "CreateProcess (CreateProcessW) und CreateProcessAsUser schreiben in den Puffer von lpCommandLine. Ein PChar auf Speicher, der nicht beschreibbar ist, führt zu einer Zugriffsverle' + 'tzung. Gemeldet wird PChar(…)/PWideChar(…) auf: ein String-Literal oder eine Konstante; eine Verkettung aus genau einem Literal und einem Wert (ist der Wert leer, liefert die RTL das Literal selbst); ' + 'eine lokale String-Variable, deren letzte Zuweisung vor dem Aufruf eines davon ist, ohne UniqueString danach; einen String-Parameter (Sicherheit mittel, der Aufrufer kann ein Literal übergeben). Funkt' + 'ionsergebnisse wie Format und Verkettungen aus mehreren Teilen sind beschreibbare Heap-Strings und bleiben still, ebenso CreateProcessA, das die Befehlszeile selbst kopiert. Korrektur: Befehlszeile in' + ' eine lokale Variable kopieren und UniqueString aufrufen; bei einer Variablen UniqueString vor der Anweisung. In Schleifenbedingungen keine Korrektur."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "form-access-before-create",' + #10 +
    '      "name": "Zugriff auf ein Formular, das noch nicht erzeugt ist",' + #10 +
    '      "description": "Der Konstruktor, AfterConstruction oder der OnCreate-Handler eines automatisch erzeugten Formulars bzw. Datenmoduls benutzt die globale Variable eines anderen Formulars, das die ' + '.dpr erst danach mit Application.CreateForm erzeugt. Die Variable ist dort noch nil. Die Reihenfolge stammt aus der .dpr des Projekts, zu dem die Unit gehört; der OnCreate-Handler aus der Formulardate' + 'i (ohne Eintrag FormCreate bzw. DataModuleCreate). Still, wenn die Routine die Variable prüft (Assigned, Vergleich mit nil), selbst zuweist, mit CreateForm erzeugt oder einen gleichnamigen lokalen Nam' + 'en deklariert, und bei Formularen, die nicht automatisch erzeugt werden. Jede Variable wird je Routine einmal gemeldet. Sicherheit mittel. Keine Korrektur: die Reihenfolge in der .dpr ändern oder den ' + 'Zugriff nach OnShow verlegen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "except-handler-order",' + #10 +
    '      "name": "Allgemeiner Exception-Handler vor speziellem",' + #10 +
    '      "description": "In einem try..except mit mehreren on-Handlern gewinnt der erste passende. Ein Handler für eine Klasse, die ein früherer Handler schon fängt, wird nie erreicht: Sein Code ist tot ' + 'und die Sonderbehandlung läuft nie. Gemeldet, wenn ein früherer Handler dieselbe Klasse, einen Vorfahren davon, Exception (deckt jede Exception-Klasse ab) oder TObject nennt. Vorfahren kommen aus der ' + 'Unit, dem Projektindex und einer Tabelle bekannter RTL-, VCL- und FireDAC-Exceptions (etwa EStreamError > EFOpenError, EIntError > ERangeError); unbekannte Klassen werden nur mit Exception und TObject' + ' verglichen. Korrektur: den speziellen Handler vor den allgemeinen verschieben (nur, wenn beide Handler auf eigenen Zeilen stehen). Ein doppelter Handler für dieselbe Klasse wird ohne Korrektur gemeld' + 'et."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "reraise-exception-object",' + #10 +
    '      "name": "raise E statt raise im Handler",' + #10 +
    '      "description": "raise E; in einem Handler on E: … löst das gefangene Exception-Objekt als neues raise aus. Die RTL gibt das Objekt nicht doppelt frei, aber die Ausnahme beginnt jetzt im Handler:' + ' ExceptAddr und die Aufrufliste von Werkzeugen wie madExcept oder JclDebug zeigen auf den Handler statt auf den ursprünglichen Fehler, die Absprungstelle geht verloren. raise; wirft die aktuelle Excep' + 'tion unverändert weiter. Auch raise E at … wird gemeldet, dann ohne Korrektur. Still, wenn der Handler das Objekt mit AcquireExceptionObject übernimmt oder der Variablen ein neues Objekt zuweist, in a' + 'nonymen Methoden und bei Handlern ohne Variablennamen. Konfidenz hoch. Korrektur: raise E; → raise;."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "blocking-call-in-main-thread",' + #10 +
    '      "name": "Blockierender Aufruf im Hauptthread",' + #10 +
    '      "description": "Sleep, WaitFor, WaitForSingleObject, WaitForMultipleObjects oder Wait in Methoden von Formularen und Frames (Klassen, die von TForm, TCustomForm, TFrame oder TCustomFrame erben) ' + 'und in Ereignis-Handlern (Methoden mit Parameter Sender) außerhalb von Thread-Klassen. Die Oberfläche friert ein, solange der Aufruf wartet; wartet der andere Thread auf Synchronize, hängt das Program' + 'm. WaitFor ohne Timeout auf einer Variablen nennt die Gefahr der Synchronize-Verklemmung. Sleep, WaitForSingleObject und WaitForMultipleObjects zählen nur ohne Empfänger (oder mit Winapi.Windows), Wai' + 'tFor und Wait nur mit Empfänger. Ein Literal-Timeout unter maxSleepMs (Sleep(10), WaitForSingleObject(H, 0)) bleibt still, außer ein kurzes Sleep in einer Warteschleife ohne Application.ProcessMessage' + 's. Anonyme Methoden sind ausgenommen (TTask.Run, TThread.Queue), eingebettete Routinen gehören zu ihrer Methode. Konfidenz mittel. Keine Schnellkorrektur: die Arbeit in TTask.Run auslagern und das Erg' + 'ebnis mit TThread.Queue melden.",' + #10 +
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
    '      "description": "Eine while- oder repeat-Schleife in TThread.Execute oder in einer Methode der Thread-Klasse, die nur von dort aufgerufen wird (auch über andere solche Methoden, eingebettete Rout' + 'inen eingeschlossen), prüft Terminated nicht. Terminate wirkt dann nicht, und WaitFor bzw. Free hängen beim Beenden. Gemeldet für Endlosschleifen (while True, until False) und für Warteschleifen mit S' + 'leep, WaitFor, WaitForSingleObject, WaitForMultipleObjects, MsgWaitForMultipleObjects, Wait oder Yield, deren Bedingung und Rumpf Terminated bzw. CheckTerminated nie erwähnen. Thread-Klassen kommen au' + 's der Unit und dem Index. Begrenzte Schleifen, for-Schleifen, anonyme Methoden und Klassen, die TerminatedSet überschreiben (sie beenden ihre Schleifen auf anderem Weg), bleiben still. Konfidenz hoch.' + ' Korrektur: Terminated in die Schleifenbedingung aufnehmen (while True → while not Terminated, sonst and not Terminated; until False → until Terminated, sonst or Terminated)."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "anonymous-thread-not-started",' + #10 +
    '      "name": "Anonymer Thread nie gestartet",' + #10 +
    '      "description": "TThread.CreateAnonymousThread(…) legt den Thread angehalten und mit FreeOnTerminate an. Ohne Start läuft er nie, und weil er nie endet, wird er auch nie freigegeben. Gemeldet für' + ' den Aufruf als eigene Anweisung und für eine lokale Variable (auch Inline-Variable), die weder mit Start oder Resume gestartet noch weitergegeben wird (Argument, Zuweisung, Result, Feld). Eigenschaft' + 'en wie FreeOnTerminate oder OnTerminate zu setzen gilt nicht als Weitergabe. Konfidenz hoch. Korrektur: .Start anhängen; bei einer Variablen T.Start; nach der letzten Anweisung desselben Blocks, die s' + 'ie erwähnt."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "task-exception-unobserved",' + #10 +
    '      "name": "Exception in TTask geht verloren",' + #10 +
    '      "description": "TTask.Run(…) bzw. TTask.Create(…).Start, dessen Ergebnis nicht gespeichert und nie mit Wait, Status o. ä. abgefragt wird und dessen anonyme Methode kein try … except hat. Eine Ex' + 'ception im Task verschwindet still. Auch gemeldet für eine lokale Variable, die nie wieder vorkommt (bei TTask.Create nur in V.Start). Still bei gespeicherten Ergebnissen (Felder, Result, jede andere ' + 'Verwendung der Variablen) und bei Methodenzeigern, deren Rumpf die Regel nicht sieht. Konfidenz mittel. Korrektur: den Rumpf in try … except einschließen und die Meldung über TThread.Queue mit ShowMes' + 'sage im Hauptthread zeigen (ergänzt Vcl.Dialogs, in FireMonkey-Units FMX.Dialogs, und System.SysUtils im uses, wenn sie fehlen); nur, wenn begin und end der anonymen Methode auf eigenen Zeilen stehen.' + '"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dataset-loop-without-next",' + #10 +
    '      "name": "Datenmengen-Schleife ohne Next",' + #10 +
    '      "description": "while not Q.Eof do ohne Q.Next im Rumpf oder mit Next nur auf einem Teil der Wege, die die Schleife fortsetzen (if ohne else, Continue vor Next). Die Schleife dreht endlos auf de' + 'mselben Datensatz. Delete, MoveBy, Last, Close, FindNext und Free zählen ebenfalls als Weiterbewegen; Break, Exit, Abort und raise beenden die Schleife. Innere while- und for-Schleifen laufen vielleic' + 'ht nie und zählen nicht. Wird Q im Rumpf weitergegeben (Argument, Zuweisung, with), kann der Aufgerufene den Zeiger bewegen, und die Regel bleibt still. Konfidenz hoch, wenn Next ganz fehlt, mittel, w' + 'enn nur einzelne Wege es auslassen. Korrektur: Q.Next; am Ende des begin … end-Rumpfs einfügen (nur, wenn Next ganz fehlt)."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dataset-edit-without-post",' + #10 +
    '      "name": "Edit oder Append ohne Post",' + #10 +
    '      "description": "Nach Edit, Append oder Insert (ohne Argumente) einer Datenmenge ruft dieselbe Routine weder Post noch Cancel (noch CheckBrowseMode) auf. Die Änderung bleibt offen und geht beim S' + 'crollen still verloren oder wird später unerwartet gespeichert; bei einer Exception dazwischen bricht sie niemand ab. Still, wenn eine andere Routine der Unit dieselbe Datenmenge postet oder abbricht ' + '(Bearbeiten-Knopf mit eigenem Speichern-Knopf), und wenn die Datenmenge nach Edit weitergegeben wird (Argument, Zuweisung, with). Konfidenz mittel. Korrektur: die folgenden Anweisungen, die die Datenm' + 'enge benutzen, in try … except einschließen, mit Post am Ende des try-Teils und Cancel; raise; im except-Teil."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "transaction-without-rollback",' + #10 +
    '      "name": "Transaktion ohne Rollback",' + #10 +
    '      "description": "StartTransaction ohne Rollback im except des unmittelbar folgenden try. Bei einer Exception bleibt die Transaktion offen und hält Sperren. Erkannt für FireDAC (TFDConnection, TFD' + 'Transaction), IBX und dbExpress (StartTransaction/Commit/Rollback), dbExpress ab XE (BeginTransaction/CommitFreeAndNil/RollbackFreeAndNil, auch als T := Conn.BeginTransaction) und ADO (BeginTrans/Comm' + 'itTrans/RollbackTrans). Die Option pairs ersetzt diese Paare durch eigene. Das Rollback darf in einem try … except innerhalb eines direkt folgenden try … finally stehen. Still, wenn eine andere Routin' + 'e der Unit dieselbe Verbindung zurückrollt (Transaktion über mehrere Ereignisse). Konfidenz hoch. Korrektur: die Anweisungen bis zum Commit desselben Blocks in try … except mit Rollback (mit den Argum' + 'enten des Commit) und raise; einschließen; nur, wenn im selben Block ein Commit folgt.",' + #10 +
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
    '      "description": "UPDATE oder DELETE ohne WHERE in einem String-Literal, in SQL.Text, SQL.Add, CommandText, im ersten Argument von ExecSQL, ExecSQLScalar, Open, ExecuteDirect oder Execute oder in ' + 'SQL.Strings/CommandText der Formulardatei. Das betrifft alle Zeilen der Tabelle; meist ist die Bedingung vergessen. Die Regel setzt den SQL-Text je Query innerhalb einer Routine zusammen (Clear und ei' + 'n neuer Text beginnen von vorn) und setzt Konstanten und lokale Werte ein. JOIN, TOP, LIMIT und ROWS schränken die Zeilen ebenfalls ein; ein WHERE in einer Unterabfrage oder einem Kommentar zählt nich' + 't. Unbekannte Teile hinter dem Tabellennamen (Variablen, Aufrufe an der Stelle einer Klausel) lassen die Anweisung still; ein dynamischer Tabellenname meldet mit mittlerer Konfidenz. Still, wenn die R' + 'outine den SQL-Text weitergibt oder eine andere Routine der Unit ihn ergänzt; SQL der Formulardatei zählt nur, solange die Unit es nicht verändert. Literale außerhalb von SQL-Eigenschaften zählen nur ' + 'mit DELETE bzw. UPDATE in Großbuchstaben, damit Meldungstexte still bleiben. Konfidenz hoch, keine Korrektur; Tabellen, die absichtlich geleert werden, gehören in allowTables.",' + #10 +
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
    '      "description": "Der Kopf im implementation-Teil hat andere Parameter (Anzahl, Name, Typ, const/var/out), einen anderen Ergebnistyp, procedure statt function oder eine andere Aufrufkonvention als' + ' die Deklaration im Typ (wie E2037). Bei Überladungen wird die nächstliegende Deklaration verglichen (Parameteranzahl, dann Typen, Namen und Modifizierer); ist sie nicht eindeutig, melden declared-not' + '-implemented und implemented-not-declared beide Seiten. Ein Rumpf darf Parameterliste, Ergebnistyp und Aufrufkonvention weglassen. Methoden in {$IF}-Blöcken werden übergangen; mit Include-Dateien ist ' + 'die Konfidenz mittel. Korrektur: Kopf der Implementierung an die Deklaration angleichen oder als zweite Aktion die Deklaration an die Implementierung (Standardwerte bleiben in der Deklaration). refact' + 'oring.syncSignatures = false entfernt nur die Korrekturen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "interface-not-implemented",' + #10 +
    '      "name": "Interface-Methode fehlt in der Klasse",' + #10 +
    '      "description": "Eine Klasse nennt ein Interface, implementiert aber nicht alle seine Methoden, auch die der Vorfahr-Interfaces (wie E2291). Eine gleichnamige Methode der Klasse mit anderer Signa' + 'tur wird an dieser Methode gemeldet (wie E2211). Geerbte Methoden der Vorfahrklassen, Methodenzuordnungen (procedure IFoo.Bar = Baz) und Properties mit implements zählen; ebenso die öffentlichen Metho' + 'den von TObject und die IInterface-Methoden von TInterfacedObject und ähnlichen RTL-Basen. Endet die Kette der Vorfahrklassen bei einer unbekannten Klasse oder ist das Interface unbekannt, bleibt die ' + 'Regel still. Gemeldet wird auch eine Methodenzuordnung für ein Interface, das die Klasse nicht nennt (wie E2265). Klassen in {$IF}-Blöcken werden übergangen. Korrektur: fehlende Methoden deklarieren u' + 'nd leer implementieren (nicht bei abweichendem Kopf)."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "uses-unit-not-found",' + #10 +
    '      "name": "Unit in uses nicht gefunden",' + #10 +
    '      "description": "Eine Unit aus uses oder contains liegt weder im Projekt noch in den Ordnern, die der Compiler durchsucht: Ordner der verwendenden Datei, Projektordner, Suchpfade und DCU-Ausgabeo' + 'rdner der .dproj, Bibliothekspfade der Installation, jeweils als .pas oder .dcu und mit jedem Unit-Namespace davor (SysUtils → System.SysUtils); bei Packages zusätzlich die Units der requires-Packages' + ' (wie F2613). Ebenso gemeldet: eine Datei aus in ''…'', die es nicht gibt (F1026), ein Package aus requires, das weder als .dpk noch als .dcp gefunden wird (E2202), eine Unit, die sich selbst einbindet ' + '(F2092), und einmal eine fehlende Unit System, also ein fehlender Bibliothekspfad, statt einer Meldung je Unit (F1027). Einträge in {$IF}-Blöcken werden übergangen; ohne bekannte Installation, mit off' + 'enem Makro in einem Suchpfad oder einem requires-Package mit unbekanntem Inhalt bleibt die Regel still. Die Meldung nennt ähnliche Units. Korrekturen: die Unit mit Namespace (Forms → Vcl.Forms) bzw. e' + 'ine ähnlich geschriebene einsetzen oder den Ordner unter dem Projekt, in dem die Unit liegt, in DCC_UnitSearchPath der Basiskonfiguration der .dproj aufnehmen.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "searchPaths",' + #10 +
    '          "description": "Wo Units gesucht werden: project (wie der Compiler: Projekt, Suchpfade der .dproj, Bibliothekspfade, .pas und .dcu), atlas (was Atlas kennt: Index und Quellpfade der Installa' + 'tion) oder both."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unresolved-attribute",' + #10 +
    '      "name": "Attribut nicht gefunden und still ignoriert",' + #10 +
    '      "description": "Ein Attribut [Name] lässt sich weder einer Klasse NameAttribute noch Name zuordnen, meist weil eine Unit in uses fehlt. Delphi warnt nur (W1074) und übergeht das Attribut: DUnitX' + '-Tests laufen dann nicht, JSON- oder ORM-Zuordnungen fehlen. Die Meldung nennt die Unit, die das Attribut im Index deklariert; eine Fassaden-Unit, die den Typ aus einer anderen Kandidatin weiterreicht' + ' (DUnitX.TestFramework statt DUnitX.Attributes), geht vor, und die DUnitX-Attribute sind auch ohne DUnitX im Index bekannt. Attribute des Compilers wie Weak, Unsafe, Ref und Volatile zählen immer. Sti' + 'll ohne die Unit System im Index, wenn eine Unit aus uses nicht im Index steht (sie könnte das Attribut deklarieren), in {$IF}-Blöcken und bei unbekanntem Vorfahren der umgebenden Klasse; mit Include-' + 'Dateien ist die Konfidenz mittel. Korrektur: Unit in uses aufnehmen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "comparison-as-statement",' + #10 +
    '      "name": "Vergleich statt Zuweisung als Anweisung",' + #10 +
    '      "description": "Ein Vergleich wie Result = 0; oder FAktiv = True; steht als eigene Anweisung; gemeint war :=. Delphi meldet E2014 erst beim Übersetzen. Bei = mit zuweisbarer linker Seite (Variab' + 'le, Feld, Element, Ziel eines Zeigers) ersetzt die Korrektur = durch :=. Andere Vergleiche und Ausdrücke, deren Wert verfällt (A <> B;, A + B;, not A;, ein Literal), meldet die Regel ohne Korrektur, e' + 'benso einen Aufruf links."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "duplicate-case-label",' + #10 +
    '      "name": "Doppelte case-Marke",' + #10 +
    '      "description": "Zwei Marken einer case-Anweisung decken denselben Wert ab (wie E2030), auch über Bereiche (1..5 und 3), Konstanten mit gleichem Wert, Zeichen (''a'' und #97) und Bereiche von Aufzä' + 'hlungswerten. Gleiches gilt für die Marken eines varianten Record-Teils (wie E2027). Die Werte ergeben sich aus Zahlen, Zeichen, Konstanten und Aufzählungswerten über die Namensauflösung; Marken mit u' + 'nbekanntem Wert vergleicht die Regel nur über den Text. Gemeldet wird eine Marke nur, wenn die frühere immer mit übersetzt wird: verschiedene Zweige desselben {$IF} stoßen nie zusammen. Korrektur: den' + ' doppelten Wert aus dem späteren Zweig entfernen bzw. den ganzen Zweig, wenn es seine einzige Marke war; eine teilweise Überschneidung von Bereichen meldet die Regel ohne Korrektur."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "field-after-method",' + #10 +
    '      "name": "Feld nach Methoden im selben Abschnitt",' + #10 +
    '      "description": "In einem Sichtbarkeitsabschnitt einer Klasse, eines Objekts oder Records folgt eine Felddeklaration auf eine Methode oder Property. Delphi verlangt Felder zuerst oder einen neuen' + ' Abschnitt bzw. var (E2169); FPC übersetzt das. Korrekturen: das Feld samt Attributen und Kommentaren an den Anfang des Abschnitts verschieben oder var davor setzen. In Records steht var vorn, weil da' + 's Verschieben das Speicherlayout ändert. Gemeldet wird ein Feld nur, wenn eine Methode davor immer mit übersetzt wird, wenn das Feld übersetzt wird; mit bedingten Zweigen dazwischen gibt es nur var."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "overload-directive-missing",' + #10 +
    '      "name": "Überladung ohne overload oder mit gleicher Signatur",' + #10 +
    '      "description": "Zwei Routinen oder Methoden gleichen Namens im selben Gültigkeitsbereich (ein Typ, die Unit über interface und implementation, die in einer Routine verschachtelten Routinen), von' + ' denen mindestens eine kein overload trägt (wie E2254, bzw. E2267, wenn es der früheren fehlt), oder zwei Überladungen mit gleichen Parameterarten und -typen (wie E2252, bzw. E2301 mit auch gleichem E' + 'rgebnistyp). Ein Rumpf zu einer früheren Deklaration (interface, forward) zählt nicht. Operatoren, Methodenrümpfe und Deklarationen in verschiedenen Zweigen desselben {$IF} bleiben außen vor. Korrektu' + 'r: overload; an alle Deklarationen ohne anhängen, vor den übrigen Direktiven."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "duplicate-declaration",' + #10 +
    '      "name": "Bezeichner doppelt deklariert",' + #10 +
    '      "description": "Ein Bezeichner ist im selben Gültigkeitsbereich zweimal deklariert (wie E2004): lokale Variable, Konstante, Typ oder Label und ein Parameter der Routine, zwei Felder, ein Feld un' + 'd eine Methode oder Property eines Typs, zwei Typen, Konstante und Variable der Unit über interface und implementation hinweg. Ebenso eine Unit doppelt in uses oder in den uses-Klauseln von interface ' + 'und implementation zugleich (Option checkUses). Überladungen und Rümpfe von Routinen, eine Vorwärtsdeklaration und ihr Typ, TList neben TList<T> und Deklarationen in verschiedenen Zweigen desselben {$' + 'IF} zählen nicht. Korrektur: zweite Deklaration entfernen (den ganzen var-, const-, type- oder label-Abschnitt, wenn sie seine einzige war; bei uses den doppelten Eintrag); keine bei Parametern, Metho' + 'den und Properties.",' + #10 +
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
    '      "description": "Ein {$IFDEF}, {$IFNDEF}, {$IFOPT} oder {$IF}, das nie geschlossen wird, sodass der Rest der Datei an seiner Bedingung hängt (wie E2095, bei {$IF} E2280); {$ELSE}, {$ELSEIF}, {$EN' + 'DIF} oder {$IFEND} ohne passendes {$IF…} oder nach {$ELSE} (wie E2279); {$IFDEF}, {$IFNDEF}, {$DEFINE} oder {$UNDEF} ohne gültiges Symbol (wie E2173); eine unbekannte Direktive oder ein unbekannter {$' + 'WARN}-Bezeichner (wie W1030), mit dem nächstliegenden bekannten Namen als Korrektur; {$POPOPT} ohne {$PUSHOPT} (wie W1078) oder {$PUSHOPT} ohne {$POPOPT} (wie W1079); ein ungültiger Wert für {$ALIGN} ' + 'bzw. {$A} (wie E2573). Unbekannte Namen prüft die Regel nicht in Zweigen, deren Bedingung FPC abfragt, {$PUSHOPT}/{$POPOPT} nur, wenn keines davon in einem bedingten Zweig steht. Korrekturen: {$ENDIF}' + ' vor der ersten Leerzeile hinter dem offenen Block ergänzen, überzählige Direktive entfernen, Tippfehler korrigieren."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "override-target-missing",' + #10 +
    '      "name": "override ohne passende virtuelle Methode",' + #10 +
    '      "description": "Eine Methode mit override, zu der kein Vorfahr eine virtuelle (oder dynamic, abstract) Methode mit gleichem Namen und gleichen Parametern hat (wie E2137): oft ein Tippfehler (Des' + 'tory) oder im Vorfahren geänderte Parameter. Die Meldung nennt die nächstliegende virtuelle Methode des Vorfahren („dort heißt es Ausfuehren(const Modus: TModus)“) bzw. einen ähnlichen Namen. Außerdem' + ': override auf eine statische Methode (wie E2170), auf eine finale (wie E2352) und Ableiten von einer sealed-Klasse (wie E2353). Vorfahren sucht die Regel in der Datei und im Symbolindex; bricht die K' + 'ette an einer unbekannten Klasse ab, bleibt sie still. Ohne System im Index gelten die virtuellen Methoden von TObject als vorhanden. Typparameter generischer Vorfahren, Typaliase und Synonyme wie Lon' + 'gint passen. Korrektur: Signatur des Vorfahren in Deklaration und Implementierung übernehmen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "abstract-class-instantiated",' + #10 +
    '      "name": "Instanz einer Klasse mit abstrakten Methoden",' + #10 +
    '      "description": "Create auf einer Klasse, die abstrakte Methoden deklariert oder erbt, ohne sie zu überschreiben (wie W1020), oder auf einer als abstract deklarierten Klasse (wie E2402). Der Aufr' + 'uf einer abstrakten Methode löst zur Laufzeit EAbstractError aus; die Meldung nennt die offenen Methoden. Klassen sucht die Regel in der Datei und im Symbolindex; Überladungen mit gleicher Parameterza' + 'hl gelten als eine Methode. Aufrufe über Klassenreferenzen, inherited Create und Konstruktor-Rümpfe prüft sie nicht. Korrektur für eine Klasse dieser Datei, die die abstrakten Methoden erbt: dort über' + 'schreiben (wie die Code-Aktion „überschreiben“)."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "property-accessor-invalid",' + #10 +
    '      "name": "Getter oder Setter einer Property ungültig",' + #10 +
    '      "description": "Der Name hinter read oder write einer Property passt nicht: Er ist weder in der Klasse noch in ihren Vorfahren deklariert oder ist eine Property (wie E2168); Getter oder Setter h' + 'aben die falsche Art, Parameter oder Typen (wie E2234); der Setter nimmt einen var- oder out-Parameter (wie E2282); die Zugriffsmethode ist überladen (wie E2271); eine Klassen-Property nutzt ein Insta' + 'nzmitglied oder eine Klassenmethode ohne static (wie E2355), eine Instanz-Property ein Klassenmitglied (wie E2356); eine Array-Property oder eine Property mit index nutzt ein Feld (wie E2174); ein Fel' + 'dselektor geht über ein Feld, das kein Record ist (wie E2459), nennt ein Mitglied, das kein Feld ist (wie E2461), oder ein Feld, das dem Record fehlt (wie E2562). Namen sucht die Regel in der Datei un' + 'd für Vorfahren im Symbolindex; sie bleibt still, wenn die Kette der Vorfahren abbricht, der Name nur in einem inaktiven Zweig steht, die Klasse ihn nicht sieht oder Include-Dateien einbindet. Typen v' + 'ergleicht sie nur, wenn beide eingebaut oder als eigener Typ deklariert sind. Korrektur für ein fehlendes F<Name>, Get<Name> oder Set<Name>: anlegen (wie die Vervollständigung hinter read/write, compl' + 'etion.accessorSection)."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "assign-to-property-member",' + #10 +
    '      "name": "Zuweisung an ein Feld eines Property-Records",' + #10 +
    '      "description": "Zuweisung an ein Feld eines Records, den eine Property mit Getter, eine Default- oder Array-Property oder ein Funktionsergebnis nur als Kopie liefert (wie E2064): Die Zuweisung h' + 'at keine Wirkung. Zuweisungen an untypisierte Konstanten meldet die Regel ebenso. Typen kommen aus der Namensauflösung; gemeldet wird nur bei sicher bekanntem Record-Typ. Liest die Property direkt ein' + ' Feld, schreibt Delphi in dieses Feld, und die Regel bleibt still. Korrektur bei einer Property mit write: über eine lokale Variable zuweisen und zurückschreiben; die Variable wird in der Routine dekl' + 'ariert, die Unit ihres Typs in uses ergänzt."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "readonly-property-assigned",' + #10 +
    '      "name": "Zuweisung an eine Property ohne write",' + #10 +
    '      "description": "Zuweisung an eine Property ohne write (wie E2129) bzw. Lesen einer Property ohne read (wie E2130). Die Regel meldet nur, wenn die Namensauflösung die Property sicher findet; Neud' + 'eklarationen ohne read und write (property Caption;) gelten als unbekannt. Korrekturen: Count := 0 wird Clear, wenn der Typ Clear hat; in einer Methode der deklarierenden Klasse das Feld hinter read z' + 'uweisen; für eine Property dieser Datei den Setter anlegen und write ergänzen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "sql-select-star",' + #10 +
    '      "name": "SELECT * im Code",' + #10 +
    '      "description": "SELECT * oder SELECT Alias.* in einer Spaltenliste, an denselben Stellen wie bei sql-write-without-where: String-Literale, SQL.Text, SQL.Add, CommandText, das erste Argument von ' + 'ExecSQL, Open und ähnlichen Aufrufen, Konstanten, lokale Werte und SQL.Strings/CommandText der Formulardatei. Neue Spalten ändern still die Datenmenge, persistente Felder passen nicht mehr, und es wer' + 'den mehr Daten übertragen als nötig. Unterabfragen zählen; EXISTS (SELECT * …) und COUNT(*) bleiben still, ebenso eine Spaltenliste aus einer Variablen. Literale außerhalb von SQL-Eigenschaften zählen' + ' nur mit SELECT in Großbuchstaben und einem FROM, damit Meldungstexte still bleiben. Standardmäßig aus (in den Regeleinstellungen oder mit dem Profil strict einschalten). Konfidenz hoch. Schnellkorrek' + 'tur: Steht der Stern in einem einzelnen Literal und hat die Datenmenge persistente Felder in der Formulardatei, ersetzt sie * durch deren FieldName-Liste (ohne berechnete und Nachschlagefelder)."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "path-concat-without-delimiter",' + #10 +
    '      "name": "Pfad ohne Trennzeichen zusammengesetzt",' + #10 +
    '      "description": "Ein Ordner ohne abschließendes Trennzeichen wird mit + an einen Datei- oder Ordnernamen gehängt: Ergebnisse von ExtractFileDir, ExcludeTrailingPathDelimiter, GetCurrentDir, GetHo' + 'mePath, TPath.GetDocumentsPath und den übrigen TPath.Get…Path-Ordnern, TPath.GetDirectoryName, TDirectory.GetCurrentDirectory und TDirectory.GetParent, direkt aufgerufen oder in einer lokalen Variable' + 'n, der die Routine nur solche Werte zuweist. Das Ergebnis ist C:\\Datendatei.txt statt C:\\Daten\\datei.txt. ExtractFilePath, IncludeTrailingPathDelimiter und TPath.GetTempPath enden mit einem Trennze' + 'ichen und bleiben still, ebenso Trennzeichen, Endungen (ExtractFileExt, ''.bak'') und Texte, die mit Leerzeichen oder Satzzeichen beginnen. Ein Literal als Name meldet mit hoher, ein Bezeichner mit mitt' + 'lerer Konfidenz. Geht eine lokale Variable an eine Prozedur außer ForceDirectories, FileExists und ähnlichen lesenden Aufrufen, kann sie dort geändert werden und bleibt still. Schnellkorrektur: TPath.' + 'Combine(Ordner, Name), System.IOUtils wird in die uses eingetragen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "hardcoded-path",' + #10 +
    '      "name": "Fester Dateipfad im Code",' + #10 +
    '      "description": "Ein String-Literal mit Laufwerksbuchstaben (C:\\…, auch mit /) oder UNC-Pfad (\\\\server\\freigabe\\…); Pfade unter C:\\Users bzw. C:\\Documents and Settings bekommen eine eigene' + ' Meldung. Auf anderen Rechnern fehlt der Pfad. Laufwerkswurzeln wie ''C:\\'' allein und die Präfixe \\\\?\\ und \\\\.\\ bleiben still, ebenso Kommentare, Test-Units und Units aus allowUnits (z. B. eine ' + 'Unit mit den Standardpfaden einer Installation). Konfidenz hoch, keine Korrektur: den Pfad aus TPath (GetDocumentsPath, GetHomePath, GetSharedDocumentsPath), den Einstellungen oder einer Umgebungsvari' + 'ablen holen.",' + #10 +
    '      "options": [' + #10 +
    '        {' + #10 +
    '          "name": "allowUnits",' + #10 +
    '          "description": "Units, in denen feste Pfade erlaubt sind, nach Unit-Namen; * am Ende passt auf ein Präfix (App.Config*)."' + #10 +
    '        }' + #10 +
    '      ]' + #10 +
    '    }' + #10 +
    '  ]' + #10 +
    '}' + #10 +
    '' + #10);
  Result := '';
end;

end.
