unit Atlas.IDE.Welcome.ContinueIssues;

// Reiter „Issues“ von „Weiterarbeiten“ in der IDE (#2052): Arbeitsstand je
// Issue mitschreiben, auflisten und fortsetzen.
// - Speichern (nur mit welcomePage.continue.issues): beim Schließen eines
//   Projekts und beim Beenden der IDE derselbe Stand wie „Zuletzt“ zusätzlich
//   unter dem aktiven Issue; beim Wechsel des aktiven Issues („Beginnen“,
//   „Beenden“) meldet der Tracker das bisherige Issue (SaveIssue) und der
//   aktuelle Stand des offenen Projekts geht unter diese Kennung. Änderungen
//   vor dem Wechsel gehören zum vorigen Issue. Behobene Issues fallen dabei
//   heraus.
// - Aktives Issue und Zustand kommen vom Tracker über den Vertrag
//   Atlas.IDE.Contracts.IssueWork (TAtlasWelcomeNeighbors); ohne Tracker gibt
//   es weder Reiter noch Speichern.
// - Fortsetzen: Branch nur nach Rückfrage wechseln (Abfrage im Hintergrund);
//   fehlt der Branch, nur die Reiter mit Hinweis. Dann Projekt öffnen, Reiter
//   in ihrer Reihenfolge, Cursor an die letzte Änderung.
// - Nach „Beginnen“ bietet OfferRestore „Arbeitsstand wiederherstellen“ an.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Welcome.Continue,
  Atlas.Core.Welcome.ContinueIssues,
  Atlas.IDE.Contracts.IssueWork,
  Atlas.UI.Welcome.ContinueIssues,
  Atlas.IDE.Welcome.Continue.Editor;

type
  TAtlasIdeContinueIssues = class(TInterfacedObject, IAtlasContinueIssuesSource)
  private
    FMessage: TProc<string>;
    FChanged: TProc;
    // Änderungsstellen dieser Sitzung (gehört TAtlasIdeContinue).
    FChanges: TDictionary<string, TAtlasWorkTab>;
    FStopped: Boolean;
    FNotice: string;
    // Beginn des aktiven Issues (UTC); ältere Änderungen gehören zum vorigen.
    FSince: TDateTime;
    procedure Report(const AText: string);
    procedure Changed;
    function SinceChanges: TArray<TAtlasWorkTab>;
    function StatesOf(const AProject: string; const AKeys: TArray<string>): TArray<TAtlasIssueStateKind>;
    function FindEntry(const AProject, AKey: string; out ATarget: string; out AEntry: TAtlasIssueWorkEntry): Boolean;
    procedure Store(const ATarget: string; const AIssue: TAtlasIssueWorkIssue; const ASnapshot: TAtlasContinueSnapshot);
    procedure BranchChecked(const AProject: string; const AEntry: TAtlasIssueWorkEntry; AStep: TAtlasIssueBranchStep;
      const ACurrent: string);
    procedure SwitchThenOpen(const AProject: string; const AEntry: TAtlasIssueWorkEntry);
    procedure OpenPlan(const AProject: string; const AEntry: TAtlasIssueWorkEntry);
  public
    /// <summary>AMessage: Zeile in die Meldungsansicht; AChanges: Änderungsstellen von „Weiterarbeiten“
    /// (gehört dem Aufrufer); AChanged: Bereich neu zeichnen.</summary>
    constructor Create(const AMessage: TProc<string>; AChanges: TDictionary<string, TAtlasWorkTab>;
      const AChanged: TProc);
    /// <summary>Danach wirkungslos; laufende Abfragen tun nichts mehr.</summary>
    procedure Stop;
    /// <summary>welcomePage.continue.issues (mit Willkommensseite und „Weiterarbeiten“) an?</summary>
    function Enabled: Boolean;
    /// <summary>„Zuletzt“ hat ASnapshot für ATarget geschrieben (Schließen, Beenden): denselben Stand unter dem
    /// aktiven Issue sichern.</summary>
    procedure ProjectWritten(const ATarget: string; const ASnapshot: TAtlasContinueSnapshot);
    { IAtlasIssueWork (über Atlas.IDE.Welcome.IssueWork) }
    procedure SaveIssue(const AProject: string; const AIssue: TAtlasIssueWorkIssue);
    function HasState(const AProject, AKey: string): Boolean;
    procedure OfferRestore(const AProject, AKey: string);
    procedure StatusesChanged;
    { IAtlasContinueIssuesSource }
    function IssuesEnabled: Boolean;
    function IssueRows: TAtlasIssueWorkRows;
    function IssuesNotice: string;
    procedure ResumeIssue(const AProject, AKey: string);
  end;

implementation

uses
  System.UITypes,
  System.DateUtils,
  Vcl.Dialogs,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.VersionControl.Contract,
  Atlas.UI.Welcome.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Contracts.VersionControl,
  Atlas.IDE.Projects.Summaries,
  Atlas.IDE.Welcome.Neighbors,
  Atlas.IDE.Welcome.Search;

function NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

function StateKindOf(AStatus: TAtlasIssueWorkStatus): TAtlasIssueStateKind;
begin
  case AStatus of
    TAtlasIssueWorkStatus.Open:
      Result := TAtlasIssueStateKind.Open;
    TAtlasIssueWorkStatus.Resolved:
      Result := TAtlasIssueStateKind.Resolved;
  else
    Result := TAtlasIssueStateKind.Unknown;
  end;
end;

/// <summary>Hinweis auf fehlende Dateien beim Fortsetzen; '' ohne.</summary>
function MissingFilesText(const AMissing: TArray<string>): string;
var
  mNames: TArray<string>;
  mIndex: Integer;
begin
  Result := '';
  if Length(AMissing) = 0 then
  begin
    Exit;
  end;
  SetLength(mNames, Length(AMissing));
  for mIndex := 0 to High(AMissing) do
  begin
    mNames[mIndex] := TAtlasWelcomeContinue.FileNameOf(AMissing[mIndex]);
  end;
  Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeContinueMissing, [string.Join(', ', mNames)]);
end;

/// <summary>Im Hintergrund: ausgecheckter Branch und ob es AStored gibt; AKnown False, wenn die Versionsverwaltung
/// nicht antwortet (dann bleibt der Branch).</summary>
procedure ProbeBranch(const AFolder, AStored: string; out ACurrent: string; out AExists, AKnown: Boolean);
var
  mVcs: IAtlasVersionControl;
  mHead: TAtlasVcsHead;
  mBranching: IAtlasVcsBranching;
begin
  ACurrent := '';
  AExists := False;
  AKnown := False;
  mVcs := TAtlasIdeVcs.ForFolder(AFolder, TAtlasWelcomeContinue.cCallTimeoutMs);
  if (mVcs = nil) or (mVcs.Head(mHead) <> TAtlasVcsOutcome.Ok) then
  begin
    Exit;
  end;
  ACurrent := mHead.Branch;
  if SameText(ACurrent, AStored) then
  begin
    AExists := True;
    AKnown := True;
    Exit;
  end;
  AKnown := Supports(mVcs, IAtlasVcsBranching, mBranching) and
    (mBranching.BranchExists(AStored, AExists) = TAtlasVcsOutcome.Ok);
end;

{ TAtlasIdeContinueIssues }

constructor TAtlasIdeContinueIssues.Create(const AMessage: TProc<string>; AChanges: TDictionary<string, TAtlasWorkTab>;
  const AChanged: TProc);
begin
  inherited Create;
  FMessage := AMessage;
  FChanges := AChanges;
  FChanged := AChanged;
end;

procedure TAtlasIdeContinueIssues.Stop;
begin
  FStopped := True;
  FChanges := nil;
  FChanged := nil;
end;

procedure TAtlasIdeContinueIssues.Report(const AText: string);
begin
  if Assigned(FMessage) and (AText <> '') then
  begin
    FMessage(AText);
  end;
end;

procedure TAtlasIdeContinueIssues.Changed;
begin
  if not FStopped and Assigned(FChanged) then
  begin
    FChanged();
  end;
end;

function TAtlasIdeContinueIssues.Enabled: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := not FStopped and mSettings.WelcomePage and mSettings.WelcomePageContinue and
    mSettings.WelcomePageContinueIssues;
end;

function TAtlasIdeContinueIssues.IssuesEnabled: Boolean;
var
  mSource: IAtlasIssueWorkSource;
begin
  // Ohne Tracker-Modul kein Reiter.
  Result := Enabled and TAtlasWelcomeNeighbors.IssueWorkSource(mSource);
end;

function TAtlasIdeContinueIssues.IssuesNotice: string;
begin
  Result := '';
  if IssuesEnabled then
  begin
    Result := FNotice;
  end;
end;

function TAtlasIdeContinueIssues.SinceChanges: TArray<TAtlasWorkTab>;
var
  mTab: TAtlasWorkTab;
begin
  Result := nil;
  if FChanges = nil then
  begin
    Exit;
  end;
  for mTab in FChanges.Values do
  begin
    if (FSince <= 0) or (mTab.ChangedAt >= FSince) then
    begin
      Result := Result + [mTab];
    end;
  end;
end;

function TAtlasIdeContinueIssues.StatesOf(const AProject: string;
  const AKeys: TArray<string>): TArray<TAtlasIssueStateKind>;
var
  mSource: IAtlasIssueWorkSource;
  mInfos: TArray<TAtlasIssueWorkInfo>;
  mIndex, mFound: Integer;
begin
  SetLength(Result, Length(AKeys));
  for mIndex := 0 to High(Result) do
  begin
    Result[mIndex] := TAtlasIssueStateKind.Unknown;
  end;
  if (Length(AKeys) = 0) or not TAtlasWelcomeNeighbors.IssueWorkSource(mSource) then
  begin
    Exit;
  end;
  mInfos := mSource.Statuses(AProject, AKeys);
  for mIndex := 0 to High(AKeys) do
  begin
    for mFound := 0 to High(mInfos) do
    begin
      if TAtlasWelcomeContinueIssues.SameKey(mInfos[mFound].Key, AKeys[mIndex]) then
      begin
        Result[mIndex] := StateKindOf(mInfos[mFound].Status);
        Break;
      end;
    end;
  end;
end;

function TAtlasIdeContinueIssues.FindEntry(const AProject, AKey: string; out ATarget: string;
  out AEntry: TAtlasIssueWorkEntry): Boolean;
var
  mCandidates: TArray<string>;
  mCandidate: string;
  mSummary: TAtlasProjectSummary;
  mEntries: TAtlasIssueWorkEntries;
begin
  ATarget := '';
  AEntry := Default(TAtlasIssueWorkEntry);
  Result := False;
  if (AProject = '') or (AKey = '') then
  begin
    Exit;
  end;
  // Gespeichert wird unter der offenen Projektgruppe, sonst unter dem Projekt.
  mCandidates := TArray<string>.Create(TAtlasIdeContinueEditor.TargetOf(AProject), AProject);
  for mCandidate in mCandidates do
  begin
    if (mCandidate <> '') and TAtlasProjectSummaries.Load(TAtlasIdeProjectSummaries.Folder, mCandidate, mSummary) and
      TAtlasWelcomeContinueIssues.Read(mSummary, mEntries) and
      TAtlasWelcomeContinueIssues.Find(mEntries, AKey, AEntry) and (AEntry.State.TabCount > 0) then
    begin
      ATarget := mCandidate;
      Exit(True);
    end;
  end;
end;

procedure TAtlasIdeContinueIssues.Store(const ATarget: string; const AIssue: TAtlasIssueWorkIssue;
  const ASnapshot: TAtlasContinueSnapshot);
var
  mRoot: string;
  mSummary: TAtlasProjectSummary;
  mEntries: TAtlasIssueWorkEntries;
  mOld, mEntry: TAtlasIssueWorkEntry;
  mResolved: TArray<string>;
  mCount: Integer;
begin
  if (ATarget = '') or (Trim(AIssue.Key) = '') or (Length(ASnapshot.Tabs) = 0) then
  begin
    Exit;
  end;
  mRoot := TAtlasIdeProjectSummaries.Folder;
  mEntries := nil;
  if TAtlasProjectSummaries.Load(mRoot, ATarget, mSummary) then
  begin
    TAtlasWelcomeContinueIssues.Read(mSummary, mEntries);
  end;
  if not TAtlasWelcomeContinueIssues.Find(mEntries, AIssue.Key, mOld) then
  begin
    mOld := TAtlasIssueWorkEntry.Create(AIssue.Key, '', '', TAtlasWorkState.Empty);
  end;
  mEntry := TAtlasIssueWorkEntry.Create(AIssue.Key, AIssue.Title, AIssue.Branch,
    TAtlasWelcomeContinue.Build(ASnapshot.Tabs, ASnapshot.Active, SinceChanges, mOld.State, NowUtc));
  if mEntry.Title = '' then
  begin
    mEntry.Title := mOld.Title;
  end;
  if mEntry.Branch = '' then
  begin
    mEntry.Branch := mOld.Branch;
  end;
  // Behobene Issues fallen beim Speichern heraus.
  mResolved := TAtlasWelcomeContinueIssues.ResolvedKeys(TAtlasWelcomeContinueIssues.Keys(mEntries),
    StatesOf(ATarget, TAtlasWelcomeContinueIssues.Keys(mEntries)));
  mCount := TAtlasIdeSettings.Current.WelcomePageContinueIssuesCount;
  mEntries := TAtlasWelcomeContinueIssues.Store(TAtlasWelcomeContinueIssues.Without(mEntries, mResolved), mEntry,
    mCount);
  TAtlasProjectSummaries.Update(mRoot, ATarget,
    procedure(var ASummary: TAtlasProjectSummary)
    begin
      TAtlasWelcomeContinueIssues.Write(ASummary, mEntries);
    end);
end;

procedure TAtlasIdeContinueIssues.ProjectWritten(const ATarget: string; const ASnapshot: TAtlasContinueSnapshot);
var
  mSource: IAtlasIssueWorkSource;
  mIssue: TAtlasIssueWorkIssue;
begin
  if not Enabled or not TAtlasWelcomeNeighbors.IssueWorkSource(mSource) or
    not mSource.ActiveIssue(ATarget, mIssue) then
  begin
    Exit;
  end;
  Store(ATarget, mIssue, ASnapshot);
end;

procedure TAtlasIdeContinueIssues.SaveIssue(const AProject: string; const AIssue: TAtlasIssueWorkIssue);
var
  mTarget: string;
begin
  if not Enabled or (Trim(AIssue.Key) = '') or (FChanges = nil) then
  begin
    Exit;
  end;
  // Nur das offene Projekt (bzw. seine Gruppe) hat Reiter, die zu AIssue gehören.
  mTarget := TAtlasIdeContinueEditor.CurrentTarget;
  if (mTarget = '') or not TAtlasWelcomeContinue.SameFile(mTarget, TAtlasIdeContinueEditor.TargetOf(AProject)) then
  begin
    Exit;
  end;
  Store(mTarget, AIssue, TAtlasIdeContinueEditor.TakeSnapshot(FChanges));
  // Änderungen ab jetzt gehören zum nächsten Issue.
  FSince := NowUtc;
  Changed;
end;

function TAtlasIdeContinueIssues.HasState(const AProject, AKey: string): Boolean;
var
  mTarget: string;
  mEntry: TAtlasIssueWorkEntry;
begin
  Result := Enabled and FindEntry(AProject, AKey, mTarget, mEntry);
end;

procedure TAtlasIdeContinueIssues.OfferRestore(const AProject, AKey: string);
var
  mTarget: string;
  mEntry: TAtlasIssueWorkEntry;
begin
  if not Enabled or not FindEntry(AProject, AKey, mTarget, mEntry) then
  begin
    Exit;
  end;
  if MessageDlg(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeIssuesRestorePrompt,
    [mEntry.Key, TAtlasContinueIssueTexts.TabsText(mEntry.State.TabCount)]), mtConfirmation, [mbYes, mbNo],
    0) = mrYes then
  begin
    ResumeIssue(mTarget, mEntry.Key);
  end;
end;

procedure TAtlasIdeContinueIssues.StatusesChanged;
begin
  Changed;
end;

function TAtlasIdeContinueIssues.IssueRows: TAtlasIssueWorkRows;
var
  mProjects: TArray<string>;
  mRoot, mCurrent: string;
  mOwner: TAtlasIdeContinueIssues;
begin
  Result := nil;
  if not IssuesEnabled then
  begin
    Exit;
  end;
  // Das offene Projekt zuerst: Beim Wechsel des Issues ist es noch offen.
  mProjects := nil;
  mCurrent := TAtlasIdeContinueEditor.CurrentTarget;
  if mCurrent <> '' then
  begin
    mProjects := mProjects + [mCurrent];
  end;
  try
    mProjects := mProjects + TAtlasIdeWelcomeSearch.ClosedProjects;
  except
    // Registry nicht lesbar: nur das offene Projekt.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
  end;
  mRoot := TAtlasIdeProjectSummaries.Folder;
  mOwner := Self;
  Result := TAtlasWelcomeContinueIssues.Rows(mProjects,
    function(const AProject: string; out ASummary: TAtlasProjectSummary): Boolean
    begin
      Result := TAtlasProjectSummaries.Load(mRoot, AProject, ASummary);
    end,
    function(const AProject: string; const AKeys: TArray<string>): TArray<TAtlasIssueStateKind>
    begin
      Result := mOwner.StatesOf(AProject, AKeys);
    end,
    TAtlasIdeSettings.Current.WelcomePageContinueIssuesCount);
end;

procedure TAtlasIdeContinueIssues.ResumeIssue(const AProject, AKey: string);
var
  mTarget, mFolder, mStored, mCurrent: string;
  mEntry: TAtlasIssueWorkEntry;
  mKeep: IAtlasContinueIssuesSource;
  mExists, mKnown: Boolean;
begin
  if not Enabled then
  begin
    Report(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueDisabled));
    Exit;
  end;
  if not FindEntry(AProject, AKey, mTarget, mEntry) then
  begin
    Report(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueNothing));
    Exit;
  end;
  if not FileExists(mTarget) then
  begin
    Report(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeProjectsMissing, [mTarget]));
    Exit;
  end;
  FNotice := '';
  if mEntry.Branch = '' then
  begin
    OpenPlan(mTarget, mEntry);
    Exit;
  end;
  // Branch im Hintergrund prüfen; Rückfrage und Öffnen im Hauptthread.
  mKeep := Self;
  mFolder := ExtractFileDir(mTarget);
  mStored := mEntry.Branch;
  mCurrent := '';
  mExists := False;
  mKnown := False;
  if not TAtlasIdeVcs.Run(
    procedure
    begin
      ProbeBranch(mFolder, mStored, mCurrent, mExists, mKnown);
    end,
    procedure
    var
      Step: TAtlasIssueBranchStep;
    begin
      if (mKeep = nil) or FStopped then
      begin
        Exit;
      end;
      Step := TAtlasIssueBranchStep.Keep;
      if mKnown then
      begin
        Step := TAtlasWelcomeContinueIssues.BranchStep(mStored, mCurrent, mExists);
      end;
      BranchChecked(mTarget, mEntry, Step, mCurrent);
    end) then
  begin
    OpenPlan(mTarget, mEntry);
  end;
end;

procedure TAtlasIdeContinueIssues.BranchChecked(const AProject: string; const AEntry: TAtlasIssueWorkEntry;
  AStep: TAtlasIssueBranchStep; const ACurrent: string);
begin
  case AStep of
    TAtlasIssueBranchStep.Missing:
      begin
        // Branch nicht mehr vorhanden: nur die Reiter.
        FNotice := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeIssuesBranchMissing, [AEntry.Branch]);
        Report(FNotice);
        OpenPlan(AProject, AEntry);
      end;
    TAtlasIssueBranchStep.Ask:
      case MessageDlg(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeIssuesSwitchPrompt,
        [AEntry.Key, AEntry.Branch, ACurrent, sLineBreak, sLineBreak]), mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
        mrYes:
          SwitchThenOpen(AProject, AEntry);
        mrNo:
          OpenPlan(AProject, AEntry);
      end;
  else
    OpenPlan(AProject, AEntry);
  end;
end;

procedure TAtlasIdeContinueIssues.SwitchThenOpen(const AProject: string; const AEntry: TAtlasIssueWorkEntry);
var
  mKeep: IAtlasContinueIssuesSource;
  mFolder, mBranch, mProject: string;
  mEntry: TAtlasIssueWorkEntry;
  mOutcome: TAtlasVcsOutcome;
begin
  mKeep := Self;
  mFolder := ExtractFileDir(AProject);
  mBranch := AEntry.Branch;
  mProject := AProject;
  mEntry := AEntry;
  mOutcome := TAtlasVcsOutcome.Failed;
  if not TAtlasIdeVcs.Run(
    procedure
    var
      Branching: IAtlasVcsBranching;
    begin
      if Supports(TAtlasIdeVcs.ForFolder(mFolder), IAtlasVcsBranching, Branching) then
      begin
        mOutcome := Branching.SwitchBranch(mBranch);
      end;
    end,
    procedure
    begin
      if (mKeep = nil) or FStopped then
      begin
        Exit;
      end;
      // Wechsel gescheitert (z. B. lokale Änderungen): Grund melden, die Reiter trotzdem öffnen.
      if mOutcome <> TAtlasVcsOutcome.Ok then
      begin
        FNotice := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeIssuesSwitchFailed,
          [mBranch, AtlasVcsOutcomeName(mOutcome)]);
        Report(FNotice);
      end;
      OpenPlan(mProject, mEntry);
    end) then
  begin
    OpenPlan(AProject, AEntry);
  end;
end;

procedure TAtlasIdeContinueIssues.OpenPlan(const AProject: string; const AEntry: TAtlasIssueWorkEntry);
var
  mProject: string;
  mEntry: TAtlasIssueWorkEntry;
begin
  mProject := AProject;
  mEntry := AEntry;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Plan: TAtlasContinuePlan;
      Tab: TAtlasWorkTab;
      Missing: string;
    begin
      Plan := TAtlasWelcomeContinue.Plan(mProject, mEntry.State,
        function(const AFileName: string): Boolean
        begin
          Result := FileExists(AFileName);
        end);
      Missing := MissingFilesText(Plan.Missing);
      if Missing <> '' then
      begin
        Report(Missing);
        FNotice := Trim(FNotice + ' ' + Missing);
      end;
      TAtlasIdeContinueEditor.EnsureProject(mProject);
      // Reiter in ihrer Reihenfolge; danach den zuvor aktiven noch einmal, damit er vorn liegt.
      for Tab in Plan.Open do
      begin
        TAtlasIdeContinueEditor.OpenTab(Tab);
      end;
      if (Plan.Active >= 0) and (Plan.Active <= High(Plan.Open)) then
      begin
        TAtlasIdeContinueEditor.OpenTab(Plan.Open[Plan.Active]);
      end;
      Changed;
    end);
end;

end.
