unit Atlas.Common.Mutation.Generator;

// Erzeugt die Mutanten einer Unit aus dem Syntaxbaum (#1460), nie durch
// Textersetzen. Jeder Mutant verändert genau eine Stelle; die Operatoren
// stehen in Atlas.Common.Mutation.Contract.
//
// Mutiert wird nur in Rümpfen von Routinen (begin … end, auch lokale
// Routinen und anonyme Methoden darin), nicht in asm-Blöcken. Ausgenommen:
//   - Code in inaktiven Zweigen der bedingten Kompilierung: Der Baum kommt
//     aus den aktiven Zweigen unter TMutationOptions.Defines.
//   - Assert und Protokollaufrufe samt ihrer Argumente: Aufrufe, deren Ziel
//     einen Namen wie Log, Logger, FLogger, LogInfo oder OutputDebugString
//     enthält (Login dagegen nicht).
//   - Zeilen mit "// atlas-ignore: mutation" (auch lsp-ignore) am Ende oder
//     in der Zeile darüber; steht der Kommentar am Kopf einer Routine oder
//     darüber, die ganze Routine.
//   - Marken von case-Zweigen (doppelte Marken übersetzen nicht).
//   - + und - mit einem String-Literal als Operand (- gibt es für Strings
//     nicht).
//   - Exit, Break und Continue als „Anweisung entfernen“; Exit(x) wird nur
//     in Funktionen mit Ergebnistyp im Kopf zu Exit(Default(Typ)), nicht in
//     anonymen Methoden und nicht, wenn x schon wie ein Vorgabewert aussieht
//     (nil, 0, False, '', Default(…)).
// Die Mutanten stehen nach Position im Quelltext; Id zählt ab 1.

interface

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Mutation.Contract;

type
  TMutationGenerator = class
  public
    /// <summary>Mutanten von AText unter AOptions (Baum aus den aktiven Zweigen unter AOptions.Defines).
    /// </summary>
    class function ForText(const AText: string; const AOptions: TMutationOptions): TArray<TMutant>; static;
    /// <summary>Mutanten aus einem schon geparsten Baum ATree von AText; AOptions.Defines bleibt hier ohne
    /// Wirkung.</summary>
    class function ForTree(ATree: TSyntaxTree; const AText: string; const AOptions: TMutationOptions):
      TArray<TMutant>; static;
    /// <summary>Ist ANode (Ziel eines Aufrufs) Assert oder ein Protokollaufruf?</summary>
    class function IsQuietTarget(ANode: TSyntaxNode): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Pascal.TreeCache;

const
  cStatementKinds = [TSyntaxKind.Block, TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement,
    TSyntaxKind.IfStatement, TSyntaxKind.CaseStatement, TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement,
    TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement, TSyntaxKind.WithStatement, TSyntaxKind.TryStatement,
    TSyntaxKind.RaiseStatement, TSyntaxKind.GotoStatement, TSyntaxKind.LabeledStatement, TSyntaxKind.InlineVar,
    TSyntaxKind.InlineConst, TSyntaxKind.EmptyStatement];
  /// <summary>Anweisungen, die „Anweisung entfernen“ nicht anfasst: Sie steuern den Ablauf.</summary>
  cFlowCalls: array[0..2] of string = ('Exit', 'Break', 'Continue');
  /// <summary>Weitere Ziele, die als Protokollaufruf gelten.</summary>
  cQuietNames: array[0..1] of string = ('Assert', 'OutputDebugString');
  cIgnoreMarkers: array[0..1] of string = ('atlas-ignore:', 'lsp-ignore:');

type
  /// <summary>Eintrag des Stapels beim Durchlauf eines Rumpfs.</summary>
  TWalkEntry = record
    Node: TSyntaxNode;
    /// <summary>Innerhalb einer anonymen Methode: Exit meint deren Ergebnis.</summary>
    InAnonymous: Boolean;
    class function Create(ANode: TSyntaxNode; AInAnonymous: Boolean): TWalkEntry; static;
  end;

  /// <summary>Ein Lauf über einen Baum.</summary>
  TMutationRun = class
  private
    FTree: TSyntaxTree;
    FText: string;
    FOptions: TMutationOptions;
    FIgnored: TDictionary<Integer, Boolean>;
    FMutants: TList<TMutant>;
    FRoutine: string;
    FResultType: string;
    procedure CollectIgnoredLines;
    function IsIgnored(ALine: Integer): Boolean;
    function TextOf(ANode: TSyntaxNode): string;
    procedure Add(AOperator: TMutationOperator; const AStartPos, AEndPos: TTextPosition; AStartOffset,
      AEndOffset: Integer; const AReplacement: string);
    procedure AddNode(AOperator: TMutationOperator; ANode: TSyntaxNode; const AReplacement: string);
    procedure Routine(ARoutine: TSyntaxNode; const AName: string);
    procedure WalkBody(ABody: TSyntaxNode);
    procedure Visit(const AEntry: TWalkEntry; AStack: TStack<TWalkEntry>);
    procedure Statement(ANode: TSyntaxNode; AInAnonymous: Boolean);
    procedure Binary(ANode: TSyntaxNode);
    procedure Unary(ANode: TSyntaxNode);
    procedure Leaf(ANode: TSyntaxNode);
    procedure ExitDefault(ACall: TSyntaxNode);
    function OperatorToken(ANode: TSyntaxNode; out AToken: TPascalToken): Boolean;
    function Wanted(const AName: string): Boolean;
  public
    constructor Create(ATree: TSyntaxTree; const AText: string; const AOptions: TMutationOptions);
    destructor Destroy; override;
    function Run: TArray<TMutant>;
  end;

{ TWalkEntry }

class function TWalkEntry.Create(ANode: TSyntaxNode; AInAnonymous: Boolean): TWalkEntry;
begin
  Result.Node := ANode;
  Result.InAnonymous := AInAnonymous;
end;

{ Hilfsfunktionen }

/// <summary>Rumpf (Block) einer Routine; nil ohne Rumpf oder mit asm-Rumpf.</summary>
function BodyOf(ARoutine: TSyntaxNode): TSyntaxNode;
var
  mIndex: Integer;
begin
  for mIndex := ARoutine.ChildCount - 1 downto 0 do
  begin
    if ARoutine[mIndex].Kind = TSyntaxKind.Block then
    begin
      Exit(ARoutine[mIndex]);
    end;
  end;
  Result := nil;
end;

/// <summary>Name ohne Präfix T, F, I, A, G oder m vor einem Großbuchstaben (FLogger → Logger).</summary>
function WithoutPrefix(const AName: string): string;
begin
  Result := AName;
  if (Length(Result) > 1) and CharInSet(Result[1], ['T', 'F', 'I', 'A', 'G', 'm']) and
    CharInSet(Result[2], ['A'..'Z']) then
  begin
    Result := Copy(Result, 2, MaxInt);
  end;
end;

/// <summary>Log, Logger, Logging, LogInfo …, nicht Login oder Logic.</summary>
function IsLogName(const AName: string): Boolean;
var
  mName: string;
begin
  mName := WithoutPrefix(AName);
  if not StartsText('Log', mName) then
  begin
    Exit(False);
  end;
  Result := (Length(mName) = 3) or CharInSet(mName[4], ['A'..'Z', '_']) or StartsText('Logger', mName) or
    StartsText('Logging', mName) or StartsText('Logs', mName);
end;

function IsQuietName(const AName: string): Boolean;
begin
  Result := IsLogName(AName) or (IndexText(AName, cQuietNames) >= 0);
end;

function IsStringLiteral(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Literal) and (ANode.Name <> '') and CharInSet(ANode.Name[1], ['''', '#']);
end;

/// <summary>Sieht AText wie ein Vorgabewert aus (nil, 0, False, '', Default(…))?</summary>
function LooksDefault(const AText: string): Boolean;
var
  mText: string;
begin
  mText := Trim(AText);
  Result := SameText(mText, 'nil') or (mText = '0') or SameText(mText, 'False') or (mText = '''''') or
    StartsText('Default(', mText) or (mText = '0.0');
end;

/// <summary>Neuer Operator zu AOperator (Kleinschreibung) und Art; False ohne Gegenstück.</summary>
function Swapped(const AOperator: string; out AReplacement: string; out AKind: TMutationOperator): Boolean;
const
  cPairs: array[0..9, 0..1] of string = (('<', '<='), ('<=', '<'), ('>', '>='), ('>=', '>'), ('=', '<>'),
    ('<>', '='), ('and', 'or'), ('or', 'and'), ('+', '-'), ('-', '+'));
  cKinds: array[0..9] of TMutationOperator = (TMutationOperator.Boundary, TMutationOperator.Boundary,
    TMutationOperator.Boundary, TMutationOperator.Boundary, TMutationOperator.Equality, TMutationOperator.Equality,
    TMutationOperator.Logical, TMutationOperator.Logical, TMutationOperator.Arithmetic,
    TMutationOperator.Arithmetic);
var
  mIndex: Integer;
begin
  for mIndex := Low(cPairs) to High(cPairs) do
  begin
    if cPairs[mIndex, 0] = AOperator then
    begin
      AReplacement := cPairs[mIndex, 1];
      AKind := cKinds[mIndex];
      Exit(True);
    end;
  end;
  AReplacement := '';
  AKind := TMutationOperator.Boundary;
  Result := False;
end;

/// <summary>AReplacement in der Schreibweise von AOriginal (AND → OR, false → true).</summary>
function SameCase(const AOriginal, AReplacement: string): string;
begin
  if (AOriginal <> '') and (AOriginal = UpperCase(AOriginal)) and (AOriginal <> LowerCase(AOriginal)) then
  begin
    Result := UpperCase(AReplacement);
  end
  else if (AOriginal = LowerCase(AOriginal)) and (AOriginal <> UpperCase(AOriginal)) then
  begin
    Result := LowerCase(AReplacement);
  end
  else
  begin
    Result := AReplacement;
  end;
end;

{ TMutationRun }

constructor TMutationRun.Create(ATree: TSyntaxTree; const AText: string; const AOptions: TMutationOptions);
begin
  inherited Create;
  FTree := ATree;
  FText := AText;
  FOptions := AOptions;
  FIgnored := TDictionary<Integer, Boolean>.Create;
  FMutants := TList<TMutant>.Create;
end;

destructor TMutationRun.Destroy;
begin
  FMutants.Free;
  FIgnored.Free;
  inherited;
end;

procedure TMutationRun.CollectIgnoredLines;
var
  mToken: TPascalToken;
  mText, mMarker: string;
  mAt: Integer;
begin
  for mToken in FTree.Tokens do
  begin
    if mToken.Kind <> TPascalTokenKind.Comment then
    begin
      Continue;
    end;
    mText := LowerCase(mToken.Text);
    for mMarker in cIgnoreMarkers do
    begin
      mAt := Pos(mMarker, mText);
      if (mAt > 0) and ContainsText(Copy(mText, mAt + Length(mMarker), MaxInt), TMutation.cIgnoreId) then
      begin
        FIgnored.AddOrSetValue(mToken.StartPos.Line, True);
        FIgnored.AddOrSetValue(mToken.EndPos.Line + 1, True);
      end;
    end;
  end;
end;

function TMutationRun.IsIgnored(ALine: Integer): Boolean;
begin
  Result := FIgnored.ContainsKey(ALine);
end;

function TMutationRun.TextOf(ANode: TSyntaxNode): string;
begin
  Result := Copy(FText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

function TMutationRun.Wanted(const AName: string): Boolean;
var
  mDot: Integer;
begin
  if FOptions.Routine = '' then
  begin
    Exit(True);
  end;
  mDot := LastDelimiter('.', AName);
  Result := SameText(AName, FOptions.Routine) or SameText(Copy(AName, mDot + 1, MaxInt), FOptions.Routine);
end;

procedure TMutationRun.Add(AOperator: TMutationOperator; const AStartPos, AEndPos: TTextPosition; AStartOffset,
  AEndOffset: Integer; const AReplacement: string);
var
  mMutant: TMutant;
begin
  if not (AOperator in FOptions.Operators) or IsIgnored(AStartPos.Line) then
  begin
    Exit;
  end;
  if ((FOptions.FirstLine >= 0) and (AStartPos.Line < FOptions.FirstLine)) or
    ((FOptions.LastLine >= 0) and (AStartPos.Line > FOptions.LastLine)) then
  begin
    Exit;
  end;
  mMutant := Default(TMutant);
  mMutant.Operator := AOperator;
  mMutant.Routine := FRoutine;
  mMutant.Range := TTextRange.Create(AStartPos, AEndPos);
  mMutant.StartOffset := AStartOffset;
  mMutant.EndOffset := AEndOffset;
  mMutant.Original := Copy(FText, AStartOffset + 1, AEndOffset - AStartOffset);
  mMutant.Replacement := AReplacement;
  FMutants.Add(mMutant);
end;

procedure TMutationRun.AddNode(AOperator: TMutationOperator; ANode: TSyntaxNode; const AReplacement: string);
begin
  Add(AOperator, ANode.StartPos, ANode.EndPos, ANode.StartOffset, ANode.EndOffset, AReplacement);
end;

function TMutationRun.OperatorToken(ANode: TSyntaxNode; out AToken: TPascalToken): Boolean;
var
  mIndex, mUntil: Integer;
  mTokens: TArray<TPascalToken>;
begin
  mTokens := FTree.Tokens;
  mIndex := FTree.FirstTokenFrom(ANode[0].EndOffset);
  mUntil := ANode[1].StartOffset;
  while (mIndex <= High(mTokens)) and (mTokens[mIndex].Offset < mUntil) do
  begin
    if SameText(mTokens[mIndex].Text, ANode.Name) and
      (mTokens[mIndex].Kind in [TPascalTokenKind.Symbol, TPascalTokenKind.Keyword]) then
    begin
      AToken := mTokens[mIndex];
      Exit(True);
    end;
    Inc(mIndex);
  end;
  AToken := Default(TPascalToken);
  Result := False;
end;

procedure TMutationRun.Binary(ANode: TSyntaxNode);
var
  mToken: TPascalToken;
  mReplacement: string;
  mKind: TMutationOperator;
  mArithmetic: Boolean;
begin
  if (ANode.ChildCount <> 2) or not Swapped(LowerCase(ANode.Name), mReplacement, mKind) then
  begin
    Exit;
  end;
  mArithmetic := mKind = TMutationOperator.Arithmetic;
  if mArithmetic and (IsStringLiteral(ANode[0]) or IsStringLiteral(ANode[1])) then
  begin
    Exit;
  end;
  if OperatorToken(ANode, mToken) then
  begin
    Add(mKind, mToken.StartPos, mToken.EndPos, mToken.Offset, mToken.Offset + Length(mToken.Text),
      SameCase(mToken.Text, mReplacement));
  end;
  // x + 1 bzw. x - 1 → x
  if mArithmetic and (ANode[1].Kind = TSyntaxKind.Literal) and (ANode[1].Name = '1') then
  begin
    AddNode(TMutationOperator.RemoveIncrement, ANode, TextOf(ANode[0]));
  end;
end;

procedure TMutationRun.Unary(ANode: TSyntaxNode);
begin
  if SameText(ANode.Name, 'not') and (ANode.ChildCount = 1) then
  begin
    AddNode(TMutationOperator.RemoveNot, ANode, TextOf(ANode[0]));
  end;
end;

procedure TMutationRun.Leaf(ANode: TSyntaxNode);
begin
  if ANode.Kind = TSyntaxKind.Identifier then
  begin
    if SameText(ANode.Name, 'True') then
    begin
      AddNode(TMutationOperator.BooleanLiteral, ANode, SameCase(ANode.Name, 'False'));
    end
    else if SameText(ANode.Name, 'False') then
    begin
      AddNode(TMutationOperator.BooleanLiteral, ANode, SameCase(ANode.Name, 'True'));
    end;
  end
  else if ANode.Name = '0' then
  begin
    AddNode(TMutationOperator.NumberLiteral, ANode, '1');
  end
  else if ANode.Name = '1' then
  begin
    AddNode(TMutationOperator.NumberLiteral, ANode, '0');
  end;
end;

procedure TMutationRun.ExitDefault(ACall: TSyntaxNode);
var
  mArgument: TSyntaxNode;
begin
  if (FResultType = '') or (ACall.ChildCount <> 2) then
  begin
    Exit;
  end;
  mArgument := ACall[1];
  if LooksDefault(TextOf(mArgument)) then
  begin
    Exit;
  end;
  AddNode(TMutationOperator.ExitDefault, mArgument, 'Default(' + FResultType + ')');
end;

/// <summary>Ziel eines Aufrufs in einer Aufrufanweisung: bei Call dessen erstes Kind, sonst der Ausdruck.
/// </summary>
function CallTarget(AStatement: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if AStatement.ChildCount = 0 then
  begin
    Exit;
  end;
  Result := AStatement[0];
  if (Result.Kind = TSyntaxKind.Call) and (Result.ChildCount > 0) then
  begin
    Result := Result[0];
  end;
end;

procedure TMutationRun.Statement(ANode: TSyntaxNode; AInAnonymous: Boolean);
var
  mTarget: TSyntaxNode;
begin
  if ANode.Kind = TSyntaxKind.AssignStatement then
  begin
    AddNode(TMutationOperator.RemoveStatement, ANode, '');
    Exit;
  end;
  mTarget := CallTarget(ANode);
  if (mTarget <> nil) and (mTarget.Kind = TSyntaxKind.Identifier) and SameText(mTarget.Name, 'Exit') then
  begin
    if not AInAnonymous and (ANode[0].Kind = TSyntaxKind.Call) then
    begin
      ExitDefault(ANode[0]);
    end;
    Exit;
  end;
  if IndexText(ANode.Name, cFlowCalls) < 0 then
  begin
    AddNode(TMutationOperator.RemoveStatement, ANode, '');
  end;
end;

class function TMutationGenerator.IsQuietTarget(ANode: TSyntaxNode): Boolean;
var
  mNode: TSyntaxNode;
begin
  mNode := ANode;
  while mNode <> nil do
  begin
    case mNode.Kind of
      TSyntaxKind.Identifier:
        Exit(IsQuietName(mNode.Name));
      TSyntaxKind.MemberAccess, TSyntaxKind.Call, TSyntaxKind.IndexAccess, TSyntaxKind.Dereference,
        TSyntaxKind.GenericArgs:
        begin
          if (mNode.Kind = TSyntaxKind.MemberAccess) and IsQuietName(mNode.Name) then
          begin
            Exit(True);
          end;
          if mNode.ChildCount = 0 then
          begin
            Exit(False);
          end;
          mNode := mNode[0];
        end;
    else
      Exit(False);
    end;
  end;
  Result := False;
end;

procedure TMutationRun.Visit(const AEntry: TWalkEntry; AStack: TStack<TWalkEntry>);
var
  mNode: TSyntaxNode;
  mIndex: Integer;
  mInAnonymous: Boolean;
begin
  mNode := AEntry.Node;
  mInAnonymous := AEntry.InAnonymous;
  case mNode.Kind of
    TSyntaxKind.AsmBlock, TSyntaxKind.RoutineDecl:
      Exit;
    TSyntaxKind.AnonymousMethod:
      mInAnonymous := True;
    TSyntaxKind.CallStatement:
      begin
        if TMutationGenerator.IsQuietTarget(CallTarget(mNode)) then
        begin
          Exit;
        end;
        Statement(mNode, mInAnonymous);
      end;
    TSyntaxKind.AssignStatement:
      Statement(mNode, mInAnonymous);
    TSyntaxKind.BinaryExpr:
      Binary(mNode);
    TSyntaxKind.UnaryExpr:
      Unary(mNode);
    TSyntaxKind.Identifier, TSyntaxKind.Literal:
      Leaf(mNode);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
  for mIndex := mNode.ChildCount - 1 downto 0 do
  begin
    // Marken eines case-Zweigs bleiben, nur seine Anweisungen zählen.
    if (mNode.Kind = TSyntaxKind.CaseItem) and not (mNode[mIndex].Kind in cStatementKinds) then
    begin
      Continue;
    end;
    // Exit selbst ist kein Wahrheitswert oder Zahl: nur die Argumente besuchen.
    AStack.Push(TWalkEntry.Create(mNode[mIndex], mInAnonymous));
  end;
end;

procedure TMutationRun.WalkBody(ABody: TSyntaxNode);
var
  mStack: TStack<TWalkEntry>;
begin
  mStack := TStack<TWalkEntry>.Create;
  try
    mStack.Push(TWalkEntry.Create(ABody, False));
    while mStack.Count > 0 do
    begin
      Visit(mStack.Pop, mStack);
    end;
  finally
    mStack.Free;
  end;
end;

/// <summary>Ergebnistyp im Kopf von ARoutine als Text; '' ohne (Prozedur oder Kurzform ohne Signatur).</summary>
function ResultTypeOf(ARoutine: TSyntaxNode; const AText: string): string;
var
  mHeader, mType: TSyntaxNode;
begin
  Result := '';
  mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  if mHeader = nil then
  begin
    Exit;
  end;
  mType := mHeader.FindChild(TSyntaxKind.TypeReference);
  if mType <> nil then
  begin
    Result := Trim(Copy(AText, mType.StartOffset + 1, mType.EndOffset - mType.StartOffset));
  end;
end;

procedure TMutationRun.Routine(ARoutine: TSyntaxNode; const AName: string);
var
  mBody: TSyntaxNode;
  mIndex: Integer;
begin
  for mIndex := 0 to ARoutine.ChildCount - 1 do
  begin
    if ARoutine[mIndex].Kind = TSyntaxKind.RoutineDecl then
    begin
      Routine(ARoutine[mIndex], AName + '.' + ARoutine[mIndex].Name);
    end;
  end;
  mBody := BodyOf(ARoutine);
  if (mBody = nil) or not Wanted(AName) or IsIgnored(ARoutine.StartPos.Line) then
  begin
    Exit;
  end;
  FRoutine := AName;
  FResultType := ResultTypeOf(ARoutine, FText);
  WalkBody(mBody);
end;

function TMutationRun.Run: TArray<TMutant>;
var
  mStack: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  CollectIgnoredLines;
  mStack := TStack<TSyntaxNode>.Create;
  try
    mStack.Push(FTree.Root);
    while mStack.Count > 0 do
    begin
      mNode := mStack.Pop;
      if mNode.Kind = TSyntaxKind.RoutineDecl then
      begin
        Routine(mNode, mNode.Name);
        Continue;
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mStack.Push(mNode[mIndex]);
      end;
    end;
  finally
    mStack.Free;
  end;
  FMutants.Sort(TComparer<TMutant>.Construct(
    function(const A, B: TMutant): Integer
    begin
      Result := A.StartOffset - B.StartOffset;
      if Result = 0 then
      begin
        Result := Ord(A.Operator) - Ord(B.Operator);
      end;
      if Result = 0 then
      begin
        Result := A.EndOffset - B.EndOffset;
      end;
    end));
  Result := FMutants.ToArray;
  for mIndex := 0 to High(Result) do
  begin
    Result[mIndex].Id := mIndex + 1;
  end;
end;

{ TMutationGenerator }

class function TMutationGenerator.ForTree(ATree: TSyntaxTree; const AText: string;
  const AOptions: TMutationOptions): TArray<TMutant>;
var
  mRun: TMutationRun;
begin
  mRun := TMutationRun.Create(ATree, AText, AOptions);
  try
    Result := mRun.Run;
  finally
    mRun.Free;
  end;
end;

class function TMutationGenerator.ForText(const AText: string; const AOptions: TMutationOptions): TArray<TMutant>;
var
  mTree: TSyntaxTree;
  mPreprocessor: TPreprocessorOptions;
  mProcessed: TPreprocessorResult;
begin
  // Wie der Baum im Editor: ohne Symbole die Vordefinitionen (Win32, Delphi 13).
  mPreprocessor := TPascalPreprocessor.EditorOptions(AOptions.Defines);
  mTree := TSyntaxTreeCache.ParseActive(AText, mPreprocessor, nil, mProcessed);
  try
    Result := ForTree(mTree, AText, AOptions);
  finally
    mTree.Free;
  end;
end;

end.
