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
    class function Create(AGroup: TAtlasWelcomeSearchGroup; const ACaption, ADetail, ATarget: string): TAtlasWelcomeHit; static;
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
    GroupLimit = 4;
    /// <summary>Unter der Teilfolge (200): Tippfehler stehen hinten.</summary>
    ScoreTypo = 100;
    NoMatch = -1;
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
    Exit(True);
  if not CharInSet(AText[AIndex - 1], ['0'..'9', 'A'..'Z', 'a'..'z']) then
    Exit(CharInSet(AText[AIndex], ['0'..'9', 'A'..'Z', 'a'..'z']));
  Result := TAtlasCompletionMatcher.IsWordStart(AText, AIndex);
end;

class function TAtlasWelcomeSearch.Score(const APattern, AText: string): Integer;
var
  Pattern: string;
  Limit, Index, Distance, Best: Integer;
begin
  Pattern := Trim(APattern);
  if (Pattern = '') or (AText = '') then
    Exit(NoMatch);
  Result := TAtlasCompletionMatcher.Score(Pattern, AText);
  if Result <> TAtlasCompletionMatcher.NoMatch then
    Exit;
  Result := NoMatch;
  Limit := TAtlasCompletionMatcher.TypoLimit(Pattern);
  if Limit = 0 then
    Exit;
  Best := MaxInt;
  for Index := 1 to Length(AText) do
    if StartsWord(AText, Index) then
    begin
      Distance := TAtlasCompletionMatcher.TypoDistance(Pattern, Copy(AText, Index, MaxInt));
      if Distance < Best then
        Best := Distance;
    end;
  if Best <= Limit then
    Result := ScoreTypo - Best;
end;

class function TAtlasWelcomeSearch.ScoreHit(const APattern: string; const AHit: TAtlasWelcomeHit): Integer;
begin
  Result := Score(APattern, AHit.Caption);
  if AHit.Alias <> '' then
    Result := Max(Result, Score(APattern, AHit.Alias));
  // Der Server hat schon gefiltert, auch nach Container und Teilen, die hier nicht stehen.
  if AHit.Prefiltered and (Result = NoMatch) and (Trim(APattern) <> '') then
    Result := 0;
end;

class function TAtlasWelcomeSearch.Search(const APattern: string; const ACandidates: TArray<TAtlasWelcomeHit>;
  const ASymbolHint: string): TArray<TAtlasWelcomeSearchResult>;
begin
  Result := Search(APattern, ACandidates, ASymbolHint, GroupLimit);
end;

class function TAtlasWelcomeSearch.Search(const APattern: string; const ACandidates: TArray<TAtlasWelcomeHit>;
  const ASymbolHint: string; ALimit: Integer): TArray<TAtlasWelcomeSearchResult>;
var
  Group: TAtlasWelcomeSearchGroup;
  Found: TList<Integer>;
  Scores: TArray<Integer>;
  Candidates: TArray<TAtlasWelcomeHit>;
  Index: Integer;
  Entry: TAtlasWelcomeSearchResult;
begin
  Result := nil;
  Candidates := ACandidates;
  SetLength(Scores, Length(Candidates));
  for Index := 0 to High(Candidates) do
    Scores[Index] := ScoreHit(APattern, Candidates[Index]);
  Found := TList<Integer>.Create;
  try
    for Group := Low(TAtlasWelcomeSearchGroup) to High(TAtlasWelcomeSearchGroup) do
    begin
      Found.Clear;
      for Index := 0 to High(Candidates) do
        if (Candidates[Index].Group = Group) and (Scores[Index] <> NoMatch) then
          Found.Add(Index);
      Found.Sort(TComparer<Integer>.Construct(
        function(const A, B: Integer): Integer
        begin
          // Gefilterte Symbole behalten die Reihenfolge des Servers.
          if Candidates[A].Prefiltered and Candidates[B].Prefiltered then
            Result := 0
          else
            Result := Scores[B] - Scores[A];
          if Result = 0 then
            Result := A - B;
        end));
      Entry := Default(TAtlasWelcomeSearchResult);
      Entry.Group := Group;
      if (Group = TAtlasWelcomeSearchGroup.Symbols) and (ASymbolHint <> '') and (Found.Count = 0) then
        Entry.Hint := ASymbolHint;
      for Index := 0 to Min(Found.Count, ALimit) - 1 do
      begin
        Entry.Hits := Entry.Hits + [Candidates[Found[Index]]];
        Entry.Hits[High(Entry.Hits)].Score := Scores[Found[Index]];
      end;
      Entry.More := Max(0, Found.Count - ALimit);
      if (Length(Entry.Hits) > 0) or (Entry.Hint <> '') then
        Result := Result + [Entry];
    end;
  finally
    Found.Free;
  end;
end;

class function TAtlasWelcomeSearch.Flatten(const AResults: TArray<TAtlasWelcomeSearchResult>): TArray<TAtlasWelcomeHit>;
var
  Entry: TAtlasWelcomeSearchResult;
begin
  Result := nil;
  for Entry in AResults do
    Result := Result + Entry.Hits;
end;

function Row(AKind: TAtlasWelcomeRowKind; AGroup: TAtlasWelcomeSearchGroup; AIndex: Integer;
  const AText: string): TAtlasWelcomeSearchRow;
begin
  Result.Kind := AKind;
  Result.Group := AGroup;
  Result.Index := AIndex;
  Result.Text := AText;
end;

class function TAtlasWelcomeSearch.Rows(const AResults: TArray<TAtlasWelcomeSearchResult>): TArray<TAtlasWelcomeSearchRow>;
var
  Entry: TAtlasWelcomeSearchResult;
  Index, Flat: Integer;
begin
  Result := nil;
  Flat := 0;
  for Entry in AResults do
  begin
    Result := Result + [Row(TAtlasWelcomeRowKind.Group, Entry.Group, -1, '')];
    for Index := 0 to High(Entry.Hits) do
    begin
      Result := Result + [Row(TAtlasWelcomeRowKind.Hit, Entry.Group, Flat, '')];
      Inc(Flat);
    end;
    if Entry.Hint <> '' then
      Result := Result + [Row(TAtlasWelcomeRowKind.Hint, Entry.Group, -1, Entry.Hint)];
    if Entry.More > 0 then
      Result := Result + [Row(TAtlasWelcomeRowKind.More, Entry.Group, Entry.More, '')];
  end;
end;

class function TAtlasWelcomeSearch.IsProjectFile(const AFileName: string): Boolean;
var
  Extension: string;
begin
  Extension := LowerCase(ExtractFileExt(Trim(AFileName)));
  Result := (Extension = '.dproj') or (Extension = '.dpr') or (Extension = '.dpk') or (Extension = '.groupproj');
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
  Index: Integer;
begin
  // Ziffern am Ende: File_12 → 12; ohne Ziffern ans Ende.
  Index := Length(AName);
  while (Index > 0) and CharInSet(AName[Index], ['0'..'9']) do
    Dec(Index);
  Result := StrToIntDef(Copy(AName, Index + 1, MaxInt), MaxInt);
end;

class function TAtlasWelcomeSearch.RecentProjects(const AValues: TArray<TPair<string, string>>): TArray<string>;
var
  Values: TValueList;
  Pair: TPair<string, string>;
  Part, Path: string;
  Seen: TDictionary<string, Boolean>;
begin
  Result := nil;
  Values := TValueList.Create;
  Seen := TDictionary<string, Boolean>.Create;
  try
    Values.AddRange(AValues);
    Values.Sort(TValueComparer.Construct(
      function(const A, B: TPair<string, string>): Integer
      begin
        Result := CompareValue(NumberOf(A.Key), NumberOf(B.Key));
        if Result = 0 then
          Result := CompareText(A.Key, B.Key);
      end));
    for Pair in Values do
      for Part in Pair.Value.Split([',']) do
      begin
        // Delphi 13 setzt den Pfad in Hochkommas: TProjectGroup,'C:\P\A.groupproj',1.
        Path := AnsiDequotedStr(Trim(Part), '''');
        if IsProjectFile(Path) and IsAbsolute(Path) then
        begin
          if not Seen.ContainsKey(AnsiUpperCase(Path)) then
          begin
            Seen.Add(AnsiUpperCase(Path), True);
            Result := Result + [Path];
          end;
          Break;
        end;
      end;
  finally
    Seen.Free;
    Values.Free;
  end;
end;

end.
