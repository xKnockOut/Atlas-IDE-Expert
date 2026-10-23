unit Atlas.Common.Editing.VarBlock;

// var-Block pflegen (#644, refactoring.varBlock): drei Glühbirnen rund um die
// lokalen Variablen einer Routine.
//   - „In Inline-Variable umwandeln“ auf einer Variablen des var-Abschnitts:
//     Die Deklaration wandert vor die Anweisung mit der ersten Verwendung, und
//     zwar in die innerste Anweisungsliste (begin … end, try-Teil, finally,
//     except ohne Handler, repeat, case-else), deren Rest alle Verwendungen
//     enthält. Ist diese Anweisung X := E und liest E X nicht, wird daraus
//     var X: T := E (var X := E, wenn E offensichtlich den Typ T hat); sonst
//     steht var X: T; davor, aber nie in einer Schleife (jeder Durchlauf
//     begänne mit einer neuen Variablen). Nicht bei Verwendungen in
//     verschachtelten Routinen oder anonymen Methoden (Capture), bei
//     bedingter Übersetzung, absolute und goto. Ob die Sprachversion
//     Inline-Variablen kennt, prüft der Aufrufer (TVarBlockOptions).
//   - „In var-Block verschieben“ auf einer Inline-Variablen: Eintrag X: T im
//     var-Abschnitt; aus var X := E wird X := E, var X: T; entfällt. Den Typ
//     von var X := E liefert der Aufrufer (TVarBlockTypeLookup, #453). Nicht,
//     wenn der Name in der Routine sonst etwas anderes meint (anderer lokaler
//     Name, derselbe Bezeichner außerhalb des Gültigkeitsbereichs), bei
//     Capture und für var X: T; ohne Startwert in einer Schleife. Verwaltete
//     Werte (Strings, Interfaces) leben danach bis zum Ende der Routine.
//   - „var-Block aufräumen“ im var-Abschnitt einer Routine: ungenutzte
//     Variablen entfernen (#91), Einträge nach erster Verwendung oder
//     alphabetisch sortieren und aufeinanderfolgende gleichen Typs
//     zusammenfassen (I, J: Integer) bzw. ohne merge trennen. Zusammengefasst
//     und getrennt werden nur benannte Typen: Zwei Einträge array of Integer
//     sind zwei verschiedene Typen, einer mit zwei Namen ist einer.
// Kommentare über einer Variablen und am Zeilenende wandern mit. Beim
// Aufräumen gehören alle Kommentarzeilen zwischen zwei Einträgen zum
// folgenden; Einträge mit Kommentar werden weder zusammengefasst noch
// getrennt.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Editing.CodeActions;

type
{$SCOPEDENUMS ON}
  /// <summary>Einstellung refactoring.varBlockSort: erste Verwendung, alphabetisch, wie bisher.</summary>
  TVarBlockSort = (Usage, Alpha, None);
{$SCOPEDENUMS OFF}

  /// <summary>Typ der Inline-Variablen ADecl ohne Typangabe (var X := E) und Edits, die ihn sichtbar machen
  /// (uses); False, wenn er sich nicht ermitteln lässt.</summary>
  TVarBlockTypeLookup = reference to function(ADecl: TSyntaxNode; out AType: string;
    out AEdits: TArray<TTextEdit>): Boolean;

  TVarBlockOptions = record
    /// <summary>„In Inline-Variable umwandeln“ anbieten (Sprachversion ab 10.3).</summary>
    InlineVariables: Boolean;
    /// <summary>Gleiche Typen beim Aufräumen zusammenfassen; False trennt sie.</summary>
    Merge: Boolean;
    Sort: TVarBlockSort;
    Style: TFormatStyle;
    /// <summary>Übergabeart von Argumenten (nil: nur die Datei und die Standardroutinen).</summary>
    Lookup: TFlowSignatureLookup;
    /// <summary>Typ von var X := E; nil: nur Inline-Variablen mit Typangabe.</summary>
    Types: TVarBlockTypeLookup;
    class function Default: TVarBlockOptions; static;
  end;

  TVarBlock = class
  public const
    SortNames: array[TVarBlockSort] of string = ('usage', 'alpha', 'none');
  public
    /// <summary>Sortierung zum Namen der Einstellung; usage bei unbekanntem.</summary>
    class function SortOf(const AName: string): TVarBlockSort; static;
    /// <summary>Aktionen an APosition: Umwandeln an einer Variablen, Aufräumen im var-Abschnitt einer Routine.
    /// </summary>
    class function Actions(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const AOptions: TVarBlockOptions): TArray<TCodeAction>; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Semantics.Reassigned,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.RoutineLocals;

const
  LoopKinds = [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
    TSyntaxKind.RepeatStatement];
  ConditionalWords: array[0..7] of string = ('IF', 'IFDEF', 'IFNDEF', 'IFOPT', 'ELSE', 'ELSEIF', 'ENDIF', 'IFEND');
  /// <summary>Typen, die ein Inline-Eintrag übernehmen kann; Records, Aufzählungen usw. bleiben im Abschnitt.
  /// </summary>
  InlineTypeKinds = [TSyntaxKind.TypeReference, TSyntaxKind.ArrayType, TSyntaxKind.SetType,
    TSyntaxKind.PointerType, TSyntaxKind.ProcedureType];

type
  /// <summary>Zeilen des Textes: Enthält eine Zeile Code, einen Kommentar, beginnt dort ein Kommentar als
  /// Erstes?</summary>
  TLineInfo = record
    Lines: TArray<string>;
    Code: TArray<Boolean>;
    Comment: TArray<Boolean>;
    CommentStarts: TArray<Boolean>;
  end;

  /// <summary>Eintrag des var-Abschnitts beim Aufräumen.</summary>
  TVarEntry = record
    Decl: TSyntaxNode;
    Names: TArray<string>;
    TypeText: string;
    /// <summary>Der Typ hat einen Namen: zusammenfassen und trennen erlaubt.</summary>
    Named: Boolean;
    Comments: TArray<string>;
    Trailing: string;
    /// <summary>Erste Zeile samt Kommentaren darüber; Ende samt Kommentar dahinter.</summary>
    FirstLine: Integer;
    EndPos: TTextPosition;
    EndLine: Integer;
  end;

  /// <summary>Zeile des aufgeräumten Abschnitts: ein oder mehrere Namen eines Typs.</summary>
  TVarItem = record
    Names: TArray<string>;
    TypeText: string;
    Named: Boolean;
    Comments: TArray<string>;
    Trailing: string;
    /// <summary>Offset der ersten Verwendung; Reihenfolge im Abschnitt.</summary>
    FirstUse: Integer;
    Order: Integer;
  end;

{ TVarBlockOptions }

class function TVarBlockOptions.Default: TVarBlockOptions;
begin
  Result.InlineVariables := True;
  Result.Merge := True;
  Result.Sort := TVarBlockSort.Usage;
  Result.Style := TFormatStyle.Default;
  Result.Lookup := nil;
  Result.Types := nil;
end;

{ Hilfen }

function CleanName(const AText: string): string;
begin
  Result := AText;
  if StartsStr('&', Result) then
    Result := Copy(Result, 2, MaxInt);
end;

/// <summary>Innerste Routine (benannt oder anonym), in der ANode steht.</summary>
function OwnerRoutine(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode.Parent;
  while (Result <> nil) and not (Result.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) do
    Result := Result.Parent;
end;

/// <summary>Liegt ANode unterhalb von ABody in einer Schleife?</summary>
function InLoop(ANode, ABody: TSyntaxNode): Boolean;
var
  Node: TSyntaxNode;
begin
  Result := False;
  Node := ANode.Parent;
  while (Node <> nil) and (Node <> ABody) do
  begin
    if Node.Kind in LoopKinds then
      Exit(True);
    Node := Node.Parent;
  end;
end;

/// <summary>Bedingte Übersetzung ({$IFDEF …}, {$ELSE}, {$ENDIF} …) im Bereich [AFrom, ATo).</summary>
function HasConditional(const ATokens: TArray<TPascalToken>; AFrom, ATo: Integer): Boolean;
var
  Token: TPascalToken;
  Text: string;
  Stop: Integer;
begin
  Result := False;
  for Token in ATokens do
    if (Token.Kind = TPascalTokenKind.Directive) and (Token.Offset >= AFrom) and (Token.Offset < ATo) then
    begin
      Text := Token.Text;
      if StartsStr('{$', Text) then
        Text := Copy(Text, 3, MaxInt)
      else
        Text := Copy(Text, 4, MaxInt);
      Stop := 1;
      while (Stop <= Length(Text)) and CharInSet(Text[Stop], ['A'..'Z', 'a'..'z']) do
        Inc(Stop);
      if MatchText(Copy(Text, 1, Stop - 1), ConditionalWords) then
        Exit(True);
    end;
end;

/// <summary>Index des ersten Tokens in [AFrom, ATo) mit dem Text AWord (Bezeichner, Schlüsselwort oder Symbol,
/// Groß-/Kleinschreibung egal); -1 ohne.</summary>
function FindToken(const ATokens: TArray<TPascalToken>; AFrom, ATo: Integer; const AWord: string): Integer;
var
  Index: Integer;
begin
  Result := -1;
  Index := TRoutineBody.TokenAt(ATokens, AFrom);
  while (Index <= High(ATokens)) and (ATokens[Index].Offset < ATo) do
  begin
    if (ATokens[Index].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword, TPascalTokenKind.Symbol]) and
      SameText(ATokens[Index].Text, AWord) then
      Exit(Index);
    Inc(Index);
  end;
end;

/// <summary>Offset des ersten Bezeichners AName (nicht hinter einem Punkt) in [AFrom, ATo) außerhalb von
/// [ASkipFrom, ASkipTo); -1 ohne.</summary>
function WordOffset(const ATokens: TArray<TPascalToken>; const AName: string; AFrom, ATo, ASkipFrom,
  ASkipTo: Integer): Integer;
var
  Index, Previous: Integer;
begin
  Result := -1;
  Index := TRoutineBody.TokenAt(ATokens, AFrom);
  while (Index <= High(ATokens)) and (ATokens[Index].Offset < ATo) do
  begin
    if (ATokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(CleanName(ATokens[Index].Text), AName) and
      ((ATokens[Index].Offset < ASkipFrom) or (ATokens[Index].Offset >= ASkipTo)) then
    begin
      Previous := TRoutineBody.PreviousToken(ATokens, Index);
      if (Previous < 0) or not ATokens[Previous].IsSymbol('.') then
        Exit(ATokens[Index].Offset);
    end;
    Inc(Index);
  end;
end;

function LineInfoOf(const AText: string; const ATokens: TArray<TPascalToken>): TLineInfo;
var
  Token: TPascalToken;
  Line: Integer;
  CodeBefore: Boolean;
  LastCodeLine: Integer;
begin
  Result.Lines := TTextLines.SplitLines(AText);
  SetLength(Result.Code, Length(Result.Lines));
  SetLength(Result.Comment, Length(Result.Lines));
  SetLength(Result.CommentStarts, Length(Result.Lines));
  LastCodeLine := -1;
  for Token in ATokens do
  begin
    if Token.Text = '' then
      Continue;
    if Token.Kind = TPascalTokenKind.Comment then
    begin
      CodeBefore := LastCodeLine = Token.StartPos.Line;
      if not CodeBefore and (Token.StartPos.Line <= High(Result.Lines)) and
        not Result.Comment[Token.StartPos.Line] then
        Result.CommentStarts[Token.StartPos.Line] := True;
      for Line := Token.StartPos.Line to Token.EndPos.Line do
        if Line <= High(Result.Lines) then
          Result.Comment[Line] := True;
    end
    else
    begin
      for Line := Token.StartPos.Line to Token.EndPos.Line do
        if Line <= High(Result.Lines) then
          Result.Code[Line] := True;
      LastCodeLine := Token.EndPos.Line;
    end;
  end;
end;

/// <summary>Erste Zeile der Kommentarzeilen direkt über ALine, nicht vor AAfter + 1; ALine ohne. AStrict: Eine
/// Leerzeile beendet die Suche.</summary>
function CommentStart(const AInfo: TLineInfo; ALine, AAfter: Integer; AStrict: Boolean): Integer;
var
  Line: Integer;
begin
  Result := ALine;
  Line := ALine - 1;
  while (Line > AAfter) and (Line >= 0) and not AInfo.Code[Line] do
  begin
    if AInfo.Comment[Line] then
      Result := Line
    else if AStrict then
      Break;
    Dec(Line);
  end;
  // Nicht mitten in einem Kommentar beginnen, der zu Code darüber gehört.
  while (Result < ALine) and not AInfo.CommentStarts[Result] do
    Inc(Result);
end;

/// <summary>Kommentarzeilen AFirst..ALast - 1 ohne Leerzeilen außerhalb von Kommentaren, ohne die Einrückung der
/// ersten.</summary>
function CommentLines(const AInfo: TLineInfo; AFirst, ALast: Integer): TArray<string>;
var
  Line: Integer;
  Indent, Text: string;
begin
  Result := nil;
  if AFirst >= ALast then
    Exit;
  Indent := TTextLines.IndentOf(AInfo.Lines[AFirst]);
  for Line := AFirst to ALast - 1 do
  begin
    if not AInfo.Comment[Line] then
      Continue;
    Text := TrimRight(AInfo.Lines[Line]);
    if StartsStr(Indent, Text) then
      Text := Copy(Text, Length(Indent) + 1, MaxInt)
    else
      Text := TrimLeft(Text);
    Result := Result + [Text];
  end;
end;

/// <summary>Kommentar hinter dem Token AIndex auf derselben Zeile, wenn danach kein Code mehr auf der Zeile
/// steht; '' sonst. AEnd ist das Ende des Kommentars bzw. des Tokens.</summary>
function TrailingComment(const AText: string; const ATokens: TArray<TPascalToken>; AIndex: Integer;
  out AEnd: TTextPosition): string;
var
  First, Last: Integer;
begin
  Result := '';
  AEnd := ATokens[AIndex].EndPos;
  First := AIndex + 1;
  if (First > High(ATokens)) or (ATokens[First].Kind <> TPascalTokenKind.Comment) or
    (ATokens[First].StartPos.Line <> ATokens[AIndex].EndPos.Line) then
    Exit;
  Last := First;
  while (Last < High(ATokens)) and (ATokens[Last + 1].Kind = TPascalTokenKind.Comment) and
    (ATokens[Last + 1].StartPos.Line = ATokens[Last].EndPos.Line) do
    Inc(Last);
  if (Last < High(ATokens)) and (ATokens[Last + 1].Text <> '') and
    (ATokens[Last + 1].StartPos.Line = ATokens[Last].EndPos.Line) then
    Exit;
  AEnd := ATokens[Last].EndPos;
  Result := Copy(AText, ATokens[First].Offset + 1, ATokens[Last].Offset + Length(ATokens[Last].Text) -
    ATokens[First].Offset);
end;

/// <summary>Index des letzten Tokens von ANode (Ende ausschließlich).</summary>
function LastTokenOf(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode): Integer;
begin
  Result := TRoutineBody.TokenAt(ATokens, ANode.EndOffset) - 1;
  while (Result > 0) and (ATokens[Result].Kind = TPascalTokenKind.Comment) do
    Dec(Result);
end;

/// <summary>Code-Token in [AFrom, ATo) auf den Zeilen AFirstLine..ALastLine außerhalb von [ASkipFrom, ASkipTo)?
/// </summary>
function CodeOnLines(const ATokens: TArray<TPascalToken>; AFirstLine, ALastLine, ASkipFrom,
  ASkipTo: Integer): Boolean;
var
  Token: TPascalToken;
begin
  Result := False;
  for Token in ATokens do
    if (Token.Kind <> TPascalTokenKind.Comment) and (Token.Text <> '') and (Token.StartPos.Line >= AFirstLine) and
      (Token.StartPos.Line <= ALastLine) and ((Token.Offset < ASkipFrom) or (Token.Offset >= ASkipTo)) then
      Exit(True);
end;

{ In Inline-Variable umwandeln }

/// <summary>Schreibt E den Typ T offensichtlich fest (Zahl → Integer, String → string, True/False → Boolean,
/// T.Create)?</summary>
function ObviousType(const ATokens: TArray<TPascalToken>; AExpression: TSyntaxNode; const ATypeText: string): Boolean;
var
  First, Last, Next: Integer;
  Text: string;
begin
  Result := False;
  First := TRoutineBody.TokenAt(ATokens, AExpression.StartOffset);
  Last := LastTokenOf(ATokens, AExpression);
  if (First > High(ATokens)) or (Last < First) then
    Exit;
  Text := ATokens[First].Text;
  if First = Last then
    case ATokens[First].Kind of
      TPascalTokenKind.Number:
        Result := SameText(ATypeText, 'Integer') and CharInSet(Text[1], ['0'..'9']) and
          (LastDelimiter('.eE', Text) = 0) and (Length(Text) < 10);
      TPascalTokenKind.StringLiteral:
        Result := SameText(ATypeText, 'string') and (Length(Text) <> 3) and (Text <> '''''''''');
      TPascalTokenKind.Identifier:
        Result := SameText(ATypeText, 'Boolean') and (SameText(Text, 'True') or SameText(Text, 'False'));
    end
  else if (ATokens[First].Kind = TPascalTokenKind.Identifier) and SameText(Text, ATypeText) then
  begin
    // T.Create bzw. T.Create(…)
    Next := TRoutineBody.NextToken(ATokens, First);
    if (Next <= Last) and ATokens[Next].IsSymbol('.') then
    begin
      Next := TRoutineBody.NextToken(ATokens, Next);
      Result := (Next <= Last) and SameText(ATokens[Next].Text, 'Create') and
        ((Next = Last) or ATokens[TRoutineBody.NextToken(ATokens, Next)].IsSymbol('('));
      if Result and (Next < Last) then
        Result := ATokens[Last].IsSymbol(')');
    end;
  end;
end;

/// <summary>Index von ANode unter seinen Geschwistern.</summary>
function ChildIndex(ANode: TSyntaxNode): Integer;
begin
  Result := ANode.Parent.ChildCount - 1;
  while (Result >= 0) and (ANode.Parent[Result] <> ANode) do
    Dec(Result);
end;

/// <summary>Anweisung, vor der die Inline-Variable steht: die äußerste Anweisung um AFirst in der innersten
/// Liste, deren Rest ab dort alle Verwendungen bis ALast enthält; nil ohne.</summary>
function AnchorStatement(AFirst, ABody: TSyntaxNode; ALast: Integer): TSyntaxNode;
var
  Node, ListEnd: TSyntaxNode;
  Index: Integer;
begin
  Result := nil;
  Node := AFirst;
  while (Node <> nil) and (Node <> ABody) do
  begin
    if TRoutineBody.InList(Node) then
    begin
      // Die Liste endet vor finally/except bzw. vor der Bedingung von repeat.
      ListEnd := Node;
      Index := ChildIndex(Node) + 1;
      while (Index < Node.Parent.ChildCount) and TRoutineBody.InList(Node.Parent[Index]) do
      begin
        ListEnd := Node.Parent[Index];
        Inc(Index);
      end;
      if ALast < ListEnd.EndOffset then
        Exit(Node);
    end;
    Node := Node.Parent;
  end;
end;

function InlineAction(const AText: string; ATree: TSyntaxTree; const AInfo: TLineInfo;
  const ASymbol: TReassignedSymbol; out AAction: TCodeAction): Boolean;
var
  Tokens: TArray<TPascalToken>;
  Routine, Section, Body, First, Statement: TSyntaxNode;
  Occurrence: TReassignedOccurrence;
  LastUse, Index, DeclLine, CommentLine, SemicolonIndex, StatementEnd: Integer;
  TypeText, LineBreak, Indent, Lead, Trailing, Declaration: string;
  Comments: TArray<string>;
  Initialized, MoveComments: Boolean;
  TrailingEnd: TTextPosition;
  Edits: TArray<TTextEdit>;
begin
  Result := False;
  Routine := ASymbol.Routine;
  if (ASymbol.Kind <> TReassignedKind.Local) or (ASymbol.Decl = nil) or
    (ASymbol.Decl.Kind <> TSyntaxKind.VarDecl) or (Routine = nil) or (Routine.Kind <> TSyntaxKind.RoutineDecl) then
    Exit;
  Section := ASymbol.Decl.Parent;
  Body := TRoutineBody.BodyOf(Routine);
  if (Section = nil) or (Section.Parent <> Routine) or (Body = nil) or (ASymbol.Decl.ChildCount = 0) or
    not (ASymbol.Decl[0].Kind in InlineTypeKinds) then
    Exit;
  // Zwei Namen eines Typs ohne Namen sind ein Typ; getrennt wären es zwei.
  if (Pos(',', ASymbol.Decl.Name) > 0) and (ASymbol.Decl[0].Kind <> TSyntaxKind.TypeReference) then
    Exit;
  Tokens := ATree.Tokens;
  if HasConditional(Tokens, Routine.StartOffset, Routine.EndOffset) or
    (FindToken(Tokens, Section.StartOffset, Section.EndOffset, 'absolute') >= 0) or
    (FindToken(Tokens, ASymbol.Decl.StartOffset, ASymbol.Decl.EndOffset, '=') >= 0) or
    TRoutineLocals.HasKind(Body, TSyntaxKind.GotoStatement) then
    Exit;
  TypeText := Trim(TRoutineLocals.TypeChildText(AText, ASymbol.Decl));
  if TypeText = '' then
    Exit;
  First := nil;
  LastUse := -1;
  for Occurrence in ASymbol.Occurrences do
    if Occurrence.Node <> nil then
    begin
      // Capture: Eine anonyme Methode oder verschachtelte Routine sähe die Inline-Variable anders.
      if (OwnerRoutine(Occurrence.Node) <> Routine) or not TRoutineBody.Within(Occurrence.Node, Body) then
        Exit;
      if First = nil then
        First := Occurrence.Node;
      LastUse := Occurrence.Offset;
    end;
  if First = nil then
    Exit;
  Statement := AnchorStatement(First, Body, LastUse);
  if Statement = nil then
    Exit;
  // var X: T := E, wenn die Anweisung X := E ist und E X nicht liest.
  Initialized := (Statement.Kind = TSyntaxKind.AssignStatement) and (Statement.ChildCount >= 2) and
    (Statement[0] = First) and (First.Kind = TSyntaxKind.Identifier);
  if Initialized then
    for Occurrence in ASymbol.Occurrences do
      if (Occurrence.Node <> nil) and (Occurrence.Node <> First) and (Occurrence.Offset >= Statement.StartOffset) and
        (Occurrence.Offset < Statement.EndOffset) then
        Initialized := False;
  if not Initialized and InLoop(Statement, Body) then
    Exit;
  LineBreak := TTextLines.LineBreakOf(AText);
  Indent := TTextLines.IndentOf(AText, Statement.StartPos.Line);
  // Kommentare wandern nur mit einem Eintrag, der allein auf seinen Zeilen steht.
  DeclLine := ASymbol.Decl.StartPos.Line;
  SemicolonIndex := LastTokenOf(Tokens, ASymbol.Decl);
  Trailing := TrailingComment(AText, Tokens, SemicolonIndex, TrailingEnd);
  MoveComments := (Pos(',', ASymbol.Decl.Name) = 0) and not CodeOnLines(Tokens, DeclLine,
    ASymbol.Decl.EndPos.Line, ASymbol.Decl.StartOffset, ASymbol.Decl.EndOffset);
  CommentLine := DeclLine;
  Comments := nil;
  if MoveComments then
  begin
    CommentLine := CommentStart(AInfo, DeclLine, Section.StartPos.Line, True);
    Comments := CommentLines(AInfo, CommentLine, DeclLine);
  end
  else
    Trailing := '';
  Lead := '';
  for Index := 0 to High(Comments) do
    Lead := Lead + Comments[Index] + LineBreak + Indent;
  Edits := nil;
  if Initialized then
  begin
    Declaration := 'var ';
    // Steht hinter der Anweisung (und ihrem ";") noch etwas auf der Zeile, kommt der mitwandernde Kommentar
    // darüber.
    StatementEnd := LastTokenOf(Tokens, Statement);
    if (StatementEnd < High(Tokens)) and Tokens[StatementEnd + 1].IsSymbol(';') then
      Inc(StatementEnd);
    if (Trailing <> '') and (StatementEnd < High(Tokens)) and (Tokens[StatementEnd + 1].Text <> '') and
      (Tokens[StatementEnd + 1].StartPos.Line = Tokens[StatementEnd].EndPos.Line) then
    begin
      Lead := Lead + Trailing + LineBreak + Indent;
      Trailing := '';
    end;
    Edits := Edits + [TTextEdit.Create(TTextRange.Create(Statement.StartPos, Statement.StartPos),
      Lead + Declaration)];
    if not ObviousType(Tokens, Statement[1], TypeText) then
      Edits := Edits + [TTextEdit.Create(TTextRange.Create(First.EndPos, First.EndPos), ': ' + TypeText)];
    if Trailing <> '' then
      Edits := Edits + [TTextEdit.Create(TTextRange.Create(Tokens[StatementEnd].EndPos, Tokens[StatementEnd].EndPos),
        ' ' + Trailing)];
  end
  else
  begin
    Declaration := Format('var %s: %s;', [ASymbol.Name, TypeText]);
    if Trailing <> '' then
      Declaration := Declaration + ' ' + Trailing;
    Edits := Edits + [TTextEdit.Create(TTextRange.Create(Statement.StartPos, Statement.StartPos),
      Lead + Declaration + LineBreak + Indent)];
  end;
  TRoutineLocals.RemoveVariables(ATree, ASymbol.Decl, [ASymbol.Name], Edits);
  // Kommentarzeilen darüber, sofern das Entfernen sie nicht schon umfasst.
  if (CommentLine < DeclLine) and (Edits[High(Edits)].Range.StartPos.Line > CommentLine) then
    Edits := Edits + [TTextEdit.Create(TTextRange.Create(CommentLine, 0, DeclLine, 0), '')];
  AAction := Default(TCodeAction);
  AAction.Title := Format('In Inline-Variable umwandeln (var %s)', [ASymbol.Name]);
  AAction.Kind := RewriteKind;
  AAction.Edits := Edits;
  Result := True;
end;

{ In var-Block verschieben }

function SectionAction(const AText: string; ATree: TSyntaxTree; const AInfo: TLineInfo;
  const ASymbol: TReassignedSymbol; const AOptions: TVarBlockOptions; out AAction: TCodeAction): Boolean;
var
  Tokens: TArray<TPascalToken>;
  Routine, Body, Decl: TSyntaxNode;
  Locals: TArray<TRoutineLocal>;
  Local: TRoutineLocal;
  Occurrence: TReassignedOccurrence;
  ScopeEnd, Keyword, NameToken, Assign, Semicolon, CommentLine, Index: Integer;
  TypeText, Entry, Prefix, EntryIndent, LineBreak, Trailing, Moved: string;
  Extra, Edits: TArray<TTextEdit>;
  Comments: TArray<string>;
  Add: TTextEdit;
  TrailingEnd: TTextPosition;
begin
  Result := False;
  Routine := ASymbol.Routine;
  Decl := ASymbol.Decl;
  if (ASymbol.Kind <> TReassignedKind.InlineVariable) or (Decl = nil) or (Decl.Kind <> TSyntaxKind.InlineVar) or
    (Pos(',', Decl.Name) > 0) or (Routine = nil) or (Routine.Kind <> TSyntaxKind.RoutineDecl) then
    Exit;
  Body := TRoutineBody.BodyOf(Routine);
  Tokens := ATree.Tokens;
  if (Body = nil) or HasConditional(Tokens, Routine.StartOffset, Routine.EndOffset) then
    Exit;
  Keyword := TRoutineBody.TokenAt(Tokens, Decl.StartOffset);
  if (Keyword > High(Tokens)) or not Tokens[Keyword].IsKeyword('var') then
    Exit;
  NameToken := TRoutineBody.NextToken(Tokens, Keyword);
  // Gültigkeitsbereich der Inline-Variablen; kein anderer lokaler Name gleich.
  ScopeEnd := -1;
  Locals := TRoutineLocals.Collect(AText, ATree, Routine);
  for Local in Locals do
    if SameText(Local.Name, ASymbol.Name) then
      if Local.Decl = Decl then
        ScopeEnd := Local.ScopeEnd
      else
        Exit;
  if ScopeEnd < 0 then
    Exit;
  // Meint derselbe Bezeichner sonst in der Routine etwas anderes (Feld, globale Variable), sähe er danach die
  // Variable.
  if WordOffset(Tokens, ASymbol.Name, Routine.StartOffset, Routine.EndOffset, Decl.StartOffset, ScopeEnd + 1) >= 0 then
    Exit;
  for Occurrence in ASymbol.Occurrences do
    if (Occurrence.Node <> nil) and (OwnerRoutine(Occurrence.Node) <> Routine) then
      Exit;
  Assign := FindToken(Tokens, Decl.StartOffset, Decl.EndOffset, ':=');
  // Ohne Startwert beginnt jeder Schleifendurchlauf mit einer neuen Variablen.
  if (Assign < 0) and InLoop(Decl, Body) then
    Exit;
  Extra := nil;
  TypeText := Trim(TRoutineLocals.TypeChildText(AText, Decl));
  if TypeText = '' then
    if not Assigned(AOptions.Types) or not AOptions.Types(Decl, TypeText, Extra) or (Trim(TypeText) = '') then
      Exit;
  TypeText := Trim(TypeText);
  LineBreak := TTextLines.LineBreakOf(AText);
  Entry := Format('%s: %s;', [CleanName(Tokens[NameToken].Text), TypeText]);
  Add := TRoutineBody.AddVariable(AText, Routine, CleanName(Tokens[NameToken].Text), TypeText, AOptions.Style);
  Edits := nil;
  if Assign >= 0 then
    // var X: T := E  ->  X := E
    Edits := Edits + [TTextEdit.Create(TTextRange.Create(Tokens[Keyword].StartPos, Tokens[Assign].StartPos),
      Tokens[NameToken].Text + ' ')]
  else
  begin
    Semicolon := TRoutineBody.NextToken(Tokens, LastTokenOf(Tokens, Decl));
    if (Semicolon > High(Tokens)) or not Tokens[Semicolon].IsSymbol(';') then
      Exit;
    if CodeOnLines(Tokens, Decl.StartPos.Line, Tokens[Semicolon].EndPos.Line, Decl.StartOffset,
      Tokens[Semicolon].Offset + 1) then
      Edits := Edits + [TTextEdit.Create(TTextRange.Create(Decl.StartPos, Tokens[Semicolon].EndPos), '')]
    else
    begin
      // Allein auf der Zeile: Zeile weg, Kommentare darüber und dahinter wandern in den Abschnitt.
      Trailing := TrailingComment(AText, Tokens, Semicolon, TrailingEnd);
      CommentLine := CommentStart(AInfo, Decl.StartPos.Line, -1, True);
      Comments := CommentLines(AInfo, CommentLine, Decl.StartPos.Line);
      Edits := Edits + [TTextEdit.Create(TTextRange.Create(CommentLine, 0, Tokens[Semicolon].EndPos.Line + 1, 0),
        '')];
      Prefix := Copy(Add.NewText, 1, Pos(Entry, Add.NewText) - 1);
      EntryIndent := Copy(Prefix, LastDelimiter(#10, Prefix) + 1, MaxInt);
      Moved := '';
      for Index := 0 to High(Comments) do
        Moved := Moved + Comments[Index] + LineBreak + EntryIndent;
      Moved := Moved + Entry;
      if Trailing <> '' then
        Moved := Moved + ' ' + Trailing;
      Add.NewText := StringReplace(Add.NewText, Entry, Moved, []);
    end;
  end;
  AAction := Default(TCodeAction);
  AAction.Title := Format('In var-Block verschieben (%s)', [ASymbol.Name]);
  AAction.Kind := RewriteKind;
  AAction.Edits := TArray<TTextEdit>.Create(Add) + Edits + Extra;
  Result := True;
end;

{ var-Block aufräumen }

/// <summary>Typtext ohne Leerraum und in Kleinbuchstaben: Vergleich beim Zusammenfassen.</summary>
function TypeKey(const ATypeText: string): string;
var
  Character: Char;
begin
  Result := '';
  for Character in LowerCase(ATypeText) do
    if not CharInSet(Character, [' ', #9, #10, #13]) then
      Result := Result + Character;
end;

/// <summary>Kommt AItem vor ACandidate? Stabil über Order.</summary>
function Before(const AItem, ACandidate: TVarItem; ASort: TVarBlockSort): Boolean;
var
  Compared: Integer;
begin
  case ASort of
    TVarBlockSort.Usage:
      if AItem.FirstUse <> ACandidate.FirstUse then
        Exit(AItem.FirstUse < ACandidate.FirstUse);
    TVarBlockSort.Alpha:
      begin
        Compared := CompareText(AItem.Names[0], ACandidate.Names[0]);
        if Compared <> 0 then
          Exit(Compared < 0);
      end;
  end;
  Result := AItem.Order < ACandidate.Order;
end;

/// <summary>Einträge des Abschnitts samt Kommentaren; False, wenn der Abschnitt etwas enthält, das beim
/// Neuschreiben verloren ginge oder seine Bedeutung änderte (Direktiven, absolute, Startwerte, Kommentare
/// mitten in einem Eintrag).</summary>
function SectionEntries(const AText: string; const ATokens: TArray<TPascalToken>; const AInfo: TLineInfo;
  ASection: TSyntaxNode; out AEntries: TArray<TVarEntry>): Boolean;
var
  Index, Token, First, Last, After: Integer;
  Decl: TSyntaxNode;
  Entry: TVarEntry;
  Name: string;
begin
  Result := False;
  AEntries := nil;
  if (ASection.ChildCount = 0) or HasConditional(ATokens, ASection.StartOffset, ASection.EndOffset) or
    (FindToken(ATokens, ASection.StartOffset, ASection.EndOffset, 'absolute') >= 0) or
    (FindToken(ATokens, ASection.StartOffset, ASection.EndOffset, '=') >= 0) then
    Exit;
  After := ASection.StartPos.Line;
  for Index := 0 to ASection.ChildCount - 1 do
  begin
    Decl := ASection[Index];
    if (Decl.Kind <> TSyntaxKind.VarDecl) or (Decl.ChildCount = 0) then
      Exit;
    First := TRoutineBody.TokenAt(ATokens, Decl.StartOffset);
    Last := LastTokenOf(ATokens, Decl);
    for Token := First to Last do
      if ATokens[Token].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive] then
        Exit;
    // Kommentar vor dem Eintrag auf derselben Zeile
    if (First > 0) and (ATokens[First - 1].Kind = TPascalTokenKind.Comment) and
      (ATokens[First - 1].EndPos.Line = Decl.StartPos.Line) then
      Exit;
    Entry := Default(TVarEntry);
    Entry.Decl := Decl;
    for Name in Decl.Name.Split([',']) do
      Entry.Names := Entry.Names + [Trim(Name)];
    Entry.TypeText := Trim(TRoutineLocals.TypeChildText(AText, Decl));
    if Entry.TypeText = '' then
      Exit;
    Entry.Named := Decl[0].Kind = TSyntaxKind.TypeReference;
    Entry.FirstLine := Decl.StartPos.Line;
    if (Decl.StartPos.Line > After) or (Index = 0) then
    begin
      Entry.FirstLine := CommentStart(AInfo, Decl.StartPos.Line, After, False);
      Entry.Comments := CommentLines(AInfo, Entry.FirstLine, Decl.StartPos.Line);
    end;
    Entry.Trailing := TrailingComment(AText, ATokens, Last, Entry.EndPos);
    Entry.EndLine := Entry.EndPos.Line;
    After := Entry.EndLine;
    AEntries := AEntries + [Entry];
  end;
  Result := True;
end;

function CleanupAction(const AText: string; ATree: TSyntaxTree; const AInfo: TLineInfo;
  const ASymbols: TArray<TReassignedSymbol>; ASection: TSyntaxNode; const AOptions: TVarBlockOptions;
  out AAction: TCodeAction): Boolean;
var
  Tokens: TArray<TPascalToken>;
  Routine: TSyntaxNode;
  Entries: TArray<TVarEntry>;
  Entry: TVarEntry;
  Items, Sorted, Merged: TArray<TVarItem>;
  Item: TVarItem;
  Symbol: TReassignedSymbol;
  Occurrence: TReassignedOccurrence;
  Kept: TArray<string>;
  Name, LineBreak, Indent, Line, NewText, OldText, Removed: string;
  Index, Inner, FirstUse, WordUse, Order, StartOffset, EndOffset: Integer;
  Lines: TArray<string>;
  RangeStart, RangeEnd: TTextPosition;
  Inserted, AtLineStart: Boolean;
begin
  Result := False;
  Routine := ASection.Parent;
  Tokens := ATree.Tokens;
  if not SectionEntries(AText, Tokens, AInfo, ASection, Entries) then
    Exit;
  // Einträge in Zeilen; ungenutzte Namen fallen weg.
  Items := nil;
  Removed := '';
  Order := 0;
  for Entry in Entries do
  begin
    Kept := nil;
    FirstUse := MaxInt;
    for Name in Entry.Names do
    begin
      WordUse := MaxInt;
      for Symbol in ASymbols do
        if (Symbol.Decl = Entry.Decl) and SameText(Symbol.Name, Name) then
          for Occurrence in Symbol.Occurrences do
            if (Occurrence.Node <> nil) and (Occurrence.Offset < WordUse) then
              WordUse := Occurrence.Offset;
      // Absicherung, falls die Analyse eine Verwendung nicht sieht (asm, with): Jeder gleichnamige
      // Bezeichner in der Routine zählt als Verwendung.
      if WordUse = MaxInt then
      begin
        WordUse := WordOffset(Tokens, Name, Routine.StartOffset, Routine.EndOffset, ASection.StartOffset,
          ASection.EndOffset);
        if WordUse < 0 then
        begin
          if Removed <> '' then
            Removed := Removed + ', ';
          Removed := Removed + Name;
          Continue;
        end;
      end;
      if WordUse < FirstUse then
        FirstUse := WordUse;
      if Entry.Named and (Entry.Comments = nil) and (Entry.Trailing = '') then
      begin
        // Ohne Kommentar: jeder Name eine eigene Zeile, zusammengefasst wird danach.
        Item := Default(TVarItem);
        Item.Names := [Name];
        Item.TypeText := Entry.TypeText;
        Item.Named := True;
        Item.FirstUse := WordUse;
        Item.Order := Order;
        Inc(Order);
        Items := Items + [Item];
      end
      else
        Kept := Kept + [Name];
    end;
    if Kept <> nil then
    begin
      Item := Default(TVarItem);
      Item.Names := Kept;
      Item.TypeText := Entry.TypeText;
      Item.Comments := Entry.Comments;
      Item.Trailing := Entry.Trailing;
      Item.FirstUse := FirstUse;
      Item.Order := Order;
      Inc(Order);
      Items := Items + [Item];
    end;
  end;
  // Stabil sortieren (Einfügen).
  Sorted := nil;
  for Item in Items do
  begin
    Inserted := False;
    for Index := 0 to High(Sorted) do
      if Before(Item, Sorted[Index], AOptions.Sort) then
      begin
        Insert(Item, Sorted, Index);
        Inserted := True;
        Break;
      end;
    if not Inserted then
      Sorted := Sorted + [Item];
  end;
  Merged := nil;
  for Item in Sorted do
  begin
    Index := High(Merged);
    if AOptions.Merge and (Index >= 0) and Item.Named and Merged[Index].Named and (Item.Comments = nil) and
      (Item.Trailing = '') and (Merged[Index].Comments = nil) and (Merged[Index].Trailing = '') and
      (TypeKey(Item.TypeText) = TypeKey(Merged[Index].TypeText)) then
      Merged[Index].Names := Merged[Index].Names + Item.Names
    else
      Merged := Merged + [Item];
  end;
  LineBreak := TTextLines.LineBreakOf(AText);
  StartOffset := Entries[0].Decl.StartOffset;
  EndOffset := Entries[High(Entries)].Decl.EndOffset;
  AtLineStart := not CodeOnLines(Tokens, Entries[0].Decl.StartPos.Line, Entries[0].Decl.StartPos.Line, StartOffset,
    MaxInt);
  if Merged = nil then
  begin
    // Alles ungenutzt: der ganze Abschnitt samt "var", wenn er eigene Zeilen hat.
    if CodeOnLines(Tokens, ASection.StartPos.Line, ASection.StartPos.Line, ASection.StartOffset, MaxInt) or
      CodeOnLines(Tokens, Entries[High(Entries)].EndLine, Entries[High(Entries)].EndLine, 0, EndOffset) then
      Exit;
    RangeStart := TTextPosition.Create(ASection.StartPos.Line, 0);
    RangeEnd := TTextPosition.Create(Entries[High(Entries)].EndLine + 1, 0);
    NewText := '';
  end
  else
  begin
    if AtLineStart then
    begin
      Indent := TTextLines.IndentOf(AText, Entries[0].Decl.StartPos.Line);
      RangeStart := TTextPosition.Create(Entries[0].FirstLine, 0);
    end
    else
    begin
      Indent := TTextLines.IndentOf(AText, ASection.StartPos.Line) + TRoutineBody.IndentUnit(AOptions.Style);
      RangeStart := Entries[0].Decl.StartPos;
    end;
    RangeEnd := Entries[High(Entries)].EndPos;
    Lines := nil;
    for Item in Merged do
    begin
      for Line in Item.Comments do
        Lines := Lines + [Line];
      Line := Format('%s: %s;', [string.Join(', ', Item.Names), Item.TypeText]);
      if Item.Trailing <> '' then
        Line := Line + ' ' + Item.Trailing;
      Lines := Lines + [Line];
    end;
    NewText := '';
    for Index := 0 to High(Lines) do
    begin
      if Index > 0 then
        NewText := NewText + LineBreak;
      if (Index > 0) or AtLineStart then
        NewText := NewText + Indent;
      NewText := NewText + Lines[Index];
    end;
  end;
  // Unverändert: keine Aktion.
  OldText := '';
  for Inner := RangeStart.Line to RangeEnd.Line do
    if Inner <= High(AInfo.Lines) then
    begin
      Line := AInfo.Lines[Inner];
      if Inner = RangeEnd.Line then
        Line := Copy(Line, 1, RangeEnd.Character);
      if Inner = RangeStart.Line then
        Line := Copy(Line, RangeStart.Character + 1, MaxInt);
      if Inner > RangeStart.Line then
        OldText := OldText + LineBreak;
      OldText := OldText + Line;
    end;
  if OldText = NewText then
    Exit;
  AAction := Default(TCodeAction);
  AAction.Title := 'var-Block aufräumen';
  if Removed <> '' then
    AAction.Title := AAction.Title + Format(' (ungenutzt: %s)', [Removed]);
  AAction.Kind := RewriteKind;
  AAction.Edits := [TTextEdit.Create(TTextRange.Create(RangeStart, RangeEnd), NewText)];
  Result := True;
end;

{ TVarBlock }

class function TVarBlock.SortOf(const AName: string): TVarBlockSort;
var
  Sort: TVarBlockSort;
begin
  for Sort := Low(TVarBlockSort) to High(TVarBlockSort) do
    if SameText(SortNames[Sort], AName) then
      Exit(Sort);
  Result := TVarBlockSort.Usage;
end;

/// <summary>var-Abschnitt einer Routine, der AOffset enthält (ab "var" bis zum Ende des letzten Eintrags);
/// nil sonst.</summary>
function SectionAt(ATree: TSyntaxTree; AOffset: Integer): TSyntaxNode;
var
  Found: TSyntaxNode;
  Offset: Integer;
begin
  Offset := AOffset;
  Found := ATree.Root.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      if (Offset < ANode.StartOffset) or (Offset > ANode.EndOffset) then
        Exit(TSyntaxSearchStep.Skip);
      if (ANode.Kind = TSyntaxKind.VarSection) and (ANode.Parent <> nil) and
        (ANode.Parent.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) then
        Exit(TSyntaxSearchStep.Found);
      Result := TSyntaxSearchStep.Descend;
    end);
  Result := Found;
end;

/// <summary>Offset der Position im Text; -1 außerhalb.</summary>
function OffsetOf(const AInfo: TLineInfo; const APosition: TTextPosition; const ALineBreak: string): Integer;
var
  Line: Integer;
begin
  Result := -1;
  if (APosition.Line < 0) or (APosition.Line > High(AInfo.Lines)) then
    Exit;
  Result := 0;
  for Line := 0 to APosition.Line - 1 do
    Result := Result + Length(AInfo.Lines[Line]) + Length(ALineBreak);
  Result := Result + APosition.Character;
end;

class function TVarBlock.Actions(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const AOptions: TVarBlockOptions): TArray<TCodeAction>;
var
  Symbols: TArray<TReassignedSymbol>;
  Symbol: TReassignedSymbol;
  Info: TLineInfo;
  Section: TSyntaxNode;
  Action: TCodeAction;
  Offset: Integer;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  Info := LineInfoOf(AText, ATree.Tokens);
  Symbols := TReassigned.Analyze(AText, ATree, AOptions.Lookup);
  if TReassigned.SymbolAt(Symbols, APosition, Symbol) then
  begin
    if AOptions.InlineVariables and InlineAction(AText, ATree, Info, Symbol, Action) then
      Result := Result + [Action];
    if SectionAction(AText, ATree, Info, Symbol, AOptions, Action) then
      Result := Result + [Action];
  end;
  Offset := OffsetOf(Info, APosition, TTextLines.LineBreakOf(AText));
  if Offset < 0 then
    Exit;
  Section := SectionAt(ATree, Offset);
  if (Section <> nil) and CleanupAction(AText, ATree, Info, Symbols, Section, AOptions, Action) then
    Result := Result + [Action];
end;

end.
