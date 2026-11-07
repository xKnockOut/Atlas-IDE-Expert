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
    cMaxEntries = 20000;
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
  mIndex: Integer;
begin
  Result := 2166136261;
  for mIndex := 1 to Length(AText) do
  begin
    Result := Result xor Ord(AText[mIndex]);
    // In 64 Bit gerechnet und abgeschnitten: kein Überlauf, auch mit Überlaufprüfung.
    Result := Cardinal((UInt64(Result) * 16777619) and $FFFFFFFF);
  end;
end;

class function TMetricsCollector.IsSource(const AFileName: string): Boolean;
var
  mExtension: string;
begin
  mExtension := LowerCase(ExtractFileExt(AFileName));
  Result := (mExtension = '.pas') or (mExtension = '.dpr') or (mExtension = '.dpk');
end;

class function TMetricsCollector.RelativePath(const ARoot, AFileName: string): string;
var
  mRoot, mPath: string;
begin
  mPath := StringReplace(AFileName, '\', '/', [rfReplaceAll]);
  mRoot := StringReplace(ARoot, '\', '/', [rfReplaceAll]);
  if (mRoot <> '') and (mRoot[Length(mRoot)] <> '/') then
  begin
    mRoot := mRoot + '/';
  end;
  if (mRoot <> '/') and (mRoot <> '') and SameText(Copy(mPath, 1, Length(mRoot)), mRoot) then
  begin
    Result := Copy(mPath, Length(mRoot) + 1, MaxInt);
  end
  else
  begin
    Result := AFileName;
  end;
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
  mKey: string;
  mEntry: TEntry;
  mSum: Cardinal;
begin
  mKey := UpperCase(AFileName);
  mSum := Checksum(AText);
  TMonitor.Enter(FLock);
  try
    if FCache.TryGetValue(mKey, mEntry) and (mEntry.Size = Length(AText)) and (mEntry.Checksum = mSum) then
    begin
      Exit(mEntry.Routines);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  Result := TMetricsCalculator.ForText(AText);
  mEntry.Size := Length(AText);
  mEntry.Checksum := mSum;
  mEntry.Routines := Result;
  TMonitor.Enter(FLock);
  try
    if (FCache.Count >= cMaxEntries) and not FCache.ContainsKey(mKey) then
    begin
      FCache.Clear;
    end;
    FCache.AddOrSetValue(mKey, mEntry);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TMetricsCollector.Collect(const AFiles: TArray<string>; const ARoot: string;
  const AReadText: TMetricsReadText): TArray<TFileMetrics>;
var
  mSeen: TDictionary<string, Boolean>;
  mList: TList<TFileMetrics>;
  mFileName, mText: string;
begin
  mSeen := TDictionary<string, Boolean>.Create;
  mList := TList<TFileMetrics>.Create;
  try
    for mFileName in AFiles do
    begin
      if not IsSource(mFileName) or mSeen.ContainsKey(UpperCase(mFileName)) then
      begin
        Continue;
      end;
      mSeen.Add(UpperCase(mFileName), True);
      if not Assigned(AReadText) or not AReadText(mFileName, mText) then
      begin
        Continue;
      end;
      mList.Add(TFileMetrics.Create(RelativePath(ARoot, mFileName), FileRoutines(mFileName, mText)));
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
    mSeen.Free;
  end;
end;

end.
