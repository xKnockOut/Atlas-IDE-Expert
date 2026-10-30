unit Atlas.Common.Rules.Builtin.TypeKinds;

// Ausdruck oder Deklaration hat nicht die geforderte Typart (Gruppe „Compiler
// vorab“, #1024, #1370). Regel type-kind-required, Stufe T; die Typart kommt
// aus TResolvedTypeKinds (Semantics.TypeKinds). Gemeldet wird nur, was dcc 13
// in den Fällen aus Tests/Compilermeldungen meldet (#1328: nie strenger als
// dcc):
//   - Index auf einer Variablen, einem Feld oder einer Konstante einfacher Art
//     (Zahl, Boolean, Zeichen, Aufzählung) (wie E2016).
//   - ^ auf einem Wert einfacher Art, einer Klasse, einem Record oder einem
//     Interface (wie E2017). Korrektur bei Klasse, Record und Interface vor
//     einem Punkt: ^ entfernen.
//   - Punkt bzw. with auf einem Wert einfacher Art (wie E2018).
//   - object mit Vorfahr, der kein object-Typ ist; TypeOf und Dispose mit
//     Destruktor auf einem Wert bzw. Zeiger einfacher Art (wie E2019).
//   - Klasse mit Vorfahr, der keine Klasse und kein Interface ist (Record,
//     Klassenreferenz, Aufzählung, einfacher Typ) (wie E2021).
//   - Class-Helper mit Vorfahr, der kein Helfer ist (wie E2022).
//   - New mit Konstruktor auf einem Zeiger einfacher Art (wie E2467).
//   - Record-Helper für eine Klasse oder ein Interface (wie E2474).
//   - Methode ohne class über den Klassentyp aufgerufen (TBasis.Machen)
//     außerhalb von Methoden der Klasse und ihrer Nachfahren (wie E2076).
//   - Slice außerhalb eines Arguments bzw. an einen Parameter mit einfachem
//     Typ (wie E2193).
//   - Record als Element eines Arrays an array of const (wie E2150).
//   - Write/Writeln bzw. Read/Readln mit Klasse, Record oder Interface (wie
//     E2054 bzw. E2055). Korrektur bei Klassen in Write/Writeln: ToString.
// Still bleibt die Regel bei unbekanntem Typ, bei Aliasen ohne bekannten Text,
// in bedingten Deklarationen, wenn ein Helfer für den Typ sichtbar ist oder
// eine Unit aus uses nicht im Index steht (sie könnte einen Helfer bzw. eine
// eigene Routine gleichen Namens deklarieren), bei Records mit Implicit-
// Operator und bei unbekannten Vorfahren.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  TypeKindRequiredRuleId = 'type-kind-required';

type
  TTypeKindRequiredRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterTypeKindRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.TypeIdentity,
  Atlas.Common.Semantics.TypeKinds,
  Atlas.Common.Semantics.UnresolvedNames;

type
  /// <summary>Ein Prüflauf über einen Baum; hält Namensauflösung und Ziel der Meldungen.</summary>
  TTypeKindChecker = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FResolver: TNameResolver;
    FFileName: string;
    FUsesKnown: Boolean;
    function NodeText(ANode: TSyntaxNode): string;
    function Range(ANode: TSyntaxNode): TTextRange;
    /// <summary>Wert ANode (kein Typ, keine Unit, nicht bedingt deklariert) samt Typ und Typart.</summary>
    function ValueType(ANode: TSyntaxNode; out ASymbol, AType: TResolvedSymbol;
      out AKind: TResolvedTypeKind): Boolean;
    /// <summary>Typart des Typnamens ATypeRef (TypeReference) an seiner Stelle; Unknown ohne sichere Auflösung.
    /// </summary>
    function ReferencedKind(ATypeRef: TSyntaxNode; out AType: TResolvedSymbol): TResolvedTypeKind;
    /// <summary>Kann ein Helfer für den Typ AType des Werts ASymbol an ANode Mitglieder liefern? Auch, wenn eine
    /// Unit aus uses fehlt. Gesucht wird für den Typ, seinen eingebauten Zielnamen und den deklarierten Alias.
    /// </summary>
    function HelperPossible(const ASymbol, AType: TResolvedSymbol; ANode: TSyntaxNode): Boolean;
    /// <summary>Record mit class operator Implicit: Der Compiler kann ihn umwandeln.</summary>
    function HasImplicit(const AType: TResolvedSymbol): Boolean;
    /// <summary>Ruft ACall die eingebaute Routine AName auf (nicht von einer eigenen gleichen Namens verdeckt)?
    /// </summary>
    function IsIntrinsic(ACall: TSyntaxNode; const AName: string): Boolean;
    /// <summary>Deklarierter Typ von ASymbol als Quelltext ("^Byte", "TextFile"): TypeName, sonst der Kopf aus
    /// dem Index, sonst die Deklaration im Baum (lokale Namen); '' ohne.</summary>
    function DeclaredTypeText(const ASymbol: TResolvedSymbol): string;
    /// <summary>Typname des Ziels des Zeigers ANode (^Integer, PInteger = ^Integer); '' ohne.</summary>
    function PointeeName(ANode: TSyntaxNode): string;
    /// <summary>Ist ANode eine Variable bzw. ein Parameter vom Typ Text oder TextFile (auch ohne System im
    /// Index)?</summary>
    function IsTextFile(ANode: TSyntaxNode): Boolean;
    procedure CheckIndex(ANode: TSyntaxNode);
    procedure CheckDereference(ANode: TSyntaxNode);
    procedure CheckMember(ANode: TSyntaxNode);
    procedure CheckWith(ANode: TSyntaxNode);
    procedure CheckObjectType(ANode: TSyntaxNode);
    procedure CheckClassType(ANode: TSyntaxNode);
    procedure CheckHelperType(ANode: TSyntaxNode);
    procedure CheckCall(ANode: TSyntaxNode);
    procedure CheckConstructorForm(ANode: TSyntaxNode);
    procedure CheckTypeOf(ANode: TSyntaxNode);
    procedure CheckSlice(ANode: TSyntaxNode);
    procedure CheckConstArray(ANode: TSyntaxNode);
    procedure CheckTextIo(ANode: TSyntaxNode; AWrite: Boolean);
    procedure CheckClassMethodForm(ANode: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport; AResolver: TNameResolver);
    procedure Run;
  end;

const
  cValueKinds = [TIndexSymbolKind.Variable, TIndexSymbolKind.Field, TIndexSymbolKind.Constant,
    TIndexSymbolKind.Property_, TIndexSymbolKind.Method, TIndexSymbolKind.Routine, TIndexSymbolKind.EnumMember];
  cExpressionKinds = [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.Call, TSyntaxKind.IndexAccess,
    TSyntaxKind.Dereference];
  // Standarddateien der Unit System für Write/Read ohne Dateiargument davor.
  cStandardTextFiles: array[0..2] of string = ('Input', 'Output', 'ErrOutput');

function ResolverFileName(const AContext: TRuleContext): string;
begin
  Result := AContext.FileName;
  if Result = '' then
    Result := AContext.RelativePath;
  if Result = '' then
    Result := AContext.UnitName + '.pas';
end;

/// <summary>Alle Knoten unter ARoot in Pre-Order über einen eigenen Stapel (tiefe Ausdrucksketten, Bericht M1).
/// </summary>
function PreOrder(ARoot: TSyntaxNode): TArray<TSyntaxNode>;
var
  mPending: TStack<TSyntaxNode>;
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
  if ARoot = nil then
    Exit;
  mPending := TStack<TSyntaxNode>.Create;
  mNodes := TList<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      mNodes.Add(mNode);
      for mIndex := mNode.ChildCount - 1 downto 0 do
        mPending.Push(mNode[mIndex]);
    end;
    Result := mNodes.ToArray;
  finally
    mNodes.Free;
    mPending.Free;
  end;
end;

/// <summary>Liegt APosition im Bereich von ANode?</summary>
function Covers(ANode: TSyntaxNode; const APosition: TTextPosition): Boolean;
begin
  Result := ((ANode.StartPos.Line < APosition.Line) or ((ANode.StartPos.Line = APosition.Line) and
    (ANode.StartPos.Character <= APosition.Character))) and ((ANode.EndPos.Line > APosition.Line) or
    ((ANode.EndPos.Line = APosition.Line) and (ANode.EndPos.Character >= APosition.Character)));
end;

/// <summary>Direkte Kinder von ANode, die Typnamen sind (Vorfahren, Helferziel).</summary>
function TypeReferences(ANode: TSyntaxNode): TArray<TSyntaxNode>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to ANode.ChildCount - 1 do
    if ANode[mIndex].Kind = TSyntaxKind.TypeReference then
      Result := Result + [ANode[mIndex]];
end;

/// <summary>Position von ANode unter den Argumenten seines Aufrufs (1 = erstes); 0, wenn ANode kein Argument ist.
/// </summary>
function ArgumentPosition(ANode: TSyntaxNode): Integer;
var
  mParent: TSyntaxNode;
  mIndex: Integer;
begin
  Result := 0;
  mParent := ANode.Parent;
  if (mParent = nil) or (mParent.Kind <> TSyntaxKind.Call) then
    Exit;
  for mIndex := 1 to mParent.ChildCount - 1 do
    if mParent[mIndex] = ANode then
      Exit(mIndex);
end;

{ TTypeKindChecker }

constructor TTypeKindChecker.Create(const AContext: TRuleContext; const AReport: IRuleReport;
  AResolver: TNameResolver);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FResolver := AResolver;
  FFileName := ResolverFileName(AContext);
  FUsesKnown := (AContext.Index <> nil) and TUnresolvedNames.UsesKnown(AContext.Index,
    TUsesClauses.UsedUnits(AContext.Tree.Tokens), AContext.Namespaces, AContext.EnsureUnit);
end;

function TTypeKindChecker.NodeText(ANode: TSyntaxNode): string;
begin
  Result := Copy(FContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

function TTypeKindChecker.Range(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

function TTypeKindChecker.ValueType(ANode: TSyntaxNode; out ASymbol, AType: TResolvedSymbol;
  out AKind: TResolvedTypeKind): Boolean;
var
  mNode: TSyntaxNode;
  mFound: Boolean;
begin
  AKind := TResolvedTypeKind.Unknown;
  mNode := ANode;
  while (mNode.Kind = TSyntaxKind.ParenExpr) and (mNode.ChildCount = 1) do
    mNode := mNode[0];
  Result := (mNode.Kind in cExpressionKinds) and
    FResolver.NodeType(FContext.Tree, FFileName, mNode, ASymbol, AType, mFound) and mFound and
    not ASymbol.IsType and (ASymbol.Kind in [TResolvedKind.Symbol, TResolvedKind.Local]) and
    (ASymbol.SymbolKind in cValueKinds) and (ASymbol.Condition = '') and (ASymbol.VariantBranch = '') and
    (AType.TypeParams = '');
  if Result then
  begin
    AKind := TResolvedTypeKinds.OfType(AType);
    Result := AKind <> TResolvedTypeKind.Unknown;
  end;
end;

function TTypeKindChecker.ReferencedKind(ATypeRef: TSyntaxNode; out AType: TResolvedSymbol): TResolvedTypeKind;
var
  mResolved: TResolvedSymbol;
  mName: string;
begin
  Result := TResolvedTypeKind.Unknown;
  AType := Default(TResolvedSymbol);
  mName := Trim(ATypeRef.Name);
  if (mName = '') or ContainsStr(mName, '<') then
    Exit;
  if (Pos('.', mName) = 0) and TNameResolver.IsBuiltinTypeName(mName) then
  begin
    Result := TResolvedTypeKinds.OfBuiltin(mName);
    AType.Name := mName;
    Exit;
  end;
  mResolved := FResolver.ResolveChain(FContext.Tree, FFileName, mName.Split(['.']), ATypeRef.StartOffset);
  if not mResolved.Found or not mResolved.IsType or (mResolved.Condition <> '') or
    not FResolver.TypeOf(mResolved, AType) then
    Exit;
  if AType.TypeParams <> '' then
    Exit;
  Result := TResolvedTypeKinds.OfType(AType);
end;

function TTypeKindChecker.HelperPossible(const ASymbol, AType: TResolvedSymbol; ANode: TSyntaxNode): Boolean;
var
  mHelper: TResolvedSymbol;
  mNames: TArray<string>;
  mName: string;
begin
  if not FUsesKnown then
    Exit(True);
  // Helfer gelten auch für eingebaute Aliase (TIntegerHelper für LongInt) und für den Alias, mit dem der Wert
  // deklariert ist (record helper for TZahl mit TZahl = Integer).
  mNames := TArray<string>.Create(AType.Name, TTypeIdentity.BuiltinName(AType.Name), DeclaredTypeText(ASymbol));
  for mName in mNames do
    if (mName <> '') and IsValidIdent(mName, True) and
      FResolver.VisibleHelper(FContext.Tree, FFileName, mName, ANode.StartOffset, mHelper) then
      Exit(True);
  Result := False;
end;

function TTypeKindChecker.HasImplicit(const AType: TResolvedSymbol): Boolean;
var
  mMember: TResolvedSymbol;
begin
  Result := FResolver.FindMember(AType, 'Implicit', mMember);
end;

function TTypeKindChecker.IsIntrinsic(ACall: TSyntaxNode; const AName: string): Boolean;
var
  mCallee: TSyntaxNode;
  mSymbol, mType: TResolvedSymbol;
  mFound: Boolean;
begin
  Result := False;
  if (ACall.Kind <> TSyntaxKind.Call) or (ACall.ChildCount = 0) then
    Exit;
  mCallee := ACall[0];
  if (mCallee.Kind <> TSyntaxKind.Identifier) or not SameText(mCallee.Name, AName) then
    Exit;
  // Ohne Deklaration im Index ist es die eingebaute Routine, sofern keine unbekannte Unit eine gleichnamige bringt.
  if not FResolver.NodeType(FContext.Tree, FFileName, mCallee, mSymbol, mType, mFound) then
    Exit(FUsesKnown);
  Result := mSymbol.Builtin or SameText(mSymbol.UnitName, 'System');
end;

function TTypeKindChecker.DeclaredTypeText(const ASymbol: TResolvedSymbol): string;
var
  mNode, mDecl: TSyntaxNode;
  mIndex: Integer;
begin
  Result := Trim(ASymbol.TypeName);
  if Result <> '' then
    Exit;
  Result := TResolvedTypeKinds.DeclaredText(ASymbol.Signature);
  if (Result <> '') or (ASymbol.Kind <> TResolvedKind.Local) then
    Exit;
  // Lokale Variable mit Typ ohne Namen (mZeiger: ^Byte): Text des Typknotens ihrer Deklaration, die innerste
  // um den Namen.
  mDecl := nil;
  for mNode in PreOrder(FContext.Tree.Root) do
    if (mNode.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.Parameter, TSyntaxKind.Field, TSyntaxKind.InlineVar]) and
      Covers(mNode, ASymbol.SelectionRange.StartPos) then
      mDecl := mNode;
  if mDecl <> nil then
    for mIndex := 0 to mDecl.ChildCount - 1 do
      if mDecl[mIndex].Kind in [TSyntaxKind.TypeReference, TSyntaxKind.PointerType, TSyntaxKind.ArrayType,
        TSyntaxKind.FileType, TSyntaxKind.SetType] then
        Exit(Trim(NodeText(mDecl[mIndex])));
end;

function TTypeKindChecker.PointeeName(ANode: TSyntaxNode): string;
var
  mSymbol, mType: TResolvedSymbol;
  mFound: Boolean;
  mText: string;
begin
  Result := '';
  if not (ANode.Kind in cExpressionKinds) or
    not FResolver.NodeType(FContext.Tree, FFileName, ANode, mSymbol, mType, mFound) or mSymbol.IsType or
    not (mSymbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field]) or (mSymbol.Condition <> '') then
    Exit;
  mText := DeclaredTypeText(mSymbol);
  if not StartsStr('^', mText) and mFound and not mType.Builtin and
    (mType.SymbolKind = TIndexSymbolKind.TypeAlias) then
    mText := TResolvedTypeKinds.DeclaredText(mType.Signature);
  if StartsStr('^', mText) then
    Result := Trim(Copy(mText, 2, MaxInt));
end;

function TTypeKindChecker.IsTextFile(ANode: TSyntaxNode): Boolean;
var
  mSymbol, mType: TResolvedSymbol;
  mFound: Boolean;
  mText: string;
begin
  Result := False;
  if not (ANode.Kind in cExpressionKinds) or
    not FResolver.NodeType(FContext.Tree, FFileName, ANode, mSymbol, mType, mFound) or mSymbol.IsType or
    not (mSymbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field]) then
    Exit;
  mText := DeclaredTypeText(mSymbol);
  if StartsText('System.', mText) then
    mText := Copy(mText, 8, MaxInt);
  Result := MatchText(mText, ['Text', 'TextFile']);
  if not Result and mFound and not mType.Builtin and (mType.SymbolKind = TIndexSymbolKind.TypeAlias) then
    Result := MatchText(TResolvedTypeKinds.DeclaredText(mType.Signature), ['Text', 'TextFile']);
end;

procedure TTypeKindChecker.CheckIndex(ANode: TSyntaxNode);
var
  mSymbol, mType: TResolvedSymbol;
  mKind: TResolvedTypeKind;
begin
  // Properties mit Index und Funktionen ohne Klammern sehen im Baum gleich aus; nur Variablen, Felder, Konstanten.
  if (ANode.ChildCount = 0) or not ValueType(ANode[0], mSymbol, mType, mKind) or
    not (mSymbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field, TIndexSymbolKind.Constant]) or
    not TResolvedTypeKinds.IsSimpleValue(mKind) or HelperPossible(mSymbol, mType, ANode) then
    Exit;
  FReport.Add(Range(ANode), Format('%s ist %s (%s), kein Array; ein Index ist hier nicht möglich (wie E2016).',
    [NodeText(ANode[0]), TResolvedTypeKinds.Describe(mKind), mType.Name]), TRuleConfidence.High);
end;

procedure TTypeKindChecker.CheckDereference(ANode: TSyntaxNode);
var
  mSymbol, mType: TResolvedSymbol;
  mKind: TResolvedTypeKind;
  mFixes: TArray<TRuleFix>;
  mBase: string;
begin
  if (ANode.ChildCount <> 1) or not ValueType(ANode[0], mSymbol, mType, mKind) then
    Exit;
  if not TResolvedTypeKinds.IsSimpleValue(mKind) and not (mKind in [TResolvedTypeKind.Class_,
    TResolvedTypeKind.Record_, TResolvedTypeKind.Interface_]) then
    Exit;
  mBase := NodeText(ANode[0]);
  mFixes := nil;
  // Obj^.Feld: Klassen und Interfaces sind schon Verweise, Records erreicht der Punkt direkt.
  if not TResolvedTypeKinds.IsSimpleValue(mKind) and (ANode.Parent <> nil) and
    (ANode.Parent.Kind = TSyntaxKind.MemberAccess) and (ANode.Parent.ChildCount > 0) and
    (ANode.Parent[0] = ANode) then
    mFixes := [TRuleFix.Create('^ entfernen', [TTextEdit.Create(Range(ANode), mBase)], True)];
  FReport.Add(Range(ANode), Format('%s ist %s (%s), kein Zeiger; ^ ist hier nicht möglich (wie E2017).',
    [mBase, TResolvedTypeKinds.Describe(mKind), mType.Name]), TRuleConfidence.High, mFixes);
end;

procedure TTypeKindChecker.CheckMember(ANode: TSyntaxNode);
var
  mSymbol, mType, mMember: TResolvedSymbol;
  mKind: TResolvedTypeKind;
begin
  // X.TryGetValue<Integer>: Der Parser legt um X.TryGetValue einen Knoten gleichen Namens mit den Typargumenten;
  // das ist kein Punkt auf dem Ergebnis.
  if (ANode.ChildCount > 1) and (ANode[ANode.ChildCount - 1].Kind = TSyntaxKind.GenericArgs) then
    Exit;
  if (ANode.ChildCount = 0) or not ValueType(ANode[0], mSymbol, mType, mKind) or
    not TResolvedTypeKinds.IsSimpleValue(mKind) or HelperPossible(mSymbol, mType, ANode) or
    FResolver.FindMember(mType, ANode.Name, mMember) then
    Exit;
  FReport.Add(Range(ANode), Format('%s ist %s (%s), kein Record, keine Klasse und kein object-Typ; .%s ist hier ' +
    'nicht möglich (wie E2018).', [NodeText(ANode[0]), TResolvedTypeKinds.Describe(mKind), mType.Name, ANode.Name]),
    TRuleConfidence.High);
end;

procedure TTypeKindChecker.CheckWith(ANode: TSyntaxNode);
var
  mIndex: Integer;
  mElement: TSyntaxNode;
  mSymbol, mType: TResolvedSymbol;
  mKind: TResolvedTypeKind;
begin
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    mElement := ANode[mIndex];
    if not (mElement.Kind in cExpressionKinds + [TSyntaxKind.ParenExpr]) or
      not ValueType(mElement, mSymbol, mType, mKind) or not TResolvedTypeKinds.IsSimpleValue(mKind) or
      HelperPossible(mSymbol, mType, mElement) then
      Continue;
    FReport.Add(Range(mElement), Format('with braucht einen Record, eine Klasse oder einen object-Typ; %s ist %s ' +
      '(%s) (wie E2018).', [NodeText(mElement), TResolvedTypeKinds.Describe(mKind), mType.Name]),
      TRuleConfidence.High);
  end;
end;

procedure TTypeKindChecker.CheckObjectType(ANode: TSyntaxNode);
var
  mRefs: TArray<TSyntaxNode>;
  mType: TResolvedSymbol;
  mKind: TResolvedTypeKind;
begin
  mRefs := TypeReferences(ANode);
  if Length(mRefs) = 0 then
    Exit;
  mKind := ReferencedKind(mRefs[0], mType);
  if not (mKind in [TResolvedTypeKind.Class_, TResolvedTypeKind.Record_, TResolvedTypeKind.Interface_,
    TResolvedTypeKind.Helper]) then
    Exit;
  FReport.Add(Range(mRefs[0]), Format('Der Vorfahr eines object-Typs muss ein object-Typ sein; %s ist %s ' +
    '(wie E2019).', [mRefs[0].Name, TResolvedTypeKinds.Describe(mKind)]), TRuleConfidence.High);
end;

procedure TTypeKindChecker.CheckClassType(ANode: TSyntaxNode);
var
  mRefs: TArray<TSyntaxNode>;
  mType: TResolvedSymbol;
  mKind: TResolvedTypeKind;
begin
  mRefs := TypeReferences(ANode);
  if Length(mRefs) = 0 then
    Exit;
  mKind := ReferencedKind(mRefs[0], mType);
  if (mKind in [TResolvedTypeKind.Unknown, TResolvedTypeKind.Class_, TResolvedTypeKind.Interface_,
    TResolvedTypeKind.Helper, TResolvedTypeKind.Object_]) then
    Exit;
  FReport.Add(Range(mRefs[0]), Format('Der Vorfahr einer Klasse muss eine Klasse sein; %s ist %s (wie E2021).',
    [mRefs[0].Name, TResolvedTypeKinds.Describe(mKind)]), TRuleConfidence.High);
end;

procedure TTypeKindChecker.CheckHelperType(ANode: TSyntaxNode);
var
  mRefs: TArray<TSyntaxNode>;
  mType: TResolvedSymbol;
  mKind: TResolvedTypeKind;
  mTarget: TSyntaxNode;
begin
  mRefs := TypeReferences(ANode);
  if Length(mRefs) = 0 then
    Exit;
  mTarget := mRefs[High(mRefs)];
  if SameText(ANode.Name, 'class') and (Length(mRefs) = 2) then
  begin
    // class helper (TVorfahr) for TZiel: Der Vorfahr muss selbst ein Class-Helper sein.
    mKind := ReferencedKind(mRefs[0], mType);
    if mKind in [TResolvedTypeKind.Class_, TResolvedTypeKind.Record_, TResolvedTypeKind.Interface_,
      TResolvedTypeKind.Object_] then
      FReport.Add(Range(mRefs[0]), Format('Der Vorfahr eines Class-Helpers muss ein Class-Helper sein; %s ist %s ' +
        '(wie E2022).', [mRefs[0].Name, TResolvedTypeKinds.Describe(mKind)]), TRuleConfidence.High);
  end
  else if SameText(ANode.Name, 'record') then
  begin
    mKind := ReferencedKind(mTarget, mType);
    if mKind in [TResolvedTypeKind.Class_, TResolvedTypeKind.Interface_] then
      FReport.Add(Range(mTarget), Format('Ein Record-Helper braucht einen Record oder einfachen Typ; %s ist %s, ' +
        'dafür gibt es class helper (wie E2474).', [mTarget.Name, TResolvedTypeKinds.Describe(mKind)]),
        TRuleConfidence.High);
  end;
end;

procedure TTypeKindChecker.CheckConstructorForm(ANode: TSyntaxNode);
var
  mPointee, mRoutine, mCode: string;
  mKind: TResolvedTypeKind;
begin
  // New(P, Init) bzw. Dispose(P, Done): erweiterte Form nur für Zeiger auf object-Typen.
  if ANode.ChildCount < 3 then
    Exit;
  if IsIntrinsic(ANode, 'New') then
  begin
    mRoutine := 'New mit Konstruktor braucht einen Zeiger auf einen Record oder object-Typ';
    mCode := 'E2467';
  end
  else if IsIntrinsic(ANode, 'Dispose') then
  begin
    mRoutine := 'Dispose mit Destruktor braucht einen Zeiger auf einen object-Typ';
    mCode := 'E2019';
  end
  else
    Exit;
  mPointee := PointeeName(ANode[1]);
  if (mPointee = '') or not TNameResolver.IsBuiltinTypeName(mPointee) then
    Exit;
  mKind := TResolvedTypeKinds.OfBuiltin(mPointee);
  if not TResolvedTypeKinds.IsSimpleValue(mKind) then
    Exit;
  FReport.Add(Range(ANode[1]), Format('%s; %s zeigt auf %s (wie %s).', [mRoutine, NodeText(ANode[1]), mPointee,
    mCode]), TRuleConfidence.High);
end;

procedure TTypeKindChecker.CheckTypeOf(ANode: TSyntaxNode);
var
  mSymbol, mType: TResolvedSymbol;
  mKind: TResolvedTypeKind;
begin
  if (ANode.ChildCount <> 2) or not IsIntrinsic(ANode, 'TypeOf') or
    not ValueType(ANode[1], mSymbol, mType, mKind) or not TResolvedTypeKinds.IsSimpleValue(mKind) then
    Exit;
  FReport.Add(Range(ANode[1]), Format('TypeOf braucht einen object-Typ mit VMT; %s ist %s (%s) (wie E2019).',
    [NodeText(ANode[1]), TResolvedTypeKinds.Describe(mKind), mType.Name]), TRuleConfidence.High);
end;

procedure TTypeKindChecker.CheckSlice(ANode: TSyntaxNode);
var
  mParent: TSyntaxNode;
  mPosition: Integer;
  mCandidates: TArray<TResolvedSymbol>;
  mCandidate: TResolvedSymbol;
  mKind: TResolvedTypeKind;
  mParam: string;
begin
  if not IsIntrinsic(ANode, 'Slice') then
    Exit;
  mParent := ANode.Parent;
  if mParent = nil then
    Exit;
  mPosition := ArgumentPosition(ANode);
  if mPosition = 0 then
  begin
    // Als Wert einer Zuweisung, in einem Ausdruck oder als Startwert einer Inline-Variablen.
    if not (mParent.Kind in [TSyntaxKind.AssignStatement, TSyntaxKind.BinaryExpr, TSyntaxKind.InlineVar]) then
      Exit;
  end
  else
  begin
    // Argument eines Aufrufs: nur, wenn jede mögliche Routine dort einen Parameter einfacher Art erwartet.
    mCandidates := FResolver.CallCandidates(FContext.Tree, FFileName, mParent[0]);
    if Length(mCandidates) = 0 then
      Exit;
    for mCandidate in mCandidates do
    begin
      if mCandidate.Builtin or not (mCandidate.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine]) or
        (Length(mCandidate.ParamTypes) < mPosition) then
        Exit;
      mParam := mCandidate.ParamTypes[mPosition - 1];
      mKind := TResolvedTypeKinds.OfText(mParam);
      if (mKind = TResolvedTypeKind.Unknown) or (mKind = TResolvedTypeKind.Array_) then
        Exit;
    end;
  end;
  FReport.Add(Range(ANode), 'Slice ist nur als Argument für einen offenen Array-Parameter möglich (wie E2193).',
    TRuleConfidence.High);
end;

procedure TTypeKindChecker.CheckConstArray(ANode: TSyntaxNode);
var
  mPosition, mIndex: Integer;
  mCandidates: TArray<TResolvedSymbol>;
  mCandidate, mSymbol, mType: TResolvedSymbol;
  mKind: TResolvedTypeKind;
  mElement: TSyntaxNode;
begin
  mPosition := ArgumentPosition(ANode);
  if mPosition = 0 then
    Exit;
  mCandidates := FResolver.CallCandidates(FContext.Tree, FFileName, ANode.Parent[0]);
  if Length(mCandidates) = 0 then
    Exit;
  for mCandidate in mCandidates do
    if mCandidate.Builtin or (Length(mCandidate.ParamTypes) < mPosition) or
      not SameText(Trim(mCandidate.ParamTypes[mPosition - 1]), 'array of const') then
      Exit;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    mElement := ANode[mIndex];
    if not ValueType(mElement, mSymbol, mType, mKind) or (mKind <> TResolvedTypeKind.Record_) or
      HasImplicit(mType) then
      Continue;
    FReport.Add(Range(mElement), Format('%s ist ein Record (%s); array of const nimmt keine Records (wie E2150).',
      [NodeText(mElement), mType.Name]), TRuleConfidence.High);
  end;
end;

procedure TTypeKindChecker.CheckTextIo(ANode: TSyntaxNode; AWrite: Boolean);
var
  mFirst, mIndex: Integer;
  mArg: TSyntaxNode;
  mSymbol, mType: TResolvedSymbol;
  mKind: TResolvedTypeKind;
  mText, mRoutine: string;
  mFixes: TArray<TRuleFix>;
begin
  if ANode.ChildCount < 2 then
    Exit;
  mRoutine := ANode[0].Name;
  mFirst := 1;
  mArg := ANode[1];
  if (mArg.Kind = TSyntaxKind.Identifier) and MatchText(mArg.Name, cStandardTextFiles) and
    not ValueType(mArg, mSymbol, mType, mKind) then
    // Input, Output, ErrOutput aus System, auch ohne System im Index.
    mFirst := 2
  else if IsTextFile(mArg) then
    mFirst := 2
  else
  begin
    if not ValueType(mArg, mSymbol, mType, mKind) or (mKind = TResolvedTypeKind.File_) then
      // Unbekanntes erstes Argument oder typisierte Datei (Write(F, Datensatz)).
      Exit;
  end;
  for mIndex := mFirst to ANode.ChildCount - 1 do
  begin
    mArg := ANode[mIndex];
    if not ValueType(mArg, mSymbol, mType, mKind) or not (mKind in [TResolvedTypeKind.Class_,
      TResolvedTypeKind.Record_, TResolvedTypeKind.Interface_]) or
      ((mKind = TResolvedTypeKind.Record_) and HasImplicit(mType)) then
      Continue;
    mText := NodeText(mArg);
    mFixes := nil;
    if AWrite then
    begin
      if mKind = TResolvedTypeKind.Class_ then
        mFixes := [TRuleFix.Create(mText + '.ToString', [TTextEdit.Create(Range(mArg), mText + '.ToString')])];
      FReport.Add(Range(mArg), Format('%s kann %s nicht ausgeben: %s ist %s (wie E2054).', [mRoutine, mText,
        mType.Name, TResolvedTypeKinds.Describe(mKind)]), TRuleConfidence.High, mFixes);
    end
    else
      FReport.Add(Range(mArg), Format('%s kann %s nicht einlesen: %s ist %s (wie E2055).', [mRoutine, mText,
        mType.Name, TResolvedTypeKinds.Describe(mKind)]), TRuleConfidence.High);
  end;
end;

procedure TTypeKindChecker.CheckClassMethodForm(ANode: TSyntaxNode);
var
  mBase, mOuter: TSyntaxNode;
  mBaseSymbol, mBaseType, mMember, mMemberType, mCandidate, mOwner, mOwnerType: TResolvedSymbol;
  mFound, mComplete: Boolean;
  mCandidates: TArray<TResolvedSymbol>;
  mName, mClassPart: string;
  mAncestors: TArray<string>;
begin
  // TBasis.Machen als Anweisung oder vor Klammern.
  if (ANode.ChildCount <> 1) or (ANode.Parent = nil) then
    Exit;
  if not ((ANode.Parent.Kind = TSyntaxKind.CallStatement) or ((ANode.Parent.Kind = TSyntaxKind.Call) and
    (ANode.Parent[0] = ANode))) then
    Exit;
  mBase := ANode[0];
  if (mBase.Kind <> TSyntaxKind.Identifier) or
    not FResolver.NodeType(FContext.Tree, FFileName, mBase, mBaseSymbol, mBaseType, mFound) or
    not mBaseSymbol.IsType or (mBaseSymbol.SymbolKind <> TIndexSymbolKind.ClassType) or
    (mBaseSymbol.TypeParams <> '') or (mBaseSymbol.Condition <> '') then
    Exit;
  if not FResolver.NodeType(FContext.Tree, FFileName, ANode, mMember, mMemberType, mFound) or
    (mMember.SymbolKind <> TIndexSymbolKind.Method) or (mMember.Condition <> '') then
    Exit;
  mCandidates := FResolver.CallCandidates(FContext.Tree, FFileName, ANode);
  if Length(mCandidates) = 0 then
    Exit;
  for mCandidate in mCandidates do
    if (mCandidate.SymbolKind <> TIndexSymbolKind.Method) or MatchText('class', mCandidate.Directives) or
      MatchText('static', mCandidate.Directives) or StartsText('class ', Trim(mCandidate.Signature)) then
      Exit;
  // In Methoden der Klasse und ihrer Nachfahren ruft TBasis.Machen die Methode mit Self auf.
  mOuter := ANode.Parent;
  while mOuter <> nil do
  begin
    if (mOuter.Kind = TSyntaxKind.RoutineDecl) and (Pos('.', mOuter.Name) > 0) then
    begin
      mName := mOuter.Name;
      mClassPart := Copy(mName, 1, LastDelimiter('.', mName) - 1);
      mOwner := FResolver.ResolveChain(FContext.Tree, FFileName, mClassPart.Split(['.']), mOuter.StartOffset);
      if not mOwner.Found or not FResolver.TypeOf(mOwner, mOwnerType) or
        (mOwnerType.SymbolKind <> TIndexSymbolKind.ClassType) then
        Exit;
      if SameText(mOwnerType.QualifiedName, mBaseType.QualifiedName) then
        Exit;
      mAncestors := FResolver.AncestorNames(mOwnerType, mComplete);
      if not mComplete or MatchText(mBaseType.Name, mAncestors) then
        Exit;
    end;
    mOuter := mOuter.Parent;
  end;
  FReport.Add(Range(ANode), Format('%s ist keine Klassenmethode; %s.%s geht nur in Methoden von %s und seinen ' +
    'Nachfahren (wie E2076).', [mMember.Name, mBase.Name, ANode.Name, mBaseType.Name]), TRuleConfidence.High);
end;

procedure TTypeKindChecker.CheckCall(ANode: TSyntaxNode);
var
  mCallee: string;
begin
  if (ANode.ChildCount = 0) or (ANode[0].Kind <> TSyntaxKind.Identifier) then
    Exit;
  mCallee := ANode[0].Name;
  if MatchText(mCallee, ['New', 'Dispose']) then
    CheckConstructorForm(ANode)
  else if SameText(mCallee, 'TypeOf') then
    CheckTypeOf(ANode)
  else if SameText(mCallee, 'Slice') then
    CheckSlice(ANode)
  else if MatchText(mCallee, ['Write', 'Writeln']) and IsIntrinsic(ANode, mCallee) then
    CheckTextIo(ANode, True)
  else if MatchText(mCallee, ['Read', 'Readln']) and IsIntrinsic(ANode, mCallee) then
    CheckTextIo(ANode, False);
end;

procedure TTypeKindChecker.Run;
var
  mNode: TSyntaxNode;
begin
  for mNode in PreOrder(FContext.Tree.Root) do
    case mNode.Kind of
      TSyntaxKind.IndexAccess:
        CheckIndex(mNode);
      TSyntaxKind.Dereference:
        CheckDereference(mNode);
      TSyntaxKind.MemberAccess:
        begin
          CheckMember(mNode);
          CheckClassMethodForm(mNode);
        end;
      TSyntaxKind.WithStatement:
        CheckWith(mNode);
      TSyntaxKind.ObjectType:
        CheckObjectType(mNode);
      TSyntaxKind.ClassType:
        CheckClassType(mNode);
      TSyntaxKind.HelperType:
        CheckHelperType(mNode);
      TSyntaxKind.Call:
        CheckCall(mNode);
      TSyntaxKind.SetConstructor:
        CheckConstArray(mNode);
    else
      // Übrige Knoten verlangen keine Typart.
    end;
end;

{ TTypeKindRequiredRule }

function TTypeKindRequiredRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(TypeKindRequiredRuleId, TRuleSeverity.Error,
    'Ausdruck oder Deklaration hat nicht die geforderte Typart');
end;

procedure TTypeKindRequiredRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mResolver: TNameResolver;
  mChecker: TTypeKindChecker;
  mFileName: string;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  mFileName := ResolverFileName(AContext);
  mResolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit, AContext.TreeUnits);
  try
    mResolver.Namespaces := AContext.Namespaces;
    mResolver.PinTree(AContext.Tree, mFileName);
    try
      mChecker := TTypeKindChecker.Create(AContext, AReport, mResolver);
      try
        mChecker.Run;
      finally
        mChecker.Free;
      end;
    finally
      mResolver.UnpinTree;
    end;
  finally
    mResolver.Free;
  end;
end;

procedure RegisterTypeKindRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TTypeKindRequiredRule.Create);
end;

end.
