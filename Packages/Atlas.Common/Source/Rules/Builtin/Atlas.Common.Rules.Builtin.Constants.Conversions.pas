unit Atlas.Common.Rules.Builtin.Constants.Conversions;

// Regeln zu Zahltypen in Ausdrücken und Zuweisungen (Teil von Atlas.Common.Rules.Builtin.Constants, dort
// registriert; Beschreibung dort): signed-unsigned-mix, narrowing-assignment, string-length-limit.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract;

const
  SignedUnsignedMixRuleId = 'signed-unsigned-mix';
  NarrowingAssignmentRuleId = 'narrowing-assignment';
  StringLengthLimitRuleId = 'string-length-limit';

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
  Atlas.Common.Pascal.DirectiveNames,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.OrdinalConstants,
  Atlas.Common.Semantics.ConstantValues,
  Atlas.Common.Rules.TypedScope,
  Atlas.Common.Rules.Options,
  Atlas.Text.Lines,
  Atlas.Common.Rules.Builtin.Constants.Types;

{ TSignedUnsignedMixRule }

function TSignedUnsignedMixRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(SignedUnsignedMixRuleId, TRuleSeverity.Warning,
    'Vorzeichenbehaftet und vorzeichenlos gemischt');
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
    Result := Format('%s und %s verglichen: ein negativer Wert in %s wird vorzeichenlos verglichen (wie W1023).',
      [ASignedType, AUnsignedType, ASignedText]);
  end
  else if AUnsignedBits = 64 then
  begin
    Result := Format('%s und %s gemischt: ein negativer Wert in %s wird vorzeichenlos gerechnet (wie W1073).',
      [ASignedType, AUnsignedType, ASignedText]);
  end
  else if AComparison then
  begin
    Result := Format('%s und %s verglichen: beide Operanden werden auf Int64 erweitert (wie W1023).',
      [ASignedType, AUnsignedType]);
  end
  else
  begin
    Result := Format('%s und %s gemischt: beide Operanden werden auf Int64 erweitert (wie W1024).',
      [ASignedType, AUnsignedType]);
  end;
end;

procedure TSignedUnsignedMixRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
type
  TOperandKinds = array[0..1] of TIntegerKind;
  TOperandTypes = array[0..1] of string;
const
  // Kürzer gehaltene Operanden erscheinen mit Namen in der Meldung.
  MaxOperandText = 30;
var
  FileName: string;
  Resolver: TNameResolver;
  Cache: IRuleDerivedCache;
  // Vorfilter vor der Namensauflösung: Namen mit vorzeichenlosem Typ.
  Unsigned: TTypedNames;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  procedure EnsureResolver;
  begin
    if Resolver = nil then
    begin
      // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
      Cache := TRuleDerived.Open(AContext);
      Resolver := TRuleDerived.Resolver(Cache, AContext);
      Resolver.PinTree(AContext.Tree, FileName);
    end;
  end;

  /// <summary>Typen beider Operanden von ANode; False, wenn einer nicht sicher bekannt ist oder beide dasselbe
  /// Vorzeichen haben.</summary>
  function OperandKinds(ANode: TSyntaxNode; out AKinds: TOperandKinds; out ATypes: TOperandTypes): Boolean;
  begin
    EnsureResolver;
    Result := OperandKind(Resolver, AContext.Tree, FileName, ANode[0], AKinds[0], ATypes[0]) and
      OperandKind(Resolver, AContext.Tree, FileName, ANode[1], AKinds[1], ATypes[1]) and
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
      (not Unsigned.Suspect(OperandName(ANode[0])) and not Unsigned.Suspect(OperandName(ANode[1]))) or
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
    if (Length(mSignedText) > MaxOperandText) or (Pos(#10, mSignedText) > 0) then
    begin
      mSignedText := 'Wert';
    end;
    mUnsignedNode := ANode[mUnsigned];
    AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), MixMessage(mComparison, mKinds[mUnsigned].Bits,
      mTypes[mSigned], mTypes[mUnsigned], mSignedText), TRuleConfidence.Medium,
      [TRuleFix.Create(Format('%s in Int64 umwandeln', [NodeText(mUnsignedNode)]),
      [TTextEdit.Create(TTextRange.Create(mUnsignedNode.StartPos, mUnsignedNode.EndPos),
      'Int64(' + NodeText(mUnsignedNode) + ')')])]);
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.BinaryExpr then
        begin
          CheckMix(Node);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  FileName := AContext.FileName;
  if FileName = '' then
  begin
    FileName := AContext.RelativePath;
  end;
  if FileName = '' then
  begin
    FileName := AContext.UnitName + '.pas';
  end;
  Resolver := nil;
  Unsigned := TTypedNames.Create(AContext, ['Cardinal', 'UInt64']);
  try
    Visit(AContext.Tree.Root);
  finally
    if Resolver <> nil then
    begin
      Resolver.UnpinTree;
    end;
    Unsigned.Free;
  end;
end;

{ TNarrowingAssignmentRule }

function TNarrowingAssignmentRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(NarrowingAssignmentRuleId, TRuleSeverity.Warning,
    'Zuweisung mit möglichem Datenverlust', True);
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
  MaxValueText = 30;
var
  FileName: string;
  Resolver: TNameResolver;
  Cache: IRuleDerivedCache;
  Sources: TTypedNames;
  // Paare "quelle>ziel" in einheitlichen Namen.
  Pairs: TDictionary<string, Boolean>;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  procedure EnsureResolver;
  begin
    if Resolver = nil then
    begin
      // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
      Cache := TRuleDerived.Open(AContext);
      Resolver := TRuleDerived.Resolver(Cache, AContext);
      Resolver.PinTree(AContext.Tree, FileName);
    end;
  end;

  /// <summary>Einheitlicher Name des Typs ATypeName; eigene Aliase über den aufgelösten Typ
  /// (ATypeInfo aus NodeType bzw. ResolveType).</summary>
  function Canonical(const ATypeName: string; const ATypeInfo: TResolvedSymbol; ATypeFound: Boolean): string;
  var
    Body: string;
  begin
    Result := CanonicalTypeName(ATypeName);
    if (IntegerWidth(Result) > 0) or IsFloatName(Result) or not ATypeFound then
    begin
      Exit;
    end;
    // Aufgelöst ist entweder der Zieltyp selbst (Integer) oder der Alias mit Signatur (TZahl = Integer).
    Body := CanonicalTypeName(ATypeInfo.Name);
    if (IntegerWidth(Body) = 0) and not IsFloatName(Body) then
    begin
      Body := CanonicalTypeName(TypeBodyOf(ATypeInfo.Signature));
    end;
    if (IntegerWidth(Body) > 0) or IsFloatName(Body) then
    begin
      Result := Body;
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
    Result := Resolver.NodeType(AContext.Tree, FileName, ANode, mSymbol, mTypeInfo, mTypeFound) and
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
    // Iterativ (Bericht M1): Nachordnung, die Operanden zuerst; lange Rechenketten ergeben sehr tiefe Bäume.
    // Bekannte Typen stehen in mKnown, unbekannte fehlen dort.
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
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.Call,
          TSyntaxKind.IndexAccess] then
        begin
          if Sources.Suspect(OperandName(Node)) then
          begin
            Exit(True);
          end;
        end
        else if Node.Kind in [TSyntaxKind.ParenExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.BinaryExpr] then
        begin
          for Index := Node.ChildCount - 1 downto 0 do
          begin
            Pending.Push(Node[Index]);
          end;
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  /// <summary>Typknoten der Deklaration des Ziels in dieser Datei (einzelne Variable oder einzelnes Feld);
  /// nil, wenn die Deklaration woanders steht oder mehrere Namen teilt.</summary>
  function DeclarationTypeNode(const ASymbol: TResolvedSymbol): TSyntaxNode;
  var
    Found: TSyntaxNode;

    procedure Search(ARoot: TSyntaxNode);
    var
      Index: Integer;
      Node: TSyntaxNode;
      Pending: TStack<TSyntaxNode>;
    begin
      // Iterativ (Bericht M1).
      Pending := TStack<TSyntaxNode>.Create;
      try
        Pending.Push(ARoot);
        while Pending.Count > 0 do
        begin
          Node := Pending.Pop;
          if (Node.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.Field, TSyntaxKind.InlineVar]) and
            (Node.ChildCount > 0) and SameText(Node.Name, ASymbol.Name) and
            (Node.StartPos.Line = ASymbol.SelectionRange.StartPos.Line) and
            (Node[0].Kind = TSyntaxKind.TypeReference) then
          begin
            Found := Node[0];
            Exit;
          end;
          for Index := Node.ChildCount - 1 downto 0 do
          begin
            Pending.Push(Node[Index]);
          end;
        end;
      finally
        Pending.Free;
      end;
    end;

  begin
    Found := nil;
    if (ASymbol.FileName = '') or SameText(ASymbol.FileName, FileName) or
      SameText(ExtractFileName(ASymbol.FileName), ExtractFileName(FileName)) then
    begin
      Search(AContext.Tree.Root);
    end;
    Result := Found;
  end;

  procedure Report(AValue: TSyntaxNode; const ATargetDisplay, ATargetCanonical: string;
    ATargetTypeNode: TSyntaxNode);
  var
    SourceCanonical, SourceDisplay, ValueText, CodeSuffix, Message: string;
    Fixes: TArray<TRuleFix>;
  begin
    if not MaySource(AValue) or not ExpressionType(AValue, SourceCanonical, SourceDisplay) or
      not Pairs.ContainsKey(SourceCanonical + '>' + ATargetCanonical) then
    begin
      Exit;
    end;
    CodeSuffix := '';
    if IsFloatName(ATargetCanonical) then
    begin
      if (SourceCanonical = 'extended') and (ATargetCanonical = 'double') then
      begin
        CodeSuffix := ' (wie W1066)';
      end
      else
      begin
        CodeSuffix := ' (wie W1072)';
      end;
    end;
    ValueText := NodeText(AValue);
    if (Length(ValueText) > MaxValueText) or (Pos(#10, ValueText) > 0) then
    begin
      ValueText := 'Der Wert';
    end;
    Message := Format('%s ist %s; die Zuweisung an %s kann Daten verlieren%s.',
      [ValueText, SourceDisplay, ATargetDisplay, CodeSuffix]);
    Fixes := [TRuleFix.Create('Ausdrücklich in ' + ATargetDisplay + ' umwandeln',
      [TTextEdit.Create(TTextRange.Create(AValue.StartPos, AValue.EndPos),
      ATargetDisplay + '(' + NodeText(AValue) + ')')])];
    if ATargetTypeNode <> nil then
    begin
      Fixes := Fixes + [TRuleFix.Create('Zieltyp auf ' + SourceDisplay + ' vergrößern',
        [TTextEdit.Create(TTextRange.Create(ATargetTypeNode.StartPos, ATargetTypeNode.EndPos), SourceDisplay)])];
    end;
    AReport.Add(TTextRange.Create(AValue.StartPos, AValue.EndPos), Message, TRuleConfidence.Medium, Fixes);
  end;

  procedure CheckAssignment(ANode: TSyntaxNode);
  var
    Symbol, TypeInfo: TResolvedSymbol;
    TypeFound: Boolean;
    Target: string;
  begin
    if (ANode.ChildCount <> 2) or not MaySource(ANode[1]) then
    begin
      Exit;
    end;
    EnsureResolver;
    if not (ANode[0].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess]) or
      not Resolver.NodeType(AContext.Tree, FileName, ANode[0], Symbol, TypeInfo, TypeFound) or
      not (Symbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field,
      TIndexSymbolKind.Property_]) or (Symbol.TypeName = '') then
    begin
      Exit;
    end;
    Target := Canonical(Symbol.TypeName, TypeInfo, TypeFound);
    if (ANode[0].Kind = TSyntaxKind.Identifier) and not Symbol.IsParameter then
    begin
      Report(ANode[1], Symbol.TypeName, Target, DeclarationTypeNode(Symbol));
    end
    else
    begin
      Report(ANode[1], Symbol.TypeName, Target, nil);
    end;
  end;

  procedure CheckInlineVar(ANode: TSyntaxNode);
  var
    TypeInfo: TResolvedSymbol;
    TypeName: string;
  begin
    if (ANode.ChildCount <> 2) or (ANode[0].Kind <> TSyntaxKind.TypeReference) or (Pos(',', ANode.Name) > 0) or
      not MaySource(ANode[1]) then
    begin
      Exit;
    end;
    EnsureResolver;
    TypeName := NodeText(ANode[0]);
    TypeInfo := Resolver.ResolveType(AContext.Tree, FileName, ANode[0].StartPos);
    Report(ANode[1], TypeName, Canonical(TypeName, TypeInfo, TypeInfo.Found), ANode[0]);
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.AssignStatement then
        begin
          CheckAssignment(Node);
        end
        else if Node.Kind = TSyntaxKind.InlineVar then
        begin
          CheckInlineVar(Node);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

var
  mSourceNames: TArray<string>;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  FileName := AContext.FileName;
  if FileName = '' then
  begin
    FileName := AContext.RelativePath;
  end;
  if FileName = '' then
  begin
    FileName := AContext.UnitName + '.pas';
  end;
  Pairs := TDictionary<string, Boolean>.Create;
  Resolver := nil;
  Sources := nil;
  try
    mSourceNames := ReadPairs(TRuleOptions.Strings(AContext.Options, 'types', DefaultTypes), Pairs);
    if Pairs.Count = 0 then
    begin
      Exit;
    end;
    Sources := TTypedNames.Create(AContext, mSourceNames);
    Visit(AContext.Tree.Root);
  finally
    if Resolver <> nil then
    begin
      Resolver.UnpinTree;
    end;
    Sources.Free;
    Pairs.Free;
  end;
end;

{ TStringLengthLimitRule }

function TStringLengthLimitRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(StringLengthLimitRuleId, TRuleSeverity.Warning, 'String-Grenze überschritten');
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
    Result := mValue;
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
  MaxLiteral = 255;
  MaxResourceString = 4096;
  // Ab Delphi 12 (BDS 23) dürfen Literale länger sein.
  LongLiteralVersion = 23;
var
  FileName: string;
  Resolver: TNameResolver;
  // Namen und Typen mit string[N]/ShortString (Vorfilter vor der Namensauflösung).
  LocalNames, ShortTypes, Suspects: TDictionary<string, Boolean>;
  // Werte von Konstanten für string[Laenge]; erst bei Bedarf.
  Values: TConstantValues;
  // Deklarationen dieser Datei nach Namen (klein), erst bei Bedarf (EnsureDeclarations).
  Declarations: TObjectDictionary<string, TList<TSyntaxNode>>;
  TypeBodies: TDictionary<string, TSyntaxNode>;
  // Hält den Resolver des Laufs (oder einen eigenen Cache ohne Engine).
  Cache: IRuleDerivedCache;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  procedure EnsureResolver;
  begin
    if Resolver = nil then
    begin
      // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
      Cache := TRuleDerived.Open(AContext);
      Resolver := TRuleDerived.Resolver(Cache, AContext);
      Resolver.PinTree(AContext.Tree, FileName);
    end;
  end;

  /// <summary>Typknoten string[Ausdruck] aus dem Baum: N über die Konstantenwerte (auch string[Laenge]); 0 bei
  /// anderen Typen.</summary>
  function BracketLength(ATypeNode: TSyntaxNode): Integer;
  var
    Value: Int64;
  begin
    Result := 0;
    if (ATypeNode.Kind <> TSyntaxKind.TypeReference) or not SameText(ATypeNode.Name, 'string') or
      (ATypeNode.ChildCount <> 1) then
    begin
      Exit;
    end;
    EnsureResolver;
    if Values = nil then
    begin
      Values := TConstantValues.Create(AContext.Tree, FileName, AContext.Index, Resolver);
    end;
    if (Values.Check(ATypeNode[0], Value) = TOrdinalStatus.Value) and (Value >= 1) and (Value <= 255) then
    begin
      Result := Value;
    end;
  end;

  /// <summary>Nennt der Typknoten string[…], ShortString oder einen eigenen Alias darauf?</summary>
  function IsShortTypeNode(ATypeNode: TSyntaxNode): Boolean;
  begin
    Result := ((ATypeNode.Kind = TSyntaxKind.TypeReference) and SameText(ATypeNode.Name, 'string') and
      (ATypeNode.ChildCount = 1)) or (ShortStringLength(NodeText(ATypeNode)) > 0) or
      ShortTypes.ContainsKey(LowerCase(Trim(NodeText(ATypeNode))));
  end;

  /// <summary>Zeichen des konstanten String-Ausdrucks ANode (Literale, mit + verkettet); -1 sonst.</summary>
  function ExpressionLength(ANode: TSyntaxNode): Integer;
  var
    mLongest, mChars: Integer;
    mEntry: TSyntaxPostOrderEntry;
    mPending: TStack<TSyntaxPostOrderEntry>;
    mLengths: TDictionary<TSyntaxNode, Integer>;
  begin
    // Iterativ (Bericht M1): Nachordnung, die Operanden zuerst; lange Verkettungen ergeben sehr tiefe Bäume.
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
    if ShortTypes.ContainsKey(LowerCase(ATypeName)) then
    begin
      Exit(1);
    end;
    Result := IndexShortAlias(AContext.NameFacts, AContext.Index, ATypeName);
  end;

  procedure CollectTypes(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.TypeDecl) and (Node.ChildCount > 0) and IsShortTypeNode(Node[0]) then
        begin
          ShortTypes.AddOrSetValue(LowerCase(Node.Name), True);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  procedure CollectLocal(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Name: string;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.Field, TSyntaxKind.Parameter, TSyntaxKind.PropertyDecl,
          TSyntaxKind.InlineVar]) and (Node.ChildCount > 0) and IsShortTypeNode(Node[0]) then
        begin
          for Name in Node.Name.Split([',']) do
          begin
            LocalNames.AddOrSetValue(LowerCase(Trim(Name)), True);
          end;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  function Suspect(const AName: string): Boolean;
  var
    Key: string;
    Location: TSymbolLocation;
  begin
    Key := LowerCase(AName);
    if (Key = '') or LocalNames.ContainsKey(Key) then
    begin
      Exit(Key <> '');
    end;
    if Suspects.TryGetValue(Key, Result) then
    begin
      Exit;
    end;
    Result := False;
    // Ohne eigene Aliase der Datei hängt die Antwort nur vom Index ab: über alle Units gemerkt.
    if ShortTypes.Count = 0 then
    begin
      Result := IndexShortVariable(AContext.NameFacts, AContext.Index, AName);
    end
    else if AContext.Index <> nil then
    begin
      for Location in AContext.Index.FindSymbols(AName) do
      begin
        if (Location.Symbol.Kind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field,
          TIndexSymbolKind.Property_]) and ((ShortStringLength(Location.Symbol.Signature) > 0) or
          ((Location.Symbol.TypeName <> '') and (AliasLength(Location.Symbol.TypeName) > 0))) then
        begin
          Result := True;
          Break;
        end;
      end;
    end;
    Suspects.Add(Key, Result);
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
      if not Declarations.TryGetValue(mKey, mNodes) then
      begin
        mNodes := TList<TSyntaxNode>.Create;
        Declarations.Add(mKey, mNodes);
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
    if Declarations <> nil then
    begin
      Exit;
    end;
    Declarations := TObjectDictionary<string, TList<TSyntaxNode>>.Create([doOwnsValues]);
    TypeBodies := TDictionary<string, TSyntaxNode>.Create;
    // Iterativ (Bericht M1); Vorordnung wie die frühere Suche, damit der erste Treffer gleich bleibt.
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(AContext.Tree.Root);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if (mNode.Kind = TSyntaxKind.TypeDecl) and (mNode.ChildCount > 0) and
          not TypeBodies.ContainsKey(LowerCase(mNode.Name)) then
        begin
          TypeBodies.Add(LowerCase(mNode.Name), mNode[0]);
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
    if not TypeBodies.TryGetValue(LowerCase(ATypeName), Result) then
    begin
      Result := nil;
    end;
  end;

  // TypeNodeLength und TypeNameLength rufen sich gegenseitig auf; die Rekursion bleibt (Bericht M1): sie folgt
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
    Body: TSyntaxNode;
  begin
    Result := 0;
    if ShortTypes.ContainsKey(LowerCase(ATypeName)) then
    begin
      Body := LocalTypeBody(ATypeName);
      if (Body <> nil) and (Body <> AFrom) then
      begin
        Result := TypeNodeLength(Body);
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
    Nodes: TList<TSyntaxNode>;
    Node: TSyntaxNode;
  begin
    Result := nil;
    AFixable := False;
    if not ((ASymbol.FileName = '') or SameText(ASymbol.FileName, FileName) or
      SameText(ExtractFileName(ASymbol.FileName), ExtractFileName(FileName))) then
    begin
      Exit;
    end;
    EnsureDeclarations;
    if not Declarations.TryGetValue(LowerCase(ASymbol.Name), Nodes) then
    begin
      Exit;
    end;
    for Node in Nodes do
    begin
      if (Node.StartPos.Line <= ASymbol.SelectionRange.StartPos.Line) and
        (Node.EndPos.Line >= ASymbol.SelectionRange.StartPos.Line) then
      begin
        Result := Node[0];
        AFixable := (Node.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.InlineVar, TSyntaxKind.ConstDecl]) and
          (Pos(',', Node.Name) = 0) and (Result.Kind = TSyntaxKind.TypeReference);
        Exit;
      end;
    end;
  end;

  procedure ReportTruncated(AValue: TSyntaxNode; ALength, ALimit: Integer; ATypeNode: TSyntaxNode);
  var
    Fixes: TArray<TRuleFix>;
  begin
    Fixes := nil;
    if ATypeNode <> nil then
    begin
      Fixes := [TRuleFix.Create('Als string deklarieren', [TTextEdit.Create(TTextRange.Create(ATypeNode.StartPos,
        ATypeNode.EndPos), 'string')])];
    end;
    AReport.Add(TTextRange.Create(AValue.StartPos, AValue.EndPos), Format('Das Literal hat %d Zeichen und wird ' +
      'auf %d gekürzt (wie W1014).', [ALength, ALimit]), TRuleConfidence.High, Fixes);
  end;

  /// <summary>Typisierte Konstante oder initialisierte Variable: const K: string[8] = '…'.</summary>
  procedure CheckDeclaration(ANode: TSyntaxNode);
  var
    Limit, Chars: Integer;
    TypeNode: TSyntaxNode;
  begin
    if ANode.ChildCount <> 2 then
    begin
      Exit;
    end;
    Chars := ExpressionLength(ANode[1]);
    if Chars <= 0 then
    begin
      Exit;
    end;
    Limit := TypeNodeLength(ANode[0]);
    if (Limit = 0) or (Chars <= Limit) then
    begin
      Exit;
    end;
    TypeNode := nil;
    if (Pos(',', ANode.Name) = 0) and (ANode[0].Kind = TSyntaxKind.TypeReference) then
    begin
      TypeNode := ANode[0];
    end;
    ReportTruncated(ANode[1], Chars, Limit, TypeNode);
  end;

  procedure CheckAssignment(ANode: TSyntaxNode);
  var
    Symbol, TypeInfo: TResolvedSymbol;
    TypeFound, Fixable: Boolean;
    Limit, Chars: Integer;
    TypeNode: TSyntaxNode;
  begin
    if (ANode.ChildCount <> 2) or not (ANode[0].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) or
      not Suspect(ANode[0].Name) then
    begin
      Exit;
    end;
    Chars := ExpressionLength(ANode[1]);
    if Chars <= 0 then
    begin
      Exit;
    end;
    EnsureResolver;
    if not Resolver.NodeType(AContext.Tree, FileName, ANode[0], Symbol, TypeInfo, TypeFound) or
      not (Symbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field, TIndexSymbolKind.Property_]) then
    begin
      Exit;
    end;
    // Deklaration in dieser Datei: Länge aus dem Baum (auch string[Laenge]); sonst aus der Signatur.
    TypeNode := DeclarationTypeNode(Symbol, Fixable);
    if TypeNode <> nil then
    begin
      Limit := TypeNodeLength(TypeNode);
    end
    else
    begin
      Limit := ShortStringLength(Copy(Symbol.Signature, Pos(':', Symbol.Signature) + 1, MaxInt));
      if (Limit = 0) and (Symbol.TypeName <> '') then
      begin
        Limit := TypeNameLength(Symbol.TypeName, nil);
      end;
    end;
    if (Limit = 0) or (Chars <= Limit) then
    begin
      Exit;
    end;
    if Fixable and (ANode[0].Kind = TSyntaxKind.Identifier) then
    begin
      ReportTruncated(ANode[1], Chars, Limit, TypeNode);
    end
    else
    begin
      ReportTruncated(ANode[1], Chars, Limit, nil);
    end;
  end;

  procedure CheckResourceStrings(ASection: TSyntaxNode);
  var
    Index, Chars: Integer;
    Decl: TSyntaxNode;
  begin
    for Index := 0 to ASection.ChildCount - 1 do
    begin
      Decl := ASection[Index];
      if (Decl.Kind <> TSyntaxKind.ConstDecl) or (Decl.ChildCount = 0) then
      begin
        Continue;
      end;
      Chars := ExpressionLength(Decl[Decl.ChildCount - 1]);
      if Chars > MaxResourceString then
      begin
        AReport.AddWithSeverity(TTextRange.Create(Decl[Decl.ChildCount - 1].StartPos,
          Decl[Decl.ChildCount - 1].EndPos), Format('Der resourcestring %s hat %d Zeichen; Windows erlaubt höchstens ' +
          '%d (wie E2381).', [Decl.Name, Chars, MaxResourceString]), TRuleSeverity.Error, nil);
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
      if mCount = MaxLiteral then
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
    Token: TPascalToken;
    Longest, Major: Integer;
    Split: string;
    Fixes: TArray<TRuleFix>;
  begin
    Major := StrToIntDef(Copy(AContext.DelphiVersion, 1, Pos('.', AContext.DelphiVersion + '.') - 1), 0);
    if (Major <= 0) or (Major >= LongLiteralVersion) then
    begin
      Exit;
    end;
    for Token in AContext.Tree.Tokens do
    begin
      if (Token.Kind = TPascalTokenKind.StringLiteral) and (Length(Token.Text) > MaxLiteral) and
        (LiteralLength(Token.Text, Longest) >= 0) and (Longest > MaxLiteral) then
      begin
        Fixes := nil;
        Split := SplitLiteral(Token.Text);
        if Split <> '' then
        begin
          Fixes := [TRuleFix.Create('Literal teilen', [TTextEdit.Create(TTextRange.Create(Token.StartPos,
            Token.EndPos), Split)])];
        end;
        AReport.AddWithSeverity(TTextRange.Create(Token.StartPos, Token.EndPos), Format('Das Literal hat %d ' +
          'Zeichen in Anführungszeichen; vor Delphi 12 sind höchstens %d erlaubt (wie E2056).',
          [Longest, MaxLiteral]), TRuleSeverity.Error, Fixes);
      end;
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        case Node.Kind of
          TSyntaxKind.AssignStatement:
            CheckAssignment(Node);
          TSyntaxKind.ConstDecl, TSyntaxKind.VarDecl, TSyntaxKind.InlineVar:
            CheckDeclaration(Node);
          TSyntaxKind.ConstSection:
            if SameText(Node.Name, 'resourcestring') then
            begin
              CheckResourceStrings(Node);
            end;
        else
          // Übrige Werte bewusst ohne Wirkung.
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  FileName := AContext.FileName;
  if FileName = '' then
  begin
    FileName := AContext.RelativePath;
  end;
  if FileName = '' then
  begin
    FileName := AContext.UnitName + '.pas';
  end;
  Resolver := nil;
  Values := nil;
  Declarations := nil;
  TypeBodies := nil;
  LocalNames := TDictionary<string, Boolean>.Create;
  ShortTypes := TDictionary<string, Boolean>.Create;
  Suspects := TDictionary<string, Boolean>.Create;
  try
    CollectTypes(AContext.Tree.Root);
    CollectLocal(AContext.Tree.Root);
    Visit(AContext.Tree.Root);
    CheckLongLiterals;
  finally
    Values.Free;
    if Resolver <> nil then
    begin
      Resolver.UnpinTree;
    end;
    TypeBodies.Free;
    Declarations.Free;
    Suspects.Free;
    ShortTypes.Free;
    LocalNames.Free;
  end;
end;

end.
