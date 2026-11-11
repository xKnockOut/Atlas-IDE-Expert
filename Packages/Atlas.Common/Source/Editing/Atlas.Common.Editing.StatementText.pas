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
  Atlas.Common.Pascal.TokenCursor,
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
  mIndex: Integer;
begin
  Result := nil;
  if ANode = nil then
  begin
    Exit;
  end;
  if ANode.Kind = TSyntaxKind.Block then
  begin
    for mIndex := 0 to ANode.ChildCount - 1 do
    begin
      if TRoutineBody.IsStatement(ANode[mIndex]) and (ANode[mIndex].Kind <> TSyntaxKind.EmptyStatement) then
      begin
        Result := Result + [ANode[mIndex]];
      end;
    end;
  end
  else if TRoutineBody.IsStatement(ANode) and (ANode.Kind <> TSyntaxKind.EmptyStatement) then
  begin
    Result := [ANode];
  end;
end;

/// <summary>Zeile (ab 0) des Offsets AOffset.</summary>
function LineOfOffset(const AText: string; AOffset: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex := 1 to AOffset do
  begin
    if AText[mIndex] = #10 then
    begin
      Inc(Result);
    end;
  end;
end;

class procedure TStatementText.Span(ATree: TSyntaxTree; AStatement: TSyntaxNode; ALast: Boolean; out AStart,
  AEnd: Integer);
var
  mTokens: TArray<TPascalToken>;
  mIndex, mEndLine, mPrevious: Integer;
begin
  mTokens := ATree.Tokens;
  // Davor: Kommentare zwischen dem vorigen Code-Token und der Anweisung. Steht ein Kommentar in der Zeile eines
  // Semikolons, gehört er zur vorigen Anweisung; hinter then, else, begin, do oder einer Marke zum Zweig.
  AStart := AStatement.StartOffset;
  mIndex := TRoutineBody.TokenAt(mTokens, AStatement.StartOffset) - 1;
  mPrevious := TRoutineBody.PreviousToken(mTokens, mIndex + 1);
  while (mIndex >= 0) and IsTrivia(mTokens[mIndex]) do
  begin
    if (mPrevious >= 0) and mTokens[mPrevious].IsSymbol(';') and
      (mTokens[mIndex].StartPos.Line = mTokens[mPrevious].EndPos.Line) then
    begin
      Break;
    end;
    AStart := mTokens[mIndex].Offset;
    Dec(mIndex);
  end;
  // Dahinter, hinter einem Semikolon: in derselben Zeile, bei der letzten Anweisung bis zum Code.
  AEnd := AStatement.EndOffset;
  mIndex := TRoutineBody.TokenAt(mTokens, AStatement.EndOffset);
  if (mIndex <= High(mTokens)) and mTokens[mIndex].IsSymbol(';') and (mTokens[mIndex].Offset = AStatement.EndOffset) then
  begin
    Inc(mIndex);
  end;
  mEndLine := AStatement.EndPos.Line;
  while (mIndex <= High(mTokens)) and IsTrivia(mTokens[mIndex]) and
    (ALast or (mTokens[mIndex].StartPos.Line = mEndLine)) do
  begin
    AEnd := mTokens[mIndex].Offset + Length(mTokens[mIndex].Text);
    Inc(mIndex);
  end;
end;

class function TStatementText.Text(const AText: string; ATree: TSyntaxTree; AStatement: TSyntaxNode; ALast: Boolean;
  const AIndent, ALineBreak: string): string;
var
  mTokens: TArray<TPascalToken>;
  mIndex, mStart, mStop, mEndLine: Integer;
  mTrailing, mRemove: string;
begin
  mTokens := ATree.Tokens;
  Span(ATree, AStatement, ALast, mStart, mStop);
  mRemove := TTextLines.IndentOf(AText, LineOfOffset(AText, mStart));
  Result := TRoutineBody.Reindent(TTextLines.NormalizeLineBreaks(Copy(AText, mStart + 1,
    AStatement.EndOffset - mStart), ALineBreak), mRemove, AIndent, ALineBreak);
  // Kommentare dahinter: dieselben Token wie in Span.
  mIndex := TRoutineBody.TokenAt(mTokens, AStatement.EndOffset);
  mEndLine := AStatement.EndPos.Line;
  mTrailing := '';
  while (mIndex <= High(mTokens)) and (mTokens[mIndex].Offset < mStop) do
  begin
    if IsTrivia(mTokens[mIndex]) then
    begin
      if mTokens[mIndex].StartPos.Line = mEndLine then
      begin
        if mTrailing <> '' then
        begin
          mTrailing := mTrailing + ' ';
        end;
        mTrailing := mTrailing + mTokens[mIndex].Text;
      end
      else
      begin
        // Kommentare in eigenen Zeilen: eigene Zeile, auch hinter dem Semikolon (Finish).
        mTrailing := mTrailing + ALineBreak + AIndent + mTokens[mIndex].Text;
      end;
    end;
    Inc(mIndex);
  end;
  // Die Kommentare stehen hinter dem Semikolon bzw. else, das der Aufrufer anhängt (Finish); bis dahin hinter
  // der Marke #0.
  if mTrailing <> '' then
  begin
    Result := Result + #0 + mTrailing;
  end;
end;

class function TStatementText.Uncovered(ATree: TSyntaxTree; AStart, AEnd: Integer;
  const ASpans: TArray<TStatementSpan>): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mIndex: Integer;
  mSpan_: TStatementSpan;
  mCovered: Boolean;
begin
  mTokens := ATree.Tokens;
  mIndex := TRoutineBody.TokenAt(mTokens, AStart);
  while (mIndex <= High(mTokens)) and (mTokens[mIndex].Offset < AEnd) do
  begin
    if mTokens[mIndex].Kind = TPascalTokenKind.Comment then
    begin
      mCovered := False;
      for mSpan_ in ASpans do
      begin
        if (mTokens[mIndex].Offset >= mSpan_.StartOffset) and (mTokens[mIndex].Offset < mSpan_.EndOffset) then
        begin
          mCovered := True;
        end;
      end;
      if not mCovered then
      begin
        Exit(True);
      end;
    end;
    Inc(mIndex);
  end;
  Result := False;
end;

class function TStatementText.SpanOf(ATree: TSyntaxTree; AStatement: TSyntaxNode; ALast: Boolean): TStatementSpan;
begin
  Span(ATree, AStatement, ALast, Result.StartOffset, Result.EndOffset);
end;

class function TStatementText.Finish(const AStatement, ASuffix: string): string;
var
  mMarker: Integer;
  mRest: string;
begin
  mMarker := Pos(#0, AStatement);
  if mMarker = 0 then
  begin
    Exit(AStatement + ASuffix);
  end;
  mRest := Copy(AStatement, mMarker + 1, MaxInt);
  if (mRest <> '') and CharInSet(mRest[1], [#10, #13]) then
  begin
    Result := Copy(AStatement, 1, mMarker - 1) + ASuffix + mRest;
  end
  else
  begin
    Result := Copy(AStatement, 1, mMarker - 1) + ASuffix + ' ' + mRest;
  end;
end;

class function TStatementText.List(const AText: string; ATree: TSyntaxTree; const AStatements: TArray<TSyntaxNode>;
  const AIndent, ALineBreak: string): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(AStatements) do
  begin
    if mIndex > 0 then
    begin
      Result := Result + ALineBreak;
    end;
    Result := Result + Finish(Text(AText, ATree, AStatements[mIndex], mIndex = High(AStatements), AIndent,
      ALineBreak), ';');
  end;
end;

class function TStatementText.Branch(const AText: string; ATree: TSyntaxTree; const AStatements: TArray<TSyntaxNode>;
  const ALayout: TStatementLayout; AEmptyBlock: Boolean): string;
var
  mInner: string;
begin
  if AStatements = nil then
  begin
    if AEmptyBlock then
    begin
      Result := ALayout.LineBreak + ALayout.Indent + 'begin' + ALayout.LineBreak + ALayout.Indent + 'end';
    end
    else
    begin
      Result := '';
    end;
    Exit;
  end;
  if Length(AStatements) = 1 then
  begin
    mInner := Text(AText, ATree, AStatements[0], True, ALayout.Indent + ALayout.IndentUnit, ALayout.LineBreak);
    Result := ALayout.LineBreak + mInner;
    Exit;
  end;
  Result := ALayout.LineBreak + ALayout.Indent + 'begin' + ALayout.LineBreak +
    List(AText, ATree, AStatements, ALayout.Indent + ALayout.IndentUnit, ALayout.LineBreak) + ALayout.LineBreak +
    ALayout.Indent + 'end';
end;

class function TStatementText.HasComment(ATree: TSyntaxTree; AStart, AEnd: Integer): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mIndex: Integer;
begin
  mTokens := ATree.Tokens;
  mIndex := TRoutineBody.TokenAt(mTokens, AStart);
  while (mIndex <= High(mTokens)) and (mTokens[mIndex].Offset < AEnd) do
  begin
    if mTokens[mIndex].Kind = TPascalTokenKind.Comment then
    begin
      Exit(True);
    end;
    Inc(mIndex);
  end;
  Result := False;
end;

class function TStatementText.Spans(ATree: TSyntaxTree; const ABranches: TArray<TSyntaxNode>): TArray<TStatementSpan>;
var
  mBranch_: TSyntaxNode;
  mItems: TArray<TSyntaxNode>;
  mIndex: Integer;
begin
  Result := nil;
  for mBranch_ in ABranches do
  begin
    mItems := Statements(mBranch_);
    for mIndex := 0 to High(mItems) do
    begin
      Result := Result + [SpanOf(ATree, mItems[mIndex], mIndex = High(mItems))];
    end;
  end;
end;

class function TStatementText.GuardedBranch(const AText: string; ATree: TSyntaxTree; ABranch: TSyntaxNode;
  const ALayout: TStatementLayout; ABeforeElse: Boolean): string;
var
  mItems: TArray<TSyntaxNode>;
begin
  mItems := Statements(ABranch);
  if ABeforeElse and (Length(mItems) = 1) and (mItems[0].Kind = TSyntaxKind.IfStatement) then
  begin
    Result := ALayout.LineBreak + ALayout.Indent + 'begin' + ALayout.LineBreak +
      List(AText, ATree, mItems, ALayout.Indent + ALayout.IndentUnit, ALayout.LineBreak) +
      ALayout.LineBreak + ALayout.Indent + 'end';
  end
  else
  begin
    Result := Branch(AText, ATree, mItems, ALayout, True);
  end;
end;

class function TStatementText.ReplacementEnd(ATree: TSyntaxTree; ANode: TSyntaxNode;
  const ASpans: TArray<TStatementSpan>; out ASuffix: string): TTextPosition;
var
  mTokens: TArray<TPascalToken>;
  mIndex, mStop: Integer;
  mSpan_: TStatementSpan;
begin
  Result := ANode.EndPos;
  ASuffix := '';
  mStop := ANode.EndOffset;
  for mSpan_ in ASpans do
  begin
    if mSpan_.EndOffset > mStop then
    begin
      mStop := mSpan_.EndOffset;
    end;
  end;
  mTokens := ATree.Tokens;
  mIndex := TRoutineBody.TokenAt(mTokens, ANode.EndOffset);
  // Das Semikolon gehört zur Ersetzung: Ein Kommentar hinter der letzten Anweisung (// …) stünde sonst vor ihm
  // und schlösse es aus.
  if (mIndex <= High(mTokens)) and mTokens[mIndex].IsSymbol(';') then
  begin
    ASuffix := ';';
    Result := mTokens[mIndex].EndPos;
    Inc(mIndex);
  end;
  while (mIndex <= High(mTokens)) and (mTokens[mIndex].Offset < mStop) do
  begin
    if mTokens[mIndex].IsSymbol(';') then
    begin
      ASuffix := ';';
    end;
    Result := mTokens[mIndex].EndPos;
    Inc(mIndex);
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
  mIndex: Integer;
begin
  for mIndex := 0 to AParent.ChildCount - 1 do
  begin
    if AParent[mIndex] = AChild then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Liegt A vor B (oder auf B)?</summary>
function NotAfter(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character <= B.Character));
end;

class function TStatementText.HeadAt(ATree: TSyntaxTree; const APosition: TTextPosition;
  AKind: TSyntaxKind): TSyntaxNode;
var
  mFound: TSyntaxNode;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  mFound := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      HeadEnd: TTextPosition;
    begin
      Result := True;
      if (ANode.Kind = AKind) and (ANode.ChildCount >= 2) then
      begin
        HeadEnd := ANode[1].StartPos;
        if NotAfter(ANode.StartPos, APosition) and NotAfter(APosition, HeadEnd) then
        begin
          mFound := ANode;
        end;
      end;
    end);
  Result := mFound;
end;

end.
