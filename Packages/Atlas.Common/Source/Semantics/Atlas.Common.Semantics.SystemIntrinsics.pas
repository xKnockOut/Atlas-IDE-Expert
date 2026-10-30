unit Atlas.Common.Semantics.SystemIntrinsics;

// Bezeichner der Unit System ohne Quelltext (#880): Compiler-Intrinsics (Assigned, Length, SetLength,
// Inc ...), eingebaute Typen (Integer, Int64, NativeInt ..., auch Text/TextFile und die alten Typen Real48,
// OpenString, OleVariant, LongInt, #1382), die Datei-Routinen (AssignFile, Append, Reset, CloseFile, Eof ...),
// Speicher (GetMem, FreeMem, ReallocMem), Mathematik (Sqrt, Sin, Int, Frac ...) und RunError (#1382) sowie
// True/False. Die Unit System ist immer eingebunden; was in System.pas steht, kommt aus dem Index, sofern
// die RTL-Quelle indexiert ist. Diese Liste ergänzt nur, was dort fehlt, und gilt deshalb erst nach allen
// indexierten Units.
// Die Köpfe sind für Parameter-Hinweis und Hover gedacht; generische bzw. untypisierte Parameter
// stehen wie in der Delphi-Hilfe ohne Typ.

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract;

type
  TSystemIntrinsic = record
    Name: string;
    /// <summary>Kopf einer Überladung, z. B. "procedure Inc(var X; N: Integer);" oder "type Integer".</summary>
    Declaration: string;
    Documentation: string;
    /// <summary>Routine, eingebauter Typ (RecordType) oder Konstante.</summary>
    Kind: TIndexSymbolKind;
    MinArgs: Integer;
    MaxArgs: Integer;
  end;

  TSystemIntrinsics = class
  public
    /// <summary>Alle Einträge; Überladungen stehen einzeln, gleichnamige direkt hintereinander.</summary>
    class function All: TArray<TSystemIntrinsic>; static;
    /// <summary>Alle Überladungen zu AName (Groß-/Kleinschreibung egal); leer, wenn unbekannt.</summary>
    class function Find(const AName: string): TArray<TSystemIntrinsic>; static;
    class function IsKnown(const AName: string): Boolean; static;
    /// <summary>Ist AName ein eingebauter Typ dieser Liste (Integer, TextFile …)?</summary>
    class function IsType(const AName: string): Boolean; static;
    /// <summary>Bezeichner an APosition (im Namen oder direkt dahinter), der ein Eintrag dieser Liste sein
    /// kann: nicht hinter einem Punkt (Liste.Length ist ein Mitglied) und nicht mit &amp;-Escape.</summary>
    class function NameAt(ATree: TSyntaxTree; const APosition: TTextPosition; out AName: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.Contract;

const
  // Name|Art (R Routine, T Typ, C Konstante)|Kopf|Beschreibung
  Entries: array[0..145] of string = (
    'Abs|R|function Abs(X): <Typ von X>;|Betrag einer Zahl.',
    'Addr|R|function Addr(var X): Pointer;|Adresse einer Variablen oder Routine (wie @).',
    'Append|R|procedure Append(var F: Text);|Öffnet eine Textdatei zum Anhängen.',
    'ArcTan|R|function ArcTan(const X: Extended): Extended;|Arkustangens im Bogenmaß.',
    'Assert|R|procedure Assert(Condition: Boolean);|Löst EAssertionFailed aus, wenn Condition False ist.',
    'Assert|R|procedure Assert(Condition: Boolean; const Message: string);|Löst EAssertionFailed mit Message aus, wenn Condition False ist.',
    'Assign|R|procedure Assign(var F; const FileName: string; CodePage: Word = 0);|Verbindet eine Dateivariable mit einem Dateinamen (alter Name von AssignFile).',
    'Assigned|R|function Assigned(const P): Boolean;|True, wenn Zeiger, Objekt, Interface oder Methodenzeiger nicht nil ist.',
    'AssignFile|R|procedure AssignFile(var F; const FileName: string; CodePage: Word = 0);|Verbindet eine Dateivariable mit einem Dateinamen; CodePage nur für Textdateien.',
    'AtomicCmpExchange|R|function AtomicCmpExchange(var Target; NewValue, Comparand): <Typ von Target>;|Vergleicht Target mit Comparand und setzt bei Gleichheit NewValue (atomar); liefert den alten Wert.',
    'AtomicDecrement|R|function AtomicDecrement(var Target; Decrement: Integer = 1): <Typ von Target>;|Verringert Target atomar und liefert den neuen Wert.',
    'AtomicExchange|R|function AtomicExchange(var Target; Value): <Typ von Target>;|Setzt Target atomar auf Value und liefert den alten Wert.',
    'AtomicIncrement|R|function AtomicIncrement(var Target; Increment: Integer = 1): <Typ von Target>;|Erhöht Target atomar und liefert den neuen Wert.',
    'BlockRead|R|procedure BlockRead(var F: File; var Buf; Count: Integer; var AmtTransferred: Integer = 0);|Liest Count Datensätze einer untypisierten Datei in Buf.',
    'BlockWrite|R|procedure BlockWrite(var F: File; const Buf; Count: Integer; var AmtTransferred: Integer = 0);|Schreibt Count Datensätze aus Buf in eine untypisierte Datei.',
    'Break|R|procedure Break;|Verlässt die innerste Schleife.',
    'Chr|R|function Chr(X: Byte): Char;|Zeichen zum Ordinalwert X.',
    'Close|R|procedure Close(var F);|Schließt eine Datei (alter Name von CloseFile).',
    'CloseFile|R|procedure CloseFile(var F);|Schließt eine mit AssignFile verbundene Datei.',
    'Concat|R|function Concat(const S1, S2: string): string;|Verkettet Strings oder dynamische Arrays (beliebig viele Argumente).',
    'Continue|R|procedure Continue;|Springt zum nächsten Durchlauf der innersten Schleife.',
    'Copy|R|function Copy(const S: string; Index, Count: Integer): string;|Teilstring bzw. Teil eines dynamischen Arrays ab Index (Strings ab 1, Arrays ab 0).',
    'Copy|R|function Copy(const S: string; Index: Integer): string;|Rest ab Index.',
    'Cos|R|function Cos(const X: Extended): Extended;|Kosinus eines Winkels im Bogenmaß.',
    'Dec|R|procedure Dec(var X);|Verringert X um 1.',
    'Dec|R|procedure Dec(var X; N: Integer);|Verringert X um N.',
    'Default|R|function Default(T): T;|Standardwert des Typs T (0, nil, leerer String ...).',
    'Delete|R|procedure Delete(var S: string; Index, Count: Integer);|Entfernt Count Zeichen bzw. Elemente ab Index.',
    'Dispose|R|procedure Dispose(var P: Pointer);|Gibt eine mit New angelegte Variable frei.',
    'Eof|R|function Eof(var F): Boolean;|True am Dateiende.',
    'Eof|R|function Eof: Boolean;|True am Ende der Standardeingabe.',
    'Eoln|R|function Eoln(var F: Text): Boolean;|True am Zeilenende einer Textdatei.',
    'Eoln|R|function Eoln: Boolean;|True am Zeilenende der Standardeingabe.',
    'Erase|R|procedure Erase(var F);|Löscht die mit F verbundene, geschlossene Datei.',
    'Exclude|R|procedure Exclude(var S; I);|Entfernt das Element I aus der Menge S.',
    'Exit|R|procedure Exit;|Verlässt die aktuelle Routine.',
    'Exit|R|procedure Exit(const Value);|Setzt Result auf Value und verlässt die Funktion.',
    'Exp|R|function Exp(const X: Extended): Extended;|e hoch X.',
    'Fail|R|procedure Fail;|Bricht im Konstruktor eines object-Typs das Anlegen ab (alte object-Syntax).',
    'FilePos|R|function FilePos(var F): Int64;|Aktuelle Position in einer typisierten oder untypisierten Datei.',
    'FileSize|R|function FileSize(var F): Int64;|Größe einer typisierten oder untypisierten Datei in Datensätzen.',
    'Finalize|R|procedure Finalize(var V; Count: NativeInt = 1);|Gibt verwaltete Inhalte (Strings, Interfaces ...) von V frei.',
    'Flush|R|procedure Flush(var F: Text);|Schreibt den Puffer einer Textdatei.',
    'Frac|R|function Frac(const X: Extended): Extended;|Nachkommateil einer Zahl.',
    'FreeMem|R|procedure FreeMem(var P: Pointer; Size: NativeInt = 0);|Gibt mit GetMem oder AllocMem angelegten Speicher frei.',
    'GetMem|R|procedure GetMem(var P: Pointer; Size: NativeInt);|Legt Size Bytes Speicher an und setzt P darauf (Inhalt nicht initialisiert).',
    'GetTypeKind|R|function GetTypeKind(T): TTypeKind;|Art des Typs T, zur Übersetzungszeit ausgewertet.',
    'Halt|R|procedure Halt(ExitCode: Integer = 0);|Beendet das Programm.',
    'HasWeakRef|R|function HasWeakRef(T): Boolean;|True, wenn T [Weak]-Referenzen enthält.',
    'Hi|R|function Hi(X: Word): Byte;|Höherwertiges Byte von X.',
    'High|R|function High(X): Integer;|Höchster Index bzw. Wert eines Arrays, Strings oder Ordinaltyps.',
    'Inc|R|procedure Inc(var X);|Erhöht X um 1.',
    'Inc|R|procedure Inc(var X; N: Integer);|Erhöht X um N.',
    'Include|R|procedure Include(var S; I);|Fügt das Element I der Menge S hinzu.',
    'Initialize|R|procedure Initialize(var V; Count: NativeInt = 1);|Initialisiert verwaltete Inhalte von V.',
    'Insert|R|procedure Insert(const Source: string; var Dest: string; Index: Integer);|Fügt Source an der Stelle Index in Dest ein (auch dynamische Arrays).',
    'Int|R|function Int(const X: Extended): Extended;|Ganzzahliger Teil einer Zahl als Gleitkommazahl.',
    'IOResult|R|function IOResult: Integer;|Fehlercode der letzten Ein-/Ausgabe unter {$I-}; setzt ihn zurück.',
    'IsConstValue|R|function IsConstValue(const Value): Boolean;|True, wenn Value zur Übersetzungszeit konstant ist.',
    'IsManagedType|R|function IsManagedType(T): Boolean;|True, wenn T verwaltete Inhalte hat (Strings, Interfaces ...).',
    'Length|R|function Length(const S): Integer;|Länge eines Strings oder Anzahl der Elemente eines Arrays.',
    'Ln|R|function Ln(const X: Extended): Extended;|Natürlicher Logarithmus.',
    'Lo|R|function Lo(X: Word): Byte;|Niederwertiges Byte von X.',
    'Low|R|function Low(X): Integer;|Niedrigster Index bzw. Wert eines Arrays, Strings oder Ordinaltyps.',
    'New|R|procedure New(var P: Pointer);|Legt eine neue dynamische Variable an und setzt P darauf.',
    'Odd|R|function Odd(X: Int64): Boolean;|True, wenn X ungerade ist.',
    'Ord|R|function Ord(X): Int64;|Ordinalwert von X.',
    'Pi|R|function Pi: Extended;|Die Zahl Pi.',
    'Pred|R|function Pred(X): <Typ von X>;|Vorgänger des Ordinalwerts X.',
    'Ptr|R|function Ptr(Address: NativeInt): Pointer;|Zeiger auf die Adresse Address.',
    'Read|R|procedure Read(var F: Text; var V1);|Liest Werte aus einer Datei bzw. der Konsole.',
    'Readln|R|procedure Readln(var F: Text; var V1);|Liest Werte und springt in die nächste Zeile.',
    'ReallocMem|R|procedure ReallocMem(var P: Pointer; Size: NativeInt);|Ändert die Größe eines mit GetMem angelegten Speicherblocks; Size 0 gibt ihn frei.',
    'Rename|R|procedure Rename(var F; const NewName: string);|Benennt die mit F verbundene, geschlossene Datei um.',
    'Reset|R|procedure Reset(var F; RecSize: Integer = 128);|Öffnet eine bestehende Datei; RecSize nur für untypisierte Dateien.',
    'ReturnAddress|R|function ReturnAddress: Pointer;|Rücksprungadresse der aktuellen Routine.',
    'Rewrite|R|procedure Rewrite(var F; RecSize: Integer = 128);|Legt eine Datei an bzw. leert sie; RecSize nur für untypisierte Dateien.',
    'Round|R|function Round(X: Extended): Int64;|Rundet X auf die nächste Ganzzahl.',
    'RunError|R|procedure RunError(ErrorCode: Byte = 0);|Beendet das Programm mit einem Laufzeitfehler.',
    'Seek|R|procedure Seek(var F; N: Int64);|Setzt die Position in einer typisierten oder untypisierten Datei.',
    'SeekEof|R|function SeekEof(var F: Text): Boolean;|Wie Eof, überspringt vorher Leerraum.',
    'SeekEof|R|function SeekEof: Boolean;|Wie Eof für die Standardeingabe, überspringt vorher Leerraum.',
    'SeekEoln|R|function SeekEoln(var F: Text): Boolean;|Wie Eoln, überspringt vorher Leerzeichen und Tabs.',
    'SeekEoln|R|function SeekEoln: Boolean;|Wie Eoln für die Standardeingabe, überspringt vorher Leerzeichen und Tabs.',
    'SetLength|R|procedure SetLength(var S; NewLength: NativeInt);|Setzt die Länge eines Strings oder dynamischen Arrays (mehrdimensional: weitere Längen).',
    'SetString|R|procedure SetString(var S: string; Buffer: PChar; Length: Integer);|Setzt S auf Length Zeichen ab Buffer.',
    'SetTextBuf|R|procedure SetTextBuf(var F: Text; var Buf; Size: Integer = 0);|Gibt einer Textdatei einen eigenen Puffer.',
    'Sin|R|function Sin(const X: Extended): Extended;|Sinus eines Winkels im Bogenmaß.',
    'SizeOf|R|function SizeOf(const X): Integer;|Größe einer Variablen oder eines Typs in Byte.',
    'Slice|R|function Slice(var A; Count: Integer): <offenes Array>;|Die ersten Count Elemente von A als offenes Array-Argument.',
    'Sqr|R|function Sqr(X): <Typ von X>;|Quadrat von X.',
    'Sqrt|R|function Sqrt(const X: Extended): Extended;|Quadratwurzel.',
    'Str|R|procedure Str(const X; var S: string);|Wandelt eine Zahl in einen String.',
    'Succ|R|function Succ(X): <Typ von X>;|Nachfolger des Ordinalwerts X.',
    'Swap|R|function Swap(X: Word): Word;|Vertauscht höher- und niederwertiges Byte.',
    'Trunc|R|function Trunc(X: Extended): Int64;|Schneidet die Nachkommastellen ab.',
    'Truncate|R|procedure Truncate(var F);|Schneidet eine Datei an der aktuellen Position ab.',
    'TypeHandle|R|function TypeHandle(T): Pointer;|Typinformation zu T (wie TypeInfo).',
    'TypeInfo|R|function TypeInfo(T): Pointer;|Zeiger auf die RTTI des Typs T.',
    'TypeOf|R|function TypeOf(X): Pointer;|Zeiger auf die VMT eines Objekttyps.',
    'Val|R|procedure Val(const S: string; var V; var Code: Integer);|Wandelt einen String in eine Zahl; Code ist die Fehlerstelle oder 0.',
    'Write|R|procedure Write(var F: Text; const P1);|Schreibt Werte in eine Datei bzw. auf die Konsole.',
    'Writeln|R|procedure Writeln(var F: Text; const P1);|Schreibt Werte und einen Zeilenumbruch.',
    'Boolean|T|type Boolean = (False, True);|Wahrheitswert.',
    'ByteBool|T|type ByteBool|Wahrheitswert, 1 Byte, ungleich 0 ist True.',
    'WordBool|T|type WordBool|Wahrheitswert, 2 Byte, ungleich 0 ist True.',
    'LongBool|T|type LongBool|Wahrheitswert, 4 Byte, ungleich 0 ist True.',
    'ShortInt|T|type ShortInt = -128..127;|Ganzzahl, 8 Bit mit Vorzeichen.',
    'SmallInt|T|type SmallInt = -32768..32767;|Ganzzahl, 16 Bit mit Vorzeichen.',
    'Integer|T|type Integer = -2147483648..2147483647;|Ganzzahl, 32 Bit mit Vorzeichen.',
    'Int64|T|type Int64 = -9223372036854775808..9223372036854775807;|Ganzzahl, 64 Bit mit Vorzeichen.',
    'Byte|T|type Byte = 0..255;|Ganzzahl, 8 Bit ohne Vorzeichen.',
    'Word|T|type Word = 0..65535;|Ganzzahl, 16 Bit ohne Vorzeichen.',
    'Cardinal|T|type Cardinal = 0..4294967295;|Ganzzahl, 32 Bit ohne Vorzeichen.',
    'UInt64|T|type UInt64 = 0..18446744073709551615;|Ganzzahl, 64 Bit ohne Vorzeichen.',
    'NativeInt|T|type NativeInt|Ganzzahl mit Vorzeichen in Zeigergröße (32 bzw. 64 Bit).',
    'NativeUInt|T|type NativeUInt|Ganzzahl ohne Vorzeichen in Zeigergröße (32 bzw. 64 Bit).',
    'Char|T|type Char = WideChar;|Zeichen, UTF-16-Codeeinheit.',
    'WideChar|T|type WideChar|Zeichen, UTF-16-Codeeinheit (2 Byte).',
    'AnsiChar|T|type AnsiChar|Zeichen, 1 Byte.',
    'UnicodeString|T|type UnicodeString|String aus UTF-16-Zeichen mit Referenzzählung (= string).',
    'AnsiString|T|type AnsiString|String aus 1-Byte-Zeichen mit Codepage.',
    'WideString|T|type WideString|COM-String (BSTR) ohne Referenzzählung.',
    'ShortString|T|type ShortString|String mit höchstens 255 Zeichen, Länge im ersten Byte.',
    'Pointer|T|type Pointer|Untypisierter Zeiger.',
    'PChar|T|type PChar = ^Char;|Zeiger auf nullterminierte Zeichen.',
    'PAnsiChar|T|type PAnsiChar = ^AnsiChar;|Zeiger auf nullterminierte 1-Byte-Zeichen.',
    'PWideChar|T|type PWideChar = ^WideChar;|Zeiger auf nullterminierte UTF-16-Zeichen.',
    'Single|T|type Single|Gleitkommazahl, 4 Byte.',
    'Double|T|type Double|Gleitkommazahl, 8 Byte.',
    'Extended|T|type Extended|Gleitkommazahl, 10 Byte unter Win32, sonst 8 Byte.',
    'Real|T|type Real = Double;|Gleitkommazahl (= Double).',
    'Comp|T|type Comp|64-Bit-Ganzzahl im Gleitkommaformat.',
    'Currency|T|type Currency|Festkommazahl mit 4 Nachkommastellen, 8 Byte.',
    'Variant|T|type Variant|Wert wechselnden Typs.',
    'Text|T|type Text|Textdatei für AssignFile, Reset, Readln und Writeln.',
    'TextFile|T|type TextFile = Text;|Textdatei für AssignFile, Reset, Readln und Writeln.',
    'Real48|T|type Real48|Alte Gleitkommazahl mit 6 Byte.',
    'OpenString|T|type OpenString|Offener ShortString-Parameter (alte Syntax).',
    'PShortString|T|type PShortString = ^ShortString;|Zeiger auf einen ShortString.',
    'Extended80|T|type Extended80|Gleitkommazahl mit 10 Byte auf allen Plattformen.',
    'LongInt|T|type LongInt|Ganzzahl mit Vorzeichen, 32 Bit (unter 64-Bit-Linux und iOS 64 Bit).',
    'LongWord|T|type LongWord|Ganzzahl ohne Vorzeichen, 32 Bit (unter 64-Bit-Linux und iOS 64 Bit).',
    'OleVariant|T|type OleVariant|Variant mit nur OLE-kompatiblen Typen.',
    'True|C|const True = Boolean(1);|Wahrheitswert wahr.',
    'False|C|const False = Boolean(0);|Wahrheitswert falsch.');

var
  GEntries: TArray<TSystemIntrinsic>;

/// <summary>Mindest- und Höchstzahl der Argumente aus dem Kopf; Parameter mit Standardwert zählen nicht
/// zur Mindestzahl.</summary>
procedure CountArgs(const ADeclaration: string; out AMin, AMax: Integer);
var
  Open, Close, Count: Integer;
  Group, Names: string;
begin
  AMin := 0;
  AMax := 0;
  Open := Pos('(', ADeclaration);
  Close := Pos(')', ADeclaration);
  if (Open = 0) or (Close < Open) then
    Exit;
  for Group in Copy(ADeclaration, Open + 1, Close - Open - 1).Split([';']) do
  begin
    Names := Group;
    if Pos(':', Names) > 0 then
      Names := Copy(Names, 1, Pos(':', Names) - 1);
    Count := Length(Names.Split([',']));
    Inc(AMax, Count);
    if Pos('=', Group) = 0 then
      Inc(AMin, Count);
  end;
end;

function Build: TArray<TSystemIntrinsic>;
var
  Index: Integer;
  Parts: TArray<string>;
begin
  SetLength(Result, Length(Entries));
  for Index := 0 to High(Entries) do
  begin
    Parts := Entries[Index].Split(['|']);
    Result[Index].Name := Parts[0];
    if Parts[1] = 'T' then
      Result[Index].Kind := TIndexSymbolKind.RecordType
    else if Parts[1] = 'C' then
      Result[Index].Kind := TIndexSymbolKind.Constant
    else
      Result[Index].Kind := TIndexSymbolKind.Routine;
    Result[Index].Declaration := Parts[2];
    Result[Index].Documentation := Parts[3];
    Result[Index].MinArgs := 0;
    Result[Index].MaxArgs := 0;
    if Result[Index].Kind = TIndexSymbolKind.Routine then
      CountArgs(Parts[2], Result[Index].MinArgs, Result[Index].MaxArgs);
  end;
end;

{ TSystemIntrinsics }

class function TSystemIntrinsics.All: TArray<TSystemIntrinsic>;
begin
  Result := GEntries;
end;

class function TSystemIntrinsics.Find(const AName: string): TArray<TSystemIntrinsic>;
var
  Entry: TSystemIntrinsic;
begin
  Result := nil;
  for Entry in GEntries do
    if SameText(Entry.Name, AName) then
      Result := Result + [Entry];
end;

class function TSystemIntrinsics.IsKnown(const AName: string): Boolean;
begin
  Result := Length(Find(AName)) > 0;
end;

class function TSystemIntrinsics.IsType(const AName: string): Boolean;
var
  mEntry: TSystemIntrinsic;
begin
  for mEntry in GEntries do
    if (mEntry.Kind = TIndexSymbolKind.RecordType) and SameText(mEntry.Name, AName) then
      Exit(True);
  Result := False;
end;

class function TSystemIntrinsics.NameAt(ATree: TSyntaxTree; const APosition: TTextPosition;
  out AName: string): Boolean;
var
  Tokens: TArray<TPascalToken>;
  Index, Previous: Integer;
begin
  AName := '';
  Result := False;
  if ATree = nil then
    Exit;
  Tokens := ATree.Tokens;
  for Index := 0 to High(Tokens) do
  begin
    if (Tokens[Index].StartPos.Line <> APosition.Line) or (Tokens[Index].StartPos.Character > APosition.Character) or
      (Tokens[Index].EndPos.Line <> APosition.Line) or (Tokens[Index].EndPos.Character < APosition.Character) then
      Continue;
    if (Tokens[Index].Kind <> TPascalTokenKind.Identifier) or Tokens[Index].Text.StartsWith('&') then
      Continue;
    Previous := Index - 1;
    while (Previous >= 0) and (Tokens[Previous].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
      Dec(Previous);
    if (Previous >= 0) and Tokens[Previous].IsSymbol('.') then
      Exit;
    if IsKnown(Tokens[Index].Text) then
    begin
      AName := Tokens[Index].Text;
      Exit(True);
    end;
  end;
end;

initialization
  // Einmal beim Laden aufbauen: Anfragen lesen die Liste danach nur noch, auch aus Worker-Threads.
  GEntries := Build;

finalization
  GEntries := nil;

end.
