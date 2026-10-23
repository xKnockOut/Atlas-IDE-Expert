unit Atlas.Core.Search.Files;

// Atlas-Suche über mehrere Dateien (#893, search.multiFile), ohne VCL und
// Open Tools API:
// - Sources: Dateien der Bereiche „Offene Dateien“, „Projekt“ und
//   „Projektgruppe“, jede einmal (Groß-/Kleinschreibung egal), nur Quelltexte
//   (.pas, .dpr, .dpk, .inc, .dfm, .fmx). Ungespeicherte Puffer der IDE haben
//   Vorrang vor der Platte: Ihr Text kommt mit, die übrigen Dateien lädt Run.
// - Run: sucht Datei für Datei mit der Suche der Leiste (ganzer Text als
//   Bereich) und meldet jede Datei mit Treffern über AFound, sobald sie fertig
//   ist; ACancelled bricht zwischen zwei Dateien ab. Run läuft in der IDE in
//   einem eigenen Thread (Atlas.IDE.Search.FileSearch) und berührt dabei nur
//   seine Argumente. Binäre Dateien (#0 im Text, etwa binäre Formulare) und
//   nicht lesbare zählen als übersprungen.
// - NextLocation: F3/Umschalt+F3 über Dateien: nach dem letzten Treffer der
//   aktuellen Datei geht es mit dem ersten der nächsten Datei weiter, am Ende
//   wieder von vorn (Umlauf).
// Zeilen und Zeichen 0-basiert wie in Atlas.Core.Search.Matching.

interface

uses
  System.SysUtils,
  Atlas.Core.Search.Matching;

type
  TAtlasSearchSource = record
    FileName: string;
    /// <summary>Text aus dem Puffer der IDE; ohne HasText lädt Run die Datei.</summary>
    Text: string;
    HasText: Boolean;
    class function FromDisk(const AFileName: string): TAtlasSearchSource; static;
    class function FromBuffer(const AFileName, AText: string): TAtlasSearchSource; static;
  end;

  TAtlasFileHits = record
    FileName: string;
    /// <summary>Durchsuchter Text; vor dem Ersetzen wird geprüft, ob die Datei noch so aussieht.</summary>
    Text: string;
    Lines: TArray<string>;
    Hits: TArray<TAtlasSearchHit>;
  end;

  TAtlasSearchLoader = reference to function(const AFileName: string; out AText: string): Boolean;

  TAtlasFileSearchSummary = record
    Files: Integer;
    FilesWithHits: Integer;
    Hits: Integer;
    Skipped: Integer;
    Cancelled: Boolean;
  end;

  TAtlasFileSearch = class
  public
    class function IsSearchable(const AFileName: string): Boolean; static;
    /// <summary>Lädt eine Datei wie TAtlasIdeWorkspaceEdit.CurrentText für nicht geöffnete Dateien: Kodierung aus
    /// BOM bzw. "encoding" der nächsten atlas.json (#121). Aus jedem Thread aufrufbar.</summary>
    class function DiskLoader: TAtlasSearchLoader; static;
    /// <summary>AFiles einmal und nur Quelltexte; Puffer aus ABuffers ersetzen die Platte. Reihenfolge: aktive
    /// Datei AFirst zuerst, dann wie in AFiles.</summary>
    class function Sources(const AFiles: TArray<string>; const ABuffers: TArray<TAtlasSearchSource>;
      const AFirst: string): TArray<TAtlasSearchSource>; static;
    /// <summary>Treffer in einem Text (ganzer Text als Bereich).</summary>
    class function SearchText(const AFileName, AText: string; const AQuery: TAtlasSearchQuery): TAtlasFileHits;
      static;
    class function Run(const ASources: TArray<TAtlasSearchSource>; const AQuery: TAtlasSearchQuery;
      const ALoad: TAtlasSearchLoader; const ACancelled: TFunc<Boolean>;
      const AFound: TProc<TAtlasFileHits>): TAtlasFileSearchSummary; static;
    class function HitCount(const AResults: TArray<TAtlasFileHits>): Integer; static;
    class function IndexOfFile(const AResults: TArray<TAtlasFileHits>; const AFileName: string): Integer; static;
    /// <summary>Nächster (ABackward: voriger) Treffer ab AFrom in AFileName über alle Dateien. False ohne
    /// Treffer. Liegt AFileName nicht in AResults, beginnt es mit der ersten bzw. letzten Datei.</summary>
    class function NextLocation(const AResults: TArray<TAtlasFileHits>; const AFileName: string;
      const AFrom: TAtlasSearchPos; ABackward: Boolean; out AFileIndex, AHitIndex: Integer;
      out AWrapped: Boolean): Boolean; static;
  end;

implementation

uses
  Atlas.Text.Lines,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Files.EncodingDefault;

{ TAtlasSearchSource }

class function TAtlasSearchSource.FromDisk(const AFileName: string): TAtlasSearchSource;
begin
  Result.FileName := AFileName;
  Result.Text := '';
  Result.HasText := False;
end;

class function TAtlasSearchSource.FromBuffer(const AFileName, AText: string): TAtlasSearchSource;
begin
  Result.FileName := AFileName;
  Result.Text := AText;
  Result.HasText := True;
end;

{ TAtlasFileSearch }

class function TAtlasFileSearch.IsSearchable(const AFileName: string): Boolean;
const
  Extensions: array[0..5] of string = ('.pas', '.dpr', '.dpk', '.inc', '.dfm', '.fmx');
var
  Extension, Known: string;
begin
  Extension := LowerCase(ExtractFileExt(AFileName));
  for Known in Extensions do
    if Extension = Known then
      Exit(True);
  Result := False;
end;

class function TAtlasFileSearch.DiskLoader: TAtlasSearchLoader;
begin
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := '';
      Result := FileExists(AFileName);
      if Result then
        AText := TAtlasTextFile.Load(AFileName, TAtlasEncodingDefault.CodePageFor(AFileName)).Text;
    end;
end;

class function TAtlasFileSearch.Sources(const AFiles: TArray<string>; const ABuffers: TArray<TAtlasSearchSource>;
  const AFirst: string): TArray<TAtlasSearchSource>;
var
  Ordered, Seen: TArray<string>;
  FileName, Known: string;
  Buffer, Source: TAtlasSearchSource;
  Duplicate: Boolean;
begin
  Result := nil;
  // Die aktive Datei zuerst, aber nur, wenn sie zum Bereich gehört.
  Ordered := nil;
  for FileName in AFiles do
    if (AFirst <> '') and SameText(FileName, AFirst) then
      Ordered := [FileName];
  Ordered := Ordered + AFiles;
  Seen := nil;
  for FileName in Ordered do
  begin
    if (FileName = '') or not IsSearchable(FileName) then
      Continue;
    Duplicate := False;
    for Known in Seen do
      if SameText(Known, FileName) then
        Duplicate := True;
    if Duplicate then
      Continue;
    Seen := Seen + [FileName];
    Source := TAtlasSearchSource.FromDisk(FileName);
    for Buffer in ABuffers do
      if Buffer.HasText and SameText(Buffer.FileName, FileName) then
        Source := TAtlasSearchSource.FromBuffer(FileName, Buffer.Text);
    Result := Result + [Source];
  end;
end;

class function TAtlasFileSearch.SearchText(const AFileName, AText: string;
  const AQuery: TAtlasSearchQuery): TAtlasFileHits;
begin
  Result.FileName := AFileName;
  Result.Text := AText;
  Result.Lines := TTextLines.SplitLines(AText);
  Result.Hits := TAtlasTextSearch.FindAll(Result.Lines, AQuery.Text, AQuery.Options,
    TAtlasSearchArea.Whole(Result.Lines));
end;

class function TAtlasFileSearch.Run(const ASources: TArray<TAtlasSearchSource>; const AQuery: TAtlasSearchQuery;
  const ALoad: TAtlasSearchLoader; const ACancelled: TFunc<Boolean>;
  const AFound: TProc<TAtlasFileHits>): TAtlasFileSearchSummary;
var
  Source: TAtlasSearchSource;
  Text: string;
  Found: TAtlasFileHits;
begin
  Result := Default(TAtlasFileSearchSummary);
  for Source in ASources do
  begin
    if Assigned(ACancelled) and ACancelled() then
    begin
      Result.Cancelled := True;
      Exit;
    end;
    Text := Source.Text;
    if not Source.HasText then
      try
        if not Assigned(ALoad) or not ALoad(Source.FileName, Text) then
        begin
          Inc(Result.Skipped);
          Continue;
        end;
      except
        // Gesperrt oder gelöscht: weiter mit der nächsten Datei.
        on Exception do
        begin
          Inc(Result.Skipped);
          Continue;
        end;
      end;
    if Pos(#0, Text) > 0 then
    begin
      Inc(Result.Skipped);
      Continue;
    end;
    Inc(Result.Files);
    Found := SearchText(Source.FileName, Text, AQuery);
    if Length(Found.Hits) = 0 then
      Continue;
    Inc(Result.FilesWithHits);
    Inc(Result.Hits, Length(Found.Hits));
    if Assigned(AFound) then
      AFound(Found);
  end;
end;

class function TAtlasFileSearch.HitCount(const AResults: TArray<TAtlasFileHits>): Integer;
var
  Item: TAtlasFileHits;
begin
  Result := 0;
  for Item in AResults do
    Inc(Result, Length(Item.Hits));
end;

class function TAtlasFileSearch.IndexOfFile(const AResults: TArray<TAtlasFileHits>;
  const AFileName: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(AResults) do
    if SameText(AResults[Index].FileName, AFileName) then
      Exit(Index);
  Result := -1;
end;

class function TAtlasFileSearch.NextLocation(const AResults: TArray<TAtlasFileHits>; const AFileName: string;
  const AFrom: TAtlasSearchPos; ABackward: Boolean; out AFileIndex, AHitIndex: Integer;
  out AWrapped: Boolean): Boolean;
var
  Current, Step, Count, Index: Integer;
  Hits: TArray<TAtlasSearchHit>;
begin
  AFileIndex := -1;
  AHitIndex := -1;
  AWrapped := False;
  Count := Length(AResults);
  Result := HitCount(AResults) > 0;
  if not Result then
    Exit;
  Current := IndexOfFile(AResults, AFileName);
  if Current >= 0 then
  begin
    // Erst in der aktuellen Datei, ohne Umlauf.
    Hits := AResults[Current].Hits;
    if ABackward then
    begin
      for Index := High(Hits) downto 0 do
        if TAtlasSearchPos.Compare(Hits[Index].StartPos, AFrom) < 0 then
        begin
          AFileIndex := Current;
          AHitIndex := Index;
          Exit;
        end;
    end
    else
      for Index := 0 to High(Hits) do
        if TAtlasSearchPos.Compare(Hits[Index].StartPos, AFrom) >= 0 then
        begin
          AFileIndex := Current;
          AHitIndex := Index;
          Exit;
        end;
  end;
  // Dann die nächste bzw. vorige Datei mit Treffern; über das Ende hinaus von der anderen Seite.
  if ABackward then
    Step := -1
  else
    Step := 1;
  Index := Current;
  if Index < 0 then
  begin
    if ABackward then
      Index := Count
    else
      Index := -1;
  end;
  repeat
    Index := Index + Step;
    if Index >= Count then
    begin
      Index := 0;
      AWrapped := True;
    end
    else if Index < 0 then
    begin
      Index := Count - 1;
      AWrapped := True;
    end;
  until Length(AResults[Index].Hits) > 0;
  AFileIndex := Index;
  if ABackward then
    AHitIndex := High(AResults[Index].Hits)
  else
    AHitIndex := 0;
end;

end.
