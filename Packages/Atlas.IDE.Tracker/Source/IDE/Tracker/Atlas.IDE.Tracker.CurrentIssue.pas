unit Atlas.IDE.Tracker.CurrentIssue;

// Begonnenes Issue für KI-Assistenten (#2051, issues.shareWithAssistants) in
// der IDE: TAtlasIdeIssuesStatus ruft Sync bei jeder Aktualisierung der
// Statuszeile (nach „Beginnen“, „Beenden“, Projektwechsel und alle paar
// Sekunden). Sync liest den Stand der Issue-Vorschau aus dem Zwischenspeicher
// (ohne Netz), stößt höchstens alle paar Minuten eine Auffrischung im
// Hintergrund an und schreibt <gitdir>/atlas-current-issue.json nur bei
// geändertem Inhalt (TAtlasCurrentIssuePlan). So kommt ein im Tracker
// abgehakter Punkt mit der nächsten Auffrischung in die Datei. Clear löscht
// sie, wenn der Bereich abgeschaltet wird; beim Entladen bleibt sie wie das
// Präfix für den Git-Hook. Nur im Hauptthread.

interface

uses
  Atlas.Core.Tracker.MyIssues,
  Atlas.IDE.Tracker.IssuesContext,
  Atlas.IDE.Tracker.IssuesServices;

type
  TAtlasIdeCurrentIssue = class
  private
    FContext: TAtlasIdeIssuesContext;
    FServices: TAtlasIdeIssuesServices;
    // Zuletzt bedientes Projekt und sein Git-Ordner.
    FProject: string;
    FGitDir: string;
    function GitDirFor(const AProject: string): string;
  public
    constructor Create(AContext: TAtlasIdeIssuesContext; AServices: TAtlasIdeIssuesServices);
    /// <summary>Datei des Projekts AProject auf das aktive Issue AActive bringen.</summary>
    procedure Sync(const AProject: string; const AActive: TAtlasActiveIssue);
    /// <summary>Datei des zuletzt bedienten Projekts löschen.</summary>
    procedure Clear;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Tracker.CurrentIssue,
  Atlas.Core.Tracker.CurrentIssuePlan,
  Atlas.Core.Tracker.Files,
  Atlas.IDE.Foundation.Settings;

const
  cLogNotWritten = 'Meine Issues: Datei für KI-Assistenten nicht geschrieben'; // german-ok: Diagnoseprotokoll, nicht in der Oberfläche

{ TAtlasIdeCurrentIssue }

constructor TAtlasIdeCurrentIssue.Create(AContext: TAtlasIdeIssuesContext; AServices: TAtlasIdeIssuesServices);
begin
  inherited Create;
  FContext := AContext;
  FServices := AServices;
end;

function TAtlasIdeCurrentIssue.GitDirFor(const AProject: string): string;
var
  mFolder: string;
begin
  if SameText(AProject, FProject) and (FGitDir <> '') then
  begin
    Exit(FGitDir);
  end;
  // „Gilt für“ kann ein Ordner sein, sonst eine .dproj bzw. .groupproj.
  mFolder := AProject;
  if not TAtlasTrackerFiles.Files.FolderExists(mFolder) then
  begin
    mFolder := ExtractFileDir(AProject);
  end;
  Result := TAtlasCurrentIssuePlan.GitDirOf(mFolder);
  if Result = '' then
  begin
    // Beim Beginnen ermittelt (Worktree), falls der Ordner selbst keinen nennt.
    Result := FContext.StateOf(AProject).GitDir;
  end;
end;

/// <summary>Fehlschlag ins Protokoll (anonym, ohne Kennung und Pfad).</summary>
procedure LogFailure(AResult: TAtlasCurrentIssueSync);
begin
  if AResult = TAtlasCurrentIssueSync.Failed then
  begin
    TAtlasGuard.Log(cLogNotWritten);
  end;
end;

procedure TAtlasIdeCurrentIssue.Sync(const AProject: string; const AActive: TAtlasActiveIssue);
var
  mSource: TAtlasCurrentIssueSource;
  mGitDir: string;
  mShare: Boolean;
begin
  if AProject = '' then
  begin
    Exit;
  end;
  mGitDir := GitDirFor(AProject);
  // Projektwechsel: Die Datei des bisherigen Projekts bleibt, sie gehört zu dessen Arbeitskopie.
  FProject := AProject;
  FGitDir := mGitDir;
  if mGitDir = '' then
  begin
    Exit;
  end;
  mShare := TAtlasIdeSettings.Current.IssuesShareWithAssistants;
  mSource := Default(TAtlasCurrentIssueSource);
  if mShare and AActive.Active then
  begin
    mSource.Key := AActive.Key;
    mSource.Title := AActive.Title;
    mSource.Branch := AActive.Branch;
    mSource.Started := AActive.StartedUtc;
    mSource.Target := FContext.TargetOf(AProject);
    if FServices.Preview <> nil then
    begin
      // Fehlt der Stand oder ist er alt, frischt ihn Prefetch im Hintergrund auf (höchstens alle paar Minuten).
      FServices.Preview.Checklists.Prefetch(mSource.Target, AActive.Key);
      mSource.HasDetails := FServices.Preview.Lookups.Peek(mSource.Target, AActive.Key, mSource.Details);
    end;
  end;
  LogFailure(TAtlasCurrentIssuePlan.Sync(mGitDir, mShare, AActive.Active, TAtlasCurrentIssuePlan.Build(mSource)));
end;

procedure TAtlasIdeCurrentIssue.Clear;
begin
  if FGitDir <> '' then
  begin
    LogFailure(TAtlasCurrentIssuePlan.Sync(FGitDir, False, False, TAtlasCurrentIssue.Empty));
  end;
  FProject := '';
  FGitDir := '';
end;

end.
