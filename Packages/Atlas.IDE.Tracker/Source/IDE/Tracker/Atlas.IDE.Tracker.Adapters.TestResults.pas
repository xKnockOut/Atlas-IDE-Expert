unit Atlas.IDE.Tracker.Adapters.TestResults;

// Kachel „Testergebnisse“ (#763), Rolle Adapters: TAtlasTestResultsSourceAdapter
// erfüllt IAtlasTestResultsSource aus Atlas.UI.Tracker.TestResults und
// TAtlasTestsSummaryListener IAtlasProjectSummaryListener aus
// Atlas.IDE.Projects.Summaries; beide reichen an TAtlasIdeTestResults
// (Atlas.IDE.Tracker.TestResults) weiter und halten es, solange sie gehalten
// werden. Anlegen und Anmelden nur in der Komposition des Moduls. Hauptthread.

interface

uses
  Atlas.Core.Tracker.TestResults,
  Atlas.IDE.Projects.Summaries,
  Atlas.UI.Tracker.TestResults,
  Atlas.IDE.Tracker.TestResults;

type
  /// <summary>Quelle der Kachel „Testergebnisse“ über ATests.</summary>
  TAtlasTestResultsSourceAdapter = class(TInterfacedObject, IAtlasTestResultsSource)
  private
    FTests: TAtlasIdeTestResults;
    FTestsRef: IInterface;
  public
    constructor Create(ATests: TAtlasIdeTestResults);
    function View: TAtlasTestResultsView;
    procedure Select(const AProject: string);
    procedure OpenTest(const ARow: TAtlasTestRow; const AFailure: TAtlasTestFailureItem);
    procedure RerunFailed(const ARow: TAtlasTestRow; const ATests: TArray<string>);
    procedure Debug(const ARow: TAtlasTestRow; const AFailure: TAtlasTestFailureItem);
    function CanCompare(const AFailure: TAtlasTestFailureItem): Boolean;
    procedure Compare(const AFailure: TAtlasTestFailureItem);
    procedure Browse(const ARow: TAtlasTestRow);
    procedure QueryNow(const ARow: TAtlasTestRow);
    procedure Credentials(const ARow: TAtlasTestRow);
    procedure OpenProject(const ARow: TAtlasTestRow);
    function CanEnterCredentials: Boolean;
    procedure Shown;
  end;

  /// <summary>Geänderte Zusammenfassungen an ATests.</summary>
  TAtlasTestsSummaryListener = class(TInterfacedObject, IAtlasProjectSummaryListener)
  private
    FTests: TAtlasIdeTestResults;
    FTestsRef: IInterface;
  public
    constructor Create(ATests: TAtlasIdeTestResults);
    procedure SummaryChanged(const AProject: string);
  end;

implementation

{ TAtlasTestResultsSourceAdapter }

constructor TAtlasTestResultsSourceAdapter.Create(ATests: TAtlasIdeTestResults);
begin
  inherited Create;
  FTests := ATests;
  FTestsRef := ATests;
end;

function TAtlasTestResultsSourceAdapter.View: TAtlasTestResultsView;
begin
  Result := FTests.View;
end;

procedure TAtlasTestResultsSourceAdapter.Select(const AProject: string);
begin
  FTests.Select(AProject);
end;

procedure TAtlasTestResultsSourceAdapter.OpenTest(const ARow: TAtlasTestRow; const AFailure: TAtlasTestFailureItem);
begin
  FTests.OpenTest(ARow, AFailure);
end;

procedure TAtlasTestResultsSourceAdapter.RerunFailed(const ARow: TAtlasTestRow; const ATests: TArray<string>);
begin
  FTests.RerunFailed(ARow, ATests);
end;

procedure TAtlasTestResultsSourceAdapter.Debug(const ARow: TAtlasTestRow; const AFailure: TAtlasTestFailureItem);
begin
  FTests.Debug(ARow, AFailure);
end;

function TAtlasTestResultsSourceAdapter.CanCompare(const AFailure: TAtlasTestFailureItem): Boolean;
begin
  Result := FTests.CanCompare(AFailure);
end;

procedure TAtlasTestResultsSourceAdapter.Compare(const AFailure: TAtlasTestFailureItem);
begin
  FTests.Compare(AFailure);
end;

procedure TAtlasTestResultsSourceAdapter.Browse(const ARow: TAtlasTestRow);
begin
  FTests.Browse(ARow);
end;

procedure TAtlasTestResultsSourceAdapter.QueryNow(const ARow: TAtlasTestRow);
begin
  FTests.QueryNow(ARow);
end;

procedure TAtlasTestResultsSourceAdapter.Credentials(const ARow: TAtlasTestRow);
begin
  FTests.Credentials(ARow);
end;

procedure TAtlasTestResultsSourceAdapter.OpenProject(const ARow: TAtlasTestRow);
begin
  FTests.OpenProject(ARow);
end;

function TAtlasTestResultsSourceAdapter.CanEnterCredentials: Boolean;
begin
  Result := FTests.CanEnterCredentials;
end;

procedure TAtlasTestResultsSourceAdapter.Shown;
begin
  FTests.Shown;
end;

{ TAtlasTestsSummaryListener }

constructor TAtlasTestsSummaryListener.Create(ATests: TAtlasIdeTestResults);
begin
  inherited Create;
  FTests := ATests;
  FTestsRef := ATests;
end;

procedure TAtlasTestsSummaryListener.SummaryChanged(const AProject: string);
begin
  FTests.SummaryChanged(AProject);
end;

end.
