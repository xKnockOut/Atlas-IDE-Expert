unit Atlas.Common.Profiling.Profile;

// Stichproben-Profiler (#2057), Fachlogik: ein Lauf als Datei. Wer die Proben nimmt (Prober im Plugin bzw. Server),
// gibt je Probe den aufgelösten Aufrufstapel an TAtlasProfileBuilder; daraus entsteht ein TAtlasProfile mit
// Rahmen (Routine, Unit, Datei, Zeile, Bibliothek ja/nein) und gleichen Stapeln samt Anzahl. Gespeichert wird als
// JSON unter <Atlas-Cache>\profiles\profile-<Zeit>.json; die letzten fünf Läufe bleiben (TAtlasProfileStore).
//   {"version":1, "program":…, "project":…, "platform":…, "startedAt":ISO 8601, "durationMs":…, "intervalMs":…,
//    "samples":…, "frames":[{"routine","unit","file","line","library"}],
//    "stacks":[{"frames":[0,4,7], "count":12}]}            Index 0 eines Stapels = innerster Rahmen.
// Auswertung (Methoden, Zeilen, Vergleich) in Atlas.Common.Profiling.Report.

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  /// <summary>Eine aufgelöste Stelle: Routine, Unit, Datei und Zeile (0 = ohne); IsLibrary für RTL/VCL usw.
  /// </summary>
  TAtlasProfileFrame = record
    Routine: string;
    UnitName: string;
    FileName: string;
    Line: Integer;
    IsLibrary: Boolean;
    /// <summary>Schlüssel für das Zusammenfassen gleicher Rahmen.</summary>
    function Key: string;
  end;

  /// <summary>Ein Aufrufstapel als Indizes in TAtlasProfile.Frames (0 = innerster) und wie oft er vorkam.</summary>
  TAtlasProfileStack = record
    Frames: TArray<Integer>;
    Count: Integer;
  end;

  TAtlasProfile = record
    ProgramName: string;
    Project: string;
    Platform: string;
    StartedAt: TDateTime;
    DurationMs: Int64;
    IntervalMs: Integer;
    /// <summary>Proben, in denen ein Thread gerechnet hat (Summe der Count aller Stapel).</summary>
    Samples: Integer;
    Frames: TArray<TAtlasProfileFrame>;
    Stacks: TArray<TAtlasProfileStack>;
  end;

  /// <summary>Sammelt Proben und fasst gleiche Rahmen und Stapel zusammen.</summary>
  TAtlasProfileBuilder = class
  private
    FFrames: TList<TAtlasProfileFrame>;
    FFrameIndex: TDictionary<string, Integer>;
    FStacks: TList<TAtlasProfileStack>;
    FStackIndex: TDictionary<string, Integer>;
    FSamples: Integer;
    function FrameIndexOf(const AFrame: TAtlasProfileFrame): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Eine Probe; AFrames[0] ist der innerste Rahmen. Leere Stapel zählen nicht.</summary>
    procedure AddSample(const AFrames: TArray<TAtlasProfileFrame>);
    /// <summary>Rahmen, Stapel und Probenzahl in AProfile übernehmen; die übrigen Felder bleiben.</summary>
    procedure FillProfile(var AProfile: TAtlasProfile);
    property Samples: Integer read FSamples;
  end;

  TAtlasProfileJson = record
  public const
    cVersion = 1;
  public
    class function ToText(const AProfile: TAtlasProfile): string; static;
    /// <summary>False bei kaputtem Inhalt, unbekannter Version oder Indizes außerhalb der Rahmen.</summary>
    class function TryParse(const AText: string; out AProfile: TAtlasProfile): Boolean; static;
  end;

  /// <summary>Ablage der Läufe: Ordner, Dateiname und welche Dateien beim Aufräumen gehen.</summary>
  TAtlasProfileStore = record
  public const
    cKeep = 5;
    cPrefix = 'profile-';
  public
    /// <summary>Ordner der Läufe unter dem Atlas-Cache ACacheRoot.</summary>
    class function Folder(const ACacheRoot: string): string; static;
    /// <summary>profile-JJJJMMTT-HHNNSS.json; sortiert nach Zeit wie nach Name.</summary>
    class function FileNameFor(AStartedAt: TDateTime): string; static;
    /// <summary>Nur Dateien nach FileNameFor, neueste zuerst.</summary>
    class function Newest(const AFiles: TArray<string>): TArray<string>; static;
    /// <summary>Was über die neuesten AKeep hinaus geht und gelöscht werden soll.</summary>
    class function Surplus(const AFiles: TArray<string>; AKeep: Integer): TArray<string>; static;
  end;

  /// <summary>Units der Laufzeitbibliothek und der Frameworks von RAD Studio (für „Nur eigener Code“).</summary>
  TAtlasLibraryUnits = record
  public
    class function IsLibrary(const AUnitName: string): Boolean; static;
  end;

implementation

uses
  System.JSON,
  System.DateUtils,
  System.StrUtils,
  System.Generics.Defaults,
  System.IOUtils;

{ TAtlasProfileFrame }

function TAtlasProfileFrame.Key: string;
begin
  Result := Routine + #1 + FileName + #1 + IntToStr(Line);
end;

{ TAtlasProfileBuilder }

constructor TAtlasProfileBuilder.Create;
begin
  inherited Create;
  FFrames := TList<TAtlasProfileFrame>.Create;
  FFrameIndex := TDictionary<string, Integer>.Create;
  FStacks := TList<TAtlasProfileStack>.Create;
  FStackIndex := TDictionary<string, Integer>.Create;
end;

destructor TAtlasProfileBuilder.Destroy;
begin
  FStackIndex.Free;
  FStacks.Free;
  FFrameIndex.Free;
  FFrames.Free;
  inherited;
end;

function TAtlasProfileBuilder.FrameIndexOf(const AFrame: TAtlasProfileFrame): Integer;
begin
  if not FFrameIndex.TryGetValue(AFrame.Key, Result) then
  begin
    Result := FFrames.Add(AFrame);
    FFrameIndex.Add(AFrame.Key, Result);
  end;
end;

procedure TAtlasProfileBuilder.AddSample(const AFrames: TArray<TAtlasProfileFrame>);
var
  mIndexes: TArray<Integer>;
  mKey: string;
  mPosition: Integer;
  mStack: TAtlasProfileStack;
begin
  if Length(AFrames) = 0 then
  begin
    Exit;
  end;
  SetLength(mIndexes, Length(AFrames));
  mKey := '';
  for mPosition := 0 to High(AFrames) do
  begin
    mIndexes[mPosition] := FrameIndexOf(AFrames[mPosition]);
    mKey := mKey + IntToStr(mIndexes[mPosition]) + ',';
  end;
  Inc(FSamples);
  if FStackIndex.TryGetValue(mKey, mPosition) then
  begin
    mStack := FStacks[mPosition];
    Inc(mStack.Count);
    FStacks[mPosition] := mStack;
    Exit;
  end;
  mStack.Frames := mIndexes;
  mStack.Count := 1;
  FStackIndex.Add(mKey, FStacks.Add(mStack));
end;

procedure TAtlasProfileBuilder.FillProfile(var AProfile: TAtlasProfile);
begin
  AProfile.Frames := FFrames.ToArray;
  AProfile.Stacks := FStacks.ToArray;
  AProfile.Samples := FSamples;
end;

{ TAtlasProfileJson }

function FrameToJson(const AFrame: TAtlasProfileFrame): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('routine', AFrame.Routine);
  Result.AddPair('unit', AFrame.UnitName);
  Result.AddPair('file', AFrame.FileName);
  Result.AddPair('line', TJSONNumber.Create(AFrame.Line));
  Result.AddPair('library', TJSONBool.Create(AFrame.IsLibrary));
end;

function StackToJson(const AStack: TAtlasProfileStack): TJSONObject;
var
  mFrames: TJSONArray;
  mIndex: Integer;
begin
  mFrames := TJSONArray.Create;
  for mIndex in AStack.Frames do
  begin
    mFrames.Add(mIndex);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('frames', mFrames);
  Result.AddPair('count', TJSONNumber.Create(AStack.Count));
end;

procedure AddHeader(ARoot: TJSONObject; const AProfile: TAtlasProfile);
begin
  ARoot.AddPair('version', TJSONNumber.Create(TAtlasProfileJson.cVersion));
  ARoot.AddPair('program', AProfile.ProgramName);
  ARoot.AddPair('project', AProfile.Project);
  ARoot.AddPair('platform', AProfile.Platform);
  ARoot.AddPair('startedAt', DateToISO8601(AProfile.StartedAt, False));
  ARoot.AddPair('durationMs', TJSONNumber.Create(AProfile.DurationMs));
  ARoot.AddPair('intervalMs', TJSONNumber.Create(AProfile.IntervalMs));
  ARoot.AddPair('samples', TJSONNumber.Create(AProfile.Samples));
end;

class function TAtlasProfileJson.ToText(const AProfile: TAtlasProfile): string;
var
  mRoot: TJSONObject;
  mFrames, mStacks: TJSONArray;
  mFrame: TAtlasProfileFrame;
  mStack: TAtlasProfileStack;
begin
  mRoot := TJSONObject.Create;
  try
    AddHeader(mRoot, AProfile);
    mFrames := TJSONArray.Create;
    mRoot.AddPair('frames', mFrames);
    for mFrame in AProfile.Frames do
    begin
      mFrames.AddElement(FrameToJson(mFrame));
    end;
    mStacks := TJSONArray.Create;
    mRoot.AddPair('stacks', mStacks);
    for mStack in AProfile.Stacks do
    begin
      mStacks.AddElement(StackToJson(mStack));
    end;
    Result := mRoot.ToJSON([]);
  finally
    mRoot.Free;
  end;
end;

function FrameFromJson(AValue: TJSONValue; out AFrame: TAtlasProfileFrame): Boolean;
begin
  AFrame := Default(TAtlasProfileFrame);
  Result := (AValue is TJSONObject) and AValue.TryGetValue<string>('routine', AFrame.Routine);
  if Result then
  begin
    AValue.TryGetValue<string>('unit', AFrame.UnitName);
    AValue.TryGetValue<string>('file', AFrame.FileName);
    AValue.TryGetValue<Integer>('line', AFrame.Line);
    AValue.TryGetValue<Boolean>('library', AFrame.IsLibrary);
  end;
end;

function StackFromJson(AValue: TJSONValue; AFrameCount: Integer; out AStack: TAtlasProfileStack): Boolean;
var
  mFrames: TJSONArray;
  mPosition, mIndex: Integer;
begin
  AStack := Default(TAtlasProfileStack);
  Result := (AValue is TJSONObject) and AValue.TryGetValue<TJSONArray>('frames', mFrames) and
    AValue.TryGetValue<Integer>('count', AStack.Count) and (mFrames.Count > 0) and (AStack.Count > 0);
  if not Result then
  begin
    Exit;
  end;
  SetLength(AStack.Frames, mFrames.Count);
  for mPosition := 0 to mFrames.Count - 1 do
  begin
    mIndex := StrToIntDef(mFrames.Items[mPosition].Value, -1);
    if (mIndex < 0) or (mIndex >= AFrameCount) then
    begin
      Exit(False);
    end;
    AStack.Frames[mPosition] := mIndex;
  end;
end;

function ReadHeader(ARoot: TJSONObject; var AProfile: TAtlasProfile): Boolean;
var
  mVersion: Integer;
  mStarted: string;
begin
  Result := ARoot.TryGetValue<Integer>('version', mVersion) and (mVersion = TAtlasProfileJson.cVersion) and
    ARoot.TryGetValue<string>('program', AProfile.ProgramName) and ARoot.TryGetValue<string>('startedAt', mStarted);
  if not Result then
  begin
    Exit;
  end;
  ARoot.TryGetValue<string>('project', AProfile.Project);
  ARoot.TryGetValue<string>('platform', AProfile.Platform);
  ARoot.TryGetValue<Int64>('durationMs', AProfile.DurationMs);
  ARoot.TryGetValue<Integer>('intervalMs', AProfile.IntervalMs);
  Result := TryISO8601ToDate(mStarted, AProfile.StartedAt, False);
end;

function ReadFrames(ARoot: TJSONObject; var AProfile: TAtlasProfile): Boolean;
var
  mFrames: TJSONArray;
  mPosition: Integer;
begin
  Result := ARoot.TryGetValue<TJSONArray>('frames', mFrames);
  if not Result then
  begin
    Exit;
  end;
  SetLength(AProfile.Frames, mFrames.Count);
  for mPosition := 0 to mFrames.Count - 1 do
  begin
    if not FrameFromJson(mFrames.Items[mPosition], AProfile.Frames[mPosition]) then
    begin
      Exit(False);
    end;
  end;
end;

function ReadStacks(ARoot: TJSONObject; var AProfile: TAtlasProfile): Boolean;
var
  mStacks: TJSONArray;
  mPosition: Integer;
begin
  Result := ARoot.TryGetValue<TJSONArray>('stacks', mStacks);
  if not Result then
  begin
    Exit;
  end;
  SetLength(AProfile.Stacks, mStacks.Count);
  AProfile.Samples := 0;
  for mPosition := 0 to mStacks.Count - 1 do
  begin
    if not StackFromJson(mStacks.Items[mPosition], Length(AProfile.Frames), AProfile.Stacks[mPosition]) then
    begin
      Exit(False);
    end;
    Inc(AProfile.Samples, AProfile.Stacks[mPosition].Count);
  end;
end;

class function TAtlasProfileJson.TryParse(const AText: string; out AProfile: TAtlasProfile): Boolean;
var
  mValue: TJSONValue;
begin
  AProfile := Default(TAtlasProfile);
  mValue := TJSONObject.ParseJSONValue(AText);
  try
    Result := (mValue is TJSONObject) and ReadHeader(TJSONObject(mValue), AProfile) and
      ReadFrames(TJSONObject(mValue), AProfile) and ReadStacks(TJSONObject(mValue), AProfile);
  finally
    mValue.Free;
  end;
  if not Result then
  begin
    AProfile := Default(TAtlasProfile);
  end;
end;

{ TAtlasProfileStore }

class function TAtlasProfileStore.Folder(const ACacheRoot: string): string;
begin
  Result := TPath.Combine(ACacheRoot, 'profiles');
end;

class function TAtlasProfileStore.FileNameFor(AStartedAt: TDateTime): string;
begin
  Result := cPrefix + FormatDateTime('yyyymmdd"-"hhnnss', AStartedAt) + '.json';
end;

function IsProfileFile(const AFileName: string): Boolean;
var
  mName: string;
begin
  mName := ExtractFileName(AFileName.Replace('/', PathDelim));
  Result := StartsText(TAtlasProfileStore.cPrefix, mName) and EndsText('.json', mName);
end;

class function TAtlasProfileStore.Newest(const AFiles: TArray<string>): TArray<string>;
var
  mFile: string;
  mList: TList<string>;
begin
  mList := TList<string>.Create;
  try
    for mFile in AFiles do
    begin
      if IsProfileFile(mFile) then
      begin
        mList.Add(mFile);
      end;
    end;
    mList.Sort(TComparer<string>.Construct(
      function(const ALeft, ARight: string): Integer
      begin
        Result := CompareText(ExtractFileName(ARight), ExtractFileName(ALeft));
        if Result = 0 then
        begin
          Result := CompareStr(ARight, ALeft);
        end;
      end));
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

class function TAtlasProfileStore.Surplus(const AFiles: TArray<string>; AKeep: Integer): TArray<string>;
var
  mNewest: TArray<string>;
  mIndex: Integer;
begin
  Result := nil;
  mNewest := Newest(AFiles);
  for mIndex := AKeep to High(mNewest) do
  begin
    Result := Result + [mNewest[mIndex]];
  end;
end;

{ TAtlasLibraryUnits }

class function TAtlasLibraryUnits.IsLibrary(const AUnitName: string): Boolean;
const
  cExact: array[0..1] of string = ('System', 'SysInit');
  cPrefixes: array[0..15] of string = ('System.', 'Vcl.', 'Winapi.', 'Data.', 'FMX.', 'Xml.', 'Soap.', 'REST.',
    'Web.', 'Datasnap.', 'FireDAC.', 'IBX.', 'Posix.', 'Macapi.', 'Androidapi.', 'iOSapi.');
var
  mText: string;
begin
  for mText in cExact do
  begin
    if SameText(AUnitName, mText) then
    begin
      Exit(True);
    end;
  end;
  for mText in cPrefixes do
  begin
    if StartsText(mText, AUnitName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

end.
