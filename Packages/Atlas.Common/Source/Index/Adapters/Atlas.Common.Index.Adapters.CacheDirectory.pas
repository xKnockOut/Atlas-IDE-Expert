unit Atlas.Common.Index.Adapters.CacheDirectory;

// Cache-Ordner auf der Platte (#184, #492):
// - Ablage: <Wurzel>\Index\<IDE-Version>\<Projekt-Hash>\index.atlasidx, der
//   Bibliotheks-Index getrennt unter <Wurzel>\Index\<IDE-Version>\Bibliothek\
//   <Hash>\index.atlasidx. Die Wurzel ist %LOCALAPPDATA%\Atlas.
// - Sperre je Cache-Datei über "<cache>.lock", offen gehalten ohne Mitbenutzung.
//   Öffnen mehrere Serverinstanzen dasselbe Projekt, schreibt nur die erste den
//   Cache; die anderen lesen ihn nur.
// - Ein Name je Projektschlüssel, gleich für LSP- und MCP-Modus (#62).
// - Aufräumen auf eine Höchstgröße, älteste Caches zuerst; Caches im alten
//   Format (index-*.json direkt in der Wurzel) zählen mit und gehen zuerst.
// - Leeren auf Wunsch (Kommandozeile --clear-cache, Befehl „Index löschen“).

interface

uses
  System.SysUtils,
  System.Classes;

type
  TIndexCacheDirectory = class
  public const
    /// <summary>Caches bis Format 11 direkt in der Wurzel.</summary>
    LegacyPattern = 'index-*.json';
    CacheFileName = 'index.atlasidx';
    CachePattern = '*.atlasidx';
    IndexFolder = 'Index';
    LibraryFolder = 'Bibliothek';
    /// <summary>Ordnername ohne bekannte Delphi-Version.</summary>
    NoVersion = 'ohne-Delphi';
    LockExtension = '.lock';
  public
    /// <summary>Ordner der Caches unter dem Benutzerprofil (Windows: %LOCALAPPDATA%\Atlas).</summary>
    class function DefaultRoot: string; static;
    /// <summary>Kurzer, stabiler Hash (16 Hex-Zeichen, ohne Groß-/Kleinschreibung) eines Schlüssels.</summary>
    class function KeyHash(const AKey: string): string; static;
    /// <summary>Ordner für AIdeVersion (BDS-Version wie "37.0"; '' = ohne Installation).</summary>
    class function VersionFolder(const ARoot, AIdeVersion: string): string; static;
    /// <summary>Cache-Datei des Projekts zum Projektschlüssel (TIndexProjectFiles.Signature).
    /// Hängt nur an Version und Schlüssel, damit LSP- und MCP-Prozess denselben Cache teilen (#62).</summary>
    class function FileFor(const ARoot, AIdeVersion, ASignature: string): string; static;
    /// <summary>Gemeinsamer Bibliotheks-Cache (TIndexProjectFiles.LibrarySignature), getrennt vom Projekt.</summary>
    class function LibraryFileFor(const ARoot, AIdeVersion, ASignature: string): string; static;
    /// <summary>Datei des letzten IDE-Builds für den Arbeitsordner AWorkspace (#556), gleich für LSP- und
    /// MCP-Prozess; bewusst kein Index-Cache, damit das Aufräumen sie nicht erfasst.</summary>
    class function BuildFileFor(const ARoot, AWorkspace: string): string; static;
    /// <summary>Sperrt ACacheFile; nil, wenn eine andere Instanz sie hält. Freigeben hebt die Sperre auf.</summary>
    class function TryLock(const ACacheFile: string): TStream; static;
    /// <summary>True, wenn eine andere Instanz ACacheFile gesperrt hat.</summary>
    class function IsLocked(const ACacheFile: string): Boolean; static;
    /// <summary>Löscht die ältesten Caches über AMaxBytes; liefert die Anzahl.</summary>
    class function Cleanup(const ARoot: string; AMaxBytes: Int64; const AKeep: string): Integer; overload; static;
    /// <summary>Wie oben mit mehreren eigenen Caches (Projekt und Bibliothek, #616).</summary>
    class function Cleanup(const ARoot: string; AMaxBytes: Int64; const AKeep: TArray<string>): Integer; overload;
      static;
    /// <summary>Löscht alle nicht gesperrten Caches; liefert die Anzahl.</summary>
    class function Clear(const ARoot: string): Integer; static;
    /// <summary>Löscht die genannten Caches samt Sperrdatei, wenn keine andere Instanz sie hält.</summary>
    class function Remove(const AFiles: TArray<string>): Integer; static;
    /// <summary>Größe der vorhandenen Dateien in Byte.</summary>
    class function SizeOf(const AFiles: TArray<string>): Int64; static;
    /// <summary>Größe aller Index-Caches unter ARoot in Byte.</summary>
    class function TotalSize(const ARoot: string): Int64; static;
  end;

implementation

// Hashes rechnen modulo 2^64.
{$Q-}

uses
  System.IOUtils,
  Atlas.Common.Index.CacheHousekeeping;

class function TIndexCacheDirectory.DefaultRoot: string;
begin
  Result := TPath.Combine(TPath.GetCachePath, 'Atlas');
end;

class function TIndexCacheDirectory.KeyHash(const AKey: string): string;
var
  Key: string;
  Hash: UInt64;
  Index: Integer;
begin
  // FNV-1a mit 64 Bit über die UTF-16-Zeichen; GetHashCode ist nur 32 Bit und nicht über
  // Versionen hinweg zugesichert.
  Key := AnsiUpperCase(AKey);
  Hash := UInt64($CBF29CE484222325);
  for Index := 1 to Length(Key) do
  begin
    Hash := Hash xor Ord(Key[Index]);
    Hash := Hash * UInt64($100000001B3);
  end;
  Result := IntToHex(Int64(Hash), 16);
end;

function SafeFolderName(const AValue: string): string;
var
  Index: Integer;
begin
  Result := Trim(AValue);
  for Index := 1 to Length(Result) do
    if not CharInSet(Result[Index], ['0'..'9', 'A'..'Z', 'a'..'z', '.', '-', '_']) then
      Result[Index] := '_';
end;

class function TIndexCacheDirectory.VersionFolder(const ARoot, AIdeVersion: string): string;
var
  Name: string;
begin
  Name := SafeFolderName(AIdeVersion);
  if Name = '' then
    Name := NoVersion;
  Result := TPath.Combine(TPath.Combine(ARoot, IndexFolder), Name);
end;

class function TIndexCacheDirectory.FileFor(const ARoot, AIdeVersion, ASignature: string): string;
begin
  Result := TPath.Combine(TPath.Combine(VersionFolder(ARoot, AIdeVersion), KeyHash(ASignature)), CacheFileName);
end;

class function TIndexCacheDirectory.LibraryFileFor(const ARoot, AIdeVersion, ASignature: string): string;
begin
  Result := TPath.Combine(TPath.Combine(TPath.Combine(VersionFolder(ARoot, AIdeVersion), LibraryFolder),
    KeyHash(ASignature)), CacheFileName);
end;

class function TIndexCacheDirectory.BuildFileFor(const ARoot, AWorkspace: string): string;
var
  Key: string;
begin
  Key := AnsiUpperCase(ExcludeTrailingPathDelimiter(AWorkspace.Replace('/', '\')));
  Result := TPath.Combine(ARoot, Format('build-%.8x.json', [Cardinal(Key.GetHashCode)]));
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

function CacheFiles(const ARoot: string): TArray<string>;
var
  Folder: string;
begin
  Result := nil;
  if not TDirectory.Exists(ARoot) then
    Exit;
  Result := TDirectory.GetFiles(ARoot, TIndexCacheDirectory.LegacyPattern);
  Folder := TPath.Combine(ARoot, TIndexCacheDirectory.IndexFolder);
  if TDirectory.Exists(Folder) then
    Result := Result + TDirectory.GetFiles(Folder, TIndexCacheDirectory.CachePattern, TSearchOption.soAllDirectories);
end;

function ListCaches(const ARoot: string): TArray<TCacheFileInfo>;
var
  FileName: string;
  Info: TCacheFileInfo;
begin
  Result := nil;
  for FileName in CacheFiles(ARoot) do
  begin
    Info.FileName := FileName;
    Info.Size := TFile.GetSize(FileName);
    Info.LastWrite := TFile.GetLastWriteTime(FileName);
    Info.Locked := TIndexCacheDirectory.IsLocked(FileName);
    Result := Result + [Info];
  end;
end;

function RemoveCache(const AFileName: string): Boolean;
var
  Folder: string;
begin
  Result := System.SysUtils.DeleteFile(AFileName);
  if not Result then
    Exit;
  System.SysUtils.DeleteFile(AFileName + TIndexCacheDirectory.LockExtension);
  // Leeren Projektordner mitnehmen; der Versionsordner bleibt.
  Folder := ExtractFileDir(AFileName);
  try
    if TDirectory.Exists(Folder) and TDirectory.IsEmpty(Folder) then
      TDirectory.Delete(Folder);
  except
    on Exception do
      ;
  end;
end;

class function TIndexCacheDirectory.Cleanup(const ARoot: string; AMaxBytes: Int64; const AKeep: string): Integer;
begin
  Result := Cleanup(ARoot, AMaxBytes, TArray<string>.Create(AKeep));
end;

class function TIndexCacheDirectory.Cleanup(const ARoot: string; AMaxBytes: Int64;
  const AKeep: TArray<string>): Integer;
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

class function TIndexCacheDirectory.Remove(const AFiles: TArray<string>): Integer;
var
  FileName: string;
begin
  Result := 0;
  for FileName in AFiles do
    if (FileName <> '') and FileExists(FileName) and not IsLocked(FileName) and RemoveCache(FileName) then
      Inc(Result);
end;

class function TIndexCacheDirectory.TotalSize(const ARoot: string): Int64;
begin
  Result := SizeOf(CacheFiles(ARoot));
end;

class function TIndexCacheDirectory.SizeOf(const AFiles: TArray<string>): Int64;
var
  FileName: string;
begin
  Result := 0;
  for FileName in AFiles do
    if (FileName <> '') and FileExists(FileName) then
      Inc(Result, TFile.GetSize(FileName));
end;

end.
