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
    '      "id": "unknown-rule-id",' + #10 +
    '      "name": "Unknown rule id",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "description": "An lsp-ignore comment names a rule id that does not exist, so it suppresses nothing. The message suggests the most similar known id (typo); such a comment is not also reported as' + ' unused-suppression.",' + #10 +
    '      "bad": "// lsp-ignore: empty-exept\ntry X; except end;",' + #10 +
    '      "good": "// lsp-ignore: empty-except\ntry X; except end;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "bidi-control",' + #10 +
    '      "name": "Bidirectional control character",' + #10 +
    '      "category": "vulnerability",' + #10 +
    '      "severity": "error",' + #10 +
    '      "description": "Bidirectional control characters can make code display differently from how it compiles (Trojan Source); also in form files. Direction marks in RTL text only with low confidence.' + '",' + #10 +
    '      "bad": "if IsAdmin then { U+202E } begin",' + #10 +
    '      "good": "if IsAdmin then begin"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "invisible-char",' + #10 +
    '      "name": "Invisible character",' + #10 +
    '      "category": "security-hotspot",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "Invisible or zero-width characters in the source code and form files; medium confidence in strings and comments.",' + #10 +
    '      "bad": "Count{U+200B} := 0;",' + #10 +
    '      "good": "Count := 0;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "control-char",' + #10 +
    '      "name": "Control character",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "description": "NUL or control characters or invalid UTF-8 bytes in the source code and the form file; invalid bytes with exact line and column.",' + #10 +
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
    '      "id": "forbidden-uses",' + #10 +
    '      "name": "Forbidden uses",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "error",' + #10 +
    '      "description": "A uses entry violates a layer rule configured under \"layers\" in atlas.json, e.g. *.Common.* must not use Vcl.*.",' + #10 +
    '      "bad": "unit App.Common.Model;\ninterface\nuses Vcl.Forms;",' + #10 +
    '      "good": "unit App.Common.Model;\ninterface\nuses System.Classes;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "architecture-role-import",' + #10 +
    '      "name": "Import violates the role matrix",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "A uses entry violates the import matrix of the role concept (output artefact, feature, role: Contract, Internals, Providers, Adapters, Composition, Hosting). Off by default; swit' + 'ch it on in atlas.json with the option \"prefixes\". Approved exceptions go to \"allow\" as \"Source -> Target\" globs.",' + #10 +
    '      "bad": "unit Atlas.Common.Logging.Contract;\ninterface\nuses Atlas.Common.Logging.Providers.Logger;",' + #10 +
    '      "good": "unit Atlas.Common.Logging.Contract;\ninterface\nuses System.SysUtils;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "architecture-contract-content",' + #10 +
    '      "name": "Class in a contract unit",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "A contract unit declares a class in its interface section. Contracts hold only records, interfaces, enumerations and exceptions. Off by default; switch it on in atlas.json with t' + 'he option \"prefixes\". Approved exceptions go to \"allow\" as \"Unit.Type\" globs.",' + #10 +
    '      "bad": "unit App.Orders.Contract;\ninterface\ntype\n  TOrderList = class\n  end;",' + #10 +
    '      "good": "unit App.Orders.Contract;\ninterface\ntype\n  IOrderList = interface\n  end;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "thread-vcl-access",' + #10 +
    '      "name": "VCL access from a thread",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "TThread.Execute, TThread.CreateAnonymousThread or TTask accesses the VCL (Application, Screen, ShowMessage, MessageDlg …) outside Synchronize or Queue. The VCL is not thread-safe' + '.",' + #10 +
    '      "bad": "procedure TWorker.Execute;\nbegin\n  Application.Title := ''Done'';\nend;",' + #10 +
    '      "good": "procedure TWorker.Execute;\nbegin\n  TThread.Queue(nil, procedure begin Application.Title := ''Done'' end);\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "lock-without-finally",' + #10 +
    '      "name": "Lock without try/finally",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "A lock (TCriticalSection.Enter/Acquire, TMonitor.Enter, BeginRead/BeginWrite, TSpinLock.Enter, TMutex.Acquire, EnterCriticalSection or a pair from the lockPairs option) is not di' + 'rectly followed by try/finally releasing it. An exception leaves the lock held.",' + #10 +
    '      "bad": "CS.Enter;\nDoWork;\nCS.Leave;",' + #10 +
    '      "good": "CS.Enter;\ntry\n  DoWork;\nfinally\n  CS.Leave;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "thread-use-after-free-on-terminate",' + #10 +
    '      "name": "Thread used after start with FreeOnTerminate",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "A thread with FreeOnTerminate := True may free itself as soon as it is started; using the variable afterwards can access a freed object.",' + #10 +
    '      "bad": "T.FreeOnTerminate := True;\nT.Start;\nLog(T.ThreadID);",' + #10 +
    '      "good": "Log(T.ThreadID);\nT.FreeOnTerminate := True;\nT.Start;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "thread-free-with-free-on-terminate",' + #10 +
    '      "name": "Free on a thread with FreeOnTerminate",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "description": "Free on a thread with FreeOnTerminate := True frees it twice.",' + #10 +
    '      "bad": "T.FreeOnTerminate := True;\nT.Start;\nT.Free;",' + #10 +
    '      "good": "T.FreeOnTerminate := True;\nT.Start;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "synchronize-in-destructor",' + #10 +
    '      "name": "Synchronize in thread destructor",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "Synchronize in the destructor of a TThread descendant (or a method it calls) deadlocks: the main thread waits in WaitFor while the thread waits for Synchronize.",' + #10 +
    '      "bad": "destructor TWorker.Destroy;\nbegin\n  Synchronize(Notify);\n  inherited;\nend;",' + #10 +
    '      "good": "destructor TWorker.Destroy;\nbegin\n  inherited;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "thread-resume-suspend",' + #10 +
    '      "name": "Deprecated TThread.Resume/Suspend",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "TThread.Resume and Suspend are deprecated. Start a created thread with Start; Suspend has no safe replacement, wait with an event instead.",' + #10 +
    '      "bad": "FWorker.Resume;",' + #10 +
    '      "good": "FWorker.Start;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "result-not-set",' + #10 +
    '      "name": "Function result possibly not set",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "A path through the function ends without assigning Result. The caller then reads an undefined value.",' + #10 +
    '      "bad": "function Find: Integer;\nbegin\n  if Ok then\n    Result := 1;\nend;",' + #10 +
    '      "good": "function Find: Integer;\nbegin\n  Result := 0;\n  if Ok then\n    Result := 1;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "possibly-uninitialized",' + #10 +
    '      "name": "Variable possibly uninitialized",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "A local variable is read on a path where it was never assigned.",' + #10 +
    '      "bad": "var I: Integer;\nbegin\n  if Ok then\n    I := 1;\n  Writeln(I);\nend;",' + #10 +
    '      "good": "var I: Integer;\nbegin\n  I := 0;\n  if Ok then\n    I := 1;\n  Writeln(I);\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unreachable-code",' + #10 +
    '      "name": "Unreachable code",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "A statement after Exit, raise, Abort, Halt, Break, Continue or goto is never executed. Usually a leftover or a misplaced jump. Only the first statement of an unreachable section ' + 'is reported.",' + #10 +
    '      "bad": "procedure Save;\nbegin\n  Exit;\n  Store;\nend;",' + #10 +
    '      "good": "procedure Save;\nbegin\n  if not Ready then\n    Exit;\n  Store;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unused-local",' + #10 +
    '      "name": "Unused local variable",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "description": "A local variable is declared but never used. Like compiler hint H2164, but while typing.",' + #10 +
    '      "bad": "procedure Foo;\nvar\n  I, Count: Integer;\nbegin\n  I := 1;\n  Bar(I);\nend;",' + #10 +
    '      "good": "procedure Foo;\nvar\n  I: Integer;\nbegin\n  I := 1;\n  Bar(I);\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unused-parameter",' + #10 +
    '      "name": "Unused parameter",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "description": "A parameter is never used in the routine body. Overridden and virtual methods, event handlers, published methods, interface implementations and callbacks are exempt.",' + #10 +
    '      "bad": "function Twice(A, B: Integer): Integer;\nbegin\n  Result := 2 * A;\nend;",' + #10 +
    '      "good": "function Twice(A: Integer): Integer;\nbegin\n  Result := 2 * A;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unused-assignment",' + #10 +
    '      "name": "Value assigned is never used",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "description": "A value assigned to a local variable is overwritten or the routine ends before it is read. Like compiler hint H2077.",' + #10 +
    '      "bad": "procedure Foo;\nvar\n  I: Integer;\nbegin\n  I := 0;\n  I := Calc;\n  Bar(I);\nend;",' + #10 +
    '      "good": "procedure Foo;\nvar\n  I: Integer;\nbegin\n  I := Calc;\n  Bar(I);\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "declared-not-implemented",' + #10 +
    '      "name": "Declared but not implemented",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "description": "A method is declared in a class, record or object but has no body in the implementation section. The compiler reports this only when compiling (E2065).",' + #10 +
    '      "bad": "type\n  TFoo = class\n    procedure Run;\n  end;\n\nimplementation\n\nend.",' + #10 +
    '      "good": "type\n  TFoo = class\n    procedure Run;\n  end;\n\nimplementation\n\nprocedure TFoo.Run;\nbegin\nend;\n\nend."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "implemented-not-declared",' + #10 +
    '      "name": "Implemented but not declared",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "description": "A method body TFoo.Bar has no matching declaration in the type.",' + #10 +
    '      "bad": "type\n  TFoo = class\n  end;\n\nimplementation\n\nprocedure TFoo.Run;\nbegin\nend;",' + #10 +
    '      "good": "type\n  TFoo = class\n  private\n    procedure Run;\n  end;\n\nimplementation\n\nprocedure TFoo.Run;\nbegin\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "destroy-without-override",' + #10 +
    '      "name": "Destroy without override",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "A destructor Destroy is declared without override. Free calls TObject.Destroy, so this destructor never runs.",' + #10 +
    '      "bad": "type\n  TFoo = class\n    destructor Destroy;\n  end;",' + #10 +
    '      "good": "type\n  TFoo = class\n    destructor Destroy; override;\n  end;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-create-without-override",' + #10 +
    '      "name": "Component constructor without override",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "A TComponent descendant declares constructor Create(AOwner: TComponent) without override. Components created from a form file are built through the virtual constructor and skip t' + 'his one.",' + #10 +
    '      "bad": "type\n  TMyPanel = class(TCustomPanel)\n    constructor Create(AOwner: TComponent);\n  end;",' + #10 +
    '      "good": "type\n  TMyPanel = class(TCustomPanel)\n    constructor Create(AOwner: TComponent); override;\n  end;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "hides-virtual",' + #10 +
    '      "name": "Method hides virtual method",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "A method has the same name as a virtual method of an ancestor but neither overrides nor reintroduces it (compiler warning W1010).",' + #10 +
    '      "bad": "type\n  TBase = class\n    procedure Run; virtual;\n  end;\n  TFoo = class(TBase)\n    procedure Run;\n  end;",' + #10 +
    '      "good": "type\n  TBase = class\n    procedure Run; virtual;\n  end;\n  TFoo = class(TBase)\n    procedure Run; override;\n  end;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "virtual-instead-of-override",' + #10 +
    '      "name": "virtual instead of override",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "A descendant declares a method virtual although the ancestor already has a virtual method with the same signature; this starts a new chain instead of overriding.",' + #10 +
    '      "bad": "type\n  TFoo = class(TBase)\n    procedure Run; virtual;\n  end;",' + #10 +
    '      "good": "type\n  TFoo = class(TBase)\n    procedure Run; override;\n  end;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "captured-loop-variable",' + #10 +
    '      "name": "Captured loop variable",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "An anonymous method passed to a deferred API (TThread.Queue, TTask.Run, ...) captures a variable that changes before it runs, such as a for-in loop variable. Delphi captures the ' + 'variable, not its value.",' + #10 +
    '      "bad": "for S in List do\n  TThread.Queue(nil, procedure begin Memo1.Lines.Add(S); end);",' + #10 +
    '      "good": "function CaptureS(const AValue: string): TProc;\nbegin\n  Result := procedure begin Memo1.Lines.Add(AValue); end;\nend;\n...\nfor S in List do\n  TThread.Queue(nil, CaptureS(S));"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-missing-inherited",' + #10 +
    '      "name": "Component method without inherited",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "An overridden Loaded, CreateParams, CreateWnd, Notification, SetParent, Destroy or Paint of a component does not call inherited, so the VCL skips its own work there. For Paint th' + 'e confidence is low, because TCustomControl.Paint only draws the design-time frame.",' + #10 +
    '      "bad": "procedure TMyControl.Loaded;\nbegin\n  UpdateLayout;\nend;",' + #10 +
    '      "good": "procedure TMyControl.Loaded;\nbegin\n  inherited;\n  UpdateLayout;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-default-mismatch",' + #10 +
    '      "name": "default does not match constructor",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "A property declares a default value, but the constructor sets its field to a different literal. The streaming system does not store values equal to default, so the property is lo' + 'aded wrongly from the DFM.",' + #10 +
    '      "bad": "property Size: Integer read FSize write FSize default 5;\n...\nFSize := 10;",' + #10 +
    '      "good": "property Size: Integer read FSize write FSize default 10;\n...\nFSize := 10;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-missing-free-notification",' + #10 +
    '      "name": "Component reference without FreeNotification",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "A component property refers to another component, but its setter does not call FreeNotification. When the other component is freed, a dangling pointer remains. Subcomponents crea' + 'ted in the constructor are ignored.",' + #10 +
    '      "bad": "procedure TMyControl.SetLink(const Value: TControl);\nbegin\n  FLink := Value;\nend;",' + #10 +
    '      "good": "procedure TMyControl.SetLink(const Value: TControl);\nbegin\n  FLink := Value;\n  if Value <> nil then Value.FreeNotification(Self);\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-setter-without-invalidate",' + #10 +
    '      "name": "Setter without Invalidate",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "description": "A property setter changes a field that Paint reads, but does not call Invalidate (or Repaint, Refresh, Changed). The control keeps showing the old state.",' + #10 +
    '      "bad": "procedure TMyControl.SetColor(const Value: TColor);\nbegin\n  FColor := Value;\nend;",' + #10 +
    '      "good": "procedure TMyControl.SetColor(const Value: TColor);\nbegin\n  FColor := Value;\n  Invalidate;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-fixed-pixels",' + #10 +
    '      "name": "Fixed pixel values",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "Paint or Resize uses fixed pixel values that are too small above 96 dpi. Values passed through ScaleValue or MulDiv, 0, 1 and -1, and factors of multiplications and divisions are' + ' not reported.",' + #10 +
    '      "bad": "Canvas.FillRect(Rect(0, 0, 16, 16));",' + #10 +
    '      "good": "Canvas.FillRect(Rect(0, 0, ScaleValue(16), ScaleValue(16)));"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-hardcoded-color",' + #10 +
    '      "name": "Hardcoded color in Paint",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "description": "Paint uses an RGB literal, a $00BBGGRR constant or a TColor cast. Such colors ignore VCL styles; system colors like clBtnFace are fine.",' + #10 +
    '      "bad": "Canvas.Brush.Color := $00FF8000;",' + #10 +
    '      "good": "Canvas.Brush.Color := StyleServices.GetSystemColor(clHighlight);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "form-field-without-object",' + #10 +
    '      "name": "Form field without object",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "A published component field of the form class has no object in the .dfm/.fmx next to the unit. After loading, the field stays nil. Fields outside published are not checked.",' + #10 +
    '      "bad": "Edit1: TEdit;  // object Edit1 was deleted from the form",' + #10 +
    '      "good": "// remove the field or restore the object"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "form-object-without-field",' + #10 +
    '      "name": "Form object without field",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "An object of the form file has no field in the form class. Inherited objects, objects inside inline frames, unnamed components and collection items are skipped. The fix adds the ' + 'field.",' + #10 +
    '      "bad": "object Button2: TButton  // no Button2 in TForm1",' + #10 +
    '      "good": "Button2: TButton;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "form-field-type-mismatch",' + #10 +
    '      "name": "Form field type differs from object",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "The field type differs from the class of the object in the form file. Without source for the class in the form file, nothing is compared. The fix changes the field type.",' + #10 +
    '      "bad": "Edit1: TEdit;  // object Edit1: TMaskEdit",' + #10 +
    '      "good": "Edit1: TMaskEdit;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "security-command-injection",' + #10 +
    '      "name": "Command injection",' + #10 +
    '      "category": "vulnerability",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "ShellExecute, ShellExecuteEx, CreateProcess or WinExec receives an argument built with +, Format or Concat from non-constant values. Input could inject further commands. Without ' + 'data flow analysis only this simple pattern is found (medium confidence).",' + #10 +
    '      "bad": "ShellExecute(0, ''open'', PChar(''cmd /c '' + Edit1.Text), nil, nil, SW_SHOW);",' + #10 +
    '      "good": "ShellExecute(0, ''open'', ''tool.exe'', PChar(QuotedArgument), nil, SW_SHOW);  // validated"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "security-path-traversal",' + #10 +
    '      "name": "Path traversal",' + #10 +
    '      "category": "vulnerability",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "A file access (TFileStream.Create, LoadFromFile, AssignFile, TFile.*) uses a path from input data (Text, ParamStr, Request) without TPath.GetFullPath check. Experimental until da' + 'ta flow analysis is available.",' + #10 +
    '      "bad": "List.LoadFromFile(''C:\\Data\\'' + Edit1.Text);",' + #10 +
    '      "good": "Path := TPath.GetFullPath(TPath.Combine(Root, Edit1.Text));  // then check it starts with Root"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "security-weak-crypto",' + #10 +
    '      "name": "Weak cryptography",' + #10 +
    '      "category": "security-hotspot",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "description": "MD5, SHA-1, DES or RC4 is used. For checksums this is fine; for passwords and signatures it is not. Low confidence, medium when the statement mentions a password, secret or signa' + 'ture.",' + #10 +
    '      "bad": "Stored := THashSHA1.GetHashString(PasswordText);",' + #10 +
    '      "good": "Stored := THashSHA2.GetHashString(Salt + PasswordText);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "security-tls-verification-disabled",' + #10 +
    '      "name": "TLS certificate check disabled",' + #10 +
    '      "category": "vulnerability",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "Indy SSLOptions.VerifyMode := [], an OnVerifyPeer handler that always returns True, or a ValidateServerCertificate handler that sets Accepted := True without a check.",' + #10 +
    '      "bad": "IdSSL.SSLOptions.VerifyMode := [];",' + #10 +
    '      "good": "IdSSL.SSLOptions.VerifyMode := [sslvrfPeer];"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "security-insecure-http",' + #10 +
    '      "name": "Unencrypted http:// URL",' + #10 +
    '      "category": "security-hotspot",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "description": "A string contains an http:// URL. XML namespaces and schema URIs, comments and localhost, 127.0.0.1 and [::1] are skipped. The fix replaces http:// with https://.",' + #10 +
    '      "bad": "Client.Get(''http://api.example.com/data'');",' + #10 +
    '      "good": "Client.Get(''https://api.example.com/data'');"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "security-insecure-random",' + #10 +
    '      "name": "Random for security values",' + #10 +
    '      "category": "security-hotspot",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "Random is assigned to a token, password, salt, nonce or key. Random is predictable; use a cryptographic random generator. Missing Randomize is a separate topic (#153).",' + #10 +
    '      "bad": "Token := IntToStr(Random(MaxInt));",' + #10 +
    '      "good": "Token := TNetEncoding.Base64URL.EncodeBytesToString(CryptoRandomBytes(32));"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dfm-circular-datasource",' + #10 +
    '      "name": "Circular master-detail or data source link",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "MasterSource/DataSource links in the form file form a cycle (tblA → dsB → tblB → dsA → tblA). Opening the datasets recurses or never shows consistent data.",' + #10 +
    '      "bad": "tblA.MasterSource = dsB; tblB.MasterSource = dsA",' + #10 +
    '      "good": "tblB.MasterSource = dsA  // tblA has no master"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dfm-master-without-fields",' + #10 +
    '      "name": "Master-detail without MasterFields",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "A dataset has MasterSource but no MasterFields. The detail is not filtered and shows all records.",' + #10 +
    '      "bad": "MasterSource = dsKunden",' + #10 +
    '      "good": "MasterSource = dsKunden; MasterFields = ''KundenID''"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dfm-required-field-without-control",' + #10 +
    '      "name": "Required field without visible input control",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "A persistent field with Required = True is bound to no visible data-aware control (a grid without DataField counts for all fields). The user cannot fill it and posting fails.",' + #10 +
    '      "bad": "tblKundenName: Required = True, no TDBEdit for Name",' + #10 +
    '      "good": "edName: TDBEdit; DataSource = dsKunden; DataField = ''Name''"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dfm-control-field-type-mismatch",' + #10 +
    '      "name": "Data-aware control does not fit the field type",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "The control does not suit the persistent field, e.g. TDBEdit on a TBooleanField or blob field, TDBImage on a non-graphic field.",' + #10 +
    '      "bad": "edAktiv: TDBEdit; DataField = ''Aktiv''  // TBooleanField",' + #10 +
    '      "good": "cbAktiv: TDBCheckBox; DataField = ''Aktiv''"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dfm-duplicate-binding",' + #10 +
    '      "name": "Two controls bound to the same field",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "Two input controls use the same DataSource and DataField. Usually a copy-and-paste error. Display controls (TDBText, TDBImage) are ignored.",' + #10 +
    '      "bad": "ed1, ed2: DataSource = dsA; DataField = ''Name''",' + #10 +
    '      "good": "ed1: DataField = ''Name''; ed2: DataField = ''Vorname''"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "dfm-property",' + #10 +
    '      "name": "Component property violates a property rule",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "A component property in the form file does not meet a rule from dfmPropertyRules in atlas.json (class, property, condition, value). A property that is not stored counts with its ' + 'default value; objects of the ancestor form are only reported where this form sets the value itself. The quick fix sets the value in the form file (fix: auto also with source.fixAll); the command \"Ap' + 'ply property rules\" corrects one form, the project or the group with a preview.",' + #10 +
    '      "bad": "// dfmPropertyRules: TLabel.Transparent = True\nobject Label1: TLabel\n  Caption = ''Name''\nend",' + #10 +
    '      "good": "object Label1: TLabel\n  Caption = ''Name''\n  Transparent = True\nend"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "foreign-form-control-access",' + #10 +
    '      "name": "Access to controls of another form",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "Code accesses a field of a form or frame from another unit through its global variable (Form2.Edit1.Text). This couples the units tightly; use a method or property of the form.",' + #10 +
    '      "bad": "Form2.Edit1.Text := ''x'';",' + #10 +
    '      "good": "Form2.Kundenname := ''x'';"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "security-sql-injection",' + #10 +
    '      "name": "SQL text built from values (SQL injection)",' + #10 +
    '      "category": "vulnerability",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "SQL.Text, SQL.Add, CommandText, ExecSQL or Open receives text built with + or Format from non-constant values. User input could inject SQL. Use parameters (:Name, ParamByName). C' + 'onstants, resourcestrings, IntToStr and QuotedStr are not reported; user input (TEdit.Text, TMemo.Lines) raises the confidence to high.",' + #10 +
    '      "bad": "Q.SQL.Text := ''select * from K where N = '''''' + Edit1.Text + '''''''';",' + #10 +
    '      "good": "Q.SQL.Text := ''select * from K where N = :N'';\nQ.ParamByName(''N'').AsString := Edit1.Text;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "slash-command",' + #10 +
    '      "name": "Quick command not executed",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "description": "A line starting with /name was not executed and stays in the code: the command is unknown, switched off (slashCommands.disabled) or does not fit at this place. The message names ' + 'the reason.",' + #10 +
    '      "bad": "/gibtsnicht X",' + #10 +
    '      "good": "/uses System.Classes"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "empty-except",' + #10 +
    '      "name": "Empty except block",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "An except block without statements swallows every exception. A block that contains only a comment counts as deliberate and is not reported.",' + #10 +
    '      "bad": "try\n  Save;\nexcept\nend;",' + #10 +
    '      "good": "try\n  Save;\nexcept\n  on E: EInOutError do\n    Log(E.Message);\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "interface-guid",' + #10 +
    '      "name": "Interface without GUID",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "An interface declares no GUID. Supports, as and QueryInterface need one. The confidence is high when the interface is used with them in the same file, otherwise low. The quick fi' + 'x inserts a new GUID.",' + #10 +
    '      "bad": "type\n  ISaver = interface\n    procedure Save;\n  end;",' + #10 +
    '      "good": "type\n  ISaver = interface\n    [''{6C1D2A57-0E3B-4F8A-9B2D-5A7E4C3F1D08}'']\n    procedure Save;\n  end;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "duplicate-interface-guid",' + #10 +
    '      "name": "Two interfaces with the same GUID",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "description": "Two interfaces in the file declare the same GUID, usually after copying a declaration. Supports and as then mix them up. The quick fix generates a new GUID.",' + #10 +
    '      "bad": "ILoader = interface\n  [''{6C1D2A57-0E3B-4F8A-9B2D-5A7E4C3F1D08}'']\nend;\nISaver = interface\n  [''{6C1D2A57-0E3B-4F8A-9B2D-5A7E4C3F1D08}'']\nend;",' + #10 +
    '      "good": "ILoader = interface\n  [''{6C1D2A57-0E3B-4F8A-9B2D-5A7E4C3F1D08}'']\nend;\nISaver = interface\n  [''{0B9E4F21-7C6D-4A3E-8F15-2D9C7B6A4E31}'']\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "file-header",' + #10 +
    '      "name": "File header missing or different",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "description": "The file does not start with the header from the rule option \"template\". Off by default; switch it on in atlas.json with a template. The quick fix inserts the header.",' + #10 +
    '      "bad": "unit Tools;",' + #10 +
    '      "good": "// Copyright (c) Example GmbH\nunit Tools;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "hardcoded-string",' + #10 +
    '      "name": "Text in code instead of resourcestring",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "description": "A string literal with words for people stands in a statement. Move it to a resourcestring so it can be translated. Off by default, low confidence.",' + #10 +
    '      "bad": "ShowMessage(''File not found'');",' + #10 +
    '      "good": "resourcestring\n  SFileNotFound = ''File not found'';\n...\nShowMessage(SFileNotFound);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "self-assignment",' + #10 +
    '      "name": "Assignment to itself",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "A variable, field or property is assigned to itself. Usually a different value was meant, for example a parameter or another field. If a parameter or local variable hides a field' + ' of the same name (Name := Name), Atlas offers Self.Name := Name as the fix.",' + #10 +
    '      "bad": "FName := FName;",' + #10 +
    '      "good": "FName := AName;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "for-high-to-low",' + #10 +
    '      "name": "for loop counts down with to",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "The loop starts at the upper bound (High, Count - 1) and ends at the lower one, but uses to. It never runs; downto was meant.",' + #10 +
    '      "bad": "for I := High(A) to Low(A) do\n  Save(A[I]);",' + #10 +
    '      "good": "for I := High(A) downto Low(A) do\n  Save(A[I]);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "exception-not-raised",' + #10 +
    '      "name": "Exception created but not raised",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "An exception object is created as a statement on its own. Without raise nothing happens and the object leaks.",' + #10 +
    '      "bad": "if X = nil then\n  EArgumentException.Create(''X missing'');",' + #10 +
    '      "good": "if X = nil then\n  raise EArgumentException.Create(''X missing'');"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "assert-side-effect",' + #10 +
    '      "name": "Assert with side effect",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "The argument of Assert changes data (Inc, Dec, a Try… function with an out parameter or a method from the option mutatingMethods). With {$C-} the compiler removes the whole call ' + 'including the side effect.",' + #10 +
    '      "bad": "Assert(List.Remove(X) >= 0);",' + #10 +
    '      "good": "Index := List.Remove(X);\nAssert(Index >= 0);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "ifthen-side-effect",' + #10 +
    '      "name": "IfThen evaluates both branches",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "IfThen is a function: both branches are evaluated before the call. A nil access or a function call in the branch that is not chosen still happens. High confidence when a branch d' + 'ereferences a name checked in the condition, medium for a function call.",' + #10 +
    '      "bad": "S := IfThen(Assigned(X), X.Name, '''');",' + #10 +
    '      "good": "if Assigned(X) then S := X.Name else S := '''';"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "random-without-randomize",' + #10 +
    '      "name": "Random without Randomize",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "description": "Random is used, but the unit never calls Randomize, so every start yields the same sequence. Randomize often sits in the .dpr, so the rule is off by default and has low confidenc' + 'e.",' + #10 +
    '      "bad": "Dice := Random(6) + 1;",' + #10 +
    '      "good": "Randomize; // once at program start\n...\nDice := Random(6) + 1;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "int32-mul-overflow",' + #10 +
    '      "name": "Int32 multiplication assigned to Int64",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "Both operands have at most 32 bits, so the product is computed in 32 bits and overflows before it is assigned to the Int64 variable. Cast one operand to Int64.",' + #10 +
    '      "bad": "Total := Width * Height; // Total: Int64; Width, Height: Integer",' + #10 +
    '      "good": "Total := Int64(Width) * Height;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "sizeof-pointer",' + #10 +
    '      "name": "SizeOf of a pointer in Move or FillChar",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "description": "SizeOf of a pointer, string or dynamic array is the size of the reference (4 or 8 bytes), not of the data. Move and FillChar then copy or clear too little.",' + #10 +
    '      "bad": "FillChar(Buffer[0], SizeOf(Buffer), 0); // Buffer: TBytes",' + #10 +
    '      "good": "FillChar(Buffer[0], Length(Buffer) * SizeOf(Buffer[0]), 0);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "char-to-pchar",' + #10 +
    '      "name": "Char cast to PChar",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "description": "PChar(C) with a Char variable turns the character code into an address. A string was meant.",' + #10 +
    '      "bad": "ShowMessage(PChar(C)); // C: Char",' + #10 +
    '      "good": "ShowMessage(PChar(string(C)));"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "float-equality",' + #10 +
    '      "name": "Floating-point comparison with = or <>",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "description": "Floating-point values are rarely exactly equal after calculations. Compare with SameValue from System.Math and a tolerance. Comparisons with 0 are not reported.",' + #10 +
    '      "bad": "if Total = Expected then",' + #10 +
    '      "good": "if SameValue(Total, Expected) then"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "constructor-on-instance",' + #10 +
    '      "name": "Constructor called on an instance",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "Create is called on a variable instead of the class. That does not create a new object; with an unassigned variable it crashes. Class references (class of …) are not reported.",' + #10 +
    '      "bad": "List.Create; // List: TStringList",' + #10 +
    '      "good": "List := TStringList.Create;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "format-without-settings",' + #10 +
    '      "name": "Formatting depends on the locale",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "description": "Format with %f, %n, %m, %g or %e and functions like FloatToStr, StrToFloat or DateToStr without a TFormatSettings parameter use the user''s locale (decimal separator, date format)' + '. For files, protocols and logs pass fixed TFormatSettings. Format(''%d'', …) is not reported.",' + #10 +
    '      "bad": "Line := Format(''%.2f'', [Amount]);",' + #10 +
    '      "good": "Line := Format(''%.2f'', [Amount], TFormatSettings.Invariant);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "generic-exception-raised",' + #10 +
    '      "name": "Generic exception raised",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "description": "Raising the base class Exception prevents callers from handling the error specifically. Declare a dedicated exception class.",' + #10 +
    '      "bad": "raise Exception.Create(''Customer missing'');",' + #10 +
    '      "good": "raise ECustomerMissing.Create(''Customer missing'');"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "catch-all-without-raise",' + #10 +
    '      "name": "Catch-all handler without re-raise",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "A handler for Exception that neither re-raises nor ends the program swallows every error, including programming errors. Off by default; intended for library code.",' + #10 +
    '      "bad": "except\n  on E: Exception do\n    Log(E.Message);\nend;",' + #10 +
    '      "good": "except\n  on E: Exception do\n  begin\n    Log(E.Message);\n    raise;\n  end;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "exception-freed",' + #10 +
    '      "name": "Exception object freed manually",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "error",' + #10 +
    '      "description": "The RTL frees an exception object after its handler or after raise. Freeing it manually causes a double free.",' + #10 +
    '      "bad": "on E: Exception do\n  E.Free;",' + #10 +
    '      "good": "on E: Exception do\n  Log(E.Message);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "string-concat-in-loop",' + #10 +
    '      "name": "String concatenation in a loop",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "description": "A string variable is extended step by step inside a loop. Delphi usually grows strings in place, so this is reported only with low confidence and is off by default; for many iter' + 'ations TStringBuilder is faster.",' + #10 +
    '      "bad": "for I := 1 to 10000 do\n  S := S + IntToStr(I);",' + #10 +
    '      "good": "Builder := TStringBuilder.Create;\ntry\n  for I := 1 to 10000 do\n    Builder.Append(I);\n  S := Builder.ToString;\nfinally\n  Builder.Free;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "loop-invariant-call",' + #10 +
    '      "name": "Expensive call in a loop condition",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "description": "The condition of while and until is evaluated on every iteration. Calls like Trim, Format or FileExists and properties like Lines.Text there are recomputed each time; compute the' + 'm once before the loop. Bounds of for loops are evaluated only once and are not reported. Off by default.",' + #10 +
    '      "bad": "while I < Length(Trim(Memo.Lines.Text)) do\n  Inc(I);",' + #10 +
    '      "good": "Text := Trim(Memo.Lines.Text);\nwhile I < Length(Text) do\n  Inc(I);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "missing-begin-update",' + #10 +
    '      "name": "Adding items in a loop without BeginUpdate",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "description": "Items.Add, Lines.Add and similar calls in a loop repaint the control on every call. Wrap the loop in BeginUpdate and try … finally EndUpdate. Off by default.",' + #10 +
    '      "bad": "for I := 1 to 1000 do\n  ListBox1.Items.Add(IntToStr(I));",' + #10 +
    '      "good": "ListBox1.Items.BeginUpdate;\ntry\n  for I := 1 to 1000 do\n    ListBox1.Items.Add(IntToStr(I));\nfinally\n  ListBox1.Items.EndUpdate;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "bool-compare",' + #10 +
    '      "name": "Comparison with True or False",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "description": "Comparing a Boolean with True or False is redundant; use the expression or not directly.",' + #10 +
    '      "bad": "if Visible = True then\n  Show;",' + #10 +
    '      "good": "if Visible then\n  Show;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "redundant-assigned-free",' + #10 +
    '      "name": "Assigned check before Free",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "description": "Free already checks for nil, so testing Assigned before Free or FreeAndNil is redundant.",' + #10 +
    '      "bad": "if Assigned(List) then\n  List.Free;",' + #10 +
    '      "good": "List.Free;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "raise-in-finally",' + #10 +
    '      "name": "raise in a finally block",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "An exception raised in a finally block replaces the exception that is currently propagating, which is then lost.",' + #10 +
    '      "bad": "try\n  Work;\nfinally\n  raise Exception.Create(''Fehler'');\nend;",' + #10 +
    '      "good": "try\n  Work;\nfinally\n  Cleanup;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "redundant-parens",' + #10 +
    '      "name": "Redundant parentheses",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "description": "Parentheses around a whole condition or a single identifier add nothing. Off by default.",' + #10 +
    '      "bad": "if (Done) then\n  Exit;",' + #10 +
    '      "good": "if Done then\n  Exit;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "redundant-begin-end",' + #10 +
    '      "name": "begin … end around a single statement",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "description": "A begin … end block that holds exactly one statement can be removed. Off by default.",' + #10 +
    '      "bad": "if Done then\nbegin\n  Exit;\nend;",' + #10 +
    '      "good": "if Done then\n  Exit;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "with-statement",' + #10 +
    '      "name": "with statement",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "description": "Inside a with block it is unclear which object an identifier belongs to, and a new member of the with object silently changes the meaning. Write the expression out or use a local' + ' variable.",' + #10 +
    '      "bad": "with Customer do\n  Name := Edit.Text;",' + #10 +
    '      "good": "Customer.Name := Edit.Text;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-method-length",' + #10 +
    '      "name": "Method too long",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "description": "The method has more code lines than the limit (default 60). Blank lines, comments, compiler directives and local routines do not count. Split the method into smaller ones. Set th' + 'e limit with the option max, e.g. \"rules\": {\"metric-method-length\": {\"max\": 80}}.",' + #10 +
    '      "bad": "procedure TImport.Run;\nbegin\n  // 120 lines: read, check, convert and save\nend;",' + #10 +
    '      "good": "procedure TImport.Run;\nbegin\n  Read;\n  Check;\n  Convert;\n  Save;\nend;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-nesting-depth",' + #10 +
    '      "name": "Nesting too deep",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "description": "The method nests if, case, loops and try deeper than the limit (default 4). else if stays on the level of its if. Leave early with Exit or Continue, or move inner parts into thei' + 'r own methods. Set the limit with the option max.",' + #10 +
    '      "bad": "for Item in Items do\n  if Item.Active then\n    for Line in Item.Lines do\n      if Line.Valid then\n        try\n          Save(Line);\n        except\n          Log;\n        end;",' + #10 +
    '      "good": "for Item in Items do\n  if Item.Active then\n    SaveLines(Item);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-cyclomatic-complexity",' + #10 +
    '      "name": "Cyclomatic complexity too high",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "description": "The cyclomatic complexity of the method is above the limit (default 15). It starts at 1 and adds 1 for every if, while, repeat and for, every case branch without else, every and/' + 'or in a condition and every except on; an except without on counts once. Many paths need many tests. Set the limit with the option max.",' + #10 +
    '      "bad": "case Kind of\n  1: A;\n  2: B;\n  // ... 20 branches\nend;",' + #10 +
    '      "good": "Handlers[Kind]();"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-cognitive-complexity",' + #10 +
    '      "name": "Cognitive complexity too high",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "description": "The cognitive complexity of the method is above the limit (default 15). Following SonarSource, if, case, loops and except handlers count 1 plus their nesting level; else, else if' + ', goto and every sequence of equal logical operators count 1. Nested code is harder to read than code in sequence. Set the limit with the option max.",' + #10 +
    '      "bad": "if A then\n  for I := 0 to N do\n    if B and C or D then\n      while E do\n        F;",' + #10 +
    '      "good": "if not A then\n  Exit;\nfor I := 0 to N do\n  ProcessItem(I);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-parameter-count",' + #10 +
    '      "name": "Too many parameters",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "description": "The method has more parameters than the limit (default 6). Group related values in a record or class. Set the limit with the option max.",' + #10 +
    '      "bad": "procedure Book(const AName, AStreet, ACity, AZip: string; AAmount: Currency; ADate: TDate; ANote: string);",' + #10 +
    '      "good": "procedure Book(const AAddress: TAddress; const AOrder: TOrder);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "todo-comment",' + #10 +
    '      "name": "Open TODO comment",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "description": "A comment starts with a marker for open work: // TODO, // FIXME or the IDE to-do format { TODO 1 -oOwner -cCategory : Text }. The hint shows marker, priority, category, owner and' + ' text, so open work appears in the problem list. Off by default; switch it on in atlas.json, e.g. \"rules\": {\"todo-comment\": {\"severity\": \"hint\"}}. Completed entries ({ DONE … }) are never repo' + 'rted. The option keywords sets the markers (default [\"TODO\", \"FIXME\"]); it also applies to get_todos and --todos.",' + #10 +
    '      "bad": "// TODO 1 -oMarco -cGUI : set focus\nEdit.Text := '''';",' + #10 +
    '      "good": "Edit.Text := '''';\nEdit.SetFocus;"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "component-palette-icon",' + #10 +
    '      "name": "Registered component without palette icon",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "hint",' + #10 +
    '      "description": "Every class passed to RegisterComponents needs a bitmap named after the class in upper case in a .dcr or .res included with {$R}. From Delphi 11 the sizes 16, 24 and 32 px (NAME1' + '6, NAME24, NAME32) are expected as well. Silent when the unit includes no readable resource file.",' + #10 +
    '      "bad": "{$R *.dcr} // without TMYBUTTON\nRegisterComponents(''Samples'', [TMyButton]);",' + #10 +
    '      "good": "{$R *.dcr} // with TMYBUTTON16, TMYBUTTON24, TMYBUTTON32\nRegisterComponents(''Samples'', [TMyButton]);"' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unresolved-identifier",' + #10 +
    '      "name": "Unresolved identifier",' + #10 +
    '      "category": "bug",' + #10 +
    '      "severity": "warning",' + #10 +
    '      "description": "An identifier in a statement is declared neither in the unit nor in the units it uses (like compiler error E2003). Checked while typing, without the compiler; with blocks, asm an' + 'd anonymous methods are skipped.",' + #10 +
    '      "bad": "procedure Foo;\nbegin\n  Lst.Add(''x'');\nend;",' + #10 +
    '      "good": "procedure Foo;\nvar\n  Lst: TStringList;\nbegin\n  Lst := TStringList.Create;\n  Lst.Add(''x'');\nend;"' + #10 +
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
    '      "description": "Ein uses-Eintrag verletzt eine Schichtregel unter \"layers\" in atlas.json, z. B. darf *.Common.* nicht Vcl.* verwenden."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "architecture-role-import",' + #10 +
    '      "name": "Import verletzt die Rollenmatrix",' + #10 +
    '      "description": "Ein uses-Eintrag verletzt die Importmatrix des Rollenkonzepts (Ausgabeartefakt, Feature, Rolle: Contract, Internals, Providers, Adapters, Composition, Hosting). Standardmäßig aus' + '; in atlas.json mit der Option \"prefixes\" einschalten. Genehmigte Ausnahmen stehen unter \"allow\" als \"Quelle -> Ziel\"-Globs."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "architecture-contract-content",' + #10 +
    '      "name": "Klasse in einer Contract-Unit",' + #10 +
    '      "description": "Eine Contract-Unit deklariert im interface eine Klasse. Contracts enthalten nur Records, Interfaces, Aufzählungen und Ausnahmen. Standardmäßig aus; in atlas.json mit der Option \' + '"prefixes\" einschalten. Genehmigte Ausnahmen stehen unter \"allow\" als \"Unit.Typ\"-Globs."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "thread-vcl-access",' + #10 +
    '      "name": "VCL-Zugriff aus einem Thread",' + #10 +
    '      "description": "TThread.Execute, TThread.CreateAnonymousThread oder TTask greift außerhalb von Synchronize oder Queue auf die VCL zu (Application, Screen, ShowMessage, MessageDlg …). Die VCL ist' + ' nicht threadsicher."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "lock-without-finally",' + #10 +
    '      "name": "Sperre ohne try/finally",' + #10 +
    '      "description": "Auf eine Sperre (TCriticalSection.Enter/Acquire, TMonitor.Enter, BeginRead/BeginWrite, TSpinLock.Enter, TMutex.Acquire, EnterCriticalSection oder ein Paar aus der Option lockPair' + 's) folgt kein try/finally mit der Freigabe. Eine Ausnahme lässt die Sperre gesetzt."' + #10 +
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
    '      "description": "Eine lokale Variable ist deklariert, wird aber nie verwendet. Wie Compilerhinweis H2164, aber schon beim Tippen."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unused-parameter",' + #10 +
    '      "name": "Ungenutzter Parameter",' + #10 +
    '      "description": "Ein Parameter wird im Rumpf der Routine nicht verwendet. Ausgenommen sind überschriebene und virtuelle Methoden, Ereignis-Handler, published-Methoden, Interface-Implementierungen' + ' und Callbacks."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "unused-assignment",' + #10 +
    '      "name": "Zugewiesener Wert ungenutzt",' + #10 +
    '      "description": "Ein einer lokalen Variable zugewiesener Wert wird überschrieben oder die Routine endet, bevor er gelesen wird. Wie Compilerhinweis H2077."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "declared-not-implemented",' + #10 +
    '      "name": "Deklariert, aber nicht implementiert",' + #10 +
    '      "description": "Eine Methode ist in einer Klasse, einem Record oder Objekt deklariert, hat aber keinen Rumpf im implementation-Abschnitt. Der Compiler meldet das erst beim Kompilieren (E2065)."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "implemented-not-declared",' + #10 +
    '      "name": "Implementiert, aber nicht deklariert",' + #10 +
    '      "description": "Ein Methodenrumpf TFoo.Bar hat keine passende Deklaration im Typ."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "destroy-without-override",' + #10 +
    '      "name": "Destroy ohne override",' + #10 +
    '      "description": "Ein destructor Destroy ist ohne override deklariert. Free ruft TObject.Destroy auf, dieser Destruktor läuft also nie."' + #10 +
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
    '      "description": "Eine anonyme Methode, die an eine verzögert ausführende API (TThread.Queue, TTask.Run …) geht, erfasst eine Variable, die sich vor dem Aufruf noch ändert, etwa die Variable einer' + ' for-in-Schleife. Delphi erfasst die Variable, nicht ihren Wert."' + #10 +
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
    '      "description": "Eine Zeile, die mit /name beginnt, wurde nicht ausgeführt und steht noch im Code: Der Befehl ist unbekannt, abgeschaltet (slashCommands.disabled) oder passt an dieser Stelle nich' + 't. Die Meldung nennt den Grund."' + #10 +
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
    '      "description": "Die Datei beginnt nicht mit dem Kopf aus der Regeloption \"template\". Standardmäßig aus; in atlas.json mit einer Vorlage einschalten. Die Schnellkorrektur fügt den Kopf ein."' + #10 +
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
    '      "description": "Das Argument von Assert verändert Daten (Inc, Dec, eine Try…-Funktion mit out-Parameter oder eine Methode aus der Option mutatingMethods). Mit {$C-} entfernt der Compiler den gan' + 'zen Aufruf samt Seiteneffekt."' + #10 +
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
    '      "description": "Die Methode hat mehr Codezeilen als der Grenzwert (Vorgabe 60). Leerzeilen, Kommentare, Compiler-Direktiven und lokale Routinen zählen nicht mit. Die Methode in kleinere aufteile' + 'n. Den Grenzwert setzt die Option max, z. B. \"rules\": {\"metric-method-length\": {\"max\": 80}}."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-nesting-depth",' + #10 +
    '      "name": "Zu tief verschachtelt",' + #10 +
    '      "description": "Die Methode verschachtelt if, case, Schleifen und try tiefer als der Grenzwert (Vorgabe 4). else if bleibt auf der Ebene seines if. Mit Exit oder Continue früh verlassen oder inn' + 'ere Teile in eigene Methoden auslagern. Den Grenzwert setzt die Option max."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-cyclomatic-complexity",' + #10 +
    '      "name": "Zyklomatische Komplexität zu hoch",' + #10 +
    '      "description": "Die zyklomatische Komplexität der Methode liegt über dem Grenzwert (Vorgabe 15). Sie beginnt bei 1 und steigt um 1 je if, while, repeat und for, je case-Zweig ohne else, je and/o' + 'r in einer Bedingung und je except on; ein except ohne on zählt einmal. Viele Pfade brauchen viele Tests. Den Grenzwert setzt die Option max."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-cognitive-complexity",' + #10 +
    '      "name": "Kognitive Komplexität zu hoch",' + #10 +
    '      "description": "Die kognitive Komplexität der Methode liegt über dem Grenzwert (Vorgabe 15). Nach SonarSource zählen if, case, Schleifen und except-Behandler 1 plus ihre Schachtelungsebene; else' + ', else if, goto und jede Folge gleicher logischer Operatoren zählen 1. Verschachtelter Code ist schwerer zu lesen als Code hintereinander. Den Grenzwert setzt die Option max."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "metric-parameter-count",' + #10 +
    '      "name": "Zu viele Parameter",' + #10 +
    '      "description": "Die Methode hat mehr Parameter als der Grenzwert (Vorgabe 6). Zusammengehörige Werte in einem Record oder einer Klasse bündeln. Den Grenzwert setzt die Option max."' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '      "id": "todo-comment",' + #10 +
    '      "name": "Offener TODO-Kommentar",' + #10 +
    '      "description": "Ein Kommentar beginnt mit einer Marke für offene Arbeit: // TODO, // FIXME oder das Format der IDE-To-Do-Liste { TODO 1 -oPerson -cKategorie : Text }. Der Hinweis zeigt Marke, Pr' + 'iorität, Kategorie, Person und Text, damit offene Arbeit in der Problemliste erscheint. In der Vorgabe aus; in atlas.json einschalten, z. B. \"rules\": {\"todo-comment\": {\"severity\": \"hint\"}}. Er' + 'ledigte Einträge ({ DONE … }) meldet die Regel nie. Die Option keywords legt die Marken fest (Vorgabe [\"TODO\", \"FIXME\"]); sie gilt auch für get_todos und --todos."' + #10 +
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
    '    }' + #10 +
    '  ]' + #10 +
    '}' + #10 +
    '' + #10);
  Result := '';
end;

end.
