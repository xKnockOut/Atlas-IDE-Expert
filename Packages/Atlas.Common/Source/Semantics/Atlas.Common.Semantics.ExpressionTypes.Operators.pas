unit Atlas.Common.Semantics.ExpressionTypes.Operators;

// Operatorregeln der Ausdruckstypen (#689): Kategorie, Breite und Vorzeichen eingebauter Typen und das Ergebnis
// zweistelliger und einstelliger Operatoren nach Delphis Regeln (die breitere Ganzzahl, Int64 bei Cardinal mit
// Vorzeichen, Gleitkomma vor Ganzzahl, Currency mit Ganzzahl bleibt Currency, / immer Extended), dazu die Art
// einer impliziten Umwandlung. Den Ausdruck durchläuft Atlas.Common.Semantics.ExpressionTypes.

interface

uses
  Atlas.Common.Semantics.ExpressionTypes.Contract,
  Atlas.Common.Semantics.NameResolver;

type
  /// <summary>Typ eines Teilausdrucks: Name, Kategorie, aufgelöstes Symbol oder Fehler.</summary>
  TExpressionTyped = record
    Name: string;
    Category: TExpressionCategory;
    /// <summary>Breite in Byte bei Ganzzahlen, Rang bei Gleitkomma; 0 sonst.</summary>
    Width: Integer;
    Signed: Boolean;
    /// <summary>Aufgelöster Typ (für Fundort und Grundtyp), Name '' ohne.</summary>
    Symbol: TResolvedSymbol;
    Base: string;
    Error: TExpressionErrorKind;
    ErrorDetail: string;
    function Known: Boolean;
  end;

  /// <summary>Typen der Operanden nach Delphis Regeln: Kategorie, Ergebnis von Operatoren, Umwandlungen.</summary>
  TExpressionOperators = class
  public
    /// <summary>Kategorie, Breite und Vorzeichen eines eingebauten Typnamens.</summary>
    class function CategoryOf(const ATypeName: string; out AWidth: Integer; out ASigned: Boolean):
      TExpressionCategory; static;
    /// <summary>Bekannter Typ AName mit Kategorie, Breite und Vorzeichen.</summary>
    class function Typed(const AName: string): TExpressionTyped; static;
    /// <summary>Kein Typ, sondern der Fehler AKind mit ADetail.</summary>
    class function Failed(AKind: TExpressionErrorKind; const ADetail: string): TExpressionTyped; static;
    /// <summary>Ergebnis eines zweistelligen Operators außer Vergleich und as; ANoted, wenn die Operanden als
    /// Umwandlung vermerkt werden.</summary>
    class function OperationResult(const AOperator: string; const ALeft, ARight: TExpressionTyped;
      ARightIsSet: Boolean; out ANoted: Boolean): TExpressionTyped; static;
    /// <summary>Ergebnis eines einstelligen Operators (@, not, Vorzeichen) mit bekanntem Operanden.</summary>
    class function UnaryResult(const AOperator: string; const AOperand: TExpressionTyped): TExpressionTyped; static;
    /// <summary>Art der Umwandlung von AOperand nach AResult: Zahlen werden erweitert, Variant und Char umgewandelt.
    /// </summary>
    class function ConversionKind(const AOperand, AResult: TExpressionTyped;
      out AKind: TExpressionConversionKind): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

type
  /// <summary>Kategorie, Breite (Rang bei Gleitkomma) und Vorzeichen eines eingebauten Typnamens.</summary>
  TBuiltinCategory = record
    Name: string;
    Category: TExpressionCategory;
    Width: Integer;
    Signed: Boolean;
  end;

const
  cBuiltinCategories: array[0..51] of TBuiltinCategory = (
    (Name: 'ShortInt'; Category: TExpressionCategory.Integer_; Width: 1; Signed: True),
    (Name: 'Int8'; Category: TExpressionCategory.Integer_; Width: 1; Signed: True),
    (Name: 'Byte'; Category: TExpressionCategory.Integer_; Width: 1; Signed: False),
    (Name: 'UInt8'; Category: TExpressionCategory.Integer_; Width: 1; Signed: False),
    (Name: 'SmallInt'; Category: TExpressionCategory.Integer_; Width: 2; Signed: True),
    (Name: 'Int16'; Category: TExpressionCategory.Integer_; Width: 2; Signed: True),
    (Name: 'Word'; Category: TExpressionCategory.Integer_; Width: 2; Signed: False),
    (Name: 'UInt16'; Category: TExpressionCategory.Integer_; Width: 2; Signed: False),
    (Name: 'Integer'; Category: TExpressionCategory.Integer_; Width: 4; Signed: True),
    (Name: 'LongInt'; Category: TExpressionCategory.Integer_; Width: 4; Signed: True),
    (Name: 'Int32'; Category: TExpressionCategory.Integer_; Width: 4; Signed: True),
    (Name: 'FixedInt'; Category: TExpressionCategory.Integer_; Width: 4; Signed: True),
    (Name: 'Cardinal'; Category: TExpressionCategory.Integer_; Width: 4; Signed: False),
    (Name: 'LongWord'; Category: TExpressionCategory.Integer_; Width: 4; Signed: False),
    (Name: 'UInt32'; Category: TExpressionCategory.Integer_; Width: 4; Signed: False),
    (Name: 'FixedUInt'; Category: TExpressionCategory.Integer_; Width: 4; Signed: False),
    (Name: 'DWORD'; Category: TExpressionCategory.Integer_; Width: 4; Signed: False),
    (Name: 'Int64'; Category: TExpressionCategory.Integer_; Width: 8; Signed: True),
    (Name: 'NativeInt'; Category: TExpressionCategory.Integer_; Width: 8; Signed: True),
    (Name: 'IntPtr'; Category: TExpressionCategory.Integer_; Width: 8; Signed: True),
    (Name: 'UInt64'; Category: TExpressionCategory.Integer_; Width: 8; Signed: False),
    (Name: 'NativeUInt'; Category: TExpressionCategory.Integer_; Width: 8; Signed: False),
    (Name: 'UIntPtr'; Category: TExpressionCategory.Integer_; Width: 8; Signed: False),
    (Name: 'Single'; Category: TExpressionCategory.Float; Width: 1; Signed: False),
    (Name: 'Real48'; Category: TExpressionCategory.Float; Width: 2; Signed: False),
    (Name: 'Double'; Category: TExpressionCategory.Float; Width: 3; Signed: False),
    (Name: 'Real'; Category: TExpressionCategory.Float; Width: 3; Signed: False),
    (Name: 'Comp'; Category: TExpressionCategory.Float; Width: 3; Signed: False),
    (Name: 'Extended'; Category: TExpressionCategory.Float; Width: 4; Signed: False),
    (Name: 'Currency'; Category: TExpressionCategory.Currency_; Width: 0; Signed: False),
    (Name: 'Boolean'; Category: TExpressionCategory.Boolean_; Width: 0; Signed: False),
    (Name: 'ByteBool'; Category: TExpressionCategory.Boolean_; Width: 0; Signed: False),
    (Name: 'WordBool'; Category: TExpressionCategory.Boolean_; Width: 0; Signed: False),
    (Name: 'LongBool'; Category: TExpressionCategory.Boolean_; Width: 0; Signed: False),
    (Name: 'Char'; Category: TExpressionCategory.Char_; Width: 0; Signed: False),
    (Name: 'WideChar'; Category: TExpressionCategory.Char_; Width: 0; Signed: False),
    (Name: 'AnsiChar'; Category: TExpressionCategory.Char_; Width: 0; Signed: False),
    (Name: 'string'; Category: TExpressionCategory.String_; Width: 0; Signed: False),
    (Name: 'UnicodeString'; Category: TExpressionCategory.String_; Width: 0; Signed: False),
    (Name: 'AnsiString'; Category: TExpressionCategory.String_; Width: 0; Signed: False),
    (Name: 'WideString'; Category: TExpressionCategory.String_; Width: 0; Signed: False),
    (Name: 'ShortString'; Category: TExpressionCategory.String_; Width: 0; Signed: False),
    (Name: 'RawByteString'; Category: TExpressionCategory.String_; Width: 0; Signed: False),
    (Name: 'UTF8String'; Category: TExpressionCategory.String_; Width: 0; Signed: False),
    (Name: 'Variant'; Category: TExpressionCategory.Variant_; Width: 0; Signed: False),
    (Name: 'OleVariant'; Category: TExpressionCategory.Variant_; Width: 0; Signed: False),
    (Name: 'Pointer'; Category: TExpressionCategory.Pointer_; Width: 0; Signed: False),
    (Name: 'PChar'; Category: TExpressionCategory.Pointer_; Width: 0; Signed: False),
    (Name: 'PWideChar'; Category: TExpressionCategory.Pointer_; Width: 0; Signed: False),
    (Name: 'PAnsiChar'; Category: TExpressionCategory.Pointer_; Width: 0; Signed: False),
    (Name: 'PByte'; Category: TExpressionCategory.Pointer_; Width: 0; Signed: False),
    (Name: 'nil'; Category: TExpressionCategory.Nil_; Width: 0; Signed: False));

function TExpressionTyped.Known: Boolean;
begin
  Result := Name <> '';
end;

class function TExpressionOperators.CategoryOf(const ATypeName: string; out AWidth: Integer;
  out ASigned: Boolean): TExpressionCategory;
var
  mName: string;
  mEntry: TBuiltinCategory;
begin
  AWidth := 0;
  ASigned := False;
  mName := ATypeName;
  if StartsText('System.', mName) then
  begin
    mName := Copy(mName, 8, MaxInt);
  end;
  Result := TExpressionCategory.Other;
  if mName = '' then
  begin
    Result := TExpressionCategory.Unknown;
  end
  else if StartsStr('^', mName) then
  begin
    Result := TExpressionCategory.Pointer_;
  end
  else if StartsText('set of ', mName) then
  begin
    Result := TExpressionCategory.Set_;
  end;
  for mEntry in cBuiltinCategories do
  begin
    if SameText(mEntry.Name, mName) then
    begin
      AWidth := mEntry.Width;
      ASigned := mEntry.Signed;
      Result := mEntry.Category;
      Break;
    end;
  end;
end;

class function TExpressionOperators.Typed(const AName: string): TExpressionTyped;
var
  mWidth: Integer;
  mSigned: Boolean;
begin
  Result := Default(TExpressionTyped);
  Result.Name := AName;
  Result.Category := CategoryOf(AName, mWidth, mSigned);
  Result.Width := mWidth;
  Result.Signed := mSigned;
end;

class function TExpressionOperators.Failed(AKind: TExpressionErrorKind; const ADetail: string): TExpressionTyped;
begin
  Result := Default(TExpressionTyped);
  Result.Error := AKind;
  Result.ErrorDetail := ADetail;
end;

function IsNumeric(const AType: TExpressionTyped): Boolean;
begin
  Result := AType.Category in [TExpressionCategory.Integer_, TExpressionCategory.Float, TExpressionCategory.Currency_];
end;

/// <summary>Mindestens eine Seite hat die Kategorie ACategory.</summary>
function HasCategory(const ALeft, ARight: TExpressionTyped; ACategory: TExpressionCategory): Boolean;
begin
  Result := (ALeft.Category = ACategory) or (ARight.Category = ACategory);
end;

/// <summary>Beide Seiten haben die Kategorie ACategory.</summary>
function BothCategory(const ALeft, ARight: TExpressionTyped; ACategory: TExpressionCategory): Boolean;
begin
  Result := (ALeft.Category = ACategory) and (ARight.Category = ACategory);
end;

/// <summary>Ganzzahl der Breite AWidth ohne Vorzeichen.</summary>
function IsUnsigned(const AType: TExpressionTyped; AWidth: Integer): Boolean;
begin
  Result := (AType.Width = AWidth) and not AType.Signed;
end;

/// <summary>Ergebnis einer ganzzahligen Rechnung (Delphi): mindestens Integer; Int64 bzw. UInt64, wenn eine Seite
/// 64 Bit hat; Cardinal nur, wenn beide Seiten 32 Bit ohne Vorzeichen sind, mit Vorzeichen Int64.</summary>
function IntegerResult(const ALeft, ARight: TExpressionTyped): TExpressionTyped;
begin
  if ((ALeft.Width = 8) or (ARight.Width = 8)) and SameText(ALeft.Name, ARight.Name) then
  begin
    Result := TExpressionOperators.Typed(ALeft.Name);
  end
  else if IsUnsigned(ALeft, 8) or IsUnsigned(ARight, 8) then
  begin
    Result := TExpressionOperators.Typed('UInt64');
  end
  else if (ALeft.Width = 8) or (ARight.Width = 8) then
  begin
    Result := TExpressionOperators.Typed('Int64');
  end
  else if IsUnsigned(ALeft, 4) and IsUnsigned(ARight, 4) then
  begin
    Result := TExpressionOperators.Typed('Cardinal');
  end
  else if IsUnsigned(ALeft, 4) or IsUnsigned(ARight, 4) then
  begin
    Result := TExpressionOperators.Typed('Int64');
  end
  else
  begin
    Result := TExpressionOperators.Typed('Integer');
  end;
end;

/// <summary>Ergebnis von + - * mit mindestens einer Gleitkomma- oder Currency-Seite: Currency mit Ganzzahl bleibt
/// Currency, mit Gleitkomma Extended; sonst die breitere Gleitkommaseite.</summary>
function RealResult(const ALeft, ARight: TExpressionTyped): TExpressionTyped;
begin
  if HasCategory(ALeft, ARight, TExpressionCategory.Currency_) and
    HasCategory(ALeft, ARight, TExpressionCategory.Float) then
  begin
    Result := TExpressionOperators.Typed('Extended');
  end
  else if HasCategory(ALeft, ARight, TExpressionCategory.Currency_) then
  begin
    Result := TExpressionOperators.Typed('Currency');
  end
  else if (ARight.Category = TExpressionCategory.Float) and
    ((ALeft.Category <> TExpressionCategory.Float) or (ARight.Width > ALeft.Width)) then
  begin
    Result := TExpressionOperators.Typed(ARight.Name);
  end
  else
  begin
    Result := TExpressionOperators.Typed(ALeft.Name);
  end;
end;

/// <summary>Operator passt nicht zu den Operanden; Detail "Operator|Links|Rechts".</summary>
function Mismatch(const AOperator: string; const ALeft, ARight: TExpressionTyped): TExpressionTyped;
begin
  Result := TExpressionOperators.Failed(TExpressionErrorKind.OperatorMismatch, AOperator + '|' + ALeft.Name + '|' + ARight.Name);
end;

/// <summary>Zeichen oder string.</summary>
function IsText(const AType: TExpressionTyped): Boolean;
begin
  Result := AType.Category in [TExpressionCategory.String_, TExpressionCategory.Char_];
end;

/// <summary>Verkettung mit +: der string-Typ einer Seite, aus zwei Zeichen ein string.</summary>
function ConcatResult(const ALeft, ARight: TExpressionTyped): TExpressionTyped;
begin
  if ALeft.Category = TExpressionCategory.String_ then
  begin
    Result := TExpressionOperators.Typed(ALeft.Name);
  end
  else if ARight.Category = TExpressionCategory.String_ then
  begin
    Result := TExpressionOperators.Typed(ARight.Name);
  end
  else
  begin
    Result := TExpressionOperators.Typed('string');
  end;
end;

/// <summary>+ - * mit einer Menge: die Mengenseite; rechts genügt ein Mengenkonstruktor.</summary>
function SetResult(const AOperator: string; const ALeft, ARight: TExpressionTyped;
  ARightIsSet: Boolean): TExpressionTyped;
begin
  if (ALeft.Category = TExpressionCategory.Set_) and ((ARight.Category = TExpressionCategory.Set_) or ARightIsSet) then
  begin
    Result := ALeft;
  end
  else if ARight.Category = TExpressionCategory.Set_ then
  begin
    Result := ARight;
  end
  else
  begin
    Result := Mismatch(AOperator, ALeft, ARight);
  end;
end;

/// <summary>+ - * ohne Zahlen und Strings: Mengen, Zeiger ± Zahl, Zeiger - Zeiger.</summary>
function PointerOrSetResult(const AOperator: string; const ALeft, ARight: TExpressionTyped;
  ARightIsSet: Boolean): TExpressionTyped;
begin
  if HasCategory(ALeft, ARight, TExpressionCategory.Set_) then
  begin
    Result := SetResult(AOperator, ALeft, ARight, ARightIsSet);
  end
  else if (ALeft.Category = TExpressionCategory.Pointer_) and (ARight.Category = TExpressionCategory.Integer_) and
    (AOperator <> '*') then
  begin
    Result := ALeft;
  end
  else if BothCategory(ALeft, ARight, TExpressionCategory.Pointer_) and (AOperator = '-') then
  begin
    Result := TExpressionOperators.Typed('NativeInt');
  end
  else
  begin
    Result := Mismatch(AOperator, ALeft, ARight);
  end;
end;

/// <summary>Ergebnis von + - *; ANoted, wenn die Operanden umgewandelt werden können (Zahlen, Strings).</summary>
function AdditiveResult(const AOperator: string; const ALeft, ARight: TExpressionTyped; ARightIsSet: Boolean;
  out ANoted: Boolean): TExpressionTyped;
begin
  ANoted := True;
  if BothCategory(ALeft, ARight, TExpressionCategory.Integer_) then
  begin
    Result := IntegerResult(ALeft, ARight);
  end
  else if IsNumeric(ALeft) and IsNumeric(ARight) then
  begin
    Result := RealResult(ALeft, ARight);
  end
  else if (AOperator = '+') and IsText(ALeft) and IsText(ARight) then
  begin
    Result := ConcatResult(ALeft, ARight);
  end
  else
  begin
    ANoted := False;
    Result := PointerOrSetResult(AOperator, ALeft, ARight, ARightIsSet);
  end;
end;

/// <summary>shl/shr: ein 64-Bit-Operand bleibt, sonst wie Integer.</summary>
function ShiftResult(const ALeft: TExpressionTyped): TExpressionTyped;
begin
  if ALeft.Width = 8 then
  begin
    Result := TExpressionOperators.Typed(ALeft.Name);
  end
  else
  begin
    Result := IntegerResult(ALeft, TExpressionOperators.Typed('Integer'));
  end;
end;

/// <summary>Ergebnis von /, div, mod, ganzzahligem and/or/xor, shl, shr; Error Unknown ohne Detail bei unbekanntem
/// Operator.</summary>
function OtherResult(const AOperator: string; const ALeft, ARight: TExpressionTyped): TExpressionTyped;
begin
  if (AOperator = '/') and IsNumeric(ALeft) and IsNumeric(ARight) then
  begin
    Result := TExpressionOperators.Typed('Extended');
  end
  else if AOperator = '/' then
  begin
    Result := Mismatch(AOperator, ALeft, ARight);
  end
  else if not MatchStr(AOperator, ['div', 'mod', 'and', 'or', 'xor', 'shl', 'shr']) then
  begin
    Result := TExpressionOperators.Failed(TExpressionErrorKind.Unknown, '');
  end
  else if not BothCategory(ALeft, ARight, TExpressionCategory.Integer_) then
  begin
    Result := Mismatch(AOperator, ALeft, ARight);
  end
  else if MatchStr(AOperator, ['shl', 'shr']) then
  begin
    Result := ShiftResult(ALeft);
  end
  else
  begin
    Result := IntegerResult(ALeft, ARight);
  end;
end;

/// <summary>Ergebnis eines zweistelligen Operators außer Vergleich und as; ANoted, wenn die Operanden als
/// Umwandlung vermerkt werden.</summary>
class function TExpressionOperators.OperationResult(const AOperator: string; const ALeft, ARight: TExpressionTyped;
  ARightIsSet: Boolean; out ANoted: Boolean): TExpressionTyped;
begin
  ANoted := False;
  if HasCategory(ALeft, ARight, TExpressionCategory.Variant_) then
  begin
    Result := TExpressionOperators.Typed('Variant');
  end
  else if MatchStr(AOperator, ['+', '-', '*']) then
  begin
    Result := AdditiveResult(AOperator, ALeft, ARight, ARightIsSet, ANoted);
  end
  else if MatchStr(AOperator, ['and', 'or', 'xor']) and BothCategory(ALeft, ARight, TExpressionCategory.Boolean_) then
  begin
    Result := TExpressionOperators.Typed('Boolean');
  end
  else
  begin
    Result := OtherResult(AOperator, ALeft, ARight);
    ANoted := Result.Known;
  end;
end;

/// <summary>not: Boolean, Ganzzahl und Variant bleiben.</summary>
function NotResult(const AOperand: TExpressionTyped): TExpressionTyped;
begin
  if AOperand.Category in [TExpressionCategory.Boolean_, TExpressionCategory.Integer_,
    TExpressionCategory.Variant_] then
  begin
    Result := AOperand;
  end
  else
  begin
    Result := TExpressionOperators.Failed(TExpressionErrorKind.OperatorMismatch, 'not||' + AOperand.Name);
  end;
end;

/// <summary>Ergebnis eines einstelligen Operators (@, not, Vorzeichen) mit bekanntem Operanden.</summary>
class function TExpressionOperators.UnaryResult(const AOperator: string;
  const AOperand: TExpressionTyped): TExpressionTyped;
begin
  if AOperator = '@' then
  begin
    Result := TExpressionOperators.Typed('Pointer');
  end
  else if SameText(AOperator, 'not') then
  begin
    Result := NotResult(AOperand);
  end
  else if not (IsNumeric(AOperand) or (AOperand.Category = TExpressionCategory.Variant_)) then
  begin
    Result := TExpressionOperators.Failed(TExpressionErrorKind.OperatorMismatch, AOperator + '||' + AOperand.Name);
  end
  else if (AOperand.Category = TExpressionCategory.Integer_) and (AOperand.Width < 4) then
  begin
    // -Byte rechnet als Integer.
    Result := TExpressionOperators.Typed('Integer');
  end
  else
  begin
    Result := AOperand;
  end;
end;

/// <summary>Art der Umwandlung von AOperand nach AResult: Zahlen werden erweitert, Variant und Char umgewandelt.
/// </summary>
class function TExpressionOperators.ConversionKind(const AOperand, AResult: TExpressionTyped;
  out AKind: TExpressionConversionKind): Boolean;
begin
  Result := True;
  AKind := TExpressionConversionKind.Widen;
  if IsNumeric(AOperand) and IsNumeric(AResult) then
  begin
    AKind := TExpressionConversionKind.Widen;
  end
  else if (AOperand.Category in [TExpressionCategory.Variant_, TExpressionCategory.Char_]) and
    (AResult.Category in [TExpressionCategory.String_, TExpressionCategory.Integer_, TExpressionCategory.Float,
    TExpressionCategory.Currency_, TExpressionCategory.Boolean_]) then
  begin
    AKind := TExpressionConversionKind.Convert;
  end
  else
  begin
    Result := False;
  end;
end;

end.
