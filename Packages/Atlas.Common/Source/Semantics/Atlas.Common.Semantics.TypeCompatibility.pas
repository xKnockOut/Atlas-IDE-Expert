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
  Atlas.Common.Semantics.ExpressionTypes;

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
    Result.Kind := TValueKind.Other;
end;

class function TValueType.Create(const AName: string; ACategory: TExpressionCategory; AKind: TValueKind): TValueType;
begin
  Result := Default(TValueType);
  Result.Name := AName;
  Result.Category := ACategory;
  Result.Kind := AKind;
end;

{ TTypeCompatibility }

class function TTypeCompatibility.AssignIncompatible(const ATarget, ASource: TValueType): Boolean;
var
  mSource: TExpressionCategory;
  mSourceDecided, mSourceObject: Boolean;
begin
  Result := False;
  if not ATarget.Known or not ASource.Known then
    Exit;
  mSourceDecided := IsDecided(ASource);
  // Klassen, Interfaces und Aufzählungen haben keine Umwandlung in eingebaute Typen (Records schon: Implicit).
  mSourceObject := ASource.Kind in [TValueKind.ClassLike, TValueKind.Enum];
  if not mSourceDecided and not mSourceObject then
    Exit;
  mSource := ASource.Category;
  if not mSourceDecided then
    mSource := TExpressionCategory.Other;
  case ATarget.Kind of
    TValueKind.Builtin:
      begin
        if mSourceObject then
          Exit(ATarget.Category in [TExpressionCategory.Integer_, TExpressionCategory.Float,
            TExpressionCategory.Currency_, TExpressionCategory.Boolean_, TExpressionCategory.Char_,
            TExpressionCategory.String_]);
        case ATarget.Category of
          TExpressionCategory.Integer_:
            Result := mSource in [TExpressionCategory.Float, TExpressionCategory.Currency_,
              TExpressionCategory.Boolean_, TExpressionCategory.Char_, TExpressionCategory.String_,
              TExpressionCategory.Nil_, TExpressionCategory.Pointer_];
          TExpressionCategory.Float, TExpressionCategory.Currency_:
            Result := mSource in [TExpressionCategory.Boolean_, TExpressionCategory.Char_,
              TExpressionCategory.String_, TExpressionCategory.Nil_, TExpressionCategory.Pointer_];
          TExpressionCategory.Boolean_:
            Result := mSource in [TExpressionCategory.Integer_, TExpressionCategory.Float,
              TExpressionCategory.Currency_, TExpressionCategory.Char_, TExpressionCategory.String_,
              TExpressionCategory.Nil_, TExpressionCategory.Pointer_];
          TExpressionCategory.Char_:
            // Eine untypisierte Konstante 'a' ist auch ein Zeichen.
            Result := (mSource in [TExpressionCategory.Integer_, TExpressionCategory.Float,
              TExpressionCategory.Currency_, TExpressionCategory.Boolean_, TExpressionCategory.Nil_,
              TExpressionCategory.Pointer_]) or ((mSource = TExpressionCategory.String_) and not ASource.UntypedText);
          TExpressionCategory.String_:
            // PChar und nil gehen in einen String; Mengen bleiben offen.
            Result := mSource in [TExpressionCategory.Integer_, TExpressionCategory.Float,
              TExpressionCategory.Currency_, TExpressionCategory.Boolean_];
        else
          // Zeiger, Variant, Mengen: offen.
        end;
      end;
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

class function TTypeCompatibility.OperatorFit(const AOperator: string; const ALeft, ARight: TValueType): TOperatorFit;
var
  mLeftElement, mRightElement: TValueType;
begin
  Result := TOperatorFit.Unknown;
  if not IsDecided(ALeft) or not IsDecided(ARight) then
    Exit;
  if not MatchStr(AOperator, ['+', '-', '*', '/', 'div', 'mod', 'and', 'or', 'xor', 'shl', 'shr']) then
    Exit;
  // Zeiger und nil: Zeigerarithmetik hängt an {$POINTERMATH}.
  if (ALeft.Category in [TExpressionCategory.Pointer_, TExpressionCategory.Nil_]) or
    (ARight.Category in [TExpressionCategory.Pointer_, TExpressionCategory.Nil_]) then
    Exit;
  if not OperatorDefined(AOperator, ALeft.Category) or not OperatorDefined(AOperator, ARight.Category) then
    Exit(TOperatorFit.NotApplicable);
  if IsNumeric(ALeft.Category) and IsNumeric(ARight.Category) then
  begin
    // div, mod, and … nur mit Ganzzahlen; die Gleitkommaseite ist oben schon ausgeschieden.
    Result := TOperatorFit.Fits;
    Exit;
  end;
  if (ALeft.Category = TExpressionCategory.Boolean_) and (ARight.Category = TExpressionCategory.Boolean_) then
    Exit(TOperatorFit.Fits);
  if IsText(ALeft.Category) and IsText(ARight.Category) then
    Exit(TOperatorFit.Fits);
  // string + Integer: + ist für beide definiert, aber nicht zusammen (wie E2010). Char + Integer bleibt offen.
  if (AOperator = '+') and (((ALeft.Category = TExpressionCategory.String_) and IsNumeric(ARight.Category)) or
    (IsNumeric(ALeft.Category) and (ARight.Category = TExpressionCategory.String_))) then
    Exit(TOperatorFit.Incompatible);
  if (ALeft.Category = TExpressionCategory.Set_) and (ARight.Category = TExpressionCategory.Set_) then
  begin
    // Mengen aus Zahlen und aus Zeichen: [1] + ['a'] (wie E2010).
    mLeftElement := TValueType.FromBuiltin(SetElement(ALeft.Name));
    mRightElement := TValueType.FromBuiltin(SetElement(ARight.Name));
    if IsDecided(mLeftElement) and IsDecided(mRightElement) and
      (mLeftElement.Category in [TExpressionCategory.Integer_, TExpressionCategory.Char_, TExpressionCategory.Boolean_]) and
      (mRightElement.Category in [TExpressionCategory.Integer_, TExpressionCategory.Char_, TExpressionCategory.Boolean_]) and
      (mLeftElement.Category <> mRightElement.Category) then
      Exit(TOperatorFit.Incompatible);
    Exit(TOperatorFit.Fits);
  end;
  // Übrige Mischungen (Integer and Boolean, Menge + Zahl): offen.
end;

class function TTypeCompatibility.UnaryNotApplicable(const AOperator: string; const AOperand: TValueType): Boolean;
begin
  Result := False;
  if not IsDecided(AOperand) then
    Exit;
  if SameText(AOperator, 'not') then
    Result := AOperand.Category in [TExpressionCategory.Float, TExpressionCategory.Currency_,
      TExpressionCategory.Char_, TExpressionCategory.String_, TExpressionCategory.Set_]
  else if (AOperator = '-') or (AOperator = '+') then
    Result := AOperand.Category in [TExpressionCategory.Boolean_, TExpressionCategory.Char_,
      TExpressionCategory.String_, TExpressionCategory.Set_];
end;

class function TTypeCompatibility.VarParamDiffers(const AFormal, AActual: TValueType): Boolean;
begin
  Result := False;
  if not IsDecided(AFormal) or not IsDecided(AActual) then
    Exit;
  if not (AFormal.Category in [TExpressionCategory.Integer_, TExpressionCategory.Float, TExpressionCategory.Currency_,
    TExpressionCategory.Boolean_, TExpressionCategory.Char_, TExpressionCategory.String_]) or
    not (AActual.Category in [TExpressionCategory.Integer_, TExpressionCategory.Float, TExpressionCategory.Currency_,
    TExpressionCategory.Boolean_, TExpressionCategory.Char_, TExpressionCategory.String_]) then
    Exit;
  // Nur eingebaute Namen: Ein Alias TFloat = Single ist derselbe Typ wie Single, TZahl = type Integer ein anderer.
  if PlatformDependent(AFormal.Name) or PlatformDependent(AActual.Name) or
    (FromBuiltinKind(AFormal.Name) <> TValueKind.Builtin) or (FromBuiltinKind(AActual.Name) <> TValueKind.Builtin) then
    Exit;
  Result := not TTypeIdentity.Same(AFormal.Name, AActual.Name);
end;

class function TTypeCompatibility.PlatformDependent(const AName: string): Boolean;
var
  mName: string;
begin
  mName := AName;
  if StartsText('System.', mName) then
    mName := Copy(mName, 8, MaxInt);
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
    Result := Trim(Copy(ASetName, 8, MaxInt));
end;

end.
