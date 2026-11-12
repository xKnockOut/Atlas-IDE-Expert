unit Atlas.Common.Rules.Catalog.Data.De.Migration;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog.de.json.
// Nicht von Hand ändern.

interface

const
  cCatalogLinesDeMigration: array[0..29] of string = (
    '{',
    '      "id": "pointer-integer-cast",',
    '      "name": "Zeiger in einer 32-Bit-Zahl",',
    '      "description": "Umstellung auf Win64 (#112): Integer(P), Cardinal(Obj), LongInt(@X), DWORD(Pointer(X)) und andere Umwandlungen in einen 32-Bit-Ganzzahltyp mit einem Zeiger, einem Objekt, einer K' +
    'lassenreferenz oder einem Interface als Argument. Unter Win64 sind Zeiger 8 Byte groß, die oberen 32 Bit gehen verloren. Auch umgekehrt: TKunde(I) bzw. IKunde(I) mit I: Integer heißt, I hat einen Zeig' +
    'er in 32 Bit gehalten. Pointer(I) bleibt still (Zahlen in Zeigerlisten sind gewollt und verlustfrei). Gemeldet wird nur bei sicher bekanntem Typ, dessen Deklaration immer mit der Umwandlung übersetzt ' +
    'wird; still in inaktiven Zweigen, in Zweigen nach Plattform ({$IFDEF CPUX86}, {$IFDEF WIN32}, {$IF SizeOf(Pointer) = 4} samt {$ELSE}) und vor Delphi XE2. Korrektur: NativeInt bzw. NativeUInt statt des' +
    ' 32-Bit-Typs."',
    '    },',
    '{',
    '      "id": "handle-as-integer",',
    '      "name": "Handle oder Nachrichtenparameter in einer 32-Bit-Zahl",',
    '      "description": "Umstellung auf Win64 (#112): Parameter wParam bzw. lParam (auch AWParam, ALParam) mit Longint, Integer, Cardinal oder DWORD und das Ergebnis einer solchen Routine (Fensterprozedu' +
    'r): Unter Win64 sind WPARAM, LPARAM und LRESULT 64 Bit breit. Außerdem die Zuweisung eines Handles (THandle, HWND, HDC, HMODULE …), WPARAM, LPARAM, LRESULT oder *_PTR an eine Variable mit 32-Bit-Ganzz' +
    'ahltyp; der Typ stammt aus der Deklaration der Quelle und gilt daher auch ohne Windows-Quelltexte. NativeInt nach Integer meldet narrowing-assignment. Still in inaktiven Zweigen, in Zweigen nach Platt' +
    'form und vor Delphi XE2. Korrekturen: WPARAM, LPARAM bzw. LRESULT als Typ; bei einer lokalen Variablen, die allein deklariert ist, den Typ der Quelle übernehmen."',
    '    },',
    '{',
    '      "id": "window-long-ptr",',
    '      "name": "…LongPtr statt …Long für Zeiger und Handles",',
    '      "description": "Umstellung auf Win64 (#112): SetWindowLong, GetWindowLong, SetClassLong und GetClassLong (auch mit A bzw. W) mit einem Index, der einen Zeiger oder ein Handle liest bzw. schreibt' +
    ': GWL_WNDPROC, GWL_USERDATA, GWL_HINSTANCE, GWL_HWNDPARENT, DWL_MSGRESULT, DWL_DLGPROC, DWL_USER und die GCL_-Indizes für Symbole, Mauszeiger, Hintergrund, Modul, Menüname und Fensterprozedur. Unter W' +
    'in64 lesen und schreiben diese Funktionen nur 32 Bit. Indizes mit 32-Bit-Werten (GWL_STYLE, GWL_EXSTYLE, GWL_ID) meldet die Regel nicht. Still in inaktiven Zweigen, in Zweigen nach Plattform und vor D' +
    'elphi XE2. Korrektur: …LongPtr mit dem GWLP_-, DWLP_- bzw. GCLP_-Index; eine 32-Bit-Umwandlung des neuen Werts wird LONG_PTR."',
    '    },',
    '{',
    '      "id": "asm-without-win64",',
    '      "name": "Assembler ohne Win64-Variante",',
    '      "description": "Umstellung auf Win64 (#112): asm-Block außerhalb eines Zweigs nach Plattform ({$IFDEF CPUX86}, {$IFNDEF CPUX64}, {$IFNDEF PUREPASCAL} …). dcc64 übersetzt weder x86-Assembler noch' +
    ' asm innerhalb von begin … end (E1025). Routinen, deren asm 64-Bit-Register (rax, r8 …) verwendet, sind schon Win64-Code und werden nicht gemeldet. Dateien für Free Pascal ({$MODE …}, {$ASMMODE …}) un' +
    'd Delphi-Versionen vor XE2 bleiben still. Keine Korrektur: Die Pascal-Variante entsteht von Hand."',
    '    },',
    '{',
    '      "id": "char-count-as-bytes",',
    '      "name": "Zeichenzahl als Byteanzahl",',
    '      "description": "Umstellung auf Unicode (#117): Length(S) bzw. StrLen(P) als Byteanzahl von Move, FillChar, CopyMemory, MoveMemory, ZeroMemory, FillMemory, CompareMem, BlockRead, BlockWrite, Read' +
    'File, WriteFile oder der Stream-Methoden Read, ReadBuffer, Write und WriteBuffer mit einem Puffer aus demselben String (S[1], @S[1], PChar(S), Pointer(S)^) sowie GetMem bzw. ReallocMem eines PChar mit' +
    ' Length(S) (+ 1). Seit Delphi 2009 hat ein Char 2 Byte: Es wird nur die Hälfte der Zeichen kopiert bzw. die Hälfte des Speichers angelegt. S ist sicher string, UnicodeString oder WideString, P sicher ' +
    'PChar bzw. PWideChar; Length(S) darf mit + bzw. - um eine Zahl verschoben sein. Still in inaktiven Zweigen, mit {$H-} und vor Delphi 2009. Korrektur: mit SizeOf(Char) malnehmen; nicht sicher, weil ein' +
    ' Zielpuffer aus AnsiChar dann überläuft und stattdessen eine Umwandlung braucht."',
    '    },',
    '{',
    '      "id": "ansi-api-call",',
    '      "name": "Ansi-Funktion mit umgewandeltem string",',
    '      "description": "Umstellung auf Unicode (#117): Aufruf einer …A-Funktion (MessageBoxA, CreateFileA …) mit PAnsiChar(AnsiString(S)) und S sicher string: Zeichen außerhalb der ANSI-Codepage gehen v' +
    'erloren. Die Funktion ohne A nimmt den string unverändert. Mischungen von AnsiString und string (string-conversion, W1057/W1058) und PChar auf AnsiString (suspicious-string-pointer-cast, W1044) sind e' +
    'igene Regeln. Still in inaktiven Zweigen, mit {$H-} und vor Delphi 2009. Korrektur: Funktion ohne A mit PChar(S); angeboten, wenn die Funktion nicht aufgelöst ist oder aus einer Winapi-Unit stammt und' +
    ' kein anderes Argument sicher ein Ansi-Typ ist."',
    '    }');

implementation

end.
