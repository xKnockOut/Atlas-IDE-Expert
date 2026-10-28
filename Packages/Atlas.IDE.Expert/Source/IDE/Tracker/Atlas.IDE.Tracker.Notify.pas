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
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Notify,
  Atlas.UI.Notifications.Notice,
  Atlas.IDE.Tracker.IssuePreview;

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
  end;

  TAtlasIdeIssueNotify = class(TInterfacedObject)
  public const
    /// <summary>Takt der Prüfung, ob eine Verbindung fällig ist.</summary>
    TickMs = 30000;
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
    FThread: TThread;
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
    procedure ReleaseThread(AWait: Boolean);
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
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Strings,
  Atlas.UI.Popup.Window,
  Atlas.UI.Tracker.Notify,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings;

{ TAtlasIdeIssueNotify }

constructor TAtlasIdeIssueNotify.Create(const AHooks: TAtlasIssueNotifyHooks; const AFolder: string);
begin
  inherited Create;
  FHooks := AHooks;
  FFolder := AFolder;
  FFile := TAtlasTrackerNotifyFile.Empty;
  FSchedules := TDictionary<string, TAtlasTrackerNotifySchedule>.Create;
end;

destructor TAtlasIdeIssueNotify.Destroy;
begin
  Stop;
  ReleaseThread(True);
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
  mInput: TLastInputInfo;
  mMinimized: Boolean;
  mIdle: UInt64;
  mNow: DWORD;
begin
  mMinimized := IsIconic(Application.Handle);
  if (Application.MainForm <> nil) and Application.MainForm.HandleAllocated then
    mMinimized := mMinimized or IsIconic(Application.MainForm.Handle);
  mIdle := 0;
  mInput.cbSize := SizeOf(mInput);
  // Zähler in Millisekunden (32 Bit, läuft nach 49 Tagen über): über den Überlauf hinweg gerechnet.
  if GetLastInputInfo(mInput) then
  begin
    mNow := GetTickCount;
    if mNow >= mInput.dwTime then
      mIdle := mNow - mInput.dwTime
    else
      mIdle := UInt64(High(DWORD)) - mInput.dwTime + mNow + 1;
  end;
  Result := TAtlasTrackerNotify.UserActive(mMinimized, mIdle);
end;

procedure TAtlasIdeIssueNotify.Start;
begin
  if FStarted then
    Exit;
  FStarted := True;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := TickMs;
  FTimer.OnTimer := TimerTick;
  FTimer.Enabled := True;
end;

procedure TAtlasIdeIssueNotify.Stop;
begin
  if not FStarted then
    Exit;
  FStarted := False;
  FreeAndNil(FTimer);
  FreeAndNil(FToast);
  FToastOpen := nil;
  // Die Abfrage endet mit der Zeitgrenze des Transports; kurz warten, dann sich selbst überlassen.
  ReleaseThread(True);
  // Die Hooks halten „Meine Issues“: Stop löst den Ring.
  FHooks := Default(TAtlasIssueNotifyHooks);
end;

procedure TAtlasIdeIssueNotify.ReleaseThread(AWait: Boolean);
begin
  if FThread = nil then
    Exit;
  if AWait and not FThread.Finished then
    TAtlasShutdown.WaitForThreads([FThread]);
  if FThread.Finished then
    FreeAndNil(FThread)
  else if AWait then
  begin
    FThread.FreeOnTerminate := True;
    FThread := nil;
  end;
end;

procedure TAtlasIdeIssueNotify.EnsureLoaded;
begin
  if FLoaded then
    Exit;
  FLoaded := True;
  FFile := TAtlasTrackerNotify.Load(FFolder);
end;

procedure TAtlasIdeIssueNotify.SaveFile;
begin
  if not TAtlasTrackerNotify.Save(FFolder, FFile) then
    TAtlasGuard.Log('Issue-Meldungen: Stand nicht gespeichert');
end;

function TAtlasIdeIssueNotify.SyncEnabled: Boolean;
var
  mIndex: Integer;
  mNow: TDateTime;
begin
  EnsureLoaded;
  Result := Active;
  if Result = FFile.Enabled then
    Exit;
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
    FHooks.Changed();
end;

function TAtlasIdeIssueNotify.ScheduleOf(const AId: string): TAtlasTrackerNotifySchedule;
begin
  if not FSchedules.TryGetValue(AId, Result) then
    Result := Default(TAtlasTrackerNotifySchedule);
end;

procedure TAtlasIdeIssueNotify.TimerTick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      Poll(False);
    end);
end;

procedure TAtlasIdeIssueNotify.Refresh;
begin
  if not FStarted then
    Exit;
  Poll(False);
end;

procedure TAtlasIdeIssueNotify.PollNow;
begin
  if not FStarted then
    Exit;
  Poll(True);
end;

function TAtlasIdeIssueNotify.Jobs(AOnDemand: Boolean): TArray<TJob>;
var
  mTarget: TAtlasTrackerTarget;
  mJob: TJob;
  mIds: TList<string>;
  mConnection: TAtlasTrackerNotifyConnection;
  mSchedule: TAtlasTrackerNotifySchedule;
  mSettings: TAtlasPluginSettings;
  mNowMs: UInt64;
  mActive, mDue, mAdded: Boolean;
begin
  Result := nil;
  if not Assigned(FHooks.Targets) or not Assigned(FHooks.Provider) then
    Exit;
  mSettings := TAtlasIdeSettings.Current;
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
        Continue;
      mIds.Add(mJob.Id);
      mSchedule := ScheduleOf(mJob.Id);
      if AOnDemand then
        mDue := mSchedule.DueOnDemand(mNowMs)
      else
        mDue := mSchedule.Due(mNowMs, mActive, mSettings.IssuesNotifyIntervalMinutes);
      if not mDue then
        Continue;
      mJob.Provider := FHooks.Provider(mTarget.Provider);
      if mJob.Provider = nil then
        Continue;
      mJob.Target := mTarget;
      mJob.Generation := FGeneration;
      // Neue Verbindung: ab jetzt.
      if not FFile.Find(mJob.Id, mConnection) then
      begin
        mConnection := TAtlasTrackerNotify.Fresh(mJob.Id, NowUtc);
        FFile.Put(mConnection);
        mAdded := True;
      end;
      mJob.Poll := TAtlasTrackerPoll.Create(mConnection.Since, mConnection.Me,
        TAtlasTrackerNotify.ScopeOf(mSettings.IssuesNotifyScope));
      mJob.Poll.LastModified := mConnection.LastModified;
      mJob.Poll.PollSeconds := mSchedule.PollSeconds;
      mSchedule.Started(mNowMs);
      FSchedules.AddOrSetValue(mJob.Id, mSchedule);
      Result := Result + [mJob];
    end;
  finally
    mIds.Free;
  end;
  if mAdded then
    SaveFile;
end;

procedure TAtlasIdeIssueNotify.Poll(AOnDemand: Boolean);
var
  mJobs: TArray<TJob>;
begin
  if not FStarted or not SyncEnabled then
    Exit;
  // Eine Abfrage zur Zeit; was fällig bleibt, kommt mit dem nächsten Takt.
  ReleaseThread(False);
  if FThread <> nil then
    Exit;
  mJobs := Jobs(AOnDemand);
  if Length(mJobs) = 0 then
    Exit;
  FThread := TThread.CreateAnonymousThread(Worker(Self, Self, mJobs, FHooks.Transport));
  FThread.FreeOnTerminate := False;
  FThread.Start;
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
      mTransport: IAtlasCiTransport;
      mStatus: Integer;
      mText: string;
      mIgnored: TAtlasCiFetchError;
    begin
      for mJob in AJobs do
      begin
        if TAtlasShutdown.Signalled then
          Exit;
        mOutcome := Default(TOutcome);
        mOutcome.Job := mJob;
        mOutcome.Changes := nil;
        mOutcome.Error := TAtlasCiFetchError.None;
        try
          // Token aus dem Anmeldespeicher, ohne Dialog; ohne Token kein Netz.
          mTransport := nil;
          if Assigned(ATransport) then
            mTransport := ATransport(mJob.Provider, mJob.Target);
          if mTransport = nil then
            mOutcome.Skipped := True
          else
          begin
            // Anmeldename einmal je Verbindung: eigene Änderungen und „dir zugewiesen“.
            if (mOutcome.Job.Poll.Me = '') and (mJob.Provider.ProbeUrl(mJob.Target) <> '') and
              mTransport.Get(mJob.Provider.ProbeUrl(mJob.Target), TAtlasTrackerNotify.TimeoutMs, mStatus, mText,
              mIgnored) and (mStatus = 200) then
              mOutcome.Job.Poll.Me := TAtlasTrackerNotify.LoginOf(mText);
            mOutcome.Succeeded := mJob.Provider.Changes(mJob.Target, mTransport, TAtlasTrackerNotify.TimeoutMs,
              mOutcome.Job.Poll, mOutcome.Changes, mOutcome.Error);
          end;
        except
          // Kein Dialog, kein Fehler an die IDE: als Netzfehler werten.
          on E: Exception do
          begin
            mOutcome.Succeeded := False;
            mOutcome.Error := TAtlasCiFetchError.Network;
            TAtlasGuard.Log('Issue-Meldungen: Abfrage mit ' + E.ClassName + ' abgebrochen');
          end;
        end;
        mTransport := nil;
        if TAtlasShutdown.Signalled then
          Exit;
        Deliver(AKeep, AOwner, mOutcome);
      end;
    end;
end;

class procedure TAtlasIdeIssueNotify.Deliver(const AKeep: IInterface; AOwner: TAtlasIdeIssueNotify;
  const AOutcome: TOutcome);
begin
  TAtlasMainThread.Queue(TAtlasFeature.WelcomePage,
    procedure
    begin
      if AKeep <> nil then
        AOwner.Delivered(AOutcome);
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
    Exit;
  mSchedule := ScheduleOf(AOutcome.Job.Id);
  if not AOutcome.Succeeded then
  begin
    TAtlasGuard.Log(Format('Issue-Meldungen: %s nicht abgefragt (%s)', [AOutcome.Job.Target.Provider,
      TAtlasCiBuild.ErrorKey(AOutcome.Error)]));
    if mSchedule.Failed and (AOutcome.Error <> TAtlasCiFetchError.Cancelled) then
      NotifyError(AOutcome.Job, AOutcome.Error);
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
    TAtlasTrackerNotify.MaxNotices, mRest);
  TAtlasTrackerNotify.MarkUnseen(mConnection, mNotices);
  FFile.Put(mConnection);
  SaveFile;
  // Anonym: Anbieter und Anzahl.
  TAtlasGuard.Log(Format('Issue-Meldungen: %s, %d Issues geändert', [AOutcome.Job.Target.Provider,
    Length(mNotices) + mRest]));
  if Length(mNotices) = 0 then
    Exit;
  Notify(AOutcome.Job, mNotices, mRest);
  if Assigned(FHooks.Changed) then
    FHooks.Changed();
end;

class function TAtlasIdeIssueNotify.OpenAction(const AKeep: IInterface; AOwner: TAtlasIdeIssueNotify;
  const ATarget: TAtlasTrackerTarget; const AKey: string; AAnchor: TDateTime): TProc;
begin
  // Eigene Routine: Jede Meldung behält ihr Issue.
  Result :=
    procedure
    begin
      if AKeep <> nil then
        AOwner.OpenIssue(ATarget, AKey, AAnchor);
    end;
end;

class function TAtlasIdeIssueNotify.SettingsAction(const AKeep: IInterface; AOwner: TAtlasIdeIssueNotify): TProc;
begin
  Result :=
    procedure
    begin
      if (AKeep <> nil) and AOwner.FStarted and Assigned(AOwner.FHooks.Settings) then
        AOwner.FHooks.Settings();
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
  mCaption := TAtlasStrings.Text(TAtlasTextId.IssueNotifyOpen);
  if ARest > 0 then
    mCenter.Notify(TAtlasNotificationSources.Issues, TAtlasNotificationSeverity.Info,
      TAtlasTrackerNoticeText.MoreTitle(ARest), TAtlasStrings.Text(TAtlasTextId.IssueNotifyMoreText));
  // Älteste zuerst in die Liste, damit die neueste oben steht; eingeblendet wird nur die neueste.
  for mIndex := High(ANotices) downto 0 do
  begin
    mNotice := ANotices[mIndex];
    mTarget := AJob.Target;
    // GitHub: das Repository der Meldung, nicht das des Projekts.
    if mNotice.Project <> '' then
      mTarget.Project := mNotice.Project;
    mOpen := OpenAction(Self, Self, mTarget, mNotice.Key, mNotice.Anchor);
    mTitle := TAtlasTrackerNoticeText.Title(mNotice);
    mMode := mCenter.Notify(TAtlasNotificationSources.Issues, TAtlasNotificationSeverity.Info, mTitle, mNotice.Title,
      [TAtlasNotificationCenter.Action(mCaption, mOpen)]);
    if (mIndex = 0) and (mMode = TAtlasNotificationMode.Show) then
      ShowToast(mTitle, mNotice.Title, mCaption, mOpen);
  end;
end;

procedure TAtlasIdeIssueNotify.NotifyError(const AJob: TJob; AError: TAtlasCiFetchError);
var
  mTitle, mText, mCaption: string;
  mRun: TProc;
begin
  mTitle := TAtlasTrackerNoticeText.ErrorTitle(AError, AJob.Target.Server);
  mText := TAtlasStrings.Text(TAtlasTextId.IssueNotifyErrorText);
  mCaption := TAtlasStrings.Text(TAtlasTextId.IssuePreviewFixSettings);
  mRun := SettingsAction(Self, Self);
  if TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.Issues, TAtlasNotificationSeverity.Warning,
    mTitle, mText, [TAtlasNotificationCenter.Action(mCaption, mRun)]) = TAtlasNotificationMode.Show then
    ShowToast(mTitle, mText, mCaption, mRun);
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
          FToastOpen();
      end;
  end;
  FToastOpen := ARun;
  mArea := Screen.WorkAreaRect;
  if Application.MainForm <> nil then
    mArea := Application.MainForm.BoundsRect;
  FToast.Colors := TAtlasIdeStyle.Colors;
  FToast.SetScaling(TAtlasPopupWindow.MonitorPPI(mArea.BottomRight), 1, '', 10);
  FToast.ShowNotice(ATitle, AText, [AAction], mArea);
end;

procedure TAtlasIdeIssueNotify.OpenIssue(const ATarget: TAtlasTrackerTarget; const AKey: string; AAnchor: TDateTime);
var
  mAnchor: TDateTime;
begin
  if not FStarted or not Assigned(FHooks.Open) then
    Exit;
  // Der älteste ungesehene Kommentar, falls seit der Meldung weitere kamen.
  mAnchor := AnchorOf(ATarget, AKey);
  if mAnchor = 0 then
    mAnchor := AAnchor;
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
    Exit;
  EnsureLoaded;
  if not FFile.Enabled or not FFile.Find(TAtlasTrackerNotify.ConnectionId(ATarget), mConnection) then
    Exit;
  for mItem in mConnection.Unseen do
    if SameText(mItem.Project, TAtlasTrackerNotify.UnseenProject(ATarget)) then
      Result := Result + [mItem.Key];
end;

function TAtlasIdeIssueNotify.AnchorOf(const ATarget: TAtlasTrackerTarget; const AKey: string): TDateTime;
var
  mConnection: TAtlasTrackerNotifyConnection;
  mIndex: Integer;
begin
  Result := 0;
  EnsureLoaded;
  if not FFile.Find(TAtlasTrackerNotify.ConnectionId(ATarget), mConnection) then
    Exit;
  mIndex := mConnection.IndexOfUnseen(AKey, TAtlasTrackerNotify.UnseenProject(ATarget));
  if mIndex >= 0 then
    Result := mConnection.Unseen[mIndex].Anchor;
end;

procedure TAtlasIdeIssueNotify.Seen(const ATarget: TAtlasTrackerTarget; const AKey: string);
var
  mConnection: TAtlasTrackerNotifyConnection;
begin
  if not FStarted then
    Exit;
  EnsureLoaded;
  if not FFile.Find(TAtlasTrackerNotify.ConnectionId(ATarget), mConnection) or
    not TAtlasTrackerNotify.Seen(mConnection, AKey, TAtlasTrackerNotify.UnseenProject(ATarget)) then
    Exit;
  FFile.Put(mConnection);
  SaveFile;
  if Assigned(FHooks.Changed) then
    FHooks.Changed();
end;

end.
