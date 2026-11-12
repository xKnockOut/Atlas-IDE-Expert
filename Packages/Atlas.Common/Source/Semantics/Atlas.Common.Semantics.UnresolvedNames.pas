unit Atlas.Common.Semantics.UnresolvedNames;

// Bezeichner, die sich nicht auflösen lassen (#178), für das MCP-Werkzeug
// check_code. Bewusst vorsichtig, weil die Namensauflösung nur die
// Grundstufe kennt:
// - geprüft wird nur der erste Name einer Kette (A in A.B.C) in
//   Anweisungen, nicht in Deklarationen;
// - with-Blöcke, asm und anonyme Methoden werden übersprungen;
// - Compiler-Intrinsics (Length, Inc, Exit, …) gelten als bekannt;
// - ohne Unit System im Index wird gar nichts gemeldet, weil dann jeder
//   RTL-Name fehlen würde.
// Alte object-Syntax (#1382): In New(P, Init) und Dispose(P, Done) ist das
// zweite Argument ein Konstruktor bzw. Destruktor des object-Typs hinter P,
// kein eigener Bezeichner. Fehlt er in diesem Typ (samt bekannten Vorfahren),
// lautet der Befund wie E2601 bzw. E2602; Fail außerhalb eines Konstruktors
// wie E2078. Ist der Typ hinter P kein object-Typ oder unbekannt, bleibt der
// Name still (E2467 und E2019 gehören zu anderen Regeln).

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver;

type
  TUnresolvedName = record
    Name: string;
    Range: TTextRange;
    /// <summary>Gemeinter Name, z. B. TState.Error für einen Wert unter {$SCOPEDENUMS ON} (#849); sonst ''.
    /// </summary>
    Suggestion: string;
    /// <summary>'' für einen nicht deklarierten Namen (E2003); E2601 bzw. E2602 für einen fehlenden Konstruktor
    /// bzw. Destruktor in New/Dispose, E2078 für Fail außerhalb eines Konstruktors (#1382).</summary>
    Code: string;
    /// <summary>Bei E2601 und E2602 der object-Typ hinter dem Zeiger.</summary>
    Owner: string;
  end;

  TUnresolvedNames = class
  public const
    cMaxNames = 100;
  public
    /// <summary>True, wenn der Index die Unit System kennt und die Prüfung damit aussagekräftig ist.</summary>
    class function Available(const AIndex: ISymbolIndex): Boolean; static;
    /// <summary>Kennt der Index (oder AEnsureUnit) alle Units aus AUnits, auch über ANamespaces? Sonst kann ein
    /// Name aus einer unbekannten Unit stammen, und die Prüfung schweigt.</summary>
    class function UsesKnown(const AIndex: ISymbolIndex; const AUnits, ANamespaces: TArray<string>;
      const AEnsureUnit: TEnsureUnitFunc): Boolean; static;
    /// <summary>Nicht auflösbare Namen in ATree, höchstens MaxNames.</summary>
    class function Find(AResolver: TNameResolver; ATree: TSyntaxTree;
      const AFileName: string): TArray<TUnresolvedName>; static;
    /// <summary>Vom Compiler eingebaute Routinen und Konstanten ohne Deklaration in System.pas.</summary>
    class function IsIntrinsic(const AName: string): Boolean; static;
    /// <summary>Meldung zu einem Eintrag mit Code (E2601, E2602, E2078); '' ohne Code.</summary>
    class function Describe(const AName: TUnresolvedName): string; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Semantics.SystemIntrinsics,
  Atlas.Common.Localization.Texts;

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TUnresolvedNamesText = (IsNotAConstructorOf, IsNotADestructorOf, FailIsOnlyAllowedIn);

const
  cTexts: array[TUnresolvedNamesText] of TAtlasText = (
    (De: '"%s" ist kein Konstruktor von %s; New braucht einen Konstruktor des object-Typs (wie E2601).';
     En: '"%s" is not a constructor of %s; New needs a constructor of the object type (like E2601).'),
    (De: '"%s" ist kein Destruktor von %s; Dispose braucht einen Destruktor des object-Typs (wie E2602).';
     En: '"%s" is not a destructor of %s; Dispose needs a destructor of the object type (like E2602).'),
    (De: 'Fail ist nur im Konstruktor eines object-Typs erlaubt (wie E2078).';
     En: 'Fail is only allowed in the constructor of an object type (like E2078).'));

const
  // Sonderfälle zusätzlich zu TSystemIntrinsics (dort die Bezeichner von System ohne Quelltext, #880).
  cIntrinsics: array[0..63] of string = (
    'Abs', 'Addr', 'Assert', 'Assigned', 'AtomicCmpExchange', 'AtomicDecrement', 'AtomicExchange',
    'AtomicIncrement', 'Break', 'Chr', 'Concat', 'Continue', 'Copy', 'Dec', 'Default',
    'Delete', 'Dispose', 'Exclude', 'Exit', 'False', 'FillChar', 'Finalize', 'GetTypeKind', 'Halt', 'HasWeakRef',
    'Hi', 'High', 'Inc', 'Include', 'Initialize', 'Insert', 'IsConstValue', 'IsManagedType', 'Length', 'Lo', 'Low',
    'Move', 'NameOf', 'New', 'nil', 'Odd', 'Ord', 'Pred', 'Ptr', 'Read', 'ReadLn', 'Result', 'Round', 'Self',
    'SetLength',
    'SetString', 'SizeOf', 'Slice', 'Str', 'Succ', 'Swap', 'True', 'Trunc', 'TypeInfo', 'Write', 'WriteLn',
    // Konstanten aus System.pas, die im Index fehlen können (Ursache nicht geprüft, #647).
    'MaxInt', 'MaxLongint',
    // Aus SysInit, das der Compiler immer einbindet.
    'HInstance');

class function TUnresolvedNames.IsIntrinsic(const AName: string): Boolean;
var
  mName: string;
begin
  // Dieselbe Liste wie Hover und Namensauflösung: Sqr, Pi, Int … fehlten hier und galten als nicht deklariert.
  if TSystemIntrinsics.IsKnown(AName) then
  begin
    Exit(True);
  end;
  for mName in cIntrinsics do
  begin
    if SameText(mName, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TUnresolvedNames.Describe(const AName: TUnresolvedName): string;
begin
  if AName.Code = 'E2601' then
  begin
    Result := cTexts[TUnresolvedNamesText.IsNotAConstructorOf].Fmt([AName.Name, AName.Owner]);
  end
  else if AName.Code = 'E2602' then
  begin
    Result := cTexts[TUnresolvedNamesText.IsNotADestructorOf].Fmt([AName.Name, AName.Owner]);
  end
  else if AName.Code = 'E2078' then
  begin
    Result := cTexts[TUnresolvedNamesText.FailIsOnlyAllowedIn].Text;
  end
  else
  begin
    Result := '';
  end;
end;

/// <summary>Name hinter "^" in der Signatur eines Zeigertyps (PAltObjekt = ^TAltObjekt); False ohne gültigen Namen.
/// </summary>
function PointerTarget(const ASignature: string; out ATarget: string): Boolean;
begin
  ATarget := '';
  if Pos('^', ASignature) > 0 then
  begin
    ATarget := Trim(Copy(ASignature, Pos('^', ASignature) + 1, MaxInt));
  end;
  if EndsStr(';', ATarget) then
  begin
    ATarget := Trim(Copy(ATarget, 1, Length(ATarget) - 1));
  end;
  Result := (ATarget <> '') and IsValidIdent(ATarget, True);
end;

/// <summary>Object-Typ hinter dem Zeiger APointer (Variable oder Zeigertyp wie PAltObjekt = ^TAltObjekt).
/// </summary>
function ObjectTarget(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string; APointer: TSyntaxNode;
  out AType: TResolvedSymbol): Boolean;
var
  mPointer: TResolvedSymbol;
  mTarget: string;
begin
  AType := Default(TResolvedSymbol);
  if APointer.Kind <> TSyntaxKind.Identifier then
  begin
    Exit(False);
  end;
  mPointer := AResolver.ResolveType(ATree, AFileName, APointer.StartPos);
  if not mPointer.Found then
  begin
    Exit(False);
  end;
  if mPointer.SymbolKind = TIndexSymbolKind.ObjectType then
  begin
    AType := mPointer;
    Exit(True);
  end;
  if not PointerTarget(mPointer.Signature, mTarget) then
  begin
    Exit(False);
  end;
  AType := AResolver.ResolveChain(ATree, AFileName, mTarget.Split(['.']), APointer.StartOffset);
  Result := AType.Found and (AType.SymbolKind = TIndexSymbolKind.ObjectType);
end;

/// <summary>Liegt ANode im Rumpf eines Konstruktors (nächste umgebende Routine)?</summary>
function InConstructor(ATree: TSyntaxTree; ANode: TSyntaxNode): Boolean;
var
  mNode: TSyntaxNode;
  mToken: TPascalToken;
begin
  mNode := ANode.Parent;
  while (mNode <> nil) and (mNode.Kind <> TSyntaxKind.RoutineDecl) do
  begin
    mNode := mNode.Parent;
  end;
  if mNode = nil then
  begin
    Exit(False);
  end;
  for mToken in ATree.Tokens do
  begin
    if mToken.Offset >= mNode.StartOffset then
    begin
      if mToken.IsKeyword('constructor') then
      begin
        Exit(True);
      end;
      if not mToken.IsKeyword('class') and not (mToken.Kind in [TPascalTokenKind.Comment,
        TPascalTokenKind.Directive]) then
      begin
        Exit(False);
      end;
    end;
  end;
  Result := False;
end;

class function TUnresolvedNames.Available(const AIndex: ISymbolIndex): Boolean;
var
  mSystemUnit: TUnitIndex;
begin
  Result := (AIndex <> nil) and AIndex.FindUnit('System', mSystemUnit);
end;

type
  /// <summary>Eintrag in TUnresolvedNames.Find: Knoten und ob er in Anweisungen liegt.</summary>
  TUnresolvedEntry = record
    Node: TSyntaxNode;
    InStatements: Boolean;
  end;

function UnresolvedEntry(ANode: TSyntaxNode; AInStatements: Boolean): TUnresolvedEntry;
begin
  Result.Node := ANode;
  Result.InStatements := AInStatements;
end;

class function TUnresolvedNames.UsesKnown(const AIndex: ISymbolIndex; const AUnits, ANamespaces: TArray<string>;
  const AEnsureUnit: TEnsureUnitFunc): Boolean;
var
  mName, mNamespace: string;
  mFound: TUnitIndex;
  mKnown: Boolean;
begin
  for mName in AUnits do
  begin
    mKnown := AIndex.FindUnit(mName, mFound);
    for mNamespace in ANamespaces do
    begin
      if not mKnown then
      begin
        mKnown := AIndex.FindUnit(mNamespace + '.' + mName, mFound);
      end;
    end;
    if not mKnown and Assigned(AEnsureUnit) then
    begin
      mKnown := AEnsureUnit(mName);
    end;
    if not mKnown then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

class function TUnresolvedNames.Find(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName: string): TArray<TUnresolvedName>;
var
  // Nachschlagen statt Liste: bei vielen Inline-Variablen sonst ein Lauf je Bezeichner (Diagnoselog 15.10.2026).
  mDeclared: TDictionary<string, Boolean>;
  // Konstruktor- und Destruktornamen in New/Dispose (#1382): keine eigenen Bezeichner.
  mMembers: TDictionary<TSyntaxNode, Boolean>;

  function IsDeclared(const AName: string): Boolean;
  begin
    Result := mDeclared.ContainsKey(UpperCase(AName));
  end;

  // Namen, die die Grundstufe nicht sicher als lokal kennt: Ausnahmevariablen und Inline-Variablen.
  procedure CollectDeclared(ARoot: TSyntaxNode);
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
  begin
    // Iterativ mit eigenem Stapel.
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if (mNode.Kind in [TSyntaxKind.ExceptionHandler, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst,
          TSyntaxKind.LabeledStatement, TSyntaxKind.GotoStatement]) and (mNode.Name <> '') then
        begin
          mDeclared.AddOrSetValue(UpperCase(mNode.Name), True);
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

  /// <summary>Aufruf New(P, Init) bzw. Dispose(P, Done) der Routine aus System: Init bzw. Done in AMember.</summary>
  function AllocationMember(ACall: TSyntaxNode; out AMember: TSyntaxNode): Boolean;
  begin
    AMember := nil;
    if (ACall.ChildCount < 3) or (ACall[0].Kind <> TSyntaxKind.Identifier) or
      not MatchText(ACall[0].Name, ['New', 'Dispose']) or IsDeclared(ACall[0].Name) or
      AResolver.ResolveChain(ATree, AFileName, [ACall[0].Name], ACall[0].StartOffset).Found then
    begin
      Exit(False);
    end;
    AMember := ACall[2];
    if (AMember.Kind = TSyntaxKind.Call) and (AMember.ChildCount > 0) then
    begin
      AMember := AMember[0];
    end;
    Result := (AMember.Kind = TSyntaxKind.Identifier) and (AMember.Name <> '');
  end;

  /// <summary>Der object-Typ hinter APointer ist vollständig bekannt und hat kein Element AName.</summary>
  function MemberMissing(APointer: TSyntaxNode; const AName: string; out AType: TResolvedSymbol): Boolean;
  var
    mFound: TResolvedSymbol;
    mComplete: Boolean;
  begin
    Result := False;
    if ObjectTarget(AResolver, ATree, AFileName, APointer, AType) then
    begin
      AResolver.Queries.AncestorNames(AType, mComplete);
      Result := mComplete and not AResolver.FindMember(AType, AName, mFound);
    end;
  end;

  /// <summary>New(P, Init) bzw. Dispose(P, Done) mit der Routine aus System (#1382): Den Namen des Konstruktors
  /// bzw. Destruktors merken; fehlt er im object-Typ hinter P, Eintrag mit E2601 bzw. E2602.</summary>
  procedure CheckAllocation(ACall: TSyntaxNode);
  var
    mMember: TSyntaxNode;
    mType: TResolvedSymbol;
    mItem: TUnresolvedName;
  begin
    if not AllocationMember(ACall, mMember) then
    begin
      Exit;
    end;
    mMembers.AddOrSetValue(mMember, True);
    if not MemberMissing(ACall[1], mMember.Name, mType) then
    begin
      Exit;
    end;
    mItem := Default(TUnresolvedName);
    mItem.Name := mMember.Name;
    mItem.Range := TTextRange.Create(mMember.StartPos, mMember.EndPos);
    mItem.Owner := mType.Name;
    if SameText(ACall[0].Name, 'Dispose') then
    begin
      mItem.Code := 'E2602';
    end
    else
    begin
      mItem.Code := 'E2601';
    end;
    Result := Result + [mItem];
  end;

  /// <summary>Fail aus System außerhalb eines Konstruktors (#1382, wie E2078).</summary>
  procedure CheckFail(ANode: TSyntaxNode);
  var
    mItem: TUnresolvedName;
  begin
    if not SameText(ANode.Name, 'Fail') or IsDeclared(ANode.Name) or InConstructor(ATree, ANode) or
      AResolver.ResolveChain(ATree, AFileName, [ANode.Name], ANode.StartOffset).Found then
    begin
      Exit;
    end;
    mItem := Default(TUnresolvedName);
    mItem.Name := ANode.Name;
    mItem.Range := TTextRange.Create(ANode.StartPos, ANode.EndPos);
    mItem.Code := 'E2078';
    Result := Result + [mItem];
  end;

  /// <summary>Kann der Bezeichner ANode ein fehlender Name sein? Typumwandlungen und Typhelfer (Integer(X),
  /// string.Join) sowie der Anfang eines Unit-Namens (Winapi in Winapi.Windows.TextOut) nicht (#647).</summary>
  function IsCandidate(ANode: TSyntaxNode): Boolean;
  begin
    Result := not IsIntrinsic(ANode.Name) and not IsDeclared(ANode.Name) and
      not TResolverText.IsBuiltinTypeName(ANode.Name) and not mMembers.ContainsKey(ANode);
  end;

  /// <summary>Eintrag für den Bezeichner ANode, wenn er sich nicht auflösen lässt.</summary>
  procedure CheckIdentifier(ANode: TSyntaxNode);
  var
    mResolved: TResolvedSymbol;
    mItem: TUnresolvedName;
  begin
    if not IsCandidate(ANode) then
    begin
      Exit;
    end;
    // IsUnitPrefix erst danach: ResolveChain legt die Unit und den Abschnitt fest.
    mResolved := AResolver.ResolveChain(ATree, AFileName, [ANode.Name], ANode.StartOffset);
    if not mResolved.Found and not AResolver.IsUnitPrefix(ANode.Name) and not AResolver.HasUnknownAncestor then
    begin
      mItem := Default(TUnresolvedName);
      mItem.Name := ANode.Name;
      mItem.Range := TTextRange.Create(ANode.StartPos, ANode.EndPos);
      AResolver.Queries.ScopedEnumValue(ATree, AFileName, ANode.Name, ANode.StartOffset, mItem.Suggestion);
      Result := Result + [mItem];
    end;
  end;

  /// <summary>Anweisungen stehen in Blöcken von Routinen und in initialization/finalization.</summary>
  function InStatementsAt(ANode: TSyntaxNode; AInStatements: Boolean): Boolean;
  begin
    Result := AInStatements;
    if ANode.Kind in [TSyntaxKind.Block, TSyntaxKind.InitializationSection, TSyntaxKind.FinalizationSection] then
    begin
      Result := True;
    end
    else if ANode.Kind in [TSyntaxKind.VarSection, TSyntaxKind.ConstSection, TSyntaxKind.TypeSection,
      TSyntaxKind.RoutineHeader, TSyntaxKind.Parameters, TSyntaxKind.GenericArgs] then
    begin
      Result := False;
    end;
  end;

  /// <summary>Prüfungen eines Knotens in den Anweisungen.</summary>
  procedure CheckNode(ANode: TSyntaxNode);
  begin
    if ANode.Kind = TSyntaxKind.Call then
    begin
      CheckAllocation(ANode);
    end
    else if (ANode.Kind = TSyntaxKind.Identifier) and (ANode.Name <> '') then
    begin
      CheckFail(ANode);
      CheckIdentifier(ANode);
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    mPending: TStack<TUnresolvedEntry>;
    mEntry: TUnresolvedEntry;
    mInStatements: Boolean;
    mIndex: Integer;
  begin
    // Iterativ mit eigenem Stapel; die Kinder rückwärts darauf, damit Reihenfolge und Grenze
    // MaxNames dieselben bleiben wie in der früheren Rekursion.
    mPending := TStack<TUnresolvedEntry>.Create;
    try
      mPending.Push(UnresolvedEntry(ARoot, False));
      while (mPending.Count > 0) and (Length(Result) < cMaxNames) do
      begin
        mEntry := mPending.Pop;
        if mEntry.Node.Kind in [TSyntaxKind.WithStatement, TSyntaxKind.AsmBlock, TSyntaxKind.AnonymousMethod,
          TSyntaxKind.Error] then
        begin
          Continue;
        end;
        mInStatements := InStatementsAt(mEntry.Node, mEntry.InStatements);
        if mInStatements then
        begin
          CheckNode(mEntry.Node);
        end;
        for mIndex := mEntry.Node.ChildCount - 1 downto 0 do
        begin
          mPending.Push(UnresolvedEntry(mEntry.Node[mIndex], mInStatements));
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  mDeclared := TDictionary<string, Boolean>.Create;
  mMembers := TDictionary<TSyntaxNode, Boolean>.Create;
  try
    CollectDeclared(ATree.Root);
    AResolver.PinTree(ATree, AFileName);
    try
      Visit(ATree.Root);
    finally
      AResolver.UnpinTree;
    end;
  finally
    mMembers.Free;
    mDeclared.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Semantics.UnresolvedNames', cTexts);

end.
