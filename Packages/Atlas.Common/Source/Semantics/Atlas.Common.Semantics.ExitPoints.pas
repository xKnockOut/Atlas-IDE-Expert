unit Atlas.Common.Semantics.ExitPoints;

// Austrittspunkte einer Routine (#698), gemeinsam für die Hervorhebung im
// IDE-Plugin (atlas.server.exitPoints) und textDocument/documentHighlight
// (#307, Atlas.Common.Lsp.KeywordHighlights):
// - Auf Exit, raise, Abort, Halt, RunError oder dem Namen der Routine in ihrem
//   Kopf: alle Stellen, an denen die Routine verlassen wird. Dazu zählen
//   Aufrufe von Routinen, die immer auslösen: Routinen derselben Unit, deren
//   Kontrollflussgraph (#143) das normale Ende nie erreicht, und bekannte
//   RTL-Routinen (RaiseLastOSError …). Das abschließende end nur, wenn ein Weg
//   dort herausfällt; ein Aufruf, der immer auslöst, beendet den Weg.
// - Auf Result bzw. dem Funktionsnamen als Ziel einer Zuweisung zusätzlich
//   jede Zuweisung an das Ergebnis. Austritte, an denen es auf einem Weg noch
//   ungesetzt sein kann, tragen ResultMissing (wie W1035 des Compilers).
// - Auf except, on oder der Klasse in on E: EKlasse: Aufrufe im try-Teil, die
//   laut XMLDoc (<exception cref>, #427) eine passende Exception auslösen
//   können, und raise-Anweisungen dieses Typs im try-Teil.
// - Auf Break/Continue: Kopf, do und Ende der Schleife sowie ihre übrigen
//   Break/Continue.
// Verschachtelte Routinen und anonyme Methoden zählen nur für sich. Was eine
// Routine laut XMLDoc auslöst und ob eine Klasse von einer anderen abstammt,
// fragt die Analyse über Funktionen; ohne Angabe gelten der Baum selbst
// (Doku und Klassen derselben Unit) und die Namenskonvention (jede Klasse
// stammt von Exception ab).

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
{$SCOPEDENUMS ON}
  TExitPointKind = (
    /// <summary>Exit bzw. Exit(Wert).</summary>
    ExitCall,
    /// <summary>raise, auch raise; im except-Teil, und Abort.</summary>
    RaiseStatement,
    /// <summary>Halt und RunError beenden das Programm.</summary>
    Terminate,
    /// <summary>Aufruf einer Routine, die immer auslöst.</summary>
    RaisingCall,
    /// <summary>Abschließendes end, wenn ein Weg dort herausfällt.</summary>
    FallThrough,
    /// <summary>Zuweisung an Result bzw. den Funktionsnamen.</summary>
    ResultAssign,
    /// <summary>Aufruf im try-Teil, der die Exception laut XMLDoc auslösen kann, oder raise dieses Typs.</summary>
    ExceptionSource,
    /// <summary>except, on bzw. die Klasse eines Handlers, von dem die Abfrage ausging.</summary>
    Handler,
    /// <summary>Kopf, do, end bzw. until der Schleife.</summary>
    LoopPart,
    /// <summary>Break bzw. Continue der Schleife.</summary>
    LoopJump);

  /// <summary>Wovon die Abfrage ausging.</summary>
  TExitPointQuery = (None, Routine, ResultValue, Exceptions, Loop);
{$SCOPEDENUMS OFF}

  TExitPoint = record
    Kind: TExitPointKind;
    Range: TTextRange;
    /// <summary>Austritt einer Funktion, an dem das Ergebnis auf einem Weg noch ungesetzt sein kann.</summary>
    ResultMissing: Boolean;
    /// <summary>Name der Routine bei RaisingCall und ExceptionSource (Aufruf), Klasse bei raise in
    /// ExceptionSource; sonst ''.</summary>
    Detail: string;
    /// <summary>Bei ExceptionSource: die passende Exception-Klasse; sonst ''.</summary>
    ExceptionClass: string;
    function IsExit: Boolean;
  end;

  TExitPointSet = record
    Query: TExitPointQuery;
    /// <summary>Name der Routine wie im Kopf (TFoo.Bar); '' ohne.</summary>
    RoutineName: string;
    /// <summary>Name der Routine im Kopf (Ort der Marke „3 Austritte“); nur mit HasRoutine.</summary>
    RoutineRange: TTextRange;
    HasRoutine: Boolean;
    /// <summary>Funktion (mit Ergebnistyp).</summary>
    IsFunction: Boolean;
    /// <summary>Alle Stellen nach Position.</summary>
    Points: TArray<TExitPoint>;
    function Found: Boolean;
    /// <summary>Zahl der Austritte (Exit, raise, Halt, auslösende Aufrufe, end).</summary>
    function ExitCount: Integer;
    /// <summary>Kann die Funktion auf einem Weg ohne Ergebnis enden?</summary>
    function ResultMissing: Boolean;
  end;

  TExitPointOptions = record
    /// <summary>highlight.exitPoints.exceptions: Abfragen auf except bzw. on beantworten.</summary>
    Exceptions: Boolean;
    /// <summary>highlight.exitPoints.loops: Abfragen auf Break bzw. Continue beantworten.</summary>
    Loops: Boolean;
    /// <summary>Was als Austritt zählt (highlight.exitKeywords: Exit, raise, Abort, Halt; RunError gilt mit
    /// Halt); nil = alles. Aufrufe, die immer auslösen, zählen immer; weitere Wörter gelten wie solche
    /// Aufrufe.</summary>
    Keywords: TArray<string>;
    class function Default: TExitPointOptions; static;
  end;

  /// <summary>Exception-Klassen, die der Aufruf mit dem Ziel ACallee (Identifier oder MemberAccess) laut XMLDoc
  /// auslösen kann; nil, wenn nichts bekannt ist.</summary>
  TExitPointExceptionLookup = reference to function(ACallee: TSyntaxNode): TArray<string>;

  /// <summary>Ist AClass die Klasse AHandler oder stammt sie davon ab? AOffset ist die Stelle des Handlers.</summary>
  TExitPointClassTest = reference to function(const AClass, AHandler: string; AOffset: Integer): Boolean;

  TExitPoints = class
  public const
    /// <summary>RTL-Routinen, die immer auslösen bzw. das Programm beenden.</summary>
    RaisingRoutines: array[0..3] of string = ('RaiseLastOSError', 'RaiseLastWin32Error', 'OutOfMemoryError',
      'Abort');
  public
    /// <summary>Stellen zur Abfrage an APosition; Query None, wenn dort nichts Passendes steht.</summary>
    class function Find(ATree: TSyntaxTree; const APosition: TTextPosition;
      const AOptions: TExitPointOptions; const AExceptions: TExitPointExceptionLookup;
      const AIsA: TExitPointClassTest): TExitPointSet; overload; static;
    /// <summary>Wie oben mit Doku und Klassen nur aus dem Baum (ALines sind seine Zeilen).</summary>
    class function Find(ATree: TSyntaxTree; const ALines: TArray<string>; const APosition: TTextPosition;
      const AOptions: TExitPointOptions): TExitPointSet; overload; static;
    /// <summary>Austritte der Routine bzw. anonymen Methode ARoutine (ohne die Abfrage).</summary>
    class function RoutineExits(ATree: TSyntaxTree; ARoutine: TSyntaxNode;
      const AOptions: TExitPointOptions): TExitPointSet; static;
    /// <summary>XMLDoc der Routinen in ATree: &lt;exception cref&gt; über Deklaration oder Rumpf.</summary>
    class function TreeExceptions(ATree: TSyntaxTree; const ALines: TArray<string>): TExitPointExceptionLookup;
      static;
    /// <summary>Vererbung der Klassen in ATree; unbekannte Klassen stammen von Exception ab.</summary>
    class function TreeClassTest(ATree: TSyntaxTree): TExitPointClassTest; static;
    /// <summary>Name der Routine, die der Aufruf mit dem Ziel ACallee meint: einfacher Name oder Self.Name;
    /// '' bei Aufrufen über andere Objekte.</summary>
    class function PlainCallee(ACallee: TSyntaxNode): string; static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.XmlDoc,
  Atlas.Common.Semantics.ControlFlow;

type
  TSyntaxKindSet = set of TSyntaxKind;

const
  RoutineKinds = [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod];
  LoopKinds = [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
    TSyntaxKind.RepeatStatement];

{ TExitPoint }

function TExitPoint.IsExit: Boolean;
begin
  Result := Kind in [TExitPointKind.ExitCall, TExitPointKind.RaiseStatement, TExitPointKind.Terminate,
    TExitPointKind.RaisingCall, TExitPointKind.FallThrough];
end;

{ TExitPointSet }

function TExitPointSet.Found: Boolean;
begin
  Result := Query <> TExitPointQuery.None;
end;

function TExitPointSet.ExitCount: Integer;
var
  Point: TExitPoint;
begin
  Result := 0;
  for Point in Points do
    if Point.IsExit then
      Inc(Result);
end;

function TExitPointSet.ResultMissing: Boolean;
var
  Point: TExitPoint;
begin
  Result := False;
  for Point in Points do
    if Point.ResultMissing then
      Exit(True);
end;

{ TExitPointOptions }

class function TExitPointOptions.Default: TExitPointOptions;
begin
  Result.Exceptions := True;
  Result.Loops := True;
  Result.Keywords := nil;
end;

{ Hilfen }

function ShortName(const AName: string): string;
begin
  Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

function TokenRange(const AToken: TPascalToken): TTextRange;
begin
  Result := TTextRange.Create(AToken.StartPos, AToken.EndPos);
end;

/// <summary>Token, das an AOffset beginnt; -1 ohne.</summary>
function TokenAtOffset(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
var
  Low, High, Middle: Integer;
begin
  Low := 0;
  High := Length(ATokens) - 1;
  while Low <= High do
  begin
    Middle := (Low + High) div 2;
    if ATokens[Middle].Offset < AOffset then
      Low := Middle + 1
    else if ATokens[Middle].Offset > AOffset then
      High := Middle - 1
    else
      Exit(Middle);
  end;
  Result := -1;
end;

/// <summary>Bezeichner oder Schlüsselwort, auf dem APosition steht (auch direkt dahinter); -1 ohne.</summary>
function WordAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
var
  Index: Integer;
  Token: TPascalToken;
begin
  for Index := 0 to High(ATokens) do
  begin
    Token := ATokens[Index];
    if (Token.StartPos.Line > APosition.Line) or
      ((Token.StartPos.Line = APosition.Line) and (Token.StartPos.Character > APosition.Character)) then
      Break;
    if (Token.EndPos.Line = APosition.Line) and (APosition.Character <= Token.EndPos.Character) and
      (Token.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) then
      Exit(Index);
  end;
  Result := -1;
end;

/// <summary>Letztes Schlüsselwort AWord in [AStartOffset, AEndOffset); -1 ohne.</summary>
function LastKeyword(const ATokens: TArray<TPascalToken>; AStartOffset, AEndOffset: Integer;
  const AWord: string): Integer;
var
  Index: Integer;
begin
  Result := -1;
  for Index := 0 to High(ATokens) do
  begin
    if ATokens[Index].Offset >= AEndOffset then
      Break;
    if (ATokens[Index].Offset >= AStartOffset) and ATokens[Index].IsKeyword(AWord) then
      Result := Index;
  end;
end;

/// <summary>Innerster Knoten einer der Arten AKinds, der AOffset enthält; ABoundaries beenden die Suche nach
/// außen (ein Break in einer anonymen Methode gehört nicht zur Schleife außen).</summary>
function Innermost(ARoot: TSyntaxNode; AOffset: Integer; const AKinds, ABoundaries: TSyntaxKindSet): TSyntaxNode;
var
  Node, Child: TSyntaxNode;
  Index: Integer;
begin
  // Von der Wurzel abwärts dem Kind folgen, das AOffset enthält; der letzte Treffer ist der innerste.
  Result := nil;
  Node := ARoot;
  while Node <> nil do
  begin
    Child := nil;
    for Index := 0 to Node.ChildCount - 1 do
      if (AOffset >= Node[Index].StartOffset) and (AOffset < Node[Index].EndOffset) then
      begin
        Child := Node[Index];
        Break;
      end;
    if Child = nil then
      Break;
    if Child.Kind in AKinds then
      Result := Child
    else if Child.Kind in ABoundaries then
      Result := nil;
    Node := Child;
  end;
end;

function BodyOf(ARoutine: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if ARoutine <> nil then
    Result := ARoutine.FindChild(TSyntaxKind.Block);
end;

/// <summary>Knoten unter ARoot ohne verschachtelte Routinen und anonyme Methoden, in Baumreihenfolge.</summary>
function OwnNodes(ARoot: TSyntaxNode; const AKinds: TSyntaxKindSet): TArray<TSyntaxNode>;
var
  List: TList<TSyntaxNode>;
  Kinds: TSyntaxKindSet;
  Root: TSyntaxNode;
begin
  List := TList<TSyntaxNode>.Create;
  try
    Kinds := AKinds;
    Root := ARoot;
    ARoot.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        if (ANode <> Root) and (ANode.Kind in RoutineKinds) then
          Exit(False);
        if ANode.Kind in Kinds then
          List.Add(ANode);
        Result := True;
      end);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function IsFunctionRoutine(ARoutine: TSyntaxNode): Boolean;
var
  Header: TSyntaxNode;
begin
  Result := False;
  if ARoutine = nil then
    Exit;
  if ARoutine.Kind = TSyntaxKind.AnonymousMethod then
    Header := ARoutine
  else
    Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  Result := (Header <> nil) and (Header.FindChild(TSyntaxKind.TypeReference) <> nil);
end;

class function TExitPoints.PlainCallee(ACallee: TSyntaxNode): string;
begin
  Result := '';
  if ACallee = nil then
    Exit;
  if ACallee.Kind = TSyntaxKind.Identifier then
    Result := ACallee.Name
  else if (ACallee.Kind = TSyntaxKind.MemberAccess) and (ACallee.ChildCount = 1) and
    (ACallee[0].Kind = TSyntaxKind.Identifier) and SameText(ACallee[0].Name, 'Self') then
    Result := ACallee.Name;
end;

/// <summary>Ziel eines Aufrufs: bei CallStatement der Ausdruck (bzw. dessen Ziel, wenn es ein Aufruf mit
/// Klammern ist), bei Call das erste Kind.</summary>
function CalleeOf(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if ANode.ChildCount = 0 then
    Exit;
  Result := ANode[0];
  if (ANode.Kind = TSyntaxKind.CallStatement) and (Result.Kind = TSyntaxKind.Call) and (Result.ChildCount > 0) then
    Result := Result[0];
end;

/// <summary>Name einer Anweisung wie Exit, Break, Abort: nur ohne Objekt davor (TMonitor.Exit(FLock) zählt
/// nicht, #647).</summary>
function StatementWord(AStatement: TSyntaxNode): string;
begin
  Result := '';
  if AStatement.Kind <> TSyntaxKind.CallStatement then
    Exit;
  if AStatement.ChildCount = 0 then
    Result := AStatement.Name
  else
    Result := TExitPoints.PlainCallee(CalleeOf(AStatement));
  if (Result <> '') and (Pos('.', Result) > 0) then
    Result := '';
end;

/// <summary>Bereich des Namens am Ende des Aufrufziels (Foo bzw. Bar in Obj.Bar).</summary>
function CalleeNameRange(const ATokens: TArray<TPascalToken>; ACallee: TSyntaxNode): TTextRange;
var
  Index: Integer;
begin
  Result := TTextRange.Create(ACallee.StartPos, ACallee.EndPos);
  for Index := High(ATokens) downto 0 do
    if ATokens[Index].Offset < ACallee.EndOffset then
    begin
      if ATokens[Index].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword] then
        Result := TokenRange(ATokens[Index]);
      Break;
    end;
end;

function WordWanted(const AOptions: TExitPointOptions; const AWord: string): Boolean;
begin
  Result := (AOptions.Keywords = nil) or MatchText(AWord, AOptions.Keywords) or
    (SameText(AWord, 'RunError') and MatchText('Halt', AOptions.Keywords));
end;

function ComparePoints(const A, B: TExitPoint): Integer;
begin
  Result := A.Range.StartPos.Line - B.Range.StartPos.Line;
  if Result = 0 then
    Result := A.Range.StartPos.Character - B.Range.StartPos.Character;
  if Result = 0 then
    Result := Ord(A.Kind) - Ord(B.Kind);
end;

/// <summary>Nach Position, je Stelle nur der erste Eintrag (TArray.Sort ist nicht stabil: Art als dritter
/// Schlüssel).</summary>
function Sorted(const APoints: TArray<TExitPoint>): TArray<TExitPoint>;
var
  Items: TArray<TExitPoint>;
  Point: TExitPoint;
  Count: Integer;
begin
  Items := Copy(APoints);
  TArray.Sort<TExitPoint>(Items, TComparer<TExitPoint>.Construct(ComparePoints));
  Result := nil;
  SetLength(Result, Length(Items));
  Count := 0;
  for Point in Items do
  begin
    if (Count > 0) and (Result[Count - 1].Range.StartPos = Point.Range.StartPos) then
      Continue;
    Result[Count] := Point;
    Inc(Count);
  end;
  SetLength(Result, Count);
end;

function MakePoint(AKind: TExitPointKind; const ARange: TTextRange; const ADetail: string): TExitPoint;
begin
  Result := Default(TExitPoint);
  Result.Kind := AKind;
  Result.Range := ARange;
  Result.Detail := ADetail;
end;

{ Routinen, die immer auslösen }

type
  /// <summary>Namen der Routinen derselben Unit, die das normale Ende nie erreichen (#143).</summary>
  TRaisingRoutines = class
  private
    FNames: TDictionary<string, Boolean>;
  public
    constructor Create(ATree: TSyntaxTree);
    destructor Destroy; override;
    function Contains(const AName: string): Boolean;
  end;

constructor TRaisingRoutines.Create(ATree: TSyntaxTree);
var
  Routines: TList<TSyntaxNode>;
  Routine, Body: TSyntaxNode;
  Graph: TControlFlowGraph;
  Name: string;
begin
  inherited Create;
  FNames := TDictionary<string, Boolean>.Create;
  for Name in TExitPoints.RaisingRoutines do
    FNames.AddOrSetValue(UpperCase(Name), True);
  if ATree = nil then
    Exit;
  Routines := TList<TSyntaxNode>.Create;
  try
    ATree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        if (ANode.Kind = TSyntaxKind.RoutineDecl) and (ANode.FindChild(TSyntaxKind.Block) <> nil) then
          Routines.Add(ANode);
        // Anonyme Methoden haben keinen Namen; was in ihnen steht, zählt nicht.
        Result := ANode.Kind <> TSyntaxKind.AnonymousMethod;
      end);
    for Routine in Routines do
    begin
      Body := BodyOf(Routine);
      // Vorfilter: Ohne raise und Abort im eigenen Rumpf kann die Routine nicht immer auslösen.
      if Length(OwnNodes(Body, [TSyntaxKind.RaiseStatement])) = 0 then
        Continue;
      Graph := TControlFlowGraph.Build(Routine);
      try
        if Graph.Complete and (Graph.IsReachable(Graph.ExitNode) = TFlowAnswer.No) and
          (Graph.IsReachable(Graph.RaiseExit) = TFlowAnswer.Yes) then
          FNames.AddOrSetValue(UpperCase(ShortName(Routine.Name)), True);
      finally
        Graph.Free;
      end;
    end;
  finally
    Routines.Free;
  end;
end;

destructor TRaisingRoutines.Destroy;
begin
  FNames.Free;
  inherited;
end;

function TRaisingRoutines.Contains(const AName: string): Boolean;
begin
  Result := (AName <> '') and FNames.ContainsKey(UpperCase(AName));
end;

{ Austritte }

/// <summary>Kann ein Weg am Ende herausfallen? Wie ControlFlow, aber ein Aufruf, der immer auslöst, beendet
/// den Weg. Unvollständiger Graph: ja (lieber das end zeigen als einen Austritt verschweigen).</summary>
function FallsThrough(AGraph: TControlFlowGraph; ARaising: TRaisingRoutines;
  out AEnds: TArray<TFlowNode>): Boolean;
var
  Seen: TArray<Boolean>;
  Stack: TStack<TFlowNode>;
  Node, Next: TFlowNode;
  Ends: TDictionary<TFlowNode, Boolean>;
begin
  AEnds := nil;
  if not AGraph.Complete then
    Exit(True);
  Ends := TDictionary<TFlowNode, Boolean>.Create;
  Stack := TStack<TFlowNode>.Create;
  try
    for Node in AGraph.FallThrough do
      Ends.AddOrSetValue(Node, True);
    SetLength(Seen, AGraph.Nodes.Count);
    Stack.Push(AGraph.Entry);
    Seen[AGraph.Entry.Index] := True;
    while Stack.Count > 0 do
    begin
      Node := Stack.Pop;
      // RunError beendet das Programm wie Halt (das ControlFlow schon ans Ende führt).
      if (Node.Syntax <> nil) and (Node.Syntax.Kind = TSyntaxKind.CallStatement) and
        (ARaising.Contains(StatementWord(Node.Syntax)) or SameText(StatementWord(Node.Syntax), 'RunError')) then
        Continue;
      if Ends.ContainsKey(Node) then
        AEnds := AEnds + [Node];
      for Next in Node.Successors do
        if not Seen[Next.Index] then
        begin
          Seen[Next.Index] := True;
          Stack.Push(Next);
        end;
    end;
  finally
    Stack.Free;
    Ends.Free;
  end;
  Result := Length(AEnds) > 0;
end;

/// <summary>Kann das Ergebnis vor ANode (bzw. mit AAfter nach ANode) noch ungesetzt sein? Nur sichere Wege:
/// Eine unsichere Änderung (var-Argument, Result.Feld …) gilt als gesetzt.</summary>
function MissingAt(AGraph: TControlFlowGraph; ANode: TFlowNode; const AName: string; AAfter: Boolean): Boolean;

  function Missing(const AVariable: string): Boolean;
  var
    Reaching: TReachingDefinitions;
  begin
    if AAfter and (SameText(ANode.Defines, AVariable) or ANode.TouchesName(AVariable)) then
      Exit(False);
    Reaching := AGraph.ReachingDefinitions(ANode, AVariable);
    Result := Reaching.FromEntry;
  end;

begin
  Result := (ANode <> nil) and AGraph.Complete and Missing('Result') and Missing(AName);
end;

function ExitPointsOf(ATree: TSyntaxTree; ARoutine: TSyntaxNode; const AOptions: TExitPointOptions;
  ARaising: TRaisingRoutines; out ASet: TExitPointSet): Boolean;
var
  Tokens: TArray<TPascalToken>;
  Body, Node, Header: TSyntaxNode;
  Points: TList<TExitPoint>;
  Point: TExitPoint;
  Graph: TControlFlowGraph;
  Word, Name: string;
  Index: Integer;
  Ends: TArray<TFlowNode>;
  EndNode: TFlowNode;
  Kind: TExitPointKind;
  Wanted: Boolean;
begin
  ASet := Default(TExitPointSet);
  Body := BodyOf(ARoutine);
  Result := Body <> nil;
  if not Result then
    Exit;
  Tokens := ATree.Tokens;
  ASet.RoutineName := ARoutine.Name;
  ASet.IsFunction := IsFunctionRoutine(ARoutine);
  Name := ShortName(ARoutine.Name);
  if ARoutine.Kind = TSyntaxKind.RoutineDecl then
  begin
    Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    if Header <> nil then
      for Index := 0 to High(Tokens) do
      begin
        if Tokens[Index].Offset >= Header.EndOffset then
          Break;
        if (Tokens[Index].Offset >= Header.StartOffset) and (Tokens[Index].Kind = TPascalTokenKind.Identifier) and
          SameText(Tokens[Index].Text, Name) then
        begin
          ASet.RoutineRange := TokenRange(Tokens[Index]);
          ASet.HasRoutine := True;
          Break;
        end;
      end;
  end;
  Points := TList<TExitPoint>.Create;
  Graph := TControlFlowGraph.Build(ARoutine);
  try
    for Node in OwnNodes(Body, [TSyntaxKind.CallStatement, TSyntaxKind.RaiseStatement]) do
    begin
      Index := TokenAtOffset(Tokens, Node.StartOffset);
      if Index < 0 then
        Continue;
      Wanted := False;
      Kind := TExitPointKind.ExitCall;
      Word := '';
      if Node.Kind = TSyntaxKind.RaiseStatement then
      begin
        Kind := TExitPointKind.RaiseStatement;
        Wanted := WordWanted(AOptions, 'raise');
      end
      else
      begin
        Word := StatementWord(Node);
        if SameText(Word, 'Exit') then
          Wanted := WordWanted(AOptions, 'Exit')
        else if SameText(Word, 'Abort') then
        begin
          Kind := TExitPointKind.RaiseStatement;
          Wanted := WordWanted(AOptions, 'Abort');
        end
        else if SameText(Word, 'Halt') or SameText(Word, 'RunError') then
        begin
          Kind := TExitPointKind.Terminate;
          Wanted := WordWanted(AOptions, Word);
        end
        else if ARaising.Contains(Word) or ((Word <> '') and (AOptions.Keywords <> nil) and
          MatchText(Word, AOptions.Keywords)) then
        begin
          // Eigene Wörter aus highlight.exitKeywords (etwa eine Fehlerroutine des Projekts) wie ein Aufruf, der
          // immer auslöst.
          Kind := TExitPointKind.RaisingCall;
          Wanted := True;
        end;
      end;
      if not Wanted then
        Continue;
      Point := MakePoint(Kind, TokenRange(Tokens[Index]), '');
      if Kind = TExitPointKind.RaisingCall then
        Point.Detail := Word;
      // Exit ohne Wert in einer Funktion: Ist das Ergebnis auf einem Weg hierher noch ungesetzt?
      if ASet.IsFunction and (Kind = TExitPointKind.ExitCall) and not ((Node.ChildCount > 0) and
        (Node[0].Kind = TSyntaxKind.Call) and (Node[0].ChildCount > 1)) then
        Point.ResultMissing := MissingAt(Graph, Graph.NodeOf(Node), Name, False);
      Points.Add(Point);
    end;
    // Abschließendes end, wenn ein Weg herausfällt.
    if FallsThrough(Graph, ARaising, Ends) then
    begin
      Index := LastKeyword(Tokens, Body.StartOffset, Body.EndOffset, 'end');
      if Index >= 0 then
      begin
        Point := MakePoint(TExitPointKind.FallThrough, TokenRange(Tokens[Index]), '');
        if ASet.IsFunction then
          for EndNode in Ends do
            Point.ResultMissing := Point.ResultMissing or MissingAt(Graph, EndNode, Name, True);
        Points.Add(Point);
      end;
    end;
    ASet.Points := Sorted(Points.ToArray);
  finally
    Graph.Free;
    Points.Free;
  end;
end;

{ Ergebnis }

function IsResultTarget(AStatement: TSyntaxNode; const AName: string): Boolean;
begin
  Result := (AStatement.Kind = TSyntaxKind.AssignStatement) and (AStatement.ChildCount > 0) and
    (AStatement[0].Kind = TSyntaxKind.Identifier) and
    (SameText(AStatement[0].Name, 'Result') or SameText(AStatement[0].Name, AName));
end;

function ResultAssignments(ARoutine: TSyntaxNode): TArray<TExitPoint>;
var
  Node: TSyntaxNode;
  Name: string;
begin
  Result := nil;
  Name := ShortName(ARoutine.Name);
  for Node in OwnNodes(BodyOf(ARoutine), [TSyntaxKind.AssignStatement]) do
    if IsResultTarget(Node, Name) then
      Result := Result + [MakePoint(TExitPointKind.ResultAssign,
        TTextRange.Create(Node[0].StartPos, Node[0].EndPos), '')];
end;

{ Exceptions }

function HandlerClass(AHandler: TSyntaxNode): string;
var
  TypeNode: TSyntaxNode;
begin
  Result := '';
  TypeNode := AHandler.FindChild(TSyntaxKind.TypeReference);
  if TypeNode <> nil then
    Result := TypeNode.Name;
end;

/// <summary>Klasse eines raise-Ausdrucks: EFoo.Create(…) bzw. EFoo.CreateFmt(…) → EFoo; '' sonst.</summary>
function RaisedClass(ARaise: TSyntaxNode): string;
var
  Node: TSyntaxNode;
begin
  Result := '';
  if ARaise.ChildCount = 0 then
    Exit;
  Node := ARaise[0];
  if (Node.Kind = TSyntaxKind.Call) and (Node.ChildCount > 0) then
    Node := Node[0];
  if (Node.Kind = TSyntaxKind.MemberAccess) and (Node.ChildCount = 1) and
    (Node[0].Kind = TSyntaxKind.Identifier) and StartsText('Create', Node.Name) then
    Result := Node[0].Name;
end;

function ExceptionSources(ATree: TSyntaxTree; ATry: TSyntaxNode; const AClasses: TArray<string>;
  AOffset: Integer; const AExceptions: TExitPointExceptionLookup; const AIsA: TExitPointClassTest): TArray<TExitPoint>;
var
  Part, Node, Callee: TSyntaxNode;
  Index: Integer;
  Raised, Handler, Matched: string;
  Documented: TArray<string>;
  Point: TExitPoint;

  function Matching(const AClass: string): string;
  var
    Candidate: string;
  begin
    Result := '';
    if AClass = '' then
      Exit;
    // Bloßes except ohne Handler: jede Exception passt.
    if AClasses = nil then
      Exit(AClass);
    for Candidate in AClasses do
      if SameText(AClass, Candidate) or (Assigned(AIsA) and AIsA(AClass, Candidate, AOffset)) then
        Exit(AClass);
  end;

begin
  Result := nil;
  for Index := 0 to ATry.ChildCount - 1 do
  begin
    Part := ATry[Index];
    if Part.Kind in [TSyntaxKind.ExceptBlock, TSyntaxKind.FinallyBlock] then
      Continue;
    for Node in OwnNodes(Part, [TSyntaxKind.CallStatement, TSyntaxKind.Call, TSyntaxKind.RaiseStatement]) do
    begin
      if Node.Kind = TSyntaxKind.RaiseStatement then
      begin
        Raised := RaisedClass(Node);
        Matched := Matching(Raised);
        if Matched <> '' then
        begin
          Point := MakePoint(TExitPointKind.ExceptionSource, TTextRange.Create(Node.StartPos, Node.StartPos), Raised);
          // Nur das Wort raise.
          Point.Range.EndPos.Character := Point.Range.StartPos.Character + Length('raise');
          Point.ExceptionClass := Matched;
          Result := Result + [Point];
        end;
        Continue;
      end;
      // Foo(1); steht als CallStatement über einem Call: nur der Call zählt.
      if (Node.Kind = TSyntaxKind.CallStatement) and (Node.ChildCount > 0) and (Node[0].Kind = TSyntaxKind.Call) then
        Continue;
      Callee := CalleeOf(Node);
      if (Callee = nil) or not Assigned(AExceptions) then
        Continue;
      Documented := AExceptions(Callee);
      for Handler in Documented do
      begin
        Matched := Matching(Handler);
        if Matched = '' then
          Continue;
        Point := MakePoint(TExitPointKind.ExceptionSource, CalleeNameRange(ATree.Tokens, Callee), Callee.Name);
        Point.ExceptionClass := Matched;
        Result := Result + [Point];
        Break;
      end;
    end;
  end;
end;

{ Schleifen }

/// <summary>Break und Continue, die ALoop verlassen bzw. fortsetzen (nicht die innerer Schleifen).</summary>
function LoopJumps(ALoop: TSyntaxNode): TArray<TSyntaxNode>;
var
  List: TList<TSyntaxNode>;
  Loop: TSyntaxNode;
begin
  List := TList<TSyntaxNode>.Create;
  try
    Loop := ALoop;
    ALoop.Walk(
      function(ANode: TSyntaxNode): Boolean
      var
        Word: string;
      begin
        if (ANode <> Loop) and (ANode.Kind in RoutineKinds + LoopKinds) then
          Exit(False);
        Result := True;
        if ANode.Kind <> TSyntaxKind.CallStatement then
          Exit;
        Word := StatementWord(ANode);
        if SameText(Word, 'Break') or SameText(Word, 'Continue') then
          List.Add(ANode);
      end);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function LoopPoints(ATree: TSyntaxTree; ALoop: TSyntaxNode): TArray<TExitPoint>;
var
  Tokens: TArray<TPascalToken>;
  Index: Integer;
  Body: TSyntaxNode;
begin
  Result := nil;
  Tokens := ATree.Tokens;
  Index := TokenAtOffset(Tokens, ALoop.StartOffset);
  if Index >= 0 then
    Result := Result + [MakePoint(TExitPointKind.LoopPart, TokenRange(Tokens[Index]), '')];
  if ALoop.Kind = TSyntaxKind.RepeatStatement then
  begin
    Index := LastKeyword(Tokens, ALoop.StartOffset, ALoop.EndOffset, 'until');
    if Index >= 0 then
      Result := Result + [MakePoint(TExitPointKind.LoopPart, TokenRange(Tokens[Index]), '')];
  end
  else if ALoop.ChildCount > 0 then
  begin
    Body := ALoop[ALoop.ChildCount - 1];
    Index := LastKeyword(Tokens, ALoop.StartOffset, Body.StartOffset, 'do');
    if Index >= 0 then
      Result := Result + [MakePoint(TExitPointKind.LoopPart, TokenRange(Tokens[Index]), '')];
    if Body.Kind = TSyntaxKind.Block then
    begin
      Index := LastKeyword(Tokens, Body.StartOffset, Body.EndOffset, 'end');
      if Index >= 0 then
        Result := Result + [MakePoint(TExitPointKind.LoopPart, TokenRange(Tokens[Index]), '')];
    end;
  end;
  // Break und Continue dieser Schleife, nicht die einer inneren.
  for Body in LoopJumps(ALoop) do
  begin
    Index := TokenAtOffset(Tokens, Body.StartOffset);
    if Index >= 0 then
      Result := Result + [MakePoint(TExitPointKind.LoopJump, TokenRange(Tokens[Index]), '')];
  end;
end;

{ TExitPoints }

class function TExitPoints.RoutineExits(ATree: TSyntaxTree; ARoutine: TSyntaxNode;
  const AOptions: TExitPointOptions): TExitPointSet;
var
  Raising: TRaisingRoutines;
begin
  Raising := TRaisingRoutines.Create(ATree);
  try
    if ExitPointsOf(ATree, ARoutine, AOptions, Raising, Result) then
      Result.Query := TExitPointQuery.Routine;
  finally
    Raising.Free;
  end;
end;

class function TExitPoints.Find(ATree: TSyntaxTree; const ALines: TArray<string>; const APosition: TTextPosition;
  const AOptions: TExitPointOptions): TExitPointSet;
begin
  Result := Find(ATree, APosition, AOptions, TreeExceptions(ATree, ALines), TreeClassTest(ATree));
end;

/// <summary>RoutineDecl mit Rumpf, in deren Kopf AOffset liegt; nil sonst.</summary>
function RoutineOfHeader(ARoot: TSyntaxNode; AOffset: Integer): TSyntaxNode;
var
  Routine, Header: TSyntaxNode;
begin
  Result := nil;
  Routine := Innermost(ARoot, AOffset, [TSyntaxKind.RoutineDecl], []);
  if (Routine = nil) or (BodyOf(Routine) = nil) then
    Exit;
  Header := Routine.FindChild(TSyntaxKind.RoutineHeader);
  if (Header <> nil) and (AOffset >= Header.StartOffset) and (AOffset < Header.EndOffset) then
    Result := Routine;
end;

class function TExitPoints.Find(ATree: TSyntaxTree; const APosition: TTextPosition;
  const AOptions: TExitPointOptions; const AExceptions: TExitPointExceptionLookup;
  const AIsA: TExitPointClassTest): TExitPointSet;
var
  Tokens: TArray<TPascalToken>;
  Index: Integer;
  Token: TPascalToken;
  Routine, Loop, Statement, Handler, TryNode, ExceptPart, Child: TSyntaxNode;
  Raising: TRaisingRoutines;
  Classes: TArray<string>;
  Points: TArray<TExitPoint>;
  Word: string;
  Qualified: Boolean;
begin
  Result := Default(TExitPointSet);
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  Tokens := ATree.Tokens;
  Index := WordAt(Tokens, APosition);
  if Index < 0 then
    Exit;
  Token := Tokens[Index];
  // Foo.Exit, Obj.Break, Obj.Result: kein Austritt (der Kopf TFoo.Run zählt).
  Qualified := (Index > 0) and Tokens[Index - 1].IsSymbol('.');
  Word := Token.Text;
  Routine := Innermost(ATree.Root, Token.Offset, RoutineKinds, []);
  Raising := TRaisingRoutines.Create(ATree);
  try
    // Break und Continue: die Schleife.
    if (Token.Kind = TPascalTokenKind.Identifier) and MatchText(Word, ['Break', 'Continue']) and not Qualified then
    begin
      Loop := Innermost(ATree.Root, Token.Offset, LoopKinds, RoutineKinds);
      if (Loop = nil) or not AOptions.Loops then
        Exit;
      Result.Query := TExitPointQuery.Loop;
      Result.Points := Sorted(LoopPoints(ATree, Loop));
      Exit;
    end;
    // except, on und die Klasse eines Handlers: die auslösenden Stellen im try-Teil.
    if Token.IsKeyword('except') or ((Token.Kind = TPascalTokenKind.Identifier) and
      (Innermost(ATree.Root, Token.Offset, [TSyntaxKind.ExceptionHandler], RoutineKinds) <> nil)) then
    begin
      Handler := Innermost(ATree.Root, Token.Offset, [TSyntaxKind.ExceptionHandler], RoutineKinds);
      if Token.IsKeyword('except') then
      begin
        Handler := nil;
        ExceptPart := Innermost(ATree.Root, Token.Offset, [TSyntaxKind.ExceptBlock], RoutineKinds);
      end
      else
      begin
        // Nur "on" und die Klasse, nicht der Rumpf des Handlers oder der Name der Variablen.
        Child := Handler.FindChild(TSyntaxKind.TypeReference);
        if not (SameText(Word, 'on') and (Token.Offset = Handler.StartOffset)) and
          not ((Child <> nil) and (Token.Offset >= Child.StartOffset) and (Token.Offset < Child.EndOffset)) then
          Handler := nil;
        ExceptPart := nil;
        if Handler <> nil then
          ExceptPart := Handler.Parent;
      end;
      if (ExceptPart <> nil) and (ExceptPart.Kind = TSyntaxKind.ExceptBlock) and
        ((Handler <> nil) or Token.IsKeyword('except')) then
      begin
        if not AOptions.Exceptions then
          Exit;
        TryNode := ExceptPart.Parent;
        Classes := nil;
        if Handler <> nil then
          Classes := [HandlerClass(Handler)]
        else
          for Index := 0 to ExceptPart.ChildCount - 1 do
            if ExceptPart[Index].Kind = TSyntaxKind.ExceptionHandler then
              Classes := Classes + [HandlerClass(ExceptPart[Index])];
        Points := ExceptionSources(ATree, TryNode, Classes, Token.Offset, AExceptions, AIsA);
        Points := Points + [MakePoint(TExitPointKind.Handler, TokenRange(Token), '')];
        Result.Query := TExitPointQuery.Exceptions;
        Result.Points := Sorted(Points);
        Exit;
      end;
    end;
    // Name der Routine im Kopf ihrer Implementierung.
    if Token.Kind = TPascalTokenKind.Identifier then
    begin
      Statement := RoutineOfHeader(ATree.Root, Token.Offset);
      if (Statement <> nil) and SameText(Word, ShortName(Statement.Name)) then
      begin
        if ExitPointsOf(ATree, Statement, AOptions, Raising, Result) then
          Result.Query := TExitPointQuery.Routine;
        Exit;
      end;
    end;
    if Qualified or (Routine = nil) or (BodyOf(Routine) = nil) or (Token.Offset < BodyOf(Routine).StartOffset) then
      Exit;
    // Result bzw. der Funktionsname als Ziel einer Zuweisung: Austritte und Zuweisungen.
    if IsFunctionRoutine(Routine) and (Token.Kind = TPascalTokenKind.Identifier) then
    begin
      Statement := Innermost(ATree.Root, Token.Offset, [TSyntaxKind.AssignStatement], RoutineKinds);
      if SameText(Word, 'Result') or ((Statement <> nil) and (Statement.ChildCount > 0) and
        (Statement[0].StartOffset = Token.Offset) and IsResultTarget(Statement, ShortName(Routine.Name))) then
      begin
        if ExitPointsOf(ATree, Routine, AOptions, Raising, Result) then
        begin
          Result.Query := TExitPointQuery.ResultValue;
          Result.Points := Sorted(Result.Points + ResultAssignments(Routine));
        end;
        Exit;
      end;
    end;
    // Exit, raise, Abort, Halt, RunError und Aufrufe, die immer auslösen.
    Statement := Innermost(ATree.Root, Token.Offset, [TSyntaxKind.CallStatement, TSyntaxKind.RaiseStatement],
      RoutineKinds);
    if (Statement = nil) or (Statement.StartOffset <> Token.Offset) then
      Exit;
    if not ((Statement.Kind = TSyntaxKind.RaiseStatement) or MatchText(StatementWord(Statement),
      ['Exit', 'Abort', 'Halt', 'RunError']) or Raising.Contains(StatementWord(Statement)) or
      ((AOptions.Keywords <> nil) and (StatementWord(Statement) <> '') and
      MatchText(StatementWord(Statement), AOptions.Keywords))) then
      Exit;
    if ExitPointsOf(ATree, Routine, AOptions, Raising, Result) then
      Result.Query := TExitPointQuery.Routine;
  finally
    Raising.Free;
  end;
end;

type
  TRoutineExceptions = record
    Name: string;
    Classes: TArray<string>;
  end;

class function TExitPoints.TreeExceptions(ATree: TSyntaxTree; const ALines: TArray<string>):
  TExitPointExceptionLookup;
var
  Docs: TArray<TRoutineExceptions>;
  Lines: TArray<string>;
begin
  Docs := nil;
  Lines := ALines;
  // Deklarationen in Klassen und Rümpfe: der ///-Kommentar darüber. Einmal je Lookup gelesen.
  if (ATree <> nil) and (ATree.Root <> nil) then
    ATree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      var
        Doc: TXmlDoc;
        Entry: TXmlDocEntry;
        Item: TRoutineExceptions;
        Comment: string;
      begin
        Result := ANode.Kind <> TSyntaxKind.AnonymousMethod;
        if not (ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.RoutineHeader]) or
          ((ANode.Kind = TSyntaxKind.RoutineHeader) and (ANode.Parent <> nil) and
          (ANode.Parent.Kind = TSyntaxKind.RoutineDecl)) then
          Exit;
        Comment := TXmlDoc.CommentAbove(Lines, ANode.StartPos.Line);
        if Comment = '' then
          Exit;
        Doc := TXmlDoc.Parse(Comment);
        if Length(Doc.Exceptions) = 0 then
          Exit;
        Item.Name := ShortName(ANode.Name);
        Item.Classes := nil;
        for Entry in Doc.Exceptions do
          Item.Classes := Item.Classes + [TXmlDoc.NormalizeCref(Entry.Name)];
        Docs := Docs + [Item];
      end);
  Result :=
    function(ACallee: TSyntaxNode): TArray<string>
    var
      Name: string;
      Item: TRoutineExceptions;
    begin
      Result := nil;
      Name := PlainCallee(ACallee);
      if (Name = '') and (ACallee <> nil) and (ACallee.Kind = TSyntaxKind.MemberAccess) then
        Name := ACallee.Name;
      if Name = '' then
        Exit;
      for Item in Docs do
        if SameText(Item.Name, Name) then
          Result := Result + Item.Classes;
    end;
end;

class function TExitPoints.TreeClassTest(ATree: TSyntaxTree): TExitPointClassTest;
var
  Tree: TSyntaxTree;
begin
  Tree := ATree;
  Result :=
    function(const AClass, AHandler: string; AOffset: Integer): Boolean
    var
      Current, Ancestor: string;
      Depth: Integer;
      Found: Boolean;
    begin
      // Jede Exception-Klasse stammt von Exception ab (Konvention der RTL).
      if SameText(AHandler, 'Exception') or SameText(AHandler, 'System.SysUtils.Exception') or
        SameText(AClass, AHandler) then
        Exit(True);
      Result := False;
      if Tree = nil then
        Exit;
      Current := AClass;
      for Depth := 1 to 32 do
      begin
        Ancestor := '';
        Found := False;
        Tree.Root.Walk(
          function(ANode: TSyntaxNode): Boolean
          var
            ClassNode, First: TSyntaxNode;
          begin
            Result := not Found;
            if Found or (ANode.Kind <> TSyntaxKind.TypeDecl) or not SameText(ANode.Name, Current) then
              Exit;
            ClassNode := ANode.FindChild(TSyntaxKind.ClassType);
            if ClassNode = nil then
              Exit;
            Found := True;
            First := ClassNode.FindChild(TSyntaxKind.TypeReference);
            if First <> nil then
              Ancestor := First.Name;
          end);
        if Ancestor = '' then
          Exit;
        if SameText(Ancestor, AHandler) then
          Exit(True);
        Current := Ancestor;
      end;
    end;
end;

end.
