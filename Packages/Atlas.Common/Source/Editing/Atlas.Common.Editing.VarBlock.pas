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
  System.Math,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Semantics.Reassigned,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.RoutineLocals,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TVarBlockText = (CleanUpVarBlock, ConvertToInlineVariableVar, MoveToVarBlock, Unused);

const
  cTexts: array[TVarBlockText] of TAtlasText = (
    (De: 'var-Block aufräumen'; En: 'Clean up var block'),
    (De: 'In Inline-Variable umwandeln (var %s)'; En: 'Convert to inline variable (var %s)'),
    (De: 'In var-Block verschieben (%s)'; En: 'Move to var block (%s)'),
    (De: ' (ungenutzt: %s)'; En: ' (unused: %s)'));

{$SCOPEDENUMS OFF}

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
  begin
    Result := Copy(Result, 2, MaxInt);
  end;
end;

/// <summary>Innerste Routine (benannt oder anonym), in der ANode steht.</summary>
function OwnerRoutine(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode.Parent;
  while (Result <> nil) and not (Result.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) do
  begin
    Result := Result.Parent;
  end;
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
    begin
      Exit(True);
    end;
    Node := Node.Parent;
  end;
end;

/// <summary>Bedingte Übersetzung ({$IFDEF …}, {$ELSE}, {$ENDIF} …) im Bereich [AFrom, ATo).</summary>
function HasConditional(const ATokens: TArray<TPascalToken>; AFrom, ATo: Integer): Boolean;
var
  Text: string;
  Stop: Integer;
  mIndex: Integer;
begin
  Result := False;
  // Binär zum ersten Token des Bereichs statt ab Dateianfang (#1323).
  mIndex := TRoutineBody.TokenAt(ATokens, AFrom);
  while (mIndex <= High(ATokens)) and (ATokens[mIndex].Offset < ATo) do
  begin
    if ATokens[mIndex].Kind = TPascalTokenKind.Directive then
    begin
      Text := ATokens[mIndex].Text;
      if StartsStr('{$', Text) then
      begin
        Text := Copy(Text, 3, MaxInt);
      end
      else
      begin
        Text := Copy(Text, 4, MaxInt);
      end;
      Stop := 1;
      while (Stop <= Length(Text)) and CharInSet(Text[Stop], ['A'..'Z', 'a'..'z']) do
      begin
        Inc(Stop);
      end;
      if MatchText(Copy(Text, 1, Stop - 1), ConditionalWords) then
      begin
        Exit(True);
      end;
    end;
    Inc(mIndex);
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
    begin
      Exit(Index);
    end;
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
      begin
        Exit(ATokens[Index].Offset);
      end;
    end;
    Inc(Index);
  end;
end;

/// <summary>Markiert in AFlags die Zeilen des Tokens AToken, soweit es sie gibt.</summary>
procedure MarkLines(var AFlags: TArray<Boolean>; const AToken: TPascalToken);
var
  mLine: Integer;
begin
  for mLine := AToken.StartPos.Line to Min(AToken.EndPos.Line, High(AFlags)) do
  begin
    AFlags[mLine] := True;
  end;
end;

function LineInfoOf(const AText: string; const ATokens: TArray<TPascalToken>): TLineInfo;
var
  mToken: TPascalToken;
  mLastCodeLine: Integer;
begin
  Result.Lines := TTextLines.SplitLines(AText);
  SetLength(Result.Code, Length(Result.Lines));
  SetLength(Result.Comment, Length(Result.Lines));
  SetLength(Result.CommentStarts, Length(Result.Lines));
  mLastCodeLine := -1;
  for mToken in ATokens do
  begin
    if mToken.Text = '' then
    begin
      Continue;
    end;
    if mToken.Kind <> TPascalTokenKind.Comment then
    begin
      MarkLines(Result.Code, mToken);
      mLastCodeLine := mToken.EndPos.Line;
      Continue;
    end;
    // Ein Kommentar beginnt die Zeile, wenn davor auf ihr kein Code und kein anderer Kommentar steht.
    if (mLastCodeLine <> mToken.StartPos.Line) and (mToken.StartPos.Line <= High(Result.Lines)) and
      not Result.Comment[mToken.StartPos.Line] then
    begin
      Result.CommentStarts[mToken.StartPos.Line] := True;
    end;
    MarkLines(Result.Comment, mToken);
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
    begin
      Result := Line;
    end
    else if AStrict then
    begin
      Break;
    end;
    Dec(Line);
  end;
  // Nicht mitten in einem Kommentar beginnen, der zu Code darüber gehört.
  while (Result < ALine) and not AInfo.CommentStarts[Result] do
  begin
    Inc(Result);
  end;
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
  begin
    Exit;
  end;
  Indent := TTextLines.IndentOf(AInfo.Lines[AFirst]);
  for Line := AFirst to ALast - 1 do
  begin
    if not AInfo.Comment[Line] then
    begin
      Continue;
    end;
    Text := TrimRight(AInfo.Lines[Line]);
    if StartsStr(Indent, Text) then
    begin
      Text := Copy(Text, Length(Indent) + 1, MaxInt);
    end
    else
    begin
      Text := TrimLeft(Text);
    end;
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
  begin
    Exit;
  end;
  Last := First;
  while (Last < High(ATokens)) and (ATokens[Last + 1].Kind = TPascalTokenKind.Comment) and
    (ATokens[Last + 1].StartPos.Line = ATokens[Last].EndPos.Line) do
  begin
    Inc(Last);
  end;
  if (Last < High(ATokens)) and (ATokens[Last + 1].Text <> '') and
    (ATokens[Last + 1].StartPos.Line = ATokens[Last].EndPos.Line) then
  begin
    Exit;
  end;
  AEnd := ATokens[Last].EndPos;
  Result := Copy(AText, ATokens[First].Offset + 1, ATokens[Last].Offset + Length(ATokens[Last].Text) -
    ATokens[First].Offset);
end;

/// <summary>Index des letzten Tokens von ANode (Ende ausschließlich).</summary>
function LastTokenOf(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode): Integer;
begin
  Result := TRoutineBody.TokenAt(ATokens, ANode.EndOffset) - 1;
  while (Result > 0) and (ATokens[Result].Kind = TPascalTokenKind.Comment) do
  begin
    Dec(Result);
  end;
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
  begin
    if (Token.Kind <> TPascalTokenKind.Comment) and (Token.Text <> '') and
      InRange(Token.StartPos.Line, AFirstLine, ALastLine) and
      ((Token.Offset < ASkipFrom) or (Token.Offset >= ASkipTo)) then
    begin
      Exit(True);
    end;
  end;
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
  begin
    Exit;
  end;
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
      begin
        Result := ATokens[Last].IsSymbol(')');
      end;
    end;
  end;
end;

/// <summary>Index von ANode unter seinen Geschwistern.</summary>
function ChildIndex(ANode: TSyntaxNode): Integer;
begin
  Result := ANode.Parent.ChildCount - 1;
  while (Result >= 0) and (ANode.Parent[Result] <> ANode) do
  begin
    Dec(Result);
  end;
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
      begin
        Exit(Node);
      end;
    end;
    Node := Node.Parent;
  end;
end;

/// <summary>Steht hinter dem Token AIndex auf derselben Zeile noch ein Token?</summary>
function CodeFollows(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
begin
  Result := (AIndex < High(ATokens)) and (ATokens[AIndex + 1].Text <> '') and
    (ATokens[AIndex + 1].StartPos.Line = ATokens[AIndex].EndPos.Line);
end;

type
  /// <summary>Arbeitsstand von „In Inline-Variable umwandeln“: die Variable Symbol aus dem Abschnitt Section der
  /// Routine Routine, ihre erste Verwendung First, die Anweisung Statement, vor die sie wandert, und was mit ihr
  /// wandert (Lead über, Trailing hinter der Deklaration).</summary>
  TInlineMove = record
    Text: string;
    Tree: TSyntaxTree;
    Tokens: TArray<TPascalToken>;
    Symbol: TReassignedSymbol;
    Routine: TSyntaxNode;
    Section: TSyntaxNode;
    Body: TSyntaxNode;
    First: TSyntaxNode;
    Statement: TSyntaxNode;
    LastUse: Integer;
    TypeText: string;
    LineBreak: string;
    Indent: string;
    Lead: string;
    Trailing: string;
    DeclLine: Integer;
    CommentLine: Integer;
    /// <summary>Aus X := E wird var X: T := E.</summary>
    Initialized: Boolean;
    /// <summary>Lokale Variable im var-Abschnitt einer benannten Routine mit übertragbarem Typ?</summary>
    function IsCandidate: Boolean;
    /// <summary>Bedingte Übersetzung, absolute, Startwert, goto oder Typ ohne Text; setzt sonst TypeText.</summary>
    function IsUnsupported: Boolean;
    /// <summary>Erste und letzte Verwendung im Rumpf; False bei Capture oder ohne Verwendung.</summary>
    function FindUses: Boolean;
    /// <summary>Ist Statement X := E mit X als erster Verwendung?</summary>
    function AssignsFirst: Boolean;
    /// <summary>Kommt die Variable in Statement außer als First vor?</summary>
    function ReadsInStatement: Boolean;
    /// <summary>Anweisung und Art der Deklaration; False, wenn keine passt.</summary>
    function FindAnchor: Boolean;
    /// <summary>Kommentare, die mit einem Eintrag wandern, der allein auf seinen Zeilen steht.</summary>
    procedure CollectComments(const AInfo: TLineInfo);
    /// <summary>Letztes Token der Anweisung samt ";".</summary>
    function StatementEnd: Integer;
    function InitializedEdits: TArray<TTextEdit>;
    function DeclarationEdits: TArray<TTextEdit>;
    function Edits: TArray<TTextEdit>;
  end;

function TInlineMove.IsCandidate: Boolean;
begin
  Routine := Symbol.Routine;
  Result := (Symbol.Kind = TReassignedKind.Local) and (Symbol.Decl <> nil) and
    (Symbol.Decl.Kind = TSyntaxKind.VarDecl) and (Routine <> nil) and (Routine.Kind = TSyntaxKind.RoutineDecl);
  if not Result then
  begin
    Exit;
  end;
  Section := Symbol.Decl.Parent;
  Body := TRoutineBody.BodyOf(Routine);
  Result := (Section <> nil) and (Section.Parent = Routine) and (Body <> nil) and (Symbol.Decl.ChildCount > 0) and
    (Symbol.Decl[0].Kind in InlineTypeKinds);
  // Zwei Namen eines Typs ohne Namen sind ein Typ; getrennt wären es zwei.
  Result := Result and ((Pos(',', Symbol.Decl.Name) = 0) or (Symbol.Decl[0].Kind = TSyntaxKind.TypeReference));
end;

function TInlineMove.IsUnsupported: Boolean;
begin
  Result := HasConditional(Tokens, Routine.StartOffset, Routine.EndOffset) or
    (FindToken(Tokens, Section.StartOffset, Section.EndOffset, 'absolute') >= 0) or
    (FindToken(Tokens, Symbol.Decl.StartOffset, Symbol.Decl.EndOffset, '=') >= 0) or
    TRoutineLocals.HasKind(Body, TSyntaxKind.GotoStatement);
  if not Result then
  begin
    TypeText := Trim(TRoutineLocals.TypeChildText(Text, Symbol.Decl));
    Result := TypeText = '';
  end;
end;

function TInlineMove.FindUses: Boolean;
var
  mOccurrence: TReassignedOccurrence;
begin
  First := nil;
  LastUse := -1;
  for mOccurrence in Symbol.Occurrences do
  begin
    if mOccurrence.Node = nil then
    begin
      Continue;
    end;
    // Capture: Eine anonyme Methode oder verschachtelte Routine sähe die Inline-Variable anders.
    if (OwnerRoutine(mOccurrence.Node) <> Routine) or not TRoutineBody.Within(mOccurrence.Node, Body) then
    begin
      Exit(False);
    end;
    if First = nil then
    begin
      First := mOccurrence.Node;
    end;
    LastUse := mOccurrence.Offset;
  end;
  Result := First <> nil;
end;

function TInlineMove.AssignsFirst: Boolean;
begin
  Result := (Statement.Kind = TSyntaxKind.AssignStatement) and (Statement.ChildCount >= 2) and
    (Statement[0] = First) and (First.Kind = TSyntaxKind.Identifier);
end;

function TInlineMove.ReadsInStatement: Boolean;
var
  mOccurrence: TReassignedOccurrence;
begin
  for mOccurrence in Symbol.Occurrences do
  begin
    if (mOccurrence.Node <> nil) and (mOccurrence.Node <> First) and
      (mOccurrence.Offset >= Statement.StartOffset) and (mOccurrence.Offset < Statement.EndOffset) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TInlineMove.FindAnchor: Boolean;
begin
  Result := FindUses;
  if Result then
  begin
    Statement := AnchorStatement(First, Body, LastUse);
    Result := Statement <> nil;
  end;
  if Result then
  begin
    // var X: T := E, wenn die Anweisung X := E ist und E X nicht liest.
    Initialized := AssignsFirst and not ReadsInStatement;
    Result := Initialized or not InLoop(Statement, Body);
  end;
end;

procedure TInlineMove.CollectComments(const AInfo: TLineInfo);
var
  mTrailingEnd: TTextPosition;
  mComment: string;
begin
  LineBreak := TTextLines.LineBreakOf(Text);
  Indent := TTextLines.IndentOf(Text, Statement.StartPos.Line);
  DeclLine := Symbol.Decl.StartPos.Line;
  CommentLine := DeclLine;
  Lead := '';
  Trailing := '';
  // Kommentare wandern nur mit einem Eintrag, der allein auf seinen Zeilen steht.
  if (Pos(',', Symbol.Decl.Name) > 0) or CodeOnLines(Tokens, DeclLine, Symbol.Decl.EndPos.Line,
    Symbol.Decl.StartOffset, Symbol.Decl.EndOffset) then
  begin
    Exit;
  end;
  Trailing := TrailingComment(Text, Tokens, LastTokenOf(Tokens, Symbol.Decl), mTrailingEnd);
  CommentLine := CommentStart(AInfo, DeclLine, Section.StartPos.Line, True);
  for mComment in CommentLines(AInfo, CommentLine, DeclLine) do
  begin
    Lead := Lead + mComment + LineBreak + Indent;
  end;
end;

function TInlineMove.StatementEnd: Integer;
begin
  Result := LastTokenOf(Tokens, Statement);
  if (Result < High(Tokens)) and Tokens[Result + 1].IsSymbol(';') then
  begin
    Inc(Result);
  end;
end;

function TInlineMove.InitializedEdits: TArray<TTextEdit>;
var
  mEnd: Integer;
  mLead, mTrailing: string;
begin
  mLead := Lead;
  mTrailing := Trailing;
  mEnd := StatementEnd;
  // Steht hinter der Anweisung (und ihrem ";") noch etwas auf der Zeile, kommt der mitwandernde Kommentar darüber.
  if (mTrailing <> '') and CodeFollows(Tokens, mEnd) then
  begin
    mLead := mLead + mTrailing + LineBreak + Indent;
    mTrailing := '';
  end;
  Result := TArray<TTextEdit>.Create(TTextEdit.Create(TTextRange.Create(Statement.StartPos, Statement.StartPos),
    mLead + 'var '));
  if not ObviousType(Tokens, Statement[1], TypeText) then
  begin
    Result := Result + [TTextEdit.Create(TTextRange.Create(First.EndPos, First.EndPos), ': ' + TypeText)];
  end;
  if mTrailing <> '' then
  begin
    Result := Result + [TTextEdit.Create(TTextRange.Create(Tokens[mEnd].EndPos, Tokens[mEnd].EndPos),
      ' ' + mTrailing)];
  end;
end;

function TInlineMove.DeclarationEdits: TArray<TTextEdit>;
var
  mDeclaration: string;
begin
  mDeclaration := Format('var %s: %s;', [Symbol.Name, TypeText]);
  if Trailing <> '' then
  begin
    mDeclaration := mDeclaration + ' ' + Trailing;
  end;
  Result := TArray<TTextEdit>.Create(TTextEdit.Create(TTextRange.Create(Statement.StartPos, Statement.StartPos),
    Lead + mDeclaration + LineBreak + Indent));
end;

function TInlineMove.Edits: TArray<TTextEdit>;
begin
  if Initialized then
  begin
    Result := InitializedEdits;
  end
  else
  begin
    Result := DeclarationEdits;
  end;
  TRoutineLocals.RemoveVariables(Tree, Symbol.Decl, [Symbol.Name], Result);
  // Kommentarzeilen darüber, sofern das Entfernen sie nicht schon umfasst.
  if (CommentLine < DeclLine) and (Result[High(Result)].Range.StartPos.Line > CommentLine) then
  begin
    Result := Result + [TTextEdit.Create(TTextRange.Create(CommentLine, 0, DeclLine, 0), '')];
  end;
end;

function InlineAction(const AText: string; ATree: TSyntaxTree; const AInfo: TLineInfo;
  const ASymbol: TReassignedSymbol; out AAction: TCodeAction): Boolean;
var
  mMove: TInlineMove;
begin
  mMove := Default(TInlineMove);
  mMove.Text := AText;
  mMove.Tree := ATree;
  mMove.Tokens := ATree.Tokens;
  mMove.Symbol := ASymbol;
  Result := mMove.IsCandidate and not mMove.IsUnsupported and mMove.FindAnchor;
  if Result then
  begin
    mMove.CollectComments(AInfo);
    AAction := Default(TCodeAction);
    AAction.Title := cTexts[TVarBlockText.ConvertToInlineVariableVar].Fmt([ASymbol.Name]);
    AAction.Kind := RewriteKind;
    AAction.Edits := mMove.Edits;
  end;
end;

{ In var-Block verschieben }

type
  /// <summary>Arbeitsstand von „In var-Block verschieben“: die Inline-Variable Symbol (Deklaration Decl ab dem
  /// Token Keyword, Name NameToken, ":=" Assign oder -1) der Routine Routine mit Typ TypeText; Extra macht den
  /// Typ sichtbar (uses).</summary>
  TSectionMove = record
    Text: string;
    Tree: TSyntaxTree;
    Tokens: TArray<TPascalToken>;
    Symbol: TReassignedSymbol;
    Routine: TSyntaxNode;
    Body: TSyntaxNode;
    Decl: TSyntaxNode;
    Keyword: Integer;
    NameToken: Integer;
    Assign: Integer;
    TypeText: string;
    Extra: TArray<TTextEdit>;
    /// <summary>Einzelne Inline-Variable einer benannten Routine ohne bedingte Übersetzung?</summary>
    function IsCandidate: Boolean;
    /// <summary>Ende des Gültigkeitsbereichs; -1, wenn ein anderer lokaler Name gleich ist.</summary>
    function ScopeEnd: Integer;
    /// <summary>Verwendet eine verschachtelte Routine oder anonyme Methode die Variable?</summary>
    function IsCaptured: Boolean;
    /// <summary>Ändert das Verschieben die Bedeutung nicht?</summary>
    function IsSafe: Boolean;
    /// <summary>Typ aus der Deklaration oder über AOptions.Types; False ohne.</summary>
    function ResolveType(const AOptions: TVarBlockOptions): Boolean;
    /// <summary>Edits für var X: T; ohne Startwert; AAdd nimmt Kommentare der Zeile mit.</summary>
    function DeclarationRemoval(const AInfo: TLineInfo; ASemicolon: Integer; const AEntry: string;
      var AAdd: TTextEdit): TArray<TTextEdit>;
    function BuildEdits(const AInfo: TLineInfo; const AStyle: TFormatStyle; out AEdits: TArray<TTextEdit>): Boolean;
  end;

function TSectionMove.IsCandidate: Boolean;
begin
  Routine := Symbol.Routine;
  Decl := Symbol.Decl;
  Result := (Symbol.Kind = TReassignedKind.InlineVariable) and (Decl <> nil) and
    (Decl.Kind = TSyntaxKind.InlineVar) and (Pos(',', Decl.Name) = 0);
  Result := Result and (Routine <> nil) and (Routine.Kind = TSyntaxKind.RoutineDecl);
  if not Result then
  begin
    Exit;
  end;
  Body := TRoutineBody.BodyOf(Routine);
  Result := (Body <> nil) and not HasConditional(Tokens, Routine.StartOffset, Routine.EndOffset);
  if Result then
  begin
    Keyword := TRoutineBody.TokenAt(Tokens, Decl.StartOffset);
    Result := (Keyword <= High(Tokens)) and Tokens[Keyword].IsKeyword('var');
  end;
  if Result then
  begin
    NameToken := TRoutineBody.NextToken(Tokens, Keyword);
  end;
end;

function TSectionMove.ScopeEnd: Integer;
var
  mLocal: TRoutineLocal;
begin
  Result := -1;
  for mLocal in TRoutineLocals.Collect(Text, Tree, Routine) do
  begin
    if not SameText(mLocal.Name, Symbol.Name) then
    begin
      Continue;
    end;
    if mLocal.Decl <> Decl then
    begin
      Exit(-1);
    end;
    Result := mLocal.ScopeEnd;
  end;
end;

function TSectionMove.IsCaptured: Boolean;
var
  mOccurrence: TReassignedOccurrence;
begin
  for mOccurrence in Symbol.Occurrences do
  begin
    if (mOccurrence.Node <> nil) and (OwnerRoutine(mOccurrence.Node) <> Routine) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TSectionMove.IsSafe: Boolean;
var
  mScopeEnd: Integer;
begin
  // Gültigkeitsbereich der Inline-Variablen; kein anderer lokaler Name gleich. Meint derselbe Bezeichner sonst
  // in der Routine etwas anderes (Feld, globale Variable), sähe er danach die Variable.
  mScopeEnd := ScopeEnd;
  Result := (mScopeEnd >= 0) and (WordOffset(Tokens, Symbol.Name, Routine.StartOffset, Routine.EndOffset,
    Decl.StartOffset, mScopeEnd + 1) < 0) and not IsCaptured;
  if Result then
  begin
    Assign := FindToken(Tokens, Decl.StartOffset, Decl.EndOffset, ':=');
    // Ohne Startwert beginnt jeder Schleifendurchlauf mit einer neuen Variablen.
    Result := (Assign >= 0) or not InLoop(Decl, Body);
  end;
end;

function TSectionMove.ResolveType(const AOptions: TVarBlockOptions): Boolean;
begin
  Extra := nil;
  TypeText := Trim(TRoutineLocals.TypeChildText(Text, Decl));
  Result := TypeText <> '';
  if not Result then
  begin
    Result := Assigned(AOptions.Types) and AOptions.Types(Decl, TypeText, Extra) and (Trim(TypeText) <> '');
  end;
  TypeText := Trim(TypeText);
end;

function TSectionMove.DeclarationRemoval(const AInfo: TLineInfo; ASemicolon: Integer; const AEntry: string;
  var AAdd: TTextEdit): TArray<TTextEdit>;
var
  mTrailing, mPrefix, mIndent, mMoved, mComment, mLineBreak: string;
  mCommentLine: Integer;
  mTrailingEnd: TTextPosition;
begin
  if CodeOnLines(Tokens, Decl.StartPos.Line, Tokens[ASemicolon].EndPos.Line, Decl.StartOffset,
    Tokens[ASemicolon].Offset + 1) then
  begin
    Exit(TArray<TTextEdit>.Create(TTextEdit.Create(TTextRange.Create(Decl.StartPos, Tokens[ASemicolon].EndPos), '')));
  end;
  // Allein auf der Zeile: Zeile weg, Kommentare darüber und dahinter wandern in den Abschnitt.
  mLineBreak := TTextLines.LineBreakOf(Text);
  mTrailing := TrailingComment(Text, Tokens, ASemicolon, mTrailingEnd);
  mCommentLine := CommentStart(AInfo, Decl.StartPos.Line, -1, True);
  Result := TArray<TTextEdit>.Create(TTextEdit.Create(TTextRange.Create(mCommentLine, 0,
    Tokens[ASemicolon].EndPos.Line + 1, 0), ''));
  mPrefix := Copy(AAdd.NewText, 1, Pos(AEntry, AAdd.NewText) - 1);
  mIndent := Copy(mPrefix, LastDelimiter(#10, mPrefix) + 1, MaxInt);
  mMoved := '';
  for mComment in CommentLines(AInfo, mCommentLine, Decl.StartPos.Line) do
  begin
    mMoved := mMoved + mComment + mLineBreak + mIndent;
  end;
  mMoved := mMoved + AEntry;
  if mTrailing <> '' then
  begin
    mMoved := mMoved + ' ' + mTrailing;
  end;
  AAdd.NewText := StringReplace(AAdd.NewText, AEntry, mMoved, []);
end;

function TSectionMove.BuildEdits(const AInfo: TLineInfo; const AStyle: TFormatStyle;
  out AEdits: TArray<TTextEdit>): Boolean;
var
  mName, mEntry: string;
  mAdd: TTextEdit;
  mSemicolon: Integer;
begin
  AEdits := nil;
  mName := CleanName(Tokens[NameToken].Text);
  mEntry := Format('%s: %s;', [mName, TypeText]);
  mAdd := TRoutineBody.AddVariable(Text, Routine, mName, TypeText, AStyle);
  Result := True;
  if Assign >= 0 then
  begin
    // var X: T := E  ->  X := E
    AEdits := TArray<TTextEdit>.Create(TTextEdit.Create(TTextRange.Create(Tokens[Keyword].StartPos,
      Tokens[Assign].StartPos), Tokens[NameToken].Text + ' '));
  end
  else
  begin
    mSemicolon := TRoutineBody.NextToken(Tokens, LastTokenOf(Tokens, Decl));
    Result := (mSemicolon <= High(Tokens)) and Tokens[mSemicolon].IsSymbol(';');
    if Result then
    begin
      AEdits := DeclarationRemoval(AInfo, mSemicolon, mEntry, mAdd);
    end;
  end;
  AEdits := TArray<TTextEdit>.Create(mAdd) + AEdits + Extra;
end;

function SectionAction(const AText: string; ATree: TSyntaxTree; const AInfo: TLineInfo;
  const ASymbol: TReassignedSymbol; const AOptions: TVarBlockOptions; out AAction: TCodeAction): Boolean;
var
  mMove: TSectionMove;
  mEdits: TArray<TTextEdit>;
begin
  mMove := Default(TSectionMove);
  mMove.Text := AText;
  mMove.Tree := ATree;
  mMove.Tokens := ATree.Tokens;
  mMove.Symbol := ASymbol;
  Result := mMove.IsCandidate and mMove.IsSafe and mMove.ResolveType(AOptions) and
    mMove.BuildEdits(AInfo, AOptions.Style, mEdits);
  if Result then
  begin
    AAction := Default(TCodeAction);
    AAction.Title := cTexts[TVarBlockText.MoveToVarBlock].Fmt([ASymbol.Name]);
    AAction.Kind := RewriteKind;
    AAction.Edits := mEdits;
  end;
end;

{ var-Block aufräumen }

/// <summary>Typtext ohne Leerraum und in Kleinbuchstaben: Vergleich beim Zusammenfassen.</summary>
function TypeKey(const ATypeText: string): string;
var
  Character: Char;
begin
  Result := '';
  for Character in LowerCase(ATypeText) do
  begin
    if not CharInSet(Character, [' ', #9, #10, #13]) then
    begin
      Result := Result + Character;
    end;
  end;
end;

/// <summary>Kommt AItem vor ACandidate? Stabil über Order.</summary>
function Before(const AItem, ACandidate: TVarItem; ASort: TVarBlockSort): Boolean;
var
  Compared: Integer;
begin
  case ASort of
    TVarBlockSort.Usage:
      if AItem.FirstUse <> ACandidate.FirstUse then
      begin
        Exit(AItem.FirstUse < ACandidate.FirstUse);
      end;
    TVarBlockSort.Alpha:
      begin
        Compared := CompareText(AItem.Names[0], ACandidate.Names[0]);
        if Compared <> 0 then
        begin
          Exit(Compared < 0);
        end;
      end;
    TVarBlockSort.None: ;
  end;
  Result := AItem.Order < ACandidate.Order;
end;

/// <summary>Bedingte Übersetzung, absolute oder Startwerte im Abschnitt: Neuschreiben ginge nicht verlustfrei.
/// </summary>
function SectionUnsupported(const ATokens: TArray<TPascalToken>; ASection: TSyntaxNode): Boolean;
begin
  Result := (ASection.ChildCount = 0) or HasConditional(ATokens, ASection.StartOffset, ASection.EndOffset) or
    (FindToken(ATokens, ASection.StartOffset, ASection.EndOffset, 'absolute') >= 0) or
    (FindToken(ATokens, ASection.StartOffset, ASection.EndOffset, '=') >= 0);
end;

/// <summary>Variablendeklaration ohne Kommentar oder Direktive darin oder davor auf derselben Zeile; ALast ist
/// ihr letztes Token.</summary>
function PlainDecl(const ATokens: TArray<TPascalToken>; ADecl: TSyntaxNode; out ALast: Integer): Boolean;
var
  mFirst, mToken: Integer;
begin
  ALast := -1;
  if (ADecl.Kind <> TSyntaxKind.VarDecl) or (ADecl.ChildCount = 0) then
  begin
    Exit(False);
  end;
  mFirst := TRoutineBody.TokenAt(ATokens, ADecl.StartOffset);
  ALast := LastTokenOf(ATokens, ADecl);
  for mToken := mFirst to ALast do
  begin
    if ATokens[mToken].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive] then
    begin
      Exit(False);
    end;
  end;
  // Kommentar vor dem Eintrag auf derselben Zeile
  Result := not ((mFirst > 0) and (ATokens[mFirst - 1].Kind = TPascalTokenKind.Comment) and
    (ATokens[mFirst - 1].EndPos.Line = ADecl.StartPos.Line));
end;

/// <summary>Eintrag zur Deklaration ADecl, noch ohne Kommentare.</summary>
function EntryOf(const AText: string; ADecl: TSyntaxNode): TVarEntry;
var
  mName: string;
begin
  Result := Default(TVarEntry);
  Result.Decl := ADecl;
  for mName in ADecl.Name.Split([',']) do
  begin
    Result.Names := Result.Names + [Trim(mName)];
  end;
  Result.TypeText := Trim(TRoutineLocals.TypeChildText(AText, ADecl));
  Result.Named := ADecl[0].Kind = TSyntaxKind.TypeReference;
  Result.FirstLine := ADecl.StartPos.Line;
end;

/// <summary>Einträge des Abschnitts samt Kommentaren; False, wenn der Abschnitt etwas enthält, das beim
/// Neuschreiben verloren ginge oder seine Bedeutung änderte (Direktiven, absolute, Startwerte, Kommentare
/// mitten in einem Eintrag).</summary>
function SectionEntries(const AText: string; const ATokens: TArray<TPascalToken>; const AInfo: TLineInfo;
  ASection: TSyntaxNode; out AEntries: TArray<TVarEntry>): Boolean;
var
  mIndex, mLast, mAfter: Integer;
  mDecl: TSyntaxNode;
  mEntry: TVarEntry;
begin
  AEntries := nil;
  if SectionUnsupported(ATokens, ASection) then
  begin
    Exit(False);
  end;
  mAfter := ASection.StartPos.Line;
  for mIndex := 0 to ASection.ChildCount - 1 do
  begin
    mDecl := ASection[mIndex];
    if not PlainDecl(ATokens, mDecl, mLast) then
    begin
      Exit(False);
    end;
    mEntry := EntryOf(AText, mDecl);
    if mEntry.TypeText = '' then
    begin
      Exit(False);
    end;
    if (mDecl.StartPos.Line > mAfter) or (mIndex = 0) then
    begin
      mEntry.FirstLine := CommentStart(AInfo, mDecl.StartPos.Line, mAfter, False);
      mEntry.Comments := CommentLines(AInfo, mEntry.FirstLine, mDecl.StartPos.Line);
    end;
    mEntry.Trailing := TrailingComment(AText, ATokens, mLast, mEntry.EndPos);
    mEntry.EndLine := mEntry.EndPos.Line;
    mAfter := mEntry.EndLine;
    AEntries := AEntries + [mEntry];
  end;
  Result := True;
end;

/// <summary>Benannter Typ ohne Kommentare: darf zusammengefasst und getrennt werden.</summary>
function IsPlainEntry(const AEntry: TVarEntry): Boolean;
begin
  Result := AEntry.Named and (AEntry.Comments = nil) and (AEntry.Trailing = '');
end;

function IsPlainItem(const AItem: TVarItem): Boolean;
begin
  Result := AItem.Named and (AItem.Comments = nil) and (AItem.Trailing = '');
end;

/// <summary>Dürfen die Zeilen AFirst und ASecond eine werden (I, J: Integer)?</summary>
function CanMerge(const AFirst, ASecond: TVarItem): Boolean;
begin
  Result := IsPlainItem(AFirst) and IsPlainItem(ASecond) and (TypeKey(AFirst.TypeText) = TypeKey(ASecond.TypeText));
end;

/// <summary>AItems stabil sortiert (Einfügen).</summary>
function SortedItems(const AItems: TArray<TVarItem>; ASort: TVarBlockSort): TArray<TVarItem>;
var
  mItem: TVarItem;
  mIndex: Integer;
  mInserted: Boolean;
begin
  Result := nil;
  for mItem in AItems do
  begin
    mInserted := False;
    for mIndex := 0 to High(Result) do
    begin
      if Before(mItem, Result[mIndex], ASort) then
      begin
        Insert(mItem, Result, mIndex);
        mInserted := True;
        Break;
      end;
    end;
    if not mInserted then
    begin
      Result := Result + [mItem];
    end;
  end;
end;

/// <summary>Aufeinanderfolgende Zeilen gleichen Typs zusammengefasst, wenn AMerge.</summary>
function MergedItems(const AItems: TArray<TVarItem>; AMerge: Boolean): TArray<TVarItem>;
var
  mItem: TVarItem;
  mIndex: Integer;
begin
  Result := nil;
  for mItem in AItems do
  begin
    mIndex := High(Result);
    if AMerge and (mIndex >= 0) and CanMerge(Result[mIndex], mItem) then
    begin
      Result[mIndex].Names := Result[mIndex].Names + mItem.Names;
    end
    else
    begin
      Result := Result + [mItem];
    end;
  end;
end;

/// <summary>Zeilen des aufgeräumten Abschnitts ohne Einrückung, Kommentare über ihrem Eintrag.</summary>
function ItemLines(const AItems: TArray<TVarItem>): TArray<string>;
var
  mItem: TVarItem;
  mLine: string;
begin
  Result := nil;
  for mItem in AItems do
  begin
    Result := Result + mItem.Comments;
    mLine := Format('%s: %s;', [string.Join(', ', mItem.Names), mItem.TypeText]);
    if mItem.Trailing <> '' then
    begin
      mLine := mLine + ' ' + mItem.Trailing;
    end;
    Result := Result + [mLine];
  end;
end;

type
  /// <summary>Arbeitsstand von „var-Block aufräumen“ im Abschnitt Section der Routine Routine: Einträge Entries,
  /// daraus die Zeilen Items, die Namen ungenutzter Variablen Removed und der Bereich RangeStart..RangeEnd, den
  /// das Edit ersetzt.</summary>
  TCleanup = record
    Text: string;
    LineBreak: string;
    Tokens: TArray<TPascalToken>;
    Info: TLineInfo;
    Routine: TSyntaxNode;
    Section: TSyntaxNode;
    Symbols: TArray<TReassignedSymbol>;
    Entries: TArray<TVarEntry>;
    Items: TArray<TVarItem>;
    Removed: string;
    RangeStart: TTextPosition;
    RangeEnd: TTextPosition;
    class function Create(const AText: string; ATree: TSyntaxTree; const AInfo: TLineInfo;
      const ASymbols: TArray<TReassignedSymbol>; ASection: TSyntaxNode): TCleanup; static;
    /// <summary>Offset der ersten Verwendung des Namens AName aus AEntry; -1 ungenutzt.</summary>
    function FirstUseOf(const AEntry: TVarEntry; const AName: string): Integer;
    procedure AddRemoved(const AName: string);
    procedure AddItem(const ANames: TArray<string>; const AEntry: TVarEntry; AFirstUse: Integer);
    /// <summary>Einträge in Zeilen; ungenutzte Namen fallen weg.</summary>
    procedure CollectItems;
    /// <summary>Alles ungenutzt: der ganze Abschnitt samt "var", wenn er eigene Zeilen hat.</summary>
    function RemovalRange: Boolean;
    /// <summary>Neuer Text der Einträge AItems; setzt den Bereich.</summary>
    function RewriteText(const AItems: TArray<TVarItem>; const AStyle: TFormatStyle): string;
    /// <summary>Bisheriger Text im Bereich.</summary>
    function OldText: string;
    function Action(const AOptions: TVarBlockOptions; out AAction: TCodeAction): Boolean;
  end;

class function TCleanup.Create(const AText: string; ATree: TSyntaxTree; const AInfo: TLineInfo;
  const ASymbols: TArray<TReassignedSymbol>; ASection: TSyntaxNode): TCleanup;
begin
  Result := Default(TCleanup);
  Result.Text := AText;
  Result.LineBreak := TTextLines.LineBreakOf(AText);
  Result.Tokens := ATree.Tokens;
  Result.Info := AInfo;
  Result.Routine := ASection.Parent;
  Result.Section := ASection;
  Result.Symbols := ASymbols;
end;

function TCleanup.FirstUseOf(const AEntry: TVarEntry; const AName: string): Integer;
var
  mSymbol: TReassignedSymbol;
  mOccurrence: TReassignedOccurrence;
begin
  Result := MaxInt;
  for mSymbol in Symbols do
  begin
    if (mSymbol.Decl <> AEntry.Decl) or not SameText(mSymbol.Name, AName) then
    begin
      Continue;
    end;
    for mOccurrence in mSymbol.Occurrences do
    begin
      if (mOccurrence.Node <> nil) and (mOccurrence.Offset < Result) then
      begin
        Result := mOccurrence.Offset;
      end;
    end;
  end;
  // Absicherung, falls die Analyse eine Verwendung nicht sieht (asm, with): Jeder gleichnamige Bezeichner in der
  // Routine zählt als Verwendung.
  if Result = MaxInt then
  begin
    Result := WordOffset(Tokens, AName, Routine.StartOffset, Routine.EndOffset, Section.StartOffset,
      Section.EndOffset);
  end;
end;

procedure TCleanup.AddRemoved(const AName: string);
begin
  if Removed <> '' then
  begin
    Removed := Removed + ', ';
  end;
  Removed := Removed + AName;
end;

procedure TCleanup.AddItem(const ANames: TArray<string>; const AEntry: TVarEntry; AFirstUse: Integer);
var
  mItem: TVarItem;
begin
  mItem := Default(TVarItem);
  mItem.Names := ANames;
  mItem.TypeText := AEntry.TypeText;
  mItem.Named := IsPlainEntry(AEntry);
  mItem.Comments := AEntry.Comments;
  mItem.Trailing := AEntry.Trailing;
  mItem.FirstUse := AFirstUse;
  mItem.Order := Length(Items);
  Items := Items + [mItem];
end;

procedure TCleanup.CollectItems;
var
  mEntry: TVarEntry;
  mName: string;
  mKept: TArray<string>;
  mFirstUse, mWordUse: Integer;
begin
  Items := nil;
  Removed := '';
  for mEntry in Entries do
  begin
    mKept := nil;
    mFirstUse := MaxInt;
    for mName in mEntry.Names do
    begin
      mWordUse := FirstUseOf(mEntry, mName);
      if mWordUse < 0 then
      begin
        AddRemoved(mName);
        Continue;
      end;
      mFirstUse := Min(mFirstUse, mWordUse);
      if IsPlainEntry(mEntry) then
      begin
        // Ohne Kommentar: jeder Name eine eigene Zeile, zusammengefasst wird danach.
        AddItem(TArray<string>.Create(mName), mEntry, mWordUse);
      end
      else
      begin
        mKept := mKept + [mName];
      end;
    end;
    if mKept <> nil then
    begin
      AddItem(mKept, mEntry, mFirstUse);
    end;
  end;
end;

function TCleanup.RemovalRange: Boolean;
var
  mLast: TVarEntry;
begin
  mLast := Entries[High(Entries)];
  Result := not CodeOnLines(Tokens, Section.StartPos.Line, Section.StartPos.Line, Section.StartOffset, MaxInt) and
    not CodeOnLines(Tokens, mLast.EndLine, mLast.EndLine, 0, mLast.Decl.EndOffset);
  RangeStart := TTextPosition.Create(Section.StartPos.Line, 0);
  RangeEnd := TTextPosition.Create(mLast.EndLine + 1, 0);
end;

function TCleanup.RewriteText(const AItems: TArray<TVarItem>; const AStyle: TFormatStyle): string;
var
  mAtLineStart: Boolean;
  mIndent: string;
  mLines: TArray<string>;
  mIndex: Integer;
  mFirst: TSyntaxNode;
begin
  mFirst := Entries[0].Decl;
  mAtLineStart := not CodeOnLines(Tokens, mFirst.StartPos.Line, mFirst.StartPos.Line, mFirst.StartOffset, MaxInt);
  if mAtLineStart then
  begin
    mIndent := TTextLines.IndentOf(Text, mFirst.StartPos.Line);
    RangeStart := TTextPosition.Create(Entries[0].FirstLine, 0);
  end
  else
  begin
    mIndent := TTextLines.IndentOf(Text, Section.StartPos.Line) + TRoutineBody.IndentUnit(AStyle);
    RangeStart := mFirst.StartPos;
  end;
  RangeEnd := Entries[High(Entries)].EndPos;
  mLines := ItemLines(AItems);
  Result := '';
  for mIndex := 0 to High(mLines) do
  begin
    if mIndex > 0 then
    begin
      Result := Result + LineBreak;
    end;
    if (mIndex > 0) or mAtLineStart then
    begin
      Result := Result + mIndent;
    end;
    Result := Result + mLines[mIndex];
  end;
end;

function TCleanup.OldText: string;
var
  mLine: Integer;
  mText: string;
begin
  Result := '';
  for mLine := RangeStart.Line to Min(RangeEnd.Line, High(Info.Lines)) do
  begin
    mText := Info.Lines[mLine];
    if mLine = RangeEnd.Line then
    begin
      mText := Copy(mText, 1, RangeEnd.Character);
    end;
    if mLine = RangeStart.Line then
    begin
      mText := Copy(mText, RangeStart.Character + 1, MaxInt);
    end;
    if mLine > RangeStart.Line then
    begin
      Result := Result + LineBreak;
    end;
    Result := Result + mText;
  end;
end;

function TCleanup.Action(const AOptions: TVarBlockOptions; out AAction: TCodeAction): Boolean;
var
  mItems: TArray<TVarItem>;
  mNewText: string;
begin
  Result := SectionEntries(Text, Tokens, Info, Section, Entries);
  if not Result then
  begin
    Exit;
  end;
  CollectItems;
  mItems := MergedItems(SortedItems(Items, AOptions.Sort), AOptions.Merge);
  mNewText := '';
  if mItems = nil then
  begin
    Result := RemovalRange;
  end
  else
  begin
    mNewText := RewriteText(mItems, AOptions.Style);
  end;
  // Unverändert: keine Aktion.
  Result := Result and (OldText <> mNewText);
  if not Result then
  begin
    Exit;
  end;
  AAction := Default(TCodeAction);
  AAction.Title := cTexts[TVarBlockText.CleanUpVarBlock].Text;
  if Removed <> '' then
  begin
    AAction.Title := AAction.Title + cTexts[TVarBlockText.Unused].Fmt([Removed]);
  end;
  AAction.Kind := RewriteKind;
  AAction.Edits := TArray<TTextEdit>.Create(TTextEdit.Create(TTextRange.Create(RangeStart, RangeEnd), mNewText));
end;

{ TVarBlock }

class function TVarBlock.SortOf(const AName: string): TVarBlockSort;
var
  Sort: TVarBlockSort;
begin
  for Sort := Low(TVarBlockSort) to High(TVarBlockSort) do
  begin
    if SameText(SortNames[Sort], AName) then
    begin
      Exit(Sort);
    end;
  end;
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
      begin
        Exit(TSyntaxSearchStep.Skip);
      end;
      if (ANode.Kind = TSyntaxKind.VarSection) and (ANode.Parent <> nil) and
        (ANode.Parent.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) then
      begin
        Exit(TSyntaxSearchStep.Found);
      end;
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
  begin
    Exit;
  end;
  Result := 0;
  for Line := 0 to APosition.Line - 1 do
  begin
    Result := Result + Length(AInfo.Lines[Line]) + Length(ALineBreak);
  end;
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
  Cleanup: TCleanup;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  Info := LineInfoOf(AText, ATree.Tokens);
  Symbols := TReassigned.Analyze(AText, ATree, AOptions.Lookup);
  if TReassigned.SymbolAt(Symbols, APosition, Symbol) then
  begin
    if AOptions.InlineVariables and InlineAction(AText, ATree, Info, Symbol, Action) then
    begin
      Result := Result + [Action];
    end;
    if SectionAction(AText, ATree, Info, Symbol, AOptions, Action) then
    begin
      Result := Result + [Action];
    end;
  end;
  Offset := OffsetOf(Info, APosition, TTextLines.LineBreakOf(AText));
  if Offset < 0 then
  begin
    Exit;
  end;
  Section := SectionAt(ATree, Offset);
  if Section = nil then
  begin
    Exit;
  end;
  Cleanup := TCleanup.Create(AText, ATree, Info, Symbols, Section);
  if Cleanup.Action(AOptions, Action) then
  begin
    Result := Result + [Action];
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.VarBlock', cTexts);

end.
