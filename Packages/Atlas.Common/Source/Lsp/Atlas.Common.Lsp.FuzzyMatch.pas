unit Atlas.Common.Lsp.FuzzyMatch;

// Unscharfer Vergleich von Namen mit einer Suchanfrage, gemeinsam für die
// Symbolsuche (#39) und die Vervollständigung (#229).
//
// Treffer sind exakte Namen, Präfixe, Teilwörter und Teilfolgen (Zeichen in
// Reihenfolge). Bei Teilfolgen zählen Wortanfänge besonders: Großbuchstaben,
// Zeichen nach "_", "." oder Ziffern. So findet "TBB" TBButton und "GTH"
// GetTypeHierarchy. Groß- und Kleinschreibung spielt keine Rolle.
//
// Wortanfänge bestimmt TTextFuzzy aus Atlas.Text (ADR 0012). Die
// Vervollständigung nutzt CompletionScore: Teilfolgen gelten dort nur mit
// Wortgrenzen (TTextFuzzy.MatchesBoundedSubsequence), wie im Plugin, das die
// Liste beim Weitertippen selbst filtert. Sonst verschwänden Einträge, die der
// Server geliefert hat, beim nächsten Zeichen (D-05). Die Symbolsuche (Score)
// bleibt großzügiger.

interface

type
  TFuzzyMatch = class
  public const
    /// <summary>Punktzahl für keinen Treffer.</summary>
    NoMatch = -1;
  public
    /// <summary>Punktzahl von AName für AQuery, höher ist besser; NoMatch ohne Treffer.
    /// Exakt vor Präfix vor Teilwort vor Teilfolge.</summary>
    class function Score(const AName, AQuery: string): Integer; static;
    /// <summary>Wie Score, aber Teilfolgen nur mit Wortgrenzen (Regel des Plugins); für die
    /// Vervollständigung.</summary>
    class function CompletionScore(const AName, AQuery: string): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.Fuzzy;

const
  ExactScore = 4000;
  PrefixScore = 3000;
  SubstringScore = 2000;
  SubsequenceScore = 1000;

/// <summary>Teilfolge mit Bewertung; mit APreferWordStarts springt jedes Zeichen
/// ohne direkten Anschluss zum nächsten passenden Wortanfang.</summary>
function SubsequenceScoreOf(const AName, ALowerName, AQuery: string; APreferWordStarts: Boolean): Integer;
var
  QueryIndex, NameIndex, Candidate, Previous: Integer;
begin
  Result := SubsequenceScore;
  NameIndex := 1;
  Previous := 0;
  for QueryIndex := 1 to Length(AQuery) do
  begin
    Candidate := 0;
    // Direkter Anschluss an den vorigen Treffer hat Vorrang.
    if (Previous > 0) and (Previous < Length(ALowerName)) and (ALowerName[Previous + 1] = AQuery[QueryIndex]) then
      Candidate := Previous + 1
    else if APreferWordStarts then
    begin
      Candidate := NameIndex;
      while (Candidate <= Length(ALowerName)) and
        not ((ALowerName[Candidate] = AQuery[QueryIndex]) and TTextFuzzy.IsWordStart(AName, Candidate)) do
        Inc(Candidate);
      if Candidate > Length(ALowerName) then
        Candidate := 0;
    end;
    if Candidate = 0 then
    begin
      Candidate := NameIndex;
      while (Candidate <= Length(ALowerName)) and (ALowerName[Candidate] <> AQuery[QueryIndex]) do
        Inc(Candidate);
      if Candidate > Length(ALowerName) then
        Exit(TFuzzyMatch.NoMatch);
    end;
    if TTextFuzzy.IsWordStart(AName, Candidate) then
      Inc(Result, 10);
    if Candidate = Previous + 1 then
      Inc(Result, 5)
    else
      Dec(Result, Candidate - NameIndex);
    Previous := Candidate;
    NameIndex := Candidate + 1;
  end;
  // Kürzere Namen bei gleicher Güte zuerst.
  Dec(Result, Length(AName) - Length(AQuery));
  if Result <= TFuzzyMatch.NoMatch then
    Result := 0;
end;

{ TFuzzyMatch }

class function TFuzzyMatch.Score(const AName, AQuery: string): Integer;
var
  LowerName, Query: string;
  Found, Plain: Integer;
begin
  Query := LowerCase(AQuery);
  if Query = '' then
    Exit(NoMatch);
  LowerName := LowerCase(AName);
  Found := Pos(Query, LowerName);
  if Found = 1 then
  begin
    if Length(LowerName) = Length(Query) then
      Exit(ExactScore);
    Exit(PrefixScore - (Length(LowerName) - Length(Query)));
  end;
  if Found > 1 then
  begin
    Result := SubstringScore - Found;
    if TTextFuzzy.IsWordStart(AName, Found) then
      Inc(Result, 500);
    Exit;
  end;
  Result := SubsequenceScoreOf(AName, LowerName, Query, True);
  Plain := SubsequenceScoreOf(AName, LowerName, Query, False);
  if Plain > Result then
    Result := Plain;
  if Result >= SubstringScore then
    Result := SubstringScore - 1;
end;

class function TFuzzyMatch.CompletionScore(const AName, AQuery: string): Integer;
var
  LowerName, Query: string;
  Found: Integer;
begin
  Query := LowerCase(AQuery);
  if Query = '' then
    Exit(NoMatch);
  LowerName := LowerCase(AName);
  Found := Pos(Query, LowerName);
  // Präfix und Teilwort wie Score: Diese Treffer filtert auch das Plugin nicht weg.
  if Found > 0 then
    Exit(Score(AName, AQuery));
  if not TTextFuzzy.MatchesBoundedSubsequence(AQuery, AName) then
    Exit(NoMatch);
  Result := SubsequenceScoreOf(AName, LowerName, Query, True);
  if Result = NoMatch then
    Result := 0;
  if Result >= SubstringScore then
    Result := SubstringScore - 1;
end;

end.
