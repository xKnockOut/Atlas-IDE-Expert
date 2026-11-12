unit Atlas.Common.Rules.Catalog.Data.En.Migration;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog.json.
// Nicht von Hand ändern.

interface

const
  cCatalogLinesEnMigration: array[0..59] of string = (
    '{',
    '      "id": "pointer-integer-cast",',
    '      "name": "Pointer in a 32-bit integer",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "migration",',
    '      "description": "Win64 migration (#112): Integer(P), Cardinal(Obj), LongInt(@X), DWORD(Pointer(X)) and other casts to a 32-bit integer type with a pointer, an object, a class reference or an inte' +
    'rface as argument. Under Win64 pointers are 8 bytes and the upper 32 bits are lost. The reverse is reported as well: TKunde(I) or IKunde(I) with I: Integer means I held a pointer in 32 bits. Pointer(I' +
    ') stays silent (numbers in pointer lists are intended and lossless). The rule only reports when the type is known for sure and its declaration is always compiled together with the cast; casts in inact' +
    'ive branches and in branches by platform ({$IFDEF CPUX86}, {$IFDEF WIN32}, {$IF SizeOf(Pointer) = 4} and their {$ELSE}) are silent, as are Delphi versions before XE2. Quick fix: NativeInt or NativeUIn' +
    't instead of the 32-bit type.",',
    '      "bad": "Liste.Add(IntToStr(Integer(Kunde)));",',
    '      "good": "Liste.Add(IntToStr(NativeInt(Kunde)));"',
    '    },',
    '{',
    '      "id": "handle-as-integer",',
    '      "name": "Handle or message parameter in a 32-bit integer",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "migration",',
    '      "description": "Win64 migration (#112): parameters wParam or lParam (also AWParam, ALParam) declared as Longint, Integer, Cardinal or DWORD, and the result of such a routine (window procedure): ' +
    'under Win64 WPARAM, LPARAM and LRESULT are 64 bits wide. Also the assignment of a handle (THandle, HWND, HDC, HMODULE ...), WPARAM, LPARAM, LRESULT or *_PTR value to a variable of a 32-bit integer typ' +
    'e; the type comes from the declaration of the source, so it also works without the Windows sources. NativeInt to Integer is reported by narrowing-assignment. Silent in inactive branches, in branches b' +
    'y platform and before Delphi XE2. Quick fixes: WPARAM, LPARAM or LRESULT as the type; for a local variable declared alone, take over the type of the source.",',
    '      "bad": "function FensterProc(Wnd: HWND; Msg: UINT; wParam: Longint; lParam: Longint): Longint; stdcall;",',
    '      "good": "function FensterProc(Wnd: HWND; Msg: UINT; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;"',
    '    },',
    '{',
    '      "id": "window-long-ptr",',
    '      "name": "…LongPtr instead of …Long for pointers and handles",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "migration",',
    '      "description": "Win64 migration (#112): SetWindowLong, GetWindowLong, SetClassLong and GetClassLong (also with A or W) with an index that reads or writes a pointer or handle: GWL_WNDPROC, GWL_US' +
    'ERDATA, GWL_HINSTANCE, GWL_HWNDPARENT, DWL_MSGRESULT, DWL_DLGPROC, DWL_USER and the GCL_ indices for icons, cursor, background, module, menu name and window procedure. Under Win64 these functions read' +
    ' and write only 32 bits. Indices with 32-bit values (GWL_STYLE, GWL_EXSTYLE, GWL_ID) are not reported. Silent in inactive branches, in branches by platform and before Delphi XE2. Quick fix: ...LongPtr' +
    ' with the GWLP_, DWLP_ or GCLP_ index; a 32-bit cast of the new value becomes LONG_PTR.",',
    '      "bad": "SetWindowLong(Handle, GWL_WNDPROC, Integer(@NeueProc));",',
    '      "good": "SetWindowLongPtr(Handle, GWLP_WNDPROC, LONG_PTR(@NeueProc));"',
    '    },',
    '{',
    '      "id": "asm-without-win64",',
    '      "name": "Assembler without Win64 variant",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "migration",',
    '      "description": "Win64 migration (#112): asm block outside a branch by platform ({$IFDEF CPUX86}, {$IFNDEF CPUX64}, {$IFNDEF PUREPASCAL} ...). dcc64 compiles neither x86 assembler nor asm inside ' +
    'begin ... end (E1025). Routines whose asm uses 64-bit registers (rax, r8 ...) are already Win64 code and are not reported. Files for Free Pascal ({$MODE ...}, {$ASMMODE ...}) and Delphi versions befor' +
    'e XE2 are silent. No quick fix: the Pascal variant has to be written by hand.",',
    '      "bad": "function Tausche(Wert: Cardinal): Cardinal;\nasm\n  bswap eax\nend;",',
    '      "good": "function Tausche(Wert: Cardinal): Cardinal;\n{$IFDEF CPUX86}\nasm\n  bswap eax\nend;\n{$ELSE}\nbegin\n  Result := Swap(Wert shr 16) or (Cardinal(Swap(Wert)) shl 16);\nend;\n{$ENDIF}"',
    '    },',
    '{',
    '      "id": "char-count-as-bytes",',
    '      "name": "Character count as byte count",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "migration",',
    '      "description": "Unicode migration (#117): Length(S) or StrLen(P) as the byte count of Move, FillChar, CopyMemory, MoveMemory, ZeroMemory, FillMemory, CompareMem, BlockRead, BlockWrite, ReadFile,' +
    ' WriteFile or the stream methods Read, ReadBuffer, Write and WriteBuffer with a buffer from the same string (S[1], @S[1], PChar(S), Pointer(S)^), and GetMem or ReallocMem of a PChar with Length(S) (+ ' +
    '1). Since Delphi 2009 a Char has 2 bytes: only half of the characters is copied, or half the memory allocated. S must be string, UnicodeString or WideString for sure, P PChar or PWideChar; Length(S) m' +
    'ay be shifted by a number with + or -. Silent in inactive branches, with {$H-} and before Delphi 2009. Quick fix: multiply by SizeOf(Char); not safe, because a target buffer of AnsiChar then overflows' +
    ' and needs a conversion instead.",',
    '      "bad": "Move(S[1], Puffer, Length(S));",',
    '      "good": "Move(S[1], Puffer, Length(S) * SizeOf(Char));"',
    '    },',
    '{',
    '      "id": "ansi-api-call",',
    '      "name": "Ansi function with converted string",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "migration",',
    '      "description": "Unicode migration (#117): call of an ...A function (MessageBoxA, CreateFileA ...) with PAnsiChar(AnsiString(S)) and S being string for sure: characters outside the ANSI code page' +
    ' are lost. The function without A takes the string unchanged. Mixing AnsiString and string (string-conversion, W1057/W1058) and PChar on AnsiString (suspicious-string-pointer-cast, W1044) are separate' +
    ' rules. Silent in inactive branches, with {$H-} and before Delphi 2009. Quick fix: the function without A with PChar(S); offered when the function is not resolved or comes from a Winapi unit and no ot' +
    'her argument is an Ansi type for sure.",',
    '      "bad": "MessageBoxA(0, PAnsiChar(AnsiString(Text)), ''Atlas'', MB_OK);",',
    '      "good": "MessageBox(0, PChar(Text), ''Atlas'', MB_OK);"',
    '    }');

implementation

end.
