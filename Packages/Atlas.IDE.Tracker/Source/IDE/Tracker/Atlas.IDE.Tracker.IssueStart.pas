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
// - „Beenden“: mit issues.syncState der Dialog „ATL-123 beenden“, sonst die
//   Rückfrage; danach die Zeiterfassung (#1267).
// Arbeit mit der Versionsverwaltung im Hintergrund (TAtlasIdeVcs.Run), Dialoge
// im Hauptthread. Protokoll anonym: Art und Ergebnis.

interface

uses
  System.SysUtils,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.MyIssues,
  Atlas.Core.Vcs.BranchPlan,
  Atlas.IDE.Tracker.IssuesContext,
  Atlas.IDE.Tracker.IssuesServices,
  Atlas.IDE.Tracker.IssuesStatus;

type
  /// <summary>Ein „Beginnen“ vom Prüfen der Arbeitskopie bis zum Ergebnis.</summary>
  TAtlasIssueStartJob = record
    Project: string;
    Issue: TAtlasTrackerIssue;
    Plan: TAtlasIssueStartPlan;
    /// <summary>Lokale Änderungen der Arbeitskopie.</summary>
    Changes: Integer;
    /// <summary>Stand für den Plan (#1288), nur wenn der Branch noch fehlt.</summary>
    Facts: TAtlasVcsBranchFacts;
    /// <summary>Request statt nur Plan ausführen (Dialog bzw. Git-Optionen, #1289).</summary>
    UseRequest: Boolean;
    Request: TAtlasVcsBranchRequest;
    /// <summary>Nach dem Dialog: scheitert der Abruf, „Vom lokalen Stand abzweigen?“ anbieten (#1289).</summary>
    OfferLocal: Boolean;
    Outcome: TAtlasIssueStartResult;
    /// <summary>Im Hintergrund: Art der Versionsverwaltung, Plan, lokale Änderungen und Stand.</summary>
    procedure Inspect(const AOptions: TAtlasIssuesOptions);
    /// <summary>Im Hintergrund: Plan bzw. Request ausführen; im worktree Hook-Ordner des neuen Ordners.</summary>
    procedure Execute;
    /// <summary>Neuer bzw. umzuschaltender Branch mit gültigem Namen?</summary>
    function Branching: Boolean;
    /// <summary>Ohne Dialog fragen, ob lokale Änderungen mitgehen (uncommitted = ask)?</summary>
    function AsksUncommitted(const AOptions: TAtlasVcsGitBranchOptions): Boolean;
    /// <summary>Im Dialog für Git entschieden.</summary>
    function InDialog: Boolean;
    /// <summary>Mit stash oder worktree entschieden.</summary>
    function Settled: Boolean;
    /// <summary>Lokale Änderungen noch nicht entschieden (AAsked: ohne Dialog gefragt)?</summary>
    function ChangesOpen(AAsked: Boolean): Boolean;
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
    procedure Inspect(const AJob: TAtlasIssueStartJob; const AOptions: TAtlasIssuesOptions);
    procedure NotStarted(const AJob: TAtlasIssueStartJob);
    procedure Cancelled(const AProject: string);
    procedure Prepared(const AJob: TAtlasIssueStartJob);
    class function DefaultChoice(var AJob: TAtlasIssueStartJob; var AAsked: Boolean): Boolean; static;
    function DialogChoice(var AJob: TAtlasIssueStartJob): Boolean;
    function ConfirmChanges(const AJob: TAtlasIssueStartJob; AAsked: Boolean): Boolean;
    procedure Run(const AJob: TAtlasIssueStartJob);
    procedure Executed(const AJob: TAtlasIssueStartJob);
    procedure Finished(const AJob: TAtlasIssueStartJob);
    function ReportFailure(const AJob: TAtlasIssueStartJob): Boolean;
    procedure Remember(const AJob: TAtlasIssueStartJob);
    procedure Track(const AJob: TAtlasIssueStartJob);
    procedure OpenAfter(const AJob: TAtlasIssueStartJob);
    procedure AskHook(var AState: TAtlasIssuesState; const AHooks: string);
    procedure EndedLocally(const AProject, ABranch, AKey: string);
    procedure EndWithTracker(const AProject, ABranch, AKey: string; const AProvider: IAtlasTrackerProvider;
      const ATarget: TAtlasTrackerTarget; const AState: TAtlasIssuesState);
  public
    constructor Create(AContext: TAtlasIdeIssuesContext; AServices: TAtlasIdeIssuesServices;
      AStatus: TAtlasIdeIssuesStatus);
    /// <summary>„Beginnen“ für AIssue (Bereich an, kein Beginnen läuft, Projekt vorhanden).</summary>
    procedure Start(const AIssue: TAtlasTrackerIssue; AMode: TAtlasIssueStart);
    /// <summary>Das aktuelle Issue beenden (Dialog mit issues.syncState, sonst Rückfrage).</summary>
    procedure EndActive;
  end;

implementation

uses
  System.UITypes,
  Vcl.Dialogs,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Tracker.CommitHook,
  Atlas.Core.Tracker.Links,
  Atlas.Core.Vcs.Contract,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.LinkDialogs,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Vcs.Branching,
  Atlas.IDE.Vcs.Service,
  Atlas.IDE.Tracker.Workflow,
  Atlas.IDE.Tracker.IssueLinkWrites;

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
  mVcs := TAtlasIdeVcs.ForFolder(ExtractFileDir(Project), TAtlasIdeVcs.AtLeast(cVcsTimeoutMs));
  mKind := TAtlasVcsKind.None;
  if mVcs <> nil then
  begin
    mKind := mVcs.Kind;
  end;
  Plan := TAtlasMyIssues.PlanStart(mKind, AOptions, Issue);
  if not Branching or (mVcs = nil) then
  begin
    Exit;
  end;
  if mVcs.Changes(mItems) = TAtlasVcsOutcome.Ok then
  begin
    Changes := TAtlasVcsBranchPlan.LocalChanges(mItems);
  end;
  // Vorhandener Branch: nur umschalten, ohne Dialog (wie bisher).
  if Supports(mVcs, IAtlasVcsBranching, mBranching) and
    (mBranching.BranchExists(Plan.Branch, Plan.Svn, mExists) = TAtlasVcsOutcome.Ok) and not mExists then
  begin
    Facts := TAtlasVcsBranchPlan.Inspect(mVcs, Plan.Bases);
    Facts.LocalChanges := Changes;
  end;
end;

procedure TAtlasIssueStartJob.Execute;
var
  mDir, mHooks, mGitDir: string;
  mVcs: IAtlasVersionControl;
  mBranching: IAtlasVcsBranching;
begin
  mDir := ExtractFileDir(Project);
  if UseRequest then
  begin
    Outcome := TAtlasMyIssues.Execute(TAtlasIdeVcs.ForFolder(mDir, TAtlasIdeVcs.AtLeast(cVcsTimeoutMs)), Plan,
      Request, TAtlasIdeBranching.Progress(Request.Kind));
  end
  else
  begin
    Outcome := TAtlasMyIssues.Execute(TAtlasIdeVcs.ForFolder(mDir, TAtlasIdeVcs.AtLeast(cVcsTimeoutMs)), Plan);
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

function TAtlasIssueStartJob.Branching: Boolean;
begin
  Result := (Plan.Mode = TAtlasIssueStart.Branch) and Plan.Valid;
end;

function TAtlasIssueStartJob.AsksUncommitted(const AOptions: TAtlasVcsGitBranchOptions): Boolean;
begin
  Result := (Request.Kind = TAtlasVcsKind.Git) and (Request.WorktreeFolder = '') and (Changes > 0) and
    (AOptions.Uncommitted = TAtlasVcsGitUncommitted.Ask);
end;

function TAtlasIssueStartJob.InDialog: Boolean;
begin
  Result := OfferLocal and (Request.Kind = TAtlasVcsKind.Git);
end;

function TAtlasIssueStartJob.Settled: Boolean;
begin
  Result := UseRequest and (Request.Stash or (Request.WorktreeFolder <> ''));
end;

function TAtlasIssueStartJob.ChangesOpen(AAsked: Boolean): Boolean;
begin
  Result := Branching and (Changes > 0) and not AAsked and not InDialog and not Settled;
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
  Result.Svn := TAtlasIdeBranching.SvnOptions(AProject);
end;

/// <summary>Hinweis nach gelungenem Beginnen.</summary>
function NoticeOf(const AJob: TAtlasIssueStartJob): string;
begin
  case AJob.Outcome.Outcome of
    TAtlasIssueStartOutcome.Started:
      if AJob.Outcome.Folder <> '' then
      begin
        Result := TAtlasStrings.Fmt(TAtlasTextId.VcsBranchWorktreeCreated, [AJob.Outcome.Branch, AJob.Outcome.Base,
          AJob.Outcome.Folder]);
      end
      else
      begin
        Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesCreated, [AJob.Outcome.Branch, AJob.Outcome.Base]);
      end;
    TAtlasIssueStartOutcome.Switched:
      Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesSwitched, [AJob.Outcome.Branch]);
  else
    if AJob.Plan.Prefix <> '' then
    begin
      Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesRememberedPrefix, [AJob.Issue.Key, AJob.Plan.Prefix]);
    end
    else
    begin
      Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesRemembered, [AJob.Issue.Key]);
    end;
  end;
end;

/// <summary>Projekt, für das das Issue gilt: im worktree (#1289) das im neuen Ordner.</summary>
function ProjectOf(const AJob: TAtlasIssueStartJob): string;
begin
  Result := AJob.Project;
  if AJob.Outcome.Folder <> '' then
  begin
    Result := TAtlasVcsBranchPlan.ProjectInFolder(AJob.Project, AJob.Outcome.WorkingRoot, AJob.Outcome.Folder);
  end;
  if Result = '' then
  begin
    Result := AJob.Project;
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
  mProject := FContext.CurrentProject;
  mTarget := FContext.TargetOf(mProject);
  // Sperrt ein zweites „Beginnen“, solange die Prüfung läuft.
  FContext.StartProject := mProject;
  FContext.Notice := TAtlasIssuesNotice.Create(mProject, TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesStarting,
    [mIssue.Key]), False);
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
  mJob: TAtlasIssueStartJob;
begin
  if not FContext.CanStart or (AIssue.Key = '') then
  begin
    Exit;
  end;
  mJob := Default(TAtlasIssueStartJob);
  mJob.Project := FContext.CurrentProject;
  mJob.Issue := AIssue;
  mJob.Facts := TAtlasVcsBranchFacts.Empty;
  FContext.StartProject := mJob.Project;
  FContext.Notice := TAtlasIssuesNotice.Create(mJob.Project, TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesStarting,
    [AIssue.Key]), False);
  FContext.Changed;
  Inspect(mJob, StartOptions(FServices, mJob.Project, AMode));
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
  FContext.Notice := TAtlasIssuesNotice.Create(AJob.Project, TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesNotStarted,
    [AJob.Issue.Key]), True);
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
  mJob.UseRequest := False;
  mJob.OfferLocal := False;
  mJob.Request := Default(TAtlasVcsBranchRequest);
  mAsked := False;
  // Neuer Branch (#1288): mit vcs.branch.confirm erst der Dialog „Branch anlegen“; „Abbrechen“ ändert nichts.
  // Ohne Dialog die Vorgaben aus dem Plan und den Git-Optionen (#1289). Findet SVN ohne erkennbares Layout
  // keinen Ort (#1290), fragt der Dialog trotzdem danach, statt an einem geratenen Ort anzulegen.
  if mJob.Branching and (mJob.Facts.Outcome = TAtlasVcsOutcome.Ok) and
    not (DefaultChoice(mJob, mAsked) and DialogChoice(mJob)) then
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
  mOptions := TAtlasIdeBranching.GitOptions;
  AJob.UseRequest := TAtlasVcsBranchPlan.DefaultRequest(AJob.Facts, AJob.Plan.Branch, AJob.Plan.Message,
    AJob.Issue.Key, TAtlasVcsBranchOptions.Make(mOptions, AJob.Plan.Svn), AJob.Request);
  // uncommitted = ask ohne Dialog: mitnehmen, beiseitelegen oder abbrechen.
  if AJob.UseRequest and AJob.AsksUncommitted(mOptions) then
  begin
    Result := TAtlasIdeBranching.AskUncommitted(AJob.Changes, AJob.Plan.Branch, AJob.Request.Stash);
    AAsked := Result;
  end;
end;

function TAtlasIdeIssueStart.DialogChoice(var AJob: TAtlasIssueStartJob): Boolean;
var
  mNeverAsk: Boolean;
begin
  Result := True;
  if not TAtlasIdeSettings.Current.VcsBranchConfirm and
    (AJob.UseRequest or (AJob.Facts.Kind <> TAtlasVcsKind.Svn)) then
  begin
    Exit;
  end;
  Result := TAtlasIdeBranching.Ask(ExtractFileDir(AJob.Project), AJob.Facts, TAtlasIdeBranching.Setup(AJob.Plan.Branch,
    AJob.Plan.Message, AJob.Issue.Key, AJob.Plan.Svn, True), AJob.Request, mNeverAsk);
  if not Result then
  begin
    Exit;
  end;
  if mNeverAsk then
  begin
    TAtlasIdeBranching.StopAsking;
  end;
  AJob.UseRequest := True;
  AJob.OfferLocal := True;
  AJob.Plan.Branch := AJob.Request.Name;
end;

function TAtlasIdeIssueStart.ConfirmChanges(const AJob: TAtlasIssueStartJob; AAsked: Boolean): Boolean;
begin
  // Lokale Änderungen: vorher fragen (Git nimmt sie mit, wenn sie nicht kollidieren). Nicht, wenn sie schon
  // entschieden sind: im Dialog (Git), bei stash oder worktree (#1289).
  Result := not AJob.ChangesOpen(AAsked) or (MessageDlg(TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesLocalChanges,
    [AJob.Changes, AJob.Plan.Branch, sLineBreak + sLineBreak]), mtConfirmation, [mbYes, mbNo], 0) = mrYes);
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
  if AJob.OfferLocal and (AJob.Outcome.Outcome = TAtlasIssueStartOutcome.Failed) and
    TAtlasIdeBranching.AskLocal(AJob.Facts, AJob.Request, AJob.Outcome.Steps, AJob.Outcome.Run, mFallback) then
  begin
    mJob := AJob;
    mJob.UseRequest := True;
    mJob.Request := mFallback;
    mJob.OfferLocal := False;
    Run(mJob);
  end
  else
  begin
    Finished(AJob);
  end;
end;

function TAtlasIdeIssueStart.ReportFailure(const AJob: TAtlasIssueStartJob): Boolean;
var
  mResult: TAtlasIssueStartResult;
begin
  mResult := AJob.Outcome;
  Result := mResult.Outcome in [TAtlasIssueStartOutcome.InvalidName, TAtlasIssueStartOutcome.Failed];
  if mResult.Outcome = TAtlasIssueStartOutcome.InvalidName then
  begin
    FContext.Notice := TAtlasIssuesNotice.Create(AJob.Project, TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesInvalidName,
      [AJob.Issue.Key]), True);
  end
  else if mResult.Outcome = TAtlasIssueStartOutcome.Failed then
  begin
    FContext.Notice := TAtlasIssuesNotice.Create(AJob.Project, TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesStartFailed,
      [mResult.Branch, AtlasVcsOutcomeName(mResult.Reason)]), True);
    // Mit Plan (#1288): Schritt, Grund und was schon auf dem Server liegt; worktree-Ordner belegt (#1289).
    if mResult.FolderTaken then
    begin
      FContext.Report(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchFolderTaken, [mResult.Folder]));
    end
    else if Length(mResult.Steps) > 0 then
    begin
      FContext.Report(TAtlasIdeBranching.FailureText(AJob.Plan.Kind, mResult.Steps, mResult.Run));
    end
    else
    begin
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
  mMode := TAtlasIssueStart.Branch;
  if AJob.Outcome.Outcome = TAtlasIssueStartOutcome.Remembered then
  begin
    mMode := TAtlasIssueStart.Remember;
  end;
  // worktree (#1289): Das Issue gilt für das Projekt im neuen Ordner; die bisherige Arbeitskopie bleibt.
  mProject := ProjectOf(AJob);
  mState := FContext.StateOf(mProject);
  TAtlasMyIssues.Started(mState, AJob.Issue, mMode, AJob.Outcome.Branch, TAtlasIdeIssuesTargets.NowUtc);
  if AJob.Outcome.GitDir <> '' then
  begin
    mState.GitDir := AJob.Outcome.GitDir;
  end;
  // Git-Hook für das Präfix: nur mit Muster und nach Zustimmung.
  if (AJob.Plan.Prefix <> '') and (AJob.Outcome.Hooks <> '') then
  begin
    AskHook(mState, AJob.Outcome.Hooks);
  end;
  FContext.SaveState(mProject, mState);
end;

procedure TAtlasIdeIssueStart.Track(const AJob: TAtlasIssueStartJob);
var
  mTarget: TAtlasTrackerTarget;
begin
  // Tracker nachführen (#1266): Ergebnis als eigene Zeile, der Branch bleibt auch bei einem Fehler.
  if FServices.Sync <> nil then
  begin
    mTarget := FContext.TargetOf(AJob.Project);
    FServices.Sync.Started(FContext.ProviderOf(mTarget.Provider), mTarget, AJob.Issue.Key, AJob.Outcome.Branch);
  end;
  FServices.ActiveChanged;
  // Branch und Änderungen neu abfragen; „Projekte“ meldet sich danach selbst.
  if (FContext.Welcome <> nil) and (AJob.Outcome.Outcome <> TAtlasIssueStartOutcome.Remembered) then
  begin
    FContext.Welcome.Refresh(AJob.Project);
  end;
  FContext.Changed;
  // Nur der Push danach scheiterte (#1289): der lokale Branch bleibt, die Meldung nennt den Grund.
  if AJob.Outcome.PushFailed then
  begin
    FContext.Report(TAtlasStrings.Fmt(TAtlasTextId.VcsBranchPushFailed, [AJob.Outcome.Branch,
      TAtlasIdeBranching.ServerState(AJob.Outcome.Reason)]));
  end;
end;

procedure TAtlasIdeIssueStart.OpenAfter(const AJob: TAtlasIssueStartJob);
var
  mOpen: string;
begin
  // Danach das Projekt öffnen (ein offenes bleibt offen); im worktree nur nach Rückfrage das dortige.
  if (FContext.Welcome <> nil) and (AJob.Outcome.Folder = '') then
  begin
    FContext.Welcome.Open(AJob.Project);
  end
  else if FContext.Welcome <> nil then
  begin
    mOpen := TAtlasIdeBranching.WorktreeProject(AJob.Project, AJob.Outcome.WorkingRoot, AJob.Outcome.Folder);
    if TAtlasIdeBranching.OfferWorktree(AJob.Outcome.Branch, AJob.Outcome.Folder, mOpen) then
    begin
      FContext.Welcome.Open(mOpen);
    end;
  end;
  // SVN „frisch auschecken“ (#1290): die alte Arbeitskopie bleibt; dieselbe Gruppe im neuen Ordner anbieten.
  if AJob.Outcome.CheckoutFolder <> '' then
  begin
    TAtlasIdeBranching.OfferOpen(AJob.Project, AJob.Outcome.WorkingRoot, AJob.Outcome.CheckoutFolder);
  end;
  // Externals festgeschrieben bzw. mitverzweigt und umgeschaltet (#1291): Index neu.
  if AJob.Outcome.IndexRebuild then
  begin
    TAtlasIdeBranching.RebuildIndex;
  end;
end;

procedure TAtlasIdeIssueStart.Finished(const AJob: TAtlasIssueStartJob);
begin
  FContext.StartProject := '';
  // Anonym: Art, Ergebnis; nie Kennung, Branch oder Pfad.
  TAtlasGuard.Log(Format(cLogStarted, [TAtlasMyIssues.StartName(AJob.Plan.Mode), AtlasVcsKindName(AJob.Plan.Kind),
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
end;

procedure TAtlasIdeIssueStart.AskHook(var AState: TAtlasIssuesState; const AHooks: string);
begin
  // Einmal je Projekt fragen; ein fremder Hook bleibt unangetastet.
  if (AHooks = '') or (AState.Hook <> '') then
  begin
    Exit;
  end;
  if TAtlasCommitHook.State(AHooks) = TAtlasCommitHookState.Own then
  begin
    AState.Hook := TAtlasMyIssues.cHookYes;
  end
  else if MessageDlg(TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesHookPrompt, [sLineBreak + sLineBreak]),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
  begin
    AState.Hook := TAtlasMyIssues.cHookNo;
  end
  else if TAtlasCommitHook.State(AHooks) = TAtlasCommitHookState.Foreign then
  begin
    AState.Hook := TAtlasMyIssues.cHookForeign;
    FContext.Report(TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesHookForeign));
  end
  else if TAtlasCommitHook.Install(AHooks, TAtlasStrings.Language = TAtlasLanguage.English) then
  begin
    AState.Hook := TAtlasMyIssues.cHookYes;
    TAtlasGuard.Log(cLogHook);
  end
  else
  begin
    FContext.Report(TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesHookFailed));
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
      mProject := FContext.CurrentProject;
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
      // Tracker nachführen (#1266): Dialog statt Rückfrage; ohne issues.syncState wie bisher.
      mProvider := FContext.ProviderOf(mTarget.Provider);
      if (FServices.Sync <> nil) and FServices.Sync.Enabled(mProvider, mTarget) then
      begin
        EndWithTracker(mProject, mBranch, mCurrent.Key, mProvider, mTarget, mState);
      end
      else if MessageDlg(TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesEndConfirm, [mCurrent.Key]), mtConfirmation,
        [mbYes, mbNo], 0) = mrYes then
      begin
        EndedLocally(mProject, mBranch, mCurrent.Key);
      end;
    end);
end;

procedure TAtlasIdeIssueStart.EndedLocally(const AProject, ABranch, AKey: string);
var
  mState: TAtlasIssuesState;
begin
  if not FContext.Started then
  begin
    Exit;
  end;
  mState := FContext.StateOf(AProject);
  TAtlasMyIssues.Ended(mState, ABranch);
  FContext.SaveState(AProject, mState);
  // Zeiterfassung (#1267): Zeit schreiben und das Buchen anbieten (Beschreibung aus den Commits).
  if FServices.Time <> nil then
  begin
    FServices.Time.Ended(FServices.TimeIssueOf(AProject, AKey), ExtractFileDir(AProject), ABranch,
      TAtlasIdeSettings.Current.IssuesBranchBase);
  end;
  FContext.Notice := TAtlasIssuesNotice.Create(AProject, TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesEnded, [AKey]),
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
  FServices.Sync.EndIssue(AProvider, ATarget, TAtlasIdeTrackerEnd.Create(AKey, ABranch, ExtractFileDir(AProject),
    TAtlasIdeSettings.Current.IssuesBranchBase, mPullRequest),
    procedure(AChange: TAtlasTrackerWrite)
    begin
      if mKeep <> nil then
      begin
        mOwner.EndedLocally(mProject, mBranch, mKey);
      end;
    end);
end;

end.
