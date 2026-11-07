unit Atlas.Text.Fuzzy;

// Unscharfe Namensprädikate für die Vervollständigung (gemeinsam für Server
// und Plugin, ADR 0012). Die Punktzahlen bleiben je Seite (Server: Tausende
// Symbole, Plugin: Stufen mit Quell-Rang); geteilt werden die Regeln, ob ein
// Name überhaupt passt. Nur deren Abweichung lässt Einträge beim Weitertippen
// verschwinden (D-05).

interface

type
  TTextFuzzy = class
  public
    /// <summary>AName[AIndex] (1-basiert) beginnt ein Wort: erstes Zeichen; Zeichen nach "_" oder "."
    /// (außer "_" und "."); Großbuchstabe nach Klein- oder Ziffer oder vor einem Kleinbuchstaben
    /// ("S" in TStringList); Ziffer nach Nicht-Ziffer; Kleinbuchstabe nach Ziffer.</summary>
    class function IsWordStart(const AName: string; AIndex: Integer): Boolean; static;
    /// <summary>Jedes Musterzeichen trifft der Reihe nach einen Wortanfang (ohne Groß/Klein).</summary>
    class function MatchesWordStarts(const APattern, AName: string): Boolean; static;
    /// <summary>Teilfolge mit Wortgrenzen: das erste Zeichen auf einem Wortanfang, jedes weitere direkt
    /// anschließend oder auf einem Wortanfang ("stl" → TStringList, nicht "myLis" →
    /// ERROR_TOO_MANY_LINKS). Ohne Groß/Klein; leeres Muster passt.</summary>
    class function MatchesBoundedSubsequence(const APattern, AName: string): Boolean; static;
    /// <summary>Editierabstand nach Levenshtein ohne Groß-/Kleinschreibung; über ALimit hinaus ALimit + 1.</summary>
    class function EditDistance(const A, B: string; ALimit: Integer): Integer; static;
    /// <summary>Nächstliegender Name aus ACandidates für einen Tippfehler (#989, #997): höchstens zwei Zeichen
    /// anders und weniger als die Hälfte von AName, bei Gleichstand der erste; '' ohne passenden Namen oder
    /// wenn AName selbst vorkommt.</summary>
    class function Closest(const AName: string; const ACandidates: TArray<string>): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  System.Character;

{ TTextFuzzy }

class function TTextFuzzy.IsWordStart(const AName: string; AIndex: Integer): Boolean;
var
  mCurrent, mPrevious: Char;
begin
  if AIndex = 1 then
  begin
    Exit(True);
  end;
  mCurrent := AName[AIndex];
  mPrevious := AName[AIndex - 1];
  if (mPrevious = '_') or (mPrevious = '.') then
  begin
    Exit((mCurrent <> '_') and (mCurrent <> '.'));
  end;
  if mCurrent.IsUpper then
  begin
    Exit(mPrevious.IsLower or mPrevious.IsDigit or
      ((AIndex < Length(AName)) and AName[AIndex + 1].IsLower));
  end;
  if mCurrent.IsDigit then
  begin
    Exit(not mPrevious.IsDigit);
  end;
  Result := mCurrent.IsLower and mPrevious.IsDigit;
end;

class function TTextFuzzy.MatchesWordStarts(const APattern, AName: string): Boolean;
var
  mPatternIndex, mNameIndex: Integer;
begin
  mPatternIndex := 1;
  for mNameIndex := 1 to Length(AName) do
  begin
    if (mPatternIndex <= Length(APattern)) and IsWordStart(AName, mNameIndex) and
      (UpCase(AName[mNameIndex]) = UpCase(APattern[mPatternIndex])) then
    begin
      Inc(mPatternIndex);
    end;
  end;
  Result := mPatternIndex > Length(APattern);
end;

class function TTextFuzzy.MatchesBoundedSubsequence(const APattern, AName: string): Boolean;
var
  mReached, mNext: TArray<Boolean>;
  mPatternIndex, mNameIndex: Integer;
  mPrevious: Boolean;
begin
  if APattern = '' then
  begin
    Exit(True);
  end;
  // Reached[i]: Das Muster bis zum aktuellen Zeichen endet passend bei AName[i].
  mReached := nil;
  SetLength(mReached, Length(AName) + 1);
  for mNameIndex := 1 to Length(AName) do
  begin
    mReached[mNameIndex] := IsWordStart(AName, mNameIndex) and (UpCase(AName[mNameIndex]) = UpCase(APattern[1]));
  end;
  for mPatternIndex := 2 to Length(APattern) do
  begin
    mNext := nil;
    SetLength(mNext, Length(AName) + 1);
    mPrevious := False;
    for mNameIndex := 1 to Length(AName) do
    begin
      // Previous: Irgendwo vor NameIndex - 1 endete das bisherige Muster.
      mNext[mNameIndex] := (UpCase(AName[mNameIndex]) = UpCase(APattern[mPatternIndex])) and
        (mReached[mNameIndex - 1] or (mPrevious and IsWordStart(AName, mNameIndex)));
      mPrevious := mPrevious or mReached[mNameIndex - 1];
    end;
    mReached := mNext;
  end;
  Result := False;
  for mNameIndex := 1 to Length(AName) do
  begin
    if mReached[mNameIndex] then
    begin
      Exit(True);
    end;
  end;
end;

class function TTextFuzzy.EditDistance(const A, B: string; ALimit: Integer): Integer;
var
  mLeft, mRight: string;
  mRow, mNext: TArray<Integer>;
  I, J, mBest: Integer;
begin
  mLeft := LowerCase(A);
  mRight := LowerCase(B);
  if Abs(Length(mLeft) - Length(mRight)) > ALimit then
  begin
    Exit(ALimit + 1);
  end;
  SetLength(mRow, Length(mRight) + 1);
  SetLength(mNext, Length(mRight) + 1);
  for J := 0 to Length(mRight) do
  begin
    mRow[J] := J;
  end;
  for I := 1 to Length(mLeft) do
  begin
    mNext[0] := I;
    mBest := mNext[0];
    for J := 1 to Length(mRight) do
    begin
      mNext[J] := Min(Min(mRow[J] + 1, mNext[J - 1] + 1), mRow[J - 1] + Ord(mLeft[I] <> mRight[J]));
      mBest := Min(mBest, mNext[J]);
    end;
    if mBest > ALimit then
    begin
      Exit(ALimit + 1);
    end;
    mRow := Copy(mNext);
  end;
  Result := mRow[Length(mRight)];
end;

class function TTextFuzzy.Closest(const AName: string; const ACandidates: TArray<string>): string;
var
  mCandidate: string;
  mBest, mValue: Integer;
begin
  Result := '';
  mBest := Min(3, (Length(AName) + 1) div 2);
  for mCandidate in ACandidates do
  begin
    mValue := EditDistance(AName, mCandidate, mBest);
    if mValue = 0 then
    begin
      Exit('');
    end;
    if mValue < mBest then
    begin
      mBest := mValue;
      Result := mCandidate;
    end;
  end;
end;

end.
