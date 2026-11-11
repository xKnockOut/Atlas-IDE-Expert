unit Atlas.Common.Lsp.FuzzyMatch;

// Unscharfer Vergleich von Namen mit einer Suchanfrage, gemeinsam für die
// Symbolsuche (#39) und die Vervollständigung (#229).
//
// Treffer sind exakte Namen, Präfixe, Teilwörter und Teilfolgen (Zeichen in
// Reihenfolge). Bei Teilfolgen zählen Wortanfänge besonders: Großbuchstaben,
// Zeichen nach "_", "." oder Ziffern. So findet "TBB" TBButton und "GTH"
// GetTypeHierarchy. Groß- und Kleinschreibung spielt keine Rolle.
//
// Wortanfänge bestimmt TTextFuzzy aus Atlas.Text. Die
// Vervollständigung nutzt CompletionScore: Teilfolgen gelten dort nur mit
// Wortgrenzen (TTextFuzzy.MatchesBoundedSubsequence), wie im Plugin, das die
// Liste beim Weitertippen selbst filtert. Sonst verschwänden Einträge, die der
// Server geliefert hat, beim nächsten Zeichen. Die Symbolsuche (Score)
// bleibt großzügiger.

interface

type
  TFuzzyMatch = class
  public const
    /// <summary>Punktzahl für keinen Treffer.</summary>
    cNoMatch = -1;
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
  cExactScore = 4000;
  cPrefixScore = 3000;
  cSubstringScore = 2000;
  cSubsequenceScore = 1000;

/// <summary>Erste Stelle ab AFrom, an der AChar steht und ein Wort beginnt; 0 ohne Treffer.</summary>
function WordStartFrom(const AName, ALowerName: string; AChar: Char; AFrom: Integer): Integer;
begin
  Result := AFrom;
  while (Result <= Length(ALowerName)) and
    not ((ALowerName[Result] = AChar) and TTextFuzzy.IsWordStart(AName, Result)) do
  begin
    Inc(Result);
  end;
  if Result > Length(ALowerName) then
  begin
    Result := 0;
  end;
end;

/// <summary>Erste Stelle ab AFrom, an der AChar steht; 0 ohne Treffer.</summary>
function CharFrom(const ALowerName: string; AChar: Char; AFrom: Integer): Integer;
begin
  Result := AFrom;
  while (Result <= Length(ALowerName)) and (ALowerName[Result] <> AChar) do
  begin
    Inc(Result);
  end;
  if Result > Length(ALowerName) then
  begin
    Result := 0;
  end;
end;

/// <summary>Stelle für das nächste Zeichen AChar der Anfrage; 0 ohne Treffer. Direkter Anschluss
/// an APrevious hat Vorrang, mit APreferWordStarts danach der nächste passende Wortanfang.</summary>
function NextCandidate(const AName, ALowerName: string; AChar: Char; ANameIndex, APrevious: Integer;
  APreferWordStarts: Boolean): Integer;
begin
  Result := 0;
  if (APrevious > 0) and (APrevious < Length(ALowerName)) and (ALowerName[APrevious + 1] = AChar) then
  begin
    Result := APrevious + 1;
  end
  else if APreferWordStarts then
  begin
    Result := WordStartFrom(AName, ALowerName, AChar, ANameIndex);
  end;
  if Result = 0 then
  begin
    Result := CharFrom(ALowerName, AChar, ANameIndex);
  end;
end;

/// <summary>Teilfolge mit Bewertung; mit APreferWordStarts springt jedes Zeichen
/// ohne direkten Anschluss zum nächsten passenden Wortanfang.</summary>
function SubsequenceScoreOf(const AName, ALowerName, AQuery: string; APreferWordStarts: Boolean): Integer;
var
  mQueryIndex, mNameIndex, mCandidate, mPrevious: Integer;
begin
  Result := cSubsequenceScore;
  mNameIndex := 1;
  mPrevious := 0;
  for mQueryIndex := 1 to Length(AQuery) do
  begin
    mCandidate := NextCandidate(AName, ALowerName, AQuery[mQueryIndex], mNameIndex, mPrevious, APreferWordStarts);
    if mCandidate = 0 then
    begin
      Exit(TFuzzyMatch.cNoMatch);
    end;
    if TTextFuzzy.IsWordStart(AName, mCandidate) then
    begin
      Inc(Result, 10);
    end;
    if mCandidate = mPrevious + 1 then
    begin
      Inc(Result, 5);
    end
    else
    begin
      Dec(Result, mCandidate - mNameIndex);
    end;
    mPrevious := mCandidate;
    mNameIndex := mCandidate + 1;
  end;
  // Kürzere Namen bei gleicher Güte zuerst.
  Dec(Result, Length(AName) - Length(AQuery));
  if Result <= TFuzzyMatch.cNoMatch then
  begin
    Result := 0;
  end;
end;

{ TFuzzyMatch }

class function TFuzzyMatch.Score(const AName, AQuery: string): Integer;
var
  mLowerName, mQuery: string;
  mFound, mPlain: Integer;
begin
  mQuery := LowerCase(AQuery);
  if mQuery = '' then
  begin
    Exit(cNoMatch);
  end;
  mLowerName := LowerCase(AName);
  mFound := Pos(mQuery, mLowerName);
  if mFound = 1 then
  begin
    if Length(mLowerName) = Length(mQuery) then
    begin
      Exit(cExactScore);
    end;
    Exit(cPrefixScore - (Length(mLowerName) - Length(mQuery)));
  end;
  if mFound > 1 then
  begin
    Result := cSubstringScore - mFound;
    if TTextFuzzy.IsWordStart(AName, mFound) then
    begin
      Inc(Result, 500);
    end;
    Exit;
  end;
  Result := SubsequenceScoreOf(AName, mLowerName, mQuery, True);
  mPlain := SubsequenceScoreOf(AName, mLowerName, mQuery, False);
  if mPlain > Result then
  begin
    Result := mPlain;
  end;
  if Result >= cSubstringScore then
  begin
    Result := cSubstringScore - 1;
  end;
end;

class function TFuzzyMatch.CompletionScore(const AName, AQuery: string): Integer;
var
  mLowerName, mQuery: string;
  mFound: Integer;
begin
  mQuery := LowerCase(AQuery);
  if mQuery = '' then
  begin
    Exit(cNoMatch);
  end;
  mLowerName := LowerCase(AName);
  mFound := Pos(mQuery, mLowerName);
  // Präfix und Teilwort wie Score: Diese Treffer filtert auch das Plugin nicht weg.
  if mFound > 0 then
  begin
    Exit(Score(AName, AQuery));
  end;
  if not TTextFuzzy.MatchesBoundedSubsequence(AQuery, AName) then
  begin
    Exit(cNoMatch);
  end;
  Result := SubsequenceScoreOf(AName, mLowerName, mQuery, True);
  if Result = cNoMatch then
  begin
    Result := 0;
  end;
  if Result >= cSubstringScore then
  begin
    Result := cSubstringScore - 1;
  end;
end;

end.
