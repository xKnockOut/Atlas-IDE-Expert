unit Atlas.Common.History.Similarity;

// Ähnlichkeit zweier Routinen für die Symbolgeschichte (#2641): Gleiche Anweisungsfolge bis auf Namen heißt
// Vorgänger. Verglichen wird der Rumpf ohne Kopf (der Name gehört zum Kopf): Bezeichner werden zu "I",
// Zeichenketten zu "S", Zahlen zu "N", Schlüsselwörter und Satzzeichen bleiben, Kommentare und Direktiven fallen
// weg. Maß ist der Dice-Koeffizient über Folgen von drei Token (Trigramme mit Häufigkeit). Rümpfe unter
// cMinTokens Token sind zu kurz für eine Aussage und haben die Ähnlichkeit 0.

interface

uses
  System.SysUtils;

type
  TSymbolSimilarity = class
  public const
    /// <summary>Kürzere Rümpfe vergleichen nicht (Ähnlichkeit 0).</summary>
    cMinTokens = 12;
  public
    /// <summary>Token des Rumpfs von ARoutineText (Kopf bis zum ersten ";" außerhalb von Klammern
    /// übersprungen) in vergleichbarer Form.</summary>
    class function Shape(const ARoutineText: string): TArray<string>; static;
    /// <summary>Dice-Koeffizient der Trigramme von ALeft und ARight (0–1).</summary>
    class function Compare(const ALeft, ARight: TArray<string>): Double; static;
  end;

implementation

uses
  System.Math,
  System.Generics.Collections,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer;

/// <summary>Index hinter dem Kopf: hinter dem ersten ";" außerhalb von Klammern; 0, wenn keins kommt.</summary>
function BodyStart(const ATokens: TArray<TPascalToken>): Integer;
var
  mIndex, mDepth: Integer;
begin
  mDepth := 0;
  for mIndex := 0 to High(ATokens) do
  begin
    if ATokens[mIndex].Kind <> TPascalTokenKind.Symbol then
    begin
      Continue;
    end;
    if ATokens[mIndex].IsSymbol('(') or ATokens[mIndex].IsSymbol('[') then
    begin
      Inc(mDepth);
    end
    else if ATokens[mIndex].IsSymbol(')') or ATokens[mIndex].IsSymbol(']') then
    begin
      Dec(mDepth);
    end
    else if (mDepth <= 0) and ATokens[mIndex].IsSymbol(';') then
    begin
      Exit(mIndex + 1);
    end;
  end;
  Result := 0;
end;

/// <summary>Vergleichbare Form eines Tokens; '' = fällt weg.</summary>
function TokenShape(const AToken: TPascalToken): string;
begin
  case AToken.Kind of
    TPascalTokenKind.Identifier:
      Result := 'I';
    TPascalTokenKind.Keyword:
      Result := LowerCase(AToken.Text);
    TPascalTokenKind.Number:
      Result := 'N';
    TPascalTokenKind.StringLiteral, TPascalTokenKind.CharLiteral:
      Result := 'S';
    TPascalTokenKind.Symbol, TPascalTokenKind.Unknown:
      Result := AToken.Text;
  else
    Result := '';
  end;
end;

class function TSymbolSimilarity.Shape(const ARoutineText: string): TArray<string>;
var
  mTokens: TArray<TPascalToken>;
  mIndex, mCount: Integer;
  mShape: string;
begin
  Result := nil;
  mTokens := TPascalLexer.Tokenize(ARoutineText);
  SetLength(Result, Length(mTokens));
  mCount := 0;
  for mIndex := BodyStart(mTokens) to High(mTokens) do
  begin
    mShape := TokenShape(mTokens[mIndex]);
    if mShape <> '' then
    begin
      Result[mCount] := mShape;
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

/// <summary>Trigramme von ATokens mit Häufigkeit in AGrams.</summary>
procedure CountGrams(const ATokens: TArray<string>; AGrams: TDictionary<string, Integer>);
var
  mIndex, mCount: Integer;
  mKey: string;
begin
  for mIndex := 0 to Length(ATokens) - 3 do
  begin
    mKey := ATokens[mIndex] + #1 + ATokens[mIndex + 1] + #1 + ATokens[mIndex + 2];
    if not AGrams.TryGetValue(mKey, mCount) then
    begin
      mCount := 0;
    end;
    AGrams.AddOrSetValue(mKey, mCount + 1);
  end;
end;

class function TSymbolSimilarity.Compare(const ALeft, ARight: TArray<string>): Double;
var
  mLeft, mRight: TDictionary<string, Integer>;
  mPair: TPair<string, Integer>;
  mOther, mShared: Integer;
begin
  if (Length(ALeft) < cMinTokens) or (Length(ARight) < cMinTokens) then
  begin
    Exit(0);
  end;
  mLeft := TDictionary<string, Integer>.Create;
  mRight := TDictionary<string, Integer>.Create;
  try
    CountGrams(ALeft, mLeft);
    CountGrams(ARight, mRight);
    mShared := 0;
    for mPair in mLeft do
    begin
      if mRight.TryGetValue(mPair.Key, mOther) then
      begin
        Inc(mShared, Min(mPair.Value, mOther));
      end;
    end;
    // Je Seite Länge - 2 Trigramme.
    Result := 2 * mShared / (Length(ALeft) - 2 + Length(ARight) - 2);
  finally
    mRight.Free;
    mLeft.Free;
  end;
end;

end.
