unit Atlas.IDE.Tracker.TestActions;

// Aktionen der Kachel „Testergebnisse“ (#763, eigene Unit des
// Moduls Tracker): Projekt öffnen (Willkommensseite), Test öffnen (für
// Fehlschläge vom Server über die Testunit im Projekt gesucht),
// „Fehlgeschlagene erneut ausführen“ (#69) und „Im Debugger“ (#585) über das
// Modul Tests aus der Registry (IAtlasTestRunner, IAtlasTestsSource), „Im
// Browser“ die Seite des Builds. Ohne Modul Tests meldet „erneut ausführen“,
// dass die Tests aus sind. Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.TestResults,
  Atlas.IDE.Tracker.Access,
  Atlas.IDE.Tracker.WelcomeLink;

type
  /// <summary>Aktionen der Kachel: Projekt öffnen, Test öffnen, ausführen und debuggen, Seite des Builds.</summary>
  TAtlasTestResultsActions = class
  private
    FLink: TAtlasTrackerWelcomeLink;
    FAccess: IAtlasCiAccess;
    FMessage: TProc<string>;
    procedure Report(const AText: string);
    function EnsureOpen(const AProject: string): Boolean;
    function Locate(const ARow: TAtlasTestRow; const AItem: TAtlasTestFailureItem; out AFileName: string;
      out ALine: Integer): Boolean;
    class function TestProjectOf(const ARow: TAtlasTestRow): string; static;
    class function ProjectIsOpen(const AFileName: string): Boolean; static;
  public
    constructor Create(ALink: TAtlasTrackerWelcomeLink; const AAccess: IAtlasCiAccess; const AMessage: TProc<string>);
    /// <summary>Beim Stoppen: die Verbindung zur Willkommensseite loslassen; „Projekt öffnen“ ist danach
    /// wirkungslos.</summary>
    procedure Release;
    procedure OpenTest(const ARow: TAtlasTestRow; const AItem: TAtlasTestFailureItem);
    procedure RerunFailed(const ARow: TAtlasTestRow; const ATests: TArray<string>);
    procedure Debug(const ARow: TAtlasTestRow; const AItem: TAtlasTestFailureItem);
    procedure OpenProject(const ARow: TAtlasTestRow);
    /// <summary>Seite des Builds ANumber; nur Web-Adressen aus der eingetragenen Adresse.</summary>
    procedure OpenBuildPage(const AJob: TAtlasCiJob; ANumber: Integer);
    /// <summary>Job aus der .atlas von AProject ohne Branch (Zugang hinterlegen).</summary>
    class function JobOfProject(const AProject: string): TAtlasCiJob; static;
  end;


implementation

uses
  Winapi.Windows,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Tracker.Files,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Contributions,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Settings.TeamFile,
  Atlas.IDE.Contracts.Tests,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.TeamFile,
  Atlas.IDE.Results.Commands,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.TestResults.Strings;

const
  cHttps = 'https://';
  cHttp = 'http://';

{ TAtlasTestResultsActions }

constructor TAtlasTestResultsActions.Create(ALink: TAtlasTrackerWelcomeLink; const AAccess: IAtlasCiAccess;
  const AMessage: TProc<string>);
begin
  inherited Create;
  FLink := ALink;
  FAccess := AAccess;
  FMessage := AMessage;
end;

procedure TAtlasTestResultsActions.Release;
begin
  FLink := nil;
end;

procedure TAtlasTestResultsActions.Report(const AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
end;

class function TAtlasTestResultsActions.TestProjectOf(const ARow: TAtlasTestRow): string;
begin
  Result := ARow.TestProject;
  if Result = '' then
  begin
    Result := ARow.Project;
  end;
end;

class function TAtlasTestResultsActions.ProjectIsOpen(const AFileName: string): Boolean;
var
  mModules: IOTAModuleServices;
begin
  Result := Supports(BorlandIDEServices, IOTAModuleServices, mModules) and (mModules.FindModule(AFileName) <> nil);
end;

class function TAtlasTestResultsActions.JobOfProject(const AProject: string): TAtlasCiJob;
var
  mTeam: TAtlasTeamSettings;
  mProvider: string;
begin
  mTeam := TAtlasIdeTeamFile.ForProject(AProject);
  mProvider := mTeam.Ci.Provider;
  if mProvider = '' then
  begin
    mProvider := TAtlasIdeSettings.Current.WelcomePageTestsCiProvider;
  end;
  Result := TAtlasCiJob.Create(mProvider, mTeam.Ci.Url, mTeam.Ci.Job, mTeam.Ci.Multibranch, '');
end;

function TAtlasTestResultsActions.EnsureOpen(const AProject: string): Boolean;
var
  mActions: IOTAActionServices;
begin
  Result := False;
  if not FileExists(AProject) then
  begin
    Report(TAtlasTestResultsStrings.Fmt(TAtlasTestResultsTextId.WelcomeProjectsMissing, [AProject]));
  end
  else if ProjectIsOpen(AProject) then
  begin
    // Schon offen: nicht neu laden.
    Result := True;
  end
  else if Supports(BorlandIDEServices, IOTAActionServices, mActions) then
  begin
    TAtlasGuard.RunIde(
      procedure
      begin
        mActions.OpenProject(AProject, True);
      end);
    Result := ProjectIsOpen(AProject);
  end;
end;

function TAtlasTestResultsActions.Locate(const ARow: TAtlasTestRow; const AItem: TAtlasTestFailureItem;
  out AFileName: string; out ALine: Integer): Boolean;
var
  mItem: IInterface;
  mTests: IAtlasTestsSource;
begin
  AFileName := '';
  ALine := 0;
  Result := False;
  // Fehlschlag vom Server: Test in seiner Testunit im Projekt suchen (Modul Tests).
  for mItem in TAtlasModuleContributions.Active(AtlasModuleRegistry, IAtlasTestsSource) do
  begin
    if not Result and Supports(mItem, IAtlasTestsSource, mTests) then
    begin
      Result := mTests.LocateByName(TestProjectOf(ARow), AItem.Test, AFileName, ALine);
    end;
  end;
end;

procedure TAtlasTestResultsActions.OpenTest(const ARow: TAtlasTestRow; const AItem: TAtlasTestFailureItem);
var
  mFileName: string;
  mLine: Integer;
begin
  mFileName := AItem.FileName;
  mLine := AItem.Line;
  if (mFileName = '') or not FileExists(mFileName) then
  begin
    if not EnsureOpen(ARow.Project) then
    begin
      Exit;
    end;
    if not Locate(ARow, AItem, mFileName, mLine) then
    begin
      Report(TAtlasTestResultsStrings.Fmt(TAtlasTestResultsTextId.WelcomeTestsNotFound, [AItem.Test]));
      Exit;
    end;
  end
  else if not EnsureOpen(ARow.Project) then
  begin
    Exit;
  end;
  // Die Zusammenfassung zählt ab 1, der Editor ab 0.
  TAtlasIdeResults.Open(mFileName, mLine - 1, 0);
end;

procedure TAtlasTestResultsActions.RerunFailed(const ARow: TAtlasTestRow; const ATests: TArray<string>);
var
  mItem: IInterface;
  mRunner: IAtlasTestRunner;
begin
  if (Length(ATests) = 0) or not EnsureOpen(ARow.Project) then
  begin
    Exit;
  end;
  // Genau diese Tests (--run), im Testprojekt des letzten Laufs; über das Modul Tests.
  for mItem in TAtlasModuleContributions.Active(AtlasModuleRegistry, IAtlasTestRunner) do
  begin
    if Supports(mItem, IAtlasTestRunner, mRunner) then
    begin
      mRunner.RunTests(TestProjectOf(ARow), ATests);
      Exit;
    end;
  end;
  Report(TAtlasStrings.Text(TAtlasTextId.TestsRunOff));
end;

procedure TAtlasTestResultsActions.Debug(const ARow: TAtlasTestRow; const AItem: TAtlasTestFailureItem);
var
  mItem: IInterface;
  mTests: IAtlasTestsSource;
  mReason: string;
begin
  if not EnsureOpen(ARow.Project) then
  begin
    Exit;
  end;
  for mItem in TAtlasModuleContributions.Active(AtlasModuleRegistry, IAtlasTestsSource) do
  begin
    if Supports(mItem, IAtlasTestsSource, mTests) then
    begin
      if not mTests.DebugByName(TestProjectOf(ARow), AItem.Test, mReason) and (mReason <> '') then
      begin
        Report(mReason);
      end;
      Exit;
    end;
  end;
end;

procedure TAtlasTestResultsActions.OpenProject(const ARow: TAtlasTestRow);
begin
  if FLink <> nil then
  begin
    FLink.Open(ARow.Project);
  end;
end;

procedure TAtlasTestResultsActions.OpenBuildPage(const AJob: TAtlasCiJob; ANumber: Integer);
var
  mProvider: IAtlasCiProvider;
  mUrl: string;
begin
  mProvider := nil;
  if FAccess <> nil then
  begin
    mProvider := FAccess.Provider(AJob.Provider);
  end;
  if mProvider = nil then
  begin
    Exit;
  end;
  mUrl := mProvider.BuildPage(AJob, ANumber);
  // Nur Web-Adressen aus der eingetragenen Adresse, nie etwas aus der Antwort des Servers.
  if mUrl.StartsWith(cHttps, True) or mUrl.StartsWith(cHttp, True) then
  begin
    TAtlasTrackerFiles.Shell.Open(mUrl);
  end;
end;

end.
