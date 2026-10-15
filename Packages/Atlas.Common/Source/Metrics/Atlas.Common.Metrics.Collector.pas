unit Atlas.Common.Metrics.Collector;

// Kennzahlen mehrerer Dateien für Bericht, MCP und Projekt-Zusammenfassung
// (#66). Ein Zwischenspeicher je Datei (Prüfsumme und Länge des Textes)
// erspart nach einem Build das erneute Parsen unveränderter Units.
// Threadsicher: Server-Befehl und MCP können gleichzeitig fragen.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Metrics.Contract;

type
  /// <summary>Text einer Datei (geöffnetes Dokument oder Platte); False, wenn sie fehlt.</summary>
  TMetricsReadText = reference to function(const AFileName: string; out AText: string): Boolean;

  TMetricsCollector = class
  private type
    TEntry = record
      Size: Integer;
      Checksum: Cardinal;
      Routines: TArray<TRoutineMetrics>;
    end;
  private const
    /// <summary>Höchstzahl gemerkter Dateien; darüber beginnt der Speicher von vorn.</summary>
    MaxEntries = 20000;
  private
    FLock: TObject;
    FCache: TDictionary<string, TEntry>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Kennzahlen der Routinen in AText; unveränderter Text kommt aus dem Zwischenspeicher.</summary>
    function FileRoutines(const AFileName, AText: string): TArray<TRoutineMetrics>;
    /// <summary>Kennzahlen aller Quelltexte (.pas, .dpr, .dpk) aus AFiles, doppelte nur einmal,
    /// Pfade relativ zu ARoot. Unlesbare Dateien fehlen.</summary>
    function Collect(const AFiles: TArray<string>; const ARoot: string;
      const AReadText: TMetricsReadText): TArray<TFileMetrics>;
    /// <summary>Gemerkte Dateien (für Tests).</summary>
    function CachedCount: Integer;
    /// <summary>Pfad relativ zu ARoot mit „/“; außerhalb von ARoot der Pfad selbst.</summary>
    class function RelativePath(const ARoot, AFileName: string): string; static;
    /// <summary>True für .pas, .dpr und .dpk.</summary>
    class function IsSource(const AFileName: string): Boolean; static;
    /// <summary>Prüfsumme (FNV-1a über die UTF-16-Zeichen).</summary>
    class function Checksum(const AText: string): Cardinal; static;
  end;

implementation

uses
  Atlas.Common.Metrics.Calculator;

{ TMetricsCollector }

constructor TMetricsCollector.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FCache := TDictionary<string, TEntry>.Create;
end;

destructor TMetricsCollector.Destroy;
begin
  FCache.Free;
  FLock.Free;
  inherited Destroy;
end;

class function TMetricsCollector.Checksum(const AText: string): Cardinal;
var
  Index: Integer;
begin
  Result := 2166136261;
  for Index := 1 to Length(AText) do
  begin
    Result := Result xor Ord(AText[Index]);
    // In 64 Bit gerechnet und abgeschnitten: kein Überlauf, auch mit Überlaufprüfung.
    Result := Cardinal((UInt64(Result) * 16777619) and $FFFFFFFF);
  end;
end;

class function TMetricsCollector.IsSource(const AFileName: string): Boolean;
var
  Extension: string;
begin
  Extension := LowerCase(ExtractFileExt(AFileName));
  Result := (Extension = '.pas') or (Extension = '.dpr') or (Extension = '.dpk');
end;

class function TMetricsCollector.RelativePath(const ARoot, AFileName: string): string;
var
  Root, Path: string;
begin
  Path := StringReplace(AFileName, '\', '/', [rfReplaceAll]);
  Root := StringReplace(ARoot, '\', '/', [rfReplaceAll]);
  if (Root <> '') and (Root[Length(Root)] <> '/') then
    Root := Root + '/';
  if (Root <> '/') and (Root <> '') and SameText(Copy(Path, 1, Length(Root)), Root) then
    Result := Copy(Path, Length(Root) + 1, MaxInt)
  else
    Result := AFileName;
end;

function TMetricsCollector.CachedCount: Integer;
begin
  TMonitor.Enter(FLock);
  try
    Result := FCache.Count;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TMetricsCollector.FileRoutines(const AFileName, AText: string): TArray<TRoutineMetrics>;
var
  Key: string;
  Entry: TEntry;
  Sum: Cardinal;
begin
  Key := UpperCase(AFileName);
  Sum := Checksum(AText);
  TMonitor.Enter(FLock);
  try
    if FCache.TryGetValue(Key, Entry) and (Entry.Size = Length(AText)) and (Entry.Checksum = Sum) then
      Exit(Entry.Routines);
  finally
    TMonitor.Exit(FLock);
  end;
  Result := TMetricsCalculator.ForText(AText);
  Entry.Size := Length(AText);
  Entry.Checksum := Sum;
  Entry.Routines := Result;
  TMonitor.Enter(FLock);
  try
    if (FCache.Count >= MaxEntries) and not FCache.ContainsKey(Key) then
      FCache.Clear;
    FCache.AddOrSetValue(Key, Entry);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TMetricsCollector.Collect(const AFiles: TArray<string>; const ARoot: string;
  const AReadText: TMetricsReadText): TArray<TFileMetrics>;
var
  Seen: TDictionary<string, Boolean>;
  List: TList<TFileMetrics>;
  FileName, Text: string;
begin
  Seen := TDictionary<string, Boolean>.Create;
  List := TList<TFileMetrics>.Create;
  try
    for FileName in AFiles do
    begin
      if not IsSource(FileName) or Seen.ContainsKey(UpperCase(FileName)) then
        Continue;
      Seen.Add(UpperCase(FileName), True);
      if not Assigned(AReadText) or not AReadText(FileName, Text) then
        Continue;
      List.Add(TFileMetrics.Create(RelativePath(ARoot, FileName), FileRoutines(FileName, Text)));
    end;
    Result := List.ToArray;
  finally
    List.Free;
    Seen.Free;
  end;
end;

end.
