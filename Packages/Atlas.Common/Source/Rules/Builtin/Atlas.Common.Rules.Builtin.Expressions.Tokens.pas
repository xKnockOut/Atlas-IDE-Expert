unit Atlas.Common.Rules.Builtin.Expressions.Tokens;

// Hilfen der Ausdrucksregeln (Atlas.Common.Rules.Builtin.Expressions) über der Tokenliste: Code-Token ohne
// Kommentare und Direktiven, Operandenende, einfacher Bezeichner, Lage im Routinenrumpf, Länge eines Literals
// und die Form "not X op Y" für operator-precedence.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Text.Lines;

type
  /// <summary>Token von "not X op Y": not, X, der Operator, Anfang und Ende von Y.</summary>
  TNotComparison = record
    NotToken: Integer;
    Operand: Integer;
    Op: Integer;
    Right: Integer;
    Last: Integer;
  end;

/// <summary>Kommentar oder Direktive?</summary>
function IsTrivia(const AToken: TPascalToken): Boolean;
/// <summary>Erstes Code-Token ab AIndex; hinter dem Ende, wenn keines.</summary>
function NextCode(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
/// <summary>Letztes Code-Token vor AIndex; -1, wenn keines.</summary>
function PreviousCode(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
/// <summary>Quelltext der Token AFirst..ALast wie geschrieben.</summary>
function SourceText(const AText: string; const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): string;
/// <summary>Bereich der Token AFirst..ALast.</summary>
function RangeOf(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): TTextRange;
/// <summary>Vergleichsoperator (=, &lt;&gt;, &lt;, &gt;, &lt;=, &gt;=)?</summary>
function IsComparison(const AToken: TPascalToken): Boolean;
/// <summary>Boolescher Typ oder Variant: not wirkt dort wie gemeint bzw. ist nicht sicher zu beurteilen.</summary>
function IsLogical(const AType: string): Boolean;
/// <summary>Einfacher Bezeichner: kein Teil einer Kette A.B und kein Aufruf.</summary>
function IsPlainIdentifier(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
/// <summary>Letztes Token des rechten Operanden ab AStart: bis vor das nächste Wort oder Zeichen, das den
/// Vergleich beendet (then, and, ;, schließende Klammer …), auf derselben Klammerebene; -1 ohne Operand.</summary>
function OperandEnd(const ATokens: TArray<TPascalToken>; AStart: Integer): Integer;
/// <summary>Liegt APosition im Rumpf (begin … end) einer Routine?</summary>
function InStatements(ATree: TSyntaxTree; const APosition: TTextPosition): Boolean;
/// <summary>"not X in …" bzw. "not X op …" mit einfachem Bezeichner X ab dem Token AIndex (not)?</summary>
function NotComparisonAt(const ATokens: TArray<TPascalToken>; AIndex: Integer; out AParts: TNotComparison): Boolean;
/// <summary>Zeichenzahl eines Literals aus '…'- und #n-Teilen ('''' zählt als ein Zeichen); -1, wenn
/// ALiteral kein solches Literal ist.</summary>
function PascalLiteralLength(const ALiteral: string): Integer;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function NextCode(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
  begin
    Inc(Result);
  end;
end;

function PreviousCode(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
  begin
    Dec(Result);
  end;
end;

function SourceText(const AText: string; const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): string;
begin
  Result := Copy(AText, ATokens[AFirst].Offset + 1,
    ATokens[ALast].Offset + Length(ATokens[ALast].Text) - ATokens[AFirst].Offset);
end;

function RangeOf(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): TTextRange;
begin
  Result := TTextRange.Create(ATokens[AFirst].StartPos, ATokens[ALast].EndPos);
end;

function IsComparison(const AToken: TPascalToken): Boolean;
begin
  Result := (AToken.Kind = TPascalTokenKind.Symbol) and MatchStr(AToken.Text, ['=', '<>', '<', '>', '<=', '>=']);
end;

function IsLogical(const AType: string): Boolean;
begin
  Result := MatchText(AType, ['Boolean', 'ByteBool', 'WordBool', 'LongBool', 'Variant', 'OleVariant']);
end;

/// <summary>Setzt das Token AIndex eine Kette oder einen Aufruf fort (., (, [, ^)?</summary>
function ContinuesChain(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
begin
  Result := (AIndex <= High(ATokens)) and (ATokens[AIndex].IsSymbol('.') or ATokens[AIndex].IsSymbol('(') or
    ATokens[AIndex].IsSymbol('[') or ATokens[AIndex].IsSymbol('^'));
end;

function IsPlainIdentifier(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  mPrevious: Integer;
begin
  Result := (AIndex >= 0) and (AIndex <= High(ATokens)) and (ATokens[AIndex].Kind = TPascalTokenKind.Identifier);
  if not Result then
  begin
    Exit;
  end;
  mPrevious := PreviousCode(ATokens, AIndex);
  Result := not ((mPrevious >= 0) and (ATokens[mPrevious].IsSymbol('.') or ATokens[mPrevious].IsSymbol('@'))) and
    not ContinuesChain(ATokens, NextCode(ATokens, AIndex + 1));
end;

/// <summary>Beendet AToken auf oberster Klammerebene den Operanden eines Vergleichs?</summary>
function EndsOperand(const AToken: TPascalToken): Boolean;
begin
  Result := (AToken.Kind = TPascalTokenKind.Keyword) and MatchText(AToken.Text, ['then', 'do', 'of', 'else',
    'until', 'end', 'to', 'downto', 'and', 'or', 'xor', 'in', 'begin', 'except', 'finally']);
  Result := Result or ((AToken.Kind = TPascalTokenKind.Symbol) and MatchStr(AToken.Text, [';', ',', ':=', ':'])) or
    IsComparison(AToken);
end;

function OperandEnd(const ATokens: TArray<TPascalToken>; AStart: Integer): Integer;
var
  mIndex, mDepth: Integer;
begin
  Result := -1;
  mDepth := 0;
  for mIndex := AStart to High(ATokens) do
  begin
    if IsTrivia(ATokens[mIndex]) then
    begin
      Continue;
    end;
    if ATokens[mIndex].IsSymbol('(') or ATokens[mIndex].IsSymbol('[') then
    begin
      Inc(mDepth);
    end
    else if ATokens[mIndex].IsSymbol(')') or ATokens[mIndex].IsSymbol(']') then
    begin
      if mDepth = 0 then
      begin
        Exit;
      end;
      Dec(mDepth);
    end
    else if (mDepth = 0) and EndsOperand(ATokens[mIndex]) then
    begin
      Exit;
    end;
    Result := mIndex;
  end;
end;

/// <summary>Liegt APosition bei oder hinter AStart?</summary>
function AtOrAfter(const APosition, AStart: TTextPosition): Boolean;
begin
  Result := (AStart.Line < APosition.Line) or ((AStart.Line = APosition.Line) and
    (AStart.Character <= APosition.Character));
end;

/// <summary>Ist ANode ein Block, der APosition enthält?</summary>
function BlockContains(ANode: TSyntaxNode; const APosition: TTextPosition): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Block) and AtOrAfter(APosition, ANode.StartPos) and
    not AtOrAfter(APosition, ANode.EndPos);
end;

function InStatements(ATree: TSyntaxTree; const APosition: TTextPosition): Boolean;
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  Result := False;
  if ATree.Root = nil then
  begin
    Exit;
  end;
  // Iterativ (Bericht M1).
  mPending := TStack<TSyntaxNode>.Create;
  try
    for mIndex := ATree.Root.ChildCount - 1 downto 0 do
    begin
      mPending.Push(ATree.Root[mIndex]);
    end;
    while not Result and (mPending.Count > 0) do
    begin
      mNode := mPending.Pop;
      Result := BlockContains(mNode, APosition);
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

function NotComparisonAt(const ATokens: TArray<TPascalToken>; AIndex: Integer; out AParts: TNotComparison): Boolean;
begin
  AParts := Default(TNotComparison);
  AParts.NotToken := AIndex;
  Result := ATokens[AIndex].IsKeyword('not');
  if not Result then
  begin
    Exit;
  end;
  AParts.Operand := NextCode(ATokens, AIndex + 1);
  AParts.Op := NextCode(ATokens, AParts.Operand + 1);
  Result := IsPlainIdentifier(ATokens, AParts.Operand) and (AParts.Op <= High(ATokens)) and
    (ATokens[AParts.Op].IsKeyword('in') or IsComparison(ATokens[AParts.Op]));
  if Result then
  begin
    AParts.Right := NextCode(ATokens, AParts.Op + 1);
    AParts.Last := OperandEnd(ATokens, AParts.Right);
    Result := AParts.Last >= AParts.Right;
  end;
end;

/// <summary>Zeichen des Abschnitts '…' ab AIndex (auf dem Apostroph); '''' zählt als ein Zeichen. AIndex
/// steht danach hinter dem schließenden Apostroph.</summary>
function QuotedLength(const ALiteral: string; var AIndex: Integer): Integer;
begin
  Result := 0;
  Inc(AIndex);
  while AIndex <= Length(ALiteral) do
  begin
    // '' im Literal ist ein Apostroph, sonst endet der Abschnitt.
    if (ALiteral[AIndex] = '''') and ((AIndex = Length(ALiteral)) or (ALiteral[AIndex + 1] <> '''')) then
    begin
      Break;
    end;
    if ALiteral[AIndex] = '''' then
    begin
      Inc(AIndex);
    end;
    Inc(Result);
    Inc(AIndex);
  end;
  Inc(AIndex);
end;

/// <summary>Liest #n ab AIndex (auf dem #); False, wenn n keine Zahl ist. AIndex steht danach hinter n.</summary>
function ReadCharCode(const ALiteral: string; var AIndex: Integer): Boolean;
var
  mDigits: string;
  mValue: Integer;
begin
  Inc(AIndex);
  mDigits := '';
  while (AIndex <= Length(ALiteral)) and CharInSet(ALiteral[AIndex], ['$', '0'..'9', 'A'..'F', 'a'..'f', '_']) do
  begin
    if ALiteral[AIndex] <> '_' then
    begin
      mDigits := mDigits + ALiteral[AIndex];
    end;
    Inc(AIndex);
  end;
  Result := TryStrToInt(mDigits, mValue);
end;

function PascalLiteralLength(const ALiteral: string): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  mIndex := 1;
  while (Result >= 0) and (mIndex <= Length(ALiteral)) do
  begin
    if ALiteral[mIndex] = '''' then
    begin
      Inc(Result, QuotedLength(ALiteral, mIndex));
    end
    else if (ALiteral[mIndex] = '#') and ReadCharCode(ALiteral, mIndex) then
    begin
      Inc(Result);
    end
    else
    begin
      Result := -1;
    end;
  end;
end;

end.
