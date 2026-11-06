unit Atlas.Common.Lsp.DataFlow.Targets;

// Datenfluss (#690), Wohin: Zuweisungen, Argumente (an den Parameter des Aufgerufenen), Rückgaben (Result,
// Exit), Initialisierungen, Schleifen und Properties, die das Feld lesen; sonst eine Verwendung (Bedingung,
// Index, verworfenes Ergebnis) als Blatt. Über Routinen außerhalb des Projekts und Typumwandlungen
// (IntToStr(X), Integer(X)) geht der Wert weiter nach außen. TDataFlowRun ist die oberste Stufe eines Laufs.

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.DataFlow.Types,
  Atlas.Common.Lsp.DataFlow.Sources;

type
  /// <summary>Wie es nach einem Schritt nach oben weitergeht: weiter steigen, als Verwendung enden (Blatt) oder
  /// fertig (Stelle schon angelegt).</summary>
  TDataFlowClimb = (Climb, Use, Done);

  /// <summary>Weg eines Werts vom Vorkommen an Position nach oben im Baum.</summary>
  TDataFlowWalk = record
    Tree: TSyntaxTree;
    FileName: string;
    Position: TTextPosition;
    Current: TSyntaxNode;
    Parent: TSyntaxNode;
    Reason: string;
    Via: string;
    function Spot(AKind: TDataFlowKind): TDataFlowSpot;
  end;

  TDataFlowRun = class(TDataFlowSources)
  protected
    procedure TargetsOf(const ASymbol: TDataFlowSymbol);
    procedure TargetAt(const ALocation: TReferenceLocation);
    /// <summary>Feld bzw. Getter hinter read: Der Wert geht in die Property.</summary>
    procedure PropertyTarget(ATree: TSyntaxTree; const ALocation: TReferenceLocation; AProperty: TSyntaxNode);
    procedure FlowUp(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
      AStart: TSyntaxNode);
    function StepAt(var AWalk: TDataFlowWalk): TDataFlowClimb;
    function CallStep(var AWalk: TDataFlowWalk): TDataFlowClimb;
    function ExitStep(var AWalk: TDataFlowWalk): TDataFlowClimb;
    /// <summary>Move(X, Ziel, …), Str(X, Ziel), Val(X, Ziel, …): Der Wert geht ins zweite Argument.</summary>
    function CopyStep(var AWalk: TDataFlowWalk): TDataFlowClimb;
    /// <summary>Argument einer Routine: an ihren Parameter; Typumwandlungen und Routinen von außen reichen den
    /// Wert im Ergebnis weiter.</summary>
    function RoutineStep(var AWalk: TDataFlowWalk; AArgument: Integer): TDataFlowClimb;
    function AssignStep(var AWalk: TDataFlowWalk): TDataFlowClimb;
    /// <summary>Result := … bzw. Funktionsname := … gibt den Wert zurück.</summary>
    function IsReturnAssignment(const AWalk: TDataFlowWalk; out ATarget: TDataFlowSymbol): Boolean;
    function DeclarationStep(var AWalk: TDataFlowWalk): TDataFlowClimb;
    function LoopStep(var AWalk: TDataFlowWalk): TDataFlowClimb;
  public
    function Run(const ARequest: TDataFlowRequest): TDataFlowResult;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.DataFlow.Syntax;

function ClimbIf(ACondition: Boolean): TDataFlowClimb;
begin
  if ACondition then
  begin
    Result := TDataFlowClimb.Climb;
  end
  else
  begin
    Result := TDataFlowClimb.Use;
  end;
end;

function UnsafeClimb(var AWalk: TDataFlowWalk; const AReason: string): TDataFlowClimb;
begin
  AWalk.Reason := AReason;
  Result := TDataFlowClimb.Climb;
end;

function IsCopyCall(const AName: string; AArgument: Integer): Boolean;
begin
  Result := MatchText(AName, ['move', 'str', 'val']) and (AArgument = 0);
end;

{ TDataFlowWalk }

function TDataFlowWalk.Spot(AKind: TDataFlowKind): TDataFlowSpot;
begin
  Result := TDataFlowSpot.Create(AKind, FileName, Position);
end;

{ TDataFlowRun }

procedure TDataFlowRun.TargetsOf(const ASymbol: TDataFlowSymbol);
var
  mLocation: TReferenceLocation;
begin
  if FFiles.TreeOf(ASymbol.FileName) = nil then
  begin
    Exit;
  end;
  for mLocation in Occurrences(ASymbol) do
  begin
    CheckCancelled;
    if not TDataFlowSyntax.IsFormFile(mLocation.FileName) then
    begin
      TargetAt(mLocation);
    end;
  end;
end;

procedure TDataFlowRun.TargetAt(const ALocation: TReferenceLocation);
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
  if mNode.Kind = TSyntaxKind.PropertyDecl then
  begin
    PropertyTarget(mTree, ALocation, mNode);
  end
  // Köpfe von Deklaration und Implementierung sind keine Verwendung, Ziele von Zuweisungen auch nicht.
  else if (mNode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
    not TDataFlowSyntax.InRoutineHeader(mNode) and not TDataFlowSyntax.WrittenTarget(mNode, mStatement, mReason) then
  begin
    FlowUp(mTree, ALocation.FileName, ALocation.Range.StartPos, mNode);
  end;
end;

procedure TDataFlowRun.PropertyTarget(ATree: TSyntaxTree; const ALocation: TReferenceLocation;
  AProperty: TSyntaxNode);
var
  mPosition: TTextPosition;
  mProperty: TDataFlowSymbol;
begin
  if SameText(TDataFlowSyntax.AccessorBefore(ATree, ALocation.Range.StartPos), 'read') and
    TDataFlowSyntax.PropertyName(ATree, AProperty, mPosition) and
    ResolveSymbol(ATree, ALocation.FileName, mPosition, mProperty) then
  begin
    AddTargetNode(TDataFlowSpot.Create(TDataFlowKind.PropertyRead, ALocation.FileName, ALocation.Range.StartPos),
      mProperty, TDataFlowEdge.Create('property ' + mProperty.Name, '', ''));
  end;
end;

procedure TDataFlowRun.FlowUp(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
  AStart: TSyntaxNode);
var
  mWalk: TDataFlowWalk;
  mStep: TDataFlowClimb;
begin
  mWalk := Default(TDataFlowWalk);
  mWalk.Tree := ATree;
  mWalk.FileName := AFileName;
  mWalk.Position := APosition;
  mWalk.Current := AStart;
  mStep := TDataFlowClimb.Climb;
  while mStep = TDataFlowClimb.Climb do
  begin
    mWalk.Parent := mWalk.Current.Parent;
    mStep := TDataFlowClimb.Use;
    if mWalk.Parent <> nil then
    begin
      mStep := StepAt(mWalk);
    end;
    if mStep = TDataFlowClimb.Climb then
    begin
      mWalk.Current := mWalk.Parent;
    end;
  end;
  if mStep = TDataFlowClimb.Use then
  begin
    // Bedingung, Index, verworfenes Ergebnis, Mitgliedszugriff: verwendet, fließt aber nicht weiter.
    AddLeafNode(mWalk.Spot(TDataFlowKind.Use), TDataFlowEdge.Create('', mWalk.Via, mWalk.Reason));
  end;
end;

function TDataFlowRun.StepAt(var AWalk: TDataFlowWalk): TDataFlowClimb;
begin
  case AWalk.Parent.Kind of
    TSyntaxKind.ParenExpr, TSyntaxKind.BinaryExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.SetConstructor,
      TSyntaxKind.RangeExpr:
      Result := TDataFlowClimb.Climb;
    TSyntaxKind.IfExpr:
      // Die Bedingung selbst fließt nicht in das Ergebnis.
      Result := ClimbIf(AWalk.Parent[0] <> AWalk.Current);
    TSyntaxKind.IndexAccess:
      Result := ClimbIf(AWalk.Parent[0] = AWalk.Current);
    TSyntaxKind.Dereference:
      Result := UnsafeClimb(AWalk, 'pointer');
    TSyntaxKind.AddressOf:
      Result := UnsafeClimb(AWalk, 'address');
    TSyntaxKind.Call:
      Result := CallStep(AWalk);
    TSyntaxKind.AssignStatement:
      Result := AssignStep(AWalk);
    TSyntaxKind.InlineVar, TSyntaxKind.InlineConst, TSyntaxKind.VarDecl, TSyntaxKind.ConstDecl:
      Result := DeclarationStep(AWalk);
    TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement:
      Result := LoopStep(AWalk);
  else
    Result := TDataFlowClimb.Use;
  end;
end;

function TDataFlowRun.CallStep(var AWalk: TDataFlowWalk): TDataFlowClimb;
var
  mName: string;
  mArgument: Integer;
begin
  // Der Aufgerufene selbst: Sein Ergebnis fließt weiter.
  if AWalk.Parent[0] = AWalk.Current then
  begin
    Exit(TDataFlowClimb.Climb);
  end;
  mArgument := TDataFlowSyntax.ChildIndex(AWalk.Parent, AWalk.Current) - 1;
  mName := TDataFlowSyntax.CalleeName(AWalk.Parent);
  if mName = 'exit' then
  begin
    Result := ExitStep(AWalk);
  end
  else if (mName = 'write') or (mName = 'writeln') then
  begin
    AddLeafNode(AWalk.Spot(TDataFlowKind.Output), TDataFlowEdge.Create(FFiles.ExprText(AWalk.FileName, AWalk.Parent),
      TDataFlowSyntax.ShortName(AWalk.Parent.Name), AWalk.Reason));
    Result := TDataFlowClimb.Done;
  end
  else if IsCopyCall(mName, mArgument) and (AWalk.Parent.ChildCount > 2) then
  begin
    if mName = 'move' then
    begin
      AWalk.Reason := 'move';
    end;
    Result := CopyStep(AWalk);
  end
  else
  begin
    Result := RoutineStep(AWalk, mArgument);
  end;
end;

function TDataFlowRun.ExitStep(var AWalk: TDataFlowWalk): TDataFlowClimb;
var
  mTarget: TDataFlowSymbol;
begin
  if EnclosingFunction(AWalk.Tree, AWalk.FileName, AWalk.Parent, mTarget) then
  begin
    AddTargetNode(AWalk.Spot(TDataFlowKind.Return), mTarget,
      TDataFlowEdge.Create(FFiles.ExprText(AWalk.FileName, AWalk.Parent), 'Exit', AWalk.Reason));
  end;
  Result := TDataFlowClimb.Done;
end;

function TDataFlowRun.CopyStep(var AWalk: TDataFlowWalk): TDataFlowClimb;
var
  mTarget: TDataFlowSymbol;
begin
  if TargetRoot(AWalk.Tree, AWalk.FileName, AWalk.Parent[2], AWalk.Reason, mTarget) then
  begin
    AddTargetNode(AWalk.Spot(TDataFlowKind.Assignment), mTarget,
      TDataFlowEdge.Create(FFiles.ExprText(AWalk.FileName, AWalk.Parent[2]),
      TDataFlowSyntax.ShortName(AWalk.Parent.Name), AWalk.Reason));
  end;
  Result := TDataFlowClimb.Done;
end;

function TDataFlowRun.RoutineStep(var AWalk: TDataFlowWalk; AArgument: Integer): TDataFlowClimb;
var
  mResolved: TResolvedSymbol;
  mParams: TArray<TDataFlowParam>;
begin
  if not ResolvedAt(AWalk.Tree, AWalk.FileName, TDataFlowSyntax.NamePosition(AWalk.Tree, AWalk.Parent[0]),
    mResolved) or (mResolved.SymbolKind in cTypeKinds) or not FFiles.InProject(mResolved.FileName) then
  begin
    // Typumwandlung oder Routine von außen: Der Wert steckt im Ergebnis.
    if AWalk.Via = '' then
    begin
      AWalk.Via := TDataFlowSyntax.ShortName(AWalk.Parent.Name);
    end;
    Exit(TDataFlowClimb.Climb);
  end;
  Result := TDataFlowClimb.Use;
  mParams := ParamsOf(mResolved.FileName, mResolved.SelectionRange.StartPos);
  if (AArgument >= 0) and (AArgument <= High(mParams)) then
  begin
    AddTargetNode(AWalk.Spot(TDataFlowKind.Argument), mParams[AArgument].Symbol,
      TDataFlowEdge.Create(FFiles.ExprText(AWalk.FileName, AWalk.Parent), mResolved.Name, AWalk.Reason));
    Result := TDataFlowClimb.Done;
  end;
end;

function TDataFlowRun.IsReturnAssignment(const AWalk: TDataFlowWalk; out ATarget: TDataFlowSymbol): Boolean;
var
  mName: string;
begin
  mName := AWalk.Parent[0].Name;
  Result := (AWalk.Parent[0].Kind = TSyntaxKind.Identifier) and
    EnclosingFunction(AWalk.Tree, AWalk.FileName, AWalk.Parent, ATarget) and (SameText(mName, 'Result') or
    SameText(TDataFlowSyntax.CleanName(mName), TDataFlowSyntax.ShortName(ATarget.Name)));
end;

function TDataFlowRun.AssignStep(var AWalk: TDataFlowWalk): TDataFlowClimb;
var
  mTarget: TDataFlowSymbol;
  mEdge: TDataFlowEdge;
begin
  if (AWalk.Parent.ChildCount < 2) or (AWalk.Parent[1] <> AWalk.Current) then
  begin
    Exit(TDataFlowClimb.Use);
  end;
  Result := TDataFlowClimb.Done;
  if IsReturnAssignment(AWalk, mTarget) then
  begin
    mEdge := TDataFlowEdge.Create(FFiles.ExprText(AWalk.FileName, AWalk.Parent), AWalk.Via, AWalk.Reason);
    AddTargetNode(AWalk.Spot(TDataFlowKind.Return), mTarget, mEdge);
  end
  else if TargetRoot(AWalk.Tree, AWalk.FileName, AWalk.Parent[0], AWalk.Reason, mTarget) then
  begin
    mEdge := TDataFlowEdge.Create(FFiles.ExprText(AWalk.FileName, AWalk.Parent), AWalk.Via, AWalk.Reason);
    AddTargetNode(AWalk.Spot(TDataFlowKind.Assignment), mTarget, mEdge);
  end;
end;

function TDataFlowRun.DeclarationStep(var AWalk: TDataFlowWalk): TDataFlowClimb;
var
  mPosition: TTextPosition;
  mTarget: TDataFlowSymbol;
begin
  if AWalk.Current.Kind in cTypeNodeKinds then
  begin
    Exit(TDataFlowClimb.Use);
  end;
  if SameText(TDataFlowSyntax.AccessorBefore(AWalk.Tree, AWalk.Current.StartPos), 'absolute') then
  begin
    AWalk.Reason := 'absolute';
  end;
  if TDataFlowSyntax.FirstDeclaredName(AWalk.Tree, AWalk.Parent, mPosition) and
    ResolveSymbol(AWalk.Tree, AWalk.FileName, mPosition, mTarget) then
  begin
    AddTargetNode(AWalk.Spot(TDataFlowKind.Initializer), mTarget,
      TDataFlowEdge.Create(FFiles.ExprText(AWalk.FileName, AWalk.Parent), AWalk.Via, AWalk.Reason));
  end;
  Result := TDataFlowClimb.Done;
end;

function TDataFlowRun.LoopStep(var AWalk: TDataFlowWalk): TDataFlowClimb;
var
  mPosition: TTextPosition;
  mTarget: TDataFlowSymbol;
begin
  if (AWalk.Current.Kind in cStatementKinds) or (AWalk.Current.Kind in cTypeNodeKinds) then
  begin
    Exit(TDataFlowClimb.Use);
  end;
  if TDataFlowSyntax.NameInNode(AWalk.Tree, AWalk.Parent, TDataFlowSyntax.CleanName(AWalk.Parent.Name), mPosition) and
    ResolveSymbol(AWalk.Tree, AWalk.FileName, mPosition, mTarget) then
  begin
    AddTargetNode(AWalk.Spot(TDataFlowKind.Loop), mTarget,
      TDataFlowEdge.Create(FFiles.ExprText(AWalk.FileName, AWalk.Current), AWalk.Via, AWalk.Reason));
  end;
  Result := TDataFlowClimb.Done;
end;

function TDataFlowRun.Run(const ARequest: TDataFlowRequest): TDataFlowResult;
begin
  Result := Default(TDataFlowResult);
  Result.Found := ResolveSymbol(ARequest.Tree, ARequest.FileName, ARequest.Position, Result.Symbol);
  if not Result.Found then
  begin
    Exit;
  end;
  FCurrentKey := Result.Symbol.Key;
  if ARequest.Direction = TDataFlowDirection.Sources then
  begin
    SourcesOf(Result.Symbol);
  end
  else
  begin
    TargetsOf(Result.Symbol);
  end;
  Result.Nodes := FNodes.ToArray;
end;

end.
