unit Atlas.Common.Rules.Catalog.Data.En.Exceptions;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog.json.
// Nicht von Hand ändern.

interface

const
  cCatalogLinesEnExceptions: array[0..79] of string = (
    '{',
    '      "id": "empty-except",',
    '      "name": "Empty except block",',
    '      "category": "code-smell",',
    '      "severity": "warning",',
    '      "group": "exceptions",',
    '      "description": "An except block without statements swallows every exception. A block that contains only a comment counts as deliberate and is not reported.",',
    '      "bad": "try\n  Save;\nexcept\nend;",',
    '      "good": "try\n  Save;\nexcept\n  on E: EInOutError do\n    Log(E.Message);\nend;"',
    '    },',
    '{',
    '      "id": "generic-exception-raised",',
    '      "name": "Generic exception raised",',
    '      "category": "code-smell",',
    '      "severity": "hint",',
    '      "group": "exceptions",',
    '      "description": "Raising the base class Exception prevents callers from handling the error specifically. Declare a dedicated exception class.",',
    '      "bad": "raise Exception.Create(''Customer missing'');",',
    '      "good": "raise ECustomerMissing.Create(''Customer missing'');"',
    '    },',
    '{',
    '      "id": "catch-all-without-raise",',
    '      "name": "Catch-all handler without re-raise",',
    '      "category": "code-smell",',
    '      "severity": "warning",',
    '      "group": "exceptions",',
    '      "description": "A handler for Exception that neither re-raises nor ends the program swallows every error, including programming errors. Off by default; intended for library code.",',
    '      "bad": "except\n  on E: Exception do\n    Log(E.Message);\nend;",',
    '      "good": "except\n  on E: Exception do\n  begin\n    Log(E.Message);\n    raise;\n  end;\nend;"',
    '    },',
    '{',
    '      "id": "exception-freed",',
    '      "name": "Exception object freed manually",',
    '      "category": "bug",',
    '      "severity": "error",',
    '      "group": "exceptions",',
    '      "description": "The RTL frees an exception object after its handler or after raise. Freeing it manually causes a double free.",',
    '      "bad": "on E: Exception do\n  E.Free;",',
    '      "good": "on E: Exception do\n  Log(E.Message);"',
    '    },',
    '{',
    '      "id": "raise-in-finally",',
    '      "name": "raise in a finally block",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "exceptions",',
    '      "description": "An exception raised in a finally block replaces the exception that is currently propagating, which is then lost.",',
    '      "bad": "try\n  Work;\nfinally\n  raise Exception.Create(''Fehler'');\nend;",',
    '      "good": "try\n  Work;\nfinally\n  Cleanup;\nend;"',
    '    },',
    '{',
    '      "id": "exception-in-destructor",',
    '      "name": "raise in a destructor",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "exceptions",',
    '      "description": "raise in a destructor (also class destructor) that no except inside the destructor catches. The exception aborts the destruction: inherited Destroy no longer runs, the object sta' +
    'ys half freed, and in a finally of the caller it hides the original exception. A raise in the try part of a try..except is caught; raise in the except or finally part, including a bare raise; to re-ra' +
    'ise, is reported. Nested routines and anonymous methods are exempt. Calls that raise are not followed. High confidence. No quick fix: log the state or release it without an exception.",',
    '      "bad": "destructor TSitzung.Destroy;\nbegin\n  if FOffen then\n    raise ESitzung.Create(''Sitzung noch offen'');\n  inherited;\nend;",',
    '      "good": "destructor TSitzung.Destroy;\nbegin\n  if FOffen then\n    Schliessen;\n  inherited;\nend;"',
    '    },',
    '{',
    '      "id": "except-handler-order",',
    '      "name": "General exception handler before a specific one",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "exceptions",',
    '      "description": "In a try..except with several on handlers the first matching handler wins. A handler for a class that an earlier handler already catches is never reached: its code is dead and th' +
    'e special treatment never runs. Reported when an earlier handler names the same class, an ancestor of it, Exception (covers every exception class) or TObject. Ancestors come from the unit, the project' +
    ' index and a table of known RTL, VCL and FireDAC exception classes (for example EStreamError > EFOpenError, EIntError > ERangeError); unknown classes are only compared with Exception and TObject. Quic' +
    'k fix: move the specific handler before the general one (only when both handlers stand on their own lines). A duplicate handler for the same class is reported without a quick fix.",',
    '      "bad": "except\n  on E: Exception do\n    Protokoll(E.Message);\n  on E: EConvertError do\n    ShowMessage(''Ungültige Zahl'');\nend;",',
    '      "good": "except\n  on E: EConvertError do\n    ShowMessage(''Ungültige Zahl'');\n  on E: Exception do\n    Protokoll(E.Message);\nend;"',
    '    },',
    '{',
    '      "id": "reraise-exception-object",',
    '      "name": "raise E instead of raise in a handler",',
    '      "category": "code-smell",',
    '      "severity": "warning",',
    '      "group": "exceptions",',
    '      "description": "raise E; in an on E: … handler raises the caught exception object again as a new raise. The RTL does not free the object twice, but the exception now starts at the handler: Excep' +
    'tAddr and the call stack of tools such as madExcept or JclDebug point to the handler instead of the original fault, and the original location is lost. raise; re-raises the current exception unchanged.' +
    ' Also reported for raise E at …, then without a quick fix. Silent when the handler takes the object over with AcquireExceptionObject or assigns a new object to the variable, inside anonymous methods a' +
    'nd for handlers without a variable name. High confidence. Quick fix: raise E; → raise;.",',
    '      "bad": "except\n  on E: EDatenbank do\n  begin\n    Protokoll(E.Message);\n    raise E;\n  end;\nend;",',
    '      "good": "except\n  on E: EDatenbank do\n  begin\n    Protokoll(E.Message);\n    raise;\n  end;\nend;"',
    '    }');

implementation

end.
