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
    DefaultMaxBytes = Int64(256) * 1024 * 1024;
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
    Result := -1
  else if ALeft.LastWrite > ARight.LastWrite then
    Result := 1
  else
    Result := CompareText(ALeft.FileName, ARight.FileName);
end;

class function TIndexCacheHousekeeping.SelectForRemoval(const AFiles: TArray<TCacheFileInfo>;
  AMaxBytes: Int64; const AKeep: string): TArray<string>;
begin
  Result := SelectForRemoval(AFiles, AMaxBytes, TArray<string>.Create(AKeep));
end;

function IsKept(const AFileName: string; const AKeep: TArray<string>): Boolean;
var
  Keep: string;
begin
  Result := False;
  for Keep in AKeep do
    if SameText(AFileName, Keep) then
      Exit(True);
end;

class function TIndexCacheHousekeeping.SelectForRemoval(const AFiles: TArray<TCacheFileInfo>;
  AMaxBytes: Int64; const AKeep: TArray<string>): TArray<string>;
var
  Sorted: TList<TCacheFileInfo>;
  Info: TCacheFileInfo;
  Total: Int64;
begin
  Result := nil;
  Total := 0;
  for Info in AFiles do
    Inc(Total, Info.Size);
  if Total <= AMaxBytes then
    Exit;
  Sorted := TList<TCacheFileInfo>.Create(TComparer<TCacheFileInfo>.Construct(CompareOldestFirst));
  try
    Sorted.AddRange(AFiles);
    Sorted.Sort;
    for Info in Sorted do
    begin
      if Total <= AMaxBytes then
        Break;
      if Info.Locked or IsKept(Info.FileName, AKeep) then
        Continue;
      Result := Result + [Info.FileName];
      Dec(Total, Info.Size);
    end;
  finally
    Sorted.Free;
  end;
end;

class function TIndexCacheHousekeeping.SelectOrphans(const AFiles: TArray<TCacheFileInfo>;
  const AKeep: TArray<string>; const AExists: TFunc<string, Boolean>): TArray<string>;
var
  Info: TCacheFileInfo;
  Origin: string;
  Known, Alive: Boolean;
begin
  Result := nil;
  for Info in AFiles do
  begin
    if Info.Locked or IsKept(Info.FileName, AKeep) then
      Continue;
    Known := False;
    Alive := False;
    for Origin in Info.Origins do
      if Origin <> '' then
      begin
        Known := True;
        if AExists(Origin) then
        begin
          Alive := True;
          Break;
        end;
      end;
    if Known and not Alive then
      Result := Result + [Info.FileName];
  end;
end;

class function TIndexCacheHousekeeping.SelectUnused(const AFiles: TArray<TCacheFileInfo>;
  const AKeep: TArray<string>; ANow: TDateTime; AMaxAgeDays: Integer): TArray<string>;
var
  Info: TCacheFileInfo;
begin
  Result := nil;
  if AMaxAgeDays <= 0 then
    Exit;
  for Info in AFiles do
    if not Info.Locked and not IsKept(Info.FileName, AKeep) and (Info.LastWrite < ANow - AMaxAgeDays) then
      Result := Result + [Info.FileName];
end;

class function TIndexCacheHousekeeping.MaxBytesOf(AMaxMb: Integer): Int64;
begin
  if AMaxMb <= 0 then
    Result := High(Int64)
  else
    Result := Int64(AMaxMb) * 1024 * 1024;
end;

end.
