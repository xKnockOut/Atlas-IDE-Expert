unit Atlas.IDE.Tracker.Notify;

// Meldungen zu meinen Issues (#1271, issues.notify, Vorgabe aus): fragt alle
// issues.notify.intervalMinutes (mindestens 2) im Hintergrund nach Änderungen
// und meldet sie in der Benachrichtigungszentrale (Quelle issues).
// - Verbindungen: der Tracker des aktuellen Projekts und die persönlichen
//   Verbindungen (issues.connections), je Anbieter und Server einmal; jede
//   fragt alle Projekte ihres Servers ab (IAtlasTrackerProvider.Changes).
// - Umfang issues.notify.scope: mir zugewiesen, dazu von mir erstellt
//   (Vorgabe), dazu beobachtete. Eigene Änderungen melden nicht.
// - Eine Meldung je Issue: „ATL-123: neuer Kommentar von …“, „… dir
//   zugewiesen“, „Zustand → …“; mehr als 10 auf einmal ergeben eine
//   Sammelmeldung. „Öffnen“ (in der Liste und in der Einblendung) zeigt das
//   Issue in „Atlas-Issue“ am ersten neuen Kommentar (#1264), sonst im Browser.
// - Bis zum Öffnen tragen die Issues in „Meine Issues“ einen Punkt, der Titel
//   des Bereichs ebenso. Stand (letzte Abfrage, Anmeldename, Punkte) in
//   %LOCALAPPDATA%\Atlas\issues\notify.json; beim Einschalten gilt „jetzt“,
//   damit Altes nicht als neu kommt.
// - Nur bei aktiver IDE (nicht minimiert, eine Eingabe in den letzten 30
//   Minuten); beim Öffnen von „Meine Issues“ sofort, höchstens einmal je
//   Minute. GitHub: If-Modified-Since und X-Poll-Interval.
// - Fehler: Abstand verdoppelt bis 60 Minuten, eine Meldung bis zum nächsten
//   Erfolg („Tracker-Einstellungen …“). Ohne Token kein Netzzugriff und keine
//   Meldung.
// - Protokoll anonym: nur Anbieter, Anzahl und Fehlerart, nie Adresse,
//   Kennung, Titel, Benutzer oder Token.
// Anbieter, Transport, Ziele, Öffnen und die Einstellungsseite kommen über
// Hooks aus „Meine Issues“.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.ExtCtrls,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Notify,
  Atlas.UI.Notifications.Notice,
  Atlas.IDE.Tracker.IssueContext,
  Atlas.Core.Diagnostics.WorkerSlot;

type
  /// <summary>Alle Tracker, die abgefragt werden sollen (auch doppelte; gezählt wird je Verbindung).</summary>
  TAtlasIssueNotifyTargetsHook = reference to function: TArray<TAtlasTrackerTarget>;
  /// <summary>Issue AKey zeigen, am Kommentar zu AAnchor (UTC; 0 = oben).</summary>
  TAtlasIssueNotifyOpenHook = reference to procedure(const ATarget: TAtlasTrackerTarget; const AKey: string;
    AAnchor: TDateTime);

  TAtlasIssueNotifyHooks = record
    Provider: TAtlasIssuePreviewProviderHook;
    Transport: TAtlasIssuePreviewTransportHook;
    Targets: TAtlasIssueNotifyTargetsHook;
    Open: TAtlasIssueNotifyOpenHook;
    /// <summary>Tools › Optionen › Atlas › Issue-Tracker.</summary>
    Settings: TProc;
    /// <summary>Punkte haben sich geändert („Meine Issues“ neu zeichnen).</summary>
    Changed: TProc;
    /// <summary>Andere haben Issues im Tracker geändert: Board und Sprint neu laden (#1272, #1277).</summary>
    Updated: TProc;
  end;

  TAtlasIdeIssueNotify = class(TInterfacedObject)
  public const
    /// <summary>Takt der Prüfung, ob eine Verbindung fällig ist.</summary>
    cTickMs = 30000;
  private type
    TJob = record
      Id: string;
      /// <summary>Stand von FGeneration beim Start: Nach Aus- und Einschalten zählt eine laufende Abfrage nicht.
      /// </summary>
      Generation: Integer;
      Target: TAtlasTrackerTarget;
      Provider: IAtlasTrackerProvider;
      Poll: TAtlasTrackerPoll;
    end;
    TOutcome = record
      Job: TJob;
      /// <summary>Ohne Token: nicht gefragt, kein Fehler.</summary>
      Skipped: Boolean;
      Succeeded: Boolean;
      Error: TAtlasCiFetchError;
      Changes: TArray<TAtlasTrackerChange>;
    end;
  private
    FHooks: TAtlasIssueNotifyHooks;
    FFolder: string;
    FStarted: Boolean;
    FTimer: TTimer;
    FWorker: TAtlasWorkerSlot;
    FFile: TAtlasTrackerNotifyFile;
    FLoaded: Boolean;
    FSchedules: TDictionary<string, TAtlasTrackerNotifySchedule>;
    FToast: TAtlasNoticeWindow;
    FToastOpen: TProc;
    FGeneration: Integer;
    procedure TimerTick(Sender: TObject);
    procedure Poll(AOnDemand: Boolean);
    procedure Delivered(const AOutcome: TOutcome);
    procedure Notify(const AJob: TJob; const ANotices: TArray<TAtlasTrackerNotice>; ARest: Integer);
    procedure NotifyError(const AJob: TJob; AError: TAtlasCiFetchError);
    procedure ShowToast(const ATitle, AText, AAction: string; const ARun: TProc);
    procedure OpenIssue(const ATarget: TAtlasTrackerTarget; const AKey: string; AAnchor: TDateTime);
    procedure EnsureLoaded;
    function SyncEnabled: Boolean;
    procedure SaveFile;
    function ScheduleOf(const AId: string): TAtlasTrackerNotifySchedule;
    function Jobs(AOnDemand: Boolean): TArray<TJob>;
    class function Worker(const AKeep: IInterface; AOwner: TAtlasIdeIssueNotify; const AJobs: TArray<TJob>;
      const ATransport: TAtlasIssuePreviewTransportHook): TProc; static;
    class procedure Deliver(const AKeep: IInterface; AOwner: TAtlasIdeIssueNotify; const AOutcome: TOutcome); static;
    class function OpenAction(const AKeep: IInterface; AOwner: TAtlasIdeIssueNotify; const ATarget: TAtlasTrackerTarget;
      const AKey: string; AAnchor: TDateTime): TProc; static;
    class function SettingsAction(const AKeep: IInterface; AOwner: TAtlasIdeIssueNotify): TProc; static;
    class function UserIsActive: Boolean; static;
    class function NowUtc: TDateTime; static;
  public
    /// <summary>AFolder: Ordner für notify.json (%LOCALAPPDATA%\Atlas\issues).</summary>
    constructor Create(const AHooks: TAtlasIssueNotifyHooks; const AFolder: string);
    destructor Destroy; override;
    procedure Start;
    /// <summary>Takt und Einblendung abmelden, kurz auf die Abfrage warten; danach wirkungslos.</summary>
    procedure Stop;
    /// <summary>Einstellungen geändert: ein- bzw. ausschalten und fällige Verbindungen gleich abfragen.</summary>
    procedure Refresh;
    /// <summary>„Meine Issues“ wurde geöffnet: abfragen, wenn die letzte Abfrage mindestens eine Minute her ist.
    /// </summary>
    procedure PollNow;
    /// <summary>Kennungen mit Punkt für den Tracker ATarget (GitHub: nur dieses Repository); nil ohne
    /// issues.notify.</summary>
    function Unseen(const ATarget: TAtlasTrackerTarget): TArray<string>;
    /// <summary>Erster neuer Kommentar des Issues mit Punkt (UTC); 0 ohne.</summary>
    function AnchorOf(const ATarget: TAtlasTrackerTarget; const AKey: string): TDateTime;
    /// <summary>Issue wurde geöffnet: Punkt entfernen.</summary>
    procedure Seen(const ATarget: TAtlasTrackerTarget; const AKey: string);
    /// <summary>issues.notify an?</summary>
    class function Active: Boolean; static;
  end;

implementation

uses
  Atlas.Core.Ci.Contract,
  Winapi.Windows,
  System.Types,
  System.DateUtils,
  Vcl.Forms,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Notifications.Center,
  Atlas.Core.Notifications.Contract,
  Atlas.Core.Notifications.Sources,
  Atlas.UI.Tracker.Strings,
  Atlas.UI.Popup.Window,
  Atlas.UI.Tracker.Notify,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings,
  Atlas.Core.Diagnostics.UserIdle;

{ TAtlasIdeIssueNotify }

constructor TAtlasIdeIssueNotify.Create(const AHooks: TAtlasIssueNotifyHooks; const AFolder: string);
begin
  inherited Create;
  FHooks := AHooks;
  FFolder := AFolder;
  FFile := TAtlasTrackerNotifyFile.Empty;
  FSchedules := TDictionary<string, TAtlasTrackerNotifySchedule>.Create;
  FWorker := TAtlasWorkerSlot.Create(HInstance);
end;

destructor TAtlasIdeIssueNotify.Destroy;
begin
  Stop;
  FWorker.Free;
  FSchedules.Free;
  inherited;
end;

class function TAtlasIdeIssueNotify.Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.IssuesNotify;
end;

class function TAtlasIdeIssueNotify.NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

class function TAtlasIdeIssueNotify.UserIsActive: Boolean;
var
  mMinimized: Boolean;
  mIdle: Cardinal;
begin
  mMinimized := IsIconic(Application.Handle);
  if (Application.MainForm <> nil) and Application.MainForm.HandleAllocated then
  begin
    mMinimized := mMinimized or IsIconic(Application.MainForm.Handle);
  end;
  // Ohne Angabe von Windows gilt der Benutzer als aktiv (0 ms).
  TAtlasUserIdle.IdleMs(mIdle);
  Result := TAtlasTrackerNotify.UserActive(mMinimized, mIdle);
end;

procedure TAtlasIdeIssueNotify.Start;
begin
  if FStarted then
  begin
    Exit;
  end;
  FStarted := True;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := TimerTick;
  FTimer.Enabled := True;
end;

procedure TAtlasIdeIssueNotify.Stop;
begin
  if not FStarted then
  begin
    Exit;
  end;
  FStarted := False;
  FreeAndNil(FTimer);
  FreeAndNil(FToast);
  FToastOpen := nil;
  // Die Abfrage endet mit der Zeitgrenze des Transports; kurz warten, dann sich selbst überlassen.
  FWorker.Stop(TAtlasShutdown.cStopMs);
  // Die Hooks halten „Meine Issues“: Stop löst den Ring.
  FHooks := Default(TAtlasIssueNotifyHooks);
end;


procedure TAtlasIdeIssueNotify.EnsureLoaded;
begin
  if FLoaded then
  begin
    Exit;
  end;
  FLoaded := True;
  FFile := TAtlasTrackerNotify.Load(FFolder);
end;

procedure TAtlasIdeIssueNotify.SaveFile;
begin
  if not TAtlasTrackerNotify.Save(FFolder, FFile) then
  begin
    TAtlasGuard.Log('Issue-Meldungen: Stand nicht gespeichert');
  end;
end;

function TAtlasIdeIssueNotify.SyncEnabled: Boolean;
var
  mIndex: Integer;
  mNow: TDateTime;
begin
  EnsureLoaded;
  Result := Active;
  if Result = FFile.Enabled then
  begin
    Exit;
  end;
  // Eingeschaltet: Was vorher geschah, ist nicht neu. Ausgeschaltet: Punkte verschwinden mit der Funktion.
  mNow := NowUtc;
  for mIndex := 0 to High(FFile.Connections) do
  begin
    FFile.Connections[mIndex].Since := mNow;
    FFile.Connections[mIndex].LastModified := '';
    FFile.Connections[mIndex].Unseen := nil;
  end;
  FFile.Enabled := Result;
  FSchedules.Clear;
  Inc(FGeneration);
  SaveFile;
  if Assigned(FHooks.Changed) then
  begin
    FHooks.Changed();
  end;
end;

function TAtlasIdeIssueNotify.ScheduleOf(const AId: string): TAtlasTrackerNotifySchedule;
begin
  if not FSchedules.TryGetValue(AId, Result) then
  begin
    Result := Default(TAtlasTrackerNotifySchedule);
  end;
end;

procedure TAtlasIdeIssueNotify.TimerTick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Tracker,
    procedure
    begin
      Poll(False);
    end);
end;

procedure TAtlasIdeIssueNotify.Refresh;
begin
  if not FStarted then
  begin
    Exit;
  end;
  Poll(False);
end;

procedure TAtlasIdeIssueNotify.PollNow;
begin
  if not FStarted then
  begin
    Exit;
  end;
  Poll(True);
end;

/// <summary>Ist die Verbindung fällig? Auf Anfrage nach eigener Regel, sonst nach issues.notifyInterval und
/// Aktivität des Benutzers.</summary>
function IsDue(var ASchedule: TAtlasTrackerNotifySchedule; AOnDemand, AActive: Boolean; ANowMs: UInt64): Boolean;
begin
  if AOnDemand then
  begin
    Result := ASchedule.DueOnDemand(ANowMs);
  end
  else
  begin
    Result := ASchedule.Due(ANowMs, AActive, TAtlasIdeSettings.Current.IssuesNotifyIntervalMinutes);
  end;
end;

/// <summary>Abfrage einer Verbindung ab ihrem Stand.</summary>
function PollOf(const AConnection: TAtlasTrackerNotifyConnection;
  const ASchedule: TAtlasTrackerNotifySchedule): TAtlasTrackerPoll;
begin
  Result := TAtlasTrackerPoll.Create(AConnection.Since, AConnection.Me,
    TAtlasTrackerNotify.ScopeOf(TAtlasIdeSettings.Current.IssuesNotifyScope));
  Result.LastModified := AConnection.LastModified;
  Result.PollSeconds := ASchedule.PollSeconds;
end;

function TAtlasIdeIssueNotify.Jobs(AOnDemand: Boolean): TArray<TJob>;
var
  mTarget: TAtlasTrackerTarget;
  mJob: TJob;
  mIds: TList<string>;
  mConnection: TAtlasTrackerNotifyConnection;
  mSchedule: TAtlasTrackerNotifySchedule;
  mNowMs: UInt64;
  mActive, mAdded: Boolean;
begin
  Result := nil;
  if not Assigned(FHooks.Targets) or not Assigned(FHooks.Provider) then
  begin
    Exit;
  end;
  mNowMs := GetTickCount64;
  mActive := UserIsActive;
  mAdded := False;
  mIds := TList<string>.Create;
  try
    for mTarget in FHooks.Targets() do
    begin
      mJob := Default(TJob);
      mJob.Id := TAtlasTrackerNotify.ConnectionId(mTarget);
      if (mJob.Id = '') or mIds.Contains(mJob.Id) then
      begin
        Continue;
      end;
      mIds.Add(mJob.Id);
      mSchedule := ScheduleOf(mJob.Id);
      if IsDue(mSchedule, AOnDemand, mActive, mNowMs) then
      begin
        mJob.Provider := FHooks.Provider(mTarget.Provider);
      end;
      if mJob.Provider = nil then
      begin
        Continue;
      end;
      mJob.Target := mTarget;
      mJob.Generation := FGeneration;
      // Neue Verbindung: ab jetzt.
      if not FFile.Find(mJob.Id, mConnection) then
      begin
        mConnection := TAtlasTrackerNotify.Fresh(mJob.Id, NowUtc);
        FFile.Put(mConnection);
        mAdded := True;
      end;
      mJob.Poll := PollOf(mConnection, mSchedule);
      mSchedule.Started(mNowMs);
      FSchedules.AddOrSetValue(mJob.Id, mSchedule);
      Result := Result + [mJob];
    end;
  finally
    mIds.Free;
  end;
  if mAdded then
  begin
    SaveFile;
  end;
end;

procedure TAtlasIdeIssueNotify.Poll(AOnDemand: Boolean);
var
  mJobs: TArray<TJob>;
begin
  if not FStarted or not SyncEnabled then
  begin
    Exit;
  end;
  // Eine Abfrage zur Zeit; was fällig bleibt, kommt mit dem nächsten Takt.
  FWorker.Prune;
  if FWorker.Busy then
  begin
    Exit;
  end;
  mJobs := Jobs(AOnDemand);
  if Length(mJobs) = 0 then
  begin
    Exit;
  end;
  FWorker.Start(TThread.CreateAnonymousThread(Worker(Self, Self, mJobs, FHooks.Transport)));
end;

/// <summary>Eine Verbindung abfragen. Token aus dem Anmeldespeicher, ohne Dialog; ohne Token kein Netz
/// (Skipped). Den Anmeldenamen fragt sie einmal je Verbindung (eigene Änderungen und „dir zugewiesen“).</summary>
function PollJob(const AJob: TAtlasIdeIssueNotify.TJob;
  const ATransport: TAtlasIssuePreviewTransportHook): TAtlasIdeIssueNotify.TOutcome;
var
  mTransport: IAtlasCiTransport;
  mStatus: Integer;
  mText: string;
  mIgnored: TAtlasCiFetchError;
begin
  Result := Default(TAtlasIdeIssueNotify.TOutcome);
  Result.Job := AJob;
  Result.Error := TAtlasCiFetchError.None;
  mTransport := nil;
  if Assigned(ATransport) then
  begin
    mTransport := ATransport(AJob.Provider, AJob.Target);
  end;
  Result.Skipped := mTransport = nil;
  if Result.Skipped then
  begin
    Exit;
  end;
  if (Result.Job.Poll.Me = '') and (AJob.Provider.ProbeUrl(AJob.Target) <> '') and
    mTransport.Get(AJob.Provider.ProbeUrl(AJob.Target), TAtlasTrackerNotify.cTimeoutMs, mStatus, mText,
    mIgnored) and (mStatus = 200) then
  begin
    Result.Job.Poll.Me := TAtlasTrackerNotify.LoginOf(mText);
  end;
  Result.Succeeded := AJob.Provider.Changes(AJob.Target, mTransport, TAtlasTrackerNotify.cTimeoutMs,
    Result.Job.Poll, Result.Changes, Result.Error);
end;

class function TAtlasIdeIssueNotify.Worker(const AKeep: IInterface; AOwner: TAtlasIdeIssueNotify;
  const AJobs: TArray<TJob>; const ATransport: TAtlasIssuePreviewTransportHook): TProc;
begin
  // Eigene Routine: Die anonyme Methode hält nur ihre Parameter, keinen Rahmen von Poll.
  Result :=
    procedure
    var
      mJob: TJob;
      mOutcome: TOutcome;
    begin
      for mJob in AJobs do
      begin
        if TAtlasShutdown.Signalled then
        begin
          Exit;
        end;
        mOutcome := Default(TOutcome);
        try
          mOutcome := PollJob(mJob, ATransport);
        except
          // Kein Dialog, kein Fehler an die IDE: als Netzfehler werten.
          on E: Exception do
          begin
            mOutcome := Default(TOutcome);
            mOutcome.Job := mJob;
            mOutcome.Error := TAtlasCiFetchError.Network;
            TAtlasGuard.Log('Issue-Meldungen: Abfrage mit ' + E.ClassName + ' abgebrochen');
          end;
        end;
        if TAtlasShutdown.Signalled then
        begin
          Exit;
        end;
        Deliver(AKeep, AOwner, mOutcome);
      end;
    end;
end;

class procedure TAtlasIdeIssueNotify.Deliver(const AKeep: IInterface; AOwner: TAtlasIdeIssueNotify;
  const AOutcome: TOutcome);
begin
  TAtlasMainThread.Queue(TAtlasFeature.Tracker,
    procedure
    begin
      if AKeep <> nil then
      begin
        AOwner.Delivered(AOutcome);
      end;
    end);
end;

procedure TAtlasIdeIssueNotify.Delivered(const AOutcome: TOutcome);
var
  mSchedule: TAtlasTrackerNotifySchedule;
  mConnection: TAtlasTrackerNotifyConnection;
  mNotices: TArray<TAtlasTrackerNotice>;
  mRest: Integer;
begin
  if not FStarted or not FFile.Enabled or AOutcome.Skipped or (AOutcome.Job.Generation <> FGeneration) then
  begin
    Exit;
  end;
  mSchedule := ScheduleOf(AOutcome.Job.Id);
  if not AOutcome.Succeeded then
  begin
    TAtlasGuard.Log(Format('Issue-Meldungen: %s nicht abgefragt (%s)', [AOutcome.Job.Target.Provider,
      TAtlasCiBuild.ErrorKey(AOutcome.Error)]));
    if mSchedule.Failed and (AOutcome.Error <> TAtlasCiFetchError.Cancelled) then
    begin
      NotifyError(AOutcome.Job, AOutcome.Error);
    end;
    FSchedules.AddOrSetValue(AOutcome.Job.Id, mSchedule);
    Exit;
  end;
  mSchedule.Succeeded(AOutcome.Job.Poll.PollSeconds);
  FSchedules.AddOrSetValue(AOutcome.Job.Id, mSchedule);
  FFile.Find(AOutcome.Job.Id, mConnection);
  mConnection.Me := AOutcome.Job.Poll.Me;
  mConnection.LastModified := AOutcome.Job.Poll.LastModified;
  mConnection.Since := TAtlasTrackerNotify.NextSince(mConnection.Since, AOutcome.Job.Poll.Latest);
  mNotices := TAtlasTrackerNotify.Summarize(TAtlasTrackerNotify.Foreign(AOutcome.Changes, mConnection.Me),
    TAtlasTrackerNotify.cMaxNotices, mRest);
  TAtlasTrackerNotify.MarkUnseen(mConnection, mNotices);
  FFile.Put(mConnection);
  SaveFile;
  // Anonym: Anbieter und Anzahl.
  TAtlasGuard.Log(Format('Issue-Meldungen: %s, %d Issues geändert', [AOutcome.Job.Target.Provider,
    Length(mNotices) + mRest]));
  if Length(mNotices) = 0 then
  begin
    Exit;
  end;
  Notify(AOutcome.Job, mNotices, mRest);
  if Assigned(FHooks.Changed) then
  begin
    FHooks.Changed();
  end;
  if Assigned(FHooks.Updated) then
  begin
    FHooks.Updated();
  end;
end;

class function TAtlasIdeIssueNotify.OpenAction(const AKeep: IInterface; AOwner: TAtlasIdeIssueNotify;
  const ATarget: TAtlasTrackerTarget; const AKey: string; AAnchor: TDateTime): TProc;
begin
  // Eigene Routine: Jede Meldung behält ihr Issue.
  Result :=
    procedure
    begin
      if AKeep <> nil then
      begin
        AOwner.OpenIssue(ATarget, AKey, AAnchor);
      end;
    end;
end;

class function TAtlasIdeIssueNotify.SettingsAction(const AKeep: IInterface; AOwner: TAtlasIdeIssueNotify): TProc;
begin
  Result :=
    procedure
    begin
      if (AKeep <> nil) and AOwner.FStarted and Assigned(AOwner.FHooks.Settings) then
      begin
        AOwner.FHooks.Settings();
      end;
    end;
end;

procedure TAtlasIdeIssueNotify.Notify(const AJob: TJob; const ANotices: TArray<TAtlasTrackerNotice>; ARest: Integer);
var
  mNotice: TAtlasTrackerNotice;
  mTarget: TAtlasTrackerTarget;
  mOpen: TProc;
  mCaption, mTitle: string;
  mCenter: IAtlasNotificationCenter;
  mIndex: Integer;
  mMode: TAtlasNotificationMode;
begin
  mCenter := TAtlasNotificationCenter.Default;
  mCaption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueNotifyOpen);
  if ARest > 0 then
  begin
    mCenter.Notify(TAtlasNotificationSources.cIssues, TAtlasNotificationSeverity.Info,
      TAtlasTrackerNoticeText.MoreTitle(ARest), TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueNotifyMoreText));
  end;
  // Älteste zuerst in die Liste, damit die neueste oben steht; eingeblendet wird nur die neueste.
  for mIndex := High(ANotices) downto 0 do
  begin
    mNotice := ANotices[mIndex];
    mTarget := AJob.Target;
    // GitHub: das Repository der Meldung, nicht das des Projekts.
    if mNotice.Project <> '' then
    begin
      mTarget.Project := mNotice.Project;
    end;
    mOpen := OpenAction(Self, Self, mTarget, mNotice.Key, mNotice.Anchor);
    mTitle := TAtlasTrackerNoticeText.Title(mNotice);
    mMode := mCenter.Notify(TAtlasNotificationSources.cIssues, TAtlasNotificationSeverity.Info, mTitle, mNotice.Title,
      [TAtlasNotificationCenter.Action(mCaption, mOpen)]);
    if (mIndex = 0) and (mMode = TAtlasNotificationMode.Show) then
    begin
      ShowToast(mTitle, mNotice.Title, mCaption, mOpen);
    end;
  end;
end;

procedure TAtlasIdeIssueNotify.NotifyError(const AJob: TJob; AError: TAtlasCiFetchError);
var
  mTitle, mText, mCaption: string;
  mRun: TProc;
begin
  mTitle := TAtlasTrackerNoticeText.ErrorTitle(AError, AJob.Target.Server);
  mText := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueNotifyErrorText);
  mCaption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewFixSettings);
  mRun := SettingsAction(Self, Self);
  if TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.cIssues, TAtlasNotificationSeverity.Warning,
    mTitle, mText, [TAtlasNotificationCenter.Action(mCaption, mRun)]) = TAtlasNotificationMode.Show then
  begin
    ShowToast(mTitle, mText, mCaption, mRun);
  end;
end;

procedure TAtlasIdeIssueNotify.ShowToast(const ATitle, AText, AAction: string; const ARun: TProc);
var
  mArea: TRect;
begin
  if FToast = nil then
  begin
    FToast := TAtlasNoticeWindow.Create(nil);
    FToast.OnAction :=
      procedure(AIndex: Integer)
      begin
        if (AIndex = 0) and Assigned(FToastOpen) then
        begin
          FToastOpen();
        end;
      end;
  end;
  FToastOpen := ARun;
  mArea := Screen.WorkAreaRect;
  if Application.MainForm <> nil then
  begin
    mArea := Application.MainForm.BoundsRect;
  end;
  FToast.Colors := TAtlasIdeStyle.Colors;
  FToast.SetScaling(TAtlasPopupWindow.MonitorPPI(mArea.BottomRight), 1, '', 10);
  FToast.ShowNotice(ATitle, AText, [AAction], mArea);
end;

procedure TAtlasIdeIssueNotify.OpenIssue(const ATarget: TAtlasTrackerTarget; const AKey: string; AAnchor: TDateTime);
var
  mAnchor: TDateTime;
begin
  if not FStarted or not Assigned(FHooks.Open) then
  begin
    Exit;
  end;
  // Der älteste ungesehene Kommentar, falls seit der Meldung weitere kamen.
  mAnchor := AnchorOf(ATarget, AKey);
  if mAnchor = 0 then
  begin
    mAnchor := AAnchor;
  end;
  Seen(ATarget, AKey);
  FHooks.Open(ATarget, AKey, mAnchor);
end;

function TAtlasIdeIssueNotify.Unseen(const ATarget: TAtlasTrackerTarget): TArray<string>;
var
  mConnection: TAtlasTrackerNotifyConnection;
  mItem: TAtlasTrackerUnseen;
begin
  Result := nil;
  if not FStarted or not Active then
  begin
    Exit;
  end;
  EnsureLoaded;
  if not FFile.Enabled or not FFile.Find(TAtlasTrackerNotify.ConnectionId(ATarget), mConnection) then
  begin
    Exit;
  end;
  for mItem in mConnection.Unseen do
  begin
    if SameText(mItem.Project, TAtlasTrackerNotify.UnseenProject(ATarget)) then
    begin
      Result := Result + [mItem.Key];
    end;
  end;
end;

function TAtlasIdeIssueNotify.AnchorOf(const ATarget: TAtlasTrackerTarget; const AKey: string): TDateTime;
var
  mConnection: TAtlasTrackerNotifyConnection;
  mIndex: Integer;
begin
  Result := 0;
  EnsureLoaded;
  if not FFile.Find(TAtlasTrackerNotify.ConnectionId(ATarget), mConnection) then
  begin
    Exit;
  end;
  mIndex := mConnection.IndexOfUnseen(AKey, TAtlasTrackerNotify.UnseenProject(ATarget));
  if mIndex >= 0 then
  begin
    Result := mConnection.Unseen[mIndex].Anchor;
  end;
end;

procedure TAtlasIdeIssueNotify.Seen(const ATarget: TAtlasTrackerTarget; const AKey: string);
var
  mConnection: TAtlasTrackerNotifyConnection;
begin
  if not FStarted then
  begin
    Exit;
  end;
  EnsureLoaded;
  if not FFile.Find(TAtlasTrackerNotify.ConnectionId(ATarget), mConnection) or
    not TAtlasTrackerNotify.Seen(mConnection, AKey, TAtlasTrackerNotify.UnseenProject(ATarget)) then
  begin
    Exit;
  end;
  FFile.Put(mConnection);
  SaveFile;
  if Assigned(FHooks.Changed) then
  begin
    FHooks.Changed();
  end;
end;

end.
