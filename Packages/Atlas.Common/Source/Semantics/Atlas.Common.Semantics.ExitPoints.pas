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
    cRaisingRoutines: array[0..3] of string = ('RaiseLastOSError', 'RaiseLastWin32Error', 'OutOfMemoryError',
      'Abort');
  public
    /// <summary>Stellen zur Abfrage an APosition; Query None, wenn dort nichts Passendes steht.</summary>
    class function Find(ATree: TSyntaxTree; const APosition: TTextPosition;
      const AOptions: TExitPointOptions; const AExceptions: TExitPointExceptionLookup;
      const AIsA: TExitPointClassTest): TExitPointSet; overload; static;
    /// <summary>Wie oben mit Doku und Klassen nur aus dem Baum (ALines sind seine Zeilen).</summary>
    class function Find(ATree: TSyntaxTree; const ALines: TArray<string>; const APosition: TTextPosition;
      const AOptions: TExitPointOptions): TExitPointSet; overload; static;
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
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Pascal.XmlDoc,
  Atlas.Common.Semantics.ControlFlow;

type
  TSyntaxKindSet = set of TSyntaxKind;

const
  cRoutineKinds = [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod];
  cLoopKinds = [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
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
  mPoint: TExitPoint;
begin
  Result := 0;
  for mPoint in Points do
  begin
    if mPoint.IsExit then
    begin
      Inc(Result);
    end;
  end;
end;

function TExitPointSet.ResultMissing: Boolean;
var
  mPoint: TExitPoint;
begin
  Result := False;
  for mPoint in Points do
  begin
    if mPoint.ResultMissing then
    begin
      Exit(True);
    end;
  end;
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

/// <summary>Bezeichner oder Schlüsselwort, auf dem APosition steht (auch direkt dahinter); -1 ohne.</summary>
function WordAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
var
  mIndex: Integer;
  mToken: TPascalToken;
begin
  for mIndex := 0 to High(ATokens) do
  begin
    mToken := ATokens[mIndex];
    if (mToken.StartPos.Line > APosition.Line) or
      ((mToken.StartPos.Line = APosition.Line) and (mToken.StartPos.Character > APosition.Character)) then
    begin
      Break;
    end;
    if (mToken.EndPos.Line = APosition.Line) and (APosition.Character <= mToken.EndPos.Character) and
      (mToken.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Letztes Schlüsselwort AWord in [AStartOffset, AEndOffset); -1 ohne.</summary>
function LastKeyword(const ATokens: TArray<TPascalToken>; AStartOffset, AEndOffset: Integer;
  const AWord: string): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(ATokens) do
  begin
    if ATokens[mIndex].Offset >= AEndOffset then
    begin
      Break;
    end;
    if (ATokens[mIndex].Offset >= AStartOffset) and ATokens[mIndex].IsKeyword(AWord) then
    begin
      Result := mIndex;
    end;
  end;
end;

/// <summary>Innerster Knoten einer der Arten AKinds, der AOffset enthält; ABoundaries beenden die Suche nach
/// außen (ein Break in einer anonymen Methode gehört nicht zur Schleife außen).</summary>
function Innermost(ARoot: TSyntaxNode; AOffset: Integer; const AKinds, ABoundaries: TSyntaxKindSet): TSyntaxNode;
var
  mNode, mChild: TSyntaxNode;
  mIndex: Integer;
begin
  // Von der Wurzel abwärts dem Kind folgen, das AOffset enthält; der letzte Treffer ist der innerste.
  Result := nil;
  mNode := ARoot;
  while mNode <> nil do
  begin
    mChild := nil;
    for mIndex := 0 to mNode.ChildCount - 1 do
    begin
      if (AOffset >= mNode[mIndex].StartOffset) and (AOffset < mNode[mIndex].EndOffset) then
      begin
        mChild := mNode[mIndex];
        Break;
      end;
    end;
    if mChild = nil then
    begin
      Break;
    end;
    if mChild.Kind in AKinds then
    begin
      Result := mChild;
    end
    else if mChild.Kind in ABoundaries then
    begin
      Result := nil;
    end;
    mNode := mChild;
  end;
end;

function BodyOf(ARoutine: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if ARoutine <> nil then
  begin
    Result := ARoutine.FindChild(TSyntaxKind.Block);
  end;
end;

/// <summary>Knoten unter ARoot ohne verschachtelte Routinen und anonyme Methoden, in Baumreihenfolge.</summary>
function OwnNodes(ARoot: TSyntaxNode; const AKinds: TSyntaxKindSet): TArray<TSyntaxNode>;
var
  mList: TList<TSyntaxNode>;
  mKinds: TSyntaxKindSet;
  mRoot: TSyntaxNode;
begin
  mList := TList<TSyntaxNode>.Create;
  try
    mKinds := AKinds;
    mRoot := ARoot;
    ARoot.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        if (ANode <> mRoot) and (ANode.Kind in cRoutineKinds) then
        begin
          Exit(False);
        end;
        if ANode.Kind in mKinds then
        begin
          mList.Add(ANode);
        end;
        Result := True;
      end);
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

function IsFunctionRoutine(ARoutine: TSyntaxNode): Boolean;
var
  mHeader: TSyntaxNode;
begin
  Result := False;
  if ARoutine = nil then
  begin
    Exit;
  end;
  if ARoutine.Kind = TSyntaxKind.AnonymousMethod then
  begin
    mHeader := ARoutine;
  end
  else
  begin
    mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  end;
  Result := (mHeader <> nil) and (mHeader.FindChild(TSyntaxKind.TypeReference) <> nil);
end;

class function TExitPoints.PlainCallee(ACallee: TSyntaxNode): string;
begin
  Result := '';
  if ACallee = nil then
  begin
    Exit;
  end;
  if ACallee.Kind = TSyntaxKind.Identifier then
  begin
    Result := ACallee.Name;
  end
  else if (ACallee.Kind = TSyntaxKind.MemberAccess) and (ACallee.ChildCount = 1) and
    (ACallee[0].Kind = TSyntaxKind.Identifier) and SameText(ACallee[0].Name, 'Self') then
  begin
    Result := ACallee.Name;
  end;
end;

/// <summary>Ziel eines Aufrufs: bei CallStatement der Ausdruck (bzw. dessen Ziel, wenn es ein Aufruf mit
/// Klammern ist), bei Call das erste Kind.</summary>
function CalleeOf(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if ANode.ChildCount = 0 then
  begin
    Exit;
  end;
  Result := ANode[0];
  if (ANode.Kind = TSyntaxKind.CallStatement) and (Result.Kind = TSyntaxKind.Call) and (Result.ChildCount > 0) then
  begin
    Result := Result[0];
  end;
end;

/// <summary>Name einer Anweisung wie Exit, Break, Abort: nur ohne Objekt davor (TMonitor.Exit(FLock) zählt
/// nicht, #647).</summary>
function StatementWord(AStatement: TSyntaxNode): string;
begin
  Result := '';
  if AStatement.Kind <> TSyntaxKind.CallStatement then
  begin
    Exit;
  end;
  if AStatement.ChildCount = 0 then
  begin
    Result := AStatement.Name;
  end
  else
  begin
    Result := TExitPoints.PlainCallee(CalleeOf(AStatement));
  end;
  if (Result <> '') and (Pos('.', Result) > 0) then
  begin
    Result := '';
  end;
end;

/// <summary>Bereich des Namens am Ende des Aufrufziels (Foo bzw. Bar in Obj.Bar).</summary>
function CalleeNameRange(const ATokens: TArray<TPascalToken>; ACallee: TSyntaxNode): TTextRange;
var
  mIndex: Integer;
begin
  Result := TTextRange.Create(ACallee.StartPos, ACallee.EndPos);
  for mIndex := High(ATokens) downto 0 do
  begin
    if ATokens[mIndex].Offset < ACallee.EndOffset then
    begin
      if ATokens[mIndex].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword] then
      begin
        Result := TokenRange(ATokens[mIndex]);
      end;
      Break;
    end;
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
  begin
    Result := A.Range.StartPos.Character - B.Range.StartPos.Character;
  end;
  if Result = 0 then
  begin
    Result := Ord(A.Kind) - Ord(B.Kind);
  end;
end;

/// <summary>Nach Position, je Stelle nur der erste Eintrag (TArray.Sort ist nicht stabil: Art als dritter
/// Schlüssel).</summary>
function Sorted(const APoints: TArray<TExitPoint>): TArray<TExitPoint>;
var
  mItems: TArray<TExitPoint>;
  mPoint: TExitPoint;
  mCount: Integer;
begin
  mItems := Copy(APoints);
  TArray.Sort<TExitPoint>(mItems, TComparer<TExitPoint>.Construct(ComparePoints));
  Result := nil;
  SetLength(Result, Length(mItems));
  mCount := 0;
  for mPoint in mItems do
  begin
    if (mCount > 0) and (Result[mCount - 1].Range.StartPos = mPoint.Range.StartPos) then
    begin
      Continue;
    end;
    Result[mCount] := mPoint;
    Inc(mCount);
  end;
  SetLength(Result, mCount);
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
  mRoutines: TList<TSyntaxNode>;
  mRoutine, mBody: TSyntaxNode;
  mGraph: TControlFlowGraph;
  mName: string;
begin
  inherited Create;
  FNames := TDictionary<string, Boolean>.Create;
  for mName in TExitPoints.cRaisingRoutines do
  begin
    FNames.AddOrSetValue(UpperCase(mName), True);
  end;
  if ATree = nil then
  begin
    Exit;
  end;
  mRoutines := TList<TSyntaxNode>.Create;
  try
    ATree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        if (ANode.Kind = TSyntaxKind.RoutineDecl) and (ANode.FindChild(TSyntaxKind.Block) <> nil) then
        begin
          mRoutines.Add(ANode);
        end;
        // Anonyme Methoden haben keinen Namen; was in ihnen steht, zählt nicht.
        Result := ANode.Kind <> TSyntaxKind.AnonymousMethod;
      end);
    for mRoutine in mRoutines do
    begin
      mBody := BodyOf(mRoutine);
      // Vorfilter: Ohne raise und Abort im eigenen Rumpf kann die Routine nicht immer auslösen.
      if Length(OwnNodes(mBody, [TSyntaxKind.RaiseStatement])) = 0 then
      begin
        Continue;
      end;
      mGraph := TControlFlowGraph.Build(mRoutine);
      try
        if mGraph.Complete and (mGraph.IsReachable(mGraph.ExitNode) = TFlowAnswer.No) and
          (mGraph.IsReachable(mGraph.RaiseExit) = TFlowAnswer.Yes) then
        begin
          FNames.AddOrSetValue(UpperCase(ShortName(mRoutine.Name)), True);
        end;
      finally
        mGraph.Free;
      end;
    end;
  finally
    mRoutines.Free;
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
  mSeen: TArray<Boolean>;
  mStack: TStack<TFlowNode>;
  mNode, mNext: TFlowNode;
  mEnds: TDictionary<TFlowNode, Boolean>;
begin
  AEnds := nil;
  if not AGraph.Complete then
  begin
    Exit(True);
  end;
  mEnds := TDictionary<TFlowNode, Boolean>.Create;
  mStack := TStack<TFlowNode>.Create;
  try
    for mNode in AGraph.FallThrough do
    begin
      mEnds.AddOrSetValue(mNode, True);
    end;
    SetLength(mSeen, AGraph.Nodes.Count);
    mStack.Push(AGraph.Entry);
    mSeen[AGraph.Entry.Index] := True;
    while mStack.Count > 0 do
    begin
      mNode := mStack.Pop;
      // RunError beendet das Programm wie Halt (das ControlFlow schon ans Ende führt).
      if (mNode.Syntax <> nil) and (mNode.Syntax.Kind = TSyntaxKind.CallStatement) and
        (ARaising.Contains(StatementWord(mNode.Syntax)) or SameText(StatementWord(mNode.Syntax), 'RunError')) then
      begin
        Continue;
      end;
      if mEnds.ContainsKey(mNode) then
      begin
        AEnds := AEnds + [mNode];
      end;
      for mNext in mNode.Successors do
      begin
        if not mSeen[mNext.Index] then
        begin
          mSeen[mNext.Index] := True;
          mStack.Push(mNext);
        end;
      end;
    end;
  finally
    mStack.Free;
    mEnds.Free;
  end;
  Result := Length(AEnds) > 0;
end;

/// <summary>Kann das Ergebnis vor ANode (bzw. mit AAfter nach ANode) noch ungesetzt sein? Nur sichere Wege:
/// Eine unsichere Änderung (var-Argument, Result.Feld …) gilt als gesetzt.</summary>
function MissingAt(AGraph: TControlFlowGraph; ANode: TFlowNode; const AName: string; AAfter: Boolean): Boolean;

  function Missing(const AVariable: string): Boolean;
  var
    mReaching: TReachingDefinitions;
  begin
    if AAfter and (SameText(ANode.Defines, AVariable) or ANode.TouchesName(AVariable)) then
    begin
      Exit(False);
    end;
    mReaching := AGraph.ReachingDefinitions(ANode, AVariable);
    Result := mReaching.FromEntry;
  end;

begin
  Result := (ANode <> nil) and AGraph.Complete and Missing('Result') and Missing(AName);
end;

type
  /// <summary>Gemeinsame Werte beim Sammeln der Austritte einer Routine.</summary>
  TExitScan = record
    Tokens: TArray<TPascalToken>;
    Graph: TControlFlowGraph;
    Options: TExitPointOptions;
    Raising: TRaisingRoutines;
    /// <summary>Kurzname der Routine (Zuweisung an den Funktionsnamen).</summary>
    Name: string;
    IsFunction: Boolean;
  end;

/// <summary>Bereich des Namens AName im Kopf der Implementierung ARoutine; False ohne.</summary>
function RoutineNameRange(const ATokens: TArray<TPascalToken>; ARoutine: TSyntaxNode; const AName: string;
  out ARange: TTextRange): Boolean;
var
  mHeader: TSyntaxNode;
  mIndex: Integer;
begin
  ARange := Default(TTextRange);
  mHeader := nil;
  if ARoutine.Kind = TSyntaxKind.RoutineDecl then
  begin
    mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  end;
  if mHeader = nil then
  begin
    Exit(False);
  end;
  mIndex := 0;
  while (mIndex <= High(ATokens)) and (ATokens[mIndex].Offset < mHeader.EndOffset) do
  begin
    if (ATokens[mIndex].Offset >= mHeader.StartOffset) and (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) and
      SameText(ATokens[mIndex].Text, AName) then
    begin
      ARange := TokenRange(ATokens[mIndex]);
      Exit(True);
    end;
    Inc(mIndex);
  end;
  Result := False;
end;

/// <summary>Art eines Aufrufs mit dem Wort AWord (Exit, Abort, Halt, RunError, auslösende Routine); False, wenn
/// der Aufruf nicht als Austritt gezeigt wird.</summary>
function CallKind(const AScan: TExitScan; const AWord: string; out AKind: TExitPointKind): Boolean;
begin
  AKind := TExitPointKind.ExitCall;
  Result := False;
  if SameText(AWord, 'Exit') then
  begin
    Result := WordWanted(AScan.Options, 'Exit');
  end
  else if SameText(AWord, 'Abort') then
  begin
    AKind := TExitPointKind.RaiseStatement;
    Result := WordWanted(AScan.Options, 'Abort');
  end
  else if SameText(AWord, 'Halt') or SameText(AWord, 'RunError') then
  begin
    AKind := TExitPointKind.Terminate;
    Result := WordWanted(AScan.Options, AWord);
  end
  else if AScan.Raising.Contains(AWord) or ((AWord <> '') and (AScan.Options.Keywords <> nil) and
    MatchText(AWord, AScan.Options.Keywords)) then
  begin
    // Eigene Wörter aus highlight.exitKeywords (etwa eine Fehlerroutine des Projekts) wie ein Aufruf, der
    // immer auslöst.
    AKind := TExitPointKind.RaisingCall;
    Result := True;
  end;
end;

/// <summary>Exit(Wert) gibt das Ergebnis mit.</summary>
function ExitWithValue(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.ChildCount > 0) and (ANode[0].Kind = TSyntaxKind.Call) and (ANode[0].ChildCount > 1);
end;

/// <summary>Austritt an der Anweisung ANode (Aufruf oder raise); False, wenn sie keiner ist.</summary>
function StatementPoint(const AScan: TExitScan; ANode: TSyntaxNode; out APoint: TExitPoint): Boolean;
var
  mIndex: Integer;
  mKind: TExitPointKind;
  mWord: string;
begin
  APoint := Default(TExitPoint);
  mIndex := TokenExactly(AScan.Tokens, ANode.StartOffset);
  mWord := '';
  if mIndex < 0 then
  begin
    Exit(False);
  end;
  if ANode.Kind = TSyntaxKind.RaiseStatement then
  begin
    mKind := TExitPointKind.RaiseStatement;
    Result := WordWanted(AScan.Options, 'raise');
  end
  else
  begin
    mWord := StatementWord(ANode);
    Result := CallKind(AScan, mWord, mKind);
  end;
  if not Result then
  begin
    Exit;
  end;
  APoint := MakePoint(mKind, TokenRange(AScan.Tokens[mIndex]), '');
  if mKind = TExitPointKind.RaisingCall then
  begin
    APoint.Detail := mWord;
  end;
  // Exit ohne Wert in einer Funktion: Ist das Ergebnis auf einem Weg hierher noch ungesetzt?
  if AScan.IsFunction and (mKind = TExitPointKind.ExitCall) and not ExitWithValue(ANode) then
  begin
    APoint.ResultMissing := MissingAt(AScan.Graph, AScan.Graph.NodeOf(ANode), AScan.Name, False);
  end;
end;

/// <summary>Abschließendes end von ABody, wenn ein Weg herausfällt.</summary>
function FallThroughPoint(const AScan: TExitScan; ABody: TSyntaxNode; out APoint: TExitPoint): Boolean;
var
  mEnds: TArray<TFlowNode>;
  mEnd: TFlowNode;
  mIndex: Integer;
begin
  APoint := Default(TExitPoint);
  mIndex := -1;
  if FallsThrough(AScan.Graph, AScan.Raising, mEnds) then
  begin
    mIndex := LastKeyword(AScan.Tokens, ABody.StartOffset, ABody.EndOffset, 'end');
  end;
  Result := mIndex >= 0;
  if not Result then
  begin
    Exit;
  end;
  APoint := MakePoint(TExitPointKind.FallThrough, TokenRange(AScan.Tokens[mIndex]), '');
  if AScan.IsFunction then
  begin
    for mEnd in mEnds do
    begin
      APoint.ResultMissing := APoint.ResultMissing or MissingAt(AScan.Graph, mEnd, AScan.Name, True);
    end;
  end;
end;

/// <summary>Austritte im Rumpf ABody.</summary>
function ScanPoints(const AScan: TExitScan; ABody: TSyntaxNode): TArray<TExitPoint>;
var
  mNode: TSyntaxNode;
  mPoint: TExitPoint;
begin
  Result := nil;
  for mNode in OwnNodes(ABody, [TSyntaxKind.CallStatement, TSyntaxKind.RaiseStatement]) do
  begin
    if StatementPoint(AScan, mNode, mPoint) then
    begin
      Result := Result + [mPoint];
    end;
  end;
  if FallThroughPoint(AScan, ABody, mPoint) then
  begin
    Result := Result + [mPoint];
  end;
end;

function ExitPointsOf(ATree: TSyntaxTree; ARoutine: TSyntaxNode; const AOptions: TExitPointOptions;
  ARaising: TRaisingRoutines; out ASet: TExitPointSet): Boolean;
var
  mBody: TSyntaxNode;
  mScan: TExitScan;
begin
  ASet := Default(TExitPointSet);
  mBody := BodyOf(ARoutine);
  Result := mBody <> nil;
  if not Result then
  begin
    Exit;
  end;
  mScan := Default(TExitScan);
  mScan.Tokens := ATree.Tokens;
  mScan.Options := AOptions;
  mScan.Raising := ARaising;
  mScan.Name := ShortName(ARoutine.Name);
  mScan.IsFunction := IsFunctionRoutine(ARoutine);
  ASet.RoutineName := ARoutine.Name;
  ASet.IsFunction := mScan.IsFunction;
  ASet.HasRoutine := RoutineNameRange(mScan.Tokens, ARoutine, mScan.Name, ASet.RoutineRange);
  mScan.Graph := TControlFlowGraph.Build(ARoutine);
  try
    ASet.Points := Sorted(ScanPoints(mScan, mBody));
  finally
    mScan.Graph.Free;
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
  mNode: TSyntaxNode;
  mName: string;
begin
  Result := nil;
  mName := ShortName(ARoutine.Name);
  for mNode in OwnNodes(BodyOf(ARoutine), [TSyntaxKind.AssignStatement]) do
  begin
    if IsResultTarget(mNode, mName) then
    begin
      Result := Result + [MakePoint(TExitPointKind.ResultAssign,
        TTextRange.Create(mNode[0].StartPos, mNode[0].EndPos), '')];
    end;
  end;
end;

{ Exceptions }

function HandlerClass(AHandler: TSyntaxNode): string;
var
  mTypeNode: TSyntaxNode;
begin
  Result := '';
  mTypeNode := AHandler.FindChild(TSyntaxKind.TypeReference);
  if mTypeNode <> nil then
  begin
    Result := mTypeNode.Name;
  end;
end;

/// <summary>Klasse eines raise-Ausdrucks: EFoo.Create(…) bzw. EFoo.CreateFmt(…) → EFoo; '' sonst.</summary>
function RaisedClass(ARaise: TSyntaxNode): string;
var
  mNode: TSyntaxNode;
begin
  Result := '';
  if ARaise.ChildCount = 0 then
  begin
    Exit;
  end;
  mNode := ARaise[0];
  if (mNode.Kind = TSyntaxKind.Call) and (mNode.ChildCount > 0) then
  begin
    mNode := mNode[0];
  end;
  if (mNode.Kind = TSyntaxKind.MemberAccess) and (mNode.ChildCount = 1) and
    (mNode[0].Kind = TSyntaxKind.Identifier) and StartsText('Create', mNode.Name) then
  begin
    Result := mNode[0].Name;
  end;
end;

type
  /// <summary>Gemeinsame Werte bei der Suche nach den auslösenden Stellen eines try-Teils.</summary>
  TExceptionScan = record
    Tokens: TArray<TPascalToken>;
    /// <summary>Klassen der Handler; nil = bloßes except ohne Handler.</summary>
    Classes: TArray<string>;
    Offset: Integer;
    Exceptions: TExitPointExceptionLookup;
    IsA: TExitPointClassTest;
  end;

/// <summary>AClass, wenn ein Handler sie fängt; sonst ''.</summary>
function MatchingClass(const AScan: TExceptionScan; const AClass: string): string;
var
  mCandidate: string;
begin
  Result := '';
  // Bloßes except ohne Handler: jede Exception passt.
  if (AClass = '') or (AScan.Classes = nil) then
  begin
    Exit(AClass);
  end;
  for mCandidate in AScan.Classes do
  begin
    if SameText(AClass, mCandidate) or (Assigned(AScan.IsA) and AScan.IsA(AClass, mCandidate, AScan.Offset)) then
    begin
      Exit(AClass);
    end;
  end;
end;

/// <summary>raise ANode mit einer gefangenen Klasse; markiert wird nur das Wort raise.</summary>
function RaisePoint(const AScan: TExceptionScan; ANode: TSyntaxNode; out APoint: TExitPoint): Boolean;
var
  mRaised, mMatched: string;
begin
  APoint := Default(TExitPoint);
  mRaised := RaisedClass(ANode);
  mMatched := MatchingClass(AScan, mRaised);
  Result := mMatched <> '';
  if Result then
  begin
    APoint := MakePoint(TExitPointKind.ExceptionSource, TTextRange.Create(ANode.StartPos, ANode.StartPos), mRaised);
    APoint.Range.EndPos.Character := APoint.Range.StartPos.Character + Length('raise');
    APoint.ExceptionClass := mMatched;
  end;
end;

/// <summary>Aufruf ANode, der laut XMLDoc eine gefangene Klasse auslösen kann.</summary>
function CallPoint(const AScan: TExceptionScan; ANode: TSyntaxNode; out APoint: TExitPoint): Boolean;
var
  mCallee: TSyntaxNode;
  mClass, mMatched: string;
begin
  APoint := Default(TExitPoint);
  // Foo(1); steht als CallStatement über einem Call: nur der Call zählt.
  mCallee := nil;
  if not ((ANode.Kind = TSyntaxKind.CallStatement) and (ANode.ChildCount > 0) and
    (ANode[0].Kind = TSyntaxKind.Call)) and Assigned(AScan.Exceptions) then
  begin
    mCallee := CalleeOf(ANode);
  end;
  if mCallee = nil then
  begin
    Exit(False);
  end;
  for mClass in AScan.Exceptions(mCallee) do
  begin
    mMatched := MatchingClass(AScan, mClass);
    if mMatched <> '' then
    begin
      APoint := MakePoint(TExitPointKind.ExceptionSource, CalleeNameRange(AScan.Tokens, mCallee), mCallee.Name);
      APoint.ExceptionClass := mMatched;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Auslösende Stellen im Teil APart eines try.</summary>
function PartSources(const AScan: TExceptionScan; APart: TSyntaxNode): TArray<TExitPoint>;
var
  mNode: TSyntaxNode;
  mPoint: TExitPoint;
  mFound: Boolean;
begin
  Result := nil;
  for mNode in OwnNodes(APart, [TSyntaxKind.CallStatement, TSyntaxKind.Call, TSyntaxKind.RaiseStatement]) do
  begin
    if mNode.Kind = TSyntaxKind.RaiseStatement then
    begin
      mFound := RaisePoint(AScan, mNode, mPoint);
    end
    else
    begin
      mFound := CallPoint(AScan, mNode, mPoint);
    end;
    if mFound then
    begin
      Result := Result + [mPoint];
    end;
  end;
end;

function ExceptionSources(ATree: TSyntaxTree; ATry: TSyntaxNode; const AClasses: TArray<string>;
  AOffset: Integer; const AExceptions: TExitPointExceptionLookup; const AIsA: TExitPointClassTest): TArray<TExitPoint>;
var
  mScan: TExceptionScan;
  mIndex: Integer;
begin
  Result := nil;
  mScan := Default(TExceptionScan);
  mScan.Tokens := ATree.Tokens;
  mScan.Classes := AClasses;
  mScan.Offset := AOffset;
  mScan.Exceptions := AExceptions;
  mScan.IsA := AIsA;
  for mIndex := 0 to ATry.ChildCount - 1 do
  begin
    if not (ATry[mIndex].Kind in [TSyntaxKind.ExceptBlock, TSyntaxKind.FinallyBlock]) then
    begin
      Result := Result + PartSources(mScan, ATry[mIndex]);
    end;
  end;
end;

{ Schleifen }

/// <summary>Break und Continue, die ALoop verlassen bzw. fortsetzen (nicht die innerer Schleifen).</summary>
function LoopJumps(ALoop: TSyntaxNode): TArray<TSyntaxNode>;
var
  mList: TList<TSyntaxNode>;
  mLoop: TSyntaxNode;
begin
  mList := TList<TSyntaxNode>.Create;
  try
    mLoop := ALoop;
    ALoop.Walk(
      function(ANode: TSyntaxNode): Boolean
      var
        Word: string;
      begin
        if (ANode <> mLoop) and (ANode.Kind in cRoutineKinds + cLoopKinds) then
        begin
          Exit(False);
        end;
        Result := True;
        if ANode.Kind <> TSyntaxKind.CallStatement then
        begin
          Exit;
        end;
        Word := StatementWord(ANode);
        if SameText(Word, 'Break') or SameText(Word, 'Continue') then
        begin
          mList.Add(ANode);
        end;
      end);
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

function LoopPoints(ATree: TSyntaxTree; ALoop: TSyntaxNode): TArray<TExitPoint>;
var
  mTokens: TArray<TPascalToken>;
  mIndex: Integer;
  mBody: TSyntaxNode;
begin
  Result := nil;
  mTokens := ATree.Tokens;
  mIndex := TokenExactly(mTokens, ALoop.StartOffset);
  if mIndex >= 0 then
  begin
    Result := Result + [MakePoint(TExitPointKind.LoopPart, TokenRange(mTokens[mIndex]), '')];
  end;
  if ALoop.Kind = TSyntaxKind.RepeatStatement then
  begin
    mIndex := LastKeyword(mTokens, ALoop.StartOffset, ALoop.EndOffset, 'until');
    if mIndex >= 0 then
    begin
      Result := Result + [MakePoint(TExitPointKind.LoopPart, TokenRange(mTokens[mIndex]), '')];
    end;
  end
  else if ALoop.ChildCount > 0 then
  begin
    mBody := ALoop[ALoop.ChildCount - 1];
    mIndex := LastKeyword(mTokens, ALoop.StartOffset, mBody.StartOffset, 'do');
    if mIndex >= 0 then
    begin
      Result := Result + [MakePoint(TExitPointKind.LoopPart, TokenRange(mTokens[mIndex]), '')];
    end;
    if mBody.Kind = TSyntaxKind.Block then
    begin
      mIndex := LastKeyword(mTokens, mBody.StartOffset, mBody.EndOffset, 'end');
      if mIndex >= 0 then
      begin
        Result := Result + [MakePoint(TExitPointKind.LoopPart, TokenRange(mTokens[mIndex]), '')];
      end;
    end;
  end;
  // Break und Continue dieser Schleife, nicht die einer inneren.
  for mBody in LoopJumps(ALoop) do
  begin
    mIndex := TokenExactly(mTokens, mBody.StartOffset);
    if mIndex >= 0 then
    begin
      Result := Result + [MakePoint(TExitPointKind.LoopJump, TokenRange(mTokens[mIndex]), '')];
    end;
  end;
end;

{ TExitPoints }

class function TExitPoints.Find(ATree: TSyntaxTree; const ALines: TArray<string>; const APosition: TTextPosition;
  const AOptions: TExitPointOptions): TExitPointSet;
begin
  Result := Find(ATree, APosition, AOptions, TreeExceptions(ATree, ALines), TreeClassTest(ATree));
end;

/// <summary>RoutineDecl mit Rumpf, in deren Kopf AOffset liegt; nil sonst.</summary>
function RoutineOfHeader(ARoot: TSyntaxNode; AOffset: Integer): TSyntaxNode;
var
  mRoutine, mHeader: TSyntaxNode;
begin
  Result := nil;
  mRoutine := Innermost(ARoot, AOffset, [TSyntaxKind.RoutineDecl], []);
  if (mRoutine = nil) or (BodyOf(mRoutine) = nil) then
  begin
    Exit;
  end;
  mHeader := mRoutine.FindChild(TSyntaxKind.RoutineHeader);
  if (mHeader <> nil) and (AOffset >= mHeader.StartOffset) and (AOffset < mHeader.EndOffset) then
  begin
    Result := mRoutine;
  end;
end;

type
  /// <summary>Abfrage an einer Stelle: das Wort dort und die Werte, mit denen TExitPoints.Find sucht.</summary>
  TExitQuery = record
    Tree: TSyntaxTree;
    Token: TPascalToken;
    Word: string;
    /// <summary>Foo.Exit, Obj.Break, Obj.Result: kein Austritt (der Kopf TFoo.Run zählt).</summary>
    Qualified: Boolean;
    Options: TExitPointOptions;
    Exceptions: TExitPointExceptionLookup;
    IsA: TExitPointClassTest;
    Raising: TRaisingRoutines;
  end;

/// <summary>Break und Continue: die Schleife. False, wenn das Wort keins davon ist.</summary>
function LoopQuery(const AQuery: TExitQuery; var ASet: TExitPointSet): Boolean;
var
  mLoop: TSyntaxNode;
begin
  Result := (AQuery.Token.Kind = TPascalTokenKind.Identifier) and MatchText(AQuery.Word, ['Break', 'Continue']) and
    not AQuery.Qualified;
  if not Result then
  begin
    Exit;
  end;
  mLoop := Innermost(AQuery.Tree.Root, AQuery.Token.Offset, cLoopKinds, cRoutineKinds);
  if (mLoop <> nil) and AQuery.Options.Loops then
  begin
    ASet.Query := TExitPointQuery.Loop;
    ASet.Points := Sorted(LoopPoints(AQuery.Tree, mLoop));
  end;
end;

/// <summary>Handler, wenn die Abfrage auf "on" oder auf seiner Klasse steht (nicht im Rumpf oder auf dem Namen
/// der Variablen); sonst nil.</summary>
function QueriedHandler(const AQuery: TExitQuery): TSyntaxNode;
var
  mClass: TSyntaxNode;
begin
  Result := nil;
  if AQuery.Token.Kind = TPascalTokenKind.Identifier then
  begin
    Result := Innermost(AQuery.Tree.Root, AQuery.Token.Offset, [TSyntaxKind.ExceptionHandler], cRoutineKinds);
  end;
  if Result = nil then
  begin
    Exit;
  end;
  mClass := Result.FindChild(TSyntaxKind.TypeReference);
  if not (SameText(AQuery.Word, 'on') and (AQuery.Token.Offset = Result.StartOffset)) and
    not ((mClass <> nil) and (AQuery.Token.Offset >= mClass.StartOffset) and
    (AQuery.Token.Offset < mClass.EndOffset)) then
  begin
    Result := nil;
  end;
end;

/// <summary>Klassen, die AHandler bzw. (ohne AHandler) alle Handler von AExceptPart fangen.</summary>
function CaughtClasses(AHandler, AExceptPart: TSyntaxNode): TArray<string>;
var
  mIndex: Integer;
begin
  if AHandler <> nil then
  begin
    Exit(TArray<string>.Create(HandlerClass(AHandler)));
  end;
  Result := nil;
  for mIndex := 0 to AExceptPart.ChildCount - 1 do
  begin
    if AExceptPart[mIndex].Kind = TSyntaxKind.ExceptionHandler then
    begin
      Result := Result + [HandlerClass(AExceptPart[mIndex])];
    end;
  end;
end;

/// <summary>except, on und die Klasse eines Handlers: die auslösenden Stellen im try-Teil. False, wenn die
/// Abfrage dort nicht steht.</summary>
function ExceptQuery(const AQuery: TExitQuery; var ASet: TExitPointSet): Boolean;
var
  mHandler, mExceptPart: TSyntaxNode;
  mPoints: TArray<TExitPoint>;
begin
  mHandler := nil;
  mExceptPart := nil;
  if AQuery.Token.IsKeyword('except') then
  begin
    mExceptPart := Innermost(AQuery.Tree.Root, AQuery.Token.Offset, [TSyntaxKind.ExceptBlock], cRoutineKinds);
  end
  else
  begin
    mHandler := QueriedHandler(AQuery);
    if mHandler <> nil then
    begin
      mExceptPart := mHandler.Parent;
    end;
  end;
  Result := (mExceptPart <> nil) and (mExceptPart.Kind = TSyntaxKind.ExceptBlock);
  if not Result or not AQuery.Options.Exceptions then
  begin
    Exit;
  end;
  mPoints := ExceptionSources(AQuery.Tree, mExceptPart.Parent, CaughtClasses(mHandler, mExceptPart),
    AQuery.Token.Offset, AQuery.Exceptions, AQuery.IsA);
  mPoints := mPoints + [MakePoint(TExitPointKind.Handler, TokenRange(AQuery.Token), '')];
  ASet.Query := TExitPointQuery.Exceptions;
  ASet.Points := Sorted(mPoints);
end;

/// <summary>Austritte von ARoutine als Abfrage AKind.</summary>
procedure RoutineQuery(const AQuery: TExitQuery; ARoutine: TSyntaxNode; AKind: TExitPointQuery;
  var ASet: TExitPointSet);
begin
  if ExitPointsOf(AQuery.Tree, ARoutine, AQuery.Options, AQuery.Raising, ASet) then
  begin
    ASet.Query := AKind;
  end;
end;

/// <summary>Name der Routine im Kopf ihrer Implementierung.</summary>
function HeaderQuery(const AQuery: TExitQuery; var ASet: TExitPointSet): Boolean;
var
  mRoutine: TSyntaxNode;
begin
  mRoutine := nil;
  if AQuery.Token.Kind = TPascalTokenKind.Identifier then
  begin
    mRoutine := RoutineOfHeader(AQuery.Tree.Root, AQuery.Token.Offset);
  end;
  Result := (mRoutine <> nil) and SameText(AQuery.Word, ShortName(mRoutine.Name));
  if Result then
  begin
    RoutineQuery(AQuery, mRoutine, TExitPointQuery.Routine, ASet);
  end;
end;

/// <summary>Result bzw. der Funktionsname als Ziel einer Zuweisung: Austritte und Zuweisungen.</summary>
function ResultQuery(const AQuery: TExitQuery; ARoutine: TSyntaxNode; var ASet: TExitPointSet): Boolean;
var
  mStatement: TSyntaxNode;
begin
  Result := False;
  if not IsFunctionRoutine(ARoutine) or (AQuery.Token.Kind <> TPascalTokenKind.Identifier) then
  begin
    Exit;
  end;
  mStatement := Innermost(AQuery.Tree.Root, AQuery.Token.Offset, [TSyntaxKind.AssignStatement], cRoutineKinds);
  Result := SameText(AQuery.Word, 'Result') or ((mStatement <> nil) and (mStatement.ChildCount > 0) and
    (mStatement[0].StartOffset = AQuery.Token.Offset) and IsResultTarget(mStatement, ShortName(ARoutine.Name)));
  if Result and ExitPointsOf(AQuery.Tree, ARoutine, AQuery.Options, AQuery.Raising, ASet) then
  begin
    ASet.Query := TExitPointQuery.ResultValue;
    ASet.Points := Sorted(ASet.Points + ResultAssignments(ARoutine));
  end;
end;

/// <summary>Exit, raise, Abort, Halt, RunError und Aufrufe, die immer auslösen.</summary>
function IsExitStatement(const AQuery: TExitQuery; AStatement: TSyntaxNode): Boolean;
var
  mWord: string;
begin
  mWord := StatementWord(AStatement);
  Result := (AStatement.Kind = TSyntaxKind.RaiseStatement) or
    MatchText(mWord, ['Exit', 'Abort', 'Halt', 'RunError']) or AQuery.Raising.Contains(mWord) or
    ((AQuery.Options.Keywords <> nil) and (mWord <> '') and MatchText(mWord, AQuery.Options.Keywords));
end;

/// <summary>Abfrage auf einer Anweisung im Rumpf von ARoutine.</summary>
procedure StatementQuery(const AQuery: TExitQuery; ARoutine: TSyntaxNode; var ASet: TExitPointSet);
var
  mStatement: TSyntaxNode;
begin
  mStatement := Innermost(AQuery.Tree.Root, AQuery.Token.Offset, [TSyntaxKind.CallStatement,
    TSyntaxKind.RaiseStatement], cRoutineKinds);
  if (mStatement <> nil) and (mStatement.StartOffset = AQuery.Token.Offset) and
    IsExitStatement(AQuery, mStatement) then
  begin
    RoutineQuery(AQuery, ARoutine, TExitPointQuery.Routine, ASet);
  end;
end;

/// <summary>Steht die Abfrage unqualifiziert im Rumpf von ARoutine?</summary>
function InBody(const AQuery: TExitQuery; ARoutine: TSyntaxNode): Boolean;
begin
  Result := not AQuery.Qualified and (ARoutine <> nil) and (BodyOf(ARoutine) <> nil) and
    (AQuery.Token.Offset >= BodyOf(ARoutine).StartOffset);
end;

class function TExitPoints.Find(ATree: TSyntaxTree; const APosition: TTextPosition;
  const AOptions: TExitPointOptions; const AExceptions: TExitPointExceptionLookup;
  const AIsA: TExitPointClassTest): TExitPointSet;
var
  mIndex: Integer;
  mQuery: TExitQuery;
  mRoutine: TSyntaxNode;
begin
  Result := Default(TExitPointSet);
  mIndex := -1;
  if (ATree <> nil) and (ATree.Root <> nil) then
  begin
    mIndex := WordAt(ATree.Tokens, APosition);
  end;
  if mIndex < 0 then
  begin
    Exit;
  end;
  mQuery := Default(TExitQuery);
  mQuery.Tree := ATree;
  mQuery.Token := ATree.Tokens[mIndex];
  mQuery.Word := mQuery.Token.Text;
  mQuery.Qualified := (mIndex > 0) and ATree.Tokens[mIndex - 1].IsSymbol('.');
  mQuery.Options := AOptions;
  mQuery.Exceptions := AExceptions;
  mQuery.IsA := AIsA;
  mRoutine := Innermost(ATree.Root, mQuery.Token.Offset, cRoutineKinds, []);
  mQuery.Raising := TRaisingRoutines.Create(ATree);
  try
    if not LoopQuery(mQuery, Result) and not ExceptQuery(mQuery, Result) and not HeaderQuery(mQuery, Result) and
      InBody(mQuery, mRoutine) and not ResultQuery(mQuery, mRoutine, Result) then
    begin
      StatementQuery(mQuery, mRoutine, Result);
    end;
  finally
    mQuery.Raising.Free;
  end;
end;

type
  TRoutineExceptions = record
    Name: string;
    Classes: TArray<string>;
  end;

/// <summary>Kopf oder Rumpf einer Routine (ein Kopf unter seiner RoutineDecl zählt nicht doppelt).</summary>
function IsDocumentedRoutine(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.RoutineDecl) or ((ANode.Kind = TSyntaxKind.RoutineHeader) and
    not ((ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.RoutineDecl)));
end;

/// <summary>&lt;exception cref&gt; im ///-Kommentar über ANode; False ohne.</summary>
function DocumentedExceptions(ANode: TSyntaxNode; const ALines: TArray<string>;
  out AItem: TRoutineExceptions): Boolean;
var
  mDoc: TXmlDoc;
  mEntry: TXmlDocEntry;
  mComment: string;
begin
  AItem := Default(TRoutineExceptions);
  mComment := '';
  if IsDocumentedRoutine(ANode) then
  begin
    mComment := TXmlDoc.CommentAbove(ALines, ANode.StartPos.Line);
  end;
  if mComment = '' then
  begin
    Exit(False);
  end;
  mDoc := TXmlDoc.Parse(mComment);
  AItem.Name := ShortName(ANode.Name);
  for mEntry in mDoc.Exceptions do
  begin
    AItem.Classes := AItem.Classes + [TXmlDoc.NormalizeCref(mEntry.Name)];
  end;
  Result := Length(AItem.Classes) > 0;
end;

/// <summary>Name, unter dem ACallee in den Doku-Einträgen steht; '' ohne.</summary>
function DocumentedName(ACallee: TSyntaxNode): string;
begin
  Result := TExitPoints.PlainCallee(ACallee);
  if (Result = '') and (ACallee <> nil) and (ACallee.Kind = TSyntaxKind.MemberAccess) then
  begin
    Result := ACallee.Name;
  end;
end;

/// <summary>Lookup über die gesammelten Einträge ADocs.</summary>
function DocumentedLookup(const ADocs: TArray<TRoutineExceptions>): TExitPointExceptionLookup;
var
  mDocs: TArray<TRoutineExceptions>;
begin
  mDocs := ADocs;
  Result :=
    function(ACallee: TSyntaxNode): TArray<string>
    var
      mName: string;
      mItem: TRoutineExceptions;
    begin
      Result := nil;
      mName := DocumentedName(ACallee);
      for mItem in mDocs do
      begin
        if (mName <> '') and SameText(mItem.Name, mName) then
        begin
          Result := Result + mItem.Classes;
        end;
      end;
    end;
end;

class function TExitPoints.TreeExceptions(ATree: TSyntaxTree; const ALines: TArray<string>):
  TExitPointExceptionLookup;
var
  mDocs: TArray<TRoutineExceptions>;
  mLines: TArray<string>;
begin
  mDocs := nil;
  mLines := ALines;
  // Deklarationen in Klassen und Rümpfe: der ///-Kommentar darüber. Einmal je Lookup gelesen.
  if (ATree <> nil) and (ATree.Root <> nil) then
  begin
    ATree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      var
        mItem: TRoutineExceptions;
      begin
        Result := ANode.Kind <> TSyntaxKind.AnonymousMethod;
        if DocumentedExceptions(ANode, mLines, mItem) then
        begin
          mDocs := mDocs + [mItem];
        end;
      end);
  end;
  Result := DocumentedLookup(mDocs);
end;

/// <summary>Erster Vorfahr der Klasse AClass in ATree; '' ohne.</summary>
function AncestorIn(ATree: TSyntaxTree; const AClass: string): string;
var
  mAncestor, mClass: string;
  mFound: Boolean;
begin
  mAncestor := '';
  mClass := AClass;
  mFound := False;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      mClassNode, mFirst: TSyntaxNode;
    begin
      Result := not mFound;
      if mFound or (ANode.Kind <> TSyntaxKind.TypeDecl) or not SameText(ANode.Name, mClass) then
      begin
        Exit;
      end;
      mClassNode := ANode.FindChild(TSyntaxKind.ClassType);
      if mClassNode = nil then
      begin
        Exit;
      end;
      mFound := True;
      mFirst := mClassNode.FindChild(TSyntaxKind.TypeReference);
      if mFirst <> nil then
      begin
        mAncestor := mFirst.Name;
      end;
    end);
  Result := mAncestor;
end;

/// <summary>Stammt AClass über die Klassen in ATree von AHandler ab (höchstens 32 Stufen)?</summary>
function DescendsIn(ATree: TSyntaxTree; const AClass, AHandler: string): Boolean;
var
  mCurrent, mAncestor: string;
  mDepth: Integer;
begin
  mCurrent := AClass;
  for mDepth := 1 to 32 do
  begin
    mAncestor := AncestorIn(ATree, mCurrent);
    if (mAncestor = '') or SameText(mAncestor, AHandler) then
    begin
      Exit(mAncestor <> '');
    end;
    mCurrent := mAncestor;
  end;
  Result := False;
end;

class function TExitPoints.TreeClassTest(ATree: TSyntaxTree): TExitPointClassTest;
var
  mTree: TSyntaxTree;
begin
  mTree := ATree;
  Result :=
    function(const AClass, AHandler: string; AOffset: Integer): Boolean
    begin
      // Jede Exception-Klasse stammt von Exception ab (Konvention der RTL).
      Result := SameText(AHandler, 'Exception') or SameText(AHandler, 'System.SysUtils.Exception') or
        SameText(AClass, AHandler) or ((mTree <> nil) and DescendsIn(mTree, AClass, AHandler));
    end;
end;

end.
