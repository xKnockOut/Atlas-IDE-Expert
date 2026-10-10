unit Argus.Common.Rules.Catalog.Data;

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
    '      "id": "forbidden-uses",' + #10 +
    '      "name": "Forbidden uses",' + #10 +
    '      "category": "code-smell",' + #10 +
    '      "severity": "error",' + #10 +
    '      "description": "A uses entry violates a layer rule configured under \"layers\" in argus.json, e.g. *.Common.* must not use Vcl.*.",' + #10 +
    '      "bad": "unit App.Common.Model;\ninterface\nuses Vcl.Forms;",' + #10 +
    '      "good": "unit App.Common.Model;\ninterface\nuses System.Classes;"' + #10 +
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
    '      "id": "forbidden-uses",' + #10 +
    '      "name": "Verbotene uses-Beziehung",' + #10 +
    '      "description": "Ein uses-Eintrag verletzt eine Schichtregel unter \"layers\" in argus.json, z. B. darf *.Common.* nicht Vcl.* verwenden."' + #10 +
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
    '    }' + #10 +
    '  ]' + #10 +
    '}' + #10 +
    '' + #10);
  Result := '';
end;

end.
