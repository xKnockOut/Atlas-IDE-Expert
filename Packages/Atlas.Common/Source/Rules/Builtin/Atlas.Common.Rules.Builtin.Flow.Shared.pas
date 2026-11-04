unit Atlas.Common.Rules.Builtin.Flow.Shared;

// Gemeinsame Hilfen der Flussregeln aus Atlas.Common.Rules.Builtin.Flow (#269): Bereiche, Namen in Ausdrücken,
// Verwendungen, die der Kontrollfluss nicht sieht.

interface

uses
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Rules.Contract;

const
  /// <summary>Einfache Typen, die Delphi nicht vorbelegt.</summary>
  SimpleTypes: array[0..23] of string = ('Integer', 'Cardinal', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt',
    'Byte', 'Word', 'ShortInt', 'SmallInt', 'LongInt', 'LongWord', 'Boolean', 'ByteBool', 'WordBool', 'LongBool',
    'Char', 'AnsiChar', 'WideChar', 'Double', 'Single', 'Extended', 'Currency', 'Pointer');
  /// <summary>Verwaltete Typen, die Delphi vorbelegt.</summary>
  ManagedTypes: array[0..7] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString',
    'Variant', 'OleVariant', 'TArray');
  /// <summary>Anweisungen und ihre Teile; ein Knoten des Graphen wertet sie nicht selbst aus.</summary>
  FlowStatementKinds = [TSyntaxKind.Block, TSyntaxKind.AsmBlock, TSyntaxKind.AssignStatement,
    TSyntaxKind.CallStatement, TSyntaxKind.IfStatement, TSyntaxKind.CaseStatement, TSyntaxKind.CaseItem,
    TSyntaxKind.CaseElse, TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
    TSyntaxKind.RepeatStatement, TSyntaxKind.WithStatement, TSyntaxKind.TryStatement, TSyntaxKind.ExceptBlock,
    TSyntaxKind.ExceptionHandler, TSyntaxKind.FinallyBlock, TSyntaxKind.RaiseStatement, TSyntaxKind.GotoStatement,
    TSyntaxKind.LabeledStatement, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst, TSyntaxKind.EmptyStatement];

function NodeRange(ANode: TSyntaxNode): TTextRange;
/// <summary>Bezeichner, an dem eine Kette wie Result.Feld oder Result[I] hängt.</summary>
function RootName(ANode: TSyntaxNode): string;
function IsName(ANode: TSyntaxNode; const AName: string): Boolean;
/// <summary>ANode ist die Zuweisung "AName := …".</summary>
function IsAssignTo(ANode: TSyntaxNode; const AName: string): Boolean;
/// <summary>Wird AName in ABlock so benutzt, dass der Kontrollfluss die Zuweisung nicht sieht?</summary>
function HasOpaqueUse(ABlock: TSyntaxNode; const AName: string): Boolean;
function ContainsKind(ANode: TSyntaxNode; AKind: TSyntaxKind): Boolean;
function ShortName(const AName: string): string;
/// <summary>Bereich des Routinennamens im Kopf; sonst der Kopf.</summary>
function HeaderNameRange(const AContext: TRuleContext; ARoutine: TSyntaxNode): TTextRange;
/// <summary>Legt die Kinder von ANode rückwärts auf APending, damit das erste Kind zuerst drankommt.</summary>
procedure PushChildren(APending: TStack<TSyntaxNode>; ANode: TSyntaxNode);

/// <summary>Name einer Variablen oder eines Feldes (X oder Self.X); sonst ''.</summary>
function FreedPath(ANode: TSyntaxNode): string;
/// <summary>Gibt die Anweisung AStatement X frei? AToNil bei FreeAndNil.</summary>
function FreedBy(AStatement: TSyntaxNode; out APath: string; out AToNil: Boolean): Boolean;

/// <summary>Ausdrücke, die ein Knoten des Graphen selbst auswertet: bei einfachen Anweisungen alle Kinder,
/// bei if, while, for, case und with nur die Bedingung bzw. den Kopf.</summary>
function OwnParts(ASyntax: TSyntaxNode): TArray<TSyntaxNode>;
/// <summary>Weist der Knoten APath sicher einen Wert zu (Zuweisung, Schleifenvariable)?</summary>
function AssignsPath(ANode: TFlowNode; const APath: string): Boolean;
/// <summary>Weist eine Anweisung unter ANode APath zu?</summary>
function SubtreeAssigns(ANode: TSyntaxNode; const APath: string): Boolean;
/// <summary>Parameter, lokale Variablen und Inline-Variablen der Routine (ohne lokale Routinen).</summary>
function LocalNames(ARoutine: TSyntaxNode): TArray<string>;
/// <summary>Hängt die Nachfolger von ANode an AQueue, die noch nicht besucht sind; Kanten nur über eine mögliche
/// Ausnahme (die Anweisung wirkt dann nicht) bleiben aus.</summary>
procedure QueueSuccessors(ANode: TFlowNode; const AVisited: TArray<Boolean>; var AQueue: TArray<TFlowNode>);
/// <summary>Hängt die noch nicht besuchten Vorgänger von ANode an AQueue.</summary>
procedure QueuePredecessors(ANode: TFlowNode; const AVisited: TArray<Boolean>; var AQueue: TArray<TFlowNode>);

/// <summary>Deklaration der Klasse AClassName (letzter Namensteil) unter ARoot; nil ohne.</summary>
function FindClassType(ARoot: TSyntaxNode; const AClassName: string): TSyntaxNode;
/// <summary>Felder der Klassendeklaration AClass (ohne verschachtelte Typen).</summary>
function ClassFields(AClass: TSyntaxNode): TArray<string>;

/// <summary>Anonyme Methode oder lokale Routine: eigener Rumpf, eigener Ablauf.</summary>
function IsRoutineBody(ANode: TSyntaxNode): Boolean;
/// <summary>Quelltext von ANode in AText.</summary>
function SourceText(const AText: string; ANode: TSyntaxNode): string;
/// <summary>Einrückung vor ANode in AText; False, wenn davor in der Zeile noch Code steht.</summary>
function LineIndent(const AText: string; ANode: TSyntaxNode; out AIndent: string): Boolean;
/// <summary>Methodenname ohne Klasse (TKlasse.Laden -&gt; Laden).</summary>
function MethodOf(ARoutine: TSyntaxNode): string;
/// <summary>Klasse einer Methode (TKlasse.Laden -&gt; TKlasse); '' bei einer Routine ohne Klasse.</summary>
function ClassOf(ARoutine: TSyntaxNode): string;
/// <summary>Letzter Namensteil der Klasse ohne Typparameter (A.TStapel&lt;T&gt; -&gt; TStapel).</summary>
function DeclaredClassName(const AQualifiedClass: string): string;
/// <summary>Beginnt ARoutine mit dem Wort AWord (constructor, destructor; nicht class constructor)?</summary>
function StartsWithWord(const AText: string; ARoutine: TSyntaxNode; const AWord: string): Boolean;
/// <summary>Ruft ARoutine die Methode AName auf (AName; AName(…); Self.AName)?</summary>
function CallsMethod(ARoutine: TSyntaxNode; const AName: string): Boolean;
/// <summary>Pfade, die ANode selbst auf nil prüft: Assigned(X), X = nil, nil &lt;&gt; X und ähnliche Vergleiche.
/// </summary>
function NilCheckedPaths(ANode: TSyntaxNode): TArray<string>;

/// <summary>Stelle von AChild unter AParent; sonst -1.</summary>
function PositionIn(AParent, AChild: TSyntaxNode): Integer;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.Contract;

function NodeRange(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

function RootName(ANode: TSyntaxNode): string;
begin
  while (ANode <> nil) and (ANode.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess,
    TSyntaxKind.Dereference]) and (ANode.ChildCount > 0) do
  begin
    ANode := ANode[0];
  end;
  if (ANode <> nil) and (ANode.Kind = TSyntaxKind.Identifier) then
  begin
    Result := ANode.Name;
  end
  else
  begin
    Result := '';
  end;
end;

function IsName(ANode: TSyntaxNode; const AName: string): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, AName);
end;

function IsAssignTo(ANode: TSyntaxNode; const AName: string): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount = 2) and IsName(ANode[0], AName);
end;

/// <summary>ANode ist AName selbst oder ein Teil davon (AName.Feld, AName[I]).</summary>
function IsNameOrPart(ANode: TSyntaxNode; const AName: string): Boolean;
begin
  Result := IsName(ANode, AName) or ((ANode.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess]) and
    SameText(RootName(ANode), AName));
end;

/// <summary>Auch X.Feld oder X[I] als Argument: Ein var- oder out-Parameter schreibt dann einen Teil von X
/// (Liste.Find(Name, Eintrag.Wert)).</summary>
function PassedAsArgument(ACall: TSyntaxNode; const AName: string): Boolean;
var
  Index: Integer;
begin
  Result := False;
  for Index := 1 to ACall.ChildCount - 1 do
  begin
    Result := Result or IsNameOrPart(ACall[Index], AName);
  end;
end;

/// <summary>AName ist ein Ausdruck von with … do.</summary>
function IsWithTarget(AWith: TSyntaxNode; const AName: string): Boolean;
var
  Index: Integer;
begin
  Result := False;
  for Index := 0 to AWith.ChildCount - 2 do
  begin
    Result := Result or SameText(RootName(AWith[Index]), AName);
  end;
end;

/// <summary>Erster Teil von ANode hängt an AName (@X.Feld, X.Feld := …).</summary>
function FirstRootIs(ANode: TSyntaxNode; const AName: string): Boolean;
begin
  Result := (ANode.ChildCount > 0) and SameText(RootName(ANode[0]), AName);
end;

function FoundIf(AFound: Boolean): TSyntaxSearchStep;
begin
  Result := TSyntaxSearchStep.Descend;
  if AFound then
  begin
    Result := TSyntaxSearchStep.Found;
  end;
end;

/// <summary>Schritt der Suche in HasOpaqueUse für ANode.</summary>
function OpaqueStep(ANode: TSyntaxNode; const AName: string): TSyntaxSearchStep;
begin
  case ANode.Kind of
    // Lokale Routinen und anonyme Methoden laufen außerhalb dieses Flusses.
    TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod:
      Result := TSyntaxSearchStep.Skip;
    TSyntaxKind.Call:
      Result := FoundIf(PassedAsArgument(ANode, AName));
    TSyntaxKind.AddressOf:
      Result := FoundIf(FirstRootIs(ANode, AName));
    TSyntaxKind.AssignStatement:
      Result := FoundIf(FirstRootIs(ANode, AName) and (ANode[0].Kind <> TSyntaxKind.Identifier));
    TSyntaxKind.WithStatement:
      Result := FoundIf(IsWithTarget(ANode, AName));
  else
    Result := TSyntaxSearchStep.Descend;
  end;
end;

function HasOpaqueUse(ABlock: TSyntaxNode; const AName: string): Boolean;
var
  Name: string;
begin
  Name := AName;
  // Iterativ (Bericht M1): Der Lauf geht auch durch lange Ausdrucksketten.
  Result := ABlock.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := OpaqueStep(ANode, Name);
    end) <> nil;
end;

function ContainsKind(ANode: TSyntaxNode; AKind: TSyntaxKind): Boolean;
var
  Kind: TSyntaxKind;
begin
  Kind := AKind;
  // Iterativ (Bericht M1).
  Result := ANode.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    begin
      if AVisited.Kind = Kind then
      begin
        Exit(TSyntaxSearchStep.Found);
      end;
      if AVisited.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
      begin
        Exit(TSyntaxSearchStep.Skip);
      end;
      Result := TSyntaxSearchStep.Descend;
    end) <> nil;
end;

function ShortName(const AName: string): string;
begin
  Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

function HeaderNameRange(const AContext: TRuleContext; ARoutine: TSyntaxNode): TTextRange;
var
  Header: TSyntaxNode;
  Token: TPascalToken;
  Index: Integer;
  Name: string;
begin
  Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  if Header = nil then
  begin
    Header := ARoutine;
  end;
  Name := ShortName(ARoutine.Name);
  for Index := AContext.Tree.FirstTokenFrom(Header.StartOffset) to High(AContext.Tree.Tokens) do
  begin
    Token := AContext.Tree.Tokens[Index];
    if Token.Offset >= Header.EndOffset then
    begin
      Break;
    end;
    if (Token.Offset >= Header.StartOffset) and SameText(Token.Text, Name) then
    begin
      Exit(TTextRange.Create(Token.StartPos, Token.EndPos));
    end;
  end;
  Result := NodeRange(Header);
end;

procedure PushChildren(APending: TStack<TSyntaxNode>; ANode: TSyntaxNode);
var
  Child: Integer;
begin
  for Child := ANode.ChildCount - 1 downto 0 do
  begin
    APending.Push(ANode[Child]);
  end;
end;

function FreedPath(ANode: TSyntaxNode): string;
begin
  Result := '';
  if ANode = nil then
  begin
    Exit;
  end;
  if ANode.Kind = TSyntaxKind.Identifier then
  begin
    Result := ANode.Name;
  end
  else if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) and IsName(ANode[0], 'Self') then
  begin
    Result := ANode.Name;
  end;
  if SameText(Result, 'Self') or SameText(Result, 'inherited') then
  begin
    Result := '';
  end;
end;

function FreedBy(AStatement: TSyntaxNode; out APath: string; out AToNil: Boolean): Boolean;
var
  Callee, Target: TSyntaxNode;
begin
  Result := False;
  APath := '';
  AToNil := False;
  if (AStatement = nil) or (AStatement.Kind <> TSyntaxKind.CallStatement) or (AStatement.ChildCount = 0) then
  begin
    Exit;
  end;
  Callee := AStatement[0];
  Target := nil;
  // X.Free; bzw. X.Free();
  if (Callee.Kind = TSyntaxKind.Call) and (Callee.ChildCount = 1) then
  begin
    Callee := Callee[0];
  end;
  if (Callee.Kind = TSyntaxKind.MemberAccess) and (Callee.ChildCount = 1) and
    MatchText(Callee.Name, ['Free', 'Destroy', 'DisposeOf']) then
  begin
    Target := Callee[0];
  end
  else if (Callee.Kind = TSyntaxKind.Call) and (Callee.ChildCount = 2) and (Callee[0].Kind = TSyntaxKind.Identifier) and
    MatchText(Callee[0].Name, ['FreeAndNil', 'Dispose']) then
  begin
    Target := Callee[1];
    AToNil := SameText(Callee[0].Name, 'FreeAndNil');
  end;
  APath := FreedPath(Target);
  Result := APath <> '';
end;

function OwnParts(ASyntax: TSyntaxNode): TArray<TSyntaxNode>;
var
  Index: Integer;
  AllChildren: Boolean;
begin
  Result := nil;
  if ASyntax = nil then
  begin
    Exit;
  end;
  AllChildren := ASyntax.Kind in [TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement,
    TSyntaxKind.RaiseStatement, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst];
  for Index := 0 to ASyntax.ChildCount - 1 do
  begin
    if AllChildren or not (ASyntax[Index].Kind in FlowStatementKinds) then
    begin
      Result := Result + [ASyntax[Index]];
    end;
  end;
end;

function AssignsPath(ANode: TFlowNode; const APath: string): Boolean;
var
  S: TSyntaxNode;
begin
  S := ANode.Syntax;
  Result := SameText(ANode.Defines, APath);
  if Result or (S = nil) then
  begin
    Exit;
  end;
  if (ANode.Kind = TFlowNodeKind.Condition) and (S.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement]) and
    SameText(S.Name, APath) then
  begin
    Exit(True);
  end;
  Result := (S.Kind = TSyntaxKind.AssignStatement) and (S.ChildCount > 0) and SameText(FreedPath(S[0]), APath);
end;

function SubtreeAssigns(ANode: TSyntaxNode; const APath: string): Boolean;
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
      if (Node.Kind = TSyntaxKind.AssignStatement) and (Node.ChildCount > 0) and
        SameText(FreedPath(Node[0]), APath) then
      begin
        Exit(True);
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

function LocalNames(ARoutine: TSyntaxNode): TArray<string>;
var
  Index: Integer;
  Name: string;
  E: TSyntaxNode;
  Pending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Result := nil;
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ARoutine);
    while Pending.Count > 0 do
    begin
      E := Pending.Pop;
      if (E <> ARoutine) and (E.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) then
      begin
        Continue;
      end;
      if E.Kind in [TSyntaxKind.Parameter, TSyntaxKind.VarDecl, TSyntaxKind.InlineVar] then
      begin
        for Name in E.Name.Split([',']) do
        begin
          Result := Result + [Trim(Name)];
        end;
      end;
      for Index := E.ChildCount - 1 downto 0 do
      begin
        Pending.Push(E[Index]);
      end;
    end;
  finally
    Pending.Free;
  end;
end;

procedure QueueSuccessors(ANode: TFlowNode; const AVisited: TArray<Boolean>; var AQueue: TArray<TFlowNode>);
var
  Next: TFlowNode;
begin
  for Next in ANode.Successors do
  begin
    if not AVisited[Next.Index] and not ANode.IsImplicitRaiseEdge(Next) then
    begin
      AQueue := AQueue + [Next];
    end;
  end;
end;

procedure QueuePredecessors(ANode: TFlowNode; const AVisited: TArray<Boolean>; var AQueue: TArray<TFlowNode>);
var
  Prev: TFlowNode;
begin
  for Prev in ANode.Predecessors do
  begin
    if not AVisited[Prev.Index] then
    begin
      AQueue := AQueue + [Prev];
    end;
  end;
end;


function FindClassType(ARoot: TSyntaxNode; const AClassName: string): TSyntaxNode;
var
  Index: Integer;
  Node: TSyntaxNode;
  Pending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Result := nil;
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ARoot);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      if (Node.Kind = TSyntaxKind.TypeDecl) and SameText(Node.Name, AClassName) then
      begin
        // Ohne class-Teil (z. B. Vorwärtsdeklaration eines anderen Typs) weitersuchen.
        Result := Node.FindChild(TSyntaxKind.ClassType);
        if Result <> nil then
        begin
          Exit;
        end;
        Continue;
      end;
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        if not (Node[Index].Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.ImplementationSection]) then
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    end;
  finally
    Pending.Free;
  end;
end;

function ClassFields(AClass: TSyntaxNode): TArray<string>;
var
  Index: Integer;
  Name: string;
  E: TSyntaxNode;
  Pending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Result := nil;
  if AClass = nil then
  begin
    Exit;
  end;
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(AClass);
    while Pending.Count > 0 do
    begin
      E := Pending.Pop;
      if E.Kind = TSyntaxKind.Field then
      begin
        for Name in E.Name.Split([',']) do
        begin
          Result := Result + [Trim(Name)];
        end;
      end;
      for Index := E.ChildCount - 1 downto 0 do
      begin
        if E[Index].Kind <> TSyntaxKind.TypeSection then
        begin
          Pending.Push(E[Index]);
        end;
      end;
    end;
  finally
    Pending.Free;
  end;
end;

function IsRoutineBody(ANode: TSyntaxNode): Boolean;
begin
  Result := ANode.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl];
end;

function SourceText(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := Copy(AText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

function LineIndent(const AText: string; ANode: TSyntaxNode; out AIndent: string): Boolean;
var
  Start: Integer;
begin
  Start := ANode.StartOffset;
  while (Start > 0) and CharInSet(AText[Start], [' ', #9]) do
  begin
    Dec(Start);
  end;
  AIndent := Copy(AText, Start + 1, ANode.StartOffset - Start);
  Result := (Start = 0) or CharInSet(AText[Start], [#10, #13]);
end;

function MethodOf(ARoutine: TSyntaxNode): string;
begin
  Result := Copy(ARoutine.Name, LastDelimiter('.', ARoutine.Name) + 1, MaxInt);
end;

function ClassOf(ARoutine: TSyntaxNode): string;
begin
  Result := Copy(ARoutine.Name, 1, LastDelimiter('.', ARoutine.Name) - 1);
end;

function DeclaredClassName(const AQualifiedClass: string): string;
begin
  Result := Copy(AQualifiedClass, LastDelimiter('.', AQualifiedClass) + 1, MaxInt);
  if Pos('<', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  end;
end;

function StartsWithWord(const AText: string; ARoutine: TSyntaxNode; const AWord: string): Boolean;
var
  Head: string;
begin
  Head := TrimLeft(SourceText(AText, ARoutine));
  Result := StartsText(AWord, Head) and (Length(Head) > Length(AWord)) and
    CharInSet(Head[Length(AWord) + 1], [' ', #9, #10, #13]);
end;

function CallsMethod(ARoutine: TSyntaxNode; const AName: string): Boolean;
var
  Name: string;
begin
  Name := AName;
  // Iterativ (Bericht M1).
  Result := ARoutine.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode.Kind in [TSyntaxKind.CallStatement, TSyntaxKind.Call]) and (ANode.ChildCount > 0) and
        SameText(FreedPath(ANode[0]), Name) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

function NilCheckedPaths(ANode: TSyntaxNode): TArray<string>;
var
  Index: Integer;
begin
  Result := nil;
  if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 2) and IsName(ANode[0], 'Assigned') and
    (FreedPath(ANode[1]) <> '') then
  begin
    Result := Result + [FreedPath(ANode[1])];
  end;
  if (ANode.Kind <> TSyntaxKind.BinaryExpr) or (ANode.ChildCount <> 2) then
  begin
    Exit;
  end;
  for Index := 0 to 1 do
  begin
    if (FreedPath(ANode[Index]) <> '') and (ANode[1 - Index].Kind = TSyntaxKind.Literal) and
      SameText(ANode[1 - Index].Name, 'nil') then
    begin
      Result := Result + [FreedPath(ANode[Index])];
    end;
  end;
end;

function PositionIn(AParent, AChild: TSyntaxNode): Integer;
var
  Index: Integer;
begin
  Result := -1;
  for Index := 0 to AParent.ChildCount - 1 do
  begin
    if AParent[Index] = AChild then
    begin
      Result := Index;
    end;
  end;
end;

end.
