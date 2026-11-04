unit Atlas.Core.Problems.FindingsCache;

// Befunde je Datei mit dem Stand des Speichers (#909): nur geänderte Dateien
// werden neu gebaut und von der Platte gelesen. Ohne VCL und Open Tools API.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Problems.Store,
  Atlas.Core.Problems.Findings;

type
  /// <summary>Befunde je Datei mit dem Stand des Speichers (TAtlasProblemStore.Stamp): Build baut nur Dateien
  /// neu, deren Stand sich geändert hat, und meldet, ob sich an der Auswahl überhaupt etwas geändert hat. So
  /// kostet ein neuer Befund in einer Datei nicht den Neuaufbau (und das Lesen von der Platte) aller Dateien.
  /// </summary>
  TAtlasFindingsCache = class
  private type
    TItem = record
      Stamp: Integer;
      Findings: TArray<TAtlasFinding>;
    end;
  private
    FItems: TDictionary<string, TItem>;
    FLastKeys: TArray<string>;
    FLastStamps: TArray<Integer>;
    FBuilt: Boolean;
    /// <summary>Nur die Einträge zu AKeys behalten: Der Speicher bleibt so groß wie die Liste.</summary>
    procedure Keep(const AKeys: TArray<string>);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Befunde der Dateien AFiles (nil = alle Dateien des Speichers), wie TAtlasFindings.FromStore.
    /// AChanged = False: dieselben Dateien mit demselben Stand wie beim letzten Aufruf.</summary>
    function Build(AStore: TAtlasProblemStore; const AFiles: TArray<string>;
      const AReadLines: TFunc<string, TArray<string>>; out AChanged: Boolean): TArray<TAtlasFinding>;
    /// <summary>Alles vergessen; der nächste Build baut alle Dateien neu.</summary>
    procedure Clear;
  end;

implementation

{ TAtlasFindingsCache }

constructor TAtlasFindingsCache.Create;
begin
  inherited Create;
  FItems := TDictionary<string, TItem>.Create;
end;

destructor TAtlasFindingsCache.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

procedure TAtlasFindingsCache.Clear;
begin
  FItems.Clear;
  FLastKeys := nil;
  FLastStamps := nil;
  FBuilt := False;
end;

procedure TAtlasFindingsCache.Keep(const AKeys: TArray<string>);
var
  mNext: TDictionary<string, TItem>;
  mItem: TItem;
  mKey: string;
begin
  if FItems.Count <= Length(AKeys) then
  begin
    Exit;
  end;
  mNext := TDictionary<string, TItem>.Create;
  try
    for mKey in AKeys do
    begin
      if FItems.TryGetValue(mKey, mItem) then
      begin
        mNext.AddOrSetValue(mKey, mItem);
      end;
    end;
    FItems.Free;
    FItems := mNext;
    mNext := nil;
  finally
    mNext.Free;
  end;
end;

function TAtlasFindingsCache.Build(AStore: TAtlasProblemStore; const AFiles: TArray<string>;
  const AReadLines: TFunc<string, TArray<string>>; out AChanged: Boolean): TArray<TAtlasFinding>;
var
  mFiles, mKeys: TArray<string>;
  mStamps: TArray<Integer>;
  mParts: TArray<TArray<TAtlasFinding>>;
  mItem: TItem;
  mIndex: Integer;
begin
  mFiles := AFiles;
  if mFiles = nil then
  begin
    mFiles := AStore.Files;
  end;
  SetLength(mKeys, Length(mFiles));
  SetLength(mStamps, Length(mFiles));
  SetLength(mParts, Length(mFiles));
  AChanged := not FBuilt or (Length(mFiles) <> Length(FLastKeys));
  for mIndex := 0 to High(mFiles) do
  begin
    mKeys[mIndex] := TAtlasProblemStore.Key(mFiles[mIndex]);
    mStamps[mIndex] := AStore.Stamp(mFiles[mIndex]);
    AChanged := AChanged or (mKeys[mIndex] <> FLastKeys[mIndex]) or (mStamps[mIndex] <> FLastStamps[mIndex]);
    if not FItems.TryGetValue(mKeys[mIndex], mItem) or (mItem.Stamp <> mStamps[mIndex]) then
    begin
      mItem.Stamp := mStamps[mIndex];
      mItem.Findings := TAtlasFindings.FromStoreFile(AStore, mFiles[mIndex], AReadLines);
      FItems.AddOrSetValue(mKeys[mIndex], mItem);
    end;
    mParts[mIndex] := mItem.Findings;
  end;
  if AChanged then
  begin
    Keep(mKeys);
    FLastKeys := mKeys;
    FLastStamps := mStamps;
    FBuilt := True;
  end;
  Result := TAtlasFindings.Concat(mParts);
end;

end.
