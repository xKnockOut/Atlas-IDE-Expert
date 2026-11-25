unit Atlas.IDE.VersionControl.Adapters.Dialogs;

// Dialoge der Versionsverwaltung für Base (#1891): TAtlasVcsDialogsAdapter erfüllt IAtlasVcsDialogs
// (Atlas.IDE.Base.Foundation.VersionControl) über TAtlasIdeBranching (Branch anlegen) und TAtlasIdeWorkingCopies
// (Arbeitskopien). Die Composition setzt ihn bei TAtlasIdeVcs ein, solange der Teil „Vcs“ läuft.

interface

uses
  System.SysUtils,
  Atlas.VersionControl.Repository.Contract,
  Atlas.VersionControl.Repository.BranchPlan,
  Atlas.IDE.Base.Foundation.VersionControl;

type
  /// <summary>IAtlasVcsDialogs über TAtlasIdeBranching und TAtlasIdeWorkingCopies.</summary>
  TAtlasVcsDialogsAdapter = class(TInterfacedObject, IAtlasVcsDialogs)
  public
    procedure CreateBranchFor(const AProject: string; const ADone: TProc);
    procedure ShowWorkingCopies(const AProject: string; const ADone: TProc);
    function AskBranch(const AAsk: TAtlasVcsBranchAsk; out ARequest: TAtlasVcsBranchRequest;
      out ANeverAsk: Boolean): Boolean;
    function SvnOptions(const AProject: string): TAtlasVcsSvnBranchOptions;
    function GitOptions: TAtlasVcsGitBranchOptions;
    procedure OfferOpen(const AProject, ARoot, AFolder: string);
    function ServerState(AOutcome: TAtlasVcsOutcome): string;
    function AskLocal(const AFacts: TAtlasVcsBranchFacts; const ARequest: TAtlasVcsBranchRequest;
      const ASteps: TArray<TAtlasVcsBranchStep>; const ARun: TAtlasVcsBranchRun;
      out AFallback: TAtlasVcsBranchRequest): Boolean;
    function AskUncommitted(AChanges: Integer; const AName: string; out AStash: Boolean): Boolean;
    function WorktreeProject(const AProject, ARoot, AFolder: string): string;
    function OfferWorktree(const AName, AFolder, ATarget: string): Boolean;
    procedure StopAsking;
    procedure RebuildIndex;
    function Progress(AKind: TAtlasVcsKind): TAtlasVcsBranchProgress;
    function FailureText(AKind: TAtlasVcsKind; const ASteps: TArray<TAtlasVcsBranchStep>;
      const ARun: TAtlasVcsBranchRun): string;
  end;

implementation

uses
  Atlas.IDE.VersionControl.Branching,
  Atlas.IDE.VersionControl.WorkingCopies;

{ TAtlasVcsDialogsAdapter }

procedure TAtlasVcsDialogsAdapter.CreateBranchFor(const AProject: string; const ADone: TProc);
begin
  TAtlasIdeBranching.CreateFor(AProject, ADone);
end;

procedure TAtlasVcsDialogsAdapter.ShowWorkingCopies(const AProject: string; const ADone: TProc);
begin
  TAtlasIdeWorkingCopies.ShowFor(AProject, ADone);
end;

function TAtlasVcsDialogsAdapter.AskBranch(const AAsk: TAtlasVcsBranchAsk; out ARequest: TAtlasVcsBranchRequest;
  out ANeverAsk: Boolean): Boolean;
begin
  Result := TAtlasIdeBranching.Ask(AAsk.Folder, AAsk.Facts, TAtlasIdeBranching.Setup(AAsk.Name, AAsk.Message,
    AAsk.Key, AAsk.Svn, AAsk.OfferNeverAsk), ARequest, ANeverAsk);
end;

function TAtlasVcsDialogsAdapter.SvnOptions(const AProject: string): TAtlasVcsSvnBranchOptions;
begin
  Result := TAtlasIdeBranching.SvnOptions(AProject);
end;

function TAtlasVcsDialogsAdapter.GitOptions: TAtlasVcsGitBranchOptions;
begin
  Result := TAtlasIdeBranching.GitOptions;
end;

procedure TAtlasVcsDialogsAdapter.OfferOpen(const AProject, ARoot, AFolder: string);
begin
  TAtlasIdeBranching.OfferOpen(AProject, ARoot, AFolder);
end;

function TAtlasVcsDialogsAdapter.ServerState(AOutcome: TAtlasVcsOutcome): string;
begin
  Result := TAtlasIdeBranching.ServerState(AOutcome);
end;

function TAtlasVcsDialogsAdapter.AskLocal(const AFacts: TAtlasVcsBranchFacts; const ARequest: TAtlasVcsBranchRequest;
  const ASteps: TArray<TAtlasVcsBranchStep>; const ARun: TAtlasVcsBranchRun;
  out AFallback: TAtlasVcsBranchRequest): Boolean;
begin
  Result := TAtlasIdeBranching.AskLocal(AFacts, ARequest, ASteps, ARun, AFallback);
end;

function TAtlasVcsDialogsAdapter.AskUncommitted(AChanges: Integer; const AName: string; out AStash: Boolean): Boolean;
begin
  Result := TAtlasIdeBranching.AskUncommitted(AChanges, AName, AStash);
end;

function TAtlasVcsDialogsAdapter.WorktreeProject(const AProject, ARoot, AFolder: string): string;
begin
  Result := TAtlasIdeBranching.WorktreeProject(AProject, ARoot, AFolder);
end;

function TAtlasVcsDialogsAdapter.OfferWorktree(const AName, AFolder, ATarget: string): Boolean;
begin
  Result := TAtlasIdeBranching.OfferWorktree(AName, AFolder, ATarget);
end;

procedure TAtlasVcsDialogsAdapter.StopAsking;
begin
  TAtlasIdeBranching.StopAsking;
end;

procedure TAtlasVcsDialogsAdapter.RebuildIndex;
begin
  TAtlasIdeBranching.RebuildIndex;
end;

function TAtlasVcsDialogsAdapter.Progress(AKind: TAtlasVcsKind): TAtlasVcsBranchProgress;
begin
  Result := TAtlasIdeBranching.Progress(AKind);
end;

function TAtlasVcsDialogsAdapter.FailureText(AKind: TAtlasVcsKind; const ASteps: TArray<TAtlasVcsBranchStep>;
  const ARun: TAtlasVcsBranchRun): string;
begin
  Result := TAtlasIdeBranching.FailureText(AKind, ASteps, ARun);
end;

end.
