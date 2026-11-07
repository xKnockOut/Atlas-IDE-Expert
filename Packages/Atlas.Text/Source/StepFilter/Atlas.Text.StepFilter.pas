unit Atlas.Text.StepFilter;

// Schrittfilter beim Hineinspringen (#850), Teil für Server und Plugin:
// - Arten eigener Routinen, die F7 überspringt: getters, setters, trivial,
//   operators, emptyConstructors (Bedeutung in Atlas.Common.Lsp.StepFilter).
// - Muster Unit.Klasse.Methode mit * als Platzhalter für beliebig viele
//   Zeichen (auch Punkte), ohne Groß-/Kleinschreibung. Ein Muster darf vorn
//   Teile weglassen: TBasisForm.* passt auf Formulare.TBasisForm.Zeigen, *.Log*
//   auf Protokoll.TProtokoll.LogInfo, TKunde.GetName auf Kunden.TKunde.GetName.
//   Ab einem Punkt heißt: Kunde.GetName passt nicht auf Kunden.TKunde.GetName.
// - Listen: Arten kommagetrennt (debug.stepFilters.kinds), Muster durch ; oder
//   Zeilen getrennt (debug.stepFilters.patterns), weil Kommas in Typargumenten
//   vorkommen (TDictionary<K,V>.Add).

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  TStepFilterKind = (Getters, Setters, Trivial, Operators, EmptyConstructors);
{$SCOPEDENUMS OFF}

  TStepFilterKinds = set of TStepFilterKind;

  TStepFilterNames = class
  public const
    cKindNames: array[TStepFilterKind] of string = ('getters', 'setters', 'trivial', 'operators',
      'emptyConstructors');
    cAllKinds = [Low(TStepFilterKind)..High(TStepFilterKind)];
    cDefaultKinds = [TStepFilterKind.Getters, TStepFilterKind.Trivial];
    cPatternSeparator = ';';
    /// <summary>Höchstens so viele Muster; weitere fallen weg.</summary>
    cMaxPatterns = 200;
  private
    class function WildMatch(const APattern, AText: string): Boolean; static;
  public
    /// <summary>Kommagetrennte Arten; unbekannte fallen weg, '' = keine.</summary>
    class function ParseKinds(const AText: string): TStepFilterKinds; static;
    /// <summary>Arten in fester Reihenfolge, kommagetrennt.</summary>
    class function KindsText(AKinds: TStepFilterKinds): string; static;
    class function NormalizeKinds(const AText: string): string; static;
    /// <summary>Art zum Namen (ohne Groß-/Kleinschreibung); False bei unbekanntem.</summary>
    class function TryKind(const AName: string; out AKind: TStepFilterKind): Boolean; static;
    /// <summary>Nicht leer, ohne Leerraum, Steuerzeichen und Trenner, nicht nur aus * und Punkten.</summary>
    class function IsValidPattern(const APattern: string): Boolean; static;
    /// <summary>Muster aus dem Text: getrennt durch ; oder Zeilen, getrimmt, ungültige und doppelte (ohne
    /// Groß-/Kleinschreibung) fallen weg, höchstens MaxPatterns.</summary>
    class function ParsePatterns(const AText: string): TArray<string>; static;
    class function PatternsText(const APatterns: TArray<string>): string; static;
    class function NormalizePatterns(const AText: string): string; static;
    /// <summary>Passt APattern auf den qualifizierten Namen AName (ganz oder ab einem Punkt)?</summary>
    class function Matches(const APattern, AName: string): Boolean; static;
    /// <summary>Index des ersten passenden Musters; -1 ohne.</summary>
    class function MatchingPattern(const APatterns: TArray<string>; const AName: string): Integer; static;
    /// <summary>Index des Musters, das genau APattern ist (ohne Groß-/Kleinschreibung); -1 ohne.</summary>
    class function IndexOfPattern(const APatterns: TArray<string>; const APattern: string): Integer; static;
    /// <summary>APatterns mit APattern am Ende; unverändert, wenn es schon darin steht oder ungültig ist.</summary>
    class function WithPattern(const APatterns: TArray<string>; const APattern: string): TArray<string>; static;
    /// <summary>APatterns ohne APattern (ohne Groß-/Kleinschreibung).</summary>
    class function WithoutPattern(const APatterns: TArray<string>; const APattern: string): TArray<string>; static;
  end;

implementation

{ TStepFilterNames }

class function TStepFilterNames.TryKind(const AName: string; out AKind: TStepFilterKind): Boolean;
var
  mKind: TStepFilterKind;
begin
  for mKind := Low(TStepFilterKind) to High(TStepFilterKind) do
  begin
    if SameText(Trim(AName), cKindNames[mKind]) then
    begin
      AKind := mKind;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TStepFilterNames.ParseKinds(const AText: string): TStepFilterKinds;
var
  mPart: string;
  mKind: TStepFilterKind;
begin
  Result := [];
  for mPart in AText.Split([',', ';']) do
  begin
    if TryKind(mPart, mKind) then
    begin
      Include(Result, mKind);
    end;
  end;
end;

class function TStepFilterNames.KindsText(AKinds: TStepFilterKinds): string;
var
  mKind: TStepFilterKind;
begin
  Result := '';
  for mKind := Low(TStepFilterKind) to High(TStepFilterKind) do
  begin
    if mKind in AKinds then
    begin
      if Result <> '' then
      begin
        Result := Result + ',';
      end;
      Result := Result + cKindNames[mKind];
    end;
  end;
end;

class function TStepFilterNames.NormalizeKinds(const AText: string): string;
begin
  Result := KindsText(ParseKinds(AText));
end;

class function TStepFilterNames.IsValidPattern(const APattern: string): Boolean;
var
  mChar: Char;
  mOnlyWild: Boolean;
begin
  Result := False;
  if APattern = '' then
  begin
    Exit;
  end;
  mOnlyWild := True;
  for mChar in APattern do
  begin
    if (mChar <= ' ') or (mChar = cPatternSeparator) or (mChar = '''') or (mChar = '"') then
    begin
      Exit;
    end;
    if (mChar <> '*') and (mChar <> '.') then
    begin
      mOnlyWild := False;
    end;
  end;
  Result := not mOnlyWild;
end;

class function TStepFilterNames.ParsePatterns(const AText: string): TArray<string>;
var
  mPart, mPattern: string;
begin
  Result := nil;
  for mPart in AText.Replace(#13, cPatternSeparator).Replace(#10, cPatternSeparator).Split([cPatternSeparator]) do
  begin
    mPattern := Trim(mPart);
    if Length(Result) >= cMaxPatterns then
    begin
      Break;
    end;
    if IsValidPattern(mPattern) and (IndexOfPattern(Result, mPattern) < 0) then
    begin
      Result := Result + [mPattern];
    end;
  end;
end;

class function TStepFilterNames.PatternsText(const APatterns: TArray<string>): string;
begin
  Result := string.Join(cPatternSeparator, ParsePatterns(string.Join(cPatternSeparator, APatterns)));
end;

class function TStepFilterNames.NormalizePatterns(const AText: string): string;
begin
  Result := string.Join(cPatternSeparator, ParsePatterns(AText));
end;

class function TStepFilterNames.WildMatch(const APattern, AText: string): Boolean;
var
  mPattern, mText: Integer;
  mStar, mMark: Integer;
begin
  // Nur * als Platzhalter: Bei einem Fehlschlag springt der Vergleich hinter den letzten * zurück.
  mPattern := 1;
  mText := 1;
  mStar := 0;
  mMark := 0;
  while mText <= Length(AText) do
  begin
    if (mPattern <= Length(APattern)) and (APattern[mPattern] = '*') then
    begin
      mStar := mPattern;
      mMark := mText;
      Inc(mPattern);
    end
    else if (mPattern <= Length(APattern)) and (APattern[mPattern] = AText[mText]) then
    begin
      Inc(mPattern);
      Inc(mText);
    end
    else if mStar > 0 then
    begin
      mPattern := mStar + 1;
      Inc(mMark);
      mText := mMark;
    end
    else
    begin
      Exit(False);
    end;
  end;
  while (mPattern <= Length(APattern)) and (APattern[mPattern] = '*') do
  begin
    Inc(mPattern);
  end;
  Result := mPattern > Length(APattern);
end;

class function TStepFilterNames.Matches(const APattern, AName: string): Boolean;
var
  mPattern, mName: string;
  mIndex: Integer;
begin
  Result := False;
  mPattern := UpperCase(Trim(APattern));
  mName := UpperCase(Trim(AName));
  if not IsValidPattern(mPattern) or (mName = '') then
  begin
    Exit;
  end;
  if WildMatch(mPattern, mName) then
  begin
    Exit(True);
  end;
  // Vorn weggelassene Teile: ab jedem Punkt des Namens neu.
  for mIndex := 1 to Length(mName) - 1 do
  begin
    if (mName[mIndex] = '.') and WildMatch(mPattern, Copy(mName, mIndex + 1, MaxInt)) then
    begin
      Exit(True);
    end;
  end;
end;

class function TStepFilterNames.MatchingPattern(const APatterns: TArray<string>; const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(APatterns) do
  begin
    if Matches(APatterns[mIndex], AName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TStepFilterNames.IndexOfPattern(const APatterns: TArray<string>; const APattern: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(APatterns) do
  begin
    if SameText(APatterns[mIndex], Trim(APattern)) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TStepFilterNames.WithPattern(const APatterns: TArray<string>;
  const APattern: string): TArray<string>;
begin
  Result := Copy(APatterns);
  if IsValidPattern(Trim(APattern)) and (IndexOfPattern(Result, APattern) < 0) and
    (Length(Result) < cMaxPatterns) then
  begin
    Result := Result + [Trim(APattern)];
  end;
end;

class function TStepFilterNames.WithoutPattern(const APatterns: TArray<string>;
  const APattern: string): TArray<string>;
var
  mItem: string;
begin
  Result := nil;
  for mItem in APatterns do
  begin
    if not SameText(mItem, Trim(APattern)) then
    begin
      Result := Result + [mItem];
    end;
  end;
end;

end.
