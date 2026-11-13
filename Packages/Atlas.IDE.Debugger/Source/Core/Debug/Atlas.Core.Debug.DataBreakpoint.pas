unit Atlas.Core.Debug.DataBreakpoint;

// Anhalten, wenn sich ein Feld ändert (#584), Kern ohne IDE:
// - Ausdruck unter dem Cursor („FKunde.FSumme“) und die Ausdrücke, mit denen
//   der Debugger Adresse („Pointer(@FKunde.FSumme)“) und Größe
//   („SizeOf(FKunde.FSumme)“) liefert.
// - Grenzen der Hardware (Intel/AMD, Debugregister DR0–DR3): vier Plätze je
//   Thread; ein Platz überwacht 1, 2 oder 4 Byte, im 64-Bit-Modus auch 8, und
//   die Adresse muss durch die Länge teilbar sein. Win32-Programme laufen auch
//   unter 64-Bit-Windows im Kompatibilitätsmodus, dort gelten 4 Byte.
// - Plan: die größte erlaubte Länge ab der Adresse des Felds. Ist das Feld
//   größer (Record, ShortString, Int64 unter Win32) oder schief ausgerichtet,
//   überwacht der Platz nur den ersten Teil (Partial). Strings sind Zeiger:
//   Der Platz meldet eine neue Zuweisung, nicht das Ändern einzelner Zeichen.
// - Alter und neuer Wert: Aus dem Text, den der Debugger beim Setzen zeigte,
//   und den Bytes des Speichers folgt, wie die Bytes zu lesen sind (mit oder
//   ohne Vorzeichen, Boolean, String über einen eigenen Ausdruck, sonst Hex).

interface

uses
  System.SysUtils;

type
  {$SCOPEDENUMS ON}
  /// <summary>Wie die überwachten Bytes als Wert zu lesen sind.</summary>
  TAtlasDataValueKind = (Signed, Unsigned, Boolean, Text, Raw);
  {$SCOPEDENUMS OFF}

  /// <summary>Was ein Hardware-Platz für ein Feld überwacht. Length 0: nichts möglich.</summary>
  TAtlasDataWatchPlan = record
    Address: UInt64;
    Length: Integer;
    /// <summary>Größe des ganzen Felds.</summary>
    Size: Integer;
    /// <summary>Nur der erste Teil des Felds (Length kleiner als Size).</summary>
    Partial: Boolean;
  end;

  TAtlasDataBreakpoint = class
  public const
    /// <summary>Debugregister DR0–DR3: Plätze für Datenhaltepunkte je Thread.</summary>
    cSlots = 4;
    /// <summary>Längste Überwachung eines Platzes im 32-Bit-Programm bzw. im 64-Bit-Modus.</summary>
    cMaxLength32 = 4;
    cMaxLength64 = 8;
    /// <summary>Ausdruck für die Zeigergröße des laufenden Programms (4 = Win32, 8 = Win64).</summary>
    cPointerSizeExpression = 'SizeOf(Pointer)';
  public
    /// <summary>Feld oder Variable unter dem Cursor („FKunde.FSumme“, „P^.X“); ACharacter 0-basiert. '' ohne
    /// Bezeichner, bei Schlüsselwörtern und Zahlen.</summary>
    class function ExpressionAt(const ALine: string; ACharacter: Integer): string; static;
    /// <summary>Ausdruck für die Adresse von AExpression.</summary>
    class function AddressExpression(const AExpression: string): string; static;
    /// <summary>Ausdruck für die Größe von AExpression in Byte.</summary>
    class function SizeExpression(const AExpression: string): string; static;
    /// <summary>Ausdruck, der einen String an AAddress liest (neuer Wert nach einer Zuweisung).</summary>
    class function TextExpression(AAddress: UInt64): string; static;
    /// <summary>Positive ganze Zahl aus dem Ergebnis des Debuggers („4“, „$10“); False sonst.</summary>
    class function TryParseSize(const AValue: string; out ASize: Integer): Boolean; static;
    /// <summary>Längste Überwachung für ein Programm mit APointerSize (4 oder 8); 4 bei unbekannter Größe.
    /// </summary>
    class function MaxLength(APointerSize: Integer): Integer; static;
    /// <summary>Plan für ein Feld der Größe ASize an AAddress.</summary>
    class function Plan(AAddress: UInt64; ASize, AMaxLength: Integer): TAtlasDataWatchPlan; static;
    /// <summary>Ist der Wert ein String (Literal ab „'“ oder „#“)? Dann überwacht der Platz den Zeiger.</summary>
    class function IsTextValue(const AValue: string): Boolean; static;
    /// <summary>Freie Plätze, wenn AUsed Datenhaltepunkte aktiv sind; nie unter 0.</summary>
    class function FreeSlots(AUsed: Integer): Integer; static;
    /// <summary>Bytes als ganze Zahl (Little Endian, höchstens 8 Byte); False bei leer oder länger.</summary>
    class function TryReadInteger(const ABytes: TBytes; ASigned: Boolean; out AValue: Int64): Boolean; static;
    /// <summary>„$2A 00 00 00“: die Bytes in Speicherreihenfolge.</summary>
    class function HexText(const ABytes: TBytes): string; static;
    /// <summary>Wie die Bytes zu lesen sind: AValue ist der Text des Debuggers zu denselben ABytes.</summary>
    class function KindOf(const AValue: string; const ABytes: TBytes; APartial: Boolean): TAtlasDataValueKind;
      static;
    /// <summary>Wert der Bytes für die Anzeige nach AKind; für Text '' (der Aufrufer wertet TextExpression aus).
    /// </summary>
    class function ValueText(AKind: TAtlasDataValueKind; const ABytes: TBytes): string; static;
    /// <summary>Unterscheiden sich die Bytes?</summary>
    class function Changed(const AOld, ANew: TBytes): Boolean; static;
  end;

implementation

uses
  Atlas.Core.Debug.Evaluate,
  Atlas.Core.Debug.InstanceBreakpoint;

const
  cBitsPerByte = 8;
  cMaxIntegerBytes = 8;
  cByteMask = $FF;
  cHexByteDigits = 2;
  cWidePointerSize = 8;
  // Wörter, die unter dem Cursor kein Feld sind.
  cKeywords: array[0..27] of string = ('and', 'array', 'begin', 'case', 'div', 'do', 'downto', 'else', 'end',
    'except', 'False', 'finally', 'for', 'if', 'in', 'inherited', 'mod', 'nil', 'not', 'of', 'or', 'repeat', 'then',
    'to', 'True', 'try', 'until', 'while');

function IsKeyword(const AWord: string): Boolean;
var
  mKeyword: string;
begin
  Result := False;
  for mKeyword in cKeywords do
  begin
    if SameText(mKeyword, AWord) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Signed oder Unsigned, wenn AValue die ganze Zahl ist, die in ABytes steht; sonst Raw.</summary>
function IntegerKind(const AValue: string; const ABytes: TBytes): TAtlasDataValueKind;
var
  mNumber, mRead: Int64;
begin
  Result := TAtlasDataValueKind.Raw;
  if not TryStrToInt64(AValue, mNumber) then
  begin
    Exit;
  end;
  if TAtlasDataBreakpoint.TryReadInteger(ABytes, True, mRead) and (mRead = mNumber) then
  begin
    Result := TAtlasDataValueKind.Signed;
  end
  else if TAtlasDataBreakpoint.TryReadInteger(ABytes, False, mRead) and (mRead = mNumber) then
  begin
    Result := TAtlasDataValueKind.Unsigned;
  end;
end;

/// <summary>Die Bytes als ganze Zahl; Hex, wenn sie keine sind.</summary>
function NumberText(const ABytes: TBytes; ASigned: Boolean): string;
var
  mNumber: Int64;
begin
  if not TAtlasDataBreakpoint.TryReadInteger(ABytes, ASigned, mNumber) then
  begin
    Result := TAtlasDataBreakpoint.HexText(ABytes);
  end
  else if ASigned then
  begin
    Result := IntToStr(mNumber);
  end
  else
  begin
    Result := UIntToStr(UInt64(mNumber));
  end;
end;

class function TAtlasDataBreakpoint.ExpressionAt(const ALine: string; ACharacter: Integer): string;
var
  mLastPart: string;
  mDot: Integer;
begin
  Result := TAtlasEvalText.ExpressionAt(ALine, ACharacter);
  mLastPart := Result;
  mDot := LastDelimiter('.^', mLastPart);
  if mDot > 0 then
  begin
    mLastPart := Copy(mLastPart, mDot + 1, MaxInt);
  end;
  if (Result = '') or (mLastPart = '') or IsKeyword(Result) or IsKeyword(mLastPart) then
  begin
    Result := '';
  end;
end;

class function TAtlasDataBreakpoint.AddressExpression(const AExpression: string): string;
begin
  Result := 'Pointer(@' + Trim(AExpression) + ')';
end;

class function TAtlasDataBreakpoint.SizeExpression(const AExpression: string): string;
begin
  Result := 'SizeOf(' + Trim(AExpression) + ')';
end;

class function TAtlasDataBreakpoint.TextExpression(AAddress: UInt64): string;
begin
  Result := 'PString(' + TAtlasInstanceBreakpoint.AddressText(AAddress) + ')^';
end;

class function TAtlasDataBreakpoint.TryParseSize(const AValue: string; out ASize: Integer): Boolean;
begin
  Result := TryStrToInt(Trim(AValue), ASize) and (ASize > 0);
  if not Result then
  begin
    ASize := 0;
  end;
end;

class function TAtlasDataBreakpoint.MaxLength(APointerSize: Integer): Integer;
begin
  if APointerSize = cWidePointerSize then
  begin
    Result := cMaxLength64;
  end
  else
  begin
    Result := cMaxLength32;
  end;
end;

class function TAtlasDataBreakpoint.Plan(AAddress: UInt64; ASize, AMaxLength: Integer): TAtlasDataWatchPlan;
var
  mLength: Integer;
begin
  Result := Default(TAtlasDataWatchPlan);
  Result.Address := AAddress;
  Result.Size := ASize;
  if (AAddress = 0) or (ASize <= 0) or (AMaxLength <= 0) then
  begin
    Exit;
  end;
  // Größte Zweierpotenz bis zur Grenze, die ins Feld passt und an der Adresse ausgerichtet ist.
  mLength := AMaxLength;
  while (mLength > 1) and ((mLength > ASize) or (AAddress mod UInt64(mLength) <> 0)) do
  begin
    mLength := mLength div 2;
  end;
  Result.Length := mLength;
  Result.Partial := mLength < ASize;
end;

class function TAtlasDataBreakpoint.IsTextValue(const AValue: string): Boolean;
var
  mValue: string;
begin
  mValue := Trim(AValue);
  Result := (mValue <> '') and CharInSet(mValue[1], ['''', '#']);
end;

class function TAtlasDataBreakpoint.FreeSlots(AUsed: Integer): Integer;
begin
  Result := cSlots - AUsed;
  if Result < 0 then
  begin
    Result := 0;
  end;
end;

class function TAtlasDataBreakpoint.TryReadInteger(const ABytes: TBytes; ASigned: Boolean;
  out AValue: Int64): Boolean;
var
  mIndex: Integer;
  mValue: UInt64;
  mBits: Integer;
begin
  AValue := 0;
  Result := (Length(ABytes) > 0) and (Length(ABytes) <= cMaxIntegerBytes);
  if not Result then
  begin
    Exit;
  end;
  mValue := 0;
  for mIndex := High(ABytes) downto 0 do
  begin
    mValue := (mValue shl cBitsPerByte) or ABytes[mIndex];
  end;
  mBits := Length(ABytes) * cBitsPerByte;
  // Vorzeichen erweitern, wenn das oberste Bit gesetzt ist und weniger als 8 Byte gelesen wurden.
  if ASigned and (mBits < cMaxIntegerBytes * cBitsPerByte) and (mValue and (UInt64(1) shl (mBits - 1)) <> 0) then
  begin
    mValue := mValue or not ((UInt64(1) shl mBits) - 1);
  end;
  // Typumwandlung deutet die Bits nur um (keine Bereichsprüfung).
  AValue := Int64(mValue);
end;

class function TAtlasDataBreakpoint.HexText(const ABytes: TBytes): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(ABytes) do
  begin
    if Result <> '' then
    begin
      Result := Result + ' ';
    end;
    Result := Result + IntToHex(ABytes[mIndex] and cByteMask, cHexByteDigits);
  end;
  if Result <> '' then
  begin
    Result := '$' + Result;
  end;
end;

class function TAtlasDataBreakpoint.KindOf(const AValue: string; const ABytes: TBytes;
  APartial: Boolean): TAtlasDataValueKind;
var
  mValue: string;
begin
  mValue := Trim(AValue);
  if IsTextValue(mValue) then
  begin
    Result := TAtlasDataValueKind.Text;
  end
  else if APartial then
  begin
    Result := TAtlasDataValueKind.Raw;
  end
  else if (Length(ABytes) = 1) and (SameText(mValue, 'True') or SameText(mValue, 'False')) then
  begin
    Result := TAtlasDataValueKind.Boolean;
  end
  else
  begin
    Result := IntegerKind(mValue, ABytes);
  end;
end;

class function TAtlasDataBreakpoint.ValueText(AKind: TAtlasDataValueKind; const ABytes: TBytes): string;
begin
  case AKind of
    TAtlasDataValueKind.Signed:
      Result := NumberText(ABytes, True);
    TAtlasDataValueKind.Unsigned:
      Result := NumberText(ABytes, False);
    TAtlasDataValueKind.Boolean:
      if Length(ABytes) = 1 then
      begin
        Result := BoolToStr(ABytes[0] <> 0, True);
      end
      else
      begin
        Result := HexText(ABytes);
      end;
    TAtlasDataValueKind.Text:
      Result := '';
  else
    Result := HexText(ABytes);
  end;
end;

class function TAtlasDataBreakpoint.Changed(const AOld, ANew: TBytes): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(AOld) <> Length(ANew);
  if Result then
  begin
    Exit;
  end;
  for mIndex := 0 to High(AOld) do
  begin
    if AOld[mIndex] <> ANew[mIndex] then
    begin
      Exit(True);
    end;
  end;
end;

end.
