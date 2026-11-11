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
    cVersion = 1;
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
    cFileName = 'time.json';
    cLockExtension = '.lock';
    /// <summary>So lange wartet ein Zugriff auf die Sperre einer anderen IDE-Instanz.</summary>
    cLockWaitMs = 2000;
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
    cMaxMinutes = 7 * 24 * 60;
  public
    /// <summary>ASeconds auf AStep Minuten gerundet (kaufmännisch); mindestens AStep, sobald Zeit da ist.</summary>
    class function Minutes(ASeconds: Int64; AStep: Integer): Integer; static;
    /// <summary>Anzeige im Statusfeld: "1:25" (Stunden:Minuten, abgeschnitten).</summary>
    class function ClockText(ASeconds: Int64): string; static;
    /// <summary>Dauer für YouTrack: "1h 25m", "45m", "2h"; '' bei 0.</summary>
    class function Presentation(AMinutes: Integer): string; static;
    /// <summary>Eingabe "1:25", "85", "85 min", "1 h 25 min", "1h 25m", "1,5 h", Einheiten deutsch und englisch
    /// ("2 Std", "2 hours", "30 minutes"); False bei 0, zu groß oder unlesbar.</summary>
    class function ParseDuration(const AText: string; out AMinutes: Integer): Boolean; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults,
  System.JSON,
  System.Math,
  System.StrUtils,
  Atlas.Core.Tracker.Files,
  Atlas.Text.Json;

const
  cLocalAppData = 'LOCALAPPDATA';
  cAtlasFolder = 'Atlas';

{ TAtlasTimeIssue }

class function TAtlasTimeIssue.Create(const AProvider, AUrl, AProject, AKey: string): TAtlasTimeIssue;
begin
  Result.Provider := LowerCase(Trim(AProvider));
  Result.Url := Trim(AUrl);
  while Result.Url.EndsWith('/') do
  begin
    Result.Url := Copy(Result.Url, 1, Length(Result.Url) - 1);
  end;
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
  begin
    Result := Round((EndAt - StartAt) * SecsPerDay);
  end;
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
  begin
    ADay := Trunc(mDate);
  end;
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
  begin
    ATime := mDay + mClock;
  end;
end;

class function TAtlasTimeLog.Empty: TAtlasTimeLog;
begin
  Result.Entries := nil;
end;

/// <summary>Eintrag aus einem Element von "entries"; False bei unvollständigen Einträgen.</summary>
function EntryOf(AItem: TJSONValue; out AEntry: TAtlasTimeEntry): Boolean;
var
  mObject: TJSONObject;
  mSeconds: TJSONValue;
begin
  AEntry := Default(TAtlasTimeEntry);
  Result := False;
  if not (AItem is TJSONObject) then
  begin
    Exit;
  end;
  mObject := TJSONObject(AItem);
  AEntry.Issue := TAtlasTimeIssue.Create(TJsonRead.Text(mObject, 'provider'), TJsonRead.Text(mObject, 'url'),
    TJsonRead.Text(mObject, 'project'), TJsonRead.Text(mObject, 'key'));
  mSeconds := mObject.Values['seconds'];
  if AEntry.Issue.IsEmpty or not (mSeconds is TJSONNumber) or not ParseDay(TJsonRead.Text(mObject, 'date'), AEntry.Day) then
  begin
    Exit;
  end;
  AEntry.Seconds := TJSONNumber(mSeconds).AsInt64;
  if AEntry.Seconds < 0 then
  begin
    AEntry.Seconds := 0;
  end;
  if not ParseTime(TJsonRead.Text(mObject, 'last'), AEntry.Last) then
  begin
    AEntry.Last := 0;
  end;
  Result := True;
end;

function HasVersion(AValue: TJSONValue): Boolean;
var
  mVersion: TJSONValue;
begin
  Result := AValue is TJSONObject;
  if Result then
  begin
    mVersion := TJSONObject(AValue).Values['version'];
    Result := (mVersion is TJSONNumber) and (TJSONNumber(mVersion).AsInt = TAtlasTimeLog.cVersion);
  end;
end;

class function TAtlasTimeLog.Parse(const AJson: string; out ALog: TAtlasTimeLog): Boolean;
var
  mValue, mItems, mItem: TJSONValue;
  mEntry: TAtlasTimeEntry;
  mText: string;
begin
  ALog := Empty;
  mText := AJson;
  // Mit oder ohne BOM geschrieben.
  if mText.StartsWith(#$FEFF) then
  begin
    mText := Copy(mText, 2, MaxInt);
  end;
  if Trim(mText) = '' then
  begin
    Exit(True);
  end;
  Result := False;
  mValue := TJSONObject.ParseJSONValue(mText);
  try
    if not HasVersion(mValue) then
    begin
      Exit;
    end;
    mItems := TJSONObject(mValue).Values['entries'];
    Result := (mItems = nil) or (mItems is TJSONArray);
    if not (mItems is TJSONArray) then
    begin
      Exit;
    end;
    for mItem in TJSONArray(mItems) do
    begin
      // Unvollständige Einträge fallen weg, der Rest bleibt.
      if EntryOf(mItem, mEntry) then
      begin
        ALog.Entries := ALog.Entries + [mEntry];
      end;
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
    mRoot.AddPair('version', TJSONNumber.Create(cVersion));
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
      begin
        mObject.AddPair('last', TimeText(mEntry.Last));
      end;
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
  begin
    if (Entries[mIndex].Day = ADay) and Entries[mIndex].Issue.Same(AIssue) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TAtlasTimeLog.AddEntry(const AIssue: TAtlasTimeIssue; ADay: Integer): Integer;
var
  mEntry: TAtlasTimeEntry;
begin
  Result := IndexOf(AIssue, ADay);
  if Result >= 0 then
  begin
    Exit;
  end;
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
  begin
    Exit;
  end;
  mFrom := ASpan.StartAt;
  while mFrom < ASpan.EndAt do
  begin
    // Ein Stück je Tag; Mitternacht gehört zum neuen Tag.
    mDayEnd := Trunc(mFrom) + 1;
    mTo := ASpan.EndAt;
    if mTo > mDayEnd then
    begin
      mTo := mDayEnd;
    end;
    mIndex := AddEntry(ASpan.Issue, Trunc(mFrom));
    mPart := TAtlasTimeSpan.Create(ASpan.Issue, mFrom, mTo);
    if Entries[mIndex].Last > mPart.StartAt then
    begin
      mPart.StartAt := Entries[mIndex].Last;
    end;
    Inc(Entries[mIndex].Seconds, mPart.Seconds);
    if mTo > Entries[mIndex].Last then
    begin
      Entries[mIndex].Last := mTo;
    end;
    mFrom := mTo;
  end;
end;

function TAtlasTimeLog.Total(const AIssue: TAtlasTimeIssue): Int64;
var
  mEntry: TAtlasTimeEntry;
begin
  Result := 0;
  for mEntry in Entries do
  begin
    if mEntry.Issue.Same(AIssue) then
    begin
      Inc(Result, mEntry.Seconds);
    end;
  end;
end;

procedure TAtlasTimeLog.Prune(const AIssue: TAtlasTimeIssue);
var
  mIndex, mNewest: Integer;
begin
  // Leere Tage fallen weg; der jüngste bleibt mit "last", damit eine andere Instanz nichts neu zählt.
  mNewest := -1;
  for mIndex := 0 to High(Entries) do
  begin
    if Entries[mIndex].Issue.Same(AIssue) and ((mNewest < 0) or (Entries[mIndex].Day > Entries[mNewest].Day)) then
    begin
      mNewest := mIndex;
    end;
  end;
  for mIndex := High(Entries) downto 0 do
  begin
    if (mIndex <> mNewest) and (Entries[mIndex].Seconds = 0) and Entries[mIndex].Issue.Same(AIssue) then
    begin
      Delete(Entries, mIndex, 1);
    end;
  end;
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
    begin
      if Entries[mIndex].Issue.Same(AIssue) and (Entries[mIndex].Seconds > 0) and
        ((mOldest < 0) or (Entries[mIndex].Day < Entries[mOldest].Day)) then
      begin
        mOldest := mIndex;
      end;
    end;
    if mOldest < 0 then
    begin
      Break;
    end;
    mTake := Entries[mOldest].Seconds;
    if mTake > ASeconds then
    begin
      mTake := ASeconds;
    end;
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
  begin
    Exit;
  end;
  mLast := 0;
  for mIndex := 0 to High(Entries) do
  begin
    if Entries[mIndex].Issue.Same(AIssue) then
    begin
      if Entries[mIndex].Last > mLast then
      begin
        mLast := Entries[mIndex].Last;
      end;
      Entries[mIndex].Seconds := 0;
    end;
  end;
  mIndex := AddEntry(AIssue, Trunc(AToday));
  if ASeconds > 0 then
  begin
    Entries[mIndex].Seconds := ASeconds;
  end;
  if mLast > Entries[mIndex].Last then
  begin
    Entries[mIndex].Last := mLast;
  end;
  Prune(AIssue);
end;

/// <summary>Stelle des Issues AIssue in AOpen; -1 ohne.</summary>
function IndexOfOpen(const AOpen: TArray<TAtlasTimeOpen>; const AIssue: TAtlasTimeIssue): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(AOpen) do
  begin
    if AOpen[mIndex].Issue.Same(AIssue) then
    begin
      Result := mIndex;
    end;
  end;
end;

/// <summary>AEntry zur offenen Zeit seines Issues zählen; neues Issue hinten anfügen.</summary>
procedure AddOpen(var AOpen: TArray<TAtlasTimeOpen>; const AEntry: TAtlasTimeEntry);
var
  mFound: Integer;
  mItem: TAtlasTimeOpen;
begin
  mFound := IndexOfOpen(AOpen, AEntry.Issue);
  if mFound < 0 then
  begin
    mItem.Issue := AEntry.Issue;
    mItem.Seconds := 0;
    mItem.FirstDay := AEntry.Day;
    mItem.LastDay := AEntry.Day;
    AOpen := AOpen + [mItem];
    mFound := High(AOpen);
  end;
  Inc(AOpen[mFound].Seconds, AEntry.Seconds);
  AOpen[mFound].FirstDay := Min(AOpen[mFound].FirstDay, AEntry.Day);
  AOpen[mFound].LastDay := Max(AOpen[mFound].LastDay, AEntry.Day);
end;

function TAtlasTimeLog.Open: TArray<TAtlasTimeOpen>;
var
  mEntry: TAtlasTimeEntry;
begin
  Result := nil;
  for mEntry in Entries do
  begin
    if mEntry.Seconds > 0 then
    begin
      AddOpen(Result, mEntry);
    end;
  end;
  // Sort ist nicht stabil: bei gleichem Tag nach Kennung weiter.
  TArray.Sort<TAtlasTimeOpen>(Result, TComparer<TAtlasTimeOpen>.Construct(
    function(const ALeft, ARight: TAtlasTimeOpen): Integer
    begin
      Result := ARight.LastDay - ALeft.LastDay;
      if Result = 0 then
      begin
        Result := CompareText(ALeft.Issue.Id, ARight.Issue.Id);
      end;
    end));
end;

{ TAtlasTimeFile }

class function TAtlasTimeFile.DefaultPath: string;
begin
  Result := TAtlasTrackerFiles.Join(TAtlasTrackerFiles.Join(TAtlasTrackerFiles.Files.Environment(cLocalAppData),
    cAtlasFolder), cFileName);
end;

function TakeLock(const APath: string): IInterface;
begin
  Result := TAtlasTrackerFiles.Files.Lock(APath + TAtlasTimeFile.cLockExtension, TAtlasTimeFile.cLockWaitMs);
end;

function ReadLocked(const APath: string; out ALog: TAtlasTimeLog): Boolean;
var
  mText: string;
begin
  ALog := TAtlasTimeLog.Empty;
  if not TAtlasTrackerFiles.Files.FileExists(APath) then
  begin
    Exit(True);
  end;
  Result := TAtlasTrackerFiles.Files.ReadText(APath, mText) and TAtlasTimeLog.Parse(mText, ALog);
end;

class function TAtlasTimeFile.Read(const APath: string; out ALog: TAtlasTimeLog): Boolean;
var
  mLock: IInterface;
begin
  ALog := TAtlasTimeLog.Empty;
  mLock := TakeLock(APath);
  if mLock = nil then
  begin
    Exit(False);
  end;
  Result := ReadLocked(APath, ALog);
end;

class function TAtlasTimeFile.Update(const APath: string; const AChange: TAtlasTimeLogChange;
  out ALog: TAtlasTimeLog): Boolean;
var
  mLock: IInterface;
begin
  ALog := TAtlasTimeLog.Empty;
  mLock := TakeLock(APath);
  if mLock = nil then
  begin
    Exit(False);
  end;
  Result := ReadLocked(APath, ALog);
  if not Result then
  begin
    Exit;
  end;
  AChange(ALog);
  Result := TAtlasTrackerFiles.Files.WriteText(APath, ALog.ToJson);
end;

{ TAtlasTimeRounding }

class function TAtlasTimeRounding.Minutes(ASeconds: Int64; AStep: Integer): Integer;
begin
  Result := 0;
  if ASeconds <= 0 then
  begin
    Exit;
  end;
  if AStep < 1 then
  begin
    AStep := 1;
  end;
  // Kaufmännisch (Round rundet bei .5 zur geraden Zahl).
  Result := Trunc(ASeconds / (60 * AStep) + 0.5) * AStep;
  if Result < AStep then
  begin
    Result := AStep;
  end;
end;

class function TAtlasTimeRounding.ClockText(ASeconds: Int64): string;
begin
  if ASeconds < 0 then
  begin
    ASeconds := 0;
  end;
  Result := Format('%d:%.2d', [ASeconds div 3600, (ASeconds mod 3600) div 60]);
end;

class function TAtlasTimeRounding.Presentation(AMinutes: Integer): string;
begin
  Result := '';
  if AMinutes <= 0 then
  begin
    Exit;
  end;
  if AMinutes < 60 then
  begin
    Exit(Format('%dm', [AMinutes]));
  end;
  if AMinutes mod 60 = 0 then
  begin
    Exit(Format('%dh', [AMinutes div 60]));
  end;
  Result := Format('%dh %dm', [AMinutes div 60, AMinutes mod 60]);
end;

function ParseNumber(const AText: string; out AValue: Double): Boolean;
var
  mFormat: TFormatSettings;
begin
  mFormat := TFormatSettings.Invariant;
  Result := (AText <> '') and TryStrToFloat(StringReplace(AText, ',', '.', []), AValue, mFormat) and (AValue >= 0);
end;

/// <summary>"1:30": Stunden und Minuten (0–59) um den Doppelpunkt an AColon.</summary>
function ParseClock(const AText: string; AColon: Integer; out AMinutes: Integer): Boolean;
var
  mHours, mRest: Integer;
begin
  AMinutes := 0;
  Result := TryStrToInt(Trim(Copy(AText, 1, AColon - 1)), mHours) and
    TryStrToInt(Trim(Copy(AText, AColon + 1, MaxInt)), mRest) and (mHours >= 0) and (mRest >= 0) and (mRest <= 59);
  if Result then
  begin
    AMinutes := mHours * 60 + mRest;
  end;
end;

/// <summary>Zeichen ab AIndex, solange sie in AChars liegen (AInSet) bzw. nicht darin liegen; AIndex dahinter.
/// </summary>
function TakeChars(const AText: string; var AIndex: Integer; const AChars: TSysCharSet; AInSet: Boolean): string;
begin
  Result := '';
  while (AIndex <= Length(AText)) and (CharInSet(AText[AIndex], AChars) = AInSet) do
  begin
    Result := Result + AText[AIndex];
    Inc(AIndex);
  end;
end;

procedure SkipSpaces(const AText: string; var AIndex: Integer);
begin
  while (AIndex <= Length(AText)) and (AText[AIndex] = ' ') do
  begin
    Inc(AIndex);
  end;
end;

/// <summary>Minuten je Einheit: h, std, stunden, hr, hour(s) 60; ohne Einheit, m, min, minuten, minute(s) 1 (#1458).
/// </summary>
function UnitFactor(const AUnit: string; out AFactor: Double): Boolean;
begin
  AFactor := 0;
  if MatchStr(AUnit, ['h', 'std', 'std.', 'stunde', 'stunden', 'hr', 'hrs', 'hour', 'hours']) then
  begin
    AFactor := 60;
  end
  else if (AUnit = '') or MatchStr(AUnit, ['m', 'min', 'min.', 'mins', 'minuten', 'minute', 'minutes']) then
  begin
    AFactor := 1;
  end;
  Result := AFactor > 0;
end;

/// <summary>Zahl mit Einheit, mehrfach ("1h 30m", "1,5 std"); eine Zahl ohne Einheit sind Minuten.</summary>
function ParseUnits(const AText: string; out ATotal: Double): Boolean;
var
  mIndex: Integer;
  mValue, mFactor: Double;
  mAny: Boolean;
begin
  ATotal := 0;
  Result := False;
  mAny := False;
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    SkipSpaces(AText, mIndex);
    if mIndex > Length(AText) then
    begin
      Break;
    end;
    if not ParseNumber(TakeChars(AText, mIndex, ['0'..'9', ',', '.'], True), mValue) then
    begin
      Exit;
    end;
    SkipSpaces(AText, mIndex);
    if not UnitFactor(TakeChars(AText, mIndex, ['0'..'9', ',', '.', ' '], False), mFactor) then
    begin
      Exit;
    end;
    ATotal := ATotal + mValue * mFactor;
    mAny := True;
  end;
  Result := mAny and (ATotal <= TAtlasTimeRounding.cMaxMinutes);
end;

class function TAtlasTimeRounding.ParseDuration(const AText: string; out AMinutes: Integer): Boolean;
var
  mText: string;
  mColon: Integer;
  mTotal: Double;
begin
  AMinutes := 0;
  mText := LowerCase(Trim(AText));
  mColon := Pos(':', mText);
  if mColon > 0 then
  begin
    Result := ParseClock(mText, mColon, AMinutes);
  end
  else
  begin
    Result := ParseUnits(mText, mTotal);
    if Result then
    begin
      AMinutes := Trunc(mTotal + 0.5);
    end;
  end;
  Result := Result and (AMinutes > 0) and (AMinutes <= cMaxMinutes);
  if not Result then
  begin
    AMinutes := 0;
  end;
end;

end.
