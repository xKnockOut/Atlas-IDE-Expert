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
    NoMatch = -1;
    ScoreExact = 1000;
    ScorePrefixCase = 900;
    ScorePrefix = 800;
    ScoreWordStarts = 600;
    ScoreSubstring = 400;
    ScoreSubsequence = 200;
  public
    /// <summary>Punktzahl von AName für APattern; NoMatch, wenn er nicht passt. Leeres Muster passt immer.</summary>
    class function Score(const APattern, AName: string): Integer; static;
    /// <summary>Indizes der passenden Einträge, beste zuerst.</summary>
    class function Filter(const AItems: TAtlasCompletionItems; const APattern: string): TArray<Integer>; static;
    /// <summary>AName[AIndex] (1-basiert) beginnt ein Wort; Regel aus TTextFuzzy (wie beim Server).</summary>
    class function IsWordStart(const AName: string; AIndex: Integer): Boolean; static;
    /// <summary>Damerau-Levenshtein-Abstand (Vertauschung zählt 1), ohne Groß-/Kleinschreibung (#485).</summary>
    class function Distance(const A, B: string): Integer; static;
    /// <summary>Tippfehler-Abstand von APattern zu AName: zum ganzen Namen oder zu seinem gleich langen Anfang.</summary>
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
  Left, Right: string;
  Rows: array of array of Integer;
  I, J, Cost: Integer;
begin
  Left := LowerCase(A);
  Right := LowerCase(B);
  SetLength(Rows, Length(Left) + 1, Length(Right) + 1);
  for I := 0 to Length(Left) do
    Rows[I][0] := I;
  for J := 0 to Length(Right) do
    Rows[0][J] := J;
  for I := 1 to Length(Left) do
    for J := 1 to Length(Right) do
    begin
      if Left[I] = Right[J] then
        Cost := 0
      else
        Cost := 1;
      Rows[I][J] := Min(Min(Rows[I - 1][J] + 1, Rows[I][J - 1] + 1), Rows[I - 1][J - 1] + Cost);
      // Vertauschte Nachbarn ("Lenght" statt "Length").
      if (I > 1) and (J > 1) and (Left[I] = Right[J - 1]) and (Left[I - 1] = Right[J]) then
        Rows[I][J] := Min(Rows[I][J], Rows[I - 2][J - 2] + 1);
    end;
  Result := Rows[Length(Left)][Length(Right)];
end;

class function TAtlasCompletionMatcher.TypoDistance(const APattern, AName: string): Integer;
begin
  Result := Distance(APattern, AName);
  if Length(AName) > Length(APattern) then
    Result := Min(Result, Distance(APattern, Copy(AName, 1, Length(APattern))));
end;

class function TAtlasCompletionMatcher.TypoLimit(const APattern: string): Integer;
begin
  if Length(APattern) < 3 then
    Result := 0
  else if Length(APattern) <= 5 then
    Result := 1
  else
    Result := 2;
end;

class function TAtlasCompletionMatcher.CommitText(const ATyped, AName: string; AFixCase: Boolean): string;
begin
  if not AFixCase and (ATyped <> '') and (Length(ATyped) <= Length(AName)) and
    SameText(ATyped, Copy(AName, 1, Length(ATyped))) then
    Result := ATyped + Copy(AName, Length(ATyped) + 1, MaxInt)
  else
    Result := AName;
end;

class function TAtlasCompletionMatcher.IsWordStart(const AName: string; AIndex: Integer): Boolean;
begin
  Result := TTextFuzzy.IsWordStart(AName, AIndex);
end;

class function TAtlasCompletionMatcher.Score(const APattern, AName: string): Integer;
begin
  if APattern = '' then
    Exit(ScoreSubsequence);
  if Length(APattern) > Length(AName) then
    Exit(NoMatch);
  if SameText(APattern, AName) then
    Result := ScoreExact
  else if AName.StartsWith(APattern) then
    Result := ScorePrefixCase
  else if AName.StartsWith(APattern, True) then
    Result := ScorePrefix
  else if TTextFuzzy.MatchesWordStarts(APattern, AName) then
    Result := ScoreWordStarts
  else if AName.ToUpper.Contains(APattern.ToUpper) then
    Result := ScoreSubstring
  else if TTextFuzzy.MatchesBoundedSubsequence(APattern, AName) then
    Result := ScoreSubsequence
  else
    Result := NoMatch;
end;

class function TAtlasCompletionMatcher.Filter(const AItems: TAtlasCompletionItems;
  const APattern: string): TArray<Integer>;
var
  Scores: TArray<Integer>;
  Matches: TList<Integer>;
  Index: Integer;
  Items: TAtlasCompletionItems;
begin
  Items := AItems;
  SetLength(Scores, Length(Items));
  Matches := TList<Integer>.Create;
  try
    for Index := 0 to High(Items) do
    begin
      if Items[Index].FilterText <> '' then
        Scores[Index] := Score(APattern, Items[Index].FilterText)
      else
        Scores[Index] := Score(APattern, Items[Index].Name);
      if Scores[Index] <> NoMatch then
        Matches.Add(Index);
    end;
    Matches.Sort(TComparer<Integer>.Construct(
      function(const A, B: Integer): Integer
      begin
        // In der aktiven Konfiguration nicht vorhanden: immer ans Ende (#476).
        Result := Ord(Items[A].Unavailable) - Ord(Items[B].Unavailable);
        if Result = 0 then
          Result := Scores[B] - Scores[A];
        if Result = 0 then
          Result := Items[A].Rank - Items[B].Rank;
        if Result = 0 then
          Result := CompareText(Items[A].Name, Items[B].Name);
        if Result = 0 then
          Result := A - B;
      end));
    Result := Matches.ToArray;
  finally
    Matches.Free;
  end;
end;

end.
