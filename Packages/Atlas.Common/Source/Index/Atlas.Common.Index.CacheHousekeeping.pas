unit Atlas.Common.Index.CacheHousekeeping;

// Aufräumregeln für den Cache-Ordner (#184): Der Ordner wird auf eine
// Höchstgröße begrenzt, die ältesten Caches gehen zuerst. Die eigenen Caches
// (Projekt und gemeinsame Bibliothek, #616) und gesperrte Caches anderer
// Instanzen bleiben stehen.
// Verwaiste Caches (index.removeOrphans): Caches, von deren Herkunft (Projektdatei,
// ersatzweise die Projekt-Units im Cache) nichts mehr existiert, etwa nach dem
// Löschen eines Branch-Ordners. Ohne bekannte Herkunft bleibt ein Cache stehen.
// Ungenutzte Caches (index.cacheMaxAgeDays): zuletzt vor mehr als n Tagen benutzt.
// LastWrite ist dafür die letzte Benutzung, nicht nur der letzte Schreibvorgang.
// Reine Logik; die Plattenzugriffe liegen in Index.Adapters.CacheDirectory.

interface

uses
  System.SysUtils;

type
  TCacheFileInfo = record
    FileName: string;
    Size: Int64;
    /// <summary>Letzte Benutzung (Schreiben des Caches oder Laden des Projekts).</summary>
    LastWrite: TDateTime;
    /// <summary>Eine andere Serverinstanz arbeitet mit diesem Cache.</summary>
    Locked: Boolean;
    /// <summary>Dateien, deren Existenz zeigt, dass das Projekt noch da ist (Projektdatei oder Projekt-Units);
    /// leer = Herkunft unbekannt.</summary>
    Origins: TArray<string>;
  end;

  TIndexCacheHousekeeping = class
  public const
    /// <summary>Höchstgröße des Cache-Ordners.</summary>
    cDefaultMaxBytes = Int64(256) * 1024 * 1024;
  public
    /// <summary>
    /// Dateien, die gelöscht werden müssen, damit AFiles in AMaxBytes passt.
    /// AKeep (eigener Cache) und gesperrte Dateien werden nie gewählt.
    /// </summary>
    class function SelectForRemoval(const AFiles: TArray<TCacheFileInfo>; AMaxBytes: Int64;
      const AKeep: string): TArray<string>; overload; static;
    /// <summary>Wie oben mit mehreren eigenen Caches (#616): Der Bibliotheks-Cache (#492) ist nicht gesperrt
    /// und wurde sonst bei jedem Start gelöscht, sobald der Ordner über der Höchstgröße lag.</summary>
    class function SelectForRemoval(const AFiles: TArray<TCacheFileInfo>; AMaxBytes: Int64;
      const AKeep: TArray<string>): TArray<string>; overload; static;
    /// <summary>Caches, von deren Herkunft keine Datei mehr existiert (AExists). AKeep, gesperrte Caches und
    /// Caches ohne Herkunft werden nie gewählt.</summary>
    class function SelectOrphans(const AFiles: TArray<TCacheFileInfo>; const AKeep: TArray<string>;
      const AExists: TFunc<string, Boolean>): TArray<string>; static;
    /// <summary>Caches, die vor mehr als AMaxAgeDays Tagen (gezählt ab ANow) zuletzt benutzt wurden;
    /// AMaxAgeDays &lt;= 0 = keine. AKeep und gesperrte Caches werden nie gewählt.</summary>
    class function SelectUnused(const AFiles: TArray<TCacheFileInfo>; const AKeep: TArray<string>;
      ANow: TDateTime; AMaxAgeDays: Integer): TArray<string>; static;
    /// <summary>Höchstgröße aus der Einstellung index.cacheMaxMb; 0 = ohne Grenze.</summary>
    class function MaxBytesOf(AMaxMb: Integer): Int64; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults;

function CompareOldestFirst(const ALeft, ARight: TCacheFileInfo): Integer;
begin
  if ALeft.LastWrite < ARight.LastWrite then
  begin
    Result := -1;
  end
  else if ALeft.LastWrite > ARight.LastWrite then
  begin
    Result := 1;
  end
  else
  begin
    Result := CompareText(ALeft.FileName, ARight.FileName);
  end;
end;

class function TIndexCacheHousekeeping.SelectForRemoval(const AFiles: TArray<TCacheFileInfo>;
  AMaxBytes: Int64; const AKeep: string): TArray<string>;
begin
  Result := SelectForRemoval(AFiles, AMaxBytes, TArray<string>.Create(AKeep));
end;

function IsKept(const AFileName: string; const AKeep: TArray<string>): Boolean;
var
  mKeep: string;
begin
  Result := False;
  for mKeep in AKeep do
  begin
    if SameText(AFileName, mKeep) then
    begin
      Exit(True);
    end;
  end;
end;

class function TIndexCacheHousekeeping.SelectForRemoval(const AFiles: TArray<TCacheFileInfo>;
  AMaxBytes: Int64; const AKeep: TArray<string>): TArray<string>;
var
  mSorted: TList<TCacheFileInfo>;
  mInfo: TCacheFileInfo;
  mTotal: Int64;
begin
  Result := nil;
  mTotal := 0;
  for mInfo in AFiles do
  begin
    Inc(mTotal, mInfo.Size);
  end;
  if mTotal <= AMaxBytes then
  begin
    Exit;
  end;
  mSorted := TList<TCacheFileInfo>.Create(TComparer<TCacheFileInfo>.Construct(CompareOldestFirst));
  try
    mSorted.AddRange(AFiles);
    mSorted.Sort;
    for mInfo in mSorted do
    begin
      if mTotal <= AMaxBytes then
      begin
        Break;
      end;
      if mInfo.Locked or IsKept(mInfo.FileName, AKeep) then
      begin
        Continue;
      end;
      Result := Result + [mInfo.FileName];
      Dec(mTotal, mInfo.Size);
    end;
  finally
    mSorted.Free;
  end;
end;

/// <summary>Nennt Info bekannte Ursprünge, von denen keiner mehr besteht?</summary>
function IsOrphan(const AInfo: TCacheFileInfo; const AExists: TFunc<string, Boolean>): Boolean;
var
  mOrigin: string;
begin
  Result := False;
  for mOrigin in AInfo.Origins do
  begin
    if mOrigin = '' then
    begin
      Continue;
    end;
    if AExists(mOrigin) then
    begin
      Exit(False);
    end;
    Result := True;
  end;
end;

class function TIndexCacheHousekeeping.SelectOrphans(const AFiles: TArray<TCacheFileInfo>;
  const AKeep: TArray<string>; const AExists: TFunc<string, Boolean>): TArray<string>;
var
  mInfo: TCacheFileInfo;
begin
  Result := nil;
  for mInfo in AFiles do
  begin
    if not mInfo.Locked and not IsKept(mInfo.FileName, AKeep) and IsOrphan(mInfo, AExists) then
    begin
      Result := Result + [mInfo.FileName];
    end;
  end;
end;

class function TIndexCacheHousekeeping.SelectUnused(const AFiles: TArray<TCacheFileInfo>;
  const AKeep: TArray<string>; ANow: TDateTime; AMaxAgeDays: Integer): TArray<string>;
var
  mInfo: TCacheFileInfo;
begin
  Result := nil;
  if AMaxAgeDays <= 0 then
  begin
    Exit;
  end;
  for mInfo in AFiles do
  begin
    if not mInfo.Locked and not IsKept(mInfo.FileName, AKeep) and (mInfo.LastWrite < ANow - AMaxAgeDays) then
    begin
      Result := Result + [mInfo.FileName];
    end;
  end;
end;

class function TIndexCacheHousekeeping.MaxBytesOf(AMaxMb: Integer): Int64;
begin
  if AMaxMb <= 0 then
  begin
    Result := High(Int64);
  end
  else
  begin
    Result := Int64(AMaxMb) * 1024 * 1024;
  end;
end;

end.
