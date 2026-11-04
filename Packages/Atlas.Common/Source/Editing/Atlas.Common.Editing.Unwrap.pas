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
    /// <summary>Compose über das ganze Konstrukt ANode (keine Direktive).</summary>
    function Whole(ANode: TSyntaxNode; const ASegments: TArray<TSegment>; ACount: Integer): TUnwrapVariant;
    function BlockCandidate(ANode: TSyntaxNode; var ACandidate: TUnwrapCandidate): Boolean;
    function FinallyCandidate(ANode, AHandler: TSyntaxNode; const ABody: TSegment; ALast: Integer;
      var ACandidate: TUnwrapCandidate): Boolean;
    procedure ExceptCandidate(ANode, AHandler: TSyntaxNode; const ABody: TSegment; var ACandidate: TUnwrapCandidate);
    function TryCandidate(ANode: TSyntaxNode; var ACandidate: TUnwrapCandidate): Boolean;
    /// <summary>Token des else zum if ANode mit then bei ADelimiter; -1 ohne. Bei "then else" wird ABranch zum
    /// else-Zweig und ABranch nil.</summary>
    function ElseOf(ANode: TSyntaxNode; ADelimiter: Integer; var ABranch: TSyntaxNode;
      out AElseBranch: TSyntaxNode): Integer;
    function IfCandidate(ANode: TSyntaxNode; var ACandidate: TUnwrapCandidate): Boolean;
    /// <summary>Bei with die Edits von „with auflösen“; sonst Hinweis und keine Varianten.</summary>
    procedure ResolveWith(ANode: TSyntaxNode; var ACandidate: TUnwrapCandidate);
    function LoopCandidate(ANode: TSyntaxNode; var ACandidate: TUnwrapCandidate): Boolean;
    function RepeatCandidate(ANode: TSyntaxNode; var ACandidate: TUnwrapCandidate): Boolean;
    procedure AddStatement(ANode: TSyntaxNode; var ACandidates: TArray<TUnwrapCandidate>);
    /// <summary>Kandidat für die Gruppe {$IF…} … {$ENDIF} (Token-Indizes AGroup), wenn sie AOffset umschließt.
    /// </summary>
    procedure AddIfDef(const AGroup: TArray<Integer>; AOffset: Integer; var ACandidates: TArray<TUnwrapCandidate>);
    procedure AddRegion(AOpener, ACloser, AOffset: Integer; var ACandidates: TArray<TUnwrapCandidate>);
    procedure AddDirectives(AOffset: Integer; var ACandidates: TArray<TUnwrapCandidate>);
  end;

  /// <summary>Arbeitsstand von TBuilder.Compose: das Konstrukt Node von StartOffset bis EndOffset (Ending mit dem
  /// Semikolon dahinter), die behaltenen Segmente, die Semikolon-Edits darin, die behaltenen Zeilen Kept
  /// (Partial: Rest hinter einem Trennwort) und die Einrückungen.</summary>
  TComposition = record
    Builder: TBuilder;
    Node: TSyntaxNode;
    StartOffset: Integer;
    EndOffset: Integer;
    Segments: TArray<TSegment>;
    Count: Integer;
    Directive: Boolean;
    Ending: Integer;
    HadSemicolon: Boolean;
    BeforeElse: Boolean;
    SingleParent: Boolean;
    Wrap: Boolean;
    Edits: TArray<TOffsetEdit>;
    Kept: TArray<string>;
    Partial: TArray<Boolean>;
    MinIndent: Integer;
    FirstLine: Integer;
    LastLine: Integer;
    Outer: Integer;
    Inner: Integer;
    /// <summary>Was hinter dem Konstrukt steht (Semikolon, else) und ob es einzeln hinter then/do steht.</summary>
    procedure Prepare;
    /// <summary>Letztes Code-Token im Segment; -1 ohne.</summary>
    function LastCodeIn(const ASegment: TSegment): Integer;
    /// <summary>Semikolon hinter dem Token ALast ergänzen (AInner: Anweisung mitten im Ergebnis) oder vor else
    /// streichen.</summary>
    function SemicolonEdit(ALast: Integer; AInner: Boolean; out AEdit: TOffsetEdit): Boolean;
    /// <summary>Semikolons: hinter jeder Anweisung eins, am Ende wie vorher am Konstrukt, vor else keins.</summary>
    procedure CollectSemicolons;
    /// <summary>Behaltene Zeilen: die erste Zeile eines Segments ist der Rest hinter dem Trennwort.</summary>
    procedure AddKept(const ASegment: TSegment);
    /// <summary>Gemeinsame Einrückung der vollen Zeilen.</summary>
    function CommonIndent: Integer;
    function LineContent(AIndex: Integer): string;
    function BodyLines: TArray<string>;
    /// <summary>Ganze Zeilen ersetzen.</summary>
    function WholeLines(const ABody: TArray<string>): TTextEdit;
    procedure StartOfEdit(AAtStart: Boolean; out AStart: Integer; out APrefix: string);
    procedure EndOfEdit(AAtEnd: Boolean; out AEnd: Integer; out ASuffix: string);
    function Replacement(const ABody: TArray<string>): TTextEdit;
    /// <summary>Vorschau: Segmente bleiben, der Rest des Konstrukts entfällt; das Semikolon dahinter bleibt.
    /// </summary>
    procedure Preview(var AVariant: TUnwrapVariant);
    function Build: TUnwrapVariant;
  end;

function WithKind(const AValue: TUnwrapVariant; AKind: TUnwrapVariantKind; ABranch: Integer): TUnwrapVariant;
begin
  Result := AValue;
  Result.Kind := AKind;
  Result.Branch := ABranch;
end;

function CountRaises(ANode: TSyntaxNode): Integer;
var
  Count: Integer;
begin
  Result := 0;
  if ANode = nil then
  begin
    Exit;
  end;
  Count := 0;
  // Walk statt Rekursion (Bericht M1). Ein raise in einer anonymen Methode gehört nicht zum except-Teil.
  ANode.Walk(
    function(AChild: TSyntaxNode): Boolean
    begin
      if AChild.Kind = TSyntaxKind.RaiseStatement then
      begin
        Inc(Count);
      end;
      Result := AChild.Kind <> TSyntaxKind.AnonymousMethod;
    end);
  Result := Count;
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
  begin
    Result.EndOffset := Result.StartOffset;
  end;
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
  begin
    Inc(Result);
  end;
  if Result > High(Tokens) then
  begin
    Result := -1;
  end;
end;

function TBuilder.PrevCode(AOffset: Integer): Integer;
begin
  Result := TRoutineBody.TokenAt(Tokens, AOffset) - 1;
  while (Result >= 0) and (not IsCode(Result) or (TokenEnd(Result) > AOffset)) do
  begin
    Dec(Result);
  end;
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
  begin
    Exit;
  end;
  for Index := AStart + 1 to AEnd do
  begin
    if CharInSet(Text[Index], [#10, #13]) then
    begin
      Exit(False);
    end;
  end;
end;

procedure TBuilder.AddPieces(AStart, AEnd: Integer; var ARanges: TArray<TTextRange>);
var
  Line, From, Till: Integer;
begin
  if AEnd <= AStart then
  begin
    Exit;
  end;
  for Line := LineOf(AStart) to LineOf(AEnd) do
  begin
    From := Table.LineStart(Line);
    if From < AStart then
    begin
      From := AStart;
    end;
    Till := Table.LineContentEnd(Line);
    if Till > AEnd then
    begin
      Till := AEnd;
    end;
    while (From < Till) and CharInSet(Text[From + 1], [' ', #9]) do
    begin
      Inc(From);
    end;
    while (Till > From) and CharInSet(Text[Till], [' ', #9]) do
    begin
      Dec(Till);
    end;
    if Till > From then
    begin
      ARanges := ARanges + [RangeOf(From, Till)];
    end;
  end;
end;

function TBuilder.ChildFrom(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    if ANode[Index].StartOffset >= AOffset then
    begin
      Exit(ANode[Index]);
    end;
  end;
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
      begin
        Inc(Depth);
      end
      else if Tokens[Index].IsSymbol(')') or Tokens[Index].IsSymbol(']') then
      begin
        Dec(Depth);
      end
      else if (Depth = 0) and Tokens[Index].IsKeyword(AWord) then
      begin
        Exit(TokenEnd(Index));
      end;
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
  begin
    Exit(TSegment.Create(ADelimiterEnd, ADelimiterEnd));
  end;
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
  begin
    if (AEdits[Index].Offset >= ASegment.StartOffset) and (AEdits[Index].Offset <= ASegment.EndOffset) then
    begin
      Result := Copy(Result, 1, AEdits[Index].Offset - ASegment.StartOffset) + AEdits[Index].Text +
        Copy(Result, AEdits[Index].Offset - ASegment.StartOffset + AEdits[Index].Length + 1, MaxInt);
    end;
  end;
end;

function TBuilder.Compose(ANode: TSyntaxNode; AStart, AEnd: Integer; const ASegments: TArray<TSegment>;
  ACount: Integer; ADirective: Boolean): TUnwrapVariant;
var
  mComposition: TComposition;
begin
  mComposition := Default(TComposition);
  mComposition.Builder := Self;
  mComposition.Node := ANode;
  mComposition.StartOffset := AStart;
  mComposition.EndOffset := AEnd;
  mComposition.Segments := ASegments;
  mComposition.Count := ACount;
  mComposition.Directive := ADirective;
  Result := mComposition.Build;
end;

function TBuilder.Whole(ANode: TSyntaxNode; const ASegments: TArray<TSegment>; ACount: Integer): TUnwrapVariant;
begin
  Result := Compose(ANode, ANode.StartOffset, ANode.EndOffset, ASegments, ACount, False);
end;

{ TComposition }

procedure TComposition.Prepare;
var
  mNext: Integer;
begin
  Ending := EndOffset;
  HadSemicolon := False;
  BeforeElse := False;
  if not Directive then
  begin
    mNext := Builder.NextCode(EndOffset);
    if (mNext >= 0) and Builder.Tokens[mNext].IsSymbol(';') then
    begin
      HadSemicolon := True;
      Ending := Builder.TokenEnd(mNext);
    end
    else
    begin
      BeforeElse := Builder.IsKeyword(mNext, 'else');
    end;
  end;
  SingleParent := not Directive and (Node <> nil) and (Node.Parent <> nil) and
    (Node.Parent.Kind in SingleStatementParents);
  Wrap := SingleParent and (Count <> 1);
end;

function TComposition.LastCodeIn(const ASegment: TSegment): Integer;
begin
  Result := Builder.PrevCode(ASegment.EndOffset);
  if (Result >= 0) and (Builder.Tokens[Result].Offset < ASegment.StartOffset) then
  begin
    Result := -1;
  end;
end;

function TComposition.SemicolonEdit(ALast: Integer; AInner: Boolean; out AEdit: TOffsetEdit): Boolean;
var
  mHas: Boolean;
begin
  AEdit := Default(TOffsetEdit);
  mHas := Builder.Tokens[ALast].IsSymbol(';');
  Result := False;
  if AInner or HadSemicolon then
  begin
    Result := not mHas;
    AEdit.Offset := Builder.TokenEnd(ALast);
    AEdit.Text := ';';
  end
  else if BeforeElse and mHas then
  begin
    Result := True;
    AEdit.Offset := Builder.Tokens[ALast].Offset;
    AEdit.Length := 1;
  end;
end;

procedure TComposition.CollectSemicolons;
var
  mIndex, mLast, mLastWithCode: Integer;
  mEdit: TOffsetEdit;
begin
  Edits := nil;
  if Directive then
  begin
    Exit;
  end;
  mLastWithCode := -1;
  for mIndex := 0 to High(Segments) do
  begin
    if LastCodeIn(Segments[mIndex]) >= 0 then
    begin
      mLastWithCode := mIndex;
    end;
  end;
  for mIndex := High(Segments) downto 0 do
  begin
    mLast := LastCodeIn(Segments[mIndex]);
    if (mLast >= 0) and SemicolonEdit(mLast, (mIndex < mLastWithCode) or (Wrap and (mIndex = mLastWithCode)),
      mEdit) then
    begin
      Edits := Edits + [mEdit];
    end;
  end;
end;

procedure TComposition.AddKept(const ASegment: TSegment);
var
  mSplit: TArray<string>;
  mFirst, mTail, mIndex: Integer;
begin
  mSplit := TTextLines.SplitLines(Builder.SegmentText(ASegment, Edits));
  for mIndex := 0 to High(mSplit) do
  begin
    mSplit[mIndex] := TrimRight(mSplit[mIndex]);
  end;
  if mSplit <> nil then
  begin
    mSplit[0] := Trim(mSplit[0]);
  end;
  mFirst := 0;
  mTail := High(mSplit);
  while (mFirst <= mTail) and (Trim(mSplit[mFirst]) = '') do
  begin
    Inc(mFirst);
  end;
  while (mTail >= mFirst) and (Trim(mSplit[mTail]) = '') do
  begin
    Dec(mTail);
  end;
  for mIndex := mFirst to mTail do
  begin
    Kept := Kept + [mSplit[mIndex]];
    Partial := Partial + [mIndex = 0];
  end;
end;

function TComposition.CommonIndent: Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(Kept) do
  begin
    if not Partial[mIndex] and (Trim(Kept[mIndex]) <> '') and
      ((Result < 0) or (TTextLines.IndentLength(Kept[mIndex]) < Result)) then
    begin
      Result := TTextLines.IndentLength(Kept[mIndex]);
    end;
  end;
  if Result < 0 then
  begin
    Result := 0;
  end;
end;

function TComposition.LineContent(AIndex: Integer): string;
begin
  if Kept[AIndex] = '' then
  begin
    Result := '';
  end
  else if Directive and not Partial[AIndex] then
  begin
    Result := Kept[AIndex];
  end
  else if Directive then
  begin
    Result := StringOfChar(' ', MinIndent) + Kept[AIndex];
  end
  else if Partial[AIndex] then
  begin
    Result := StringOfChar(' ', Inner) + Kept[AIndex];
  end
  else
  begin
    Result := StringOfChar(' ', Inner) + Copy(Kept[AIndex], MinIndent + 1, MaxInt);
  end;
end;

function TComposition.BodyLines: TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  if Wrap then
  begin
    Result := Result + [StringOfChar(' ', Outer) + 'begin'];
  end;
  for mIndex := 0 to High(Kept) do
  begin
    Result := Result + [LineContent(mIndex)];
  end;
  if Wrap and HadSemicolon then
  begin
    Result := Result + [StringOfChar(' ', Outer) + 'end;'];
  end
  else if Wrap then
  begin
    Result := Result + [StringOfChar(' ', Outer) + 'end'];
  end;
end;

function TComposition.WholeLines(const ABody: TArray<string>): TTextEdit;
var
  mEnd: Integer;
  mSuffix: string;
begin
  mSuffix := '';
  if LastLine + 1 < Builder.Table.LineCount then
  begin
    mEnd := Builder.Table.LineStart(LastLine + 1);
    if ABody <> nil then
    begin
      mSuffix := Builder.LineBreak;
    end;
  end
  else
  begin
    mEnd := Builder.Table.LineContentEnd(LastLine);
  end;
  Result := TTextEdit.Create(Builder.RangeOf(Builder.Table.LineStart(FirstLine), mEnd),
    string.Join(Builder.LineBreak, ABody) + mSuffix);
end;

procedure TComposition.StartOfEdit(AAtStart: Boolean; out AStart: Integer; out APrefix: string);
begin
  APrefix := '';
  if AAtStart then
  begin
    AStart := Builder.Table.LineStart(FirstLine);
    Exit;
  end;
  AStart := StartOffset;
  while (AStart > 0) and CharInSet(Builder.Text[AStart], [' ', #9]) do
  begin
    Dec(AStart);
  end;
  APrefix := Builder.LineBreak;
end;

procedure TComposition.EndOfEdit(AAtEnd: Boolean; out AEnd: Integer; out ASuffix: string);
begin
  ASuffix := '';
  if not AAtEnd then
  begin
    AEnd := Ending;
    while (AEnd < Length(Builder.Text)) and CharInSet(Builder.Text[AEnd + 1], [' ', #9]) do
    begin
      Inc(AEnd);
    end;
    ASuffix := Builder.LineBreak + StringOfChar(' ', Builder.LineIndent(FirstLine));
  end
  else if LastLine + 1 < Builder.Table.LineCount then
  begin
    AEnd := Builder.Table.LineStart(LastLine + 1);
    ASuffix := Builder.LineBreak;
  end
  else
  begin
    AEnd := Builder.Table.LineContentEnd(LastLine);
  end;
end;

function TComposition.Replacement(const ABody: TArray<string>): TTextEdit;
var
  mAtStart, mAtEnd: Boolean;
  mStart, mEnd: Integer;
  mPrefix, mSuffix: string;
begin
  mAtStart := Builder.IsBlank(Builder.Table.LineStart(FirstLine), StartOffset);
  mAtEnd := Builder.IsBlank(Ending, Builder.Table.LineContentEnd(LastLine));
  if mAtStart and mAtEnd then
  begin
    Exit(WholeLines(ABody));
  end;
  if ABody = nil then
  begin
    Exit(TTextEdit.Create(Builder.RangeOf(StartOffset, Ending), ''));
  end;
  if (FirstLine = LastLine) and (Length(ABody) = 1) then
  begin
    // Einzeilig im Fließtext.
    Exit(TTextEdit.Create(Builder.RangeOf(StartOffset, Ending), Trim(ABody[0])));
  end;
  StartOfEdit(mAtStart, mStart, mPrefix);
  EndOfEdit(mAtEnd, mEnd, mSuffix);
  Result := TTextEdit.Create(Builder.RangeOf(mStart, mEnd), mPrefix + string.Join(Builder.LineBreak, ABody) + mSuffix);
end;

procedure TComposition.Preview(var AVariant: TUnwrapVariant);
var
  mNext: Integer;
  mSegment: TSegment;
begin
  mNext := StartOffset;
  for mSegment in Segments do
  begin
    Builder.AddPieces(mNext, mSegment.StartOffset, AVariant.Remove);
    Builder.AddPieces(mSegment.StartOffset, mSegment.EndOffset, AVariant.Keep);
    if mSegment.EndOffset > mNext then
    begin
      mNext := mSegment.EndOffset;
    end;
  end;
  Builder.AddPieces(mNext, EndOffset, AVariant.Remove);
end;

function TComposition.Build: TUnwrapVariant;
var
  mSegment: TSegment;
begin
  Prepare;
  CollectSemicolons;
  Kept := nil;
  Partial := nil;
  for mSegment in Segments do
  begin
    AddKept(mSegment);
  end;
  MinIndent := CommonIndent;
  FirstLine := Builder.LineOf(StartOffset);
  LastLine := Builder.LineOf(Ending);
  if SingleParent then
  begin
    Outer := Builder.LineIndent(Builder.LineOf(Node.Parent.StartOffset));
    Inner := Outer + Builder.Options.IndentWidth;
  end
  else
  begin
    Outer := Builder.LineIndent(FirstLine);
    Inner := Outer;
  end;
  Result := Default(TUnwrapVariant);
  Result.Edits := TArray<TTextEdit>.Create(Replacement(BodyLines));
  Preview(Result);
end;

{ TBuilder: Kandidaten }

function StatementCount(ANode: TSyntaxNode): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if not (ANode[mIndex].Kind in [TSyntaxKind.FinallyBlock, TSyntaxKind.ExceptBlock]) then
    begin
      Inc(Result);
    end;
  end;
end;

function TryHandler(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode.FindChild(TSyntaxKind.FinallyBlock);
  if Result = nil then
  begin
    Result := ANode.FindChild(TSyntaxKind.ExceptBlock);
  end;
end;

function TBuilder.BlockCandidate(ANode: TSyntaxNode; var ACandidate: TUnwrapCandidate): Boolean;
var
  mSegment: TSegment;
  mCount: Integer;
begin
  Result := (ANode.Parent <> nil) and (ANode.Parent.Kind in StatementParents);
  if not Result then
  begin
    Exit;
  end;
  mSegment := BranchSegment(ANode.StartOffset, ANode, mCount);
  // Hinter then/do ergäbe ein Block mit mehreren Anweisungen wieder begin … end.
  Result := (mCount = ANode.ChildCount) and (mSegment.StartOffset <> ANode.StartOffset) and
    not ((ANode.Parent.Kind in SingleStatementParents) and (mCount <> 1));
  if Result then
  begin
    ACandidate.Kind := TUnwrapKind.BeginEnd;
    ACandidate.Variants := [WithKind(Whole(ANode, [mSegment], mCount), TUnwrapVariantKind.Body, 0)];
  end;
end;

function TBuilder.FinallyCandidate(ANode, AHandler: TSyntaxNode; const ABody: TSegment; ALast: Integer;
  var ACandidate: TUnwrapCandidate): Boolean;
var
  mDelimiter, mCount: Integer;
  mFinally: TSegment;
begin
  ACandidate.Kind := TUnwrapKind.TryFinally;
  mDelimiter := NextCode(AHandler.StartOffset);
  Result := IsKeyword(mDelimiter, 'finally');
  if not Result then
  begin
    Exit;
  end;
  mCount := StatementCount(ANode);
  mFinally := TSegment.Create(TokenEnd(mDelimiter), Tokens[ALast].Offset);
  ACandidate.Variants := [
    WithKind(Whole(ANode, [ABody, mFinally], mCount + AHandler.ChildCount), TUnwrapVariantKind.KeepFinally, 0),
    WithKind(Whole(ANode, [ABody], mCount), TUnwrapVariantKind.DropFinally, 0)];
end;

procedure TBuilder.ExceptCandidate(ANode, AHandler: TSyntaxNode; const ABody: TSegment;
  var ACandidate: TUnwrapCandidate);
var
  mRaises: Integer;
begin
  ACandidate.Kind := TUnwrapKind.TryExcept;
  mRaises := CountRaises(AHandler);
  if mRaises > 1 then
  begin
    ACandidate.Note := TUnwrapNote.MultipleRaise;
    ACandidate.NoteText := IntToStr(mRaises);
  end;
  ACandidate.Variants := [WithKind(Whole(ANode, [ABody], StatementCount(ANode)), TUnwrapVariantKind.Body, 0)];
end;

function TBuilder.TryCandidate(ANode: TSyntaxNode; var ACandidate: TUnwrapCandidate): Boolean;
var
  mFirst, mLast: Integer;
  mHandler: TSyntaxNode;
  mBody: TSegment;
begin
  mFirst := NextCode(ANode.StartOffset);
  mLast := PrevCode(ANode.EndOffset);
  mHandler := TryHandler(ANode);
  Result := IsKeyword(mFirst, 'try') and IsKeyword(mLast, 'end') and (mHandler <> nil);
  if not Result then
  begin
    Exit;
  end;
  mBody := TSegment.Create(TokenEnd(mFirst), mHandler.StartOffset);
  if mHandler.Kind = TSyntaxKind.FinallyBlock then
  begin
    Result := FinallyCandidate(ANode, mHandler, mBody, mLast, ACandidate);
  end
  else
  begin
    ExceptCandidate(ANode, mHandler, mBody, ACandidate);
  end;
end;

function TBuilder.ElseOf(ANode: TSyntaxNode; ADelimiter: Integer; var ABranch: TSyntaxNode;
  out AElseBranch: TSyntaxNode): Integer;
var
  mNext: Integer;
begin
  AElseBranch := nil;
  Result := NextCode(TokenEnd(ADelimiter));
  if IsKeyword(Result, 'else') then
  begin
    // if … then else …: leerer then-Zweig.
    AElseBranch := ABranch;
    ABranch := nil;
    Exit;
  end;
  Result := -1;
  if ABranch = nil then
  begin
    Exit;
  end;
  mNext := NextCode(ABranch.EndOffset);
  if IsKeyword(mNext, 'else') and (Tokens[mNext].Offset < ANode.EndOffset) then
  begin
    Result := mNext;
    AElseBranch := ChildFrom(ANode, TokenEnd(Result));
  end;
end;

function TBuilder.IfCandidate(ANode: TSyntaxNode; var ACandidate: TUnwrapCandidate): Boolean;
var
  mDelimiter, mElse, mCount: Integer;
  mBranch, mElseBranch: TSyntaxNode;
  mSegment: TSegment;
begin
  mDelimiter := -1;
  if ANode.ChildCount >= 1 then
  begin
    mDelimiter := NextCode(ANode[0].EndOffset);
  end;
  Result := IsKeyword(mDelimiter, 'then');
  if not Result then
  begin
    Exit;
  end;
  mBranch := ChildFrom(ANode, TokenEnd(mDelimiter));
  mElse := ElseOf(ANode, mDelimiter, mBranch, mElseBranch);
  ACandidate.Kind := TUnwrapKind.IfThen;
  mSegment := BranchSegment(TokenEnd(mDelimiter), mBranch, mCount);
  ACandidate.Variants := [WithKind(Whole(ANode, [mSegment], mCount), TUnwrapVariantKind.ThenBranch, 0)];
  if mElse >= 0 then
  begin
    mSegment := BranchSegment(TokenEnd(mElse), mElseBranch, mCount);
    ACandidate.Variants := ACandidate.Variants + [WithKind(Whole(ANode, [mSegment], mCount),
      TUnwrapVariantKind.ElseBranch, 0)];
  end;
end;

procedure TBuilder.ResolveWith(ANode: TSyntaxNode; var ACandidate: TUnwrapCandidate);
var
  mEdits: TArray<TTextEdit>;
  mReason: string;
begin
  // Die Bedeutung bleibt nur mit ausgeschriebenen Bezügen gleich.
  mEdits := nil;
  mReason := '';
  if Assigned(Options.ResolveWith) and Options.ResolveWith(ANode, mEdits, mReason) then
  begin
    ACandidate.Variants[0].Edits := mEdits;
  end
  else
  begin
    ACandidate.Note := TUnwrapNote.WithUnresolved;
    ACandidate.NoteText := mReason;
    ACandidate.Variants := nil;
  end;
end;

function TBuilder.LoopCandidate(ANode: TSyntaxNode; var ACandidate: TUnwrapCandidate): Boolean;
var
  mDelimiter, mCount: Integer;
  mSegment: TSegment;
begin
  mDelimiter := KeywordEnd(ANode.StartOffset, ANode.EndOffset, 'do');
  Result := mDelimiter >= 0;
  if not Result then
  begin
    Exit;
  end;
  mSegment := BranchSegment(mDelimiter, ChildFrom(ANode, mDelimiter), mCount);
  case ANode.Kind of
    TSyntaxKind.WhileStatement:
      ACandidate.Kind := TUnwrapKind.WhileDo;
    TSyntaxKind.WithStatement:
      ACandidate.Kind := TUnwrapKind.WithDo;
  else
    ACandidate.Kind := TUnwrapKind.ForDo;
    ACandidate.Note := TUnwrapNote.LoopVariable;
    ACandidate.NoteText := ANode.Name;
  end;
  ACandidate.Variants := [WithKind(Whole(ANode, [mSegment], mCount), TUnwrapVariantKind.Body, 0)];
  if ACandidate.Kind = TUnwrapKind.WithDo then
  begin
    ResolveWith(ANode, ACandidate);
  end;
end;

function TBuilder.RepeatCandidate(ANode: TSyntaxNode; var ACandidate: TUnwrapCandidate): Boolean;
var
  mFirst, mLast: Integer;
begin
  mFirst := NextCode(ANode.StartOffset);
  mLast := -1;
  if IsKeyword(mFirst, 'repeat') and (ANode.ChildCount >= 1) then
  begin
    mLast := PrevCode(ANode[ANode.ChildCount - 1].StartOffset);
  end;
  Result := IsKeyword(mLast, 'until');
  if Result then
  begin
    ACandidate.Kind := TUnwrapKind.RepeatUntil;
    ACandidate.Variants := [WithKind(Whole(ANode, [TSegment.Create(TokenEnd(mFirst), Tokens[mLast].Offset)],
      ANode.ChildCount - 1), TUnwrapVariantKind.Body, 0)];
  end;
end;

procedure TBuilder.AddStatement(ANode: TSyntaxNode; var ACandidates: TArray<TUnwrapCandidate>);
var
  mCandidate: TUnwrapCandidate;
  mFound: Boolean;
begin
  mCandidate := Default(TUnwrapCandidate);
  mCandidate.Range := RangeOf(ANode.StartOffset, ANode.EndOffset);
  case ANode.Kind of
    TSyntaxKind.Block:
      mFound := BlockCandidate(ANode, mCandidate);
    TSyntaxKind.TryStatement:
      mFound := TryCandidate(ANode, mCandidate);
    TSyntaxKind.IfStatement:
      mFound := IfCandidate(ANode, mCandidate);
    TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement, TSyntaxKind.WithStatement:
      mFound := LoopCandidate(ANode, mCandidate);
    TSyntaxKind.RepeatStatement:
      mFound := RepeatCandidate(ANode, mCandidate);
  else
    mFound := False;
  end;
  if mFound then
  begin
    ACandidates := ACandidates + [mCandidate];
  end;
end;

/// <summary>Was der Zweig ABranch der Gruppe AGroup behält: then, else oder einen weiteren {$ELSEIF}-Zweig.
/// </summary>
function BranchKind(const ATokens: TArray<TPascalToken>; const AGroup: TArray<Integer>;
  ABranch: Integer): TUnwrapVariantKind;
begin
  if ABranch = 0 then
  begin
    Result := TUnwrapVariantKind.ThenBranch;
  end
  else if TPascalLexer.DirectiveName(ATokens[AGroup[ABranch]].Text) = 'ELSE' then
  begin
    Result := TUnwrapVariantKind.ElseBranch;
  end
  else
  begin
    Result := TUnwrapVariantKind.Branch;
  end;
end;

procedure TBuilder.AddIfDef(const AGroup: TArray<Integer>; AOffset: Integer;
  var ACandidates: TArray<TUnwrapCandidate>);
var
  mOpener, mCloser, mBranch: Integer;
  mCandidate: TUnwrapCandidate;
  mSegment: TSegment;
begin
  mOpener := AGroup[0];
  mCloser := AGroup[High(AGroup)];
  if (Tokens[mOpener].Offset > AOffset) or (TokenEnd(mCloser) < AOffset) then
  begin
    Exit;
  end;
  mCandidate := Default(TUnwrapCandidate);
  mCandidate.Kind := TUnwrapKind.IfDef;
  mCandidate.Range := RangeOf(Tokens[mOpener].Offset, TokenEnd(mCloser));
  for mBranch := 0 to High(AGroup) - 1 do
  begin
    mSegment := TSegment.Create(TokenEnd(AGroup[mBranch]), Tokens[AGroup[mBranch + 1]].Offset);
    mCandidate.Variants := mCandidate.Variants + [WithKind(Compose(nil, Tokens[mOpener].Offset, TokenEnd(mCloser),
      [mSegment], 1, True), BranchKind(Tokens, AGroup, mBranch), mBranch)];
  end;
  ACandidates := ACandidates + [mCandidate];
end;

procedure TBuilder.AddRegion(AOpener, ACloser, AOffset: Integer; var ACandidates: TArray<TUnwrapCandidate>);
var
  mCandidate: TUnwrapCandidate;
begin
  if (Tokens[AOpener].Offset > AOffset) or (TokenEnd(ACloser) < AOffset) then
  begin
    Exit;
  end;
  mCandidate := Default(TUnwrapCandidate);
  mCandidate.Kind := TUnwrapKind.Region;
  mCandidate.Range := RangeOf(Tokens[AOpener].Offset, TokenEnd(ACloser));
  mCandidate.Variants := [WithKind(Compose(nil, Tokens[AOpener].Offset, TokenEnd(ACloser),
    [TSegment.Create(TokenEnd(AOpener), Tokens[ACloser].Offset)], 1, True), TUnwrapVariantKind.Body, 0)];
  ACandidates := ACandidates + [mCandidate];
end;

function IsGroupStart(const AName: string): Boolean;
begin
  Result := (AName = 'IF') or (AName = 'IFDEF') or (AName = 'IFNDEF') or (AName = 'IFOPT');
end;

function IsGroupElse(const AName: string): Boolean;
begin
  Result := (AName = 'ELSE') or (AName = 'ELSEIF');
end;

function IsGroupEnd(const AName: string): Boolean;
begin
  Result := (AName = 'ENDIF') or (AName = 'IFEND');
end;

procedure TBuilder.AddDirectives(AOffset: Integer; var ACandidates: TArray<TUnwrapCandidate>);
var
  mGroups: TStack<TArray<Integer>>;
  mRegions: TStack<Integer>;
  mIndex: Integer;
  mName: string;
begin
  mGroups := TStack<TArray<Integer>>.Create;
  mRegions := TStack<Integer>.Create;
  try
    for mIndex := 0 to High(Tokens) do
    begin
      if Tokens[mIndex].Kind <> TPascalTokenKind.Directive then
      begin
        Continue;
      end;
      mName := TPascalLexer.DirectiveName(Tokens[mIndex].Text);
      if IsGroupStart(mName) then
      begin
        mGroups.Push(TArray<Integer>.Create(mIndex));
      end
      else if IsGroupElse(mName) and (mGroups.Count > 0) then
      begin
        mGroups.Push(mGroups.Pop + [mIndex]);
      end
      else if IsGroupEnd(mName) and (mGroups.Count > 0) then
      begin
        AddIfDef(mGroups.Pop + [mIndex], AOffset, ACandidates);
      end
      else if mName = 'REGION' then
      begin
        mRegions.Push(mIndex);
      end
      else if (mName = 'ENDREGION') and (mRegions.Count > 0) then
      begin
        AddRegion(mRegions.Pop, mIndex, AOffset, ACandidates);
      end;
    end;
  finally
    mRegions.Free;
    mGroups.Free;
  end;
end;

{ TUnwrap }

function NewBuilder(const AText: string; ATree: TSyntaxTree; const AOptions: TUnwrapOptions): TBuilder;
begin
  Result.Text := AText;
  Result.Tokens := ATree.Tokens;
  Result.Table := TLineTable.Build(AText);
  Result.LineBreak := TTextLines.LineBreakOf(AText);
  Result.Options := AOptions;
  if Result.Options.IndentWidth <= 0 then
  begin
    Result.Options.IndentWidth := 2;
  end;
end;

/// <summary>Kind von ANode, das AOffset enthält; nil ohne.</summary>
function ChildAt(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
var
  mIndex: Integer;
begin
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if (ANode[mIndex].StartOffset <= AOffset) and (AOffset <= ANode[mIndex].EndOffset) then
    begin
      Exit(ANode[mIndex]);
    end;
  end;
  Result := nil;
end;

/// <summary>Pfad von der Wurzel zum innersten Knoten an AOffset (ohne die Wurzel).</summary>
function PathAt(ATree: TSyntaxTree; AOffset: Integer): TArray<TSyntaxNode>;
var
  mNode: TSyntaxNode;
begin
  Result := nil;
  mNode := ChildAt(ATree.Root, AOffset);
  while mNode <> nil do
  begin
    Result := Result + [mNode];
    mNode := ChildAt(mNode, AOffset);
  end;
end;

/// <summary>AAll, das innerste zuerst: nach Länge, bei gleicher Länge in der Reihenfolge von AAll (Anweisungen
/// vor Direktiven); höchstens AMaxLevels (0 = alle).</summary>
function InnermostFirst(const ATable: TLineTable; const AAll: TArray<TUnwrapCandidate>;
  AMaxLevels: Integer): TArray<TUnwrapCandidate>;
var
  mSizes, mOrder: TArray<Integer>;
  mIndex: Integer;
begin
  Result := nil;
  SetLength(mSizes, Length(AAll));
  SetLength(mOrder, Length(AAll));
  for mIndex := 0 to High(AAll) do
  begin
    mSizes[mIndex] := ATable.OffsetAt(AAll[mIndex].Range.EndPos) - ATable.OffsetAt(AAll[mIndex].Range.StartPos);
    mOrder[mIndex] := mIndex;
  end;
  TArray.Sort<Integer>(mOrder, TComparer<Integer>.Construct(
    function(const A, B: Integer): Integer
    begin
      Result := mSizes[A] - mSizes[B];
      if Result = 0 then
      begin
        Result := A - B;
      end;
    end));
  for mIndex := 0 to High(mOrder) do
  begin
    if (AMaxLevels > 0) and (Length(Result) >= AMaxLevels) then
    begin
      Break;
    end;
    Result := Result + [AAll[mOrder[mIndex]]];
  end;
end;

class function TUnwrap.Candidates(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const AOptions: TUnwrapOptions): TArray<TUnwrapCandidate>;
var
  mBuilder: TBuilder;
  mOffset, mIndex: Integer;
  mPath: TArray<TSyntaxNode>;
  mAll: TArray<TUnwrapCandidate>;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  mBuilder := NewBuilder(AText, ATree, AOptions);
  mOffset := mBuilder.Table.OffsetAt(APosition);
  mPath := PathAt(ATree, mOffset);
  mAll := nil;
  for mIndex := High(mPath) downto 0 do
  begin
    mBuilder.AddStatement(mPath[mIndex], mAll);
  end;
  mBuilder.AddDirectives(mOffset, mAll);
  Result := InnermostFirst(mBuilder.Table, mAll, AOptions.MaxLevels);
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
