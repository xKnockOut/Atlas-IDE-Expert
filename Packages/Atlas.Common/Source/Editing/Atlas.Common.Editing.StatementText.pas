unit Atlas.Common.Editing.StatementText;

// Anweisungen aus dem Syntaxbaum als Text für Umformungen (Kette L: #646,
// #656, #684): Ein Zweig liefert seine Anweisungen (begin … end ausgepackt),
// jede mit den Kommentaren davor und dahinter, neu eingerückt. Daraus baut
// Branch den Zweig einer neuen Anweisung: eine Anweisung direkt, mehrere in
// begin … end. Kommentare zwischen den Anweisungen bleiben bei ihrer
// Anweisung; Kommentare vor dem end eines Blocks hängen an der letzten.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  /// <summary>Eine Umformung als Code-Aktion: Titel und Textänderung.</summary>
  TStatementRewrite = record
    Title: string;
    Edit: TTextEdit;
    class function Create(const ATitle: string; const AEdit: TTextEdit): TStatementRewrite; static;
  end;

  /// <summary>Layout für neu geschriebene Anweisungen.</summary>
  TStatementLayout = record
    /// <summary>Einrückung der Zeile mit dem Schlüsselwort (if, case, Zweig).</summary>
    Indent: string;
    /// <summary>Eine Einrückungsstufe (Formatstil).</summary>
    IndentUnit: string;
    LineBreak: string;
    class function Create(const AIndent, AIndentUnit, ALineBreak: string): TStatementLayout; static;
    /// <summary>Dasselbe Layout eine Stufe tiefer.</summary>
    function Deeper: TStatementLayout;
  end;

  /// <summary>Bereich einer Anweisung samt der Kommentare, die TStatementText.Text mitnimmt (Offsets).</summary>
  TStatementSpan = record
    StartOffset: Integer;
    EndOffset: Integer;
  end;

  TStatementText = record
  public
    /// <summary>Anweisungen eines Zweigs: die eines Blocks begin … end, sonst ANode selbst. Leere Anweisungen
    /// fallen weg; nil ohne Anweisung.</summary>
    class function Statements(ANode: TSyntaxNode): TArray<TSyntaxNode>; static;
    /// <summary>Text der Anweisung samt Kommentaren davor und dahinter (dahinter nur in derselben Zeile, bei
    /// ALast bis zum nächsten Code), ohne abschließendes Semikolon, jede Zeile auf AIndent eingerückt. Die
    /// Kommentare dahinter folgen auf die Marke #0 (siehe Finish).</summary>
    class function Text(const AText: string; ATree: TSyntaxTree; AStatement: TSyntaxNode; ALast: Boolean;
      const AIndent, ALineBreak: string): string; static;
    /// <summary>Setzt ASuffix (";", " else" oder '') hinter die Anweisung und vor ihre Kommentare (Marke #0 aus
    /// Text und Branch).</summary>
    class function Finish(const AStatement, ASuffix: string): string; static;
    /// <summary>Anweisungen als Liste: je Anweisung eine Zeile auf AIndent mit Semikolon dahinter, getrennt durch
    /// ALineBreak (ohne Umbruch am Anfang und Ende).</summary>
    class function List(const AText: string; ATree: TSyntaxTree; const AStatements: TArray<TSyntaxNode>;
      const AIndent, ALineBreak: string): string; static;
    /// <summary>Zweig hinter then/else/do/case-Marke: Umbruch, eine Anweisung eine Stufe tiefer bzw. mehrere in
    /// begin … end auf ALayout.Indent. Ohne Semikolon am Ende; Kommentare hinter der letzten Anweisung stehen
    /// hinter der Marke #0, die Finish ersetzt. Ohne Anweisung: Umbruch und "begin end"-Block nur
    /// mit AEmptyBlock, sonst ''.</summary>
    class function Branch(const AText: string; ATree: TSyntaxTree; const AStatements: TArray<TSyntaxNode>;
      const ALayout: TStatementLayout; AEmptyBlock: Boolean): string; static;
    /// <summary>Bereich, den Text für AStatement liest: Anweisung samt Kommentaren davor und dahinter.</summary>
    class procedure Span(ATree: TSyntaxTree; AStatement: TSyntaxNode; ALast: Boolean; out AStart, AEnd: Integer);
      static;
    class function SpanOf(ATree: TSyntaxTree; AStatement: TSyntaxNode; ALast: Boolean): TStatementSpan; static;
    /// <summary>Steht zwischen AStart und AEnd ein Kommentar außerhalb von ASpans, den das Umschreiben verlöre?
    /// </summary>
    class function Uncovered(ATree: TSyntaxTree; AStart, AEnd: Integer; const ASpans: TArray<TStatementSpan>): Boolean;
      static;
    /// <summary>Steht ein Kommentar zwischen AStart und AEnd (Offsets), den das Umschreiben verlöre?</summary>
    class function HasComment(ATree: TSyntaxTree; AStart, AEnd: Integer): Boolean; static;
    /// <summary>Bereiche aller Anweisungen der Zweige ABranches (je Zweig die letzte mit ALast).</summary>
    class function Spans(ATree: TSyntaxTree; const ABranches: TArray<TSyntaxNode>): TArray<TStatementSpan>; static;
    /// <summary>Wie Branch für den Zweig ABranch; vor einem else (ABeforeElse) bekommt ein einzelnes inneres if
    /// begin … end, sonst gehörte das else zu ihm. Ohne Anweisung ein leerer begin … end-Block.</summary>
    class function GuardedBranch(const AText: string; ATree: TSyntaxTree; ABranch: TSyntaxNode;
      const ALayout: TStatementLayout; ABeforeElse: Boolean): string; static;
    /// <summary>Ende der Ersetzung für die Anweisung ANode: hinter ihr, über ein folgendes Semikolon und die
    /// Kommentare dahinter, die ASpans mitnehmen. ASuffix ist ';', wenn die Ersetzung ein Semikolon schluckt.
    /// </summary>
    class function ReplacementEnd(ATree: TSyntaxTree; ANode: TSyntaxNode; const ASpans: TArray<TStatementSpan>;
      out ASuffix: string): TTextPosition; static;
    /// <summary>Innerste Anweisung der Art AKind, deren Kopf (vom Anfang bis zum zweiten Kind, etwa if … then,
    /// case … of, while … do) APosition enthält; nil ohne.</summary>
    class function HeadAt(ATree: TSyntaxTree; const APosition: TTextPosition; AKind: TSyntaxKind): TSyntaxNode;
      static;
    /// <summary>Liegt APosition in ANode (Anfang und Ende eingeschlossen)?</summary>
    class function Encloses(ANode: TSyntaxNode; const APosition: TTextPosition): Boolean; static;
    /// <summary>Stelle von AChild unter den Kindern von AParent; -1, wenn es keins ist.</summary>
    class function ChildIndex(AParent, AChild: TSyntaxNode): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Text.Lines;

{ TStatementRewrite }

class function TStatementRewrite.Create(const ATitle: string; const AEdit: TTextEdit): TStatementRewrite;
begin
  Result.Title := ATitle;
  Result.Edit := AEdit;
end;

{ TStatementLayout }

class function TStatementLayout.Create(const AIndent, AIndentUnit, ALineBreak: string): TStatementLayout;
begin
  Result.Indent := AIndent;
  Result.IndentUnit := AIndentUnit;
  Result.LineBreak := ALineBreak;
end;

function TStatementLayout.Deeper: TStatementLayout;
begin
  Result := TStatementLayout.Create(Indent + IndentUnit, IndentUnit, LineBreak);
end;

{ TStatementText }

class function TStatementText.Statements(ANode: TSyntaxNode): TArray<TSyntaxNode>;
var
  Index: Integer;
begin
  Result := nil;
  if ANode = nil then
    Exit;
  if ANode.Kind = TSyntaxKind.Block then
  begin
    for Index := 0 to ANode.ChildCount - 1 do
      if TRoutineBody.IsStatement(ANode[Index]) and (ANode[Index].Kind <> TSyntaxKind.EmptyStatement) then
        Result := Result + [ANode[Index]];
  end
  else if TRoutineBody.IsStatement(ANode) and (ANode.Kind <> TSyntaxKind.EmptyStatement) then
    Result := [ANode];
end;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

/// <summary>Zeile (ab 0) des Offsets AOffset.</summary>
function LineOfOffset(const AText: string; AOffset: Integer): Integer;
var
  Index: Integer;
begin
  Result := 0;
  for Index := 1 to AOffset do
    if AText[Index] = #10 then
      Inc(Result);
end;

class procedure TStatementText.Span(ATree: TSyntaxTree; AStatement: TSyntaxNode; ALast: Boolean; out AStart,
  AEnd: Integer);
var
  Tokens: TArray<TPascalToken>;
  Index, EndLine, Previous: Integer;
begin
  Tokens := ATree.Tokens;
  // Davor: Kommentare zwischen dem vorigen Code-Token und der Anweisung. Steht ein Kommentar in der Zeile eines
  // Semikolons, gehört er zur vorigen Anweisung; hinter then, else, begin, do oder einer Marke zum Zweig.
  AStart := AStatement.StartOffset;
  Index := TRoutineBody.TokenAt(Tokens, AStatement.StartOffset) - 1;
  Previous := TRoutineBody.PreviousToken(Tokens, Index + 1);
  while (Index >= 0) and IsTrivia(Tokens[Index]) do
  begin
    if (Previous >= 0) and Tokens[Previous].IsSymbol(';') and
      (Tokens[Index].StartPos.Line = Tokens[Previous].EndPos.Line) then
      Break;
    AStart := Tokens[Index].Offset;
    Dec(Index);
  end;
  // Dahinter, hinter einem Semikolon: in derselben Zeile, bei der letzten Anweisung bis zum Code.
  AEnd := AStatement.EndOffset;
  Index := TRoutineBody.TokenAt(Tokens, AStatement.EndOffset);
  if (Index <= High(Tokens)) and Tokens[Index].IsSymbol(';') and (Tokens[Index].Offset = AStatement.EndOffset) then
    Inc(Index);
  EndLine := AStatement.EndPos.Line;
  while (Index <= High(Tokens)) and IsTrivia(Tokens[Index]) and (ALast or (Tokens[Index].StartPos.Line = EndLine)) do
  begin
    AEnd := Tokens[Index].Offset + Length(Tokens[Index].Text);
    Inc(Index);
  end;
end;

class function TStatementText.Text(const AText: string; ATree: TSyntaxTree; AStatement: TSyntaxNode; ALast: Boolean;
  const AIndent, ALineBreak: string): string;
var
  Tokens: TArray<TPascalToken>;
  Index, Start, Stop, EndLine: Integer;
  Trailing, Remove: string;
begin
  Tokens := ATree.Tokens;
  Span(ATree, AStatement, ALast, Start, Stop);
  Remove := TTextLines.IndentOf(AText, LineOfOffset(AText, Start));
  Result := TRoutineBody.Reindent(TTextLines.NormalizeLineBreaks(Copy(AText, Start + 1,
    AStatement.EndOffset - Start), ALineBreak), Remove, AIndent, ALineBreak);
  // Kommentare dahinter: dieselben Token wie in Span.
  Index := TRoutineBody.TokenAt(Tokens, AStatement.EndOffset);
  EndLine := AStatement.EndPos.Line;
  Trailing := '';
  while (Index <= High(Tokens)) and (Tokens[Index].Offset < Stop) do
  begin
    if IsTrivia(Tokens[Index]) then
    begin
      if Tokens[Index].StartPos.Line = EndLine then
      begin
        if Trailing <> '' then
          Trailing := Trailing + ' ';
        Trailing := Trailing + Tokens[Index].Text;
      end
      else
        // Kommentare in eigenen Zeilen: eigene Zeile, auch hinter dem Semikolon (Finish).
        Trailing := Trailing + ALineBreak + AIndent + Tokens[Index].Text;
    end;
    Inc(Index);
  end;
  // Die Kommentare stehen hinter dem Semikolon bzw. else, das der Aufrufer anhängt (Finish); bis dahin hinter
  // der Marke #0.
  if Trailing <> '' then
    Result := Result + #0 + Trailing;
end;

class function TStatementText.Uncovered(ATree: TSyntaxTree; AStart, AEnd: Integer;
  const ASpans: TArray<TStatementSpan>): Boolean;
var
  Tokens: TArray<TPascalToken>;
  Index: Integer;
  Span_: TStatementSpan;
  Covered: Boolean;
begin
  Tokens := ATree.Tokens;
  Index := TRoutineBody.TokenAt(Tokens, AStart);
  while (Index <= High(Tokens)) and (Tokens[Index].Offset < AEnd) do
  begin
    if Tokens[Index].Kind = TPascalTokenKind.Comment then
    begin
      Covered := False;
      for Span_ in ASpans do
        if (Tokens[Index].Offset >= Span_.StartOffset) and (Tokens[Index].Offset < Span_.EndOffset) then
          Covered := True;
      if not Covered then
        Exit(True);
    end;
    Inc(Index);
  end;
  Result := False;
end;

class function TStatementText.SpanOf(ATree: TSyntaxTree; AStatement: TSyntaxNode; ALast: Boolean): TStatementSpan;
begin
  Span(ATree, AStatement, ALast, Result.StartOffset, Result.EndOffset);
end;

class function TStatementText.Finish(const AStatement, ASuffix: string): string;
var
  Marker: Integer;
  Rest: string;
begin
  Marker := Pos(#0, AStatement);
  if Marker = 0 then
    Exit(AStatement + ASuffix);
  Rest := Copy(AStatement, Marker + 1, MaxInt);
  if (Rest <> '') and CharInSet(Rest[1], [#10, #13]) then
    Result := Copy(AStatement, 1, Marker - 1) + ASuffix + Rest
  else
    Result := Copy(AStatement, 1, Marker - 1) + ASuffix + ' ' + Rest;
end;

class function TStatementText.List(const AText: string; ATree: TSyntaxTree; const AStatements: TArray<TSyntaxNode>;
  const AIndent, ALineBreak: string): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to High(AStatements) do
  begin
    if Index > 0 then
      Result := Result + ALineBreak;
    Result := Result + Finish(Text(AText, ATree, AStatements[Index], Index = High(AStatements), AIndent,
      ALineBreak), ';');
  end;
end;

class function TStatementText.Branch(const AText: string; ATree: TSyntaxTree; const AStatements: TArray<TSyntaxNode>;
  const ALayout: TStatementLayout; AEmptyBlock: Boolean): string;
var
  Inner: string;
begin
  if AStatements = nil then
  begin
    if AEmptyBlock then
      Result := ALayout.LineBreak + ALayout.Indent + 'begin' + ALayout.LineBreak + ALayout.Indent + 'end'
    else
      Result := '';
    Exit;
  end;
  if Length(AStatements) = 1 then
  begin
    Inner := Text(AText, ATree, AStatements[0], True, ALayout.Indent + ALayout.IndentUnit, ALayout.LineBreak);
    Result := ALayout.LineBreak + Inner;
    Exit;
  end;
  Result := ALayout.LineBreak + ALayout.Indent + 'begin' + ALayout.LineBreak +
    List(AText, ATree, AStatements, ALayout.Indent + ALayout.IndentUnit, ALayout.LineBreak) + ALayout.LineBreak +
    ALayout.Indent + 'end';
end;

class function TStatementText.HasComment(ATree: TSyntaxTree; AStart, AEnd: Integer): Boolean;
var
  Tokens: TArray<TPascalToken>;
  Index: Integer;
begin
  Tokens := ATree.Tokens;
  Index := TRoutineBody.TokenAt(Tokens, AStart);
  while (Index <= High(Tokens)) and (Tokens[Index].Offset < AEnd) do
  begin
    if Tokens[Index].Kind = TPascalTokenKind.Comment then
      Exit(True);
    Inc(Index);
  end;
  Result := False;
end;

class function TStatementText.Spans(ATree: TSyntaxTree; const ABranches: TArray<TSyntaxNode>): TArray<TStatementSpan>;
var
  Branch_: TSyntaxNode;
  Items: TArray<TSyntaxNode>;
  Index: Integer;
begin
  Result := nil;
  for Branch_ in ABranches do
  begin
    Items := Statements(Branch_);
    for Index := 0 to High(Items) do
      Result := Result + [SpanOf(ATree, Items[Index], Index = High(Items))];
  end;
end;

class function TStatementText.GuardedBranch(const AText: string; ATree: TSyntaxTree; ABranch: TSyntaxNode;
  const ALayout: TStatementLayout; ABeforeElse: Boolean): string;
var
  Items: TArray<TSyntaxNode>;
begin
  Items := Statements(ABranch);
  if ABeforeElse and (Length(Items) = 1) and (Items[0].Kind = TSyntaxKind.IfStatement) then
    Result := ALayout.LineBreak + ALayout.Indent + 'begin' + ALayout.LineBreak +
      List(AText, ATree, Items, ALayout.Indent + ALayout.IndentUnit, ALayout.LineBreak) +
      ALayout.LineBreak + ALayout.Indent + 'end'
  else
    Result := Branch(AText, ATree, Items, ALayout, True);
end;

class function TStatementText.ReplacementEnd(ATree: TSyntaxTree; ANode: TSyntaxNode;
  const ASpans: TArray<TStatementSpan>; out ASuffix: string): TTextPosition;
var
  Tokens: TArray<TPascalToken>;
  Index, Stop: Integer;
  Span_: TStatementSpan;
begin
  Result := ANode.EndPos;
  ASuffix := '';
  Stop := ANode.EndOffset;
  for Span_ in ASpans do
    if Span_.EndOffset > Stop then
      Stop := Span_.EndOffset;
  Tokens := ATree.Tokens;
  Index := TRoutineBody.TokenAt(Tokens, ANode.EndOffset);
  // Das Semikolon gehört zur Ersetzung: Ein Kommentar hinter der letzten Anweisung (// …) stünde sonst vor ihm
  // und schlösse es aus.
  if (Index <= High(Tokens)) and Tokens[Index].IsSymbol(';') then
  begin
    ASuffix := ';';
    Result := Tokens[Index].EndPos;
    Inc(Index);
  end;
  while (Index <= High(Tokens)) and (Tokens[Index].Offset < Stop) do
  begin
    if Tokens[Index].IsSymbol(';') then
      ASuffix := ';';
    Result := Tokens[Index].EndPos;
    Inc(Index);
  end;
end;

class function TStatementText.Encloses(ANode: TSyntaxNode; const APosition: TTextPosition): Boolean;
begin
  Result := ((ANode.StartPos.Line < APosition.Line) or ((ANode.StartPos.Line = APosition.Line) and
    (ANode.StartPos.Character <= APosition.Character))) and ((APosition.Line < ANode.EndPos.Line) or
    ((APosition.Line = ANode.EndPos.Line) and (APosition.Character <= ANode.EndPos.Character)));
end;

class function TStatementText.ChildIndex(AParent, AChild: TSyntaxNode): Integer;
var
  Index: Integer;
begin
  for Index := 0 to AParent.ChildCount - 1 do
    if AParent[Index] = AChild then
      Exit(Index);
  Result := -1;
end;

class function TStatementText.HeadAt(ATree: TSyntaxTree; const APosition: TTextPosition;
  AKind: TSyntaxKind): TSyntaxNode;
var
  Found: TSyntaxNode;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  Found := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      HeadEnd: TTextPosition;
    begin
      Result := True;
      if (ANode.Kind = AKind) and (ANode.ChildCount >= 2) then
      begin
        HeadEnd := ANode[1].StartPos;
        if ((ANode.StartPos.Line < APosition.Line) or ((ANode.StartPos.Line = APosition.Line) and
          (ANode.StartPos.Character <= APosition.Character))) and ((APosition.Line < HeadEnd.Line) or
          ((APosition.Line = HeadEnd.Line) and (APosition.Character <= HeadEnd.Character))) then
          Found := ANode;
      end;
    end);
  Result := Found;
end;

end.
