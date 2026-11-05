unit Atlas.Common.Index.Adapters.CacheDirectory;

// Cache-Ordner auf der Platte (#184, #492):
// - Ablage: <Wurzel>\Index\<IDE-Version>\<Projekt-Hash>\index-<Format>.atlasidx,
//   der Bibliotheks-Index getrennt unter <Wurzel>\Index\<IDE-Version>\Bibliothek\
//   <Hash>\index-<Format>.atlasidx. Die Wurzel ist %LOCALAPPDATA%\Atlas.
// - Die Formatversion im Dateinamen trennt Server verschiedener Atlas-Versionen:
//   Laufen etwa ein installierter und ein neuer Server nebeneinander, schrieben
//   sie sonst abwechselnd dieselbe Datei, und jeder verwarf beim nächsten Start
//   den Cache des anderen („Formatversion 27 statt 29“) und baute alles neu auf.
//   Caches ohne Format im Namen (index.atlasidx) zählen beim Aufräumen mit.
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
    CachePattern = '*.atlasidx';
    IndexFolder = 'Index';
    LibraryFolder = 'Bibliothek';
    /// <summary>Gemeinsame Caches der Suchpfad-Units (Speicher, Rückmeldung 01.11.2026).</summary>
    SearchFolder = 'Suchpfade';
    /// <summary>Ordnername ohne bekannte Delphi-Version.</summary>
    NoVersion = 'ohne-Delphi';
    LockExtension = '.lock';
    /// <summary>Herkunft eines Projekt-Caches (Projektdatei oder Arbeitsordner), neben der Cache-Datei.</summary>
    OriginFileName = 'projekt.txt';
    BuildPattern = 'build-*.json';
    /// <summary>Zuletzt berechnete Architekturstände (#1367): &lt;Wurzel&gt;\Architektur\&lt;Hash&gt;\architecture-last.json.
    /// </summary>
    ArchitectureFolder = 'Architektur';
    ArchitectureFileName = 'architecture-last.json';
    /// <summary>Marke der letzten Benutzung neben jedem Cache.</summary>
    UseMarkerFileName = 'benutzt.stamp';
  public
    /// <summary>Name der Cache-Datei mit der Formatversion (index-29.atlasidx), damit Server verschiedener
    /// Versionen sich die Caches nicht gegenseitig überschreiben.</summary>
    class function CacheFileName: string; static;
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
    /// <summary>Gemeinsamer Cache der Suchpfad-Units aller Projekte mit gleicher ASignature (Suchpfade, Defines,
    /// Include-Pfade), getrennt vom Projekt.</summary>
    class function SearchFileFor(const ARoot, AIdeVersion, ASignature: string): string; static;
    /// <summary>Datei des letzten IDE-Builds für den Arbeitsordner AWorkspace (#556), gleich für LSP- und
    /// MCP-Prozess; bewusst kein Index-Cache, damit das Aufräumen sie nicht erfasst.</summary>
    class function BuildFileFor(const ARoot, AWorkspace: string): string; static;
    /// <summary>Zuletzt berechneter Architekturstand (#1367) zum Umfang AScopeKey (Projekt bzw. Projektgruppe,
    /// TArchitectureRequest.ScopeKey), gleich für LSP- und MCP-Prozess; außerhalb von Index, damit das Aufräumen
    /// der Index-Caches ihn nicht erfasst.</summary>
    class function ArchitectureFileFor(const ARoot, AScopeKey: string): string; static;
    /// <summary>Sperrt ACacheFile; nil, wenn eine andere Instanz sie hält. Freigeben hebt die Sperre auf.
    /// Hält dieser Prozess die Sperre schon (anderes Projekt der Gruppe), gleich nil, ohne die Datei zu öffnen.
    /// </summary>
    class function TryLock(const ACacheFile: string): TStream; static;
    /// <summary>True, wenn eine andere Instanz oder dieser Prozess ACacheFile gesperrt hat. Eigene Sperren
    /// beantwortet der Prozess selbst (#1479).</summary>
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

uses
  System.IOUtils,
  System.StrUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Cache,
  Atlas.Common.Index.CacheHousekeeping;

class function TIndexCacheDirectory.CacheFileName: string;
begin
  Result := Format('index-%d.atlasidx', [TIndexCache.FormatVersion]);
end;

class function TIndexCacheDirectory.DefaultRoot: string;
begin
  Result := TPath.Combine(TPath.GetCachePath, 'Atlas');
end;

// FNV-1a rechnet modulo 2^64: die Überlaufprüfung ist nur hier aus, danach wie vorher (#972).
{$IFOPT Q+}{$DEFINE ATLAS_HASH_UEBERLAUF}{$Q-}{$ENDIF}
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
{$IFDEF ATLAS_HASH_UEBERLAUF}{$Q+}{$UNDEF ATLAS_HASH_UEBERLAUF}{$ENDIF}

function SafeFolderName(const AValue: string): string;
var
  Index: Integer;
begin
  Result := Trim(AValue);
  for Index := 1 to Length(Result) do
  begin
    if not CharInSet(Result[Index], ['0'..'9', 'A'..'Z', 'a'..'z', '.', '-', '_']) then
    begin
      Result[Index] := '_';
    end;
  end;
end;

class function TIndexCacheDirectory.VersionFolder(const ARoot, AIdeVersion: string): string;
var
  Name: string;
begin
  Name := SafeFolderName(AIdeVersion);
  if Name = '' then
  begin
    Name := NoVersion;
  end;
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

class function TIndexCacheDirectory.SearchFileFor(const ARoot, AIdeVersion, ASignature: string): string;
begin
  Result := TPath.Combine(TPath.Combine(TPath.Combine(VersionFolder(ARoot, AIdeVersion), SearchFolder),
    KeyHash(ASignature)), CacheFileName);
end;

class function TIndexCacheDirectory.BuildFileFor(const ARoot, AWorkspace: string): string;
var
  Key: string;
begin
  Key := AnsiUpperCase(ExcludeTrailingPathDelimiter(AWorkspace.Replace('/', '\')));
  Result := TPath.Combine(ARoot, Format('build-%.8x.json', [Cardinal(Key.GetHashCode)]));
end;

class function TIndexCacheDirectory.ArchitectureFileFor(const ARoot, AScopeKey: string): string;
begin
  Result := TPath.Combine(TPath.Combine(TPath.Combine(ARoot, ArchitectureFolder), KeyHash(AScopeKey)),
    ArchitectureFileName);
end;

type
  /// <summary>Sperrdateien, die dieser Prozess offen hält (#1479). Das Aufräumen fragt bei jedem Projektstart
  /// alle Caches ab, ob sie gesperrt sind; in einer Projektgruppe hält der eigene Prozess die Sperren der schon
  /// gestarteten Projekte. Die Probe über die Datei schlägt dann nur fehl, kostet aber: Free Pascal wartet unter
  /// Linux bei belegter Sperre, bevor es aufgibt (gemessen 14 von 17 s bis „bereit“ bei 18 Projekten).</summary>
  TIndexCacheHeldLocks = class
  strict private
    class var FLock: TObject;
    class var FFiles: TDictionary<string, Boolean>;
  public
    class constructor Create;
    class destructor Destroy;
    class function KeyOf(const ACacheFile: string): string; static;
    class function Held(const ACacheFile: string): Boolean; static;
    class procedure Add(const AKey: string); static;
    class procedure Remove(const AKey: string); static;
  end;

  /// <summary>Offene Sperrdatei; meldet sich in TIndexCacheHeldLocks an und beim Freigeben ab.</summary>
  TIndexCacheLockStream = class(TFileStream)
  strict private
    FKey: string;
  public
    constructor Create(const ACacheFile: string);
    destructor Destroy; override;
  end;

{ TIndexCacheHeldLocks }

class constructor TIndexCacheHeldLocks.Create;
begin
  FLock := TObject.Create;
  FFiles := TDictionary<string, Boolean>.Create;
end;

class destructor TIndexCacheHeldLocks.Destroy;
begin
  // Eine Sperre, die erst nach dieser Unit freigegeben wird, meldet sich dann ins Leere ab (Remove prüft nil).
  FreeAndNil(FFiles);
  FreeAndNil(FLock);
end;

class function TIndexCacheHeldLocks.KeyOf(const ACacheFile: string): string;
begin
  Result := AnsiUpperCase(ExpandFileName(ACacheFile));
end;

class function TIndexCacheHeldLocks.Held(const ACacheFile: string): Boolean;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := FFiles.ContainsKey(KeyOf(ACacheFile));
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

class procedure TIndexCacheHeldLocks.Add(const AKey: string);
begin
  System.TMonitor.Enter(FLock);
  try
    FFiles.AddOrSetValue(AKey, True);
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

class procedure TIndexCacheHeldLocks.Remove(const AKey: string);
begin
  if FLock = nil then
  begin
    Exit;
  end;
  System.TMonitor.Enter(FLock);
  try
    FFiles.Remove(AKey);
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

{ TIndexCacheLockStream }

constructor TIndexCacheLockStream.Create(const ACacheFile: string);
begin
  inherited Create(ACacheFile + TIndexCacheDirectory.LockExtension, fmCreate or fmShareExclusive);
  // Erst nach dem Öffnen anmelden: Scheitert es, gehört die Sperre einem anderen.
  FKey := TIndexCacheHeldLocks.KeyOf(ACacheFile);
  TIndexCacheHeldLocks.Add(FKey);
end;

destructor TIndexCacheLockStream.Destroy;
begin
  // Abmelden vor dem Schließen: Danach darf eine Probe die Datei wieder öffnen.
  if FKey <> '' then
  begin
    TIndexCacheHeldLocks.Remove(FKey);
  end;
  inherited;
end;

class function TIndexCacheDirectory.TryLock(const ACacheFile: string): TStream;
begin
  if TIndexCacheHeldLocks.Held(ACacheFile) then
  begin
    Exit(nil);
  end;
  try
    ForceDirectories(ExtractFileDir(ACacheFile));
    Result := TIndexCacheLockStream.Create(ACacheFile);
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
  begin
    Exit(False);
  end;
  if TIndexCacheHeldLocks.Held(ACacheFile) then
  begin
    Exit(True);
  end;
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
  begin
    Exit;
  end;
  Result := TDirectory.GetFiles(ARoot, TIndexCacheDirectory.LegacyPattern);
  Folder := TPath.Combine(ARoot, TIndexCacheDirectory.IndexFolder);
  if TDirectory.Exists(Folder) then
  begin
    Result := Result + TDirectory.GetFiles(Folder, TIndexCacheDirectory.CachePattern, TSearchOption.soAllDirectories);
  end;
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
  begin
    Exit;
  end;
  System.SysUtils.DeleteFile(AFileName + TIndexCacheDirectory.LockExtension);
  // Leeren Projektordner mitnehmen; der Versionsordner bleibt. Herkunft und Marke gehören auch einem Cache
  // anderen Formats im selben Ordner und bleiben, solange einer da ist.
  Folder := ExtractFileDir(AFileName);
  if Length(TDirectory.GetFiles(Folder, TIndexCacheDirectory.CachePattern)) > 0 then
  begin
    Exit;
  end;
  System.SysUtils.DeleteFile(TPath.Combine(Folder, TIndexCacheDirectory.OriginFileName));
  System.SysUtils.DeleteFile(TPath.Combine(Folder, TIndexCacheDirectory.UseMarkerFileName));
  try
    if TDirectory.Exists(Folder) and TDirectory.IsEmpty(Folder) then
    begin
      TDirectory.Delete(Folder);
    end;
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
  begin
    if RemoveCache(FileName) then
    begin
      Inc(Result);
    end;
  end;
end;

function IsLegacyCache(const ARoot, AFileName: string): Boolean;
begin
  Result := SameText(ExcludeTrailingPathDelimiter(ExtractFileDir(AFileName)), ExcludeTrailingPathDelimiter(ARoot));
end;

function IsLibraryCache(const AFileName: string): Boolean;
var
  mFolder: string;
begin
  // Gemeinsame Caches ohne Projekt als Herkunft: <Version>\Bibliothek\<Hash>\index-<Format>.atlasidx und
  // <Version>\Suchpfade\<Hash>\… (mehrere Projekte teilen sie).
  mFolder := ExtractFileName(ExtractFileDir(ExtractFileDir(AFileName)));
  Result := SameText(mFolder, TIndexCacheDirectory.LibraryFolder) or SameText(mFolder, TIndexCacheDirectory.SearchFolder);
end;

/// <summary>Projekt-Units eines Caches ohne projekt.txt (Caches vor dieser Änderung).</summary>
function ProjectUnitsOf(const ACacheFile: string): TArray<string>;
var
  Entry: TIndexCacheEntry;
begin
  Result := nil;
  try
    for Entry in TIndexCache.ReadEntries(TFile.ReadAllBytes(ACacheFile)) do
    begin
      if not Entry.Header.Library_ and (Entry.Header.FileName <> '') then
      begin
        Result := Result + [Entry.Header.FileName];
      end;
    end;
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
  begin
    Exit;
  end;
  Origin := TIndexCacheDirectory.ReadOrigin(ACacheFile);
  if Origin <> '' then
  begin
    Result := [Origin];
    Exit;
  end;
  Result := ProjectUnitsOf(ACacheFile);
  for Origin in Result do
  begin
    if FileExists(Origin) then
    begin
      // Nachtragen, damit der Cache beim nächsten Mal nicht wieder gelesen wird.
      TIndexCacheDirectory.WriteOrigin(ACacheFile, Origin);
      Break;
    end;
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
      begin
        Result := TJSONObject(Root).GetValue<string>('project', '');
      end;
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
  // Ohne Cache-Datei (kein Bibliotheks- oder Suchpfad-Cache) gibt es nichts zu vermerken; sonst entstünde die
  // Marke im aktuellen Ordner.
  if ACacheFile = '' then
  begin
    Exit;
  end;
  Marker := TPath.Combine(ExtractFileDir(ACacheFile), UseMarkerFileName);
  try
    ForceDirectories(ExtractFileDir(Marker));
    if FileExists(Marker) then
    begin
      TFile.SetLastWriteTime(Marker, Now);
    end
    else
    begin
      TFile.WriteAllText(Marker, '');
    end;
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
    begin
      Result := TFile.GetLastWriteTime(ACacheFile);
    end;
    Marker := TPath.Combine(ExtractFileDir(ACacheFile), UseMarkerFileName);
    if FileExists(Marker) then
    begin
      Used := TFile.GetLastWriteTime(Marker);
      if Used > Result then
      begin
        Result := Used;
      end;
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
  begin
    Exit;
  end;
  for FileName in TIndexCacheHousekeeping.SelectUnused(ListCaches(ARoot), AKeep, Now, AMaxAgeDays) do
  begin
    if RemoveCache(FileName) then
    begin
      Inc(Result);
    end;
  end;
end;

class function TIndexCacheDirectory.ReadOrigin(const ACacheFile: string): string;
var
  FileName: string;
begin
  Result := '';
  FileName := TPath.Combine(ExtractFileDir(ACacheFile), OriginFileName);
  try
    if FileExists(FileName) then
    begin
      Result := Trim(TFile.ReadAllText(FileName, TEncoding.UTF8));
    end;
  except
    on Exception do
      Result := '';
  end;
end;

class procedure TIndexCacheDirectory.WriteOrigin(const ACacheFile, AOrigin: string);
begin
  if (AOrigin = '') or SameText(ReadOrigin(ACacheFile), AOrigin) then
  begin
    Exit;
  end;
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
  begin
    Exit(True);
  end;
  // Fehlt das Laufwerk oder die Freigabe (USB-Platte, Netz), ist das Projekt nicht gelöscht, nur nicht da.
  Drive := ExtractFileDrive(APath);
  Result := (Drive <> '') and not DirectoryExists(IncludeTrailingPathDelimiter(Drive));
end;

/// <summary>Löscht die Build-Stände (build-*.json) in ARoot, deren Projekt es nicht mehr gibt; Anzahl.</summary>
function RemoveOrphanBuilds(const ARoot: string): Integer;
var
  mFileName, mProject: string;
begin
  Result := 0;
  if not TDirectory.Exists(ARoot) then
  begin
    Exit;
  end;
  for mFileName in TDirectory.GetFiles(ARoot, TIndexCacheDirectory.BuildPattern) do
  begin
    mProject := BuildProjectOf(mFileName);
    if (mProject <> '') and not TIndexCacheDirectory.OriginExists(mProject) and
      System.SysUtils.DeleteFile(mFileName) then
    begin
      Inc(Result);
    end;
  end;
end;

class function TIndexCacheDirectory.RemoveOrphans(const ARoot: string; const AKeep: TArray<string>): Integer;
var
  FileName: string;
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
        begin
          Inc(Result);
        end;
        Continue;
      end;
      if not Info.Locked then
      begin
        Info.Origins := OriginsOf(FileName);
      end;
      Infos.Add(Info);
    end;
    Exists :=
      function(APath: string): Boolean
      begin
        Result := TIndexCacheDirectory.OriginExists(APath);
      end;
    for FileName in TIndexCacheHousekeeping.SelectOrphans(Infos.ToArray, AKeep, Exists) do
    begin
      if RemoveCache(FileName) then
      begin
        Inc(Result);
      end;
    end;
  finally
    Infos.Free;
  end;
  Inc(Result, RemoveOrphanBuilds(ARoot));
end;

class function TIndexCacheDirectory.Clear(const ARoot: string): Integer;
var
  Info: TCacheFileInfo;
begin
  Result := 0;
  for Info in ListCaches(ARoot) do
  begin
    if not Info.Locked and RemoveCache(Info.FileName) then
    begin
      Inc(Result);
    end;
  end;
end;

class function TIndexCacheDirectory.Remove(const AFiles: TArray<string>): Integer;
var
  FileName: string;
begin
  Result := 0;
  for FileName in AFiles do
  begin
    if (FileName <> '') and FileExists(FileName) and not IsLocked(FileName) and RemoveCache(FileName) then
    begin
      Inc(Result);
    end;
  end;
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
  begin
    if (FileName <> '') and FileExists(FileName) then
    begin
      Inc(Result, TFile.GetSize(FileName));
    end;
  end;
end;

end.
