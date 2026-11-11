unit Atlas.Common.Lsp.KeywordHighlights;

// Zusammengehörige Schlüsselwörter hervorheben (#307), Ergänzung zu
// textDocument/documentHighlight (#21):
// - Blockpaare: begin/end, try/finally/except/end, case/of/else/end,
//   repeat/until, asm/end, class/record/interface/object … end, if/then/else
//   (else gehört zum nächsten offenen if derselben Ebene),
// - Routinen: procedure/function/constructor/destructor mit begin und end,
// - Direktiven: {$IF…}/{$ELSEIF}/{$ELSE}/{$ENDIF} und {$REGION}/{$ENDREGION},
// - Ausstiegspunkte: auf Exit, raise, Abort, Halt (einstellbar) oder dem
//   Routinennamen im Kopf alle Ausstiege der Routine, ohne lokale Routinen und
//   anonyme Methoden, das end nur, wenn ein Weg dort herausfällt; auf
//   Break/Continue Kopf und Ende der Schleife samt ihrer Sprünge. Beides
//   rechnet Atlas.Common.Semantics.ExitPoints (#698), dieselbe Analyse wie
//   die Hervorhebung im Plugin.
//
// Blöcke werden über die Token mit einem Stapel gepaart, damit auch
// unfertiger Code ohne Fehler bleibt: Fehlt ein Gegenstück, bleibt nur das
// Schlüsselwort selbst übrig.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  TKeywordHighlights = class
  public
    /// <summary>Bereiche zum Schlüsselwort an APosition. False, wenn dort kein solches
    /// Schlüsselwort steht (dann gilt die Hervorhebung von Bezeichnern). Bei True kann
    /// ARanges leer sein, etwa wenn die Einstellung die Art abschaltet.</summary>
    class function Find(ATree: TSyntaxTree; const APosition: TTextPosition; const ASettings: THighlightSettings;
      out ARanges: TArray<TTextRange>): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Semantics.ExitPoints;

type
  TSyntaxKinds = set of TSyntaxKind;

  {$SCOPEDENUMS ON}
  TFrameKind = (Root, Begin_, Try_, Case_, Repeat_, Asm_, TypeBody, Record_);
  {$SCOPEDENUMS OFF}

  TFrame = class
    FKind: TFrameKind;
    FGroup: Integer;
    FPendingIfs: TList<Integer>;
    constructor Create(AKind: TFrameKind; AGroup: Integer);
    destructor Destroy; override;
  end;

  /// <summary>Gruppen zusammengehöriger Token (Indizes in ATree.Tokens).</summary>
  TGroups = class
  private
    FTokens: TArray<TPascalToken>;
    FGroups: TObjectList<TList<Integer>>;
    FGroupOf: TDictionary<Integer, Integer>;
    function NewGroup(AToken: Integer): Integer;
    procedure AddTo(AGroup, AToken: Integer);
    procedure BuildBlocks;
    procedure AddDirective(const AName: string; AToken: Integer; AConditions, ARegions: TStack<Integer>);
    procedure BuildDirectives;
  public
    constructor Create(const ATokens: TArray<TPascalToken>; ADirectives: Boolean);
    destructor Destroy; override;
    function GroupTokens(AToken: Integer; out ATokens: TArray<Integer>): Boolean;
  end;

const
  cRoutineKeywords: array[0..3] of string = ('procedure', 'function', 'constructor', 'destructor');
  cBlockKeywords: array[0..17] of string = ('begin', 'end', 'try', 'finally', 'except', 'case', 'of', 'else',
    'repeat', 'until', 'asm', 'record', 'class', 'interface', 'dispinterface', 'object', 'if', 'then');

{ TFrame }

constructor TFrame.Create(AKind: TFrameKind; AGroup: Integer);
begin
  inherited Create;
  FKind := AKind;
  FGroup := AGroup;
  FPendingIfs := TList<Integer>.Create;
end;

destructor TFrame.Destroy;
begin
  FPendingIfs.Free;
  inherited;
end;

{ TGroups }

constructor TGroups.Create(const ATokens: TArray<TPascalToken>; ADirectives: Boolean);
begin
  inherited Create;
  FTokens := ATokens;
  FGroups := TObjectList<TList<Integer>>.Create;
  FGroupOf := TDictionary<Integer, Integer>.Create;
  BuildBlocks;
  if ADirectives then
  begin
    BuildDirectives;
  end;
end;

destructor TGroups.Destroy;
begin
  FGroupOf.Free;
  FGroups.Free;
  inherited;
end;

function TGroups.NewGroup(AToken: Integer): Integer;
begin
  FGroups.Add(TList<Integer>.Create);
  Result := FGroups.Count - 1;
  AddTo(Result, AToken);
end;

procedure TGroups.AddTo(AGroup, AToken: Integer);
begin
  FGroups[AGroup].Add(AToken);
  FGroupOf.AddOrSetValue(AToken, AGroup);
end;

function TGroups.GroupTokens(AToken: Integer; out ATokens: TArray<Integer>): Boolean;
var
  mGroup: Integer;
begin
  Result := FGroupOf.TryGetValue(AToken, mGroup);
  if Result then
  begin
    ATokens := FGroups[mGroup].ToArray;
  end;
end;

type
  /// <summary>Paart die Blockschlüsselwörter eines TGroups über einen Stapel offener Blöcke.</summary>
  TBlockScan = class
  private
    FOwner: TGroups;
    FSignificants: TList<Integer>;
    FStack: TObjectStack<TFrame>;
    function TokenAtPos(APosition: Integer): TPascalToken;
    /// <summary>Position hinter der Klammer, die an AStart öffnet.</summary>
    function SkipParens(AStart: Integer): Integer;
    /// <summary>Beginnt class/interface/object an dieser Stelle einen Typrumpf mit end?</summary>
    function StartsTypeBody(APosition: Integer): Boolean;
    procedure Push(AKind: TFrameKind; AToken: Integer);
    procedure CloseTop(AToken: Integer);
    /// <summary>Öffnende Wörter (begin, try, case, …, class); False bei anderen.</summary>
    function Open(const AWord: string; APosition: Integer): Boolean;
    /// <summary>Schließende und mittlere Wörter (end, until, finally, except, of); False bei anderen.</summary>
    function Close(const AWord: string; AToken: Integer): Boolean;
    /// <summary>if, then und else.</summary>
    procedure Branch(const AWord: string; AToken: Integer);
    procedure Step(APosition: Integer);
  public
    constructor Create(AOwner: TGroups);
    destructor Destroy; override;
    procedure Run;
  end;

const
  cOpenWords: array[0..5] of string = ('begin', 'try', 'case', 'repeat', 'asm', 'record');
  cOpenKinds: array[0..5] of TFrameKind = (TFrameKind.Begin_, TFrameKind.Try_, TFrameKind.Case_, TFrameKind.Repeat_,
    TFrameKind.Asm_, TFrameKind.Record_);
  cTypeWords: array[0..3] of string = ('class', 'interface', 'dispinterface', 'object');

function Significant(const AToken: TPascalToken): Boolean;
begin
  Result := not (AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]);
end;

/// <summary>class abstract, class sealed.</summary>
function IsTypeModifier(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsKeyword('abstract') or AToken.IsKeyword('sealed') or SameText(AToken.Text, 'abstract') or
    SameText(AToken.Text, 'sealed');
end;

{ TBlockScan }

constructor TBlockScan.Create(AOwner: TGroups);
var
  mIndex: Integer;
begin
  inherited Create;
  FOwner := AOwner;
  FStack := TObjectStack<TFrame>.Create(True);
  FSignificants := TList<Integer>.Create;
  for mIndex := 0 to High(FOwner.FTokens) do
  begin
    if Significant(FOwner.FTokens[mIndex]) then
    begin
      FSignificants.Add(mIndex);
    end;
  end;
  FStack.Push(TFrame.Create(TFrameKind.Root, -1));
end;

destructor TBlockScan.Destroy;
begin
  FSignificants.Free;
  FStack.Free;
  inherited;
end;

function TBlockScan.TokenAtPos(APosition: Integer): TPascalToken;
begin
  if (APosition >= 0) and (APosition < FSignificants.Count) then
  begin
    Result := FOwner.FTokens[FSignificants[APosition]];
  end
  else
  begin
    Result := Default(TPascalToken);
  end;
end;

function TBlockScan.SkipParens(AStart: Integer): Integer;
var
  mDepth: Integer;
  mToken: TPascalToken;
begin
  Result := AStart;
  mDepth := 0;
  repeat
    mToken := TokenAtPos(Result);
    if mToken.IsSymbol('(') then
    begin
      Inc(mDepth);
    end
    else if mToken.IsSymbol(')') then
    begin
      Dec(mDepth);
    end;
    Inc(Result);
  until (mDepth = 0) or (Result >= FSignificants.Count);
end;

function TBlockScan.StartsTypeBody(APosition: Integer): Boolean;
var
  mNext: Integer;
begin
  if not TokenAtPos(APosition - 1).IsSymbol('=') then
  begin
    Exit(False);
  end;
  mNext := APosition + 1;
  // class abstract, class sealed, class helper for TFoo
  while IsTypeModifier(TokenAtPos(mNext)) do
  begin
    Inc(mNext);
  end;
  if SameText(TokenAtPos(mNext).Text, 'helper') then
  begin
    Exit(True);
  end;
  if TokenAtPos(mNext).IsKeyword('of') then
  begin
    Exit(False);
  end;
  if TokenAtPos(mNext).IsSymbol('(') then
  begin
    mNext := SkipParens(mNext);
  end;
  // Vorwärtsdeklaration: TFoo = class; bzw. class(TBasis);
  Result := not TokenAtPos(mNext).IsSymbol(';');
end;

procedure TBlockScan.Push(AKind: TFrameKind; AToken: Integer);
begin
  FStack.Push(TFrame.Create(AKind, FOwner.NewGroup(AToken)));
end;

procedure TBlockScan.CloseTop(AToken: Integer);
begin
  FOwner.AddTo(FStack.Peek.FGroup, AToken);
  FStack.Pop;
end;

function TBlockScan.Open(const AWord: string; APosition: Integer): Boolean;
var
  mWord: Integer;
begin
  mWord := IndexText(AWord, cOpenWords);
  if mWord >= 0 then
  begin
    // Varianter Teil eines Records: das end des Records schließt ihn.
    if (cOpenKinds[mWord] <> TFrameKind.Case_) or (FStack.Peek.FKind <> TFrameKind.Record_) then
    begin
      Push(cOpenKinds[mWord], FSignificants[APosition]);
    end;
    Exit(True);
  end;
  Result := MatchText(AWord, cTypeWords);
  if Result and StartsTypeBody(APosition) then
  begin
    Push(TFrameKind.TypeBody, FSignificants[APosition]);
  end;
end;

function TBlockScan.Close(const AWord: string; AToken: Integer): Boolean;
var
  mTop: TFrame;
begin
  mTop := FStack.Peek;
  Result := True;
  if AWord = 'end' then
  begin
    if not (mTop.FKind in [TFrameKind.Root, TFrameKind.Repeat_]) then
    begin
      CloseTop(AToken);
    end;
  end
  else if AWord = 'until' then
  begin
    if mTop.FKind = TFrameKind.Repeat_ then
    begin
      CloseTop(AToken);
    end;
  end
  else if MatchText(AWord, ['finally', 'except']) then
  begin
    if mTop.FKind = TFrameKind.Try_ then
    begin
      FOwner.AddTo(mTop.FGroup, AToken);
    end;
  end
  else if AWord = 'of' then
  begin
    if (mTop.FKind = TFrameKind.Case_) and (FOwner.FGroups[mTop.FGroup].Count = 1) then
    begin
      FOwner.AddTo(mTop.FGroup, AToken);
    end;
  end
  else
  begin
    Result := False;
  end;
end;

procedure TBlockScan.Branch(const AWord: string; AToken: Integer);
var
  mTop: TFrame;
begin
  mTop := FStack.Peek;
  if AWord = 'if' then
  begin
    mTop.FPendingIfs.Add(FOwner.NewGroup(AToken));
  end
  else if AWord = 'then' then
  begin
    if (mTop.FPendingIfs.Count > 0) and (FOwner.FGroups[mTop.FPendingIfs.Last].Count = 1) then
    begin
      FOwner.AddTo(mTop.FPendingIfs.Last, AToken);
    end;
  end
  else if AWord = 'else' then
  begin
    if mTop.FPendingIfs.Count > 0 then
    begin
      FOwner.AddTo(mTop.FPendingIfs.Last, AToken);
      mTop.FPendingIfs.Delete(mTop.FPendingIfs.Count - 1);
    end
    else if mTop.FKind in [TFrameKind.Case_, TFrameKind.Try_] then
    begin
      FOwner.AddTo(mTop.FGroup, AToken);
    end;
  end;
end;

procedure TBlockScan.Step(APosition: Integer);
var
  mIndex: Integer;
  mWord: string;
begin
  mIndex := FSignificants[APosition];
  if FOwner.FTokens[mIndex].IsSymbol(';') then
  begin
    FStack.Peek.FPendingIfs.Clear;
    Exit;
  end;
  if FOwner.FTokens[mIndex].Kind <> TPascalTokenKind.Keyword then
  begin
    Exit;
  end;
  mWord := LowerCase(FOwner.FTokens[mIndex].Text);
  if not Open(mWord, APosition) and not Close(mWord, mIndex) then
  begin
    Branch(mWord, mIndex);
  end;
end;

procedure TBlockScan.Run;
var
  mPosition: Integer;
begin
  for mPosition := 0 to FSignificants.Count - 1 do
  begin
    Step(mPosition);
  end;
end;

{ TGroups }

procedure TGroups.BuildBlocks;
var
  mScan: TBlockScan;
begin
  mScan := TBlockScan.Create(Self);
  try
    mScan.Run;
  finally
    mScan.Free;
  end;
end;

procedure TGroups.AddDirective(const AName: string; AToken: Integer; AConditions, ARegions: TStack<Integer>);
begin
  if MatchText(AName, ['IF', 'IFDEF', 'IFNDEF', 'IFOPT']) then
  begin
    AConditions.Push(NewGroup(AToken));
  end
  else if MatchText(AName, ['ELSEIF', 'ELSE']) and (AConditions.Count > 0) then
  begin
    AddTo(AConditions.Peek, AToken);
  end
  else if MatchText(AName, ['ENDIF', 'IFEND']) and (AConditions.Count > 0) then
  begin
    AddTo(AConditions.Pop, AToken);
  end
  else if AName = 'REGION' then
  begin
    ARegions.Push(NewGroup(AToken));
  end
  else if (AName = 'ENDREGION') and (ARegions.Count > 0) then
  begin
    AddTo(ARegions.Pop, AToken);
  end;
end;

procedure TGroups.BuildDirectives;
var
  mConditions, mRegions: TStack<Integer>;
  mIndex: Integer;
begin
  mConditions := TStack<Integer>.Create;
  mRegions := TStack<Integer>.Create;
  try
    for mIndex := 0 to High(FTokens) do
    begin
      if FTokens[mIndex].Kind = TPascalTokenKind.Directive then
      begin
        AddDirective(TPascalLexer.DirectiveName(FTokens[mIndex].Text), mIndex, mConditions, mRegions);
      end;
    end;
  finally
    mRegions.Free;
    mConditions.Free;
  end;
end;

{ Hilfen }

function TokenAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
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
      (mToken.Kind <> TPascalTokenKind.Symbol) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function IndexOfOffset(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
begin
  // Binär statt ab Dateianfang (#1342).
  Result := TSyntaxTree.FirstTokenOf(ATokens, AOffset);
  if (Result > High(ATokens)) or (ATokens[Result].Offset <> AOffset) then
  begin
    Result := -1;
  end;
end;

/// <summary>Letztes Schlüsselwort AWord vor AEndOffset ab AStartOffset; -1 wenn keins.</summary>
function LastKeywordBefore(const ATokens: TArray<TPascalToken>; AStartOffset, AEndOffset: Integer;
  const AWord: string): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := TSyntaxTree.FirstTokenOf(ATokens, AStartOffset) to High(ATokens) do
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

/// <summary>Legt die Kinder von ANode, die AOffset enthalten, auf APending (das erste oben).</summary>
procedure PushChildren(APending: TStack<TSyntaxPostOrderEntry>; ANode: TSyntaxNode; AOffset: Integer);
var
  mIndex: Integer;
  mChild: TSyntaxNode;
begin
  APending.Push(TSyntaxPostOrderEntry.Create(ANode, True));
  for mIndex := ANode.ChildCount - 1 downto 0 do
  begin
    mChild := ANode[mIndex];
    if (AOffset >= mChild.StartOffset) and (AOffset < mChild.EndOffset) then
    begin
      APending.Push(TSyntaxPostOrderEntry.Create(mChild, False));
    end;
  end;
end;

/// <summary>Verwirft die noch nicht besuchten Geschwister bis zum nächsten Vorfahren.</summary>
procedure DropSiblings(APending: TStack<TSyntaxPostOrderEntry>);
begin
  while (APending.Count > 0) and not APending.Peek.Done do
  begin
    APending.Pop;
  end;
end;

/// <summary>Innerster Knoten einer der Arten, der AOffset enthält; ohne Grenzen zu überschreiten.</summary>
function Innermost(ANode: TSyntaxNode; AOffset: Integer; const AKinds, ABoundaries: TSyntaxKinds): TSyntaxNode;
var
  mPending: TStack<TSyntaxPostOrderEntry>;
  mEntry: TSyntaxPostOrderEntry;
begin
  // Eigener Stapel statt Rekursion: Der Weg zum Offset kann durch tiefe Ausdrücke führen.
  // Ein Knoten wird nach seinen Kindern geprüft; eine Grenze beendet wie früher die Suche unter ihren
  // Geschwistern, die Vorfahren werden danach noch geprüft.
  Result := nil;
  mPending := TStack<TSyntaxPostOrderEntry>.Create;
  try
    mPending.Push(TSyntaxPostOrderEntry.Create(ANode, False));
    while (mPending.Count > 0) and (Result = nil) do
    begin
      mEntry := mPending.Pop;
      if not mEntry.Done then
      begin
        PushChildren(mPending, mEntry.Node, AOffset);
      end
      else if mEntry.Node = ANode then
      begin
        Continue;
      end
      else if mEntry.Node.Kind in AKinds then
      begin
        Result := mEntry.Node;
      end
      else if mEntry.Node.Kind in ABoundaries then
      begin
        DropSiblings(mPending);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

procedure AddToken(var ARanges: TArray<TTextRange>; const AToken: TPascalToken);
begin
  ARanges := ARanges + [TTextRange.Create(AToken.StartPos, AToken.EndPos)];
end;

/// <summary>Austritte bzw. Schleifenteile über TExitPoints (#698): ohne Exceptions (except gehört zu den
/// Blockpaaren), mit den Wörtern aus highlight.exitKeywords.</summary>
function ExitRanges(ATree: TSyntaxTree; const APosition: TTextPosition;
  const ASettings: THighlightSettings): TArray<TTextRange>;
var
  mOptions: TExitPointOptions;
  mFound: TExitPointSet;
  mPoint: TExitPoint;
begin
  Result := nil;
  mOptions := TExitPointOptions.Default;
  mOptions.Exceptions := False;
  mOptions.Keywords := ASettings.ExitKeywords;
  mFound := TExitPoints.Find(ATree, APosition, mOptions, nil, nil);
  for mPoint in mFound.Points do
  begin
    Result := Result + [mPoint.Range];
  end;
end;

/// <summary>RoutineDecl mit Rumpf, in deren Kopf AOffset liegt.</summary>
function RoutineOfHeader(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
var
  mRoot: TSyntaxNode;
  mOffset: Integer;
begin
  mRoot := ANode;
  mOffset := AOffset;
  // Search statt Rekursion; unter ANode nur Knoten, die AOffset enthalten.
  Result := ANode.Search(
    function(ACandidate: TSyntaxNode): TSyntaxSearchStep
    var
      Header: TSyntaxNode;
    begin
      if (ACandidate <> mRoot) and ((mOffset < ACandidate.StartOffset) or (mOffset >= ACandidate.EndOffset)) then
      begin
        Exit(TSyntaxSearchStep.Skip);
      end;
      Result := TSyntaxSearchStep.Descend;
      if (ACandidate.Kind = TSyntaxKind.RoutineDecl) and (ACandidate.FindChild(TSyntaxKind.Block) <> nil) then
      begin
        Header := ACandidate.FindChild(TSyntaxKind.RoutineHeader);
        if (Header <> nil) and (mOffset >= Header.StartOffset) and (mOffset < Header.EndOffset) then
        begin
          Result := TSyntaxSearchStep.Found;
        end;
      end;
    end);
end;

function ShortName(const AName: string): string;
begin
  Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

function ByPosition(const ARanges: TArray<TTextRange>): TArray<TTextRange>;
var
  mList: TList<TTextRange>;
  mRange: TTextRange;
  mIndex: Integer;
  mKnown: Boolean;
begin
  mList := TList<TTextRange>.Create(TComparer<TTextRange>.Construct(
    function(const A, B: TTextRange): Integer
    begin
      Result := A.StartPos.Line - B.StartPos.Line;
      if Result = 0 then
      begin
        Result := A.StartPos.Character - B.StartPos.Character;
      end;
    end));
  try
    for mRange in ARanges do
    begin
      mKnown := False;
      for mIndex := 0 to mList.Count - 1 do
      begin
        mKnown := mKnown or (mList[mIndex].StartPos = mRange.StartPos);
      end;
      if not mKnown then
      begin
        mList.Add(mRange);
      end;
    end;
    mList.Sort;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

type
  /// <summary>Token an der gefragten Stelle mit Baum und Einstellungen.</summary>
  TKeywordQuery = record
    Tree: TSyntaxTree;
    Index: Integer;
    Position: TTextPosition;
    Settings: THighlightSettings;
    function Token: TPascalToken;
  end;

const
  cLoops = [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
    TSyntaxKind.RepeatStatement];
  cRoutines = [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod];

function TKeywordQuery.Token: TPascalToken;
begin
  Result := Tree.Tokens[Index];
end;

/// <summary>Exit, raise, Abort, Halt … (highlight.exitKeywords), nicht als Glied hinter einem Punkt.</summary>
function IsExitWord(const AQuery: TKeywordQuery): Boolean;
begin
  Result := (AQuery.Token.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
    MatchText(AQuery.Token.Text, AQuery.Settings.ExitKeywords) and
    not ((AQuery.Index > 0) and AQuery.Tree.Tokens[AQuery.Index - 1].IsSymbol('.'));
end;

/// <summary>Ausstiegspunkte zu einem Ausstiegswort, zu Break/Continue oder zum Routinennamen im Kopf einer
/// Implementierung; False, wenn das Token keins davon ist.</summary>
function FindExits(const AQuery: TKeywordQuery; out ARanges: TArray<TTextRange>): Boolean;
var
  mToken: TPascalToken;
  mRoutine: TSyntaxNode;
begin
  ARanges := nil;
  mToken := AQuery.Token;
  if IsExitWord(AQuery) then
  begin
    Result := Innermost(AQuery.Tree.Root, mToken.Offset, cRoutines, []) <> nil;
  end
  else if MatchText(mToken.Text, ['Break', 'Continue']) then
  begin
    Result := Innermost(AQuery.Tree.Root, mToken.Offset, cLoops, cRoutines) <> nil;
  end
  else
  begin
    mRoutine := RoutineOfHeader(AQuery.Tree.Root, mToken.Offset);
    Result := (mRoutine <> nil) and SameText(mToken.Text, ShortName(mRoutine.Name)) and AQuery.Settings.ExitPoints;
  end;
  if Result and AQuery.Settings.ExitPoints then
  begin
    ARanges := ByPosition(ExitRanges(AQuery.Tree, AQuery.Position, AQuery.Settings));
  end;
end;

/// <summary>Bereiche der Gruppe des Tokens (ADirectives: mit Direktiven); False ohne Gruppe.</summary>
function GroupRanges(const AQuery: TKeywordQuery; ADirectives: Boolean; out ARanges: TArray<TTextRange>): Boolean;
var
  mGroups: TGroups;
  mMembers: TArray<Integer>;
  mMember: Integer;
begin
  ARanges := nil;
  mGroups := TGroups.Create(AQuery.Tree.Tokens, ADirectives);
  try
    Result := mGroups.GroupTokens(AQuery.Index, mMembers);
    for mMember in mMembers do
    begin
      AddToken(ARanges, AQuery.Tree.Tokens[mMember]);
    end;
  finally
    mGroups.Free;
  end;
  ARanges := ByPosition(ARanges);
end;

/// <summary>{$IF…}/{$ELSE}/{$ENDIF} und Regionen.</summary>
function FindDirective(const AQuery: TKeywordQuery; out ARanges: TArray<TTextRange>): Boolean;
begin
  ARanges := nil;
  Result := (TPascalLexer.DirectiveName(AQuery.Token.Text) <> '') and GroupRanges(AQuery, True, ARanges);
  if not AQuery.Settings.Directives then
  begin
    ARanges := nil;
  end;
end;

/// <summary>procedure/function/… einer Implementierung: Kopf, begin und end.</summary>
function FindRoutine(const AQuery: TKeywordQuery; out ARanges: TArray<TTextRange>): Boolean;
var
  mRoutine, mBlock: TSyntaxNode;
  mTokens: TArray<TPascalToken>;
  mIndex: Integer;
begin
  ARanges := nil;
  mRoutine := RoutineOfHeader(AQuery.Tree.Root, AQuery.Token.Offset);
  Result := mRoutine <> nil;
  if not Result or not AQuery.Settings.BlockPairs then
  begin
    Exit;
  end;
  mTokens := AQuery.Tree.Tokens;
  AddToken(ARanges, AQuery.Token);
  mBlock := mRoutine.FindChild(TSyntaxKind.Block);
  mIndex := IndexOfOffset(mTokens, mBlock.StartOffset);
  if mIndex >= 0 then
  begin
    AddToken(ARanges, mTokens[mIndex]);
  end;
  mIndex := LastKeywordBefore(mTokens, mBlock.StartOffset, mBlock.EndOffset, 'end');
  if mIndex >= 0 then
  begin
    AddToken(ARanges, mTokens[mIndex]);
  end;
  ARanges := ByPosition(ARanges);
end;

/// <summary>Blockpaare; ohne Gegenstück nur das Schlüsselwort selbst.</summary>
function FindBlock(const AQuery: TKeywordQuery; out ARanges: TArray<TTextRange>): Boolean;
begin
  ARanges := nil;
  Result := True;
  if AQuery.Settings.BlockPairs and not GroupRanges(AQuery, False, ARanges) then
  begin
    AddToken(ARanges, AQuery.Token);
  end;
end;

{ TKeywordHighlights }

class function TKeywordHighlights.Find(ATree: TSyntaxTree; const APosition: TTextPosition;
  const ASettings: THighlightSettings; out ARanges: TArray<TTextRange>): Boolean;
var
  mQuery: TKeywordQuery;
  mToken: TPascalToken;
begin
  ARanges := nil;
  Result := False;
  if ATree = nil then
  begin
    Exit;
  end;
  mQuery.Tree := ATree;
  mQuery.Index := TokenAt(ATree.Tokens, APosition);
  mQuery.Position := APosition;
  mQuery.Settings := ASettings;
  if mQuery.Index < 0 then
  begin
    Exit;
  end;
  mToken := mQuery.Token;
  if IsExitWord(mQuery) or (mToken.Kind = TPascalTokenKind.Identifier) then
  begin
    Result := FindExits(mQuery, ARanges);
  end
  else if mToken.Kind = TPascalTokenKind.Directive then
  begin
    Result := FindDirective(mQuery, ARanges);
  end
  else if mToken.Kind <> TPascalTokenKind.Keyword then
  begin
    Result := False;
  end
  else if MatchText(mToken.Text, cRoutineKeywords) then
  begin
    Result := FindRoutine(mQuery, ARanges);
  end
  else if MatchText(mToken.Text, cBlockKeywords) then
  begin
    Result := FindBlock(mQuery, ARanges);
  end;
end;

end.
