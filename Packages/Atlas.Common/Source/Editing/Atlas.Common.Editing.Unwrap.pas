unit Atlas.Common.Editing.Unwrap;

// Umschließung entfernen (#657) ohne Protokollbezug: Zu einer Cursorstelle
// liefert Candidates die umschließenden Konstrukte, das innerste zuerst,
// höchstens fünf. Jedes Konstrukt hat eine oder mehrere Varianten, die je
// einen Edit (das ganze Konstrukt durch den Rumpf ersetzen) und die Bereiche
// für die Vorschau (bleibt, entfällt) tragen.
//   - begin … end (nicht der Rumpf einer Routine oder anonymen Methode),
//     if … then [… else], for/for-in/while … do, repeat … until, with … do,
//     try … finally (finally-Teil behalten oder verwerfen), try … except.
//   - {$IFDEF}/{$IFNDEF}/{$IF}/{$IFOPT} … {$ENDIF}/{$IFEND} je Zweig und
//     {$REGION} … {$ENDREGION}: nur die Direktivzeilen entfallen.
// Der Rumpf rückt auf die Höhe des Konstrukts aus; steht das Konstrukt als
// einzelne Anweisung (hinter then, do, case-Marke …), auf die Höhe des
// übergeordneten Kopfs plus eine Stufe. Bleiben dort mehrere Anweisungen,
// kommen sie in begin … end. Semikolons werden so angepasst, dass das
// Ergebnis parst (vor else keins, hinter jeder Anweisung eins). Kommentare im
// Rumpf bleiben stehen. Bei with liefert TUnwrapOptions.ResolveWith die Edits
// von „with auflösen“ (#50), damit sich die Bedeutung nicht ändert.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  {$SCOPEDENUMS ON}
  TUnwrapKind = (BeginEnd, TryFinally, TryExcept, IfThen, WithDo, ForDo, WhileDo, RepeatUntil, IfDef, Region);

  /// <summary>Was die Variante behält: den Rumpf, Rumpf und finally-Teil, nur den Rumpf ohne finally, den
  /// then- oder else-Zweig oder einen weiteren {$ELSEIF}-Zweig (TUnwrapVariant.Branch).</summary>
  TUnwrapVariantKind = (Body, KeepFinally, DropFinally, ThenBranch, ElseBranch, Branch);

  /// <summary>Hinweis in der Liste: mehrere raise im except-Teil, Schleifenvariable bleibt stehen, with ist nicht
  /// auflösbar (dann ohne Varianten).</summary>
  TUnwrapNote = (None, MultipleRaise, LoopVariable, WithUnresolved);
  {$SCOPEDENUMS OFF}

  TUnwrapVariant = record
    Kind: TUnwrapVariantKind;
    /// <summary>Nummer des Zweigs ab 0 bei Direktiven, sonst 0.</summary>
    Branch: Integer;
    Edits: TArray<TTextEdit>;
    /// <summary>Bereiche, die bleiben (Vorschau grün).</summary>
    Keep: TArray<TTextRange>;
    /// <summary>Bereiche, die entfallen (Vorschau rot, durchgestrichen).</summary>
    Remove: TArray<TTextRange>;
  end;

  TUnwrapCandidate = record
    Kind: TUnwrapKind;
    Range: TTextRange;
    Note: TUnwrapNote;
    /// <summary>Zum Hinweis: Anzahl raise, Name der Schleifenvariable oder Grund.</summary>
    NoteText: string;
    Variants: TArray<TUnwrapVariant>;
  end;

  /// <summary>Edits von „with auflösen“ für AWith; False mit Grund in AReason.</summary>
  TUnwrapWithResolver = reference to function(AWith: TSyntaxNode; out AEdits: TArray<TTextEdit>;
    out AReason: string): Boolean;

  TUnwrapOptions = record
    /// <summary>Breite einer Einrückungsstufe in Leerzeichen.</summary>
    IndentWidth: Integer;
    /// <summary>Höchstzahl der gelieferten Konstrukte.</summary>
    MaxLevels: Integer;
    /// <summary>nil = with ist nicht auflösbar.</summary>
    ResolveWith: TUnwrapWithResolver;
    class function Default: TUnwrapOptions; static;
  end;

  TUnwrap = class
  public
    /// <summary>Umschließende Konstrukte an APosition, das innerste zuerst.</summary>
    class function Candidates(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const AOptions: TUnwrapOptions): TArray<TUnwrapCandidate>; static;
    /// <summary>Kennungen für das Protokoll, z. B. tryFinally, keepFinally, loopVariable.</summary>
    class function KindName(AKind: TUnwrapKind): string; static;
    class function VariantName(AKind: TUnwrapVariantKind): string; static;
    class function NoteName(ANote: TUnwrapNote): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.RoutineBody;

const
  KindNames: array[TUnwrapKind] of string = ('beginEnd', 'tryFinally', 'tryExcept', 'ifThen', 'withDo', 'forDo',
    'whileDo', 'repeatUntil', 'ifdef', 'region');
  VariantNames: array[TUnwrapVariantKind] of string = ('body', 'keepFinally', 'dropFinally', 'then', 'else',
    'branch');
  NoteNames: array[TUnwrapNote] of string = ('', 'multipleRaise', 'loopVariable', 'withUnresolved');

  /// <summary>Knoten, die genau eine Anweisung tragen: Bleiben dort mehrere, kommen sie in begin … end.</summary>
  SingleStatementParents = [TSyntaxKind.IfStatement, TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement,
    TSyntaxKind.WhileStatement, TSyntaxKind.WithStatement, TSyntaxKind.CaseItem, TSyntaxKind.ExceptionHandler,
    TSyntaxKind.LabeledStatement];

  /// <summary>Knoten, in denen ein begin … end als Anweisung steht.</summary>
  StatementParents = SingleStatementParents + [TSyntaxKind.Block, TSyntaxKind.RepeatStatement,
    TSyntaxKind.TryStatement, TSyntaxKind.FinallyBlock, TSyntaxKind.ExceptBlock, TSyntaxKind.CaseElse];

type
  /// <summary>Behaltener Text von StartOffset bis EndOffset (ausschließlich); beginnt immer hinter einem
  /// Trennwort (begin, then, do, try, finally, repeat, else, Direktive).</summary>
  TSegment = record
    StartOffset: Integer;
    EndOffset: Integer;
    class function Create(AStart, AEnd: Integer): TSegment; static;
  end;

  TOffsetEdit = record
    Offset: Integer;
    Length: Integer;
    Text: string;
  end;

  TBuilder = record
    Text: string;
    Tokens: TArray<TPascalToken>;
    Table: TLineTable;
    LineBreak: string;
    Options: TUnwrapOptions;
    function IsCode(AIndex: Integer): Boolean;
    function TokenEnd(AIndex: Integer): Integer;
    /// <summary>Erstes Code-Token (kein Kommentar, keine Direktive) ab AOffset; -1 ohne.</summary>
    function NextCode(AOffset: Integer): Integer;
    /// <summary>Letztes Code-Token, das bis AOffset endet; -1 ohne.</summary>
    function PrevCode(AOffset: Integer): Integer;
    function IsKeyword(AIndex: Integer; const AWord: string): Boolean;
    function RangeOf(AStart, AEnd: Integer): TTextRange;
    function LineOf(AOffset: Integer): Integer;
    function LineIndent(ALine: Integer): Integer;
    function IsBlank(AStart, AEnd: Integer): Boolean;
    /// <summary>Nicht leere Stücke je Zeile zwischen AStart und AEnd.</summary>
    procedure AddPieces(AStart, AEnd: Integer; var ARanges: TArray<TTextRange>);
    /// <summary>Behaltener Teil eines Zweigs hinter dem Trennwort, das bei ADelimiterEnd endet; ein begin … end
    /// wird zu seinem Inneren. ABranch nil = leerer Zweig.</summary>
    function BranchSegment(ADelimiterEnd: Integer; ABranch: TSyntaxNode; out ACount: Integer): TSegment;
    /// <summary>Erstes Kind von ANode, das ab AOffset beginnt; nil ohne.</summary>
    function ChildFrom(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
    /// <summary>Offset hinter dem ersten AWord auf Klammertiefe 0 ab AOffset bis AEnd; -1 ohne.</summary>
    function KeywordEnd(AOffset, AEnd: Integer; const AWord: string): Integer;
    function SegmentText(const ASegment: TSegment; const AEdits: TArray<TOffsetEdit>): string;
    /// <summary>Ersetzt das Konstrukt AStart..AEnd durch die Segmente. ACount = Zahl der Anweisungen darin;
    /// ADirective = Direktiven (keine Semikolons, keine neue Einrückung).</summary>
    function Compose(ANode: TSyntaxNode; AStart, AEnd: Integer; const ASegments: TArray<TSegment>;
      ACount: Integer; ADirective: Boolean): TUnwrapVariant;
    procedure AddStatement(ANode: TSyntaxNode; var ACandidates: TArray<TUnwrapCandidate>);
    procedure AddDirectives(AOffset: Integer; var ACandidates: TArray<TUnwrapCandidate>);
  end;

function WithKind(const AValue: TUnwrapVariant; AKind: TUnwrapVariantKind; ABranch: Integer): TUnwrapVariant;
begin
  Result := AValue;
  Result.Kind := AKind;
  Result.Branch := ABranch;
end;

function CountRaises(ANode: TSyntaxNode): Integer;
var
  Index: Integer;
begin
  Result := 0;
  if ANode = nil then
    Exit;
  if ANode.Kind = TSyntaxKind.RaiseStatement then
    Inc(Result);
  // Ein raise in einer anonymen Methode gehört nicht zum except-Teil.
  if ANode.Kind = TSyntaxKind.AnonymousMethod then
    Exit;
  for Index := 0 to ANode.ChildCount - 1 do
    Inc(Result, CountRaises(ANode[Index]));
end;

{ TUnwrapOptions }

class function TUnwrapOptions.Default: TUnwrapOptions;
begin
  Result.IndentWidth := 2;
  Result.MaxLevels := 5;
  Result.ResolveWith := nil;
end;

{ TSegment }

class function TSegment.Create(AStart, AEnd: Integer): TSegment;
begin
  Result.StartOffset := AStart;
  Result.EndOffset := AEnd;
  if Result.EndOffset < Result.StartOffset then
    Result.EndOffset := Result.StartOffset;
end;

{ TBuilder }

function TBuilder.IsCode(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(Tokens)) and
    not (Tokens[AIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]);
end;

function TBuilder.TokenEnd(AIndex: Integer): Integer;
begin
  Result := Tokens[AIndex].Offset + Length(Tokens[AIndex].Text);
end;

function TBuilder.NextCode(AOffset: Integer): Integer;
begin
  Result := TRoutineBody.TokenAt(Tokens, AOffset);
  while (Result <= High(Tokens)) and not IsCode(Result) do
    Inc(Result);
  if Result > High(Tokens) then
    Result := -1;
end;

function TBuilder.PrevCode(AOffset: Integer): Integer;
begin
  Result := TRoutineBody.TokenAt(Tokens, AOffset) - 1;
  while (Result >= 0) and (not IsCode(Result) or (TokenEnd(Result) > AOffset)) do
    Dec(Result);
end;

function TBuilder.IsKeyword(AIndex: Integer; const AWord: string): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(Tokens)) and Tokens[AIndex].IsKeyword(AWord);
end;

function TBuilder.RangeOf(AStart, AEnd: Integer): TTextRange;
begin
  Result := TTextRange.Create(Table.PositionAt(AStart), Table.PositionAt(AEnd));
end;

function TBuilder.LineOf(AOffset: Integer): Integer;
begin
  Result := Table.PositionAt(AOffset).Line;
end;

function TBuilder.LineIndent(ALine: Integer): Integer;
begin
  Result := TTextLines.IndentLength(Copy(Text, Table.LineStart(ALine) + 1,
    Table.LineContentEnd(ALine) - Table.LineStart(ALine)));
end;

function TBuilder.IsBlank(AStart, AEnd: Integer): Boolean;
var
  Index: Integer;
begin
  Result := Trim(Copy(Text, AStart + 1, AEnd - AStart)) = '';
  if not Result then
    Exit;
  for Index := AStart + 1 to AEnd do
    if CharInSet(Text[Index], [#10, #13]) then
      Exit(False);
end;

procedure TBuilder.AddPieces(AStart, AEnd: Integer; var ARanges: TArray<TTextRange>);
var
  Line, From, Till: Integer;
begin
  if AEnd <= AStart then
    Exit;
  for Line := LineOf(AStart) to LineOf(AEnd) do
  begin
    From := Table.LineStart(Line);
    if From < AStart then
      From := AStart;
    Till := Table.LineContentEnd(Line);
    if Till > AEnd then
      Till := AEnd;
    while (From < Till) and CharInSet(Text[From + 1], [' ', #9]) do
      Inc(From);
    while (Till > From) and CharInSet(Text[Till], [' ', #9]) do
      Dec(Till);
    if Till > From then
      ARanges := ARanges + [RangeOf(From, Till)];
  end;
end;

function TBuilder.ChildFrom(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to ANode.ChildCount - 1 do
    if ANode[Index].StartOffset >= AOffset then
      Exit(ANode[Index]);
end;

function TBuilder.KeywordEnd(AOffset, AEnd: Integer; const AWord: string): Integer;
var
  Index, Depth: Integer;
begin
  Result := -1;
  Depth := 0;
  Index := NextCode(AOffset);
  while (Index >= 0) and (Index <= High(Tokens)) and (Tokens[Index].Offset < AEnd) do
  begin
    if IsCode(Index) then
    begin
      if Tokens[Index].IsSymbol('(') or Tokens[Index].IsSymbol('[') then
        Inc(Depth)
      else if Tokens[Index].IsSymbol(')') or Tokens[Index].IsSymbol(']') then
        Dec(Depth)
      else if (Depth = 0) and Tokens[Index].IsKeyword(AWord) then
        Exit(TokenEnd(Index));
    end;
    Inc(Index);
  end;
end;

function TBuilder.BranchSegment(ADelimiterEnd: Integer; ABranch: TSyntaxNode; out ACount: Integer): TSegment;
var
  First, Last: Integer;
begin
  ACount := 0;
  if ABranch = nil then
    Exit(TSegment.Create(ADelimiterEnd, ADelimiterEnd));
  if ABranch.Kind = TSyntaxKind.Block then
  begin
    First := NextCode(ABranch.StartOffset);
    Last := PrevCode(ABranch.EndOffset);
    if IsKeyword(First, 'begin') and IsKeyword(Last, 'end') and (First < Last) then
    begin
      ACount := ABranch.ChildCount;
      Exit(TSegment.Create(TokenEnd(First), Tokens[Last].Offset));
    end;
  end;
  ACount := 1;
  Result := TSegment.Create(ADelimiterEnd, ABranch.EndOffset);
end;

function TBuilder.SegmentText(const ASegment: TSegment; const AEdits: TArray<TOffsetEdit>): string;
var
  Index: Integer;
begin
  Result := Copy(Text, ASegment.StartOffset + 1, ASegment.EndOffset - ASegment.StartOffset);
  // Die Edits sind nach Offset absteigend sortiert.
  for Index := 0 to High(AEdits) do
    if (AEdits[Index].Offset >= ASegment.StartOffset) and (AEdits[Index].Offset <= ASegment.EndOffset) then
      Result := Copy(Result, 1, AEdits[Index].Offset - ASegment.StartOffset) + AEdits[Index].Text +
        Copy(Result, AEdits[Index].Offset - ASegment.StartOffset + AEdits[Index].Length + 1, MaxInt);
end;

function TBuilder.Compose(ANode: TSyntaxNode; AStart, AEnd: Integer; const ASegments: TArray<TSegment>;
  ACount: Integer; ADirective: Boolean): TUnwrapVariant;
var
  Edits: TArray<TOffsetEdit>;
  Edit: TOffsetEdit;
  Kept, Body, Split: TArray<string>;
  Partial: TArray<Boolean>;
  Next, Last, LastWithCode, Index, Line, First, Tail, MinIndent, Outer, Inner, LineS, LineE, R1, R2,
    Ending: Integer;
  HadSemicolon, BeforeElse, SingleParent, Wrap, AtStart, AtEnd: Boolean;
  Segment: TSegment;
  NewText, Prefix, Suffix, Content: string;
begin
  Result := Default(TUnwrapVariant);
  Ending := AEnd;
  HadSemicolon := False;
  BeforeElse := False;
  if not ADirective then
  begin
    Next := NextCode(AEnd);
    if (Next >= 0) and Tokens[Next].IsSymbol(';') then
    begin
      HadSemicolon := True;
      Ending := TokenEnd(Next);
    end
    else
      BeforeElse := IsKeyword(Next, 'else');
  end;
  SingleParent := not ADirective and (ANode <> nil) and (ANode.Parent <> nil) and
    (ANode.Parent.Kind in SingleStatementParents);
  Wrap := SingleParent and (ACount <> 1);

  // Semikolons: hinter jeder Anweisung eins, am Ende wie vorher am Konstrukt, vor else keins.
  Edits := nil;
  if not ADirective then
  begin
    LastWithCode := -1;
    for Index := 0 to High(ASegments) do
    begin
      Last := PrevCode(ASegments[Index].EndOffset);
      if (Last >= 0) and (Tokens[Last].Offset >= ASegments[Index].StartOffset) then
        LastWithCode := Index;
    end;
    for Index := High(ASegments) downto 0 do
    begin
      Last := PrevCode(ASegments[Index].EndOffset);
      if (Last < 0) or (Tokens[Last].Offset < ASegments[Index].StartOffset) then
        Continue;
      Edit := Default(TOffsetEdit);
      Edit.Offset := -1;
      if (Index < LastWithCode) or (Wrap and (Index = LastWithCode)) then
      begin
        if not Tokens[Last].IsSymbol(';') then
        begin
          Edit.Offset := TokenEnd(Last);
          Edit.Text := ';';
        end;
      end
      else if HadSemicolon and not Tokens[Last].IsSymbol(';') then
      begin
        Edit.Offset := TokenEnd(Last);
        Edit.Text := ';';
      end
      else if BeforeElse and Tokens[Last].IsSymbol(';') then
      begin
        Edit.Offset := Tokens[Last].Offset;
        Edit.Length := 1;
      end;
      if Edit.Offset >= 0 then
        Edits := Edits + [Edit];
    end;
  end;

  // Behaltene Zeilen: die erste Zeile eines Segments ist der Rest hinter dem Trennwort.
  Kept := nil;
  Partial := nil;
  for Segment in ASegments do
  begin
    Split := TTextLines.SplitLines(SegmentText(Segment, Edits));
    First := 0;
    Tail := High(Split);
    if First <= Tail then
      Split[0] := Trim(Split[0]);
    for Index := 0 to High(Split) do
      Split[Index] := TrimRight(Split[Index]);
    while (First <= Tail) and (Trim(Split[First]) = '') do
      Inc(First);
    while (Tail >= First) and (Trim(Split[Tail]) = '') do
      Dec(Tail);
    for Index := First to Tail do
    begin
      Kept := Kept + [Split[Index]];
      Partial := Partial + [Index = 0];
    end;
  end;

  // Gemeinsame Einrückung der vollen Zeilen.
  MinIndent := -1;
  for Index := 0 to High(Kept) do
    if not Partial[Index] and (Trim(Kept[Index]) <> '') and
      ((MinIndent < 0) or (TTextLines.IndentLength(Kept[Index]) < MinIndent)) then
      MinIndent := TTextLines.IndentLength(Kept[Index]);
  if MinIndent < 0 then
    MinIndent := 0;

  LineS := LineOf(AStart);
  LineE := LineOf(Ending);
  if SingleParent then
    Outer := LineIndent(LineOf(ANode.Parent.StartOffset))
  else
    Outer := LineIndent(LineS);
  Inner := Outer;
  if SingleParent then
    Inner := Outer + Options.IndentWidth;
  if Wrap then
    Inner := Outer + Options.IndentWidth;

  Body := nil;
  if Wrap then
    Body := Body + [StringOfChar(' ', Outer) + 'begin'];
  for Index := 0 to High(Kept) do
  begin
    if Kept[Index] = '' then
      Content := ''
    else if ADirective and not Partial[Index] then
      Content := Kept[Index]
    else if ADirective then
      Content := StringOfChar(' ', MinIndent) + Kept[Index]
    else if Partial[Index] then
      Content := StringOfChar(' ', Inner) + Kept[Index]
    else
      Content := StringOfChar(' ', Inner) + Copy(Kept[Index], MinIndent + 1, MaxInt);
    Body := Body + [Content];
  end;
  if Wrap then
  begin
    if HadSemicolon then
      Body := Body + [StringOfChar(' ', Outer) + 'end;']
    else
      Body := Body + [StringOfChar(' ', Outer) + 'end'];
  end;

  AtStart := IsBlank(Table.LineStart(LineS), AStart);
  AtEnd := IsBlank(Ending, Table.LineContentEnd(LineE));
  Prefix := '';
  Suffix := '';
  if AtStart and AtEnd then
  begin
    // Ganze Zeilen ersetzen.
    R1 := Table.LineStart(LineS);
    if LineE + 1 < Table.LineCount then
    begin
      R2 := Table.LineStart(LineE + 1);
      if Body <> nil then
        Suffix := LineBreak;
    end
    else
      R2 := Table.LineContentEnd(LineE);
    NewText := '';
    for Line := 0 to High(Body) do
    begin
      if Line > 0 then
        NewText := NewText + LineBreak;
      NewText := NewText + Body[Line];
    end;
    NewText := NewText + Suffix;
  end
  else if Body = nil then
  begin
    R1 := AStart;
    R2 := Ending;
    NewText := '';
  end
  else if (LineS = LineE) and (Length(Body) = 1) then
  begin
    // Einzeilig im Fließtext.
    R1 := AStart;
    R2 := Ending;
    NewText := Trim(Body[0]);
  end
  else
  begin
    R1 := AStart;
    if AtStart then
      R1 := Table.LineStart(LineS)
    else
    begin
      while (R1 > 0) and CharInSet(Text[R1], [' ', #9]) do
        Dec(R1);
      Prefix := LineBreak;
    end;
    R2 := Ending;
    if AtEnd then
    begin
      if LineE + 1 < Table.LineCount then
      begin
        R2 := Table.LineStart(LineE + 1);
        Suffix := LineBreak;
      end
      else
        R2 := Table.LineContentEnd(LineE);
    end
    else
    begin
      while (R2 < Length(Text)) and CharInSet(Text[R2 + 1], [' ', #9]) do
        Inc(R2);
      Suffix := LineBreak + StringOfChar(' ', LineIndent(LineS));
    end;
    NewText := Prefix;
    for Line := 0 to High(Body) do
    begin
      if Line > 0 then
        NewText := NewText + LineBreak;
      NewText := NewText + Body[Line];
    end;
    NewText := NewText + Suffix;
  end;
  Result.Edits := [TTextEdit.Create(RangeOf(R1, R2), NewText)];

  // Vorschau: Segmente bleiben, der Rest des Konstrukts entfällt; das Semikolon dahinter bleibt stehen.
  Next := AStart;
  for Segment in ASegments do
  begin
    AddPieces(Next, Segment.StartOffset, Result.Remove);
    AddPieces(Segment.StartOffset, Segment.EndOffset, Result.Keep);
    if Segment.EndOffset > Next then
      Next := Segment.EndOffset;
  end;
  AddPieces(Next, AEnd, Result.Remove);
end;

procedure TBuilder.AddStatement(ANode: TSyntaxNode; var ACandidates: TArray<TUnwrapCandidate>);
var
  Candidate: TUnwrapCandidate;
  Segment, BodySegment, FinallySegment: TSegment;
  Count, BodyCount, Index, First, Last, Delimiter: Integer;
  Branch, ElseBranch, Handler: TSyntaxNode;
  WithEdits: TArray<TTextEdit>;
  Reason: string;
begin
  Candidate := Default(TUnwrapCandidate);
  Candidate.Range := RangeOf(ANode.StartOffset, ANode.EndOffset);
  case ANode.Kind of
    TSyntaxKind.Block:
      begin
        if (ANode.Parent = nil) or not (ANode.Parent.Kind in StatementParents) then
          Exit;
        Segment := BranchSegment(ANode.StartOffset, ANode, Count);
        if (Count <> ANode.ChildCount) or (Segment.StartOffset = ANode.StartOffset) then
          Exit;
        // Hinter then/do ergäbe ein Block mit mehreren Anweisungen wieder begin … end.
        if (ANode.Parent.Kind in SingleStatementParents) and (Count <> 1) then
          Exit;
        Candidate.Kind := TUnwrapKind.BeginEnd;
        Candidate.Variants := [WithKind(Compose(ANode, ANode.StartOffset, ANode.EndOffset, [Segment], Count, False),
          TUnwrapVariantKind.Body, 0)];
      end;
    TSyntaxKind.TryStatement:
      begin
        First := NextCode(ANode.StartOffset);
        Last := PrevCode(ANode.EndOffset);
        if not IsKeyword(First, 'try') or not IsKeyword(Last, 'end') then
          Exit;
        Handler := ANode.FindChild(TSyntaxKind.FinallyBlock);
        if Handler = nil then
          Handler := ANode.FindChild(TSyntaxKind.ExceptBlock);
        if Handler = nil then
          Exit;
        BodyCount := 0;
        for Index := 0 to ANode.ChildCount - 1 do
          if not (ANode[Index].Kind in [TSyntaxKind.FinallyBlock, TSyntaxKind.ExceptBlock]) then
            Inc(BodyCount);
        BodySegment := TSegment.Create(TokenEnd(First), Handler.StartOffset);
        if Handler.Kind = TSyntaxKind.FinallyBlock then
        begin
          Candidate.Kind := TUnwrapKind.TryFinally;
          Delimiter := NextCode(Handler.StartOffset);
          if not IsKeyword(Delimiter, 'finally') then
            Exit;
          FinallySegment := TSegment.Create(TokenEnd(Delimiter), Tokens[Last].Offset);
          Candidate.Variants := [
            WithKind(Compose(ANode, ANode.StartOffset, ANode.EndOffset, [BodySegment, FinallySegment],
              BodyCount + Handler.ChildCount, False), TUnwrapVariantKind.KeepFinally, 0),
            WithKind(Compose(ANode, ANode.StartOffset, ANode.EndOffset, [BodySegment], BodyCount, False),
              TUnwrapVariantKind.DropFinally, 0)];
        end
        else
        begin
          Candidate.Kind := TUnwrapKind.TryExcept;
          Count := CountRaises(Handler);
          if Count > 1 then
          begin
            Candidate.Note := TUnwrapNote.MultipleRaise;
            Candidate.NoteText := IntToStr(Count);
          end;
          Candidate.Variants := [WithKind(Compose(ANode, ANode.StartOffset, ANode.EndOffset, [BodySegment],
            BodyCount, False), TUnwrapVariantKind.Body, 0)];
        end;
      end;
    TSyntaxKind.IfStatement:
      begin
        if ANode.ChildCount < 1 then
          Exit;
        Delimiter := NextCode(ANode[0].EndOffset);
        if not IsKeyword(Delimiter, 'then') then
          Exit;
        Branch := ChildFrom(ANode, TokenEnd(Delimiter));
        ElseBranch := nil;
        First := -1;
        if IsKeyword(NextCode(TokenEnd(Delimiter)), 'else') then
        begin
          // if … then else …: leerer then-Zweig.
          First := NextCode(TokenEnd(Delimiter));
          ElseBranch := Branch;
          Branch := nil;
        end
        else if (Branch <> nil) and IsKeyword(NextCode(Branch.EndOffset), 'else') and
          (Tokens[NextCode(Branch.EndOffset)].Offset < ANode.EndOffset) then
        begin
          First := NextCode(Branch.EndOffset);
          ElseBranch := ChildFrom(ANode, TokenEnd(First));
        end;
        Candidate.Kind := TUnwrapKind.IfThen;
        Segment := BranchSegment(TokenEnd(Delimiter), Branch, Count);
        Candidate.Variants := [WithKind(Compose(ANode, ANode.StartOffset, ANode.EndOffset, [Segment], Count, False),
          TUnwrapVariantKind.ThenBranch, 0)];
        if First >= 0 then
        begin
          Segment := BranchSegment(TokenEnd(First), ElseBranch, Count);
          Candidate.Variants := Candidate.Variants + [WithKind(Compose(ANode, ANode.StartOffset, ANode.EndOffset,
            [Segment], Count, False), TUnwrapVariantKind.ElseBranch, 0)];
        end;
      end;
    TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
    TSyntaxKind.WithStatement:
      begin
        Delimiter := KeywordEnd(ANode.StartOffset, ANode.EndOffset, 'do');
        if Delimiter < 0 then
          Exit;
        Segment := BranchSegment(Delimiter, ChildFrom(ANode, Delimiter), Count);
        case ANode.Kind of
          TSyntaxKind.WhileStatement:
            Candidate.Kind := TUnwrapKind.WhileDo;
          TSyntaxKind.WithStatement:
            Candidate.Kind := TUnwrapKind.WithDo;
        else
          Candidate.Kind := TUnwrapKind.ForDo;
          Candidate.Note := TUnwrapNote.LoopVariable;
          Candidate.NoteText := ANode.Name;
        end;
        Candidate.Variants := [WithKind(Compose(ANode, ANode.StartOffset, ANode.EndOffset, [Segment], Count, False),
          TUnwrapVariantKind.Body, 0)];
        if Candidate.Kind = TUnwrapKind.WithDo then
        begin
          // Die Bedeutung bleibt nur mit ausgeschriebenen Bezügen gleich.
          WithEdits := nil;
          Reason := '';
          if Assigned(Options.ResolveWith) and Options.ResolveWith(ANode, WithEdits, Reason) then
            Candidate.Variants[0].Edits := WithEdits
          else
          begin
            Candidate.Note := TUnwrapNote.WithUnresolved;
            Candidate.NoteText := Reason;
            Candidate.Variants := nil;
          end;
        end;
      end;
    TSyntaxKind.RepeatStatement:
      begin
        First := NextCode(ANode.StartOffset);
        if not IsKeyword(First, 'repeat') or (ANode.ChildCount < 1) then
          Exit;
        Last := PrevCode(ANode[ANode.ChildCount - 1].StartOffset);
        if not IsKeyword(Last, 'until') then
          Exit;
        Candidate.Kind := TUnwrapKind.RepeatUntil;
        Candidate.Variants := [WithKind(Compose(ANode, ANode.StartOffset, ANode.EndOffset,
          [TSegment.Create(TokenEnd(First), Tokens[Last].Offset)], ANode.ChildCount - 1, False),
          TUnwrapVariantKind.Body, 0)];
      end;
  else
    Exit;
  end;
  ACandidates := ACandidates + [Candidate];
end;

procedure TBuilder.AddDirectives(AOffset: Integer; var ACandidates: TArray<TUnwrapCandidate>);
var
  Groups: TStack<TArray<Integer>>;
  Regions: TStack<Integer>;
  Group: TArray<Integer>;
  Index, Opener, Branch: Integer;
  Name: string;
  Candidate: TUnwrapCandidate;
  Kind: TUnwrapVariantKind;
begin
  Groups := TStack<TArray<Integer>>.Create;
  Regions := TStack<Integer>.Create;
  try
    for Index := 0 to High(Tokens) do
    begin
      if Tokens[Index].Kind <> TPascalTokenKind.Directive then
        Continue;
      Name := TPascalLexer.DirectiveName(Tokens[Index].Text);
      if (Name = 'IF') or (Name = 'IFDEF') or (Name = 'IFNDEF') or (Name = 'IFOPT') then
        Groups.Push([Index])
      else if ((Name = 'ELSE') or (Name = 'ELSEIF')) and (Groups.Count > 0) then
      begin
        Group := Groups.Pop;
        Groups.Push(Group + [Index]);
      end
      else if ((Name = 'ENDIF') or (Name = 'IFEND')) and (Groups.Count > 0) then
      begin
        Group := Groups.Pop + [Index];
        Opener := Group[0];
        if (Tokens[Opener].Offset > AOffset) or (TokenEnd(Index) < AOffset) then
          Continue;
        Candidate := Default(TUnwrapCandidate);
        Candidate.Kind := TUnwrapKind.IfDef;
        Candidate.Range := RangeOf(Tokens[Opener].Offset, TokenEnd(Index));
        for Branch := 0 to High(Group) - 1 do
        begin
          if Branch = 0 then
            Kind := TUnwrapVariantKind.ThenBranch
          else if TPascalLexer.DirectiveName(Tokens[Group[Branch]].Text) = 'ELSE' then
            Kind := TUnwrapVariantKind.ElseBranch
          else
            Kind := TUnwrapVariantKind.Branch;
          Candidate.Variants := Candidate.Variants + [WithKind(Compose(nil, Tokens[Opener].Offset, TokenEnd(Index),
            [TSegment.Create(TokenEnd(Group[Branch]), Tokens[Group[Branch + 1]].Offset)], 1, True), Kind,
            Branch)];
        end;
        ACandidates := ACandidates + [Candidate];
      end
      else if Name = 'REGION' then
        Regions.Push(Index)
      else if (Name = 'ENDREGION') and (Regions.Count > 0) then
      begin
        Opener := Regions.Pop;
        if (Tokens[Opener].Offset > AOffset) or (TokenEnd(Index) < AOffset) then
          Continue;
        Candidate := Default(TUnwrapCandidate);
        Candidate.Kind := TUnwrapKind.Region;
        Candidate.Range := RangeOf(Tokens[Opener].Offset, TokenEnd(Index));
        Candidate.Variants := [WithKind(Compose(nil, Tokens[Opener].Offset, TokenEnd(Index),
          [TSegment.Create(TokenEnd(Opener), Tokens[Index].Offset)], 1, True), TUnwrapVariantKind.Body, 0)];
        ACandidates := ACandidates + [Candidate];
      end;
    end;
  finally
    Regions.Free;
    Groups.Free;
  end;
end;

{ TUnwrap }

class function TUnwrap.Candidates(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const AOptions: TUnwrapOptions): TArray<TUnwrapCandidate>;
var
  Builder: TBuilder;
  Offset, Index: Integer;
  Node: TSyntaxNode;
  Path: TArray<TSyntaxNode>;
  Descended: Boolean;
  All: TArray<TUnwrapCandidate>;
  Sizes: TArray<Integer>;
  Order: TArray<Integer>;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  Builder.Text := AText;
  Builder.Tokens := ATree.Tokens;
  Builder.Table := TLineTable.Build(AText);
  Builder.LineBreak := TTextLines.LineBreakOf(AText);
  Builder.Options := AOptions;
  if Builder.Options.IndentWidth <= 0 then
    Builder.Options.IndentWidth := 2;
  Offset := Builder.Table.OffsetAt(APosition);

  // Pfad von der Wurzel zum innersten Knoten an der Stelle.
  Path := nil;
  Node := ATree.Root;
  repeat
    Descended := False;
    for Index := 0 to Node.ChildCount - 1 do
      if (Node[Index].StartOffset <= Offset) and (Offset <= Node[Index].EndOffset) then
      begin
        Node := Node[Index];
        Path := Path + [Node];
        Descended := True;
        Break;
      end;
  until not Descended;

  All := nil;
  for Index := High(Path) downto 0 do
    Builder.AddStatement(Path[Index], All);
  Builder.AddDirectives(Offset, All);

  // Innerstes zuerst: nach Länge, bei gleicher Länge Anweisungen vor Direktiven.
  SetLength(Sizes, Length(All));
  SetLength(Order, Length(All));
  for Index := 0 to High(All) do
  begin
    Sizes[Index] := Builder.Table.OffsetAt(All[Index].Range.EndPos) - Builder.Table.OffsetAt(All[Index].Range.StartPos);
    Order[Index] := Index;
  end;
  TArray.Sort<Integer>(Order, TComparer<Integer>.Construct(
    function(const A, B: Integer): Integer
    begin
      Result := Sizes[A] - Sizes[B];
      if Result = 0 then
        Result := A - B;
    end));
  for Index := 0 to High(Order) do
  begin
    if (AOptions.MaxLevels > 0) and (Length(Result) >= AOptions.MaxLevels) then
      Break;
    Result := Result + [All[Order[Index]]];
  end;
end;

class function TUnwrap.KindName(AKind: TUnwrapKind): string;
begin
  Result := KindNames[AKind];
end;

class function TUnwrap.VariantName(AKind: TUnwrapVariantKind): string;
begin
  Result := VariantNames[AKind];
end;

class function TUnwrap.NoteName(ANote: TUnwrapNote): string;
begin
  Result := NoteNames[ANote];
end;

end.
