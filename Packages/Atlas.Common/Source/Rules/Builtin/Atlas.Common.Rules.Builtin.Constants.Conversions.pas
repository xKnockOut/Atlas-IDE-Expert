unit Atlas.Common.Rules.Builtin.Constants.Conversions;

// Regeln zu Zahltypen in Ausdrücken und Zuweisungen (Teil von Atlas.Common.Rules.Builtin.Constants, dort
// registriert; Beschreibung dort): signed-unsigned-mix, narrowing-assignment, string-length-limit.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract;

const
  cSignedUnsignedMixRuleId = 'signed-unsigned-mix';
  cNarrowingAssignmentRuleId = 'narrowing-assignment';
  cStringLengthLimitRuleId = 'string-length-limit';

type
  TSignedUnsignedMixRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TNarrowingAssignmentRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Einheitlicher Name eines eingebauten Zahltyps (LongInt → integer, DWORD → cardinal, Real →
    /// double); sonst der Name in Kleinbuchstaben ohne "System.".</summary>
    class function CanonicalTypeName(const ATypeName: string): string; static;
    /// <summary>Vorgabe der Option types: Int64>Integer und NativeInt>Integer.</summary>
    class function DefaultTypes: TArray<string>; static;
  end;

  TStringLengthLimitRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Zeichen eines String-Literals wie im Quelltext ('ab''c'#13 → 5); ALongest ist das längste
    /// Stück in Anführungszeichen. -1, wenn der Text kein einfaches Literal ist (z. B. mehrzeilig).</summary>
    class function LiteralLength(const AText: string; out ALongest: Integer): Integer; static;
    /// <summary>Länge N von string[N] bzw. 255 bei ShortString in einem Typ- oder Signaturtext; 0 sonst.
    /// </summary>
    class function ShortStringLength(const AText: string): Integer; static;
  end;


implementation

uses
  Atlas.Common.Index.NameFacts,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.OrdinalConstants,
  Atlas.Common.Semantics.ConstantValues,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Builtin.Constants.Types,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TConstantsConversionsText = (SignTitle, ComparedUnsigned, MixedUnsigned, ComparedInt64, MixedInt64, Value, CastInt64,
    LossTitle, LikeW1066, LikeW1072, TheValue, MayLose, StringTitle, DeclareString, Truncated, ResourceTooLong,
    SplitLiteral, LiteralTooLong, CastExplicitly, WidenTarget);

const
  cTexts: array[TConstantsConversionsText] of TAtlasText = (
    (De: 'Vorzeichenbehaftet und vorzeichenlos gemischt'; En: 'Signed and unsigned mixed'),
    (De: '%s und %s verglichen: ein negativer Wert in %s wird vorzeichenlos verglichen (wie W1023).';
     En: '%s and %s compared: a negative value in %s is compared as unsigned (like W1023).'),
    (De: '%s und %s gemischt: ein negativer Wert in %s wird vorzeichenlos gerechnet (wie W1073).';
     En: '%s and %s mixed: a negative value in %s is calculated as unsigned (like W1073).'),
    (De: '%s und %s verglichen: beide Operanden werden auf Int64 erweitert (wie W1023).';
     En: '%s and %s compared: both operands are extended to Int64 (like W1023).'),
    (De: '%s und %s gemischt: beide Operanden werden auf Int64 erweitert (wie W1024).';
     En: '%s and %s mixed: both operands are extended to Int64 (like W1024).'),
    (De: 'Wert'; En: 'Value'),
    (De: '%s in Int64 umwandeln'; En: 'Cast %s to Int64'),
    (De: 'Zuweisung mit möglichem Datenverlust'; En: 'Assignment with possible data loss'),
    (De: ' (wie W1066)'; En: ' (like W1066)'),
    (De: ' (wie W1072)'; En: ' (like W1072)'),
    (De: 'Der Wert'; En: 'The value'),
    (De: '%s ist %s; die Zuweisung an %s kann Daten verlieren%s.';
     En: '%s is %s; the assignment to %s can lose data%s.'),
    (De: 'String-Grenze überschritten'; En: 'String limit exceeded'),
    (De: 'Als string deklarieren'; En: 'Declare as string'),
    (De: 'Das Literal hat %d Zeichen und wird auf %d gekürzt (wie W1014).';
     En: 'The literal has %d characters and is truncated to %d (like W1014).'),
    (De: 'Der resourcestring %s hat %d Zeichen; Windows erlaubt höchstens %d (wie E2381).';
     En: 'The resourcestring %s has %d characters; Windows allows at most %d (like E2381).'),
    (De: 'Literal teilen'; En: 'Split literal'),
    (De: 'Das Literal hat %d Zeichen in Anführungszeichen; vor Delphi 12 sind höchstens %d erlaubt (wie E2056).';
     En: 'The literal has %d characters in quotes; before Delphi 12 at most %d are allowed (like E2056).'),
    (De: 'Ausdrücklich in %s umwandeln'; En: 'Cast explicitly to %s'),
    (De: 'Zieltyp auf %s vergrößern'; En: 'Widen the target type to %s'));

{$SCOPEDENUMS OFF}

{ TSignedUnsignedMixRule }

function TSignedUnsignedMixRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cSignedUnsignedMixRuleId, TRuleSeverity.Warning,
    cTexts[TConstantsConversionsText.SignTitle].Text);
end;

/// <summary>Vergleich oder Rechnung, in der dcc Vorzeichen mischt? AComparison sagt, ob es ein Vergleich ist.
/// </summary>
function IsMixOperator(const AName: string; out AComparison: Boolean): Boolean;
begin
  AComparison := MatchStr(AName, ['=', '<>', '<', '>', '<=', '>=']);
  Result := AComparison or MatchText(AName, ['+', '-', '*', 'div', 'mod']);
end;

/// <summary>Meldung zur Mischung eines Operanden mit Vorzeichen (ASignedType, Text ASignedText) und eines
/// vorzeichenlosen (AUnsignedType mit AUnsignedBits Bit).</summary>
function MixMessage(AComparison: Boolean; AUnsignedBits: Integer; const ASignedType, AUnsignedType,
  ASignedText: string): string;
begin
  if (AUnsignedBits = 64) and AComparison then
  begin
    Result := cTexts[TConstantsConversionsText.ComparedUnsigned].Fmt([ASignedType, AUnsignedType, ASignedText]);
  end
  else if AUnsignedBits = 64 then
  begin
    Result := cTexts[TConstantsConversionsText.MixedUnsigned].Fmt([ASignedType, AUnsignedType, ASignedText]);
  end
  else if AComparison then
  begin
    Result := cTexts[TConstantsConversionsText.ComparedInt64].Fmt([ASignedType, AUnsignedType]);
  end
  else
  begin
    Result := cTexts[TConstantsConversionsText.MixedInt64].Fmt([ASignedType, AUnsignedType]);
  end;
end;

procedure TSignedUnsignedMixRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
type
  TOperandKinds = array[0..1] of TIntegerKind;
  TOperandTypes = array[0..1] of string;
const
  // Kürzer gehaltene Operanden erscheinen mit Namen in der Meldung.
  cMaxOperandText = 30;
var
  mFileName: string;
  mResolver: TNameResolver;
  mCache: IRuleDerivedCache;
  // Vorfilter vor der Namensauflösung: Namen mit vorzeichenlosem Typ.
  mUnsignedNames: TTypedNames;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  procedure EnsureResolver;
  begin
    if mResolver = nil then
    begin
      // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
      mCache := TRuleDerived.Open(AContext);
      mResolver := TRuleDerived.Resolver(mCache, AContext);
      mResolver.PinTree(AContext.Tree, mFileName);
    end;
  end;

  /// <summary>Typen beider Operanden von ANode; False, wenn einer nicht sicher bekannt ist oder beide dasselbe
  /// Vorzeichen haben.</summary>
  function OperandKinds(ANode: TSyntaxNode; out AKinds: TOperandKinds; out ATypes: TOperandTypes): Boolean;
  begin
    EnsureResolver;
    Result := OperandKind(mResolver, AContext.Tree, mFileName, ANode[0], AKinds[0], ATypes[0]) and
      OperandKind(mResolver, AContext.Tree, mFileName, ANode[1], AKinds[1], ATypes[1]) and
      (AKinds[0].Signed <> AKinds[1].Signed);
  end;

  procedure CheckMix(ANode: TSyntaxNode);
  var
    mComparison: Boolean;
    mKinds: TOperandKinds;
    mTypes: TOperandTypes;
    mSigned, mUnsigned: Integer;
    mSignedText: string;
    mUnsignedNode: TSyntaxNode;
  begin
    if (ANode.ChildCount <> 2) or not IsMixOperator(ANode.Name, mComparison) or
      (not mUnsignedNames.Suspect(OperandName(ANode[0])) and not mUnsignedNames.Suspect(OperandName(ANode[1]))) or
      not OperandKinds(ANode, mKinds, mTypes) then
    begin
      Exit;
    end;
    mSigned := 1;
    if mKinds[0].Signed then
    begin
      mSigned := 0;
    end;
    mUnsigned := 1 - mSigned;
    // Byte und Word passen in Integer, Cardinal passt in Int64: dann rechnet Delphi ohne Warnung.
    if (mKinds[mUnsigned].Bits < 32) or ((mKinds[mUnsigned].Bits = 32) and (mKinds[mSigned].Bits = 64)) then
    begin
      Exit;
    end;
    mSignedText := NodeText(ANode[mSigned]);
    if (Length(mSignedText) > cMaxOperandText) or (Pos(#10, mSignedText) > 0) then
    begin
      mSignedText := cTexts[TConstantsConversionsText.Value].Text;
    end;
    mUnsignedNode := ANode[mUnsigned];
    AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), MixMessage(mComparison, mKinds[mUnsigned].Bits,
      mTypes[mSigned], mTypes[mUnsigned], mSignedText), TRuleConfidence.Medium,
      [TRuleFix.Create(cTexts[TConstantsConversionsText.CastInt64].Fmt([NodeText(mUnsignedNode)]),
      [TTextEdit.Create(TTextRange.Create(mUnsignedNode.StartPos, mUnsignedNode.EndPos),
      'Int64(' + NodeText(mUnsignedNode) + ')')])]);
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (tiefe Bäume sprengen den Stapel nicht).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind = TSyntaxKind.BinaryExpr then
        begin
          CheckMix(mNode);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mFileName := AContext.FileName;
  if mFileName = '' then
  begin
    mFileName := AContext.RelativePath;
  end;
  if mFileName = '' then
  begin
    mFileName := AContext.UnitName + '.pas';
  end;
  mResolver := nil;
  mUnsignedNames := TTypedNames.Create(AContext, ['Cardinal', 'UInt64']);
  try
    Visit(AContext.Tree.Root);
  finally
    if mResolver <> nil then
    begin
      mResolver.UnpinTree;
    end;
    mUnsignedNames.Free;
  end;
end;

{ TNarrowingAssignmentRule }

function TNarrowingAssignmentRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cNarrowingAssignmentRuleId, TRuleSeverity.Warning,
    cTexts[TConstantsConversionsText.LossTitle].Text);
end;

class function TNarrowingAssignmentRule.DefaultTypes: TArray<string>;
begin
  Result := ['Int64>Integer', 'NativeInt>Integer'];
end;

class function TNarrowingAssignmentRule.CanonicalTypeName(const ATypeName: string): string;
begin
  Result := Atlas.Common.Rules.Builtin.Constants.Types.CanonicalTypeName(ATypeName);
end;

/// <summary>Ist der einheitliche Typname ein Gleitkommatyp?</summary>
function IsFloatName(const ACanonical: string): Boolean;
begin
  Result := (ACanonical = 'single') or (ACanonical = 'double') or (ACanonical = 'extended') or
    (ACanonical = 'real48') or (ACanonical = 'comp') or (ACanonical = 'currency');
end;

/// <summary>Breite eines ganzzahligen Typs für Rechnungen: 0 = kein ganzzahliger Typ, 32 = bis 32 Bit,
/// 48 = NativeInt/NativeUInt (plattformabhängig), 64 = Int64/UInt64.</summary>
function IntegerWidth(const ACanonical: string): Integer;
begin
  Result := 0;
  if (ACanonical = 'int64') or (ACanonical = 'uint64') then
  begin
    Result := 64;
  end
  else if (ACanonical = 'nativeint') or (ACanonical = 'nativeuint') then
  begin
    Result := 48;
  end
  else if IntegerKindOf(ACanonical).Bits > 0 then
  begin
    Result := 32;
  end;
end;

type
  /// <summary>Typ eines Ausdrucks: einheitlicher Name und Name wie deklariert.</summary>
  TNumericType = record
    Canonical: string;
    Display: string;
  end;

/// <summary>Hängt der Typ von ANode von seinen Operanden ab (Klammer, Vorzeichen, ganzzahlige Rechnung)?</summary>
function TypeFollowsOperands(ANode: TSyntaxNode): Boolean;
begin
  case ANode.Kind of
    TSyntaxKind.ParenExpr:
      Result := ANode.ChildCount = 1;
    TSyntaxKind.UnaryExpr:
      Result := (ANode.ChildCount = 1) and MatchStr(ANode.Name, ['-', '+']);
    TSyntaxKind.BinaryExpr:
      Result := (ANode.ChildCount = 2) and MatchText(ANode.Name, ['+', '-', '*', 'div', 'mod', 'and', 'or', 'xor']);
  else
    Result := False;
  end;
end;

/// <summary>Legt ANode für die Nachordnung zurück und, wenn AWithOperands, davor seine Operanden.</summary>
procedure PushPostOrder(APending: TStack<TSyntaxPostOrderEntry>; ANode: TSyntaxNode; AWithOperands: Boolean);
var
  mIndex: Integer;
begin
  APending.Push(TSyntaxPostOrderEntry.Create(ANode, True));
  if not AWithOperands then
  begin
    Exit;
  end;
  for mIndex := ANode.ChildCount - 1 downto 0 do
  begin
    APending.Push(TSyntaxPostOrderEntry.Create(ANode[mIndex], False));
  end;
end;

/// <summary>Typ einer ganzzahligen Rechnung aus den bekannten Typen der Operanden; die breitere Seite bestimmt
/// ihn.</summary>
function ArithmeticType(ANode: TSyntaxNode; AKnown: TDictionary<TSyntaxNode, TNumericType>;
  out AType: TNumericType): Boolean;
var
  mLeft, mRight: TNumericType;
begin
  AType := Default(TNumericType);
  Result := TypeFollowsOperands(ANode) and AKnown.TryGetValue(ANode[0], mLeft) and
    AKnown.TryGetValue(ANode[1], mRight) and (IntegerWidth(mLeft.Canonical) > 0) and
    (IntegerWidth(mRight.Canonical) > 0);
  if not Result then
  begin
    Exit;
  end;
  AType := mLeft;
  if IntegerWidth(mRight.Canonical) > IntegerWidth(mLeft.Canonical) then
  begin
    AType := mRight;
  end;
end;

/// <summary>Paare "quelle>ziel" aus APairs in einheitlichen Namen nach ATarget; liefert die Quelltypen.</summary>
function ReadPairs(const APairs: TArray<string>; ATarget: TDictionary<string, Boolean>): TArray<string>;
var
  mPair, mSourceName, mTargetName: string;
  mSeparator, mCount: Integer;
begin
  SetLength(Result, Length(APairs));
  mCount := 0;
  for mPair in APairs do
  begin
    mSeparator := Pos('>', mPair);
    mSourceName := CanonicalTypeName(Copy(mPair, 1, mSeparator - 1));
    mTargetName := CanonicalTypeName(Copy(mPair, mSeparator + 1, MaxInt));
    if (mSeparator > 0) and (mSourceName <> '') and (mTargetName <> '') then
    begin
      ATarget.AddOrSetValue(mSourceName + '>' + mTargetName, True);
      Result[mCount] := mSourceName;
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

procedure TNarrowingAssignmentRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
const
  cMaxValueText = 30;
var
  mFileName: string;
  mResolver: TNameResolver;
  mCache: IRuleDerivedCache;
  mSources: TTypedNames;
  // Paare "quelle>ziel" in einheitlichen Namen.
  mPairs: TDictionary<string, Boolean>;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  procedure EnsureResolver;
  begin
    if mResolver = nil then
    begin
      // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
      mCache := TRuleDerived.Open(AContext);
      mResolver := TRuleDerived.Resolver(mCache, AContext);
      mResolver.PinTree(AContext.Tree, mFileName);
    end;
  end;

  /// <summary>Einheitlicher Name des Typs ATypeName; eigene Aliase über den aufgelösten Typ
  /// (ATypeInfo aus NodeType bzw. ResolveType).</summary>
  function Canonical(const ATypeName: string; const ATypeInfo: TResolvedSymbol; ATypeFound: Boolean): string;
  var
    mBody: string;
  begin
    Result := CanonicalTypeName(ATypeName);
    if (IntegerWidth(Result) > 0) or IsFloatName(Result) or not ATypeFound then
    begin
      Exit;
    end;
    // Aufgelöst ist entweder der Zieltyp selbst (Integer) oder der Alias mit Signatur (TZahl = Integer).
    mBody := CanonicalTypeName(ATypeInfo.Name);
    if (IntegerWidth(mBody) = 0) and not IsFloatName(mBody) then
    begin
      mBody := CanonicalTypeName(TypeBodyOf(ATypeInfo.Signature));
    end;
    if (IntegerWidth(mBody) > 0) or IsFloatName(mBody) then
    begin
      Result := mBody;
    end;
  end;

  /// <summary>Typ eines Namens, Aufrufs oder Elements mit sicher bekanntem Zahltyp.</summary>
  function NamedType(ANode: TSyntaxNode; out AType: TNumericType): Boolean;
  var
    mSymbol, mTypeInfo: TResolvedSymbol;
    mTypeFound: Boolean;
  begin
    AType := Default(TNumericType);
    EnsureResolver;
    Result := mResolver.NodeType(AContext.Tree, mFileName, ANode, mSymbol, mTypeInfo, mTypeFound) and
      (mSymbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field, TIndexSymbolKind.Property_,
      TIndexSymbolKind.Method, TIndexSymbolKind.Routine, TIndexSymbolKind.Constant]) and (mSymbol.TypeName <> '');
    if Result then
    begin
      AType.Canonical := Canonical(mSymbol.TypeName, mTypeInfo, mTypeFound);
      AType.Display := mSymbol.TypeName;
      Result := (IntegerWidth(AType.Canonical) > 0) or IsFloatName(AType.Canonical);
    end;
  end;

  /// <summary>Kleine ganze Zahl innerhalb einer Rechnung: Integer, sie ändert die Breite nicht.</summary>
  function LiteralType(ANode: TSyntaxNode; out AType: TNumericType): Boolean;
  var
    mValue: Int64;
  begin
    AType := Default(TNumericType);
    Result := TOrdinalConstants.Evaluate(NodeText(ANode), nil, mValue) and (mValue >= Low(Integer)) and
      (mValue <= High(Integer));
    if Result then
    begin
      AType.Canonical := 'integer';
      AType.Display := 'Integer';
    end;
  end;

  /// <summary>Typ von ANode, wenn die Typen der Operanden schon in AKnown stehen.</summary>
  function KnownType(ANode: TSyntaxNode; AKnown: TDictionary<TSyntaxNode, TNumericType>;
    out AType: TNumericType): Boolean;
  begin
    AType := Default(TNumericType);
    case ANode.Kind of
      TSyntaxKind.ParenExpr, TSyntaxKind.UnaryExpr:
        Result := TypeFollowsOperands(ANode) and AKnown.TryGetValue(ANode[0], AType);
      TSyntaxKind.Literal:
        Result := LiteralType(ANode, AType);
      TSyntaxKind.BinaryExpr:
        Result := ArithmeticType(ANode, AKnown, AType);
      TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.Call, TSyntaxKind.IndexAccess:
        Result := NamedType(ANode, AType);
    else
      Result := False;
    end;
  end;

  /// <summary>Typ des Ausdrucks ANode: Operand mit sicher bekanntem Typ oder ganzzahlige Rechnung daraus.
  /// ADisplay ist der Typ wie deklariert; False, wenn er nicht sicher bekannt ist.</summary>
  function ExpressionType(ANode: TSyntaxNode; out ACanonical, ADisplay: string): Boolean;
  var
    mEntry: TSyntaxPostOrderEntry;
    mType: TNumericType;
    mPending: TStack<TSyntaxPostOrderEntry>;
    mKnown: TDictionary<TSyntaxNode, TNumericType>;
  begin
    // Iterativ (tiefe Bäume sprengen den Stapel nicht): Nachordnung, die Operanden zuerst; lange Rechenketten ergeben
    // sehr tiefe Bäume. Bekannte Typen stehen in mKnown, unbekannte fehlen dort.
    mPending := TStack<TSyntaxPostOrderEntry>.Create;
    mKnown := TDictionary<TSyntaxNode, TNumericType>.Create;
    try
      mPending.Push(TSyntaxPostOrderEntry.Create(ANode, False));
      while mPending.Count > 0 do
      begin
        mEntry := mPending.Pop;
        if not mEntry.Done then
        begin
          PushPostOrder(mPending, mEntry.Node, TypeFollowsOperands(mEntry.Node));
        end
        else if KnownType(mEntry.Node, mKnown, mType) then
        begin
          mKnown.AddOrSetValue(mEntry.Node, mType);
        end;
      end;
      Result := mKnown.TryGetValue(ANode, mType);
      ACanonical := mType.Canonical;
      ADisplay := mType.Display;
    finally
      mKnown.Free;
      mPending.Free;
    end;
  end;

  /// <summary>Kann der Ausdruck einen Quelltyp aus den Paaren haben (Vorfilter ohne Namensauflösung)?</summary>
  function MaySource(ANode: TSyntaxNode): Boolean;
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (tiefe Bäume sprengen den Stapel nicht).
    Result := False;
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ANode);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.Call,
          TSyntaxKind.IndexAccess] then
        begin
          if mSources.Suspect(OperandName(mNode)) then
          begin
            Exit(True);
          end;
        end
        else if mNode.Kind in [TSyntaxKind.ParenExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.BinaryExpr] then
        begin
          for mIndex := mNode.ChildCount - 1 downto 0 do
          begin
            mPending.Push(mNode[mIndex]);
          end;
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

  /// <summary>Typknoten der Deklaration des Ziels in dieser Datei (einzelne Variable oder einzelnes Feld);
  /// nil, wenn die Deklaration woanders steht oder mehrere Namen teilt.</summary>
  function DeclarationTypeNode(const ASymbol: TResolvedSymbol): TSyntaxNode;
  var
    mFound: TSyntaxNode;

    procedure Search(ARoot: TSyntaxNode);
    var
      mIndex: Integer;
      mNode: TSyntaxNode;
      mPending: TStack<TSyntaxNode>;
    begin
      // Iterativ (tiefe Bäume sprengen den Stapel nicht).
      mPending := TStack<TSyntaxNode>.Create;
      try
        mPending.Push(ARoot);
        while mPending.Count > 0 do
        begin
          mNode := mPending.Pop;
          if (mNode.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.Field, TSyntaxKind.InlineVar]) and
            (mNode.ChildCount > 0) and SameText(mNode.Name, ASymbol.Name) and
            (mNode.StartPos.Line = ASymbol.SelectionRange.StartPos.Line) and
            (mNode[0].Kind = TSyntaxKind.TypeReference) then
          begin
            mFound := mNode[0];
            Exit;
          end;
          for mIndex := mNode.ChildCount - 1 downto 0 do
          begin
            mPending.Push(mNode[mIndex]);
          end;
        end;
      finally
        mPending.Free;
      end;
    end;

  begin
    mFound := nil;
    if (ASymbol.FileName = '') or SameText(ASymbol.FileName, mFileName) or
      SameText(ExtractFileName(ASymbol.FileName), ExtractFileName(mFileName)) then
    begin
      Search(AContext.Tree.Root);
    end;
    Result := mFound;
  end;

  procedure Report(AValue: TSyntaxNode; const ATargetDisplay, ATargetCanonical: string;
    ATargetTypeNode: TSyntaxNode);
  var
    mSourceCanonical, mSourceDisplay, mValueText, mCodeSuffix, mMessage: string;
    mFixes: TArray<TRuleFix>;
  begin
    if not MaySource(AValue) or not ExpressionType(AValue, mSourceCanonical, mSourceDisplay) or
      not mPairs.ContainsKey(mSourceCanonical + '>' + ATargetCanonical) then
    begin
      Exit;
    end;
    mCodeSuffix := '';
    if IsFloatName(ATargetCanonical) then
    begin
      if (mSourceCanonical = 'extended') and (ATargetCanonical = 'double') then
      begin
        mCodeSuffix := cTexts[TConstantsConversionsText.LikeW1066].Text;
      end
      else
      begin
        mCodeSuffix := cTexts[TConstantsConversionsText.LikeW1072].Text;
      end;
    end;
    mValueText := NodeText(AValue);
    if (Length(mValueText) > cMaxValueText) or (Pos(#10, mValueText) > 0) then
    begin
      mValueText := cTexts[TConstantsConversionsText.TheValue].Text;
    end;
    mMessage := cTexts[TConstantsConversionsText.MayLose].Fmt([mValueText, mSourceDisplay, ATargetDisplay,
      mCodeSuffix]);
    mFixes := [TRuleFix.Create(cTexts[TConstantsConversionsText.CastExplicitly].Fmt([ATargetDisplay]),
      [TTextEdit.Create(TTextRange.Create(AValue.StartPos, AValue.EndPos),
      ATargetDisplay + '(' + NodeText(AValue) + ')')])];
    if ATargetTypeNode <> nil then
    begin
      mFixes := mFixes + [TRuleFix.Create(cTexts[TConstantsConversionsText.WidenTarget].Fmt([mSourceDisplay]),
        [TTextEdit.Create(TTextRange.Create(ATargetTypeNode.StartPos, ATargetTypeNode.EndPos), mSourceDisplay)])];
    end;
    AReport.Add(TTextRange.Create(AValue.StartPos, AValue.EndPos), mMessage, TRuleConfidence.Medium, mFixes);
  end;

  procedure CheckAssignment(ANode: TSyntaxNode);
  var
    mSymbol, mTypeInfo: TResolvedSymbol;
    mTypeFound: Boolean;
    mTarget: string;
  begin
    if (ANode.ChildCount <> 2) or not MaySource(ANode[1]) then
    begin
      Exit;
    end;
    EnsureResolver;
    if not (ANode[0].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess]) or
      not mResolver.NodeType(AContext.Tree, mFileName, ANode[0], mSymbol, mTypeInfo, mTypeFound) or
      not (mSymbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field,
      TIndexSymbolKind.Property_]) or (mSymbol.TypeName = '') then
    begin
      Exit;
    end;
    mTarget := Canonical(mSymbol.TypeName, mTypeInfo, mTypeFound);
    if (ANode[0].Kind = TSyntaxKind.Identifier) and not mSymbol.IsParameter then
    begin
      Report(ANode[1], mSymbol.TypeName, mTarget, DeclarationTypeNode(mSymbol));
    end
    else
    begin
      Report(ANode[1], mSymbol.TypeName, mTarget, nil);
    end;
  end;

  procedure CheckInlineVar(ANode: TSyntaxNode);
  var
    mTypeInfo: TResolvedSymbol;
    mTypeName: string;
  begin
    if (ANode.ChildCount <> 2) or (ANode[0].Kind <> TSyntaxKind.TypeReference) or (Pos(',', ANode.Name) > 0) or
      not MaySource(ANode[1]) then
    begin
      Exit;
    end;
    EnsureResolver;
    mTypeName := NodeText(ANode[0]);
    mTypeInfo := mResolver.ResolveType(AContext.Tree, mFileName, ANode[0].StartPos);
    Report(ANode[1], mTypeName, Canonical(mTypeName, mTypeInfo, mTypeInfo.Found), ANode[0]);
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (tiefe Bäume sprengen den Stapel nicht).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind = TSyntaxKind.AssignStatement then
        begin
          CheckAssignment(mNode);
        end
        else if mNode.Kind = TSyntaxKind.InlineVar then
        begin
          CheckInlineVar(mNode);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

var
  mSourceNames: TArray<string>;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mFileName := AContext.FileName;
  if mFileName = '' then
  begin
    mFileName := AContext.RelativePath;
  end;
  if mFileName = '' then
  begin
    mFileName := AContext.UnitName + '.pas';
  end;
  mPairs := TDictionary<string, Boolean>.Create;
  mResolver := nil;
  mSources := nil;
  try
    mSourceNames := ReadPairs(TRuleOptions.Strings(AContext.Options, 'types', DefaultTypes), mPairs);
    if mPairs.Count = 0 then
    begin
      Exit;
    end;
    mSources := TTypedNames.Create(AContext, mSourceNames);
    Visit(AContext.Tree.Root);
  finally
    if mResolver <> nil then
    begin
      mResolver.UnpinTree;
    end;
    mSources.Free;
    mPairs.Free;
  end;
end;

{ TStringLengthLimitRule }

function TStringLengthLimitRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cStringLengthLimitRuleId, TRuleSeverity.Warning,
    cTexts[TConstantsConversionsText.StringTitle].Text);
end;

/// <summary>Position hinter dem Stück in Anführungszeichen, das an AStart beginnt; ASegment zählt seine Zeichen.
/// 0, wenn es nicht geschlossen wird.</summary>
function QuotedSegmentEnd(const AText: string; AStart: Integer; out ASegment: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  ASegment := 0;
  mIndex := AStart + 1;
  while mIndex <= Length(AText) do
  begin
    if (AText[mIndex] = '''') and ((mIndex = Length(AText)) or (AText[mIndex + 1] <> '''')) then
    begin
      Exit(mIndex + 1);
    end;
    // Verdoppeltes Anführungszeichen: ein Zeichen.
    if AText[mIndex] = '''' then
    begin
      Inc(mIndex);
    end;
    // Ein Zeichen außerhalb der Basisebene ist ein Element, aber zwei UTF-16-Einheiten.
    if (Ord(AText[mIndex]) < $DC00) or (Ord(AText[mIndex]) > $DFFF) then
    begin
      Inc(ASegment);
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Position hinter dem Zeichencode (#65, #$41), der an AStart beginnt.</summary>
function CharCodeEnd(const AText: string; AStart: Integer): Integer;
var
  mDigits: TSysCharSet;
begin
  Result := AStart + 1;
  mDigits := ['0'..'9'];
  if (Result <= Length(AText)) and (AText[Result] = '$') then
  begin
    Inc(Result);
    mDigits := ['0'..'9', 'a'..'f', 'A'..'F'];
  end;
  while (Result <= Length(AText)) and CharInSet(AText[Result], mDigits) do
  begin
    Inc(Result);
  end;
end;

class function TStringLengthLimitRule.LiteralLength(const AText: string; out ALongest: Integer): Integer;
var
  mIndex, mSegment: Integer;
begin
  Result := 0;
  ALongest := 0;
  // Mehrzeilige Strings (''' … ''') zählen nicht.
  if AText.StartsWith('''''''') then
  begin
    Exit(-1);
  end;
  mIndex := 1;
  while (mIndex <= Length(AText)) and (Result >= 0) do
  begin
    if AText[mIndex] = '''' then
    begin
      mIndex := QuotedSegmentEnd(AText, mIndex, mSegment);
      Inc(Result, mSegment);
      if mSegment > ALongest then
      begin
        ALongest := mSegment;
      end;
      if mIndex = 0 then
      begin
        Result := -1;
      end;
    end
    else if AText[mIndex] = '#' then
    begin
      mIndex := CharCodeEnd(AText, mIndex);
      Inc(Result);
    end
    else
    begin
      Result := -1;
    end;
  end;
end;

/// <summary>Nennt die Deklaration AText (klein) ShortString als ganzes Wort?</summary>
function NamesShortString(const AText: string): Boolean;
var
  mWord: string;
begin
  Result := False;
  for mWord in DeclarationWords(AText) do
  begin
    if (mWord = 'shortstring') or (mWord = 'system.shortstring') then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Position des ersten Zeichens ab AStart, das kein Leerzeichen und kein Tabulator ist.</summary>
function SkipSpaces(const AText: string; AStart: Integer): Integer;
begin
  Result := AStart;
  while (Result <= Length(AText)) and CharInSet(AText[Result], [' ', #9]) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Position von "[" hinter dem ersten ganzen Wort "string", auf das eine eckige Klammer folgt; 0 ohne.
/// </summary>
function FirstStringBracket(const AText: string): Integer;
var
  mStart, mOpen: Integer;
begin
  Result := 0;
  mOpen := Pos('string', AText);
  while (mOpen > 0) and (Result = 0) do
  begin
    mStart := mOpen + Length('string');
    // Ganzes Wort: nicht Teil von "AnsiString" oder "TStringList".
    if (mOpen = 1) or not CharInSet(AText[mOpen - 1], ['a'..'z', '0'..'9', '_', '.']) then
    begin
      mOpen := SkipSpaces(AText, mStart);
      if (mOpen <= Length(AText)) and (AText[mOpen] = '[') then
      begin
        Result := mOpen;
      end;
    end;
    mOpen := PosEx('string', AText, mStart);
  end;
end;

class function TStringLengthLimitRule.ShortStringLength(const AText: string): Integer;
var
  mText: string;
  mOpen, mClose: Integer;
  mValue: Int64;
begin
  Result := 0;
  mText := LowerCase(AText);
  if NamesShortString(mText) then
  begin
    Exit(255);
  end;
  mOpen := FirstStringBracket(mText);
  mClose := 0;
  if mOpen > 0 then
  begin
    mClose := PosEx(']', mText, mOpen);
  end;
  if (mClose > 0) and TOrdinalConstants.Evaluate(Copy(AText, mOpen + 1, mClose - mOpen - 1), nil, mValue) and
    (mValue >= 1) and (mValue <= 255) then
  begin
    Result := Integer(mValue);
  end;
end;

/// <summary>N, wenn ATypeName im Index ein Alias auf string[N]/ShortString ist; 0 sonst. Hängt nur vom Index ab
/// und wird über alle Units des Laufs gemerkt (TIndexNameFacts).</summary>
function IndexShortAlias(const AFacts: IIndexNameFacts; const AIndex: ISymbolIndex; const ATypeName: string): Integer;
var
  mFacts: IIndexNameFacts;
  mIndex: ISymbolIndex;
  mName: string;
begin
  mFacts := AFacts;
  mIndex := AIndex;
  mName := ATypeName;
  Result := TIndexNameFacts.Get(mFacts, mIndex, 'shortAlias:' + UpperCase(mName),
    function: Integer
    var
      mLocations: TArray<TSymbolLocation>;
      mPosition: Integer;
    begin
      Result := 0;
      if mIndex = nil then
      begin
        Exit;
      end;
      mLocations := mIndex.FindSymbols(mName);
      for mPosition := 0 to High(mLocations) do
      begin
        if mLocations[mPosition].Symbol.Kind = TIndexSymbolKind.TypeAlias then
        begin
          Result := TStringLengthLimitRule.ShortStringLength(TypeBodyOf(mLocations[mPosition].Symbol.Signature));
          if Result > 0 then
          begin
            Exit;
          end;
        end;
      end;
    end);
end;

/// <summary>Gibt es im Index eine Variable, ein Feld oder eine Property AName vom Typ string[N]/ShortString oder
/// einem Alias darauf aus dem Index? Wie IndexShortAlias über alle Units gemerkt; lokale Aliase prüft der Aufrufer.
/// </summary>
function IndexShortVariable(const AFacts: IIndexNameFacts; const AIndex: ISymbolIndex; const AName: string): Boolean;
var
  mFacts: IIndexNameFacts;
  mIndex: ISymbolIndex;
  mName: string;
begin
  mFacts := AFacts;
  mIndex := AIndex;
  mName := AName;
  Result := TIndexNameFacts.Get(mFacts, mIndex, 'shortVariable:' + UpperCase(mName),
    function: Integer
    var
      mLocations: TArray<TSymbolLocation>;
      mPosition: Integer;
      mTypeName: string;
    begin
      Result := 0;
      if mIndex = nil then
      begin
        Exit;
      end;
      mLocations := mIndex.FindSymbols(mName);
      for mPosition := 0 to High(mLocations) do
      begin
        if mLocations[mPosition].Symbol.Kind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field,
          TIndexSymbolKind.Property_] then
        begin
          mTypeName := mLocations[mPosition].Symbol.TypeName;
          if (TStringLengthLimitRule.ShortStringLength(mLocations[mPosition].Symbol.Signature) > 0) or
            ((mTypeName <> '') and ((TStringLengthLimitRule.ShortStringLength(mTypeName) > 0) or
            (IsValidIdent(mTypeName, True) and (IndexShortAlias(mFacts, mIndex, mTypeName) > 0)))) then
          begin
            Exit(1);
          end;
        end;
      end;
    end) <> 0;
end;

/// <summary>Klammer um einen Ausdruck oder Verkettung mit +: die Länge folgt aus den Operanden.</summary>
function CombinesLength(ANode: TSyntaxNode): Boolean;
begin
  Result := ((ANode.Kind = TSyntaxKind.ParenExpr) and (ANode.ChildCount = 1)) or
    ((ANode.Kind = TSyntaxKind.BinaryExpr) and (ANode.Name = '+') and (ANode.ChildCount = 2));
end;

/// <summary>Gemerkte Länge von ANode in ALengths; -1, wenn sie unbekannt ist.</summary>
function KnownLength(ALengths: TDictionary<TSyntaxNode, Integer>; ANode: TSyntaxNode): Integer;
begin
  if not ALengths.TryGetValue(ANode, Result) then
  begin
    Result := -1;
  end;
end;

/// <summary>Länge der Klammer oder Verkettung ANode aus den Längen der Operanden in ALengths; -1, wenn eine
/// unbekannt ist.</summary>
function CombinedLength(ANode: TSyntaxNode; ALengths: TDictionary<TSyntaxNode, Integer>): Integer;
var
  mLeft, mRight: Integer;
begin
  if ANode.Kind = TSyntaxKind.ParenExpr then
  begin
    Exit(KnownLength(ALengths, ANode[0]));
  end;
  Result := -1;
  mLeft := KnownLength(ALengths, ANode[0]);
  mRight := KnownLength(ALengths, ANode[1]);
  if (mLeft >= 0) and (mRight >= 0) then
  begin
    Result := mLeft + mRight;
  end;
end;

/// <summary>Nächstes Zeichen des Literals ATokenText ab AIndex wie im Quelltext (verdoppeltes
/// Anführungszeichen, Ersatzpaar zusammen); AIndex rückt dahinter. '' bei einem einzelnen Anführungszeichen.
/// </summary>
function NextLiteralChar(const ATokenText: string; var AIndex: Integer): string;
begin
  if ATokenText[AIndex] = '''' then
  begin
    // Nur verdoppelte Anführungszeichen dürfen innen stehen.
    Result := '';
    if (AIndex + 1 < Length(ATokenText)) and (ATokenText[AIndex + 1] = '''') then
    begin
      Result := '''''';
      Inc(AIndex, 2);
    end;
    Exit;
  end;
  Result := ATokenText[AIndex];
  // Ersatzpaar zusammenhalten.
  if (Ord(ATokenText[AIndex]) >= $D800) and (Ord(ATokenText[AIndex]) <= $DBFF) and
    (AIndex + 1 < Length(ATokenText)) then
  begin
    Inc(AIndex);
    Result := Result + ATokenText[AIndex];
  end;
  Inc(AIndex);
end;

procedure TStringLengthLimitRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
const
  cMaxLiteral = 255;
  cMaxResourceString = 4096;
  // Ab Delphi 12 (BDS 23) dürfen Literale länger sein.
  cLongLiteralVersion = 23;
var
  mFileName: string;
  mResolver: TNameResolver;
  // Namen und Typen mit string[N]/ShortString (Vorfilter vor der Namensauflösung).
  mLocalNames, mShortTypes, mSuspects: TDictionary<string, Boolean>;
  // Werte von Konstanten für string[Laenge]; erst bei Bedarf.
  mValues: TConstantValues;
  // Deklarationen dieser Datei nach Namen (klein), erst bei Bedarf (EnsureDeclarations).
  mDeclarations: TObjectDictionary<string, TList<TSyntaxNode>>;
  mTypeBodies: TDictionary<string, TSyntaxNode>;
  // Hält den Resolver des Laufs (oder einen eigenen Cache ohne Engine).
  mCache: IRuleDerivedCache;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  procedure EnsureResolver;
  begin
    if mResolver = nil then
    begin
      // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
      mCache := TRuleDerived.Open(AContext);
      mResolver := TRuleDerived.Resolver(mCache, AContext);
      mResolver.PinTree(AContext.Tree, mFileName);
    end;
  end;

  /// <summary>Typknoten string[Ausdruck] aus dem Baum: N über die Konstantenwerte (auch string[Laenge]); 0 bei
  /// anderen Typen.</summary>
  function BracketLength(ATypeNode: TSyntaxNode): Integer;
  var
    mValue: Int64;
  begin
    Result := 0;
    if (ATypeNode.Kind <> TSyntaxKind.TypeReference) or not SameText(ATypeNode.Name, 'string') or
      (ATypeNode.ChildCount <> 1) then
    begin
      Exit;
    end;
    EnsureResolver;
    if mValues = nil then
    begin
      mValues := TConstantValues.Create(AContext.Tree, mFileName, AContext.Index, mResolver);
    end;
    if (mValues.Check(ATypeNode[0], mValue) = TOrdinalStatus.Value) and (mValue >= 1) and (mValue <= 255) then
    begin
      Result := Integer(mValue);
    end;
  end;

  /// <summary>Nennt der Typknoten string[…], ShortString oder einen eigenen Alias darauf?</summary>
  function IsShortTypeNode(ATypeNode: TSyntaxNode): Boolean;
  begin
    Result := ((ATypeNode.Kind = TSyntaxKind.TypeReference) and SameText(ATypeNode.Name, 'string') and
      (ATypeNode.ChildCount = 1)) or (ShortStringLength(NodeText(ATypeNode)) > 0) or
      mShortTypes.ContainsKey(LowerCase(Trim(NodeText(ATypeNode))));
  end;

  /// <summary>Zeichen des konstanten String-Ausdrucks ANode (Literale, mit + verkettet); -1 sonst.</summary>
  function ExpressionLength(ANode: TSyntaxNode): Integer;
  var
    mLongest, mChars: Integer;
    mEntry: TSyntaxPostOrderEntry;
    mPending: TStack<TSyntaxPostOrderEntry>;
    mLengths: TDictionary<TSyntaxNode, Integer>;
  begin
    // Iterativ (tiefe Bäume sprengen den Stapel nicht): Nachordnung, die Operanden zuerst; lange Verkettungen ergeben
    // sehr tiefe Bäume.
    mPending := TStack<TSyntaxPostOrderEntry>.Create;
    mLengths := TDictionary<TSyntaxNode, Integer>.Create;
    try
      mPending.Push(TSyntaxPostOrderEntry.Create(ANode, False));
      while mPending.Count > 0 do
      begin
        mEntry := mPending.Pop;
        if not mEntry.Done then
        begin
          PushPostOrder(mPending, mEntry.Node, CombinesLength(mEntry.Node));
          Continue;
        end;
        mChars := -1;
        if mEntry.Node.Kind = TSyntaxKind.Literal then
        begin
          mChars := LiteralLength(NodeText(mEntry.Node), mLongest);
        end
        else if CombinesLength(mEntry.Node) then
        begin
          mChars := CombinedLength(mEntry.Node, mLengths);
        end;
        mLengths.AddOrSetValue(mEntry.Node, mChars);
      end;
      Result := KnownLength(mLengths, ANode);
    finally
      mLengths.Free;
      mPending.Free;
    end;
  end;

  /// <summary>Ist ATypeName ein Alias auf string[N]/ShortString (eigene Datei oder Index)? Liefert N.</summary>
  function AliasLength(const ATypeName: string): Integer;
  begin
    Result := ShortStringLength(ATypeName);
    if (Result > 0) or not IsValidIdent(ATypeName, True) then
    begin
      Exit;
    end;
    if mShortTypes.ContainsKey(LowerCase(ATypeName)) then
    begin
      Exit(1);
    end;
    Result := IndexShortAlias(AContext.NameFacts, AContext.Index, ATypeName);
  end;

  procedure CollectTypes(ARoot: TSyntaxNode);
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (tiefe Bäume sprengen den Stapel nicht).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if (mNode.Kind = TSyntaxKind.TypeDecl) and (mNode.ChildCount > 0) and IsShortTypeNode(mNode[0]) then
        begin
          mShortTypes.AddOrSetValue(LowerCase(mNode.Name), True);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

  procedure CollectLocal(ARoot: TSyntaxNode);
  var
    mIndex: Integer;
    mName: string;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (tiefe Bäume sprengen den Stapel nicht).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if (mNode.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.Field, TSyntaxKind.Parameter, TSyntaxKind.PropertyDecl,
          TSyntaxKind.InlineVar]) and (mNode.ChildCount > 0) and IsShortTypeNode(mNode[0]) then
        begin
          for mName in mNode.Name.Split([',']) do
          begin
            mLocalNames.AddOrSetValue(LowerCase(Trim(mName)), True);
          end;
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

  function Suspect(const AName: string): Boolean;
  var
    mKey: string;
    mLocation: TSymbolLocation;
  begin
    mKey := LowerCase(AName);
    if (mKey = '') or mLocalNames.ContainsKey(mKey) then
    begin
      Exit(mKey <> '');
    end;
    if mSuspects.TryGetValue(mKey, Result) then
    begin
      Exit;
    end;
    Result := False;
    // Ohne eigene Aliase der Datei hängt die Antwort nur vom Index ab: über alle Units gemerkt.
    if mShortTypes.Count = 0 then
    begin
      Result := IndexShortVariable(AContext.NameFacts, AContext.Index, AName);
    end
    else if AContext.Index <> nil then
    begin
      for mLocation in AContext.Index.FindSymbols(AName) do
      begin
        if (mLocation.Symbol.Kind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field,
          TIndexSymbolKind.Property_]) and ((ShortStringLength(mLocation.Symbol.Signature) > 0) or
          ((mLocation.Symbol.TypeName <> '') and (AliasLength(mLocation.Symbol.TypeName) > 0))) then
        begin
          Result := True;
          Break;
        end;
      end;
    end;
    mSuspects.Add(mKey, Result);
  end;

  /// <summary>Merkt die Deklaration ANode unter jedem ihrer Namen (A, B: Integer).</summary>
  procedure AddDeclaration(ANode: TSyntaxNode);
  var
    mName, mKey: string;
    mNodes: TList<TSyntaxNode>;
  begin
    for mName in ANode.Name.Split([',']) do
    begin
      mKey := LowerCase(Trim(mName));
      if not mDeclarations.TryGetValue(mKey, mNodes) then
      begin
        mNodes := TList<TSyntaxNode>.Create;
        mDeclarations.Add(mKey, mNodes);
      end;
      mNodes.Add(ANode);
    end;
  end;

  /// <summary>Einmal je Datei: Typdeklarationen und Deklarationen mit Typ nach Namen, in Baumreihenfolge. Vorher
  /// durchsuchte jede verdächtige Zuweisung den ganzen Baum (Zuweisungen × Knoten, Sekunden bei großen Units).
  /// </summary>
  procedure EnsureDeclarations;
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    if mDeclarations <> nil then
    begin
      Exit;
    end;
    mDeclarations := TObjectDictionary<string, TList<TSyntaxNode>>.Create([doOwnsValues]);
    mTypeBodies := TDictionary<string, TSyntaxNode>.Create;
    // Iterativ (tiefe Bäume sprengen den Stapel nicht); Vorordnung wie die frühere Suche, damit der erste Treffer
    // gleich bleibt.
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(AContext.Tree.Root);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if (mNode.Kind = TSyntaxKind.TypeDecl) and (mNode.ChildCount > 0) and
          not mTypeBodies.ContainsKey(LowerCase(mNode.Name)) then
        begin
          mTypeBodies.Add(LowerCase(mNode.Name), mNode[0]);
        end;
        if (mNode.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.InlineVar, TSyntaxKind.ConstDecl, TSyntaxKind.Field,
          TSyntaxKind.Parameter]) and (mNode.ChildCount > 0) then
        begin
          AddDeclaration(mNode);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

  /// <summary>Typknoten hinter "=" der Typdeklaration ATypeName in dieser Datei; nil sonst.</summary>
  function LocalTypeBody(const ATypeName: string): TSyntaxNode;
  begin
    EnsureDeclarations;
    if not mTypeBodies.TryGetValue(LowerCase(ATypeName), Result) then
    begin
      Result := nil;
    end;
  end;

  // TypeNodeLength und TypeNameLength rufen sich gegenseitig auf; die Rekursion bleibt: sie folgt
  // nur einer Kette von Typaliasen (TName = TKurz; TKurz = string[8]), nicht dem Syntaxbaum.
  function TypeNameLength(const ATypeName: string; AFrom: TSyntaxNode): Integer; forward;

  /// <summary>N des Typknotens ATypeNode (string[N], ShortString oder Alias darauf); 0 sonst.</summary>
  function TypeNodeLength(ATypeNode: TSyntaxNode): Integer;
  begin
    Result := BracketLength(ATypeNode);
    if Result = 0 then
    begin
      Result := ShortStringLength(NodeText(ATypeNode));
    end;
    if (Result = 0) and (ATypeNode.Kind = TSyntaxKind.TypeReference) then
    begin
      Result := TypeNameLength(Trim(NodeText(ATypeNode)), ATypeNode);
    end;
  end;

  /// <summary>N des Alias ATypeName: eigener Alias aus dem Baum (auch string[Laenge]), sonst aus der Signatur
  /// im Index; 0 sonst. AFrom verhindert, dass ein Knoten sich selbst auswertet.</summary>
  function TypeNameLength(const ATypeName: string; AFrom: TSyntaxNode): Integer;
  var
    mBody: TSyntaxNode;
  begin
    Result := 0;
    if mShortTypes.ContainsKey(LowerCase(ATypeName)) then
    begin
      mBody := LocalTypeBody(ATypeName);
      if (mBody <> nil) and (mBody <> AFrom) then
      begin
        Result := TypeNodeLength(mBody);
      end;
    end
    else
    begin
      Result := AliasLength(ATypeName);
    end;
  end;

  /// <summary>Typknoten der Deklaration von ASymbol in dieser Datei; nil, wenn sie woanders steht. AFixable:
  /// einzelne Variable, Inline-Variable oder typisierte Konstante (keine Record-Felder, deren Größe zählen kann,
  /// keine Parameter).</summary>
  function DeclarationTypeNode(const ASymbol: TResolvedSymbol; out AFixable: Boolean): TSyntaxNode;
  var
    mNodes: TList<TSyntaxNode>;
    mNode: TSyntaxNode;
  begin
    Result := nil;
    AFixable := False;
    if not ((ASymbol.FileName = '') or SameText(ASymbol.FileName, mFileName) or
      SameText(ExtractFileName(ASymbol.FileName), ExtractFileName(mFileName))) then
    begin
      Exit;
    end;
    EnsureDeclarations;
    if not mDeclarations.TryGetValue(LowerCase(ASymbol.Name), mNodes) then
    begin
      Exit;
    end;
    for mNode in mNodes do
    begin
      if (mNode.StartPos.Line <= ASymbol.SelectionRange.StartPos.Line) and
        (mNode.EndPos.Line >= ASymbol.SelectionRange.StartPos.Line) then
      begin
        Result := mNode[0];
        AFixable := (mNode.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.InlineVar, TSyntaxKind.ConstDecl]) and
          (Pos(',', mNode.Name) = 0) and (Result.Kind = TSyntaxKind.TypeReference);
        Exit;
      end;
    end;
  end;

  procedure ReportTruncated(AValue: TSyntaxNode; ALength, ALimit: Integer; ATypeNode: TSyntaxNode);
  var
    mFixes: TArray<TRuleFix>;
  begin
    mFixes := nil;
    if ATypeNode <> nil then
    begin
      mFixes := [TRuleFix.Create(cTexts[TConstantsConversionsText.DeclareString].Text,
        [TTextEdit.Create(TTextRange.Create(ATypeNode.StartPos,
        ATypeNode.EndPos), 'string')])];
    end;
    AReport.Add(TTextRange.Create(AValue.StartPos, AValue.EndPos),
      cTexts[TConstantsConversionsText.Truncated].Fmt([ALength, ALimit]), TRuleConfidence.High, mFixes);
  end;

  /// <summary>Typisierte Konstante oder initialisierte Variable: const K: string[8] = '…'.</summary>
  procedure CheckDeclaration(ANode: TSyntaxNode);
  var
    mLimit, mChars: Integer;
    mTypeNode: TSyntaxNode;
  begin
    if ANode.ChildCount <> 2 then
    begin
      Exit;
    end;
    mChars := ExpressionLength(ANode[1]);
    if mChars <= 0 then
    begin
      Exit;
    end;
    mLimit := TypeNodeLength(ANode[0]);
    if (mLimit = 0) or (mChars <= mLimit) then
    begin
      Exit;
    end;
    mTypeNode := nil;
    if (Pos(',', ANode.Name) = 0) and (ANode[0].Kind = TSyntaxKind.TypeReference) then
    begin
      mTypeNode := ANode[0];
    end;
    ReportTruncated(ANode[1], mChars, mLimit, mTypeNode);
  end;

  procedure CheckAssignment(ANode: TSyntaxNode);
  var
    mSymbol, mTypeInfo: TResolvedSymbol;
    mTypeFound, mFixable: Boolean;
    mLimit, mChars: Integer;
    mTypeNode: TSyntaxNode;
  begin
    if (ANode.ChildCount <> 2) or not (ANode[0].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) or
      not Suspect(ANode[0].Name) then
    begin
      Exit;
    end;
    mChars := ExpressionLength(ANode[1]);
    if mChars <= 0 then
    begin
      Exit;
    end;
    EnsureResolver;
    if not mResolver.NodeType(AContext.Tree, mFileName, ANode[0], mSymbol, mTypeInfo, mTypeFound) or
      not (mSymbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field, TIndexSymbolKind.Property_]) then
    begin
      Exit;
    end;
    // Deklaration in dieser Datei: Länge aus dem Baum (auch string[Laenge]); sonst aus der Signatur.
    mTypeNode := DeclarationTypeNode(mSymbol, mFixable);
    if mTypeNode <> nil then
    begin
      mLimit := TypeNodeLength(mTypeNode);
    end
    else
    begin
      mLimit := ShortStringLength(Copy(mSymbol.Signature, Pos(':', mSymbol.Signature) + 1, MaxInt));
      if (mLimit = 0) and (mSymbol.TypeName <> '') then
      begin
        mLimit := TypeNameLength(mSymbol.TypeName, nil);
      end;
    end;
    if (mLimit = 0) or (mChars <= mLimit) then
    begin
      Exit;
    end;
    if mFixable and (ANode[0].Kind = TSyntaxKind.Identifier) then
    begin
      ReportTruncated(ANode[1], mChars, mLimit, mTypeNode);
    end
    else
    begin
      ReportTruncated(ANode[1], mChars, mLimit, nil);
    end;
  end;

  procedure CheckResourceStrings(ASection: TSyntaxNode);
  var
    mIndex, mChars: Integer;
    mDecl: TSyntaxNode;
  begin
    for mIndex := 0 to ASection.ChildCount - 1 do
    begin
      mDecl := ASection[mIndex];
      if (mDecl.Kind <> TSyntaxKind.ConstDecl) or (mDecl.ChildCount = 0) then
      begin
        Continue;
      end;
      mChars := ExpressionLength(mDecl[mDecl.ChildCount - 1]);
      if mChars > cMaxResourceString then
      begin
        AReport.AddWithSeverity(TTextRange.Create(mDecl[mDecl.ChildCount - 1].StartPos,
          mDecl[mDecl.ChildCount - 1].EndPos),
            cTexts[TConstantsConversionsText.ResourceTooLong].Fmt([mDecl.Name, mChars,
            cMaxResourceString]), TRuleSeverity.Error, nil);
      end;
    end;
  end;

  /// <summary>Teilt das Literal ATokenText in Stücke zu höchstens MaxLiteral Zeichen ('…' + '…'); '' wenn es
  /// nicht nur aus einem Stück in Anführungszeichen besteht.</summary>
  function SplitLiteral(const ATokenText: string): string;
  var
    mIndex, mCount: Integer;
    mPart, mChar: string;
  begin
    Result := '';
    if (Length(ATokenText) < 2) or (ATokenText[1] <> '''') or (ATokenText[Length(ATokenText)] <> '''') then
    begin
      Exit;
    end;
    mPart := '';
    mCount := 0;
    mIndex := 2;
    while mIndex < Length(ATokenText) do
    begin
      if mCount = cMaxLiteral then
      begin
        Result := Result + '''' + mPart + ''' + ';
        mPart := '';
        mCount := 0;
      end;
      mChar := NextLiteralChar(ATokenText, mIndex);
      if mChar = '' then
      begin
        Exit('');
      end;
      mPart := mPart + mChar;
      Inc(mCount);
    end;
    Result := Result + '''' + mPart + '''';
  end;

  procedure CheckLongLiterals;
  var
    mToken: TPascalToken;
    mLongest, mMajor: Integer;
    mSplit: string;
    mFixes: TArray<TRuleFix>;
  begin
    mMajor := StrToIntDef(Copy(AContext.DelphiVersion, 1, Pos('.', AContext.DelphiVersion + '.') - 1), 0);
    if (mMajor <= 0) or (mMajor >= cLongLiteralVersion) then
    begin
      Exit;
    end;
    for mToken in AContext.Tree.Tokens do
    begin
      if (mToken.Kind = TPascalTokenKind.StringLiteral) and (Length(mToken.Text) > cMaxLiteral) and
        (LiteralLength(mToken.Text, mLongest) >= 0) and (mLongest > cMaxLiteral) then
      begin
        mFixes := nil;
        mSplit := SplitLiteral(mToken.Text);
        if mSplit <> '' then
        begin
          mFixes := [TRuleFix.Create(cTexts[TConstantsConversionsText.SplitLiteral].Text,
            [TTextEdit.Create(TTextRange.Create(mToken.StartPos,
            mToken.EndPos), mSplit)])];
        end;
        AReport.AddWithSeverity(TTextRange.Create(mToken.StartPos, mToken.EndPos),
          cTexts[TConstantsConversionsText.LiteralTooLong].Fmt(
          [mLongest, cMaxLiteral]), TRuleSeverity.Error, mFixes);
      end;
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (tiefe Bäume sprengen den Stapel nicht).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        case mNode.Kind of
          TSyntaxKind.AssignStatement:
            CheckAssignment(mNode);
          TSyntaxKind.ConstDecl, TSyntaxKind.VarDecl, TSyntaxKind.InlineVar:
            CheckDeclaration(mNode);
          TSyntaxKind.ConstSection:
            if SameText(mNode.Name, 'resourcestring') then
            begin
              CheckResourceStrings(mNode);
            end;
        else
          // Übrige Werte bewusst ohne Wirkung.
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mFileName := AContext.FileName;
  if mFileName = '' then
  begin
    mFileName := AContext.RelativePath;
  end;
  if mFileName = '' then
  begin
    mFileName := AContext.UnitName + '.pas';
  end;
  mResolver := nil;
  mValues := nil;
  mDeclarations := nil;
  mTypeBodies := nil;
  mLocalNames := TDictionary<string, Boolean>.Create;
  mShortTypes := TDictionary<string, Boolean>.Create;
  mSuspects := TDictionary<string, Boolean>.Create;
  try
    CollectTypes(AContext.Tree.Root);
    CollectLocal(AContext.Tree.Root);
    Visit(AContext.Tree.Root);
    CheckLongLiterals;
  finally
    mValues.Free;
    if mResolver <> nil then
    begin
      mResolver.UnpinTree;
    end;
    mTypeBodies.Free;
    mDeclarations.Free;
    mSuspects.Free;
    mShortTypes.Free;
    mLocalNames.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Constants.Conversions', cTexts);

end.
