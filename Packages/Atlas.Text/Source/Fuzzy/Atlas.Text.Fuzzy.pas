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
  Current, Previous: Char;
begin
  if AIndex = 1 then
    Exit(True);
  Current := AName[AIndex];
  Previous := AName[AIndex - 1];
  if (Previous = '_') or (Previous = '.') then
    Exit((Current <> '_') and (Current <> '.'));
  if Current.IsUpper then
    Exit(Previous.IsLower or Previous.IsDigit or
      ((AIndex < Length(AName)) and AName[AIndex + 1].IsLower));
  if Current.IsDigit then
    Exit(not Previous.IsDigit);
  Result := Current.IsLower and Previous.IsDigit;
end;

class function TTextFuzzy.MatchesWordStarts(const APattern, AName: string): Boolean;
var
  PatternIndex, NameIndex: Integer;
begin
  PatternIndex := 1;
  for NameIndex := 1 to Length(AName) do
    if (PatternIndex <= Length(APattern)) and IsWordStart(AName, NameIndex) and
      (UpCase(AName[NameIndex]) = UpCase(APattern[PatternIndex])) then
      Inc(PatternIndex);
  Result := PatternIndex > Length(APattern);
end;

class function TTextFuzzy.MatchesBoundedSubsequence(const APattern, AName: string): Boolean;
var
  Reached, Next: TArray<Boolean>;
  PatternIndex, NameIndex: Integer;
  Previous: Boolean;
begin
  if APattern = '' then
    Exit(True);
  // Reached[i]: Das Muster bis zum aktuellen Zeichen endet passend bei AName[i].
  Reached := nil;
  SetLength(Reached, Length(AName) + 1);
  for NameIndex := 1 to Length(AName) do
    Reached[NameIndex] := IsWordStart(AName, NameIndex) and (UpCase(AName[NameIndex]) = UpCase(APattern[1]));
  for PatternIndex := 2 to Length(APattern) do
  begin
    Next := nil;
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
  end;
  Result := False;
  for NameIndex := 1 to Length(AName) do
    if Reached[NameIndex] then
      Exit(True);
end;

class function TTextFuzzy.EditDistance(const A, B: string; ALimit: Integer): Integer;
var
  Left, Right: string;
  Row, Next: TArray<Integer>;
  I, J, Best: Integer;
begin
  Left := LowerCase(A);
  Right := LowerCase(B);
  if Abs(Length(Left) - Length(Right)) > ALimit then
    Exit(ALimit + 1);
  SetLength(Row, Length(Right) + 1);
  SetLength(Next, Length(Right) + 1);
  for J := 0 to Length(Right) do
    Row[J] := J;
  for I := 1 to Length(Left) do
  begin
    Next[0] := I;
    Best := Next[0];
    for J := 1 to Length(Right) do
    begin
      Next[J] := Min(Min(Row[J] + 1, Next[J - 1] + 1), Row[J - 1] + Ord(Left[I] <> Right[J]));
      Best := Min(Best, Next[J]);
    end;
    if Best > ALimit then
      Exit(ALimit + 1);
    Row := Copy(Next);
  end;
  Result := Row[Length(Right)];
end;

class function TTextFuzzy.Closest(const AName: string; const ACandidates: TArray<string>): string;
var
  Candidate: string;
  Best, Value: Integer;
begin
  Result := '';
  Best := Min(3, (Length(AName) + 1) div 2);
  for Candidate in ACandidates do
  begin
    Value := EditDistance(AName, Candidate, Best);
    if Value = 0 then
      Exit('');
    if Value < Best then
    begin
      Best := Value;
      Result := Candidate;
    end;
  end;
end;

end.
