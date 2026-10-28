unit Atlas.IDE.Welcome.Sprint;

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
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Board,
  Atlas.Core.Tracker.Sprint,
  Atlas.Core.Vcs.Worker,
  Atlas.Core.Welcome.Sections,
  Atlas.UI.Welcome.Sprint;

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
  end;

  TAtlasIdeSprint = class(TInterfacedObject, IAtlasSprintSource)
  public const
    /// <summary>Reihenfolge außerhalb des Atlas-Layouts: direkt nach „Meine Issues“.</summary>
    Order = 27;
    /// <summary>Name des Zwischenspeichers für den aktuellen Sprint bzw. die Arbeitstage.</summary>
    CacheName = 'sprint';
    WorkDaysName = 'workdays';
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
    FHasSnapshot: Boolean;
    FSnapshot: TAtlasBoardSnapshot;
    FCalendar: TAtlasSprintCalendar;
    FPrevious: TArray<TAtlasSprintSummary>;
    // Die Vorsprints wurden mit dem Vergleich geladen (issues.sprint.compare eingeschaltet: neu laden).
    FWithPrevious: Boolean;
    FStale: Boolean;
    FError: TAtlasCiFetchError;
    FLoadedTick: UInt64;
    procedure Changed;
    procedure RegisterSection;
    function CurrentTarget(out ATarget: TAtlasTrackerTarget): Boolean;
    procedure Prepare(const ATarget: TAtlasTrackerTarget);
    procedure Load(AForce: Boolean);
    procedure Loaded(AGeneration: Integer; const ATarget: TAtlasTrackerTarget; ASucceeded: Boolean;
      const ASnapshot: TAtlasBoardSnapshot; const ACalendar: TAtlasSprintCalendar; ACalendarKnown: Boolean;
      const APrevious: TArray<TAtlasSprintSummary>; AWithPrevious: Boolean; AError: TAtlasCiFetchError);
    procedure CancelLoad;
    function Due(const ATarget: TAtlasTrackerTarget): Boolean;
    class function NowUtc: TDateTime; static;
  public
    /// <summary>ACacheFolder: Ordner des Zwischenspeichers ('' = keiner).</summary>
    constructor Create(const AHooks: TAtlasSprintHooks; const ACacheFolder: string);
    destructor Destroy; override;
    /// <summary>Bereich und Fabrik anmelden.</summary>
    procedure Start;
    /// <summary>Abbrechen, Bereich abmelden, Hooks lösen; danach wirkungslos.</summary>
    procedure Stop;
    /// <summary>Nach geänderten Einstellungen oder anderem Projekt: Sichtbarkeit, Titel und Inhalt neu.</summary>
    procedure Refresh;
    /// <summary>Nach einer Abfrage von „Meine Issues“ (#765): laden, wenn fällig; AForce bei „Jetzt abfragen“.
    /// </summary>
    procedure IssuesFetched(AForce: Boolean);
    function Section: TAtlasWelcomeSection;
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
  Winapi.ShellAPI,
  System.DateUtils,
  System.Diagnostics,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Welcome.Issues,
  Atlas.UI.Strings,
  Atlas.UI.Welcome.Frame,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Tracker.Board;

{ TAtlasIdeSprint }

constructor TAtlasIdeSprint.Create(const AHooks: TAtlasSprintHooks; const ACacheFolder: string);
begin
  inherited Create;
  FHooks := AHooks;
  FCacheFolder := ACacheFolder;
  FWorker := TAtlasVcsWorker.Create;
  FCalendar := TAtlasSprintCalendar.WorkWeek;
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
var
  mKeep: IAtlasSprintSource;
begin
  if FStarted then
    Exit;
  FStarted := True;
  mKeep := Self;
  TAtlasWelcomeViews.Register(TAtlasWelcomeIds.Sprint,
    function(AOwner: TComponent): TAtlasWelcomeSectionFrame
    var
      mFrame: TAtlasWelcomeSprintFrame;
    begin
      mFrame := TAtlasWelcomeSprintFrame.Create(AOwner);
      mFrame.Source := mKeep;
      Result := mFrame;
    end);
  FTitle := '';
  RegisterSection;
end;

procedure TAtlasIdeSprint.Stop;
begin
  if not FStarted then
    Exit;
  FStarted := False;
  Inc(FGeneration);
  CancelLoad;
  FWorker.Stop(1000);
  TAtlasWelcomeViews.Unregister(TAtlasWelcomeIds.Sprint);
  TAtlasWelcomeSections.Default.Remove(TAtlasWelcomeIds.Sprint);
  // Die Hooks halten den Bereich „Meine Issues“: Stop löst den Ring.
  FHooks := Default(TAtlasSprintHooks);
end;

procedure TAtlasIdeSprint.CancelLoad;
begin
  if FCancel <> nil then
    FCancel.Cancel;
  FCancel := nil;
end;

function TAtlasIdeSprint.Section: TAtlasWelcomeSection;
begin
  Result := TAtlasWelcomeSection.Create(TAtlasWelcomeIds.Sprint, TAtlasWelcomeSprintFrame.TitleText, Order,
    TAtlasWelcomeColumn.Right,
    function: Boolean
    begin
      Result := Active;
    end);
end;

procedure TAtlasIdeSprint.RegisterSection;
var
  mNext: TAtlasWelcomeSection;
begin
  if not FStarted then
    Exit;
  mNext := Section;
  // Nur beim ersten Mal bzw. nach einem Sprachwechsel: Add meldet allen Beobachtern.
  if mNext.Title <> FTitle then
  begin
    FTitle := mNext.Title;
    FActive := Active;
    TAtlasWelcomeSections.Default.Add(mNext);
  end;
end;

procedure TAtlasIdeSprint.Refresh;
var
  mTitle: string;
begin
  if not FStarted then
    Exit;
  mTitle := FTitle;
  RegisterSection;
  if mTitle <> FTitle then
    Exit;
  // welcomePage.sprint umgeschaltet: Auswahl der Bereiche neu; sonst nur der Inhalt.
  if FActive <> Active then
  begin
    FActive := Active;
    TAtlasWelcomeSections.Default.Changed;
  end;
  // Anderes Projekt bzw. andere Zuordnung: Stand aus dem Zwischenspeicher des neuen Trackers.
  FPrepared := False;
  Changed;
end;

procedure TAtlasIdeSprint.Changed;
begin
  if FStarted then
    TAtlasWelcomeSections.Default.Changed(TAtlasWelcomeIds.Sprint);
end;

function TAtlasIdeSprint.CurrentTarget(out ATarget: TAtlasTrackerTarget): Boolean;
var
  mProject: string;
begin
  ATarget := TAtlasTrackerTarget.Create('', '', '', '');
  mProject := '';
  if Assigned(FHooks.Project) then
    mProject := FHooks.Project();
  Result := mProject <> '';
  if Result and Assigned(FHooks.Target) then
    ATarget := FHooks.Target(mProject);
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
    TAtlasTrackerBoard.WriteText(mFile, TAtlasTrackerSprint.SummaryToJson(ASummary));
end;

procedure TAtlasIdeSprint.Prepare(const ATarget: TAtlasTrackerTarget);
var
  mSprint: TAtlasBoardSprint;
  mSummary: TAtlasSprintSummary;
  mFile, mText: string;
begin
  if FPrepared and SameText(FTargetKey, ATarget.Key) then
    Exit;
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
  FStale := False;
  FError := TAtlasCiFetchError.None;
  FPrevious := nil;
  FWithPrevious := False;
  FCalendar := TAtlasSprintCalendar.WorkWeek;
  FHasSnapshot := TAtlasTrackerBoard.Load(FCacheFolder, ATarget, CacheName, FSnapshot);
  if not FHasSnapshot then
    FSnapshot := TAtlasBoardSnapshot.Empty;
  mFile := TAtlasTrackerBoard.CacheFile(FCacheFolder, ATarget, WorkDaysName);
  if (mFile <> '') and TAtlasTrackerBoard.ReadText(mFile, mText) then
    FCalendar := TAtlasSprintCalendar.FromText(mText);
  if not FHasSnapshot then
    Exit;
  // Vorsprints nur aus dem Zwischenspeicher; fehlt einer, holt ihn die nächste Abfrage.
  for mSprint in TAtlasTrackerSprint.PreviousSprints(FSnapshot.Sprints, FSnapshot.Sprint,
    TAtlasTrackerSprint.VelocitySprints) do
    if CachedSummary(FCacheFolder, ATarget, FSnapshot.Board.Id, mSprint.Id, mSummary) then
      FPrevious := FPrevious + [mSummary];
end;

function TAtlasIdeSprint.Due(const ATarget: TAtlasTrackerTarget): Boolean;
begin
  Result := (FLoadedTick = 0) or (GetTickCount64 - FLoadedTick >= UInt64(TAtlasWelcomeIssues.DueMinutes) * 60000) or
    (TAtlasIdeSettings.Current.IssuesSprintCompare and not FWithPrevious);
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
  mTarget: TAtlasTrackerTarget;
  mProvider: IAtlasTrackerProvider;
  mBoards: IAtlasTrackerBoards;
  mWorkDays: IAtlasTrackerWorkDays;
  mTransport: IAtlasCiTransport;
  mGeneration: Integer;
  mKeep: IAtlasSprintSource;
  mOwner: TAtlasIdeSprint;
  mFolder, mBoardId: string;
  mCompare, mOk, mCalendarKnown: Boolean;
  mSnapshot: TAtlasBoardSnapshot;
  mCalendar: TAtlasSprintCalendar;
  mPrevious: TArray<TAtlasSprintSummary>;
  mError: TAtlasCiFetchError;
begin
  // welcomePage.sprint aus: keine Abfrage.
  if not FStarted or not Active or FLoading then
    Exit;
  if not CurrentTarget(mTarget) or (mTarget.Server = '') then
    Exit;
  Prepare(mTarget);
  if not AForce and not Due(mTarget) then
    Exit;
  mProvider := nil;
  if Assigned(FHooks.Provider) then
    mProvider := FHooks.Provider(mTarget.Provider);
  mBoards := TAtlasIdeBoard.BoardsOf(mTarget);
  if (mProvider = nil) or (mBoards = nil) then
    Exit;
  mTransport := nil;
  if Assigned(FHooks.Transport) then
    mTransport := FHooks.Transport(mProvider, mTarget);
  Inc(FGeneration);
  mGeneration := FGeneration;
  FLoadedTick := GetTickCount64;
  if mTransport = nil then
  begin
    Loaded(mGeneration, mTarget, False, TAtlasBoardSnapshot.Empty, FCalendar, False, nil, False,
      TAtlasCiFetchError.Unauthorized);
    Exit;
  end;
  if not Supports(mTransport, IAtlasCiCancel, FCancel) then
    FCancel := nil;
  if not Supports(mBoards, IAtlasTrackerWorkDays, mWorkDays) then
    mWorkDays := nil;
  FLoading := True;
  mKeep := Self;
  mOwner := Self;
  mFolder := FCacheFolder;
  // Gewähltes Board behalten (das erste des Projekts, solange keins bekannt ist).
  mBoardId := '';
  if FHasSnapshot then
    mBoardId := FSnapshot.Board.Id;
  // issues.sprint.compare aus: kein früherer Sprint wird gefragt.
  mCompare := TAtlasIdeSettings.Current.IssuesSprintCompare;
  mSnapshot := TAtlasBoardSnapshot.Empty;
  mCalendar := FCalendar;
  mCalendarKnown := False;
  mPrevious := nil;
  mOk := False;
  mError := TAtlasCiFetchError.Network;
  if not FWorker.Run(
    procedure
    var
      mWatch: TStopwatch;
      mDays: TArray<Integer>;
      mSprint: TAtlasBoardSprint;
      mSummary: TAtlasSprintSummary;
      mOld: TAtlasBoardSnapshot;
      mOldError: TAtlasCiFetchError;
      mLeft: Int64;
    begin
      mWatch := TStopwatch.StartNew;
      try
        mOk := mBoards.LoadBoard(mTarget, mTransport, mBoardId, '', TAtlasTrackerBoard.TimeoutMs, mSnapshot, mError);
        // Board weg (gelöscht, kein Zugriff mehr): das erste des Projekts.
        if not mOk and (mBoardId <> '') and (mError = TAtlasCiFetchError.NotFound) then
          mOk := mBoards.LoadBoard(mTarget, mTransport, '', '', TAtlasTrackerBoard.TimeoutMs, mSnapshot, mError);
        if mOk and (mWorkDays <> nil) and
          mWorkDays.WorkDays(mTarget, mTransport, TAtlasTrackerBoard.TimeoutMs, mDays) then
        begin
          mCalendar := TAtlasSprintCalendar.Create(mDays);
          mCalendarKnown := True;
        end;
        if mOk and mCompare then
          for mSprint in TAtlasTrackerSprint.PreviousSprints(mSnapshot.Sprints, mSnapshot.Sprint,
            TAtlasTrackerSprint.VelocitySprints) do
          begin
            // Abgeschlossene Sprints ändern sich nicht: einmal fragen, dann aus dem Zwischenspeicher.
            if CachedSummary(mFolder, mTarget, mSnapshot.Board.Id, mSprint.Id, mSummary) then
            begin
              mPrevious := mPrevious + [mSummary];
              Continue;
            end;
            mLeft := TAtlasTrackerSprint.TimeoutMs - mWatch.ElapsedMilliseconds;
            if mLeft < 1000 then
              Break;
            if not mBoards.LoadBoard(mTarget, mTransport, mSnapshot.Board.Id, mSprint.Id, Integer(mLeft), mOld,
              mOldError) then
              Continue;
            mSummary := TAtlasTrackerSprint.Summarize(mOld, mCalendar, NowUtc);
            SaveSummary(mFolder, mTarget, mSnapshot.Board.Id, mSummary);
            mPrevious := mPrevious + [mSummary];
          end;
      except
        // Kein Dialog, kein Fehler an die IDE: als Netzfehler werten.
        on E: Exception do
        begin
          mOk := False;
          mError := TAtlasCiFetchError.Network;
          TAtlasGuard.Log('Sprint: Abfrage mit ' + E.ClassName + ' abgebrochen');
        end;
      end;
      mTransport := nil;
    end,
    procedure
    begin
      if mKeep <> nil then
        mOwner.Loaded(mGeneration, mTarget, mOk, mSnapshot, mCalendar, mCalendarKnown, mPrevious, mCompare, mError);
    end) then
    Loaded(mGeneration, mTarget, False, TAtlasBoardSnapshot.Empty, FCalendar, False, nil, False,
      TAtlasCiFetchError.Cancelled);
  Changed;
end;

procedure TAtlasIdeSprint.Loaded(AGeneration: Integer; const ATarget: TAtlasTrackerTarget; ASucceeded: Boolean;
  const ASnapshot: TAtlasBoardSnapshot; const ACalendar: TAtlasSprintCalendar; ACalendarKnown: Boolean;
  const APrevious: TArray<TAtlasSprintSummary>; AWithPrevious: Boolean; AError: TAtlasCiFetchError);
var
  mFile: string;
begin
  if AGeneration <> FGeneration then
    Exit;
  FCancel := nil;
  FLoading := False;
  if not FStarted then
    Exit;
  // Anonym: Anbieter und Ergebnis; nie Adresse, Board, Sprint oder Kennungen.
  TAtlasGuard.Log('Sprint: ' + ATarget.Provider + ', ' + TAtlasCiBuild.ErrorKey(AError));
  if ASucceeded then
  begin
    FSnapshot := ASnapshot;
    FSnapshot.Fetched := NowUtc;
    FHasSnapshot := True;
    FStale := False;
    FError := TAtlasCiFetchError.None;
    FPrevious := APrevious;
    FWithPrevious := AWithPrevious;
    TAtlasTrackerBoard.Save(FCacheFolder, ATarget, CacheName, FSnapshot);
    if ACalendarKnown then
    begin
      FCalendar := ACalendar;
      mFile := TAtlasTrackerBoard.CacheFile(FCacheFolder, ATarget, WorkDaysName);
      if mFile <> '' then
        TAtlasTrackerBoard.WriteText(mFile, FCalendar.Text);
    end;
  end
  else
  begin
    // Letzter Stand bleibt mit „Stand vom … · Grund“; ohne Stand der Grund allein.
    FStale := True;
    FError := AError;
  end;
  Changed;
end;

function TAtlasIdeSprint.View: TAtlasSprintTile;
var
  mTarget: TAtlasTrackerTarget;
  mSettings: TAtlasPluginSettings;
  mPrevious: TArray<TAtlasSprintSummary>;
begin
  Result := Default(TAtlasSprintTile);
  if not FStarted or not Active then
    Exit;
  mSettings := TAtlasIdeSettings.Current;
  Result.Burndown := mSettings.IssuesSprintBurndown;
  Result.Compare := mSettings.IssuesSprintCompare;
  Result.CanAssign := Assigned(FHooks.CanAssign) and FHooks.CanAssign();
  if not CurrentTarget(mTarget) then
  begin
    Result.Status := TAtlasSprintTileStatus.NoProject;
    Exit;
  end;
  if (mTarget.Server = '') or not Assigned(FHooks.Provider) or (FHooks.Provider(mTarget.Provider) = nil) or
    (TAtlasIdeBoard.BoardsOf(mTarget) = nil) then
  begin
    Result.Status := TAtlasSprintTileStatus.NoTracker;
    Exit;
  end;
  Prepare(mTarget);
  Result.Loading := FLoading;
  Result.Stale := FStale;
  Result.Error := FError;
  if not FHasSnapshot then
  begin
    if FLoading or not FStale then
      Result.Status := TAtlasSprintTileStatus.Loading
    else if FError = TAtlasCiFetchError.NotFound then
      Result.Status := TAtlasSprintTileStatus.NoBoard
    else
      Result.Status := TAtlasSprintTileStatus.Failed;
    Exit;
  end;
  // Ohne Vergleich keine Vorsprints (Linie, Abweichung, Velocity).
  mPrevious := nil;
  if Result.Compare then
    mPrevious := FPrevious;
  Result.Sprint := TAtlasTrackerSprint.View(FSnapshot, FCalendar, NowUtc, mPrevious);
  if Result.Sprint.Known then
    Result.Status := TAtlasSprintTileStatus.Ready
  else
    Result.Status := TAtlasSprintTileStatus.NoSprint;
end;

procedure TAtlasIdeSprint.OpenBoard;
begin
  if FStarted and Assigned(FHooks.OpenBoard) then
    FHooks.OpenBoard();
end;

procedure TAtlasIdeSprint.BrowseBoard;
begin
  if FStarted and FHasSnapshot and (FSnapshot.Page <> '') then
    ShellExecute(0, 'open', PChar(FSnapshot.Page), nil, nil, SW_SHOWNORMAL);
end;

procedure TAtlasIdeSprint.FilterIssues(ADone: Boolean);
var
  mTile: TAtlasSprintTile;
begin
  if not FStarted or not Assigned(FHooks.Filter) then
    Exit;
  mTile := View;
  if mTile.Status <> TAtlasSprintTileStatus.Ready then
    Exit;
  if ADone then
    FHooks.Filter(TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesFilterDone, [mTile.Sprint.Name]), mTile.Sprint.MineDone)
  else
    FHooks.Filter(TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesFilterOpen, [mTile.Sprint.Name]), mTile.Sprint.MineOpen);
end;

procedure TAtlasIdeSprint.AssignProject;
begin
  if FStarted and Assigned(FHooks.Assign) then
    FHooks.Assign();
end;

end.
