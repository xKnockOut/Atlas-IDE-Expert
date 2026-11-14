unit Atlas.Common.Profiling.Sampling;

// Stichproben-Profiler (#2057), Fachlogik zwischen Prober und Profildatei:
// - TAtlasRawStacks fasst gleiche Stapel roher Adressen während des Laufs zusammen (der Prober nimmt alle 10 ms
//   je rechnendem Thread eine Probe; gleiche Stapel sind die Regel).
// - TAtlasProfileResolver löst nach dem Lauf jede Adresse einmal auf: im Hauptmodul über die Map-Datei (Routine,
//   Unit, Datei, Zeile), sonst als „[modul.dll]“, und baut daraus den Lauf (Atlas.Text.Profile).
// Ohne Windows, damit beides unter FPC getestet wird; der Prober selbst liegt in Atlas.Windows.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Text.MapFile,
  Atlas.Common.Profiling.Contract,
  Atlas.Text.Profile;

type
  /// <summary>Gleiche Stapel zusammengefasst; nicht threadsicher (gehört dem Thread des Probers).</summary>
  TAtlasRawStacks = class
  private
    FStacks: TList<TAtlasRawStack>;
    FIndex: TDictionary<string, Integer>;
    FSamples: Integer;
    class function KeyOf(const AAddresses: TArray<UInt64>): string; static;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Eine Probe; AAddresses[0] ist der innerste Rahmen. Leere Stapel zählen nicht.</summary>
    procedure Add(const AAddresses: TArray<UInt64>);
    /// <summary>Alle Stapel in der Reihenfolge ihres ersten Auftretens.</summary>
    function ToArray: TArray<TAtlasRawStack>;
    procedure Clear;
    property Samples: Integer read FSamples;
  end;

  /// <summary>Rohe Adressen eines Laufs in Rahmen auflösen.</summary>
  TAtlasProfileResolver = class
  private
    FRun: TAtlasSampleRun;
    FMap: TMapFile;
    FFrames: TDictionary<UInt64, TAtlasProfileFrame>;
    function ModuleOf(AAddress: UInt64): Integer;
    function Describe(AAddress: UInt64): TAtlasProfileFrame;
  public
    /// <summary>AMap darf nil sein (keine Map-Datei); gehört weiter dem Aufrufer.</summary>
    constructor Create(const ARun: TAtlasSampleRun; AMap: TMapFile);
    destructor Destroy; override;
    /// <summary>Ein aufgelöster Rahmen; dieselbe Adresse wird nur einmal aufgelöst.</summary>
    function Frame(AAddress: UInt64): TAtlasProfileFrame;
    /// <summary>Rahmen, Stapel, Probenzahl und Dauer in AProfile; die übrigen Felder bleiben.</summary>
    procedure FillProfile(var AProfile: TAtlasProfile);
  end;

implementation

{ TAtlasRawStacks }

constructor TAtlasRawStacks.Create;
begin
  inherited Create;
  FStacks := TList<TAtlasRawStack>.Create;
  FIndex := TDictionary<string, Integer>.Create;
end;

destructor TAtlasRawStacks.Destroy;
begin
  FIndex.Free;
  FStacks.Free;
  inherited;
end;

class function TAtlasRawStacks.KeyOf(const AAddresses: TArray<UInt64>): string;
var
  mParts: TArray<string>;
  mIndex: Integer;
begin
  SetLength(mParts, Length(AAddresses));
  for mIndex := 0 to High(AAddresses) do
  begin
    mParts[mIndex] := IntToHex(AAddresses[mIndex], 1);
  end;
  Result := string.Join(',', mParts);
end;

procedure TAtlasRawStacks.Add(const AAddresses: TArray<UInt64>);
var
  mKey: string;
  mIndex: Integer;
  mStack: TAtlasRawStack;
begin
  if Length(AAddresses) = 0 then
  begin
    Exit;
  end;
  Inc(FSamples);
  mKey := KeyOf(AAddresses);
  if FIndex.TryGetValue(mKey, mIndex) then
  begin
    mStack := FStacks[mIndex];
    Inc(mStack.Count);
    FStacks[mIndex] := mStack;
    Exit;
  end;
  mStack.Addresses := Copy(AAddresses);
  mStack.Count := 1;
  FIndex.Add(mKey, FStacks.Add(mStack));
end;

function TAtlasRawStacks.ToArray: TArray<TAtlasRawStack>;
begin
  Result := FStacks.ToArray;
end;

procedure TAtlasRawStacks.Clear;
begin
  FStacks.Clear;
  FIndex.Clear;
  FSamples := 0;
end;

{ TAtlasProfileResolver }

constructor TAtlasProfileResolver.Create(const ARun: TAtlasSampleRun; AMap: TMapFile);
begin
  inherited Create;
  FRun := ARun;
  FMap := AMap;
  FFrames := TDictionary<UInt64, TAtlasProfileFrame>.Create;
end;

destructor TAtlasProfileResolver.Destroy;
begin
  FFrames.Free;
  inherited;
end;

function TAtlasProfileResolver.ModuleOf(AAddress: UInt64): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FRun.Modules) do
  begin
    if (AAddress >= FRun.Modules[mIndex].Base) and
      (AAddress - FRun.Modules[mIndex].Base < FRun.Modules[mIndex].Size) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TAtlasProfileResolver.Describe(AAddress: UInt64): TAtlasProfileFrame;
var
  mModule: Integer;
  mLocation: TMapLocation;
  mName: string;
begin
  Result := Default(TAtlasProfileFrame);
  Result.IsLibrary := True;
  mModule := ModuleOf(AAddress);
  if mModule < 0 then
  begin
    Result.Routine := '$' + IntToHex(AAddress, 1);
    Exit;
  end;
  mName := ExtractFileName(FRun.Modules[mModule].FileName.Replace('/', '\'));
  Result.Routine := '[' + mName + ']';
  Result.UnitName := mName;
  if mModule <> FRun.MainModule then
  begin
    Exit;
  end;
  // Hauptmodul: Ohne Map oder Map-Eintrag (Startcode, Lücken) bleibt es beim Modulnamen, zählt aber als eigener
  // Code.
  Result.IsLibrary := False;
  if FMap = nil then
  begin
    Exit;
  end;
  mLocation := FMap.ResolveAddress(AAddress, FRun.Modules[mModule].Base);
  if not mLocation.Found then
  begin
    Exit;
  end;
  Result.Routine := mLocation.Routine;
  Result.UnitName := mLocation.UnitName;
  Result.FileName := mLocation.FileName;
  Result.Line := mLocation.Line;
  Result.IsLibrary := TAtlasLibraryUnits.IsLibrary(mLocation.UnitName);
end;

function TAtlasProfileResolver.Frame(AAddress: UInt64): TAtlasProfileFrame;
begin
  if not FFrames.TryGetValue(AAddress, Result) then
  begin
    Result := Describe(AAddress);
    FFrames.Add(AAddress, Result);
  end;
end;

procedure TAtlasProfileResolver.FillProfile(var AProfile: TAtlasProfile);
var
  mBuilder: TAtlasProfileBuilder;
  mStack: TAtlasRawStack;
  mFrames: TArray<TAtlasProfileFrame>;
  mIndex: Integer;
  mRepeat: Integer;
begin
  mBuilder := TAtlasProfileBuilder.Create;
  try
    for mStack in FRun.Stacks do
    begin
      SetLength(mFrames, Length(mStack.Addresses));
      for mIndex := 0 to High(mStack.Addresses) do
      begin
        mFrames[mIndex] := Frame(mStack.Addresses[mIndex]);
      end;
      // Gleiche Stapel einzeln übergeben: Der Builder zählt je Aufruf eine Probe.
      for mRepeat := 1 to mStack.Count do
      begin
        mBuilder.AddSample(mFrames);
      end;
    end;
    mBuilder.FillProfile(AProfile);
  finally
    mBuilder.Free;
  end;
  AProfile.DurationMs := FRun.DurationMs;
end;

end.
