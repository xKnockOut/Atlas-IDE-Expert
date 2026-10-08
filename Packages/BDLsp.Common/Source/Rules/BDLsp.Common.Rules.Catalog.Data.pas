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
    '    }' + #10 +
    '  ]' + #10 +
    '}' + #10 +
    '' + #10);
  Result := '';
end;

end.
