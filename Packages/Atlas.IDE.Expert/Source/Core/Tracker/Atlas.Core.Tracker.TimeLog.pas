unit Atlas.Core.Tracker.TimeLog;

// Erfasste Zeit je Issue und Tag (#1267), ohne VCL und Open Tools API.
// - TAtlasTimeIssue: Issue mit Anbieter, Adresse und Projekt des Trackers, damit
//   eine offene Buchung auch nach einem Projektwechsel ihr Ziel kennt.
// - TAtlasTimeLog: Einträge je Issue und Tag mit Sekunden und dem Zeitpunkt,
//   bis zu dem gezählt ist ("last"). Add verteilt eine Spanne auf die Tage und
//   zählt nur, was nach "last" liegt: Zwei IDE-Instanzen, die dieselbe Zeit
//   melden, addieren sie nicht doppelt. Subtract zieht gebuchte bzw.
//   verworfene Zeit vom ältesten Tag an ab; SetTotal korrigiert die Summe.
// - Datei %LOCALAPPDATA%\Atlas\time.json (JSON, "version": 1); TAtlasTimeFile
//   liest und ändert sie nur unter der Sperrdatei time.json.lock (exklusiv
//   geöffnet, bis LockWaitMs wiederholt). Eine unlesbare Datei wird nie
//   überschrieben.
// - TAtlasTimeRounding: Rundung der vorgeschlagenen Dauer, Anzeige "1:25",
//   Dauer für YouTrack ("1h 25m") und Eingabe der Dauer ("1:25", "85",
//   "1 h 25 min", "1,5 h").
// Zeiten sind lokale Zeit der IDE; ein Tag ist Trunc(Zeit).

interface

uses
  System.SysUtils;

type
  /// <summary>Issue, auf das Zeit gezählt wird.</summary>
  TAtlasTimeIssue = record
    /// <summary>"github" oder "youtrack".</summary>
    Provider: string;
    /// <summary>Adresse des Trackers ohne "/" am Ende.</summary>
    Url: string;
    /// <summary>Projekt wie in TAtlasTrackerTarget ('' erlaubt).</summary>
    Project: string;
    Key: string;
    class function Create(const AProvider, AUrl, AProject, AKey: string): TAtlasTimeIssue; static;
    class function None: TAtlasTimeIssue; static;
    function IsEmpty: Boolean;
    /// <summary>Vergleichswert: Adresse und Projekt klein, Kennung groß.</summary>
    function Id: string;
    function Same(const AOther: TAtlasTimeIssue): Boolean;
  end;

  /// <summary>Zeitraum aktiver Arbeit an einem Issue.</summary>
  TAtlasTimeSpan = record
    Issue: TAtlasTimeIssue;
    StartAt: TDateTime;
    EndAt: TDateTime;
    class function Create(const AIssue: TAtlasTimeIssue; AStartAt, AEndAt: TDateTime): TAtlasTimeSpan; static;
    function Seconds: Int64;
  end;

  /// <summary>Gezählte Zeit eines Issues an einem Tag.</summary>
  TAtlasTimeEntry = record
    Issue: TAtlasTimeIssue;
    /// <summary>Trunc(Datum).</summary>
    Day: Integer;
    Seconds: Int64;
    /// <summary>Bis hierhin ist gezählt (gegen doppeltes Zählen mehrerer IDE-Instanzen).</summary>
    Last: TDateTime;
  end;

  /// <summary>Noch nicht gebuchte Zeit eines Issues über alle Tage.</summary>
  TAtlasTimeOpen = record
    Issue: TAtlasTimeIssue;
    Seconds: Int64;
    FirstDay: Integer;
    LastDay: Integer;
  end;

  TAtlasTimeLog = record
  public const
    Version = 1;
  public
    Entries: TArray<TAtlasTimeEntry>;
    class function Empty: TAtlasTimeLog; static;
    /// <summary>False bei ungültigem JSON oder fremder Version (die Datei bleibt dann unangetastet).</summary>
    class function Parse(const AJson: string; out ALog: TAtlasTimeLog): Boolean; static;
    function ToJson: string;
    /// <summary>ASpan auf die Tage verteilen; Zeit vor "last" des Tages zählt nicht noch einmal.</summary>
    procedure Add(const ASpan: TAtlasTimeSpan);
    /// <summary>Sekunden von AIssue über alle Tage.</summary>
    function Total(const AIssue: TAtlasTimeIssue): Int64;
    /// <summary>Gebuchte oder verworfene Zeit vom ältesten Tag an abziehen.</summary>
    procedure Subtract(const AIssue: TAtlasTimeIssue; ASeconds: Int64);
    /// <summary>Summe von AIssue korrigieren: alles auf den Tag AToday.</summary>
    procedure SetTotal(const AIssue: TAtlasTimeIssue; ASeconds: Int64; AToday: TDateTime);
    /// <summary>Issues mit Zeit, zuletzt bearbeitete zuerst.</summary>
    function Open: TArray<TAtlasTimeOpen>;
  private
    function IndexOf(const AIssue: TAtlasTimeIssue; ADay: Integer): Integer;
    function AddEntry(const AIssue: TAtlasTimeIssue; ADay: Integer): Integer;
    procedure Prune(const AIssue: TAtlasTimeIssue);
  end;

  /// <summary>Änderung an der Datei unter der Sperre.</summary>
  TAtlasTimeLogChange = reference to procedure(var ALog: TAtlasTimeLog);

  TAtlasTimeFile = class
  public const
    FileName = 'time.json';
    LockExtension = '.lock';
    /// <summary>So lange wartet ein Zugriff auf die Sperre einer anderen IDE-Instanz.</summary>
    LockWaitMs = 2000;
  public
    /// <summary>%LOCALAPPDATA%\Atlas\time.json.</summary>
    class function DefaultPath: string; static;
    /// <summary>Datei lesen; eine fehlende Datei ist leer. False ohne Sperre oder bei unlesbarer Datei.</summary>
    class function Read(const APath: string; out ALog: TAtlasTimeLog): Boolean; static;
    /// <summary>Lesen, AChange anwenden, schreiben, alles unter der Sperre; ALog ist der neue Stand. False ohne
    /// Sperre, bei unlesbarer Datei (bleibt unangetastet) oder wenn das Schreiben scheitert.</summary>
    class function Update(const APath: string; const AChange: TAtlasTimeLogChange;
      out ALog: TAtlasTimeLog): Boolean; static;
  end;

  TAtlasTimeRounding = class
  public const
    /// <summary>Größte Dauer, die die Eingabe annimmt (eine Woche).</summary>
    MaxMinutes = 7 * 24 * 60;
  public
    /// <summary>ASeconds auf AStep Minuten gerundet (kaufmännisch); mindestens AStep, sobald Zeit da ist.</summary>
    class function Minutes(ASeconds: Int64; AStep: Integer): Integer; static;
    /// <summary>Anzeige im Statusfeld: "1:25" (Stunden:Minuten, abgeschnitten).</summary>
    class function ClockText(ASeconds: Int64): string; static;
    /// <summary>Dauer für YouTrack: "1h 25m", "45m", "2h"; '' bei 0.</summary>
    class function Presentation(AMinutes: Integer): string; static;
    /// <summary>Eingabe "1:25", "85", "85 min", "1 h 25 min", "1h 25m", "1,5 h"; False bei 0, zu groß oder
    /// unlesbar.</summary>
    class function ParseDuration(const AText: string; out AMinutes: Integer): Boolean; static;
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.IOUtils,
  System.JSON;

{ TAtlasTimeIssue }

class function TAtlasTimeIssue.Create(const AProvider, AUrl, AProject, AKey: string): TAtlasTimeIssue;
begin
  Result.Provider := LowerCase(Trim(AProvider));
  Result.Url := Trim(AUrl);
  while Result.Url.EndsWith('/') do
    Result.Url := Copy(Result.Url, 1, Length(Result.Url) - 1);
  Result.Project := Trim(AProject);
  Result.Key := Trim(AKey);
end;

class function TAtlasTimeIssue.None: TAtlasTimeIssue;
begin
  Result := Create('', '', '', '');
end;

function TAtlasTimeIssue.IsEmpty: Boolean;
begin
  Result := Key = '';
end;

function TAtlasTimeIssue.Id: string;
begin
  Result := LowerCase(Url) + '|' + LowerCase(Project) + '|' + UpperCase(Key);
end;

function TAtlasTimeIssue.Same(const AOther: TAtlasTimeIssue): Boolean;
begin
  Result := Id = AOther.Id;
end;

{ TAtlasTimeSpan }

class function TAtlasTimeSpan.Create(const AIssue: TAtlasTimeIssue; AStartAt, AEndAt: TDateTime): TAtlasTimeSpan;
begin
  Result.Issue := AIssue;
  Result.StartAt := AStartAt;
  Result.EndAt := AEndAt;
end;

function TAtlasTimeSpan.Seconds: Int64;
begin
  Result := 0;
  if EndAt > StartAt then
    Result := Round((EndAt - StartAt) * SecsPerDay);
end;

{ TAtlasTimeLog }

function DayText(ADay: Integer): string;
begin
  Result := FormatDateTime('yyyy"-"mm"-"dd', ADay);
end;

function TimeText(AValue: TDateTime): string;
begin
  Result := FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss', AValue);
end;

function ParseDay(const AText: string; out ADay: Integer): Boolean;
var
  mYear, mMonth, mDay: Integer;
  mDate: TDateTime;
begin
  Result := (Length(AText) = 10) and (AText[5] = '-') and (AText[8] = '-') and
    TryStrToInt(Copy(AText, 1, 4), mYear) and TryStrToInt(Copy(AText, 6, 2), mMonth) and
    TryStrToInt(Copy(AText, 9, 2), mDay) and TryEncodeDate(mYear, mMonth, mDay, mDate);
  ADay := 0;
  if Result then
    ADay := Trunc(mDate);
end;

function ParseTime(const AText: string; out ATime: TDateTime): Boolean;
var
  mDay, mHour, mMinute, mSecond: Integer;
  mClock: TDateTime;
begin
  ATime := 0;
  Result := (Length(AText) = 19) and (AText[11] = 'T') and ParseDay(Copy(AText, 1, 10), mDay) and
    TryStrToInt(Copy(AText, 12, 2), mHour) and TryStrToInt(Copy(AText, 15, 2), mMinute) and
    TryStrToInt(Copy(AText, 18, 2), mSecond) and TryEncodeTime(mHour, mMinute, mSecond, 0, mClock);
  if Result then
    ATime := mDay + mClock;
end;

function TextOf(AObject: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := AObject.Values[AName];
  if mValue is TJSONString then
    Result := TJSONString(mValue).Value;
end;

class function TAtlasTimeLog.Empty: TAtlasTimeLog;
begin
  Result.Entries := nil;
end;

class function TAtlasTimeLog.Parse(const AJson: string; out ALog: TAtlasTimeLog): Boolean;
var
  mValue, mItems, mItem, mSeconds, mVersion: TJSONValue;
  mEntry: TAtlasTimeEntry;
  mObject: TJSONObject;
  mText: string;
begin
  ALog := Empty;
  mText := AJson;
  // Mit oder ohne BOM geschrieben.
  if mText.StartsWith(#$FEFF) then
    mText := Copy(mText, 2, MaxInt);
  if Trim(mText) = '' then
    Exit(True);
  Result := False;
  mValue := TJSONObject.ParseJSONValue(mText);
  try
    if not (mValue is TJSONObject) then
      Exit;
    mVersion := TJSONObject(mValue).Values['version'];
    if not (mVersion is TJSONNumber) or (TJSONNumber(mVersion).AsInt <> Version) then
      Exit;
    mItems := TJSONObject(mValue).Values['entries'];
    if (mItems <> nil) and not (mItems is TJSONArray) then
      Exit;
    Result := True;
    if mItems = nil then
      Exit;
    for mItem in TJSONArray(mItems) do
    begin
      if not (mItem is TJSONObject) then
        Continue;
      mObject := TJSONObject(mItem);
      mEntry.Issue := TAtlasTimeIssue.Create(TextOf(mObject, 'provider'), TextOf(mObject, 'url'),
        TextOf(mObject, 'project'), TextOf(mObject, 'key'));
      mSeconds := mObject.Values['seconds'];
      // Unvollständige Einträge fallen weg, der Rest bleibt.
      if mEntry.Issue.IsEmpty or not (mSeconds is TJSONNumber) or
        not ParseDay(TextOf(mObject, 'date'), mEntry.Day) then
        Continue;
      mEntry.Seconds := TJSONNumber(mSeconds).AsInt64;
      if mEntry.Seconds < 0 then
        mEntry.Seconds := 0;
      if not ParseTime(TextOf(mObject, 'last'), mEntry.Last) then
        mEntry.Last := 0;
      ALog.Entries := ALog.Entries + [mEntry];
    end;
  finally
    mValue.Free;
  end;
end;

function TAtlasTimeLog.ToJson: string;
var
  mRoot, mObject: TJSONObject;
  mItems: TJSONArray;
  mEntry: TAtlasTimeEntry;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('version', TJSONNumber.Create(Version));
    mItems := TJSONArray.Create;
    mRoot.AddPair('entries', mItems);
    for mEntry in Entries do
    begin
      mObject := TJSONObject.Create;
      mObject.AddPair('provider', mEntry.Issue.Provider);
      mObject.AddPair('url', mEntry.Issue.Url);
      mObject.AddPair('project', mEntry.Issue.Project);
      mObject.AddPair('key', mEntry.Issue.Key);
      mObject.AddPair('date', DayText(mEntry.Day));
      mObject.AddPair('seconds', TJSONNumber.Create(mEntry.Seconds));
      if mEntry.Last > 0 then
        mObject.AddPair('last', TimeText(mEntry.Last));
      mItems.AddElement(mObject);
    end;
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

function TAtlasTimeLog.IndexOf(const AIssue: TAtlasTimeIssue; ADay: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Entries) do
    if (Entries[mIndex].Day = ADay) and Entries[mIndex].Issue.Same(AIssue) then
      Exit(mIndex);
  Result := -1;
end;

function TAtlasTimeLog.AddEntry(const AIssue: TAtlasTimeIssue; ADay: Integer): Integer;
var
  mEntry: TAtlasTimeEntry;
begin
  Result := IndexOf(AIssue, ADay);
  if Result >= 0 then
    Exit;
  mEntry.Issue := AIssue;
  mEntry.Day := ADay;
  mEntry.Seconds := 0;
  mEntry.Last := 0;
  Entries := Entries + [mEntry];
  Result := High(Entries);
end;

procedure TAtlasTimeLog.Add(const ASpan: TAtlasTimeSpan);
var
  mFrom, mTo, mDayEnd: TDateTime;
  mIndex: Integer;
  mPart: TAtlasTimeSpan;
begin
  if ASpan.Issue.IsEmpty or (ASpan.EndAt <= ASpan.StartAt) then
    Exit;
  mFrom := ASpan.StartAt;
  while mFrom < ASpan.EndAt do
  begin
    // Ein Stück je Tag; Mitternacht gehört zum neuen Tag.
    mDayEnd := Trunc(mFrom) + 1;
    mTo := ASpan.EndAt;
    if mTo > mDayEnd then
      mTo := mDayEnd;
    mIndex := AddEntry(ASpan.Issue, Trunc(mFrom));
    mPart := TAtlasTimeSpan.Create(ASpan.Issue, mFrom, mTo);
    if Entries[mIndex].Last > mPart.StartAt then
      mPart.StartAt := Entries[mIndex].Last;
    Inc(Entries[mIndex].Seconds, mPart.Seconds);
    if mTo > Entries[mIndex].Last then
      Entries[mIndex].Last := mTo;
    mFrom := mTo;
  end;
end;

function TAtlasTimeLog.Total(const AIssue: TAtlasTimeIssue): Int64;
var
  mEntry: TAtlasTimeEntry;
begin
  Result := 0;
  for mEntry in Entries do
    if mEntry.Issue.Same(AIssue) then
      Inc(Result, mEntry.Seconds);
end;

procedure TAtlasTimeLog.Prune(const AIssue: TAtlasTimeIssue);
var
  mIndex, mNewest: Integer;
begin
  // Leere Tage fallen weg; der jüngste bleibt mit "last", damit eine andere Instanz nichts neu zählt.
  mNewest := -1;
  for mIndex := 0 to High(Entries) do
    if Entries[mIndex].Issue.Same(AIssue) and ((mNewest < 0) or (Entries[mIndex].Day > Entries[mNewest].Day)) then
      mNewest := mIndex;
  for mIndex := High(Entries) downto 0 do
    if (mIndex <> mNewest) and (Entries[mIndex].Seconds = 0) and Entries[mIndex].Issue.Same(AIssue) then
      Delete(Entries, mIndex, 1);
end;

procedure TAtlasTimeLog.Subtract(const AIssue: TAtlasTimeIssue; ASeconds: Int64);
var
  mIndex, mOldest: Integer;
  mTake: Int64;
begin
  while ASeconds > 0 do
  begin
    mOldest := -1;
    for mIndex := 0 to High(Entries) do
      if Entries[mIndex].Issue.Same(AIssue) and (Entries[mIndex].Seconds > 0) and
        ((mOldest < 0) or (Entries[mIndex].Day < Entries[mOldest].Day)) then
        mOldest := mIndex;
    if mOldest < 0 then
      Break;
    mTake := Entries[mOldest].Seconds;
    if mTake > ASeconds then
      mTake := ASeconds;
    Dec(Entries[mOldest].Seconds, mTake);
    Dec(ASeconds, mTake);
  end;
  Prune(AIssue);
end;

procedure TAtlasTimeLog.SetTotal(const AIssue: TAtlasTimeIssue; ASeconds: Int64; AToday: TDateTime);
var
  mIndex: Integer;
  mLast: TDateTime;
begin
  if AIssue.IsEmpty then
    Exit;
  mLast := 0;
  for mIndex := 0 to High(Entries) do
    if Entries[mIndex].Issue.Same(AIssue) then
    begin
      if Entries[mIndex].Last > mLast then
        mLast := Entries[mIndex].Last;
      Entries[mIndex].Seconds := 0;
    end;
  mIndex := AddEntry(AIssue, Trunc(AToday));
  if ASeconds > 0 then
    Entries[mIndex].Seconds := ASeconds;
  if mLast > Entries[mIndex].Last then
    Entries[mIndex].Last := mLast;
  Prune(AIssue);
end;

function TAtlasTimeLog.Open: TArray<TAtlasTimeOpen>;
var
  mEntry: TAtlasTimeEntry;
  mIndex, mFound: Integer;
  mItem: TAtlasTimeOpen;
begin
  Result := nil;
  for mEntry in Entries do
  begin
    if mEntry.Seconds <= 0 then
      Continue;
    mFound := -1;
    for mIndex := 0 to High(Result) do
      if Result[mIndex].Issue.Same(mEntry.Issue) then
        mFound := mIndex;
    if mFound < 0 then
    begin
      mItem.Issue := mEntry.Issue;
      mItem.Seconds := 0;
      mItem.FirstDay := mEntry.Day;
      mItem.LastDay := mEntry.Day;
      Result := Result + [mItem];
      mFound := High(Result);
    end;
    Inc(Result[mFound].Seconds, mEntry.Seconds);
    if mEntry.Day < Result[mFound].FirstDay then
      Result[mFound].FirstDay := mEntry.Day;
    if mEntry.Day > Result[mFound].LastDay then
      Result[mFound].LastDay := mEntry.Day;
  end;
  // Sort ist nicht stabil: bei gleichem Tag nach Kennung weiter.
  TArray.Sort<TAtlasTimeOpen>(Result, TComparer<TAtlasTimeOpen>.Construct(
    function(const ALeft, ARight: TAtlasTimeOpen): Integer
    begin
      Result := ARight.LastDay - ALeft.LastDay;
      if Result = 0 then
        Result := CompareText(ALeft.Issue.Id, ARight.Issue.Id);
    end));
end;

{ TAtlasTimeFile }

class function TAtlasTimeFile.DefaultPath: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), FileName);
end;

function TakeLock(const APath: string): TStream;
var
  mWaited: Integer;
begin
  Result := nil;
  mWaited := 0;
  ForceDirectories(ExtractFileDir(APath));
  while Result = nil do
  begin
    try
      Result := TFileStream.Create(APath + TAtlasTimeFile.LockExtension, fmCreate or fmShareExclusive);
    except
      on EStreamError do
        Result := nil;
      on EInOutError do
        Result := nil;
    end;
    if Result <> nil then
      Break;
    if mWaited >= TAtlasTimeFile.LockWaitMs then
      Exit;
    Sleep(25);
    Inc(mWaited, 25);
  end;
end;

function ReadLocked(const APath: string; out ALog: TAtlasTimeLog): Boolean;
begin
  ALog := TAtlasTimeLog.Empty;
  if not FileExists(APath) then
    Exit(True);
  try
    Result := TAtlasTimeLog.Parse(TFile.ReadAllText(APath, TEncoding.UTF8), ALog);
  except
    on EInOutError do
      Result := False;
    on EFileStreamError do
      Result := False;
    on EEncodingError do
      Result := False;
  end;
end;

class function TAtlasTimeFile.Read(const APath: string; out ALog: TAtlasTimeLog): Boolean;
var
  mLock: TStream;
begin
  ALog := TAtlasTimeLog.Empty;
  mLock := TakeLock(APath);
  if mLock = nil then
    Exit(False);
  try
    Result := ReadLocked(APath, ALog);
  finally
    mLock.Free;
  end;
end;

class function TAtlasTimeFile.Update(const APath: string; const AChange: TAtlasTimeLogChange;
  out ALog: TAtlasTimeLog): Boolean;
var
  mLock: TStream;
begin
  ALog := TAtlasTimeLog.Empty;
  mLock := TakeLock(APath);
  if mLock = nil then
    Exit(False);
  try
    Result := ReadLocked(APath, ALog);
    if not Result then
      Exit;
    AChange(ALog);
    try
      TFile.WriteAllText(APath, ALog.ToJson, TEncoding.UTF8);
    except
      on EInOutError do
        Result := False;
      on EFileStreamError do
        Result := False;
    end;
  finally
    mLock.Free;
  end;
end;

{ TAtlasTimeRounding }

class function TAtlasTimeRounding.Minutes(ASeconds: Int64; AStep: Integer): Integer;
begin
  Result := 0;
  if ASeconds <= 0 then
    Exit;
  if AStep < 1 then
    AStep := 1;
  // Kaufmännisch (Round rundet bei .5 zur geraden Zahl).
  Result := Trunc(ASeconds / (60 * AStep) + 0.5) * AStep;
  if Result < AStep then
    Result := AStep;
end;

class function TAtlasTimeRounding.ClockText(ASeconds: Int64): string;
begin
  if ASeconds < 0 then
    ASeconds := 0;
  Result := Format('%d:%.2d', [ASeconds div 3600, (ASeconds mod 3600) div 60]);
end;

class function TAtlasTimeRounding.Presentation(AMinutes: Integer): string;
begin
  Result := '';
  if AMinutes <= 0 then
    Exit;
  if AMinutes < 60 then
    Exit(Format('%dm', [AMinutes]));
  if AMinutes mod 60 = 0 then
    Exit(Format('%dh', [AMinutes div 60]));
  Result := Format('%dh %dm', [AMinutes div 60, AMinutes mod 60]);
end;

function ParseNumber(const AText: string; out AValue: Double): Boolean;
var
  mFormat: TFormatSettings;
begin
  mFormat := TFormatSettings.Invariant;
  Result := (AText <> '') and TryStrToFloat(StringReplace(AText, ',', '.', []), AValue, mFormat) and (AValue >= 0);
end;

class function TAtlasTimeRounding.ParseDuration(const AText: string; out AMinutes: Integer): Boolean;
var
  mText, mNumber, mUnit: string;
  mIndex, mColon, mHours, mRest: Integer;
  mValue, mTotal: Double;
  mAny: Boolean;
begin
  AMinutes := 0;
  Result := False;
  mText := LowerCase(Trim(AText));
  if mText = '' then
    Exit;
  mColon := Pos(':', mText);
  if mColon > 0 then
  begin
    if not TryStrToInt(Trim(Copy(mText, 1, mColon - 1)), mHours) or
      not TryStrToInt(Trim(Copy(mText, mColon + 1, MaxInt)), mRest) or (mHours < 0) or (mRest < 0) or
      (mRest > 59) then
      Exit;
    AMinutes := mHours * 60 + mRest;
  end
  else
  begin
    // Zahl mit Einheit (h, std, stunden; m, min, minuten), mehrfach; eine Zahl ohne Einheit sind Minuten.
    mTotal := 0;
    mAny := False;
    mIndex := 1;
    while mIndex <= Length(mText) do
    begin
      while (mIndex <= Length(mText)) and (mText[mIndex] = ' ') do
        Inc(mIndex);
      if mIndex > Length(mText) then
        Break;
      mNumber := '';
      while (mIndex <= Length(mText)) and CharInSet(mText[mIndex], ['0'..'9', ',', '.']) do
      begin
        mNumber := mNumber + mText[mIndex];
        Inc(mIndex);
      end;
      if not ParseNumber(mNumber, mValue) then
        Exit;
      while (mIndex <= Length(mText)) and (mText[mIndex] = ' ') do
        Inc(mIndex);
      mUnit := '';
      while (mIndex <= Length(mText)) and not CharInSet(mText[mIndex], ['0'..'9', ',', '.', ' ']) do
      begin
        mUnit := mUnit + mText[mIndex];
        Inc(mIndex);
      end;
      if (mUnit = 'h') or (mUnit = 'std') or (mUnit = 'std.') or (mUnit = 'stunde') or (mUnit = 'stunden') then
        mTotal := mTotal + mValue * 60
      else if (mUnit = '') or (mUnit = 'm') or (mUnit = 'min') or (mUnit = 'min.') or (mUnit = 'minuten') then
        mTotal := mTotal + mValue
      else
        Exit;
      mAny := True;
    end;
    if not mAny or (mTotal > MaxMinutes) then
      Exit;
    AMinutes := Trunc(mTotal + 0.5);
  end;
  Result := (AMinutes > 0) and (AMinutes <= MaxMinutes);
  if not Result then
    AMinutes := 0;
end;

end.
