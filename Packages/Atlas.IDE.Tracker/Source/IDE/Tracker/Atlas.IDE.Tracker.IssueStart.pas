unit Atlas.IDE.Tracker.IssueStart;

// „Beginnen“ und „Beenden“ von „Meine Issues“ (#765, aus
// Atlas.IDE.Tracker.MyIssues gelöst, #1455):
// - Warnung beim Beginnen (#1279, issues.warnBlocked): vorher liest die
//   Vorschau die Verknüpfungen; ist ein „hängt ab von“-Issue offen, fragt
//   Atlas mit „Trotzdem beginnen“ und „ATL-129 ansehen“.
// - Git legt den Branch nach Muster von der Basis an (main, sonst master) und
//   checkt ihn aus, SVN kopiert ^/trunk nach ^/branches/<Name>; ein
//   vorhandener Branch wird nur ausgecheckt. Fehlt der Branch noch, zeigt
//   Atlas mit vcs.branch.confirm den Dialog „Branch anlegen“ (#1288); ohne
//   Dialog gelten vcs.branch.git.* (#1289). Bei lokalen Änderungen fragt Atlas
//   vorher. Mit worktree gilt das Issue für das Projekt im neuen Ordner.
// - Danach Git-Hook für das Präfix (nach Zustimmung), Tracker nachführen
//   (#1266) und das Projekt öffnen.
// - Sprint (#2128, issues.sprintOnStart): Mit Tracker nachführen und einem
//   laufenden Sprint des Boards im Zwischenspeicher (Sprint-Kachel, sonst
//   Board), in dem das Issue fehlt, fragt „Beginnen“ vorher (ask) bzw. nimmt
//   ohne Frage auf (always); Abbrechen bricht das Beginnen ab. Aufgenommen
//   wird mit dem Nachführen; danach laden Board und Sprint-Kachel neu.
// - „Beenden“: mit issues.syncState der Dialog „ATL-123 beenden“, sonst die
//   Rückfrage; danach die Zeiterfassung (#1267).
// - „Weiterarbeiten“ an einem wieder geöffneten Issue (#2127): wie
//   „Beginnen“, aber auf dem gemerkten Branch statt nach Muster, ohne Warnung
//   und ohne den Tracker nachzuführen (der Zustand kam von dort); fehlt der
//   Branch, fragt Atlas, ob er neu angelegt werden soll. Danach den
//   Arbeitsstand ohne Rückfrage wiederherstellen (IAtlasIssueWork.Restore).
// - Verknüpfter Branch (#2138, issues.github.linkBranch, nur Git und GitHub):
//   Fehlt der Branch noch, legt GitHub ihn an und verknüpft ihn mit dem Issue
//   (bzw. nennt den schon verknüpften); danach Abruf und Auschecken mit
//   Upstream, ohne den Dialog „Branch anlegen“. Gibt es ihn schon, fehlt das
//   Recht oder zeigt origin woandershin, der lokale Weg wie bisher; eine Zeile
//   in den Meldungen sagt, was geschah (TAtlasLinkedStart).
// Arbeit mit der Versionsverwaltung im Hintergrund (TAtlasIdeVcs.Run), Dialoge
// im Hauptthread. Protokoll anonym: Art und Ergebnis.

interface

uses
  System.SysUtils,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.MyIssues,
  Atlas.Core.Tracker.StartPlan,
  Atlas.IDE.Tracker.IssuesContext,
  Atlas.IDE.Tracker.LinkedStart,
  Atlas.IDE.Tracker.IssuesServices,
  Atlas.IDE.Tracker.IssuesStatus;

type
  /// <summary>Ein „Beginnen“ vom Prüfen der Arbeitskopie bis zum Ergebnis.</summary>
  TAtlasIssueStartJob = record
    Project: string;
    /// <summary>Haupt-Arbeitskopie (#1926): erster Pfad aus issues.projects, sonst Ordner des Projekts.</summary>
    Folder: string;
    Issue: TAtlasTrackerIssue;
    /// <summary>Plan, lokale Änderungen, Stand, Wahl im Dialog, gemerkter Branch (#2127); die Entscheidungen
    /// darüber stehen in Core (TAtlasIssueStartState).</summary>
    State: TAtlasIssueStartState;
    Outcome: TAtlasIssueStartResult;
    /// <summary>In diesen Sprint aufnehmen (#2128); nicht gesetzt = keiner.</summary>
    Sprint: TAtlasTrackerSprintRef;
    /// <summary>Verknüpfter Branch (#2138): Tracker, Ziel und Transport; nicht Active = aus.</summary>
    Link: TAtlasIdeLinkSetup;
    /// <summary>Was mit dem verknüpften Branch geschah; Outcome None = nicht versucht.</summary>
    Linked: TAtlasIdeLinkedResult;
    /// <summary>Im Hintergrund: Art der Versionsverwaltung, Plan, lokale Änderungen und Stand.</summary>
    procedure Inspect(const AOptions: TAtlasIssuesOptions);
    /// <summary>Im Hintergrund: Plan bzw. Request ausführen; im worktree Hook-Ordner des neuen Ordners.</summary>
    procedure Execute;
    /// <summary>Im Hintergrund: verknüpften Branch anlegen bzw. finden und auschecken; True, wenn Outcome steht.
    /// </summary>
    function StartLinked: Boolean;
  end;

  TAtlasIdeIssueStart = class
  private
    FContext: TAtlasIdeIssuesContext;
    FServices: TAtlasIdeIssuesServices;
    FStatus: TAtlasIdeIssuesStatus;
    procedure CheckBlocked(const AIssue: TAtlasTrackerIssue; AMode: TAtlasIssueStart);
    procedure Blocked(const AProject: string; const ATarget: TAtlasTrackerTarget; const AIssue: TAtlasTrackerIssue;
      AMode: TAtlasIssueStart; AKnown: Boolean; const ADetails: TAtlasTrackerDetails);
    procedure StartChecked(const AIssue: TAtlasTrackerIssue; AMode: TAtlasIssueStart);
    /// <summary>Sprint für „Beginnen“ (#2128): ASprint gesetzt = aufnehmen; False = abgebrochen.</summary>
    function AskSprint(const AIssue: TAtlasTrackerIssue; out ASprint: TAtlasTrackerSprintRef): Boolean;
    /// <summary>Laufender Sprint ohne AKey im Zwischenspeicher von Sprint-Kachel bzw. Board.</summary>
    class function CachedSprint(const ATarget: TAtlasTrackerTarget; const AKey: string;
      out ASprint: TAtlasTrackerSprintRef): Boolean; static;
    procedure StartJob(const AIssue: TAtlasTrackerIssue; AMode: TAtlasIssueStart; const AResumeBranch: string;
      const ASprint: TAtlasTrackerSprintRef);
    /// <summary>Nach dem Nachführen: Board und Sprint-Kachel neu laden.</summary>
    function SprintWritten: TProc;
    /// <summary>„Weiterarbeiten“, Branch fehlt: neu anlegen? (sonst abbrechen)</summary>
    class function RecreateGone(const AJob: TAtlasIssueStartJob): Boolean; static;
    procedure Inspect(const AJob: TAtlasIssueStartJob; const AOptions: TAtlasIssuesOptions);
    procedure NotStarted(const AJob: TAtlasIssueStartJob);
    procedure Cancelled(const AProject: string);
    procedure Prepared(const AJob: TAtlasIssueStartJob);
    class function DefaultChoice(var AJob: TAtlasIssueStartJob; var AAsked: Boolean): Boolean; static;
    class function DialogChoice(var AJob: TAtlasIssueStartJob): Boolean; static;
    function ConfirmChanges(const AJob: TAtlasIssueStartJob; AAsked: Boolean): Boolean;
    procedure Run(const AJob: TAtlasIssueStartJob);
    procedure Executed(const AJob: TAtlasIssueStartJob);
    procedure Finished(const AJob: TAtlasIssueStartJob);
    function ReportFailure(const AJob: TAtlasIssueStartJob): Boolean;
    procedure Remember(const AJob: TAtlasIssueStartJob);
    procedure Track(const AJob: TAtlasIssueStartJob);
    procedure OpenAfter(const AJob: TAtlasIssueStartJob);
    procedure AskHook(var AState: TAtlasIssuesState; const AHooks: string);
    /// <summary>Beendet: AWritten ist der in den Tracker geschriebene Zustand ('' = nicht geändert).</summary>
    procedure EndedLocally(const AProject, ABranch, AKey, AWritten: string; AAbandoned: Boolean);
    procedure EndWithTracker(const AProject, ABranch, AKey: string; const AProvider: IAtlasTrackerProvider;
      const ATarget: TAtlasTrackerTarget; const AState: TAtlasIssuesState);
  public
    constructor Create(AContext: TAtlasIdeIssuesContext; AServices: TAtlasIdeIssuesServices;
      AStatus: TAtlasIdeIssuesStatus);
    /// <summary>„Beginnen“ für AIssue (Bereich an, kein Beginnen läuft, Projekt vorhanden).</summary>
    procedure Start(const AIssue: TAtlasTrackerIssue; AMode: TAtlasIssueStart);
    /// <summary>Das aktuelle Issue beenden (Dialog mit issues.syncState, sonst Rückfrage).</summary>
    procedure EndActive;
    /// <summary>„Weiterarbeiten“ an einem wieder geöffneten Issue (#2127) auf ABranch ('' = wie „Beginnen“).
    /// </summary>
    procedure Resume(const AIssue: TAtlasTrackerIssue; const ABranch: string);
  end;

implementation

uses
  System.UITypes,
  Vcl.Dialogs,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Tracker.CommitHook,
  Atlas.Core.Tracker.Links,
  Atlas.Core.Tracker.Workflow,
  Atlas.Core.VersionControl.BranchPlan,
  Atlas.Core.VersionControl.Contract,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.Workflow.Strings,
  Atlas.UI.Tracker.MyIssues.Strings,
  Atlas.UI.Tracker.LinkDialogs,
  Atlas.UI.Tracker.SprintDialog,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Contracts.VersionControl,
  Atlas.IDE.Tracker.IssueWorkLink,
  Atlas.IDE.Tracker.SprintTile,
  Atlas.IDE.Tracker.Workflow,
  Atlas.IDE.Tracker.WorkingCopies;

const
  /// <summary>Zeitlimit je Aufruf der Versionsverwaltung bei „Beginnen“.</summary>
  cVcsTimeoutMs = 30000;
  cLogBlocked = 'Meine Issues: Beginnen mit %d offenen Abhängigkeiten';
  cLogStarted = 'Meine Issues: Beginnen %s, %s (%s)';
  cLogHook = 'Meine Issues: Git-Hook prepare-commit-msg angelegt';
  cLogEnded = 'Meine Issues: aktuelles Issue beendet';

{ TAtlasIssueStartJob }

procedure TAtlasIssueStartJob.Inspect(const AOptions: TAtlasIssuesOptions);
var
  mVcs: IAtlasVersionControl;
  mKind: TAtlasVcsKind;
  mItems: TArray<TAtlasVcsChange>;
  mBranching: IAtlasVcsBranching;
  mExists: Boolean;
begin
  mVcs := TAtlasIdeVcs.ForFolder(Folder, TAtlasIdeVcs.AtLeast(cVcsTimeoutMs));
  mKind := TAtlasVcsKind.None;
  if mVcs <> nil then
  begin
    mKind := mVcs.Kind;
  end;
  State.Plan := TAtlasMyIssues.PlanStart(mKind, AOptions, Issue);
  TAtlasMyIssues.ResumeOn(State.Plan, State.ResumeBranch);
  if not State.Branching or (mVcs = nil) then
  begin
    Exit;
  end;
  if mVcs.Changes(mItems) = TAtlasVcsOutcome.Ok then
  begin
    State.Changes := TAtlasVcsBranchPlan.LocalChanges(mItems);
  end;
  // Vorhandener Branch: nur umschalten, ohne Dialog (wie bisher).
  if Supports(mVcs, IAtlasVcsBranching, mBranching) and
    (mBranching.BranchExists(State.Plan.Branch, State.Plan.Svn, mExists) = TAtlasVcsOutcome.Ok) then
  begin
    State.LocalExists := mExists;
    if not mExists then
    begin
      State.Facts := TAtlasVcsBranchPlan.Inspect(mVcs, State.Plan.Bases);
      State.Facts.LocalChanges := State.Changes;
    end;
  end;
end;

procedure TAtlasIssueStartJob.Execute;
var
  mDir, mHooks, mGitDir: string;
  mVcs: IAtlasVersionControl;
  mBranching: IAtlasVcsBranching;
begin
  // Verknüpfter Branch (#2138): sonst der lokale Weg wie bisher.
  if State.Linking and StartLinked then
  begin
    Exit;
  end;
  mDir := Folder;
  if State.UseRequest then
  begin
    Outcome := TAtlasMyIssues.Execute(TAtlasIdeVcs.ForFolder(mDir, TAtlasIdeVcs.AtLeast(cVcsTimeoutMs)), State.Plan,
      State.Request, TAtlasIdeVcs.Dialogs.Progress(State.Request.Kind));
  end
  else
  begin
    Outcome := TAtlasMyIssues.Execute(TAtlasIdeVcs.ForFolder(mDir, TAtlasIdeVcs.AtLeast(cVcsTimeoutMs)), State.Plan);
  end;
  // worktree (#1289): Hook und Präfix-Datei gehören zum neuen Ordner (eigener Verwaltungsordner).
  if (Outcome.Outcome <> TAtlasIssueStartOutcome.Started) or (Outcome.Folder = '') then
  begin
    Exit;
  end;
  Outcome.Hooks := '';
  Outcome.GitDir := '';
  mVcs := TAtlasIdeVcs.ForFolder(Outcome.Folder, TAtlasIdeVcs.AtLeast(cVcsTimeoutMs));
  if Supports(mVcs, IAtlasVcsBranching, mBranching) and
    (mBranching.HookFolders(mHooks, mGitDir) = TAtlasVcsOutcome.Ok) then
  begin
    Outcome.Hooks := mHooks;
    Outcome.GitDir := mGitDir;
  end;
end;

function TAtlasIssueStartJob.StartLinked: Boolean;
begin
  Result := False;
  if State.LocalExists then
  begin
    Linked := TAtlasIdeLinkedResult.Make(TAtlasTrackerBranchLinkOutcome.Exists, State.Plan.Branch);
    Exit;
  end;
  Linked := TAtlasIdeLinkedStart.Run(Link, Folder, Issue.Key, State.Plan.Branch, State.LinkBase);
  Result := Linked.CheckedOut;
  if not Result then
  begin
    Exit;
  end;
  // Angelegt: wie ein neuer Branch; schon verknüpft: wie ein vorhandener.
  Outcome := Default(TAtlasIssueStartResult);
  Outcome.Outcome := TAtlasIssueStartOutcome.Switched;
  if Linked.Link.Outcome = TAtlasTrackerBranchLinkOutcome.Created then
  begin
    Outcome.Outcome := TAtlasIssueStartOutcome.Started;
  end;
  Outcome.Branch := Linked.Link.Branch;
  Outcome.Base := Linked.Link.Base;
  Outcome.Reason := TAtlasVcsOutcome.Ok;
  Outcome.Hooks := Linked.Hooks;
  Outcome.GitDir := Linked.GitDir;
end;

/// <summary>Einstellungen für „Beginnen“ in AProject mit AMode.</summary>
function StartOptions(AServices: TAtlasIdeIssuesServices; const AProject: string;
  AMode: TAtlasIssueStart): TAtlasIssuesOptions;
begin
  Result := AServices.Options;
  Result.Start := AMode;
  // Hauptbranch des Projekts (#1286) als Basis, wenn issues.branchBase leer ist.
  Result.MainBranch := TAtlasIdeVcs.MainBranchOf(AProject, TAtlasIdeFiles.GroupOfProject(AProject));
  // SVN (#1290): Ort, Quelle, Danach und Nachricht aus vcs.branch.svn.*.
  Result.Svn := TAtlasIdeVcs.Dialogs.SvnOptions(AProject);
end;

/// <summary>Hinweis nach gelungenem Beginnen.</summary>
function NoticeOf(const AJob: TAtlasIssueStartJob): string;
begin
  case TAtlasIssueStartFlow.Notice(AJob.Outcome, AJob.State.Plan.Prefix) of
    TAtlasStartNotice.Worktree:
      Result := TAtlasStrings.Fmt(TAtlasTextId.VcsBranchWorktreeCreated, [AJob.Outcome.Branch, AJob.Outcome.Base,
        AJob.Outcome.Folder]);
    TAtlasStartNotice.Created:
      Result := TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.WelcomeIssuesCreated,
        [AJob.Outcome.Branch, AJob.Outcome.Base]);
    TAtlasStartNotice.Switched:
      Result := TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.WelcomeIssuesSwitched, [AJob.Outcome.Branch]);
    TAtlasStartNotice.RememberedPrefix:
      Result := TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.WelcomeIssuesRememberedPrefix,
        [AJob.Issue.Key, AJob.State.Plan.Prefix]);
  else
    Result := TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.WelcomeIssuesRemembered, [AJob.Issue.Key]);
  end;
end;

{ TAtlasIdeIssueStart }

constructor TAtlasIdeIssueStart.Create(AContext: TAtlasIdeIssuesContext; AServices: TAtlasIdeIssuesServices;
  AStatus: TAtlasIdeIssuesStatus);
begin
  inherited Create;
  FContext := AContext;
  FServices := AServices;
  FStatus := AStatus;
end;

procedure TAtlasIdeIssueStart.CheckBlocked(const AIssue: TAtlasTrackerIssue; AMode: TAtlasIssueStart);
var
  mKeep: IAtlasIdeIssuesActions;
  mOwner: TAtlasIdeIssueStart;
  mProject: string;
  mTarget: TAtlasTrackerTarget;
  mIssue: TAtlasTrackerIssue;
begin
  mKeep := FContext.Actions;
  mOwner := Self;
  mIssue := AIssue;
  mProject := FContext.Selection.CurrentProject;
  mTarget := FContext.TargetOf(mProject);
  // Sperrt ein zweites „Beginnen“, solange die Prüfung läuft.
  FContext.StartProject := mProject;
  FContext.Notice := TAtlasIssuesNotice.Create(mProject,
    TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.WelcomeIssuesStarting, [mIssue.Key]), False);
  FContext.Changed;
  FServices.Preview.LinkWrites.CheckBlocked(mTarget, mIssue.Key,
    procedure(AKnown: Boolean; const ADetails: TAtlasTrackerDetails)
    begin
      if (mKeep <> nil) and mOwner.FContext.Started then
      begin
        mOwner.Blocked(mProject, mTarget, mIssue, AMode, AKnown, ADetails);
      end;
    end);
end;

procedure TAtlasIdeIssueStart.Blocked(const AProject: string; const ATarget: TAtlasTrackerTarget;
  const AIssue: TAtlasTrackerIssue; AMode: TAtlasIssueStart; AKnown: Boolean; const ADetails: TAtlasTrackerDetails);
var
  mBlockers: TArray<TAtlasTrackerLink>;
  mChoice: TAtlasBlockedChoice;
begin
  FContext.StartProject := '';
  mBlockers := nil;
  if AKnown then
  begin
    mBlockers := TAtlasTrackerLinks.WarnOnStart(TAtlasIdeSettings.Current.IssuesWarnBlocked, ADetails);
  end;
  mChoice := TAtlasBlockedChoice.StartAnyway;
  if Length(mBlockers) > 0 then
  begin
    TAtlasGuard.Log(Format(cLogBlocked, [Length(mBlockers)], TFormatSettings.Invariant));
    mChoice := TAtlasBlockedPrompt.Ask(mBlockers);
  end;
  if mChoice = TAtlasBlockedChoice.StartAnyway then
  begin
    StartChecked(AIssue, AMode);
    Exit;
  end;
  Cancelled(AProject);
  if (mChoice = TAtlasBlockedChoice.ShowBlocker) and (FServices.Preview <> nil) then
  begin
    FServices.Preview.ShowLink(ATarget, mBlockers[0]);
  end;
end;

procedure TAtlasIdeIssueStart.StartChecked(const AIssue: TAtlasTrackerIssue; AMode: TAtlasIssueStart);
var
  mSprint: TAtlasTrackerSprintRef;
begin
  if FContext.CanStart and AskSprint(AIssue, mSprint) then
  begin
    StartJob(AIssue, AMode, '', mSprint);
  end;
end;

function TAtlasIdeIssueStart.AskSprint(const AIssue: TAtlasTrackerIssue; out ASprint: TAtlasTrackerSprintRef): Boolean;
var
  mMode: string;
  mTarget: TAtlasTrackerTarget;
  mFound: TAtlasTrackerSprintRef;
  mAnswer: TAtlasSprintAnswer;
  mDontAsk: Boolean;
  mNext: TAtlasPluginSettings;
  mStep: TAtlasSprintOnStart;
  mWrites: Boolean;
begin
  ASprint := TAtlasTrackerSprintRef.None;
  Result := True;
  mMode := TAtlasIdeSettings.Current.IssuesSprintOnStart;
  mTarget := FContext.TargetOf(FContext.Selection.CurrentProject);
  // Den Zwischenspeicher nur lesen, wenn überhaupt aufgenommen werden kann.
  mWrites := (mMode <> TAtlasPluginSettings.cIssuesSprintNever) and (FServices.Sync <> nil) and
    FServices.Sync.Enabled(FContext.ProviderOf(mTarget.Provider), mTarget);
  mStep := TAtlasIssueStartFlow.SprintOnStart(mMode, mWrites, mWrites and CachedSprint(mTarget, AIssue.Key, mFound));
  if mStep = TAtlasSprintOnStart.Skip then
  begin
    Exit;
  end;
  if mStep = TAtlasSprintOnStart.Take then
  begin
    ASprint := mFound;
    Exit;
  end;
  mAnswer := TAtlasTrackerSprintDialog.Ask(AIssue.Key, AIssue.Title, mFound, mDontAsk);
  Result := mAnswer <> TAtlasSprintAnswer.Cancel;
  if mAnswer = TAtlasSprintAnswer.Add then
  begin
    ASprint := mFound;
  end;
  // „Nicht mehr fragen“ merkt die Antwort: aufnehmen = always, ohne Sprint = never.
  if mDontAsk then
  begin
    mNext := TAtlasIdeSettings.Stored;
    mNext.IssuesSprintOnStart := TAtlasIssueStartFlow.RememberedSprintMode(ASprint.IsSet);
    TAtlasIdeSettings.Update(mNext);
  end;
end;

class function TAtlasIdeIssueStart.CachedSprint(const ATarget: TAtlasTrackerTarget; const AKey: string;
  out ASprint: TAtlasTrackerSprintRef): Boolean;
begin
  Result := TAtlasIssueStartFlow.CachedSprint(TAtlasIdeIssuesTargets.IssuesFolder, TAtlasIdeSprint.cCacheName, ATarget,
    AKey, TAtlasIdeIssuesTargets.NowUtc, ASprint);
end;

procedure TAtlasIdeIssueStart.StartJob(const AIssue: TAtlasTrackerIssue; AMode: TAtlasIssueStart;
  const AResumeBranch: string; const ASprint: TAtlasTrackerSprintRef);
var
  mJob: TAtlasIssueStartJob;
begin
  if not FContext.CanStart or (AIssue.Key = '') then
  begin
    Exit;
  end;
  // Arbeitsstand je Issue (#2052): den des bisher aktiven Issues sichern, bevor der Branch wechselt.
  TAtlasTrackerIssueWorkLink.BeforeStart(FContext, FContext.Selection.CurrentProject, AIssue.Key);
  mJob := Default(TAtlasIssueStartJob);
  mJob.Project := FContext.Selection.CurrentProject;
  mJob.Folder := TAtlasIdeTrackerWorkingCopies.FolderOf(mJob.Project);
  mJob.Issue := AIssue;
  mJob.State.ResumeBranch := AResumeBranch;
  mJob.Sprint := ASprint;
  mJob.State.Facts := TAtlasVcsBranchFacts.Empty;
  mJob.Link := TAtlasIdeLinkedStart.Setup(FContext, mJob.Project);
  mJob.State.LinkActive := mJob.Link.Active;
  FContext.StartProject := mJob.Project;
  FContext.Notice := TAtlasIssuesNotice.Create(mJob.Project,
    TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.WelcomeIssuesStarting, [AIssue.Key]), False);
  FContext.Changed;
  Inspect(mJob, StartOptions(FServices, mJob.Project, AMode));
end;

function TAtlasIdeIssueStart.SprintWritten: TProc;
var
  mServices: TAtlasIdeIssuesServices;
begin
  mServices := FServices;
  Result :=
    procedure
    begin
      // Das Board lädt nur, wenn es sichtbar ist; die Kachel sofort.
      if mServices.Board <> nil then
      begin
        mServices.Board.Refresh;
      end;
      if mServices.Sprint <> nil then
      begin
        mServices.Sprint.IssuesFetched(True);
      end;
    end;
end;

class function TAtlasIdeIssueStart.RecreateGone(const AJob: TAtlasIssueStartJob): Boolean;
begin
  Result := MessageDlg(TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.WelcomeIssuesContinueBranchGone,
    [AJob.State.Plan.Branch]), mtConfirmation, [mbYes, mbNo], 0) = mrYes;
end;

procedure TAtlasIdeIssueStart.Inspect(const AJob: TAtlasIssueStartJob; const AOptions: TAtlasIssuesOptions);
var
  mJob: TAtlasIssueStartJob;
  mOptions: TAtlasIssuesOptions;
  mKeep: IAtlasIdeIssuesActions;
  mOwner: TAtlasIdeIssueStart;
begin
  mJob := AJob;
  mOptions := AOptions;
  mKeep := FContext.Actions;
  mOwner := Self;
  // Art der Versionsverwaltung, lokale Änderungen und (fehlt der Branch noch) der Stand für den Plan (#1288) im
  // Hintergrund; Dialog und Rückfrage danach im Hauptthread.
  if not TAtlasIdeVcs.Run(
    procedure
    begin
      mJob.Inspect(mOptions);
    end,
    procedure
    begin
      if (mKeep <> nil) and mOwner.FContext.Started then
      begin
        mOwner.Prepared(mJob);
      end;
    end) then
  begin
    NotStarted(mJob);
  end;
end;

procedure TAtlasIdeIssueStart.NotStarted(const AJob: TAtlasIssueStartJob);
begin
  FContext.StartProject := '';
  FContext.Notice := TAtlasIssuesNotice.Create(AJob.Project,
    TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.WelcomeIssuesNotStarted, [AJob.Issue.Key]), True);
  FContext.Changed;
end;

procedure TAtlasIdeIssueStart.Cancelled(const AProject: string);
begin
  FContext.StartProject := '';
  FContext.Notice := TAtlasIssuesNotice.Create(AProject, '', False);
  FContext.Changed;
end;

procedure TAtlasIdeIssueStart.Prepared(const AJob: TAtlasIssueStartJob);
var
  mJob: TAtlasIssueStartJob;
  mAsked: Boolean;
begin
  mJob := AJob;
  mJob.State.UseRequest := False;
  mJob.State.OfferLocal := False;
  mJob.State.Request := Default(TAtlasVcsBranchRequest);
  mAsked := False;
  // „Weiterarbeiten“ (#2127): Der gemerkte Branch fehlt (Facts nur dann gelesen): erst fragen.
  if mJob.State.AsksRecreate and not RecreateGone(mJob) then
  begin
    Cancelled(mJob.Project);
    Exit;
  end;
  // Neuer Branch (#1288): mit vcs.branch.confirm erst der Dialog „Branch anlegen“; „Abbrechen“ ändert nichts.
  // Ohne Dialog die Vorgaben aus dem Plan und den Git-Optionen (#1289). Findet SVN ohne erkennbares Layout
  // keinen Ort (#1290), fragt der Dialog trotzdem danach, statt an einem geratenen Ort anzulegen. Mit
  // verknüpftem Branch (#2138) ohne Dialog: Name und Basis kommen vom Muster, angelegt wird auf dem Server.
  if mJob.State.ChoosesBranch and not (DefaultChoice(mJob, mAsked) and (mJob.State.Linking or DialogChoice(mJob))) then
  begin
    Cancelled(mJob.Project);
    Exit;
  end;
  if not ConfirmChanges(mJob, mAsked) then
  begin
    Cancelled(mJob.Project);
    Exit;
  end;
  Run(mJob);
end;

class function TAtlasIdeIssueStart.DefaultChoice(var AJob: TAtlasIssueStartJob; var AAsked: Boolean): Boolean;
var
  mOptions: TAtlasVcsGitBranchOptions;
begin
  Result := True;
  if TAtlasIdeSettings.Current.VcsBranchConfirm then
  begin
    Exit;
  end;
  mOptions := TAtlasIdeVcs.Dialogs.GitOptions;
  AJob.State.UseRequest := TAtlasVcsBranchPlan.DefaultRequest(AJob.State.Facts, AJob.State.Plan.Branch,
    AJob.State.Plan.Message, AJob.Issue.Key, TAtlasVcsBranchOptions.Make(mOptions, AJob.State.Plan.Svn),
    AJob.State.Request);
  // uncommitted = ask ohne Dialog: mitnehmen, beiseitelegen oder abbrechen.
  if AJob.State.UseRequest and AJob.State.AsksUncommitted(mOptions) then
  begin
    Result := TAtlasIdeVcs.Dialogs.AskUncommitted(AJob.State.Changes, AJob.State.Plan.Branch,
      AJob.State.Request.Stash);
    AAsked := Result;
  end;
end;

class function TAtlasIdeIssueStart.DialogChoice(var AJob: TAtlasIssueStartJob): Boolean;
var
  mNeverAsk: Boolean;
  mAsk: TAtlasVcsBranchAsk;
begin
  Result := True;
  if not AJob.State.ShowsDialog(TAtlasIdeSettings.Current.VcsBranchConfirm) then
  begin
    Exit;
  end;
  mAsk.Folder := AJob.Folder;
  mAsk.Facts := AJob.State.Facts;
  mAsk.Name := AJob.State.Plan.Branch;
  mAsk.Message := AJob.State.Plan.Message;
  mAsk.Key := AJob.Issue.Key;
  mAsk.Svn := AJob.State.Plan.Svn;
  mAsk.OfferNeverAsk := True;
  Result := TAtlasIdeVcs.Dialogs.AskBranch(mAsk, AJob.State.Request, mNeverAsk);
  if not Result then
  begin
    Exit;
  end;
  if mNeverAsk then
  begin
    TAtlasIdeVcs.Dialogs.StopAsking;
  end;
  AJob.State.UseRequest := True;
  AJob.State.OfferLocal := True;
  AJob.State.Plan.Branch := AJob.State.Request.Name;
end;

function TAtlasIdeIssueStart.ConfirmChanges(const AJob: TAtlasIssueStartJob; AAsked: Boolean): Boolean;
begin
  // Lokale Änderungen: vorher fragen (Git nimmt sie mit, wenn sie nicht kollidieren). Nicht, wenn sie schon
  // entschieden sind: im Dialog (Git), bei stash oder worktree (#1289).
  Result := not AJob.State.ChangesOpen(AAsked) or (MessageDlg(TAtlasWorkflowStrings.Fmt(
    TAtlasWorkflowTextId.WelcomeIssuesLocalChanges, [AJob.State.Changes, AJob.State.Plan.Branch,
    sLineBreak + sLineBreak]),
    mtConfirmation, [mbYes, mbNo], 0) = mrYes);
end;

procedure TAtlasIdeIssueStart.Run(const AJob: TAtlasIssueStartJob);
var
  mJob: TAtlasIssueStartJob;
  mKeep: IAtlasIdeIssuesActions;
  mOwner: TAtlasIdeIssueStart;
begin
  mJob := AJob;
  mJob.Outcome := Default(TAtlasIssueStartResult);
  mKeep := FContext.Actions;
  mOwner := Self;
  if not TAtlasIdeVcs.Run(
    procedure
    begin
      mJob.Execute;
    end,
    procedure
    begin
      if (mKeep <> nil) and mOwner.FContext.Started then
      begin
        mOwner.Executed(mJob);
      end;
    end) then
  begin
    NotStarted(mJob);
  end;
end;

procedure TAtlasIdeIssueStart.Executed(const AJob: TAtlasIssueStartJob);
var
  mJob: TAtlasIssueStartJob;
  mFallback: TAtlasVcsBranchRequest;
begin
  // Abruf gescheitert (#1289), noch nichts geändert: nach dem Dialog vom lokalen Stand, ohne erneute Frage.
  if AJob.State.OfferLocal and (AJob.Outcome.Outcome = TAtlasIssueStartOutcome.Failed) and
    TAtlasIdeVcs.Dialogs.AskLocal(AJob.State.Facts, AJob.State.Request, AJob.Outcome.Steps, AJob.Outcome.Run,
    mFallback) then
  begin
    mJob := AJob;
    mJob.State.UseRequest := True;
    mJob.State.Request := mFallback;
    mJob.State.OfferLocal := False;
    Run(mJob);
  end
  else
  begin
    Finished(AJob);
  end;
end;

procedure TAtlasIdeIssueStart.Finished(const AJob: TAtlasIssueStartJob);
begin
  FContext.StartProject := '';
  if AJob.Linked.Link.Outcome <> TAtlasTrackerBranchLinkOutcome.None then
  begin
    FContext.Report(TAtlasIdeLinkedStart.Report(AJob.Link, AJob.Issue.Key, AJob.Linked));
  end;
  // Anonym: Art, Ergebnis; nie Kennung, Branch oder Pfad.
  TAtlasGuard.Log(Format(cLogStarted, [TAtlasMyIssues.StartName(AJob.State.Plan.Mode),
    AtlasVcsKindName(AJob.State.Plan.Kind),
    AtlasVcsOutcomeName(AJob.Outcome.Reason)], TFormatSettings.Invariant));
  if ReportFailure(AJob) then
  begin
    Exit;
  end;
  Remember(AJob);
  FContext.Notice := TAtlasIssuesNotice.Create(AJob.Project, NoticeOf(AJob), False);
  FStatus.Update;
  Track(AJob);
  OpenAfter(AJob);
  // Arbeitsstand je Issue (#2052): gemerkte Reiter anbieten; im neuen worktree gelten die alten Pfade nicht.
  // „Weiterarbeiten“ (#2127) stellt ihn ohne Rückfrage wieder her.
  case TAtlasIssueStartFlow.WorkAfter(AJob.Outcome.Folder, AJob.State.Resuming) of
    TAtlasStartWork.Restore:
      TAtlasTrackerIssueWorkLink.AfterResume(AJob.Project, AJob.Issue.Key);
    TAtlasStartWork.Offer:
      TAtlasTrackerIssueWorkLink.AfterStart(AJob.Project, AJob.Issue.Key);
    TAtlasStartWork.None:
      begin
        // Neuer worktree: die alten Pfade gelten dort nicht.
      end;
  end;
end;

function TAtlasIdeIssueStart.ReportFailure(const AJob: TAtlasIssueStartJob): Boolean;
var
  mResult: TAtlasIssueStartResult;
  mFailure: TAtlasStartFailure;
begin
  mResult := AJob.Outcome;
  mFailure := TAtlasIssueStartFlow.Failure(mResult);
  Result := mFailure <> TAtlasStartFailure.None;
  if mFailure = TAtlasStartFailure.InvalidName then
  begin
    FContext.Notice := TAtlasIssuesNotice.Create(AJob.Project,
      TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.WelcomeIssuesInvalidName, [AJob.Issue.Key]), True);
  end
  else if Result then
  begin
    FContext.Notice := TAtlasIssuesNotice.Create(AJob.Project,
      TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.WelcomeIssuesStartFailed,
      [mResult.Branch, AtlasVcsOutcomeName(mResult.Reason)]), True);
    case mFailure of
      TAtlasStartFailure.FolderTaken:
        FContext.Report(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchFolderTaken, [mResult.Folder]));
      TAtlasStartFailure.Steps:
        FContext.Report(TAtlasIdeVcs.Dialogs.FailureText(AJob.State.Plan.Kind, mResult.Steps, mResult.Run));
    else
      FContext.Report(FContext.Notice.Text);
    end;
  end;
  if Result then
  begin
    FContext.Changed;
  end;
end;

procedure TAtlasIdeIssueStart.Remember(const AJob: TAtlasIssueStartJob);
var
  mState: TAtlasIssuesState;
  mMode: TAtlasIssueStart;
  mProject: string;
begin
  mMode := TAtlasIssueStartFlow.ModeAfter(AJob.Outcome);
  // worktree (#1289): Das Issue gilt für das Projekt im neuen Ordner; die bisherige Arbeitskopie bleibt.
  mProject := TAtlasIssueStartFlow.ProjectAfter(AJob.Project, AJob.Outcome);
  mState := FContext.StateOf(mProject);
  TAtlasMyIssues.Started(mState, AJob.Issue, mMode, AJob.Outcome.Branch, TAtlasIdeIssuesTargets.NowUtc);
  if AJob.Outcome.GitDir <> '' then
  begin
    mState.GitDir := AJob.Outcome.GitDir;
  end;
  // Git-Hook für das Präfix: nur mit Muster und nach Zustimmung.
  if (AJob.State.Plan.Prefix <> '') and (AJob.Outcome.Hooks <> '') then
  begin
    AskHook(mState, AJob.Outcome.Hooks);
  end;
  FContext.SaveState(mProject, mState);
end;

procedure TAtlasIdeIssueStart.Track(const AJob: TAtlasIssueStartJob);
var
  mTarget: TAtlasTrackerTarget;
begin
  // Tracker nachführen (#1266): Ergebnis als eigene Zeile, der Branch bleibt auch bei einem Fehler. Nicht bei
  // „Weiterarbeiten“ (#2127): Den Zustand hat der Tracker gerade selbst zurückgesetzt.
  if (FServices.Sync <> nil) and not AJob.State.Resuming then
  begin
    mTarget := FContext.TargetOf(AJob.Project);
    FServices.Sync.Started(FContext.ProviderOf(mTarget.Provider), mTarget, AJob.Issue.Key, AJob.Outcome.Branch,
      AJob.Sprint, SprintWritten());
  end;
  FServices.ActiveChanged;
  // Branch und Änderungen neu abfragen; „Projekte“ meldet sich danach selbst.
  if (FContext.Welcome <> nil) and (AJob.Outcome.Outcome <> TAtlasIssueStartOutcome.Remembered) then
  begin
    FContext.Welcome.Refresh(AJob.Project);
  end;
  FContext.Selection.ForgetHead(AJob.Folder);
  FContext.Changed;
  // Nur der Push danach scheiterte (#1289): der lokale Branch bleibt, die Meldung nennt den Grund.
  if AJob.Outcome.PushFailed then
  begin
    FContext.Report(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchPushFailed, [AJob.Outcome.Branch,
      TAtlasIdeVcs.Dialogs.ServerState(AJob.Outcome.Reason)]));
  end;
end;

procedure TAtlasIdeIssueStart.OpenAfter(const AJob: TAtlasIssueStartJob);
var
  mOpen: string;
begin
  // Danach das Projekt öffnen (ein offenes bleibt offen); im worktree nur nach Rückfrage das dortige. Ein Ordner
  // als gewähltes Tracker-Projekt (#1927) lässt sich nicht öffnen.
  case TAtlasIssueStartFlow.OpenAfter(TAtlasIdeFiles.IsProjectFile(AJob.Project), FContext.Welcome <> nil,
    AJob.Outcome.Folder) of
    TAtlasStartOpen.Project:
      FContext.Welcome.Open(AJob.Project);
    TAtlasStartOpen.Worktree:
      begin
        mOpen := TAtlasIdeVcs.Dialogs.WorktreeProject(AJob.Project, AJob.Outcome.WorkingRoot, AJob.Outcome.Folder);
        if TAtlasIdeVcs.Dialogs.OfferWorktree(AJob.Outcome.Branch, AJob.Outcome.Folder, mOpen) then
        begin
          FContext.Welcome.Open(mOpen);
        end;
      end;
    TAtlasStartOpen.None:
      begin
        // Nichts zu öffnen.
      end;
  end;
  // SVN „frisch auschecken“ (#1290): die alte Arbeitskopie bleibt; dieselbe Gruppe im neuen Ordner anbieten.
  if AJob.Outcome.CheckoutFolder <> '' then
  begin
    TAtlasIdeVcs.Dialogs.OfferOpen(AJob.Project, AJob.Outcome.WorkingRoot, AJob.Outcome.CheckoutFolder);
  end;
  // Externals festgeschrieben bzw. mitverzweigt und umgeschaltet (#1291): Index neu.
  if AJob.Outcome.IndexRebuild then
  begin
    TAtlasIdeVcs.Dialogs.RebuildIndex;
  end;
end;

procedure TAtlasIdeIssueStart.AskHook(var AState: TAtlasIssuesState; const AHooks: string);
var
  mStep: TAtlasHookStep;
begin
  // Einmal je Projekt fragen; ein fremder Hook bleibt unangetastet.
  mStep := TAtlasHookStep.Skip;
  if AHooks <> '' then
  begin
    mStep := TAtlasIssueStartFlow.HookStep(AHooks, AState.Hook, TAtlasCommitHook.State(AHooks));
  end;
  if mStep = TAtlasHookStep.Skip then
  begin
    Exit;
  end;
  if mStep = TAtlasHookStep.Own then
  begin
    AState.Hook := TAtlasMyIssues.cHookYes;
  end
  else if MessageDlg(TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.WelcomeIssuesHookPrompt, [sLineBreak + sLineBreak]),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
  begin
    AState.Hook := TAtlasMyIssues.cHookNo;
  end
  else if TAtlasCommitHook.State(AHooks) = TAtlasCommitHookState.Foreign then
  begin
    AState.Hook := TAtlasMyIssues.cHookForeign;
    FContext.Report(TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.WelcomeIssuesHookForeign));
  end
  else if TAtlasCommitHook.Install(AHooks, TAtlasStrings.Language = TAtlasLanguage.English) then
  begin
    AState.Hook := TAtlasMyIssues.cHookYes;
    TAtlasGuard.Log(cLogHook);
  end
  else
  begin
    FContext.Report(TAtlasMyIssuesStrings.Text(TAtlasMyIssuesTextId.WelcomeIssuesHookFailed));
  end;
end;

procedure TAtlasIdeIssueStart.EndedLocally(const AProject, ABranch, AKey, AWritten: string; AAbandoned: Boolean);
var
  mState: TAtlasIssuesState;
begin
  if not FContext.Started then
  begin
    Exit;
  end;
  mState := FContext.StateOf(AProject);
  TAtlasMyIssues.Ended(mState, ABranch);
  // Wieder geöffnete Issues (#2127): Kennung, Branch und geschriebenen Zustand merken.
  if FServices.Reopened <> nil then
  begin
    FServices.Reopened.EndedIssue(AProject, mState, AKey, ABranch, AWritten);
  end;
  FContext.SaveState(AProject, mState);
  // „Nicht geplant“ oder „Duplikat“ (#2135): Arbeitsstand verwerfen, keine Zeit anbieten.
  if AAbandoned then
  begin
    TAtlasTrackerIssueWorkLink.Forget(AProject, AKey);
  end;
  // Zeiterfassung (#1267): Zeit schreiben und das Buchen anbieten (Beschreibung aus den Commits), nicht nach
  // „nicht geplant“ oder „Duplikat“.
  if FServices.Time <> nil then
  begin
    FServices.Time.Ended(FServices.TimeIssueOf(AProject, AKey), TAtlasIdeTrackerWorkingCopies.FolderOf(AProject),
      ABranch, TAtlasIdeSettings.Current.IssuesBranchBase, not AAbandoned);
  end;
  FContext.Notice := TAtlasIssuesNotice.Create(AProject,
    TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.WelcomeIssuesEnded, [AKey]),
    False);
  TAtlasGuard.Log(cLogEnded);
  FStatus.Update;
  FServices.ActiveChanged;
  FContext.Changed;
end;

procedure TAtlasIdeIssueStart.EndWithTracker(const AProject, ABranch, AKey: string;
  const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget; const AState: TAtlasIssuesState);
var
  mKeep: IAtlasIdeIssuesActions;
  mOwner: TAtlasIdeIssueStart;
  mIssue: TAtlasTrackerIssue;
  mPullRequest, mProject, mBranch, mKey: string;
  mInput: TAtlasIdeTrackerEnd;
begin
  // Eigene Routine: Die Methodenreferenz hält nur diese Werte.
  mKeep := FContext.Actions;
  mOwner := Self;
  mProject := AProject;
  mBranch := ABranch;
  mKey := AKey;
  mPullRequest := '';
  if AState.Find(AKey, mIssue) and (mIssue.PullRequest.Number > 0) then
  begin
    mPullRequest := AProvider.PullRequestPage(ATarget, mIssue.PullRequest.Number);
  end;
  mInput := TAtlasIdeTrackerEnd.Create(AKey, ABranch, TAtlasIdeTrackerWorkingCopies.FolderOf(AProject),
    TAtlasIdeSettings.Current.IssuesBranchBase, mPullRequest);
  // Titel des Issues für den Pull Request (#2136).
  mInput.Title := mIssue.Title;
  FServices.Sync.EndIssue(AProvider, ATarget, mInput,
    procedure(AChange: TAtlasTrackerWrite)
    begin
      if mKeep <> nil then
      begin
        mOwner.EndedLocally(mProject, mBranch, mKey, AChange.State, TAtlasTrackerWorkflow.Abandons(AChange));
      end;
    end);
end;

procedure TAtlasIdeIssueStart.Start(const AIssue: TAtlasTrackerIssue; AMode: TAtlasIssueStart);
begin
  if not FContext.CanStart or (AIssue.Key = '') then
  begin
    Exit;
  end;
  // Erst prüfen, ob ein „hängt ab von“-Issue noch offen ist (#1279).
  if TAtlasIdeSettings.Current.IssuesWarnBlocked and (FServices.Preview <> nil) then
  begin
    CheckBlocked(AIssue, AMode);
  end
  else
  begin
    StartChecked(AIssue, AMode);
  end;
end;

procedure TAtlasIdeIssueStart.EndActive;
begin
  TAtlasGuard.Run(TAtlasFeature.Tracker,
    procedure
    var
      mProject, mBranch: string;
      mState: TAtlasIssuesState;
      mTarget: TAtlasTrackerTarget;
      mCurrent: TAtlasActiveIssue;
      mProvider: IAtlasTrackerProvider;
    begin
      mProject := FContext.Selection.CurrentProject;
      if not FContext.Started or (mProject = '') then
      begin
        Exit;
      end;
      mState := FContext.StateOf(mProject);
      mBranch := FContext.BranchOf(mProject);
      mTarget := FContext.TargetOf(mProject);
      mCurrent := TAtlasMyIssues.Effective(mState, mTarget.Provider, mTarget.Project, mBranch);
      if not mCurrent.Active then
      begin
        Exit;
      end;
      // Arbeitsstand je Issue (#2052) vor dem Beenden sichern.
      TAtlasTrackerIssueWorkLink.BeforeEnd(mProject, mBranch, mCurrent);
      // Tracker nachführen (#1266): Dialog statt Rückfrage; ohne issues.syncState wie bisher.
      mProvider := FContext.ProviderOf(mTarget.Provider);
      if (FServices.Sync <> nil) and FServices.Sync.Enabled(mProvider, mTarget) then
      begin
        EndWithTracker(mProject, mBranch, mCurrent.Key, mProvider, mTarget, mState);
      end
      else if MessageDlg(TAtlasMyIssuesStrings.Fmt(TAtlasMyIssuesTextId.WelcomeIssuesEndConfirm, [mCurrent.Key]),
        mtConfirmation, [mbYes, mbNo], 0) = mrYes then
      begin
        EndedLocally(mProject, mBranch, mCurrent.Key, '', False);
      end;
    end);
end;

procedure TAtlasIdeIssueStart.Resume(const AIssue: TAtlasTrackerIssue; const ABranch: string);
begin
  if not FContext.CanStart or (AIssue.Key = '') then
  begin
    Exit;
  end;
  // Mit gemerktem Branch immer als Branch, auch wenn issues.start „merken“ sagt: Es gab ihn schon.
  StartJob(AIssue, TAtlasIssueStartFlow.ResumeMode(ABranch, FServices.Options.Start), ABranch,
    TAtlasTrackerSprintRef.None);
end;

end.
