unit Atlas.IDE.Tracker.SprintTile;

// Bereich „Sprint“ in der IDE (#1277): Quelle der Kachel (IAtlasSprintSource)
// und Anmeldung als Bereich atlas.sprint der Willkommensseite.
// - Tracker wie „Meine Issues“ (Projekt des Bereichs: .atlas, sonst Zuordnung
//   #1261); Board-Zugriff wie das Fenster „Atlas-Board“ (#1272,
//   TAtlasIdeBoard.BoardsOf). Ohne Tracker bzw. Board der Hinweis mit
//   „zuordnen …“.
// - Keine eigene Abfrage-Schleife: geladen wird beim Anzeigen des Bereichs
//   und nach jeder Abfrage von „Meine Issues“, höchstens alle 10 Minuten
//   (DueMinutes von „Meine Issues“); „Jetzt abfragen“ lädt sofort. Im
//   Hintergrund (TAtlasVcsWorker) mit 15 s für alles zusammen: aktueller
//   Sprint, Arbeitstage (YouTrack, IAtlasTrackerWorkDays) und mit
//   issues.sprint.compare die drei vorherigen Sprints.
// - Zwischenspeicher neben dem Board (%LOCALAPPDATA%\Atlas\issues):
//   "<TrackerId>-sprint.json" (letzter Stand des aktuellen Sprints),
//   "<TrackerId>-workdays.json" (Arbeitstage als Text) und je
//   abgeschlossenem Sprint "<TrackerId>-sprint-<Board>-<Sprint>.json" mit der
//   Zusammenfassung; die werden nie neu gefragt. Ohne Antwort bleibt der
//   letzte Stand mit „Stand vom … · Grund“.
// - Mit welcomePage.sprint aus: kein Bereich, keine Abfrage.
// - Protokoll anonym: nur Anbieter und Ergebnis.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Diagnostics,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Board,
  Atlas.Core.Tracker.Sprint,
  Atlas.Core.VersionControl.Worker,
  Atlas.UI.Tracker.SprintTile,
  Atlas.IDE.Tracker.WelcomeLink;

type
  TAtlasSprintProviderHook = reference to function(const AName: string): IAtlasTrackerProvider;
  /// <summary>Transport mit dem Token aus dem Anmeldespeicher; nil ohne Token.</summary>
  TAtlasSprintTransportHook = reference to function(const AProvider: IAtlasTrackerProvider;
    const ATarget: TAtlasTrackerTarget): IAtlasCiTransport;
  /// <summary>„Meine Issues“ auf AIssues beschränken, Beschriftung ACaption.</summary>
  TAtlasSprintFilterHook = reference to procedure(const ACaption: string; const AIssues: TArray<TAtlasTrackerIssue>);

  TAtlasSprintHooks = record
    Provider: TAtlasSprintProviderHook;
    Transport: TAtlasSprintTransportHook;
    /// <summary>Projekt des Bereichs „Meine Issues“; '' ohne.</summary>
    Project: TFunc<string>;
    /// <summary>Tracker dieses Projekts; Server '' ohne.</summary>
    Target: TFunc<string, TAtlasTrackerTarget>;
    /// <summary>Fenster „Atlas-Board“ (#1272).</summary>
    OpenBoard: TProc;
    Filter: TAtlasSprintFilterHook;
    CanAssign: TFunc<Boolean>;
    /// <summary>„zuordnen …“ (#1261).</summary>
    Assign: TProc;
    /// <summary>Meldungen an die Willkommensseite (gehört dem Aufrufer); nil ohne.</summary>
    Welcome: TAtlasTrackerWelcomeLink;
  end;

  /// <summary>Stand der Kachel für den Tracker des Projekts (letzte Antwort bzw. Zwischenspeicher).</summary>
  TAtlasSprintState = record
    HasSnapshot: Boolean;
    Snapshot: TAtlasBoardSnapshot;
    Calendar: TAtlasSprintCalendar;
    Previous: TArray<TAtlasSprintSummary>;
    // Die Vorsprints wurden mit dem Vergleich geladen (issues.sprint.compare eingeschaltet: neu laden).
    WithPrevious: Boolean;
    Stale: Boolean;
    Error: TAtlasCiFetchError;
  end;

  /// <summary>Ergebnis einer Abfrage im Hintergrund.</summary>
  TAtlasSprintResult = record
    Succeeded: Boolean;
    Snapshot: TAtlasBoardSnapshot;
    Calendar: TAtlasSprintCalendar;
    /// <summary>Arbeitstage kamen vom Tracker (sonst bleibt der Kalender des Stands).</summary>
    CalendarKnown: Boolean;
    Previous: TArray<TAtlasSprintSummary>;
    WithPrevious: Boolean;
    Error: TAtlasCiFetchError;
    /// <summary>Fehlschlag mit AError; ACalendar bleibt.</summary>
    class function Failed(const ACalendar: TAtlasSprintCalendar; AError: TAtlasCiFetchError): TAtlasSprintResult;
      static;
  end;

  /// <summary>Eine Abfrage: aktueller Sprint, Arbeitstage und mit Vergleich die Vorsprints; läuft im
  /// Hintergrund und schreibt nur in Outcome.</summary>
  TAtlasSprintJob = record
    Target: TAtlasTrackerTarget;
    Boards: IAtlasTrackerBoards;
    WorkDays: IAtlasTrackerWorkDays;
    Transport: IAtlasCiTransport;
    Folder: string;
    /// <summary>Gewähltes Board ('' = das erste des Projekts).</summary>
    BoardId: string;
    /// <summary>issues.sprint.compare: frühere Sprints fragen.</summary>
    Compare: Boolean;
    Watch: TStopwatch;
    Outcome: TAtlasSprintResult;
    procedure Execute;
    function LoadCurrent: Boolean;
    procedure LoadWorkDays;
    procedure LoadPrevious;
  end;

  TAtlasIdeSprint = class(TInterfacedObject, IAtlasSprintSource)
  public const
    /// <summary>Kennung der Kachel; dieselbe wie früher als Bereich der Willkommensseite.</summary>
    cTileId = 'atlas.sprint';
    /// <summary>Reihenfolge außerhalb des Atlas-Layouts: direkt nach „Meine Issues“.</summary>
    cOrder = 27;
    /// <summary>Name des Zwischenspeichers für den aktuellen Sprint bzw. die Arbeitstage.</summary>
    cCacheName = 'sprint';
    cWorkDaysName = 'workdays';
  private
    FHooks: TAtlasSprintHooks;
    FCacheFolder: string;
    FStarted: Boolean;
    FTitle: string;
    FActive: Boolean;
    FWorker: TAtlasVcsWorker;
    FCancel: IAtlasCiCancel;
    FGeneration: Integer;
    FLoading: Boolean;
    // Stand für den Tracker FTargetKey (Wechsel des Projekts: aus dem Zwischenspeicher neu).
    FTargetKey: string;
    FPrepared: Boolean;
    FState: TAtlasSprintState;
    FLoadedTick: UInt64;
    procedure Changed;
    /// <summary>Titel oder Schalter der Kachel geändert: der Willkommensseite melden.</summary>
    procedure UpdateTileInfo;
    function CurrentTarget(out ATarget: TAtlasTrackerTarget): Boolean;
    procedure Prepare(const ATarget: TAtlasTrackerTarget);
    procedure Load(AForce: Boolean);
    /// <summary>Fällige Abfrage vorbereiten; False, wenn nichts zu fragen ist.</summary>
    function Fetchable(AForce: Boolean; out AJob: TAtlasSprintJob): Boolean;
    procedure Run(AGeneration: Integer; const AJob: TAtlasSprintJob);
    procedure Loaded(AGeneration: Integer; const ATarget: TAtlasTrackerTarget; const AResult: TAtlasSprintResult);
    procedure CancelLoad;
    function Due(const ATarget: TAtlasTrackerTarget): Boolean;
    class function NowUtc: TDateTime; static;
  public
    /// <summary>ACacheFolder: Ordner des Zwischenspeichers ('' = keiner).</summary>
    constructor Create(const AHooks: TAtlasSprintHooks; const ACacheFolder: string);
    destructor Destroy; override;
    /// <summary>Starten; die Kachel stellt die Komposition bereit.</summary>
    procedure Start;
    /// <summary>Abbrechen, Hooks lösen; danach wirkungslos.</summary>
    procedure Stop;
    /// <summary>Nach geänderten Einstellungen oder anderem Projekt: Sichtbarkeit, Titel und Inhalt neu.</summary>
    procedure Refresh;
    /// <summary>Nach einer Abfrage von „Meine Issues“ (#765): laden, wenn fällig; AForce bei „Jetzt abfragen“.
    /// </summary>
    procedure IssuesFetched(AForce: Boolean);
    /// <summary>welcomePage.sprint an?</summary>
    class function Active: Boolean; static;
    /// <summary>Zusammenfassung des abgeschlossenen Sprints ASprintId aus dem Zwischenspeicher; False ohne
    /// (lesbare) Datei.</summary>
    class function CachedSummary(const AFolder: string; const ATarget: TAtlasTrackerTarget;
      const ABoardId, ASprintId: string; out ASummary: TAtlasSprintSummary): Boolean; static;
    /// <summary>Zusammenfassung eines abgeschlossenen Sprints merken; Fehler beim Schreiben werden übergangen.
    /// </summary>
    class procedure SaveSummary(const AFolder: string; const ATarget: TAtlasTrackerTarget; const ABoardId: string;
      const ASummary: TAtlasSprintSummary); static;
    { IAtlasSprintSource }
    function View: TAtlasSprintTile;
    procedure Shown;
    procedure OpenBoard;
    procedure BrowseBoard;
    procedure FilterIssues(ADone: Boolean);
    procedure AssignProject;
  end;

implementation

uses
  Winapi.Windows,
  System.DateUtils,
  Atlas.Core.Tracker.Files,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Tracker.MyIssues,
  Atlas.UI.Tracker.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Tracker.Board;

const
  cStopWaitMs = 1000;
  cMsPerMinute = 60000;
  // Weniger Zeit übrig: keine weiteren Vorsprints fragen.
  cMinLeftMs = 1000;
  cLogAborted = 'Sprint: Abfrage mit %s abgebrochen';
  cLogOutcome = 'Sprint: %s, %s';

{ TAtlasSprintResult }

class function TAtlasSprintResult.Failed(const ACalendar: TAtlasSprintCalendar;
  AError: TAtlasCiFetchError): TAtlasSprintResult;
begin
  Result := Default(TAtlasSprintResult);
  Result.Calendar := ACalendar;
  Result.Error := AError;
end;

{ TAtlasSprintJob }

procedure TAtlasSprintJob.Execute;
begin
  Watch := TStopwatch.StartNew;
  Outcome.WithPrevious := Compare;
  try
    Outcome.Succeeded := LoadCurrent;
    if Outcome.Succeeded then
    begin
      LoadWorkDays;
    end;
    if Outcome.Succeeded and Compare then
    begin
      LoadPrevious;
    end;
  except
    // Kein Dialog, kein Fehler an die IDE: als Netzfehler werten.
    on E: Exception do
    begin
      Outcome.Succeeded := False;
      Outcome.Error := TAtlasCiFetchError.Network;
      TAtlasGuard.Log(Format(cLogAborted, [E.ClassName], TFormatSettings.Invariant));
    end;
  end;
  Transport := nil;
end;

function TAtlasSprintJob.LoadCurrent: Boolean;
begin
  Result := Boards.LoadBoard(TAtlasBoardRequest.Create(Target, Transport, BoardId, '', TAtlasTrackerBoard.cTimeoutMs),
    Outcome.Snapshot, Outcome.Error);
  // Board weg (gelöscht, kein Zugriff mehr): das erste des Projekts.
  if not Result and (BoardId <> '') and (Outcome.Error = TAtlasCiFetchError.NotFound) then
  begin
    Result := Boards.LoadBoard(TAtlasBoardRequest.Create(Target, Transport, '', '', TAtlasTrackerBoard.cTimeoutMs),
      Outcome.Snapshot, Outcome.Error);
  end;
end;

procedure TAtlasSprintJob.LoadWorkDays;
var
  mDays: TArray<Integer>;
begin
  if (WorkDays <> nil) and WorkDays.WorkDays(Target, Transport, TAtlasTrackerBoard.cTimeoutMs, mDays) then
  begin
    Outcome.Calendar := TAtlasSprintCalendar.Create(mDays);
    Outcome.CalendarKnown := True;
  end;
end;

procedure TAtlasSprintJob.LoadPrevious;
var
  mSprint: TAtlasBoardSprint;
  mSummary: TAtlasSprintSummary;
  mOld: TAtlasBoardSnapshot;
  mOldError: TAtlasCiFetchError;
  mLeft: Int64;
begin
  for mSprint in TAtlasTrackerSprint.PreviousSprints(Outcome.Snapshot.Sprints, Outcome.Snapshot.Sprint,
    TAtlasTrackerSprint.cVelocitySprints) do
  begin
    // Abgeschlossene Sprints ändern sich nicht: einmal fragen, dann aus dem Zwischenspeicher.
    mLeft := TAtlasTrackerSprint.cTimeoutMs - Watch.ElapsedMilliseconds;
    if TAtlasIdeSprint.CachedSummary(Folder, Target, Outcome.Snapshot.Board.Id, mSprint.Id, mSummary) then
    begin
      Outcome.Previous := Outcome.Previous + [mSummary];
    end
    else if mLeft < cMinLeftMs then
    begin
      Break;
    end
    else if Boards.LoadBoard(TAtlasBoardRequest.Create(Target, Transport, Outcome.Snapshot.Board.Id, mSprint.Id,
      Integer(mLeft)), mOld, mOldError) then
    begin
      mSummary := TAtlasTrackerSprint.Summarize(mOld, Outcome.Calendar, TAtlasIdeSprint.NowUtc);
      TAtlasIdeSprint.SaveSummary(Folder, Target, Outcome.Snapshot.Board.Id, mSummary);
      Outcome.Previous := Outcome.Previous + [mSummary];
    end;
  end;
end;

{ TAtlasIdeSprint }

constructor TAtlasIdeSprint.Create(const AHooks: TAtlasSprintHooks; const ACacheFolder: string);
begin
  inherited Create;
  FHooks := AHooks;
  FCacheFolder := ACacheFolder;
  FWorker := TAtlasVcsWorker.Create;
  FState.Calendar := TAtlasSprintCalendar.WorkWeek;
end;

destructor TAtlasIdeSprint.Destroy;
begin
  FWorker.Free;
  inherited;
end;

class function TAtlasIdeSprint.Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.WelcomePageSprint;
end;

class function TAtlasIdeSprint.NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

procedure TAtlasIdeSprint.Start;
begin
  if FStarted then
  begin
    Exit;
  end;
  FStarted := True;
  FTitle := '';
  UpdateTileInfo;
end;

procedure TAtlasIdeSprint.Stop;
begin
  if not FStarted then
  begin
    Exit;
  end;
  FStarted := False;
  Inc(FGeneration);
  CancelLoad;
  FWorker.Stop(cStopWaitMs);
  // Die Hooks halten den Bereich „Meine Issues“: Stop löst den Ring.
  FHooks := Default(TAtlasSprintHooks);
end;

procedure TAtlasIdeSprint.CancelLoad;
begin
  if FCancel <> nil then
  begin
    FCancel.Cancel;
  end;
  FCancel := nil;
end;

procedure TAtlasIdeSprint.UpdateTileInfo;
var
  mTitle: string;
begin
  if not FStarted then
  begin
    Exit;
  end;
  mTitle := TAtlasTrackerSprintView.TitleText;
  // Nur beim ersten Mal, nach einem Sprachwechsel bzw. mit umgeschaltetem welcomePage.sprint.
  if (mTitle <> FTitle) or (FActive <> Active) then
  begin
    FTitle := mTitle;
    FActive := Active;
    if FHooks.Welcome <> nil then
    begin
      FHooks.Welcome.TileInfoChanged(cTileId);
    end;
  end;
end;

procedure TAtlasIdeSprint.Refresh;
begin
  if not FStarted then
  begin
    Exit;
  end;
  UpdateTileInfo;
  // Anderes Projekt bzw. andere Zuordnung: Stand aus dem Zwischenspeicher des neuen Trackers.
  FPrepared := False;
  Changed;
end;

procedure TAtlasIdeSprint.Changed;
begin
  if FStarted and (FHooks.Welcome <> nil) then
  begin
    FHooks.Welcome.TileChanged(cTileId);
  end;
end;

function TAtlasIdeSprint.CurrentTarget(out ATarget: TAtlasTrackerTarget): Boolean;
var
  mProject: string;
begin
  ATarget := TAtlasTrackerTarget.Create('', '', '', '');
  mProject := '';
  if Assigned(FHooks.Project) then
  begin
    mProject := FHooks.Project();
  end;
  Result := mProject <> '';
  if Result and Assigned(FHooks.Target) then
  begin
    ATarget := FHooks.Target(mProject);
  end;
end;

class function TAtlasIdeSprint.CachedSummary(const AFolder: string; const ATarget: TAtlasTrackerTarget;
  const ABoardId, ASprintId: string; out ASummary: TAtlasSprintSummary): Boolean;
var
  mFile, mText: string;
begin
  ASummary := Default(TAtlasSprintSummary);
  mFile := TAtlasTrackerBoard.CacheFile(AFolder, ATarget, TAtlasTrackerSprint.SummaryName(ABoardId, ASprintId));
  Result := (mFile <> '') and TAtlasTrackerBoard.ReadText(mFile, mText) and
    TAtlasTrackerSprint.SummaryFromJson(mText, ASummary);
end;

class procedure TAtlasIdeSprint.SaveSummary(const AFolder: string; const ATarget: TAtlasTrackerTarget;
  const ABoardId: string; const ASummary: TAtlasSprintSummary);
var
  mFile: string;
begin
  mFile := TAtlasTrackerBoard.CacheFile(AFolder, ATarget, TAtlasTrackerSprint.SummaryName(ABoardId, ASummary.Id));
  if mFile <> '' then
  begin
    TAtlasTrackerBoard.WriteText(mFile, TAtlasTrackerSprint.SummaryToJson(ASummary));
  end;
end;

procedure TAtlasIdeSprint.Prepare(const ATarget: TAtlasTrackerTarget);
var
  mSprint: TAtlasBoardSprint;
  mSummary: TAtlasSprintSummary;
  mFile, mText: string;
begin
  if FPrepared and SameText(FTargetKey, ATarget.Key) then
  begin
    Exit;
  end;
  // Anderer Tracker: laufende Abfrage gilt nicht mehr, letzter Stand aus dem Zwischenspeicher.
  if not SameText(FTargetKey, ATarget.Key) then
  begin
    Inc(FGeneration);
    CancelLoad;
    FLoading := False;
    FLoadedTick := 0;
  end;
  FPrepared := True;
  FTargetKey := ATarget.Key;
  FState.Stale := False;
  FState.Error := TAtlasCiFetchError.None;
  FState.Previous := nil;
  FState.WithPrevious := False;
  FState.Calendar := TAtlasSprintCalendar.WorkWeek;
  FState.HasSnapshot := TAtlasTrackerBoard.Load(FCacheFolder, ATarget, cCacheName, FState.Snapshot);
  if not FState.HasSnapshot then
  begin
    FState.Snapshot := TAtlasBoardSnapshot.Empty;
  end;
  mFile := TAtlasTrackerBoard.CacheFile(FCacheFolder, ATarget, cWorkDaysName);
  if (mFile <> '') and TAtlasTrackerBoard.ReadText(mFile, mText) then
  begin
    FState.Calendar := TAtlasSprintCalendar.FromText(mText);
  end;
  if not FState.HasSnapshot then
  begin
    Exit;
  end;
  // Vorsprints nur aus dem Zwischenspeicher; fehlt einer, holt ihn die nächste Abfrage.
  for mSprint in TAtlasTrackerSprint.PreviousSprints(FState.Snapshot.Sprints, FState.Snapshot.Sprint,
    TAtlasTrackerSprint.cVelocitySprints) do
  begin
    if CachedSummary(FCacheFolder, ATarget, FState.Snapshot.Board.Id, mSprint.Id, mSummary) then
    begin
      FState.Previous := FState.Previous + [mSummary];
    end;
  end;
end;

function TAtlasIdeSprint.Due(const ATarget: TAtlasTrackerTarget): Boolean;
begin
  Result := (FLoadedTick = 0) or (GetTickCount64 - FLoadedTick >= UInt64(TAtlasMyIssues.cDueMinutes) * cMsPerMinute) or
    (TAtlasIdeSettings.Current.IssuesSprintCompare and not FState.WithPrevious);
end;

procedure TAtlasIdeSprint.Shown;
begin
  Load(False);
end;

procedure TAtlasIdeSprint.IssuesFetched(AForce: Boolean);
begin
  Load(AForce);
end;

procedure TAtlasIdeSprint.Load(AForce: Boolean);
var
  mJob: TAtlasSprintJob;
  mGeneration: Integer;
begin
  if not Fetchable(AForce, mJob) then
  begin
    Exit;
  end;
  Inc(FGeneration);
  mGeneration := FGeneration;
  FLoadedTick := GetTickCount64;
  if mJob.Transport = nil then
  begin
    Loaded(mGeneration, mJob.Target, TAtlasSprintResult.Failed(FState.Calendar, TAtlasCiFetchError.Unauthorized));
    Exit;
  end;
  if not Supports(mJob.Transport, IAtlasCiCancel, FCancel) then
  begin
    FCancel := nil;
  end;
  if not Supports(mJob.Boards, IAtlasTrackerWorkDays, mJob.WorkDays) then
  begin
    mJob.WorkDays := nil;
  end;
  FLoading := True;
  Run(mGeneration, mJob);
  Changed;
end;

function TAtlasIdeSprint.Fetchable(AForce: Boolean; out AJob: TAtlasSprintJob): Boolean;
var
  mTarget: TAtlasTrackerTarget;
  mProvider: IAtlasTrackerProvider;
begin
  AJob := Default(TAtlasSprintJob);
  // welcomePage.sprint aus: keine Abfrage.
  Result := FStarted and Active and not FLoading;
  if not Result or not CurrentTarget(mTarget) or (mTarget.Server = '') then
  begin
    Exit(False);
  end;
  Prepare(mTarget);
  mProvider := nil;
  if Assigned(FHooks.Provider) then
  begin
    mProvider := FHooks.Provider(mTarget.Provider);
  end;
  AJob.Target := mTarget;
  AJob.Boards := TAtlasIdeBoard.BoardsOf(mProvider);
  Result := (AForce or Due(mTarget)) and (mProvider <> nil) and (AJob.Boards <> nil);
  if Result and Assigned(FHooks.Transport) then
  begin
    AJob.Transport := FHooks.Transport(mProvider, mTarget);
  end;
end;

procedure TAtlasIdeSprint.Run(AGeneration: Integer; const AJob: TAtlasSprintJob);
var
  mJob: TAtlasSprintJob;
  mGeneration: Integer;
  mKeep: IAtlasSprintSource;
  mOwner: TAtlasIdeSprint;
begin
  mJob := AJob;
  mGeneration := AGeneration;
  mKeep := Self;
  mOwner := Self;
  mJob.Folder := FCacheFolder;
  // Gewähltes Board behalten (das erste des Projekts, solange keins bekannt ist).
  if FState.HasSnapshot then
  begin
    mJob.BoardId := FState.Snapshot.Board.Id;
  end;
  // issues.sprint.compare aus: kein früherer Sprint wird gefragt.
  mJob.Compare := TAtlasIdeSettings.Current.IssuesSprintCompare;
  mJob.Outcome := TAtlasSprintResult.Failed(FState.Calendar, TAtlasCiFetchError.Network);
  if not FWorker.Run(
    procedure
    begin
      mJob.Execute;
    end,
    procedure
    begin
      if mKeep <> nil then
      begin
        mOwner.Loaded(mGeneration, mJob.Target, mJob.Outcome);
      end;
    end) then
  begin
    Loaded(mGeneration, mJob.Target, TAtlasSprintResult.Failed(FState.Calendar, TAtlasCiFetchError.Cancelled));
  end;
end;

procedure TAtlasIdeSprint.Loaded(AGeneration: Integer; const ATarget: TAtlasTrackerTarget;
  const AResult: TAtlasSprintResult);
var
  mFile: string;
begin
  if AGeneration <> FGeneration then
  begin
    Exit;
  end;
  FCancel := nil;
  FLoading := False;
  if not FStarted then
  begin
    Exit;
  end;
  // Anonym: Anbieter und Ergebnis; nie Adresse, Board, Sprint oder Kennungen.
  TAtlasGuard.Log(Format(cLogOutcome, [ATarget.Provider, TAtlasCiBuild.ErrorKey(AResult.Error)],
    TFormatSettings.Invariant));
  if not AResult.Succeeded then
  begin
    // Letzter Stand bleibt mit „Stand vom … · Grund“; ohne Stand der Grund allein.
    FState.Stale := True;
    FState.Error := AResult.Error;
    Changed;
    Exit;
  end;
  FState.Snapshot := AResult.Snapshot;
  FState.Snapshot.Fetched := NowUtc;
  FState.HasSnapshot := True;
  FState.Stale := False;
  FState.Error := TAtlasCiFetchError.None;
  FState.Previous := AResult.Previous;
  FState.WithPrevious := AResult.WithPrevious;
  TAtlasTrackerBoard.Save(FCacheFolder, ATarget, cCacheName, FState.Snapshot);
  if AResult.CalendarKnown then
  begin
    FState.Calendar := AResult.Calendar;
    mFile := TAtlasTrackerBoard.CacheFile(FCacheFolder, ATarget, cWorkDaysName);
    if mFile <> '' then
    begin
      TAtlasTrackerBoard.WriteText(mFile, FState.Calendar.Text);
    end;
  end;
  Changed;
end;

/// <summary>Status ohne Stand: lädt noch, kein Board oder fehlgeschlagen.</summary>
function MissingStatus(const AState: TAtlasSprintState; ALoading: Boolean): TAtlasSprintTileStatus;
begin
  if ALoading or not AState.Stale then
  begin
    Result := TAtlasSprintTileStatus.Loading;
  end
  else if AState.Error = TAtlasCiFetchError.NotFound then
  begin
    Result := TAtlasSprintTileStatus.NoBoard;
  end
  else
  begin
    Result := TAtlasSprintTileStatus.Failed;
  end;
end;

function TAtlasIdeSprint.View: TAtlasSprintTile;
var
  mTarget: TAtlasTrackerTarget;
  mSettings: TAtlasPluginSettings;
  mPrevious: TArray<TAtlasSprintSummary>;
begin
  Result := Default(TAtlasSprintTile);
  if not FStarted or not Active then
  begin
    Exit;
  end;
  mSettings := TAtlasIdeSettings.Current;
  Result.Burndown := mSettings.IssuesSprintBurndown;
  Result.Compare := mSettings.IssuesSprintCompare;
  Result.CanAssign := Assigned(FHooks.CanAssign) and FHooks.CanAssign();
  if not CurrentTarget(mTarget) then
  begin
    Result.Status := TAtlasSprintTileStatus.NoProject;
    Exit;
  end;
  if (mTarget.Server = '') or not Assigned(FHooks.Provider) or
    (TAtlasIdeBoard.BoardsOf(FHooks.Provider(mTarget.Provider)) = nil) then
  begin
    Result.Status := TAtlasSprintTileStatus.NoTracker;
    Exit;
  end;
  Prepare(mTarget);
  Result.Loading := FLoading;
  Result.Stale := FState.Stale;
  Result.Error := FState.Error;
  if not FState.HasSnapshot then
  begin
    Result.Status := MissingStatus(FState, FLoading);
    Exit;
  end;
  // Ohne Vergleich keine Vorsprints (Linie, Abweichung, Velocity).
  mPrevious := nil;
  if Result.Compare then
  begin
    mPrevious := FState.Previous;
  end;
  Result.Sprint := TAtlasTrackerSprint.View(FState.Snapshot, FState.Calendar, NowUtc, mPrevious);
  if Result.Sprint.Known then
  begin
    Result.Status := TAtlasSprintTileStatus.Ready;
  end
  else
  begin
    Result.Status := TAtlasSprintTileStatus.NoSprint;
  end;
end;

procedure TAtlasIdeSprint.OpenBoard;
begin
  if FStarted and Assigned(FHooks.OpenBoard) then
  begin
    FHooks.OpenBoard();
  end;
end;

procedure TAtlasIdeSprint.BrowseBoard;
begin
  if FStarted and FState.HasSnapshot and (FState.Snapshot.Page <> '') then
  begin
    TAtlasTrackerFiles.Shell.Open(FState.Snapshot.Page);
  end;
end;

procedure TAtlasIdeSprint.FilterIssues(ADone: Boolean);
var
  mTile: TAtlasSprintTile;
begin
  if not FStarted or not Assigned(FHooks.Filter) then
  begin
    Exit;
  end;
  mTile := View;
  if mTile.Status <> TAtlasSprintTileStatus.Ready then
  begin
    Exit;
  end;
  if ADone then
  begin
    FHooks.Filter(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.WelcomeIssuesFilterDone, [mTile.Sprint.Name]), mTile.Sprint.MineDone);
  end
  else
  begin
    FHooks.Filter(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.WelcomeIssuesFilterOpen, [mTile.Sprint.Name]), mTile.Sprint.MineOpen);
  end;
end;

procedure TAtlasIdeSprint.AssignProject;
begin
  if FStarted and Assigned(FHooks.Assign) then
  begin
    FHooks.Assign();
  end;
end;

end.
