unit Atlas.Core.Completion.Matching;

// Filtern und Sortieren der Vervollständigung im Plugin (#409, #229): Beim
// Weitertippen fragt das Popup nicht den Server, sondern filtert die vorhandene
// Liste. Rangfolge: genauer Name, Anfang mit gleicher Schreibweise, Anfang,
// Wortanfänge (CamelCase, "TSL" → TStringList), Teilstring, Teilfolge. Bei
// gleicher Stufe gilt die Reihenfolge der Quelle (Rank), dann der Name.
// Ob ein Name passt (Wortanfänge, Teilfolge), entscheidet TTextFuzzy aus
// Atlas.Text, dieselbe Regel wie beim Server (ADR 0012, D-05).

interface

uses
  System.SysUtils,
  Atlas.Core.Completion.Contract;

type
  TAtlasCompletionMatcher = class
  public const
    cNoMatch = -1;
    cScoreExact = 1000;
    cScorePrefixCase = 900;
    cScorePrefix = 800;
    cScoreWordStarts = 600;
    cScoreSubstring = 400;
    cScoreSubsequence = 200;
  public
    /// <summary>Punktzahl von AName für APattern; NoMatch, wenn er nicht passt. Leeres Muster passt immer.</summary>
    class function Score(const APattern, AName: string): Integer; static;
    /// <summary>Indizes der passenden Einträge, beste zuerst.</summary>
    class function Filter(const AItems: TAtlasCompletionItems; const APattern: string): TArray<Integer>; static;
    /// <summary>AName[AIndex] (1-basiert) beginnt ein Wort; Regel aus TTextFuzzy (wie beim Server).</summary>
    class function IsWordStart(const AName: string; AIndex: Integer): Boolean; static;
    /// <summary>Damerau-Levenshtein-Abstand (Vertauschung zählt 1), ohne Groß-/Kleinschreibung (#485).</summary>
    class function Distance(const A, B: string): Integer; static;
    /// <summary>Tippfehler-Abstand von APattern zu AName: zum ganzen Namen oder zu seinem gleich langen
    /// Anfang.</summary>
    class function TypoDistance(const APattern, AName: string): Integer; static;
    /// <summary>Höchster erlaubter Abstand: 1 bis 5 Zeichen, sonst 2; 0 bei weniger als 3 Zeichen (#485).</summary>
    class function TypoLimit(const APattern: string): Integer; static;
    /// <summary>Einfügetext beim Übernehmen (#433): mit AFixCase der deklarierte Name, sonst
    /// bleibt das getippte Wort in seiner Schreibweise stehen, wenn der Name damit beginnt.</summary>
    class function CommitText(const ATyped, AName: string; AFixCase: Boolean): string; static;
  end;

implementation

uses
  System.Math,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Text.Fuzzy;

{ TAtlasCompletionMatcher }

class function TAtlasCompletionMatcher.Distance(const A, B: string): Integer;
var
  mLeft, mRight: string;
  mRows: array of array of Integer;
  I, J, mCost: Integer;
begin
  mLeft := LowerCase(A);
  mRight := LowerCase(B);
  SetLength(mRows, Length(mLeft) + 1, Length(mRight) + 1);
  for I := 0 to Length(mLeft) do
  begin
    mRows[I][0] := I;
  end;
  for J := 0 to Length(mRight) do
  begin
    mRows[0][J] := J;
  end;
  for I := 1 to Length(mLeft) do
  begin
    for J := 1 to Length(mRight) do
    begin
      if mLeft[I] = mRight[J] then
      begin
        mCost := 0;
      end
      else
      begin
        mCost := 1;
      end;
      mRows[I][J] := Min(Min(mRows[I - 1][J] + 1, mRows[I][J - 1] + 1), mRows[I - 1][J - 1] + mCost);
      // Vertauschte Nachbarn ("Lenght" statt "Length").
      if (I > 1) and (J > 1) and (mLeft[I] = mRight[J - 1]) and (mLeft[I - 1] = mRight[J]) then
      begin
        mRows[I][J] := Min(mRows[I][J], mRows[I - 2][J - 2] + 1);
      end;
    end;
  end;
  Result := mRows[Length(mLeft)][Length(mRight)];
end;

class function TAtlasCompletionMatcher.TypoDistance(const APattern, AName: string): Integer;
begin
  Result := Distance(APattern, AName);
  if Length(AName) > Length(APattern) then
  begin
    Result := Min(Result, Distance(APattern, Copy(AName, 1, Length(APattern))));
  end;
end;

class function TAtlasCompletionMatcher.TypoLimit(const APattern: string): Integer;
begin
  if Length(APattern) < 3 then
  begin
    Result := 0;
  end
  else if Length(APattern) <= 5 then
  begin
    Result := 1;
  end
  else
  begin
    Result := 2;
  end;
end;

class function TAtlasCompletionMatcher.CommitText(const ATyped, AName: string; AFixCase: Boolean): string;
begin
  if not AFixCase and (ATyped <> '') and (Length(ATyped) <= Length(AName)) and
    SameText(ATyped, Copy(AName, 1, Length(ATyped))) then
  begin
    Result := ATyped + Copy(AName, Length(ATyped) + 1, MaxInt);
  end
  else
  begin
    Result := AName;
  end;
end;

class function TAtlasCompletionMatcher.IsWordStart(const AName: string; AIndex: Integer): Boolean;
begin
  Result := TTextFuzzy.IsWordStart(AName, AIndex);
end;

class function TAtlasCompletionMatcher.Score(const APattern, AName: string): Integer;
begin
  if APattern = '' then
  begin
    Exit(cScoreSubsequence);
  end;
  if Length(APattern) > Length(AName) then
  begin
    Exit(cNoMatch);
  end;
  if SameText(APattern, AName) then
  begin
    Result := cScoreExact;
  end
  else if AName.StartsWith(APattern) then
  begin
    Result := cScorePrefixCase;
  end
  else if AName.StartsWith(APattern, True) then
  begin
    Result := cScorePrefix;
  end
  else if TTextFuzzy.MatchesWordStarts(APattern, AName) then
  begin
    Result := cScoreWordStarts;
  end
  else if AName.ToUpper.Contains(APattern.ToUpper) then
  begin
    Result := cScoreSubstring;
  end
  else if TTextFuzzy.MatchesBoundedSubsequence(APattern, AName) then
  begin
    Result := cScoreSubsequence;
  end
  else
  begin
    Result := cNoMatch;
  end;
end;

class function TAtlasCompletionMatcher.Filter(const AItems: TAtlasCompletionItems;
  const APattern: string): TArray<Integer>;
var
  mScores: TArray<Integer>;
  mMatches: TList<Integer>;
  mIndex: Integer;
  mItems: TAtlasCompletionItems;
begin
  mItems := AItems;
  SetLength(mScores, Length(mItems));
  mMatches := TList<Integer>.Create;
  try
    for mIndex := 0 to High(mItems) do
    begin
      if mItems[mIndex].FilterText <> '' then
      begin
        mScores[mIndex] := Score(APattern, mItems[mIndex].FilterText);
      end
      else
      begin
        mScores[mIndex] := Score(APattern, mItems[mIndex].Name);
      end;
      if mScores[mIndex] <> cNoMatch then
      begin
        mMatches.Add(mIndex);
      end;
    end;
    mMatches.Sort(TComparer<Integer>.Construct(
      function(const A, B: Integer): Integer
      begin
        // In der aktiven Konfiguration nicht vorhanden: immer ans Ende (#476).
        Result := Ord(mItems[A].Unavailable) - Ord(mItems[B].Unavailable);
        if Result = 0 then
        begin
          Result := mScores[B] - mScores[A];
        end;
        if Result = 0 then
        begin
          Result := mItems[A].Rank - mItems[B].Rank;
        end;
        if Result = 0 then
        begin
          Result := CompareText(mItems[A].Name, mItems[B].Name);
        end;
        if Result = 0 then
        begin
          Result := A - B;
        end;
      end));
    Result := mMatches.ToArray;
  finally
    mMatches.Free;
  end;
end;

end.
