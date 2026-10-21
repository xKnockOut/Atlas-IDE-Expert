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
// - Verwaiste Caches löschen (index.removeOrphans): Neben jedem Projekt-Cache
//   steht in projekt.txt die Projektdatei (ohne Projektdatei der Arbeitsordner).
//   Fehlt sie, gelten die Projekt-Units aus dem Cache als Herkunft; die erste
//   noch vorhandene wird als projekt.txt nachgetragen, damit der Cache nur
//   einmal gelesen wird. Existiert nichts mehr davon, geht der Cache. Liegt die
//   Herkunft auf einem Laufwerk, das gerade fehlt (USB, Netz), bleibt er.
//   Caches im alten Format (index-*.json) liest keine Version mehr; sie gehen
//   immer. Ebenso die Datei des letzten Builds, wenn ihr Projekt fehlt.
// - Ungenutzte Caches löschen (index.cacheMaxAgeDays): Jedes Laden eines
//   Projekts erneuert benutzt.stamp neben Projekt- und Bibliotheks-Cache; als
//   letzte Benutzung gilt der jüngere Zeitpunkt von Cache und Marke. Dieselbe
//   Zeit ordnet auch das Aufräumen nach Größe.

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
    /// <summary>Herkunft eines Projekt-Caches (Projektdatei oder Arbeitsordner), neben index.atlasidx.</summary>
    OriginFileName = 'projekt.txt';
    BuildPattern = 'build-*.json';
    /// <summary>Marke der letzten Benutzung neben jedem Cache.</summary>
    UseMarkerFileName = 'benutzt.stamp';
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
    /// <summary>Löscht verwaiste Caches (Herkunft gelöscht) und Build-Dateien gelöschter Projekte; AKeep
    /// (eigene Caches) und gesperrte bleiben. Liefert die Anzahl.</summary>
    class function RemoveOrphans(const ARoot: string; const AKeep: TArray<string>): Integer; static;
    /// <summary>Schreibt die Herkunft (Projektdatei, sonst Arbeitsordner) neben ACacheFile, wenn sie sich ändert.</summary>
    class procedure WriteOrigin(const ACacheFile, AOrigin: string); static;
    /// <summary>Löscht Caches, die vor mehr als AMaxAgeDays Tagen zuletzt benutzt wurden (0 = keine); AKeep
    /// und gesperrte bleiben. Liefert die Anzahl.</summary>
    class function RemoveUnused(const ARoot: string; AMaxAgeDays: Integer; const AKeep: TArray<string>): Integer;
      static;
    /// <summary>Vermerkt die Benutzung von ACacheFile (benutzt.stamp).</summary>
    class procedure TouchUse(const ACacheFile: string); static;
    /// <summary>Letzte Benutzung: jüngerer Zeitpunkt von Cache und Marke.</summary>
    class function LastUse(const ACacheFile: string): TDateTime; static;
    /// <summary>Herkunft aus WriteOrigin; '' = unbekannt.</summary>
    class function ReadOrigin(const ACacheFile: string): string; static;
    /// <summary>True, wenn die Datei oder der Ordner existiert oder sein Laufwerk gerade fehlt (dann ist nichts
    /// entschieden).</summary>
    class function OriginExists(const APath: string): Boolean; static;
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
  System.StrUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Cache,
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
    Info.LastWrite := TIndexCacheDirectory.LastUse(FileName);
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
  System.SysUtils.DeleteFile(TPath.Combine(Folder, TIndexCacheDirectory.OriginFileName));
  System.SysUtils.DeleteFile(TPath.Combine(Folder, TIndexCacheDirectory.UseMarkerFileName));
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

function IsLegacyCache(const ARoot, AFileName: string): Boolean;
begin
  Result := SameText(ExcludeTrailingPathDelimiter(ExtractFileDir(AFileName)), ExcludeTrailingPathDelimiter(ARoot));
end;

function IsLibraryCache(const AFileName: string): Boolean;
begin
  // <Version>\Bibliothek\<Hash>\index.atlasidx
  Result := SameText(ExtractFileName(ExtractFileDir(ExtractFileDir(AFileName))), TIndexCacheDirectory.LibraryFolder);
end;

/// <summary>Projekt-Units eines Caches ohne projekt.txt (Caches vor dieser Änderung).</summary>
function ProjectUnitsOf(const ACacheFile: string): TArray<string>;
var
  Entry: TIndexCacheEntry;
begin
  Result := nil;
  try
    for Entry in TIndexCache.ReadEntries(TFile.ReadAllBytes(ACacheFile)) do
      if not Entry.Header.Library_ and (Entry.Header.FileName <> '') then
        Result := Result + [Entry.Header.FileName];
  except
    // Nicht lesbar (gesperrt, beschädigt): Herkunft unbekannt, der Cache bleibt.
    on Exception do
      Result := nil;
  end;
end;

function OriginsOf(const ACacheFile: string): TArray<string>;
var
  Origin: string;
begin
  Result := nil;
  if IsLibraryCache(ACacheFile) then
    Exit;
  Origin := TIndexCacheDirectory.ReadOrigin(ACacheFile);
  if Origin <> '' then
  begin
    Result := [Origin];
    Exit;
  end;
  Result := ProjectUnitsOf(ACacheFile);
  for Origin in Result do
    if FileExists(Origin) then
    begin
      // Nachtragen, damit der Cache beim nächsten Mal nicht wieder gelesen wird.
      TIndexCacheDirectory.WriteOrigin(ACacheFile, Origin);
      Break;
    end;
end;

/// <summary>Projekt einer Build-Datei (#556); '' = unbekannt.</summary>
function BuildProjectOf(const AFileName: string): string;
var
  Root: TJSONValue;
begin
  Result := '';
  try
    Root := TJSONObject.ParseJSONValue(TFile.ReadAllText(AFileName, TEncoding.UTF8));
    try
      if Root is TJSONObject then
        Result := TJSONObject(Root).GetValue<string>('project', '');
    finally
      Root.Free;
    end;
  except
    on Exception do
      Result := '';
  end;
end;

class procedure TIndexCacheDirectory.TouchUse(const ACacheFile: string);
var
  Marker: string;
begin
  Marker := TPath.Combine(ExtractFileDir(ACacheFile), UseMarkerFileName);
  try
    ForceDirectories(ExtractFileDir(Marker));
    if FileExists(Marker) then
      TFile.SetLastWriteTime(Marker, Now)
    else
      TFile.WriteAllText(Marker, '');
  except
    // Ohne Marke zählt die Zeit des Caches; schlimmstenfalls wird er früher neu aufgebaut.
    on Exception do
      ;
  end;
end;

class function TIndexCacheDirectory.LastUse(const ACacheFile: string): TDateTime;
var
  Marker: string;
  Used: TDateTime;
begin
  Result := 0;
  try
    if FileExists(ACacheFile) then
      Result := TFile.GetLastWriteTime(ACacheFile);
    Marker := TPath.Combine(ExtractFileDir(ACacheFile), UseMarkerFileName);
    if FileExists(Marker) then
    begin
      Used := TFile.GetLastWriteTime(Marker);
      if Used > Result then
        Result := Used;
    end;
  except
    on Exception do
      ;
  end;
end;

class function TIndexCacheDirectory.RemoveUnused(const ARoot: string; AMaxAgeDays: Integer;
  const AKeep: TArray<string>): Integer;
var
  FileName: string;
begin
  Result := 0;
  if AMaxAgeDays <= 0 then
    Exit;
  for FileName in TIndexCacheHousekeeping.SelectUnused(ListCaches(ARoot), AKeep, Now, AMaxAgeDays) do
    if RemoveCache(FileName) then
      Inc(Result);
end;

class function TIndexCacheDirectory.ReadOrigin(const ACacheFile: string): string;
var
  FileName: string;
begin
  Result := '';
  FileName := TPath.Combine(ExtractFileDir(ACacheFile), OriginFileName);
  try
    if FileExists(FileName) then
      Result := Trim(TFile.ReadAllText(FileName, TEncoding.UTF8));
  except
    on Exception do
      Result := '';
  end;
end;

class procedure TIndexCacheDirectory.WriteOrigin(const ACacheFile, AOrigin: string);
begin
  if (AOrigin = '') or SameText(ReadOrigin(ACacheFile), AOrigin) then
    Exit;
  try
    ForceDirectories(ExtractFileDir(ACacheFile));
    TFile.WriteAllText(TPath.Combine(ExtractFileDir(ACacheFile), OriginFileName), AOrigin, TEncoding.UTF8);
  except
    // Ohne Herkunft bleibt der Cache nur beim Aufräumen nach Größe.
    on Exception do
      ;
  end;
end;

class function TIndexCacheDirectory.OriginExists(const APath: string): Boolean;
var
  Drive: string;
begin
  if FileExists(APath) or DirectoryExists(APath) then
    Exit(True);
  // Fehlt das Laufwerk oder die Freigabe (USB-Platte, Netz), ist das Projekt nicht gelöscht, nur nicht da.
  Drive := ExtractFileDrive(APath);
  Result := (Drive <> '') and not DirectoryExists(IncludeTrailingPathDelimiter(Drive));
end;

class function TIndexCacheDirectory.RemoveOrphans(const ARoot: string; const AKeep: TArray<string>): Integer;
var
  FileName, Project: string;
  Infos: TList<TCacheFileInfo>;
  Info: TCacheFileInfo;
  Exists: TFunc<string, Boolean>;
begin
  Result := 0;
  Infos := TList<TCacheFileInfo>.Create;
  try
    for FileName in CacheFiles(ARoot) do
    begin
      Info := Default(TCacheFileInfo);
      Info.FileName := FileName;
      Info.Locked := IsLocked(FileName);
      if IsLegacyCache(ARoot, FileName) then
      begin
        // Format bis 11: liest keine Version mehr.
        if not Info.Locked and (IndexText(FileName, AKeep) < 0) and RemoveCache(FileName) then
          Inc(Result);
        Continue;
      end;
      if not Info.Locked then
        Info.Origins := OriginsOf(FileName);
      Infos.Add(Info);
    end;
    Exists :=
      function(APath: string): Boolean
      begin
        Result := TIndexCacheDirectory.OriginExists(APath);
      end;
    for FileName in TIndexCacheHousekeeping.SelectOrphans(Infos.ToArray, AKeep, Exists) do
      if RemoveCache(FileName) then
        Inc(Result);
  finally
    Infos.Free;
  end;
  if TDirectory.Exists(ARoot) then
    for FileName in TDirectory.GetFiles(ARoot, BuildPattern) do
    begin
      Project := BuildProjectOf(FileName);
      if (Project <> '') and not OriginExists(Project) and System.SysUtils.DeleteFile(FileName) then
        Inc(Result);
    end;
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
