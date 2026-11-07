unit Atlas.Common.Lsp.DataFlow.Base;

// Datenfluss (#690): Grundstufe eines Laufs. Löst Symbole auf, findet Vorkommen und Parameter, sammelt die
// Quellen eines Werts und fasst gleiche Stellen zu einem Knoten zusammen. Woher steht in .Sources, Wohin in
// .Targets.

interface

uses
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.DataFlow.Types,
  Atlas.Common.Lsp.DataFlow.Files;

type
  TDataFlowBase = class
  protected
    FResolver: TNameResolver;
    FIndex: ISymbolIndex;
    FOptions: TDataFlowOptions;
    FCancellation: IJsonRpcCancellationToken;
    FFiles: TDataFlowFiles;
    FNodes: TList<TDataFlowNode>;
    FGroups: TDictionary<string, Integer>;
    /// <summary>Schlüssel des gefragten Symbols (Zyklus).</summary>
    FCurrentKey: string;
    procedure CheckCancelled;
    /// <summary>Stellen dieser Datei fallen weg (Tests, außerhalb des Projekts).</summary>
    function Excluded(const AFileName: string): Boolean;
    function LeafOf(const ASymbol: TDataFlowSymbol): TDataFlowLeaf;
    function ResolvedAt(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
      out AResolved: TResolvedSymbol): Boolean;
    /// <summary>Symbol an APosition; Result steht für die umgebende Funktion.</summary>
    function ResolveSymbol(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
      out ASymbol: TDataFlowSymbol): Boolean;
    function FunctionOf(ATree: TSyntaxTree; const AFileName: string; ARoutine: TSyntaxNode;
      out ASymbol: TDataFlowSymbol): Boolean;
    function EnclosingFunction(ATree: TSyntaxTree; const AFileName: string; ANode: TSyntaxNode;
      out ASymbol: TDataFlowSymbol): Boolean;
    function ParamsOf(const AFileName: string; const APosition: TTextPosition): TArray<TDataFlowParam>;
    function Occurrences(const ASymbol: TDataFlowSymbol): TArray<TReferenceLocation>;
    procedure AddSource(var ANode: TDataFlowNode; const ASymbol: TDataFlowSymbol);
    /// <summary>Symbole, Literale und unsichere Teile des Ausdrucks AExpr in ANode.</summary>
    procedure CollectValue(ATree: TSyntaxTree; const AFileName: string; AExpr: TSyntaxNode;
      var ANode: TDataFlowNode);
    procedure AddNode(const ANode: TDataFlowNode);
    function NewNode(const ASpot: TDataFlowSpot; const AEdge: TDataFlowEdge): TDataFlowNode;
    /// <summary>Stelle mit dem Wert AValue; seine Symbole werden die Quellen.</summary>
    procedure AddValueNode(const ASpot: TDataFlowSpot; ATree: TSyntaxTree; AValue: TSyntaxNode;
      const AVia, AUnsafeReason: string);
    /// <summary>Stelle, deren Wert in ATarget geht bzw. aus ihm kommt.</summary>
    procedure AddTargetNode(const ASpot: TDataFlowSpot; const ATarget: TDataFlowSymbol; const AEdge: TDataFlowEdge);
    /// <summary>Stelle ohne Quellen (Blatt).</summary>
    procedure AddLeafNode(const ASpot: TDataFlowSpot; const AEdge: TDataFlowEdge);
    /// <summary>Geschriebenes Symbol von AExpr (Liste[I], P^ führen zu Liste bzw. P).</summary>
    function TargetRoot(ATree: TSyntaxTree; const AFileName: string; AExpr: TSyntaxNode;
      var AUnsafeReason: string; out ASymbol: TDataFlowSymbol): Boolean;
  public
    constructor Create(const ARequest: TDataFlowRequest);
    destructor Destroy; override;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Lsp.Definition,
  Atlas.Common.Lsp.DataFlow.Syntax;

type
  /// <summary>Sammelt die Quellen eines Ausdrucks in eine Stelle; eigener Stapel statt Rekursion (Bericht
  /// M1).</summary>
  TValueCollector = class
  private
    FRun: TDataFlowBase;
    FTree: TSyntaxTree;
    FFileName: string;
    FPending: TStack<TSyntaxNode>;
    FNode: TDataFlowNode;
    procedure PushChildren(ANode: TSyntaxNode; AFrom: Integer);
    procedure PushFirst(ANode: TSyntaxNode);
    procedure MarkUnsafe(const AReason: string);
    procedure AddSymbolAt(const APosition: TTextPosition);
    procedure Identifier(ANode: TSyntaxNode);
    procedure Call(ANode: TSyntaxNode);
    procedure Visit(ANode: TSyntaxNode);
  public
    constructor Create(ARun: TDataFlowBase; ATree: TSyntaxTree; const AFileName: string);
    destructor Destroy; override;
    procedure Collect(AExpr: TSyntaxNode; var ANode: TDataFlowNode);
  end;

function SymbolFromResolved(const AResolved: TResolvedSymbol): TDataFlowSymbol;
begin
  Result := Default(TDataFlowSymbol);
  Result.Name := AResolved.Name;
  Result.FileName := AResolved.FileName;
  Result.Position := AResolved.SelectionRange.StartPos;
  Result.SymbolKind := AResolved.SymbolKind;
end;

function IsResultToken(ATree: TSyntaxTree; AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (ATree.Tokens[AIndex].Kind = TPascalTokenKind.Identifier) and
    SameText(ATree.Tokens[AIndex].Text, 'Result');
end;

/// <summary>Kopf der Routine an ANode (Deklaration oder Kopf selbst bzw. darüber); nil, wenn keiner.</summary>
function HeaderAt(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  if Result.Kind = TSyntaxKind.RoutineDecl then
  begin
    Result := Result.FindChild(TSyntaxKind.RoutineHeader);
  end;
  while (Result <> nil) and (Result.Kind <> TSyntaxKind.RoutineHeader) do
  begin
    Result := Result.Parent;
  end;
end;

{ TValueCollector }

constructor TValueCollector.Create(ARun: TDataFlowBase; ATree: TSyntaxTree; const AFileName: string);
begin
  inherited Create;
  FRun := ARun;
  FTree := ATree;
  FFileName := AFileName;
  FPending := TStack<TSyntaxNode>.Create;
end;

destructor TValueCollector.Destroy;
begin
  FPending.Free;
  inherited;
end;

procedure TValueCollector.PushChildren(ANode: TSyntaxNode; AFrom: Integer);
var
  mIndex: Integer;
begin
  for mIndex := ANode.ChildCount - 1 downto AFrom do
  begin
    FPending.Push(ANode[mIndex]);
  end;
end;

procedure TValueCollector.PushFirst(ANode: TSyntaxNode);
begin
  if ANode.ChildCount > 0 then
  begin
    FPending.Push(ANode[0]);
  end;
end;

procedure TValueCollector.MarkUnsafe(const AReason: string);
begin
  FNode.Unsafe := True;
  if FNode.UnsafeReason = '' then
  begin
    FNode.UnsafeReason := AReason;
  end;
end;

procedure TValueCollector.AddSymbolAt(const APosition: TTextPosition);
var
  mSymbol: TDataFlowSymbol;
begin
  if FRun.ResolveSymbol(FTree, FFileName, APosition, mSymbol) and not (mSymbol.SymbolKind in cTypeKinds) then
  begin
    FRun.AddSource(FNode, mSymbol);
  end;
end;

procedure TValueCollector.Identifier(ANode: TSyntaxNode);
var
  mName: string;
begin
  mName := LowerCase(ANode.Name);
  if (mName = 'nil') or (mName = 'true') or (mName = 'false') then
  begin
    FNode.Literal := True;
  end
  else
  begin
    AddSymbolAt(ANode.StartPos);
  end;
end;

procedure TValueCollector.Call(ANode: TSyntaxNode);
var
  mResolved: TResolvedSymbol;
  mOuter: Boolean;
begin
  // Routinen des Projekts liefern ihr Ergebnis; Typumwandlungen und Routinen von außen reichen die
  // Argumente durch.
  mOuter := True;
  if (ANode.ChildCount > 0) and FRun.ResolvedAt(FTree, FFileName, TDataFlowSyntax.NamePosition(FTree, ANode[0]),
    mResolved) and not (mResolved.SymbolKind in cTypeKinds) then
  begin
    if FRun.FFiles.InProject(mResolved.FileName) then
    begin
      FRun.AddSource(FNode, SymbolFromResolved(mResolved));
      mOuter := False;
    end
    else if FNode.Via = '' then
    begin
      FNode.Via := TDataFlowSyntax.ShortName(ANode.Name);
    end;
  end;
  if mOuter then
  begin
    PushChildren(ANode, 1);
  end;
end;

procedure TValueCollector.Visit(ANode: TSyntaxNode);
begin
  case ANode.Kind of
    TSyntaxKind.Literal:
      FNode.Literal := True;
    TSyntaxKind.Identifier:
      Identifier(ANode);
    TSyntaxKind.MemberAccess:
      AddSymbolAt(TDataFlowSyntax.NamePosition(FTree, ANode));
    TSyntaxKind.Call:
      Call(ANode);
    TSyntaxKind.IndexAccess:
      PushFirst(ANode);
    TSyntaxKind.Dereference:
      begin
        MarkUnsafe('pointer');
        PushFirst(ANode);
      end;
    TSyntaxKind.AddressOf:
      MarkUnsafe('address');
    TSyntaxKind.IfExpr:
      PushChildren(ANode, 1);
    TSyntaxKind.InheritedExpr, TSyntaxKind.AnonymousMethod, TSyntaxKind.GenericArgs:
      ;
  else
    PushChildren(ANode, 0);
  end;
end;

procedure TValueCollector.Collect(AExpr: TSyntaxNode; var ANode: TDataFlowNode);
begin
  FNode := ANode;
  FPending.Push(AExpr);
  while FPending.Count > 0 do
  begin
    Visit(FPending.Pop);
  end;
  ANode := FNode;
end;

{ TDataFlowBase }

constructor TDataFlowBase.Create(const ARequest: TDataFlowRequest);
begin
  inherited Create;
  FResolver := ARequest.Resolver;
  FIndex := ARequest.Index;
  FOptions := ARequest.Options;
  FCancellation := ARequest.Cancellation;
  FFiles := TDataFlowFiles.Create(ARequest);
  FNodes := TList<TDataFlowNode>.Create;
  FGroups := TDictionary<string, Integer>.Create;
end;

destructor TDataFlowBase.Destroy;
begin
  FGroups.Free;
  FNodes.Free;
  FFiles.Free;
  inherited;
end;

procedure TDataFlowBase.CheckCancelled;
begin
  if FCancellation <> nil then
  begin
    FCancellation.ThrowIfCancellationRequested;
  end;
end;

function TDataFlowBase.Excluded(const AFileName: string): Boolean;
begin
  Result := (FOptions.ExcludeTests and FFiles.IsTestFile(AFileName)) or
    (FOptions.OnlyProject and not FFiles.InProject(AFileName));
end;

function TDataFlowBase.LeafOf(const ASymbol: TDataFlowSymbol): TDataFlowLeaf;
var
  mKey, mAncestor: string;
begin
  Result := TDataFlowLeaf.None;
  if ASymbol.SymbolKind in cConstantKinds then
  begin
    Exit(TDataFlowLeaf.Constant);
  end;
  if not FFiles.InProject(ASymbol.FileName) then
  begin
    Exit(TDataFlowLeaf.Outside);
  end;
  mKey := ASymbol.Key;
  if mKey = FCurrentKey then
  begin
    Result := TDataFlowLeaf.Cycle;
  end;
  for mAncestor in FOptions.Path do
  begin
    if SameText(mAncestor, mKey) then
    begin
      Result := TDataFlowLeaf.Cycle;
    end;
  end;
end;

function TDataFlowBase.ResolvedAt(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
  out AResolved: TResolvedSymbol): Boolean;
begin
  AResolved := FResolver.Resolve(ATree, AFileName, APosition);
  Result := (AResolved.Kind in [TResolvedKind.Symbol, TResolvedKind.Local]) and (AResolved.FileName <> '');
end;

function TDataFlowBase.FunctionOf(ATree: TSyntaxTree; const AFileName: string; ARoutine: TSyntaxNode;
  out ASymbol: TDataFlowSymbol): Boolean;
var
  mHeader: TSyntaxNode;
  mName: string;
  mPosition: TTextPosition;
  mResolved: TResolvedSymbol;
begin
  mHeader := ARoutine;
  if ARoutine.Kind = TSyntaxKind.RoutineDecl then
  begin
    mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  end;
  Result := mHeader <> nil;
  if Result then
  begin
    mName := TDataFlowSyntax.ShortName(mHeader.Name);
    Result := TDataFlowSyntax.RoutineNamePosition(ATree, mHeader, mName, mPosition);
  end;
  if not Result then
  begin
    Exit;
  end;
  if ResolvedAt(ATree, AFileName, mPosition, mResolved) and (mResolved.SymbolKind in cRoutineKinds) then
  begin
    ASymbol := SymbolFromResolved(mResolved);
  end
  else
  begin
    ASymbol := Default(TDataFlowSymbol);
    ASymbol.Name := mName;
    ASymbol.FileName := AFileName;
    ASymbol.Position := mPosition;
    ASymbol.SymbolKind := TIndexSymbolKind.Routine;
  end;
end;

function TDataFlowBase.EnclosingFunction(ATree: TSyntaxTree; const AFileName: string; ANode: TSyntaxNode;
  out ASymbol: TDataFlowSymbol): Boolean;
var
  mCurrent: TSyntaxNode;
begin
  mCurrent := ANode;
  // Result in einer anonymen Methode gehört zu ihr, nicht zur Routine außen.
  while (mCurrent <> nil) and (mCurrent.Kind <> TSyntaxKind.AnonymousMethod) and
    not ((mCurrent.Kind = TSyntaxKind.RoutineDecl) and (mCurrent.FindChild(TSyntaxKind.Block) <> nil)) do
  begin
    mCurrent := mCurrent.Parent;
  end;
  Result := (mCurrent <> nil) and (mCurrent.Kind <> TSyntaxKind.AnonymousMethod) and
    FunctionOf(ATree, AFileName, mCurrent, ASymbol);
end;

function TDataFlowBase.ResolveSymbol(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
  out ASymbol: TDataFlowSymbol): Boolean;
var
  mIndex: Integer;
  mResolved: TResolvedSymbol;
  mTargets: TArray<TDefinitionTarget>;
begin
  ASymbol := Default(TDataFlowSymbol);
  mIndex := TDataFlowSyntax.TokenIndexAt(ATree, APosition);
  // Result steht für die Funktion, in der es vorkommt.
  if IsResultToken(ATree, mIndex) then
  begin
    Exit(EnclosingFunction(ATree, AFileName, TDataFlowSyntax.NodeAt(ATree.Root, APosition), ASymbol));
  end;
  if ResolvedAt(ATree, AFileName, APosition, mResolved) then
  begin
    ASymbol := SymbolFromResolved(mResolved);
    Exit(True);
  end;
  mTargets := TLspDefinition.Targets(FResolver, FIndex, ATree, AFileName, APosition, True);
  Result := Length(mTargets) > 0;
  if Result then
  begin
    ASymbol.FileName := mTargets[0].FileName;
    ASymbol.Position := mTargets[0].SelectionRange.StartPos;
    ASymbol.SymbolKind := TIndexSymbolKind.Variable;
    if mIndex >= 0 then
    begin
      ASymbol.Name := TDataFlowSyntax.CleanName(ATree.Tokens[mIndex].Text);
    end;
  end;
end;

function TDataFlowBase.ParamsOf(const AFileName: string; const APosition: TTextPosition): TArray<TDataFlowParam>;
var
  mTree: TSyntaxTree;
  mHeader, mParameters, mParameter: TSyntaxNode;
  mIndex: Integer;
  mName: string;
  mParam: TDataFlowParam;
begin
  Result := nil;
  mTree := FFiles.TreeOf(AFileName);
  mHeader := nil;
  if mTree <> nil then
  begin
    mHeader := HeaderAt(TDataFlowSyntax.NodeAt(mTree.Root, APosition));
  end;
  mParameters := nil;
  if mHeader <> nil then
  begin
    mParameters := mHeader.FindChild(TSyntaxKind.Parameters);
  end;
  if mParameters = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mParameters.ChildCount - 1 do
  begin
    mParameter := mParameters[mIndex];
    if mParameter.Kind <> TSyntaxKind.Parameter then
    begin
      Continue;
    end;
    for mName in mParameter.Name.Split([',']) do
    begin
      mParam := Default(TDataFlowParam);
      mParam.Name := Trim(mName);
      mParam.Modifier := mParameter.Modifier;
      mParam.FileName := AFileName;
      if not TDataFlowSyntax.NameInNode(mTree, mParameter, TDataFlowSyntax.CleanName(mParam.Name),
        mParam.Position) then
      begin
        mParam.Position := mParameter.StartPos;
      end;
      Result := Result + [mParam];
    end;
  end;
end;

function TDataFlowBase.Occurrences(const ASymbol: TDataFlowSymbol): TArray<TReferenceLocation>;
var
  mTree: TSyntaxTree;
begin
  Result := nil;
  mTree := FFiles.TreeOf(ASymbol.FileName);
  if mTree <> nil then
  begin
    Result := TLspReferences.Find(FResolver, FIndex, mTree, TReferenceSearch.Create(ASymbol.FileName,
      ASymbol.Position, True, FFiles.Files, FFiles.ReadText), FCancellation);
  end;
end;

procedure TDataFlowBase.AddSource(var ANode: TDataFlowNode; const ASymbol: TDataFlowSymbol);
var
  mExisting: TDataFlowSymbol;
  mSymbol: TDataFlowSymbol;
begin
  for mExisting in ANode.Sources do
  begin
    if mExisting.Key = ASymbol.Key then
    begin
      Exit;
    end;
  end;
  mSymbol := ASymbol;
  mSymbol.Leaf := LeafOf(mSymbol);
  ANode.Sources := ANode.Sources + [mSymbol];
end;

procedure TDataFlowBase.CollectValue(ATree: TSyntaxTree; const AFileName: string; AExpr: TSyntaxNode;
  var ANode: TDataFlowNode);
var
  mCollector: TValueCollector;
begin
  if AExpr = nil then
  begin
    Exit;
  end;
  mCollector := TValueCollector.Create(Self, ATree, AFileName);
  try
    mCollector.Collect(AExpr, ANode);
  finally
    mCollector.Free;
  end;
end;

procedure TDataFlowBase.AddNode(const ANode: TDataFlowNode);
var
  mKey: string;
  mSource: TDataFlowSymbol;
  mSlot: Integer;
  mExisting: TDataFlowNode;
begin
  if Length(ANode.Places) = 0 then
  begin
    Exit;
  end;
  mKey := IntToStr(Ord(ANode.Kind)) + '|' + ANode.Detail + '|' + ANode.Via + '|' + ANode.UnsafeReason;
  for mSource in ANode.Sources do
  begin
    mKey := mKey + '|' + mSource.Key;
  end;
  if FGroups.TryGetValue(mKey, mSlot) then
  begin
    mExisting := FNodes[mSlot];
    mExisting.Places := mExisting.Places + ANode.Places;
    FNodes[mSlot] := mExisting;
  end
  else if FNodes.Count < cMaxDataFlowNodes then
  begin
    FGroups.Add(mKey, FNodes.Add(ANode));
  end;
end;

function TDataFlowBase.NewNode(const ASpot: TDataFlowSpot; const AEdge: TDataFlowEdge): TDataFlowNode;
begin
  Result := Default(TDataFlowNode);
  Result.Kind := ASpot.Kind;
  Result.Places := [FFiles.Place(ASpot.FileName, ASpot.Position)];
  Result.Detail := AEdge.Detail;
  Result.Via := AEdge.Via;
  Result.Unsafe := AEdge.UnsafeReason <> '';
  Result.UnsafeReason := AEdge.UnsafeReason;
end;

procedure TDataFlowBase.AddValueNode(const ASpot: TDataFlowSpot; ATree: TSyntaxTree; AValue: TSyntaxNode;
  const AVia, AUnsafeReason: string);
var
  mNode: TDataFlowNode;
begin
  if Excluded(ASpot.FileName) then
  begin
    Exit;
  end;
  mNode := NewNode(ASpot, TDataFlowEdge.Create(FFiles.ExprText(ASpot.FileName, AValue), AVia, AUnsafeReason));
  CollectValue(ATree, ASpot.FileName, AValue, mNode);
  AddNode(mNode);
end;

procedure TDataFlowBase.AddTargetNode(const ASpot: TDataFlowSpot; const ATarget: TDataFlowSymbol;
  const AEdge: TDataFlowEdge);
var
  mNode: TDataFlowNode;
begin
  if Excluded(ASpot.FileName) then
  begin
    Exit;
  end;
  mNode := NewNode(ASpot, AEdge);
  AddSource(mNode, ATarget);
  AddNode(mNode);
end;

procedure TDataFlowBase.AddLeafNode(const ASpot: TDataFlowSpot; const AEdge: TDataFlowEdge);
begin
  if not Excluded(ASpot.FileName) then
  begin
    AddNode(NewNode(ASpot, AEdge));
  end;
end;

function TDataFlowBase.TargetRoot(ATree: TSyntaxTree; const AFileName: string; AExpr: TSyntaxNode;
  var AUnsafeReason: string; out ASymbol: TDataFlowSymbol): Boolean;
var
  mCurrent: TSyntaxNode;
begin
  Result := False;
  mCurrent := AExpr;
  // Liste[I] := … schreibt in Liste, P^ := … über einen Zeiger.
  while (mCurrent <> nil) and (mCurrent.Kind in [TSyntaxKind.IndexAccess, TSyntaxKind.Dereference]) and
    (mCurrent.ChildCount > 0) do
  begin
    if (mCurrent.Kind = TSyntaxKind.Dereference) and (AUnsafeReason = '') then
    begin
      AUnsafeReason := 'pointer';
    end;
    mCurrent := mCurrent[0];
  end;
  if (mCurrent <> nil) and (mCurrent.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
  begin
    Result := ResolveSymbol(ATree, AFileName, TDataFlowSyntax.NamePosition(ATree, mCurrent), ASymbol);
  end;
end;

end.
