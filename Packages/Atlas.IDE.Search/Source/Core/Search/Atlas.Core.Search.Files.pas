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

  /// <summary>Fundstelle von NextLocation: Datei in den Ergebnissen, Treffer darin; Wrapped nach einem Umlauf.
  /// </summary>
  TAtlasFileLocation = record
    FileIndex: Integer;
    HitIndex: Integer;
    Wrapped: Boolean;
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
      const AFrom: TAtlasSearchPos; ABackward: Boolean; out ALocation: TAtlasFileLocation): Boolean; static;
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
  cExtensions: array[0..5] of string = ('.pas', '.dpr', '.dpk', '.inc', '.dfm', '.fmx');
var
  mExtension, mKnown: string;
begin
  mExtension := LowerCase(ExtractFileExt(AFileName));
  for mKnown in cExtensions do
  begin
    if mExtension = mKnown then
    begin
      Exit(True);
    end;
  end;
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
      begin
        AText := TAtlasTextFile.Load(AFileName, TAtlasEncodingDefault.CodePageFor(AFileName)).Text;
      end;
    end;
end;

/// <summary>Die aktive Datei zuerst, aber nur, wenn sie zum Bereich gehört; danach alle wie in AFiles.</summary>
function ActiveFirst(const AFiles: TArray<string>; const AFirst: string): TArray<string>;
var
  mFileName: string;
begin
  Result := nil;
  for mFileName in AFiles do
  begin
    if (AFirst <> '') and SameText(mFileName, AFirst) then
    begin
      Result := TArray<string>.Create(mFileName);
    end;
  end;
  Result := Result + AFiles;
end;

function ContainsText(const AList: TArray<string>; const AText: string): Boolean;
var
  mItem: string;
begin
  for mItem in AList do
  begin
    if SameText(mItem, AText) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Quelle der Datei: der Puffer aus ABuffers, wenn es einen mit Text gibt, sonst die Platte.</summary>
function SourceFor(const AFileName: string; const ABuffers: TArray<TAtlasSearchSource>): TAtlasSearchSource;
var
  mBuffer: TAtlasSearchSource;
begin
  Result := TAtlasSearchSource.FromDisk(AFileName);
  for mBuffer in ABuffers do
  begin
    if mBuffer.HasText and SameText(mBuffer.FileName, AFileName) then
    begin
      Result := TAtlasSearchSource.FromBuffer(AFileName, mBuffer.Text);
    end;
  end;
end;

class function TAtlasFileSearch.Sources(const AFiles: TArray<string>; const ABuffers: TArray<TAtlasSearchSource>;
  const AFirst: string): TArray<TAtlasSearchSource>;
var
  mSeen: TArray<string>;
  mFileName: string;
begin
  Result := nil;
  mSeen := nil;
  for mFileName in ActiveFirst(AFiles, AFirst) do
  begin
    if (mFileName <> '') and IsSearchable(mFileName) and not ContainsText(mSeen, mFileName) then
    begin
      mSeen := mSeen + [mFileName];
      Result := Result + [SourceFor(mFileName, ABuffers)];
    end;
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

/// <summary>Text der Quelle; False, wenn sie sich nicht laden lässt (gesperrt, gelöscht) oder binär ist (#0 im
/// Text, etwa ein binäres Formular).</summary>
function SourceText(const ASource: TAtlasSearchSource; const ALoad: TAtlasSearchLoader; out AText: string): Boolean;
begin
  AText := ASource.Text;
  Result := ASource.HasText;
  if not Result then
  begin
    try
      Result := Assigned(ALoad) and ALoad(ASource.FileName, AText);
    except
      // Gesperrt oder gelöscht: weiter mit der nächsten Datei.
      on Exception do
      begin
        Result := False;
      end;
    end;
  end;
  Result := Result and (Pos(#0, AText) = 0);
end;

class function TAtlasFileSearch.Run(const ASources: TArray<TAtlasSearchSource>; const AQuery: TAtlasSearchQuery;
  const ALoad: TAtlasSearchLoader; const ACancelled: TFunc<Boolean>;
  const AFound: TProc<TAtlasFileHits>): TAtlasFileSearchSummary;
var
  mSource: TAtlasSearchSource;
  mText: string;
  mFound: TAtlasFileHits;
begin
  Result := Default(TAtlasFileSearchSummary);
  for mSource in ASources do
  begin
    if Assigned(ACancelled) and ACancelled() then
    begin
      Result.Cancelled := True;
      Exit;
    end;
    if not SourceText(mSource, ALoad, mText) then
    begin
      Inc(Result.Skipped);
      Continue;
    end;
    Inc(Result.Files);
    mFound := SearchText(mSource.FileName, mText, AQuery);
    if Length(mFound.Hits) > 0 then
    begin
      Inc(Result.FilesWithHits);
      Inc(Result.Hits, Length(mFound.Hits));
      if Assigned(AFound) then
      begin
        AFound(mFound);
      end;
    end;
  end;
end;

class function TAtlasFileSearch.HitCount(const AResults: TArray<TAtlasFileHits>): Integer;
var
  mItem: TAtlasFileHits;
begin
  Result := 0;
  for mItem in AResults do
  begin
    Inc(Result, Length(mItem.Hits));
  end;
end;

class function TAtlasFileSearch.IndexOfFile(const AResults: TArray<TAtlasFileHits>;
  const AFileName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AResults) do
  begin
    if SameText(AResults[mIndex].FileName, AFileName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Nächste (ABackward: vorige) Datei mit Treffern nach ACurrent (-1: vor der ersten bzw. hinter der
/// letzten Datei); über das Ende hinaus von der anderen Seite mit AWrapped. Mindestens eine Datei muss Treffer
/// haben.</summary>
function NextFileWithHits(const AResults: TArray<TAtlasFileHits>; ACurrent: Integer; ABackward: Boolean;
  var AWrapped: Boolean): Integer;
var
  mStep, mCount: Integer;
begin
  mCount := Length(AResults);
  mStep := 1;
  Result := ACurrent;
  if ABackward then
  begin
    mStep := -1;
    if Result < 0 then
    begin
      Result := mCount;
    end;
  end;
  repeat
    Result := Result + mStep;
    if Result >= mCount then
    begin
      Result := 0;
      AWrapped := True;
    end
    else if Result < 0 then
    begin
      Result := mCount - 1;
      AWrapped := True;
    end;
  until Length(AResults[Result].Hits) > 0;
end;

class function TAtlasFileSearch.NextLocation(const AResults: TArray<TAtlasFileHits>; const AFileName: string;
  const AFrom: TAtlasSearchPos; ABackward: Boolean; out ALocation: TAtlasFileLocation): Boolean;
var
  mCurrent: Integer;
  mWrapped: Boolean;
begin
  ALocation := Default(TAtlasFileLocation);
  ALocation.FileIndex := -1;
  ALocation.HitIndex := -1;
  Result := HitCount(AResults) > 0;
  if not Result then
  begin
    Exit;
  end;
  mCurrent := IndexOfFile(AResults, AFileName);
  if mCurrent >= 0 then
  begin
    // Erst in der aktuellen Datei, ohne Umlauf.
    ALocation.HitIndex := TAtlasTextSearch.Next(AResults[mCurrent].Hits, AFrom, ABackward, mWrapped);
    if (ALocation.HitIndex >= 0) and not mWrapped then
    begin
      ALocation.FileIndex := mCurrent;
      Exit;
    end;
  end;
  // Dann die nächste bzw. vorige Datei mit Treffern.
  ALocation.FileIndex := NextFileWithHits(AResults, mCurrent, ABackward, ALocation.Wrapped);
  ALocation.HitIndex := 0;
  if ABackward then
  begin
    ALocation.HitIndex := High(AResults[ALocation.FileIndex].Hits);
  end;
end;

end.
