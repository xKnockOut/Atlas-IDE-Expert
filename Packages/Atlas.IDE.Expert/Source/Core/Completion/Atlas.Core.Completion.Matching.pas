unit Atlas.Core.Completion.Matching;

// Filtern und Sortieren der Vervollständigung im Plugin (#409, #229): Beim
// Weitertippen fragt das Popup nicht den Server, sondern filtert die vorhandene
// Liste. Rangfolge: genauer Name, Anfang mit gleicher Schreibweise, Anfang,
// Wortanfänge (CamelCase, "TSL" → TStringList), Teilstring, Teilfolge. Bei
// gleicher Stufe gilt die Reihenfolge der Quelle (Rank), dann der Name.

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
    /// <summary>AName[AIndex] (1-basiert) beginnt ein Wort: CamelCase, nach "_", Ziffern.</summary>
    class function IsWordStart(const AName: string; AIndex: Integer): Boolean; static;
  end;

implementation

uses
  System.Character,
  System.Generics.Collections,
  System.Generics.Defaults;

function IsWordStart(const AName: string; AIndex: Integer): Boolean;
var
  Current, Previous: Char;
begin
  // 1-basiert. Wortanfang: erstes Zeichen, Großbuchstabe nach Kleinbuchstaben oder Ziffer,
  // Großbuchstabe vor einem Kleinbuchstaben ("S" in TStringList), Zeichen nach "_",
  // Ziffer nach Buchstaben.
  if AIndex = 1 then
    Exit(True);
  Current := AName[AIndex];
  Previous := AName[AIndex - 1];
  if Previous = '_' then
    Exit(Current <> '_');
  if Current.IsUpper then
    Exit(Previous.IsLower or Previous.IsDigit or
      ((AIndex < Length(AName)) and AName[AIndex + 1].IsLower));
  Result := Current.IsDigit and not Previous.IsDigit;
end;

function MatchesWordStarts(const APattern, AName: string): Boolean;
var
  PatternIndex, NameIndex: Integer;
begin
  // Jedes Musterzeichen trifft einen Wortanfang, in Reihenfolge; Großschreibung egal.
  PatternIndex := 1;
  for NameIndex := 1 to Length(AName) do
    if (PatternIndex <= Length(APattern)) and IsWordStart(AName, NameIndex) and
      (UpCase(AName[NameIndex]) = UpCase(APattern[PatternIndex])) then
      Inc(PatternIndex);
  Result := PatternIndex > Length(APattern);
end;

function MatchesSubsequence(const APattern, AName: string): Boolean;
var
  Reached, Next: TArray<Boolean>;
  PatternIndex, NameIndex: Integer;
  Previous: Boolean;
begin
  // Teilfolge mit Wortgrenzen: Das erste Zeichen trifft einen Wortanfang, jedes weitere
  // folgt direkt auf das vorige oder trifft einen Wortanfang. "stl" passt auf TStringList,
  // verstreute Treffer wie "myLis" in ERROR_TOO_MANY_LINKS nicht.
  // Reached[i]: Das Muster bis zum aktuellen Zeichen endet passend bei AName[i].
  SetLength(Reached, Length(AName) + 1);
  for NameIndex := 1 to Length(AName) do
    Reached[NameIndex] := IsWordStart(AName, NameIndex) and (UpCase(AName[NameIndex]) = UpCase(APattern[1]));
  for PatternIndex := 2 to Length(APattern) do
  begin
    SetLength(Next, Length(AName) + 1);
    Previous := False;
    for NameIndex := 1 to Length(AName) do
    begin
      // Previous: Irgendwo vor NameIndex - 1 endete das bisherige Muster.
      Next[NameIndex] := (UpCase(AName[NameIndex]) = UpCase(APattern[PatternIndex])) and
        (Reached[NameIndex - 1] or (Previous and IsWordStart(AName, NameIndex)));
      Previous := Previous or Reached[NameIndex - 1];
    end;
    Reached := Next;
    Next := nil;
  end;
  Result := False;
  for NameIndex := 1 to Length(AName) do
    if Reached[NameIndex] then
      Exit(True);
end;

{ TAtlasCompletionMatcher }

class function TAtlasCompletionMatcher.IsWordStart(const AName: string; AIndex: Integer): Boolean;
begin
  Result := Atlas.Core.Completion.Matching.IsWordStart(AName, AIndex);
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
  else if MatchesWordStarts(APattern, AName) then
    Result := ScoreWordStarts
  else if AName.ToUpper.Contains(APattern.ToUpper) then
    Result := ScoreSubstring
  else if MatchesSubsequence(APattern, AName) then
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
