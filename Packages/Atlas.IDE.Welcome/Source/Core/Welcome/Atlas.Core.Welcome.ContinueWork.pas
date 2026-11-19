unit Atlas.Core.Welcome.ContinueWork;

// Ablauf von „Weiterarbeiten“ (#755) ohne IDE: Änderungsstellen dieser
// Sitzung mitschreiben, beim Schließen eines Projekts (und beim Beenden der
// IDE) den Arbeitsstand in die Projekt-Zusammenfassung schreiben, HEAD und
// eingehende Commits im Hintergrund abfragen (#1286) und einen Arbeitsstand
// fortsetzen. Alles, was die IDE betrifft, läuft über IAtlasContinueHost;
// die IDE-Seite (Atlas.IDE.Welcome.Adapters.Continue) meldet nur die
// Ereignisse des Editors und zeigt den Bereich.
// - Gruppe und Projekte melden ihr Schließen einzeln: Die Reiter werden beim
//   ersten Schließen einer Datei festgehalten und einmal je Schließen
//   geschrieben (TAtlasContinueSession).
// - Nach dem Schreiben trägt die HEAD-Abfrage ihren Stand nur nach, wenn in
//   der Zusammenfassung noch derselbe Stand steht.
// - Nach Stop kommt keine Antwort mehr an (Regel 3); ein Objekt hält sich
//   selbst über seine Schnittstelle, solange eine Abfrage läuft.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Welcome.Contract,
  Atlas.Core.Welcome.Continue,
  Atlas.Core.Welcome.ContinueQueries;

type
  TAtlasContinueWork = class(TInterfacedObject)
  private type
    /// <summary>Festgehaltene Reiter beim ersten Schließen einer Datei.</summary>
    TBatch = record
      Snapshot: TAtlasContinueSnapshot;
      /// <summary>Letztes Schließen einer Datei und letzter geschriebener Stand.</summary>
      Ticks: TAtlasContinueTicks;
    end;
  private
    FHost: IAtlasContinueHost;
    FStopped: Boolean;
    // Großgeschriebener Pfad → letzte Änderungsstelle dieser Sitzung.
    FChanges: TDictionary<string, TAtlasWorkTab>;
    FBatch: TBatch;
    // Normiertes Ziel → HEAD-Stand und Abfragen; eingehende Commits zum obersten Eintrag.
    FHeads: TAtlasContinueHeads;
    FIncoming: TAtlasContinueIncomingQueries;
    FNotice: string;
    FOnWritten: TProc<string, TAtlasContinueSnapshot>;
    function Top: TAtlasContinueEntry;
    function IncomingDue(AForce: Boolean; out AEntry: TAtlasContinueEntry): Boolean;
    function ResumeState(const AProject: string; out AState: TAtlasWorkState): Boolean;
    procedure StoreHead(const ATarget: string; AStamp: TDateTime; const AHead: TAtlasWorkState);
    procedure WriteState(const ATarget: string; const ASnapshot: TAtlasContinueSnapshot; AProbe: Boolean);
    procedure QueryHead(const ATarget: string; AStamp: TDateTime);
    procedure HeadArrived(const AKey, ATarget: string; AStarted: UInt64; AStamp: TDateTime; AOk: Boolean;
      const AHead: TAtlasWorkState);
    procedure Changed;
  public
    constructor Create(const AHost: IAtlasContinueHost);
    destructor Destroy; override;
    /// <summary>welcomePage.continue an und nicht angehalten.</summary>
    function Enabled: Boolean;
    /// <summary>Mitschreiben: Enabled und die Willkommensseite ist an.</summary>
    function Recording: Boolean;
    /// <summary>Datei AFileName an Zeile und Spalte geändert (bei jedem Tastendruck).</summary>
    procedure Modified(const AFileName: string; ALine, ACol: Integer);
    /// <summary>Editor aktiviert: HEAD aktuell halten (höchstens einmal je Minute).</summary>
    procedure Activated;
    /// <summary>Eine Quelltextdatei wird geschlossen.</summary>
    procedure SourceClosing;
    procedure ProjectOpened(const AFileName: string);
    procedure ProjectClosing(const AFileName: string);
    /// <summary>Plugin nach dem Öffnen eines Projekts geladen: HEAD trotzdem kennen.</summary>
    procedure Started;
    /// <summary>Stand des offenen Projekts schreiben (Beenden der IDE), danach wirkungslos.</summary>
    procedure Stop;
    function Entries: TAtlasContinueEntries;
    function Incoming: TAtlasContinueIncoming;
    function IncomingQuerying: Boolean;
    function Notice: string;
    /// <summary>Arbeitsstand von AProject fortsetzen: Projekt, Reiter in ihrer Reihenfolge, der aktive zuletzt.
    /// </summary>
    procedure Resume(const AProject: string);
    /// <summary>Obersten Arbeitsstand fortsetzen (Palettenbefehl Atlas.Continue).</summary>
    procedure ResumeLatest;
    /// <summary>Eingehende Commits abfragen, wenn fällig (AForce: auch bei frischem Ergebnis).</summary>
    procedure RefreshIncoming(AForce: Boolean);
    property Stopped: Boolean read FStopped;
    /// <summary>Änderungsstellen dieser Sitzung (für den Reiter „Issues“, #2052).</summary>
    property Changes: TDictionary<string, TAtlasWorkTab> read FChanges;
    /// <summary>Nach dem Schreiben eines Stands: Ziel und Reiter (Reiter „Issues“, #2052).</summary>
    property OnWritten: TProc<string, TAtlasContinueSnapshot> read FOnWritten write FOnWritten;
  end;

implementation

uses
  Atlas.Core.Projects.Contract.Summary,
  Atlas.Core.Projects.Summary.Json;

const
  cOneSecond = 1 / SecsPerDay;

function Key(const APath: string): string;
begin
  Result := SummaryNormalizedPath(APath);
end;

/// <summary>HEAD aus AHead in AState übernehmen.</summary>
procedure TakeHead(var AState: TAtlasWorkState; const AHead: TAtlasWorkState);
begin
  AState.VcsKind := AHead.VcsKind;
  AState.Head := AHead.Head;
  AState.Upstream := AHead.Upstream;
  AState.UpstreamRevision := AHead.UpstreamRevision;
end;

{ TAtlasContinueWork }

constructor TAtlasContinueWork.Create(const AHost: IAtlasContinueHost);
begin
  inherited Create;
  FHost := AHost;
  FChanges := TDictionary<string, TAtlasWorkTab>.Create;
  FHeads := TAtlasContinueHeads.Create;
  FIncoming := TAtlasContinueIncomingQueries.Create;
end;

destructor TAtlasContinueWork.Destroy;
begin
  FStopped := True;
  FIncoming.Free;
  FHeads.Free;
  FChanges.Free;
  FOnWritten := nil;
  FHost := nil;
  inherited Destroy;
end;

procedure TAtlasContinueWork.Changed;
begin
  if not FStopped then
  begin
    FHost.Changed;
  end;
end;

function TAtlasContinueWork.Enabled: Boolean;
begin
  Result := not FStopped and FHost.Settings.Continue;
end;

function TAtlasContinueWork.Recording: Boolean;
begin
  // Ohne Willkommensseite gibt es den Bereich nicht: dann auch nichts mitschreiben.
  Result := Enabled and FHost.Settings.WelcomePage;
end;

function TAtlasContinueWork.Top: TAtlasContinueEntry;
var
  mList: TAtlasContinueEntries;
begin
  Result := Default(TAtlasContinueEntry);
  mList := Entries;
  if Length(mList) > 0 then
  begin
    Result := mList[0];
  end;
end;

procedure TAtlasContinueWork.Modified(const AFileName: string; ALine, ACol: Integer);
var
  mTab: TAtlasWorkTab;
begin
  if (AFileName = '') or not Recording then
  begin
    Exit;
  end;
  // Nur die Stelle merken: Methode erst beim Festhalten der Reiter.
  mTab := TAtlasWorkTab.Create(AFileName, ALine, ACol);
  mTab.Changed := True;
  mTab.ChangedAt := FHost.NowUtc;
  FChanges.AddOrSetValue(AnsiUpperCase(mTab.FileName), mTab);
end;

procedure TAtlasContinueWork.Activated;
var
  mTarget: string;
begin
  if not Recording or not FHost.Settings.Incoming then
  begin
    Exit;
  end;
  mTarget := FHost.CurrentTarget;
  if (mTarget = '') or FHeads.Recent(Key(mTarget), FHost.Ticks, TAtlasWelcomeContinue.cRefreshMs) then
  begin
    Exit;
  end;
  QueryHead(mTarget, 0);
end;

procedure TAtlasContinueWork.SourceClosing;
begin
  if not Recording then
  begin
    Exit;
  end;
  // Erste Datei einer Folge: Reiter festhalten, solange sie noch alle offen sind.
  if TAtlasContinueSession.HoldTabs(FBatch.Ticks, FHost.Ticks) then
  begin
    FBatch.Snapshot := FHost.TakeSnapshot(FChanges);
  end;
  FBatch.Ticks.Held := FHost.Ticks;
end;

procedure TAtlasContinueWork.ProjectOpened(const AFileName: string);
var
  mTarget: string;
begin
  if not Recording then
  begin
    Exit;
  end;
  mTarget := FHost.TargetOf(AFileName);
  if mTarget <> '' then
  begin
    QueryHead(mTarget, 0);
  end;
end;

procedure TAtlasContinueWork.ProjectClosing(const AFileName: string);
var
  mTarget: string;
  mSnapshot: TAtlasContinueSnapshot;
  mStep: TAtlasContinueCloseStep;
begin
  if not Recording then
  begin
    Exit;
  end;
  // Gruppe und ihre Projekte melden sich einzeln: einmal je Schließen schreiben.
  mStep := TAtlasContinueSession.CloseStep(FBatch.Ticks, FHost.Ticks);
  mTarget := FHost.TargetOf(AFileName);
  if (mStep = TAtlasContinueCloseStep.Skip) or (mTarget = '') then
  begin
    Exit;
  end;
  if mStep = TAtlasContinueCloseStep.UseHeld then
  begin
    mSnapshot := FBatch.Snapshot;
  end
  else
  begin
    mSnapshot := FHost.TakeSnapshot(FChanges);
  end;
  WriteState(mTarget, mSnapshot, True);
end;

procedure TAtlasContinueWork.Started;
begin
  if Recording then
  begin
    QueryHead(FHost.CurrentTarget, 0);
  end;
end;

procedure TAtlasContinueWork.Stop;
var
  mTarget: string;
begin
  if FStopped then
  begin
    Exit;
  end;
  // Beenden der IDE: Ist das Projekt noch offen (kein Schließen gemeldet), jetzt schreiben, ohne Abfrage.
  try
    if Recording and TAtlasContinueSession.WriteOnStop(FBatch.Ticks, FHost.Ticks) then
    begin
      mTarget := FHost.CurrentTarget;
      if mTarget <> '' then
      begin
        WriteState(mTarget, FHost.TakeSnapshot(FChanges), False);
      end;
    end;
  finally
    FStopped := True;
  end;
end;

procedure TAtlasContinueWork.StoreHead(const ATarget: string; AStamp: TDateTime; const AHead: TAtlasWorkState);
var
  mStamp: TDateTime;
  mHead: TAtlasWorkState;
begin
  mStamp := AStamp;
  mHead := AHead;
  FHost.UpdateSummary(ATarget,
    procedure(var ASummary: TAtlasProjectSummary)
    var
      mStored: TAtlasWorkState;
    begin
      if not TAtlasWelcomeContinue.Read(ASummary, mStored) or (Abs(mStored.At - mStamp) > cOneSecond) then
      begin
        Exit;
      end;
      TakeHead(mStored, mHead);
      TAtlasWelcomeContinue.Write(ASummary, mStored);
    end);
end;

procedure TAtlasContinueWork.WriteState(const ATarget: string; const ASnapshot: TAtlasContinueSnapshot;
  AProbe: Boolean);
var
  mOld, mState, mHead: TAtlasWorkState;
  mSummary: TAtlasProjectSummary;
  mStamp: TDateTime;
begin
  // Ohne offene Reiter bleibt der vorige Stand (z. B. alles schon geschlossen).
  if Length(ASnapshot.Tabs) = 0 then
  begin
    Exit;
  end;
  mStamp := FHost.NowUtc;
  mOld := TAtlasWorkState.Empty;
  if FHost.LoadSummary(ATarget, mSummary) then
  begin
    TAtlasWelcomeContinue.Read(mSummary, mOld);
  end;
  mState := TAtlasWelcomeContinue.Build(ASnapshot.Tabs, ASnapshot.Active, FChanges.Values.ToArray, mOld, mStamp);
  if FHeads.TryHead(Key(ATarget), mHead) then
  begin
    TakeHead(mState, mHead);
  end;
  FHost.UpdateSummary(ATarget,
    procedure(var ASummary: TAtlasProjectSummary)
    begin
      TAtlasWelcomeContinue.Write(ASummary, mState);
    end);
  // Derselbe Stand unter dem aktiven Issue (#2052), solange die Änderungen dieser Sitzung noch da sind.
  if Assigned(FOnWritten) then
  begin
    FOnWritten(ATarget, ASnapshot);
  end;
  FBatch.Ticks.Written := FHost.Ticks;
  FBatch.Ticks.Held := 0;
  FBatch.Snapshot := Default(TAtlasContinueSnapshot);
  // Neue Sitzung: Änderungen gehören zum geschriebenen Stand.
  FChanges.Clear;
  FIncoming.Outdate(ATarget);
  // HEAD frisch abfragen und nachtragen; beim Beenden der IDE weder Abfrage noch neues Zeichnen.
  if not AProbe then
  begin
    Exit;
  end;
  QueryHead(ATarget, mStamp);
  Changed;
end;

procedure TAtlasContinueWork.HeadArrived(const AKey, ATarget: string; AStarted: UInt64; AStamp: TDateTime;
  AOk: Boolean; const AHead: TAtlasWorkState);
begin
  if FStopped then
  begin
    Exit;
  end;
  FHeads.Arrived(AKey, AStarted, FHost.Ticks, AOk, AHead);
  if AOk and (AStamp > 0) then
  begin
    StoreHead(ATarget, AStamp, AHead);
    Changed;
  end;
end;

procedure TAtlasContinueWork.QueryHead(const ATarget: string; AStamp: TDateTime);
var
  mKeep: IInterface;
  mSelf: TAtlasContinueWork;
  mKey, mTarget: string;
  mStarted: UInt64;
begin
  if FStopped or (ATarget = '') then
  begin
    Exit;
  end;
  mKey := Key(ATarget);
  if FHeads.Querying(mKey, FHost.Ticks) then
  begin
    Exit;
  end;
  mTarget := ATarget;
  mStarted := FHost.Ticks;
  FHeads.Started(mKey, mStarted);
  mKeep := Self;
  mSelf := Self;
  if not FHost.QueryHead(ExtractFileDir(ATarget),
    procedure(AOk: Boolean; const AHead: TAtlasWorkState)
    begin
      if mKeep <> nil then
      begin
        mSelf.HeadArrived(mKey, mTarget, mStarted, AStamp, AOk, AHead);
      end;
    end) then
  begin
    FHeads.NotStarted(mKey, FHost.Ticks);
  end;
end;

function TAtlasContinueWork.IncomingDue(AForce: Boolean; out AEntry: TAtlasContinueEntry): Boolean;
begin
  AEntry := Default(TAtlasContinueEntry);
  Result := Enabled and FHost.Settings.Incoming and not FIncoming.Running(FHost.Ticks);
  if Result then
  begin
    AEntry := Top;
    Result := AEntry.Project <> '';
  end;
  if Result then
  begin
    Result := FIncoming.Due(AForce, AEntry.Project, FHost.Ticks);
  end;
end;

procedure TAtlasContinueWork.RefreshIncoming(AForce: Boolean);
var
  mKeep: IInterface;
  mSelf: TAtlasContinueWork;
  mEntry: TAtlasContinueEntry;
  mRequest: TAtlasContinueIncomingRequest;
  mStarted: UInt64;
  mProject: string;
begin
  if not IncomingDue(AForce, mEntry) then
  begin
    Exit;
  end;
  mRequest := Default(TAtlasContinueIncomingRequest);
  mRequest.Project := mEntry.Project;
  mRequest.State := mEntry.State;
  mRequest.MainBranch := FHost.MainBranchOf(mEntry.Project);
  mRequest.Fetch := FHost.Settings.Fetch;
  mRequest.Stamp := FHost.NowUtc;
  mProject := mEntry.Project;
  mStarted := FHost.Ticks;
  FIncoming.Started(mProject, mStarted);
  mKeep := Self;
  mSelf := Self;
  if not FHost.QueryIncoming(mRequest,
    procedure(AOk: Boolean; const AFound: TAtlasContinueIncoming)
    begin
      if (mKeep <> nil) and not mSelf.FStopped and
        mSelf.FIncoming.Arrived(mProject, mStarted, mSelf.FHost.Ticks, AOk, AFound) then
      begin
        mSelf.Changed;
      end;
    end) then
  begin
    FIncoming.NotStarted(FHost.Ticks);
  end;
end;

function TAtlasContinueWork.Entries: TAtlasContinueEntries;
var
  mHost: IAtlasContinueHost;
begin
  Result := nil;
  if not Enabled then
  begin
    Exit;
  end;
  mHost := FHost;
  Result := TAtlasWelcomeContinue.Entries(FHost.RecentProjects,
    function(const AProject: string; out ASummary: TAtlasProjectSummary): Boolean
    begin
      Result := mHost.LoadSummary(AProject, ASummary);
    end,
    FHost.Settings.Count);
end;

function TAtlasContinueWork.Incoming: TAtlasContinueIncoming;
begin
  Result := Default(TAtlasContinueIncoming);
  if not Enabled or not FHost.Settings.Incoming then
  begin
    Exit;
  end;
  Result := FIncoming.Current(Top.Project);
end;

function TAtlasContinueWork.IncomingQuerying: Boolean;
var
  mEntry: TAtlasContinueEntry;
begin
  Result := False;
  if not Enabled or not FHost.Settings.Incoming or not FIncoming.Running(FHost.Ticks) then
  begin
    Exit;
  end;
  mEntry := Top;
  Result := (mEntry.Project <> '') and FIncoming.Concerns(mEntry.Project);
end;

function TAtlasContinueWork.Notice: string;
begin
  Result := '';
  if Enabled then
  begin
    Result := FNotice;
  end;
end;

function TAtlasContinueWork.ResumeState(const AProject: string; out AState: TAtlasWorkState): Boolean;
var
  mSummary: TAtlasProjectSummary;
begin
  Result := False;
  AState := TAtlasWorkState.Empty;
  if not Enabled then
  begin
    FHost.Say(FHost.Text(TAtlasContinueText.Disabled, ''));
  end
  else if not FHost.LoadSummary(AProject, mSummary) or not TAtlasWelcomeContinue.Read(mSummary, AState) or
    (AState.TabCount = 0) then
  begin
    FHost.Say(FHost.Text(TAtlasContinueText.Nothing, ''));
  end
  else if not FHost.FileExists(AProject) then
  begin
    FHost.Say(FHost.Text(TAtlasContinueText.ProjectMissing, AProject));
  end
  else
  begin
    Result := True;
  end;
end;

procedure TAtlasContinueWork.Resume(const AProject: string);
var
  mState: TAtlasWorkState;
  mPlan: TAtlasContinuePlan;
  mTab: TAtlasWorkTab;
  mHost: IAtlasContinueHost;
begin
  if not ResumeState(AProject, mState) then
  begin
    Exit;
  end;
  mHost := FHost;
  mPlan := TAtlasWelcomeContinue.Plan(AProject, mState,
    function(const AFileName: string): Boolean
    begin
      Result := mHost.FileExists(AFileName);
    end);
  FNotice := '';
  if Length(mPlan.Missing) > 0 then
  begin
    FNotice := FHost.Text(TAtlasContinueText.FilesMissing, TAtlasContinueSession.MissingNames(mPlan.Missing));
    FHost.Say(FNotice);
  end;
  FHost.EnsureProject(AProject);
  // Reiter in ihrer Reihenfolge; danach den zuvor aktiven noch einmal, damit er vorn liegt.
  for mTab in mPlan.Open do
  begin
    FHost.OpenTab(mTab);
  end;
  if TAtlasContinueSession.ActiveInPlan(mPlan.Active, Length(mPlan.Open)) then
  begin
    FHost.OpenTab(mPlan.Open[mPlan.Active]);
  end;
  Changed;
end;

procedure TAtlasContinueWork.ResumeLatest;
var
  mEntry: TAtlasContinueEntry;
begin
  if not Enabled then
  begin
    FHost.Say(FHost.Text(TAtlasContinueText.Disabled, ''));
    Exit;
  end;
  mEntry := Top;
  if mEntry.Project = '' then
  begin
    FHost.Say(FHost.Text(TAtlasContinueText.Nothing, ''));
    Exit;
  end;
  Resume(mEntry.Project);
end;

end.
