unit Atlas.Core.Tracker.StartPlan;

// Entscheidungen von „Beginnen“ und „Beenden“ in „Meine Issues“ (#765) ohne IDE prüfbar (#1967); die IDE
// (Atlas.IDE.Tracker.IssueStart) fragt die Versionsverwaltung, zeigt Dialoge und Meldungen:
// - Stand eines Laufs (TAtlasIssueStartState): neuer Branch nach Muster, „Weiterarbeiten“ auf dem gemerkten
//   (#2127), verknüpfter Branch (#2138), lokale Änderungen und ob sie schon entschieden sind (Dialog, stash,
//   worktree, #1289), wann der Dialog „Branch anlegen“ kommt (#1288, #1290).
// - Sprint beim Beginnen (#2128, issues.sprintOnStart), Git-Hook für das Präfix (einmal je Projekt, ein fremder
//   bleibt), Meldung bei einem Fehlschlag, was nach dem Beginnen geöffnet und wiederhergestellt wird.

interface

uses
  Atlas.Core.Tracker.CommitHook,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.MyIssues,
  Atlas.Core.VersionControl.BranchPlan;

type
  /// <summary>Was ein Lauf von „Beginnen“ über Plan, Arbeitskopie und Wahl im Dialog weiß.</summary>
  TAtlasIssueStartState = record
    Plan: TAtlasIssueStartPlan;
    /// <summary>Lokale Änderungen der Arbeitskopie.</summary>
    Changes: Integer;
    /// <summary>Stand für den Plan (#1288); nur gelesen, wenn der Branch noch fehlt.</summary>
    Facts: TAtlasVcsBranchFacts;
    /// <summary>Request gilt (aus dem Dialog bzw. den Vorgaben).</summary>
    UseRequest: Boolean;
    Request: TAtlasVcsBranchRequest;
    /// <summary>Im Dialog gewählt: Scheitert der Abruf, wird der lokale Stand angeboten.</summary>
    OfferLocal: Boolean;
    /// <summary>„Weiterarbeiten“ (#2127) auf diesem Branch; '' = neu nach Muster.</summary>
    ResumeBranch: string;
    /// <summary>Verknüpfter Branch (#2138) ist eingeschaltet.</summary>
    LinkActive: Boolean;
    /// <summary>Den Branch gibt es lokal schon.</summary>
    LocalExists: Boolean;
    function Resuming: Boolean;
    /// <summary>Ein gültiger Branch soll entstehen bzw. umgeschaltet werden.</summary>
    function Branching: Boolean;
    /// <summary>Der Branch fehlt noch und der Stand ist gelesen: Vorgaben bzw. Dialog „Branch anlegen“.</summary>
    function ChoosesBranch: Boolean;
    /// <summary>„Weiterarbeiten“, aber der gemerkte Branch fehlt: erst fragen, ob er neu entstehen soll.</summary>
    function AsksRecreate: Boolean;
    /// <summary>uncommitted = ask ohne Dialog (Git, ohne worktree, mit Änderungen).</summary>
    function AsksUncommitted(const AOptions: TAtlasVcsGitBranchOptions): Boolean;
    /// <summary>Den Dialog „Branch anlegen“ zeigen: mit vcs.branch.confirm, sonst nur, wenn SVN ohne erkennbares
    /// Layout keinen Ort fand (#1290).</summary>
    function ShowsDialog(AConfirm: Boolean): Boolean;
    /// <summary>Lokale Änderungen entschied der Dialog (Git).</summary>
    function InDialog: Boolean;
    /// <summary>Lokale Änderungen sind über stash bzw. worktree entschieden (#1289).</summary>
    function Settled: Boolean;
    /// <summary>Vor dem Beginnen nach den lokalen Änderungen fragen (AAsked: schon gefragt).</summary>
    function ChangesOpen(AAsked: Boolean): Boolean;
    /// <summary>Über den verknüpften Branch beginnen (#2138): nicht beim Weiterarbeiten oder wenn stash bzw.
    /// worktree gewählt ist.</summary>
    function Linking: Boolean;
    /// <summary>Basis für den verknüpften Branch: die erste des Plans, sonst ''.</summary>
    function LinkBase: string;
  end;

{$SCOPEDENUMS ON}
  /// <summary>Sprint beim Beginnen (#2128): keiner, ohne Frage aufnehmen oder fragen.</summary>
  TAtlasSprintOnStart = (Skip, Take, Ask);
  /// <summary>Git-Hook für das Präfix: nichts tun (kein Hook-Ordner oder schon entschieden), schon unserer,
  /// fragen.</summary>
  TAtlasHookStep = (Skip, Own, Ask);
  /// <summary>Was „Beginnen“ bei einem Fehlschlag meldet: nichts (kein Fehlschlag), ungültiger Name, Ordner des
  /// worktree belegt, Schritte des Plans oder nur die Meldung.</summary>
  TAtlasStartFailure = (None, InvalidName, FolderTaken, Steps, Plain);
  /// <summary>Was nach dem Beginnen geöffnet wird: nichts (kein Projekt), das Projekt, nach Rückfrage das im
  /// worktree.</summary>
  TAtlasStartOpen = (None, Project, Worktree);
  /// <summary>Arbeitsstand je Issue (#2052) nach dem Beginnen: nichts (neuer worktree), wiederherstellen
  /// („Weiterarbeiten“, #2127), anbieten.</summary>
  TAtlasStartWork = (None, Restore, Offer);
  /// <summary>Hinweis nach gelungenem Beginnen: worktree angelegt, Branch angelegt, umgeschaltet, gemerkt mit
  /// bzw. ohne Präfix.</summary>
  TAtlasStartNotice = (Worktree, Created, Switched, RememberedPrefix, Remembered);
{$SCOPEDENUMS OFF}

  TAtlasIssueStartFlow = class
  public
    /// <summary>issues.sprintOnStart AMode mit nachgeführtem Tracker (AWrites) und einem laufenden Sprint ohne
    /// das Issue (AFound).</summary>
    class function SprintOnStart(const AMode: string; AWrites, AFound: Boolean): TAtlasSprintOnStart; static;
    /// <summary>Laufender Sprint, in dem AKey fehlt, ohne Netz aus dem zuletzt gelesenen Stand in AFolder: erst
    /// der der Sprint-Kachel (ASprintCache, laufender Sprint), sonst der des Boards (gewählter Sprint).</summary>
    class function CachedSprint(const AFolder, ASprintCache: string; const ATarget: TAtlasTrackerTarget;
      const AKey: string; ANowUtc: TDateTime; out ASprint: TAtlasTrackerSprintRef): Boolean; static;
    /// <summary>„Nicht mehr fragen“: aufgenommen = always, ohne Sprint = never.</summary>
    class function RememberedSprintMode(ATaken: Boolean): string; static;
    /// <summary>Git-Hook im Ordner AHooks; ACurrent ist die gemerkte Antwort des Projekts.</summary>
    class function HookStep(const AHooks, ACurrent: string; AState: TAtlasCommitHookState): TAtlasHookStep; static;
    /// <summary>Meldung zu AResult.</summary>
    class function Failure(const AResult: TAtlasIssueStartResult): TAtlasStartFailure; static;
    /// <summary>Gemerkt wird als Branch, nur nach Remembered als Merken.</summary>
    class function ModeAfter(const AResult: TAtlasIssueStartResult): TAtlasIssueStart; static;
    /// <summary>Hinweis nach gelungenem Beginnen mit AResult; APrefix ist das Präfix des Plans.</summary>
    class function Notice(const AResult: TAtlasIssueStartResult; const APrefix: string): TAtlasStartNotice; static;
    /// <summary>Projekt, für das das Issue nach AResult gilt: im worktree (#1289) das im neuen Ordner, sonst
    /// AProject.</summary>
    class function ProjectAfter(const AProject: string; const AResult: TAtlasIssueStartResult): string; static;
    /// <summary>Öffnen nach dem Beginnen: AProjectFile (ein Ordner lässt sich nicht öffnen, #1927), mit Seite
    /// AWelcome; AFolder ist der Ordner eines neuen worktree.</summary>
    class function OpenAfter(AProjectFile, AWelcome: Boolean; const AFolder: string): TAtlasStartOpen; static;
    /// <summary>Arbeitsstand nach dem Beginnen; im neuen worktree gelten die alten Pfade nicht.</summary>
    class function WorkAfter(const AFolder: string; AResuming: Boolean): TAtlasStartWork; static;
    /// <summary>„Weiterarbeiten“ (#2127) mit gemerktem ABranch immer als Branch, sonst wie AStart.</summary>
    class function ResumeMode(const ABranch: string; AStart: TAtlasIssueStart): TAtlasIssueStart; static;
  end;

implementation

uses
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Tracker.Board,
  Atlas.Core.Tracker.SprintStart,
  Atlas.Core.VersionControl.Contract;

{ TAtlasIssueStartState }

function TAtlasIssueStartState.Resuming: Boolean;
begin
  Result := ResumeBranch <> '';
end;

function TAtlasIssueStartState.Branching: Boolean;
begin
  Result := (Plan.Mode = TAtlasIssueStart.Branch) and Plan.Valid;
end;

function TAtlasIssueStartState.ChoosesBranch: Boolean;
begin
  Result := Branching and (Facts.Outcome = TAtlasVcsOutcome.Ok);
end;

function TAtlasIssueStartState.AsksRecreate: Boolean;
begin
  Result := Resuming and ChoosesBranch;
end;

function TAtlasIssueStartState.AsksUncommitted(const AOptions: TAtlasVcsGitBranchOptions): Boolean;
begin
  Result := (Request.Kind = TAtlasVcsKind.Git) and (Request.WorktreeFolder = '') and (Changes > 0) and
    (AOptions.Uncommitted = TAtlasVcsGitUncommitted.Ask);
end;

function TAtlasIssueStartState.ShowsDialog(AConfirm: Boolean): Boolean;
begin
  Result := AConfirm or (not UseRequest and (Facts.Kind = TAtlasVcsKind.Svn));
end;

function TAtlasIssueStartState.InDialog: Boolean;
begin
  Result := OfferLocal and (Request.Kind = TAtlasVcsKind.Git);
end;

function TAtlasIssueStartState.Settled: Boolean;
begin
  Result := UseRequest and (Request.Stash or (Request.WorktreeFolder <> ''));
end;

function TAtlasIssueStartState.ChangesOpen(AAsked: Boolean): Boolean;
begin
  Result := Branching and (Changes > 0) and not AAsked and not InDialog and not Settled;
end;

function TAtlasIssueStartState.Linking: Boolean;
begin
  Result := LinkActive and Branching and not Resuming and not Settled;
end;

function TAtlasIssueStartState.LinkBase: string;
begin
  Result := '';
  if Length(Plan.Bases) > 0 then
  begin
    Result := Plan.Bases[0];
  end;
end;

{ TAtlasIssueStartFlow }

class function TAtlasIssueStartFlow.SprintOnStart(const AMode: string; AWrites, AFound: Boolean): TAtlasSprintOnStart;
begin
  if (AMode = TAtlasPluginSettings.cIssuesSprintNever) or not AWrites or not AFound then
  begin
    Exit(TAtlasSprintOnStart.Skip);
  end;
  if AMode = TAtlasPluginSettings.cIssuesSprintAlways then
  begin
    Exit(TAtlasSprintOnStart.Take);
  end;
  Result := TAtlasSprintOnStart.Ask;
end;

class function TAtlasIssueStartFlow.CachedSprint(const AFolder, ASprintCache: string;
  const ATarget: TAtlasTrackerTarget; const AKey: string; ANowUtc: TDateTime;
  out ASprint: TAtlasTrackerSprintRef): Boolean;
var
  mSnapshot: TAtlasBoardSnapshot;
begin
  ASprint := TAtlasTrackerSprintRef.None;
  Result := TAtlasTrackerBoard.Load(AFolder, ATarget, ASprintCache, mSnapshot) and
    TAtlasSprintStart.Running(mSnapshot, ANowUtc);
  if not Result then
  begin
    Result := TAtlasTrackerBoard.Load(AFolder, ATarget, mSnapshot) and TAtlasSprintStart.Running(mSnapshot, ANowUtc);
  end;
  Result := Result and TAtlasSprintStart.Missing(mSnapshot, AKey, ANowUtc, ASprint);
end;

class function TAtlasIssueStartFlow.RememberedSprintMode(ATaken: Boolean): string;
begin
  Result := TAtlasPluginSettings.cIssuesSprintNever;
  if ATaken then
  begin
    Result := TAtlasPluginSettings.cIssuesSprintAlways;
  end;
end;

class function TAtlasIssueStartFlow.HookStep(const AHooks, ACurrent: string;
  AState: TAtlasCommitHookState): TAtlasHookStep;
begin
  // Einmal je Projekt fragen; ein fremder Hook bleibt unangetastet (entschieden nach der Frage).
  if (AHooks = '') or (ACurrent <> '') then
  begin
    Exit(TAtlasHookStep.Skip);
  end;
  if AState = TAtlasCommitHookState.Own then
  begin
    Exit(TAtlasHookStep.Own);
  end;
  Result := TAtlasHookStep.Ask;
end;

class function TAtlasIssueStartFlow.Failure(const AResult: TAtlasIssueStartResult): TAtlasStartFailure;
begin
  if AResult.Outcome = TAtlasIssueStartOutcome.InvalidName then
  begin
    Exit(TAtlasStartFailure.InvalidName);
  end;
  if AResult.Outcome <> TAtlasIssueStartOutcome.Failed then
  begin
    Exit(TAtlasStartFailure.None);
  end;
  // Mit Plan (#1288): Schritt, Grund und was schon auf dem Server liegt; worktree-Ordner belegt (#1289).
  if AResult.FolderTaken then
  begin
    Exit(TAtlasStartFailure.FolderTaken);
  end;
  if Length(AResult.Steps) > 0 then
  begin
    Exit(TAtlasStartFailure.Steps);
  end;
  Result := TAtlasStartFailure.Plain;
end;

class function TAtlasIssueStartFlow.ModeAfter(const AResult: TAtlasIssueStartResult): TAtlasIssueStart;
begin
  Result := TAtlasIssueStart.Branch;
  if AResult.Outcome = TAtlasIssueStartOutcome.Remembered then
  begin
    Result := TAtlasIssueStart.Remember;
  end;
end;

class function TAtlasIssueStartFlow.Notice(const AResult: TAtlasIssueStartResult;
  const APrefix: string): TAtlasStartNotice;
begin
  if (AResult.Outcome = TAtlasIssueStartOutcome.Started) and (AResult.Folder <> '') then
  begin
    Exit(TAtlasStartNotice.Worktree);
  end;
  if AResult.Outcome = TAtlasIssueStartOutcome.Started then
  begin
    Exit(TAtlasStartNotice.Created);
  end;
  if AResult.Outcome = TAtlasIssueStartOutcome.Switched then
  begin
    Exit(TAtlasStartNotice.Switched);
  end;
  if APrefix <> '' then
  begin
    Exit(TAtlasStartNotice.RememberedPrefix);
  end;
  Result := TAtlasStartNotice.Remembered;
end;

class function TAtlasIssueStartFlow.ProjectAfter(const AProject: string; const AResult: TAtlasIssueStartResult): string;
begin
  Result := AProject;
  if AResult.Folder <> '' then
  begin
    Result := TAtlasVcsBranchPlan.ProjectInFolder(AProject, AResult.WorkingRoot, AResult.Folder);
  end;
  if Result = '' then
  begin
    Result := AProject;
  end;
end;

class function TAtlasIssueStartFlow.OpenAfter(AProjectFile, AWelcome: Boolean; const AFolder: string): TAtlasStartOpen;
begin
  if not AProjectFile or not AWelcome then
  begin
    Exit(TAtlasStartOpen.None);
  end;
  if AFolder = '' then
  begin
    Exit(TAtlasStartOpen.Project);
  end;
  Result := TAtlasStartOpen.Worktree;
end;

class function TAtlasIssueStartFlow.WorkAfter(const AFolder: string; AResuming: Boolean): TAtlasStartWork;
begin
  if AFolder <> '' then
  begin
    Exit(TAtlasStartWork.None);
  end;
  if AResuming then
  begin
    Exit(TAtlasStartWork.Restore);
  end;
  Result := TAtlasStartWork.Offer;
end;

class function TAtlasIssueStartFlow.ResumeMode(const ABranch: string; AStart: TAtlasIssueStart): TAtlasIssueStart;
begin
  Result := AStart;
  if ABranch <> '' then
  begin
    Result := TAtlasIssueStart.Branch;
  end;
end;

end.
