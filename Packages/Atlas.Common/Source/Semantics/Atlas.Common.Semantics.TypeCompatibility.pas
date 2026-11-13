unit Atlas.Common.Semantics.TypeCompatibility;

// Verträglichkeit zweier sicher bekannter Typen (#1369), gemeinsam für die
// Regeln der Stufe T, die inkompatible Typen melden: Zuweisung (Ziel und
// Quelle), Operatoren mit beiden Operanden und var-Parameter. Entschieden wird
// nur über die grobe Art des Typs (TExpressionCategory) bzw. die Art der
// Deklaration (Klasse, Aufzählung, statisches Array); alles, was davon
// abhängt, wie Delphi den Typ genau deklariert (Records mit class operator,
// Teilbereiche, Mengen benannter Typen, Zeiger), bleibt offen. Atlas meldet
// nie etwas, was dcc übersetzt (#1328): offen heißt still.
//   - AssignIncompatible: Ziel := Quelle ist sicher ein Fehler (wie E2010),
//     etwa Integer := string, Boolean := Integer, TObject := 0,
//     array[0..2] of Integer := nil.
//   - OperatorFit: Operator für beide Seiten nicht definiert (wie E2015:
//     string - Char, Double div Integer) bzw. definiert, aber nicht
//     verträglich (wie E2010: string + Integer).
//   - VarParamDiffers: Typ eines var-Arguments ist ein anderer als der des
//     Parameters (wie E2033); Typen, die je Plattform anders sind (NativeInt,
//     Extended …), bleiben offen.

interface

uses
  Atlas.Common.Semantics.ExpressionTypes,
  Atlas.Common.Semantics.ExpressionTypes.Contract;

type
{$SCOPEDENUMS ON}
  /// <summary>Art der Deklaration eines Typs, soweit sie für die Verträglichkeit zählt. Builtin heißt: Die Kategorie
  /// (TExpressionCategory) entscheidet; Other: unbekannt bzw. nicht entscheidbar (Record, Teilbereich, Zeiger …).
  /// </summary>
  TValueKind = (Unknown, Builtin, ClassLike, Enum, StaticArray, Other);
  /// <summary>Ergebnis von TTypeCompatibility.OperatorFit.</summary>
  TOperatorFit = (Fits, NotApplicable, Incompatible, Unknown);
{$SCOPEDENUMS OFF}

  /// <summary>Ein sicher bekannter Typ eines Ausdrucks oder einer Deklaration.</summary>
  TValueType = record
    /// <summary>Name wie in der Meldung (Integer, string, TObject, array[0..2] of Integer).</summary>
    Name: string;
    Category: TExpressionCategory;
    Kind: TValueKind;
    /// <summary>Untypisierte String-Konstante: mit einem Zeichen auch als Char verträglich.</summary>
    UntypedText: Boolean;
    function Known: Boolean;
    /// <summary>Typ aus einem eingebauten Namen (Kategorie über TExpressionTypes.CategoryOf).</summary>
    class function FromBuiltin(const AName: string): TValueType; static;
    class function Create(const AName: string; ACategory: TExpressionCategory; AKind: TValueKind): TValueType; static;
  end;

  TTypeCompatibility = record
  public
    /// <summary>Ist "ATarget := ASource" sicher unverträglich (wie E2010)? False, wenn es offen ist.</summary>
    class function AssignIncompatible(const ATarget, ASource: TValueType): Boolean; static;
    /// <summary>Passt der binäre Operator AOperator (klein geschrieben) zu beiden Seiten? Vergleiche, in, is und as
    /// bleiben Unknown.</summary>
    class function OperatorFit(const AOperator: string; const ALeft, ARight: TValueType): TOperatorFit; static;
    /// <summary>Ist der einstellige Operator AOperator (not, -, +) auf AOperand sicher nicht anwendbar (wie
    /// E2015)?</summary>
    class function UnaryNotApplicable(const AOperator: string; const AOperand: TValueType): Boolean; static;
    /// <summary>Ist der Typ AActual eines var- bzw. out-Arguments sicher ein anderer als der Typ AFormal des
    /// Parameters (wie E2033)? Beide eingebaut; je Plattform verschiedene Typen bleiben offen.</summary>
    class function VarParamDiffers(const AFormal, AActual: TValueType): Boolean; static;
    /// <summary>Hängt der eingebaute Typ von der Plattform ab (NativeInt, Extended, LongInt …)?</summary>
    class function PlatformDependent(const AName: string): Boolean; static;
    /// <summary>Langer String (verwaltet, zeigergroß): string, AnsiString, WideString …, nicht ShortString.
    /// </summary>
    class function IsLongString(const AName: string): Boolean; static;
    /// <summary>Elementtyp aus "set of X"; '' ohne.</summary>
    class function SetElement(const ASetName: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Semantics.TypeIdentity;

const
  // Je Plattform verschieden groß bzw. unter Windows und Linux verschieden deklariert.
  cPlatformTypes: array[0..9] of string = ('NativeInt', 'NativeUInt', 'IntPtr', 'UIntPtr', 'LongInt', 'LongWord',
    'Extended', 'Comp', 'Real48', 'THandle');
  cLongStrings: array[0..6] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString',
    'UTF8String', 'System.string');

/// <summary>Kategorien, für die ein Operator definiert ist. Zeiger, nil, Variant und Mengen fehlen bewusst
/// (Zeigerarithmetik mit {$POINTERMATH}, Mengen in eigener Prüfung).</summary>
function OperatorDefined(const AOperator: string; ACategory: TExpressionCategory): Boolean;
begin
  case ACategory of
    TExpressionCategory.Integer_:
      Result := MatchStr(AOperator, ['+', '-', '*', '/', 'div', 'mod', 'and', 'or', 'xor', 'shl', 'shr']);
    TExpressionCategory.Float, TExpressionCategory.Currency_:
      Result := MatchStr(AOperator, ['+', '-', '*', '/']);
    TExpressionCategory.Boolean_:
      Result := MatchStr(AOperator, ['and', 'or', 'xor']);
    TExpressionCategory.Char_, TExpressionCategory.String_:
      Result := AOperator = '+';
    TExpressionCategory.Set_:
      Result := MatchStr(AOperator, ['+', '-', '*']);
  else
    Result := True;
  end;
end;

function IsNumeric(ACategory: TExpressionCategory): Boolean;
begin
  Result := ACategory in [TExpressionCategory.Integer_, TExpressionCategory.Float, TExpressionCategory.Currency_];
end;

function IsText(ACategory: TExpressionCategory): Boolean;
begin
  Result := ACategory in [TExpressionCategory.Char_, TExpressionCategory.String_];
end;

/// <summary>Eingebauter Typ, über dessen Kategorie entschieden wird.</summary>
function IsDecided(const AType: TValueType): Boolean;
begin
  Result := (AType.Kind = TValueKind.Builtin) and (AType.Category in [TExpressionCategory.Integer_,
    TExpressionCategory.Float, TExpressionCategory.Currency_, TExpressionCategory.Boolean_, TExpressionCategory.Char_,
    TExpressionCategory.String_, TExpressionCategory.Set_, TExpressionCategory.Pointer_, TExpressionCategory.Nil_]);
end;

function FromBuiltinKind(const AName: string): TValueKind;
begin
  Result := TValueType.FromBuiltin(AName).Kind;
end;

{ TValueType }

function TValueType.Known: Boolean;
begin
  Result := (Kind <> TValueKind.Unknown) and (Name <> '');
end;

class function TValueType.FromBuiltin(const AName: string): TValueType;
var
  mWidth: Integer;
  mSigned: Boolean;
begin
  Result := Default(TValueType);
  Result.Name := AName;
  Result.Category := TExpressionTypes.CategoryOf(AName, mWidth, mSigned);
  Result.Kind := TValueKind.Builtin;
  if Result.Category in [TExpressionCategory.Unknown, TExpressionCategory.Other] then
  begin
    Result.Kind := TValueKind.Other;
  end;
end;

class function TValueType.Create(const AName: string; ACategory: TExpressionCategory; AKind: TValueKind): TValueType;
begin
  Result := Default(TValueType);
  Result.Name := AName;
  Result.Category := ACategory;
  Result.Kind := AKind;
end;

{ TTypeCompatibility }

/// <summary>Zuweisung an einen eingebauten Typ der Art ATarget aus ASource (Other, wenn offen) unverträglich?
/// ASourceObject: Klasse, Interface oder Aufzählung.</summary>
function BuiltinIncompatible(ATarget, ASource: TExpressionCategory; ASourceObject, AUntypedText: Boolean): Boolean;
begin
  Result := False;
  if ASourceObject then
  begin
    Exit(ATarget in [TExpressionCategory.Integer_, TExpressionCategory.Float, TExpressionCategory.Currency_,
      TExpressionCategory.Boolean_, TExpressionCategory.Char_, TExpressionCategory.String_]);
  end;
  case ATarget of
    TExpressionCategory.Integer_:
      Result := ASource in [TExpressionCategory.Float, TExpressionCategory.Currency_, TExpressionCategory.Boolean_,
        TExpressionCategory.Char_, TExpressionCategory.String_, TExpressionCategory.Nil_, TExpressionCategory.Pointer_];
    TExpressionCategory.Float, TExpressionCategory.Currency_:
      Result := ASource in [TExpressionCategory.Boolean_, TExpressionCategory.Char_, TExpressionCategory.String_,
        TExpressionCategory.Nil_, TExpressionCategory.Pointer_];
    TExpressionCategory.Boolean_:
      Result := ASource in [TExpressionCategory.Integer_, TExpressionCategory.Float, TExpressionCategory.Currency_,
        TExpressionCategory.Char_, TExpressionCategory.String_, TExpressionCategory.Nil_, TExpressionCategory.Pointer_];
    TExpressionCategory.Char_:
      // Eine untypisierte Konstante 'a' ist auch ein Zeichen.
      Result := (ASource in [TExpressionCategory.Integer_, TExpressionCategory.Float, TExpressionCategory.Currency_,
        TExpressionCategory.Boolean_, TExpressionCategory.Nil_, TExpressionCategory.Pointer_]) or
        ((ASource = TExpressionCategory.String_) and not AUntypedText);
    TExpressionCategory.String_:
      // PChar und nil gehen in einen String; Mengen bleiben offen.
      Result := ASource in [TExpressionCategory.Integer_, TExpressionCategory.Float, TExpressionCategory.Currency_,
        TExpressionCategory.Boolean_];
  else
    // Zeiger, Variant, Mengen: offen.
  end;
end;

class function TTypeCompatibility.AssignIncompatible(const ATarget, ASource: TValueType): Boolean;
var
  mSource: TExpressionCategory;
  mSourceDecided, mSourceObject: Boolean;
begin
  Result := False;
  if not ATarget.Known or not ASource.Known then
  begin
    Exit;
  end;
  mSourceDecided := IsDecided(ASource);
  // Klassen, Interfaces und Aufzählungen haben keine Umwandlung in eingebaute Typen (Records schon: Implicit).
  mSourceObject := ASource.Kind in [TValueKind.ClassLike, TValueKind.Enum];
  if not mSourceDecided and not mSourceObject then
  begin
    Exit;
  end;
  mSource := ASource.Category;
  if not mSourceDecided then
  begin
    mSource := TExpressionCategory.Other;
  end;
  case ATarget.Kind of
    TValueKind.Builtin:
      Result := BuiltinIncompatible(ATarget.Category, mSource, mSourceObject, ASource.UntypedText);
    TValueKind.ClassLike:
      Result := (mSource in [TExpressionCategory.Integer_, TExpressionCategory.Float, TExpressionCategory.Currency_,
        TExpressionCategory.Boolean_, TExpressionCategory.Char_, TExpressionCategory.String_]) or
        (ASource.Kind = TValueKind.Enum);
    TValueKind.Enum:
      Result := (mSource in [TExpressionCategory.Integer_, TExpressionCategory.Float, TExpressionCategory.Currency_,
        TExpressionCategory.Boolean_, TExpressionCategory.Char_, TExpressionCategory.String_,
        TExpressionCategory.Nil_, TExpressionCategory.Pointer_]) or (ASource.Kind = TValueKind.ClassLike);
    TValueKind.StaticArray:
      // array[0..2] of Char := 'abc' übersetzt dcc; Zeichen und Strings bleiben offen.
      Result := mSource in [TExpressionCategory.Integer_, TExpressionCategory.Float, TExpressionCategory.Currency_,
        TExpressionCategory.Boolean_, TExpressionCategory.Nil_];
  else
    // Records, Teilbereiche, Unbekanntes: offen.
  end;
end;

/// <summary>Zwei Mengen: [1] + ['a'] aus Zahlen und aus Zeichen ist unverträglich (wie E2010).</summary>
function SetFit(const ALeft, ARight: TValueType): TOperatorFit;
const
  cOrdinal = [TExpressionCategory.Integer_, TExpressionCategory.Char_, TExpressionCategory.Boolean_];
var
  mLeft, mRight: TValueType;
begin
  Result := TOperatorFit.Fits;
  mLeft := TValueType.FromBuiltin(TTypeCompatibility.SetElement(ALeft.Name));
  mRight := TValueType.FromBuiltin(TTypeCompatibility.SetElement(ARight.Name));
  if IsDecided(mLeft) and IsDecided(mRight) and (mLeft.Category in cOrdinal) and
    (mRight.Category in cOrdinal) and (mLeft.Category <> mRight.Category) then
  begin
    Result := TOperatorFit.Incompatible;
  end;
end;

/// <summary>string + Integer: + ist für beide definiert, aber nicht zusammen (wie E2010). Char + Integer bleibt
/// offen.</summary>
function StringPlusNumber(const AOperator: string; ALeft, ARight: TExpressionCategory): Boolean;
begin
  Result := (AOperator = '+') and (((ALeft = TExpressionCategory.String_) and IsNumeric(ARight)) or
    (IsNumeric(ALeft) and (ARight = TExpressionCategory.String_)));
end;

/// <summary>Beide Seiten haben die Kategorie ACategory.</summary>
function BothOf(ALeft, ARight, ACategory: TExpressionCategory): Boolean;
begin
  Result := (ALeft = ACategory) and (ARight = ACategory);
end;

/// <summary>AOperator ist für beide Seiten definiert: passen sie zusammen?</summary>
function DefinedFit(const AOperator: string; const ALeft, ARight: TValueType): TOperatorFit;
var
  mLeft, mRight: TExpressionCategory;
begin
  mLeft := ALeft.Category;
  mRight := ARight.Category;
  // div, mod, and … nur mit Ganzzahlen; die Gleitkommaseite ist vorher schon ausgeschieden.
  if (IsNumeric(mLeft) and IsNumeric(mRight)) or BothOf(mLeft, mRight, TExpressionCategory.Boolean_) or
    (IsText(mLeft) and IsText(mRight)) then
  begin
    Result := TOperatorFit.Fits;
  end
  else if StringPlusNumber(AOperator, mLeft, mRight) then
  begin
    Result := TOperatorFit.Incompatible;
  end
  else if BothOf(mLeft, mRight, TExpressionCategory.Set_) then
  begin
    Result := SetFit(ALeft, ARight);
  end
  else
  begin
    // Übrige Mischungen (Integer and Boolean, Menge + Zahl): offen.
    Result := TOperatorFit.Unknown;
  end;
end;

class function TTypeCompatibility.OperatorFit(const AOperator: string; const ALeft, ARight: TValueType): TOperatorFit;
begin
  Result := TOperatorFit.Unknown;
  if not IsDecided(ALeft) or not IsDecided(ARight) or
    not MatchStr(AOperator, ['+', '-', '*', '/', 'div', 'mod', 'and', 'or', 'xor', 'shl', 'shr']) then
  begin
    Exit;
  end;
  // Zeiger und nil: Zeigerarithmetik hängt an {$POINTERMATH}.
  if (ALeft.Category in [TExpressionCategory.Pointer_, TExpressionCategory.Nil_]) or
    (ARight.Category in [TExpressionCategory.Pointer_, TExpressionCategory.Nil_]) then
  begin
    Exit;
  end;
  if not OperatorDefined(AOperator, ALeft.Category) or not OperatorDefined(AOperator, ARight.Category) then
  begin
    Result := TOperatorFit.NotApplicable;
  end
  else
  begin
    Result := DefinedFit(AOperator, ALeft, ARight);
  end;
end;

class function TTypeCompatibility.UnaryNotApplicable(const AOperator: string; const AOperand: TValueType): Boolean;
begin
  Result := False;
  if not IsDecided(AOperand) then
  begin
    Exit;
  end;
  if SameText(AOperator, 'not') then
  begin
    Result := AOperand.Category in [TExpressionCategory.Float, TExpressionCategory.Currency_,
      TExpressionCategory.Char_, TExpressionCategory.String_, TExpressionCategory.Set_];
  end
  else if (AOperator = '-') or (AOperator = '+') then
  begin
    Result := AOperand.Category in [TExpressionCategory.Boolean_, TExpressionCategory.Char_,
      TExpressionCategory.String_, TExpressionCategory.Set_];
  end;
end;

class function TTypeCompatibility.VarParamDiffers(const AFormal, AActual: TValueType): Boolean;
begin
  Result := False;
  if not IsDecided(AFormal) or not IsDecided(AActual) then
  begin
    Exit;
  end;
  if not (AFormal.Category in [TExpressionCategory.Integer_, TExpressionCategory.Float, TExpressionCategory.Currency_,
    TExpressionCategory.Boolean_, TExpressionCategory.Char_, TExpressionCategory.String_]) or
    not (AActual.Category in [TExpressionCategory.Integer_, TExpressionCategory.Float, TExpressionCategory.Currency_,
    TExpressionCategory.Boolean_, TExpressionCategory.Char_, TExpressionCategory.String_]) then
  begin
    Exit;
  end;
  // Nur eingebaute Namen: Ein Alias TFloat = Single ist derselbe Typ wie Single, TZahl = type Integer ein anderer.
  if PlatformDependent(AFormal.Name) or PlatformDependent(AActual.Name) or
    (FromBuiltinKind(AFormal.Name) <> TValueKind.Builtin) or (FromBuiltinKind(AActual.Name) <> TValueKind.Builtin) then
  begin
    Exit;
  end;
  Result := not TTypeIdentity.Same(AFormal.Name, AActual.Name);
end;

class function TTypeCompatibility.PlatformDependent(const AName: string): Boolean;
var
  mName: string;
begin
  mName := AName;
  if StartsText('System.', mName) then
  begin
    mName := Copy(mName, 8, MaxInt);
  end;
  Result := MatchText(mName, cPlatformTypes);
end;

class function TTypeCompatibility.IsLongString(const AName: string): Boolean;
begin
  Result := MatchText(AName, cLongStrings);
end;

class function TTypeCompatibility.SetElement(const ASetName: string): string;
begin
  Result := '';
  if StartsText('set of ', ASetName) then
  begin
    Result := Trim(Copy(ASetName, 8, MaxInt));
  end;
end;

end.
