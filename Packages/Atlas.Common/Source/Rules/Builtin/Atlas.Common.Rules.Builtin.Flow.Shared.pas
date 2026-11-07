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
  cSimpleTypes: array[0..23] of string = ('Integer', 'Cardinal', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt',
    'Byte', 'Word', 'ShortInt', 'SmallInt', 'LongInt', 'LongWord', 'Boolean', 'ByteBool', 'WordBool', 'LongBool',
    'Char', 'AnsiChar', 'WideChar', 'Double', 'Single', 'Extended', 'Currency', 'Pointer');
  /// <summary>Verwaltete Typen, die Delphi vorbelegt.</summary>
  cManagedTypes: array[0..7] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString',
    'Variant', 'OleVariant', 'TArray');
  /// <summary>Anweisungen und ihre Teile; ein Knoten des Graphen wertet sie nicht selbst aus.</summary>
  cFlowStatementKinds = [TSyntaxKind.Block, TSyntaxKind.AsmBlock, TSyntaxKind.AssignStatement,
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
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 1 to ACall.ChildCount - 1 do
  begin
    Result := Result or IsNameOrPart(ACall[mIndex], AName);
  end;
end;

/// <summary>AName ist ein Ausdruck von with … do.</summary>
function IsWithTarget(AWith: TSyntaxNode; const AName: string): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 0 to AWith.ChildCount - 2 do
  begin
    Result := Result or SameText(RootName(AWith[mIndex]), AName);
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
  mName: string;
begin
  mName := AName;
  // Iterativ (Bericht M1): Der Lauf geht auch durch lange Ausdrucksketten.
  Result := ABlock.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := OpaqueStep(ANode, mName);
    end) <> nil;
end;

function ContainsKind(ANode: TSyntaxNode; AKind: TSyntaxKind): Boolean;
var
  mKind: TSyntaxKind;
begin
  mKind := AKind;
  // Iterativ (Bericht M1).
  Result := ANode.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    begin
      if AVisited.Kind = mKind then
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
  mHeader: TSyntaxNode;
  mToken: TPascalToken;
  mIndex: Integer;
  mName: string;
begin
  mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  if mHeader = nil then
  begin
    mHeader := ARoutine;
  end;
  mName := ShortName(ARoutine.Name);
  for mIndex := AContext.Tree.FirstTokenFrom(mHeader.StartOffset) to High(AContext.Tree.Tokens) do
  begin
    mToken := AContext.Tree.Tokens[mIndex];
    if mToken.Offset >= mHeader.EndOffset then
    begin
      Break;
    end;
    if (mToken.Offset >= mHeader.StartOffset) and SameText(mToken.Text, mName) then
    begin
      Exit(TTextRange.Create(mToken.StartPos, mToken.EndPos));
    end;
  end;
  Result := NodeRange(mHeader);
end;

procedure PushChildren(APending: TStack<TSyntaxNode>; ANode: TSyntaxNode);
var
  mChild: Integer;
begin
  for mChild := ANode.ChildCount - 1 downto 0 do
  begin
    APending.Push(ANode[mChild]);
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
  mCallee, mTarget: TSyntaxNode;
begin
  Result := False;
  APath := '';
  AToNil := False;
  if (AStatement = nil) or (AStatement.Kind <> TSyntaxKind.CallStatement) or (AStatement.ChildCount = 0) then
  begin
    Exit;
  end;
  mCallee := AStatement[0];
  mTarget := nil;
  // X.Free; bzw. X.Free();
  if (mCallee.Kind = TSyntaxKind.Call) and (mCallee.ChildCount = 1) then
  begin
    mCallee := mCallee[0];
  end;
  if (mCallee.Kind = TSyntaxKind.MemberAccess) and (mCallee.ChildCount = 1) and
    MatchText(mCallee.Name, ['Free', 'Destroy', 'DisposeOf']) then
  begin
    mTarget := mCallee[0];
  end
  else if (mCallee.Kind = TSyntaxKind.Call) and (mCallee.ChildCount = 2) and
    (mCallee[0].Kind = TSyntaxKind.Identifier) and
    MatchText(mCallee[0].Name, ['FreeAndNil', 'Dispose']) then
  begin
    mTarget := mCallee[1];
    AToNil := SameText(mCallee[0].Name, 'FreeAndNil');
  end;
  APath := FreedPath(mTarget);
  Result := APath <> '';
end;

function OwnParts(ASyntax: TSyntaxNode): TArray<TSyntaxNode>;
var
  mIndex: Integer;
  mAllChildren: Boolean;
begin
  Result := nil;
  if ASyntax = nil then
  begin
    Exit;
  end;
  mAllChildren := ASyntax.Kind in [TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement,
    TSyntaxKind.RaiseStatement, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst];
  for mIndex := 0 to ASyntax.ChildCount - 1 do
  begin
    if mAllChildren or not (ASyntax[mIndex].Kind in cFlowStatementKinds) then
    begin
      Result := Result + [ASyntax[mIndex]];
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
  mIndex: Integer;
  mNode: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Result := False;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if (mNode.Kind = TSyntaxKind.AssignStatement) and (mNode.ChildCount > 0) and
        SameText(FreedPath(mNode[0]), APath) then
      begin
        Exit(True);
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

function LocalNames(ARoutine: TSyntaxNode): TArray<string>;
var
  mIndex: Integer;
  mName: string;
  E: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Result := nil;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoutine);
    while mPending.Count > 0 do
    begin
      E := mPending.Pop;
      if (E <> ARoutine) and (E.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) then
      begin
        Continue;
      end;
      if E.Kind in [TSyntaxKind.Parameter, TSyntaxKind.VarDecl, TSyntaxKind.InlineVar] then
      begin
        for mName in E.Name.Split([',']) do
        begin
          Result := Result + [Trim(mName)];
        end;
      end;
      for mIndex := E.ChildCount - 1 downto 0 do
      begin
        mPending.Push(E[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

procedure QueueSuccessors(ANode: TFlowNode; const AVisited: TArray<Boolean>; var AQueue: TArray<TFlowNode>);
var
  mNext: TFlowNode;
begin
  for mNext in ANode.Successors do
  begin
    if not AVisited[mNext.Index] and not ANode.IsImplicitRaiseEdge(mNext) then
    begin
      AQueue := AQueue + [mNext];
    end;
  end;
end;

procedure QueuePredecessors(ANode: TFlowNode; const AVisited: TArray<Boolean>; var AQueue: TArray<TFlowNode>);
var
  mPrev: TFlowNode;
begin
  for mPrev in ANode.Predecessors do
  begin
    if not AVisited[mPrev.Index] then
    begin
      AQueue := AQueue + [mPrev];
    end;
  end;
end;


function FindClassType(ARoot: TSyntaxNode; const AClassName: string): TSyntaxNode;
var
  mIndex: Integer;
  mNode: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Result := nil;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if (mNode.Kind = TSyntaxKind.TypeDecl) and SameText(mNode.Name, AClassName) then
      begin
        // Ohne class-Teil (z. B. Vorwärtsdeklaration eines anderen Typs) weitersuchen.
        Result := mNode.FindChild(TSyntaxKind.ClassType);
        if Result <> nil then
        begin
          Exit;
        end;
        Continue;
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        if not (mNode[mIndex].Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.ImplementationSection]) then
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    end;
  finally
    mPending.Free;
  end;
end;

function ClassFields(AClass: TSyntaxNode): TArray<string>;
var
  mIndex: Integer;
  mName: string;
  E: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Result := nil;
  if AClass = nil then
  begin
    Exit;
  end;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(AClass);
    while mPending.Count > 0 do
    begin
      E := mPending.Pop;
      if E.Kind = TSyntaxKind.Field then
      begin
        for mName in E.Name.Split([',']) do
        begin
          Result := Result + [Trim(mName)];
        end;
      end;
      for mIndex := E.ChildCount - 1 downto 0 do
      begin
        if E[mIndex].Kind <> TSyntaxKind.TypeSection then
        begin
          mPending.Push(E[mIndex]);
        end;
      end;
    end;
  finally
    mPending.Free;
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
  mStart: Integer;
begin
  mStart := ANode.StartOffset;
  while (mStart > 0) and CharInSet(AText[mStart], [' ', #9]) do
  begin
    Dec(mStart);
  end;
  AIndent := Copy(AText, mStart + 1, ANode.StartOffset - mStart);
  Result := (mStart = 0) or CharInSet(AText[mStart], [#10, #13]);
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
  mHead: string;
begin
  mHead := TrimLeft(SourceText(AText, ARoutine));
  Result := StartsText(AWord, mHead) and (Length(mHead) > Length(AWord)) and
    CharInSet(mHead[Length(AWord) + 1], [' ', #9, #10, #13]);
end;

function CallsMethod(ARoutine: TSyntaxNode; const AName: string): Boolean;
var
  mName: string;
begin
  mName := AName;
  // Iterativ (Bericht M1).
  Result := ARoutine.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode.Kind in [TSyntaxKind.CallStatement, TSyntaxKind.Call]) and (ANode.ChildCount > 0) and
        SameText(FreedPath(ANode[0]), mName) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

function NilCheckedPaths(ANode: TSyntaxNode): TArray<string>;
var
  mIndex: Integer;
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
  for mIndex := 0 to 1 do
  begin
    if (FreedPath(ANode[mIndex]) <> '') and (ANode[1 - mIndex].Kind = TSyntaxKind.Literal) and
      SameText(ANode[1 - mIndex].Name, 'nil') then
    begin
      Result := Result + [FreedPath(ANode[mIndex])];
    end;
  end;
end;

function PositionIn(AParent, AChild: TSyntaxNode): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to AParent.ChildCount - 1 do
  begin
    if AParent[mIndex] = AChild then
    begin
      Result := mIndex;
    end;
  end;
end;

end.
