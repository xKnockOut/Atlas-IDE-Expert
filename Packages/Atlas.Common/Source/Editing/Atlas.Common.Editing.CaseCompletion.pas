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

  /// <summary>Ergebnis von TCaseCompletion.Complete.</summary>
  TCaseCompletionEdits = record
    Edits: TArray<TTextEdit>;
    /// <summary>Anzahl der neuen Zweige.</summary>
    Count: Integer;
    /// <summary>Die case-Anweisung hat einen else-Teil; die Zweige stehen davor.</summary>
    HasElse: Boolean;
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
    /// <summary>Zweige "&lt;Wert&gt;: ;" für die Werte aus AValues ohne Marke, in Deklarationsreihenfolge vor dem else
    /// (AHasElse) bzw. vor dem end. False, wenn nichts fehlt, eine Marke kein Wert ist oder end fehlt.</summary>
    class function Complete(const AText: string; ATree: TSyntaxTree; ACase: TSyntaxNode;
      const AValues: TArray<string>; const APrefix: string; out AResult: TCaseCompletionEdits): Boolean; static;
  end;

implementation

uses
  Atlas.Text.Lines;

function Compare(const A, B: TTextPosition): Integer;
begin
  Result := A.Line - B.Line;
  if Result = 0 then
  begin
    Result := A.Character - B.Character;
  end;
end;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function Prev(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
  begin
    Dec(Result);
  end;
end;

function Next(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
  begin
    Inc(Result);
  end;
end;

function IsKeywordIn(const AToken: TPascalToken; const AWords: array of string): Boolean;
var
  Word: string;
begin
  Result := False;
  if AToken.Kind <> TPascalTokenKind.Keyword then
  begin
    Exit;
  end;
  for Word in AWords do
  begin
    if AToken.IsKeyword(Word) then
    begin
      Exit(True);
    end;
  end;
end;

function CleanName(const AText: string): string;
begin
  if (AText <> '') and (AText[1] = '&') then
  begin
    Result := Copy(AText, 2, MaxInt);
  end
  else
  begin
    Result := AText;
  end;
end;

/// <summary>Breite von AIndent, Tabulator als zwei Zeichen.</summary>
function Width(const AIndent: string): Integer;
var
  Character: Char;
begin
  Result := 0;
  for Character in AIndent do
  begin
    if Character = #9 then
    begin
      Inc(Result, 2);
    end
    else
    begin
      Inc(Result);
    end;
  end;
end;

function IsOpenBracket(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol('(') or AToken.IsSymbol('[');
end;

function IsCloseBracket(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol(')') or AToken.IsSymbol(']');
end;

/// <summary>Beendet AToken den Ausdruck zwischen case und of: ein Schlüsselwort außer Operatoren und nil bzw.
/// inherited oder ein ";".</summary>
function EndsCaseExpression(const AToken: TPascalToken): Boolean;
begin
  Result := (AToken.Kind = TPascalTokenKind.Keyword) and not IsKeywordIn(AToken, ['not', 'and', 'or', 'xor', 'div',
    'mod', 'shl', 'shr', 'nil', 'inherited']) or AToken.IsSymbol(';');
end;

/// <summary>"case &lt;Ausdruck&gt; of" mit dem "of" an AIndex: rückwärts bis zum case, Klammern im Ausdruck
/// übergehen; -1 ohne.</summary>
function CaseBeforeOf(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
var
  mParens: Integer;
begin
  Result := -1;
  mParens := 0;
  AIndex := Prev(ATokens, AIndex);
  while AIndex >= 0 do
  begin
    if IsCloseBracket(ATokens[AIndex]) then
    begin
      Inc(mParens);
    end
    else if IsOpenBracket(ATokens[AIndex]) then
    begin
      Dec(mParens);
    end
    else if mParens = 0 then
    begin
      if ATokens[AIndex].IsKeyword('case') then
      begin
        Exit(AIndex);
      end;
      if EndsCaseExpression(ATokens[AIndex]) then
      begin
        Exit;
      end;
    end;
    AIndex := Prev(ATokens, AIndex);
  end;
end;

type
  {$SCOPEDENUMS ON}
  /// <summary>Schritt der Rückwärtssuche nach dem case eines Zweigs.</summary>
  TCaseSearchStep = (Continue_, Stop, Found);
  {$SCOPEDENUMS OFF}

/// <summary>Öffnender Block (begin, try, asm, case, repeat) bei der Rückwärtssuche: schließt einen übergangenen
/// Block oder ist auf Ebene 0 das gesuchte case bzw. das Ende der Suche.</summary>
function OpenerStep(const AToken: TPascalToken; var ADepth: Integer): TCaseSearchStep;
begin
  Result := TCaseSearchStep.Stop;
  if ADepth > 0 then
  begin
    Dec(ADepth);
    Result := TCaseSearchStep.Continue_;
  end
  else if AToken.IsKeyword('case') then
  begin
    Result := TCaseSearchStep.Found;
  end;
end;

/// <summary>Ein Token der Rückwärtssuche nach dem case eines Zweigs; zählt Blöcke und Klammern mit.</summary>
function BranchSearchStep(const AToken: TPascalToken; var ADepth, AParens: Integer): TCaseSearchStep;
begin
  Result := TCaseSearchStep.Continue_;
  if IsCloseBracket(AToken) then
  begin
    Inc(AParens);
  end
  else if IsOpenBracket(AToken) then
  begin
    Result := OpenerStep(AToken, AParens);
  end
  else if IsKeywordIn(AToken, ['end', 'until']) then
  begin
    Inc(ADepth);
  end
  else if IsKeywordIn(AToken, ['begin', 'try', 'asm', 'case', 'repeat']) then
  begin
    Result := OpenerStep(AToken, ADepth);
  end
  else if (ADepth = 0) and IsKeywordIn(AToken, ['var', 'const', 'type', 'procedure', 'function', 'constructor',
    'destructor', 'implementation', 'uses', 'record', 'class', 'object', 'interface']) then
  begin
    Result := TCaseSearchStep.Stop;
  end;
end;

/// <summary>case-Anweisung, deren Zweig an AIndex (";" bzw. "of") endet; -1 sonst.</summary>
function EnclosingCase(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
var
  mDepth, mParens: Integer;
begin
  if ATokens[AIndex].IsKeyword('of') then
  begin
    Exit(CaseBeforeOf(ATokens, AIndex));
  end;
  Result := -1;
  mDepth := 0;
  mParens := 0;
  AIndex := Prev(ATokens, AIndex);
  while (AIndex >= 0) and (Result < 0) do
  begin
    case BranchSearchStep(ATokens[AIndex], mDepth, mParens) of
      TCaseSearchStep.Found:
        Result := AIndex;
      TCaseSearchStep.Stop:
        Break;
    else
      AIndex := Prev(ATokens, AIndex);
    end;
  end;
end;

/// <summary>Token vor dem Cursor (mit Kommentaren) und das getippte Wort (APrefix, -1 ohne); False, wenn vor dem
/// Cursor nichts steht.</summary>
function CursorTokens(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition;
  out ABefore, APrefix: Integer): Boolean;
var
  mIndex: Integer;
begin
  ABefore := -1;
  APrefix := -1;
  for mIndex := 0 to High(ATokens) do
  begin
    if Compare(ATokens[mIndex].StartPos, APosition) >= 0 then
    begin
      Break;
    end;
    ABefore := mIndex;
  end;
  if (ABefore >= 0) and (ATokens[ABefore].Kind = TPascalTokenKind.Identifier) and
    (Compare(APosition, ATokens[ABefore].EndPos) <= 0) then
  begin
    APrefix := ABefore;
    Dec(ABefore);
  end;
  Result := ABefore >= 0;
end;

/// <summary>Endet vor dem Cursor ein Zweig ("of" oder ";", Kommentar dazwischen erlaubt)? AIndex: dieses Token.</summary>
function BranchStart(const ATokens: TArray<TPascalToken>; ABefore: Integer; out AIndex: Integer): Boolean;
begin
  AIndex := ABefore;
  if IsTrivia(ATokens[AIndex]) then
  begin
    AIndex := Prev(ATokens, AIndex);
  end;
  Result := (AIndex >= 0) and (ATokens[AIndex].IsKeyword('of') or ATokens[AIndex].IsSymbol(';'));
end;

/// <summary>"of" der case-Anweisung an ACaseIndex, höchstens bis ALimit; False ohne.</summary>
function FindOf(const ATokens: TArray<TPascalToken>; ACaseIndex, ALimit: Integer; out AOfIndex: Integer): Boolean;
var
  mParens: Integer;
begin
  AOfIndex := Next(ATokens, ACaseIndex);
  mParens := 0;
  while AOfIndex <= ALimit do
  begin
    if IsOpenBracket(ATokens[AOfIndex]) then
    begin
      Inc(mParens);
    end
    else if IsCloseBracket(ATokens[AOfIndex]) then
    begin
      Dec(mParens);
    end
    else if (mParens = 0) and ATokens[AOfIndex].IsKeyword('of') then
    begin
      Break;
    end;
    AOfIndex := Next(ATokens, AOfIndex);
  end;
  Result := (AOfIndex <= ALimit) and ATokens[AOfIndex].IsKeyword('of');
end;

/// <summary>Steht vor dem Token AIndex ein ":="?</summary>
function AfterAssignment(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  mPrev: Integer;
begin
  mPrev := Prev(ATokens, AIndex);
  Result := (mPrev >= 0) and ATokens[mPrev].IsSymbol(':=');
end;

/// <summary>Beendet das Token AIndex die Zweige einer case-Anweisung ohne "end"? Anonyme Methoden (Post(procedure
/// begin … end), X := function …) beenden den case nicht (#1109): In Klammern oder nach := steht keine
/// Deklaration; Klammern prüft der Aufrufer.</summary>
function EndsBranches(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
begin
  Result := IsKeywordIn(ATokens[AIndex], ['until', 'except', 'finally', 'procedure', 'function', 'constructor',
    'destructor', 'implementation', 'initialization', 'finalization', 'var', 'const', 'type']) and
    not (IsKeywordIn(ATokens[AIndex], ['procedure', 'function']) and AfterAssignment(ATokens, AIndex));
end;

/// <summary>Ist das Token AIndex das else einer case-Anweisung (nach ";" oder direkt nach ihrem "of")?</summary>
function IsCaseElse(const ATokens: TArray<TPascalToken>; AIndex, AOfIndex: Integer): Boolean;
var
  mPrev: Integer;
begin
  mPrev := Prev(ATokens, AIndex);
  Result := ATokens[AIndex].IsKeyword('else') and (mPrev >= 0) and
    (ATokens[mPrev].IsSymbol(';') or (mPrev = AOfIndex));
end;

/// <summary>Steht das Token AIndex am Zeilenanfang (das Token davor endet in einer früheren Zeile)?</summary>
function StartsLine(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  mPrev: Integer;
begin
  mPrev := Prev(ATokens, AIndex);
  Result := (mPrev >= 0) and (ATokens[mPrev].EndPos.Line < ATokens[AIndex].StartPos.Line);
end;

type
  /// <summary>Vorwärtslauf vom "of" bis zum "end" einer case-Anweisung: sammelt die Marken und erkennt den
  /// else-Teil.</summary>
  TLabelScan = record
    Tokens: TArray<TPascalToken>;
    Text: string;
    Position: TTextPosition;
    /// <summary>Token vor dem Cursor und getipptes Wort (-1 ohne).</summary>
    Before: Integer;
    Prefix: Integer;
    OfIndex: Integer;
    Slot: TCaseBranchSlot;
    Depth: Integer;
    Parens: Integer;
    /// <summary>Am Anfang eines Zweigs, vor dessen ":".</summary>
    AtStart: Boolean;
    InElse: Boolean;
    Element: string;
    Parts: TArray<string>;
    FirstLabel: Integer;
    /// <summary>Prüft das Token AIndex auf der Ebene der Zweige; AStop: Die Zweige enden hier. False, wenn der
    /// Cursor im else-Teil steht.</summary>
    function CheckTopLevel(AIndex: Integer; out AStop: Boolean): Boolean;
    procedure TrackNesting(AIndex: Integer);
    procedure AddLabelToken(AIndex: Integer);
    procedure CollectLabel(AIndex: Integer);
    /// <summary>Läuft die Zweige ab; False, wenn der Cursor im else-Teil steht.</summary>
    function Run: Boolean;
    /// <summary>Einrückung wie die vorhandenen Zweige, sonst eine Ebene tiefer als case.</summary>
    function BranchIndent: string;
    function EditRange: TTextRange;
  end;

function TLabelScan.CheckTopLevel(AIndex: Integer; out AStop: Boolean): Boolean;
begin
  Result := True;
  AStop := False;
  if Depth <> 0 then
  begin
    Exit;
  end;
  if Tokens[AIndex].IsKeyword('end') then
  begin
    // Links von der case-Zeile: "end" des umgebenden Blocks, das eigene fehlt.
    Slot.HasEnd := Width(TTextLines.IndentOf(Text, Tokens[AIndex].StartPos.Line)) >= Width(Slot.CaseIndent);
    AStop := True;
  end
  else if (Parens = 0) and EndsBranches(Tokens, AIndex) then
  begin
    AStop := True;
  end
  else if IsCaseElse(Tokens, AIndex, OfIndex) then
  begin
    InElse := True;
    // Cursor im else-Teil: dort stehen Anweisungen, keine Zweige.
    Result := Compare(Tokens[AIndex].StartPos, Position) >= 0;
  end;
end;

procedure TLabelScan.TrackNesting(AIndex: Integer);
begin
  if IsKeywordIn(Tokens[AIndex], ['begin', 'try', 'asm', 'case', 'repeat']) then
  begin
    Inc(Depth);
  end
  else if IsKeywordIn(Tokens[AIndex], ['end', 'until']) then
  begin
    Dec(Depth);
  end
  else if IsOpenBracket(Tokens[AIndex]) then
  begin
    Inc(Parens);
  end
  else if IsCloseBracket(Tokens[AIndex]) then
  begin
    Dec(Parens);
  end;
end;

/// <summary>Token einer Marke vor ihrem ":": Teile einer Liste trennt ",", das getippte Wort zählt nicht.</summary>
procedure TLabelScan.AddLabelToken(AIndex: Integer);
begin
  if Tokens[AIndex].IsSymbol(':') then
  begin
    Slot.Labels := Slot.Labels + Parts + [Element];
    AtStart := False;
  end
  else if Tokens[AIndex].IsSymbol(',') then
  begin
    Parts := Parts + [Element];
    Element := '';
  end
  else if AIndex <> Prefix then
  begin
    if FirstLabel < 0 then
    begin
      FirstLabel := AIndex;
    end;
    Element := Element + CleanName(Tokens[AIndex].Text);
  end;
end;

procedure TLabelScan.CollectLabel(AIndex: Integer);
begin
  if (Depth <> 0) or (Parens <> 0) or InElse then
  begin
    Exit;
  end;
  if Tokens[AIndex].IsSymbol(';') then
  begin
    AtStart := True;
    Element := '';
    Parts := nil;
  end
  else if AtStart then
  begin
    AddLabelToken(AIndex);
  end;
end;

function TLabelScan.Run: Boolean;
var
  mIndex, mLastToken: Integer;
  mStop: Boolean;
begin
  Result := True;
  Depth := 0;
  Parens := 0;
  AtStart := True;
  InElse := False;
  Element := '';
  Parts := nil;
  FirstLabel := -1;
  mLastToken := OfIndex;
  mIndex := Next(Tokens, OfIndex);
  while mIndex <= High(Tokens) do
  begin
    if not CheckTopLevel(mIndex, mStop) then
    begin
      Exit(False);
    end;
    if mStop then
    begin
      Break;
    end;
    if (mIndex <> Prefix) and (Compare(Tokens[mIndex].StartPos, Position) >= 0) then
    begin
      Slot.Following := True;
    end;
    TrackNesting(mIndex);
    CollectLabel(mIndex);
    mLastToken := mIndex;
    mIndex := Next(Tokens, mIndex);
  end;
  Slot.EndInsert := Tokens[mLastToken].EndPos;
  Slot.BranchIndent := BranchIndent;
  Slot.EditRange := EditRange;
end;

function TLabelScan.BranchIndent: string;
begin
  if (FirstLabel >= 0) and StartsLine(Tokens, FirstLabel) then
  begin
    Result := TTextLines.IndentOf(Text, Tokens[FirstLabel].StartPos.Line);
  end
  else
  begin
    Result := Slot.CaseIndent + '  ';
  end;
end;

function TLabelScan.EditRange: TTextRange;
begin
  if Prefix >= 0 then
  begin
    Result := TTextRange.Create(Tokens[Before].EndPos, Tokens[Prefix].EndPos);
  end
  else
  begin
    Result := TTextRange.Create(Tokens[Before].EndPos, Position);
  end;
end;

{ TCaseCompletion }

class function TCaseCompletion.BranchSlot(const AText: string; const ATokens: TArray<TPascalToken>;
  const APosition: TTextPosition; out ASlot: TCaseBranchSlot): Boolean;
var
  mScan: TLabelScan;
  mIndex, mCaseIndex: Integer;
begin
  ASlot := Default(TCaseBranchSlot);
  mScan := Default(TLabelScan);
  mCaseIndex := -1;
  Result := CursorTokens(ATokens, APosition, mScan.Before, mScan.Prefix) and BranchStart(ATokens, mScan.Before,
    mIndex);
  if Result then
  begin
    mCaseIndex := EnclosingCase(ATokens, mIndex);
    Result := (mCaseIndex >= 0) and FindOf(ATokens, mCaseIndex, mIndex, mScan.OfIndex);
  end;
  if not Result then
  begin
    Exit;
  end;
  mScan.Tokens := ATokens;
  mScan.Text := AText;
  mScan.Position := APosition;
  mScan.Slot.CasePos := ATokens[mCaseIndex].StartPos;
  mScan.Slot.CaseIndent := TTextLines.IndentOf(AText, ATokens[mCaseIndex].StartPos.Line);
  Result := mScan.Run;
  if Result then
  begin
    ASlot := mScan.Slot;
  end;
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
    begin
      if SameText(AValues[Index], LastPart(AName)) then
      begin
        Exit(Index);
      end;
    end;
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
  begin
    Present[Index] := False;
  end;
  for Element in ALabels do
  begin
    Bounds := Element.Split(['..']);
    if (Length(Bounds) < 1) or (Length(Bounds) > 2) then
    begin
      Exit(False);
    end;
    Low_ := IndexOfValue(Bounds[0]);
    High_ := Low_;
    if Length(Bounds) = 2 then
    begin
      High_ := IndexOfValue(Bounds[1]);
    end;
    if (Low_ < 0) or (High_ < 0) then
    begin
      Exit(False);
    end;
    for Index := Low_ to High_ do
    begin
      Present[Index] := True;
    end;
  end;
  for Index := 0 to High(AValues) do
  begin
    if not Present[Index] then
    begin
      AMissing := AMissing + [AValues[Index]];
    end;
  end;
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
    begin
      Result := Result + '$0';
    end;
    Result := Result + ';';
  end;
  if not ASlot.HasEnd and not ASlot.Following then
  begin
    Result := Result + ALineBreak + ASlot.CaseIndent + 'end;';
  end;
end;

class function TCaseCompletion.EndText(const ASlot: TCaseBranchSlot; const ALineBreak: string): string;
begin
  Result := '';
  if not ASlot.HasEnd and ASlot.Following then
  begin
    Result := ALineBreak + ASlot.CaseIndent + 'end;';
  end;
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
  begin
    Exit;
  end;
  Node := ATree.Root;
  repeat
    Descended := False;
    for Index := 0 to Node.ChildCount - 1 do
    begin
      if Contains(Node[Index], APosition) then
      begin
        Node := Node[Index];
        if Node.Kind = TSyntaxKind.CaseStatement then
        begin
          Result := Node;
        end;
        Descended := True;
        Break;
      end;
    end;
  until not Descended;
end;

/// <summary>Index des ersten Tokens ab AOffset.</summary>
function TokenAt(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
begin
  Result := 0;
  while (Result <= High(ATokens)) and (ATokens[Result].Offset < AOffset) do
  begin
    Inc(Result);
  end;
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
    begin
      Inc(Parens);
    end
    else if Tokens[Index].IsSymbol(')') or Tokens[Index].IsSymbol(']') then
    begin
      Dec(Parens);
    end
    else if (Parens = 0) and Tokens[Index].IsKeyword('of') then
    begin
      APosition := Tokens[Index].EndPos;
      Exit(True);
    end;
    Inc(Index);
  end;
end;

/// <summary>Anker der neuen Zweige: "else" der case-Anweisung ACase, sonst ihr "end"; -1 ohne.</summary>
function CaseAnchor(const ATokens: TArray<TPascalToken>; ACase: TSyntaxNode; out AHasElse: Boolean): Integer;
var
  mElse: TSyntaxNode;
begin
  mElse := ACase.FindChild(TSyntaxKind.CaseElse);
  AHasElse := mElse <> nil;
  if AHasElse then
  begin
    Result := TokenAt(ATokens, mElse.StartOffset);
  end
  else
  begin
    Result := TokenAt(ATokens, ACase.EndOffset) - 1;
    while (Result >= 0) and IsTrivia(ATokens[Result]) do
    begin
      Dec(Result);
    end;
  end;
  if (Result < 0) or (Result > High(ATokens)) or not IsKeywordIn(ATokens[Result], ['else', 'end']) then
  begin
    Result := -1;
  end;
end;

function LineBreakOf(const AText: string): string;
begin
  Result := #10;
  if Pos(#13#10, AText) > 0 then
  begin
    Result := #13#10;
  end;
end;

/// <summary>Einfügungen vor dem Anker AAnchor: vom letzten Token davor (auch einem Kommentar) bis vor den Anker
/// neue Zeilen ABranches, dann ATail (Zeilenumbruch und Einrückung von case). Das fehlende ";" gehört hinter den
/// Zweig ABefore, nicht hinter seinen Kommentar.</summary>
function AnchorEdits(const ATokens: TArray<TPascalToken>; AAnchor, ABefore: Integer;
  const ABranches, ATail: string): TArray<TTextEdit>;
var
  mSemicolon: string;
begin
  mSemicolon := '';
  if not (ATokens[ABefore].IsSymbol(';') or ATokens[ABefore].IsKeyword('of')) then
  begin
    mSemicolon := ';';
  end;
  if ABefore = AAnchor - 1 then
  begin
    Result := [TTextEdit.Create(TTextRange.Create(ATokens[ABefore].EndPos, ATokens[AAnchor].StartPos),
      mSemicolon + ABranches + ATail)];
  end
  else
  begin
    Result := [TTextEdit.Create(TTextRange.Create(ATokens[AAnchor - 1].EndPos, ATokens[AAnchor].StartPos),
      ABranches + ATail)];
    if mSemicolon <> '' then
    begin
      Result := Result + [TTextEdit.Create(TTextRange.Create(ATokens[ABefore].EndPos, ATokens[ABefore].EndPos),
        mSemicolon)];
    end;
  end;
end;

class function TCaseCompletion.Complete(const AText: string; ATree: TSyntaxTree; ACase: TSyntaxNode;
  const AValues: TArray<string>; const APrefix: string; out AResult: TCaseCompletionEdits): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mOfPos: TTextPosition;
  mSlot: TCaseBranchSlot;
  mAbsent: TArray<string>;
  mAnchor, mBefore: Integer;
  mLineBreak, mBranches, mValue: string;
begin
  AResult := Default(TCaseCompletionEdits);
  Result := (ACase <> nil) and OfPosition(ATree, ACase, mOfPos);
  if Result then
  begin
    mTokens := ATree.Tokens;
    Result := BranchSlot(AText, mTokens, mOfPos, mSlot) and mSlot.HasEnd and
      Missing(AValues, mSlot.Labels, mAbsent) and (mAbsent <> nil);
  end;
  mAnchor := -1;
  mBefore := -1;
  if Result then
  begin
    mAnchor := CaseAnchor(mTokens, ACase, AResult.HasElse);
    if mAnchor >= 0 then
    begin
      mBefore := Prev(mTokens, mAnchor);
    end;
  end;
  if mBefore < 0 then
  begin
    Exit(False);
  end;
  mLineBreak := LineBreakOf(AText);
  mBranches := '';
  for mValue in mAbsent do
  begin
    mBranches := mBranches + mLineBreak + mSlot.BranchIndent + APrefix + mValue + ': ;';
  end;
  AResult.Edits := AnchorEdits(mTokens, mAnchor, mBefore, mBranches, mLineBreak + mSlot.CaseIndent);
  AResult.Count := Length(mAbsent);
end;

end.
