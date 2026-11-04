unit Atlas.Common.Lsp.DataFlow.Sources;

// Datenfluss (#690), Woher: Zuweisungen (:=), var- und out-Argumente, Read/ReadLn (externe Eingabe),
// Initialisierungen, Schleifenvariablen, Schreiben über eine Property (write FFeld bzw. Setter), Inc/Dec und
// Verwandte. Ein Parameter führt zu den Argumenten aller Aufrufer (auch über eine Property mit diesem
// Setter), eine Funktion zu den Zuweisungen an Result bzw. ihren Namen und zu Exit(Wert), eine Property
// zusätzlich zum gelesenen Feld bzw. Getter.

interface

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.DataFlow.Types,
  Atlas.Common.Lsp.DataFlow.Base;

type
  TDataFlowSources = class(TDataFlowBase)
  protected
    procedure SourcesOf(const ASymbol: TDataFlowSymbol);
    /// <summary>Konstante: ein Blatt mit ihrem Wert.</summary>
    procedure ConstantSource(const ASymbol: TDataFlowSymbol; ATree: TSyntaxTree);
    /// <summary>Alle schreibenden Vorkommen des Symbols, dazu Aufrufer (Parameter) und Getter (Property).</summary>
    procedure WriteSources(const ASymbol: TDataFlowSymbol; ATree: TSyntaxTree);
    procedure ClassifyWrite(const ASymbol: TDataFlowSymbol; const ALocation: TReferenceLocation);
    /// <summary>Deklaration mit Wert: var X := …, X: T = …; X: T absolute Y ist eine unsichere Kante.</summary>
    procedure InitializerWrite(ATree: TSyntaxTree; const ALocation: TReferenceLocation; ANode: TSyntaxNode);
    procedure LoopWrite(const ASymbol: TDataFlowSymbol; ATree: TSyntaxTree; const ALocation: TReferenceLocation;
      ANode: TSyntaxNode);
    /// <summary>Vorkommen als Bezeichner: Ziel einer Zuweisung, sonst Argument, absolute oder Adresse.</summary>
    procedure UseWrite(const ASymbol: TDataFlowSymbol; ATree: TSyntaxTree; const ALocation: TReferenceLocation;
      ANode: TSyntaxNode);
    /// <summary>Name des Setters einer Property; leer bei write FFeld und für andere Symbole.</summary>
    function SetterOf(const ASymbol: TDataFlowSymbol): string;
    procedure IndirectWrite(const ASymbol: TDataFlowSymbol; ATree: TSyntaxTree; const ALocation: TReferenceLocation;
      ANode: TSyntaxNode; const AUnsafeReason: string);
    /// <summary>X: T absolute Y: Jede Zuweisung an X ändert Y.</summary>
    procedure AbsoluteWrite(ATree: TSyntaxTree; const ALocation: TReferenceLocation; ADeclaration: TSyntaxNode);
    procedure ArgumentWrite(const ASymbol: TDataFlowSymbol; const ASite: TDataFlowCallSite);
    /// <summary>Eingebaute Routinen, die ein Argument schreiben; False, wenn ASite keine ist.</summary>
    function BuiltinWrite(const ASymbol: TDataFlowSymbol; const ASite: TDataFlowCallSite): Boolean;
    procedure ModifyWrite(const ASymbol: TDataFlowSymbol; const ASite: TDataFlowCallSite);
    procedure FillCharWrite(const ASite: TDataFlowCallSite);
    /// <summary>Routine mit var- bzw. out-Parameter an dieser Stelle: Der Wert kommt aus ihrem Rumpf.</summary>
    procedure RoutineArgumentWrite(const ASite: TDataFlowCallSite);
    procedure CallerArguments(const ASymbol: TDataFlowSymbol; ADeclaration: TSyntaxNode);
    procedure CallerArgument(const ARoutine: TDataFlowSymbol; const ALocation: TReferenceLocation;
      AParamIndex: Integer; AIsLast: Boolean);
    procedure FunctionSources(const ASymbol: TDataFlowSymbol);
    /// <summary>Routine mit Rumpf im Projekt; nil ohne (Bibliothek, abstract, external).</summary>
    function FunctionBody(const ASymbol: TDataFlowSymbol; out ABodyFile: string): TSyntaxNode;
    procedure PropertyReads(const ASymbol: TDataFlowSymbol);
    /// <summary>Zuweisungen an die Property AProperty. Indizierte Properties: Der Wert ist der letzte Parameter
    /// des Setters, davor stehen die Indizes.</summary>
    procedure PropertyWrites(ATree: TSyntaxTree; const AFileName: string; AProperty: TSyntaxNode;
      AParamIndex: Integer);
    procedure PropertyWriteAt(const AProperty: TDataFlowSymbol; const ALocation: TReferenceLocation);
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Definition,
  Atlas.Common.Lsp.DataFlow.Syntax;

function IsInputCall(const AName: string; AArgument: Integer): Boolean;
begin
  Result := MatchText(AName, ['read', 'readln']) or (SameText(AName, 'blockread') and (AArgument = 1));
end;

function IsModifyCall(const AName: string; AArgument: Integer): Boolean;
begin
  Result := MatchText(AName, ['inc', 'dec', 'include', 'exclude', 'setlength', 'delete']) and (AArgument = 0) or
    SameText(AName, 'insert') and (AArgument = 1);
end;

/// <summary>Str, Val und Move schreiben das zweite Argument aus dem ersten.</summary>
function IsCopyCall(const ASite: TDataFlowCallSite): Boolean;
begin
  Result := MatchText(ASite.Callee, ['str', 'val', 'move']) and (ASite.Argument = 1) and (ASite.Call.ChildCount > 1);
end;

/// <summary>Kopf einer Routine über einem Parameter; nil bei anonymen Methoden und Prozedurtypen.</summary>
function CallableHeader(ADeclaration: TSyntaxNode): TSyntaxNode;
begin
  Result := ADeclaration;
  while (Result <> nil) and not (Result.Kind in [TSyntaxKind.RoutineHeader, TSyntaxKind.AnonymousMethod,
    TSyntaxKind.ProcedureType]) do
  begin
    Result := Result.Parent;
  end;
  if (Result <> nil) and (Result.Kind <> TSyntaxKind.RoutineHeader) then
  begin
    Result := nil;
  end;
end;

function ParamIndexOf(const AParams: TArray<TDataFlowParam>; const APosition: TTextPosition): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(AParams) do
  begin
    if AParams[mIndex].Position = APosition then
    begin
      Result := mIndex;
    end;
  end;
end;

function IsWrittenParam(const AParams: TArray<TDataFlowParam>; AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(AParams)) and
    (AParams[AIndex].Modifier in [TParameterModifier.VarParam, TParameterModifier.OutParam]);
end;

/// <summary>ACall ruft ANode auf und hat ein Argument AParamIndex.</summary>
function IsCallWithArgument(ACall, ANode: TSyntaxNode; AParamIndex: Integer): Boolean;
begin
  Result := (ACall <> nil) and (ACall.Kind = TSyntaxKind.Call) and (ACall[0] = ANode) and
    (AParamIndex + 1 < ACall.ChildCount);
end;

/// <summary>Result := … bzw. Name := … (Funktionsname).</summary>
function IsResultAssignment(ANode: TSyntaxNode; const AName: string): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount >= 2) and
    (ANode[0].Kind = TSyntaxKind.Identifier) and
    (SameText(ANode[0].Name, 'Result') or SameText(TDataFlowSyntax.CleanName(ANode[0].Name), AName));
end;

function IsExitWithValue(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 2) and (ANode[0].Kind = TSyntaxKind.Identifier) and
    SameText(ANode[0].Name, 'Exit');
end;

/// <summary>Zuweisungen an Result bzw. den Namen und Exit(Wert), ohne verschachtelte Routinen und anonyme
/// Methoden.</summary>
function ReturnStatements(ABlock: TSyntaxNode; const AName: string): TArray<TSyntaxNode>;
var
  mName: string;
  mReturns: TList<TSyntaxNode>;
begin
  mName := AName;
  mReturns := TList<TSyntaxNode>.Create;
  try
    ABlock.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := not (ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]);
        if IsResultAssignment(ANode, mName) or IsExitWithValue(ANode) then
        begin
          mReturns.Add(ANode);
        end;
      end);
    Result := mReturns.ToArray;
  finally
    mReturns.Free;
  end;
end;

{ TDataFlowSources }

procedure TDataFlowSources.SourcesOf(const ASymbol: TDataFlowSymbol);
var
  mTree: TSyntaxTree;
begin
  mTree := FFiles.TreeOf(ASymbol.FileName);
  if ASymbol.SymbolKind in cConstantKinds then
  begin
    ConstantSource(ASymbol, mTree);
  end
  else if not FFiles.InProject(ASymbol.FileName) or (mTree = nil) then
  begin
    AddLeafNode(TDataFlowSpot.Create(TDataFlowKind.Outside, ASymbol.FileName, ASymbol.Position),
      TDataFlowEdge.Create(ASymbol.Name, '', ''));
  end
  else if ASymbol.SymbolKind in cRoutineKinds then
  begin
    FunctionSources(ASymbol);
  end
  else
  begin
    WriteSources(ASymbol, mTree);
  end;
end;

procedure TDataFlowSources.ConstantSource(const ASymbol: TDataFlowSymbol; ATree: TSyntaxTree);
var
  mNode: TDataFlowNode;
  mDeclaration, mValue: TSyntaxNode;
begin
  mNode := NewNode(TDataFlowSpot.Create(TDataFlowKind.Constant, ASymbol.FileName, ASymbol.Position),
    TDataFlowEdge.Create(ASymbol.Name, '', ''));
  mNode.Literal := True;
  mDeclaration := nil;
  if ATree <> nil then
  begin
    mDeclaration := TDataFlowSyntax.NodeAt(ATree.Root, ASymbol.Position);
  end;
  if (mDeclaration <> nil) and (mDeclaration.Kind = TSyntaxKind.ConstDecl) and (mDeclaration.ChildCount > 0) then
  begin
    mValue := mDeclaration[mDeclaration.ChildCount - 1];
    if not (mValue.Kind in cTypeNodeKinds) then
    begin
      mNode.Detail := FFiles.ExprText(ASymbol.FileName, mValue);
    end;
  end;
  AddNode(mNode);
end;

procedure TDataFlowSources.WriteSources(const ASymbol: TDataFlowSymbol; ATree: TSyntaxTree);
var
  mLocation: TReferenceLocation;
  mDeclaration: TSyntaxNode;
begin
  for mLocation in Occurrences(ASymbol) do
  begin
    CheckCancelled;
    if not TDataFlowSyntax.IsFormFile(mLocation.FileName) then
    begin
      ClassifyWrite(ASymbol, mLocation);
    end;
  end;
  mDeclaration := TDataFlowSyntax.NodeAt(ATree.Root, ASymbol.Position);
  if mDeclaration.Kind = TSyntaxKind.Parameter then
  begin
    CallerArguments(ASymbol, mDeclaration);
  end;
  if ASymbol.SymbolKind = TIndexSymbolKind.Property_ then
  begin
    PropertyReads(ASymbol);
  end;
end;

procedure TDataFlowSources.ClassifyWrite(const ASymbol: TDataFlowSymbol; const ALocation: TReferenceLocation);
var
  mTree: TSyntaxTree;
  mNode: TSyntaxNode;
begin
  mTree := FFiles.TreeOf(ALocation.FileName);
  if mTree = nil then
  begin
    Exit;
  end;
  mNode := TDataFlowSyntax.NodeAt(mTree.Root, ALocation.Range.StartPos);
  case mNode.Kind of
    TSyntaxKind.VarDecl, TSyntaxKind.InlineVar:
      InitializerWrite(mTree, ALocation, mNode);
    TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement:
      LoopWrite(ASymbol, mTree, ALocation, mNode);
    TSyntaxKind.PropertyDecl:
      // Feld hinter write: Jede Zuweisung an die Property schreibt hinein.
      if (ASymbol.SymbolKind = TIndexSymbolKind.Field) and
        SameText(TDataFlowSyntax.AccessorBefore(mTree, ALocation.Range.StartPos), 'write') then
      begin
        PropertyWrites(mTree, ALocation.FileName, mNode, 0);
      end;
    TSyntaxKind.Identifier, TSyntaxKind.MemberAccess:
      UseWrite(ASymbol, mTree, ALocation, mNode);
  else
    // Andere Knoten (Typen, Köpfe, Abschnitte) schreiben nicht.
    ;
  end;
end;

procedure TDataFlowSources.InitializerWrite(ATree: TSyntaxTree; const ALocation: TReferenceLocation;
  ANode: TSyntaxNode);
var
  mValue: TSyntaxNode;
  mReason: string;
begin
  if ANode.ChildCount = 0 then
  begin
    Exit;
  end;
  mValue := ANode[ANode.ChildCount - 1];
  if mValue.Kind in cTypeNodeKinds then
  begin
    Exit;
  end;
  mReason := '';
  if SameText(TDataFlowSyntax.AccessorBefore(ATree, mValue.StartPos), 'absolute') then
  begin
    mReason := 'absolute';
  end;
  AddValueNode(TDataFlowSpot.Create(TDataFlowKind.Initializer, ALocation.FileName, ALocation.Range.StartPos), ATree,
    mValue, '', mReason);
end;

procedure TDataFlowSources.LoopWrite(const ASymbol: TDataFlowSymbol; ATree: TSyntaxTree;
  const ALocation: TReferenceLocation; ANode: TSyntaxNode);
var
  mLoop: TDataFlowNode;
  mIndex: Integer;
  mChild: TSyntaxNode;
begin
  if not SameText(TDataFlowSyntax.CleanName(ANode.Name), TDataFlowSyntax.CleanName(ASymbol.Name)) or
    Excluded(ALocation.FileName) then
  begin
    Exit;
  end;
  mLoop := NewNode(TDataFlowSpot.Create(TDataFlowKind.Loop, ALocation.FileName, ALocation.Range.StartPos),
    TDataFlowEdge.Create('', '', ''));
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    mChild := ANode[mIndex];
    if (mChild.Kind in cStatementKinds) or (mChild.Kind in cTypeNodeKinds) then
    begin
      Continue;
    end;
    if mLoop.Detail <> '' then
    begin
      mLoop.Detail := mLoop.Detail + ' .. ';
    end;
    mLoop.Detail := mLoop.Detail + FFiles.ExprText(ALocation.FileName, mChild);
    CollectValue(ATree, ALocation.FileName, mChild, mLoop);
  end;
  if ANode.Kind = TSyntaxKind.ForInStatement then
  begin
    mLoop.Via := 'in';
  end;
  AddNode(mLoop);
end;

procedure TDataFlowSources.UseWrite(const ASymbol: TDataFlowSymbol; ATree: TSyntaxTree;
  const ALocation: TReferenceLocation; ANode: TSyntaxNode);
var
  mStatement: TSyntaxNode;
  mReason: string;
begin
  mReason := '';
  if TDataFlowSyntax.WrittenTarget(ANode, mStatement, mReason) then
  begin
    AddValueNode(TDataFlowSpot.Create(TDataFlowKind.Assignment, ALocation.FileName, ALocation.Range.StartPos), ATree,
      mStatement[1], SetterOf(ASymbol), mReason);
  end
  else
  begin
    IndirectWrite(ASymbol, ATree, ALocation, ANode, mReason);
  end;
end;

function TDataFlowSources.SetterOf(const ASymbol: TDataFlowSymbol): string;
var
  mTree: TSyntaxTree;
  mDeclaration: TSyntaxNode;
  mPosition: TTextPosition;
  mSetter: TResolvedSymbol;
begin
  Result := '';
  mTree := nil;
  if ASymbol.SymbolKind = TIndexSymbolKind.Property_ then
  begin
    mTree := FFiles.TreeOf(ASymbol.FileName);
  end;
  if mTree = nil then
  begin
    Exit;
  end;
  mDeclaration := TDataFlowSyntax.NodeAt(mTree.Root, ASymbol.Position);
  if (mDeclaration.Kind = TSyntaxKind.PropertyDecl) and
    TDataFlowSyntax.Accessor(mTree, mDeclaration, 'write', mPosition) and
    ResolvedAt(mTree, ASymbol.FileName, mPosition, mSetter) and (mSetter.SymbolKind in cRoutineKinds) then
  begin
    Result := mSetter.Name;
  end;
end;

procedure TDataFlowSources.IndirectWrite(const ASymbol: TDataFlowSymbol; ATree: TSyntaxTree;
  const ALocation: TReferenceLocation; ANode: TSyntaxNode; const AUnsafeReason: string);
var
  mParent: TSyntaxNode;
  mPosition: TTextPosition;
begin
  mParent := ANode.Parent;
  if mParent = nil then
  begin
    Exit;
  end;
  mPosition := ALocation.Range.StartPos;
  if (mParent.Kind = TSyntaxKind.VarDecl) and SameText(TDataFlowSyntax.AccessorBefore(ATree, mPosition),
    'absolute') then
  begin
    AbsoluteWrite(ATree, ALocation, mParent);
  end
  else if (mParent.Kind = TSyntaxKind.Call) and (mParent[0] <> ANode) then
  begin
    ArgumentWrite(ASymbol, TDataFlowCallSite.Create(ATree, ALocation.FileName, mParent,
      TDataFlowSyntax.ChildIndex(mParent, ANode) - 1, mPosition, AUnsafeReason));
  end
  else if mParent.Kind = TSyntaxKind.AddressOf then
  begin
    // Über die Adresse kann der Wert sich überall ändern.
    AddLeafNode(TDataFlowSpot.Create(TDataFlowKind.Address, ALocation.FileName, mPosition),
      TDataFlowEdge.Create(FFiles.ExprText(ALocation.FileName, mParent), '', 'address'));
  end;
end;

procedure TDataFlowSources.AbsoluteWrite(ATree: TSyntaxTree; const ALocation: TReferenceLocation;
  ADeclaration: TSyntaxNode);
var
  mPosition: TTextPosition;
  mAlias: TDataFlowSymbol;
begin
  if TDataFlowSyntax.FirstDeclaredName(ATree, ADeclaration, mPosition) and
    ResolveSymbol(ATree, ALocation.FileName, mPosition, mAlias) then
  begin
    AddTargetNode(TDataFlowSpot.Create(TDataFlowKind.Assignment, ALocation.FileName, ALocation.Range.StartPos), mAlias,
      TDataFlowEdge.Create(FFiles.ExprText(ALocation.FileName, ADeclaration), 'absolute', 'absolute'));
  end;
end;

procedure TDataFlowSources.ArgumentWrite(const ASymbol: TDataFlowSymbol; const ASite: TDataFlowCallSite);
begin
  if not BuiltinWrite(ASymbol, ASite) then
  begin
    RoutineArgumentWrite(ASite);
  end;
end;

function TDataFlowSources.BuiltinWrite(const ASymbol: TDataFlowSymbol; const ASite: TDataFlowCallSite): Boolean;
var
  mName: string;
begin
  Result := True;
  mName := ASite.Callee;
  if IsInputCall(mName, ASite.Argument) then
  begin
    AddLeafNode(ASite.Spot(TDataFlowKind.Input), TDataFlowEdge.Create(FFiles.ExprText(ASite.FileName, ASite.Call),
      ASite.Via, ASite.UnsafeReason));
  end
  else if IsModifyCall(mName, ASite.Argument) then
  begin
    ModifyWrite(ASymbol, ASite);
  end
  else if IsCopyCall(ASite) and (mName = 'move') then
  begin
    AddValueNode(ASite.Spot(TDataFlowKind.Assignment), ASite.Tree, ASite.Call[1], ASite.Via, 'move');
  end
  else if IsCopyCall(ASite) then
  begin
    AddValueNode(ASite.Spot(TDataFlowKind.Assignment), ASite.Tree, ASite.Call[1], ASite.Via, ASite.UnsafeReason);
  end
  else if (mName = 'fillchar') and (ASite.Argument = 0) then
  begin
    FillCharWrite(ASite);
  end
  else
  begin
    Result := False;
  end;
end;

procedure TDataFlowSources.ModifyWrite(const ASymbol: TDataFlowSymbol; const ASite: TDataFlowCallSite);
var
  mNode: TDataFlowNode;
  mArgument: Integer;
begin
  if Excluded(ASite.FileName) then
  begin
    Exit;
  end;
  mNode := NewNode(ASite.Spot(TDataFlowKind.Modify), TDataFlowEdge.Create(FFiles.ExprText(ASite.FileName,
    ASite.Call), ASite.Via, ''));
  AddSource(mNode, ASymbol);
  for mArgument := 1 to ASite.Call.ChildCount - 1 do
  begin
    if mArgument - 1 <> ASite.Argument then
    begin
      CollectValue(ASite.Tree, ASite.FileName, ASite.Call[mArgument], mNode);
    end;
  end;
  AddNode(mNode);
end;

procedure TDataFlowSources.FillCharWrite(const ASite: TDataFlowCallSite);
begin
  if ASite.Call.ChildCount > 3 then
  begin
    AddValueNode(ASite.Spot(TDataFlowKind.Assignment), ASite.Tree, ASite.Call[3], ASite.Via, 'fillchar');
  end
  else
  begin
    AddLeafNode(ASite.Spot(TDataFlowKind.Assignment), TDataFlowEdge.Create(FFiles.ExprText(ASite.FileName,
      ASite.Call), ASite.Via, 'fillchar'));
  end;
end;

procedure TDataFlowSources.RoutineArgumentWrite(const ASite: TDataFlowCallSite);
var
  mResolved: TResolvedSymbol;
  mParams: TArray<TDataFlowParam>;
  mKind: TDataFlowKind;
begin
  if not ResolvedAt(ASite.Tree, ASite.FileName, TDataFlowSyntax.NamePosition(ASite.Tree, ASite.Call[0]),
    mResolved) or not (mResolved.SymbolKind in cRoutineKinds) then
  begin
    Exit;
  end;
  mParams := ParamsOf(mResolved.FileName, mResolved.SelectionRange.StartPos);
  if not IsWrittenParam(mParams, ASite.Argument) then
  begin
    Exit;
  end;
  mKind := TDataFlowKind.VarArgument;
  if mParams[ASite.Argument].Modifier = TParameterModifier.OutParam then
  begin
    mKind := TDataFlowKind.OutArgument;
  end;
  AddTargetNode(ASite.Spot(mKind), mParams[ASite.Argument].Symbol,
    TDataFlowEdge.Create(FFiles.ExprText(ASite.FileName, ASite.Call), mResolved.Name, ASite.UnsafeReason));
end;

procedure TDataFlowSources.CallerArguments(const ASymbol: TDataFlowSymbol; ADeclaration: TSyntaxNode);
var
  mHeader: TSyntaxNode;
  mParams: TArray<TDataFlowParam>;
  mParamIndex: Integer;
  mRoutine: TDataFlowSymbol;
  mLocation: TReferenceLocation;
begin
  mHeader := CallableHeader(ADeclaration);
  if mHeader = nil then
  begin
    Exit;
  end;
  mParams := ParamsOf(ASymbol.FileName, mHeader.StartPos);
  mParamIndex := ParamIndexOf(mParams, ASymbol.Position);
  // out-Parameter bekommen vom Aufrufer keinen Wert.
  if (mParamIndex < 0) or (mParams[mParamIndex].Modifier = TParameterModifier.OutParam) or
    not FunctionOf(FFiles.TreeOf(ASymbol.FileName), ASymbol.FileName, mHeader, mRoutine) then
  begin
    Exit;
  end;
  for mLocation in Occurrences(mRoutine) do
  begin
    CheckCancelled;
    CallerArgument(mRoutine, mLocation, mParamIndex, mParamIndex = High(mParams));
  end;
end;

procedure TDataFlowSources.CallerArgument(const ARoutine: TDataFlowSymbol; const ALocation: TReferenceLocation;
  AParamIndex: Integer; AIsLast: Boolean);
var
  mTree: TSyntaxTree;
  mNode, mCall: TSyntaxNode;
begin
  mTree := FFiles.TreeOf(ALocation.FileName);
  if mTree = nil then
  begin
    Exit;
  end;
  mNode := TDataFlowSyntax.NodeAt(mTree.Root, ALocation.Range.StartPos);
  if mNode.Kind = TSyntaxKind.PropertyDecl then
  begin
    // Setter einer Property: Der Wert jeder Zuweisung an sie kommt als letzter Parameter an.
    if AIsLast and SameText(TDataFlowSyntax.AccessorBefore(mTree, ALocation.Range.StartPos), 'write') then
    begin
      PropertyWrites(mTree, ALocation.FileName, mNode, AParamIndex);
    end;
    Exit;
  end;
  mCall := nil;
  if mNode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess] then
  begin
    mCall := mNode.Parent;
  end;
  if IsCallWithArgument(mCall, mNode, AParamIndex) then
  begin
    AddValueNode(TDataFlowSpot.Create(TDataFlowKind.CallerArgument, ALocation.FileName,
      mCall[AParamIndex + 1].StartPos), mTree, mCall[AParamIndex + 1], ARoutine.Name, '');
  end;
end;

function TDataFlowSources.FunctionBody(const ASymbol: TDataFlowSymbol; out ABodyFile: string): TSyntaxNode;
var
  mTargets: TArray<TDefinitionTarget>;
  mBodyTree: TSyntaxTree;
  mPosition: TTextPosition;
begin
  Result := nil;
  mTargets := TLspDefinition.Targets(FResolver, FIndex, FFiles.TreeOf(ASymbol.FileName), ASymbol.FileName,
    ASymbol.Position, False);
  ABodyFile := ASymbol.FileName;
  mPosition := ASymbol.Position;
  if Length(mTargets) > 0 then
  begin
    ABodyFile := mTargets[0].FileName;
    mPosition := mTargets[0].SelectionRange.StartPos;
  end;
  mBodyTree := FFiles.TreeOf(ABodyFile);
  if (mBodyTree <> nil) and FFiles.InProject(ABodyFile) then
  begin
    Result := TDataFlowSyntax.RoutineWithBody(TDataFlowSyntax.NodeAt(mBodyTree.Root, mPosition));
  end;
end;

procedure TDataFlowSources.FunctionSources(const ASymbol: TDataFlowSymbol);
var
  mBody, mStatement: TSyntaxNode;
  mBodyFile, mVia: string;
  mBodyTree: TSyntaxTree;
begin
  mBody := FunctionBody(ASymbol, mBodyFile);
  if mBody = nil then
  begin
    // Ohne Rumpf im Projekt (Bibliothek, abstract, external): ein Blatt.
    AddLeafNode(TDataFlowSpot.Create(TDataFlowKind.Outside, ASymbol.FileName, ASymbol.Position),
      TDataFlowEdge.Create(ASymbol.Name, '', ''));
    Exit;
  end;
  mBodyTree := FFiles.TreeOf(mBodyFile);
  for mStatement in ReturnStatements(mBody.FindChild(TSyntaxKind.Block), TDataFlowSyntax.ShortName(ASymbol.Name)) do
  begin
    CheckCancelled;
    mVia := '';
    if mStatement.Kind <> TSyntaxKind.AssignStatement then
    begin
      mVia := 'Exit';
    end;
    AddValueNode(TDataFlowSpot.Create(TDataFlowKind.Return, mBodyFile, mStatement.StartPos), mBodyTree,
      mStatement[1], mVia, '');
  end;
end;

procedure TDataFlowSources.PropertyReads(const ASymbol: TDataFlowSymbol);
var
  mTree: TSyntaxTree;
  mDeclaration: TSyntaxNode;
  mPosition: TTextPosition;
  mReader: TDataFlowSymbol;
begin
  // Der gelesene Wert kommt aus dem Feld bzw. Getter hinter read.
  mTree := FFiles.TreeOf(ASymbol.FileName);
  mDeclaration := TDataFlowSyntax.NodeAt(mTree.Root, ASymbol.Position);
  if (mDeclaration.Kind = TSyntaxKind.PropertyDecl) and
    TDataFlowSyntax.Accessor(mTree, mDeclaration, 'read', mPosition) and
    ResolveSymbol(mTree, ASymbol.FileName, mPosition, mReader) then
  begin
    AddTargetNode(TDataFlowSpot.Create(TDataFlowKind.PropertyRead, ASymbol.FileName, mPosition), mReader,
      TDataFlowEdge.Create('read ' + mReader.Name, '', ''));
  end;
end;

procedure TDataFlowSources.PropertyWrites(ATree: TSyntaxTree; const AFileName: string; AProperty: TSyntaxNode;
  AParamIndex: Integer);
var
  mPosition: TTextPosition;
  mProperty: TDataFlowSymbol;
  mLocation: TReferenceLocation;
begin
  if (AParamIndex < 0) or not TDataFlowSyntax.PropertyName(ATree, AProperty, mPosition) then
  begin
    Exit;
  end;
  if not ResolveSymbol(ATree, AFileName, mPosition, mProperty) then
  begin
    mProperty := Default(TDataFlowSymbol);
    mProperty.Name := TDataFlowSyntax.CleanName(AProperty.Name);
    mProperty.FileName := AFileName;
    mProperty.Position := mPosition;
    mProperty.SymbolKind := TIndexSymbolKind.Property_;
  end;
  for mLocation in Occurrences(mProperty) do
  begin
    CheckCancelled;
    PropertyWriteAt(mProperty, mLocation);
  end;
end;

procedure TDataFlowSources.PropertyWriteAt(const AProperty: TDataFlowSymbol; const ALocation: TReferenceLocation);
var
  mTree: TSyntaxTree;
  mNode, mStatement: TSyntaxNode;
  mReason: string;
begin
  mTree := FFiles.TreeOf(ALocation.FileName);
  if mTree = nil then
  begin
    Exit;
  end;
  mNode := TDataFlowSyntax.NodeAt(mTree.Root, ALocation.Range.StartPos);
  mReason := '';
  if (mNode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
    TDataFlowSyntax.WrittenTarget(mNode, mStatement, mReason) then
  begin
    AddValueNode(TDataFlowSpot.Create(TDataFlowKind.PropertyWrite, ALocation.FileName, ALocation.Range.StartPos),
      mTree, mStatement[1], AProperty.Name, mReason);
  end;
end;

end.
