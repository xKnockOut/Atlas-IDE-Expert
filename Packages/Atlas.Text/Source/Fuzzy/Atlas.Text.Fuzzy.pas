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
  end;

implementation

uses
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

end.
