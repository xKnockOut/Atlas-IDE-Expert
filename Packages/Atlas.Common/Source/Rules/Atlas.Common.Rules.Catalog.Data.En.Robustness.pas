unit Atlas.Common.Rules.Catalog.Data.En.Robustness;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog.json.
// Nicht von Hand ändern.

interface

const
  cCatalogLinesEnRobustness: array[0..179] of string = (
    '{',
    '      "id": "random-without-randomize",',
    '      "name": "Random without Randomize",',
    '      "category": "code-smell",',
    '      "severity": "hint",',
    '      "group": "robustness",',
    '      "description": "Random is used, but the unit never calls Randomize, so every start yields the same sequence. Randomize often sits in the .dpr, so the rule is off by default and has low confidenc' +
    'e.",',
    '      "bad": "Dice := Random(6) + 1;",',
    '      "good": "Randomize; // once at program start\n...\nDice := Random(6) + 1;"',
    '    },',
    '{',
    '      "id": "format-without-settings",',
    '      "name": "Formatting depends on the locale",',
    '      "category": "code-smell",',
    '      "severity": "hint",',
    '      "group": "robustness",',
    '      "description": "Format with %f, %n, %m, %g or %e and functions like FloatToStr, StrToFloat or DateToStr without a TFormatSettings parameter use the user''s locale (decimal separator, date format)' +
    '. For files, protocols and logs pass fixed TFormatSettings. Format(''%d'', …) is not reported, nor are FormatDateTime and FormatFloat with a fixed picture without separators (: / . ,), such as ''yyyy\"-\' +
    '"mm\"-\"dd'' or ''ddddd t''. Own routines of the same name stay silent when name resolution finds them: local routines, methods of the own class, routines of the own unit and of a unit that comes after S' +
    'ystem.SysUtils in uses.",',
    '      "bad": "Line := Format(''%.2f'', [Amount]);",',
    '      "good": "Line := Format(''%.2f'', [Amount], TFormatSettings.Invariant);"',
    '    },',
    '{',
    '      "id": "debug-display-placeholder",',
    '      "name": "Debugger display names an unknown member",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "robustness",',
    '      "description": "A debugger display rule above a type (// atlas-debug: ''{Name}, {City}'', [AtlasDebugDisplay(''…'')], // atlas-debug-children: Name, City or [AtlasDebugChildren(''…'')]) names a placeh' +
    'older or child that is not a field, property or method of the type or one of its ancestors, or the template is invalid (unclosed or empty brace). In the debugger such a placeholder stays empty ({?Name' +
    '}). Ancestors come from the unit and the index; when an ancestor is unknown the rule stays silent for that type. Members of TObject (ClassName, ToString, …) are always known.",',
    '      "bad": "// atlas-debug: ''{Name}, {Stadt}''\nTKunde = class\n  Name, Ort: string;\nend;",',
    '      "good": "// atlas-debug: ''{Name}, {Ort}''\nTKunde = class\n  Name, Ort: string;\nend;"',
    '    },',
    '{',
    '      "id": "null-compare",',
    '      "name": "Comparison with Null instead of VarIsNull or IsNull",',
    '      "category": "code-smell",',
    '      "severity": "warning",',
    '      "group": "robustness",',
    '      "description": "X = Null or X <> Null compares a variant with Null. The result depends on the global System.Variants.NullEqualityRule: with the default ncrLoose the comparison works as expected,' +
    ' with ncrStrict it is never true and with ncrError it raises an exception. A library, a test framework or another part of the project can change the rule. VarIsNull(X) and Field.IsNull check independe' +
    'ntly of it. Reported only where the comparison stands on its own (condition, argument, assignment); not X = Null binds as (not X) = Null and gets no quick fix. High confidence. Quick fix: Field.IsNull' +
    ' for X.Value on FieldByName, FindField, Fields[...], ParamByName, Params[...] or a field of type T...Field/T...Param, otherwise VarIsNull(X); with <> preceded by not.",',
    '      "bad": "if qryKunde.FieldByName(''Geburtstag'').Value = Null then\n  Alter := 0;",',
    '      "good": "if qryKunde.FieldByName(''Geburtstag'').IsNull then\n  Alter := 0;"',
    '    },',
    '{',
    '      "id": "path-concat-without-delimiter",',
    '      "name": "Path joined without delimiter",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "robustness",',
    '      "description": "A folder without a trailing path delimiter is joined to a file or folder name with +: results of ExtractFileDir, ExcludeTrailingPathDelimiter, GetCurrentDir, GetHomePath, TPath.G' +
    'etDocumentsPath and the other TPath.Get…Path folders, TPath.GetDirectoryName, TDirectory.GetCurrentDirectory and TDirectory.GetParent, called directly or held in a local variable that the routine only' +
    ' assigns such values to. The result is C:\\Datadatei.txt instead of C:\\Data\\datei.txt. ExtractFilePath, IncludeTrailingPathDelimiter and TPath.GetTempPath end with a delimiter and stay silent, as do' +
    ' delimiters, extensions (ExtractFileExt, ''.bak'') and texts that start with a space or punctuation. A literal name reports with high confidence, an identifier with medium confidence. A local variable p' +
    'assed to a procedure other than ForceDirectories, FileExists and similar read-only calls may be changed there and stays silent. Quick fix: TPath.Combine(Folder, Name), adding System.IOUtils to uses.",',
    '      "bad": "Ordner := TPath.GetDocumentsPath;\nDatei := Ordner + ''export.csv'';",',
    '      "good": "Ordner := TPath.GetDocumentsPath;\nDatei := TPath.Combine(Ordner, ''export.csv'');"',
    '    },',
    '{',
    '      "id": "hardcoded-path",',
    '      "name": "Hard-coded file path",',
    '      "category": "code-smell",',
    '      "severity": "hint",',
    '      "group": "robustness",',
    '      "description": "A string literal with a drive letter (C:\\…, also with /) or a UNC path (\\\\server\\share\\…); paths under C:\\Users or C:\\Documents and Settings get their own message. On othe' +
    'r computers the path is missing. Drive roots such as ''C:\\'' alone and the prefixes \\\\?\\ and \\\\.\\ stay silent, as do comments, test units and units listed in allowUnits (for example a unit with t' +
    'he default paths of an installation). High confidence, no quick fix: take the path from TPath (GetDocumentsPath, GetHomePath, GetSharedDocumentsPath), the settings or an environment variable.",',
    '      "bad": "Protokoll.SaveToFile(''C:\\Users\\marco\\Desktop\\log.txt'');",',
    '      "good": "Protokoll.SaveToFile(TPath.Combine(TPath.GetDocumentsPath, ''log.txt''));",',
    '      "options": [',
    '        {',
    '          "name": "allowUnits",',
    '          "type": "string-list",',
    '          "default": [],',
    '          "description": "Units in which hard-coded paths are allowed, by unit name; * at the end matches a prefix (App.Config*)."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "filename-compare-case",',
    '      "name": "File names compared with =",',
    '      "category": "bug",',
    '      "severity": "hint",',
    '      "group": "robustness",',
    '      "description": "A comparison with = or <> where one side is a file or path name: the result of ExtractFileName, ExtractFilePath, ExtractFileDir, ExtractFileExt, ExpandFileName, ChangeFileExt and' +
    ' related System.SysUtils functions, of TPath.GetFileName, GetExtension, GetDirectoryName, GetFullPath, Combine and related methods, or a variable or property whose name ends in FileName, or Applicatio' +
    'n.ExeName. On Windows Kunde.pas and kunde.PAS are the same file. Comparisons with an empty string, nil or a literal without letters stay silent, as does ExtractFileDir(X) = X (both sides come from the' +
    ' same text). It also stays silent when the same statement compares the same two sides ignoring case (SameText, AnsiSameText, CompareText, AnsiCompareText, SameFileName, AnsiCompareFileName), for examp' +
    'le platform-dependent with PathDelim = ''\\'', and in test units (test doubles compare with names the test assigns itself). Medium confidence. Quick fix: SameFileName(A, B), or not SameFileName(A, B) fo' +
    'r <>; adds System.SysUtils to uses if needed.",',
    '      "bad": "if ExtractFileName(Datei) = ''Config.ini'' then",',
    '      "good": "if SameFileName(ExtractFileName(Datei), ''Config.ini'') then"',
    '    },',
    '{',
    '      "id": "initialization-not-finalized",',
    '      "name": "Object created at startup is not freed",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "robustness",',
    '      "description": "An object is created with TClass.Create in the initialization section and assigned to a unit variable, or created in a class constructor and assigned to a class var, but the unit' +
    ' never frees it (no Free, Destroy, DisposeOf, Release or FreeAndNil anywhere in the unit). FastMM reports a leak on shutdown; in packages the object stays behind on every unload. Interface and record ' +
    'types, components with an owner (Application, Self, Owner) and objects the unit hands over stay silent: every mention of the variable must be harmless (member access, comparison with nil, Assigned, a ' +
    'new Create or nil assignment); passing it as an argument, assigning it elsewhere, with, a property reading it or FreeOnTerminate silence the rule. For variables in the interface section and public cla' +
    'ss vars the rule also stays silent when another indexed unit uses the name. High confidence. Quick fix: FreeAndNil at the end of finalization or in the class destructor; a missing finalization section' +
    ' or class destructor (declaration and body) is created and System.SysUtils is added to uses when needed.",',
    '      "bad": "initialization\n  GProtokoll := TProtokoll.Create;\nend.",',
    '      "good": "initialization\n  GProtokoll := TProtokoll.Create;\n\nfinalization\n  FreeAndNil(GProtokoll);\nend."',
    '    },',
    '{',
    '      "id": "compiler-warnings-disabled",',
    '      "name": "Compiler warnings or checks switched off up to the end of the unit",',
    '      "category": "code-smell",',
    '      "severity": "warning",',
    '      "group": "robustness",',
    '      "description": "{$WARNINGS OFF}, {$HINTS OFF}, {$WARN X OFF}, {$R-}, {$Q-} (also combined as {$R-,Q-}) or the long forms {$RANGECHECKS OFF} and {$OVERFLOWCHECKS OFF} without a later restore up t' +
    'o the end of the unit. Messages and checks disappear far beyond the intended spot, and the 0/0/0 rule is bypassed. Any later ON, +, DEFAULT or ERROR for the same switch counts as a restore, also insid' +
    'e {$IFOPT}/{$IFDEF} patterns, as does a later {$POPOPT}. A switch whose counterpart stands in another branch of the same {$IF} ({$IFDEF DEBUG}{$R+}{$ELSE}{$R-}{$ENDIF}) is a deliberate setting per con' +
    'figuration and stays silent, as does a directive with no code after it; {$R *.dfm} is a resource, not a range check. Option allow lists switches that may stay off (warning names such as SYMBOL_PLATFOR' +
    'M, WARNINGS, HINTS, R or RANGECHECKS, Q or OVERFLOWCHECKS). High confidence. Quick fix: insert the restore ({$WARNINGS ON}, {$WARN X DEFAULT}, {$R+} …) after the next block; for range and overflow che' +
    'cks only individually, since {$R+} may switch on a check the project has off.",',
    '      "bad": "{$WARNINGS OFF}\nfunction AlteBerechnung(const Wert: Integer): Integer;\nbegin\n  Result := Wert * 2;\nend;",',
    '      "good": "{$WARNINGS OFF}\nfunction AlteBerechnung(const Wert: Integer): Integer;\nbegin\n  Result := Wert * 2;\nend;\n{$WARNINGS ON}",',
    '      "options": [',
    '        {',
    '          "name": "allow",',
    '          "type": "string-list",',
    '          "default": [],',
    '          "description": "Switches that may stay off up to the end of the unit: warning names for {$WARN} (SYMBOL_PLATFORM), WARNINGS, HINTS, R or RANGECHECKS, Q or OVERFLOWCHECKS; case is ignored."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "dll-export-unsafe",',
    '      "name": "Exported routine not safe across DLL boundaries",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "robustness",',
    '      "description": "A routine of this file listed in exports has no calling convention (stdcall, cdecl, safecall, winapi or pascal; register is the Delphi convention) or takes or returns a string (s' +
    'tring, UnicodeString, AnsiString, UTF8String, RawByteString), a dynamic array (TBytes, TArray<T>, …DynArray, array of T declared in the file), an object or an interface without GUID. Callers in other ' +
    'languages or Delphi versions crash; strings and dynamic arrays live in the memory manager of the DLL. WideString, ShortString, PChar, open array parameters and records are fine. Objects are only recog' +
    'nised for certain: classes of the file, of the index and common RTL classes; interfaces only from the file. Routines from other units and overloads that the exports entry does not pin down stay silent' +
    '. With ShareMem or SimpleShareMem in uses, strings and dynamic arrays are allowed (option allowShareMem). The finding sits on the exports entry; for strings it recommends PChar with buffer and length.' +
    ' High confidence. Quick fix: add stdcall to every header of the routine (only individually, since it changes the interface for existing callers).",',
    '      "bad": "function KundeName(Id: Integer): string;\n…\nexports\n  KundeName;",',
    '      "good": "function KundeName(Id: Integer; Puffer: PChar; Laenge: Integer): Integer; stdcall;\n…\nexports\n  KundeName;",',
    '      "options": [',
    '        {',
    '          "name": "allowShareMem",',
    '          "type": "boolean",',
    '          "default": true,',
    '          "description": "With ShareMem or SimpleShareMem in uses, strings and dynamic arrays are allowed in exported routines."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "global-formatsettings-modified",',
    '      "name": "Global FormatSettings is modified",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "robustness",',
    '      "description": "Assignment to the global FormatSettings or one of its fields (also to the deprecated global variables DecimalSeparator, ShortDateFormat, ThousandSeparator … of older Delphi versi' +
    'ons). This changes the formatting for the whole application, for every package in the same process (in an IDE plugin the IDE itself) and for all threads, and is not thread-safe; it is often a workarou' +
    'nd to force a dot as decimal separator. Reported only when the name is surely the variable from System.SysUtils: no local declaration, no member of the class or its ancestors (silent when the chain of' +
    ' ancestors ends at an unknown class), not inside with. Complements format-without-settings, which reports formatting calls without settings. High confidence. Quick fix when the routine changes the glo' +
    'bal settings only once and formats something afterwards: declare a local TFormatSettings (TFormatSettings.Invariant for DecimalSeparator := ''.'', otherwise a copy of FormatSettings with the changed fie' +
    'ld) and pass it to the formatting calls that follow. With allowInProgram on, assignments in the .dpr are allowed.",',
    '      "bad": "procedure TExport.Schreiben;\nbegin\n  FormatSettings.DecimalSeparator := ''.'';\n  Zeile := FloatToStr(Betrag);\nend;",',
    '      "good": "procedure TExport.Schreiben;\nvar\n  FS: TFormatSettings;\nbegin\n  FS := TFormatSettings.Invariant;\n  Zeile := FloatToStr(Betrag, FS);\nend;",',
    '      "options": [',
    '        {',
    '          "name": "allowInProgram",',
    '          "type": "boolean",',
    '          "default": false,',
    '          "description": "Allow the assignments in the .dpr, for example once at program start."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "ui-call-in-console-or-service",',
    '      "name": "Dialog in a console program or service",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "robustness",',
    '      "description": "ShowMessage, ShowMessageFmt, MessageDlg, TaskMessageDlg, InputBox, InputQuery, Application.MessageBox or TDialogService in a program with {$APPTYPE CONSOLE} (or DCC_ConsoleTarget' +
    ' in the .dproj), in a Windows service or in a DLL without forms. In a service the dialog blocks invisibly; a console program waits for a click nobody sees when it runs unattended. A service is a unit ' +
    'with a class derived from TService, or any unit of a project whose .dpr uses Vcl.SvcMgr without Vcl.Forms. A DLL without forms is a library whose .dpr lists no form and does not use Vcl.Forms; there t' +
    'he rule reports with medium confidence, because only the host decides whether there is a user interface. Units with a form file, calls under if IsConsole and routines of the same name declared in the ' +
    'unit stay silent. Counterpart of writeln-in-gui-app. High confidence. No quick fix: log the message instead of showing it.",',
    '      "bad": "procedure TDatenDienst.ServiceExecute(Sender: TService);\nbegin\n  if not Verbinden then\n    ShowMessage(''Keine Verbindung'');\nend;",',
    '      "good": "procedure TDatenDienst.ServiceExecute(Sender: TService);\nbegin\n  if not Verbinden then\n    LogMessage(''Keine Verbindung'', EVENTLOG_ERROR_TYPE);\nend;"',
    '    },',
    '{',
    '      "id": "load-without-encoding",',
    '      "name": "Loading or saving text without an encoding",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "robustness",',
    '      "description": "LoadFromFile, SaveToFile, LoadFromStream or SaveToStream of a TStrings (TStringList, Memo.Lines, ListBox.Items, Query.SQL) and TFile.ReadAllText or TFile.ReadAllLines without an ' +
    'encoding: a file without BOM is read with the ANSI code page of the machine, and SaveToFile writes ANSI, so umlauts get lost between machines. The receiver must be a declared string list or a Lines, I' +
    'tems, SQL or Strings property; bitmaps, streams and datasets stay silent. Also silent when the list sets DefaultEncoding anywhere in the unit or was loaded with an encoding earlier in the same routine' +
    ' (SaveToFile then keeps that encoding). TFile.WriteAllText, TStreamReader and TStreamWriter already default to UTF-8 and are not reported. Medium confidence. Quick fix: add TEncoding.UTF8 (option defa' +
    'ultEncoding) as the last argument and System.SysUtils to uses.",',
    '      "bad": "Zeilen.LoadFromFile(Pfad);",',
    '      "good": "Zeilen.LoadFromFile(Pfad, TEncoding.UTF8);",',
    '      "options": [',
    '        {',
    '          "name": "defaultEncoding",',
    '          "type": "string",',
    '          "default": "UTF8",',
    '          "description": "TEncoding property the quick fix inserts: UTF8, Unicode, BigEndianUnicode, ANSI, ASCII, UTF7 or Default."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "registry-hklm-write",',
    '      "name": "Writing to HKEY_LOCAL_MACHINE",',
    '      "category": "bug",',
    '      "severity": "hint",',
    '      "group": "robustness",',
    '      "description": "RootKey := HKEY_LOCAL_MACHINE on a TRegistry followed in the same routine by a writing access on the same object: OpenKey(…, True), CreateKey, Write…, DeleteKey, DeleteValue, Ren' +
    'ameValue, MoveKey, SaveKey or RestoreKey. Without administrator rights this fails or silently lands in the registry virtualization. Use HKEY_CURRENT_USER for user settings; exclude installer code thro' +
    'ugh exclude. Reading (OpenKeyReadOnly, Read…, OpenKey(…, False)), another RootKey before the write and writes in the other branch of {$IFDEF} stay silent. High confidence. Quick fix: RootKey := HKEY_C' +
    'URRENT_USER.",',
    '      "bad": "Reg.RootKey := HKEY_LOCAL_MACHINE;\nReg.OpenKey(''Software\\Firma\\Programm'', True);\nReg.WriteString(''Sprache'', Sprache);",',
    '      "good": "Reg.RootKey := HKEY_CURRENT_USER;\nReg.OpenKey(''Software\\Firma\\Programm'', True);\nReg.WriteString(''Sprache'', Sprache);"',
    '    }');

implementation

end.
