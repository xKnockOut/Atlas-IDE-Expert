unit Atlas.IDE.Tracker.LinkedStart;

// Verknüpfter Branch beim „Beginnen“ in der IDE (#2138), für
// Atlas.IDE.Tracker.IssueStart:
// - Setup im Hauptthread: issues.github.linkBranch (auch je Verbindung) und
//   ein Tracker, der IAtlasTrackerBranchLinker kann; sonst nichts.
// - Run im Hintergrund: Transport mit dem Token aus dem Anmeldespeicher,
//   origin aus .git/config, Versionsverwaltung des Ordners; dann
//   TAtlasLinkedStart.
// - Report: die Zeile für die Meldungen mit Grund.

interface

uses
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.LinkedStart,
  Atlas.IDE.Tracker.IssuesContext;

type
  /// <summary>Ergebnis von Run; hier benannt, damit „Beginnen“ nur diese Unit braucht.</summary>
  TAtlasIdeLinkedResult = TAtlasLinkedStartResult;

  /// <summary>Was „Beginnen“ für den verknüpften Branch braucht; Linker nil = aus.</summary>
  TAtlasIdeLinkSetup = record
    Linker: IAtlasTrackerBranchLinker;
    Provider: IAtlasTrackerProvider;
    Target: TAtlasTrackerTarget;
    Transports: TAtlasTrackerTransportHook;
    function Active: Boolean;
  end;

  TAtlasIdeLinkedStart = class
  public const
    /// <summary>Zeitlimit je Anfrage an den Tracker bzw. die Versionsverwaltung.</summary>
    cTrackerTimeoutMs = 15000;
    cVcsTimeoutMs = 30000;
  public
    /// <summary>Im Hauptthread: eingeschaltet für das Tracker-Ziel von AProject?</summary>
    class function Setup(AContext: TAtlasIdeIssuesContext; const AProject: string): TAtlasIdeLinkSetup; static;
    /// <summary>Im Hintergrund: Branch ABranch für AKey in der Arbeitskopie AFolder von ABase anlegen bzw. den
    /// verknüpften finden, abrufen und auschecken.</summary>
    class function Run(const ASetup: TAtlasIdeLinkSetup; const AFolder, AKey, ABranch,
      ABase: string): TAtlasIdeLinkedResult; static;
    /// <summary>Zeile für die Meldungen; '' ohne Versuch.</summary>
    class function Report(const ASetup: TAtlasIdeLinkSetup; const AKey: string;
      const AResult: TAtlasIdeLinkedResult): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.VersionControl.Contract,
  Atlas.IDE.Contracts.VersionControl,
  Atlas.IDE.Tracker.PathSuggestions,
  Atlas.IDE.Tracker.Workflow,
  Atlas.UI.Tracker.GitHubStrings,
  Atlas.UI.Tracker.MyIssues.Text;

{ TAtlasIdeLinkSetup }

function TAtlasIdeLinkSetup.Active: Boolean;
begin
  Result := Linker <> nil;
end;

{ TAtlasIdeLinkedStart }

class function TAtlasIdeLinkedStart.Setup(AContext: TAtlasIdeIssuesContext;
  const AProject: string): TAtlasIdeLinkSetup;
begin
  Result := Default(TAtlasIdeLinkSetup);
  Result.Target := AContext.TargetOf(AProject);
  if not Result.Target.Configured or not TAtlasIdeTrackerSync.Options(Result.Target).GitHub.LinkBranch then
  begin
    Exit;
  end;
  Result.Provider := AContext.ProviderOf(Result.Target.Provider);
  if Supports(Result.Provider, IAtlasTrackerBranchLinker, Result.Linker) then
  begin
    Result.Transports := AContext.Hooks.Transport;
  end;
end;

class function TAtlasIdeLinkedStart.Run(const ASetup: TAtlasIdeLinkSetup; const AFolder, AKey, ABranch,
  ABase: string): TAtlasIdeLinkedResult;
var
  mRequest: TAtlasLinkedStartRequest;
  mTransport: IAtlasCiTransport;
begin
  mTransport := nil;
  if Assigned(ASetup.Transports) then
  begin
    mTransport := ASetup.Transports(ASetup.Provider, ASetup.Target);
  end;
  mRequest := Default(TAtlasLinkedStartRequest);
  mRequest.Vcs := TAtlasIdeVcs.ForFolder(AFolder, TAtlasIdeVcs.AtLeast(cVcsTimeoutMs));
  mRequest.Linker := ASetup.Linker;
  mRequest.Call := TAtlasTrackerCall.Create(ASetup.Target, mTransport, cTrackerTimeoutMs);
  mRequest.Key := AKey;
  mRequest.Branch := ABranch;
  mRequest.Base := ABase;
  mRequest.Origin := TAtlasIdeTrackerPathSuggestions.OriginOfFolder(AFolder);
  Result := TAtlasLinkedStart.Run(mRequest);
end;

class function TAtlasIdeLinkedStart.Report(const ASetup: TAtlasIdeLinkSetup; const AKey: string;
  const AResult: TAtlasIdeLinkedResult): string;
var
  mReason: string;
  mFetched: Boolean;
begin
  mFetched := AResult.Fetch = TAtlasVcsOutcome.Ok;
  mReason := AResult.Link.Message;
  if not mFetched then
  begin
    mReason := AtlasVcsOutcomeName(AResult.Fetch);
  end
  else if mReason = '' then
  begin
    mReason := TAtlasTrackerIssuesText.ErrorText(AResult.Link.Error);
  end;
  Result := TAtlasGitHubStrings.LinkLine(AKey, ASetup.Target.Project, mReason, AResult.Link, mFetched);
end;

end.
