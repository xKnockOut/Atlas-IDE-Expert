unit Atlas.IDE.Tracker.IssueWorkLink;

// Arbeitsstand je Issue (#2052), Meldungen an die Willkommensseite über den
// Vertrag Atlas.IDE.Contracts.IssueWork: „Beginnen“, „Beenden“ und „Prüfen“
// (#2126) melden das bisherige Issue (Arbeitsstand sichern); nach „Beginnen“
// bietet sie das Wiederherstellen an, nach „Weiterarbeiten“ (#2127) und dem
// Rückweg von „Prüfen“ stellt sie ihn ohne Rückfrage her. Ohne
// Willkommensseite wirkungslos. Eigene Unit, damit die Dienste von „Meine
// Issues“ sie ohne Zyklus nutzen (aus Atlas.IDE.Tracker.IssueWork gelöst).
// Hauptthread.

interface

uses
  Atlas.Core.Tracker.MyIssues,
  Atlas.IDE.Contracts.IssueWork,
  Atlas.IDE.Tracker.IssuesContext;

type
  TAtlasTrackerIssueWorkLink = class
  public
    /// <summary>Arbeitsstand je Issue der Willkommensseite; False ohne sie.</summary>
    class function Work(out AWork: IAtlasIssueWork): Boolean; static;
    /// <summary>Aktives Issue von AProject im Format des Vertrags; False ohne.</summary>
    class function ActiveOf(AContext: TAtlasIdeIssuesContext; const AProject: string;
      out AIssue: TAtlasIssueWorkIssue): Boolean; static;
    /// <summary>Vor „Beginnen“ von ANewKey: Arbeitsstand des bisher aktiven Issues sichern (nicht, wenn es dasselbe
    /// ist).</summary>
    class procedure BeforeStart(AContext: TAtlasIdeIssuesContext; const AProject, ANewKey: string); static;
    /// <summary>Vor „Beenden“: Arbeitsstand von AActive (auf ABranch) sichern.</summary>
    class procedure BeforeEnd(const AProject, ABranch: string; const AActive: TAtlasActiveIssue); static;
    /// <summary>Nach „Beginnen“: „Arbeitsstand wiederherstellen?“, wenn es einen gibt.</summary>
    class procedure AfterStart(const AProject, AKey: string); static;
    /// <summary>Nach „Weiterarbeiten“ an einem wieder geöffneten Issue (#2127): ohne Rückfrage wiederherstellen.
    /// </summary>
    class procedure AfterResume(const AProject, AKey: string); static;
    /// <summary>Kennung des aktiven Issues von AProject; '' ohne (für „Prüfen“, #2126).</summary>
    class function ActiveKey(AContext: TAtlasIdeIssuesContext; const AProject: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Tracker.Contract;

function IssueOf(const AActive: TAtlasActiveIssue; const ABranch: string): TAtlasIssueWorkIssue;
begin
  Result := Default(TAtlasIssueWorkIssue);
  Result.Key := AActive.Key;
  Result.Title := AActive.Title;
  Result.Branch := AActive.Branch;
  // Aus dem Branch erkannt bzw. ohne gemerkten Branch: der ausgecheckte.
  if Result.Branch = '' then
  begin
    Result.Branch := ABranch;
  end;
end;

{ TAtlasTrackerIssueWorkLink }

class function TAtlasTrackerIssueWorkLink.Work(out AWork: IAtlasIssueWork): Boolean;
var
  mItems: TArray<IInterface>;
begin
  AWork := nil;
  Result := False;
  if AtlasModuleRegistry = nil then
  begin
    Exit;
  end;
  mItems := AtlasModuleRegistry.FindAll(IAtlasIssueWork);
  Result := (Length(mItems) > 0) and Supports(mItems[0], IAtlasIssueWork, AWork) and AWork.Enabled;
end;

class function TAtlasTrackerIssueWorkLink.ActiveOf(AContext: TAtlasIdeIssuesContext; const AProject: string;
  out AIssue: TAtlasIssueWorkIssue): Boolean;
var
  mTarget: TAtlasTrackerTarget;
  mBranch: string;
  mActive: TAtlasActiveIssue;
begin
  AIssue := Default(TAtlasIssueWorkIssue);
  Result := False;
  if (AContext = nil) or (AProject = '') then
  begin
    Exit;
  end;
  mTarget := AContext.TargetOf(AProject);
  mBranch := AContext.BranchOf(AProject);
  mActive := TAtlasMyIssues.Effective(AContext.StateOf(AProject), mTarget.Provider, mTarget.Project, mBranch);
  Result := mActive.Active;
  if Result then
  begin
    AIssue := IssueOf(mActive, mBranch);
  end;
end;

class procedure TAtlasTrackerIssueWorkLink.BeforeStart(AContext: TAtlasIdeIssuesContext;
  const AProject, ANewKey: string);
var
  mWork: IAtlasIssueWork;
  mIssue: TAtlasIssueWorkIssue;
begin
  if Work(mWork) and ActiveOf(AContext, AProject, mIssue) and not SameText(mIssue.Key, ANewKey) then
  begin
    mWork.SaveIssue(AProject, mIssue);
  end;
end;

class procedure TAtlasTrackerIssueWorkLink.BeforeEnd(const AProject, ABranch: string;
  const AActive: TAtlasActiveIssue);
var
  mWork: IAtlasIssueWork;
begin
  if AActive.Active and Work(mWork) then
  begin
    mWork.SaveIssue(AProject, IssueOf(AActive, ABranch));
  end;
end;

class procedure TAtlasTrackerIssueWorkLink.AfterStart(const AProject, AKey: string);
var
  mWork: IAtlasIssueWork;
begin
  if Work(mWork) and mWork.HasState(AProject, AKey) then
  begin
    mWork.OfferRestore(AProject, AKey);
  end;
end;

class procedure TAtlasTrackerIssueWorkLink.AfterResume(const AProject, AKey: string);
var
  mWork: IAtlasIssueWork;
begin
  if Work(mWork) and mWork.HasState(AProject, AKey) then
  begin
    mWork.Restore(AProject, AKey);
  end;
end;

class function TAtlasTrackerIssueWorkLink.ActiveKey(AContext: TAtlasIdeIssuesContext;
  const AProject: string): string;
var
  mIssue: TAtlasIssueWorkIssue;
begin
  Result := '';
  if ActiveOf(AContext, AProject, mIssue) then
  begin
    Result := mIssue.Key;
  end;
end;

end.
