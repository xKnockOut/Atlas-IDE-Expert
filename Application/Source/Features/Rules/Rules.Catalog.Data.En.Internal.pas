unit Rules.Catalog.Data.En.Internal;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog.json.
// Nicht von Hand ändern.

interface

const
  cCatalogLinesEnInternal: array[0..54] of string = (
    '{',
    '      "id": "unused-suppression",',
    '      "name": "Unused suppression",',
    '      "category": "code-smell",',
    '      "severity": "hint",',
    '      "group": "internal",',
    '      "description": "An lsp-ignore comment suppresses no finding and can be removed.",',
    '      "bad": "// lsp-ignore: empty-except\nX := 1;",',
    '      "good": "X := 1;",',
    '      "safeFix": true',
    '    },',
    '{',
    '      "id": "unknown-rule-id",',
    '      "name": "Unknown rule id",',
    '      "category": "code-smell",',
    '      "severity": "hint",',
    '      "group": "internal",',
    '      "description": "An lsp-ignore comment names a rule id that does not exist, so it suppresses nothing. The message suggests the most similar known id (typo); such a comment is not also reported as' +
    ' unused-suppression.",',
    '      "bad": "// lsp-ignore: empty-exept\ntry X; except end;",',
    '      "good": "// lsp-ignore: empty-except\ntry X; except end;",',
    '      "safeFix": true',
    '    },',
    '{',
    '      "id": "unit-too-deep",',
    '      "name": "Unit too deep to check",',
    '      "category": "code-smell",',
    '      "severity": "hint",',
    '      "group": "internal",',
    '      "description": "The syntax tree of the unit is more than 100000 levels deep, so the rules do not run for it. Such trees only come from chains with as many terms, such as X := A - B - C - … The h' +
    'int marks the deepest point; splitting the chain into partial expressions makes the unit checkable again.",',
    '      "bad": "X := A - B - C - D - E; // … 100000 terms",',
    '      "good": "Part := A - B - C;\nX := Part - D - E;",',
    '      "safeFix": false',
    '    },',
    '{',
    '      "id": "rule-failed",',
    '      "name": "Rule failed",',
    '      "category": "bug",',
    '      "severity": "error",',
    '      "group": "internal",',
    '      "description": "A rule stopped with an exception on this unit, so its findings are missing. The error is at line 1 and names the rule and the exception class; without it the unit would look clea' +
    'n. It cannot be suppressed with a comment. This is a bug in Atlas: please report it with the unit or a small example.",',
    '      "bad": "// The rule throws on this unit: before, the check ended without findings.",',
    '      "good": "// The unit gets rule-failed until the rule is fixed.",',
    '      "safeFix": false',
    '    },',
    '{',
    '      "id": "slash-command",',
    '      "name": "Quick command not executed",',
    '      "category": "code-smell",',
    '      "severity": "hint",',
    '      "group": "internal",',
    '      "description": "A line starting with /name was not executed and stays in the code: the command is unknown, switched off (slashCommands.disabled) or does not fit at this place. The message names ' +
    'the reason. \"/ignore rule\" is also reported when that rule finds nothing in the line below.",',
    '      "bad": "/gibtsnicht X",',
    '      "good": "/uses System.Classes",',
    '      "safeFix": false',
    '    }');

implementation

end.
