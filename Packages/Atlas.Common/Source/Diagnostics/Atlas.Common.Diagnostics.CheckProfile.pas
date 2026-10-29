unit Atlas.Common.Diagnostics.CheckProfile;

// Zeitprofil eines Prüflaufs (#1356): je Unit die Dauer ihrer Prüfung und je
// Regel die Summe ihrer Laufzeit mit Zahl der Aufrufe. Gemessen wird nichts
// zusätzlich: Die Regel-Engine misst jede Regel ohnehin (früher nur für
// slowRule im Diagnoselog) und meldet die Dauer hier, die Projektprüfung bzw.
// --check misst die Dauer je Unit.
//
// - TCheckProfiler sammelt threadsicher. Wer prüft, hängt ihn mit Attach an
//   den eigenen Thread; die Engine findet ihn über RuleTimed. Ohne
//   angehängten Profiler kostet RuleTimed nur das Lesen einer threadvar.
// - Zeiten in Mikrosekunden, damit die vielen kurzen Regeln (unter 1 ms) in
//   der Summe nicht verschwinden; ausgegeben in Millisekunden mit einer
//   Nachkommastelle.
// - Snapshot liefert die ACount langsamsten Units und Regeln, bei Gleichstand
//   eindeutig nach Name (Unit, dann Datei) bzw. Kennung sortiert, dazu die
//   Summen über alle Units und Regeln: Die Summe der Units passt zur Dauer
//   des Laufs, auch wenn nur die langsamsten angezeigt werden.
// - Eine Unit, die mehrmals drankommt (Frist abgelaufen, unterbrochen),
//   zählt mit der Summe aller Versuche.
// - TCheckTimings ist der Bericht von --check --timings: Profil, Indexzeit
//   und Speicher als Markdown oder JSON.

interface

uses
  System.SysUtils,
  System.JSON,
  System.SyncObjs,
  System.Generics.Collections;

type
  TCheckProfileUnit = record
    /// <summary>Unit-Name (Dateiname ohne Endung).</summary>
    Name: string;
    /// <summary>Voller Pfad zum Öffnen; '' im anonymisierten Status.</summary>
    FileName: string;
    Ms: Double;
  end;

  TCheckProfileRule = record
    Id: string;
    /// <summary>Summe über den Lauf.</summary>
    Ms: Double;
    Calls: Integer;
  end;

  /// <summary>Wandelt einen Unit-Namen für den anonymisierten Status um (z. B. in name#3).</summary>
  TCheckProfileNameFunc = reference to function(const AName: string): string;

  TCheckRunProfile = record
  public const
    /// <summary>So viele Units und Regeln zeigen Fenster, Status und --check.</summary>
    cTop = 10;
  public
    /// <summary>Nummer des Laufs; 0 = noch keiner.</summary>
    Serial: Integer;
    Active: Boolean;
    /// <summary>Beginn des Laufs (Ortszeit); 0 = noch keiner.</summary>
    Started: TDateTime;
    DurationMs: Int64;
    /// <summary>Tatsächlich geprüfte Units.</summary>
    Units: Integer;
    /// <summary>Summe über alle geprüften Units bzw. alle Regelaufrufe.</summary>
    UnitMs: Double;
    RuleMs: Double;
    SlowUnits: TArray<TCheckProfileUnit>;
    SlowRules: TArray<TCheckProfileRule>;
    /// <summary>Kopie mit umgewandelten Unit-Namen und ohne Pfade.</summary>
    function Anonymized(const AName: TCheckProfileNameFunc): TCheckRunProfile;
    /// <summary>Der Aufrufer übernimmt das Objekt.</summary>
    function ToJson: TJSONObject;
    /// <summary>Tabellen der langsamsten Units und Regeln als Markdown; '' vor dem ersten Lauf.</summary>
    function ToMarkdown: string;
    class function Milliseconds(AMicroseconds: Int64): Double; static;
  end;

  /// <summary>Bericht von --check --timings (#1356).</summary>
  TCheckTimings = record
    Profile: TCheckRunProfile;
    /// <summary>Aufbau des Symbolindex in ms; -1 ohne Index (--no-index).</summary>
    IndexMs: Int64;
    IndexUnits: Integer;
    /// <summary>Speicher des Index nach Bereichen und Heap gesamt in Byte; Total -1 = unbekannt.</summary>
    ProjectBytes: Int64;
    LibraryBytes: Int64;
    UsageBytes: Int64;
    TotalBytes: Int64;
    function ToMarkdown: string;
    /// <summary>Der Aufrufer übernimmt das Objekt.</summary>
    function ToJson: TJSONObject;
    /// <summary>Endung .json: JSON, sonst Markdown.</summary>
    class function IsJsonFile(const AFileName: string): Boolean; static;
  end;

  TCheckProfiler = class
  private type
    TUnitEntry = record
      FileName: string;
      Microseconds: Int64;
    end;
    TRuleEntry = record
      Microseconds: Int64;
      Calls: Integer;
    end;
  private
    FLock: TCriticalSection;
    FSerial: Integer;
    FActive: Boolean;
    FStarted: TDateTime;
    FDurationMs: Int64;
    // Schlüssel: Datei ohne Groß-/Kleinschreibung.
    FUnits: TDictionary<string, TUnitEntry>;
    FRules: TDictionary<string, TRuleEntry>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Neuer Lauf: vergisst den vorigen.</summary>
    procedure BeginRun(AStarted: TDateTime);
    procedure FinishRun(ADurationMs: Int64);
    /// <summary>Dauer der Prüfung einer Unit; mehrere Versuche addieren sich.</summary>
    procedure AddUnit(const AFileName: string; AMicroseconds: Int64);
    procedure AddRule(const ARuleId: string; AMicroseconds: Int64);
    /// <summary>Stand mit den ACount langsamsten Units und Regeln; ARunningMs: Dauer eines laufenden Laufs.</summary>
    function Snapshot(ACount: Integer; ARunningMs: Int64): TCheckRunProfile; overload;
    function Snapshot(ACount: Integer): TCheckRunProfile; overload;
    /// <summary>Hängt AProfiler an den aktuellen Thread (nil löst ihn); liefert den bisherigen.</summary>
    class function Attach(AProfiler: TCheckProfiler): TCheckProfiler; static;
    /// <summary>Von der Regel-Engine: Laufzeit einer Regel an den Profiler des Threads; ohne ihn nichts.</summary>
    class procedure RuleTimed(const ARuleId: string; AMicroseconds: Int64); static;
    /// <summary>Mikrosekunden aus Ticks von TStopwatch.</summary>
    class function TicksToMicroseconds(ATicks, AFrequency: Int64): Int64; static;
  end;

implementation

uses
  System.Math,
  System.DateUtils,
  System.Generics.Defaults;

threadvar
  CurrentProfiler: TCheckProfiler;

function MsText(AValue: Double): string;
begin
  Result := FormatFloat('0.0', AValue, TFormatSettings.Invariant);
end;

{ TCheckRunProfile }

class function TCheckRunProfile.Milliseconds(AMicroseconds: Int64): Double;
begin
  Result := RoundTo(AMicroseconds / 1000, -1);
end;

function TCheckRunProfile.Anonymized(const AName: TCheckProfileNameFunc): TCheckRunProfile;
var
  mIndex: Integer;
begin
  Result := Self;
  Result.SlowUnits := Copy(SlowUnits);
  for mIndex := 0 to High(Result.SlowUnits) do
  begin
    Result.SlowUnits[mIndex].Name := AName(Result.SlowUnits[mIndex].Name);
    Result.SlowUnits[mIndex].FileName := '';
  end;
end;

function TCheckRunProfile.ToJson: TJSONObject;
var
  mItems: TJSONArray;
  mItem: TJSONObject;
  mUnit: TCheckProfileUnit;
  mRule: TCheckProfileRule;
begin
  Result := TJSONObject.Create;
  Result.AddPair('serial', TJSONNumber.Create(Serial));
  Result.AddPair('active', TJSONBool.Create(Active));
  if Started = 0 then
    Result.AddPair('started', '')
  else
    Result.AddPair('started', DateToISO8601(Started, False));
  Result.AddPair('durationMs', TJSONNumber.Create(DurationMs));
  Result.AddPair('units', TJSONNumber.Create(Units));
  Result.AddPair('unitMs', TJSONNumber.Create(UnitMs));
  Result.AddPair('ruleMs', TJSONNumber.Create(RuleMs));
  mItems := TJSONArray.Create;
  for mUnit in SlowUnits do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('name', mUnit.Name);
    if mUnit.FileName <> '' then
      mItem.AddPair('file', mUnit.FileName);
    mItem.AddPair('ms', TJSONNumber.Create(mUnit.Ms));
    mItems.AddElement(mItem);
  end;
  Result.AddPair('slowUnits', mItems);
  mItems := TJSONArray.Create;
  for mRule in SlowRules do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('id', mRule.Id);
    mItem.AddPair('ms', TJSONNumber.Create(mRule.Ms));
    mItem.AddPair('calls', TJSONNumber.Create(mRule.Calls));
    mItems.AddElement(mItem);
  end;
  Result.AddPair('slowRules', mItems);
end;

function TCheckRunProfile.ToMarkdown: string;
var
  mBuilder: TStringBuilder;
  mUnit: TCheckProfileUnit;
  mRule: TCheckProfileRule;
begin
  if Serial = 0 then
    Exit('');
  mBuilder := TStringBuilder.Create;
  try
    if Active then
      mBuilder.Append(Format('Prüflauf läuft seit %d ms: %d Units geprüft', [DurationMs, Units]))
    else
      mBuilder.Append(Format('Letzter Prüflauf: %d Units in %d ms', [Units, DurationMs]));
    if Started <> 0 then
      mBuilder.Append(', Beginn ').Append(FormatDateTime('dd.mm.yyyy hh":"nn":"ss', Started));
    mBuilder.Append(Format(' (Summe Units %s ms, Summe Regeln %s ms)', [MsText(UnitMs), MsText(RuleMs)]));
    mBuilder.Append(#10);
    if Length(SlowUnits) > 0 then
    begin
      mBuilder.Append(#10).Append('| Langsamste Units | ms |').Append(#10);
      mBuilder.Append('|---|---:|').Append(#10);
      for mUnit in SlowUnits do
        mBuilder.Append(Format('| %s | %s |', [mUnit.Name, MsText(mUnit.Ms)])).Append(#10);
    end;
    if Length(SlowRules) > 0 then
    begin
      mBuilder.Append(#10).Append('| Langsamste Regeln | ms | Aufrufe |').Append(#10);
      mBuilder.Append('|---|---:|---:|').Append(#10);
      for mRule in SlowRules do
        mBuilder.Append(Format('| %s | %s | %d |', [mRule.Id, MsText(mRule.Ms), mRule.Calls])).Append(#10);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

{ TCheckTimings }

function MegaBytes(ABytes: Int64): string;
begin
  Result := FormatFloat('0.0', ABytes / (1024 * 1024), TFormatSettings.Invariant);
end;

class function TCheckTimings.IsJsonFile(const AFileName: string): Boolean;
begin
  Result := SameText(ExtractFileExt(AFileName), '.json');
end;

function TCheckTimings.ToMarkdown: string;
var
  mBuilder: TStringBuilder;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('# Atlas --check: Zeitprofil').Append(#10#10);
    if IndexMs >= 0 then
      mBuilder.Append(Format('- Symbolindex: %d Units in %d ms', [IndexUnits, IndexMs])).Append(#10)
    else
      mBuilder.Append('- Symbolindex: keiner (--no-index)').Append(#10);
    mBuilder.Append(Format('- Prüfung: %d Units in %d ms', [Profile.Units, Profile.DurationMs])).Append(#10);
    mBuilder.Append(#10).Append('| Speicher | MB |').Append(#10);
    mBuilder.Append('|---|---:|').Append(#10);
    mBuilder.Append('| Symbole | ').Append(MegaBytes(ProjectBytes)).Append(' |').Append(#10);
    mBuilder.Append('| Bibliotheks-Units | ').Append(MegaBytes(LibraryBytes)).Append(' |').Append(#10);
    mBuilder.Append('| Verwendungen | ').Append(MegaBytes(UsageBytes)).Append(' |').Append(#10);
    if TotalBytes >= 0 then
      mBuilder.Append('| Gesamt (Heap) | ').Append(MegaBytes(TotalBytes)).Append(' |').Append(#10);
    if Profile.Serial > 0 then
      mBuilder.Append(#10).Append(Profile.ToMarkdown);
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

function TCheckTimings.ToJson: TJSONObject;
var
  mIndex, mMemory: TJSONObject;
begin
  Result := TJSONObject.Create;
  mIndex := TJSONObject.Create;
  mIndex.AddPair('ms', TJSONNumber.Create(IndexMs));
  mIndex.AddPair('units', TJSONNumber.Create(IndexUnits));
  Result.AddPair('index', mIndex);
  mMemory := TJSONObject.Create;
  mMemory.AddPair('symbols', TJSONNumber.Create(ProjectBytes));
  mMemory.AddPair('libraryUnits', TJSONNumber.Create(LibraryBytes));
  mMemory.AddPair('usages', TJSONNumber.Create(UsageBytes));
  mMemory.AddPair('total', TJSONNumber.Create(TotalBytes));
  Result.AddPair('memory', mMemory);
  Result.AddPair('checkRun', Profile.ToJson);
end;

{ TCheckProfiler }

constructor TCheckProfiler.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FUnits := TDictionary<string, TUnitEntry>.Create;
  FRules := TDictionary<string, TRuleEntry>.Create;
end;

destructor TCheckProfiler.Destroy;
begin
  FRules.Free;
  FUnits.Free;
  FLock.Free;
  inherited;
end;

procedure TCheckProfiler.BeginRun(AStarted: TDateTime);
begin
  FLock.Enter;
  try
    Inc(FSerial);
    FActive := True;
    FStarted := AStarted;
    FDurationMs := 0;
    FUnits.Clear;
    FRules.Clear;
  finally
    FLock.Leave;
  end;
end;

procedure TCheckProfiler.FinishRun(ADurationMs: Int64);
begin
  FLock.Enter;
  try
    FActive := False;
    FDurationMs := ADurationMs;
  finally
    FLock.Leave;
  end;
end;

procedure TCheckProfiler.AddUnit(const AFileName: string; AMicroseconds: Int64);
var
  mKey: string;
  mEntry: TUnitEntry;
begin
  mKey := AnsiLowerCase(AFileName);
  FLock.Enter;
  try
    if not FUnits.TryGetValue(mKey, mEntry) then
    begin
      mEntry.FileName := AFileName;
      mEntry.Microseconds := 0;
    end;
    Inc(mEntry.Microseconds, AMicroseconds);
    FUnits.AddOrSetValue(mKey, mEntry);
  finally
    FLock.Leave;
  end;
end;

procedure TCheckProfiler.AddRule(const ARuleId: string; AMicroseconds: Int64);
var
  mEntry: TRuleEntry;
begin
  FLock.Enter;
  try
    if not FRules.TryGetValue(ARuleId, mEntry) then
      mEntry := Default(TRuleEntry);
    Inc(mEntry.Microseconds, AMicroseconds);
    Inc(mEntry.Calls);
    FRules.AddOrSetValue(ARuleId, mEntry);
  finally
    FLock.Leave;
  end;
end;

function TCheckProfiler.Snapshot(ACount: Integer): TCheckRunProfile;
begin
  Result := Snapshot(ACount, -1);
end;

function TCheckProfiler.Snapshot(ACount: Integer; ARunningMs: Int64): TCheckRunProfile;
var
  mUnits: TList<TCheckProfileUnit>;
  mRules: TList<TCheckProfileRule>;
  mUnitPair: TPair<string, TUnitEntry>;
  mRulePair: TPair<string, TRuleEntry>;
  mUnit: TCheckProfileUnit;
  mRule: TCheckProfileRule;
  mUnitSum, mRuleSum: Int64;
begin
  Result := Default(TCheckRunProfile);
  mUnits := TList<TCheckProfileUnit>.Create;
  mRules := TList<TCheckProfileRule>.Create;
  try
    mUnitSum := 0;
    mRuleSum := 0;
    FLock.Enter;
    try
      Result.Serial := FSerial;
      Result.Active := FActive;
      Result.Started := FStarted;
      Result.DurationMs := FDurationMs;
      if FActive and (ARunningMs >= 0) then
        Result.DurationMs := ARunningMs;
      Result.Units := FUnits.Count;
      for mUnitPair in FUnits do
      begin
        mUnit.FileName := mUnitPair.Value.FileName;
        mUnit.Name := ChangeFileExt(ExtractFileName(mUnitPair.Value.FileName), '');
        mUnit.Ms := TCheckRunProfile.Milliseconds(mUnitPair.Value.Microseconds);
        mUnits.Add(mUnit);
        Inc(mUnitSum, mUnitPair.Value.Microseconds);
      end;
      for mRulePair in FRules do
      begin
        mRule.Id := mRulePair.Key;
        mRule.Ms := TCheckRunProfile.Milliseconds(mRulePair.Value.Microseconds);
        mRule.Calls := mRulePair.Value.Calls;
        mRules.Add(mRule);
        Inc(mRuleSum, mRulePair.Value.Microseconds);
      end;
    finally
      FLock.Leave;
    end;
    Result.UnitMs := TCheckRunProfile.Milliseconds(mUnitSum);
    Result.RuleMs := TCheckRunProfile.Milliseconds(mRuleSum);
    // Nicht stabil sortiert: bei Gleichstand eindeutig über Name und Datei bzw. Kennung.
    mUnits.Sort(TComparer<TCheckProfileUnit>.Construct(
      function(const ALeft, ARight: TCheckProfileUnit): Integer
      begin
        Result := CompareValue(ARight.Ms, ALeft.Ms);
        if Result = 0 then
          Result := CompareText(ALeft.Name, ARight.Name);
        if Result = 0 then
          Result := CompareText(ALeft.FileName, ARight.FileName);
        if Result = 0 then
          Result := CompareStr(ALeft.FileName, ARight.FileName);
      end));
    mRules.Sort(TComparer<TCheckProfileRule>.Construct(
      function(const ALeft, ARight: TCheckProfileRule): Integer
      begin
        Result := CompareValue(ARight.Ms, ALeft.Ms);
        if Result = 0 then
          Result := CompareStr(ALeft.Id, ARight.Id);
      end));
    while mUnits.Count > ACount do
      mUnits.Delete(mUnits.Count - 1);
    while mRules.Count > ACount do
      mRules.Delete(mRules.Count - 1);
    Result.SlowUnits := mUnits.ToArray;
    Result.SlowRules := mRules.ToArray;
  finally
    mRules.Free;
    mUnits.Free;
  end;
end;

class function TCheckProfiler.Attach(AProfiler: TCheckProfiler): TCheckProfiler;
begin
  Result := CurrentProfiler;
  CurrentProfiler := AProfiler;
end;

class procedure TCheckProfiler.RuleTimed(const ARuleId: string; AMicroseconds: Int64);
var
  mProfiler: TCheckProfiler;
begin
  mProfiler := CurrentProfiler;
  if mProfiler <> nil then
    mProfiler.AddRule(ARuleId, AMicroseconds);
end;

class function TCheckProfiler.TicksToMicroseconds(ATicks, AFrequency: Int64): Int64;
begin
  if AFrequency <= 0 then
    Exit(0);
  // In zwei Schritten, damit ATicks * 1000000 bei langen Läufen nicht überläuft.
  Result := (ATicks div AFrequency) * 1000000 + ((ATicks mod AFrequency) * 1000000) div AFrequency;
end;

end.
