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
    /// <summary>Was Enter ersetzt: von "[" bis hinter "]", ohne schließende Klammer bis zum Ende des
    /// Getippten.</summary>
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
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.TokenCursor;

function Compare(const A, B: TTextPosition): Integer;
begin
  Result := A.Line - B.Line;
  if Result = 0 then
  begin
    Result := A.Character - B.Character;
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
  mIndex: Integer;
begin
  APrefix := -1;
  Result := -1;
  for mIndex := 0 to High(ATokens) do
  begin
    if Compare(ATokens[mIndex].StartPos, APosition) >= 0 then
    begin
      Break;
    end;
    if not IsTrivia(ATokens[mIndex]) then
    begin
      Result := mIndex;
    end;
  end;
  if (Result >= 0) and (ATokens[Result].Kind = TPascalTokenKind.Identifier) and
    (Compare(APosition, ATokens[Result].EndPos) <= 0) then
  begin
    APrefix := Result;
    Result := PreviousCode(ATokens, Result);
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
    AIndex := PreviousCode(ATokens, AIndex);
    if (AIndex >= 0) and ATokens[AIndex].IsSymbol('.') then
    begin
      AIndex := PreviousCode(ATokens, AIndex);
    end
    else
    begin
      Break;
    end;
  end;
end;

/// <summary>Klammern rückwärts zählen; False bei einer offenen Klammer ohne Partner: Der Cursor steht dann in
/// einem Ausdruck, nicht am Zweiganfang.</summary>
function StepParens(const AToken: TPascalToken; var AParens: Integer): Boolean;
begin
  Result := True;
  if AToken.IsSymbol(')') or AToken.IsSymbol(']') then
  begin
    Inc(AParens);
  end
  else if AToken.IsSymbol('(') or AToken.IsSymbol('[') then
  begin
    Result := AParens > 0;
    Dec(AParens);
  end;
end;

/// <summary>AIndex, wenn dort case steht; -1 sonst.</summary>
function CaseIndexOf(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := -1;
  if ATokens[AIndex].IsKeyword('case') then
  begin
    Result := AIndex;
  end;
end;

/// <summary>Umgebende case-Anweisung, wenn AIndex (";" oder ",") am Ende eines ihrer Zweige steht; -1 sonst.</summary>
function EnclosingCase(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
var
  mDepth, mParens: Integer;
begin
  Result := -1;
  mDepth := 0;
  mParens := 0;
  AIndex := PreviousCode(ATokens, AIndex);
  while AIndex >= 0 do
  begin
    if not StepParens(ATokens[AIndex], mParens) then
    begin
      Exit;
    end;
    if ATokens[AIndex].IsKeyword('end') then
    begin
      Inc(mDepth);
    end
    else if IsKeywordIn(ATokens[AIndex], ['begin', 'try', 'asm', 'record', 'class', 'object', 'interface',
      'case']) then
    begin
      if mDepth = 0 then
      begin
        Exit(CaseIndexOf(ATokens, AIndex));
      end;
      Dec(mDepth);
    end
    // "else" bleibt außen vor: Es kann zu einem if in einem Zweig gehören. Im else-Teil der case-Anweisung
    // selbst gilt die Stelle dann auch als Zweiganfang; das schadet nicht.
    else if (mDepth = 0) and IsKeywordIn(ATokens[AIndex], ['repeat', 'var', 'const', 'type', 'procedure',
      'function', 'constructor', 'destructor', 'implementation', 'uses']) then
    begin
      Exit;
    end;
    AIndex := PreviousCode(ATokens, AIndex);
  end;
end;

/// <summary>"of" der case-Anweisung, deren Zweig hinter AIndex beginnt: direkt nach "of", nach dem ";" eines
/// Zweigs oder in einer Liste "a, |"; -1 sonst.</summary>
function CaseOfBefore(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
var
  mCase: Integer;
begin
  if ATokens[AIndex].IsKeyword('of') then
  begin
    Exit(AIndex);
  end;
  Result := -1;
  if ATokens[AIndex].IsSymbol(';') or ATokens[AIndex].IsSymbol(',') then
  begin
    mCase := EnclosingCase(ATokens, AIndex);
    if mCase >= 0 then
    begin
      Result := Next(ATokens, mCase);
      while (Result <= High(ATokens)) and (Result < AIndex) and not ATokens[Result].IsKeyword('of') do
      begin
        Result := Next(ATokens, Result);
      end;
      if (Result > High(ATokens)) or not ATokens[Result].IsKeyword('of') then
      begin
        Result := -1;
      end;
    end;
  end;
end;

{ TCompletionEnums }

class function TCompletionEnums.ValueSlot(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition;
  out ASlot: TEnumValueSlot): Boolean;
var
  mIndex, mPrefix, mOf, mStart: Integer;
begin
  ASlot := Default(TEnumValueSlot);
  Result := False;
  mIndex := TokenBefore(ATokens, APosition, mPrefix);
  if mIndex < 0 then
  begin
    Exit;
  end;
  // Vergleich: "Kette = |", "Kette <> |".
  if ATokens[mIndex].IsSymbol('=') or ATokens[mIndex].IsSymbol('<>') then
  begin
    ASlot.Names := ChainBefore(ATokens, PreviousCode(ATokens, mIndex), mStart);
    ASlot.Offset := ATokens[mIndex].Offset;
    Exit(ASlot.Names <> nil);
  end;
  mOf := CaseOfBefore(ATokens, mIndex);
  if mOf < 0 then
  begin
    Exit;
  end;
  ASlot.Names := ChainBefore(ATokens, PreviousCode(ATokens, mOf), mStart);
  // Nur "case Kette of": ein anderer Ausdruck (Funktionsaufruf, Rechnung) bleibt außen vor.
  Result := (ASlot.Names <> nil) and (PreviousCode(ATokens, mStart) >= 0) and
    ATokens[PreviousCode(ATokens, mStart)].IsKeyword('case');
  if Result then
  begin
    ASlot.Offset := ATokens[mOf].Offset;
  end
  else
  begin
    ASlot.Names := nil;
  end;
end;

/// <summary>AElement an APresent anhängen, wenn es nicht leer ist, und leeren.</summary>
procedure FlushElement(var APresent: TArray<string>; var AElement: string);
begin
  if AElement <> '' then
  begin
    APresent := APresent + [AElement];
  end;
  AElement := '';
end;

/// <summary>Teil einer Menge: Wert, Komma, Bereich oder Punkt eines qualifizierten Werts.</summary>
function IsSetPart(const AToken: TPascalToken): Boolean;
begin
  Result := (AToken.Kind = TPascalTokenKind.Identifier) or AToken.IsSymbol(',') or AToken.IsSymbol('..') or
    AToken.IsSymbol('.');
end;

/// <summary>Öffnende Klammer rückwärts ab AIndex über Werte, Kommas und Bereiche; -1 ohne.</summary>
function OpeningBracket(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result >= 0) and not ATokens[Result].IsSymbol('[') do
  begin
    if not IsSetPart(ATokens[Result]) then
    begin
      Exit(-1);
    end;
    Result := PreviousCode(ATokens, Result);
  end;
end;

/// <summary>"Liste[", "F(x)[", "P^[", "'abc'[": Index, keine Menge.</summary>
function IsIndexBase(const AToken: TPascalToken): Boolean;
begin
  Result := (AToken.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Number, TPascalTokenKind.StringLiteral,
    TPascalTokenKind.CharLiteral]) or AToken.IsSymbol(')') or AToken.IsSymbol(']') or AToken.IsSymbol('^');
end;

/// <summary>AToken an das Element AElement anfügen ("," schließt es ab); ACounts False für das Wort am Cursor.
/// False bei einem Token, das nicht zur Menge gehört.</summary>
function AppendElement(const AToken: TPascalToken; ACounts: Boolean; var APresent: TArray<string>;
  var AElement: string): Boolean;
begin
  Result := True;
  if AToken.IsSymbol(',') then
  begin
    FlushElement(APresent, AElement);
  end
  else if AToken.IsSymbol('.') or AToken.IsSymbol('..') then
  begin
    AElement := AElement + AToken.Text;
  end
  else if AToken.Kind = TPascalTokenKind.Identifier then
  begin
    if ACounts then
    begin
      AElement := AElement + CleanName(AToken.Text);
    end;
  end
  else
  begin
    Result := False;
  end;
end;

/// <summary>Elemente vorwärts ab ABracket bis zur schließenden Klammer; das Wort am Cursor (APrefix) zählt nicht
/// als enthalten. False, wenn die Klammer fehlt; ALast ist das letzte gelesene Token.</summary>
function ClosedElements(const ATokens: TArray<TPascalToken>; ABracket, APrefix: Integer;
  out APresent: TArray<string>; out ALast: Integer): Boolean;
var
  mIndex: Integer;
  mElement: string;
begin
  APresent := nil;
  mElement := '';
  Result := False;
  ALast := ABracket;
  mIndex := Next(ATokens, ABracket);
  while mIndex <= High(ATokens) do
  begin
    if ATokens[mIndex].IsSymbol(']') then
    begin
      Result := True;
      ALast := mIndex;
      Break;
    end;
    if not AppendElement(ATokens[mIndex], mIndex <> APrefix, APresent, mElement) then
    begin
      Break;
    end;
    ALast := mIndex;
    mIndex := Next(ATokens, mIndex);
  end;
  FlushElement(APresent, mElement);
end;

/// <summary>Offene Klammer: Was hinter dem Cursor folgt, gehört nicht zur Menge (nächste Zeile, Anweisung).
/// </summary>
function OpenElements(const ATokens: TArray<TPascalToken>; ABracket, APrefix: Integer;
  const APosition: TTextPosition): TArray<string>;
var
  mIndex: Integer;
  mElement: string;
begin
  Result := nil;
  mElement := '';
  mIndex := Next(ATokens, ABracket);
  while (mIndex <= High(ATokens)) and (Compare(ATokens[mIndex].StartPos, APosition) < 0) do
  begin
    if ATokens[mIndex].IsSymbol(',') then
    begin
      FlushElement(Result, mElement);
    end
    else if mIndex <> APrefix then
    begin
      mElement := mElement + CleanName(ATokens[mIndex].Text);
    end;
    mIndex := Next(ATokens, mIndex);
  end;
  FlushElement(Result, mElement);
end;

class function TCompletionEnums.SetSlot(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition;
  out ASlot: TEnumSetSlot): Boolean;
var
  mPrefix, mBracket, mBefore, mStart, mLast: Integer;
begin
  ASlot := Default(TEnumSetSlot);
  Result := False;
  mBracket := OpeningBracket(ATokens, TokenBefore(ATokens, APosition, mPrefix));
  if mBracket < 0 then
  begin
    Exit;
  end;
  mBefore := PreviousCode(ATokens, mBracket);
  if (mBefore < 0) or IsIndexBase(ATokens[mBefore]) then
  begin
    Exit;
  end;
  if ATokens[mBefore].IsKeyword('in') then
  begin
    ASlot.ElementOf := ChainBefore(ATokens, PreviousCode(ATokens, mBefore), mStart);
    if ASlot.ElementOf = nil then
    begin
      Exit;
    end;
  end;
  ASlot.Bracket := ATokens[mBracket].StartPos;
  ASlot.Offset := ATokens[mBracket].Offset;
  if ClosedElements(ATokens, mBracket, mPrefix, ASlot.Present, mLast) then
  begin
    ASlot.EditRange := TTextRange.Create(ASlot.Bracket, ATokens[mLast].EndPos);
  end
  else
  begin
    ASlot.Present := OpenElements(ATokens, mBracket, mPrefix, APosition);
    ASlot.EditRange := TTextRange.Create(ASlot.Bracket, APosition);
    if mPrefix >= 0 then
    begin
      ASlot.EditRange := TTextRange.Create(ASlot.Bracket, ATokens[mPrefix].EndPos);
    end;
  end;
  Result := True;
end;

/// <summary>Bei "," einen neuen Wert erwarten, sonst den erwarteten Namen an AValues anhängen.</summary>
procedure TakeEnumValue(const AToken: TPascalToken; var AExpect: Boolean; var AValues: TArray<string>);
begin
  if AToken.IsSymbol(',') then
  begin
    AExpect := True;
  end
  else if AExpect and (AToken.Kind = TPascalTokenKind.Identifier) then
  begin
    AValues := AValues + [CleanName(AToken.Text)];
    AExpect := False;
  end;
end;

class function TCompletionEnums.EnumValues(const ADeclaration: string): TArray<string>;
var
  mTokens: TArray<TPascalToken>;
  mIndex, mDepth: Integer;
  mExpect: Boolean;
begin
  Result := nil;
  mTokens := TPascalLexer.Tokenize(ADeclaration);
  // "Name = (": die erste Klammer direkt hinter dem "=".
  mIndex := 0;
  while (mIndex <= High(mTokens)) and not mTokens[mIndex].IsSymbol('=') do
  begin
    Inc(mIndex);
  end;
  mIndex := Next(mTokens, mIndex);
  if (mIndex > High(mTokens)) or not mTokens[mIndex].IsSymbol('(') then
  begin
    Exit;
  end;
  mDepth := 0;
  mExpect := True;
  while mIndex <= High(mTokens) do
  begin
    if mTokens[mIndex].IsSymbol('(') then
    begin
      Inc(mDepth);
    end
    else if mTokens[mIndex].IsSymbol(')') then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Break;
      end;
    end
    else if mDepth = 1 then
    begin
      TakeEnumValue(mTokens[mIndex], mExpect, Result);
    end;
    mIndex := Next(mTokens, mIndex);
  end;
end;

class function TCompletionEnums.SetElement(const ADeclaration: string): string;
var
  mTokens: TArray<TPascalToken>;
  mIndex: Integer;
begin
  Result := '';
  mTokens := TPascalLexer.Tokenize(ADeclaration);
  mIndex := 0;
  while (mIndex <= High(mTokens)) and not mTokens[mIndex].IsSymbol('=') do
  begin
    Inc(mIndex);
  end;
  mIndex := Next(mTokens, mIndex);
  if (mIndex <= High(mTokens)) and mTokens[mIndex].IsKeyword('packed') then
  begin
    mIndex := Next(mTokens, mIndex);
  end;
  if (mIndex > High(mTokens)) or not mTokens[mIndex].IsKeyword('set') then
  begin
    Exit;
  end;
  mIndex := Next(mTokens, mIndex);
  if (mIndex > High(mTokens)) or not mTokens[mIndex].IsKeyword('of') then
  begin
    Exit;
  end;
  mIndex := Next(mTokens, mIndex);
  while (mIndex <= High(mTokens)) and (mTokens[mIndex].Kind = TPascalTokenKind.Identifier) do
  begin
    Result := Result + CleanName(mTokens[mIndex].Text);
    mIndex := Next(mTokens, mIndex);
    if (mIndex <= High(mTokens)) and mTokens[mIndex].IsSymbol('.') then
    begin
      Result := Result + '.';
      mIndex := Next(mTokens, mIndex);
    end
    else
    begin
      Break;
    end;
  end;
end;

class function TCompletionEnums.ScopedAt(const AText: string; AOffset: Integer): Boolean;
var
  mMatch: TMatch;
begin
  Result := False;
  for mMatch in TRegEx.Matches(Copy(AText, 1, AOffset), '\{\$SCOPEDENUMS\s+(ON|OFF)\s*\}', [roIgnoreCase]) do
  begin
    Result := SameText(mMatch.Groups[1].Value, 'ON');
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
    mIndex: Integer;
  begin
    for mIndex := 0 to High(AValues) do
    begin
      if SameText(AValues[mIndex], LastPart(AName)) then
      begin
        Exit(mIndex);
      end;
    end;
    Result := -1;
  end;

var
  mElement: string;
  mBounds: TArray<string>;
  mLow_, mHigh_, mIndex: Integer;
begin
  SetLength(AChecked, Length(AValues));
  for mIndex := 0 to High(AChecked) do
  begin
    AChecked[mIndex] := False;
  end;
  for mElement in APresent do
  begin
    mBounds := mElement.Split(['..']);
    mLow_ := IndexOfValue(mBounds[0]);
    mHigh_ := mLow_;
    if Length(mBounds) = 2 then
    begin
      mHigh_ := IndexOfValue(mBounds[1]);
    end
    else if Length(mBounds) > 2 then
    begin
      Exit(False);
    end;
    if (mLow_ < 0) or (mHigh_ < 0) then
    begin
      Exit(False);
    end;
    for mIndex := mLow_ to mHigh_ do
    begin
      AChecked[mIndex] := True;
    end;
  end;
  Result := True;
end;

end.
