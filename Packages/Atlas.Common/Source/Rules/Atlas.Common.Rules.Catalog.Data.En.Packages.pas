unit Atlas.Common.Rules.Catalog.Data.En.Packages;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog.json.
// Nicht von Hand ändern.

interface

const
  cCatalogLinesEnPackages: array[0..58] of string = (
    '{',
    '      "id": "implicit-package-import",',
    '      "name": "Implicit package import",',
    '      "category": "code-smell",',
    '      "severity": "warning",',
    '      "group": "packages",',
    '      "description": "In a package (.dpk) a unit from contains uses a unit that is neither in contains nor provided by a package in requires. The compiler pulls it in implicitly (W1033), which later c' +
    'auses duplicate units when another package also contains it. The quick fix adds the unit to contains.",',
    '      "bad": "package Werkzeuge;\nrequires rtl;\ncontains\n  uHaupt in ''uHaupt.pas'';  // uHaupt uses uMathe\nend.",',
    '      "good": "package Werkzeuge;\nrequires rtl;\ncontains\n  uHaupt in ''uHaupt.pas'',\n  uMathe in ''uMathe.pas'';\nend."',
    '    },',
    '{',
    '      "id": "ota-notifier-not-removed",',
    '      "name": "IDE notifier without RemoveNotifier",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "packages",',
    '      "description": "AddNotifier on IOTAServices, IOTAEditorServices, IOTAModule and so on (or another pair from registerPairs) whose index never reaches RemoveNotifier: the call is a statement witho' +
    'ut assignment, or the variable it is assigned to is never passed to RemoveNotifier in the unit (in finalization, a destructor or Destroyed). The IDE then calls the notifier after the package is unload' +
    'ed, in memory that no longer holds the code. Register… calls inside the procedure Register are exempt: the IDE removes those wizards itself. Medium confidence. Quick fix in methods: keep the index in ' +
    'a field (FNotifierIndex in the private section) and add RemoveNotifier to the destructor, which is created if missing; in procedures of the unit: a global variable initialized with -1 and RemoveNotifi' +
    'er in finalization. No quick fix when the receiver is a parameter or local variable.",',
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
    '      ]',
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
    '      ]',
    '    }');

implementation

end.
