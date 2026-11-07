unit Atlas.Common.Semantics.ExpressionTypes;

// Typ eines Ausdrucks (#689): zu einer Markierung bzw. dem Cursor der
// kleinste vollständige Ausdruck im Syntaxbaum (wiederholt: der umschließende)
// und sein Typ.
//   - Blätter (Bezeichner, Ketten A.B.C, Aufrufe, Indizes, Dereferenzierung,
//     inherited) über die Namensauflösung: Variablen, Felder, Properties,
//     Funktionsergebnisse, Konstruktoren, Typumwandlungen, Aufzählungswerte;
//     generische Typparameter eingesetzt (FList.First: TKunde statt T),
//     Aliase mit Grundtyp (TKundenGruppen = TDictionary<…>). Dazu Literale,
//     nil, True/False und die Intrinsics der Unit System (Length, SizeOf,
//     Round …), Arrays (array of T, TArray<T>) und Zeiger (^T, PChar).
//   - Operatoren: Arithmetik nach Delphis Regeln (die breitere Ganzzahl, Int64
//     bei Cardinal mit Vorzeichen, Gleitkomma vor Ganzzahl, Currency mit
//     Ganzzahl bleibt Currency, / immer Extended), div/mod, Logik bitweise
//     oder Boolean, Vergleiche, in, is, as, Strings (+), Mengen, Zeiger ± Zahl,
//     Mengenkonstruktoren, anonyme Methoden (reference to …) und if-Ausdrücke.
//   - Implizite Umwandlungen: Operanden einer Rechnung, die erweitert werden
//     (Count: Integer → Currency), Variant und Char, die umgewandelt werden,
//     und Argumente, deren Typ nicht dem Parameter der gewählten Überladung
//     entspricht; bei mehreren Überladungen deren Kopf.
//   - Wert konstanter Ganzzahl-Ausdrücke über TConstantValues, SizeOf auch für
//     Records derselben Unit mit Feldern fester Größe (Ausrichtung wie {$A8}
//     bzw. packed).
//   - Fehler statt Typ: kein Ausdruck, unbekannter Name, Operator passt nicht,
//     Prozedur ohne Ergebnis, Typ nicht bestimmbar.
// Rekursion nur entlang der Ausdrucksstruktur mit Tiefenschranke.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver;

type
{$SCOPEDENUMS ON}
  /// <summary>Erweitern (Ganzzahl → Gleitkomma, schmale → breite Zahl) bzw. umwandeln (Variant, Char).</summary>
  TExpressionConversionKind = (Widen, Convert);
  TExpressionErrorKind = (None, NoExpression, UnknownName, OperatorMismatch, NoResult, Unknown);
  /// <summary>Grobe Art eines Typs für die Operatorregeln.</summary>
  TExpressionCategory = (Unknown, Integer_, Float, Currency_, Boolean_, Char_, String_, Variant_, Set_, Pointer_,
    Nil_, Other);
{$SCOPEDENUMS OFF}

  TExpressionConversion = record
    /// <summary>Teilausdruck wie im Quelltext (gekürzt).</summary>
    Expression: string;
    FromType: string;
    ToType: string;
    Kind: TExpressionConversionKind;
  end;

  TExpressionTypeInfo = record
    /// <summary>Bereich und Text des Ausdrucks, dessen Typ gilt.</summary>
    Range: TTextRange;
    Expression: string;
    /// <summary>Typ wie im Quelltext ('' bei Fehler).</summary>
    TypeName: string;
    /// <summary>Grundtyp eines Alias; '' sonst.</summary>
    BaseName: string;
    /// <summary>Fundort der Typdeklaration; TypeFile '' ohne (eingebaute Typen).</summary>
    TypeFile: string;
    TypeLine: Integer;
    TypeCharacter: Integer;
    Conversions: TArray<TExpressionConversion>;
    /// <summary>Kopf der gewählten Überladung, wenn es mehrere gibt; '' sonst.</summary>
    Overload: string;
    HasValue: Boolean;
    Value: Int64;
    Error: TExpressionErrorKind;
    /// <summary>Name bzw. Operator und Operandentypen zum Fehler.</summary>
    ErrorDetail: string;
    function Found: Boolean;
  end;

  TExpressionTypeOptions = record
    Conversions: Boolean;
    ConstValue: Boolean;
    class function Default: TExpressionTypeOptions; static;
  end;

  TExpressionTypes = class
  public const
    cMaxConversions = 8;
    cMaxExpressionLength = 60;
  private type
    TTyped = record
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
  private
    FResolver: TNameResolver;
    FTree: TSyntaxTree;
    FFileName: string;
    FText: string;
    FIndex: ISymbolIndex;
    FOptions: TExpressionTypeOptions;
    FConversions: TArray<TExpressionConversion>;
    FOverload: string;
    FDepth: Integer;
    function TypeNode(ANode: TSyntaxNode): TTyped;
    function TypeLeaf(ANode: TSyntaxNode): TTyped;
    function LeafResolved(ANode: TSyntaxNode; out ATyped: TTyped): Boolean;
    function MemberOf(ANode: TSyntaxNode; const AOwner: TTyped; out ATyped: TTyped): Boolean;
    function LeafMember(ANode: TSyntaxNode; out ATyped: TTyped): Boolean;
    function TypeBinary(ANode: TSyntaxNode): TTyped;
    function TypeComparison(ANode: TSyntaxNode; const AOperator: string): TTyped;
    function TypeOperation(ANode: TSyntaxNode; const AOperator: string): TTyped;
    function TypeUnary(ANode: TSyntaxNode): TTyped;
    function TypeSet(ANode: TSyntaxNode): TTyped;
    function TypeIntrinsic(ANode: TSyntaxNode; out ATyped: TTyped): Boolean;
    function ArrayText(const ASymbol, ATypeInfo: TResolvedSymbol; ATypeFound: Boolean): string;
    function TypeElement(ANode: TSyntaxNode; out ATyped: TTyped): Boolean;
    function TypeDereference(ANode: TSyntaxNode): TTyped;
    function FromText(const ATypeText: string; const AOwner: TResolvedSymbol): TTyped;
    function FromSymbol(const ASymbol, AType: TResolvedSymbol; ATypeFound: Boolean): TTyped;
    procedure NoteArguments(ANode: TSyntaxNode; const ARoutine: TResolvedSymbol);
    procedure NoteOperand(ANode: TSyntaxNode; const AOperand, AResult: TTyped; AWhole: Boolean);
    function BinaryOperands(ANode: TSyntaxNode; out ALeft, ARight: Int64): Boolean;
    function Evaluate(ANode: TSyntaxNode; out AValue: Int64): Boolean;
    procedure DescribeFound(ANode: TSyntaxNode; const AFound: TTyped; var AInfo: TExpressionTypeInfo);
  public
    /// <summary>AResolver muss ATree (AFileName) gepinnt haben; AText ist der Text des Baums. AIndex darf nil sein
    /// (dann keine Werte über Konstanten anderer Units).</summary>
    constructor Create(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
      const AIndex: ISymbolIndex; const AOptions: TExpressionTypeOptions);
    /// <summary>Kleinster vollständiger Ausdruck, der AStart..AEnd (Offsets) umfasst; mit AExpand der kleinste,
    /// der echt größer ist. nil ohne Ausdruck.</summary>
    class function FindExpression(ATree: TSyntaxTree; AStart, AEnd: Integer; AExpand: Boolean): TSyntaxNode; static;
    class function IsExpression(ANode: TSyntaxNode): Boolean; static;
    /// <summary>Kategorie, Breite und Vorzeichen eines eingebauten Typnamens.</summary>
    class function CategoryOf(const ATypeName: string; out AWidth: Integer; out ASigned: Boolean):
      TExpressionCategory; static;
    /// <summary>Typ des Ausdrucks ANode.</summary>
    function Describe(ANode: TSyntaxNode): TExpressionTypeInfo;
    /// <summary>Ausdruck an AStart..AEnd suchen und beschreiben; Error NoExpression ohne Ausdruck.</summary>
    function DescribeAt(AStart, AEnd: Integer; AExpand: Boolean): TExpressionTypeInfo;
  end;

implementation

// Überläufe beim Rechnen mit Konstanten melden sich als EIntOverflow.
{$OVERFLOWCHECKS ON}

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.ConstantValues,
  Atlas.Common.Semantics.ExpressionTypes.RecordSizes,
  Atlas.Common.Semantics.OrdinalConstants,
  Atlas.Common.Semantics.TypeIdentity;

type
  /// <summary>Kategorie, Breite (Rang bei Gleitkomma) und Vorzeichen eines eingebauten Typnamens.</summary>
  TBuiltinCategory = record
    Name: string;
    Category: TExpressionCategory;
    Width: Integer;
    Signed: Boolean;
  end;

  /// <summary>Ergebnistyp eines Intrinsics, der nicht vom Argument abhängt.</summary>
  TIntrinsicResult = record
    Name: string;
    TypeName: string;
  end;

const
  cMaxDepth = 64;
  cExpressionKinds = [TSyntaxKind.Identifier, TSyntaxKind.Literal, TSyntaxKind.MemberAccess, TSyntaxKind.Call,
    TSyntaxKind.IndexAccess, TSyntaxKind.Dereference, TSyntaxKind.AddressOf, TSyntaxKind.SetConstructor,
    TSyntaxKind.BinaryExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.ParenExpr, TSyntaxKind.InheritedExpr,
    TSyntaxKind.AnonymousMethod, TSyntaxKind.IfExpr];
  cComparisonOperators: array[0..8] of string = ('=', '<>', '<', '>', '<=', '>=', 'in', 'is', 'not in');
  cArithmeticOperators: array[0..9] of string = ('+', '-', '*', 'div', 'mod', 'shl', 'shr', 'and', 'or', 'xor');
  cSectionKeywords: array[0..4] of string = ('begin', 'var', 'const', 'type', 'label');
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
  cIntrinsicResults: array[0..25] of TIntrinsicResult = (
    (Name: 'Length'; TypeName: 'Integer'), (Name: 'SizeOf'; TypeName: 'Integer'),
    (Name: 'Pos'; TypeName: 'Integer'), (Name: 'Integer'; TypeName: 'Integer'),
    (Name: 'Round'; TypeName: 'Int64'), (Name: 'Trunc'; TypeName: 'Int64'),
    (Name: 'Chr'; TypeName: 'Char'), (Name: 'UpCase'; TypeName: 'Char'),
    (Name: 'Assigned'; TypeName: 'Boolean'), (Name: 'Odd'; TypeName: 'Boolean'),
    (Name: 'Eof'; TypeName: 'Boolean'), (Name: 'Eoln'; TypeName: 'Boolean'),
    (Name: 'IsManagedType'; TypeName: 'Boolean'), (Name: 'Sqrt'; TypeName: 'Extended'),
    (Name: 'Sin'; TypeName: 'Extended'), (Name: 'Cos'; TypeName: 'Extended'),
    (Name: 'Exp'; TypeName: 'Extended'), (Name: 'Ln'; TypeName: 'Extended'),
    (Name: 'ArcTan'; TypeName: 'Extended'), (Name: 'Frac'; TypeName: 'Extended'),
    (Name: 'Int'; TypeName: 'Extended'), (Name: 'Pi'; TypeName: 'Extended'),
    (Name: 'Concat'; TypeName: 'string'), (Name: 'Addr'; TypeName: 'Pointer'),
    (Name: 'TypeInfo'; TypeName: 'Pointer'), (Name: 'Ptr'; TypeName: 'Pointer'));

function TExpressionTypeInfo.Found: Boolean;
begin
  Result := TypeName <> '';
end;

class function TExpressionTypeOptions.Default: TExpressionTypeOptions;
begin
  Result.Conversions := True;
  Result.ConstValue := True;
end;

function TExpressionTypes.TTyped.Known: Boolean;
begin
  Result := Name <> '';
end;

function Typed(const AName: string): TExpressionTypes.TTyped;
var
  mWidth: Integer;
  mSigned: Boolean;
begin
  Result := Default(TExpressionTypes.TTyped);
  Result.Name := AName;
  Result.Category := TExpressionTypes.CategoryOf(AName, mWidth, mSigned);
  Result.Width := mWidth;
  Result.Signed := mSigned;
end;

function Failed(AKind: TExpressionErrorKind; const ADetail: string): TExpressionTypes.TTyped;
begin
  Result := Default(TExpressionTypes.TTyped);
  Result.Error := AKind;
  Result.ErrorDetail := ADetail;
end;

/// <summary>Ersetzt ganze Wörter nach Bindungen "T=TKunde" (ohne Unit-Präfix).</summary>
function Substitute(const AText: string; const ABindings: TArray<string>): string;
var
  mBinding, mName, mValue: string;
  mIndex, mStart: Integer;
begin
  Result := AText;
  for mBinding in ABindings do
  begin
    mName := Copy(mBinding, 1, Pos('=', mBinding) - 1);
    mValue := Copy(mBinding, Pos('=', mBinding) + 1, MaxInt);
    if mName = '' then
    begin
      Continue;
    end;
    mIndex := 1;
    while mIndex <= Length(Result) - Length(mName) + 1 do
    begin
      mStart := mIndex;
      if SameText(Copy(Result, mStart, Length(mName)), mName) and
        ((mStart = 1) or not CharInSet(Result[mStart - 1], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.'])) and
        ((mStart + Length(mName) > Length(Result)) or
        not CharInSet(Result[mStart + Length(mName)], ['A'..'Z', 'a'..'z', '0'..'9', '_'])) then
      begin
        Result := Copy(Result, 1, mStart - 1) + mValue + Copy(Result, mStart + Length(mName), MaxInt);
        Inc(mIndex, Length(mValue));
      end
      else
      begin
        Inc(mIndex);
      end;
    end;
  end;
end;

/// <summary>Typargumente der Bindungen ohne Unit-Präfix: "TList" mit T=Kunden.TKunde wird "TList&lt;TKunde&gt;".
/// </summary>
function WithArguments(AResolver: TNameResolver; const AName: string; const ABindings: TArray<string>): string;
var
  mBinding: string;
  mValues: TArray<string>;
begin
  Result := AName;
  if (Length(ABindings) = 0) or (Pos('<', AName) > 0) then
  begin
    Exit;
  end;
  mValues := nil;
  for mBinding in ABindings do
  begin
    mValues := mValues + [AResolver.Queries.UnqualifyType(Copy(mBinding, Pos('=', mBinding) + 1, MaxInt))];
  end;
  Result := Result + '<' + string.Join(', ', mValues) + '>';
end;

function Unqualified(AResolver: TNameResolver; const ABindings: TArray<string>): TArray<string>;
var
  mBinding: string;
begin
  Result := nil;
  for mBinding in ABindings do
  begin
    Result := Result + [Copy(mBinding, 1, Pos('=', mBinding)) +
      AResolver.Queries.UnqualifyType(Copy(mBinding, Pos('=', mBinding) + 1, MaxInt))];
  end;
end;

function SameType(const A, B: string): Boolean;
begin
  // Eingebaute Aliase (LongInt = Integer, Real = Double …) und Unit-Präfixe wie überall (#1324).
  Result := TTypeIdentity.Same(A, B);
end;
function IsNumeric(const AType: TExpressionTypes.TTyped): Boolean;
begin
  Result := AType.Category in [TExpressionCategory.Integer_, TExpressionCategory.Float, TExpressionCategory.Currency_];
end;

/// <summary>Mindestens eine Seite hat die Kategorie ACategory.</summary>
function HasCategory(const ALeft, ARight: TExpressionTypes.TTyped; ACategory: TExpressionCategory): Boolean;
begin
  Result := (ALeft.Category = ACategory) or (ARight.Category = ACategory);
end;

/// <summary>Beide Seiten haben die Kategorie ACategory.</summary>
function BothCategory(const ALeft, ARight: TExpressionTypes.TTyped; ACategory: TExpressionCategory): Boolean;
begin
  Result := (ALeft.Category = ACategory) and (ARight.Category = ACategory);
end;

/// <summary>Ganzzahl der Breite AWidth ohne Vorzeichen.</summary>
function IsUnsigned(const AType: TExpressionTypes.TTyped; AWidth: Integer): Boolean;
begin
  Result := (AType.Width = AWidth) and not AType.Signed;
end;

/// <summary>Ergebnis einer ganzzahligen Rechnung (Delphi): mindestens Integer; Int64 bzw. UInt64, wenn eine Seite
/// 64 Bit hat; Cardinal nur, wenn beide Seiten 32 Bit ohne Vorzeichen sind, mit Vorzeichen Int64.</summary>
function IntegerResult(const ALeft, ARight: TExpressionTypes.TTyped): TExpressionTypes.TTyped;
begin
  if ((ALeft.Width = 8) or (ARight.Width = 8)) and SameText(ALeft.Name, ARight.Name) then
  begin
    Result := Typed(ALeft.Name);
  end
  else if IsUnsigned(ALeft, 8) or IsUnsigned(ARight, 8) then
  begin
    Result := Typed('UInt64');
  end
  else if (ALeft.Width = 8) or (ARight.Width = 8) then
  begin
    Result := Typed('Int64');
  end
  else if IsUnsigned(ALeft, 4) and IsUnsigned(ARight, 4) then
  begin
    Result := Typed('Cardinal');
  end
  else if IsUnsigned(ALeft, 4) or IsUnsigned(ARight, 4) then
  begin
    Result := Typed('Int64');
  end
  else
  begin
    Result := Typed('Integer');
  end;
end;

/// <summary>Ergebnis von + - * mit mindestens einer Gleitkomma- oder Currency-Seite: Currency mit Ganzzahl bleibt
/// Currency, mit Gleitkomma Extended; sonst die breitere Gleitkommaseite.</summary>
function RealResult(const ALeft, ARight: TExpressionTypes.TTyped): TExpressionTypes.TTyped;
begin
  if HasCategory(ALeft, ARight, TExpressionCategory.Currency_) and
    HasCategory(ALeft, ARight, TExpressionCategory.Float) then
  begin
    Result := Typed('Extended');
  end
  else if HasCategory(ALeft, ARight, TExpressionCategory.Currency_) then
  begin
    Result := Typed('Currency');
  end
  else if (ARight.Category = TExpressionCategory.Float) and
    ((ALeft.Category <> TExpressionCategory.Float) or (ARight.Width > ALeft.Width)) then
  begin
    Result := Typed(ARight.Name);
  end
  else
  begin
    Result := Typed(ALeft.Name);
  end;
end;

/// <summary>Operator passt nicht zu den Operanden; Detail "Operator|Links|Rechts".</summary>
function Mismatch(const AOperator: string; const ALeft, ARight: TExpressionTypes.TTyped): TExpressionTypes.TTyped;
begin
  Result := Failed(TExpressionErrorKind.OperatorMismatch, AOperator + '|' + ALeft.Name + '|' + ARight.Name);
end;

/// <summary>Zeichen oder string.</summary>
function IsText(const AType: TExpressionTypes.TTyped): Boolean;
begin
  Result := AType.Category in [TExpressionCategory.String_, TExpressionCategory.Char_];
end;

/// <summary>Verkettung mit +: der string-Typ einer Seite, aus zwei Zeichen ein string.</summary>
function ConcatResult(const ALeft, ARight: TExpressionTypes.TTyped): TExpressionTypes.TTyped;
begin
  if ALeft.Category = TExpressionCategory.String_ then
  begin
    Result := Typed(ALeft.Name);
  end
  else if ARight.Category = TExpressionCategory.String_ then
  begin
    Result := Typed(ARight.Name);
  end
  else
  begin
    Result := Typed('string');
  end;
end;

/// <summary>+ - * mit einer Menge: die Mengenseite; rechts genügt ein Mengenkonstruktor.</summary>
function SetResult(const AOperator: string; const ALeft, ARight: TExpressionTypes.TTyped;
  ARightIsSet: Boolean): TExpressionTypes.TTyped;
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
function PointerOrSetResult(const AOperator: string; const ALeft, ARight: TExpressionTypes.TTyped;
  ARightIsSet: Boolean): TExpressionTypes.TTyped;
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
    Result := Typed('NativeInt');
  end
  else
  begin
    Result := Mismatch(AOperator, ALeft, ARight);
  end;
end;

/// <summary>Ergebnis von + - *; ANoted, wenn die Operanden umgewandelt werden können (Zahlen, Strings).</summary>
function AdditiveResult(const AOperator: string; const ALeft, ARight: TExpressionTypes.TTyped; ARightIsSet: Boolean;
  out ANoted: Boolean): TExpressionTypes.TTyped;
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
function ShiftResult(const ALeft: TExpressionTypes.TTyped): TExpressionTypes.TTyped;
begin
  if ALeft.Width = 8 then
  begin
    Result := Typed(ALeft.Name);
  end
  else
  begin
    Result := IntegerResult(ALeft, Typed('Integer'));
  end;
end;

/// <summary>Ergebnis von /, div, mod, ganzzahligem and/or/xor, shl, shr; Error Unknown ohne Detail bei unbekanntem
/// Operator.</summary>
function OtherResult(const AOperator: string; const ALeft, ARight: TExpressionTypes.TTyped): TExpressionTypes.TTyped;
begin
  if (AOperator = '/') and IsNumeric(ALeft) and IsNumeric(ARight) then
  begin
    Result := Typed('Extended');
  end
  else if AOperator = '/' then
  begin
    Result := Mismatch(AOperator, ALeft, ARight);
  end
  else if not MatchStr(AOperator, ['div', 'mod', 'and', 'or', 'xor', 'shl', 'shr']) then
  begin
    Result := Failed(TExpressionErrorKind.Unknown, '');
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
function OperationResult(const AOperator: string; const ALeft, ARight: TExpressionTypes.TTyped;
  ARightIsSet: Boolean; out ANoted: Boolean): TExpressionTypes.TTyped;
begin
  ANoted := False;
  if HasCategory(ALeft, ARight, TExpressionCategory.Variant_) then
  begin
    Result := Typed('Variant');
  end
  else if MatchStr(AOperator, ['+', '-', '*']) then
  begin
    Result := AdditiveResult(AOperator, ALeft, ARight, ARightIsSet, ANoted);
  end
  else if MatchStr(AOperator, ['and', 'or', 'xor']) and BothCategory(ALeft, ARight, TExpressionCategory.Boolean_) then
  begin
    Result := Typed('Boolean');
  end
  else
  begin
    Result := OtherResult(AOperator, ALeft, ARight);
    ANoted := Result.Known;
  end;
end;

/// <summary>not: Boolean, Ganzzahl und Variant bleiben.</summary>
function NotResult(const AOperand: TExpressionTypes.TTyped): TExpressionTypes.TTyped;
begin
  if AOperand.Category in [TExpressionCategory.Boolean_, TExpressionCategory.Integer_,
    TExpressionCategory.Variant_] then
  begin
    Result := AOperand;
  end
  else
  begin
    Result := Failed(TExpressionErrorKind.OperatorMismatch, 'not||' + AOperand.Name);
  end;
end;

/// <summary>Ergebnis eines einstelligen Operators (@, not, Vorzeichen) mit bekanntem Operanden.</summary>
function UnaryResult(const AOperator: string; const AOperand: TExpressionTypes.TTyped): TExpressionTypes.TTyped;
begin
  if AOperator = '@' then
  begin
    Result := Typed('Pointer');
  end
  else if SameText(AOperator, 'not') then
  begin
    Result := NotResult(AOperand);
  end
  else if not (IsNumeric(AOperand) or (AOperand.Category = TExpressionCategory.Variant_)) then
  begin
    Result := Failed(TExpressionErrorKind.OperatorMismatch, AOperator + '||' + AOperand.Name);
  end
  else if (AOperand.Category = TExpressionCategory.Integer_) and (AOperand.Width < 4) then
  begin
    // -Byte rechnet als Integer.
    Result := Typed('Integer');
  end
  else
  begin
    Result := AOperand;
  end;
end;

/// <summary>Ein Alias (TPreis = Currency) ist keine Umwandlung.</summary>
function IsAliasOf(const AOperand, AResult: TExpressionTypes.TTyped): Boolean;
begin
  Result := SameType(AOperand.Name, AResult.Name) or SameType(AOperand.Base, AResult.Name) or
    SameType(AOperand.Name, AResult.Base);
end;

/// <summary>Literale und Zwischenergebnisse (A * B) nur als ganzer Ausdruck; sonst steht der Grund weiter innen.
/// </summary>
function OperandShown(ANode: TSyntaxNode; AWhole: Boolean): Boolean;
begin
  Result := AWhole or not (ANode.Kind in [TSyntaxKind.Literal, TSyntaxKind.BinaryExpr, TSyntaxKind.ParenExpr]);
end;

/// <summary>Art der Umwandlung von AOperand nach AResult: Zahlen werden erweitert, Variant und Char umgewandelt.
/// </summary>
function ConversionKind(const AOperand, AResult: TExpressionTypes.TTyped;
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

function NodeTextOf(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := Copy(AText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

/// <summary>Text von ANode in einer Zeile, auf MaxExpressionLength gekürzt.</summary>
function ShortText(const AText: string; ANode: TSyntaxNode): string;
var
  mIndex: Integer;
begin
  Result := NodeTextOf(AText, ANode);
  for mIndex := 1 to Length(Result) do
  begin
    if CharInSet(Result[mIndex], [#9, #10, #13]) then
    begin
      Result[mIndex] := ' ';
    end;
  end;
  while Pos('  ', Result) > 0 do
  begin
    Result := StringReplace(Result, '  ', ' ', [rfReplaceAll]);
  end;
  Result := Trim(Result);
  if Length(Result) > TExpressionTypes.cMaxExpressionLength then
  begin
    Result := Copy(Result, 1, TExpressionTypes.cMaxExpressionLength - 1) + #$2026;
  end;
end;

/// <summary>#13 bzw. #$41 ohne weitere Teile.</summary>
function IsCharCode(const AText: string): Boolean;
begin
  Result := (AText[1] = '#') and (Pos('''', AText) = 0) and (Pos('#', Copy(AText, 2, MaxInt)) = 0);
end;

/// <summary>'a', '''' und #13 sind Zeichen, alles Längere ein string.</summary>
function QuotedType(const AText: string): string;
begin
  if ((Length(AText) = 3) and (AText[1] = '''')) or (AText = '''''''''') or IsCharCode(AText) then
  begin
    Result := 'Char';
  end
  else
  begin
    Result := 'string';
  end;
end;

/// <summary>Ganzzahl-Literal: Integer, außerhalb seines Bereichs Int64.</summary>
function IntegerLiteral(AValue: Int64): string;
begin
  if (AValue < Low(Integer)) or (AValue > High(Integer)) then
  begin
    Result := 'Int64';
  end
  else
  begin
    Result := 'Integer';
  end;
end;

/// <summary>Typ eines Literals (Zeichen, string, Zahl, nil); False bei unbekannter Form.</summary>
function LiteralType(const AText: string; out ATyped: TExpressionTypes.TTyped): Boolean;
var
  mValue: Int64;
begin
  Result := True;
  ATyped := Default(TExpressionTypes.TTyped);
  if (AText <> '') and CharInSet(AText[1], ['''', '#', '^']) then
  begin
    ATyped := Typed(QuotedType(AText));
  end
  else if TOrdinalConstants.TryNumber(AText, mValue) then
  begin
    ATyped := Typed(IntegerLiteral(mValue));
  end
  else if (AText <> '') and CharInSet(AText[1], ['0'..'9']) then
  begin
    ATyped := Typed('Extended');
  end
  else if SameText(AText, 'nil') then
  begin
    ATyped := Typed('nil');
  end
  else
  begin
    Result := False;
  end;
end;

/// <summary>Literal oder die Namen nil, True und False; AText ist der Text des Baums.</summary>
function ConstantLeaf(ANode: TSyntaxNode; const AText: string; out ATyped: TExpressionTypes.TTyped): Boolean;
var
  mText: string;
begin
  Result := False;
  ATyped := Default(TExpressionTypes.TTyped);
  mText := ANode.Name;
  if ANode.Kind = TSyntaxKind.Literal then
  begin
    if mText = '' then
    begin
      mText := NodeTextOf(AText, ANode);
    end;
    Result := LiteralType(mText, ATyped);
  end
  else if (ANode.Kind = TSyntaxKind.Identifier) and SameText(mText, 'nil') then
  begin
    ATyped := Typed('nil');
    Result := True;
  end
  else if (ANode.Kind = TSyntaxKind.Identifier) and (SameText(mText, 'True') or SameText(mText, 'False')) then
  begin
    ATyped := Typed('Boolean');
    Result := True;
  end;
end;

/// <summary>Aufruf eines Namens: Name(...).</summary>
function IsNamedCall(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount > 0) and (ANode[0].Kind = TSyntaxKind.Identifier);
end;

/// <summary>SizeOf(Name) mit einem Namen als Argument.</summary>
function IsSizeOfCall(ANode: TSyntaxNode): Boolean;
begin
  Result := IsNamedCall(ANode) and SameText(ANode[0].Name, 'SizeOf') and (ANode.ChildCount = 2) and
    (ANode[1].Kind = TSyntaxKind.Identifier);
end;

/// <summary>Ergebnistyp eines Intrinsics, der nicht vom Argument abhängt; '' sonst.</summary>
function FixedIntrinsic(const AName: string): string;
var
  mEntry: TIntrinsicResult;
begin
  Result := '';
  for mEntry in cIntrinsicResults do
  begin
    if SameText(mEntry.Name, AName) then
    begin
      Result := mEntry.TypeName;
      Break;
    end;
  end;
end;

/// <summary>High/Low: Ordinalwert bzw. -typ bleibt, Array und string ergeben Integer.</summary>
function BoundResult(const AArgument: TExpressionTypes.TTyped): TExpressionTypes.TTyped;
begin
  if (AArgument.Category in [TExpressionCategory.Integer_, TExpressionCategory.Char_, TExpressionCategory.Boolean_]) or
    ((AArgument.Symbol.Name <> '') and (AArgument.Symbol.SymbolKind = TIndexSymbolKind.EnumType)) then
  begin
    Result := AArgument;
  end
  else
  begin
    Result := Typed('Integer');
  end;
end;

/// <summary>Copy: string, bei einem Array dessen Typ.</summary>
function CopyResult(const AArgument: TExpressionTypes.TTyped): TExpressionTypes.TTyped;
begin
  if AArgument.Known and (AArgument.Category <> TExpressionCategory.String_) then
  begin
    Result := AArgument;
  end
  else
  begin
    Result := Typed('string');
  end;
end;

/// <summary>Ord: Integer, Ord eines Int64 bleibt Int64; Random: ohne Argument Extended, sonst Integer.</summary>
function NumberIntrinsic(const AName: string; const AArgument: TExpressionTypes.TTyped;
  ACount: Integer): TExpressionTypes.TTyped;
begin
  if SameText(AName, 'Ord') and (AArgument.Width = 8) then
  begin
    Result := Typed('Int64');
  end
  else if SameText(AName, 'Random') and (ACount = 0) then
  begin
    Result := Typed('Extended');
  end
  else
  begin
    Result := Typed('Integer');
  end;
end;

/// <summary>Intrinsics, deren Typ vom ersten Argument abhängt; False bei unbekanntem Namen oder Argument.</summary>
function ArgumentIntrinsic(const AName: string; const AArgument: TExpressionTypes.TTyped; ACount: Integer;
  out ATyped: TExpressionTypes.TTyped): Boolean;
begin
  Result := True;
  ATyped := Default(TExpressionTypes.TTyped);
  if MatchText(AName, ['Ord', 'Random']) then
  begin
    ATyped := NumberIntrinsic(AName, AArgument, ACount);
  end
  else if MatchText(AName, ['High', 'Low']) then
  begin
    ATyped := BoundResult(AArgument);
  end
  else if MatchText(AName, ['Succ', 'Pred', 'Abs', 'Sqr', 'Swap', 'Default']) then
  begin
    ATyped := AArgument;
    Result := AArgument.Known;
  end
  else if SameText(AName, 'Copy') then
  begin
    ATyped := CopyResult(AArgument);
  end
  else
  begin
    Result := False;
  end;
end;

/// <summary>Typ von SomeType.Create ohne eigenen Konstruktor im Index (aus TObject).</summary>
function IsDefaultConstructor(const AName: string; const AOwner: TExpressionTypes.TTyped): Boolean;
begin
  Result := SameText(AName, 'Create') and AOwner.Symbol.IsType and
    (AOwner.Symbol.SymbolKind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.RecordType]);
end;

/// <summary>Typ eines aufgelösten Symbols mit eingesetzten Typargumenten.</summary>
function SymbolTyped(AResolver: TNameResolver; const ASymbol: TResolvedSymbol): TExpressionTypes.TTyped;
begin
  Result := Typed(WithArguments(AResolver, ASymbol.Name, ASymbol.Bindings));
  Result.Symbol := ASymbol;
end;

/// <summary>Ein Typname, den die Namensauflösung bestimmen soll (kein eingebauter Typ, kein Array).</summary>
function IsDeclaredType(const ATyped: TExpressionTypes.TTyped; const AText: string): Boolean;
begin
  Result := (ATyped.Category = TExpressionCategory.Other) and (AText <> '') and not StartsText('array', AText);
end;

/// <summary>Mengen- und Zeigertypen aus der Signatur (TFarben = set of TFarbe, PKunde = ^TKunde); ACategory sonst.
/// </summary>
function SignatureCategory(const ASignature: string; ACategory: TExpressionCategory): TExpressionCategory;
var
  mBody: string;
begin
  Result := ACategory;
  if Pos('=', ASignature) > 0 then
  begin
    mBody := Trim(Copy(ASignature, Pos('=', ASignature) + 1, MaxInt));
    if StartsText('set of', mBody) then
    begin
      Result := TExpressionCategory.Set_;
    end
    else if StartsStr('^', mBody) then
    begin
      Result := TExpressionCategory.Pointer_;
    end;
  end;
end;

/// <summary>Alias: Grundtyp dazu; TZahl = Integer rechnet wie Integer.</summary>
procedure AddAliasBase(AResolver: TNameResolver; const AResolved: TResolvedSymbol;
  var ATyped: TExpressionTypes.TTyped);
var
  mFollowed: TResolvedSymbol;
begin
  if not AResolved.Builtin and (AResolved.SymbolKind = TIndexSymbolKind.TypeAlias) and
    AResolver.TypeOf(AResolved, mFollowed) and not SameType(mFollowed.Name, AResolved.Name) then
  begin
    ATyped.Base := WithArguments(AResolver, mFollowed.Name, mFollowed.Bindings);
    if mFollowed.Builtin then
    begin
      ATyped.Category := TExpressionTypes.CategoryOf(mFollowed.Name, ATyped.Width, ATyped.Signed);
    end;
  end;
end;

/// <summary>AText ohne abschließendes Semikolon.</summary>
function WithoutSemicolon(const AText: string): string;
begin
  Result := AText;
  if EndsStr(';', Result) then
  begin
    Result := Copy(Result, 1, Length(Result) - 1);
  end;
end;

/// <summary>array … oder TArray&lt;…&gt;.</summary>
function IsArrayText(const AText: string): Boolean;
begin
  Result := StartsText('array', AText) or StartsText('TArray<', AText);
end;

/// <summary>array [..] of T.</summary>
function IsArrayOf(const AText: string): Boolean;
begin
  Result := StartsText('array', AText) and (Pos(' of ', LowerCase(AText)) > 0);
end;

/// <summary>Elementtyp hinter " of ".</summary>
function AfterOf(const AText: string): string;
begin
  Result := Copy(AText, Pos(' of ', LowerCase(AText)) + 4, MaxInt);
end;

/// <summary>Elementtyp eines Array-Typtexts nach ADepth weiteren Indizes (array of array); False ohne Array.
/// </summary>
function ElementOf(const AText: string; ADepth: Integer; out AElement: string): Boolean;
var
  mIndex: Integer;
begin
  Result := True;
  if IsArrayOf(AText) then
  begin
    AElement := AfterOf(AText);
  end
  else if StartsText('TArray<', AText) and EndsStr('>', AText) then
  begin
    AElement := Copy(AText, 8, Length(AText) - 8);
  end
  else
  begin
    AElement := '';
    Result := False;
  end;
  for mIndex := 1 to ADepth do
  begin
    if IsArrayOf(Trim(AElement)) then
    begin
      AElement := AfterOf(AElement);
    end;
  end;
end;

/// <summary>Zieltyp der eingebauten Zeigertypen (PChar → Char); '' sonst.</summary>
function BuiltinTarget(const AName: string): string;
begin
  if MatchText(AName, ['PChar', 'PWideChar']) then
  begin
    Result := 'Char';
  end
  else if SameText(AName, 'PAnsiChar') then
  begin
    Result := 'AnsiChar';
  end
  else if SameText(AName, 'PByte') then
  begin
    Result := 'Byte';
  end
  else
  begin
    Result := '';
  end;
end;

/// <summary>Zieltyp von ^T bzw. eines Zeigertyps PKunde = ^TKunde; False ohne.</summary>
function PointerTarget(const AInner: TExpressionTypes.TTyped; out AText: string): Boolean;
var
  mSignature: string;
begin
  Result := True;
  mSignature := AInner.Symbol.Signature;
  if StartsStr('^', AInner.Name) then
  begin
    AText := Copy(AInner.Name, 2, MaxInt);
  end
  else if Pos('^', mSignature) > 0 then
  begin
    AText := WithoutSemicolon(Trim(Copy(mSignature, Pos('^', mSignature) + 1, MaxInt)));
  end
  else
  begin
    AText := '';
    Result := False;
  end;
end;

/// <summary>Änderung der Klammertiefe durch AToken.</summary>
function DepthChange(const AToken: TPascalToken): Integer;
begin
  Result := 0;
  if AToken.IsSymbol('(') then
  begin
    Result := 1;
  end
  else if AToken.IsSymbol(')') then
  begin
    Result := -1;
  end;
end;

/// <summary>begin bzw. ein Deklarationsabschnitt beendet den Kopf einer anonymen Methode.</summary>
function IsSectionStart(const AToken: TPascalToken): Boolean;
var
  mKeyword: string;
begin
  Result := False;
  for mKeyword in cSectionKeywords do
  begin
    if AToken.IsKeyword(mKeyword) then
    begin
      Result := True;
      Break;
    end;
  end;
end;

/// <summary>: , ; – nach ihnen folgt ein Leerzeichen.</summary>
function IsSeparator(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol(':') or AToken.IsSymbol(',') or AToken.IsSymbol(';');
end;

/// <summary>AHeader mit AToken; Leerzeichen zwischen Wörtern, nicht vor Klammern und Trennzeichen.</summary>
function HeaderWith(const AHeader: string; const AToken: TPascalToken): string;
begin
  Result := AHeader;
  if (Result <> '') and not IsSeparator(AToken) and not AToken.IsSymbol('(') and not AToken.IsSymbol(')') and
    not EndsStr('(', Result) then
  begin
    Result := Result + ' ';
  end;
  Result := Result + AToken.Text;
  if IsSeparator(AToken) then
  begin
    Result := Result + ' ';
  end;
end;

/// <summary>Typ einer anonymen Methode: "reference to" mit dem Kopf bis zum ersten begin bzw.
/// Deklarationsabschnitt außerhalb der Klammern.</summary>
function AnonymousType(ATree: TSyntaxTree; ANode: TSyntaxNode): TExpressionTypes.TTyped;
var
  mTokens: TArray<TPascalToken>;
  mIndex, mDepth: Integer;
  mHeader: string;
begin
  mTokens := ATree.Tokens;
  mHeader := '';
  mDepth := 0;
  for mIndex := TSyntaxTree.FirstTokenOf(mTokens, ANode.StartOffset) to High(mTokens) do
  begin
    if mTokens[mIndex].Offset >= ANode.EndOffset then
    begin
      Break;
    end;
    if (mTokens[mIndex].Offset >= ANode.StartOffset) and
      not (mTokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      mDepth := mDepth + DepthChange(mTokens[mIndex]);
      if (mDepth = 0) and IsSectionStart(mTokens[mIndex]) then
      begin
        Break;
      end;
      mHeader := HeaderWith(mHeader, mTokens[mIndex]);
    end;
  end;
  mHeader := StringReplace(Trim(mHeader), '  ', ' ', [rfReplaceAll]);
  Result := Typed('reference to ' + mHeader);
end;

/// <summary>Rechnet zwei Konstanten; False bei unbekanntem Operator, Division durch 0 und Überlauf.</summary>
function Arithmetic(const AOperator: string; ALeft, ARight: Int64; out AValue: Int64): Boolean;
begin
  AValue := 0;
  Result := MatchStr(AOperator, cArithmeticOperators) and not ((ARight = 0) and MatchStr(AOperator, ['div', 'mod']));
  if not Result then
  begin
    Exit;
  end;
  try
    case IndexStr(AOperator, cArithmeticOperators) of
      0: AValue := ALeft + ARight;
      1: AValue := ALeft - ARight;
      2: AValue := ALeft * ARight;
      3: AValue := ALeft div ARight;
      4: AValue := ALeft mod ARight;
      5: AValue := ALeft shl ARight;
      6: AValue := ALeft shr ARight;
      7: AValue := ALeft and ARight;
      8: AValue := ALeft or ARight;
      9: AValue := ALeft xor ARight;
    else
      Result := False;
    end;
  except
    on EIntOverflow do
    begin
      Result := False;
    end;
  end;
end;

/// <summary>ANode ist die rechte Seite von "Ziel := Wert".</summary>
function IsAssignedValue(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.AssignStatement) and
    (ANode.Parent.ChildCount = 2) and (ANode.Parent[1] = ANode);
end;

/// <summary>Fundort der Typdeklaration; nicht für eingebaute Typen.</summary>
procedure SetTypeLocation(const ASymbol: TResolvedSymbol; var AInfo: TExpressionTypeInfo);
begin
  if (ASymbol.Name <> '') and not ASymbol.Builtin and (ASymbol.FileName <> '') then
  begin
    AInfo.TypeFile := ASymbol.FileName;
    AInfo.TypeLine := ASymbol.SelectionRange.StartPos.Line;
    AInfo.TypeCharacter := ASymbol.SelectionRange.StartPos.Character;
  end;
end;

/// <summary>Fehler statt Typ: Art Unknown ohne genauere Art, Detail der Ausdruck ohne genaueres Detail.</summary>
procedure DescribeError(const AFound: TExpressionTypes.TTyped; var AInfo: TExpressionTypeInfo);
begin
  AInfo.Error := AFound.Error;
  if AInfo.Error = TExpressionErrorKind.None then
  begin
    AInfo.Error := TExpressionErrorKind.Unknown;
  end;
  AInfo.ErrorDetail := AFound.ErrorDetail;
  if AInfo.ErrorDetail = '' then
  begin
    AInfo.ErrorDetail := AInfo.Expression;
  end;
end;

/// <summary>Typtext einer Array-Deklaration in ATree ("array of TKunde", auch geschachtelt), deren Name an der
/// Stelle von ASymbol steht; '' sonst (lokale Variablen tragen keinen Typtext im Index).</summary>
function LocalArrayText(ATree: TSyntaxTree; const AText: string; const ASymbol: TResolvedSymbol): string;
var
  mFound, mNode: TSyntaxNode;
  mOffset: Integer;
begin
  Result := '';
  mOffset := TLineTable.Build(AText).OffsetAt(ASymbol.SelectionRange.StartPos);
  mFound := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := (mFound = nil) and (ANode.StartOffset <= mOffset) and (ANode.EndOffset >= mOffset);
      if Result and (ANode.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.Field, TSyntaxKind.Parameter]) then
      begin
        mFound := ANode;
      end;
    end);
  if mFound = nil then
  begin
    Exit;
  end;
  mNode := mFound.FindChild(TSyntaxKind.ArrayType);
  while (mNode <> nil) and (mNode.ChildCount > 0) do
  begin
    Result := Result + 'array of ';
    mNode := mNode[mNode.ChildCount - 1];
    if mNode.Kind <> TSyntaxKind.ArrayType then
    begin
      Result := Result + TIndexExtractor.TypeText(mNode);
      Exit;
    end;
  end;
  Result := '';
end;

{ TExpressionTypes }

constructor TExpressionTypes.Create(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
  const AIndex: ISymbolIndex; const AOptions: TExpressionTypeOptions);
begin
  inherited Create;
  FResolver := AResolver;
  FTree := ATree;
  FFileName := AFileName;
  FText := AText;
  FIndex := AIndex;
  FOptions := AOptions;
end;

class function TExpressionTypes.IsExpression(ANode: TSyntaxNode): Boolean;
var
  mParent: TSyntaxNode;
begin
  Result := (ANode <> nil) and (ANode.Kind in cExpressionKinds);
  if not Result then
  begin
    Exit;
  end;
  // Teile einer Kette sind keine eigenen Ausdrücke: das Mitglied hinter dem Punkt ist der MemberAccess selbst;
  // Typargumente und Bereiche (1..3) nicht.
  mParent := ANode.Parent;
  if (mParent <> nil) and (mParent.Kind in [TSyntaxKind.GenericArgs, TSyntaxKind.TypeReference]) then
  begin
    Result := False;
  end;
end;

class function TExpressionTypes.FindExpression(ATree: TSyntaxTree; AStart, AEnd: Integer;
  AExpand: Boolean): TSyntaxNode;
var
  mBest: TSyntaxNode;
begin
  mBest := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit(nil);
  end;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      Covers: Boolean;
    begin
      // Nur in Knoten absteigen, die die Stelle enthalten.
      Result := (ANode.StartOffset <= AStart) and (ANode.EndOffset >= AEnd);
      if not Result or not IsExpression(ANode) then
      begin
        Exit;
      end;
      Covers := True;
      if AExpand then
      begin
        Covers := (ANode.StartOffset < AStart) or (ANode.EndOffset > AEnd);
      end;
      if Covers and ((mBest = nil) or (ANode.EndOffset - ANode.StartOffset <= mBest.EndOffset - mBest.StartOffset)) then
      begin
        mBest := ANode;
      end;
    end);
  Result := mBest;
end;

class function TExpressionTypes.CategoryOf(const ATypeName: string; out AWidth: Integer;
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

function TExpressionTypes.FromText(const ATypeText: string; const AOwner: TResolvedSymbol): TTyped;
var
  mFromUnit: TUnitIndex;
  mResolved: TResolvedSymbol;
  mText: string;
begin
  mText := Trim(ATypeText);
  Result := Typed(FResolver.Queries.UnqualifyType(mText));
  if IsDeclaredType(Result, mText) and (AOwner.Name <> '') and FResolver.DeclaringUnit(AOwner, mFromUnit) and
    FResolver.ResolveTypeTextFrom(mFromUnit, mText, mResolved) then
  begin
    Result.Symbol := mResolved;
    Result.Category := SignatureCategory(mResolved.Signature, Result.Category);
    AddAliasBase(FResolver, mResolved, Result);
  end;
end;

function TExpressionTypes.FromSymbol(const ASymbol, AType: TResolvedSymbol; ATypeFound: Boolean): TTyped;
begin
  if ASymbol.IsType then
  begin
    // Typumwandlung TFoo(X) bzw. der Typ selbst.
    Result := SymbolTyped(FResolver, ASymbol);
  end
  else if (ASymbol.SymbolKind = TIndexSymbolKind.Constructor_) and ATypeFound then
  begin
    Result := SymbolTyped(FResolver, AType);
  end
  else if ASymbol.SymbolKind = TIndexSymbolKind.Constructor_ then
  begin
    Result := Typed(ASymbol.Container);
  end
  else if ASymbol.SymbolKind = TIndexSymbolKind.EnumMember then
  begin
    Result := FromText(ASymbol.Container, ASymbol);
  end
  else if ASymbol.TypeName <> '' then
  begin
    Result := FromText(Substitute(ASymbol.TypeName, Unqualified(FResolver, ASymbol.Bindings)), ASymbol);
    if (Result.Symbol.Name = '') and ATypeFound and not AType.Builtin then
    begin
      Result.Symbol := AType;
    end;
  end
  else if ASymbol.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine] then
  begin
    Result := Failed(TExpressionErrorKind.NoResult, ASymbol.Name);
  end
  else if ATypeFound then
  begin
    // Inline-Variable ohne Typ: der aufgelöste Typ.
    Result := SymbolTyped(FResolver, AType);
  end
  else
  begin
    Result := Default(TTyped);
  end;
end;

function TExpressionTypes.TypeNode(ANode: TSyntaxNode): TTyped;
begin
  Result := Default(TTyped);
  if ANode = nil then
  begin
    Exit;
  end;
  if FDepth > cMaxDepth then
  begin
    Exit(Failed(TExpressionErrorKind.Unknown, ''));
  end;
  Inc(FDepth);
  try
    case ANode.Kind of
      TSyntaxKind.ParenExpr:
        if ANode.ChildCount = 1 then
        begin
          Result := TypeNode(ANode[0]);
        end;
      TSyntaxKind.BinaryExpr:
        Result := TypeBinary(ANode);
      TSyntaxKind.UnaryExpr:
        Result := TypeUnary(ANode);
      TSyntaxKind.SetConstructor:
        Result := TypeSet(ANode);
      TSyntaxKind.AnonymousMethod:
        Result := AnonymousType(FTree, ANode);
      TSyntaxKind.IfExpr:
        if ANode.ChildCount >= 2 then
        begin
          Result := TypeNode(ANode[1]);
        end;
      TSyntaxKind.AddressOf:
        Result := Typed('Pointer');
      TSyntaxKind.Dereference:
        Result := TypeDereference(ANode);
    else
      Result := TypeLeaf(ANode);
    end;
  finally
    Dec(FDepth);
  end;
end;

function TExpressionTypes.TypeLeaf(ANode: TSyntaxNode): TTyped;
begin
  if ConstantLeaf(ANode, FText, Result) or TypeIntrinsic(ANode, Result) or LeafResolved(ANode, Result) or
    TypeElement(ANode, Result) or LeafMember(ANode, Result) then
  begin
    Exit;
  end;
  if (ANode.Kind = TSyntaxKind.Identifier) and (Length(FResolver.CallCandidates(FTree, FFileName, ANode)) = 0) then
  begin
    Result := Failed(TExpressionErrorKind.UnknownName, ANode.Name);
  end
  else
  begin
    Result := Failed(TExpressionErrorKind.Unknown, ShortText(FText, ANode));
  end;
end;

function TExpressionTypes.LeafResolved(ANode: TSyntaxNode; out ATyped: TTyped): Boolean;
var
  mSymbol, mTypeInfo: TResolvedSymbol;
  mTypeFound: Boolean;
  mValue: Int64;
begin
  ATyped := Default(TTyped);
  Result := FResolver.NodeType(FTree, FFileName, ANode, mSymbol, mTypeInfo, mTypeFound) and
    (mSymbol.Kind <> TResolvedKind.UnitName);
  if not Result then
  begin
    Exit;
  end;
  ATyped := FromSymbol(mSymbol, mTypeInfo, mTypeFound);
  if ATyped.Known and (ANode.Kind = TSyntaxKind.Call) and
    (mSymbol.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine, TIndexSymbolKind.Constructor_]) then
  begin
    NoteArguments(ANode, mSymbol);
  end;
  if not ATyped.Known and (ATyped.Error = TExpressionErrorKind.None) then
  begin
    // Untypisierte Konstante: aus ihrem Wert.
    Result := (mSymbol.SymbolKind = TIndexSymbolKind.Constant) and Evaluate(ANode, mValue);
    if Result then
    begin
      ATyped := Typed('Integer');
    end;
  end;
end;

function TExpressionTypes.MemberOf(ANode: TSyntaxNode; const AOwner: TTyped; out ATyped: TTyped): Boolean;
var
  mOwnerType, mMember: TResolvedSymbol;
begin
  ATyped := Default(TTyped);
  Result := (AOwner.Symbol.Name <> '') and FResolver.TypeOf(AOwner.Symbol, mOwnerType) and
    FResolver.FindMember(mOwnerType, ANode.Name, mMember);
  if Result then
  begin
    ATyped := FromSymbol(mMember, Default(TResolvedSymbol), False);
    Result := ATyped.Known or (ATyped.Error <> TExpressionErrorKind.None);
  end;
end;

function TExpressionTypes.LeafMember(ANode: TSyntaxNode; out ATyped: TTyped): Boolean;
var
  mOwner: TTyped;
begin
  // P^.Name und andere Empfänger, die die Namensauflösung nicht kennt: Mitglied am selbst bestimmten Typ.
  ATyped := Default(TTyped);
  Result := (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount > 0) and
    (ANode.FindChild(TSyntaxKind.GenericArgs) = nil);
  if not Result then
  begin
    Exit;
  end;
  mOwner := TypeNode(ANode[0]);
  ATyped := mOwner;
  if mOwner.Known and not MemberOf(ANode, mOwner, ATyped) then
  begin
    // TKunde.Create ohne eigenen Konstruktor im Index (aus TObject): ein TKunde.
    ATyped := mOwner;
    Result := IsDefaultConstructor(ANode.Name, mOwner);
  end;
end;

function TExpressionTypes.TypeIntrinsic(ANode: TSyntaxNode; out ATyped: TTyped): Boolean;
var
  mCandidates: TArray<TResolvedSymbol>;
  mArgument: TTyped;
  mFixed: string;
begin
  // Intrinsics der Unit System, sofern der Name nicht anders deklariert ist.
  ATyped := Default(TTyped);
  Result := IsNamedCall(ANode);
  if Result then
  begin
    mCandidates := FResolver.CallCandidates(FTree, FFileName, ANode[0]);
    Result := (Length(mCandidates) = 0) or SameText(mCandidates[0].UnitName, 'System');
  end;
  if not Result then
  begin
    Exit;
  end;
  mArgument := Default(TTyped);
  if ANode.ChildCount > 1 then
  begin
    mArgument := TypeNode(ANode[1]);
  end;
  mFixed := FixedIntrinsic(ANode[0].Name);
  if mFixed <> '' then
  begin
    ATyped := Typed(mFixed);
  end
  else
  begin
    Result := ArgumentIntrinsic(ANode[0].Name, mArgument, ANode.ChildCount - 1, ATyped);
  end;
end;

function TExpressionTypes.ArrayText(const ASymbol, ATypeInfo: TResolvedSymbol; ATypeFound: Boolean): string;
begin
  Result := Substitute(ASymbol.TypeName, Unqualified(FResolver, ASymbol.Bindings));
  if (Result = '') and SameText(ASymbol.FileName, FFileName) then
  begin
    Result := LocalArrayText(FTree, FText, ASymbol);
  end;
  if ATypeFound and not IsArrayText(Result) and (Pos('=', ATypeInfo.Signature) > 0) then
  begin
    // Eigener Array-Typ: TZeilen = array of string.
    Result := Trim(Copy(ATypeInfo.Signature, Pos('=', ATypeInfo.Signature) + 1, MaxInt));
  end;
  Result := WithoutSemicolon(Result);
end;

function TExpressionTypes.TypeElement(ANode: TSyntaxNode; out ATyped: TTyped): Boolean;
var
  mSymbol, mTypeInfo: TResolvedSymbol;
  mTypeFound: Boolean;
  mElement: string;
begin
  ATyped := Default(TTyped);
  Result := (ANode.Kind = TSyntaxKind.IndexAccess) and (ANode.ChildCount > 0) and
    FResolver.NodeType(FTree, FFileName, ANode[0], mSymbol, mTypeInfo, mTypeFound) and
    ElementOf(ArrayText(mSymbol, mTypeInfo, mTypeFound), ANode.ChildCount - 2, mElement);
  if Result then
  begin
    ATyped := FromText(mElement, mSymbol);
    Result := ATyped.Known;
  end;
end;

function TExpressionTypes.TypeDereference(ANode: TSyntaxNode): TTyped;
var
  mInner: TTyped;
  mTarget: string;
begin
  Result := Default(TTyped);
  if ANode.ChildCount = 0 then
  begin
    Exit;
  end;
  mInner := TypeNode(ANode[0]);
  if not mInner.Known then
  begin
    Result := mInner;
  end
  else if BuiltinTarget(mInner.Name) <> '' then
  begin
    Result := Typed(BuiltinTarget(mInner.Name));
  end
  else if PointerTarget(mInner, mTarget) then
  begin
    Result := FromText(mTarget, mInner.Symbol);
  end
  else
  begin
    // Objekt^ bzw. unbekannt: der Typ selbst bleibt unbestimmt.
    Result := Failed(TExpressionErrorKind.Unknown, ShortText(FText, ANode));
  end;
end;

function TExpressionTypes.TypeBinary(ANode: TSyntaxNode): TTyped;
var
  mOperator: string;
begin
  Result := Default(TTyped);
  if ANode.ChildCount <> 2 then
  begin
    Exit;
  end;
  mOperator := LowerCase(ANode.Name);
  if MatchText(mOperator, cComparisonOperators) then
  begin
    Result := TypeComparison(ANode, mOperator);
  end
  else if mOperator = 'as' then
  begin
    Result := TypeNode(ANode[1]);
  end
  else
  begin
    Result := TypeOperation(ANode, mOperator);
  end;
end;

function TExpressionTypes.TypeComparison(ANode: TSyntaxNode; const AOperator: string): TTyped;
var
  mLeft, mRight: TTyped;
begin
  // Operanden trotzdem prüfen: ein unbekannter Name ist ein Fehler.
  Result := Typed('Boolean');
  mLeft := TypeNode(ANode[0]);
  if mLeft.Error = TExpressionErrorKind.UnknownName then
  begin
    Result := mLeft;
  end
  else if AOperator <> 'is' then
  begin
    mRight := TypeNode(ANode[1]);
    if mRight.Error = TExpressionErrorKind.UnknownName then
    begin
      Result := mRight;
    end;
  end;
end;

function TExpressionTypes.TypeOperation(ANode: TSyntaxNode; const AOperator: string): TTyped;
var
  mLeft, mRight: TTyped;
  mNoted: Boolean;
begin
  mLeft := TypeNode(ANode[0]);
  if not mLeft.Known then
  begin
    Exit(mLeft);
  end;
  mRight := TypeNode(ANode[1]);
  if not mRight.Known then
  begin
    Exit(mRight);
  end;
  Result := OperationResult(AOperator, mLeft, mRight, ANode[1].Kind = TSyntaxKind.SetConstructor, mNoted);
  if Result.Error = TExpressionErrorKind.Unknown then
  begin
    Result.ErrorDetail := ShortText(FText, ANode);
  end;
  if mNoted then
  begin
    NoteOperand(ANode[0], mLeft, Result, False);
    NoteOperand(ANode[1], mRight, Result, False);
  end;
end;

procedure TExpressionTypes.NoteOperand(ANode: TSyntaxNode; const AOperand, AResult: TTyped; AWhole: Boolean);
var
  mConversion: TExpressionConversion;
begin
  mConversion := Default(TExpressionConversion);
  if FOptions.Conversions and (Length(FConversions) < cMaxConversions) and OperandShown(ANode, AWhole) and
    not IsAliasOf(AOperand, AResult) and ConversionKind(AOperand, AResult, mConversion.Kind) then
  begin
    mConversion.Expression := ShortText(FText, ANode);
    mConversion.FromType := AOperand.Name;
    mConversion.ToType := AResult.Name;
    FConversions := FConversions + [mConversion];
  end;
end;

procedure TExpressionTypes.NoteArguments(ANode: TSyntaxNode; const ARoutine: TResolvedSymbol);
var
  mCandidates: TArray<TResolvedSymbol>;
  mIndex: Integer;
  mArgument, mParameter: TTyped;
  mSaved: TArray<TExpressionConversion>;
begin
  mCandidates := FResolver.CallCandidates(FTree, FFileName, ANode[0]);
  if (Length(mCandidates) > 1) and (FOverload = '') then
  begin
    FOverload := ARoutine.Signature;
  end;
  if not FOptions.Conversions then
  begin
    Exit;
  end;
  for mIndex := 1 to ANode.ChildCount - 1 do
  begin
    if mIndex - 1 > High(ARoutine.ParamTypes) then
    begin
      Break;
    end;
    if ARoutine.ParamTypes[mIndex - 1] = '' then
    begin
      Continue;
    end;
    // Typen der Argumente ohne deren eigene Umwandlungen: die gehören zu Teilausdrücken.
    mSaved := FConversions;
    mArgument := TypeNode(ANode[mIndex]);
    FConversions := mSaved;
    mParameter := FromText(Substitute(ARoutine.ParamTypes[mIndex - 1], Unqualified(FResolver, ARoutine.Bindings)),
      ARoutine);
    if mArgument.Known and mParameter.Known then
    begin
      NoteOperand(ANode[mIndex], mArgument, mParameter, False);
    end;
  end;
end;

function TExpressionTypes.TypeUnary(ANode: TSyntaxNode): TTyped;
var
  mOperand: TTyped;
begin
  Result := Default(TTyped);
  if ANode.ChildCount = 1 then
  begin
    mOperand := TypeNode(ANode[0]);
    Result := mOperand;
    if mOperand.Known then
    begin
      Result := UnaryResult(ANode.Name, mOperand);
    end;
  end;
end;

function TExpressionTypes.TypeSet(ANode: TSyntaxNode): TTyped;
var
  mElement: TTyped;
  mFirst: TSyntaxNode;
begin
  if ANode.ChildCount = 0 then
  begin
    Exit(Typed('set of ()'));
  end;
  mFirst := ANode[0];
  if (mFirst.Kind = TSyntaxKind.RangeExpr) and (mFirst.ChildCount > 0) then
  begin
    mFirst := mFirst[0];
  end;
  mElement := TypeNode(mFirst);
  if not mElement.Known then
  begin
    Exit(mElement);
  end;
  // Zahlen in einer Menge sind Byte-Werte.
  if mElement.Category = TExpressionCategory.Integer_ then
  begin
    mElement := Typed('Byte');
  end;
  Result := Typed('set of ' + mElement.Name);
  Result.Category := TExpressionCategory.Set_;
end;

function TExpressionTypes.BinaryOperands(ANode: TSyntaxNode; out ALeft, ARight: Int64): Boolean;
begin
  ALeft := 0;
  ARight := 0;
  Result := (ANode.Kind = TSyntaxKind.BinaryExpr) and (ANode.ChildCount = 2) and
    MatchStr(LowerCase(ANode.Name), cArithmeticOperators) and Evaluate(ANode[0], ALeft) and
    Evaluate(ANode[1], ARight);
end;

function TExpressionTypes.Evaluate(ANode: TSyntaxNode; out AValue: Int64): Boolean;
var
  mValues: TConstantValues;
  mLeft, mRight: Int64;
  mSize: Integer;
begin
  Result := False;
  AValue := 0;
  if (ANode = nil) or (FDepth > cMaxDepth) then
  begin
    Exit;
  end;
  Inc(FDepth);
  try
    if IsSizeOfCall(ANode) and TRecordSizes.Measure(FTree, FDepth, ANode[1].Name, mSize) then
    begin
      // SizeOf eines Records derselben Unit.
      AValue := mSize;
      Result := True;
    end
    else if (ANode.Kind = TSyntaxKind.ParenExpr) and (ANode.ChildCount = 1) then
    begin
      Result := Evaluate(ANode[0], AValue);
    end
    else if BinaryOperands(ANode, mLeft, mRight) then
    begin
      Result := Arithmetic(LowerCase(ANode.Name), mLeft, mRight, AValue);
    end
    else
    begin
      mValues := TConstantValues.Create(FTree, FFileName, FIndex, FResolver);
      try
        Result := mValues.EvaluateNode(ANode, AValue);
      finally
        mValues.Free;
      end;
    end;
  finally
    Dec(FDepth);
  end;
end;

procedure TExpressionTypes.DescribeFound(ANode: TSyntaxNode; const AFound: TTyped; var AInfo: TExpressionTypeInfo);
var
  mSaved: TArray<TExpressionConversion>;
  mTarget: TTyped;
  mValue: Int64;
begin
  AInfo.TypeName := AFound.Name;
  AInfo.BaseName := AFound.Base;
  SetTypeLocation(AFound.Symbol, AInfo);
  // Rechte Seite einer Zuweisung: Umwandlung in den Typ des Ziels (Variant → string).
  if FOptions.Conversions and IsAssignedValue(ANode) then
  begin
    mSaved := FConversions;
    mTarget := TypeNode(ANode.Parent[0]);
    FConversions := mSaved;
    if mTarget.Known then
    begin
      NoteOperand(ANode, AFound, mTarget, True);
    end;
  end;
  AInfo.Conversions := FConversions;
  AInfo.Overload := FOverload;
  // Wert nur für Rechnungen und Namen, nicht für das Literal selbst.
  if FOptions.ConstValue and (ANode.Kind <> TSyntaxKind.Literal) and
    (AFound.Category in [TExpressionCategory.Integer_, TExpressionCategory.Char_, TExpressionCategory.Boolean_]) then
  begin
    FDepth := 0;
    AInfo.HasValue := Evaluate(ANode, mValue);
    if AInfo.HasValue then
    begin
      AInfo.Value := mValue;
    end;
  end;
end;

function TExpressionTypes.Describe(ANode: TSyntaxNode): TExpressionTypeInfo;
var
  mFound: TTyped;
begin
  Result := Default(TExpressionTypeInfo);
  if ANode = nil then
  begin
    Result.Error := TExpressionErrorKind.NoExpression;
    Exit;
  end;
  FConversions := nil;
  FOverload := '';
  FDepth := 0;
  Result.Range := TTextRange.Create(ANode.StartPos, ANode.EndPos);
  Result.Expression := ShortText(FText, ANode);
  mFound := TypeNode(ANode);
  if mFound.Known then
  begin
    DescribeFound(ANode, mFound, Result);
  end
  else
  begin
    DescribeError(mFound, Result);
  end;
end;

function TExpressionTypes.DescribeAt(AStart, AEnd: Integer; AExpand: Boolean): TExpressionTypeInfo;
begin
  Result := Describe(FindExpression(FTree, AStart, AEnd, AExpand));
end;

end.
