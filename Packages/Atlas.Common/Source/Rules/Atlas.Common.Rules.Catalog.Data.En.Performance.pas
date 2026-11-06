unit Atlas.Common.Rules.Catalog.Data.En.Performance;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog.json.
// Nicht von Hand ändern.

interface

const
  cCatalogLinesEnPerformance: array[0..73] of string = (
    '{',
    '      "id": "string-concat-in-loop",',
    '      "name": "String concatenation in a loop",',
    '      "category": "code-smell",',
    '      "severity": "hint",',
    '      "group": "performance",',
    '      "description": "A string variable is extended step by step inside a loop. Delphi usually grows strings in place, so this is reported only with low confidence and is off by default; for many iter' +
    'ations TStringBuilder is faster. Silent when the variable is assigned anew earlier in every iteration, directly in the loop body and not behind then, else or a case label (it does not grow across the ' +
    'loop).",',
    '      "bad": "for I := 1 to 10000 do\n  S := S + IntToStr(I);",',
    '      "good": "Builder := TStringBuilder.Create;\ntry\n  for I := 1 to 10000 do\n    Builder.Append(I);\n  S := Builder.ToString;\nfinally\n  Builder.Free;\nend;"',
    '    },',
    '{',
    '      "id": "loop-invariant-call",',
    '      "name": "Expensive call in a loop condition",',
    '      "category": "code-smell",',
    '      "severity": "hint",',
    '      "group": "performance",',
    '      "description": "The condition of while and until is evaluated on every iteration. Calls like Trim, Format or FileExists and properties like Lines.Text there are recomputed each time; compute the' +
    'm once before the loop. Bounds of for loops are evaluated only once and are not reported, nor is .Text when it is a field of a type in the same file (record field), nor calls whose argument the loop c' +
    'hanges (assignment, Inc, Dec, Delete, SetLength, Include, Exclude). Off by default.",',
    '      "bad": "while I < Length(Trim(Memo.Lines.Text)) do\n  Inc(I);",',
    '      "good": "Text := Trim(Memo.Lines.Text);\nwhile I < Length(Text) do\n  Inc(I);"',
    '    },',
    '{',
    '      "id": "missing-begin-update",',
    '      "name": "Adding items in a loop without BeginUpdate",',
    '      "category": "code-smell",',
    '      "severity": "hint",',
    '      "group": "performance",',
    '      "description": "Items.Add, Lines.Add and similar calls in a loop repaint the control on every call. Wrap the loop in BeginUpdate and try … finally EndUpdate. Silent for menus (TMenuItem has no B' +
    'eginUpdate, also through fields such as FParts.Menu.Items) and for for loops with at most 10 iterations (fixed bounds or a static array of the same file). Off by default.",',
    '      "bad": "for I := 1 to 1000 do\n  ListBox1.Items.Add(IntToStr(I));",',
    '      "good": "ListBox1.Items.BeginUpdate;\ntry\n  for I := 1 to 1000 do\n    ListBox1.Items.Add(IntToStr(I));\nfinally\n  ListBox1.Items.EndUpdate;\nend;"',
    '    },',
    '{',
    '      "id": "setlength-in-loop",',
    '      "name": "Array grows by one element in a loop",',
    '      "category": "code-smell",',
    '      "severity": "hint",',
    '      "group": "performance",',
    '      "description": "SetLength(A, Length(A) + 1) inside a loop copies the dynamic array on every iteration. The rule only reports when A is surely a dynamic array (array of, TArray<T>, an array type ' +
    'of the file or a known RTL type such as TBytes), never for strings. In a for loop the count is known: the message names it, and when A is a local variable not used before the loop and only written as ' +
    'A[High(A)] or A[Length(A) - 1] inside it, the quick fix sets the length once before the loop and indexes with the loop variable. Otherwise collect the values in a TList<T>.",',
    '      "bad": "for I := 0 to Liste.Count - 1 do\nbegin\n  SetLength(Namen, Length(Namen) + 1);\n  Namen[High(Namen)] := Liste[I].Name;\nend;",',
    '      "good": "SetLength(Namen, Liste.Count);\nfor I := 0 to Liste.Count - 1 do\n  Namen[I] := Liste[I].Name;"',
    '    },',
    '{',
    '      "id": "managed-param-without-const",',
    '      "name": "Managed parameter without const",',
    '      "category": "code-smell",',
    '      "severity": "hint",',
    '      "group": "performance",',
    '      "description": "A value parameter of type string, interface, dynamic or open array, or a record of the file with at least minRecordSize bytes, that the routine never changes. Every call pays ref' +
    'erence counting or a copy; const avoids both. Changed means: assigned, a part assigned (characters, fields, elements), passed to var or out, @Param, a method call on a record, a for loop variable. The' +
    ' rule only reports when this is certain: calls with unknown signature (methods without the symbol index, overloads), with blocks, captures in anonymous methods, bare inherited and asm make it stay sil' +
    'ent. Virtual, dynamic, abstract and message methods, calling conventions, external and exported routines, methods of classes implementing interfaces, published methods and methods used as values (even' +
    't handlers, @Routine, form file) are skipped because their signature is given from outside; overrides only with ignoreOverrides = false and then without fix. The fix adds const in the implementation a' +
    'nd the declaration and splits parameter groups when needed. References as method pointers in other units are not visible to the rule; the compiler reports them after the fix.",',
    '      "bad": "function Formatieren(Text: string; Kunde: TKundenDaten): string;\nbegin\n  Result := Text + Kunde.Name;\nend;",',
    '      "good": "function Formatieren(const Text: string; const Kunde: TKundenDaten): string;\nbegin\n  Result := Text + Kunde.Name;\nend;",',
    '      "options": [',
    '        {',
    '          "name": "minRecordSize",',
    '          "type": "integer",',
    '          "default": 16,',
    '          "description": "Report record parameters from this size in bytes on."',
    '        },',
    '        {',
    '          "name": "ignoreOverrides",',
    '          "type": "boolean",',
    '          "default": true,',
    '          "description": "Do not report overrides; their signature is given by the ancestor."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "case-insensitive-compare",',
    '      "name": "Comparison through UpperCase or LowerCase",',
    '      "category": "code-smell",',
    '      "severity": "hint",',
    '      "group": "performance",',
    '      "description": "UpperCase(A) = UpperCase(B), LowerCase(A) <> ''x'', AnsiUpperCase(...) or A.ToUpper = B.ToUpper creates two strings for one comparison. SameText (AnsiSameText for the Ansi function' +
    's and the Unicode string helpers) is shorter and faster. A literal is only accepted if the conversion does not change it; UpperCase(A) = LowerCase(B) and UpperCase(A) = ''ja'' are left alone because the' +
    'y are different mistakes. Does not replace the string helper modernisation of #71. High confidence. Quick fix: SameText(A, B) or not SameText(A, B).",',
    '      "bad": "if UpperCase(Land) = UpperCase(Standard) then",',
    '      "good": "if SameText(Land, Standard) then"',
    '    }');

implementation

end.
