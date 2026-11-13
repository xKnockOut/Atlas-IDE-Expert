unit Atlas.IDE.Tracker.Review;

// „Prüfen“ (#2126): Branch eines Issues auschecken, bauen, die betroffenen
// Tests ausführen und das Ergebnis in den Tracker schreiben; danach zurück auf
// den eigenen Stand. Dialog: Atlas.UI.Tracker.ReviewDialog (nicht modal).
// - Eigener Stand: Arbeitsstand des aktiven Issues sichern (IAtlasIssueWork,
//   #2052), eigenen Branch aus dem Stand der Arbeitskopie merken.
// - Im Hintergrund: Stand, lokale Änderungen und alle Branches; Kandidaten aus
//   Muster und Kennung (TAtlasTrackerReview.Candidates). Bei genau einem
//   wechselt Atlas gleich, sonst wählt der Benutzer im Dialog.
// - Build über IAtlasBuildRequests des Moduls Build-Pipeline (aktive
//   Konfiguration, issues.reviewBuild), danach der Befehl
//   Atlas.RunAffectedTests; das Ende meldet das Modul Tests über
//   IAtlasTestsListener (dieses Objekt, angemeldet in Atlas.IDE.Tracker.Parts).
// - „Senden“ schreibt über TAtlasIdeTrackerSync.Apply. Der Rückweg wechselt auf
//   den eigenen Branch und stellt den Arbeitsstand ohne Rückfrage her.
// - Regel 3: Nach Stop erreicht kein Rückruf mehr den Ablauf (FStopped,
//   Laufnummer, Forget beim Build); der Dialog schließt.
// Hauptthread; Versionsverwaltung im Hintergrund (TAtlasIdeVcs.Run). Protokoll
// ohne Kennung, Branch oder Pfad.

interface

uses
  System.SysUtils,
  Atlas.Core.Build.Requests,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Development,
  Atlas.Core.Tracker.MyIssues,
  Atlas.Core.Tracker.Review,
  Atlas.Core.VersionControl.Contract,
  Atlas.IDE.Contracts.Tests,
  Atlas.IDE.Tracker.IssuesContext,
  Atlas.IDE.Tracker.Workflow,
  Atlas.UI.Tracker.EndDialog,
  Atlas.UI.Tracker.ReviewDialog;

type
  /// <summary>Was der Hintergrund über die Arbeitskopie herausfindet.</summary>
  TAtlasReviewInspection = record
    Kind: TAtlasVcsKind;
    Head: TAtlasVcsHead;
    /// <summary>Lokale Änderungen der Arbeitskopie.</summary>
    Changes: Integer;
    /// <summary>Branches des Issues (Muster, dann Kennung).</summary>
    Candidates: TArray<string>;
    /// <summary>Alle Branches, wenn keiner die Kennung trägt.</summary>
    Choices: TArray<string>;
    /// <summary>Im Hintergrund: Stand, Änderungen und Branches von AFolder; Kandidaten nach Muster aus AOptions
    /// und nach der Kennung aus ARequest.</summary>
    procedure Inspect(const AFolder: string; const ARequest: TAtlasIssueDevelopmentRequest;
      const AOptions: TAtlasIssuesOptions; const AIssue: TAtlasTrackerIssue);
  end;

  TAtlasIdeIssueReview = class(TInterfacedObject, IAtlasTestsListener)
  public const
    /// <summary>Befehl des Moduls Tests: betroffene Tests des aktiven Projekts ausführen (#1353).</summary>
    cAffectedTests = 'Atlas.RunAffectedTests';
  private
    FContext: TAtlasIdeIssuesContext;
    FSync: TAtlasIdeTrackerSync;
    FDialog: TAtlasTrackerReviewDialog;
    FState: TAtlasReviewState;
    FInspection: TAtlasReviewInspection;
    FProject: string;
    FFolder: string;
    FTarget: TAtlasTrackerTarget;
    FRun: Integer;
    FStopped: Boolean;
    function Current(ARun: Integer): Boolean;
    procedure OpenDialog;
    function DialogEvents: TAtlasReviewDialogEvents;
    procedure ReadStates;
    procedure Inspect(const AIssue: TAtlasTrackerIssue; const AOptions: TAtlasIssuesOptions);
    procedure Inspected(const AInspection: TAtlasReviewInspection);
    procedure AskBranch;
    procedure Switch(const ABranch: string);
    procedure Switched(AOutcome: TAtlasVcsOutcome);
    procedure StartBuild;
    procedure NotBuilt(const AReason: string);
    procedure BuildDone(const AReport: TAtlasBuildReport; const AError: string);
    procedure StartTests;
    procedure Send(const AChange: TAtlasTrackerWrite; const ADone: TAtlasTrackerSendDone);
    procedure Closed(AReturn: Boolean);
    procedure GoBack(const AState: TAtlasReviewState);
    procedure WentBack(const AState: TAtlasReviewState; AOutcome: TAtlasVcsOutcome);
    procedure ShowState;
    procedure CloseDialog;
    procedure Moved;
    function BuildProject: string;
  public
    /// <summary>AContext und ASync (nicht nil) gehören „Meine Issues“ und leben bis Stop.</summary>
    constructor Create(AContext: TAtlasIdeIssuesContext; ASync: TAtlasIdeTrackerSync);
    /// <summary>„Prüfen“ für AIssue im Projekt des Bereichs; läuft schon eine Prüfung, kommt ihr Dialog nach vorn.
    /// </summary>
    procedure Review(const AIssue: TAtlasTrackerIssue; const AOptions: TAtlasIssuesOptions);
    /// <summary>Beim Stoppen: Dialog schließen, Build vergessen; danach wirkungslos.</summary>
    procedure Stop;
    /// <summary>Als IAtlasTestsListener in AScope anmelden (Ende der betroffenen Tests).</summary>
    function ProvideIn(const AScope: IAtlasModuleScope): IAtlasRegistration;
    /// <summary>Ist der Dialog offen?</summary>
    function Busy: Boolean;
    { IAtlasTestsListener }
    procedure TestsFinished(const ATestProject: string; APassed, AFailed: Integer);
  end;

implementation

uses
  System.UITypes,
  Vcl.Dialogs,
  Atlas.Core.Build.Events,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.Contributions,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Tracker.CommentEditor,
  Atlas.Core.VersionControl.BranchPlan,
  Atlas.IDE.Contracts.BuildRequests,
  Atlas.IDE.Contracts.VersionControl,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Tracker.IssueWorkLink,
  Atlas.IDE.Tracker.WorkingCopies,
  Atlas.UI.Tracker.Workflow.Strings;

const
  /// <summary>Zeitlimit je Aufruf der Versionsverwaltung.</summary>
  cVcsTimeoutMs = 30000;
  cProjectExtension = '.dproj';
  cLogReview = 'Review: %s, %d candidates';
  cLogBack = 'Review: back %s';

/// <summary>Builds des Moduls Build-Pipeline; nil, solange es fehlt oder nicht läuft.</summary>
function BuildRequests: IAtlasBuildRequests;
var
  mItem: IInterface;
begin
  Result := nil;
  for mItem in TAtlasModuleContributions.Active(AtlasModuleRegistry, IAtlasBuildRequests) do
  begin
    if Supports(mItem, IAtlasBuildRequests, Result) then
    begin
      Exit;
    end;
  end;
end;

/// <summary>Gibt es den Befehl AId in der Palette (Modul Tests geladen)?</summary>
function HasCommand(const AId: string): Boolean;
var
  mCommand: TAtlasCommand;
begin
  Result := False;
  for mCommand in TAtlasIdeHost.PaletteCommands do
  begin
    if SameText(mCommand.Id, AId) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Im Hintergrund auf ABranch wechseln; Failed ohne Versionsverwaltung.</summary>
function SwitchTo(const AFolder, ABranch: string; const ASvn: TAtlasVcsSvnBranchOptions): TAtlasVcsOutcome;
var
  mBranching: IAtlasVcsBranching;
begin
  Result := TAtlasVcsOutcome.Failed;
  if Supports(TAtlasIdeVcs.ForFolder(AFolder, TAtlasIdeVcs.AtLeast(cVcsTimeoutMs)), IAtlasVcsBranching,
    mBranching) then
  begin
    Result := mBranching.SwitchBranch(ABranch, ASvn);
  end;
end;

{ TAtlasReviewInspection }

procedure TAtlasReviewInspection.Inspect(const AFolder: string; const ARequest: TAtlasIssueDevelopmentRequest;
  const AOptions: TAtlasIssuesOptions; const AIssue: TAtlasTrackerIssue);
var
  mVcs: IAtlasVersionControl;
  mHistory: IAtlasVcsHistory;
  mItems: TArray<TAtlasVcsChange>;
  mRefs: TArray<TAtlasVcsRef>;
  mOptions: TAtlasIssuesOptions;
  mPlan: TAtlasIssueStartPlan;
begin
  mVcs := TAtlasIdeVcs.ForFolder(AFolder, TAtlasIdeVcs.AtLeast(cVcsTimeoutMs));
  if mVcs = nil then
  begin
    Exit;
  end;
  Kind := mVcs.Kind;
  if mVcs.Head(Head) <> TAtlasVcsOutcome.Ok then
  begin
    Head := TAtlasVcsHead.Empty;
  end;
  if mVcs.Changes(mItems) = TAtlasVcsOutcome.Ok then
  begin
    Changes := TAtlasVcsBranchPlan.LocalChanges(mItems);
  end;
  if not Supports(mVcs, IAtlasVcsHistory, mHistory) or (mHistory.AllBranches(mRefs) <> TAtlasVcsOutcome.Ok) then
  begin
    Exit;
  end;
  // Branch nach Muster (issues.branchPattern), auch wenn issues.start „merken“ sagt.
  mOptions := AOptions;
  mOptions.Start := TAtlasIssueStart.Branch;
  mPlan := TAtlasMyIssues.PlanStart(Kind, mOptions, AIssue);
  if not mPlan.Valid then
  begin
    mPlan.Branch := '';
  end;
  Candidates := TAtlasTrackerReview.Candidates(ARequest, mPlan.Branch, mRefs);
  Choices := TAtlasTrackerReview.AllBranches(mRefs);
end;

{ TAtlasIdeIssueReview }

constructor TAtlasIdeIssueReview.Create(AContext: TAtlasIdeIssuesContext; ASync: TAtlasIdeTrackerSync);
begin
  inherited Create;
  FContext := AContext;
  FSync := ASync;
end;

function TAtlasIdeIssueReview.Current(ARun: Integer): Boolean;
begin
  Result := not FStopped and (FRun = ARun) and (FDialog <> nil);
end;

function TAtlasIdeIssueReview.Busy: Boolean;
begin
  Result := FDialog <> nil;
end;

function TAtlasIdeIssueReview.ProvideIn(const AScope: IAtlasModuleScope): IAtlasRegistration;
begin
  Result := AScope.Provide(IAtlasTestsListener, Self as IAtlasTestsListener);
end;

procedure TAtlasIdeIssueReview.Review(const AIssue: TAtlasTrackerIssue; const AOptions: TAtlasIssuesOptions);
begin
  if FStopped or (AIssue.Key = '') then
  begin
    Exit;
  end;
  if FDialog <> nil then
  begin
    FDialog.Show;
    if not SameText(FState.Key, AIssue.Key) then
    begin
      FDialog.ShowNote(TAtlasWorkflowStrings.Fmt(TAtlasWorkflowTextId.TrackerReviewBusy, [FState.Key]));
    end;
    Exit;
  end;
  FProject := FContext.Selection.CurrentProject;
  if FProject = '' then
  begin
    Exit;
  end;
  FFolder := TAtlasIdeTrackerWorkingCopies.FolderOf(FProject);
  FTarget := FContext.TargetOf(FProject);
  FInspection := Default(TAtlasReviewInspection);
  Inc(FRun);
  // Eigener Stand (#2052): Arbeitsstand des aktiven Issues sichern, bevor der Branch wechselt.
  TAtlasTrackerIssueWorkLink.BeforeStart(FContext, FProject, AIssue.Key);
  FState := TAtlasReviewState.Create(AIssue.Key, TAtlasIdeSettings.Current.IssuesReviewBuild);
  FState.OwnKey := TAtlasTrackerIssueWorkLink.ActiveKey(FContext, FProject);
  if SameText(FState.OwnKey, AIssue.Key) then
  begin
    FState.OwnKey := '';
  end;
  FState.Marks[TAtlasReviewStep.Saved] := TAtlasReviewMark.Running;
  OpenDialog;
  Inspect(AIssue, AOptions);
end;

procedure TAtlasIdeIssueReview.OpenDialog;
var
  mAssist: IAtlasCommentAssist;
begin
  FDialog := TAtlasTrackerReviewDialog.CreateDialog(nil, FState, TAtlasIdeTrackerSync.Options(FTarget),
    TAtlasTrackerReview.CommentFor(TAtlasIdeSettings.Current.IssuesReviewComment, TAtlasWorkflowStrings.English));
  FDialog.Events := DialogEvents;
  // Kommentar-Editor (#1278) mit eigenem Entwurfsfeld; die Vorlage ist kein Entwurf.
  mAssist := nil;
  if Assigned(FSync.CommentAssist) then
  begin
    mAssist := FSync.CommentAssist(FTarget, FState.Key, TAtlasCommentDrafts.cFieldReview);
  end;
  FDialog.Parts.Editor.Enhanced := mAssist <> nil;
  FDialog.Parts.Editor.Bind(mAssist);
  FDialog.Show;
  ReadStates;
end;

function TAtlasIdeIssueReview.DialogEvents: TAtlasReviewDialogEvents;
var
  mKeep: IInterface;
  mOwner: TAtlasIdeIssueReview;
  mRun: Integer;
begin
  // Die Ereignisse halten das Objekt, bis der Dialog sie löst (Schließen, Stop).
  mKeep := Self;
  mOwner := Self;
  mRun := FRun;
  Result.Switch :=
    procedure(ABranch: string)
    begin
      if (mKeep <> nil) and mOwner.Current(mRun) then
      begin
        mOwner.Switch(ABranch);
      end;
    end;
  Result.Send :=
    procedure(const AChange: TAtlasTrackerWrite; const ADone: TAtlasTrackerSendDone)
    begin
      if (mKeep <> nil) and mOwner.Current(mRun) then
      begin
        mOwner.Send(AChange, ADone);
      end;
    end;
  Result.Closed :=
    procedure(AReturn: Boolean)
    begin
      if (mKeep <> nil) and mOwner.Current(mRun) then
      begin
        mOwner.Closed(AReturn);
      end;
    end;
end;

procedure TAtlasIdeIssueReview.ReadStates;
var
  mKeep: IInterface;
  mOwner: TAtlasIdeIssueReview;
  mRun: Integer;
begin
  mKeep := Self;
  mOwner := Self;
  mRun := FRun;
  FSync.ReadStates(FContext.ProviderOf(FTarget.Provider), FTarget, FState.Key,
    procedure(const AStates: TArray<string>; const ARules: TAtlasTrackerStateRules)
    begin
      if (mKeep <> nil) and mOwner.Current(mRun) then
      begin
        mOwner.FDialog.SetStates(AStates, ARules);
      end;
    end);
end;

procedure TAtlasIdeIssueReview.Inspect(const AIssue: TAtlasTrackerIssue; const AOptions: TAtlasIssuesOptions);
var
  mKeep: IInterface;
  mOwner: TAtlasIdeIssueReview;
  mRun: Integer;
  mFound: TAtlasReviewInspection;
  mFolder: string;
  mRequest: TAtlasIssueDevelopmentRequest;
  mOptions: TAtlasIssuesOptions;
  mIssue: TAtlasTrackerIssue;
begin
  mKeep := Self;
  mOwner := Self;
  mRun := FRun;
  mFound := Default(TAtlasReviewInspection);
  mFolder := FFolder;
  mRequest := TAtlasIssueDevelopmentRequest.Create(FTarget.Provider, FTarget.Project, AIssue.Key, nil, nil);
  mOptions := AOptions;
  mIssue := AIssue;
  if not TAtlasIdeVcs.Run(
    procedure
    begin
      mFound.Inspect(mFolder, mRequest, mOptions, mIssue);
    end,
    procedure
    begin
      if (mKeep <> nil) and mOwner.Current(mRun) then
      begin
        mOwner.Inspected(mFound);
      end;
    end) then
  begin
    Inspected(mFound);
  end;
end;

procedure TAtlasIdeIssueReview.Inspected(const AInspection: TAtlasReviewInspection);
begin
  FInspection := AInspection;
  TAtlasGuard.Log(Format(cLogReview, [AtlasVcsKindName(AInspection.Kind), Length(AInspection.Candidates)],
    TFormatSettings.Invariant));
  if AInspection.Kind = TAtlasVcsKind.None then
  begin
    // Ohne Git oder SVN: nichts zu wechseln; Ergebnis und Kommentar gehen trotzdem.
    FState.Marks[TAtlasReviewStep.Saved] := TAtlasReviewMark.Skipped;
    FState.Marks[TAtlasReviewStep.Switched] := TAtlasReviewMark.Skipped;
    FState.Marks[TAtlasReviewStep.Build] := TAtlasReviewMark.Skipped;
    FState.Marks[TAtlasReviewStep.Tests] := TAtlasReviewMark.Skipped;
    ShowState;
    FDialog.ShowNote(TAtlasWorkflowStrings.Text(TAtlasWorkflowTextId.TrackerReviewNoVcs));
    Exit;
  end;
  FState.OwnBranch := TAtlasTrackerReview.ReturnName(AInspection.Kind, AInspection.Head);
  FState.Marks[TAtlasReviewStep.Saved] := TAtlasReviewMark.Done;
  if Length(AInspection.Candidates) = 1 then
  begin
    Switch(AInspection.Candidates[0]);
  end
  else
  begin
    ShowState;
    AskBranch;
  end;
end;

procedure TAtlasIdeIssueReview.AskBranch;
begin
  if Length(FInspection.Candidates) > 0 then
  begin
    FDialog.AskBranch(FInspection.Candidates, False);
  end
  else
  begin
    FDialog.AskBranch(FInspection.Choices, True);
  end;
end;

procedure TAtlasIdeIssueReview.Switch(const ABranch: string);
var
  mKeep: IInterface;
  mOwner: TAtlasIdeIssueReview;
  mRun: Integer;
  mFolder, mBranch: string;
  mSvn: TAtlasVcsSvnBranchOptions;
  mOutcome: TAtlasVcsOutcome;
begin
  // Lokale Änderungen: vorher fragen (Git nimmt sie mit, wenn sie nicht kollidieren).
  if (FInspection.Changes > 0) and (MessageDlg(TAtlasWorkflowStrings.Fmt(TAtlasWorkflowTextId.WelcomeIssuesLocalChanges,
    [FInspection.Changes, ABranch, sLineBreak + sLineBreak]), mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then
  begin
    AskBranch;
    Exit;
  end;
  FState.Branch := ABranch;
  FState.SwitchError := '';
  FState.Marks[TAtlasReviewStep.Switched] := TAtlasReviewMark.Running;
  ShowState;
  mKeep := Self;
  mOwner := Self;
  mRun := FRun;
  mFolder := FFolder;
  mBranch := ABranch;
  mSvn := TAtlasIdeVcs.Dialogs.SvnOptions(FProject);
  mOutcome := TAtlasVcsOutcome.Failed;
  if not TAtlasIdeVcs.Run(
    procedure
    begin
      mOutcome := SwitchTo(mFolder, mBranch, mSvn);
    end,
    procedure
    begin
      if (mKeep <> nil) and mOwner.Current(mRun) then
      begin
        mOwner.Switched(mOutcome);
      end;
    end) then
  begin
    Switched(mOutcome);
  end;
end;

procedure TAtlasIdeIssueReview.Switched(AOutcome: TAtlasVcsOutcome);
begin
  if AOutcome <> TAtlasVcsOutcome.Ok then
  begin
    // Gescheitert: Grund in der Zeile, einen anderen Branch wählen lassen.
    FState.Marks[TAtlasReviewStep.Switched] := TAtlasReviewMark.Failed;
    FState.SwitchError := AtlasVcsOutcomeName(AOutcome);
    ShowState;
    AskBranch;
    Exit;
  end;
  FState.Marks[TAtlasReviewStep.Switched] := TAtlasReviewMark.Done;
  FInspection.Changes := 0;
  Moved;
  ShowState;
  StartBuild;
end;

/// <summary>Branch gewechselt: Stand und Willkommensseite neu abfragen.</summary>
procedure TAtlasIdeIssueReview.Moved;
begin
  FContext.Selection.ForgetHead(FFolder);
  if FContext.Welcome <> nil then
  begin
    FContext.Welcome.Refresh(FProject);
  end;
  FContext.Changed;
end;

function TAtlasIdeIssueReview.BuildProject: string;
begin
  // Ein Ordner als Tracker-Projekt (#1927) lässt sich nicht bauen: dann das aktive Projekt der IDE.
  Result := FProject;
  if not SameText(ExtractFileExt(Result), cProjectExtension) then
  begin
    Result := TAtlasIdeFiles.ActiveProjectFile;
  end;
  if not SameText(ExtractFileExt(Result), cProjectExtension) then
  begin
    Result := '';
  end;
end;

procedure TAtlasIdeIssueReview.StartBuild;
var
  mRequests: IAtlasBuildRequests;
  mRequest: TAtlasBuildRequest;
  mKeep: IInterface;
  mOwner: TAtlasIdeIssueReview;
  mRun: Integer;
  mReason: string;
begin
  if FState.Marks[TAtlasReviewStep.Build] <> TAtlasReviewMark.Waiting then
  begin
    Exit;
  end;
  mRequests := BuildRequests;
  mRequest := Default(TAtlasBuildRequest);
  mRequest.Id := FState.Key;
  mRequest.Project := BuildProject;
  mRequest.Kind := TAtlasCompileKind.Make;
  if (mRequests = nil) or (mRequest.Project = '') then
  begin
    NotBuilt('');
    Exit;
  end;
  FState.Marks[TAtlasReviewStep.Build] := TAtlasReviewMark.Running;
  ShowState;
  mKeep := Self;
  mOwner := Self;
  mRun := FRun;
  if not mRequests.Start(mRequest, TAtlasTrackerReview.cRequestedBy,
    procedure(const AReport: TAtlasBuildReport; const AError: string)
    begin
      if (mKeep <> nil) and mOwner.Current(mRun) then
      begin
        mOwner.BuildDone(AReport, AError);
      end;
    end, mReason) then
  begin
    NotBuilt(mReason);
  end;
end;

procedure TAtlasIdeIssueReview.NotBuilt(const AReason: string);
begin
  // Ohne Ergebnis: „Build nicht gestartet“, die Tests entfallen.
  FState.Built(Default(TAtlasReviewBuild));
  ShowState;
  if AReason <> '' then
  begin
    FDialog.ShowNote(AReason);
  end;
end;

procedure TAtlasIdeIssueReview.BuildDone(const AReport: TAtlasBuildReport; const AError: string);
begin
  if AError <> '' then
  begin
    NotBuilt(AError);
    Exit;
  end;
  FState.Built(TAtlasTrackerReview.BuildOf(AReport));
  ShowState;
  StartTests;
end;

procedure TAtlasIdeIssueReview.StartTests;
begin
  if FState.Marks[TAtlasReviewStep.Tests] <> TAtlasReviewMark.Waiting then
  begin
    Exit;
  end;
  // Ohne Modul Tests gibt es den Befehl nicht: ausgelassen.
  if not HasCommand(cAffectedTests) then
  begin
    FState.Marks[TAtlasReviewStep.Tests] := TAtlasReviewMark.Skipped;
    ShowState;
    Exit;
  end;
  FState.Marks[TAtlasReviewStep.Tests] := TAtlasReviewMark.Running;
  ShowState;
  TAtlasIdeHost.ExecuteCommand(cAffectedTests);
end;

procedure TAtlasIdeIssueReview.TestsFinished(const ATestProject: string; APassed, AFailed: Integer);
begin
  if FStopped or (FDialog = nil) or (FState.Marks[TAtlasReviewStep.Tests] <> TAtlasReviewMark.Running) then
  begin
    Exit;
  end;
  FState.Tested(APassed, AFailed);
  ShowState;
end;

procedure TAtlasIdeIssueReview.Send(const AChange: TAtlasTrackerWrite; const ADone: TAtlasTrackerSendDone);
var
  mKeep: IInterface;
  mOwner: TAtlasIdeIssueReview;
  mRun: Integer;
  mDone: TAtlasTrackerSendDone;
begin
  mKeep := Self;
  mOwner := Self;
  mRun := FRun;
  mDone := ADone;
  FSync.Apply(FContext.ProviderOf(FTarget.Provider), FTarget, FState.Key, AChange,
    procedure(const AResult: TAtlasTrackerWriteResult)
    begin
      if (mKeep <> nil) and mOwner.Current(mRun) then
      begin
        mDone(AResult);
      end;
    end);
end;

procedure TAtlasIdeIssueReview.Closed(AReturn: Boolean);
var
  mState: TAtlasReviewState;
begin
  mState := FState;
  // Der Dialog gibt sich selbst frei (caFree).
  FDialog := nil;
  Inc(FRun);
  FContext.Report(TAtlasWorkflowStrings.Fmt(TAtlasWorkflowTextId.TrackerReviewDone, [mState.Key,
    TAtlasTrackerReviewDialog.BuildText(mState) + ', ' + TAtlasTrackerReviewDialog.TestsText(mState)]));
  if AReturn and mState.CanReturn then
  begin
    GoBack(mState);
  end;
end;

procedure TAtlasIdeIssueReview.GoBack(const AState: TAtlasReviewState);
var
  mKeep: IInterface;
  mOwner: TAtlasIdeIssueReview;
  mState: TAtlasReviewState;
  mFolder: string;
  mSvn: TAtlasVcsSvnBranchOptions;
  mOutcome: TAtlasVcsOutcome;
begin
  mKeep := Self;
  mOwner := Self;
  mState := AState;
  mFolder := FFolder;
  mSvn := TAtlasIdeVcs.Dialogs.SvnOptions(FProject);
  mOutcome := TAtlasVcsOutcome.Failed;
  if not TAtlasIdeVcs.Run(
    procedure
    begin
      mOutcome := SwitchTo(mFolder, mState.OwnBranch, mSvn);
    end,
    procedure
    begin
      if (mKeep <> nil) and not mOwner.FStopped then
      begin
        mOwner.WentBack(mState, mOutcome);
      end;
    end) then
  begin
    WentBack(mState, mOutcome);
  end;
end;

procedure TAtlasIdeIssueReview.WentBack(const AState: TAtlasReviewState; AOutcome: TAtlasVcsOutcome);
begin
  TAtlasGuard.Log(Format(cLogBack, [AtlasVcsOutcomeName(AOutcome)], TFormatSettings.Invariant));
  if AOutcome <> TAtlasVcsOutcome.Ok then
  begin
    FContext.Report(TAtlasWorkflowStrings.Fmt(TAtlasWorkflowTextId.TrackerReviewBackFailed, [AState.OwnBranch,
      AtlasVcsOutcomeName(AOutcome)]));
    Exit;
  end;
  Moved;
  FContext.Report(TAtlasWorkflowStrings.Fmt(TAtlasWorkflowTextId.TrackerReviewBackDone, [AState.OwnBranch]));
  // Arbeitsstand des eigenen Issues ohne Rückfrage zurück (#2052).
  if AState.OwnKey <> '' then
  begin
    TAtlasTrackerIssueWorkLink.AfterResume(FProject, AState.OwnKey);
  end;
end;

procedure TAtlasIdeIssueReview.ShowState;
begin
  if FDialog <> nil then
  begin
    FDialog.ShowState(FState);
  end;
end;

procedure TAtlasIdeIssueReview.CloseDialog;
var
  mDialog: TAtlasTrackerReviewDialog;
begin
  mDialog := FDialog;
  FDialog := nil;
  if mDialog <> nil then
  begin
    // Ohne Ereignisse schließen: Closed ruft nicht mehr zurück.
    mDialog.Events := Default(TAtlasReviewDialogEvents);
    mDialog.Free;
  end;
end;

procedure TAtlasIdeIssueReview.Stop;
var
  mRequests: IAtlasBuildRequests;
begin
  FStopped := True;
  Inc(FRun);
  // Ein laufender Build ruft danach nicht mehr zurück (Regel 3).
  mRequests := BuildRequests;
  if mRequests <> nil then
  begin
    mRequests.Forget(TAtlasTrackerReview.cRequestedBy);
  end;
  CloseDialog;
end;

end.
