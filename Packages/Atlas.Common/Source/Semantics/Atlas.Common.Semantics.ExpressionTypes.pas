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
    MaxConversions = 8;
    MaxExpressionLength = 60;
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
    function NodeText(ANode: TSyntaxNode): string;
    function Short(ANode: TSyntaxNode): string;
    function TypeNode(ANode: TSyntaxNode): TTyped;
    function TypeLeaf(ANode: TSyntaxNode): TTyped;
    function TypeBinary(ANode: TSyntaxNode): TTyped;
    function TypeUnary(ANode: TSyntaxNode): TTyped;
    function TypeSet(ANode: TSyntaxNode): TTyped;
    function TypeAnonymous(ANode: TSyntaxNode): TTyped;
    function TypeIntrinsic(ANode: TSyntaxNode; const AName: string; out ATyped: TTyped): Boolean;
    function TypeElement(ANode: TSyntaxNode; out ATyped: TTyped): Boolean;
    function TypeDereference(ANode: TSyntaxNode): TTyped;
    function FromText(const ATypeText: string; const AOwner: TResolvedSymbol): TTyped;
    function FromSymbol(const ASymbol, AType: TResolvedSymbol; ATypeFound: Boolean): TTyped;
    procedure NoteArguments(ANode: TSyntaxNode; const ARoutine: TResolvedSymbol);
    procedure NoteOperand(ANode: TSyntaxNode; const AOperand, AResult: TTyped; AWhole: Boolean);
    function Evaluate(ANode: TSyntaxNode; out AValue: Int64): Boolean;
    function RecordSize(const ATypeName: string; out ASize, AAlign: Integer): Boolean;
    function FieldSize(const ATypeText: string; out ASize, AAlign: Integer): Boolean;
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
  System.Math,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.ConstantValues,
  Atlas.Common.Semantics.OrdinalConstants;

const
  MaxDepth = 64;
  ExpressionKinds = [TSyntaxKind.Identifier, TSyntaxKind.Literal, TSyntaxKind.MemberAccess, TSyntaxKind.Call,
    TSyntaxKind.IndexAccess, TSyntaxKind.Dereference, TSyntaxKind.AddressOf, TSyntaxKind.SetConstructor,
    TSyntaxKind.BinaryExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.ParenExpr, TSyntaxKind.InheritedExpr,
    TSyntaxKind.AnonymousMethod, TSyntaxKind.IfExpr];
  ComparisonOperators: array[0..8] of string = ('=', '<>', '<', '>', '<=', '>=', 'in', 'is', 'not in');
  FloatNames: array[0..5] of string = ('Single', 'Real48', 'Double', 'Real', 'Comp', 'Extended');
  FloatRanks: array[0..5] of Integer = (1, 2, 3, 3, 3, 4);

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
  Width: Integer;
  Signed: Boolean;
begin
  Result := Default(TExpressionTypes.TTyped);
  Result.Name := AName;
  Result.Category := TExpressionTypes.CategoryOf(AName, Width, Signed);
  Result.Width := Width;
  Result.Signed := Signed;
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
  Binding, Name, Value: string;
  Index, Start: Integer;
begin
  Result := AText;
  for Binding in ABindings do
  begin
    Name := Copy(Binding, 1, Pos('=', Binding) - 1);
    Value := Copy(Binding, Pos('=', Binding) + 1, MaxInt);
    if Name = '' then
      Continue;
    Index := 1;
    while Index <= Length(Result) - Length(Name) + 1 do
    begin
      Start := Index;
      if SameText(Copy(Result, Start, Length(Name)), Name) and
        ((Start = 1) or not CharInSet(Result[Start - 1], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.'])) and
        ((Start + Length(Name) > Length(Result)) or
        not CharInSet(Result[Start + Length(Name)], ['A'..'Z', 'a'..'z', '0'..'9', '_'])) then
      begin
        Result := Copy(Result, 1, Start - 1) + Value + Copy(Result, Start + Length(Name), MaxInt);
        Inc(Index, Length(Value));
      end
      else
        Inc(Index);
    end;
  end;
end;

/// <summary>Typargumente der Bindungen ohne Unit-Präfix: "TList" mit T=Kunden.TKunde wird "TList&lt;TKunde&gt;".
/// </summary>
function WithArguments(AResolver: TNameResolver; const AName: string; const ABindings: TArray<string>): string;
var
  Binding: string;
  Values: TArray<string>;
begin
  Result := AName;
  if (Length(ABindings) = 0) or (Pos('<', AName) > 0) then
    Exit;
  Values := nil;
  for Binding in ABindings do
    Values := Values + [AResolver.UnqualifyType(Copy(Binding, Pos('=', Binding) + 1, MaxInt))];
  Result := Result + '<' + string.Join(', ', Values) + '>';
end;

function Unqualified(AResolver: TNameResolver; const ABindings: TArray<string>): TArray<string>;
var
  Binding: string;
begin
  Result := nil;
  for Binding in ABindings do
    Result := Result + [Copy(Binding, 1, Pos('=', Binding)) +
      AResolver.UnqualifyType(Copy(Binding, Pos('=', Binding) + 1, MaxInt))];
end;

function SameType(const A, B: string): Boolean;
var
  Left, Right: string;
begin
  Left := StringReplace(A, ' ', '', [rfReplaceAll]);
  Right := StringReplace(B, ' ', '', [rfReplaceAll]);
  Result := SameText(Left, Right) or (MatchText(Left, ['string', 'UnicodeString']) and
    MatchText(Right, ['string', 'UnicodeString'])) or (MatchText(Left, ['Integer', 'LongInt']) and
    MatchText(Right, ['Integer', 'LongInt'])) or (MatchText(Left, ['Cardinal', 'LongWord']) and
    MatchText(Right, ['Cardinal', 'LongWord'])) or (MatchText(Left, ['Char', 'WideChar']) and
    MatchText(Right, ['Char', 'WideChar'])) or (MatchText(Left, ['Double', 'Real']) and
    MatchText(Right, ['Double', 'Real']));
end;

function IsNumeric(const AType: TExpressionTypes.TTyped): Boolean;
begin
  Result := AType.Category in [TExpressionCategory.Integer_, TExpressionCategory.Float, TExpressionCategory.Currency_];
end;

/// <summary>Ergebnis einer ganzzahligen Rechnung (Delphi): mindestens Integer; Int64 bzw. UInt64, wenn eine Seite
/// 64 Bit hat; Cardinal nur, wenn beide Seiten 32 Bit ohne Vorzeichen sind, mit Vorzeichen Int64.</summary>
function IntegerResult(const ALeft, ARight: TExpressionTypes.TTyped): TExpressionTypes.TTyped;
begin
  if (ALeft.Width = 8) or (ARight.Width = 8) then
  begin
    if SameText(ALeft.Name, ARight.Name) then
      Result := Typed(ALeft.Name)
    else if ((ALeft.Width = 8) and not ALeft.Signed) or ((ARight.Width = 8) and not ARight.Signed) then
      Result := Typed('UInt64')
    else
      Result := Typed('Int64');
  end
  else if (ALeft.Width = 4) and (ARight.Width = 4) and not ALeft.Signed and not ARight.Signed then
    Result := Typed('Cardinal')
  else if ((ALeft.Width = 4) and not ALeft.Signed) or ((ARight.Width = 4) and not ARight.Signed) then
    Result := Typed('Int64')
  else
    Result := Typed('Integer');
end;

/// <summary>Ergebnis von + - * mit mindestens einer Gleitkomma- oder Currency-Seite.</summary>
function RealResult(const ALeft, ARight: TExpressionTypes.TTyped): TExpressionTypes.TTyped;
begin
  if (ALeft.Category = TExpressionCategory.Currency_) and (ARight.Category <> TExpressionCategory.Float) then
    Exit(Typed('Currency'));
  if (ARight.Category = TExpressionCategory.Currency_) and (ALeft.Category <> TExpressionCategory.Float) then
    Exit(Typed('Currency'));
  if (ALeft.Category = TExpressionCategory.Currency_) or (ARight.Category = TExpressionCategory.Currency_) then
    Exit(Typed('Extended'));
  // Die breitere Gleitkommaseite.
  if ARight.Category <> TExpressionCategory.Float then
    Result := Typed(ALeft.Name)
  else if ALeft.Category <> TExpressionCategory.Float then
    Result := Typed(ARight.Name)
  else if ARight.Width > ALeft.Width then
    Result := Typed(ARight.Name)
  else
    Result := Typed(ALeft.Name);
end;

/// <summary>Deklaration "ATypeName = record" im Baum; nil ohne.</summary>
function FindRecord(ARoot: TSyntaxNode; const ATypeName: string): TSyntaxNode;
var
  Pending: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
begin
  Result := nil;
  if ARoot = nil then
    Exit;
  // Iterativ (Bericht M1); auch lokale Typen in Routinen zählen.
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ARoot);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      if (Node.Kind = TSyntaxKind.TypeDecl) and SameText(Node.Name, ATypeName) and
        (Node.FindChild(TSyntaxKind.RecordType) <> nil) then
        Exit(Node);
      for Index := Node.ChildCount - 1 downto 0 do
        Pending.Push(Node[Index]);
    end;
  finally
    Pending.Free;
  end;
end;

/// <summary>Typtext einer Array-Deklaration in ATree ("array of TKunde", auch geschachtelt), deren Name an der
/// Stelle von ASymbol steht; '' sonst (lokale Variablen tragen keinen Typtext im Index).</summary>
function LocalArrayText(ATree: TSyntaxTree; const AText: string; const ASymbol: TResolvedSymbol): string;
var
  Found, Node: TSyntaxNode;
  Offset: Integer;
begin
  Result := '';
  Offset := TLineTable.Build(AText).OffsetAt(ASymbol.SelectionRange.StartPos);
  Found := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := (Found = nil) and (ANode.StartOffset <= Offset) and (ANode.EndOffset >= Offset);
      if Result and (ANode.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.Field, TSyntaxKind.Parameter]) then
        Found := ANode;
    end);
  if Found = nil then
    Exit;
  Node := Found.FindChild(TSyntaxKind.ArrayType);
  while (Node <> nil) and (Node.ChildCount > 0) do
  begin
    Result := Result + 'array of ';
    Node := Node[Node.ChildCount - 1];
    if Node.Kind <> TSyntaxKind.ArrayType then
    begin
      Result := Result + TIndexExtractor.TypeText(Node);
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
  Parent: TSyntaxNode;
begin
  Result := (ANode <> nil) and (ANode.Kind in ExpressionKinds);
  if not Result then
    Exit;
  // Teile einer Kette sind keine eigenen Ausdrücke: das Mitglied hinter dem Punkt ist der MemberAccess selbst;
  // Typargumente und Bereiche (1..3) nicht.
  Parent := ANode.Parent;
  if (Parent <> nil) and (Parent.Kind in [TSyntaxKind.GenericArgs, TSyntaxKind.TypeReference]) then
    Result := False;
end;

class function TExpressionTypes.FindExpression(ATree: TSyntaxTree; AStart, AEnd: Integer;
  AExpand: Boolean): TSyntaxNode;
var
  Best: TSyntaxNode;
begin
  Best := nil;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit(nil);
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      Covers: Boolean;
    begin
      // Nur in Knoten absteigen, die die Stelle enthalten.
      Result := (ANode.StartOffset <= AStart) and (ANode.EndOffset >= AEnd);
      if not Result or not IsExpression(ANode) then
        Exit;
      Covers := True;
      if AExpand then
        Covers := (ANode.StartOffset < AStart) or (ANode.EndOffset > AEnd);
      if Covers and ((Best = nil) or (ANode.EndOffset - ANode.StartOffset <= Best.EndOffset - Best.StartOffset)) then
        Best := ANode;
    end);
  Result := Best;
end;

class function TExpressionTypes.CategoryOf(const ATypeName: string; out AWidth: Integer;
  out ASigned: Boolean): TExpressionCategory;
var
  Name: string;
  Index: Integer;
begin
  AWidth := 0;
  ASigned := False;
  Name := ATypeName;
  if StartsText('System.', Name) then
    Name := Copy(Name, 8, MaxInt);
  Result := TExpressionCategory.Other;
  if Name = '' then
    Exit(TExpressionCategory.Unknown);
  if MatchText(Name, ['ShortInt', 'Int8']) then
  begin
    AWidth := 1;
    ASigned := True;
  end
  else if MatchText(Name, ['Byte', 'UInt8']) then
    AWidth := 1
  else if MatchText(Name, ['SmallInt', 'Int16']) then
  begin
    AWidth := 2;
    ASigned := True;
  end
  else if MatchText(Name, ['Word', 'UInt16']) then
    AWidth := 2
  else if MatchText(Name, ['Integer', 'LongInt', 'Int32', 'FixedInt']) then
  begin
    AWidth := 4;
    ASigned := True;
  end
  else if MatchText(Name, ['Cardinal', 'LongWord', 'UInt32', 'FixedUInt', 'DWORD']) then
    AWidth := 4
  else if MatchText(Name, ['Int64', 'NativeInt', 'IntPtr']) then
  begin
    AWidth := 8;
    ASigned := True;
  end
  else if MatchText(Name, ['UInt64', 'NativeUInt', 'UIntPtr']) then
    AWidth := 8;
  if AWidth > 0 then
    Exit(TExpressionCategory.Integer_);
  Index := IndexText(Name, FloatNames);
  if Index >= 0 then
  begin
    AWidth := FloatRanks[Index];
    Exit(TExpressionCategory.Float);
  end;
  if SameText(Name, 'Currency') then
    Exit(TExpressionCategory.Currency_);
  if MatchText(Name, ['Boolean', 'ByteBool', 'WordBool', 'LongBool']) then
    Exit(TExpressionCategory.Boolean_);
  if MatchText(Name, ['Char', 'WideChar', 'AnsiChar']) then
    Exit(TExpressionCategory.Char_);
  if MatchText(Name, ['string', 'UnicodeString', 'AnsiString', 'WideString', 'ShortString', 'RawByteString',
    'UTF8String']) then
    Exit(TExpressionCategory.String_);
  if MatchText(Name, ['Variant', 'OleVariant']) then
    Exit(TExpressionCategory.Variant_);
  if MatchText(Name, ['Pointer', 'PChar', 'PWideChar', 'PAnsiChar', 'PByte']) or StartsStr('^', Name) then
    Exit(TExpressionCategory.Pointer_);
  if SameText(Name, 'nil') then
    Exit(TExpressionCategory.Nil_);
  if StartsText('set of ', Name) then
    Exit(TExpressionCategory.Set_);
end;

function TExpressionTypes.NodeText(ANode: TSyntaxNode): string;
begin
  Result := Copy(FText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

function TExpressionTypes.Short(ANode: TSyntaxNode): string;
var
  Index: Integer;
begin
  Result := NodeText(ANode);
  for Index := 1 to Length(Result) do
    if CharInSet(Result[Index], [#9, #10, #13]) then
      Result[Index] := ' ';
  while Pos('  ', Result) > 0 do
    Result := StringReplace(Result, '  ', ' ', [rfReplaceAll]);
  Result := Trim(Result);
  if Length(Result) > MaxExpressionLength then
    Result := Copy(Result, 1, MaxExpressionLength - 1) + #$2026;
end;

function TExpressionTypes.FromText(const ATypeText: string; const AOwner: TResolvedSymbol): TTyped;
var
  FromUnit: TUnitIndex;
  Resolved, Followed: TResolvedSymbol;
  Text, Body: string;
begin
  Text := Trim(ATypeText);
  Result := Typed(FResolver.UnqualifyType(Text));
  if (Result.Category <> TExpressionCategory.Other) or (Text = '') then
    Exit;
  if StartsText('array', Text) then
    Exit;
  if (AOwner.Name <> '') and FResolver.DeclaringUnit(AOwner, FromUnit) and
    FResolver.ResolveTypeTextFrom(FromUnit, Text, Resolved) then
  begin
    Result.Symbol := Resolved;
    // Mengen- und Zeigertypen erkennt die Signatur: TFarben = set of TFarbe, PKunde = ^TKunde.
    Body := Trim(Copy(Resolved.Signature, Pos('=', Resolved.Signature) + 1, MaxInt));
    if (Pos('=', Resolved.Signature) > 0) and StartsText('set of', Body) then
      Result.Category := TExpressionCategory.Set_
    else if (Pos('=', Resolved.Signature) > 0) and StartsStr('^', Body) then
      Result.Category := TExpressionCategory.Pointer_;
    // Alias: Grundtyp dazu; TZahl = Integer rechnet wie Integer.
    if not Resolved.Builtin and (Resolved.SymbolKind = TIndexSymbolKind.TypeAlias) and
      FResolver.TypeOf(Resolved, Followed) and not SameType(Followed.Name, Resolved.Name) then
    begin
      Result.Base := WithArguments(FResolver, Followed.Name, Followed.Bindings);
      if Followed.Builtin then
        Result.Category := CategoryOf(Followed.Name, Result.Width, Result.Signed);
    end;
  end;
end;

function TExpressionTypes.FromSymbol(const ASymbol, AType: TResolvedSymbol; ATypeFound: Boolean): TTyped;
var
  Declared: string;
begin
  if ASymbol.IsType then
  begin
    // Typumwandlung TFoo(X) bzw. der Typ selbst.
    Result := Typed(WithArguments(FResolver, ASymbol.Name, ASymbol.Bindings));
    Result.Symbol := ASymbol;
    Exit;
  end;
  if (ASymbol.SymbolKind = TIndexSymbolKind.Constructor_) then
  begin
    if ATypeFound then
    begin
      Result := Typed(WithArguments(FResolver, AType.Name, AType.Bindings));
      Result.Symbol := AType;
    end
    else
      Result := Typed(ASymbol.Container);
    Exit;
  end;
  if ASymbol.SymbolKind = TIndexSymbolKind.EnumMember then
  begin
    Result := FromText(ASymbol.Container, ASymbol);
    Exit;
  end;
  Declared := ASymbol.TypeName;
  if (Declared = '') and (ASymbol.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine]) then
    Exit(Failed(TExpressionErrorKind.NoResult, ASymbol.Name));
  if Declared = '' then
  begin
    // Inline-Variable ohne Typ: der aufgelöste Typ.
    if ATypeFound then
    begin
      Result := Typed(WithArguments(FResolver, AType.Name, AType.Bindings));
      Result.Symbol := AType;
    end
    else
      Result := Default(TTyped);
    Exit;
  end;
  Declared := Substitute(Declared, Unqualified(FResolver, ASymbol.Bindings));
  Result := FromText(Declared, ASymbol);
  if (Result.Symbol.Name = '') and ATypeFound and not AType.Builtin then
    Result.Symbol := AType;
end;

function TExpressionTypes.TypeNode(ANode: TSyntaxNode): TTyped;
begin
  Result := Default(TTyped);
  if ANode = nil then
    Exit;
  if FDepth > MaxDepth then
    Exit(Failed(TExpressionErrorKind.Unknown, ''));
  Inc(FDepth);
  try
    case ANode.Kind of
      TSyntaxKind.ParenExpr:
        if ANode.ChildCount = 1 then
          Result := TypeNode(ANode[0]);
      TSyntaxKind.BinaryExpr:
        Result := TypeBinary(ANode);
      TSyntaxKind.UnaryExpr:
        Result := TypeUnary(ANode);
      TSyntaxKind.SetConstructor:
        Result := TypeSet(ANode);
      TSyntaxKind.AnonymousMethod:
        Result := TypeAnonymous(ANode);
      TSyntaxKind.IfExpr:
        if ANode.ChildCount >= 2 then
          Result := TypeNode(ANode[1]);
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
var
  Symbol, TypeInfo, OwnerType, Member: TResolvedSymbol;
  Owner: TTyped;
  TypeFound: Boolean;
  Text, Name: string;
  Value: Int64;
  Candidates: TArray<TResolvedSymbol>;
begin
  Result := Default(TTyped);
  if ANode.Kind = TSyntaxKind.Literal then
  begin
    Text := ANode.Name;
    if Text = '' then
      Text := NodeText(ANode);
    if (Text <> '') and CharInSet(Text[1], ['''', '#', '^']) then
    begin
      // 'a' und #13 sind Zeichen, alles Längere ein string.
      if ((Length(Text) = 3) and (Text[1] = '''')) or (Text = '''''''''') or
        ((Text[1] = '#') and (Pos('''', Text) = 0) and (Pos('#', Copy(Text, 2, MaxInt)) = 0)) then
        Exit(Typed('Char'));
      Exit(Typed('string'));
    end;
    if TOrdinalConstants.TryNumber(Text, Value) then
    begin
      if (Value < Low(Integer)) or (Value > High(Integer)) then
        Exit(Typed('Int64'));
      Exit(Typed('Integer'));
    end;
    if (Text <> '') and CharInSet(Text[1], ['0'..'9']) then
      Exit(Typed('Extended'));
    if SameText(Text, 'nil') then
      Exit(Typed('nil'));
  end;
  if ANode.Kind = TSyntaxKind.Identifier then
  begin
    Name := ANode.Name;
    if SameText(Name, 'nil') then
      Exit(Typed('nil'));
    if SameText(Name, 'True') or SameText(Name, 'False') then
      Exit(Typed('Boolean'));
  end;
  // Intrinsics der Unit System, sofern der Name nicht anders deklariert ist.
  if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount > 0) and (ANode[0].Kind = TSyntaxKind.Identifier) then
  begin
    Candidates := FResolver.CallCandidates(FTree, FFileName, ANode[0]);
    if ((Length(Candidates) = 0) or SameText(Candidates[0].UnitName, 'System')) and
      TypeIntrinsic(ANode, ANode[0].Name, Result) then
      Exit;
  end;
  if FResolver.NodeType(FTree, FFileName, ANode, Symbol, TypeInfo, TypeFound) and
    (Symbol.Kind <> TResolvedKind.UnitName) then
  begin
    Result := FromSymbol(Symbol, TypeInfo, TypeFound);
    if Result.Known and (ANode.Kind = TSyntaxKind.Call) and
      (Symbol.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine, TIndexSymbolKind.Constructor_]) then
      NoteArguments(ANode, Symbol);
    if Result.Known or (Result.Error <> TExpressionErrorKind.None) then
      Exit;
    // Untypisierte Konstante: aus ihrem Wert.
    if (Symbol.SymbolKind = TIndexSymbolKind.Constant) and Evaluate(ANode, Value) then
      Exit(Typed('Integer'));
  end;
  if (ANode.Kind = TSyntaxKind.IndexAccess) and TypeElement(ANode, Result) then
    Exit;
  // P^.Name und andere Empfänger, die die Namensauflösung nicht kennt: Mitglied am selbst bestimmten Typ.
  if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount > 0) and
    (ANode.FindChild(TSyntaxKind.GenericArgs) = nil) then
  begin
    Owner := TypeNode(ANode[0]);
    if not Owner.Known then
      Exit(Owner);
    if (Owner.Symbol.Name <> '') and FResolver.TypeOf(Owner.Symbol, OwnerType) and
      FResolver.FindMember(OwnerType, ANode.Name, Member) then
    begin
      Result := FromSymbol(Member, Default(TResolvedSymbol), False);
      if Result.Known or (Result.Error <> TExpressionErrorKind.None) then
        Exit;
    end;
    // TKunde.Create ohne eigenen Konstruktor im Index (aus TObject): ein TKunde.
    if SameText(ANode.Name, 'Create') and Owner.Symbol.IsType and
      (Owner.Symbol.SymbolKind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.RecordType]) then
      Exit(Owner);
  end;
  if ANode.Kind = TSyntaxKind.Identifier then
  begin
    Candidates := FResolver.CallCandidates(FTree, FFileName, ANode);
    if Length(Candidates) = 0 then
      Exit(Failed(TExpressionErrorKind.UnknownName, ANode.Name));
  end;
  Result := Failed(TExpressionErrorKind.Unknown, Short(ANode));
end;

function TExpressionTypes.TypeIntrinsic(ANode: TSyntaxNode; const AName: string; out ATyped: TTyped): Boolean;
var
  Argument: TTyped;
  Count: Integer;
begin
  Result := True;
  Count := ANode.ChildCount - 1;
  Argument := Default(TTyped);
  if Count >= 1 then
    Argument := TypeNode(ANode[1]);
  if MatchText(AName, ['Length', 'SizeOf', 'Pos', 'Ord', 'Integer']) then
  begin
    ATyped := Typed('Integer');
    // Ord eines Int64 bleibt Int64.
    if SameText(AName, 'Ord') and (Argument.Width = 8) then
      ATyped := Typed('Int64');
  end
  else if MatchText(AName, ['High', 'Low']) then
  begin
    // High(Ordinalwert bzw. -typ) ist dieser Typ, High(Array/string) Integer.
    if Argument.Category in [TExpressionCategory.Integer_, TExpressionCategory.Char_, TExpressionCategory.Boolean_] then
      ATyped := Argument
    else if (Argument.Symbol.Name <> '') and (Argument.Symbol.SymbolKind = TIndexSymbolKind.EnumType) then
      ATyped := Argument
    else
      ATyped := Typed('Integer');
  end
  else if MatchText(AName, ['Succ', 'Pred', 'Abs', 'Sqr', 'Swap']) then
  begin
    if not Argument.Known then
      Exit(False);
    ATyped := Argument;
  end
  else if MatchText(AName, ['Round', 'Trunc']) then
    ATyped := Typed('Int64')
  else if MatchText(AName, ['Chr', 'UpCase']) then
    ATyped := Typed('Char')
  else if MatchText(AName, ['Assigned', 'Odd', 'Eof', 'Eoln', 'IsManagedType']) then
    ATyped := Typed('Boolean')
  else if MatchText(AName, ['Sqrt', 'Sin', 'Cos', 'Exp', 'Ln', 'ArcTan', 'Frac', 'Int', 'Pi']) then
    ATyped := Typed('Extended')
  else if SameText(AName, 'Random') then
  begin
    if Count = 0 then
      ATyped := Typed('Extended')
    else
      ATyped := Typed('Integer');
  end
  else if SameText(AName, 'Concat') then
    ATyped := Typed('string')
  else if SameText(AName, 'Copy') then
  begin
    if Argument.Known and (Argument.Category <> TExpressionCategory.String_) then
      ATyped := Argument
    else
      ATyped := Typed('string');
  end
  else if MatchText(AName, ['Addr', 'TypeInfo', 'Ptr']) then
    ATyped := Typed('Pointer')
  else if SameText(AName, 'Default') then
  begin
    if not Argument.Known then
      Exit(False);
    ATyped := Argument;
  end
  else
    Result := False;
end;

function TExpressionTypes.TypeElement(ANode: TSyntaxNode; out ATyped: TTyped): Boolean;
var
  Symbol, TypeInfo: TResolvedSymbol;
  TypeFound: Boolean;
  Text, Element: string;
  Depth, Index: Integer;
begin
  Result := False;
  ATyped := Default(TTyped);
  if (ANode.ChildCount = 0) or not FResolver.NodeType(FTree, FFileName, ANode[0], Symbol, TypeInfo, TypeFound) then
    Exit;
  Text := Substitute(Symbol.TypeName, Unqualified(FResolver, Symbol.Bindings));
  if (Text = '') and SameText(Symbol.FileName, FFileName) then
    Text := LocalArrayText(FTree, FText, Symbol);
  if TypeFound and not StartsText('array', Text) and not StartsText('TArray<', Text) and
    (TypeInfo.Signature <> '') and (Pos('=', TypeInfo.Signature) > 0) then
    // Eigener Array-Typ: TZeilen = array of string.
    Text := Trim(Copy(TypeInfo.Signature, Pos('=', TypeInfo.Signature) + 1, MaxInt));
  if EndsStr(';', Text) then
    Text := Copy(Text, 1, Length(Text) - 1);
  Element := '';
  if StartsText('array', Text) and (Pos(' of ', LowerCase(Text)) > 0) then
    Element := Copy(Text, Pos(' of ', LowerCase(Text)) + 4, MaxInt)
  else if StartsText('TArray<', Text) and EndsStr('>', Text) then
    Element := Copy(Text, 8, Length(Text) - 8)
  else
    Exit;
  // Mehrere Indizes bei array of array: je Index eine Stufe.
  Depth := ANode.ChildCount - 2;
  for Index := 1 to Depth do
    if StartsText('array', Trim(Element)) and (Pos(' of ', LowerCase(Element)) > 0) then
      Element := Copy(Element, Pos(' of ', LowerCase(Element)) + 4, MaxInt);
  ATyped := FromText(Element, Symbol);
  Result := ATyped.Known;
end;

function TExpressionTypes.TypeDereference(ANode: TSyntaxNode): TTyped;
var
  Inner: TTyped;
  Text: string;
begin
  Result := Default(TTyped);
  if ANode.ChildCount = 0 then
    Exit;
  Inner := TypeNode(ANode[0]);
  if not Inner.Known then
    Exit(Inner);
  if SameText(Inner.Name, 'PChar') or SameText(Inner.Name, 'PWideChar') then
    Exit(Typed('Char'));
  if SameText(Inner.Name, 'PAnsiChar') then
    Exit(Typed('AnsiChar'));
  if SameText(Inner.Name, 'PByte') then
    Exit(Typed('Byte'));
  if StartsStr('^', Inner.Name) then
    Exit(FromText(Copy(Inner.Name, 2, MaxInt), Inner.Symbol));
  // PKunde = ^TKunde.
  Text := Inner.Symbol.Signature;
  if Pos('^', Text) > 0 then
  begin
    Text := Trim(Copy(Text, Pos('^', Text) + 1, MaxInt));
    if EndsStr(';', Text) then
      Text := Copy(Text, 1, Length(Text) - 1);
    Exit(FromText(Text, Inner.Symbol));
  end;
  // Objekt^ bzw. unbekannt: der Typ selbst bleibt unbestimmt.
  Result := Failed(TExpressionErrorKind.Unknown, Short(ANode));
end;

function TExpressionTypes.TypeBinary(ANode: TSyntaxNode): TTyped;
var
  Operator, Detail: string;
  Left, Right: TTyped;
begin
  Result := Default(TTyped);
  if ANode.ChildCount <> 2 then
    Exit;
  Operator := LowerCase(ANode.Name);
  if MatchText(Operator, ComparisonOperators) then
  begin
    // Operanden trotzdem prüfen: ein unbekannter Name ist ein Fehler.
    Left := TypeNode(ANode[0]);
    if Left.Error = TExpressionErrorKind.UnknownName then
      Exit(Left);
    if Operator <> 'is' then
    begin
      Right := TypeNode(ANode[1]);
      if Right.Error = TExpressionErrorKind.UnknownName then
        Exit(Right);
    end;
    Exit(Typed('Boolean'));
  end;
  if Operator = 'as' then
    Exit(TypeNode(ANode[1]));
  Left := TypeNode(ANode[0]);
  if not Left.Known then
    Exit(Left);
  Right := TypeNode(ANode[1]);
  if not Right.Known then
    Exit(Right);
  Detail := Operator + '|' + Left.Name + '|' + Right.Name;
  if (Left.Category = TExpressionCategory.Variant_) or (Right.Category = TExpressionCategory.Variant_) then
  begin
    Result := Typed('Variant');
    Exit;
  end;
  if (Operator = '+') or (Operator = '-') or (Operator = '*') then
  begin
    if (Left.Category = TExpressionCategory.Integer_) and (Right.Category = TExpressionCategory.Integer_) then
      Result := IntegerResult(Left, Right)
    else if IsNumeric(Left) and IsNumeric(Right) then
      Result := RealResult(Left, Right)
    else if (Operator = '+') and (Left.Category in [TExpressionCategory.String_, TExpressionCategory.Char_]) and
      (Right.Category in [TExpressionCategory.String_, TExpressionCategory.Char_]) then
    begin
      if Left.Category = TExpressionCategory.String_ then
        Result := Typed(Left.Name)
      else if Right.Category = TExpressionCategory.String_ then
        Result := Typed(Right.Name)
      else
        Result := Typed('string');
    end
    else if (Left.Category = TExpressionCategory.Set_) or (Right.Category = TExpressionCategory.Set_) then
    begin
      if (Left.Category = TExpressionCategory.Set_) and ((Right.Category = TExpressionCategory.Set_) or
        (ANode[1].Kind = TSyntaxKind.SetConstructor)) then
        Result := Left
      else if Right.Category = TExpressionCategory.Set_ then
        Result := Right
      else
        Exit(Failed(TExpressionErrorKind.OperatorMismatch, Detail));
      Exit;
    end
    else if (Left.Category = TExpressionCategory.Pointer_) and (Right.Category = TExpressionCategory.Integer_) and
      (Operator <> '*') then
      Exit(Left)
    else if (Left.Category = TExpressionCategory.Pointer_) and (Right.Category = TExpressionCategory.Pointer_) and
      (Operator = '-') then
      Exit(Typed('NativeInt'))
    else
      Exit(Failed(TExpressionErrorKind.OperatorMismatch, Detail));
  end
  else if Operator = '/' then
  begin
    if not (IsNumeric(Left) and IsNumeric(Right)) then
      Exit(Failed(TExpressionErrorKind.OperatorMismatch, Detail));
    Result := Typed('Extended');
  end
  else if (Operator = 'div') or (Operator = 'mod') then
  begin
    if (Left.Category <> TExpressionCategory.Integer_) or (Right.Category <> TExpressionCategory.Integer_) then
      Exit(Failed(TExpressionErrorKind.OperatorMismatch, Detail));
    Result := IntegerResult(Left, Right);
  end
  else if (Operator = 'and') or (Operator = 'or') or (Operator = 'xor') then
  begin
    if (Left.Category = TExpressionCategory.Boolean_) and (Right.Category = TExpressionCategory.Boolean_) then
      Exit(Typed('Boolean'));
    if (Left.Category <> TExpressionCategory.Integer_) or (Right.Category <> TExpressionCategory.Integer_) then
      Exit(Failed(TExpressionErrorKind.OperatorMismatch, Detail));
    Result := IntegerResult(Left, Right);
  end
  else if (Operator = 'shl') or (Operator = 'shr') then
  begin
    if (Left.Category <> TExpressionCategory.Integer_) or (Right.Category <> TExpressionCategory.Integer_) then
      Exit(Failed(TExpressionErrorKind.OperatorMismatch, Detail));
    if Left.Width = 8 then
      Result := Typed(Left.Name)
    else
      Result := IntegerResult(Left, Typed('Integer'));
  end
  else
    Exit(Failed(TExpressionErrorKind.Unknown, Short(ANode)));
  NoteOperand(ANode[0], Left, Result, False);
  NoteOperand(ANode[1], Right, Result, False);
end;

procedure TExpressionTypes.NoteOperand(ANode: TSyntaxNode; const AOperand, AResult: TTyped; AWhole: Boolean);
var
  Conversion: TExpressionConversion;
begin
  // Ein Alias (TPreis = Currency) ist keine Umwandlung.
  if not FOptions.Conversions or (Length(FConversions) >= MaxConversions) or SameType(AOperand.Name, AResult.Name) or
    SameType(AOperand.Base, AResult.Name) or SameType(AOperand.Name, AResult.Base) or
    (not AWhole and (ANode.Kind = TSyntaxKind.Literal)) then
    Exit;
  Conversion := Default(TExpressionConversion);
  if IsNumeric(AOperand) and IsNumeric(AResult) then
    Conversion.Kind := TExpressionConversionKind.Widen
  else if (AOperand.Category in [TExpressionCategory.Variant_, TExpressionCategory.Char_]) and
    (AResult.Category in [TExpressionCategory.String_, TExpressionCategory.Integer_, TExpressionCategory.Float,
    TExpressionCategory.Currency_, TExpressionCategory.Boolean_]) then
    Conversion.Kind := TExpressionConversionKind.Convert
  else
    Exit;
  // Zwischenergebnisse einer Rechnung (A * B) nur, wenn sie selbst ein Name sind; sonst steht der Grund weiter
  // innen schon da.
  if not AWhole and (ANode.Kind in [TSyntaxKind.BinaryExpr, TSyntaxKind.ParenExpr]) then
    Exit;
  Conversion.Expression := Short(ANode);
  Conversion.FromType := AOperand.Name;
  Conversion.ToType := AResult.Name;
  FConversions := FConversions + [Conversion];
end;

procedure TExpressionTypes.NoteArguments(ANode: TSyntaxNode; const ARoutine: TResolvedSymbol);
var
  Candidates: TArray<TResolvedSymbol>;
  Index: Integer;
  Argument, Parameter: TTyped;
  Saved: TArray<TExpressionConversion>;
begin
  Candidates := FResolver.CallCandidates(FTree, FFileName, ANode[0]);
  if (Length(Candidates) > 1) and (FOverload = '') then
    FOverload := ARoutine.Signature;
  if not FOptions.Conversions then
    Exit;
  for Index := 1 to ANode.ChildCount - 1 do
  begin
    if Index - 1 > High(ARoutine.ParamTypes) then
      Break;
    if ARoutine.ParamTypes[Index - 1] = '' then
      Continue;
    // Typen der Argumente ohne deren eigene Umwandlungen: die gehören zu Teilausdrücken.
    Saved := FConversions;
    Argument := TypeNode(ANode[Index]);
    FConversions := Saved;
    Parameter := FromText(Substitute(ARoutine.ParamTypes[Index - 1], Unqualified(FResolver, ARoutine.Bindings)),
      ARoutine);
    if Argument.Known and Parameter.Known then
      NoteOperand(ANode[Index], Argument, Parameter, False);
  end;
end;

function TExpressionTypes.TypeUnary(ANode: TSyntaxNode): TTyped;
var
  Operand: TTyped;
begin
  Result := Default(TTyped);
  if ANode.ChildCount <> 1 then
    Exit;
  Operand := TypeNode(ANode[0]);
  if not Operand.Known then
    Exit(Operand);
  if ANode.Name = '@' then
    Exit(Typed('Pointer'));
  if SameText(ANode.Name, 'not') then
  begin
    if not (Operand.Category in [TExpressionCategory.Boolean_, TExpressionCategory.Integer_,
      TExpressionCategory.Variant_]) then
      Exit(Failed(TExpressionErrorKind.OperatorMismatch, 'not||' + Operand.Name));
    Exit(Operand);
  end;
  if not (IsNumeric(Operand) or (Operand.Category = TExpressionCategory.Variant_)) then
    Exit(Failed(TExpressionErrorKind.OperatorMismatch, ANode.Name + '||' + Operand.Name));
  // -Byte rechnet als Integer.
  if (Operand.Category = TExpressionCategory.Integer_) and (Operand.Width < 4) then
    Exit(Typed('Integer'));
  Result := Operand;
end;

function TExpressionTypes.TypeSet(ANode: TSyntaxNode): TTyped;
var
  Element: TTyped;
  First: TSyntaxNode;
begin
  if ANode.ChildCount = 0 then
    Exit(Typed('set of ()'));
  First := ANode[0];
  if (First.Kind = TSyntaxKind.RangeExpr) and (First.ChildCount > 0) then
    First := First[0];
  Element := TypeNode(First);
  if not Element.Known then
    Exit(Element);
  // Zahlen in einer Menge sind Byte-Werte.
  if Element.Category = TExpressionCategory.Integer_ then
    Element := Typed('Byte');
  Result := Typed('set of ' + Element.Name);
  Result.Category := TExpressionCategory.Set_;
end;

function TExpressionTypes.TypeAnonymous(ANode: TSyntaxNode): TTyped;
var
  Tokens: TArray<TPascalToken>;
  Index, Depth: Integer;
  Header: string;
begin
  // Kopf bis zum ersten begin bzw. Deklarationsabschnitt außerhalb der Klammern.
  Tokens := FTree.Tokens;
  Header := '';
  Depth := 0;
  for Index := 0 to High(Tokens) do
  begin
    if Tokens[Index].Offset < ANode.StartOffset then
      Continue;
    if Tokens[Index].Offset >= ANode.EndOffset then
      Break;
    if Tokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive] then
      Continue;
    if Tokens[Index].IsSymbol('(') then
      Inc(Depth)
    else if Tokens[Index].IsSymbol(')') then
      Dec(Depth);
    if (Depth = 0) and (Tokens[Index].IsKeyword('begin') or Tokens[Index].IsKeyword('var') or
      Tokens[Index].IsKeyword('const') or Tokens[Index].IsKeyword('type') or Tokens[Index].IsKeyword('label')) then
      Break;
    if (Header <> '') and not Tokens[Index].IsSymbol('(') and not Tokens[Index].IsSymbol(')') and
      not Tokens[Index].IsSymbol(',') and not Tokens[Index].IsSymbol(';') and not Tokens[Index].IsSymbol(':') and
      not EndsStr('(', Header) then
      Header := Header + ' ';
    if Tokens[Index].IsSymbol(':') or Tokens[Index].IsSymbol(',') or Tokens[Index].IsSymbol(';') then
      Header := Header + Tokens[Index].Text + ' '
    else
      Header := Header + Tokens[Index].Text;
  end;
  Header := StringReplace(Trim(Header), '  ', ' ', [rfReplaceAll]);
  Result := Typed('reference to ' + Header);
end;

function TExpressionTypes.FieldSize(const ATypeText: string; out ASize, AAlign: Integer): Boolean;
var
  Lowest, Highest: Int64;
  HighKnown: Boolean;
  Name: string;
begin
  Name := Trim(ATypeText);
  if SameText(Name, 'Double') or SameText(Name, 'Int64') or SameText(Name, 'UInt64') or
    SameText(Name, 'Currency') or SameText(Name, 'Comp') then
  begin
    ASize := 8;
    AAlign := 8;
    Exit(True);
  end;
  if SameText(Name, 'Single') then
  begin
    ASize := 4;
    AAlign := 4;
    Exit(True);
  end;
  if TOrdinalConstants.FixedType(Name, Lowest, Highest, HighKnown, ASize) then
  begin
    AAlign := ASize;
    Exit(True);
  end;
  Result := RecordSize(Name, ASize, AAlign);
end;

function TExpressionTypes.RecordSize(const ATypeName: string; out ASize, AAlign: Integer): Boolean;
var
  Decl, Body: TSyntaxNode;
  IsPacked, Failed_: Boolean;
  Size, Align: Integer;
  Tokens: TArray<TPascalToken>;
  Index: Integer;

  procedure AddFields(AParent: TSyntaxNode);
  var
    Child, TypeRef: TSyntaxNode;
    Names: TArray<string>;
    FieldBytes, FieldAlign, Count, ChildIndex: Integer;
  begin
    for ChildIndex := 0 to AParent.ChildCount - 1 do
    begin
      Child := AParent[ChildIndex];
      if Failed_ then
        Exit;
      case Child.Kind of
        TSyntaxKind.Visibility:
          AddFields(Child);
        TSyntaxKind.Field:
          begin
            TypeRef := Child.FindChild(TSyntaxKind.TypeReference);
            if (TypeRef = nil) or (FDepth > MaxDepth) then
            begin
              Failed_ := True;
              Exit;
            end;
            Inc(FDepth);
            try
              if not FieldSize(TIndexExtractor.TypeText(TypeRef), FieldBytes, FieldAlign) then
              begin
                Failed_ := True;
                Exit;
              end;
            finally
              Dec(FDepth);
            end;
            Names := Child.Name.Split([',']);
            for Count := 1 to Length(Names) do
            begin
              if IsPacked then
                FieldAlign := 1;
              if (FieldAlign > 1) and (Size mod FieldAlign <> 0) then
                Inc(Size, FieldAlign - Size mod FieldAlign);
              Inc(Size, FieldBytes);
              Align := Max(Align, FieldAlign);
            end;
          end;
        TSyntaxKind.VariantPart:
          Failed_ := True;
      end;
    end;
  end;

begin
  Result := False;
  ASize := 0;
  AAlign := 1;
  Decl := FindRecord(FTree.Root, ATypeName);
  if Decl = nil then
    Exit;
  Body := Decl.FindChild(TSyntaxKind.RecordType);
  // packed record: das Token vor record.
  IsPacked := False;
  Tokens := FTree.Tokens;
  for Index := 1 to High(Tokens) do
    if (Tokens[Index].Offset >= Body.StartOffset) and Tokens[Index].IsKeyword('record') then
    begin
      IsPacked := (Index > 0) and Tokens[Index - 1].IsKeyword('packed');
      Break;
    end;
  Size := 0;
  Align := 1;
  Failed_ := False;
  AddFields(Body);
  if Failed_ or (Size = 0) then
    Exit;
  if not IsPacked and (Size mod Align <> 0) then
    Inc(Size, Align - Size mod Align);
  ASize := Size;
  AAlign := Align;
  if IsPacked then
    AAlign := 1;
  Result := True;
end;

function TExpressionTypes.Evaluate(ANode: TSyntaxNode; out AValue: Int64): Boolean;
var
  Values: TConstantValues;
  Left, Right: Int64;
  Size, Align: Integer;
  Operator: string;
begin
  Result := False;
  AValue := 0;
  if (ANode = nil) or (FDepth > MaxDepth) then
    Exit;
  Inc(FDepth);
  try
    // SizeOf eines Records derselben Unit.
    if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 2) and (ANode[0].Kind = TSyntaxKind.Identifier) and
      SameText(ANode[0].Name, 'SizeOf') and (ANode[1].Kind = TSyntaxKind.Identifier) and
      RecordSize(ANode[1].Name, Size, Align) then
    begin
      AValue := Size;
      Exit(True);
    end;
    if (ANode.Kind = TSyntaxKind.ParenExpr) and (ANode.ChildCount = 1) then
      Exit(Evaluate(ANode[0], AValue));
    if (ANode.Kind = TSyntaxKind.BinaryExpr) and (ANode.ChildCount = 2) then
    begin
      Operator := LowerCase(ANode.Name);
      if MatchStr(Operator, ['+', '-', '*', 'div', 'mod', 'shl', 'shr', 'and', 'or', 'xor']) and
        Evaluate(ANode[0], Left) and Evaluate(ANode[1], Right) then
      begin
        try
          if Operator = '+' then
            AValue := Left + Right
          else if Operator = '-' then
            AValue := Left - Right
          else if Operator = '*' then
            AValue := Left * Right
          else if (Operator = 'div') and (Right <> 0) then
            AValue := Left div Right
          else if (Operator = 'mod') and (Right <> 0) then
            AValue := Left mod Right
          else if Operator = 'shl' then
            AValue := Left shl Right
          else if Operator = 'shr' then
            AValue := Left shr Right
          else if Operator = 'and' then
            AValue := Left and Right
          else if Operator = 'or' then
            AValue := Left or Right
          else if Operator = 'xor' then
            AValue := Left xor Right
          else
            Exit(False);
        except
          on EIntOverflow do
            Exit(False);
        end;
        Exit(True);
      end;
    end;
    Values := TConstantValues.Create(FTree, FFileName, FIndex, FResolver);
    try
      Result := Values.EvaluateNode(ANode, AValue);
    finally
      Values.Free;
    end;
  finally
    Dec(FDepth);
  end;
end;

function TExpressionTypes.Describe(ANode: TSyntaxNode): TExpressionTypeInfo;
var
  Found, Target: TTyped;
  Saved: TArray<TExpressionConversion>;
  Value: Int64;
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
  Result.Expression := Short(ANode);
  Found := TypeNode(ANode);
  if not Found.Known then
  begin
    Result.Error := Found.Error;
    if Result.Error = TExpressionErrorKind.None then
      Result.Error := TExpressionErrorKind.Unknown;
    Result.ErrorDetail := Found.ErrorDetail;
    if Result.ErrorDetail = '' then
      Result.ErrorDetail := Result.Expression;
    Exit;
  end;
  Result.TypeName := Found.Name;
  Result.BaseName := Found.Base;
  if (Found.Symbol.Name <> '') and not Found.Symbol.Builtin and (Found.Symbol.FileName <> '') then
  begin
    Result.TypeFile := Found.Symbol.FileName;
    Result.TypeLine := Found.Symbol.SelectionRange.StartPos.Line;
    Result.TypeCharacter := Found.Symbol.SelectionRange.StartPos.Character;
  end;
  // Rechte Seite einer Zuweisung: Umwandlung in den Typ des Ziels (Variant → string).
  if FOptions.Conversions and (ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.AssignStatement) and
    (ANode.Parent.ChildCount = 2) and (ANode.Parent[1] = ANode) then
  begin
    Saved := FConversions;
    Target := TypeNode(ANode.Parent[0]);
    FConversions := Saved;
    if Target.Known then
      NoteOperand(ANode, Found, Target, True);
  end;
  Result.Conversions := FConversions;
  Result.Overload := FOverload;
  // Wert nur für Rechnungen und Namen, nicht für das Literal selbst.
  if FOptions.ConstValue and (ANode.Kind <> TSyntaxKind.Literal) and
    (Found.Category in [TExpressionCategory.Integer_, TExpressionCategory.Char_, TExpressionCategory.Boolean_]) then
  begin
    FDepth := 0;
    Result.HasValue := Evaluate(ANode, Value);
    if Result.HasValue then
      Result.Value := Value;
  end;
end;

function TExpressionTypes.DescribeAt(AStart, AEnd: Integer; AExpand: Boolean): TExpressionTypeInfo;
begin
  Result := Describe(FindExpression(FTree, AStart, AEnd, AExpand));
end;

end.
