unit Atlas.Common.Pascal.TokenCursor;

// Lesender Zugriff auf die Token einer Unit für Prüfregeln, Editierbefehle und LSP-Funktionen: Token zu einem
// Offset, nächstes und voriges Code-Token, passende Klammer. Alle Indexprüfungen an den Rändern des Token-Arrays
// stehen hier an einer Stelle; Regeln bringen keine eigenen Kopien dieser Helfer mit (Kopien-Sperre in
// Tools/Check-PackageDependencies.ps1).
//
// Die freien Funktionen dienen Aufrufern, die nur ein Array haben; TTokenCursor bündelt dieselben Zugriffe für
// eine Regel, die ihren Lauf in einem Record oder einer Klasse hält. Ein Index außerhalb des Arrays ist nie ein
// Fehler: At liefert dann ein leeres Token, die Suchen liefern ihren dokumentierten Randwert.

interface

uses
  Atlas.Common.Pascal.Contract;

type
  /// <summary>Lesender Blick auf die Token einer Unit; alle Indexprüfungen an einer Stelle.</summary>
  TTokenCursor = record
  private
    FTokens: TArray<TPascalToken>;
  public
    constructor Create(const ATokens: TArray<TPascalToken>);
    /// <summary>Anzahl der Token.</summary>
    function Count: Integer; inline;
    /// <summary>Die Token selbst (ohne Kopie).</summary>
    function Tokens: TArray<TPascalToken>; inline;
    /// <summary>Liegt AIndex im Array?</summary>
    function InRange(AIndex: Integer): Boolean; inline;
    /// <summary>Token an AIndex; außerhalb ein leeres Token (Kind Unknown, Text '', Offset -1), nie ein
    /// Fehler.</summary>
    function At(AIndex: Integer): TPascalToken;
    /// <summary>Ist das Token an AIndex das Schlüsselwort, der Bezeichner (ohne Groß-/Kleinschreibung) oder das
    /// Symbol AText? Außerhalb, bei Kommentaren, Direktiven und Literalen False.</summary>
    function Is_(AIndex: Integer; const AText: string): Boolean;
    /// <summary>Index des ersten Tokens, das bei AOffset oder dahinter beginnt; Count, wenn keines folgt.</summary>
    function From(AOffset: Integer): Integer; inline;
    /// <summary>Index des Tokens, das genau bei AOffset beginnt; -1 ohne.</summary>
    function Exactly(AOffset: Integer): Integer; inline;
    /// <summary>Erstes Code-Token ab AIndex (AIndex eingeschlossen), Kommentare und Direktiven übersprungen;
    /// Count ohne.</summary>
    function NextCode(AIndex: Integer): Integer; inline;
    /// <summary>Letztes Code-Token vor AIndex (AIndex ausgeschlossen); -1 ohne.</summary>
    function PreviousCode(AIndex: Integer): Integer; inline;
    /// <summary>Index der schließenden runden oder eckigen Klammer zur öffnenden an AOpenIndex; -1 ohne
    /// Gegenstück oder wenn an AOpenIndex keine öffnende Klammer steht.</summary>
    function MatchingParen(AOpenIndex: Integer): Integer; inline;
  end;

/// <summary>Kommentar oder Compileranweisung?</summary>
function IsTrivia(const AToken: TPascalToken): Boolean;
/// <summary>Ist AToken eines der Schlüsselwörter AWords (ohne Groß-/Kleinschreibung)?</summary>
function IsKeywordIn(const AToken: TPascalToken; const AWords: array of string): Boolean;
/// <summary>Index des ersten Tokens, das bei AOffset oder dahinter beginnt (binäre Suche, die Token sind nach
/// Offset sortiert); Length(ATokens), wenn keines folgt.</summary>
function TokenFrom(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
/// <summary>Index des Tokens, das genau bei AOffset beginnt (binäre Suche); -1 ohne.</summary>
function TokenExactly(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
/// <summary>Erstes Code-Token ab AIndex (AIndex eingeschlossen, negativ zählt wie 0, über Length(ATokens) wie
/// Length(ATokens)); Length(ATokens) ohne.</summary>
function NextCode(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
/// <summary>Letztes Code-Token vor AIndex (AIndex ausgeschlossen, über Length(ATokens) zählt wie
/// Length(ATokens)); -1 ohne.</summary>
function PreviousCode(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
/// <summary>Index der schließenden Klammer zur öffnenden an AOpen; runde und eckige Klammern (auch (. und .))
/// zählen gemeinsam. Gesucht wird nur vor AStop (Index ausgeschlossen, höchstens Length(ATokens)). -1 ohne
/// Gegenstück oder wenn an AOpen keine öffnende Klammer steht.</summary>
function MatchingParen(const ATokens: TArray<TPascalToken>; AOpen: Integer; AStop: Integer = MaxInt): Integer;

implementation

uses
  System.SysUtils;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function IsKeywordIn(const AToken: TPascalToken; const AWords: array of string): Boolean;
var
  mWord: string;
begin
  if AToken.Kind <> TPascalTokenKind.Keyword then
  begin
    Exit(False);
  end;
  for mWord in AWords do
  begin
    if SameText(AToken.Text, mWord) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TokenFrom(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
var
  mHigh, mMiddle: Integer;
begin
  Result := 0;
  mHigh := Length(ATokens);
  while Result < mHigh do
  begin
    mMiddle := (Result + mHigh) div 2;
    if ATokens[mMiddle].Offset < AOffset then
    begin
      Result := mMiddle + 1;
    end
    else
    begin
      mHigh := mMiddle;
    end;
  end;
end;

function TokenExactly(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
begin
  Result := TokenFrom(ATokens, AOffset);
  if (Result > High(ATokens)) or (ATokens[Result].Offset <> AOffset) then
  begin
    Result := -1;
  end;
end;

function NextCode(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex;
  if Result < 0 then
  begin
    Result := 0;
  end
  else if Result > Length(ATokens) then
  begin
    Result := Length(ATokens);
  end;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
  begin
    Inc(Result);
  end;
end;

function PreviousCode(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  if Result > High(ATokens) then
  begin
    Result := High(ATokens);
  end;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
  begin
    Dec(Result);
  end;
  if Result < -1 then
  begin
    Result := -1;
  end;
end;

function MatchingParen(const ATokens: TArray<TPascalToken>; AOpen: Integer; AStop: Integer): Integer;
var
  mDepth, mLast: Integer;
begin
  mLast := High(ATokens);
  if AStop <= mLast then
  begin
    mLast := AStop - 1;
  end;
  if (AOpen < 0) or (AOpen > mLast) or not (ATokens[AOpen].IsSymbol('(') or ATokens[AOpen].IsSymbol('[')) then
  begin
    Exit(-1);
  end;
  mDepth := 0;
  for Result := AOpen to mLast do
  begin
    if ATokens[Result].IsSymbol('(') or ATokens[Result].IsSymbol('[') then
    begin
      Inc(mDepth);
    end
    else if ATokens[Result].IsSymbol(')') or ATokens[Result].IsSymbol(']') then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit;
      end;
    end;
  end;
  Result := -1;
end;

{ TTokenCursor }

constructor TTokenCursor.Create(const ATokens: TArray<TPascalToken>);
begin
  FTokens := ATokens;
end;

function TTokenCursor.Count: Integer;
begin
  Result := Length(FTokens);
end;

function TTokenCursor.Tokens: TArray<TPascalToken>;
begin
  Result := FTokens;
end;

function TTokenCursor.InRange(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex < Length(FTokens));
end;

function TTokenCursor.At(AIndex: Integer): TPascalToken;
begin
  if InRange(AIndex) then
  begin
    Exit(FTokens[AIndex]);
  end;
  Result := Default(TPascalToken);
  Result.Kind := TPascalTokenKind.Unknown;
  Result.Offset := -1;
end;

function TTokenCursor.Is_(AIndex: Integer; const AText: string): Boolean;
begin
  if not InRange(AIndex) then
  begin
    Exit(False);
  end;
  case FTokens[AIndex].Kind of
    TPascalTokenKind.Keyword, TPascalTokenKind.Identifier:
      Result := SameText(FTokens[AIndex].Text, AText);
    TPascalTokenKind.Symbol:
      Result := FTokens[AIndex].IsSymbol(AText);
  else
    Result := False;
  end;
end;

function TTokenCursor.From(AOffset: Integer): Integer;
begin
  Result := TokenFrom(FTokens, AOffset);
end;

function TTokenCursor.Exactly(AOffset: Integer): Integer;
begin
  Result := TokenExactly(FTokens, AOffset);
end;

function TTokenCursor.NextCode(AIndex: Integer): Integer;
begin
  Result := Atlas.Common.Pascal.TokenCursor.NextCode(FTokens, AIndex);
end;

function TTokenCursor.PreviousCode(AIndex: Integer): Integer;
begin
  Result := Atlas.Common.Pascal.TokenCursor.PreviousCode(FTokens, AIndex);
end;

function TTokenCursor.MatchingParen(AOpenIndex: Integer): Integer;
begin
  Result := Atlas.Common.Pascal.TokenCursor.MatchingParen(FTokens, AOpenIndex);
end;

end.
