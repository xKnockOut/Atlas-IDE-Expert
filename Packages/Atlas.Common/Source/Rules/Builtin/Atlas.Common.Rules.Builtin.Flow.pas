unit Atlas.Common.Rules.Builtin.Flow;

// Flussregeln (#269) auf dem Kontrollflussgraphen (#143):
//   result-not-set            Funktion kann enden, ohne Result zu setzen (wie W1035)
//   possibly-uninitialized    lokale Variable wird möglicherweise vor der ersten
//                             Zuweisung gelesen (wie W1036)
//   unreachable-code          Anweisung nach Exit, raise, Abort, goto … wird nie
//                             ausgeführt (#94); gemeldet wird nur die erste
//                             Anweisung eines unerreichbaren Abschnitts
//   use-after-free            nach X.Free, X.Destroy, X.DisposeOf, FreeAndNil(X)
//                             oder Dispose(X) wird X ohne neue Zuweisung wieder
//                             benutzt (#915): X.Methode, X.Feld, X[…], X^, with X,
//                             nach Free auch Assigned(X) und ein zweites Free.
//                             Vom Freigabeknoten aus folgt die Regel dem Graphen;
//                             eine Zuweisung an X, die Übergabe von X an eine
//                             Routine, @X und nach FreeAndNil eine Abfrage auf nil
//                             (Assigned(X), X <> nil) beenden den Weg. Konfidenz
//                             hoch, wenn Freigabe und Zugriff im selben Block
//                             nacheinander stehen, sonst mittel. Die Aktion
//                             springt zur Freigabe.
//
// Was der Graph nicht sieht, macht die Variable "unbekannt" und erzeugt keinen
// Treffer: Übergabe als Argument (var/out-Parameter, SetLength, FillChar,
// TryGetValue …), @X, Zuweisung an ein Feld oder Element (Result.Feld := …,
// Result[I] := …), with X do, inherited in Funktionen und die alte Zuweisung
// an den Funktionsnamen. Ist der Graph unvollständig (asm, Syntaxfehler),
// gibt es ebenfalls keinen Treffer.
//
// possibly-uninitialized prüft nur Variablen, die Delphi nicht selbst
// vorbelegt: einfache Typen (Konfidenz hoch) und T…-Typen wie Klassen und
// Records (Konfidenz mittel). string, Variant, Interfaces und dynamische
// Arrays sind verwaltet und werden übergangen.

interface

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TResultNotSetRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TPossiblyUninitializedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TUnreachableCodeRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TUseAfterFreeRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

const
  UseAfterFreeRuleId = 'use-after-free';

/// <summary>Wird AName in ABlock so benutzt, dass der Kontrollfluss die Zuweisung nicht sieht?</summary>
function HasOpaqueUse(ABlock: TSyntaxNode; const AName: string): Boolean;

procedure RegisterFlowRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Rules.Derived;

const
  SimpleTypes: array[0..23] of string = ('Integer', 'Cardinal', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt',
    'Byte', 'Word', 'ShortInt', 'SmallInt', 'LongInt', 'LongWord', 'Boolean', 'ByteBool', 'WordBool', 'LongBool',
    'Char', 'AnsiChar', 'WideChar', 'Double', 'Single', 'Extended', 'Currency', 'Pointer');
  ManagedTypes: array[0..7] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString',
    'Variant', 'OleVariant', 'TArray');

function NodeRange(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

/// <summary>Bezeichner, an dem eine Kette wie Result.Feld oder Result[I] hängt.</summary>
function RootName(ANode: TSyntaxNode): string;
begin
  while (ANode <> nil) and (ANode.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess,
    TSyntaxKind.Dereference]) and (ANode.ChildCount > 0) do
    ANode := ANode[0];
  if (ANode <> nil) and (ANode.Kind = TSyntaxKind.Identifier) then
    Result := ANode.Name
  else
    Result := '';
end;

function IsName(ANode: TSyntaxNode; const AName: string): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, AName);
end;

function HasOpaqueUse(ABlock: TSyntaxNode; const AName: string): Boolean;

  function Visit(ANode: TSyntaxNode): Boolean;
  var
    Index: Integer;
  begin
    case ANode.Kind of
      // Lokale Routinen und anonyme Methoden laufen außerhalb dieses Flusses.
      TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod:
        Exit(False);
      TSyntaxKind.Call:
        for Index := 1 to ANode.ChildCount - 1 do
          if IsName(ANode[Index], AName) then
            Exit(True);
      TSyntaxKind.AddressOf:
        if (ANode.ChildCount > 0) and SameText(RootName(ANode[0]), AName) then
          Exit(True);
      TSyntaxKind.AssignStatement:
        if (ANode.ChildCount > 0) and (ANode[0].Kind <> TSyntaxKind.Identifier) and
          SameText(RootName(ANode[0]), AName) then
          Exit(True);
      TSyntaxKind.WithStatement:
        for Index := 0 to ANode.ChildCount - 2 do
          if SameText(RootName(ANode[Index]), AName) then
            Exit(True);
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      if Visit(ANode[Index]) then
        Exit(True);
    Result := False;
  end;

begin
  Result := Visit(ABlock);
end;

function ContainsKind(ANode: TSyntaxNode; AKind: TSyntaxKind): Boolean;
var
  Index: Integer;
begin
  if ANode.Kind = AKind then
    Exit(True);
  if ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
    Exit(False);
  for Index := 0 to ANode.ChildCount - 1 do
    if ContainsKind(ANode[Index], AKind) then
      Exit(True);
  Result := False;
end;

function ShortName(const AName: string): string;
begin
  Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

/// <summary>Bereich des Routinennamens im Kopf; sonst der Kopf.</summary>
function HeaderNameRange(const AContext: TRuleContext; ARoutine: TSyntaxNode): TTextRange;
var
  Header: TSyntaxNode;
  Token: TPascalToken;
  Index: Integer;
  Name: string;
begin
  Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  if Header = nil then
    Header := ARoutine;
  Name := ShortName(ARoutine.Name);
  for Index := 0 to High(AContext.Tree.Tokens) do
  begin
    Token := AContext.Tree.Tokens[Index];
    if Token.Offset >= Header.EndOffset then
      Break;
    if (Token.Offset >= Header.StartOffset) and SameText(Token.Text, Name) then
      Exit(TTextRange.Create(Token.StartPos, Token.EndPos));
  end;
  Result := NodeRange(Header);
end;

{ TResultNotSetRule }

function TResultNotSetRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('result-not-set', TRuleSeverity.Warning,
    'Funktion kann enden, ohne Result zu setzen');
end;

procedure TResultNotSetRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Routines: TArray<TSyntaxNode>;
  Routine, Header, Block: TSyntaxNode;
  Graph: TControlFlowGraph;
  Cache: IRuleDerivedCache;
  Name: string;
begin
  if AContext.Tree = nil then
    Exit;
  // Routinen, Signaturen und Graphen teilt der Lauf mit den anderen Regeln (Review P-03).
  Cache := TRuleDerived.Open(AContext);
  Routines := TRuleDerived.Routines(Cache, AContext);
  for Routine in Routines do
  begin
    Header := Routine.FindChild(TSyntaxKind.RoutineHeader);
    // Nur Funktionen: der Kopf trägt einen Ergebnistyp.
    if (Header = nil) or (Header.FindChild(TSyntaxKind.TypeReference) = nil) then
      Continue;
    Block := Routine.FindChild(TSyntaxKind.Block);
    Name := ShortName(Routine.Name);
    if HasOpaqueUse(Block, 'Result') or HasOpaqueUse(Block, Name) or ContainsKind(Block, TSyntaxKind.InheritedExpr) then
      Continue;
    Graph := TRuleDerived.Graph(Cache, AContext, Routine);
    // Alte Schreibweise: Zuweisung an den Funktionsnamen setzt ebenfalls das Ergebnis.
    if (Graph.MayEndWithout('Result') = TFlowAnswer.Yes) and (Graph.MayEndWithout(Name) = TFlowAnswer.Yes) then
      AReport.Add(HeaderNameRange(AContext, Routine),
        Format('"%s" kann enden, ohne Result zu setzen; der Rückgabewert ist dann undefiniert', [Name]),
        TRuleConfidence.High);
  end;
end;

{ TPossiblyUninitializedRule }

function TPossiblyUninitializedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('possibly-uninitialized', TRuleSeverity.Warning,
    'Variable wird möglicherweise vor der ersten Zuweisung gelesen');
end;

procedure TPossiblyUninitializedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Routines: TArray<TSyntaxNode>;
  Routine, Block, Section, Decl, TypeNode: TSyntaxNode;
  Graph: TControlFlowGraph;
  Cache: IRuleDerivedCache;
  Index, Inner: Integer;
  Name, TypeName: string;
  Confidence: TRuleConfidence;
  Reported: Boolean;

  function FlowNodeOf(ANode: TSyntaxNode): TFlowNode;
  begin
    Result := nil;
    while (ANode <> nil) and (Result = nil) do
    begin
      Result := Graph.NodeOf(ANode);
      ANode := ANode.Parent;
    end;
  end;

  // Erster Lesezugriff auf Name, der ohne vorherige Zuweisung erreichbar ist.
  procedure Visit(ANode: TSyntaxNode);
  var
    Child: Integer;
    Flow: TFlowNode;
  begin
    if Reported or (ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) then
      Exit;
    if IsName(ANode, Name) and not ((ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.AssignStatement) and
      (ANode.Parent.ChildCount > 0) and (ANode.Parent[0] = ANode)) then
    begin
      Flow := FlowNodeOf(ANode);
      if (Flow <> nil) and (Graph.IsReachable(Flow) = TFlowAnswer.Yes) and
        Graph.ReachingDefinitions(Flow, Name).FromEntry then
      begin
        AReport.Add(NodeRange(ANode),
          Format('"%s" wird hier möglicherweise gelesen, bevor ein Wert zugewiesen wurde', [Name]), Confidence);
        Reported := True;
        Exit;
      end;
    end;
    for Child := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Child]);
  end;

begin
  if AContext.Tree = nil then
    Exit;
  // Routinen, Signaturen und Graphen teilt der Lauf mit den anderen Regeln (Review P-03).
  Cache := TRuleDerived.Open(AContext);
  Routines := TRuleDerived.Routines(Cache, AContext);
  for Routine in Routines do
  begin
    Block := Routine.FindChild(TSyntaxKind.Block);
    Graph := nil;
    for Index := 0 to Routine.ChildCount - 1 do
    begin
      Section := Routine[Index];
      if Section.Kind <> TSyntaxKind.VarSection then
        Continue;
      for Inner := 0 to Section.ChildCount - 1 do
      begin
        Decl := Section[Inner];
        TypeNode := Decl.FindChild(TSyntaxKind.TypeReference);
        // var X: Integer = 0 ist vorbelegt; nur einfache Deklarationen mit Typverweis.
        if (Decl.Kind <> TSyntaxKind.VarDecl) or (TypeNode = nil) or (Decl.ChildCount <> 1) or
          (TypeNode.FindChild(TSyntaxKind.GenericArgs) <> nil) then
          Continue;
        TypeName := TypeNode.Name;
        if MatchText(TypeName, SimpleTypes) then
          Confidence := TRuleConfidence.High
        else if StartsText('T', TypeName) and (Length(TypeName) > 1) and not MatchText(TypeName, ManagedTypes) then
          Confidence := TRuleConfidence.Medium
        else
          Continue;
        for Name in Decl.Name.Split([',']) do
        begin
          if HasOpaqueUse(Block, Name.Trim) then
            Continue;
          if Graph = nil then
            Graph := TRuleDerived.Graph(Cache, AContext, Routine);
          if not Graph.Complete then
            Break;
          Reported := False;
          Visit(Block);
        end;
      end;
    end;
  end;
end;

{ TUnreachableCodeRule }

function TUnreachableCodeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('unreachable-code', TRuleSeverity.Warning, 'Anweisung wird nie ausgeführt');
end;

/// <summary>Bereich der ersten Zeile von ANode; mehrzeilige Anweisungen werden nicht ganz markiert.</summary>
function FirstLineRange(const AContext: TRuleContext; ANode: TSyntaxNode): TTextRange;
var
  Token: TPascalToken;
  Last: TTextPosition;
begin
  Last := ANode.EndPos;
  if Last.Line <> ANode.StartPos.Line then
  begin
    Last := ANode.StartPos;
    for Token in AContext.Tree.Tokens do
    begin
      if Token.Offset >= ANode.EndOffset then
        Break;
      if (Token.Offset >= ANode.StartOffset) and (Token.StartPos.Line = ANode.StartPos.Line) and
        (Token.Kind <> TPascalTokenKind.Comment) then
        Last := Token.EndPos;
    end;
  end;
  Result := TTextRange.Create(ANode.StartPos, Last);
end;

procedure TUnreachableCodeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Routines: TArray<TSyntaxNode>;
  Dead: TArray<TSyntaxNode>;
  Routine: TSyntaxNode;
  Graph: TControlFlowGraph;
  Cache: IRuleDerivedCache;
  Unreachable: TArray<TFlowNode>;
  Node: TFlowNode;

  function IsDead(ANode: TSyntaxNode): Boolean;
  var
    Item: TSyntaxNode;
  begin
    for Item in Dead do
      if Item = ANode then
        Exit(True);
    Result := False;
  end;

  function HasDead(ANode: TSyntaxNode): Boolean;
  var
    Index: Integer;
  begin
    if IsDead(ANode) then
      Exit(True);
    for Index := 0 to ANode.ChildCount - 1 do
      if HasDead(ANode[Index]) then
        Exit(True);
    Result := False;
  end;

  // Erste Anweisung eines unerreichbaren Abschnitts: nicht in einer anderen
  // unerreichbaren Anweisung enthalten, und davor steht (auf der ersten Ebene,
  // die einen Vorgänger hat) erreichbarer Code.
  function StartsDeadRun(AStatement: TSyntaxNode): Boolean;
  var
    Current, Parent: TSyntaxNode;
    Index: Integer;
  begin
    Current := AStatement.Parent;
    while (Current <> nil) and (Current <> Routine) do
    begin
      if IsDead(Current) then
        Exit(False);
      Current := Current.Parent;
    end;
    Current := AStatement;
    while (Current <> Routine) and (Current.Parent <> nil) do
    begin
      Parent := Current.Parent;
      for Index := 1 to Parent.ChildCount - 1 do
        if Parent[Index] = Current then
          Exit(not HasDead(Parent[Index - 1]));
      Current := Parent;
    end;
    Result := True;
  end;

begin
  if AContext.Tree = nil then
    Exit;
  // Routinen, Signaturen und Graphen teilt der Lauf mit den anderen Regeln (Review P-03).
  Cache := TRuleDerived.Open(AContext);
  Routines := TRuleDerived.Routines(Cache, AContext);
  for Routine in Routines do
  begin
    Graph := TRuleDerived.Graph(Cache, AContext, Routine);
    if not Graph.Complete then
      Continue;
    Unreachable := Graph.UnreachableStatements;
    Dead := nil;
    for Node in Unreachable do
      if Node.Syntax <> nil then
        Dead := Dead + [Node.Syntax];
    for Node in Unreachable do
      if (Node.Syntax <> nil) and StartsDeadRun(Node.Syntax) then
        AReport.Add(FirstLineRange(AContext, Node.Syntax), 'Diese Anweisung wird nie ausgeführt',
          TRuleConfidence.High);
  end;
end;

{ TUseAfterFreeRule }

function TUseAfterFreeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(UseAfterFreeRuleId, TRuleSeverity.Error, 'Objekt nach Free weiter benutzt');
end;

/// <summary>Name einer Variablen oder eines Feldes (X oder Self.X); sonst ''.</summary>
function FreedPath(ANode: TSyntaxNode): string;
begin
  Result := '';
  if ANode = nil then
    Exit;
  if ANode.Kind = TSyntaxKind.Identifier then
    Result := ANode.Name
  else if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) and IsName(ANode[0], 'Self') then
    Result := ANode.Name;
  if SameText(Result, 'Self') or SameText(Result, 'inherited') then
    Result := '';
end;

/// <summary>Gibt die Anweisung AStatement X frei? AToNil bei FreeAndNil.</summary>
function FreedBy(AStatement: TSyntaxNode; out APath: string; out AToNil: Boolean): Boolean;
var
  Callee, Target: TSyntaxNode;
begin
  Result := False;
  APath := '';
  AToNil := False;
  if (AStatement = nil) or (AStatement.Kind <> TSyntaxKind.CallStatement) or (AStatement.ChildCount = 0) then
    Exit;
  Callee := AStatement[0];
  Target := nil;
  // X.Free; bzw. X.Free();
  if (Callee.Kind = TSyntaxKind.Call) and (Callee.ChildCount = 1) then
    Callee := Callee[0];
  if (Callee.Kind = TSyntaxKind.MemberAccess) and (Callee.ChildCount = 1) and
    MatchText(Callee.Name, ['Free', 'Destroy', 'DisposeOf']) then
    Target := Callee[0]
  else if (Callee.Kind = TSyntaxKind.Call) and (Callee.ChildCount = 2) and (Callee[0].Kind = TSyntaxKind.Identifier) and
    MatchText(Callee[0].Name, ['FreeAndNil', 'Dispose']) then
  begin
    Target := Callee[1];
    AToNil := SameText(Callee[0].Name, 'FreeAndNil');
  end;
  APath := FreedPath(Target);
  Result := APath <> '';
end;

procedure TUseAfterFreeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
const
  StatementKinds = [TSyntaxKind.Block, TSyntaxKind.AsmBlock, TSyntaxKind.AssignStatement,
    TSyntaxKind.CallStatement, TSyntaxKind.IfStatement, TSyntaxKind.CaseStatement, TSyntaxKind.CaseItem,
    TSyntaxKind.CaseElse, TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
    TSyntaxKind.RepeatStatement, TSyntaxKind.WithStatement, TSyntaxKind.TryStatement, TSyntaxKind.ExceptBlock,
    TSyntaxKind.ExceptionHandler, TSyntaxKind.FinallyBlock, TSyntaxKind.RaiseStatement, TSyntaxKind.GotoStatement,
    TSyntaxKind.LabeledStatement, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst, TSyntaxKind.EmptyStatement];
var
  Cache: IRuleDerivedCache;
  Routine: TSyntaxNode;
  Graph: TControlFlowGraph;
  Node: TFlowNode;
  Reported: TArray<Integer>;
  Path: string;
  ToNil: Boolean;

  function AlreadyReported(AOffset: Integer): Boolean;
  var
    Offset: Integer;
  begin
    for Offset in Reported do
      if Offset = AOffset then
        Exit(True);
    Result := False;
  end;

  // Zugriffe auf APath im eigenen Teil der Anweisung bzw. Bedingung ASyntax; AStops: der Weg endet hier.
  procedure Inspect(ASyntax: TSyntaxNode; const APath: string; AToNil: Boolean; var AUses: TArray<TSyntaxNode>;
    var AStops, AGuarded: Boolean);

    procedure Visit(E: TSyntaxNode);
    var
      Index: Integer;
      Callee: TSyntaxNode;
    begin
      if E.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl] then
        Exit;
      case E.Kind of
        TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess, TSyntaxKind.Dereference:
          if (E.ChildCount > 0) and SameText(FreedPath(E[0]), APath) then
          begin
            // Nach FreeAndNil ist ein weiteres Free harmlos.
            if not (AToNil and (E.Kind = TSyntaxKind.MemberAccess) and SameText(E.Name, 'Free')) then
              AUses := AUses + [E[0]];
            for Index := 1 to E.ChildCount - 1 do
              Visit(E[Index]);
            Exit;
          end;
        TSyntaxKind.Call:
          begin
            Callee := nil;
            if E.ChildCount > 0 then
              Callee := E[0];
            for Index := 1 to E.ChildCount - 1 do
              if SameText(FreedPath(E[Index]), APath) then
              begin
                if (Callee <> nil) and (Callee.Kind = TSyntaxKind.Identifier) and
                  MatchText(Callee.Name, ['Assigned', 'FreeAndNil']) and not AToNil then
                  // Nach Free: Assigned(X) ist immer True, FreeAndNil(X) gibt doppelt frei.
                  AUses := AUses + [E[Index]]
                else if (Callee <> nil) and (Callee.Kind = TSyntaxKind.Identifier) and
                  SameText(Callee.Name, 'Assigned') then
                  AGuarded := True
                else
                  // Übergabe: die Routine kann X neu setzen oder nur vergleichen (List.Remove(X)).
                  AStops := True;
              end;
          end;
        TSyntaxKind.AddressOf:
          if (E.ChildCount > 0) and SameText(FreedPath(E[0]), APath) then
          begin
            AStops := True;
            Exit;
          end;
        TSyntaxKind.BinaryExpr:
          // X = nil, X <> nil: eine Abfrage, die den Weg trennt.
          for Index := 0 to E.ChildCount - 1 do
            if SameText(FreedPath(E[Index]), APath) then
              AGuarded := True;
      end;
      for Index := 0 to E.ChildCount - 1 do
        Visit(E[Index]);
    end;

  var
    Index: Integer;
    Child: TSyntaxNode;
    AllChildren: Boolean;
  begin
    AllChildren := ASyntax.Kind in [TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement,
      TSyntaxKind.RaiseStatement, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst];
    for Index := 0 to ASyntax.ChildCount - 1 do
    begin
      Child := ASyntax[Index];
      if not AllChildren and (Child.Kind in StatementKinds) then
        Continue;
      if (Index = 0) and (ASyntax.Kind = TSyntaxKind.AssignStatement) and SameText(FreedPath(Child), APath) then
      begin
        AStops := True;
        Continue;
      end;
      if (ASyntax.Kind = TSyntaxKind.WithStatement) and SameText(FreedPath(Child), APath) then
      begin
        AUses := AUses + [Child];
        Continue;
      end;
      Visit(Child);
    end;
  end;

  procedure Follow(AFree: TFlowNode; const APath: string; AToNil: Boolean);
  var
    Visited: TArray<Boolean>;
    Queue: TArray<TFlowNode>;
    Head: Integer;
    Current, Next: TFlowNode;
    Accesses: TArray<TSyntaxNode>;
    Access: TSyntaxNode;
    Stops, Guarded: Boolean;
    Confidence: TRuleConfidence;
    FreeLine: Integer;
    Message: string;
  begin
    SetLength(Visited, Graph.Nodes.Count);
    // Wege nur über eine mögliche Ausnahme (die Anweisung wirkt dann nicht) bleiben aus: lieber zu wenig.
    Queue := nil;
    for Next in AFree.Successors do
      if not AFree.IsImplicitRaiseEdge(Next) then
        Queue := Queue + [Next];
    FreeLine := AFree.Syntax.StartPos.Line;
    Head := 0;
    while Head < Length(Queue) do
    begin
      Current := Queue[Head];
      Inc(Head);
      if Visited[Current.Index] then
        Continue;
      Visited[Current.Index] := True;
      // for und for … in weisen der Schleifenvariablen in jedem Durchlauf neu zu.
      Stops := SameText(Current.Defines, APath) or ((Current.Kind = TFlowNodeKind.Condition) and
        (Current.Syntax.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement]) and
        SameText(Current.Syntax.Name, APath));
      Guarded := False;
      Accesses := nil;
      if (Current.Syntax <> nil) and not Stops then
        Inspect(Current.Syntax, APath, AToNil, Accesses, Stops, Guarded);
      if Guarded and AToNil then
        Continue;
      for Access in Accesses do
      begin
        if AlreadyReported(Access.StartOffset) then
          Continue;
        Reported := Reported + [Access.StartOffset];
        // Im selben Block nacheinander: der Zugriff folgt sicher auf die Freigabe.
        Confidence := TRuleConfidence.Medium;
        if (Current.Syntax.Parent = AFree.Syntax.Parent) and (Current.Syntax.StartOffset > AFree.Syntax.StartOffset)
          then
          Confidence := TRuleConfidence.High;
        if AToNil then
          Message := Format('%s wurde in Zeile %d mit FreeAndNil freigegeben und ist hier nil.',
            [APath, FreeLine + 1])
        else
          Message := Format('%s wurde in Zeile %d freigegeben und wird hier wieder gelesen.', [APath, FreeLine + 1]);
        AReport.Add(NodeRange(Access), Message, Confidence,
          [TRuleFix.Jump(Format('Zur Freigabe in Zeile %d springen', [FreeLine + 1]), AFree.Syntax.StartPos)]);
      end;
      if Stops or Guarded then
        Continue;
      for Next in Current.Successors do
        if not Visited[Next.Index] and not Current.IsImplicitRaiseEdge(Next) then
          Queue := Queue + [Next];
    end;
  end;

begin
  if AContext.Tree = nil then
    Exit;
  Cache := TRuleDerived.Open(AContext);
  Reported := nil;
  for Routine in TRuleDerived.Routines(Cache, AContext) do
  begin
    Graph := TRuleDerived.Graph(Cache, AContext, Routine);
    if not Graph.Complete then
      Continue;
    for Node in Graph.Nodes do
      if (Node.Kind = TFlowNodeKind.Statement) and FreedBy(Node.Syntax, Path, ToNil) then
        Follow(Node, Path, ToNil);
  end;
end;

procedure RegisterFlowRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TResultNotSetRule.Create);
  ARegistry.Register(TPossiblyUninitializedRule.Create);
  ARegistry.Register(TUnreachableCodeRule.Create);
  ARegistry.Register(TUseAfterFreeRule.Create);
end;

end.
