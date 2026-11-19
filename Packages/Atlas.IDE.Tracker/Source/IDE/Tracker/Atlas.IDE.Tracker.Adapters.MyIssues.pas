unit Atlas.IDE.Tracker.Adapters.MyIssues;

// Quelle der Kachel „Meine Issues“ (#765), Rolle Adapters:
// TAtlasIssuesSourceAdapter erfüllt IAtlasIssuesSource aus
// Atlas.UI.Tracker.Contract.MyIssues und reicht an TAtlasIdeIssues
// (Atlas.IDE.Tracker.MyIssues) weiter; hält die Quelle, solange eine Ansicht
// den Adapter hält. Anlegen nur in der Komposition des Moduls. Hauptthread.

interface

uses
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Contract.MyIssues,
  Atlas.UI.Tracker.Contract.MyIssues,
  Atlas.IDE.Tracker.MyIssues;

type
  /// <summary>Quelle der Kachel „Meine Issues“ über AIssues.</summary>
  TAtlasIssuesSourceAdapter = class(TInterfacedObject, IAtlasIssuesSource)
  private
    FIssues: TAtlasIdeIssues;
    FIssuesRef: IInterface;
  public
    constructor Create(AIssues: TAtlasIdeIssues);
    function View: TAtlasIssuesView;
    procedure Shown;
    procedure Start(const AIssue: TAtlasTrackerIssue; AMode: TAtlasIssueStart);
    procedure Browse(const AIssue: TAtlasTrackerIssue);
    procedure Preview(const AIssue: TAtlasTrackerIssue);
    procedure BrowsePullRequest(const AIssue: TAtlasTrackerIssue);
    procedure QueryNow;
    procedure Credentials;
    function CanEnterCredentials: Boolean;
    procedure EndActive;
    procedure AssignProject;
    procedure SelectQuery(const AName: string);
    procedure EditQueries;
    procedure ClearFilter;
    procedure SelectProject(const AKey: string);
    procedure EditProjects;
    procedure IssueAction(const AIssue: TAtlasTrackerIssue; AAction: TAtlasIssueAction);
  end;

implementation

{ TAtlasIssuesSourceAdapter }

constructor TAtlasIssuesSourceAdapter.Create(AIssues: TAtlasIdeIssues);
begin
  inherited Create;
  FIssues := AIssues;
  FIssuesRef := AIssues;
end;

function TAtlasIssuesSourceAdapter.View: TAtlasIssuesView;
begin
  Result := FIssues.View;
end;

procedure TAtlasIssuesSourceAdapter.Shown;
begin
  FIssues.Shown;
end;

procedure TAtlasIssuesSourceAdapter.Start(const AIssue: TAtlasTrackerIssue; AMode: TAtlasIssueStart);
begin
  FIssues.Start(AIssue, AMode);
end;

procedure TAtlasIssuesSourceAdapter.Browse(const AIssue: TAtlasTrackerIssue);
begin
  FIssues.Browse(AIssue);
end;

procedure TAtlasIssuesSourceAdapter.Preview(const AIssue: TAtlasTrackerIssue);
begin
  FIssues.Preview(AIssue);
end;

procedure TAtlasIssuesSourceAdapter.BrowsePullRequest(const AIssue: TAtlasTrackerIssue);
begin
  FIssues.BrowsePullRequest(AIssue);
end;

procedure TAtlasIssuesSourceAdapter.QueryNow;
begin
  FIssues.QueryNow;
end;

procedure TAtlasIssuesSourceAdapter.Credentials;
begin
  FIssues.Credentials;
end;

function TAtlasIssuesSourceAdapter.CanEnterCredentials: Boolean;
begin
  Result := FIssues.CanEnterCredentials;
end;

procedure TAtlasIssuesSourceAdapter.EndActive;
begin
  FIssues.EndActive;
end;

procedure TAtlasIssuesSourceAdapter.AssignProject;
begin
  FIssues.AssignProject;
end;

procedure TAtlasIssuesSourceAdapter.SelectQuery(const AName: string);
begin
  FIssues.SelectQuery(AName);
end;

procedure TAtlasIssuesSourceAdapter.EditQueries;
begin
  FIssues.EditQueries;
end;

procedure TAtlasIssuesSourceAdapter.ClearFilter;
begin
  FIssues.ClearFilter;
end;

procedure TAtlasIssuesSourceAdapter.SelectProject(const AKey: string);
begin
  FIssues.SelectProject(AKey);
end;

procedure TAtlasIssuesSourceAdapter.EditProjects;
begin
  FIssues.EditProjects;
end;

procedure TAtlasIssuesSourceAdapter.IssueAction(const AIssue: TAtlasTrackerIssue; AAction: TAtlasIssueAction);
begin
  FIssues.IssueAction(AIssue, AAction);
end;

end.
