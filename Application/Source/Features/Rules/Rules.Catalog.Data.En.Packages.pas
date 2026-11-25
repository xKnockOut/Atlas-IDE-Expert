unit Rules.Catalog.Data.En.Packages;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog.json.
// Nicht von Hand ändern.

interface

const
  cCatalogLinesEnPackages: array[0..270] of string = (
    '{',
    '      "id": "implicit-package-import",',
    '      "name": "Implicit package import",',
    '      "category": "code-smell",',
    '      "severity": "warning",',
    '      "group": "packages",',
    '      "description": "In a package (.dpk) a unit from contains uses a unit that is neither in contains nor provided by a package in requires. The compiler pulls it in implicitly (W1033), which later c' +
    'auses duplicate units when another package also contains it. The quick fix adds the unit to contains.",',
    '      "bad": "package Werkzeuge;\nrequires rtl;\ncontains\n  uHaupt in ''uHaupt.pas'';  // uHaupt uses uMathe\nend.",',
    '      "good": "package Werkzeuge;\nrequires rtl;\ncontains\n  uHaupt in ''uHaupt.pas'',\n  uMathe in ''uMathe.pas'';\nend.",',
    '      "safeFix": false',
    '    },',
    '{',
    '      "id": "ota-notifier-not-removed",',
    '      "name": "IDE notifier without RemoveNotifier",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "packages",',
    '      "description": "AddNotifier on IOTAServices, IOTAEditorServices, IOTAModule and so on (or another pair from registerPairs) whose index never reaches RemoveNotifier: the call is a statement witho' +
    'ut assignment, or the variable it is assigned to is never passed to RemoveNotifier in the unit (in finalization, a destructor or Destroyed). The IDE then calls the notifier after the package is unload' +
    'ed, in memory that no longer holds the code. Register… calls inside the procedure Register are exempt: the IDE removes those wizards itself. So is Result := X.AddNotifier(…) inside a method AddNotifie' +
    'r of your own (implementing an interface with its own notifier pair): the caller gets the index and removes it with RemoveNotifier. Medium confidence. Quick fix in methods: keep the index in a field (' +
    'FNotifierIndex in the private section) and add RemoveNotifier to the destructor, which is created if missing; in procedures of the unit: a global variable initialized with -1 and RemoveNotifier in fin' +
    'alization. No quick fix when the receiver is a parameter or local variable.",',
    '      "bad": "procedure Register;\nbegin\n  (BorlandIDEServices as IOTAServices).AddNotifier(TSpeicherNotifier.Create);\nend;",',
    '      "good": "var\n  NotifierIndex: Integer = -1;\n\nprocedure Register;\nbegin\n  NotifierIndex := (BorlandIDEServices as IOTAServices).AddNotifier(TSpeicherNotifier.Create);\nend;\n\ninitialization' +
    '\n\nfinalization\n  if NotifierIndex >= 0 then\n    (BorlandIDEServices as IOTAServices).RemoveNotifier(NotifierIndex);",',
    '      "options": [',
    '        {',
    '          "name": "registerPairs",',
    '          "type": "json",',
    '          "default": [',
    '            {',
    '              "open": "AddNotifier",',
    '              "close": "RemoveNotifier"',
    '            },',
    '            {',
    '              "open": "RegisterPackageWizard",',
    '              "close": "RemoveWizard"',
    '            }',
    '          ],',
    '          "description": "Pairs of the Open Tools API as [{\"open\": \"AddNotifier\", \"close\": \"RemoveNotifier\"}]; replaces the default."',
    '        }',
    '      ],',
    '      "safeFix": false',
    '    },',
    '{',
    '      "id": "ota-entry-without-guard",',
    '      "name": "IDE entry point lets exceptions through",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "packages",',
    '      "description": "A method that the IDE calls can let an exception through to the IDE, which shows it as an error message or, in the worst case, aborts saving or loading. Entry points are the publ' +
    'ic and published methods of a class that implements an interface from the interfaces option, also through ancestors (default IOTA*Notifier*, INTA*Notifier*, IOTA*Wizard*, IOTAKeyboardBinding, INTACust' +
    'omDrawMessage, IOTALocalMenu, IOTAProjectManagerMenu), the methods such a class passes to AddKeyBinding or AddMenuCommand, and in package units that hang menu entries into the IDE (INTAServices, MainM' +
    'enu, AddActionMenu, the editor or project manager menu) the methods a routine assigns to OnClick or OnExecute when it names TMenuItem or TAction; handlers of an own context menu are caught by the appl' +
    'ication. Reported when the body contains something that can raise (a call, raise, a cast with as) outside a try … except that catches every exception and outside the call of a guard routine from the g' +
    'uards option; a raise in the handler counts. Built-in and pure RTL routines (Length, Assigned, Supports, Copy, SameText …), type casts (also T…(x) and I…(x) with types the index does not know, such as' +
    ' VCL types), inherited, anonymous methods (they run later) and calls of routines of the unit whose body cannot raise do not count. Bodies that only assign values (fields, Result) stay silent. High con' +
    'fidence. Quick fixes: pass the body as an anonymous method to the first guard routine (with a parenthesis the entry is the beginning of the call, e.g. \"TAtlasGuard.Run(TAtlasFeature.Menu, \"; not whe' +
    'n the body uses Result, var or out parameters or inherited), or, with a field of type ILogger, wrap it in try … except and log the message with Error.",',
    '      "bad": "procedure TSaveNotifier.FileNotification(NotifyCode: TOTAFileNotification;\n  const FileName: string; var Cancel: Boolean);\nbegin\n  if FileName = '''' then\n    raise Exception.Create(''l' +
    'eer'');\nend;",',
    '      "good": "procedure TSaveNotifier.FileNotification(NotifyCode: TOTAFileNotification;\n  const FileName: string; var Cancel: Boolean);\nbegin\n  try\n    Pruefen(FileName);\n  except\n    on E: Ex' +
    'ception do\n      FLogger.Error(E.Message);\n  end;\nend;",',
    '      "options": [',
    '        {',
    '          "name": "guards",',
    '          "type": "string-list",',
    '          "default": [],',
    '          "description": "Guard routines that protect the body, e.g. TAtlasGuard.Run; the text before a parenthesis counts. The quick fix uses the first entry, with a parenthesis as the beginning of t' +
    'he call."',
    '        },',
    '        {',
    '          "name": "interfaces",',
    '          "type": "string-list",',
    '          "default": [',
    '            "IOTA*Notifier*",',
    '            "INTA*Notifier*",',
    '            "IOTA*Wizard*",',
    '            "IOTAKeyboardBinding",',
    '            "INTACustomDrawMessage",',
    '            "IOTALocalMenu",',
    '            "IOTAProjectManagerMenu"',
    '          ],',
    '          "description": "Interfaces whose methods are entry points (patterns with * and ?)."',
    '        }',
    '      ],',
    '      "safeFix": false',
    '    },',
    '{',
    '      "id": "register-does-work",',
    '      "name": "Register starts work instead of only registering",',
    '      "category": "code-smell",',
    '      "severity": "warning",',
    '      "group": "packages",',
    '      "description": "The procedure Register of a package (or another entry routine from the entries option) starts work instead of only registering: a call from workCalls (default Sleep, WaitFor…, Cr' +
    'eateProcess, ShellExecute…, Application.CreateForm, ShowModal, ShowMessage, MessageDlg, TTask.Run, TThread.CreateAnonymousThread) or creating a class from workClasses or one of its descendants (defaul' +
    't TTimer, TThread, TForm, THTTPClient, TIdHTTP). Register runs while the IDE starts, in no guaranteed order of the packages; work there lengthens the start and may touch packages that are not loaded y' +
    'et. Routines of the unit that are only reached from the entry routine (free routines of the implementation part, private methods of the same class) are checked too; anonymous methods and routines pass' +
    'ed as arguments run later and do not count. Registering stays allowed (RegisterPackageWizard, RegisterComponents, AddNotifier …). An entry with a dot matches the whole routine name (*.RegisterModule),' +
    ' without a dot only free routines. High confidence in the entry routine, medium in a helper. No quick fix: move the start into a wizard, a notifier or the feature table.",',
    '      "bad": "procedure Register;\nbegin\n  GTimer := TTimer.Create(nil);\n  GTimer.Enabled := True;\n  RegisterPackageWizard(TMyWizard.Create);\nend;",',
    '      "good": "procedure Register;\nbegin\n  // The wizard starts the timer once the IDE has loaded.\n  RegisterPackageWizard(TMyWizard.Create);\nend;",',
    '      "options": [',
    '        {',
    '          "name": "workCalls",',
    '          "type": "string-list",',
    '          "default": [',
    '            "Sleep",',
    '            "WaitFor*",',
    '            "CreateProcess",',
    '            "ShellExecute*",',
    '            "Application.CreateForm",',
    '            "ShowModal",',
    '            "ShowMessage",',
    '            "MessageDlg",',
    '            "TTask.Run",',
    '            "TThread.CreateAnonymousThread"',
    '          ],',
    '          "description": "Calls that count as work; with a dot the whole call (TTask.Run), otherwise the last name part; patterns with * and ?."',
    '        },',
    '        {',
    '          "name": "workClasses",',
    '          "type": "string-list",',
    '          "default": [',
    '            "TTimer",',
    '            "TThread",',
    '            "TForm",',
    '            "THTTPClient",',
    '            "TIdHTTP"',
    '          ],',
    '          "description": "Classes whose creation counts as work, including their descendants."',
    '        },',
    '        {',
    '          "name": "entries",',
    '          "type": "string-list",',
    '          "default": [',
    '            "Register"',
    '          ],',
    '          "description": "Entry routines, e.g. also *.RegisterModule; with a dot the whole name, otherwise only free routines."',
    '        }',
    '      ],',
    '      "safeFix": false',
    '    },',
    '{',
    '      "id": "dunitx-test-without-assert",',
    '      "name": "DUnitX test without assert",',
    '      "category": "code-smell",',
    '      "severity": "hint",',
    '      "group": "packages",',
    '      "description": "A [Test] or [TestCase] method that calls no check, neither itself nor through its local routines, methods of the same class, routines of the unit or free routines of other units ' +
    'known to the symbol index (AssertTextPair from a shared test unit): it is always green. Calls matching assertPatterns (default Assert.*, WillRaise*, Check*), System.Assert and calls on classes with As' +
    'sert in their name (TRuleAssert.Reports) count as checks. Tests with [WillRaise] or [Ignore] stay silent. High confidence. Quick fixes: insert Assert.Pass as a placeholder, or jump to the method.",',
    '      "bad": "[Test]\nprocedure TImportTests.LeereDateiWirdGelesen;\nbegin\n  FImport.Laden(''leer.csv'');\nend;",',
    '      "good": "[Test]\nprocedure TImportTests.LeereDateiWirdGelesen;\nbegin\n  FImport.Laden(''leer.csv'');\n  Assert.AreEqual(0, FImport.Anzahl);\nend;",',
    '      "options": [',
    '        {',
    '          "name": "assertPatterns",',
    '          "type": "string-list",',
    '          "default": [',
    '            "Assert.*",',
    '            "WillRaise*",',
    '            "Check*"',
    '          ],',
    '          "description": "Calls that count as a check, as patterns with * and ?; replaces the default."',
    '        }',
    '      ],',
    '      "safeFix": false',
    '    },',
    '{',
    '      "id": "dunitx-testcase-mismatch",',
    '      "name": "TestCase does not match the method",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "packages",',
    '      "description": "A [TestCase] whose values DUnitX cannot pass to the method, which only shows when the tests run: the number of values differs from the number of parameters (DUnitX calls through ' +
    'RTTI, default values do not count), a value does not fit the type of its parameter, or the method has no parameters at all. Values are split like DUnitX does: at every character of the separator (thir' +
    'd argument, default comma; no quotes), an empty text gives no value. Checked types: integers (decimal or hex, $FF, 0xFF), floating point (point or comma as decimal separator, DUnitX turns a comma into' +
    ' a point), Boolean (True or False) and enumerations declared in the same file (by name); other types are not checked, nor are values that are not a string literal (a constant, ''a'' + ''b''). Besides Test' +
    'Case(''Name'', ''Values''[, ''Separator'']) the newer forms TestCase(''Values''[, ''Separator''[, Trim]]) and NamedTestCase(''Name'', ''Values'') are recognized. Two arguments without a Boolean are ambiguous when t' +
    'he second one contains no letters or digits (''],{,}'', ''/''): older DUnitX versions only know TestCase(''Name'', ''Values''), so the reading whose number of values fits the method counts. Only in test units' +
    ' (uses DUnitX.TestFramework, TestFramework or TestInsight.*). High confidence. No quick fix: what was meant is unclear.",',
    '      "bad": "[Test]\n[TestCase(''Rest'', ''7,2'')]\nprocedure Teile(A, B, Rest: Integer);",',
    '      "good": "[Test]\n[TestCase(''Rest'', ''7,2,1'')]\nprocedure Teile(A, B, Rest: Integer);",',
    '      "safeFix": false',
    '    },',
    '{',
    '      "id": "dunitx-fixture-not-registered",',
    '      "name": "DUnitX fixture never registered",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "packages",',
    '      "description": "A test class DUnitX never sees, so its tests are silently missing. DUnitX finds test classes through RegisterTestFixture or, when the runner in the .dpr sets UseRTTI := True (DUn' +
    'itX project template), through the [TestFixture] attribute. 1. Not registered: a class with [Test] or [TestCase] methods that neither the initialization section of the unit nor a routine of the unit c' +
    'alled from there names (TDUnitX.RegisterTestFixture(TClass), own helpers such as Register([TA, TB])) and no other unit of its projects names, and that either has no [TestFixture] or belongs to a proje' +
    'ct whose .dpr creates a runner (TDUnitX.CreateRunner) without UseRTTI := True. A call from the option registrationCalls in initialization (an own registration function that finds all classes) counts f' +
    'or all classes of the unit. Generic and abstract classes and ancestors of other classes in the file stay silent. Quick fixes: add TDUnitX.RegisterTestFixture(TClass); to initialization, creating the s' +
    'ection if needed; with an RTTI runner also add [TestFixture] in front of the class. 2. Unit in no test project: the group has test projects, but none contains the unit. Quick fix with exactly one test' +
    ' project: add the unit to the uses of the .dpr and as DCCReference to the .dproj. Only in test units and only with the projects of the group known; without them the rule stays silent. Medium confidenc' +
    'e.",',
    '      "bad": "[TestFixture]\nTImportTests = class\n  …\nend;\n…\nend.",',
    '      "good": "[TestFixture]\nTImportTests = class\n  …\nend;\n…\ninitialization\n  TDUnitX.RegisterTestFixture(TImportTests);\nend.",',
    '      "options": [',
    '        {',
    '          "name": "registrationCalls",',
    '          "type": "string-list",',
    '          "default": [],',
    '          "description": "Own registration functions that register all test classes of a unit when called in initialization, as Name or Class.Name."',
    '        }',
    '      ],',
    '      "safeFix": false',
    '    },',
    '{',
    '      "id": "dunitx-istrue-equality",',
    '      "name": "Assert.IsTrue with a comparison instead of AreEqual",',
    '      "category": "code-smell",',
    '      "severity": "hint",',
    '      "group": "packages",',
    '      "description": "Assert.IsTrue(A = B), Assert.IsFalse(A <> B), Assert.IsTrue(X = nil), Assert.IsTrue(Assigned(X)) and the same with not: when the test fails, DUnitX only reports that the conditio' +
    'n does not hold, without the compared values. Assert.AreEqual or AreNotEqual shows expected and actual, IsNull and IsNotNull say what was found. Quick fix (safe): AreEqual or AreNotEqual with the cons' +
    'tant or literal first as the expected value, AreSame or AreNotSame for two objects or two interfaces, IsNull or IsNotNull for nil and Assigned; a message argument is kept. It is offered only when an o' +
    'verload certainly fits: both sides string, Boolean or an integer up to Integer, for nil and Assigned a class, an interface or a pointer. Floating point (AreEqual needs a tolerance), Cardinal, Int64, N' +
    'ativeInt (Length of a dynamic array), enumerations, sets and unknown types get the hint without a fix (AreEqual<T> with an explicit type, or with a tolerance). Records (AreEqual<T> compares bytes inst' +
    'ead of using their =) and nil or Assigned on method pointers and method references stay silent: no assertion fits them. Only in test units (uses DUnitX.TestFramework, TestFramework or TestInsight.*). ' +
    'High confidence.",',
    '      "bad": "Assert.IsTrue(FFake.Calls = 1, ''Aufrufe'');",',
    '      "good": "Assert.AreEqual(1, FFake.Calls, ''Aufrufe'');",',
    '      "safeFix": true',
    '    },',
    '{',
    '      "id": "dunitx-swapped-expected",',
    '      "name": "Expected and actual value swapped",',
    '      "category": "code-smell",',
    '      "severity": "hint",',
    '      "group": "packages",',
    '      "description": "Assert.AreEqual, AreNotEqual, AreSame or AreNotSame whose first argument is neither a literal nor a constant while the second one is: DUnitX takes the expected value first, so th' +
    'e failure message reports the constant as the actual value and the computed value as the expected one, which misleads. Constants are literals, True, False, nil, declared constants and enumeration valu' +
    'es, also with a sign or combined with operators. Quick fix (safe): swap the two arguments; further arguments (message, tolerance) stay. Calls with two constants or two computed values stay silent. Onl' +
    'y in test units (uses DUnitX.TestFramework, TestFramework or TestInsight.*). High confidence.",',
    '      "bad": "Assert.AreEqual(FList.Count, 4);",',
    '      "good": "Assert.AreEqual(4, FList.Count);",',
    '      "safeFix": true',
    '    },',
    '{',
    '      "id": "dunitx-setup-not-torn-down",',
    '      "name": "Field created in Setup, not freed in TearDown",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "packages",',
    '      "description": "A field of a test class that the [Setup] method (or [SetupFixture]) assigns a new object (TFake.Create …) and the matching [TearDown] method (or [TearDownFixture]) neither frees ' +
    'with Free, FreeAndNil, DisposeOf or Destroy nor sets to nil: every single test leaks the object. Methods of the same class that TearDown calls directly count as well (one level). Fields of an interfac' +
    'e type (reference counting) and objects with an owner (TButton.Create(FForm)) stay silent. With the option managedFields (default on) also string and dynamic array fields that Setup fills and TearDown' +
    ' does not clear: the DUnitX leak monitor counts their memory against each test. Without a TearDown method there is one finding on Setup for all fields. Quick fix (safe): FreeAndNil(FField); (without S' +
    'ysUtils FField.Free; FField := nil;) or FField := ''''; / FField := nil; at the end of TearDown; without TearDown it creates the method with its attribute and declaration. Only in test units (uses DUnit' +
    'X.TestFramework, TestFramework or TestInsight.*). Medium confidence: frees in deeper helper methods are not followed.",',
    '      "bad": "[Setup]\nprocedure Setup;\n…\nprocedure TFallTests.Setup;\nbegin\n  FFake := TFakeLookup.Create;\nend;",',
    '      "good": "[TearDown]\nprocedure TearDown;\n…\nprocedure TFallTests.TearDown;\nbegin\n  FreeAndNil(FFake);\nend;",',
    '      "options": [',
    '        {',
    '          "name": "managedFields",',
    '          "type": "boolean",',
    '          "default": true,',
    '          "description": "Also report string and dynamic array fields that Setup fills and TearDown does not clear."',
    '        }',
    '      ],',
    '      "safeFix": true',
    '    },',
    '{',
    '      "id": "dunitx-leak-monitor",',
    '      "name": "DUnitX test program without leak monitor",',
    '      "category": "code-smell",',
    '      "severity": "hint",',
    '      "group": "packages",',
    '      "description": "A program (.dpr) that uses DUnitX.TestFramework but no leak monitor of DUnitX (DUnitX.MemoryLeakMonitor.FastMM4 or .FastMM5): without one DUnitX measures no leaks per test, so th' +
    'e test marks in the editor never show them. DUnitX.MemoryLeakMonitor.Default does not count, it measures nothing. Reported at the DUnitX.TestFramework entry. Quick fix (safe): add the monitor to uses,' +
    ' DUnitX.MemoryLeakMonitor.FastMM5 when the program uses FastMM5, otherwise DUnitX.MemoryLeakMonitor.FastMM4, which also works with the memory manager of the RTL without FastMM4.pas. Units stay silent,' +
    ' as does a program whose project registers its own monitor (a unit uses IMemoryLeakMonitor according to the index). High confidence.",',
    '      "bad": "uses DUnitX.TestFramework, Fall.Tests;",',
    '      "good": "uses DUnitX.TestFramework, DUnitX.MemoryLeakMonitor.FastMM4, Fall.Tests;",',
    '      "safeFix": true',
    '    },',
    '{',
    '      "id": "dunitx-ignore-without-reason",',
    '      "name": "[Ignore] without a reason",',
    '      "category": "code-smell",',
    '      "severity": "hint",',
    '      "group": "packages",',
    '      "description": "[Ignore] without an argument or with an empty reason ([Ignore('''')]): the test report does not say why the test does not run, and later nobody knows whether it may run again. Reas' +
    'ons that are not a string literal (a constant) count as given. Attributes are recognized by name (with or without unit and suffix Attribute), so the rule also works without DUnitX in the search path. ' +
    'Only in test units (uses DUnitX.TestFramework, TestFramework or TestInsight.*). High confidence. No quick fix: only the author knows the reason.",',
    '      "bad": "[Test, Ignore]\nprocedure Export;",',
    '      "good": "[Test, Ignore(''Waits for the new export format (#812)'')]\nprocedure Export;",',
    '      "safeFix": false',
    '    },',
    '{',
    '      "id": "dunitx-category-empty",',
    '      "name": "[Category] without a name",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "packages",',
    '      "description": "[Category('''')] or a category text that holds only commas and blanks ([Category('' , '')]): the test ends up in no category, a filter such as --include never finds it. Names that ar' +
    'e not a string literal count as given. Attributes are recognized by name, so the rule also works without DUnitX in the search path. Only in test units (uses DUnitX.TestFramework, TestFramework or Test' +
    'Insight.*). High confidence. No quick fix: the intended category is unknown.",',
    '      "bad": "[Test, Category('''')]\nprocedure Import;",',
    '      "good": "[Test, Category(''Slow'')]\nprocedure Import;",',
    '      "safeFix": false',
    '    },',
    '{',
    '      "id": "dunitx-fixture-without-test",',
    '      "name": "[TestFixture] without a test",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "packages",',
    '      "description": "A class with [TestFixture] that has no method with [Test], [TestCase], [NamedTestCase] or [RepeatTest] and no published method (DUnitX takes published methods without attributes ' +
    'as tests): the class runs empty and the report looks green. Classes whose ancestor (other than TObject) is not declared in the same file stay silent, as do classes whose ancestor in the file has tests' +
    ' (inherited tests). Attributes are recognized by name, so the rule also works without DUnitX in the search path. Only in test units (uses DUnitX.TestFramework, TestFramework or TestInsight.*). Medium ' +
    'confidence. No quick fix.",',
    '      "bad": "[TestFixture]\nTKundeTests = class\npublic\n  procedure PruefeName;\nend;",',
    '      "good": "[TestFixture]\nTKundeTests = class\npublic\n  [Test]\n  procedure PruefeName;\nend;",',
    '      "safeFix": false',
    '    },',
    '{',
    '      "id": "dunitx-duplicate-attribute",',
    '      "name": "Duplicate attribute",',
    '      "category": "code-smell",',
    '      "severity": "hint",',
    '      "group": "packages",',
    '      "description": "The same DUnitX attribute twice on the same class or method: [Test] [Test], [Ignore] twice, [TestFixture] twice and so on. TestCase, NamedTestCase and Category may appear several' +
    ' times and are only reported when the arguments are the same (the case would run twice). Unknown attributes stay silent. Attributes are recognized by name, so the rule also works without DUnitX in the' +
    ' search path. Only in test units (uses DUnitX.TestFramework, TestFramework or TestInsight.*). High confidence. Quick fix (safe): remove the second one, alone on its line together with the line, in a l' +
    'ist together with its comma.",',
    '      "bad": "[Test]\n[Test]\nprocedure Speichern;",',
    '      "good": "[Test]\nprocedure Speichern;",',
    '      "safeFix": true',
    '    }');

implementation

end.
