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
    MaxNames = 100;
  public
    /// <summary>True, wenn der Index die Unit System kennt und die Prüfung damit aussagekräftig ist.</summary>
    class function Available(const AIndex: ISymbolIndex): Boolean; static;
    /// <summary>Kennt der Index (oder AEnsureUnit) alle Units aus AUnits, auch über ANamespaces? Sonst kann ein
    /// Name aus einer unbekannten Unit stammen, und die Prüfung schweigt.</summary>
    class function UsesKnown(const AIndex: ISymbolIndex; const AUnits, ANamespaces: TArray<string>;
      const AEnsureUnit: TEnsureUnitFunc): Boolean; static;
    /// <summary>Nicht auflösbare Namen in ATree, höchstens MaxNames.</summary>
    class function Find(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string): TArray<TUnresolvedName>; static;
    /// <summary>Vom Compiler eingebaute Routinen und Konstanten ohne Deklaration in System.pas.</summary>
    class function IsIntrinsic(const AName: string): Boolean; static;
    /// <summary>Meldung zu einem Eintrag mit Code (E2601, E2602, E2078); '' ohne Code.</summary>
    class function Describe(const AName: TUnresolvedName): string; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Semantics.SystemIntrinsics;

const
  // Sonderfälle zusätzlich zu TSystemIntrinsics (dort die Bezeichner von System ohne Quelltext, #880).
  Intrinsics: array[0..63] of string = (
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
  Name: string;
begin
  // Dieselbe Liste wie Hover und Namensauflösung: Sqr, Pi, Int … fehlten hier und galten als nicht deklariert.
  if TSystemIntrinsics.IsKnown(AName) then
  begin
    Exit(True);
  end;
  for Name in Intrinsics do
  begin
    if SameText(Name, AName) then
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
    Result := Format('"%s" ist kein Konstruktor von %s; New braucht einen Konstruktor des object-Typs (wie E2601).',
      [AName.Name, AName.Owner]);
  end
  else if AName.Code = 'E2602' then
  begin
    Result := Format('"%s" ist kein Destruktor von %s; Dispose braucht einen Destruktor des object-Typs ' +
      '(wie E2602).', [AName.Name, AName.Owner]);
  end
  else if AName.Code = 'E2078' then
  begin
    Result := 'Fail ist nur im Konstruktor eines object-Typs erlaubt (wie E2078).';
  end
  else
  begin
    Result := '';
  end;
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
  mTarget := mPointer.Signature;
  if Pos('^', mTarget) = 0 then
  begin
    Exit(False);
  end;
  mTarget := Trim(Copy(mTarget, Pos('^', mTarget) + 1, MaxInt));
  if EndsStr(';', mTarget) then
  begin
    mTarget := Trim(Copy(mTarget, 1, Length(mTarget) - 1));
  end;
  if (mTarget = '') or not IsValidIdent(mTarget, True) then
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
  SystemUnit: TUnitIndex;
begin
  Result := (AIndex <> nil) and AIndex.FindUnit('System', SystemUnit);
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
  Name, Namespace: string;
  Found: TUnitIndex;
  Known: Boolean;
begin
  for Name in AUnits do
  begin
    Known := AIndex.FindUnit(Name, Found);
    for Namespace in ANamespaces do
    begin
      if not Known then
      begin
        Known := AIndex.FindUnit(Namespace + '.' + Name, Found);
      end;
    end;
    if not Known and Assigned(AEnsureUnit) then
    begin
      Known := AEnsureUnit(Name);
    end;
    if not Known then
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
  Declared: TDictionary<string, Boolean>;
  // Konstruktor- und Destruktornamen in New/Dispose (#1382): keine eigenen Bezeichner.
  mMembers: TDictionary<TSyntaxNode, Boolean>;

  function IsDeclared(const AName: string): Boolean;
  begin
    Result := Declared.ContainsKey(UpperCase(AName));
  end;

  // Namen, die die Grundstufe nicht sicher als lokal kennt: Ausnahmevariablen und Inline-Variablen.
  procedure CollectDeclared(ARoot: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ mit eigenem Stapel (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind in [TSyntaxKind.ExceptionHandler, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst,
          TSyntaxKind.LabeledStatement, TSyntaxKind.GotoStatement]) and (Node.Name <> '') then
        begin
          Declared.AddOrSetValue(UpperCase(Node.Name), True);
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

  /// <summary>New(P, Init) bzw. Dispose(P, Done) mit der Routine aus System (#1382): Den Namen des Konstruktors
  /// bzw. Destruktors merken; fehlt er im object-Typ hinter P, Eintrag mit E2601 bzw. E2602.</summary>
  procedure CheckAllocation(ACall: TSyntaxNode);
  var
    mMember: TSyntaxNode;
    mType, mFound: TResolvedSymbol;
    mComplete: Boolean;
    mItem: TUnresolvedName;
  begin
    if (ACall.ChildCount < 3) or (ACall[0].Kind <> TSyntaxKind.Identifier) or
      not MatchText(ACall[0].Name, ['New', 'Dispose']) or IsDeclared(ACall[0].Name) or
      AResolver.ResolveChain(ATree, AFileName, [ACall[0].Name], ACall[0].StartOffset).Found then
    begin
      Exit;
    end;
    mMember := ACall[2];
    if (mMember.Kind = TSyntaxKind.Call) and (mMember.ChildCount > 0) then
    begin
      mMember := mMember[0];
    end;
    if (mMember.Kind <> TSyntaxKind.Identifier) or (mMember.Name = '') then
    begin
      Exit;
    end;
    mMembers.AddOrSetValue(mMember, True);
    if not ObjectTarget(AResolver, ATree, AFileName, ACall[1], mType) then
    begin
      Exit;
    end;
    AResolver.Queries.AncestorNames(mType, mComplete);
    if not mComplete then
    begin
      Exit;
    end;
    if AResolver.FindMember(mType, mMember.Name, mFound) then
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

  procedure Visit(ARoot: TSyntaxNode);
  var
    Pending: TStack<TUnresolvedEntry>;
    Entry: TUnresolvedEntry;
    Node: TSyntaxNode;
    InStatements: Boolean;
    Index: Integer;
    Resolved: TResolvedSymbol;
    Item: TUnresolvedName;
  begin
    // Iterativ mit eigenem Stapel (Bericht M1); die Kinder rückwärts darauf, damit Reihenfolge und Grenze
    // MaxNames dieselben bleiben wie in der früheren Rekursion.
    Pending := TStack<TUnresolvedEntry>.Create;
    try
      Pending.Push(UnresolvedEntry(ARoot, False));
      while (Pending.Count > 0) and (Length(Result) < MaxNames) do
      begin
        Entry := Pending.Pop;
        Node := Entry.Node;
        InStatements := Entry.InStatements;
        if Node.Kind in [TSyntaxKind.WithStatement, TSyntaxKind.AsmBlock, TSyntaxKind.AnonymousMethod,
          TSyntaxKind.Error] then
        begin
          Continue;
        end;
        // Anweisungen stehen in Blöcken von Routinen und in initialization/finalization.
        if Node.Kind in [TSyntaxKind.Block, TSyntaxKind.InitializationSection, TSyntaxKind.FinalizationSection] then
        begin
          InStatements := True;
        end
        else if Node.Kind in [TSyntaxKind.VarSection, TSyntaxKind.ConstSection, TSyntaxKind.TypeSection,
          TSyntaxKind.RoutineHeader, TSyntaxKind.Parameters, TSyntaxKind.GenericArgs] then
        begin
          InStatements := False;
        end;
        if InStatements and (Node.Kind = TSyntaxKind.Call) then
        begin
          CheckAllocation(Node);
        end;
        if InStatements and (Node.Kind = TSyntaxKind.Identifier) and (Node.Name <> '') then
        begin
          CheckFail(Node);
        end;
        // Typumwandlungen und Typhelfer (Integer(X), string.Join) sowie der Anfang eines Unit-Namens
        // (Winapi in Winapi.Windows.TextOut) sind keine fehlenden Bezeichner (#647).
        if InStatements and (Node.Kind = TSyntaxKind.Identifier) and (Node.Name <> '') and
          not IsIntrinsic(Node.Name) and not IsDeclared(Node.Name) and
          not TResolverText.IsBuiltinTypeName(Node.Name) and not mMembers.ContainsKey(Node) then
        begin
          // IsUnitPrefix erst danach: ResolveChain legt die Unit und den Abschnitt fest.
          Resolved := AResolver.ResolveChain(ATree, AFileName, [Node.Name], Node.StartOffset);
          if not Resolved.Found and not AResolver.IsUnitPrefix(Node.Name) and not AResolver.HasUnknownAncestor then
          begin
            Item.Name := Node.Name;
            Item.Range := TTextRange.Create(Node.StartPos, Node.EndPos);
            AResolver.Queries.ScopedEnumValue(ATree, AFileName, Node.Name, Node.StartOffset, Item.Suggestion);
            Result := Result + [Item];
          end;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(UnresolvedEntry(Node[Index], InStatements));
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  Declared := TDictionary<string, Boolean>.Create;
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
    Declared.Free;
  end;
end;

end.
