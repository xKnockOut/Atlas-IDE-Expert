unit Atlas.Common.Mcp.ProfileTools;

// Stichproben-Profiler für KI-Assistenten (MCP-Werkzeug get_profile, #2057). Liest die gespeicherten Läufe
// (Atlas.Common.Profiling.Profile, neueste zuerst) und liefert die teuersten Methoden mit Datei und heißester
// Zeile, auf Wunsch gefiltert nach Unit und verglichen mit einem zweiten Lauf, als Text oder JSON. Die Dateien
// liest die Shell; hier nur Auswahl, Auswertung und Ausgabe, damit es ohne Dateisystem testbar bleibt.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Profiling.Profile;

type
  /// <summary>Ein gespeicherter Lauf; Name = Dateiname ohne Ordner.</summary>
  TMcpProfileRun = record
    Name: string;
    Profile: TAtlasProfile;
  end;

  TMcpProfileRequest = record
  public const
    cDefaultTop = 10;
    cMaxTop = 100;
  public
    Top: Integer;
    UnitFilter: string;
    Run: string;
    CompareWith: string;
    AsJson: Boolean;
    OwnCodeOnly: Boolean;
    /// <summary>Argumente von get_profile; EMcpToolError bei ungültigen Werten.</summary>
    class function FromArguments(const AArguments: TJSONObject): TMcpProfileRequest; static;
  end;

  TMcpProfileTools = class
  public
    /// <summary>Lauf zu ARun: '' = neuester, Zahl n = n-neuester, sonst Dateiname (mit oder ohne .json);
    /// EMcpToolError, wenn keiner passt.</summary>
    class function SelectRun(const ARuns: TArray<TMcpProfileRun>; const ARun: string): Integer; static;
    /// <summary>Ergebnis von get_profile; ARuns neueste zuerst.</summary>
    class function Report(const ARuns: TArray<TMcpProfileRun>; const ARequest: TMcpProfileRequest): string; static;
    /// <summary>Antwort, solange unter AFolder kein Lauf liegt.</summary>
    class function NoRuns(const AFolder: string): string; static;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  System.DateUtils,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Profiling.Report,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  TProfileToolsText = (NoRuns, UnknownRun, TopInvalid, FormatInvalid, RunLine, NoSamples, MethodLine, HotLine,
    LibraryMark, CompareTitle, CompareLine, RunsLine, NoMethods);

const
  cTexts: array[TProfileToolsText] of TAtlasText = (
    (De: 'Noch kein Profil gespeichert. In der IDE „Start > Mit Profil ausführen“ (Atlas) starten; die Läufe ' +
      'liegen unter %s.';
     En: 'No profile saved yet. Start "Run > Run with profile" (Atlas) in the IDE; the runs are stored under %s.'),
    (De: 'Kein Lauf „%s“. Vorhanden: %s'; En: 'No run "%s". Available: %s'),
    (De: '"top" ist eine ganze Zahl von 1 bis %d'; En: '"top" is a whole number from 1 to %d'),
    (De: '"format" ist text oder json'; En: '"format" is text or json'),
    (De: 'Lauf %s · %s · %s · %.1f s · %d Proben · alle %d ms'; En: 'Run %s · %s · %s · %.1f s · %d samples · ' +
      'every %d ms'),
    (De: 'Der Lauf enthält keine Proben, in denen das Programm gerechnet hat.';
     En: 'The run contains no samples in which the program was computing.'),
    (De: '%d. %s  %s %% eigen, %s %% gesamt%s'; En: '%d. %s  %s %% self, %s %% total%s'),
    (De: '   %s, heißeste Zeile %d'; En: '   %s, hottest line %d'),
    (De: ' (Bibliothek)'; En: ' (library)'),
    (De: 'Vergleich mit Lauf %s (Eigenanteil vorher → nachher):'; En: 'Compared with run %s (self before → after):'),
    (De: '   %s  %s %% → %s %% (%s)'; En: '   %s  %s %% → %s %% (%s)'),
    (De: 'Läufe (neueste zuerst): %s'; En: 'Runs (newest first): %s'),
    (De: 'Keine Methode passt zu unit „%s“.'; En: 'No method matches unit "%s".'));

{$SCOPEDENUMS OFF}

function Number(AValue: Double): string;
begin
  Result := FormatFloat('0.0', AValue, TFormatSettings.Invariant);
end;

function SignedNumber(AValue: Double): string;
begin
  Result := FormatFloat('+0.0;-0.0;0.0', AValue, TFormatSettings.Invariant);
end;

{ TMcpProfileRequest }

class function TMcpProfileRequest.FromArguments(const AArguments: TJSONObject): TMcpProfileRequest;
var
  mFormat: string;
begin
  Result := Default(TMcpProfileRequest);
  Result.Top := cDefaultTop;
  Result.OwnCodeOnly := True;
  if AArguments <> nil then
  begin
    AArguments.TryGetValue<Integer>('top', Result.Top);
    AArguments.TryGetValue<Boolean>('ownCode', Result.OwnCodeOnly);
  end;
  if (Result.Top < 1) or (Result.Top > cMaxTop) then
  begin
    raise EMcpToolError.Create(cTexts[TProfileToolsText.TopInvalid].Fmt([cMaxTop]));
  end;
  Result.UnitFilter := TMcpArgs.OptionalString(AArguments, 'unit');
  Result.Run := TMcpArgs.OptionalString(AArguments, 'run');
  Result.CompareWith := TMcpArgs.OptionalString(AArguments, 'compareWith');
  mFormat := TMcpArgs.OptionalString(AArguments, 'format');
  if (mFormat <> '') and not SameText(mFormat, 'text') and not SameText(mFormat, 'json') then
  begin
    raise EMcpToolError.Create(cTexts[TProfileToolsText.FormatInvalid].Text);
  end;
  Result.AsJson := SameText(mFormat, 'json');
end;

{ TMcpProfileTools }

function RunNames(const ARuns: TArray<TMcpProfileRun>): string;
var
  mRun: TMcpProfileRun;
begin
  Result := '';
  for mRun in ARuns do
  begin
    if Result <> '' then
    begin
      Result := Result + ', ';
    end;
    Result := Result + mRun.Name;
  end;
end;

function SameRunName(const AName, AWanted: string): Boolean;
begin
  Result := SameText(AName, AWanted) or SameText(ChangeFileExt(AName, ''), AWanted);
end;

class function TMcpProfileTools.SelectRun(const ARuns: TArray<TMcpProfileRun>; const ARun: string): Integer;
var
  mNumber, mIndex: Integer;
begin
  if (ARun = '') and (Length(ARuns) > 0) then
  begin
    Exit(0);
  end;
  if TryStrToInt(ARun, mNumber) and (mNumber >= 1) and (mNumber <= Length(ARuns)) then
  begin
    Exit(mNumber - 1);
  end;
  for mIndex := 0 to High(ARuns) do
  begin
    if SameRunName(ARuns[mIndex].Name, ARun) then
    begin
      Exit(mIndex);
    end;
  end;
  raise EMcpToolError.Create(cTexts[TProfileToolsText.UnknownRun].Fmt([ARun, RunNames(ARuns)]));
end;

function MatchesUnit(const AMethod: TAtlasProfileMethod; const AFilter: string): Boolean;
begin
  Result := (AFilter = '') or ContainsText(AMethod.UnitName, AFilter) or
    ContainsText(ExtractFileName(AMethod.FileName.Replace('/', PathDelim)), AFilter);
end;

/// <summary>Die ersten ARequest.Top Methoden, die zum Filter passen.</summary>
function PickMethods(const AProfile: TAtlasProfile; const ARequest: TMcpProfileRequest): TArray<TAtlasProfileMethod>;
var
  mMethod: TAtlasProfileMethod;
begin
  Result := nil;
  for mMethod in TAtlasProfileAnalysis.Methods(AProfile, ARequest.OwnCodeOnly) do
  begin
    if Length(Result) >= ARequest.Top then
    begin
      Break;
    end;
    if MatchesUnit(mMethod, ARequest.UnitFilter) then
    begin
      Result := Result + [mMethod];
    end;
  end;
end;

function RunLineOf(const ARun: TMcpProfileRun): string;
begin
  Result := cTexts[TProfileToolsText.RunLine].Fmt([ARun.Name, ExtractFileName(ARun.Profile.ProgramName),
    FormatDateTime('dd"."mm"."yyyy hh":"nn', ARun.Profile.StartedAt, TFormatSettings.Invariant),
    ARun.Profile.DurationMs / 1000,
    ARun.Profile.Samples, ARun.Profile.IntervalMs]);
end;

function LibraryText(const AMethod: TAtlasProfileMethod): string;
begin
  Result := '';
  if AMethod.IsLibrary then
  begin
    Result := cTexts[TProfileToolsText.LibraryMark].Text;
  end;
end;

procedure AppendMethods(ABuilder: TStringBuilder; const AProfile: TAtlasProfile;
  const AMethods: TArray<TAtlasProfileMethod>);
var
  mIndex: Integer;
  mMethod: TAtlasProfileMethod;
begin
  for mIndex := 0 to High(AMethods) do
  begin
    mMethod := AMethods[mIndex];
    ABuilder.AppendLine(cTexts[TProfileToolsText.MethodLine].Fmt([mIndex + 1, mMethod.Routine,
      Number(TAtlasProfileAnalysis.Percent(mMethod.SelfCount, AProfile.Samples)),
      Number(TAtlasProfileAnalysis.Percent(mMethod.TotalCount, AProfile.Samples)), LibraryText(mMethod)]));
    if (mMethod.FileName <> '') and (mMethod.HotLine > 0) then
    begin
      ABuilder.AppendLine(cTexts[TProfileToolsText.HotLine].Fmt([mMethod.FileName, mMethod.HotLine]));
    end;
  end;
end;

procedure AppendComparison(ABuilder: TStringBuilder; const ARuns: TArray<TMcpProfileRun>; ARun,
  AOther: Integer; const ARequest: TMcpProfileRequest);
var
  mDeltas: TArray<TAtlasProfileDelta>;
  mIndex: Integer;
begin
  mDeltas := TAtlasProfileAnalysis.Compare(ARuns[AOther].Profile, ARuns[ARun].Profile, ARequest.OwnCodeOnly);
  ABuilder.AppendLine;
  ABuilder.AppendLine(cTexts[TProfileToolsText.CompareTitle].Fmt([ARuns[AOther].Name]));
  for mIndex := 0 to Min(ARequest.Top, Length(mDeltas)) - 1 do
  begin
    ABuilder.AppendLine(cTexts[TProfileToolsText.CompareLine].Fmt([mDeltas[mIndex].Routine,
      Number(mDeltas[mIndex].SelfBefore), Number(mDeltas[mIndex].SelfAfter),
      SignedNumber(mDeltas[mIndex].SelfChange)]));
  end;
end;

function TextReport(const ARuns: TArray<TMcpProfileRun>; ARun, AOther: Integer;
  const ARequest: TMcpProfileRequest): string;
var
  mBuilder: TStringBuilder;
  mMethods: TArray<TAtlasProfileMethod>;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.AppendLine(RunLineOf(ARuns[ARun]));
    mMethods := PickMethods(ARuns[ARun].Profile, ARequest);
    if ARuns[ARun].Profile.Samples = 0 then
    begin
      mBuilder.AppendLine(cTexts[TProfileToolsText.NoSamples].Text);
    end
    else if Length(mMethods) = 0 then
    begin
      mBuilder.AppendLine(cTexts[TProfileToolsText.NoMethods].Fmt([ARequest.UnitFilter]));
    end;
    AppendMethods(mBuilder, ARuns[ARun].Profile, mMethods);
    if AOther >= 0 then
    begin
      AppendComparison(mBuilder, ARuns, ARun, AOther, ARequest);
    end;
    mBuilder.AppendLine;
    mBuilder.Append(cTexts[TProfileToolsText.RunsLine].Fmt([RunNames(ARuns)]));
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

function RunToJson(const ARun: TMcpProfileRun): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', ARun.Name);
  Result.AddPair('program', ARun.Profile.ProgramName);
  Result.AddPair('project', ARun.Profile.Project);
  Result.AddPair('platform', ARun.Profile.Platform);
  Result.AddPair('startedAt', DateToISO8601(ARun.Profile.StartedAt, False));
  Result.AddPair('durationMs', TJSONNumber.Create(ARun.Profile.DurationMs));
  Result.AddPair('intervalMs', TJSONNumber.Create(ARun.Profile.IntervalMs));
  Result.AddPair('samples', TJSONNumber.Create(ARun.Profile.Samples));
end;

function MethodToJson(const AMethod: TAtlasProfileMethod; ASamples: Integer): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('routine', AMethod.Routine);
  Result.AddPair('unit', AMethod.UnitName);
  Result.AddPair('file', AMethod.FileName);
  Result.AddPair('hotLine', TJSONNumber.Create(AMethod.HotLine));
  Result.AddPair('selfPercent', TJSONNumber.Create(TAtlasProfileAnalysis.Percent(AMethod.SelfCount, ASamples)));
  Result.AddPair('totalPercent', TJSONNumber.Create(TAtlasProfileAnalysis.Percent(AMethod.TotalCount, ASamples)));
  Result.AddPair('selfSamples', TJSONNumber.Create(AMethod.SelfCount));
  Result.AddPair('totalSamples', TJSONNumber.Create(AMethod.TotalCount));
  Result.AddPair('library', TJSONBool.Create(AMethod.IsLibrary));
end;

function DeltaToJson(const ADelta: TAtlasProfileDelta): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('routine', ADelta.Routine);
  Result.AddPair('selfBefore', TJSONNumber.Create(ADelta.SelfBefore));
  Result.AddPair('selfAfter', TJSONNumber.Create(ADelta.SelfAfter));
  Result.AddPair('totalBefore', TJSONNumber.Create(ADelta.TotalBefore));
  Result.AddPair('totalAfter', TJSONNumber.Create(ADelta.TotalAfter));
  Result.AddPair('library', TJSONBool.Create(ADelta.IsLibrary));
end;

function ComparisonToJson(const ARuns: TArray<TMcpProfileRun>; ARun, AOther: Integer;
  const ARequest: TMcpProfileRequest): TJSONObject;
var
  mDeltas: TArray<TAtlasProfileDelta>;
  mArray: TJSONArray;
  mIndex: Integer;
begin
  mDeltas := TAtlasProfileAnalysis.Compare(ARuns[AOther].Profile, ARuns[ARun].Profile, ARequest.OwnCodeOnly);
  mArray := TJSONArray.Create;
  for mIndex := 0 to Min(ARequest.Top, Length(mDeltas)) - 1 do
  begin
    mArray.AddElement(DeltaToJson(mDeltas[mIndex]));
  end;
  Result := TJSONObject.Create;
  Result.AddPair('run', RunToJson(ARuns[AOther]));
  Result.AddPair('methods', mArray);
end;

function JsonReport(const ARuns: TArray<TMcpProfileRun>; ARun, AOther: Integer;
  const ARequest: TMcpProfileRequest): string;
var
  mRoot: TJSONObject;
  mMethods, mNames: TJSONArray;
  mMethod: TAtlasProfileMethod;
  mRun: TMcpProfileRun;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('run', RunToJson(ARuns[ARun]));
    mMethods := TJSONArray.Create;
    mRoot.AddPair('methods', mMethods);
    for mMethod in PickMethods(ARuns[ARun].Profile, ARequest) do
    begin
      mMethods.AddElement(MethodToJson(mMethod, ARuns[ARun].Profile.Samples));
    end;
    if AOther >= 0 then
    begin
      mRoot.AddPair('compare', ComparisonToJson(ARuns, ARun, AOther, ARequest));
    end;
    mNames := TJSONArray.Create;
    mRoot.AddPair('runs', mNames);
    for mRun in ARuns do
    begin
      mNames.Add(mRun.Name);
    end;
    Result := mRoot.ToJSON([]);
  finally
    mRoot.Free;
  end;
end;

class function TMcpProfileTools.Report(const ARuns: TArray<TMcpProfileRun>;
  const ARequest: TMcpProfileRequest): string;
var
  mRun, mOther: Integer;
begin
  mRun := SelectRun(ARuns, ARequest.Run);
  mOther := -1;
  if ARequest.CompareWith <> '' then
  begin
    mOther := SelectRun(ARuns, ARequest.CompareWith);
  end;
  if ARequest.AsJson then
  begin
    Result := JsonReport(ARuns, mRun, mOther, ARequest);
  end
  else
  begin
    Result := TextReport(ARuns, mRun, mOther, ARequest);
  end;
end;

class function TMcpProfileTools.NoRuns(const AFolder: string): string;
begin
  Result := cTexts[TProfileToolsText.NoRuns].Fmt([AFolder]);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Mcp.ProfileTools', cTexts);

end.
