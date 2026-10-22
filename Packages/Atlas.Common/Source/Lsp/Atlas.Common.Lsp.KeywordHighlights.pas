unit Atlas.Common.Lsp.KeywordHighlights;

// Zusammengehörige Schlüsselwörter hervorheben (#307), Ergänzung zu
// textDocument/documentHighlight (#21):
// - Blockpaare: begin/end, try/finally/except/end, case/of/else/end,
//   repeat/until, asm/end, class/record/interface/object … end, if/then/else
//   (else gehört zum nächsten offenen if derselben Ebene),
// - Routinen: procedure/function/constructor/destructor mit begin und end,
// - Direktiven: {$IF…}/{$ELSEIF}/{$ELSE}/{$ENDIF} und {$REGION}/{$ENDREGION},
// - Ausstiegspunkte: auf Exit, raise, Abort, Halt (einstellbar) oder dem
//   Routinennamen im Kopf alle Ausstiege samt end der Routine, ohne lokale
//   Routinen und anonyme Methoden; auf Break/Continue Kopf und Ende der Schleife.
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
  Atlas.Common.Pascal.Lexer;

type
  TSyntaxKinds = set of TSyntaxKind;

  {$SCOPEDENUMS ON}
  TFrameKind = (Root, Begin_, Try_, Case_, Repeat_, Asm_, TypeBody, Record_);
  {$SCOPEDENUMS OFF}

  TFrame = class
    Kind: TFrameKind;
    Group: Integer;
    PendingIfs: TList<Integer>;
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
    procedure BuildDirectives;
  public
    constructor Create(const ATokens: TArray<TPascalToken>; ADirectives: Boolean);
    destructor Destroy; override;
    function GroupTokens(AToken: Integer; out ATokens: TArray<Integer>): Boolean;
  end;

const
  RoutineKeywords: array[0..3] of string = ('procedure', 'function', 'constructor', 'destructor');
  BlockKeywords: array[0..17] of string = ('begin', 'end', 'try', 'finally', 'except', 'case', 'of', 'else',
    'repeat', 'until', 'asm', 'record', 'class', 'interface', 'dispinterface', 'object', 'if', 'then');

{ TFrame }

constructor TFrame.Create(AKind: TFrameKind; AGroup: Integer);
begin
  inherited Create;
  Kind := AKind;
  Group := AGroup;
  PendingIfs := TList<Integer>.Create;
end;

destructor TFrame.Destroy;
begin
  PendingIfs.Free;
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
    BuildDirectives;
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
  Group: Integer;
begin
  Result := FGroupOf.TryGetValue(AToken, Group);
  if Result then
    ATokens := FGroups[Group].ToArray;
end;

function Significant(const AToken: TPascalToken): Boolean;
begin
  Result := not (AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]);
end;

procedure TGroups.BuildBlocks;
var
  Stack: TObjectStack<TFrame>;
  Significants: TList<Integer>;
  Position, Index: Integer;
  Word: string;
  Top: TFrame;

  function TokenAtPos(APosition: Integer): TPascalToken;
  begin
    if (APosition >= 0) and (APosition < Significants.Count) then
      Result := FTokens[Significants[APosition]]
    else
      Result := Default(TPascalToken);
  end;

  /// <summary>Beginnt class/interface/object an dieser Stelle einen Typrumpf mit end?</summary>
  function StartsTypeBody(APosition: Integer): Boolean;
  var
    Next: Integer;
    Depth: Integer;
    Token: TPascalToken;
  begin
    if not TokenAtPos(APosition - 1).IsSymbol('=') then
      Exit(False);
    Next := APosition + 1;
    // class abstract, class sealed, class helper for TFoo
    while TokenAtPos(Next).IsKeyword('abstract') or TokenAtPos(Next).IsKeyword('sealed') or
      SameText(TokenAtPos(Next).Text, 'abstract') or SameText(TokenAtPos(Next).Text, 'sealed') do
      Inc(Next);
    if SameText(TokenAtPos(Next).Text, 'helper') then
      Exit(True);
    if TokenAtPos(Next).IsKeyword('of') then
      Exit(False);
    if TokenAtPos(Next).IsSymbol('(') then
    begin
      Depth := 0;
      repeat
        Token := TokenAtPos(Next);
        if Token.IsSymbol('(') then
          Inc(Depth)
        else if Token.IsSymbol(')') then
          Dec(Depth);
        Inc(Next);
      until (Depth = 0) or (Next >= Significants.Count);
    end;
    // Vorwärtsdeklaration: TFoo = class; bzw. class(TBasis);
    Result := not TokenAtPos(Next).IsSymbol(';');
  end;

  procedure Push(AKind: TFrameKind);
  begin
    Stack.Push(TFrame.Create(AKind, NewGroup(Index)));
  end;

begin
  Stack := TObjectStack<TFrame>.Create(True);
  Significants := TList<Integer>.Create;
  try
    for Index := 0 to High(FTokens) do
      if Significant(FTokens[Index]) then
        Significants.Add(Index);
    Stack.Push(TFrame.Create(TFrameKind.Root, -1));
    for Position := 0 to Significants.Count - 1 do
    begin
      Index := Significants[Position];
      Top := Stack.Peek;
      if FTokens[Index].IsSymbol(';') then
      begin
        Top.PendingIfs.Clear;
        Continue;
      end;
      if FTokens[Index].Kind <> TPascalTokenKind.Keyword then
        Continue;
      Word := LowerCase(FTokens[Index].Text);
      if Word = 'begin' then
        Push(TFrameKind.Begin_)
      else if Word = 'try' then
        Push(TFrameKind.Try_)
      else if Word = 'case' then
      begin
        // Varianter Teil eines Records: das end des Records schließt ihn.
        if Top.Kind <> TFrameKind.Record_ then
          Push(TFrameKind.Case_);
      end
      else if Word = 'repeat' then
        Push(TFrameKind.Repeat_)
      else if Word = 'asm' then
        Push(TFrameKind.Asm_)
      else if Word = 'record' then
        Push(TFrameKind.Record_)
      else if MatchText(Word, ['class', 'interface', 'dispinterface', 'object']) then
      begin
        if StartsTypeBody(Position) then
          Push(TFrameKind.TypeBody);
      end
      else if Word = 'end' then
      begin
        if (Top.Kind <> TFrameKind.Root) and (Top.Kind <> TFrameKind.Repeat_) then
        begin
          AddTo(Top.Group, Index);
          Stack.Pop;
        end;
      end
      else if Word = 'until' then
      begin
        if Top.Kind = TFrameKind.Repeat_ then
        begin
          AddTo(Top.Group, Index);
          Stack.Pop;
        end;
      end
      else if (Word = 'finally') or (Word = 'except') then
      begin
        if Top.Kind = TFrameKind.Try_ then
          AddTo(Top.Group, Index);
      end
      else if Word = 'of' then
      begin
        if (Top.Kind = TFrameKind.Case_) and (FGroups[Top.Group].Count = 1) then
          AddTo(Top.Group, Index);
      end
      else if Word = 'if' then
        Top.PendingIfs.Add(NewGroup(Index))
      else if Word = 'then' then
      begin
        if (Top.PendingIfs.Count > 0) and (FGroups[Top.PendingIfs.Last].Count = 1) then
          AddTo(Top.PendingIfs.Last, Index);
      end
      else if Word = 'else' then
      begin
        if Top.PendingIfs.Count > 0 then
        begin
          AddTo(Top.PendingIfs.Last, Index);
          Top.PendingIfs.Delete(Top.PendingIfs.Count - 1);
        end
        else if Top.Kind in [TFrameKind.Case_, TFrameKind.Try_] then
          AddTo(Top.Group, Index);
      end;
    end;
  finally
    Significants.Free;
    Stack.Free;
  end;
end;

procedure TGroups.BuildDirectives;
var
  Conditions, Regions: TStack<Integer>;
  Index: Integer;
  Name: string;
begin
  Conditions := TStack<Integer>.Create;
  Regions := TStack<Integer>.Create;
  try
    for Index := 0 to High(FTokens) do
    begin
      if FTokens[Index].Kind <> TPascalTokenKind.Directive then
        Continue;
      Name := TPascalLexer.DirectiveName(FTokens[Index].Text);
      if MatchText(Name, ['IF', 'IFDEF', 'IFNDEF', 'IFOPT']) then
        Conditions.Push(NewGroup(Index))
      else if MatchText(Name, ['ELSEIF', 'ELSE']) then
      begin
        if Conditions.Count > 0 then
          AddTo(Conditions.Peek, Index);
      end
      else if MatchText(Name, ['ENDIF', 'IFEND']) then
      begin
        if Conditions.Count > 0 then
          AddTo(Conditions.Pop, Index);
      end
      else if Name = 'REGION' then
        Regions.Push(NewGroup(Index))
      else if Name = 'ENDREGION' then
      begin
        if Regions.Count > 0 then
          AddTo(Regions.Pop, Index);
      end;
    end;
  finally
    Regions.Free;
    Conditions.Free;
  end;
end;

{ Hilfen }

function TokenAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
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
      (Token.Kind <> TPascalTokenKind.Symbol) then
      Exit(Index);
  end;
  Result := -1;
end;

function IndexOfOffset(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(ATokens) do
    if ATokens[Index].Offset = AOffset then
      Exit(Index);
  Result := -1;
end;

/// <summary>Letztes Schlüsselwort AWord vor AEndOffset ab AStartOffset; -1 wenn keins.</summary>
function LastKeywordBefore(const ATokens: TArray<TPascalToken>; AStartOffset, AEndOffset: Integer;
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

/// <summary>Innerster Knoten einer der Arten, der AOffset enthält; ohne Grenzen zu überschreiten.</summary>
function Innermost(ANode: TSyntaxNode; AOffset: Integer; const AKinds, ABoundaries: TSyntaxKinds): TSyntaxNode;
var
  Pending: TStack<TSyntaxPostOrderEntry>;
  Entry: TSyntaxPostOrderEntry;
  Index: Integer;
  Child: TSyntaxNode;
begin
  // Eigener Stapel statt Rekursion (Bericht M1): Der Weg zum Offset kann durch tiefe Ausdrücke führen.
  // Ein Knoten wird nach seinen Kindern geprüft; eine Grenze beendet wie früher die Suche unter ihren
  // Geschwistern, die Vorfahren werden danach noch geprüft.
  Result := nil;
  Pending := TStack<TSyntaxPostOrderEntry>.Create;
  try
    Pending.Push(TSyntaxPostOrderEntry.Create(ANode, False));
    while Pending.Count > 0 do
    begin
      Entry := Pending.Pop;
      if not Entry.Done then
      begin
        Pending.Push(TSyntaxPostOrderEntry.Create(Entry.Node, True));
        for Index := Entry.Node.ChildCount - 1 downto 0 do
        begin
          Child := Entry.Node[Index];
          if (AOffset >= Child.StartOffset) and (AOffset < Child.EndOffset) then
            Pending.Push(TSyntaxPostOrderEntry.Create(Child, False));
        end;
        Continue;
      end;
      if Entry.Node = ANode then
        Continue;
      if Entry.Node.Kind in AKinds then
        Exit(Entry.Node);
      if Entry.Node.Kind in ABoundaries then
        while (Pending.Count > 0) and not Pending.Peek.Done do
          Pending.Pop;
    end;
  finally
    Pending.Free;
  end;
end;

procedure AddToken(var ARanges: TArray<TTextRange>; const AToken: TPascalToken);
begin
  ARanges := ARanges + [TTextRange.Create(AToken.StartPos, AToken.EndPos)];
end;

function InNested(ARoutine: TSyntaxNode; AOffset: Integer): Boolean;

var
  Node, Child: TSyntaxNode;
  Index: Integer;
begin
  // Schleife statt Rekursion (Bericht M1): dem ersten Kind folgen, das AOffset enthält.
  Result := False;
  Node := ARoutine;
  while Node <> nil do
  begin
    Child := nil;
    for Index := 0 to Node.ChildCount - 1 do
      if (AOffset >= Node[Index].StartOffset) and (AOffset < Node[Index].EndOffset) then
      begin
        Child := Node[Index];
        Break;
      end;
    if (Child <> nil) and (Child.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) then
      Exit(True);
    Node := Child;
  end;
end;

/// <summary>Ausstiegspunkte der Routine bzw. anonymen Methode ARoutine.</summary>
function ExitPoints(ATree: TSyntaxTree; ARoutine: TSyntaxNode; const AKeywords: TArray<string>): TArray<TTextRange>;
var
  Tokens: TArray<TPascalToken>;
  Block: TSyntaxNode;
  Index, EndToken: Integer;
  Token: TPascalToken;
begin
  Result := nil;
  Tokens := ATree.Tokens;
  Block := ARoutine.FindChild(TSyntaxKind.Block);
  if Block = nil then
    Exit;
  for Index := 0 to High(Tokens) do
  begin
    Token := Tokens[Index];
    if Token.Offset >= Block.EndOffset then
      Break;
    if (Token.Offset < Block.StartOffset) or not (Token.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) or
      not MatchText(Token.Text, AKeywords) then
      Continue;
    // Foo.Exit ist kein Ausstieg.
    if (Index > 0) and Tokens[Index - 1].IsSymbol('.') then
      Continue;
    if not InNested(Block, Token.Offset) then
      AddToken(Result, Token);
  end;
  EndToken := LastKeywordBefore(Tokens, Block.StartOffset, Block.EndOffset, 'end');
  if EndToken >= 0 then
    AddToken(Result, Tokens[EndToken]);
end;

/// <summary>Kopf (und do) sowie Ende der Schleife ALoop.</summary>
function LoopParts(ATree: TSyntaxTree; ALoop: TSyntaxNode): TArray<TTextRange>;
var
  Tokens: TArray<TPascalToken>;
  Index: Integer;
  Body: TSyntaxNode;
begin
  Result := nil;
  Tokens := ATree.Tokens;
  Index := IndexOfOffset(Tokens, ALoop.StartOffset);
  if Index >= 0 then
    AddToken(Result, Tokens[Index]);
  if ALoop.Kind = TSyntaxKind.RepeatStatement then
  begin
    Index := LastKeywordBefore(Tokens, ALoop.StartOffset, ALoop.EndOffset, 'until');
    if Index >= 0 then
      AddToken(Result, Tokens[Index]);
    Exit;
  end;
  if ALoop.ChildCount = 0 then
    Exit;
  Body := ALoop[ALoop.ChildCount - 1];
  // do vor dem Rumpf
  Index := LastKeywordBefore(Tokens, ALoop.StartOffset, Body.StartOffset, 'do');
  if Index >= 0 then
    AddToken(Result, Tokens[Index]);
  if Body.Kind = TSyntaxKind.Block then
  begin
    Index := LastKeywordBefore(Tokens, Body.StartOffset, Body.EndOffset, 'end');
    if Index >= 0 then
      AddToken(Result, Tokens[Index]);
  end;
end;

/// <summary>RoutineDecl mit Rumpf, in deren Kopf AOffset liegt.</summary>
function RoutineOfHeader(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
var
  Root: TSyntaxNode;
  Offset: Integer;
begin
  Root := ANode;
  Offset := AOffset;
  // Search statt Rekursion (Bericht M1); unter ANode nur Knoten, die AOffset enthalten.
  Result := ANode.Search(
    function(ACandidate: TSyntaxNode): TSyntaxSearchStep
    var
      Header: TSyntaxNode;
    begin
      if (ACandidate <> Root) and ((Offset < ACandidate.StartOffset) or (Offset >= ACandidate.EndOffset)) then
        Exit(TSyntaxSearchStep.Skip);
      Result := TSyntaxSearchStep.Descend;
      if (ACandidate.Kind = TSyntaxKind.RoutineDecl) and (ACandidate.FindChild(TSyntaxKind.Block) <> nil) then
      begin
        Header := ACandidate.FindChild(TSyntaxKind.RoutineHeader);
        if (Header <> nil) and (Offset >= Header.StartOffset) and (Offset < Header.EndOffset) then
          Result := TSyntaxSearchStep.Found;
      end;
    end);
end;

function ShortName(const AName: string): string;
begin
  Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

function ByPosition(const ARanges: TArray<TTextRange>): TArray<TTextRange>;
var
  List: TList<TTextRange>;
  Range: TTextRange;
  Index: Integer;
  Known: Boolean;
begin
  List := TList<TTextRange>.Create(TComparer<TTextRange>.Construct(
    function(const A, B: TTextRange): Integer
    begin
      Result := A.StartPos.Line - B.StartPos.Line;
      if Result = 0 then
        Result := A.StartPos.Character - B.StartPos.Character;
    end));
  try
    for Range in ARanges do
    begin
      Known := False;
      for Index := 0 to List.Count - 1 do
        Known := Known or (List[Index].StartPos = Range.StartPos);
      if not Known then
        List.Add(Range);
    end;
    List.Sort;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

{ TKeywordHighlights }

class function TKeywordHighlights.Find(ATree: TSyntaxTree; const APosition: TTextPosition;
  const ASettings: THighlightSettings; out ARanges: TArray<TTextRange>): Boolean;
const
  Loops = [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
    TSyntaxKind.RepeatStatement];
  Routines = [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod];
var
  Tokens: TArray<TPascalToken>;
  Index, Member, EndToken: Integer;
  Token: TPascalToken;
  Groups: TGroups;
  Members: TArray<Integer>;
  Routine, Loop, Block: TSyntaxNode;
begin
  ARanges := nil;
  Result := False;
  if ATree = nil then
    Exit;
  Tokens := ATree.Tokens;
  Index := TokenAt(Tokens, APosition);
  if Index < 0 then
    Exit;
  Token := Tokens[Index];
  // Ausstiegspunkte: Exit, raise, Abort, Halt …
  if (Token.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
    MatchText(Token.Text, ASettings.ExitKeywords) and not ((Index > 0) and Tokens[Index - 1].IsSymbol('.')) then
  begin
    Routine := Innermost(ATree.Root, Token.Offset, Routines, []);
    if Routine = nil then
      Exit;
    if ASettings.ExitPoints then
      ARanges := ByPosition(ExitPoints(ATree, Routine, ASettings.ExitKeywords));
    Exit(True);
  end;
  // Break und Continue: die Schleife
  if (Token.Kind = TPascalTokenKind.Identifier) and MatchText(Token.Text, ['Break', 'Continue']) then
  begin
    Loop := Innermost(ATree.Root, Token.Offset, Loops, Routines);
    if Loop = nil then
      Exit;
    if ASettings.ExitPoints then
    begin
      ARanges := LoopParts(ATree, Loop);
      AddToken(ARanges, Token);
      ARanges := ByPosition(ARanges);
    end;
    Exit(True);
  end;
  // Routinenname im Kopf einer Implementierung: Ausstiegspunkte
  if Token.Kind = TPascalTokenKind.Identifier then
  begin
    Routine := RoutineOfHeader(ATree.Root, Token.Offset);
    if (Routine = nil) or not SameText(Token.Text, ShortName(Routine.Name)) or not ASettings.ExitPoints then
      Exit;
    ARanges := ByPosition(ExitPoints(ATree, Routine, ASettings.ExitKeywords));
    Exit(True);
  end;
  if Token.Kind = TPascalTokenKind.Directive then
  begin
    if TPascalLexer.DirectiveName(Token.Text) = '' then
      Exit;
    Groups := TGroups.Create(Tokens, True);
    try
      if not Groups.GroupTokens(Index, Members) then
        Exit;
      Result := True;
      if ASettings.Directives then
        for Member in Members do
          AddToken(ARanges, Tokens[Member]);
    finally
      Groups.Free;
    end;
    ARanges := ByPosition(ARanges);
    Exit;
  end;
  if Token.Kind <> TPascalTokenKind.Keyword then
    Exit;
  // procedure/function/… einer Implementierung: Kopf, begin und end
  if MatchText(Token.Text, RoutineKeywords) then
  begin
    Routine := RoutineOfHeader(ATree.Root, Token.Offset);
    if Routine = nil then
      Exit;
    Result := True;
    if not ASettings.BlockPairs then
      Exit;
    AddToken(ARanges, Token);
    Block := Routine.FindChild(TSyntaxKind.Block);
    Index := IndexOfOffset(Tokens, Block.StartOffset);
    if Index >= 0 then
      AddToken(ARanges, Tokens[Index]);
    EndToken := LastKeywordBefore(Tokens, Block.StartOffset, Block.EndOffset, 'end');
    if EndToken >= 0 then
      AddToken(ARanges, Tokens[EndToken]);
    ARanges := ByPosition(ARanges);
    Exit;
  end;
  if not MatchText(Token.Text, BlockKeywords) then
    Exit;
  Result := True;
  if not ASettings.BlockPairs then
    Exit;
  Groups := TGroups.Create(Tokens, False);
  try
    if Groups.GroupTokens(Index, Members) then
      for Member in Members do
        AddToken(ARanges, Tokens[Member])
    else
      // Ohne Gegenstück nur das Schlüsselwort selbst.
      AddToken(ARanges, Token);
  finally
    Groups.Free;
  end;
  ARanges := ByPosition(ARanges);
end;

end.
