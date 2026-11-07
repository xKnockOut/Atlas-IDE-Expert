unit Atlas.Common.Rules.Catalog.Data.En.CompilerTypes;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog.json.
// Nicht von Hand ändern.

interface

const
  cCatalogLinesEnCompilerTypes: array[0..294] of string = (
    '{',
    '      "id": "assign-to-property-member",',
    '      "name": "Assignment to a field of a property record",',
    '      "category": "bug",',
    '      "severity": "error",',
    '      "group": "compiler",',
    '      "description": "Assignment to a field of a record that a property with a getter, a default or array property or a function result only delivers as a copy (like E2064): the assignment has no effe' +
    'ct. Assignments to untyped constants are reported as well. Types come from name resolution; the rule only reports when the record type is known for sure. A property that reads a field directly lets De' +
    'lphi write into that field and stays silent. Quick fix for a property with write: assign through a local variable and write it back; the variable is declared in the routine and the unit of its type is' +
    ' added to uses.",',
    '      "bad": "Rahmen.BoundsRect.Left := 0;",',
    '      "good": "R := Rahmen.BoundsRect;\nR.Left := 0;\nRahmen.BoundsRect := R;",',
    '      "compilerCodes": [',
    '        "E2064",',
    '        "E2453"',
    '      ],',
    '      "level": "T"',
    '    },',
    '{',
    '      "id": "readonly-property-assigned",',
    '      "name": "Assignment to a property without write",',
    '      "category": "bug",',
    '      "severity": "error",',
    '      "group": "compiler",',
    '      "description": "Assignment to a property that has no write (like E2129), or reading a property that has no read (like E2130). The rule only reports when name resolution finds the property for su' +
    're; redeclarations without read and write (property Caption;) count as unknown. Quick fixes: Count := 0 becomes Clear when the type has Clear; inside a method of the declaring class, assign the field ' +
    'behind read; for a property declared in this file, create the setter and add write.",',
    '      "bad": "Liste.Count := 0;",',
    '      "good": "Liste.Clear;",',
    '      "compilerCodes": [',
    '        "E2129",',
    '        "E2130"',
    '      ],',
    '      "level": "T"',
    '    },',
    '{',
    '      "id": "untyped-pointer-refcount",',
    '      "name": "Untyped pointer bypasses reference counting",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "compiler",',
    '      "description": "An interface is assigned through a typecast to Pointer (Pointer(FIntf) := P, like W1070). Reference counting does not take part: the object is freed too early or never. The rule ' +
    'reports only when name resolution knows the interface type for sure; strings (string, AnsiString …) are reported as well, with the note \"dcc does not report this\", since Delphi warns about them only' +
    ' under NEXTGEN. Fields that already carry [weak] or [unsafe] stay silent. Quick fixes for an interface field of this file with Pointer(Y) or nil on the right: mark the field [weak] or [unsafe] and ass' +
    'ign without Pointer.",',
    '      "bad": "Pointer(FBesitzer) := Pointer(Besitzer);",',
    '      "good": "[weak] FBesitzer: IBesitzer;\n…\nFBesitzer := Besitzer;",',
    '      "compilerCodes": [',
    '        "W1070"',
    '      ],',
    '      "level": "T"',
    '    },',
    '{',
    '      "id": "comparison-always-constant",',
    '      "name": "Comparison always true or always false",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "compiler",',
    '      "description": "A comparison of a variable, field, property or function result of a built-in integer type with a constant outside or at the edge of its value range (like W1021, W1022): Cardinal ' +
    '>= 0 is always true, Byte > 255 always false. Case labels outside the range of the case expression are reported as well (like W1018); single labels that do not fit the width of the type even with the ' +
    'other sign are an error for dcc and are reported by constant-expression-error (like E1012). The rule only reports when the type is known for sure and its declaration is always compiled together with t' +
    'he comparison. NativeInt, LongInt and their unsigned counterparts count with the widest range of all platforms; subrange types are not reported. Length(...) < 0 and Length(...) >= 0 are reported as we' +
    'll, although dcc does not warn there; the message says so.",',
    '      "bad": "while Rest >= 0 do  // Rest: Cardinal",',
    '      "good": "while Rest > 0 do",',
    '      "compilerCodes": [',
    '        "W1021",',
    '        "W1022",',
    '        "W1018"',
    '      ],',
    '      "level": "T"',
    '    },',
    '{',
    '      "id": "case-selector-not-ordinal",',
    '      "name": "case or for without an ordinal type",',
    '      "category": "bug",',
    '      "severity": "error",',
    '      "group": "compiler",',
    '      "description": "case over an expression that is not ordinal (like E2001): strings, floating point numbers, classes and interfaces; a for loop whose counter is not ordinal (like E2032); case labe' +
    'ls and array bounds that are variables, fields, properties, parameters or typed constants instead of constants (like E2026). The rule only reports when the type is known for sure and its declaration i' +
    's always compiled together with the statement. Quick fix for strings whose labels are all string literals: case IndexStr(S, [...]) of with the positions as labels, System.StrUtils is added to uses.",',
    '      "bad": "case Befehl of ''start'': Starten; ''stop'': Stoppen; end;  // Befehl: string",',
    '      "good": "case IndexStr(Befehl, [''start'', ''stop'']) of 0: Starten; 1: Stoppen; end;",',
    '      "compilerCodes": [',
    '        "E2001",',
    '        "E2032",',
    '        "E2026"',
    '      ],',
    '      "level": "T"',
    '    },',
    '{',
    '      "id": "suspicious-string-pointer-cast",',
    '      "name": "Pointer and character width of a string do not match",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "compiler",',
    '      "description": "PChar or PWideChar on an AnsiString, RawByteString or UTF8String, and PAnsiChar on a string, UnicodeString or WideString (like W1044): pointer and character width do not match, a' +
    ' typical mistake after the Unicode migration; the API then reads garbage or only the first character. The rule only reports when the type of the argument is known for sure and its declaration is alway' +
    's compiled together with the cast. string(PAnsiChar) converts correctly and a pointer to TBytes may be intended; both are not reported. Quick fixes: declare an own variable with the matching string ty' +
    'pe (PChar(Pfad) with Pfad: AnsiString becomes Pfad: string), wrap the argument in string(...) or AnsiString(...), use the matching pointer type.",',
    '      "bad": "var Pfad: AnsiString; ... DeleteFile(PChar(Pfad));",',
    '      "good": "var Pfad: string; ... DeleteFile(PChar(Pfad));",',
    '      "compilerCodes": [',
    '        "W1044"',
    '      ],',
    '      "level": "T"',
    '    },',
    '{',
    '      "id": "string-conversion",',
    '      "name": "Conversion between Unicode and ANSI strings",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "compiler",',
    '      "description": "Implicit and explicit conversions between string, UnicodeString or WideString on one side and AnsiString, RawByteString or UTF8String on the other, like the compiler warnings: im' +
    'plicit to string (like W1057) or to AnsiString with possible data loss (like W1058) in assignments, inline variables with a type and arguments for value and const parameters of routines without overlo' +
    'ads; explicit casts string(A) (like W1059) and AnsiString(S) (like W1060); a string constant with characters the ANSI code page does not know assigned to an AnsiString (like W1058 and W1062); a WideCh' +
    'ar in a set expression of character literals such as C in [''0''..''9''] (like W1050); changing a character of a string directly (S[1] := ''x'', like W1068). Like dcc, W1059, W1060 and W1068 are only report' +
    'ed after {$WARN EXPLICIT_STRING_CAST ON}, {$WARN EXPLICIT_STRING_CAST_LOSS ON} or {$WARN IMMUTABLE_STRINGS ON}; {$WARN ... OFF} and {$WARNINGS OFF} silence the rule from their position, {$WARN ... ERR' +
    'OR} reports an error. Only reported when both types are known for sure (variables, fields, properties, function results and typed constants of the built-in string types from System, also via a plain a' +
    'lias) and their declarations are always compiled with the statement. Silent: concatenations, casts as source, conversions between two ANSI types (AnsiString, RawByteString, UTF8String; dcc converts by' +
    ' code page), own string types such as type AnsiString(28591), {$H-} and Delphi before 2009. W1062 depends on the ANSI code page of the compiling machine (option ansiCodePage, default 1252; 0 turns thi' +
    's check off); only characters Windows does not map to a best-fit replacement are reported: Hebrew to Thai, Hangul, kana and CJK, symbols and dingbats U+2600-U+27BF and characters outside the BMP (emoj' +
    'i). Project options of the .dproj (DCC_IMPLICIT_STRING_CAST = false, true or error and the like) count as with dcc. Quick fixes: convert explicitly (string(A), AnsiString(S)); use CharInSet and add Sy' +
    'stem.SysUtils to uses.",',
    '      "bad": "function IstZiffer(const Zeichen: Char): Boolean;\nbegin\n  Result := Zeichen in [''0''..''9''];\nend;",',
    '      "good": "function IstZiffer(const Zeichen: Char): Boolean;\nbegin\n  Result := CharInSet(Zeichen, [''0''..''9'']);\nend;",',
    '      "compilerCodes": [',
    '        "W1050",',
    '        "W1057",',
    '        "W1058",',
    '        "W1059",',
    '        "W1060",',
    '        "W1062",',
    '        "W1068"',
    '      ],',
    '      "options": [',
    '        {',
    '          "name": "ansiCodePage",',
    '          "type": "integer",',
    '          "default": 1252,',
    '          "description": "ANSI code page of the machine that compiles; characters it surely lacks are reported like W1062 when assigned to an AnsiString. Only 1252 is known; 0 or another value turns t' +
    'his check off."',
    '        }',
    '      ],',
    '      "level": "T"',
    '    },',
    '{',
    '      "id": "signed-unsigned-mix",',
    '      "name": "Signed and unsigned mixed",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "compiler",',
    '      "description": "Comparison or arithmetic (+, -, *, div, mod) with one signed and one unsigned operand whose types are known for certain (variables, fields, properties, function results, own alia' +
    'ses). With UInt64 the whole expression is computed unsigned and a negative value becomes a huge number (like W1073, comparison like W1023); with Cardinal/DWORD and a signed type up to 32 bits both ope' +
    'rands are widened to Int64 (like W1023/W1024). Silent for Byte and Word, Cardinal with Int64, literals, constants, NativeInt/NativeUInt and unknown types. Medium confidence. Quick fix: convert the uns' +
    'igned operand to Int64.",',
    '      "bad": "if Groesse + Delta < Grenze then  // Groesse: UInt64; Delta: Int64",',
    '      "good": "if Int64(Groesse) + Delta < Grenze then",',
    '      "compilerCodes": [',
    '        "W1023",',
    '        "W1024",',
    '        "W1073"',
    '      ],',
    '      "level": "T"',
    '    },',
    '{',
    '      "id": "narrowing-assignment",',
    '      "name": "Assignment with possible data loss",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "compiler",',
    '      "description": "An assignment or an inline variable with a value whose type is wider than the target, without an explicit conversion: Int64 to Integer, NativeInt to Integer (Win64) and, via the ' +
    'option types, e.g. Double to Single or Extended to Double. Like W1072 (floating point) and W1066 (Extended to Double); integers without a code, because Delphi 13 does not report W1071 even with {$WARN' +
    ' IMPLICIT_INTEGER_CAST_LOSS ON}. Only reported when both types are known for certain (variables, fields, properties, function results, own aliases and integer arithmetic built from them); literals and' +
    ' explicit conversions stay silent. Off by default; medium confidence. Quick fixes: convert explicitly; widen the type of the target''s declaration (single variable declared in the same file).",',
    '      "bad": "Anzahl := Strom.Size;  // Anzahl: Integer",',
    '      "good": "Anzahl := Integer(Strom.Size);",',
    '      "compilerCodes": [',
    '        "W1072",',
    '        "W1066"',
    '      ],',
    '      "options": [',
    '        {',
    '          "name": "types",',
    '          "type": "string-list",',
    '          "default": [',
    '            "Int64>Integer",',
    '            "NativeInt>Integer"',
    '          ],',
    '          "description": "Reported pairs source type>target type, e.g. Double>Single or Extended>Double."',
    '        }',
    '      ],',
    '      "level": "T"',
    '    },',
    '{',
    '      "id": "invalid-var-argument",',
    '      "name": "Invalid argument for a var or out parameter",',
    '      "category": "bug",',
    '      "severity": "error",',
    '      "group": "compiler",',
    '      "description": "A var or out parameter receives something that is not a variable: a constant, a constant expression such as cMax + 1, a const parameter, a property or a function result (like E21' +
    '97), a constant for an open array (like E2192) or an expression (like E2036); @ before an arithmetic or logical expression is reported as well (like E2036). A string element for a character parameter ' +
    '(S[1]) is a variable for dcc and stays silent (E2354 exists only for .NET, #1383). Reported only for routines without overloads whose header is known from the file or the index; built-in routines such' +
    ' as Inc or Move and untyped var parameters accept more and stay silent. Typed constants count as constants unless {$J+} is set. Quick fix: pass a local variable of the parameter type, and write it bac' +
    'k for properties with write.",',
    '      "bad": "procedure Zaehlen(var Wert: Integer);\n…\nZaehlen(Liste.Count);",',
    '      "good": "Anzahl := Liste.Count;\nZaehlen(Anzahl);",',
    '      "compilerCodes": [',
    '        "E2197",',
    '        "E2192",',
    '        "E2036"',
    '      ],',
    '      "level": "T"',
    '    },',
    '{',
    '      "id": "condition-not-boolean",',
    '      "name": "Condition is not Boolean",',
    '      "category": "bug",',
    '      "severity": "error",',
    '      "group": "compiler",',
    '      "description": "The condition of if, while, until or a conditional expression has a type that is surely not Boolean: a number, a pointer, a class, an interface, a string or a character (like E20' +
    '12). Unlike C, Delphi needs a Boolean. Reported only when the type is certain; Boolean types such as LongBool, enumerations, aliases and unknown types stay silent. Quick fix: add <> 0 (alternative > 0' +
    '), <> nil (alternative Assigned), <> '''' or <> #0.",',
    '      "bad": "if Liste.Count then\n  Verarbeiten;",',
    '      "good": "if Liste.Count > 0 then\n  Verarbeiten;",',
    '      "compilerCodes": [',
    '        "E2012"',
    '      ],',
    '      "level": "T"',
    '    },',
    '{',
    '      "id": "type-mismatch",',
    '      "name": "Incompatible types",',
    '      "category": "bug",',
    '      "severity": "error",',
    '      "group": "compiler",',
    '      "description": "An assignment, argument, var parameter, operator, typecast or procedural type uses incompatible types, and both types are certain: Integer := ''abc'', a class parameter with defaul' +
    't 0, a static array := nil, a procedure without result as a value, string + Integer or [1] + [''a''] (like E2010); an operator that is not defined for an operand, such as string - Char, Double div 2, no' +
    't ''a'' or X is Integer (like E2015); a var argument whose type differs from the parameter, such as Byte for Integer (like E2033); Byte(S) of a long string and an ordinal typecast of a floating-point va' +
    'lue (like E2089); Inc/Dec with a floating-point or string step and Ptr(S) (like E2008); a routine with another parameter list for a procedural type, or a method for a type without of object and vice v' +
    'ersa (like E2009); of overloaded routines none fits the procedural type (like E2010). As in dcc, Result has the type from the interface part, and of two declarations of the same local name the last on' +
    'e counts. Reported only when both sides are certain and their declarations are always compiled with the statement; records (class operator Implicit), Variant, pointers, subranges, generics, overloaded' +
    ' routines and with blocks stay silent. No quick fix: only the developer knows which side is wrong.",',
    '      "bad": "var\n  Anzahl: Integer;\nbegin\n  Anzahl := ''drei'';",',
    '      "good": "var\n  Anzahl: Integer;\nbegin\n  Anzahl := 3;",',
    '      "compilerCodes": [',
    '        "E2010",',
    '        "E2008",',
    '        "E2009",',
    '        "E2015",',
    '        "E2033",',
    '        "E2089"',
    '      ],',
    '      "level": "T"',
    '    },',
    '{',
    '      "id": "for-in-not-enumerable",',
    '      "name": "for-in over a type without enumerator",',
    '      "category": "bug",',
    '      "severity": "error",',
    '      "group": "compiler",',
    '      "description": "A for-in loop runs over a type that cannot be enumerated: a number, pointer, character or Boolean, or a class, record or interface without a public GetEnumerator, also not inheri' +
    'ted or from a helper (like E2430); or the enumerator returned by GetEnumerator lacks a public MoveNext or Current (like E2431). Strings, arrays and sets are fine. Reported only when the type and all i' +
    'ts ancestors are known; generic types and unknown types stay silent. No quick fix; if the type has Count, the message suggests an indexed loop.",',
    '      "bad": "for F in Felder.Dataset do",',
    '      "good": "for F in Felder do",',
    '      "compilerCodes": [',
    '        "E2430",',
    '        "E2431"',
    '      ],',
    '      "level": "T"',
    '    },',
    '{',
    '      "id": "type-kind-required",',
    '      "name": "Expression or declaration lacks the required kind of type",',
    '      "category": "bug",',
    '      "severity": "error",',
    '      "group": "compiler",',
    '      "description": "An operation needs a certain kind of type that the operand surely does not have: an index on a number, Boolean, character or enumeration (like E2016); ^ on such a value, a class,' +
    ' a record or an interface (like E2017); a dot or with on such a value (like E2018); an object type whose ancestor is not an object type, TypeOf on a simple value and Dispose with destructor on a point' +
    'er to a simple type (like E2019); a class whose ancestor is a record, class reference, enumeration or simple type (like E2021); a class helper whose ancestor is not a helper (like E2022); New with con' +
    'structor on a pointer to a simple type (like E2467); a record helper for a class or interface (like E2474); a method without class called through the class type outside methods of that class and its d' +
    'escendants (like E2076); Slice outside an open array argument (like E2193); a record inside an array passed to array of const (like E2150); Write/Writeln or Read/Readln with a class, record or interfa' +
    'ce (like E2054, E2055). Reported only when the type is certain: unknown types, conditional declarations, visible helpers, units missing from the index, records with an Implicit operator and unknown an' +
    'cestors stay silent. Quick fixes: remove ^ before a dot for classes, records and interfaces; write Object.ToString in Write/Writeln.",',
    '      "bad": "Kunde^.Name := ''A'';\nWriteln(ErrOutput, Kunde);",',
    '      "good": "Kunde.Name := ''A'';\nWriteln(ErrOutput, Kunde.ToString);",',
    '      "compilerCodes": [',
    '        "E2016",',
    '        "E2017",',
    '        "E2018",',
    '        "E2019",',
    '        "E2021",',
    '        "E2022",',
    '        "E2467",',
    '        "E2474",',
    '        "E2076",',
    '        "E2193",',
    '        "E2150",',
    '        "E2054",',
    '        "E2055"',
    '      ],',
    '      "level": "T"',
    '    },',
    '{',
    '      "id": "generic-inference-failed",',
    '      "name": "Type arguments cannot be inferred",',
    '      "category": "bug",',
    '      "severity": "error",',
    '      "group": "compiler",',
    '      "description": "A call of a generic method without type arguments whose type parameters cannot be inferred from the arguments: a type parameter that occurs in no parameter, for example only in t' +
    'he result (like E2531), or arguments of different kinds (number, string, Boolean) for parameters whose type is the same type parameter (like E2532). E2531 is reported as a statement, as a call with pa' +
    'rentheses and on the right side of an assignment to a value of known, non-procedural type, and only when every overload has such a type parameter. E2532 is reported only for exactly one routine withou' +
    't overload; arguments of unknown type (Variant, classes, expressions) and numbers of different size keep the rule silent. Like argument-count-mismatch it is silent for declarations in conditional bran' +
    'ches and names that an unknown ancestor can hide.",',
    '      "bad": "Zahl := TFabrik.Neu;\nTFabrik.Paar(1, ''a'');",',
    '      "good": "Zahl := TFabrik.Neu<Integer>;\nTFabrik.Paar<string>(''1'', ''a'');",',
    '      "compilerCodes": [',
    '        "E2531",',
    '        "E2532"',
    '      ],',
    '      "level": "T"',
    '    },',
    '{',
    '      "id": "argument-count-mismatch",',
    '      "name": "Wrong number of arguments",',
    '      "category": "bug",',
    '      "severity": "error",',
    '      "group": "compiler",',
    '      "description": "A call passes more arguments than the routine has parameters (like E2034) or fewer than its parameters without default value (like E2035), also as a statement without parentheses' +
    '. Checked only when the name resolves to exactly one routine: overloads, varargs, typecasts, variables of procedural type, System identifiers without source and declarations in conditional branches ar' +
    'e left to the compiler (E2250). A function called with too many arguments is only reported when its result type is known and not procedural. Quick fix: Signature help opens the parameter hint inside t' +
    'he parentheses (adds () when missing).",',
    '      "bad": "Versenden(Kunde.Mail, ''Rechnung'');",',
    '      "good": "Versenden(Kunde.Mail, ''Rechnung'', Text);",',
    '      "compilerCodes": [',
    '        "E2034",',
    '        "E2035"',
    '      ],',
    '      "level": "T"',
    '    },',
    '{',
    '      "id": "overload-resolution",',
    '      "name": "Overload not resolvable or ambiguous",',
    '      "category": "bug",',
    '      "severity": "error",',
    '      "group": "compiler",',
    '      "description": "A call of an overloaded routine or method matches no overload (like E2250), for example a floating-point value where only Integer and string are offered, or is ambiguous (like E2' +
    '251) because the matching overloads only differ in parameters with default values. Checked only when the list of overloads is certainly complete: System and all units in uses are indexed, no other uni' +
    't declares a free routine of the same name, ancestors are known, no conditional, generic, nested or varargs declarations, no with. Only built-in type families without implicit conversion count as mism' +
    'atching (float to integer, string to Char, Boolean to number …), aliases like their base type; records with an Implicit operator, classes, pointers, open arrays, Variant and overloaded calls inside th' +
    'e argument are left to the compiler. Ambiguous means: all matching overloads of the same class or unit have exactly the argument types for the passed arguments. Quick fix: Signature help shows all ove' +
    'rloads.",',
    '      "bad": "procedure Nimm(AWert: Integer); overload;\nprocedure Nimm(const AWert: string); overload;\n\nNimm(1.5);  // no overload takes a float",',
    '      "good": "Nimm(Round(1.5));",',
    '      "compilerCodes": [',
    '        "E2250",',
    '        "E2251"',
    '      ],',
    '      "level": "T"',
    '    }');

implementation

end.
