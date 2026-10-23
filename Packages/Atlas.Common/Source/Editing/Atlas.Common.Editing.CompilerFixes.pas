unit Atlas.Common.Editing.CompilerFixes;

// Schnellkorrekturen für Compilermeldungen, Teil 2 (#549), ohne Protokoll-
// bezug. Grundlage sind Nummer, Zeile und Text der Meldung (deutsche oder
// englische Ausgabe); Namen stehen in Hochkommas.
//   - H2443 (Inline-Funktion nicht erweitert): die Unit aus dem Text (letzter
//     Name in Hochkommas) ins uses des Abschnitts der Zeile eintragen.
//   - E2003 (Unbekannter Bezeichner): Units anbieten, die den Bezeichner
//     deklarieren (wie #284); RTL- und VCL-Units zuerst, dann kürzere Namen.
//   - H2077 (Wert wird nie verwendet): Zuweisung an die genannte Variable
//     entfernen, wenn die rechte Seite sicher keine Nebenwirkung hat
//     (Literale, Operatoren, lokale Variablen, Parameter, Konstanten); ist sie
//     ein Aufruf mit Klammern, bleibt nur der Aufruf. Sonst keine Korrektur:
//     Ohne Namensauflösung kann ein Name ohne Klammern eine Funktion sein.
//   - W1035 (Rückgabewert möglicherweise undefiniert): Result :=
//     Default(<Typ>); direkt hinter das begin der Funktion, Typ aus dem Kopf.
//   - W1057/W1058 (implizite String-Umwandlung): rechte Seite der Zuweisung
//     bzw. das Argument an der Spalte der Meldung in <Zieltyp>(…) setzen; der
//     Zieltyp ist der letzte Name in Hochkommas.
// FixAll fasst alle Meldungen einer Nummer in der Datei zu einer Änderung
// zusammen (überlappende Einfügungen entfallen).

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.UsesActions;

type
  /// <summary>Eine Compilermeldung; Line und Column ab 0, Column -1 ohne Spalte.</summary>
  TFixMessage = record
    Code: string;
    Line: Integer;
    Column: Integer;
    Text: string;
    class function Create(const ACode: string; ALine, AColumn: Integer; const AText: string): TFixMessage; static;
  end;

  TCompilerFix = record
    Code: string;
    Title: string;
    Edits: TArray<TTextEdit>;
    Preferred: Boolean;
  end;

  TCompilerFixContext = record
    /// <summary>Units, die einen Bezeichner deklarieren; nil = keine E2003-Korrektur.</summary>
    Declaring: TUnitsDeclaringFunc;
    Namespaces: TArray<string>;
  end;

  TCompilerFixes = class
  public
    /// <summary>Nummern mit Korrektur.</summary>
    class function Codes: TArray<string>; static;
    /// <summary>Hat ACode eine Korrektur, die FixAll für die ganze Datei anwenden kann?</summary>
    class function CanFixAll(const ACode: string): Boolean; static;
    /// <summary>Namen in Hochkommas aus dem Meldungstext, in Reihenfolge.</summary>
    class function QuotedNames(const AText: string): TArray<string>; static;
    /// <summary>Units in der Reihenfolge, in der E2003 sie anbietet.</summary>
    class function RankUnits(const AUnits: TArray<string>): TArray<string>; static;
    /// <summary>Korrekturen für AMessage im Text AText (Baum ATree).</summary>
    class function Fixes(const AText: string; ATree: TSyntaxTree; const AMessage: TFixMessage;
      const AContext: TCompilerFixContext): TArray<TCompilerFix>; static;
    /// <summary>Alle Meldungen mit ACode in einer Änderung; False, wenn es weniger als zwei Korrekturen gibt.
    /// </summary>
    class function FixAll(const AText: string; ATree: TSyntaxTree; const AMessages: TArray<TFixMessage>;
      const ACode: string; const AContext: TCompilerFixContext; out AFix: TCompilerFix): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.DisableWarning;

const
  FixCodes: array[0..5] of string = ('H2443', 'E2003', 'H2077', 'W1035', 'W1057', 'W1058');
  FixAllCodes: array[0..4] of string = ('H2443', 'H2077', 'W1035', 'W1057', 'W1058');
  // Namespaces der RTL und der Bibliotheken von Delphi: bei E2003 zuerst.
  LibraryNamespaces: array[0..12] of string = ('System', 'Winapi', 'Vcl', 'FMX', 'Data', 'Xml', 'Web', 'Soap',
    'REST', 'Datasnap', 'FireDAC', 'IBX', 'Posix');

{ TFixMessage }

class function TFixMessage.Create(const ACode: string; ALine, AColumn: Integer; const AText: string): TFixMessage;
begin
  Result.Code := UpperCase(Trim(ACode));
  Result.Line := ALine;
  Result.Column := AColumn;
  Result.Text := AText;
end;

{ Hilfen }

function OffsetOf(const AText: string; ALine: Integer): Integer;
var
  Index, Line: Integer;
begin
  // Offset ab 0 des Zeilenanfangs; -1 hinter dem Text.
  Line := 0;
  Index := 1;
  while (Line < ALine) and (Index <= Length(AText)) do
  begin
    if AText[Index] = #10 then
      Inc(Line);
    Inc(Index);
  end;
  Result := Index - 1;
  if Line < ALine then
    Result := -1;
end;

/// <summary>Alle Knoten der Art AKind, die in Zeile ALine beginnen, in Baumreihenfolge.</summary>
function NodesOnLine(ARoot: TSyntaxNode; ALine: Integer; AKind: TSyntaxKind): TArray<TSyntaxNode>;
var
  Found: TArray<TSyntaxNode>;
begin
  Found := nil;
  if ARoot <> nil then
    ARoot.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := (ANode.StartPos.Line <= ALine) and (ANode.EndPos.Line >= ALine);
        if Result and (ANode.Kind = AKind) and (ANode.StartPos.Line = ALine) then
          Found := Found + [ANode];
      end);
  Result := Found;
end;

function Insertion(const APosition: TTextPosition; const AText: string): TTextEdit;
begin
  Result := TTextEdit.Create(TTextRange.Create(APosition, APosition), AText);
end;

function Fix(const ACode, ATitle: string; const AEdits: TArray<TTextEdit>; APreferred: Boolean): TCompilerFix;
begin
  Result.Code := ACode;
  Result.Title := ATitle;
  Result.Edits := AEdits;
  Result.Preferred := APreferred;
end;

{ TCompilerFixes }

class function TCompilerFixes.Codes: TArray<string>;
var
  Index: Integer;
begin
  SetLength(Result, Length(FixCodes));
  for Index := 0 to High(FixCodes) do
    Result[Index] := FixCodes[Index];
end;

class function TCompilerFixes.CanFixAll(const ACode: string): Boolean;
begin
  Result := MatchText(Trim(ACode), FixAllCodes);
end;

class function TCompilerFixes.QuotedNames(const AText: string): TArray<string>;
var
  Index, Start: Integer;
begin
  Result := nil;
  Index := 1;
  while Index <= Length(AText) do
  begin
    if AText[Index] = '''' then
    begin
      Start := Index + 1;
      Index := Start;
      while (Index <= Length(AText)) and (AText[Index] <> '''') do
        Inc(Index);
      if Index > Length(AText) then
        Break;
      Result := Result + [Copy(AText, Start, Index - Start)];
    end;
    Inc(Index);
  end;
end;

function LibraryRank(const AUnit: string): Integer;
var
  Dot: Integer;
begin
  Dot := Pos('.', AUnit);
  Result := 1;
  if (Dot > 0) and MatchText(Copy(AUnit, 1, Dot - 1), LibraryNamespaces) then
    Result := 0;
end;

class function TCompilerFixes.RankUnits(const AUnits: TArray<string>): TArray<string>;
begin
  Result := Copy(AUnits);
  // Eindeutig weitersortieren: TArray.Sort ist nicht stabil.
  TArray.Sort<string>(Result, TComparer<string>.Construct(
    function(const ALeft, ARight: string): Integer
    begin
      Result := LibraryRank(ALeft) - LibraryRank(ARight);
      if Result = 0 then
        Result := Length(ALeft) - Length(ARight);
      if Result = 0 then
        Result := CompareText(ALeft, ARight);
      if Result = 0 then
        Result := CompareStr(ALeft, ARight);
    end));
end;

function AddUnitFix(const AText: string; ATokens: TArray<TPascalToken>; const AMessage: TFixMessage;
  const AUnit: string; APreferred: Boolean; const ATitle: string; out AFix: TCompilerFix): Boolean;
var
  Edit: TTextEdit;
  Offset: Integer;
begin
  Offset := OffsetOf(AText, AMessage.Line);
  Result := (Offset >= 0) and TUsesClauses.AddUnit(ATokens, Offset, AUnit, TTextLines.LineBreakOf(AText), Edit);
  if Result then
    AFix := Fix(AMessage.Code, ATitle, [Edit], APreferred);
end;

function IsUsed(ATokens: TArray<TPascalToken>; const AUnit: string; const ANamespaces: TArray<string>): Boolean;
begin
  Result := TUsesClauses.IsUsed(TUsesClauses.UsedUnits(ATokens), AUnit, ANamespaces);
end;

function H2443Fixes(const AText: string; ATokens: TArray<TPascalToken>; const AMessage: TFixMessage;
  const AContext: TCompilerFixContext): TArray<TCompilerFix>;
var
  Names: TArray<string>;
  UnitName: string;
  Item: TCompilerFix;
begin
  Result := nil;
  Names := TCompilerFixes.QuotedNames(AMessage.Text);
  if Length(Names) < 2 then
    Exit;
  UnitName := Names[High(Names)];
  if IsUsed(ATokens, UnitName, AContext.Namespaces) then
    Exit;
  if AddUnitFix(AText, ATokens, AMessage, UnitName, True, Format('uses %s ergänzen (%s)', [UnitName,
    AMessage.Code]), Item) then
    Result := [Item];
end;

function E2003Fixes(const AText: string; ATokens: TArray<TPascalToken>; ATree: TSyntaxTree;
  const AMessage: TFixMessage; const AContext: TCompilerFixContext): TArray<TCompilerFix>;
var
  Names, Units: TArray<string>;
  Name, UnitName: string;
  Item: TCompilerFix;
  Token: TPascalToken;
  Position: TTextPosition;
  Found: Boolean;
begin
  Result := nil;
  Names := TCompilerFixes.QuotedNames(AMessage.Text);
  if (Length(Names) = 0) or not Assigned(AContext.Declaring) then
    Exit;
  Name := Names[0];
  // Den Bezeichner in der Zeile suchen; MissingUnits prüft, ob er schon deklariert oder eingebunden ist.
  Found := False;
  Position := TTextPosition.Create(AMessage.Line, 0);
  for Token in ATokens do
    if (Token.StartPos.Line = AMessage.Line) and (Token.Kind = TPascalTokenKind.Identifier) and
      SameText(Token.Text, Name) and ((AMessage.Column < 0) or not Found or
      (Token.StartPos.Character <= AMessage.Column)) then
    begin
      Position := Token.StartPos;
      Found := True;
    end;
  if not Found then
    Exit;
  Units := TCompilerFixes.RankUnits(TUsesActions.MissingUnits(ATokens, ATree, Position, AContext.Declaring,
    AContext.Namespaces));
  for UnitName in Units do
    if AddUnitFix(AText, ATokens, AMessage, UnitName, Length(Result) = 0, Format('uses %s ergänzen (%s: %s)',
      [UnitName, AMessage.Code, Name]), Item) then
      Result := Result + [Item];
end;

function RoutineOf(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result <> nil) and (Result.Kind <> TSyntaxKind.RoutineDecl) do
    Result := Result.Parent;
end;

/// <summary>Namen, die in ARoutine (und umschließenden Routinen) als Variable, Parameter oder Konstante
/// deklariert sind.</summary>
function LocalNames(ARoutine: TSyntaxNode): TArray<string>;
var
  Names: TArray<string>;
  Routine: TSyntaxNode;
begin
  Names := ['Result', 'nil', 'True', 'False'];
  Routine := ARoutine;
  while Routine <> nil do
  begin
    Routine.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        // Nicht in Rümpfe und verschachtelte Routinen absteigen: Dort deklariert nichts Lokales.
        Result := not (ANode.Kind in [TSyntaxKind.Block]) and
          ((ANode = Routine) or (ANode.Kind <> TSyntaxKind.RoutineDecl));
        if ANode.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.Parameter, TSyntaxKind.ConstDecl] then
          Names := Names + [ANode.Name];
      end);
    Routine := RoutineOf(Routine.Parent);
  end;
  Result := Names;
end;

/// <summary>Ausdruck ohne mögliche Nebenwirkung: nur Literale, Operatoren und lokale Namen.</summary>
function IsPure(ANode: TSyntaxNode; const ALocals: TArray<string>): Boolean;
var
  Index: Integer;
begin
  case ANode.Kind of
    TSyntaxKind.Literal:
      Exit(True);
    TSyntaxKind.Identifier:
      Exit(MatchText(ANode.Name, ALocals));
    TSyntaxKind.BinaryExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.ParenExpr, TSyntaxKind.SetConstructor,
      TSyntaxKind.RangeExpr:
      begin
        // Klassenoperatoren könnten Nebenwirkungen haben; is/as und Mengen sind harmlos genug, Aufrufe nicht.
        for Index := 0 to ANode.ChildCount - 1 do
          if not IsPure(ANode[Index], ALocals) then
            Exit(False);
        Exit(True);
      end;
  end;
  Result := False;
end;

function StatementRemoval(const AText: string; ATokens: TArray<TPascalToken>; AStatement: TSyntaxNode): TTextEdit;
var
  Index, Last: Integer;
  Lines: TArray<string>;
  Line: string;
  EndPos: TTextPosition;
begin
  EndPos := AStatement.EndPos;
  if TRoutineBody.InList(AStatement) then
  begin
    // Mit dem Semikolon dahinter; steht die Anweisung allein in ihrer Zeile, verschwindet die ganze Zeile.
    Index := TRoutineBody.TokenAt(ATokens, AStatement.EndOffset);
    Last := TRoutineBody.NextToken(ATokens, Index - 1);
    if (Last >= 0) and (Last < Length(ATokens)) and ATokens[Last].IsSymbol(';') then
      EndPos := ATokens[Last].EndPos;
    Lines := TTextLines.SplitLines(AText);
    if (AStatement.StartPos.Line = EndPos.Line) and (EndPos.Line < High(Lines)) then
    begin
      Line := Lines[EndPos.Line];
      if (Trim(Copy(Line, 1, AStatement.StartPos.Character)) = '') and
        (Trim(Copy(Line, EndPos.Character + 1, MaxInt)) = '') then
        Exit(TTextEdit.Create(TTextRange.Create(EndPos.Line, 0, EndPos.Line + 1, 0), ''));
    end;
  end;
  Result := TTextEdit.Create(TTextRange.Create(AStatement.StartPos, EndPos), '');
end;

function H2077Fixes(const AText: string; ATokens: TArray<TPascalToken>; ATree: TSyntaxTree;
  const AMessage: TFixMessage): TArray<TCompilerFix>;
var
  Names: TArray<string>;
  Statement, Value: TSyntaxNode;
  Name: string;
begin
  Result := nil;
  Names := TCompilerFixes.QuotedNames(AMessage.Text);
  if Length(Names) = 0 then
    Exit;
  Name := Names[0];
  for Statement in NodesOnLine(ATree.Root, AMessage.Line, TSyntaxKind.AssignStatement) do
  begin
    if (Statement.ChildCount < 2) or (Statement[0].Kind <> TSyntaxKind.Identifier) or
      not SameText(Statement[0].Name, Name) then
      Continue;
    Value := Statement[1];
    if IsPure(Value, LocalNames(RoutineOf(Statement))) then
      Exit([Fix(AMessage.Code, Format('Wirkungslose Zuweisung an %s entfernen (%s)', [Name, AMessage.Code]),
        [StatementRemoval(AText, ATokens, Statement)], True)])
    else if Value.Kind = TSyntaxKind.Call then
      // Der Aufruf bleibt, nur die Zuweisung fällt weg.
      Exit([Fix(AMessage.Code, Format('Zuweisung an %s entfernen, nur %s aufrufen (%s)', [Name, Value.Name,
        AMessage.Code]), [TTextEdit.Create(TTextRange.Create(Statement.StartPos, Value.StartPos), '')], True)]);
  end;
end;

function W1035Fixes(const AText: string; ATree: TSyntaxTree; const AMessage: TFixMessage): TArray<TCompilerFix>;
var
  Routine, Header, Body, ResultType: TSyntaxNode;
  Index: Integer;
  TypeText, Indent: string;
  Lines: TArray<string>;
  LineBreak: string;
begin
  Result := nil;
  // Die Meldung steht auf dem end der Funktion (oder ihrem Kopf): innerste Routine um die Zeile.
  Routine := TDisableWarning.RoutineAt(ATree, AMessage.Line);
  if Routine = nil then
    Exit;
  Header := Routine.FindChild(TSyntaxKind.RoutineHeader);
  Body := TRoutineBody.BodyOf(Routine);
  if (Header = nil) or (Body = nil) then
    Exit;
  ResultType := nil;
  for Index := 0 to Header.ChildCount - 1 do
    if Header[Index].Kind = TSyntaxKind.TypeReference then
      ResultType := Header[Index];
  if ResultType = nil then
    Exit;
  TypeText := TRoutineBody.TextOf(AText, ResultType);
  Lines := TTextLines.SplitLines(AText, LineBreak);
  Indent := TTextLines.IndentOf(Lines[Body.StartPos.Line]) + '  ';
  if (Body.ChildCount > 0) and (Body[0].StartPos.Line > Body.StartPos.Line) then
    Indent := TTextLines.IndentOf(Lines[Body[0].StartPos.Line]);
  Result := [Fix(AMessage.Code, Format('Result := Default(%s); am Anfang einfügen (%s)', [TypeText,
    AMessage.Code]), [Insertion(TTextPosition.Create(Body.StartPos.Line, Body.StartPos.Character + Length('begin')),
    LineBreak + Indent + Format('Result := Default(%s);', [TypeText]))], True)];
end;

function StringCastFixes(const AText: string; ATree: TSyntaxTree; const AMessage: TFixMessage):
  TArray<TCompilerFix>;
var
  Names: TArray<string>;
  Target: string;
  Candidates: TArray<TSyntaxNode>;
  Node, Chosen: TSyntaxNode;
  Index: Integer;
begin
  Result := nil;
  Names := TCompilerFixes.QuotedNames(AMessage.Text);
  if Length(Names) < 2 then
    Exit;
  Target := Names[High(Names)];
  // Kandidaten: rechte Seiten von Zuweisungen und Argumente von Aufrufen in der Zeile.
  Candidates := nil;
  for Node in NodesOnLine(ATree.Root, AMessage.Line, TSyntaxKind.AssignStatement) do
    if Node.ChildCount >= 2 then
      Candidates := Candidates + [Node[1]];
  for Node in NodesOnLine(ATree.Root, AMessage.Line, TSyntaxKind.Call) do
    for Index := 1 to Node.ChildCount - 1 do
      if Node[Index].StartPos.Line = AMessage.Line then
        Candidates := Candidates + [Node[Index]];
  Chosen := nil;
  if AMessage.Column >= 0 then
  begin
    for Node in Candidates do
      if (Node.StartPos.Character <= AMessage.Column) and ((Node.EndPos.Line > AMessage.Line) or
        (AMessage.Column <= Node.EndPos.Character)) and ((Chosen = nil) or
        (Node.EndOffset - Node.StartOffset < Chosen.EndOffset - Chosen.StartOffset)) then
        Chosen := Node;
  end
  else
  begin
    // Ohne Spalte nur eindeutig: genau eine Zuweisung in der Zeile.
    Candidates := nil;
    for Node in NodesOnLine(ATree.Root, AMessage.Line, TSyntaxKind.AssignStatement) do
      if Node.ChildCount >= 2 then
        Candidates := Candidates + [Node[1]];
    if Length(Candidates) = 1 then
      Chosen := Candidates[0];
  end;
  if Chosen = nil then
    Exit;
  Result := [Fix(AMessage.Code, Format('Explizit umwandeln: %s(…) (%s)', [Target, AMessage.Code]),
    [Insertion(Chosen.StartPos, Target + '('), Insertion(Chosen.EndPos, ')')], True)];
end;

class function TCompilerFixes.Fixes(const AText: string; ATree: TSyntaxTree; const AMessage: TFixMessage;
  const AContext: TCompilerFixContext): TArray<TCompilerFix>;
var
  Tokens: TArray<TPascalToken>;
begin
  Result := nil;
  if (ATree = nil) or (AMessage.Line < 0) then
    Exit;
  Tokens := ATree.Tokens;
  if AMessage.Code = 'H2443' then
    Result := H2443Fixes(AText, Tokens, AMessage, AContext)
  else if AMessage.Code = 'E2003' then
    Result := E2003Fixes(AText, Tokens, ATree, AMessage, AContext)
  else if AMessage.Code = 'H2077' then
    Result := H2077Fixes(AText, Tokens, ATree, AMessage)
  else if AMessage.Code = 'W1035' then
    Result := W1035Fixes(AText, ATree, AMessage)
  else if (AMessage.Code = 'W1057') or (AMessage.Code = 'W1058') then
    Result := StringCastFixes(AText, ATree, AMessage);
end;

function Compare(const A, B: TTextPosition): Integer;
begin
  Result := A.Line - B.Line;
  if Result = 0 then
    Result := A.Character - B.Character;
end;

/// <summary>Überschneidet sich AEdit mit einer Änderung aus AEdits? Zwei Einfügungen an verschiedenen Stellen
/// nicht, an derselben schon (die Reihenfolge wäre offen).</summary>
function Overlaps(const AEdit: TTextEdit; const AEdits: TArray<TTextEdit>): Boolean;
var
  Other: TTextEdit;
begin
  for Other in AEdits do
    if (Compare(AEdit.Range.StartPos, Other.Range.EndPos) <= 0) and
      (Compare(Other.Range.StartPos, AEdit.Range.EndPos) <= 0) and
      not ((Compare(AEdit.Range.StartPos, Other.Range.EndPos) = 0) and
      (Compare(AEdit.Range.StartPos, AEdit.Range.EndPos) <> 0)) and
      not ((Compare(Other.Range.StartPos, AEdit.Range.EndPos) = 0) and
      (Compare(Other.Range.StartPos, Other.Range.EndPos) <> 0)) then
      Exit(True);
  Result := False;
end;

function OverlapsAny(const AEdits, AOthers: TArray<TTextEdit>): Boolean;
var
  Edit: TTextEdit;
begin
  for Edit in AEdits do
    if Overlaps(Edit, AOthers) then
      Exit(True);
  Result := False;
end;

class function TCompilerFixes.FixAll(const AText: string; ATree: TSyntaxTree;
  const AMessages: TArray<TFixMessage>; const ACode: string; const AContext: TCompilerFixContext;
  out AFix: TCompilerFix): Boolean;
var
  Message: TFixMessage;
  Item: TCompilerFix;
  Edits: TArray<TTextEdit>;
  Units, Added, Names: TArray<string>;
  Count: Integer;
  Code: string;
begin
  AFix := Default(TCompilerFix);
  Code := UpperCase(Trim(ACode));
  Result := False;
  if (ATree = nil) or not CanFixAll(Code) then
    Exit;
  Edits := nil;
  Count := 0;
  if Code = 'H2443' then
  begin
    // Alle Units in einem Schritt, jede einmal; AddUnits verteilt sie auf interface und implementation.
    Units := nil;
    for Message in AMessages do
      if Message.Code = Code then
      begin
        Names := QuotedNames(Message.Text);
        if (Length(Names) >= 2) and (IndexText(Names[High(Names)], Units) < 0) then
          Units := Units + [Names[High(Names)]];
      end;
    if Length(Units) < 2 then
      Exit;
    if not TUsesActions.AddUnits(ATree.Tokens, Units, AContext.Declaring, AContext.Namespaces,
      TTextLines.LineBreakOf(AText), Edits, Added) then
      Exit;
    Count := Length(Added);
  end
  else
    for Message in AMessages do
      if Message.Code = Code then
        for Item in Fixes(AText, ATree, Message, AContext) do
        begin
          // Nur die erste (bevorzugte) Korrektur je Meldung, ohne Überschneidung mit schon gesammelten.
          if not OverlapsAny(Item.Edits, Edits) then
          begin
            Edits := Edits + Item.Edits;
            Inc(Count);
          end;
          Break;
        end;
  Result := Count >= 2;
  if Result then
    AFix := Fix(Code, Format('Alle %s in der Datei beheben (%d)', [Code, Count]), Edits, False);
end;

end.
