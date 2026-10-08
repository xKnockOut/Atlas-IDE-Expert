unit BDLsp.Common.Index.CacheHousekeeping;

// Aufräumregeln für den Cache-Ordner (#184): Der Ordner wird auf eine
// Höchstgröße begrenzt, die ältesten Caches gehen zuerst. Der Cache des
// eigenen Projekts und gesperrte Caches anderer Instanzen bleiben stehen.
// Reine Logik; die Plattenzugriffe liegen in Index.Adapters.CacheDirectory.

interface

uses
  System.SysUtils;

type
  TCacheFileInfo = record
    FileName: string;
    Size: Int64;
    LastWrite: TDateTime;
    /// <summary>Eine andere Serverinstanz arbeitet mit diesem Cache.</summary>
    Locked: Boolean;
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
      const AKeep: string): TArray<string>; static;
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
      if Info.Locked or SameText(Info.FileName, AKeep) then
        Continue;
      Result := Result + [Info.FileName];
      Dec(Total, Info.Size);
    end;
  finally
    Sorted.Free;
  end;
end;

end.
