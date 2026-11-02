unit Atlas.Common.Lsp.CompletionEnums;

// Aufzählungen und Mengen in der Vervollständigung (#448), ohne Namensauflösung:
//   - ValueSlot: Stellen, an denen ein Wert vom Typ einer Kette erwartet wird und die ExpectedType nicht
//     über Zuweisung oder Parameter findet: Vergleich ("Shape.Kind = |", "<>") und Zweig einer
//     case-Anweisung ("case Shape.Kind of" und dann am Zweiganfang).
//   - SetSlot: Cursor in einem Mengenkonstruktor ("Anchors := [akLeft, |"): Lage der Klammern, schon
//     enthaltene Werte und woher der Typ kommt ("X in [" oder der erwartete Typ an der Klammer).
//   - EnumValues, SetElement: Werte einer Aufzählung bzw. Elementtyp einer Menge aus dem Text der
//     Deklaration; ScopedAt: gilt {$SCOPEDENUMS ON} an einer Stelle.
//   - Checked: welche Werte in der Klammer schon stehen, auch über Bereiche (skCircle..skRect).

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract;

type
  TEnumValueSlot = record
    /// <summary>Kette, deren Typ erwartet wird: linke Seite des Vergleichs bzw. Ausdruck nach case.</summary>
    Names: TArray<string>;
    /// <summary>Offset, an dem die Kette gilt.</summary>
    Offset: Integer;
  end;

  TEnumSetSlot = record
    /// <summary>Position der öffnenden Klammer.</summary>
    Bracket: TTextPosition;
    /// <summary>Offset der Klammer, für die Namensauflösung.</summary>
    Offset: Integer;
    /// <summary>Bei "X in [": die Kette X, deren Typ der Elementtyp ist; sonst leer, dann gilt der
    /// erwartete Typ an der Klammer.</summary>
    ElementOf: TArray<string>;
    /// <summary>Was Enter ersetzt: von "[" bis hinter "]", ohne schließende Klammer bis zum Ende des Getippten.</summary>
    EditRange: TTextRange;
    /// <summary>Schon enthaltene Werte ("akLeft", "TAlign.alTop") und Bereiche ("skCircle..skRect"), ohne das
    /// Wort am Cursor.</summary>
    Present: TArray<string>;
  end;

  TCompletionEnums = class
  public
    /// <summary>Vergleich oder case-Zweig an APosition; False sonst.</summary>
    class function ValueSlot(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition;
      out ASlot: TEnumValueSlot): Boolean; static;
    /// <summary>Cursor in einem Mengenkonstruktor; False bei Indizes ("Liste[") und außerhalb von Klammern.</summary>
    class function SetSlot(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition;
      out ASlot: TEnumSetSlot): Boolean; static;
    /// <summary>Werte aus "TAlign = (alNone, alTop = 1, …);" in Deklarationsreihenfolge; leer, wenn ADeclaration
    /// keine Aufzählung ist.</summary>
    class function EnumValues(const ADeclaration: string): TArray<string>; static;
    /// <summary>Elementtyp aus "TAnchors = set of TAnchorKind;"; '' sonst (auch bei "set of (a, b)").</summary>
    class function SetElement(const ADeclaration: string): string; static;
    /// <summary>{$SCOPEDENUMS ON} gilt an AOffset (0-basiert) in AText.</summary>
    class function ScopedAt(const AText: string; AOffset: Integer): Boolean; static;
    /// <summary>Je Wert aus AValues, ob APresent ihn enthält (auch über Bereiche); False, wenn APresent einen
    /// unbekannten Namen enthält.</summary>
    class function Checked(const AValues, APresent: TArray<string>; out AChecked: TArray<Boolean>): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  System.RegularExpressions,
  Atlas.Common.Pascal.Lexer;

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

/// <summary>Letztes Token vor APosition ohne Kommentare; APrefix: Index des Bezeichners, in oder hinter dem der
/// Cursor steht (das getippte Wort), sonst -1. Ergebnis ist das Token davor.</summary>
function TokenBefore(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition;
  out APrefix: Integer): Integer;
var
  Index: Integer;
begin
  APrefix := -1;
  Result := -1;
  for Index := 0 to High(ATokens) do
  begin
    if Compare(ATokens[Index].StartPos, APosition) >= 0 then
    begin
      Break;
    end;
    if not IsTrivia(ATokens[Index]) then
    begin
      Result := Index;
    end;
  end;
  if (Result >= 0) and (ATokens[Result].Kind = TPascalTokenKind.Identifier) and
    (Compare(APosition, ATokens[Result].EndPos) <= 0) then
  begin
    APrefix := Result;
    Result := Prev(ATokens, Result);
  end;
end;

/// <summary>Kette A.B.C, die bei AIndex endet, rückwärts gelesen; leer, wenn dort kein Bezeichner steht.</summary>
function ChainBefore(const ATokens: TArray<TPascalToken>; AIndex: Integer; out AStart: Integer): TArray<string>;
begin
  Result := nil;
  AStart := AIndex;
  while (AIndex >= 0) and (ATokens[AIndex].Kind = TPascalTokenKind.Identifier) do
  begin
    Result := [CleanName(ATokens[AIndex].Text)] + Result;
    AStart := AIndex;
    AIndex := Prev(ATokens, AIndex);
    if (AIndex >= 0) and ATokens[AIndex].IsSymbol('.') then
    begin
      AIndex := Prev(ATokens, AIndex);
    end
    else
    begin
      Break;
    end;
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

/// <summary>Umgebende case-Anweisung, wenn AIndex (";" oder ",") am Ende eines ihrer Zweige steht; -1 sonst.</summary>
function EnclosingCase(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
var
  Depth, Parens: Integer;
begin
  Result := -1;
  Depth := 0;
  Parens := 0;
  AIndex := Prev(ATokens, AIndex);
  while AIndex >= 0 do
  begin
    if ATokens[AIndex].IsSymbol(')') or ATokens[AIndex].IsSymbol(']') then
    begin
      Inc(Parens);
    end
    else if ATokens[AIndex].IsSymbol('(') or ATokens[AIndex].IsSymbol('[') then
    begin
      // Offene Klammer: der Cursor steht in einem Ausdruck, nicht am Zweiganfang.
      if Parens = 0 then
      begin
        Exit;
      end;
      Dec(Parens);
    end
    else if ATokens[AIndex].IsKeyword('end') then
    begin
      Inc(Depth);
    end
    else if IsKeywordIn(ATokens[AIndex], ['begin', 'try', 'asm', 'record', 'class', 'object', 'interface', 'case']) then
    begin
      if Depth = 0 then
      begin
        if ATokens[AIndex].IsKeyword('case') then
        begin
          Result := AIndex;
        end;
        Exit;
      end;
      Dec(Depth);
    end
    // "else" bleibt außen vor: Es kann zu einem if in einem Zweig gehören. Im else-Teil der case-Anweisung
    // selbst gilt die Stelle dann auch als Zweiganfang; das schadet nicht.
    else if (Depth = 0) and IsKeywordIn(ATokens[AIndex], ['repeat', 'var', 'const', 'type', 'procedure', 'function',
      'constructor', 'destructor', 'implementation', 'uses']) then
    begin
      Exit;
    end;
    AIndex := Prev(ATokens, AIndex);
  end;
end;

{ TCompletionEnums }

class function TCompletionEnums.ValueSlot(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition;
  out ASlot: TEnumValueSlot): Boolean;
var
  Index, Prefix, CaseIndex, OfIndex, Start: Integer;
begin
  ASlot := Default(TEnumValueSlot);
  Result := False;
  Index := TokenBefore(ATokens, APosition, Prefix);
  if Index < 0 then
  begin
    Exit;
  end;
  // Vergleich: "Kette = |", "Kette <> |".
  if ATokens[Index].IsSymbol('=') or ATokens[Index].IsSymbol('<>') then
  begin
    ASlot.Names := ChainBefore(ATokens, Prev(ATokens, Index), Start);
    ASlot.Offset := ATokens[Index].Offset;
    Exit(ASlot.Names <> nil);
  end;
  // case-Zweig: direkt nach "of", nach dem ";" eines Zweigs oder in einer Liste "a, |".
  if ATokens[Index].IsKeyword('of') then
  begin
    OfIndex := Index;
  end
  else if ATokens[Index].IsSymbol(';') or ATokens[Index].IsSymbol(',') then
  begin
    CaseIndex := EnclosingCase(ATokens, Index);
    if CaseIndex < 0 then
    begin
      Exit;
    end;
    OfIndex := Next(ATokens, CaseIndex);
    while (OfIndex <= High(ATokens)) and (OfIndex < Index) and not ATokens[OfIndex].IsKeyword('of') do
    begin
      OfIndex := Next(ATokens, OfIndex);
    end;
    if (OfIndex > High(ATokens)) or not ATokens[OfIndex].IsKeyword('of') then
    begin
      Exit;
    end;
  end
  else
  begin
    Exit;
  end;
  ASlot.Names := ChainBefore(ATokens, Prev(ATokens, OfIndex), Start);
  // Nur "case Kette of": ein anderer Ausdruck (Funktionsaufruf, Rechnung) bleibt außen vor.
  if (ASlot.Names = nil) or (Prev(ATokens, Start) < 0) or not ATokens[Prev(ATokens, Start)].IsKeyword('case') then
  begin
    ASlot.Names := nil;
    Exit;
  end;
  ASlot.Offset := ATokens[OfIndex].Offset;
  Result := True;
end;

class function TCompletionEnums.SetSlot(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition;
  out ASlot: TEnumSetSlot): Boolean;
var
  Index, Prefix, Bracket, Before, Start, Last: Integer;
  Closed: Boolean;
  Element: string;
  Present: TArray<string>;

  procedure Flush;
  begin
    if Element <> '' then
    begin
      Present := Present + [Element];
    end;
    Element := '';
  end;

begin
  ASlot := Default(TEnumSetSlot);
  Result := False;
  Index := TokenBefore(ATokens, APosition, Prefix);
  // Rückwärts über Werte, Kommas und Bereiche bis zur öffnenden Klammer.
  while (Index >= 0) and not ATokens[Index].IsSymbol('[') do
  begin
    if not ((ATokens[Index].Kind = TPascalTokenKind.Identifier) or ATokens[Index].IsSymbol(',') or
      ATokens[Index].IsSymbol('..') or ATokens[Index].IsSymbol('.')) then
    begin
      Exit;
    end;
    Index := Prev(ATokens, Index);
  end;
  if Index < 0 then
  begin
    Exit;
  end;
  Bracket := Index;
  Before := Prev(ATokens, Bracket);
  if Before < 0 then
  begin
    Exit;
  end;
  // "Liste[", "F(x)[", "P^[", "'abc'[": Index, keine Menge.
  if (ATokens[Before].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Number, TPascalTokenKind.StringLiteral,
    TPascalTokenKind.CharLiteral]) or ATokens[Before].IsSymbol(')') or ATokens[Before].IsSymbol(']') or
    ATokens[Before].IsSymbol('^') then
  begin
    Exit;
  end;
  if ATokens[Before].IsKeyword('in') then
  begin
    ASlot.ElementOf := ChainBefore(ATokens, Prev(ATokens, Before), Start);
    if ASlot.ElementOf = nil then
    begin
      Exit;
    end;
  end;
  ASlot.Bracket := ATokens[Bracket].StartPos;
  ASlot.Offset := ATokens[Bracket].Offset;
  // Vorwärts bis zur schließenden Klammer; das Wort am Cursor zählt nicht als enthalten.
  Present := nil;
  Element := '';
  Closed := False;
  Last := Bracket;
  Index := Next(ATokens, Bracket);
  while Index <= High(ATokens) do
  begin
    if ATokens[Index].IsSymbol(']') then
    begin
      Closed := True;
      Last := Index;
      Break;
    end;
    if ATokens[Index].IsSymbol(',') then
    begin
      Flush;
    end
    else if ATokens[Index].IsSymbol('.') or ATokens[Index].IsSymbol('..') then
    begin
      Element := Element + ATokens[Index].Text;
    end
    else if ATokens[Index].Kind = TPascalTokenKind.Identifier then
    begin
      if Index <> Prefix then
      begin
        Element := Element + CleanName(ATokens[Index].Text);
      end;
    end
    else
    begin
      Break;
    end;
    Last := Index;
    Index := Next(ATokens, Index);
  end;
  Flush;
  if Closed then
  begin
    ASlot.EditRange := TTextRange.Create(ASlot.Bracket, ATokens[Last].EndPos);
  end
  else
  begin
    // Offene Klammer: Was hinter dem Cursor folgt, gehört nicht zur Menge (nächste Zeile, Anweisung).
    Present := nil;
    Element := '';
    Index := Next(ATokens, Bracket);
    while (Index <= High(ATokens)) and (Compare(ATokens[Index].StartPos, APosition) < 0) do
    begin
      if ATokens[Index].IsSymbol(',') then
      begin
        Flush;
      end
      else if Index <> Prefix then
      begin
        Element := Element + CleanName(ATokens[Index].Text);
      end;
      Index := Next(ATokens, Index);
    end;
    Flush;
    if Prefix >= 0 then
    begin
      ASlot.EditRange := TTextRange.Create(ASlot.Bracket, ATokens[Prefix].EndPos);
    end
    else
    begin
      ASlot.EditRange := TTextRange.Create(ASlot.Bracket, APosition);
    end;
  end;
  ASlot.Present := Present;
  Result := True;
end;

class function TCompletionEnums.EnumValues(const ADeclaration: string): TArray<string>;
var
  Tokens: TArray<TPascalToken>;
  Index, Depth: Integer;
  Expect: Boolean;
begin
  Result := nil;
  Tokens := TPascalLexer.Tokenize(ADeclaration);
  // "Name = (": die erste Klammer direkt hinter dem "=".
  Index := 0;
  while (Index <= High(Tokens)) and not Tokens[Index].IsSymbol('=') do
  begin
    Inc(Index);
  end;
  Index := Next(Tokens, Index);
  if (Index > High(Tokens)) or not Tokens[Index].IsSymbol('(') then
  begin
    Exit;
  end;
  Depth := 0;
  Expect := True;
  while Index <= High(Tokens) do
  begin
    if Tokens[Index].IsSymbol('(') then
    begin
      Inc(Depth);
    end
    else if Tokens[Index].IsSymbol(')') then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        Break;
      end;
    end
    else if Depth = 1 then
    begin
      if Tokens[Index].IsSymbol(',') then
      begin
        Expect := True;
      end
      else if Expect and (Tokens[Index].Kind = TPascalTokenKind.Identifier) then
      begin
        Result := Result + [CleanName(Tokens[Index].Text)];
        Expect := False;
      end;
    end;
    Index := Next(Tokens, Index);
  end;
end;

class function TCompletionEnums.SetElement(const ADeclaration: string): string;
var
  Tokens: TArray<TPascalToken>;
  Index: Integer;
begin
  Result := '';
  Tokens := TPascalLexer.Tokenize(ADeclaration);
  Index := 0;
  while (Index <= High(Tokens)) and not Tokens[Index].IsSymbol('=') do
  begin
    Inc(Index);
  end;
  Index := Next(Tokens, Index);
  if (Index <= High(Tokens)) and Tokens[Index].IsKeyword('packed') then
  begin
    Index := Next(Tokens, Index);
  end;
  if (Index > High(Tokens)) or not Tokens[Index].IsKeyword('set') then
  begin
    Exit;
  end;
  Index := Next(Tokens, Index);
  if (Index > High(Tokens)) or not Tokens[Index].IsKeyword('of') then
  begin
    Exit;
  end;
  Index := Next(Tokens, Index);
  while (Index <= High(Tokens)) and (Tokens[Index].Kind = TPascalTokenKind.Identifier) do
  begin
    Result := Result + CleanName(Tokens[Index].Text);
    Index := Next(Tokens, Index);
    if (Index <= High(Tokens)) and Tokens[Index].IsSymbol('.') then
    begin
      Result := Result + '.';
      Index := Next(Tokens, Index);
    end
    else
    begin
      Break;
    end;
  end;
end;

class function TCompletionEnums.ScopedAt(const AText: string; AOffset: Integer): Boolean;
var
  Match: TMatch;
begin
  Result := False;
  for Match in TRegEx.Matches(Copy(AText, 1, AOffset), '\{\$SCOPEDENUMS\s+(ON|OFF)\s*\}', [roIgnoreCase]) do
  begin
    Result := SameText(Match.Groups[1].Value, 'ON');
  end;
end;

/// <summary>Letzter Teil eines qualifizierten Namens: TAlign.alTop → alTop.</summary>
function LastPart(const AName: string): string;
begin
  Result := AName.Substring(AName.LastIndexOf('.') + 1);
end;

class function TCompletionEnums.Checked(const AValues, APresent: TArray<string>;
  out AChecked: TArray<Boolean>): Boolean;

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
  Element: string;
  Bounds: TArray<string>;
  Low_, High_, Index: Integer;
begin
  SetLength(AChecked, Length(AValues));
  for Index := 0 to High(AChecked) do
  begin
    AChecked[Index] := False;
  end;
  for Element in APresent do
  begin
    Bounds := Element.Split(['..']);
    Low_ := IndexOfValue(Bounds[0]);
    High_ := Low_;
    if Length(Bounds) = 2 then
    begin
      High_ := IndexOfValue(Bounds[1]);
    end
    else if Length(Bounds) > 2 then
    begin
      Exit(False);
    end;
    if (Low_ < 0) or (High_ < 0) then
    begin
      Exit(False);
    end;
    for Index := Low_ to High_ do
    begin
      AChecked[Index] := True;
    end;
  end;
  Result := True;
end;

end.
