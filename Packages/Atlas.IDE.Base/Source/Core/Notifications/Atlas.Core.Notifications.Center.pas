unit Atlas.Core.Notifications.Center;

// Benachrichtigungszentrale (#601), ohne VCL:
// - TAtlasNotificationCenter: threadsichere Liste der Einträge der IDE-Sitzung,
//   neueste zuerst, höchstens MaxEntries (Vorgabe 200, ältere fallen weg), mit
//   Beobachtern für Änderungen. Default ist die Zentrale des Plugins; Tests
//   legen eigene mit eigener Uhr an.
// - Zusammenfassen: Ein Hinweis mit derselben Quelle und demselben Titel
//   innerhalb von MergeSeconds (10 s) nach dem letzten gleichartigen erhöht
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
    /// <summary>Gleichartige Hinweise innerhalb dieser Sekunden werden zusammengefasst.</summary>
    MergeSeconds = 10;
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
    class var FDefault: IAtlasNotificationCenter;
    class var FDefaultObject: TAtlasNotificationCenter;
    function Now_: TDateTime;
    function IndexOf(AId: Integer): Integer;
    function ModeLocked(const ASource: string): TAtlasNotificationMode;
    procedure Trim_;
    procedure Notify_;
    class function Copy_(const AEntry: IAtlasNotification): TEntry; static;
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
    /// <summary>Höhere der beiden Schweren.</summary>
    class function Worse(ALeft, ARight: TAtlasNotificationSeverity): TAtlasNotificationSeverity; static;
    /// <summary>"3 × Titel" ab ACount = 2, sonst ATitle.</summary>
    class function CaptionOf(const ATitle: string; ACount: Integer): string; static;
    /// <summary>Aktion mit Beschriftung.</summary>
    class function Action(const ACaption: string; const ARun: TProc): TAtlasNotificationAction; static;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Notifications.Sources;

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
  Result := TAtlasNotificationCenter.CaptionOf(FTitle, FCount);
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
  if FDefault = nil then
  begin
    FDefaultObject := TAtlasNotificationCenter.Create;
    // Bis das Plugin sie nach seinen Einstellungen einschaltet, verhält sich alles wie vor #601.
    FDefaultObject.FEnabled := False;
    FDefault := FDefaultObject;
  end;
  Result := FDefault;
end;

class function TAtlasNotificationCenter.DefaultCenter: TAtlasNotificationCenter;
begin
  Default;
  Result := FDefaultObject;
end;

class procedure TAtlasNotificationCenter.ReleaseDefault;
begin
  FDefaultObject := nil;
  FDefault := nil;
end;

class function TAtlasNotificationCenter.Worse(ALeft, ARight: TAtlasNotificationSeverity): TAtlasNotificationSeverity;
begin
  if Ord(ARight) > Ord(ALeft) then
    Result := ARight
  else
    Result := ALeft;
end;

class function TAtlasNotificationCenter.CaptionOf(const ATitle: string; ACount: Integer): string;
begin
  if ACount > 1 then
    Result := IntToStr(ACount) + ' × ' + ATitle
  else
    Result := ATitle;
end;

class function TAtlasNotificationCenter.Action(const ACaption: string; const ARun: TProc): TAtlasNotificationAction;
begin
  Result.Caption := ACaption;
  Result.Run := ARun;
end;

class function TAtlasNotificationCenter.Copy_(const AEntry: IAtlasNotification): TEntry;
begin
  Result := TEntry.Create;
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

function TAtlasNotificationCenter.Now_: TDateTime;
begin
  if Assigned(FClock) then
    Result := FClock()
  else
    Result := Now;
end;

function TAtlasNotificationCenter.IndexOf(AId: Integer): Integer;
var
  Index: Integer;
begin
  for Index := 0 to FItems.Count - 1 do
    if FItems[Index].Id = AId then
      Exit(Index);
  Result := -1;
end;

function TAtlasNotificationCenter.ModeLocked(const ASource: string): TAtlasNotificationMode;
begin
  if not FEnabled or not FModes.TryGetValue(LowerCase(ASource), Result) then
    Result := TAtlasNotificationMode.Show;
end;

procedure TAtlasNotificationCenter.Trim_;
begin
  while FItems.Count > FMaxEntries do
    FItems.Delete(FItems.Count - 1);
end;

procedure TAtlasNotificationCenter.Notify_;
var
  Listeners: TArray<TProc>;
  Listener: TProc;
begin
  FLock.Enter;
  try
    Inc(FVersion);
    Listeners := FListeners.Values.ToArray;
  finally
    FLock.Leave;
  end;
  // Außerhalb der Sperre: Beobachter dürfen die Zentrale lesen.
  for Listener in Listeners do
    try
      Listener();
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
  Stamp, Limit: TDateTime;
  Index, Found: Integer;
  Entry: TEntry;
  Existing: IAtlasNotification;
begin
  Stamp := Now_;
  FLock.Enter;
  try
    Result := ModeLocked(ASource);
    if not FEnabled or (Result = TAtlasNotificationMode.Off) then
      Exit;
    // Gleichartig: dieselbe Quelle und derselbe Titel, letzte Meldung höchstens MergeSeconds zurück.
    Limit := Stamp - MergeSeconds / SecsPerDay;
    Found := -1;
    for Index := 0 to FItems.Count - 1 do
    begin
      Existing := FItems[Index];
      if SameText(Existing.Source, ASource) and (Existing.Title = ATitle) and (Existing.Time >= Limit) then
      begin
        Found := Index;
        Break;
      end;
    end;
    if Found >= 0 then
    begin
      Entry := Copy_(FItems[Found]);
      FItems.Delete(Found);
      Inc(Entry.FCount);
      Entry.FSeverity := Worse(Entry.FSeverity, ASeverity);
    end
    else
    begin
      Entry := TEntry.Create;
      Inc(FNextId);
      Entry.FId := FNextId;
      Entry.FSource := ASource;
      Entry.FSeverity := ASeverity;
      Entry.FTitle := ATitle;
      Entry.FCount := 1;
    end;
    Entry.FText := AText;
    Entry.FTime := Stamp;
    Entry.FRead := False;
    Entry.FActions := Copy(AActions);
    FItems.Insert(0, Entry);
    Trim_;
  finally
    FLock.Leave;
  end;
  Notify_;
end;

function TAtlasNotificationCenter.ModeOf(const ASource: string): TAtlasNotificationMode;
begin
  FLock.Enter;
  try
    Result := ModeLocked(ASource);
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasNotificationCenter.SetMode(const ASource: string; AMode: TAtlasNotificationMode);
begin
  if Trim(ASource) = '' then
    Exit;
  FLock.Enter;
  try
    if AMode = TAtlasNotificationMode.Show then
      FModes.Remove(LowerCase(ASource))
    else
      FModes.AddOrSetValue(LowerCase(ASource), AMode);
  finally
    FLock.Leave;
  end;
  Notify_;
end;

procedure TAtlasNotificationCenter.ApplyModes(const ASpec: string);
var
  Entry: TAtlasNotificationSourceMode;
begin
  FLock.Enter;
  try
    FModes.Clear;
    for Entry in TAtlasNotificationSources.Parse(ASpec) do
      if Entry.Mode <> TAtlasNotificationMode.Show then
        FModes.AddOrSetValue(LowerCase(Entry.Source), Entry.Mode);
  finally
    FLock.Leave;
  end;
  Notify_;
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
  Entry: IAtlasNotification;
begin
  if ASource = '' then
    Exit(Items);
  Result := nil;
  for Entry in Items do
    if SameText(Entry.Source, ASource) then
      Result := Result + [Entry];
end;

function TAtlasNotificationCenter.Find(AId: Integer): IAtlasNotification;
var
  Index: Integer;
begin
  Result := nil;
  FLock.Enter;
  try
    Index := IndexOf(AId);
    if Index >= 0 then
      Result := FItems[Index];
  finally
    FLock.Leave;
  end;
end;

function TAtlasNotificationCenter.Sources: TArray<string>;
var
  Entry: IAtlasNotification;
  Source: string;
  Known: Boolean;
begin
  Result := nil;
  for Entry in Items do
  begin
    Known := False;
    for Source in Result do
      if SameText(Source, Entry.Source) then
        Known := True;
    if not Known then
      Result := Result + [Entry.Source];
  end;
end;

procedure TAtlasNotificationCenter.MarkRead(AId: Integer);
var
  Index: Integer;
  Entry: TEntry;
begin
  FLock.Enter;
  try
    Index := IndexOf(AId);
    if (Index < 0) or FItems[Index].Read then
      Exit;
    Entry := Copy_(FItems[Index]);
    Entry.FRead := True;
    FItems[Index] := Entry;
  finally
    FLock.Leave;
  end;
  Notify_;
end;

procedure TAtlasNotificationCenter.MarkAllRead;
var
  Index: Integer;
  Entry: TEntry;
  Changed: Boolean;
begin
  Changed := False;
  FLock.Enter;
  try
    for Index := 0 to FItems.Count - 1 do
      if not FItems[Index].Read then
      begin
        Entry := Copy_(FItems[Index]);
        Entry.FRead := True;
        FItems[Index] := Entry;
        Changed := True;
      end;
  finally
    FLock.Leave;
  end;
  if Changed then
    Notify_;
end;

procedure TAtlasNotificationCenter.Clear;
begin
  FLock.Enter;
  try
    FItems.Clear;
  finally
    FLock.Leave;
  end;
  Notify_;
end;

function TAtlasNotificationCenter.RunAction(AId, AIndex: Integer): Boolean;
var
  Entry: IAtlasNotification;
  Actions: TArray<TAtlasNotificationAction>;
  Run: TProc;
begin
  Entry := Find(AId);
  Result := False;
  if Entry = nil then
    Exit;
  Actions := Entry.Actions;
  if (AIndex < 0) or (AIndex > High(Actions)) then
    Exit;
  Run := Actions[AIndex].Run;
  // Erst gelesen, dann die Aktion: Sie kann ein Fenster öffnen oder die Liste ändern.
  MarkRead(AId);
  if Assigned(Run) then
    Run();
  Result := True;
end;

function TAtlasNotificationCenter.UnreadCount: Integer;
var
  Entry: IAtlasNotification;
begin
  Result := 0;
  FLock.Enter;
  try
    for Entry in FItems do
      if not Entry.Read then
        Inc(Result);
  finally
    FLock.Leave;
  end;
end;

function TAtlasNotificationCenter.WorstUnread(out ASeverity: TAtlasNotificationSeverity): Boolean;
var
  Entry: IAtlasNotification;
begin
  Result := False;
  ASeverity := TAtlasNotificationSeverity.Info;
  FLock.Enter;
  try
    for Entry in FItems do
      if not Entry.Read then
      begin
        if not Result then
          ASeverity := Entry.Severity
        else
          ASeverity := Worse(ASeverity, Entry.Severity);
        Result := True;
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
  Before: Integer;
begin
  FLock.Enter;
  try
    Before := FItems.Count;
    FMaxEntries := EnsureRange(AValue, MinEntries, MaxMaxEntries);
    Trim_;
    if FItems.Count = Before then
      Exit;
  finally
    FLock.Leave;
  end;
  Notify_;
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
      Exit;
    FEnabled := AValue;
    // Ausgeschaltet: keine Liste, kein Zähler.
    if not AValue then
      FItems.Clear;
  finally
    FLock.Leave;
  end;
  Notify_;
end;

end.
