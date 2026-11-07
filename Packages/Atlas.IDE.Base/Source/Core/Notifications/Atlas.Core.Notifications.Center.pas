unit Atlas.Core.Notifications.Center;

// Benachrichtigungszentrale (#601), ohne VCL:
// - TAtlasNotificationCenter: threadsichere Liste der Einträge der IDE-Sitzung,
//   neueste zuerst, höchstens MaxEntries (Vorgabe 200, ältere fallen weg), mit
//   Beobachtern für Änderungen. Default ist die Zentrale des Plugins; Tests
//   legen eigene mit eigener Uhr an.
// - Zusammenfassen: Ein Hinweis mit derselben Quelle und demselben Titel
//   innerhalb von cMergeSeconds (10 s) nach dem letzten gleichartigen erhöht
//   dessen Zähler („3 × Server neu gestartet“), übernimmt Text, Aktionen und
//   die höhere Schwere, wird wieder ungelesen und rückt nach oben.
// - Verhalten je Quelle (notifications.sources): Show (Vorgabe) und Collect
//   legen einen Eintrag an, Off nicht; die meldende Funktion zeigt ihre eigene
//   Einblendung nur bei Show. Ausgeschaltet (Enabled = False, Vorgabe bis das
//   Plugin sie einschaltet) gilt für alle Quellen Show und es entsteht kein
//   Eintrag: Alles verhält sich wie vor #601.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  Atlas.Core.Notifications.Contract;

type
  TAtlasNotificationClock = reference to function: TDateTime;

  TAtlasNotificationCenter = class(TInterfacedObject, IAtlasNotificationCenter)
  public const
    DefaultMaxEntries = 200;
    MinEntries = 10;
    MaxMaxEntries = 1000;
  private type
    TEntry = class(TInterfacedObject, IAtlasNotification)
    private
      FId: Integer;
      FSource: string;
      FSeverity: TAtlasNotificationSeverity;
      FTitle: string;
      FText: string;
      FTime: TDateTime;
      FCount: Integer;
      FRead: Boolean;
      FActions: TArray<TAtlasNotificationAction>;
    public
      function Id: Integer;
      function Source: string;
      function Severity: TAtlasNotificationSeverity;
      function Title: string;
      function Text: string;
      function Time: TDateTime;
      function Count: Integer;
      function Read: Boolean;
      function Actions: TArray<TAtlasNotificationAction>;
      function Caption: string;
    end;
  private
    FLock: TCriticalSection;
    // Neueste zuerst. Die Einträge sind unveränderlich nach außen: Änderungen ersetzen sie durch Kopien.
    FItems: TList<IAtlasNotification>;
    FModes: TDictionary<string, TAtlasNotificationMode>;
    FListeners: TDictionary<Integer, TProc>;
    FNextListener: Integer;
    FNextId: Integer;
    FVersion: Integer;
    FMaxEntries: Integer;
    FEnabled: Boolean;
    FClock: TAtlasNotificationClock;
    procedure SetEnabled(AValue: Boolean);
    function GetEnabled: Boolean;
  public
    constructor Create; overload;
    /// <summary>AClock liefert die Zeit (Tests); nil = Now.</summary>
    constructor Create(const AClock: TAtlasNotificationClock); overload;
    destructor Destroy; override;
    { IAtlasNotificationCenter }
    function Notify(const ASource: string; ASeverity: TAtlasNotificationSeverity;
      const ATitle, AText: string): TAtlasNotificationMode; overload;
    function Notify(const ASource: string; ASeverity: TAtlasNotificationSeverity; const ATitle, AText: string;
      const AActions: TArray<TAtlasNotificationAction>): TAtlasNotificationMode; overload;
    function ModeOf(const ASource: string): TAtlasNotificationMode;
    procedure SetMode(const ASource: string; AMode: TAtlasNotificationMode);
    function Items: TArray<IAtlasNotification>; overload;
    function Items(const ASource: string): TArray<IAtlasNotification>; overload;
    function Find(AId: Integer): IAtlasNotification;
    function Sources: TArray<string>;
    procedure MarkRead(AId: Integer);
    procedure MarkAllRead;
    procedure Clear;
    function RunAction(AId, AIndex: Integer): Boolean;
    function UnreadCount: Integer;
    function WorstUnread(out ASeverity: TAtlasNotificationSeverity): Boolean;
    function MaxEntries: Integer;
    procedure SetMaxEntries(AValue: Integer);
    function Version: Integer;
    function AddListener(const AListener: TProc): Integer;
    procedure RemoveListener(AHandle: Integer);
    /// <summary>Alle Verhalten aus notifications.sources setzen; nicht genannte Quellen zeigen wieder (Show).
    /// </summary>
    procedure ApplyModes(const ASpec: string);
    /// <summary>Zentrale an (Plugin-Einstellung Notifications); aus = kein Sammeln, alle Quellen zeigen.</summary>
    property Enabled: Boolean read GetEnabled write SetEnabled;
    /// <summary>Zentrale des Plugins; andere Funktionen melden hier ihre Hinweise.</summary>
    class function Default: IAtlasNotificationCenter; static;
    /// <summary>Dieselbe Zentrale als Objekt (Einschalten, Verhalten setzen); nur für die Komposition.</summary>
    class function DefaultCenter: TAtlasNotificationCenter; static;
    /// <summary>Gibt die Zentrale des Plugins frei (Entladen).</summary>
    class procedure ReleaseDefault; static;
    /// <summary>Aktion mit Beschriftung.</summary>
    class function Action(const ACaption: string; const ARun: TProc): TAtlasNotificationAction; static;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Notifications.Sources;

const
  /// <summary>Gleichartige Hinweise innerhalb dieser Sekunden werden zusammengefasst.</summary>
  cMergeSeconds = 10;

var
  /// <summary>Zentrale des Plugins (Default) und dieselbe als Objekt (DefaultCenter).</summary>
  GDefaultCenter: IAtlasNotificationCenter;
  GDefaultCenterObject: TAtlasNotificationCenter;

/// <summary>Höhere der beiden Schweren.</summary>
function Worse(ALeft, ARight: TAtlasNotificationSeverity): TAtlasNotificationSeverity;
begin
  if Ord(ARight) > Ord(ALeft) then
  begin
    Result := ARight;
  end
  else
  begin
    Result := ALeft;
  end;
end;

/// <summary>"3 × Titel" ab ACount = 2, sonst ATitle.</summary>
function CaptionOf(const ATitle: string; ACount: Integer): string;
begin
  if ACount > 1 then
  begin
    Result := IntToStr(ACount) + ' × ' + ATitle;
  end
  else
  begin
    Result := ATitle;
  end;
end;

{ TAtlasNotificationCenter.TEntry }

function TAtlasNotificationCenter.TEntry.Id: Integer;
begin
  Result := FId;
end;

function TAtlasNotificationCenter.TEntry.Source: string;
begin
  Result := FSource;
end;

function TAtlasNotificationCenter.TEntry.Severity: TAtlasNotificationSeverity;
begin
  Result := FSeverity;
end;

function TAtlasNotificationCenter.TEntry.Title: string;
begin
  Result := FTitle;
end;

function TAtlasNotificationCenter.TEntry.Text: string;
begin
  Result := FText;
end;

function TAtlasNotificationCenter.TEntry.Time: TDateTime;
begin
  Result := FTime;
end;

function TAtlasNotificationCenter.TEntry.Count: Integer;
begin
  Result := FCount;
end;

function TAtlasNotificationCenter.TEntry.Read: Boolean;
begin
  Result := FRead;
end;

function TAtlasNotificationCenter.TEntry.Actions: TArray<TAtlasNotificationAction>;
begin
  Result := FActions;
end;

function TAtlasNotificationCenter.TEntry.Caption: string;
begin
  Result := CaptionOf(FTitle, FCount);
end;

{ TAtlasNotificationCenter }

constructor TAtlasNotificationCenter.Create;
begin
  Create(nil);
end;

constructor TAtlasNotificationCenter.Create(const AClock: TAtlasNotificationClock);
begin
  inherited Create;
  FClock := AClock;
  FLock := TCriticalSection.Create;
  FItems := TList<IAtlasNotification>.Create;
  FModes := TDictionary<string, TAtlasNotificationMode>.Create;
  FListeners := TDictionary<Integer, TProc>.Create;
  FMaxEntries := DefaultMaxEntries;
  FEnabled := True;
end;

destructor TAtlasNotificationCenter.Destroy;
begin
  FListeners.Free;
  FModes.Free;
  FItems.Free;
  FLock.Free;
  inherited;
end;

class function TAtlasNotificationCenter.Default: IAtlasNotificationCenter;
begin
  if GDefaultCenter = nil then
  begin
    GDefaultCenterObject := TAtlasNotificationCenter.Create;
    // Bis das Plugin sie nach seinen Einstellungen einschaltet, verhält sich alles wie vor #601.
    GDefaultCenterObject.FEnabled := False;
    GDefaultCenter := GDefaultCenterObject;
  end;
  Result := GDefaultCenter;
end;

class function TAtlasNotificationCenter.DefaultCenter: TAtlasNotificationCenter;
begin
  Default;
  Result := GDefaultCenterObject;
end;

class procedure TAtlasNotificationCenter.ReleaseDefault;
begin
  GDefaultCenterObject := nil;
  GDefaultCenter := nil;
end;

class function TAtlasNotificationCenter.Action(const ACaption: string; const ARun: TProc): TAtlasNotificationAction;
begin
  Result.Caption := ACaption;
  Result.Run := ARun;
end;

function Copy_(const AEntry: IAtlasNotification): TAtlasNotificationCenter.TEntry;
begin
  Result := TAtlasNotificationCenter.TEntry.Create;
  Result.FId := AEntry.Id;
  Result.FSource := AEntry.Source;
  Result.FSeverity := AEntry.Severity;
  Result.FTitle := AEntry.Title;
  Result.FText := AEntry.Text;
  Result.FTime := AEntry.Time;
  Result.FCount := AEntry.Count;
  Result.FRead := AEntry.Read;
  Result.FActions := AEntry.Actions;
end;

function ClockNow(const AClock: TAtlasNotificationClock): TDateTime;
begin
  if Assigned(AClock) then
  begin
    Result := AClock();
  end
  else
  begin
    Result := Now;
  end;
end;

function IndexOfId(AItems: TList<IAtlasNotification>; AId: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to AItems.Count - 1 do
  begin
    if AItems[mIndex].Id = AId then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function ModeIn(AEnabled: Boolean; AModes: TDictionary<string, TAtlasNotificationMode>;
  const ASource: string): TAtlasNotificationMode;
begin
  if not AEnabled or not AModes.TryGetValue(LowerCase(ASource), Result) then
  begin
    Result := TAtlasNotificationMode.Show;
  end;
end;

procedure TrimTo(AItems: TList<IAtlasNotification>; AMax: Integer);
begin
  while AItems.Count > AMax do
  begin
    AItems.Delete(AItems.Count - 1);
  end;
end;

/// <summary>Version erhöhen und die Beobachter von ACenter rufen.</summary>
procedure NotifyChanged(ACenter: TAtlasNotificationCenter);
var
  mListeners: TArray<TProc>;
  mListener: TProc;
begin
  ACenter.FLock.Enter;
  try
    Inc(ACenter.FVersion);
    mListeners := ACenter.FListeners.Values.ToArray;
  finally
    ACenter.FLock.Leave;
  end;
  // Außerhalb der Sperre: Beobachter dürfen die Zentrale lesen.
  for mListener in mListeners do
    try
      mListener();
    except
      // Ein Fehler im Beobachter darf die meldende Funktion nicht stören.
      on Exception do
        ;
    end;
end;

function TAtlasNotificationCenter.Notify(const ASource: string; ASeverity: TAtlasNotificationSeverity;
  const ATitle, AText: string): TAtlasNotificationMode;
begin
  Result := Notify(ASource, ASeverity, ATitle, AText, nil);
end;

function TAtlasNotificationCenter.Notify(const ASource: string; ASeverity: TAtlasNotificationSeverity;
  const ATitle, AText: string; const AActions: TArray<TAtlasNotificationAction>): TAtlasNotificationMode;
var
  mStamp, mLimit: TDateTime;
  mIndex, mFound: Integer;
  mEntry: TEntry;
  mExisting: IAtlasNotification;
begin
  mStamp := ClockNow(FClock);
  FLock.Enter;
  try
    Result := ModeIn(FEnabled, FModes, ASource);
    if not FEnabled or (Result = TAtlasNotificationMode.Off) then
    begin
      Exit;
    end;
    // Gleichartig: dieselbe Quelle und derselbe Titel, letzte Meldung höchstens MergeSeconds zurück.
    mLimit := mStamp - cMergeSeconds / SecsPerDay;
    mFound := -1;
    for mIndex := 0 to FItems.Count - 1 do
    begin
      mExisting := FItems[mIndex];
      if SameText(mExisting.Source, ASource) and (mExisting.Title = ATitle) and (mExisting.Time >= mLimit) then
      begin
        mFound := mIndex;
        Break;
      end;
    end;
    if mFound >= 0 then
    begin
      mEntry := Copy_(FItems[mFound]);
      FItems.Delete(mFound);
      Inc(mEntry.FCount);
      mEntry.FSeverity := Worse(mEntry.FSeverity, ASeverity);
    end
    else
    begin
      mEntry := TEntry.Create;
      Inc(FNextId);
      mEntry.FId := FNextId;
      mEntry.FSource := ASource;
      mEntry.FSeverity := ASeverity;
      mEntry.FTitle := ATitle;
      mEntry.FCount := 1;
    end;
    mEntry.FText := AText;
    mEntry.FTime := mStamp;
    mEntry.FRead := False;
    mEntry.FActions := Copy(AActions);
    FItems.Insert(0, mEntry);
    TrimTo(FItems, FMaxEntries);
  finally
    FLock.Leave;
  end;
  NotifyChanged(Self);
end;

function TAtlasNotificationCenter.ModeOf(const ASource: string): TAtlasNotificationMode;
begin
  FLock.Enter;
  try
    Result := ModeIn(FEnabled, FModes, ASource);
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasNotificationCenter.SetMode(const ASource: string; AMode: TAtlasNotificationMode);
begin
  if Trim(ASource) = '' then
  begin
    Exit;
  end;
  FLock.Enter;
  try
    if AMode = TAtlasNotificationMode.Show then
    begin
      FModes.Remove(LowerCase(ASource));
    end
    else
    begin
      FModes.AddOrSetValue(LowerCase(ASource), AMode);
    end;
  finally
    FLock.Leave;
  end;
  NotifyChanged(Self);
end;

procedure TAtlasNotificationCenter.ApplyModes(const ASpec: string);
var
  mEntry: TAtlasNotificationSourceMode;
begin
  FLock.Enter;
  try
    FModes.Clear;
    for mEntry in TAtlasNotificationSources.Parse(ASpec) do
    begin
      if mEntry.Mode <> TAtlasNotificationMode.Show then
      begin
        FModes.AddOrSetValue(LowerCase(mEntry.Source), mEntry.Mode);
      end;
    end;
  finally
    FLock.Leave;
  end;
  NotifyChanged(Self);
end;

function TAtlasNotificationCenter.Items: TArray<IAtlasNotification>;
begin
  FLock.Enter;
  try
    Result := FItems.ToArray;
  finally
    FLock.Leave;
  end;
end;

function TAtlasNotificationCenter.Items(const ASource: string): TArray<IAtlasNotification>;
var
  mEntry: IAtlasNotification;
begin
  if ASource = '' then
  begin
    Exit(Items);
  end;
  Result := nil;
  for mEntry in Items do
  begin
    if SameText(mEntry.Source, ASource) then
    begin
      Result := Result + [mEntry];
    end;
  end;
end;

function TAtlasNotificationCenter.Find(AId: Integer): IAtlasNotification;
var
  mIndex: Integer;
begin
  Result := nil;
  FLock.Enter;
  try
    mIndex := IndexOfId(FItems, AId);
    if mIndex >= 0 then
    begin
      Result := FItems[mIndex];
    end;
  finally
    FLock.Leave;
  end;
end;

function TAtlasNotificationCenter.Sources: TArray<string>;
var
  mEntry: IAtlasNotification;
  mSource: string;
  mKnown: Boolean;
begin
  Result := nil;
  for mEntry in Items do
  begin
    mKnown := False;
    for mSource in Result do
    begin
      if SameText(mSource, mEntry.Source) then
      begin
        mKnown := True;
      end;
    end;
    if not mKnown then
    begin
      Result := Result + [mEntry.Source];
    end;
  end;
end;

procedure TAtlasNotificationCenter.MarkRead(AId: Integer);
var
  mIndex: Integer;
  mEntry: TEntry;
begin
  FLock.Enter;
  try
    mIndex := IndexOfId(FItems, AId);
    if (mIndex < 0) or FItems[mIndex].Read then
    begin
      Exit;
    end;
    mEntry := Copy_(FItems[mIndex]);
    mEntry.FRead := True;
    FItems[mIndex] := mEntry;
  finally
    FLock.Leave;
  end;
  NotifyChanged(Self);
end;

procedure TAtlasNotificationCenter.MarkAllRead;
var
  mIndex: Integer;
  mEntry: TEntry;
  mChanged: Boolean;
begin
  mChanged := False;
  FLock.Enter;
  try
    for mIndex := 0 to FItems.Count - 1 do
    begin
      if not FItems[mIndex].Read then
      begin
        mEntry := Copy_(FItems[mIndex]);
        mEntry.FRead := True;
        FItems[mIndex] := mEntry;
        mChanged := True;
      end;
    end;
  finally
    FLock.Leave;
  end;
  if mChanged then
  begin
    NotifyChanged(Self);
  end;
end;

procedure TAtlasNotificationCenter.Clear;
begin
  FLock.Enter;
  try
    FItems.Clear;
  finally
    FLock.Leave;
  end;
  NotifyChanged(Self);
end;

function TAtlasNotificationCenter.RunAction(AId, AIndex: Integer): Boolean;
var
  mEntry: IAtlasNotification;
  mActions: TArray<TAtlasNotificationAction>;
  mRun: TProc;
begin
  mEntry := Find(AId);
  Result := False;
  if mEntry = nil then
  begin
    Exit;
  end;
  mActions := mEntry.Actions;
  if (AIndex < 0) or (AIndex > High(mActions)) then
  begin
    Exit;
  end;
  mRun := mActions[AIndex].Run;
  // Erst gelesen, dann die Aktion: Sie kann ein Fenster öffnen oder die Liste ändern.
  MarkRead(AId);
  if Assigned(mRun) then
  begin
    mRun();
  end;
  Result := True;
end;

function TAtlasNotificationCenter.UnreadCount: Integer;
var
  mEntry: IAtlasNotification;
begin
  Result := 0;
  FLock.Enter;
  try
    for mEntry in FItems do
    begin
      if not mEntry.Read then
      begin
        Inc(Result);
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

function TAtlasNotificationCenter.WorstUnread(out ASeverity: TAtlasNotificationSeverity): Boolean;
var
  mEntry: IAtlasNotification;
begin
  Result := False;
  ASeverity := TAtlasNotificationSeverity.Info;
  FLock.Enter;
  try
    for mEntry in FItems do
    begin
      if not mEntry.Read then
      begin
        if not Result then
        begin
          ASeverity := mEntry.Severity;
        end
        else
        begin
          ASeverity := Worse(ASeverity, mEntry.Severity);
        end;
        Result := True;
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

function TAtlasNotificationCenter.MaxEntries: Integer;
begin
  FLock.Enter;
  try
    Result := FMaxEntries;
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasNotificationCenter.SetMaxEntries(AValue: Integer);
var
  mBefore: Integer;
begin
  FLock.Enter;
  try
    mBefore := FItems.Count;
    FMaxEntries := EnsureRange(AValue, MinEntries, MaxMaxEntries);
    TrimTo(FItems, FMaxEntries);
    if FItems.Count = mBefore then
    begin
      Exit;
    end;
  finally
    FLock.Leave;
  end;
  NotifyChanged(Self);
end;

function TAtlasNotificationCenter.Version: Integer;
begin
  FLock.Enter;
  try
    Result := FVersion;
  finally
    FLock.Leave;
  end;
end;

function TAtlasNotificationCenter.AddListener(const AListener: TProc): Integer;
begin
  FLock.Enter;
  try
    Inc(FNextListener);
    Result := FNextListener;
    FListeners.Add(Result, AListener);
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasNotificationCenter.RemoveListener(AHandle: Integer);
begin
  FLock.Enter;
  try
    FListeners.Remove(AHandle);
  finally
    FLock.Leave;
  end;
end;

function TAtlasNotificationCenter.GetEnabled: Boolean;
begin
  FLock.Enter;
  try
    Result := FEnabled;
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasNotificationCenter.SetEnabled(AValue: Boolean);
begin
  FLock.Enter;
  try
    if FEnabled = AValue then
    begin
      Exit;
    end;
    FEnabled := AValue;
    // Ausgeschaltet: keine Liste, kein Zähler.
    if not AValue then
    begin
      FItems.Clear;
    end;
  finally
    FLock.Leave;
  end;
  NotifyChanged(Self);
end;

end.
