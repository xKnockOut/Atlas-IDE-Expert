unit Atlas.Common.Editing.CaseCompletion;

// Fehlende Zweige einer case-Anweisung über einem Aufzählungstyp (#449), ohne Namensauflösung. Gemeinsamer
// Erzeuger für die Vervollständigung (#449), die Code-Aktion „case vervollständigen“ (#50) und den
// Schnellbefehl /case (#296):
//   - BranchSlot: Cursor am Anfang eines Zweigs (direkt nach "of" oder nach dem ";" eines Zweigs).
//     Liefert die vorhandenen Marken, die Einrückung und ob das abschließende "end" fehlt.
//   - Missing: Werte, die noch keine Marke haben; Bereiche ("skCircle..skRect") und Listen
//     ("skLine, skTriangle:") zählen als vorhanden.
//   - BranchesText: je fehlendem Wert eine Zeile "<Wert>: ;" in Deklarationsreihenfolge, eine Ebene tiefer als
//     case; "$0" markiert die Cursorposition vor dem ";" des ersten neuen Zweigs.
// Ob "end" fehlt, entscheidet die Einrückung: Ein "end" links von der case-Zeile gehört zum umgebenden Block.
// Für die Code-Aktion (#50) findet CaseAt die case-Anweisung am Cursor, und Complete ergänzt genau die
// fehlenden Werte als leere Zweige vor dem else bzw. dem end (fehlt vor ihnen das ";", kommt es dazu).

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  TCaseBranchSlot = record
    /// <summary>Position des Schlüsselworts case.</summary>
    CasePos: TTextPosition;
    /// <summary>Vorhandene Marken ohne das Wort am Cursor: "skCircle", "TShapeKind.skLine", "skA..skC".</summary>
    Labels: TArray<string>;
    /// <summary>Einrückung der case-Zeile bzw. der Zweige.</summary>
    CaseIndent: string;
    BranchIndent: string;
    /// <summary>Was die neuen Zweige ersetzen: vom Ende des Tokens vor dem Cursor bis hinter das getippte Wort.</summary>
    EditRange: TTextRange;
    /// <summary>Das abschließende "end" ist vorhanden.</summary>
    HasEnd: Boolean;
    /// <summary>Hinter dem Cursor folgen noch Zweige; ein fehlendes "end" kommt dann an EndInsert.</summary>
    Following: Boolean;
    EndInsert: TTextPosition;
  end;

  TCaseCompletion = class
  public
    /// <summary>Cursor am Anfang eines Zweigs einer case-Anweisung; False sonst, auch im else-Teil.</summary>
    class function BranchSlot(const AText: string; const ATokens: TArray<TPascalToken>;
      const APosition: TTextPosition; out ASlot: TCaseBranchSlot): Boolean; static;
    /// <summary>Werte aus AValues ohne Marke in ALabels, in Deklarationsreihenfolge; False, wenn eine Marke kein
    /// Wert aus AValues ist.</summary>
    class function Missing(const AValues, ALabels: TArray<string>; out AMissing: TArray<string>): Boolean; static;
    /// <summary>Neue Zweige für EditRange; APrefix vor jedem Wert ("TShapeKind." bei {$SCOPEDENUMS ON}). Fehlt
    /// "end" und folgt nichts, hängt es "end;" an.</summary>
    class function BranchesText(const ASlot: TCaseBranchSlot; const AMissing: TArray<string>;
      const APrefix, ALineBreak: string): string; static;
    /// <summary>Text für EndInsert, wenn "end" fehlt und Zweige folgen; '' sonst.</summary>
    class function EndText(const ASlot: TCaseBranchSlot; const ALineBreak: string): string; static;
    /// <summary>Innerste case-Anweisung, in der APosition liegt; nil ohne.</summary>
    class function CaseAt(ATree: TSyntaxTree; const APosition: TTextPosition): TSyntaxNode; static;
    /// <summary>Stelle hinter dem "of" der case-Anweisung ACase; False ohne.</summary>
    class function OfPosition(ATree: TSyntaxTree; ACase: TSyntaxNode; out APosition: TTextPosition): Boolean;
      static;
    /// <summary>Zweige "<Wert>: ;" für die Werte aus AValues ohne Marke, in Deklarationsreihenfolge vor dem else
    /// (AHasElse) bzw. vor dem end. False, wenn nichts fehlt, eine Marke kein Wert ist oder end fehlt.</summary>
    class function Complete(const AText: string; ATree: TSyntaxTree; ACase: TSyntaxNode;
      const AValues: TArray<string>; const APrefix: string; out AEdits: TArray<TTextEdit>; out ACount: Integer;
      out AHasElse: Boolean): Boolean; static;
  end;

implementation

uses
  Atlas.Text.Lines;

function Compare(const A, B: TTextPosition): Integer;
begin
  Result := A.Line - B.Line;
  if Result = 0 then
    Result := A.Character - B.Character;
end;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function Prev(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
    Dec(Result);
end;

function Next(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
    Inc(Result);
end;

function IsKeywordIn(const AToken: TPascalToken; const AWords: array of string): Boolean;
var
  Word: string;
begin
  Result := False;
  if AToken.Kind <> TPascalTokenKind.Keyword then
    Exit;
  for Word in AWords do
    if AToken.IsKeyword(Word) then
      Exit(True);
end;

function CleanName(const AText: string): string;
begin
  if (AText <> '') and (AText[1] = '&') then
    Result := Copy(AText, 2, MaxInt)
  else
    Result := AText;
end;

/// <summary>Breite von AIndent, Tabulator als zwei Zeichen.</summary>
function Width(const AIndent: string): Integer;
var
  Character: Char;
begin
  Result := 0;
  for Character in AIndent do
    if Character = #9 then
      Inc(Result, 2)
    else
      Inc(Result);
end;

/// <summary>case-Anweisung, deren Zweig an AIndex (";" bzw. "of") endet; -1 sonst.</summary>
function EnclosingCase(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
var
  Depth, Parens: Integer;
begin
  Result := -1;
  if ATokens[AIndex].IsKeyword('of') then
  begin
    // "case <Ausdruck> of": rückwärts bis zum case, Klammern im Ausdruck übergehen.
    Parens := 0;
    AIndex := Prev(ATokens, AIndex);
    while AIndex >= 0 do
    begin
      if ATokens[AIndex].IsSymbol(')') or ATokens[AIndex].IsSymbol(']') then
        Inc(Parens)
      else if ATokens[AIndex].IsSymbol('(') or ATokens[AIndex].IsSymbol('[') then
        Dec(Parens)
      else if (Parens = 0) and ATokens[AIndex].IsKeyword('case') then
        Exit(AIndex)
      else if (Parens = 0) and ((ATokens[AIndex].Kind = TPascalTokenKind.Keyword) and
        not IsKeywordIn(ATokens[AIndex], ['not', 'and', 'or', 'xor', 'div', 'mod', 'shl', 'shr', 'nil', 'inherited'])
        or ATokens[AIndex].IsSymbol(';')) then
        Exit;
      AIndex := Prev(ATokens, AIndex);
    end;
    Exit;
  end;
  Depth := 0;
  Parens := 0;
  AIndex := Prev(ATokens, AIndex);
  while AIndex >= 0 do
  begin
    if ATokens[AIndex].IsSymbol(')') or ATokens[AIndex].IsSymbol(']') then
      Inc(Parens)
    else if ATokens[AIndex].IsSymbol('(') or ATokens[AIndex].IsSymbol('[') then
    begin
      if Parens = 0 then
        Exit;
      Dec(Parens);
    end
    else if ATokens[AIndex].IsKeyword('end') or ATokens[AIndex].IsKeyword('until') then
      Inc(Depth)
    else if IsKeywordIn(ATokens[AIndex], ['begin', 'try', 'asm', 'case', 'repeat']) then
    begin
      if Depth = 0 then
      begin
        if ATokens[AIndex].IsKeyword('case') then
          Result := AIndex;
        Exit;
      end;
      Dec(Depth);
    end
    else if (Depth = 0) and IsKeywordIn(ATokens[AIndex], ['var', 'const', 'type', 'procedure', 'function',
      'constructor', 'destructor', 'implementation', 'uses', 'record', 'class', 'object', 'interface']) then
      Exit;
    AIndex := Prev(ATokens, AIndex);
  end;
end;

{ TCaseCompletion }

class function TCaseCompletion.BranchSlot(const AText: string; const ATokens: TArray<TPascalToken>;
  const APosition: TTextPosition; out ASlot: TCaseBranchSlot): Boolean;
var
  Index, Prefix, Before, CaseIndex, OfIndex, Depth, Parens, LastToken, FirstLabel: Integer;
  AtStart, InElse: Boolean;
  Element: string;
  Parts: TArray<string>;
begin
  ASlot := Default(TCaseBranchSlot);
  Result := False;
  // Token vor dem Cursor (mit Kommentaren) und das getippte Wort.
  Before := -1;
  Prefix := -1;
  for Index := 0 to High(ATokens) do
  begin
    if Compare(ATokens[Index].StartPos, APosition) >= 0 then
      Break;
    Before := Index;
  end;
  if (Before >= 0) and (ATokens[Before].Kind = TPascalTokenKind.Identifier) and
    (Compare(APosition, ATokens[Before].EndPos) <= 0) then
  begin
    Prefix := Before;
    Before := Before - 1;
  end;
  if Before < 0 then
    Exit;
  Index := Before;
  if IsTrivia(ATokens[Index]) then
    Index := Prev(ATokens, Index);
  if (Index < 0) or not (ATokens[Index].IsKeyword('of') or ATokens[Index].IsSymbol(';')) then
    Exit;
  CaseIndex := EnclosingCase(ATokens, Index);
  if CaseIndex < 0 then
    Exit;
  // "of" der case-Anweisung.
  OfIndex := Next(ATokens, CaseIndex);
  Parens := 0;
  while OfIndex <= Index do
  begin
    if ATokens[OfIndex].IsSymbol('(') or ATokens[OfIndex].IsSymbol('[') then
      Inc(Parens)
    else if ATokens[OfIndex].IsSymbol(')') or ATokens[OfIndex].IsSymbol(']') then
      Dec(Parens)
    else if (Parens = 0) and ATokens[OfIndex].IsKeyword('of') then
      Break;
    OfIndex := Next(ATokens, OfIndex);
  end;
  if (OfIndex > Index) or not ATokens[OfIndex].IsKeyword('of') then
    Exit;
  ASlot.CasePos := ATokens[CaseIndex].StartPos;
  ASlot.CaseIndent := TTextLines.IndentOf(AText, ATokens[CaseIndex].StartPos.Line);
  // Vorwärts bis zum "end" der case-Anweisung: Marken sammeln, else-Teil erkennen.
  Depth := 0;
  Parens := 0;
  AtStart := True;
  InElse := False;
  Element := '';
  Parts := nil;
  FirstLabel := -1;
  LastToken := OfIndex;
  Index := Next(ATokens, OfIndex);
  while Index <= High(ATokens) do
  begin
    if Depth = 0 then
    begin
      if ATokens[Index].IsKeyword('end') then
      begin
        // Links von der case-Zeile: "end" des umgebenden Blocks, das eigene fehlt.
        ASlot.HasEnd := Width(TTextLines.IndentOf(AText, ATokens[Index].StartPos.Line)) >= Width(ASlot.CaseIndent);
        Break;
      end;
      if IsKeywordIn(ATokens[Index], ['until', 'except', 'finally', 'procedure', 'function', 'constructor',
        'destructor', 'implementation', 'initialization', 'finalization', 'var', 'const', 'type']) then
        Break;
      if ATokens[Index].IsKeyword('else') and (Prev(ATokens, Index) >= 0) and
        (ATokens[Prev(ATokens, Index)].IsSymbol(';') or (Prev(ATokens, Index) = OfIndex)) then
      begin
        InElse := True;
        // Cursor im else-Teil: dort stehen Anweisungen, keine Zweige.
        if Compare(ATokens[Index].StartPos, APosition) < 0 then
          Exit;
      end;
    end;
    if (Index <> Prefix) and (Compare(ATokens[Index].StartPos, APosition) >= 0) then
      ASlot.Following := True;
    if IsKeywordIn(ATokens[Index], ['begin', 'try', 'asm', 'case']) then
      Inc(Depth)
    else if ATokens[Index].IsKeyword('end') then
      Dec(Depth)
    else if ATokens[Index].IsKeyword('repeat') then
      Inc(Depth)
    else if ATokens[Index].IsKeyword('until') then
      Dec(Depth)
    else if ATokens[Index].IsSymbol('(') or ATokens[Index].IsSymbol('[') then
      Inc(Parens)
    else if ATokens[Index].IsSymbol(')') or ATokens[Index].IsSymbol(']') then
      Dec(Parens);
    if (Depth = 0) and (Parens = 0) and not InElse then
    begin
      if ATokens[Index].IsSymbol(';') then
      begin
        AtStart := True;
        Element := '';
        Parts := nil;
      end
      else if AtStart then
      begin
        if ATokens[Index].IsSymbol(':') then
        begin
          ASlot.Labels := ASlot.Labels + Parts + [Element];
          AtStart := False;
        end
        else if ATokens[Index].IsSymbol(',') then
        begin
          Parts := Parts + [Element];
          Element := '';
        end
        else if Index <> Prefix then
        begin
          if FirstLabel < 0 then
            FirstLabel := Index;
          Element := Element + CleanName(ATokens[Index].Text);
        end;
      end;
    end;
    LastToken := Index;
    Index := Next(ATokens, Index);
  end;
  ASlot.EndInsert := ATokens[LastToken].EndPos;
  // Einrückung wie die vorhandenen Zweige, sonst eine Ebene tiefer als case.
  if (FirstLabel >= 0) and (Prev(ATokens, FirstLabel) >= 0) and
    (ATokens[Prev(ATokens, FirstLabel)].EndPos.Line < ATokens[FirstLabel].StartPos.Line) then
    ASlot.BranchIndent := TTextLines.IndentOf(AText, ATokens[FirstLabel].StartPos.Line)
  else
    ASlot.BranchIndent := ASlot.CaseIndent + '  ';
  if Prefix >= 0 then
    ASlot.EditRange := TTextRange.Create(ATokens[Before].EndPos, ATokens[Prefix].EndPos)
  else
    ASlot.EditRange := TTextRange.Create(ATokens[Before].EndPos, APosition);
  Result := True;
end;

/// <summary>Letzter Teil eines qualifizierten Namens: TShapeKind.skLine → skLine.</summary>
function LastPart(const AName: string): string;
begin
  Result := AName.Substring(AName.LastIndexOf('.') + 1);
end;

class function TCaseCompletion.Missing(const AValues, ALabels: TArray<string>;
  out AMissing: TArray<string>): Boolean;

  function IndexOfValue(const AName: string): Integer;
  var
    Index: Integer;
  begin
    for Index := 0 to High(AValues) do
      if SameText(AValues[Index], LastPart(AName)) then
        Exit(Index);
    Result := -1;
  end;

var
  Present: TArray<Boolean>;
  Bounds: TArray<string>;
  Element: string;
  Low_, High_, Index: Integer;
begin
  AMissing := nil;
  SetLength(Present, Length(AValues));
  for Index := 0 to High(Present) do
    Present[Index] := False;
  for Element in ALabels do
  begin
    Bounds := Element.Split(['..']);
    if (Length(Bounds) < 1) or (Length(Bounds) > 2) then
      Exit(False);
    Low_ := IndexOfValue(Bounds[0]);
    High_ := Low_;
    if Length(Bounds) = 2 then
      High_ := IndexOfValue(Bounds[1]);
    if (Low_ < 0) or (High_ < 0) then
      Exit(False);
    for Index := Low_ to High_ do
      Present[Index] := True;
  end;
  for Index := 0 to High(AValues) do
    if not Present[Index] then
      AMissing := AMissing + [AValues[Index]];
  Result := True;
end;

class function TCaseCompletion.BranchesText(const ASlot: TCaseBranchSlot; const AMissing: TArray<string>;
  const APrefix, ALineBreak: string): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to High(AMissing) do
  begin
    Result := Result + ALineBreak + ASlot.BranchIndent + APrefix + AMissing[Index] + ': ';
    if Index = 0 then
      Result := Result + '$0';
    Result := Result + ';';
  end;
  if not ASlot.HasEnd and not ASlot.Following then
    Result := Result + ALineBreak + ASlot.CaseIndent + 'end;';
end;

class function TCaseCompletion.EndText(const ASlot: TCaseBranchSlot; const ALineBreak: string): string;
begin
  Result := '';
  if not ASlot.HasEnd and ASlot.Following then
    Result := ALineBreak + ASlot.CaseIndent + 'end;';
end;

function Contains(ANode: TSyntaxNode; const APosition: TTextPosition): Boolean;
begin
  Result := (Compare(ANode.StartPos, APosition) <= 0) and (Compare(APosition, ANode.EndPos) <= 0);
end;

class function TCaseCompletion.CaseAt(ATree: TSyntaxTree; const APosition: TTextPosition): TSyntaxNode;
var
  Node: TSyntaxNode;
  Index: Integer;
  Descended: Boolean;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  Node := ATree.Root;
  repeat
    Descended := False;
    for Index := 0 to Node.ChildCount - 1 do
      if Contains(Node[Index], APosition) then
      begin
        Node := Node[Index];
        if Node.Kind = TSyntaxKind.CaseStatement then
          Result := Node;
        Descended := True;
        Break;
      end;
  until not Descended;
end;

/// <summary>Index des ersten Tokens ab AOffset.</summary>
function TokenAt(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
begin
  Result := 0;
  while (Result <= High(ATokens)) and (ATokens[Result].Offset < AOffset) do
    Inc(Result);
end;

class function TCaseCompletion.OfPosition(ATree: TSyntaxTree; ACase: TSyntaxNode;
  out APosition: TTextPosition): Boolean;
var
  Tokens: TArray<TPascalToken>;
  Index, Parens: Integer;
begin
  Result := False;
  Tokens := ATree.Tokens;
  Index := TokenAt(Tokens, ACase.StartOffset);
  Parens := 0;
  while (Index <= High(Tokens)) and (Tokens[Index].Offset < ACase.EndOffset) do
  begin
    if Tokens[Index].IsSymbol('(') or Tokens[Index].IsSymbol('[') then
      Inc(Parens)
    else if Tokens[Index].IsSymbol(')') or Tokens[Index].IsSymbol(']') then
      Dec(Parens)
    else if (Parens = 0) and Tokens[Index].IsKeyword('of') then
    begin
      APosition := Tokens[Index].EndPos;
      Exit(True);
    end;
    Inc(Index);
  end;
end;

class function TCaseCompletion.Complete(const AText: string; ATree: TSyntaxTree; ACase: TSyntaxNode;
  const AValues: TArray<string>; const APrefix: string; out AEdits: TArray<TTextEdit>; out ACount: Integer;
  out AHasElse: Boolean): Boolean;
var
  Tokens: TArray<TPascalToken>;
  OfPos: TTextPosition;
  Slot: TCaseBranchSlot;
  Absent: TArray<string>;
  ElseNode: TSyntaxNode;
  Anchor, Before, Index: Integer;
  LineBreak, Branches, Semicolon: string;
begin
  AEdits := nil;
  ACount := 0;
  AHasElse := False;
  Result := False;
  if (ACase = nil) or not OfPosition(ATree, ACase, OfPos) then
    Exit;
  Tokens := ATree.Tokens;
  if not BranchSlot(AText, Tokens, OfPos, Slot) or not Slot.HasEnd or not Missing(AValues, Slot.Labels, Absent) or
    (Absent = nil) then
    Exit;
  // Anker: "else" der case-Anweisung, sonst ihr "end".
  ElseNode := ACase.FindChild(TSyntaxKind.CaseElse);
  AHasElse := ElseNode <> nil;
  if AHasElse then
    Anchor := TokenAt(Tokens, ElseNode.StartOffset)
  else
  begin
    Anchor := TokenAt(Tokens, ACase.EndOffset) - 1;
    while (Anchor >= 0) and IsTrivia(Tokens[Anchor]) do
      Dec(Anchor);
  end;
  if (Anchor < 0) or (Anchor > High(Tokens)) or not (Tokens[Anchor].IsKeyword('else') or
    Tokens[Anchor].IsKeyword('end')) then
    Exit;
  Before := Prev(Tokens, Anchor);
  if Before < 0 then
    Exit;
  if Pos(#13#10, AText) > 0 then
    LineBreak := #13#10
  else
    LineBreak := #10;
  Semicolon := '';
  if not (Tokens[Before].IsSymbol(';') or Tokens[Before].IsKeyword('of')) then
    Semicolon := ';';
  Branches := '';
  for Index := 0 to High(Absent) do
    Branches := Branches + LineBreak + Slot.BranchIndent + APrefix + Absent[Index] + ': ;';
  // Vom letzten Token davor (auch einem Kommentar) bis vor den Anker: neue Zeilen, dann der Anker in der
  // Einrückung von case. Das fehlende ";" gehört hinter den Zweig, nicht hinter seinen Kommentar.
  if Before = Anchor - 1 then
    AEdits := [TTextEdit.Create(TTextRange.Create(Tokens[Before].EndPos, Tokens[Anchor].StartPos),
      Semicolon + Branches + LineBreak + Slot.CaseIndent)]
  else
  begin
    AEdits := [TTextEdit.Create(TTextRange.Create(Tokens[Anchor - 1].EndPos, Tokens[Anchor].StartPos),
      Branches + LineBreak + Slot.CaseIndent)];
    if Semicolon <> '' then
      AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(Tokens[Before].EndPos, Tokens[Before].EndPos),
        Semicolon)];
  end;
  ACount := Length(Absent);
  Result := True;
end;

end.
