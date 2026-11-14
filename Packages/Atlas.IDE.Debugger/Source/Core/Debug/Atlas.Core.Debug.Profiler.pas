unit Atlas.Core.Debug.Profiler;

// Stichproben-Profiler (#2057) im Plugin, Fachlogik ohne IDE:
// - TAtlasProfilerProtocol: Argumente und Antworten der Serverbefehle atlas.server.profilerStart, …Status und
//   …Stop (workspace/executeCommand mit genau einem Argument-Objekt) an den Server, der die Proben nimmt (Win64,
//   sieht auch 64-Bit-Programme). Die Namen stehen im Server in Atlas.Common.Lsp.Profiler, das das Plugin nicht
//   einbinden darf.
// - TAtlasProfileTable: Zeilen für das Fenster „Atlas: Profil“ aus der Auswertung eines Laufs
//   (Atlas.Text.ProfileReport), allein oder im Vergleich mit dem vorigen Lauf, und die Wahl des vorigen Laufs.
// Die Profildateien liest das Plugin selbst (TAtlasProfileJson); den Ordner nennt TAtlasProfileStore.

interface

uses
  System.SysUtils,
  Atlas.Text.Profile;

type
  TAtlasProfilerStartAnswer = record
    Started: Boolean;
    MapFile: string;
    /// <summary>Routinen in der Map; 0 = keine Map, die Rahmen bleiben Module.</summary>
    Routines: Integer;
  end;

  TAtlasProfilerStatusAnswer = record
    Running: Boolean;
    ProcessId: Cardinal;
    ElapsedMs: Int64;
    Samples: Integer;
    /// <summary>Zuletzt geschriebene Profildatei; '' ohne.</summary>
    LastFile: string;
  end;

  TAtlasProfilerStopAnswer = record
    FileName: string;
    Path: string;
    Samples: Integer;
    DurationMs: Int64;
  end;

  /// <summary>Was der Server über den Lauf wissen soll (für die Kopfdaten der Datei).</summary>
  TAtlasProfilerTarget = record
    ProcessId: Cardinal;
    IntervalMs: Integer;
    ProgramName: string;
    Project: string;
    Platform: string;
  end;

  TAtlasProfilerProtocol = record
  public const
    cStartCommand = 'atlas.server.profilerStart';
    cStatusCommand = 'atlas.server.profilerStatus';
    cStopCommand = 'atlas.server.profilerStop';
    /// <summary>Argumente von Status und Stop: ein leeres Objekt.</summary>
    cEmptyArguments = '[{}]';
  public
    /// <summary>Argumente von atlas.server.profilerStart: [{processId, intervalMs, program?, project?,
    /// platform?}].</summary>
    class function StartArguments(const ATarget: TAtlasProfilerTarget): string; static;
    /// <summary>False bei leerer oder kaputter Antwort.</summary>
    class function ReadStart(const AJson: string; out AAnswer: TAtlasProfilerStartAnswer): Boolean; static;
    class function ReadStatus(const AJson: string; out AAnswer: TAtlasProfilerStatusAnswer): Boolean; static;
    /// <summary>False auch ohne Datei (path und file leer).</summary>
    class function ReadStop(const AJson: string; out AAnswer: TAtlasProfilerStopAnswer): Boolean; static;
  end;

  /// <summary>Eine Zeile der Tabelle: Zellen in Spaltenfolge und wohin ein Doppelklick führt.</summary>
  TAtlasProfileRow = record
    Routine: string;
    FileName: string;
    /// <summary>Zeile für den Sprung; 0 = Datei ohne Zeile.</summary>
    Line: Integer;
    IsLibrary: Boolean;
    Cells: TArray<string>;
  end;

  TAtlasProfileTable = record
  public
    /// <summary>„12.3 %“ bzw. mit AFormat „12,3 %“.</summary>
    class function PercentText(AValue: Double; const AFormat: TFormatSettings): string; static;
    /// <summary>Änderung mit Vorzeichen: „+1.5 %“, „-0.4 %“, „0.0 %“.</summary>
    class function ChangeText(AValue: Double; const AFormat: TFormatSettings): string; static;
    /// <summary>Spalten Methode, Unit, Eigen, Gesamt, heißeste Zeile; Reihenfolge wie
    /// TAtlasProfileAnalysis.Methods.</summary>
    class function MethodRows(const AProfile: TAtlasProfile; AOwnOnly: Boolean;
      const AFormat: TFormatSettings): TArray<TAtlasProfileRow>; static;
    /// <summary>Spalten Methode, Eigen vorher, Eigen nachher, Änderung; Sprungziel aus dem neueren Lauf, sonst
    /// aus dem älteren.</summary>
    class function CompareRows(const ABefore, AAfter: TAtlasProfile; AOwnOnly: Boolean;
      const AFormat: TFormatSettings): TArray<TAtlasProfileRow>; static;
    /// <summary>Lauf vor ACurrent (Dateiname oder Pfad) unter AFiles; '' ohne.</summary>
    class function PreviousRun(const AFiles: TArray<string>; const ACurrent: string): string; static;
    /// <summary>„13.11.2026 14:05:22“ aus profile-20261113-140522.json; sonst der Dateiname.</summary>
    class function RunTitle(const AFileName: string): string; static;
  end;

implementation

uses
  System.JSON,
  System.Generics.Collections,
  Atlas.Text.ProfileReport;

function ParseObject(const AJson: string): TJSONObject;
var
  mValue: TJSONValue;
begin
  Result := nil;
  if AJson = '' then
  begin
    Exit;
  end;
  mValue := TJSONObject.ParseJSONValue(AJson);
  if mValue is TJSONObject then
  begin
    Result := TJSONObject(mValue);
  end
  else
  begin
    mValue.Free;
  end;
end;

{ TAtlasProfilerProtocol }

class function TAtlasProfilerProtocol.StartArguments(const ATarget: TAtlasProfilerTarget): string;
var
  mParams: TJSONObject;
begin
  mParams := TJSONObject.Create;
  try
    mParams.AddPair('processId', TJSONNumber.Create(Int64(ATarget.ProcessId)));
    mParams.AddPair('intervalMs', TJSONNumber.Create(ATarget.IntervalMs));
    if ATarget.ProgramName <> '' then
    begin
      mParams.AddPair('program', ATarget.ProgramName);
    end;
    if ATarget.Project <> '' then
    begin
      mParams.AddPair('project', ATarget.Project);
    end;
    if ATarget.Platform <> '' then
    begin
      mParams.AddPair('platform', ATarget.Platform);
    end;
    Result := '[' + mParams.ToJSON([]) + ']';
  finally
    mParams.Free;
  end;
end;

class function TAtlasProfilerProtocol.ReadStart(const AJson: string; out AAnswer: TAtlasProfilerStartAnswer): Boolean;
var
  mRoot: TJSONObject;
begin
  AAnswer := Default(TAtlasProfilerStartAnswer);
  mRoot := ParseObject(AJson);
  Result := mRoot <> nil;
  if not Result then
  begin
    Exit;
  end;
  try
    AAnswer.Started := mRoot.GetValue<Boolean>('started', False);
    AAnswer.MapFile := mRoot.GetValue<string>('mapFile', '');
    AAnswer.Routines := mRoot.GetValue<Integer>('routines', 0);
    Result := AAnswer.Started;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasProfilerProtocol.ReadStatus(const AJson: string;
  out AAnswer: TAtlasProfilerStatusAnswer): Boolean;
var
  mRoot: TJSONObject;
begin
  AAnswer := Default(TAtlasProfilerStatusAnswer);
  mRoot := ParseObject(AJson);
  Result := mRoot <> nil;
  if not Result then
  begin
    Exit;
  end;
  try
    AAnswer.Running := mRoot.GetValue<Boolean>('running', False);
    AAnswer.ProcessId := Cardinal(mRoot.GetValue<Int64>('processId', 0));
    AAnswer.ElapsedMs := mRoot.GetValue<Int64>('elapsedMs', 0);
    AAnswer.Samples := mRoot.GetValue<Integer>('samples', 0);
    AAnswer.LastFile := mRoot.GetValue<string>('lastFile', '');
  finally
    mRoot.Free;
  end;
end;

class function TAtlasProfilerProtocol.ReadStop(const AJson: string; out AAnswer: TAtlasProfilerStopAnswer): Boolean;
var
  mRoot: TJSONObject;
begin
  AAnswer := Default(TAtlasProfilerStopAnswer);
  mRoot := ParseObject(AJson);
  Result := mRoot <> nil;
  if not Result then
  begin
    Exit;
  end;
  try
    AAnswer.FileName := mRoot.GetValue<string>('file', '');
    AAnswer.Path := mRoot.GetValue<string>('path', '');
    AAnswer.Samples := mRoot.GetValue<Integer>('samples', 0);
    AAnswer.DurationMs := mRoot.GetValue<Int64>('durationMs', 0);
    Result := (AAnswer.Path <> '') or (AAnswer.FileName <> '');
  finally
    mRoot.Free;
  end;
end;

{ TAtlasProfileTable }

class function TAtlasProfileTable.PercentText(AValue: Double; const AFormat: TFormatSettings): string;
begin
  Result := FormatFloat('0.0', AValue, AFormat) + ' %';
end;

class function TAtlasProfileTable.ChangeText(AValue: Double; const AFormat: TFormatSettings): string;
var
  mText: string;
begin
  mText := FormatFloat('0.0', Abs(AValue), AFormat);
  // Was gerundet 0,0 ergibt, bekommt kein Vorzeichen.
  if (AValue > 0) and (mText <> FormatFloat('0.0', 0, AFormat)) then
  begin
    mText := '+' + mText;
  end
  else if (AValue < 0) and (mText <> FormatFloat('0.0', 0, AFormat)) then
  begin
    mText := '-' + mText;
  end;
  Result := mText + ' %';
end;

function LineText(ALine: Integer): string;
begin
  Result := '';
  if ALine > 0 then
  begin
    Result := IntToStr(ALine);
  end;
end;

class function TAtlasProfileTable.MethodRows(const AProfile: TAtlasProfile; AOwnOnly: Boolean;
  const AFormat: TFormatSettings): TArray<TAtlasProfileRow>;
var
  mMethods: TArray<TAtlasProfileMethod>;
  mIndex: Integer;
  mRow: TAtlasProfileRow;
begin
  mMethods := TAtlasProfileAnalysis.Methods(AProfile, AOwnOnly);
  SetLength(Result, Length(mMethods));
  for mIndex := 0 to High(mMethods) do
  begin
    mRow := Default(TAtlasProfileRow);
    mRow.Routine := mMethods[mIndex].Routine;
    mRow.FileName := mMethods[mIndex].FileName;
    mRow.Line := mMethods[mIndex].HotLine;
    mRow.IsLibrary := mMethods[mIndex].IsLibrary;
    mRow.Cells := TArray<string>.Create(mMethods[mIndex].Routine, mMethods[mIndex].UnitName,
      PercentText(TAtlasProfileAnalysis.Percent(mMethods[mIndex].SelfCount, AProfile.Samples), AFormat),
      PercentText(TAtlasProfileAnalysis.Percent(mMethods[mIndex].TotalCount, AProfile.Samples), AFormat),
      LineText(mMethods[mIndex].HotLine));
    Result[mIndex] := mRow;
  end;
end;

/// <summary>Sprungziele je Routine; der zuerst eingetragene Lauf gewinnt.</summary>
procedure AddTargets(ATargets: TDictionary<string, TAtlasProfileMethod>; const AProfile: TAtlasProfile;
  AOwnOnly: Boolean);
var
  mMethod: TAtlasProfileMethod;
begin
  for mMethod in TAtlasProfileAnalysis.Methods(AProfile, AOwnOnly) do
  begin
    if not ATargets.ContainsKey(mMethod.Routine) then
    begin
      ATargets.Add(mMethod.Routine, mMethod);
    end;
  end;
end;

class function TAtlasProfileTable.CompareRows(const ABefore, AAfter: TAtlasProfile; AOwnOnly: Boolean;
  const AFormat: TFormatSettings): TArray<TAtlasProfileRow>;
var
  mDeltas: TArray<TAtlasProfileDelta>;
  mTargets: TDictionary<string, TAtlasProfileMethod>;
  mTarget: TAtlasProfileMethod;
  mIndex: Integer;
  mRow: TAtlasProfileRow;
begin
  mDeltas := TAtlasProfileAnalysis.Compare(ABefore, AAfter, AOwnOnly);
  SetLength(Result, Length(mDeltas));
  mTargets := TDictionary<string, TAtlasProfileMethod>.Create;
  try
    AddTargets(mTargets, AAfter, AOwnOnly);
    AddTargets(mTargets, ABefore, AOwnOnly);
    for mIndex := 0 to High(mDeltas) do
    begin
      mRow := Default(TAtlasProfileRow);
      mRow.Routine := mDeltas[mIndex].Routine;
      mRow.IsLibrary := mDeltas[mIndex].IsLibrary;
      if mTargets.TryGetValue(mDeltas[mIndex].Routine, mTarget) then
      begin
        mRow.FileName := mTarget.FileName;
        mRow.Line := mTarget.HotLine;
      end;
      mRow.Cells := TArray<string>.Create(mDeltas[mIndex].Routine, PercentText(mDeltas[mIndex].SelfBefore, AFormat),
        PercentText(mDeltas[mIndex].SelfAfter, AFormat), ChangeText(mDeltas[mIndex].SelfChange, AFormat));
      Result[mIndex] := mRow;
    end;
  finally
    mTargets.Free;
  end;
end;

class function TAtlasProfileTable.PreviousRun(const AFiles: TArray<string>; const ACurrent: string): string;
var
  mNewest: TArray<string>;
  mIndex: Integer;
begin
  Result := '';
  mNewest := TAtlasProfileStore.Newest(AFiles);
  for mIndex := 0 to High(mNewest) - 1 do
  begin
    if SameText(ExtractFileName(mNewest[mIndex].Replace('/', PathDelim)),
      ExtractFileName(ACurrent.Replace('/', PathDelim))) then
    begin
      Result := mNewest[mIndex + 1];
      Exit;
    end;
  end;
end;

class function TAtlasProfileTable.RunTitle(const AFileName: string): string;
var
  mName, mStamp: string;
begin
  mName := ExtractFileName(AFileName.Replace('/', PathDelim));
  Result := mName;
  // profile-JJJJMMTT-HHNNSS.json
  mStamp := ChangeFileExt(mName, '');
  if (Length(mStamp) <> Length(TAtlasProfileStore.cPrefix) + 15) or
    not mStamp.StartsWith(TAtlasProfileStore.cPrefix, True) then
  begin
    Exit;
  end;
  mStamp := mStamp.Substring(Length(TAtlasProfileStore.cPrefix));
  Result := mStamp.Substring(6, 2) + '.' + mStamp.Substring(4, 2) + '.' + mStamp.Substring(0, 4) + ' ' +
    mStamp.Substring(9, 2) + ':' + mStamp.Substring(11, 2) + ':' + mStamp.Substring(13, 2);
end;

end.
