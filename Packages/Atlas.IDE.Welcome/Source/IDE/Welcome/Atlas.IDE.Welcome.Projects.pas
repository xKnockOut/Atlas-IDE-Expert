unit Atlas.IDE.Welcome.Projects;

// Bereich „Projekte“ in der IDE (#592): Quelle des Bereichs
// (IAtlasProjectsSource) und Anmeldung als Bereich atlas.projects der
// Willkommensseite (bzw. des Fensters „Atlas-Start“).
// - Liste: zuletzt geöffnete Projekte und Projektgruppen der IDE (Registry
//   <Basis>\Closed Projects), höchstens welcomePage.maxProjects; Schalter
//   welcomePage.projectStatus.
// - Die Projekt-Zusammenfassungen schreibt der Kern
//   (TAtlasIdeProjectSummaries, #1455), auch ohne Willkommensseite. Der Bereich
//   hört als IAtlasProjectSummaryListener auf Änderungen und zeichnet neu;
//   beim Anzeigen fragt er die Versionsverwaltung über den Kern frisch ab
//   (welcomePage.refreshVcs, je Projekt höchstens einmal je Minute).
// - Auswahl (#758): Mit eingeschaltetem Projektverlauf oder „Meine Issues“
//   (#765) wählt ein Klick auf eine Zeile das Projekt für diese Bereiche
//   (Doppelklick öffnet); Select meldet ihnen die Änderung.
// - Schnellaktionen (#764): Die Quelle der Knopfleiste (QuickActions) bekommt
//   jeder Frame; VcsOf liefert ihr den Stand der Versionsverwaltung, Refresh
//   fragt nach Pull neu ab.
// - Die Willkommensseite startet keinen Server und liest nur lokale Dateien.

interface

uses
  System.SysUtils,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Welcome.Sections,
  Atlas.Core.Welcome.Projects,
  Atlas.UI.Welcome.QuickActions,
  Atlas.UI.Welcome.Projects,
  Atlas.IDE.Projects.Summaries;

type
  TAtlasIdeProjects = class(TInterfacedObject, IAtlasProjectsSource, IAtlasProjectSummaryListener)
  public const
    /// <summary>Reihenfolge außerhalb des Atlas-Layouts.</summary>
    Order = 20;
  private
    FMessage: TProc<string>;
    FStopped: Boolean;
    // Hört auf die Zusammenfassungen des Kerns (#1455), solange der Bereich läuft.
    FListening: IAtlasRegistration;
    // Für den Projektverlauf gewähltes Projekt (#758); '' = keins.
    FSelected: string;
    // Quelle der Schnellaktionen (#764); nil = keine Knöpfe.
    FQuickActions: IAtlasQuickActionsSource;
    procedure Changed;
    procedure Report(const AText: string);
    class function TrendsOn: Boolean; static;
    class function ProjectOpen(const AFileName: string): Boolean; static;
    class function Summaries: TAtlasIdeProjectSummaries; static;
  public
    /// <summary>AMessage: Zeile in die Meldungsansicht.</summary>
    constructor Create(const AMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Bereich und Fabrik anmelden, auf die Zusammenfassungen hören.</summary>
    procedure Start;
    /// <summary>Alles abmelden (beim Entladen); danach wirkungslos.</summary>
    procedure Stop;
    function Section: TAtlasWelcomeSection;
    /// <summary>Stand der Versionsverwaltung von AProject: frisch abgefragt (diese Sitzung), sonst aus der
    /// Zusammenfassung; Empty ohne (#764).</summary>
    function VcsOf(const AProject: string): TAtlasProjectVcs;
    /// <summary>Branch und Änderungen von AProject jetzt neu abfragen (nach Pull, #764), auch innerhalb der Minute.
    /// </summary>
    procedure Refresh(const AProject: string);
    { IAtlasProjectSummaryListener }
    procedure SummaryChanged(const AProject: string);
    { IAtlasProjectsSource }
    function Entries: TAtlasProjectEntries;
    procedure Open(const AProject: string);
    procedure OpenAt(const AProject: string; const ATarget: TAtlasProjectLocation);
    procedure OpenFolder(const AProject: string);
    procedure CreateBranch(const AProject: string);
    /// <summary>„Arbeitskopien …“ (#1292): Tabelle; danach die Zeile neu abfragen.</summary>
    procedure ShowWorkingCopies(const AProject: string);
    function WorkingCopies: Boolean;
    procedure Remove(const AProject: string);
    procedure Shown;
    function Selectable: Boolean;
    procedure Select(const AProject: string);
    function Selected: string;
    /// <summary>Quelle der Schnellaktionen (#764) für neue Frames; vor Start setzen.</summary>
    property QuickActions: IAtlasQuickActionsSource read FQuickActions write FQuickActions;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.ShellAPI,
  System.Classes,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.Registry,
  Atlas.UI.Welcome.Strings,
  Atlas.UI.Welcome.Frame,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Results.Commands,
  Atlas.IDE.Vcs.Branching,
  Atlas.IDE.Vcs.WorkingCopies,
  Atlas.IDE.Welcome.Search;

{ TAtlasIdeProjects }

constructor TAtlasIdeProjects.Create(const AMessage: TProc<string>);
begin
  inherited Create;
  FMessage := AMessage;
end;

destructor TAtlasIdeProjects.Destroy;
begin
  Stop;
  inherited;
end;

class function TAtlasIdeProjects.ProjectOpen(const AFileName: string): Boolean;
var
  Modules: IOTAModuleServices;
begin
  Result := Supports(BorlandIDEServices, IOTAModuleServices, Modules) and (Modules.FindModule(AFileName) <> nil);
end;

class function TAtlasIdeProjects.Summaries: TAtlasIdeProjectSummaries;
begin
  Result := TAtlasIdeProjectSummaries.Current;
end;

procedure TAtlasIdeProjects.Start;
var
  Keep: IAtlasProjectsSource;
begin
  FStopped := False;
  Keep := Self;
  TAtlasWelcomeViews.Register(TAtlasWelcomeIds.Projects,
    function(AOwner: TComponent): TAtlasWelcomeSectionFrame
    var
      Frame: TAtlasWelcomeProjectsFrame;
    begin
      Frame := TAtlasWelcomeProjectsFrame.Create(AOwner);
      Frame.Source := Keep;
      // Schnellaktionen (#764): dieselbe Quelle für jeden Frame.
      Frame.QuickActions := QuickActions;
      Result := Frame;
    end);
  TAtlasWelcomeSections.Default.Add(Section);
  // Zusammenfassungen schreibt der Kern (#1455); der Bereich zeichnet nach jeder Änderung neu.
  FListening := AtlasModuleRegistry.Provide(IAtlasProjectSummaryListener, Self as IAtlasProjectSummaryListener);
end;

procedure TAtlasIdeProjects.Stop;
begin
  if FStopped then
  begin
    Exit;
  end;
  FStopped := True;
  if FListening <> nil then
  begin
    FListening.Revoke;
  end;
  FListening := nil;
  TAtlasWelcomeViews.Unregister(TAtlasWelcomeIds.Projects);
  TAtlasWelcomeSections.Default.Remove(TAtlasWelcomeIds.Projects);
  FQuickActions := nil;
end;

function TAtlasIdeProjects.Section: TAtlasWelcomeSection;
begin
  Result := TAtlasWelcomeSection.Create(TAtlasWelcomeIds.Projects,
    TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeProjectsTitle), Order, TAtlasWelcomeColumn.Left,
    function: Boolean
    begin
      Result := TAtlasIdeSettings.Current.WelcomePageProjectStatus;
    end);
end;

procedure TAtlasIdeProjects.Changed;
begin
  if FStopped then
  begin
    Exit;
  end;
  TAtlasWelcomeSections.Default.Changed(TAtlasWelcomeIds.Projects);
  // Der Projektverlauf (#758) liest dieselben Zusammenfassungen und folgt der Auswahl.
  TAtlasWelcomeSections.Default.Changed(TAtlasWelcomeIds.History);
  // Ebenso die Testergebnisse (#763, Abschnitt "tests" und Branch für den Multibranch-Job).
  TAtlasWelcomeSections.Default.Changed(TAtlasWelcomeIds.Tests);
  // Und „Meine Issues“ (#765): Auswahl, Branch (Branch → Ticket) und Art der Versionsverwaltung.
  TAtlasWelcomeSections.Default.Changed(TAtlasWelcomeIds.Issues);
end;

class function TAtlasIdeProjects.TrendsOn: Boolean;
begin
  Result := TAtlasIdeSettings.Current.WelcomePageTrends;
end;

function TAtlasIdeProjects.Selectable: Boolean;
begin
  // Ohne Projektverlauf und „Meine Issues“ (#765) hat eine Auswahl keinen Zweck: Klick öffnet wie bisher (#592).
  Result := not FStopped and (TrendsOn or TAtlasIdeSettings.Current.WelcomePageIssues);
end;

procedure TAtlasIdeProjects.Select(const AProject: string);
begin
  if FStopped or (TAtlasProjectSummaries.NormalizedPath(AProject) = TAtlasProjectSummaries.NormalizedPath(FSelected))
  then
  begin
    Exit;
  end;
  FSelected := AProject;
  Changed;
end;

function TAtlasIdeProjects.Selected: string;
begin
  Result := FSelected;
end;

procedure TAtlasIdeProjects.Report(const AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
end;

function TAtlasIdeProjects.Entries: TAtlasProjectEntries;
var
  Recent: TArray<string>;
  Index: Integer;
  Vcs: TAtlasProjectVcs;
  Root: string;
  mSummaries: TAtlasIdeProjectSummaries;
begin
  Result := nil;
  if FStopped then
  begin
    Exit;
  end;
  Recent := nil;
  try
    Recent := TAtlasIdeWelcomeSearch.ClosedProjects;
  except
    // Registry nicht lesbar: leere Liste statt eines Fehlers in der Willkommensseite.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
  end;
  Root := TAtlasIdeProjectSummaries.Folder;
  Result := TAtlasWelcomeProjects.Entries(Recent,
    function(const AProject: string; out ASummary: TAtlasProjectSummary): Boolean
    begin
      Result := TAtlasProjectSummaries.Load(Root, AProject, ASummary);
    end,
    TAtlasIdeSettings.Current.WelcomePageMaxProjects);
  mSummaries := Summaries;
  if mSummaries = nil then
  begin
    Exit;
  end;
  for Index := 0 to High(Result) do
  begin
    if mSummaries.LiveVcs(Result[Index].Project, Vcs) then
    begin
      Result[Index].Summary.Vcs := Vcs;
      Result[Index].VcsFresh := True;
    end;
    Result[Index].VcsQuerying := mSummaries.Querying(Result[Index].Project);
  end;
end;

procedure TAtlasIdeProjects.Shown;
var
  Entry: TAtlasProjectEntry;
begin
  if FStopped or (Summaries = nil) or not TAtlasIdeSettings.Current.WelcomePageRefreshVcs then
  begin
    Exit;
  end;
  for Entry in Entries do
  begin
    Summaries.QueryIfStale(Entry.Project);
  end;
end;

function TAtlasIdeProjects.VcsOf(const AProject: string): TAtlasProjectVcs;
begin
  Result := TAtlasProjectVcs.Empty;
  if not FStopped and (Summaries <> nil) then
  begin
    Result := Summaries.VcsOf(AProject);
  end;
end;

procedure TAtlasIdeProjects.Refresh(const AProject: string);
begin
  if not FStopped and (Summaries <> nil) then
  begin
    Summaries.Refresh(AProject);
  end;
end;

procedure TAtlasIdeProjects.SummaryChanged(const AProject: string);
begin
  Changed;
end;

procedure TAtlasIdeProjects.Open(const AProject: string);
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Actions: IOTAActionServices;
    begin
      if not FileExists(AProject) then
      begin
        Report(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeProjectsMissing, [AProject]));
        Exit;
      end;
      if Supports(BorlandIDEServices, IOTAActionServices, Actions) then
      begin
        Actions.OpenProject(AProject, True);
      end;
    end);
end;

procedure TAtlasIdeProjects.OpenAt(const AProject: string; const ATarget: TAtlasProjectLocation);
var
  Target: TAtlasProjectLocation;
begin
  Target := ATarget;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    var
      Actions: IOTAActionServices;
      Line, Column: Integer;
    begin
      if not FileExists(AProject) then
      begin
        Report(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeProjectsMissing, [AProject]));
        Exit;
      end;
      // Erst das Projekt (wie die Liste der IDE), dann die erste Meldung.
      if not ProjectOpen(AProject) and Supports(BorlandIDEServices, IOTAActionServices, Actions) then
      begin
        Actions.OpenProject(AProject, True);
      end;
      if Target.IsEmpty or not FileExists(Target.FileName) then
      begin
        Exit;
      end;
      // Die Zusammenfassung zählt ab 1, der Editor ab 0.
      Line := Target.Line - 1;
      if Line < 0 then
      begin
        Line := 0;
      end;
      Column := Target.Column - 1;
      if Column < 0 then
      begin
        Column := 0;
      end;
      TAtlasIdeResults.Open(Target.FileName, Line, Column);
    end);
end;

procedure TAtlasIdeProjects.OpenFolder(const AProject: string);
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      if FileExists(AProject) then
      begin
        // Explorer mit markierter Projektdatei.
        ShellExecute(0, 'open', 'explorer.exe', PChar('/select,"' + AProject + '"'), nil, SW_SHOWNORMAL);
      end
      else if DirectoryExists(ExtractFileDir(AProject)) then
      begin
        ShellExecute(0, 'open', PChar(ExtractFileDir(AProject)), nil, nil, SW_SHOWNORMAL);
      end
      else
      begin
        Report(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeProjectsMissing, [AProject]));
      end;
    end);
end;

procedure TAtlasIdeProjects.CreateBranch(const AProject: string);
var
  mKeep: IAtlasProjectsSource;
  mProject: string;
begin
  // Dialog „Branch anlegen“ (#1288); danach Branch und Änderungen der Zeile neu abfragen.
  mKeep := Self;
  mProject := AProject;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      TAtlasIdeBranching.CreateFor(mProject,
        procedure
        begin
          // mKeep hält den Bereich bis hierher; nach dem Beenden nichts mehr abfragen.
          if (mKeep <> nil) and not FStopped then
          begin
            Refresh(mProject);
          end;
        end);
    end);
end;

procedure TAtlasIdeProjects.ShowWorkingCopies(const AProject: string);
var
  mKeep: IAtlasProjectsSource;
  mProject: string;
begin
  mKeep := Self;
  mProject := AProject;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      TAtlasIdeWorkingCopies.ShowFor(mProject,
        procedure
        begin
          // mKeep hält den Bereich bis hierher; nach dem Beenden nichts mehr abfragen.
          if (mKeep <> nil) and not FStopped then
          begin
            Refresh(mProject);
          end;
        end);
    end);
end;

function TAtlasIdeProjects.WorkingCopies: Boolean;
begin
  Result := TAtlasIdeSettings.Current.VcsExternalsShow;
end;

procedure TAtlasIdeProjects.Remove(const AProject: string);
begin
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      // Nur dieser Bereich: Die Liste „Zuletzt geöffnet“ der IDE bleibt unverändert.
      if Summaries <> nil then
      begin
        Summaries.SetHidden(AProject, True);
      end;
    end);
end;

end.
