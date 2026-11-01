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
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Board,
  Atlas.Core.Tracker.Sprint,
  Atlas.Core.Vcs.Worker,
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
    /// <summary>Titel oder Schalter der Kachel geändert: der Willkommensseite melden.</summary>
    procedure UpdateTileInfo;
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
  Winapi.ShellAPI,
  System.DateUtils,
  System.Diagnostics,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Tracker.MyIssues,
  Atlas.UI.Strings,
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
  FWorker.Stop(1000);
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
  FStale := False;
  FError := TAtlasCiFetchError.None;
  FPrevious := nil;
  FWithPrevious := False;
  FCalendar := TAtlasSprintCalendar.WorkWeek;
  FHasSnapshot := TAtlasTrackerBoard.Load(FCacheFolder, ATarget, cCacheName, FSnapshot);
  if not FHasSnapshot then
  begin
    FSnapshot := TAtlasBoardSnapshot.Empty;
  end;
  mFile := TAtlasTrackerBoard.CacheFile(FCacheFolder, ATarget, cWorkDaysName);
  if (mFile <> '') and TAtlasTrackerBoard.ReadText(mFile, mText) then
  begin
    FCalendar := TAtlasSprintCalendar.FromText(mText);
  end;
  if not FHasSnapshot then
  begin
    Exit;
  end;
  // Vorsprints nur aus dem Zwischenspeicher; fehlt einer, holt ihn die nächste Abfrage.
  for mSprint in TAtlasTrackerSprint.PreviousSprints(FSnapshot.Sprints, FSnapshot.Sprint,
    TAtlasTrackerSprint.VelocitySprints) do
  begin
    if CachedSummary(FCacheFolder, ATarget, FSnapshot.Board.Id, mSprint.Id, mSummary) then
    begin
      FPrevious := FPrevious + [mSummary];
    end;
  end;
end;

function TAtlasIdeSprint.Due(const ATarget: TAtlasTrackerTarget): Boolean;
begin
  Result := (FLoadedTick = 0) or (GetTickCount64 - FLoadedTick >= UInt64(TAtlasMyIssues.cDueMinutes) * 60000) or
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
  begin
    Exit;
  end;
  if not CurrentTarget(mTarget) or (mTarget.Server = '') then
  begin
    Exit;
  end;
  Prepare(mTarget);
  if not AForce and not Due(mTarget) then
  begin
    Exit;
  end;
  mProvider := nil;
  if Assigned(FHooks.Provider) then
  begin
    mProvider := FHooks.Provider(mTarget.Provider);
  end;
  mBoards := TAtlasIdeBoard.BoardsOf(mProvider);
  if (mProvider = nil) or (mBoards = nil) then
  begin
    Exit;
  end;
  mTransport := nil;
  if Assigned(FHooks.Transport) then
  begin
    mTransport := FHooks.Transport(mProvider, mTarget);
  end;
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
  begin
    FCancel := nil;
  end;
  if not Supports(mBoards, IAtlasTrackerWorkDays, mWorkDays) then
  begin
    mWorkDays := nil;
  end;
  FLoading := True;
  mKeep := Self;
  mOwner := Self;
  mFolder := FCacheFolder;
  // Gewähltes Board behalten (das erste des Projekts, solange keins bekannt ist).
  mBoardId := '';
  if FHasSnapshot then
  begin
    mBoardId := FSnapshot.Board.Id;
  end;
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
        begin
          mOk := mBoards.LoadBoard(mTarget, mTransport, '', '', TAtlasTrackerBoard.TimeoutMs, mSnapshot, mError);
        end;
        if mOk and (mWorkDays <> nil) and
          mWorkDays.WorkDays(mTarget, mTransport, TAtlasTrackerBoard.TimeoutMs, mDays) then
        begin
          mCalendar := TAtlasSprintCalendar.Create(mDays);
          mCalendarKnown := True;
        end;
        if mOk and mCompare then
        begin
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
            begin
              Break;
            end;
            if not mBoards.LoadBoard(mTarget, mTransport, mSnapshot.Board.Id, mSprint.Id, Integer(mLeft), mOld,
              mOldError) then
            begin
              Continue;
            end;
            mSummary := TAtlasTrackerSprint.Summarize(mOld, mCalendar, NowUtc);
            SaveSummary(mFolder, mTarget, mSnapshot.Board.Id, mSummary);
            mPrevious := mPrevious + [mSummary];
          end;
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
      begin
        mOwner.Loaded(mGeneration, mTarget, mOk, mSnapshot, mCalendar, mCalendarKnown, mPrevious, mCompare, mError);
      end;
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
    TAtlasTrackerBoard.Save(FCacheFolder, ATarget, cCacheName, FSnapshot);
    if ACalendarKnown then
    begin
      FCalendar := ACalendar;
      mFile := TAtlasTrackerBoard.CacheFile(FCacheFolder, ATarget, cWorkDaysName);
      if mFile <> '' then
      begin
        TAtlasTrackerBoard.WriteText(mFile, FCalendar.Text);
      end;
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
  Result.Stale := FStale;
  Result.Error := FError;
  if not FHasSnapshot then
  begin
    if FLoading or not FStale then
    begin
      Result.Status := TAtlasSprintTileStatus.Loading;
    end
    else if FError = TAtlasCiFetchError.NotFound then
    begin
      Result.Status := TAtlasSprintTileStatus.NoBoard;
    end
    else
    begin
      Result.Status := TAtlasSprintTileStatus.Failed;
    end;
    Exit;
  end;
  // Ohne Vergleich keine Vorsprints (Linie, Abweichung, Velocity).
  mPrevious := nil;
  if Result.Compare then
  begin
    mPrevious := FPrevious;
  end;
  Result.Sprint := TAtlasTrackerSprint.View(FSnapshot, FCalendar, NowUtc, mPrevious);
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
  if FStarted and FHasSnapshot and (FSnapshot.Page <> '') then
  begin
    ShellExecute(0, 'open', PChar(FSnapshot.Page), nil, nil, SW_SHOWNORMAL);
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
    FHooks.Filter(TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesFilterDone, [mTile.Sprint.Name]), mTile.Sprint.MineDone);
  end
  else
  begin
    FHooks.Filter(TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesFilterOpen, [mTile.Sprint.Name]), mTile.Sprint.MineOpen);
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
