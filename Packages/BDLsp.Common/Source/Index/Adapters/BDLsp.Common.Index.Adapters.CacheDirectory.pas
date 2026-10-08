unit BDLsp.Common.Index.Adapters.CacheDirectory;

// Cache-Ordner auf der Platte (#184):
// - Sperre je Cache-Datei über "<cache>.lock", offen gehalten ohne Mitbenutzung.
//   Öffnen mehrere Serverinstanzen dasselbe Projekt, schreibt nur die erste den
//   Cache; die anderen lesen ihn nur.
// - Ein Name je Projektschlüssel, gleich für LSP- und MCP-Modus (#62).
// - Aufräumen auf eine Höchstgröße, älteste Caches zuerst.
// - Leeren auf Wunsch (Kommandozeile --clear-cache).

interface

uses
  System.SysUtils,
  System.Classes;

type
  TIndexCacheDirectory = class
  public const
    FilePattern = 'index-*.json';
    LockExtension = '.lock';
  public
    /// <summary>Ordner der Caches unter dem Benutzerprofil (Windows: %LOCALAPPDATA%).</summary>
    class function DefaultRoot: string; static;
    /// <summary>Cache-Datei zum Projektschlüssel (TIndexProjectFiles.Signature) unter ARoot.
    /// Hängt nur am Schlüssel, damit LSP- und MCP-Prozess denselben Cache teilen (#62).</summary>
    class function FileFor(const ARoot, ASignature: string): string; static;
    /// <summary>Sperrt ACacheFile; nil, wenn eine andere Instanz sie hält. Freigeben hebt die Sperre auf.</summary>
    class function TryLock(const ACacheFile: string): TStream; static;
    /// <summary>True, wenn eine andere Instanz ACacheFile gesperrt hat.</summary>
    class function IsLocked(const ACacheFile: string): Boolean; static;
    /// <summary>Löscht die ältesten Caches über AMaxBytes; liefert die Anzahl.</summary>
    class function Cleanup(const ARoot: string; AMaxBytes: Int64; const AKeep: string): Integer; static;
    /// <summary>Löscht alle nicht gesperrten Caches; liefert die Anzahl.</summary>
    class function Clear(const ARoot: string): Integer; static;
  end;

implementation

uses
  System.IOUtils,
  BDLsp.Common.Index.CacheHousekeeping;

class function TIndexCacheDirectory.DefaultRoot: string;
begin
  Result := TPath.Combine(TPath.GetCachePath, 'BetterDelphiLSP');
end;

class function TIndexCacheDirectory.FileFor(const ARoot, ASignature: string): string;
begin
  Result := TPath.Combine(ARoot, Format('index-%.8x.json', [Cardinal(ASignature.GetHashCode)]));
end;

class function TIndexCacheDirectory.TryLock(const ACacheFile: string): TStream;
begin
  try
    ForceDirectories(ExtractFileDir(ACacheFile));
    Result := TFileStream.Create(ACacheFile + LockExtension, fmCreate or fmShareExclusive);
  except
    on EStreamError do
      Result := nil;
    on EInOutError do
      Result := nil;
  end;
end;

class function TIndexCacheDirectory.IsLocked(const ACacheFile: string): Boolean;
var
  Lock: TStream;
begin
  if not FileExists(ACacheFile + LockExtension) then
    Exit(False);
  Lock := TryLock(ACacheFile);
  Result := Lock = nil;
  Lock.Free;
end;

function ListCaches(const ARoot: string): TArray<TCacheFileInfo>;
var
  FileName: string;
  Info: TCacheFileInfo;
begin
  Result := nil;
  if not TDirectory.Exists(ARoot) then
    Exit;
  for FileName in TDirectory.GetFiles(ARoot, TIndexCacheDirectory.FilePattern) do
  begin
    Info.FileName := FileName;
    Info.Size := TFile.GetSize(FileName);
    Info.LastWrite := TFile.GetLastWriteTime(FileName);
    Info.Locked := TIndexCacheDirectory.IsLocked(FileName);
    Result := Result + [Info];
  end;
end;

function RemoveCache(const AFileName: string): Boolean;
begin
  Result := System.SysUtils.DeleteFile(AFileName);
  if Result then
    System.SysUtils.DeleteFile(AFileName + TIndexCacheDirectory.LockExtension);
end;

class function TIndexCacheDirectory.Cleanup(const ARoot: string; AMaxBytes: Int64; const AKeep: string): Integer;
var
  FileName: string;
begin
  Result := 0;
  for FileName in TIndexCacheHousekeeping.SelectForRemoval(ListCaches(ARoot), AMaxBytes, AKeep) do
    if RemoveCache(FileName) then
      Inc(Result);
end;

class function TIndexCacheDirectory.Clear(const ARoot: string): Integer;
var
  Info: TCacheFileInfo;
begin
  Result := 0;
  for Info in ListCaches(ARoot) do
    if not Info.Locked and RemoveCache(Info.FileName) then
      Inc(Result);
end;

end.
