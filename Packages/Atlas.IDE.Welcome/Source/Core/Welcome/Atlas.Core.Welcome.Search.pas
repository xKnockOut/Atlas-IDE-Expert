unit Atlas.Core.Welcome.Search;

// Suchfeld der Willkommensseite (#760), Teil ohne VCL und Open Tools API:
// Kandidaten aus vier Gruppen (Projekte, Dateien, Symbole, Befehle) werden
// unscharf bewertet, je Gruppe sortiert und auf höchstens vier Treffer
// begrenzt. Die Bewertung ist die der Vervollständigung (#409, #229: genauer
// Name, Anfang, Wortanfänge, Teilstring, Teilfolge) mit Tippfehler-Toleranz
// (#485), die hier auch ab jedem Wortanfang greift: „Wlecome“ trifft
// „Atlas.IDE.Expert.WelcomePage.pas“. Befehle passen zusätzlich über ihre
// Kennung („wel“ → „Atlas-Layout anwenden“ über Atlas.WelcomeApply).
// Symbole kommen vom Server, der schon unscharf gefiltert hat; sie behalten
// dessen Reihenfolge. Läuft kein Server, zeigt die Gruppe statt Treffern
// einen Hinweis.
// RecentProjects liest die Liste „Closed Projects“ der IDE: Werte File_0,
// File_1 … mit Text wie „TProject,C:\Pfad\Projekt.dproj,…“; gezählt wird
// nach der Nummer im Namen.

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
{$SCOPEDENUMS ON}
  TAtlasWelcomeSearchGroup = (Projects, Files, Symbols, Commands);
{$SCOPEDENUMS OFF}

  TAtlasWelcomeHit = record
    Group: TAtlasWelcomeSearchGroup;
    /// <summary>Angezeigter und bewerteter Text (Projektname, Dateiname, Symbol, Befehl).</summary>
    Caption: string;
    /// <summary>Gedimmt dahinter: Ordner, Projekt, Container, Kürzel.</summary>
    Detail: string;
    /// <summary>Weiterer Text zum Bewerten (Kennung eines Befehls); '' ohne.</summary>
    Alias: string;
    /// <summary>Projektdatei, Unit oder Befehlskennung.</summary>
    Target: string;
    /// <summary>Projekt, das vor der Datei geöffnet wird ('' = keins).</summary>
    Project: string;
    /// <summary>Stelle in der Datei, 0-basiert wie LSP; -1 ohne.</summary>
    Line: Integer;
    Character: Integer;
    /// <summary>Schon vom Server gefiltert (Symbole): passt immer, Reihenfolge bleibt.</summary>
    Prefiltered: Boolean;
    Score: Integer;
    class function Create(AGroup: TAtlasWelcomeSearchGroup; const ACaption, ADetail, ATarget: string): TAtlasWelcomeHit;
      static;
  end;

  TAtlasWelcomeSearchResult = record
    Group: TAtlasWelcomeSearchGroup;
    Hits: TArray<TAtlasWelcomeHit>;
    /// <summary>Statt Treffern (Symbole ohne Server); '' ohne.</summary>
    Hint: string;
    /// <summary>Weitere Treffer über der Grenze.</summary>
    More: Integer;
  end;

{$SCOPEDENUMS ON}
  /// <summary>Zeile der Ergebnisliste: Gruppenkopf, Treffer, Hinweis oder „weitere“.</summary>
  TAtlasWelcomeRowKind = (Group, Hit, Hint, More);
{$SCOPEDENUMS OFF}

  TAtlasWelcomeSearchRow = record
    Kind: TAtlasWelcomeRowKind;
    Group: TAtlasWelcomeSearchGroup;
    /// <summary>Treffer: Index in Flatten; More: Zahl weiterer Treffer; sonst -1.</summary>
    Index: Integer;
    /// <summary>Hinweistext (Hint).</summary>
    Text: string;
  end;

  TAtlasWelcomeSearch = class
  public const
    cGroupLimit = 4;
    /// <summary>Unter der Teilfolge (200): Tippfehler stehen hinten.</summary>
    cScoreTypo = 100;
    cNoMatch = -1;
  public
    /// <summary>Punktzahl von AText für APattern; NoMatch, wenn er nicht passt. Leeres Muster passt nie.</summary>
    class function Score(const APattern, AText: string): Integer; static;
    /// <summary>Punktzahl eines Treffers (Caption und Alias).</summary>
    class function ScoreHit(const APattern: string; const AHit: TAtlasWelcomeHit): Integer; static;
    /// <summary>Gruppen in fester Reihenfolge, je höchstens GroupLimit Treffer; Gruppen ohne Treffer fehlen,
    /// außer Symbole mit ASymbolHint.</summary>
    class function Search(const APattern: string; const ACandidates: TArray<TAtlasWelcomeHit>;
      const ASymbolHint: string): TArray<TAtlasWelcomeSearchResult>; overload; static;
    /// <summary>Wie oben mit eigener Grenze je Gruppe.</summary>
    class function Search(const APattern: string; const ACandidates: TArray<TAtlasWelcomeHit>;
      const ASymbolHint: string; ALimit: Integer): TArray<TAtlasWelcomeSearchResult>; overload; static;
    /// <summary>Alle Treffer in Anzeigereihenfolge (für Pfeiltasten und Enter).</summary>
    class function Flatten(const AResults: TArray<TAtlasWelcomeSearchResult>): TArray<TAtlasWelcomeHit>; static;
    /// <summary>Zeilen der Anzeige: je Gruppe Kopf, Treffer, Hinweis und „weitere“.</summary>
    class function Rows(const AResults: TArray<TAtlasWelcomeSearchResult>): TArray<TAtlasWelcomeSearchRow>; static;
    /// <summary>Projektdateien aus den Werten von „Closed Projects“ (Name, Text), zuletzt geöffnete zuerst,
    /// ohne Duplikate.</summary>
    class function RecentProjects(const AValues: TArray<TPair<string, string>>): TArray<string>; static;
    /// <summary>Ist AFileName eine Projektdatei (.dproj, .dpr, .dpk, .groupproj)?</summary>
    class function IsProjectFile(const AFileName: string): Boolean; static;
  end;

implementation

uses
  System.Math,
  System.Generics.Defaults,
  Atlas.Core.Completion.Matching;

{ TAtlasWelcomeHit }

class function TAtlasWelcomeHit.Create(AGroup: TAtlasWelcomeSearchGroup; const ACaption, ADetail,
  ATarget: string): TAtlasWelcomeHit;
begin
  Result := Default(TAtlasWelcomeHit);
  Result.Group := AGroup;
  Result.Caption := ACaption;
  Result.Detail := ADetail;
  Result.Target := ATarget;
  Result.Line := -1;
  Result.Character := -1;
end;

{ TAtlasWelcomeSearch }

function StartsWord(const AText: string; AIndex: Integer): Boolean;
begin
  // Nach einem Trennzeichen beginnt immer ein Wort ("Expert.Welcome", "Atlas-Layout").
  if AIndex = 1 then
  begin
    Exit(True);
  end;
  if not CharInSet(AText[AIndex - 1], ['0'..'9', 'A'..'Z', 'a'..'z']) then
  begin
    Exit(CharInSet(AText[AIndex], ['0'..'9', 'A'..'Z', 'a'..'z']));
  end;
  Result := TAtlasCompletionMatcher.IsWordStart(AText, AIndex);
end;

class function TAtlasWelcomeSearch.Score(const APattern, AText: string): Integer;
var
  mPattern: string;
  mLimit, mIndex, mDistance, mBest: Integer;
begin
  mPattern := Trim(APattern);
  if (mPattern = '') or (AText = '') then
  begin
    Exit(cNoMatch);
  end;
  Result := TAtlasCompletionMatcher.Score(mPattern, AText);
  if Result <> TAtlasCompletionMatcher.cNoMatch then
  begin
    Exit;
  end;
  Result := cNoMatch;
  mLimit := TAtlasCompletionMatcher.TypoLimit(mPattern);
  if mLimit = 0 then
  begin
    Exit;
  end;
  mBest := MaxInt;
  for mIndex := 1 to Length(AText) do
  begin
    if StartsWord(AText, mIndex) then
    begin
      mDistance := TAtlasCompletionMatcher.TypoDistance(mPattern, Copy(AText, mIndex, MaxInt));
      if mDistance < mBest then
      begin
        mBest := mDistance;
      end;
    end;
  end;
  if mBest <= mLimit then
  begin
    Result := cScoreTypo - mBest;
  end;
end;

class function TAtlasWelcomeSearch.ScoreHit(const APattern: string; const AHit: TAtlasWelcomeHit): Integer;
begin
  Result := Score(APattern, AHit.Caption);
  if AHit.Alias <> '' then
  begin
    Result := Max(Result, Score(APattern, AHit.Alias));
  end;
  // Der Server hat schon gefiltert, auch nach Container und Teilen, die hier nicht stehen.
  if AHit.Prefiltered and (Result = cNoMatch) and (Trim(APattern) <> '') then
  begin
    Result := 0;
  end;
end;

class function TAtlasWelcomeSearch.Search(const APattern: string; const ACandidates: TArray<TAtlasWelcomeHit>;
  const ASymbolHint: string): TArray<TAtlasWelcomeSearchResult>;
begin
  Result := Search(APattern, ACandidates, ASymbolHint, cGroupLimit);
end;

/// <summary>Reihenfolge der Treffer (Indizes in ACandidates): höhere Bewertung zuerst; gefilterte Symbole behalten
/// die Reihenfolge des Servers; bei Gleichstand der Index.</summary>
function HitOrder(const ACandidates: TArray<TAtlasWelcomeHit>; const AScores: TArray<Integer>): IComparer<Integer>;
begin
  Result := TComparer<Integer>.Construct(
    function(const A, B: Integer): Integer
    begin
      Result := 0;
      if not (ACandidates[A].Prefiltered and ACandidates[B].Prefiltered) then
      begin
        Result := AScores[B] - AScores[A];
      end;
      if Result = 0 then
      begin
        Result := A - B;
      end;
    end);
end;

/// <summary>Gruppe AGroup: höchstens ALimit Treffer mit Bewertung, der Rest als More; ohne Symbole ASymbolHint.
/// </summary>
function GroupEntry(AGroup: TAtlasWelcomeSearchGroup; const ACandidates: TArray<TAtlasWelcomeHit>;
  const AScores: TArray<Integer>; const ASymbolHint: string; ALimit: Integer): TAtlasWelcomeSearchResult;
var
  mFound: TList<Integer>;
  mIndex: Integer;
begin
  Result := Default(TAtlasWelcomeSearchResult);
  Result.Group := AGroup;
  mFound := TList<Integer>.Create;
  try
    for mIndex := 0 to High(ACandidates) do
    begin
      if (ACandidates[mIndex].Group = AGroup) and (AScores[mIndex] <> TAtlasWelcomeSearch.cNoMatch) then
      begin
        mFound.Add(mIndex);
      end;
    end;
    mFound.Sort(HitOrder(ACandidates, AScores));
    if (AGroup = TAtlasWelcomeSearchGroup.Symbols) and (ASymbolHint <> '') and (mFound.Count = 0) then
    begin
      Result.Hint := ASymbolHint;
    end;
    for mIndex := 0 to Min(mFound.Count, ALimit) - 1 do
    begin
      Result.Hits := Result.Hits + [ACandidates[mFound[mIndex]]];
      Result.Hits[High(Result.Hits)].Score := AScores[mFound[mIndex]];
    end;
    Result.More := Max(0, mFound.Count - ALimit);
  finally
    mFound.Free;
  end;
end;

class function TAtlasWelcomeSearch.Search(const APattern: string; const ACandidates: TArray<TAtlasWelcomeHit>;
  const ASymbolHint: string; ALimit: Integer): TArray<TAtlasWelcomeSearchResult>;
var
  mGroup: TAtlasWelcomeSearchGroup;
  mScores: TArray<Integer>;
  mIndex: Integer;
  mEntry: TAtlasWelcomeSearchResult;
begin
  Result := nil;
  SetLength(mScores, Length(ACandidates));
  for mIndex := 0 to High(ACandidates) do
  begin
    mScores[mIndex] := ScoreHit(APattern, ACandidates[mIndex]);
  end;
  for mGroup := Low(TAtlasWelcomeSearchGroup) to High(TAtlasWelcomeSearchGroup) do
  begin
    mEntry := GroupEntry(mGroup, ACandidates, mScores, ASymbolHint, ALimit);
    if (Length(mEntry.Hits) > 0) or (mEntry.Hint <> '') then
    begin
      Result := Result + [mEntry];
    end;
  end;
end;

class function TAtlasWelcomeSearch.Flatten(const AResults: TArray<TAtlasWelcomeSearchResult>): TArray<TAtlasWelcomeHit>;
var
  mEntry: TAtlasWelcomeSearchResult;
begin
  Result := nil;
  for mEntry in AResults do
  begin
    Result := Result + mEntry.Hits;
  end;
end;

function Row(AKind: TAtlasWelcomeRowKind; AGroup: TAtlasWelcomeSearchGroup; AIndex: Integer;
  const AText: string): TAtlasWelcomeSearchRow;
begin
  Result.Kind := AKind;
  Result.Group := AGroup;
  Result.Index := AIndex;
  Result.Text := AText;
end;

class function TAtlasWelcomeSearch.Rows(
  const AResults: TArray<TAtlasWelcomeSearchResult>): TArray<TAtlasWelcomeSearchRow>;
var
  mEntry: TAtlasWelcomeSearchResult;
  mIndex, mFlat: Integer;
begin
  Result := nil;
  mFlat := 0;
  for mEntry in AResults do
  begin
    Result := Result + [Row(TAtlasWelcomeRowKind.Group, mEntry.Group, -1, '')];
    for mIndex := 0 to High(mEntry.Hits) do
    begin
      Result := Result + [Row(TAtlasWelcomeRowKind.Hit, mEntry.Group, mFlat, '')];
      Inc(mFlat);
    end;
    if mEntry.Hint <> '' then
    begin
      Result := Result + [Row(TAtlasWelcomeRowKind.Hint, mEntry.Group, -1, mEntry.Hint)];
    end;
    if mEntry.More > 0 then
    begin
      Result := Result + [Row(TAtlasWelcomeRowKind.More, mEntry.Group, mEntry.More, '')];
    end;
  end;
end;

class function TAtlasWelcomeSearch.IsProjectFile(const AFileName: string): Boolean;
var
  mExtension: string;
begin
  mExtension := LowerCase(ExtractFileExt(Trim(AFileName)));
  Result := (mExtension = '.dproj') or (mExtension = '.dpr') or (mExtension = '.dpk') or (mExtension = '.groupproj');
end;

/// <summary>Absoluter Windows-Pfad (C:\… oder \\Server\…); relative Einträge taugen nicht zum Öffnen.</summary>
function IsAbsolute(const APath: string): Boolean;
begin
  Result := ((Length(APath) >= 3) and (APath[2] = ':') and CharInSet(APath[3], ['\', '/'])) or
    APath.StartsWith('\\');
end;

type
  TValueList = TList<TPair<string, string>>;
  TValueComparer = TComparer<TPair<string, string>>;

function NumberOf(const AName: string): Integer;
var
  mIndex: Integer;
begin
  // Ziffern am Ende: File_12 → 12; ohne Ziffern ans Ende.
  mIndex := Length(AName);
  while (mIndex > 0) and CharInSet(AName[mIndex], ['0'..'9']) do
  begin
    Dec(mIndex);
  end;
  Result := StrToIntDef(Copy(AName, mIndex + 1, MaxInt), MaxInt);
end;

/// <summary>Erster Teil von AValue (durch Komma getrennt), der ein absoluter Pfad einer Projektdatei ist; ''
/// ohne. Delphi 13 setzt den Pfad in Hochkommas: TProjectGroup,'C:\P\A.groupproj',1.</summary>
function ProjectPathIn(const AValue: string): string;
var
  mPart: string;
begin
  for mPart in AValue.Split([',']) do
  begin
    Result := AnsiDequotedStr(Trim(mPart), '''');
    if TAtlasWelcomeSearch.IsProjectFile(Result) and IsAbsolute(Result) then
    begin
      Exit;
    end;
  end;
  Result := '';
end;

class function TAtlasWelcomeSearch.RecentProjects(const AValues: TArray<TPair<string, string>>): TArray<string>;
var
  mValues: TValueList;
  mPair: TPair<string, string>;
  mPath: string;
  mSeen: TDictionary<string, Boolean>;
begin
  Result := nil;
  mValues := TValueList.Create;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    mValues.AddRange(AValues);
    mValues.Sort(TValueComparer.Construct(
      function(const A, B: TPair<string, string>): Integer
      begin
        Result := CompareValue(NumberOf(A.Key), NumberOf(B.Key));
        if Result = 0 then
        begin
          Result := CompareText(A.Key, B.Key);
        end;
      end));
    for mPair in mValues do
    begin
      mPath := ProjectPathIn(mPair.Value);
      if (mPath <> '') and not mSeen.ContainsKey(AnsiUpperCase(mPath)) then
      begin
        mSeen.Add(AnsiUpperCase(mPath), True);
        Result := Result + [mPath];
      end;
    end;
  finally
    mSeen.Free;
    mValues.Free;
  end;
end;

end.
