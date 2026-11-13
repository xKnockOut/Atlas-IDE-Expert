unit Atlas.Core.Tracker.LinkedStart;

// „Beginnen“ mit einem verknüpften Branch (#2138, issues.github.linkBranch),
// ohne VCL und Open Tools API; aus einem Hintergrund-Thread aufrufen.
// - Nur Git und ein Tracker, der IAtlasTrackerBranchLinker kann (GitHub).
// - Zeigt origin nicht auf das Repository des Trackers: Foreign. Kennt der
//   lokale Stand origin/<Branch> schon: Exists. Sonst legt der Tracker den
//   Branch an und verknüpft ihn (bzw. nennt den schon verknüpften).
// - Liegt der Branch auf dem Server: fetch origin und auschecken; Git legt
//   den lokalen Branch mit Upstream an (checkout mit Rateregel für Remotes).
// - Alles andere geht den lokalen Weg wie bisher; Run meldet, warum.

interface

uses
  Atlas.Core.Tracker.Contract,
  Atlas.Core.VersionControl.Contract;

type
  TAtlasLinkedStartRequest = record
    Vcs: IAtlasVersionControl;
    Linker: IAtlasTrackerBranchLinker;
    Call: TAtlasTrackerCall;
    Key: string;
    /// <summary>Branch nach Muster und Basis (issues.branchBase, sonst Hauptbranch).</summary>
    Branch: string;
    Base: string;
    /// <summary>URL des Remotes origin der Arbeitskopie; '' unbekannt.</summary>
    Origin: string;
  end;

  TAtlasLinkedStartResult = record
    Link: TAtlasTrackerBranchLink;
    /// <summary>Abruf bzw. Auschecken, nachdem der Branch auf dem Server lag; Ok sonst.</summary>
    Fetch: TAtlasVcsOutcome;
    /// <summary>Nach dem Auschecken: Hook-Ordner und Verwaltungsordner; sonst ''.</summary>
    Hooks: string;
    GitDir: string;
    class function Make(AOutcome: TAtlasTrackerBranchLinkOutcome; const ABranch: string): TAtlasLinkedStartResult;
      static;
    /// <summary>Vom Server ausgecheckt; sonst den lokalen Weg gehen.</summary>
    function CheckedOut: Boolean;
  end;

  TAtlasLinkedStart = class
  public const
    cOrigin = 'origin';
  public
    /// <summary>Verknüpften Branch anlegen bzw. finden, abrufen und auschecken (Link.Branch, Link.Base).
    /// </summary>
    class function Run(const ARequest: TAtlasLinkedStartRequest): TAtlasLinkedStartResult; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasLinkedStartResult }

class function TAtlasLinkedStartResult.Make(AOutcome: TAtlasTrackerBranchLinkOutcome;
  const ABranch: string): TAtlasLinkedStartResult;
begin
  Result.Link := TAtlasTrackerBranchLink.Make(AOutcome, ABranch);
  Result.Fetch := TAtlasVcsOutcome.Ok;
  Result.Hooks := '';
  Result.GitDir := '';
end;

function TAtlasLinkedStartResult.CheckedOut: Boolean;
begin
  Result := Link.OnServer and (Fetch = TAtlasVcsOutcome.Ok);
end;

{ TAtlasLinkedStart }

/// <summary>Was vor dem Tracker zu prüfen ist; False mit AResult, wenn es nicht weitergeht.</summary>
function Eligible(const ARequest: TAtlasLinkedStartRequest; out ABranching: IAtlasVcsBranching;
  out AResult: TAtlasLinkedStartResult): Boolean;
var
  mExists: Boolean;
begin
  AResult := TAtlasLinkedStartResult.Make(TAtlasTrackerBranchLinkOutcome.None, ARequest.Branch);
  Result := False;
  ABranching := nil;
  if (ARequest.Vcs = nil) or (ARequest.Linker = nil) or (ARequest.Vcs.Kind <> TAtlasVcsKind.Git) or
    not Supports(ARequest.Vcs, IAtlasVcsBranching, ABranching) then
  begin
    Exit;
  end;
  if not ARequest.Linker.SameRepository(ARequest.Call.Target, ARequest.Origin) then
  begin
    AResult.Link.Outcome := TAtlasTrackerBranchLinkOutcome.Foreign;
  end
  else if (ABranching.RemoteBranchExists(ARequest.Branch, mExists) = TAtlasVcsOutcome.Ok) and mExists then
  begin
    AResult.Link.Outcome := TAtlasTrackerBranchLinkOutcome.Exists;
  end
  else
  begin
    Result := True;
  end;
end;

class function TAtlasLinkedStart.Run(const ARequest: TAtlasLinkedStartRequest): TAtlasLinkedStartResult;
var
  mBranching: IAtlasVcsBranching;
  mIncoming: IAtlasVcsIncoming;
  mHooks, mGitDir: string;
begin
  if not Eligible(ARequest, mBranching, Result) then
  begin
    Exit;
  end;
  Result.Link := ARequest.Linker.LinkBranch(ARequest.Call, ARequest.Key, ARequest.Branch, ARequest.Base);
  if not Result.Link.OnServer then
  begin
    Exit;
  end;
  Result.Fetch := TAtlasVcsOutcome.Failed;
  if Supports(ARequest.Vcs, IAtlasVcsIncoming, mIncoming) then
  begin
    Result.Fetch := mIncoming.Fetch(cOrigin);
  end;
  if Result.Fetch = TAtlasVcsOutcome.Ok then
  begin
    Result.Fetch := mBranching.SwitchBranch(Result.Link.Branch);
  end;
  if Result.CheckedOut and (mBranching.HookFolders(mHooks, mGitDir) = TAtlasVcsOutcome.Ok) then
  begin
    Result.Hooks := mHooks;
    Result.GitDir := mGitDir;
  end;
end;

end.
